import Foundation

final class HTTPMockURLProtocol: URLProtocol {
    private static var queues: [UUID: [Key: [MockResponse]]] = [:]
    private static var unmockedPolicyStorage: [UUID: UnmockedPolicy] = [:]
    private static let handledKey = "HTTPMockHandled"
    private static let queueLock = DispatchQueue(label: "MockURLProtocol.queueLock")
    private static let unmockedPolicyLock = DispatchQueue(label: "MockURLProtocol.unmockedPolicyLock")

    /// A plain session without `HTTPMockURLProtocol` to support passthrough of requests when policy requires it.
    private lazy var passthroughSession: URLSession = URLSession(configuration: .ephemeral)

    // MARK: - Internal methods

    static func getUnmockedPolicy(for mockIdentifier: UUID) -> UnmockedPolicy {
        unmockedPolicyLock.sync {
            unmockedPolicyStorage[mockIdentifier] ?? .notFound
        }
    }

    static func setUnmockedPolicy(for mockIdentifier: UUID, _ unmockedPolicy: UnmockedPolicy) {
        unmockedPolicyLock.sync {
            unmockedPolicyStorage[mockIdentifier] = unmockedPolicy
        }
    }

    static func setQueue(for mockIdentifier: UUID, _ queue: [Key: [MockResponse]]) {
        queueLock.sync {
            queues[mockIdentifier] = queue
        }
    }

    static func getQueue(for mockIdentifier: UUID) -> [Key: [MockResponse]] {
        queueLock.sync {
            queues[mockIdentifier] ?? [:]
        }
    }

    /// Clear all queues – basically a reset.
    static func clearQueues(mockIdentifier: UUID) {
        queueLock.sync {
            queues[mockIdentifier]?.removeAll()
        }
    }

    /// Clear the response queue for a single host.
    static func clearQueue(forHost host: String, mockIdentifier: UUID) {
        queueLock.sync {
            guard let mockQueues = queues[mockIdentifier] else { return }
            queues[mockIdentifier] = mockQueues.filter { $0.key.host != host }
        }
    }

    static func add(
        responses: [MockResponse],
        forHost host: String,
        path: String,
        queryItems: [String: String]? = nil,
        queryMatching: QueryMatching = .exact,
        forMockIdentifier mockIdentifier: UUID
    ) {
        let key = Key(host: host, path: path, queryItems: queryItems, queryMatching: queryMatching)
        add(responses: responses, forKey: key, forMockIdentifier: mockIdentifier)
    }

    static func add(
        responses givenResponses: [MockResponse],
        forKey key: Key,
        forMockIdentifier mockIdentifier: UUID
    ) {
        let responses = givenResponses.filter(\.hasValidLifetime)

        guard !responses.isEmpty else {
            if givenResponses.isEmpty {
                HTTPMockLog.trace("No valid responses provided. Skipping registration.")
            } else {
                HTTPMockLog.trace("\(givenResponses.count) response(s) provided, but none were valid. Skipping registration.")
            }
            return
        }

        var mockQueue = getQueue(for: mockIdentifier)
        var queue = mockQueue[key] ?? []

        // Let user know if they're trying to insert responses after an eternal mock.
        if queue.contains(where: \.isEternal) {
            HTTPMockLog.warning("Registering response(s) after an eternal mock for \(mockKeyDescription(key)). These responses will never be served.")
        }

        queue.append(contentsOf: responses)
        mockQueue[key] = queue
        setQueue(for: mockIdentifier, mockQueue)

        HTTPMockLog.info("Registered \(responses.count) response(s) for \(mockKeyDescription(key))")
        HTTPMockLog.debug("Current queue size for \(key.host)\(key.path): \(queue.count)")
    }

    // MARK: - Overrides

    // Decide whether to intercept request
    override class func canInit(with request: URLRequest) -> Bool {
        // Avoid re-entrancy if we are already proxying/passthrough for this request
        if URLProtocol.property(forKey: handledKey, in: request) as? Bool == true {
            return false
        }

        // Intercept all requests made with sessions that include this protocol
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let urlSession = task?.value(forKey: "session") as? URLSession,
            let mockIdentifier = urlSession.mockIdentifier
        else {
            fatalError("Could not find mock identifier for URLSession")
        }

        guard
            let url = request.url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = components.host
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let path = components.path.isEmpty ? "/" : components.path
        let queryDict = components.queryItems.toDictionary
        let requestDescription = Self.requestDescription(host: host, path: path, query: queryDict)

        HTTPMockLog.trace("Handling request → \(requestDescription)")

        // Look for, and pop, the next queued response mathing host, path and query params.
        if let mock = Self.pop(mockIdentifier: mockIdentifier, host: host, path: path, query: queryDict) {
            let sendResponse = { [weak self] in
                guard let self else { return }
                do {
                    HTTPMockLog.info("Serving mock for \(host)\(path) (\(self.statusCode(of: mock)))")
                    HTTPMockLog.debug("Remaining queue for \(requestDescription): \(Self.queueSize(mockIdentifier: mockIdentifier, host: host, path: path, query: queryDict))")

                    let response = HTTPURLResponse(
                        url: url,
                        statusCode: mock.status.code,
                        httpVersion: "HTTP/1.1",
                        headerFields: mock.headers
                    )!

                    let payload = try mock.payloadData()
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    self.client?.urlProtocol(self, didLoad: payload)
                    self.client?.urlProtocolDidFinishLoading(self)
                } catch {
                    self.client?.urlProtocol(self, didFailWithError: error)
                }
            }

            switch mock.delivery {
            case .instant:
                sendResponse()
            case .delayed(let delay):
                HTTPMockLog.info("Delaying response for \(requestDescription) for \(delay) seconds")
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: sendResponse)
            }
        } else {
            switch Self.getUnmockedPolicy(for: mockIdentifier) {
            case .notFound:
                HTTPMockLog.error("No mock found for \(requestDescription) — returning 404")
                let resp = HTTPURLResponse(
                    url: url,
                    statusCode: 404,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/plain"]
                )!
                client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data("No mock for \(host)\(path)".utf8))
                client?.urlProtocolDidFinishLoading(self)

            case .passthrough:
                HTTPMockLog.info("No mock found for \(requestDescription) — passthrough to network")
                var req = request
                let mutableReq = (req as NSURLRequest).mutableCopy() as! NSMutableURLRequest
                URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableReq) // prevent loop
                req = mutableReq as URLRequest
                let task = passthroughSession.dataTask(with: req) { data, response, error in
                    if let error {
                        self.client?.urlProtocol(self, didFailWithError: error)
                        return
                    }

                    if let response {
                        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    }

                    if let data {
                        self.client?.urlProtocol(self, didLoad: data)
                    }

                    self.client?.urlProtocolDidFinishLoading(self)
                }
                task.resume()
            }
        }
    }

    override func stopLoading() {
        // NOOP
    }

    // MARK: - Private methods

    private static func pop(
        mockIdentifier: UUID,
        host: String,
        path: String,
        query: [String: String]
    ) -> MockResponse? {
        var mockQueues = getQueue(for: mockIdentifier)

        // Find the first key matching host+path(+query).
        let matchingKey = mockQueues.keys.first {
            matches($0, host: host, path: path, query: query)
        }

        if let matchingKey {
            guard var queue = mockQueues[matchingKey], !queue.isEmpty else {
                return nil
            }

            let first = queue.removeFirst()
            switch first.lifetime {
            case .single:
                mockQueues[matchingKey] = queue
                setQueue(for: mockIdentifier, mockQueues)
            case .multiple(let count):
                switch count {
                case _ where count < 0, 0:
                    // Ignore this mock if lifetime count is at, or below, 0.
                    mockQueues[matchingKey] = queue
                    setQueue(for: mockIdentifier, mockQueues)
                    return nil
                case 1:
                    mockQueues[matchingKey] = queue
                    setQueue(for: mockIdentifier, mockQueues)
                default:
                    let copy = first.copyWithNewLifetime(.multiple(count - 1))
                    mockQueues[matchingKey] = [copy] + queue
                    setQueue(for: mockIdentifier, mockQueues)
                    HTTPMockLog.info("Mock response will be used \(count) more time(s) for \(mockKeyDescription(matchingKey))")
                    return copy
                }
            case .eternal:
                return first
            }

            if queue.isEmpty {
                HTTPMockLog.info("Queue now depleted for \(mockKeyDescription(matchingKey))")
            }

            return first
        }
        return nil
    }

    private static func matches(
        _ key: Key,
        host: String,
        path: String,
        query: [String: String]
    ) -> Bool {
        guard key.host == host, key.path == path else {
            return false
        }

        guard let requiredQueryItems = key.queryItems, !requiredQueryItems.isEmpty else {
            return true
        }

        switch key.queryMatching {
        case .exact:
            return requiredQueryItems == query
        case .contains:
            return requiredQueryItems.allSatisfy { (k, v) in query[k] == v }
        }
    }
}

// MARK: - Helper utils for logging

extension HTTPMockURLProtocol {
    private func statusCode(of mock: MockResponse) -> Int {
        mock.status.code
    }

    private static func requestDescription(host: String, path: String, query: [String: String]) -> String {
        "\(host)\(path) \(describeQuery(query, nil, dropQueryMatching: true))"
    }

    private static func mockKeyDescription(_ key: Key) -> String {
        "\(key.host)\(key.path) \(describeQuery(key.queryItems, key.queryMatching))"
    }

    private static func queueSize(
        mockIdentifier: UUID,
        host: String,
        path: String,
        query: [String: String]
    ) -> Int {
        getQueue(for: mockIdentifier)
            .filter { matches($0.key, host: host, path: path, query: query) }
            .map(\.value.count)
            .first ?? 0
    }

    private static func describeQuery(
        _ query: [String: String]?,
        _ queryMatching: QueryMatching?,
        dropQueryMatching: Bool = false
    ) -> String {
        guard let query, !query.isEmpty else {
            return "[query empty]"
        }

        let parts = query.map { "\($0)=\($1)" }.sorted().joined(separator: "&")

        if dropQueryMatching {
            return "[query: \(parts)]"
        } else {
            return "[query \(queryMatching ?? .exact): \(parts)]"
        }
    }
}

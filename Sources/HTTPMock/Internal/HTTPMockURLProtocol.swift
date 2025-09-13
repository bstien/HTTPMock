import Foundation

final class HTTPMockURLProtocol: URLProtocol {
    private static var queues: [UUID: [Key: [MockResponse]]] = [:]
    private static var unmockedPolicyStorage: [UUID: UnmockedPolicy] = [:]
    private static let matcher = HTTPMockMatcher()
    private static let handledKey = "HTTPMockHandled"
    private static let queueLock = DispatchQueue(label: "MockURLProtocol.queueLock")
    private static let unmockedPolicyLock = DispatchQueue(label: "MockURLProtocol.unmockedPolicyLock")

    /// A plain session without `HTTPMockURLProtocol` to support passthrough of requests when policy requires it.
    private lazy var passthroughSession = URLSession(configuration: .ephemeral)

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
            HTTPMockLog.warning("Registered response(s) after an eternal mock for \(keyDescription(key)). These responses will never be served.")
        }

        queue.append(contentsOf: responses)
        mockQueue[key] = queue
        setQueue(for: mockIdentifier, mockQueue)

        HTTPMockLog.info("Registered \(responses.count) response(s) for \(keyDescription(key))")
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
            let host = components.host?.lowercased()
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let path = components.path.isEmpty ? "/" : components.path
        let queryDict = components.queryItems.toDictionary
        let requestDescription = Self.requestDescription(host: host, path: path, query: queryDict)

        HTTPMockLog.trace("Handling incoming request → '\(requestDescription)'")

        // Look for, and pop, the next queued response mathing host, path and query params.
        let match = Self.findAndPopNextMock(
            for: mockIdentifier,
            host: host,
            path: path,
            query: queryDict
        )

        if let match {
            let key = match.key
            let mock = match.response
            let keyDescription = Self.keyDescription(key)

            HTTPMockLog.trace("Found mock in queue for matching registration: '\(keyDescription)'")
            HTTPMockLog.debug("Remaining queue count for '\(keyDescription)': \(Self.queueSize(for: mockIdentifier, key: key))")

            let sendResponse = { [weak self] in
                guard let self else { return }
                do {
                    HTTPMockLog.info("Serving mock for incoming request \(host)\(path) (\(self.statusCode(of: mock)))")

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
                    HTTPMockLog.error("Failed to serve mock for \(host)\(path): \(error)")
                    self.client?.urlProtocol(self, didFailWithError: error)
                }
            }

            switch mock.delivery {
            case .instant:
                sendResponse()
            case .delayed(let delay):
                HTTPMockLog.info("Delaying response for request '\(requestDescription)' for \(delay) seconds")
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: sendResponse)
            }
        } else {
            switch Self.getUnmockedPolicy(for: mockIdentifier) {
            case .notFound:
                HTTPMockLog.error("No mock found for request '\(requestDescription)' — returning 404")
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 404,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/plain"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data("No mock for \(host)\(path)".utf8))
                client?.urlProtocolDidFinishLoading(self)

            case .passthrough:
                HTTPMockLog.info("No mock found for \(requestDescription) — passthrough to network")
                var request = request

                // Set known value on request to prevent handling the same request multiple times.
                let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
                URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)
                request = mutableRequest as URLRequest

                let task = passthroughSession.dataTask(with: request) { data, response, error in
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

    private static func findAndPopNextMock(
        for mockIdentifier: UUID,
        host: String,
        path: String,
        query: [String: String]
    ) -> MockMatch? {
        var mockQueues = getQueue(for: mockIdentifier)

        // Find the first key matching host+path(+query).
        let matchingKey = matcher.match(host: host, path: path, queryItems: query, in: Set(mockQueues.keys))

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
                    HTTPMockLog.info("Mock response will be used \(count) more time(s) for \(keyDescription(matchingKey))")
                    return MockMatch(key: matchingKey, response: copy)
                }
            case .eternal:
                return MockMatch(key: matchingKey, response: first)
            }

            if queue.isEmpty {
                HTTPMockLog.info("Queue now depleted for \(keyDescription(matchingKey))")
            }

            return MockMatch(key: matchingKey, response: first)
        }
        return nil
    }
}

// MARK: - Helper utils for logging

extension HTTPMockURLProtocol {
    private func statusCode(of mock: MockResponse) -> Int {
        mock.status.code
    }

    private static func keyDescription(_ key: Key) -> String {
        "\(key.host)\(key.path) \(describeQuery(key.queryItems, key.queryMatching))"
    }

    private static func requestDescription(host: String, path: String, query: [String: String]) -> String {
        "\(host)\(path) \(describeQuery(query, nil, dropQueryMatching: true))"
    }

    private static func queueSize(for mockIdentifier: UUID, key: Key) -> Int {
        let queue = getQueue(for: mockIdentifier)
        return queue[key]?.count ?? 0
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

import Foundation

final class HTTPMockURLProtocol: URLProtocol {
    static var queues: [Key: [MockResponse]] = [:]
    static var unmockedPolicy: UnmockedPolicy = .notFound
    private static let handledKey = "HTTPMockHandled"
    private static let lock = DispatchQueue(label: "MockURLProtocol.lock")

    /// A plain session without `HTTPMockURLProtocol` to support passthrough of requests when policy requires it.
    private lazy var passthroughSession: URLSession = URLSession(configuration: .ephemeral)

    // MARK: - Internal methods

    /// Clear all queues – basically a reset.
    static func clearQueues() {
        lock.sync {
            queues.removeAll()
        }
    }

    /// Clear the response queue for a single host.
    static func clearQueue(forHost host: String) {
        lock.sync {
            queues = queues.filter { $0.key.host != host }
        }
    }

    static func add(
        responses: [MockResponse],
        forHost host: String,
        path: String,
        queryItems: [String: String]? = nil,
        queryMatching: QueryMatching = .exact
    ) {
        let key = Key(host: host, path: path, queryItems: queryItems, queryMatching: queryMatching)
        add(responses: responses, forKey: key)
    }

    static func add(responses: [MockResponse], forKey key: Key) {
        lock.sync {
            var queue = queues[key] ?? []
            queue.append(contentsOf: responses)
            queues[key] = queue

            HTTPMockLog.info("Registered \(responses.count) response(s) for \(key.host)\(key.path) \(describeQuery(key.queryItems, key.queryMatching))")
            HTTPMockLog.debug("Current queue size for \(key.host)\(key.path): \(queue.count)")
        }
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
            let url = request.url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = components.host
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let path = components.path.isEmpty ? "/" : components.path
        let queryDict = components.queryItems.toDictionary

        HTTPMockLog.trace("Request → \(host)\(path) \(Self.describeQuery(queryDict, nil))")

        // Look for, and pop, the next queued response mathing host, path and query params.
        if let mock = Self.pop(host: host, path: path, query: queryDict) {
            do {
                HTTPMockLog.info("Serving mock for \(host)\(path) (\(statusCode(of: mock)))")
                HTTPMockLog.debug("Remaining queue for \(host)\(path) \(Self.describeQuery(queryDict, nil)): \(Self.queueSize(host: host, path: path, query: queryDict))")

                let response = HTTPURLResponse(
                    url: url,
                    statusCode: mock.status.code,
                    httpVersion: "HTTP/1.1",
                    headerFields: mock.headers
                )!

                let payload = try mock.payloadData()
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: payload)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        } else {
            switch Self.unmockedPolicy {
            case .notFound:
                HTTPMockLog.error("No mock found for \(host)\(path) \(Self.describeQuery(queryDict, nil)) — returning 404")
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
                HTTPMockLog.info("No mock found for \(host)\(path) \(Self.describeQuery(queryDict, nil)) — passthrough to network")
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
        host: String,
        path: String,
        query: [String: String]
    ) -> MockResponse? {
        lock.sync {
            // Find the first key matching host+path(+query).
            let matchingKey = queues.keys.first {
                matches($0, host: host, path: path, query: query)
            }

            if let matchingKey {
                guard var queue = queues[matchingKey], !queue.isEmpty else {
                    return nil
                }

                let first = queue.removeFirst()
                queues[matchingKey] = queue

                if queue.isEmpty {
                    HTTPMockLog.info("Queue now depleted for \(matchingKey.host)\(matchingKey.path) \(describeQuery(query, nil))")
                }

                return first
            }
            return nil
        }
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

    private func statusCode(of mock: MockResponse) -> Int {
        mock.status.code
    }

    private static func queueSize(host: String, path: String, query: [String: String]) -> Int {
        lock.sync {
            queues
                .filter { matches($0.key, host: host, path: path, query: query) }
                .map(\.value.count)
                .first ?? 0
        }
    }

    private static func describeQuery(_ query: [String: String]?, _ queryMatching: QueryMatching?) -> String {
        guard let query, !query.isEmpty else { return "" }

        let parts = query.map { "\($0)=\($1)" }.sorted().joined(separator: "&")
        return "[query \(queryMatching ?? .exact): \(parts)]"
    }
}

import Foundation

final class HTTPMockURLProtocol: URLProtocol {
    static var queues: [Key: [MockResponse]] = [:]
    private static let lock = DispatchQueue(label: "MockURLProtocol.lock")

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
        lock.sync {
            let key = Key(host: host, path: path, queryItems: queryItems, queryMatching: queryMatching)
            var queue = queues[key] ?? []
            queue.append(contentsOf: responses)
            queues[key] = queue
        }
    }

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

    // Decide whether to intercept request
    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url, let host = url.host else {
            return false
        }

        let path = url.path.isEmpty ? "/" : url.path
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryDict = components?.queryItems.toDictionary ?? [:]

        return lock.sync {
            queues.keys.contains {
                matches($0, host: host, path: path, query: queryDict)
            }
        }
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

        // Look for, and pop, the next queued response mathing host, path and query params.
        if let mock = Self.pop(host: host, path: path, query: queryDict) {
            do {
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
            // Nothing queued. Fallback to 404.
            let resp = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"]
            )!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("No mock for \(host)\(path)".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        // NOOP
    }
}

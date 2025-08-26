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

    static func add(responses: [MockResponse], forHost host: String, path: String) {
        lock.sync {
            let key = Key(host: host, path: path)
            var queue = queues[key] ?? []
            queue.append(contentsOf: responses)
            queues[key] = queue
        }
    }

    private static func pop(host: String, path: String) -> MockResponse? {
        lock.sync {
            let key = Key(host: host, path: path)
            guard var queue = queues[key], !queue.isEmpty else {
                return nil
            }

            let first = queue.removeFirst()
            queues[key] = queue
            return first
        }
    }

    // Decide whether to intercept request
    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url, let host = url.host else {
            return false
        }

        let path = url.path.isEmpty ? "/" : url.path
        return lock.sync {
            queues.keys.contains {
                $0.host == host && $0.path == path
            }
        }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let path = url.path.isEmpty ? "/" : url.path

        // Pop the next queued response for (host, path)
        if let mock = Self.pop(host: host, path: path) {
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

extension HTTPMockURLProtocol {
    struct Key: Hashable {
        let host: String
        let path: String
    }
}

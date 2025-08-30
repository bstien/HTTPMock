import Foundation

public final class HTTPMock {
    public static let shared = HTTPMock()
    public let urlSession: URLSession
    public var defaultDomain = "example.com"

    public var unmockedPolicy: UnmockedPolicy {
        get { HTTPMockURLProtocol.unmockedPolicy }
        set { HTTPMockURLProtocol.unmockedPolicy = newValue }
    }

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPMockURLProtocol.self]
        urlSession = URLSession(configuration: configuration)
    }

    /// Queue responses for a given path (e.g. "/some-path") for host in `defaultDomain`. Each request will pop the next response.
    public func addResponses(
        forPath path: String,
        queryItems: [String: String]? = nil,
        queryMatching: QueryMatching = .exact,
        responses: [MockResponse]
    ) {
        HTTPMockURLProtocol.add(
            responses: responses,
            forHost: defaultDomain,
            path: normalized(path),
            queryItems: queryItems,
            queryMatching: queryMatching
        )
    }

    /// Queue responses for a given path (e.g. "/some-path") on the specified domain. Each request will pop the next response.
    public func addResponses(
        forPath path: String,
        host: String,
        queryItems: [String: String]? = nil,
        queryMatching: QueryMatching = .exact,
        responses: [MockResponse]
    ) {
        HTTPMockURLProtocol.add(
            responses: responses,
            forHost: host,
            path: normalized(path),
            queryItems: queryItems,
            queryMatching: queryMatching
        )
    }

    /// Convenience to perform requests to call directly.
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await urlSession.data(for: request)
    }

    /// Clear all queues – basically a reset.
    public func clearQueues() {
        HTTPMockURLProtocol.clearQueues()
    }

    /// Clear the response queue for a single host.
    public func clearQueue(forHost host: String) {
        HTTPMockURLProtocol.clearQueue(forHost: host)
    }

    /// Makes sure all paths are prefixed with `/`. We need this for consistency when looking up responses from the queue.
    private func normalized(_ path: String) -> String {
        path.hasPrefix("/") ? path : "/" + path
    }
}

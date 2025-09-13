import Foundation

public final class HTTPMock {
    /// A shared singleton instance for convenience. Use this for simple testing scenarios.
    /// For parallel testing or isolated mock configurations, create separate instances with `HTTPMock()`.
    public static let shared = HTTPMock()

    /// The URLSession that intercepts and mocks HTTP requests.
    /// Inject this session into your code under test to enable mocking.
    public let urlSession: URLSession

    /// A plain `URLSession` used for passthrough requests when `unmockedPolicy` is set to `.passthrough`.
    /// This session bypasses the mocking layer and makes real network requests.
    /// You can provide a custom passthrough session during initialization or configure this as needed.
    public let passthroughSession: URLSession

    /// The default domain used when registering responses without specifying a host.
    /// Defaults to "example.com" and should be changed to match your API domain.
    public var defaultDomain = "example.com"

    /// Controls how unmocked requests (requests with no registered response) are handled.
    public var unmockedPolicy: UnmockedPolicy {
        get { HTTPMockURLProtocol.getUnmockedPolicy(for: mockIdentifier) }
        set { HTTPMockURLProtocol.setUnmockedPolicy(for: mockIdentifier, newValue) }
    }

    /// Unique identifier for this HTTPMock instance, used to isolate mock queues between different instances.
    let mockIdentifier: UUID

    public convenience init(passthroughSession: URLSession? = nil) {
        self.init(identifier: UUID(), passthroughSession: passthroughSession)
    }

    required init(
        identifier mockIdentifier: UUID,
        passthroughSession: URLSession? = nil
    ) {
        self.mockIdentifier = mockIdentifier
        urlSession = URLSession.identifiedSession(with: mockIdentifier)
        self.passthroughSession = passthroughSession ?? URLSession(configuration: .ephemeral)

        HTTPMockURLProtocol.setPassthroughSession(for: mockIdentifier, self.passthroughSession)
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
            queryMatching: queryMatching,
            forMockIdentifier: mockIdentifier
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
            queryMatching: queryMatching,
            forMockIdentifier: mockIdentifier
        )
    }

    /// Convenience to perform requests to call directly.
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await urlSession.data(for: request)
    }

    /// Clear all queues – basically a reset.
    public func clearQueues() {
        HTTPMockURLProtocol.clearQueues(mockIdentifier: mockIdentifier)
    }

    /// Clear the response queue for a single host.
    public func clearQueue(forHost host: String) {
        HTTPMockURLProtocol.clearQueue(forHost: host, mockIdentifier: mockIdentifier)
    }

    /// Makes sure all paths are prefixed with `/`. We need this for consistency when looking up responses from the queue.
    private func normalized(_ path: String) -> String {
        path.hasPrefix("/") ? path : "/" + path
    }
}

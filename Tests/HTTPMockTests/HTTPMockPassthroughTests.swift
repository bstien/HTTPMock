import Testing
import Foundation
@testable import HTTPMock

struct HTTPMockPassthroughTests {
    @Test
    func passthroughSessionSetDuringInit() {
        let httpMock = HTTPMock()

        // Verify that the passthrough session was set
        let passthroughSession = HTTPMockURLProtocol.getPassthroughSession(for: httpMock.mockIdentifier)
        #expect(passthroughSession != nil)
        #expect(passthroughSession === httpMock.passthroughSession)
    }

    @Test
    func customPassthroughSessionCanBeProvided() {
        let customSession = URLSession(configuration: .default)

        let httpMock = HTTPMock(passthroughSession: customSession)
        #expect(httpMock.passthroughSession === customSession)

        let storedSession = HTTPMockURLProtocol.getPassthroughSession(for: httpMock.mockIdentifier)
        #expect(storedSession === customSession)
    }

    @Test
    func defaultPassthroughSessionUsesEphemeralConfig() {
        let httpMock = HTTPMock()

        // Default passthrough session should use ephemeral configuration
        // We check that it's not the shared cache which indicates ephemeral usage
        let isEphemeralStyle = httpMock.passthroughSession.configuration.urlCache !== URLCache.shared
        #expect(isEphemeralStyle)
    }

    @Test
    func passthroughSessionsAreIsolatedBetweenInstances() {
        let mock1 = HTTPMock()
        let mock2 = HTTPMock()

        let session1 = HTTPMockURLProtocol.getPassthroughSession(for: mock1.mockIdentifier)
        let session2 = HTTPMockURLProtocol.getPassthroughSession(for: mock2.mockIdentifier)

        #expect(session1 !== session2)
        #expect(mock1.passthroughSession !== mock2.passthroughSession)
    }

    @Test
    func sharedInstanceHasOwnPassthroughSession() {
        let sharedSession = HTTPMockURLProtocol.getPassthroughSession(for: HTTPMock.shared.mockIdentifier)
        let newInstanceSession = HTTPMockURLProtocol.getPassthroughSession(for: HTTPMock().mockIdentifier)

        #expect(sharedSession != nil)
        #expect(newInstanceSession != nil)
        #expect(sharedSession !== newInstanceSession)
    }

    @Test
    func passthroughSessionStorageAndRetrievalWorks() {
        let mockIdentifier = UUID()
        let urlSession = URLSession(configuration: .ephemeral)

        // Initially no session stored
        let initialSession = HTTPMockURLProtocol.getPassthroughSession(for: mockIdentifier)
        #expect(initialSession == nil)

        // Store session
        HTTPMockURLProtocol.setPassthroughSession(for: mockIdentifier, urlSession)

        // Retrieve stored session
        let retrievedSession = HTTPMockURLProtocol.getPassthroughSession(for: mockIdentifier)
        #expect(retrievedSession === urlSession)
    }

    @Test
    func httpMockUsesCorrectPassthroughSessionForIdentifier() {
        let customConfig = URLSessionConfiguration.background(withIdentifier: "test-background")
        let customSession = URLSession(configuration: customConfig)

        let httpMock = HTTPMock(passthroughSession: customSession)

        // Verify the custom session is stored correctly
        let storedSession = HTTPMockURLProtocol.getPassthroughSession(for: httpMock.mockIdentifier)
        #expect(storedSession === customSession)
        #expect(storedSession === httpMock.passthroughSession)
    }

    @Test
    func multipleCustomPassthroughSessionsWorkIndependently() {
        let config1 = URLSessionConfiguration.ephemeral
        config1.timeoutIntervalForRequest = 5.0
        let session1 = URLSession(configuration: config1)

        let config2 = URLSessionConfiguration.ephemeral
        config2.timeoutIntervalForRequest = 10.0
        let session2 = URLSession(configuration: config2)

        let mock1 = HTTPMock(passthroughSession: session1)
        let mock2 = HTTPMock(passthroughSession: session2)

        #expect(mock1.passthroughSession === session1)
        #expect(mock2.passthroughSession === session2)
        #expect(mock1.passthroughSession !== mock2.passthroughSession)

        let stored1 = HTTPMockURLProtocol.getPassthroughSession(for: mock1.mockIdentifier)
        let stored2 = HTTPMockURLProtocol.getPassthroughSession(for: mock2.mockIdentifier)

        #expect(stored1 === session1)
        #expect(stored2 === session2)
    }

    @Test
    func passthroughSessionIsUsed() async throws {
        // Create the passthrough session to use
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InterceptingURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)

        // Setup HTTPMock and pass on the session
        let httpMock = HTTPMock(passthroughSession: urlSession)
        httpMock.unmockedPolicy = .passthrough

        let url = try #require(URL(string: "https://example.com"))

        do {
            _ = try await httpMock.urlSession.data(from: url)
            #expect(Bool(false), "The request above should throw an error, but it didn't")
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == PassthroughSessionError.errorDomain)
            #expect(nsError.userInfo[NSUnderlyingErrorKey] as? PassthroughSessionError == .wasCalled)
        }
    }
}

// MARK: - URLProtocol for tests

/// `URLProtocol` implementation that fails immediately upon request, using `PassthroughSessionError.wasCalled`.
/// Used to test that the `passthroughSession` is actually being used.
private class InterceptingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        // Fail immediately.
        // `URLSession` seems to wrap any errors thrown here in `URLError`, so we throw an `NSError`
        // here along with some info that can we can extract and identify from the tests.
        let underlyingError = PassthroughSessionError.wasCalled
        let nsError = NSError(
            domain: PassthroughSessionError.errorDomain,
            code: underlyingError.errorCode,
            userInfo: [NSUnderlyingErrorKey: underlyingError]
        )
        client?.urlProtocol(self, didFailWithError: nsError)
    }

    override func stopLoading() {
        // NOOP
    }
}

private enum PassthroughSessionError: Int, Error, CustomNSError {
    case wasCalled = 666

    static var errorDomain: String { "HTTPMock.PassthroughSessionError" }
    var errorCode: Int { rawValue }
}

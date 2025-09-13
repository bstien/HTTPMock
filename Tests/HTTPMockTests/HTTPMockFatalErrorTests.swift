import Testing
import Foundation
@testable import HTTPMock

/// These tests are separated from the rest, so we can run them in sequence. We need to do this, because they all set the `unmockedPolicy` to `fatalError`.
/// Having them run in parallel will cause issues, since `HTTPMockURLProtocol.fatalErrorClosure` is shared and will be reset between each call to an unmocked URL
/// where the policy is `fatalError.`
@Suite(.serialized)
struct HTTPMockFatalErrorTests {
    let httpMock: HTTPMock

    init() {
        httpMock = HTTPMock()
        HTTPMockLog.level = .trace
    }

    @Test
    func unmockedPolicy_fatalError_callsFatalErrorClosure() async throws {
        var fatalErrorCalled = false

        // Set up the test closure
        HTTPMockURLProtocol.fatalErrorClosure = {
            fatalErrorCalled = true
        }

        // Configure fatal error policy
        httpMock.unmockedPolicy = .fatalError
        let url = try #require(URL(string: "https://example.com/fatal-test"))

        // The request should trigger our test closure instead of actually calling fatalError
        _ = try? await httpMock.urlSession.data(from: url)
        #expect(fatalErrorCalled == true)
        #expect(HTTPMockURLProtocol.fatalErrorClosure == nil) // Should be reset after use
    }

    @Test
    func unmockedPolicy_fatalError_resetsClosureAfterCall() async throws {
        var firstCallMade = false
        var secondCallMade = false

        // Set up the test closure for first call
        HTTPMockURLProtocol.fatalErrorClosure = {
            firstCallMade = true
        }
        httpMock.unmockedPolicy = .fatalError
        let url = try #require(URL(string: "https://example.com/fatal-reset-test"))

        // First unmocked request should trigger closure
        _ = try? await httpMock.urlSession.data(from: url)
        #expect(firstCallMade == true)
        #expect(HTTPMockURLProtocol.fatalErrorClosure == nil)

        // Set up a different closure for second call
        HTTPMockURLProtocol.fatalErrorClosure = {
            secondCallMade = true
        }

        // Second unmocked request should trigger the new closure
        _ = try? await httpMock.urlSession.data(from: url)
        #expect(secondCallMade == true)
        #expect(HTTPMockURLProtocol.fatalErrorClosure == nil)
    }

    @Test
    func unmockedPolicy_fatalError_switchingFromOtherPolicies() async throws {
        let url = try #require(URL(string: "https://example.com/policy-to-fatal"))

        // Start with notFound policy
        httpMock.unmockedPolicy = .notFound
        let (_, response1) = try await httpMock.urlSession.data(from: url)
        #expect(response1.httpStatusCode == 404)

        // Switch to fatalError policy
        var fatalErrorCalled = false
        HTTPMockURLProtocol.fatalErrorClosure = {
            fatalErrorCalled = true
        }
        httpMock.unmockedPolicy = .fatalError

        // Should now trigger fatal error behavior
        _ = try? await httpMock.urlSession.data(from: url)
        #expect(fatalErrorCalled == true)
    }
}

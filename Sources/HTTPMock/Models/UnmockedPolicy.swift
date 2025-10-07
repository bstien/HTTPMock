import Foundation

/// Policy to use when an incoming request there are no incoming requests has no registered mocked responses.
public enum UnmockedPolicy {
    /// Return a hardcoded "Not found" message, along with HTTP status 404.
    case notFound

    /// Return a user-defined mocked response.
    case mock(MockResponse)

    /// Let the request pass through to the internet.
    /// Useful for integration tests where you want to mock some responses, but let others hit actual network.
    case passthrough

    /// Throw the specified error when an unmocked request is encountered.
    case throwError(Error)

    /// Perform a `fatalError()` call to abruptly end the running app/test.
    /// Useful for strict testing of your networking.
    case fatalError
}

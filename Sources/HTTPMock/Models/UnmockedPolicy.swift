import Foundation

/// Policy to use when an incoming request there are no incoming requests has no registered mocked responses.
public enum UnmockedPolicy {
    /// Return a hardcoded "Not found" message, along with HTTP status 404.
    case notFound

    /// Let the request pass through to the internet.
    /// Useful for integration tests where you want to mock some responses, but let others hit actual network.
    case passthrough
}

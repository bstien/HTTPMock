import Foundation

/// Represents elements inside a `Path` DSL block.
public enum PathElement {
    /// Holds a `MockResponse` for the path.
    case response(MockResponse)
    /// Represents a nested `Path`.
    case child(Path)
    case headers(Headers)
}

import Foundation

/// An internal helper type representing a flat path-to-responses mapping used during hierarchical DSL flattening.
struct Registration {
    /// The full normalized path.
    let path: String

    /// The headers to include for this registration.
    let headers: [String: String]

    /// The mock responses queued for path `path`.
    let responses: [MockResponse]
}

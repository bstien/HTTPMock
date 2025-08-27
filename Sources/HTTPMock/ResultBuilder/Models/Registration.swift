import Foundation

/// An internal helper type representing a flat path-to-responses mapping used during hierarchical DSL flattening.
/// 
/// - `path`: The full normalized path.
/// - `responses`: The mock responses queued for that path.
struct Registration {
    let path: String
    let responses: [MockResponse]
}

import Foundation

/// An internal helper type representing a flat path-to-responses mapping used during hierarchical DSL flattening.
struct Registration {
    let path: String
    let headers: [String: String]
    let responses: [MockResponse]
    let queryItems: [String: String]?
    let queryMatching: QueryMatching?
}

import Foundation

extension HTTPMockURLProtocol {
    struct Key: Hashable {
        let host: String
        let path: String
        let queryItems: [String: String]?
        let queryMatching: QueryMatching
    }
}

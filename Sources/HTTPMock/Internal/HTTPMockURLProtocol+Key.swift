import Foundation

extension HTTPMockURLProtocol {
    struct Key: Hashable {
        let host: String
        let path: String
        let queryItems: [String: String]?
        let queryMatching: QueryMatching

        init(host: String, path: String, queryItems: [String : String]?, queryMatching: QueryMatching) {
            self.host = host.lowercased()
            self.path = path
            self.queryItems = queryItems
            self.queryMatching = queryMatching
        }
    }
}

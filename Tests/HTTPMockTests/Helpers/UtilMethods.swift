import Foundation
@testable import HTTPMock

func createMockKey(
    host: String = "example.com",
    path: String = "/",
    queryItems: [String : String]? = nil,
    queryMatching: QueryMatching = .exact
) -> HTTPMockURLProtocol.Key {
    .init(host: host, path: path, queryItems: queryItems, queryMatching: queryMatching)
}

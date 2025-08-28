import Foundation
@testable import HTTPMock

func createMockKey(host: String = "example.com", path: String = "/") -> HTTPMockURLProtocol.Key {
    .init(host: host, path: path)
}

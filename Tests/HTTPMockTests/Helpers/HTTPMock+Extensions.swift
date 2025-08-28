import Foundation
@testable import HTTPMock

extension HTTPMock {
    func addResponse(_ response: MockResponse, for key: HTTPMockURLProtocol.Key) {
        self.addResponses(forPath: key.path, host: key.host, responses: [response])
    }
}

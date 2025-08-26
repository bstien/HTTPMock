import Testing
import Foundation
@testable import HTTPMock

struct HTTPMockTests {
    let httpMock: HTTPMock
    var mockQueues: [HTTPMockURLProtocol.Key: [MockResponse]] {
        HTTPMockURLProtocol.queues
    }

    init() {
        HTTPMock.shared.clearQueues()
        httpMock = HTTPMock.shared
        httpMock.defaultDomain = "example.com"
    }

    @Test
    func itPrefixesSlashToPathIfNotPresent() {
        httpMock.addResponses(forPath: "root", responses: [.empty()])
        httpMock.addResponses(forPath: "/otherRoot", responses: [.empty()])

        #expect(mockQueues.count == 2)
        mockQueues.keys.forEach {
            #expect($0.path.hasPrefix("/"))
        }
    }

    @Test
    func itStoresAddedResponsesInQueue() {
        let mockKey1 = createMockKey(path: "/root")
        let mockKey2 = createMockKey(path: "/root/leaf")

        httpMock.addResponse(.empty(), for: mockKey1)
        httpMock.addResponse(.plaintext("Hey!"), for: mockKey2)
        #expect(mockQueues.count == 2)

        #expect(Set(mockQueues.keys) == Set([mockKey1, mockKey2]))
        #expect(mockQueues[mockKey1] == [.empty()])
        #expect(mockQueues[mockKey2] == [.plaintext("Hey!")])
    }

    @Test
    func itPopsFromQueueOnRequest() async throws {
        let mockKey = createMockKey()

        httpMock.addResponse(.empty(), for: mockKey)
        #expect(mockQueues.count == 1)
        #expect(mockQueues[mockKey]?.count == 1)

        let url = try #require(URL(string: "https://example.com"))
        let (_, _) = try await httpMock.urlSession.data(from: url)
        #expect(mockQueues.count == 1)
        #expect(mockQueues[mockKey]?.count == 0)
    }

    // MARK: - Helpers

    func createMockKey(host: String = "example.com", path: String = "/") -> HTTPMockURLProtocol.Key {
        .init(host: host, path: path)
    }
}

extension HTTPMock {
    func addResponse(_ response: MockResponse, for key: HTTPMockURLProtocol.Key) {
        self.addResponses(forPath: key.path, host: key.host, responses: [response])
    }
}

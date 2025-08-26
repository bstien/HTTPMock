import Testing
import Foundation
@testable import HTTPMock

struct HTTPMockTests {
    let httpMock: HTTPMock
    var mockQueues: [HTTPMockURLProtocol.Key: [MockResponse]] {
        HTTPMockURLProtocol.queues
    }

    init() {
        httpMock = HTTPMock.shared
        httpMock.defaultDomain = "example.com"
        HTTPMock.shared.clearQueues()
    }

    @Test
    func itUsesDefaultDomain() {
        // Add response using default domain.
        httpMock.addResponses(forPath: "/root", responses: [.empty()])

        let mockKey1 = createMockKey(path: "/root")
        #expect(mockQueues.count == 1)
        #expect(Set(mockQueues.keys) == Set([mockKey1]))

        // Change default domain and add new response.
        httpMock.defaultDomain = "other.example.com"
        httpMock.addResponses(forPath: "/root", responses: [.empty()])

        let mockKey2 = createMockKey(host: "other.example.com", path: "/root")
        #expect(mockQueues.count == 2)
        #expect(Set(mockQueues.keys) == Set([mockKey1, mockKey2]))
    }

    @Test
    func itClearsQueues() {
        httpMock.addResponses(forPath: "/root", host: "domain.com", responses: [.empty()])
        httpMock.addResponses(forPath: "/root", host: "example.com", responses: [.empty()])
        #expect(!mockQueues.isEmpty)

        httpMock.clearQueues()
        #expect(mockQueues.isEmpty)
    }

    @Test
    func itClearsQueueForASingleHost() {
        httpMock.addResponses(forPath: "/root", host: "domain.com", responses: [.empty()])
        httpMock.addResponses(forPath: "/root", host: "example.com", responses: [.empty()])
        #expect(mockQueues.count == 2)

        httpMock.clearQueue(forHost: "domain.com")
        #expect(mockQueues.count == 1)
        #expect(mockQueues.first?.key == createMockKey(host: "example.com", path: "/root"))
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

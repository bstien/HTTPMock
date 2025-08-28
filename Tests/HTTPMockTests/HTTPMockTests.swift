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

    @Test
    func itPopsInFifoOrderForSamePath() async throws {
        let key = createMockKey(path: "/fifo")
        httpMock.addResponse(.plaintext("one"), for: key)
        httpMock.addResponse(.plaintext("two"), for: key)
        httpMock.addResponse(.plaintext("three"), for: key)
        #expect(mockQueues[key]?.count == 3)

        let url = try #require(URL(string: "https://example.com/fifo"))
        let (data1, _) = try await httpMock.urlSession.data(from: url)
        let string1 = String(data: data1, encoding: .utf8)
        #expect(string1 == "one")

        let (data2, _) = try await httpMock.urlSession.data(from: url)
        let string2 = String(data: data2, encoding: .utf8)
        #expect(string2 == "two")

        let (data3, _) = try await httpMock.urlSession.data(from: url)
        let string3 = String(data: data3, encoding: .utf8)
        #expect(string3 == "three")

        #expect(mockQueues[key]?.isEmpty == true)
    }

    @Test
    func itSetsDefaultContentTypeAndAllowsOverride() throws {
        // `plaintext` default
        let plainText = MockResponse.plaintext("hi")
        #expect(plainText.headers["Content-Type"] == "text/plain")

        // `encodable` default
        let encodable = try MockResponse.encodable(DummyData())
        #expect(encodable.headers["Content-Type"] == "application/json")

        // override content type via explicit headers
        let override = MockResponse.plaintext("hi", headers: ["Content-Type": "application/custom"])
        #expect(override.headers["Content-Type"] == "application/custom")
    }

    @Test
    func clearingUnknownHostIsNoop() {
        httpMock.addResponses(forPath: "/root", host: "known.com", responses: [.empty()])
        #expect(mockQueues.count == 1)

        httpMock.clearQueue(forHost: "unknown.com")
        #expect(mockQueues.count == 1)
    }
}

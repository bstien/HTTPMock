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
        #expect(data1.toString == "one")

        let (data2, _) = try await httpMock.urlSession.data(from: url)
        #expect(data2.toString == "two")

        let (data3, _) = try await httpMock.urlSession.data(from: url)
        #expect(data3.toString == "three")

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

        // Override content type via explicit headers
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

    // MARK: - Query parameter matching

    @Test
    func query_exactMatch_mustMatchAllAndOnlyThoseParams() async throws {
        let host = "example.com"
        let path = "/search"

        // Register a response that matches only exactly these params (no extras)
        let exactKey = createMockKey(
            host: host,
            path: path,
            queryItems: ["q": "swift", "page": "1"],
            queryMatching: .exact
        )
        httpMock.addResponse(.plaintext("ok-exact"), for: exactKey)

        // Same params, different order -> matches
        let url1 = try #require(URL(string: "https://\(host)\(path)?page=1&q=swift"))
        let (data1, response1) = try await httpMock.urlSession.data(from: url1)
        #expect(response1.httpStatusCode == 200)
        #expect(data1.toString == "ok-exact")

        // Extra param present -> should NOT match .exact, expect 404
        let url2 = try #require(URL(string: "https://\(host)\(path)?page=1&q=swift&foo=bar"))
        let (_, response2) = try await httpMock.urlSession.data(from: url2)
        #expect(response2.httpStatusCode == 404)
    }

    @Test
    func query_containsMatch_allSpecifiedMustMatch_extrasIgnored() async throws {
        let host = "example.com"
        let path = "/search"

        let containsKey = createMockKey(
            host: host,
            path: path,
            queryItems: ["q": "swift"],
            queryMatching: .contains
        )
        httpMock.addResponses([.plaintext("ok-contains-1"), .plaintext("ok-contains-2")], for: containsKey)

        // Has extra params -> still matches (.contains)
        let url1 = try #require(URL(string: "https://\(host)\(path)?q=swift&page=2&sort=asc"))
        let (data1, response1) = try await httpMock.urlSession.data(from: url1)
        #expect(response1.httpStatusCode == 200)
        #expect(data1.toString == "ok-contains-1")

        // Only specified key present -> also matches
        let url2 = try #require(URL(string: "https://\(host)\(path)?q=swift"))
        let (data2, response2) = try await httpMock.urlSession.data(from: url2)
        #expect(response2.httpStatusCode == 200)
        #expect(data2.toString == "ok-contains-2")
    }

    @Test
    func query_containsMatch_failsWhenValueDiffers() async throws {
        let host = "example.com"
        let path = "/search"

        let containsKey = createMockKey(
            host: host,
            path: path,
            queryItems: ["q": "swift"],
            queryMatching: .contains
        )
        httpMock.addResponse(.plaintext("should-not-be-used"), for: containsKey)

        // Value differs -> should not match, expect 404
        let badUrl = try #require(URL(string: "https://\(host)\(path)?q=swiftlang"))
        let (_, response) = try await httpMock.urlSession.data(from: badUrl)
        #expect(response.httpStatusCode == 404)
    }

    @Test
    func query_containsMatch_failsWhenRequestIsMissingQueryItems() async throws {
        let host = "example.com"
        let path = "/search"

        let containsKey = createMockKey(
            host: host,
            path: path,
            queryItems: ["q": "swift", "page": "1"],
            queryMatching: .contains
        )
        httpMock.addResponse(.plaintext("will-be-hit-at-some-point"), for: containsKey)

        // No query items -> should not match, expect 404
        let url1 = try #require(URL(string: "https://\(host)\(path)"))
        let (_, response1) = try await httpMock.urlSession.data(from: url1)
        #expect(response1.httpStatusCode == 404)

        // One query item matches -> should not match, expect 404
        let url2 = try #require(URL(string: "https://\(host)\(path)?q=swift"))
        let (_, response2) = try await httpMock.urlSession.data(from: url2)
        #expect(response2.httpStatusCode == 404)

        // Both query items match -> matches
        let url3 = try #require(URL(string: "https://\(host)\(path)?q=swift&page=1"))
        let (data3, response3) = try await httpMock.urlSession.data(from: url3)
        #expect(response3.httpStatusCode == 200)
        #expect(data3.toString == "will-be-hit-at-some-point")
    }

    // MARK: - File serving

    @Test
    func itServesFileFromURL_withInferredContentType() async throws {
        let host = "example.com"
        let path = "/file-json"
        let contents = "{\"hello\":\"world\"}"
        let url = try writeTempFile(named: "fixture", ext: "json", contents: Data(contents.utf8))

        let key = createMockKey(host: host, path: path)
        httpMock.addResponse(.file(url: url), for: key)

        let requestURL = try #require(URL(string: "https://\(host)\(path)"))
        let (data, response) = try await httpMock.urlSession.data(from: requestURL)

        #expect(response.httpStatusCode == 200)
        #expect(data.toString == contents)

        #expect(response.headerValue(for: "Content-Type") == "application/json")
    }

    @Test
    func itServesFileFromURL_withExplicitContentTypeAndHeaders() async throws {
        let host = "example.com"
        let path = "/file-custom"
        let contents = "BINARYDATA"
        let url = try writeTempFile(named: "blob", ext: "bin", contents: Data(contents.utf8))

        let key = createMockKey(host: host, path: path)
        httpMock.addResponse(
            .file(url: url, status: .ok, headers: ["Cache-Control": "no-store"], contentType: "application/custom"),
            for: key
        )

        let requestURL = try #require(URL(string: "https://\(host)\(path)"))
        let (data, response) = try await httpMock.urlSession.data(from: requestURL)

        #expect(response.httpStatusCode == 200)
        #expect(data.toString == contents)

        #expect(response.headerValue(for: "Content-Type") == "application/custom")
        #expect(response.headerValue(for: "Cache-Control") == "no-store")
    }

    // MARK: - Helpers

    private func writeTempFile(named: String, ext: String, contents: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(named).appendingPathExtension(ext)
        try? FileManager.default.removeItem(at: url)
        try contents.write(to: url, options: .atomic)
        return url
    }
}

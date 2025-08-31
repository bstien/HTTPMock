import Testing
import Foundation
@testable import HTTPMock

struct HTTPMockTests {
    let httpMock: HTTPMock
    let identifier: UUID

    var mockQueues: [HTTPMockURLProtocol.Key: [MockResponse]] {
        HTTPMockURLProtocol.getQueue(for: identifier)
    }

    init() {
        identifier = UUID()
        httpMock = HTTPMock(identifier: identifier)
        httpMock.defaultDomain = "example.com"
        HTTPMockLog.level = .trace
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
    func itReturnsAHardcodedMessageOn404NotFound() async throws {
        let url = try #require(URL(string: "https://example.com"))
        let (data, response) = try await httpMock.urlSession.data(from: url)

        #expect(response.httpStatusCode == 404)
        #expect(data.toString == "No mock for example.com/")
    }

    @Test
    func itDoesNotRegisterTheKeyIfNoResponsesAreProvided() {
        let key = createMockKey()
        httpMock.addResponses([], for: key)

        #expect(mockQueues.isEmpty)
    }

    @Test
    func itDoesNotRegisterResponsesWithInvalidLifetimes() {
        let key = createMockKey()
        httpMock.addResponses([
            .empty(lifetime: .multiple(0)),
            .empty(lifetime: .multiple(-1)),
        ], for: key)

        #expect(mockQueues.isEmpty)
    }

    @Test
    func itAllowsRegisteringResponsesAfterAnEternalResponse() {
        let key = createMockKey()
        httpMock.addResponses([
            .empty(lifetime: .eternal),
            .empty(lifetime: .single),
            .empty(lifetime: .multiple(100)),
        ], for: key)

        #expect(mockQueues[key]?.count == 3)
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

    // MARK: - Lifetime tests

    @Test
    func lifetime_single_isConsumedOnce() async throws {
        let key = createMockKey(path: "/lifetime-single")
        httpMock.addResponse(.plaintext("once", lifetime: .single), for: key)
        #expect(mockQueues[key]?.count == 1)

        let url = try #require(URL(string: "https://example.com/lifetime-single"))
        let (data1, response1) = try await httpMock.urlSession.data(from: url)
        #expect(response1.httpStatusCode == 200)
        #expect(data1.toString == "once")

        // Consumed and removed
        #expect(mockQueues[key]?.isEmpty == true)

        // Next call should 404 since nothing is queued
        let (_, response2) = try await httpMock.urlSession.data(from: url)
        #expect(response2.httpStatusCode == 404)
    }

    @Test
    func lifetime_multiple_isConsumedNTimes_thenRemoved() async throws {
        let key = createMockKey(path: "/lifetime-multi")
        httpMock.addResponse(.plaintext("multi", lifetime: .multiple(3)), for: key)
        #expect(mockQueues[key]?.count == 1)

        let url = try #require(URL(string: "https://example.com/lifetime-multi"))

        for _ in 1...3 {
            let (data, response) = try await httpMock.urlSession.data(from: url)
            #expect(response.httpStatusCode == 200)
            #expect(data.toString == "multi")
            // After each hit, the single queue entry either decrements or is removed at the end.
            // We only assert final removal below.
        }

        // After 3 uses it should be removed
        #expect(mockQueues[key]?.isEmpty == true)

        // A fourth call should 404
        let (_, response) = try await httpMock.urlSession.data(from: url)
        #expect(response.httpStatusCode == 404)
    }

    @Test
    func lifetime_eternal_isNeverRemoved() async throws {
        let key = createMockKey(path: "/lifetime-eternal")
        httpMock.addResponse(.plaintext("eternal", lifetime: .eternal), for: key)
        #expect(mockQueues[key]?.count == 1)

        let url = try #require(URL(string: "https://example.com/lifetime-eternal"))

        // Hit it multiple times. It should keep serving and never be removed.
        for _ in 0..<5 {
            let (data, response) = try await httpMock.urlSession.data(from: url)
            #expect(response.httpStatusCode == 200)
            #expect(data.toString == "eternal")
            #expect(mockQueues[key]?.count == 1) // Still present
        }
    }

    // MARK: - Delivery (delay) tests

    @Test
    func delivery_immediate_returnsQuickly() async throws {
        let key = createMockKey(path: "/delay-immediate")
        httpMock.addResponse(.plaintext("ok", delivery: .instant), for: key)

        let url = try #require(URL(string: "https://example.com/delay-immediate"))
        let start = Date()
        let (data, response) = try await httpMock.urlSession.data(from: url)
        let elapsed = Date().timeIntervalSince(start)

        #expect(response.httpStatusCode == 200)
        #expect(data.toString == "ok")

        // Should complete fast. Allow some time, "just in case"™.
        #expect(elapsed < 0.1)
    }

    @Test
    func delivery_delayed_respectsInterval() async throws {
        let key = createMockKey(path: "/delay-300ms")
        httpMock.addResponse(.plaintext("slow", delivery: .delayed(0.3)), for: key)

        let url = try #require(URL(string: "https://example.com/delay-300ms"))
        let start = Date()
        let (data, response) = try await httpMock.urlSession.data(from: url)
        let elapsed = Date().timeIntervalSince(start)

        #expect(response.httpStatusCode == 200)
        #expect(data.toString == "slow")

        // Subtract some time, just in case of scheduling jitter.
        #expect(elapsed >= 0.28)
    }

    @Test
    func delivery_appliesPerResponse_inFifoOrder() async throws {
        let key = createMockKey(path: "/delay-sequence")
        httpMock.addResponse(.plaintext("requested-first-but-delivered-second", delivery: .delayed(0.2)), for: key)
        httpMock.addResponse(.plaintext("requested-second-but-delivered-first", delivery: .delayed(0.1)), for: key)


        let url = try #require(URL(string: "https://example.com/delay-sequence"))

        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { try await httpMock.urlSession.data(from: url) }
            group.addTask { try await httpMock.urlSession.data(from: url) }

            var resultStrings = [String]()
            for try await tuple in group {
                resultStrings.append(tuple.0.toString)
            }

            let expectedOrder = [
                "requested-second-but-delivered-first",
                "requested-first-but-delivered-second"
            ]
            #expect(resultStrings == expectedOrder)
        }

        #expect(mockQueues[key]?.isEmpty == true)
    }


    // MARK: - Multiple instance isolation

    @Test
    func instances_haveIsolatedQueues() {
        // Current test instance has its own identifier/queues
        #expect(mockQueues.isEmpty)

        // Create a separate instance with its own identifier
        let otherIdentifier = UUID()
        let other = HTTPMock(identifier: otherIdentifier)

        // Register responses in both
        httpMock.addResponses(forPath: "/a", host: "one.example.com", responses: [.empty()])
        other.addResponses(forPath: "/b", host: "two.example.com", responses: [.empty()])

        // Queues are stored per-identifier; they should not mix
        let queues1 = HTTPMockURLProtocol.getQueue(for: identifier)
        let queues2 = HTTPMockURLProtocol.getQueue(for: otherIdentifier)

        #expect(queues1.count == 1)
        #expect(queues2.count == 1)
        #expect(Set(queues1.keys.map { $0.host }) == ["one.example.com"])
        #expect(Set(queues2.keys.map { $0.host }) == ["two.example.com"])
    }

    @Test
    func instances_doNotCrossServeResponses() async throws {
        // Two isolated mocks
        let idA = UUID()
        let mockA = HTTPMock(identifier: idA)
        mockA.defaultDomain = "api.a.com"

        let idB = UUID()
        let mockB = HTTPMock(identifier: idB)
        mockB.defaultDomain = "api.b.com"

        // Same path on different hosts, different payloads, and both responses eternal
        mockA.addResponses(forPath: "/ping", responses: [.plaintext("A", lifetime: .eternal)])
        mockB.addResponses(forPath: "/ping", responses: [.plaintext("B", lifetime: .eternal)])

        let urlA = try #require(URL(string: "https://api.a.com/ping"))
        let urlB = try #require(URL(string: "https://api.b.com/ping"))

        let (dataA, responseA) = try await mockA.urlSession.data(from: urlA)
        #expect(responseA.httpStatusCode == 200)
        #expect(dataA.toString == "A")

        let (dataB, responseB) = try await mockB.urlSession.data(from: urlB)
        #expect(responseB.httpStatusCode == 200)
        #expect(dataB.toString == "B")

        // Cross-call: mockA hitting B's URL should be 404 (no queue in A for that host)
        let (_, crossResponse1) = try await mockA.urlSession.data(from: urlB)
        #expect(crossResponse1.httpStatusCode == 404)

        // And mockB hitting A's URL should be 404
        let (_, crossResponse2) = try await mockB.urlSession.data(from: urlA)
        #expect(crossResponse2.httpStatusCode == 404)
    }

    @Test
    func clearingOneInstanceDoesNotAffectAnother() {
        let otherId = UUID()
        let other = HTTPMock(identifier: otherId)

        httpMock.addResponses(forPath: "/x", host: "x.com", responses: [.empty()])
        other.addResponses(forPath: "/y", host: "y.com", responses: [.empty()])

        // Sanity
        #expect(HTTPMockURLProtocol.getQueue(for: identifier).count == 1)
        #expect(HTTPMockURLProtocol.getQueue(for: otherId).count == 1)

        // Clear only this test instance
        httpMock.clearQueues()

        #expect(HTTPMockURLProtocol.getQueue(for: identifier).isEmpty)
        #expect(HTTPMockURLProtocol.getQueue(for: otherId).count == 1)

        // Now clear the other; both should be empty
        other.clearQueues()
        #expect(HTTPMockURLProtocol.getQueue(for: otherId).isEmpty)
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

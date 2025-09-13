import Testing
import Foundation
@testable import HTTPMock

struct HTTPMockResultBuilderTests {
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
    func itRegistersMultipleHosts() {
        httpMock.registerResponses {
            Host("domain.com") {
                Path("/") {
                    .empty()
                }
            }

            Host("other-domain.com") {
                Path("/") {
                    .empty()
                }
            }
        }

        let expectedQueues = [
            makeKey(host: "domain.com", path: "/"),
            makeKey(host: "other-domain.com", path: "/")
        ]
        #expect(Set(mockQueues.keys) == Set(expectedQueues))
    }

    @Test
    func itRegistersUsingNestedPaths() {
        httpMock.registerResponses {
            Path("root") {
                .empty()
                Path("child") {
                    .empty()
                    Path("grand-child") {
                        .empty()
                    }
                }
            }
        }

        let expectedQueues: Set<HTTPMockURLProtocol.Key> = [
            makeKey(path: "/root"),
            makeKey(path: "/root/child"),
            makeKey(path: "/root/child/grand-child"),
        ]
        #expect(mockQueues.count == 3)
        #expect(Set(mockQueues.keys) == expectedQueues)
    }

    @Test
    func itDoesNotRegisterHostsWithoutPaths() {
        httpMock.registerResponses {
            Host("domain.com") {}
        }

        #expect(mockQueues.isEmpty)
    }

    @Test
    func itDoesNotRegisterPathsWithoutResponses() {
        httpMock.registerResponses {
            Host("example.com") {
                Path("/some-path") {}
            }
        }

        #expect(mockQueues.isEmpty)
    }

    @Test
    func itRegistersMultiplePathsForTheSameHost() {
        httpMock.registerResponses {
            Host("example.com") {
                Path("/") {
                    .empty()
                }

                Path("/some-other-path") {
                    .empty()
                }
            }
        }

        let expectedQueues: [HTTPMockURLProtocol.Key] = [
            makeKey(host: "example.com", path: "/"),
            makeKey(host: "example.com", path: "/some-other-path")
        ]
        #expect(Set(mockQueues.keys) == Set(expectedQueues))
    }

    @Test
    func itRegistersUsingDefaultDomain() throws {
        httpMock.registerResponses {
            Path("root") {
                .empty()
            }
        }

        let expectedQueues: [HTTPMockURLProtocol.Key] = [
            makeKey(path: "/root")
        ]
        #expect(Set(mockQueues.keys) == Set(expectedQueues))
    }

    @Test
    func itRegistersUsingTheProvidedDomain() throws {
        httpMock.registerResponses(host: "domain.com") {
            Path("/") {
                .empty()
            }
        }

        #expect(mockQueues.count == 1)
        #expect(try #require(mockQueues.first?.key.host) == "domain.com")
    }

    @Test
    func itOnlyAllowsASinglePrefixedSlash() {
        httpMock.registerResponses {
            Host("a") {
                Path("") {
                    .empty()
                }
            }

            Host("b") {
                Path("/") {
                    .empty()
                }
            }

            Host("c") {
                Path("///////////////") {
                    .empty()
                }
            }

            Host("d") {
                Path("//////root//////") {
                    .empty()
                }
            }

            // It doesn't handle too many slashes in between.
            Host("e") {
                Path("//////root//////roooooot//////") {
                    .empty()
                }
            }
        }

        let expectedQueues: [HTTPMockURLProtocol.Key] = [
            makeKey(host: "a", path: "/"),
            makeKey(host: "b", path: "/"),
            makeKey(host: "c", path: "/"),
            makeKey(host: "d", path: "/root"),
            makeKey(host: "e", path: "/root//////roooooot"),
        ]
        #expect(Set(mockQueues.keys) == Set(expectedQueues))
    }

    @Test
    func itFlattensNestedRootPaths() {
        httpMock.registerResponses {
            Path("/") {
                Path("/") {
                    Path("/") {
                        Path("/") {
                            .empty()
                        }
                    }
                }
            }
        }

        let expectedQueues: [HTTPMockURLProtocol.Key] = [
            makeKey(path: "/")
        ]
        #expect(Set(mockQueues.keys) == Set(expectedQueues))
    }

    @Test
    func itAddsHeadersToResponses() throws {
        httpMock.registerResponses {
            Path("/") {
                Headers(["header": "value"])
                MockResponse.empty()
            }
        }

        let firstResponse = try #require(mockQueues.first?.value.first)
        #expect(firstResponse.headers == ["header": "value"])
    }

    @Test
    func headersAreNotCascadedByDefault() throws {
        httpMock.registerResponses {
            Path("/") {
                Headers(["header": "value"])

                Path("/child") {
                    MockResponse.empty()
                }
            }
        }

        let firstResponse = try #require(mockQueues.first?.value.first)
        #expect(firstResponse.headers == [:])
    }

    @Test
    func headersCanCascade() throws {
        httpMock.registerResponses {
            Path("/") {
                Headers(["header": "value"], shouldCascade: true)

                Path("/child") {
                    MockResponse.empty()
                }
            }
        }

        let firstResponse = try #require(mockQueues.first?.value.first)
        #expect(firstResponse.headers == ["header": "value"])
    }

    @Test
    func hostLevelHeadersAreAlwaysCascaded() throws {
        httpMock.registerResponses {
            Host("example.com") {
                Headers(["header": "value"], shouldCascade: true)
                Headers(["other": "value"], shouldCascade: false)

                Path("/") {
                    MockResponse.empty()
                }
            }
        }

        let firstResponse = try #require(mockQueues.first?.value.first)
        #expect(firstResponse.headers == ["header": "value", "other": "value"])
    }

    @Test
    func responseHeadersOverrideInheritedOnConflict() throws {
        httpMock.registerResponses {
            Host("example.com") {
                Headers(["X-Shared": "host"]) // Cascaded by host
                Path("/conflict") {
                    Headers(["X-Shared": "path"]) // Local override
                    MockResponse.plaintext("ok", headers: ["X-Shared": "response"]) // Response wins
                }
            }
        }

        let resp = try #require(mockQueues[makeKey(host: "example.com", path: "/conflict")]?.first)
        #expect(resp.headers["X-Shared"] == "response")
    }

    @Test
    func laterHeadersInSameScopeOverrideEarlierOnSameKey() throws {
        httpMock.registerResponses {
            Path("/") {
                Headers(["A": "1", "B": "x"]) // First
                Headers(["B": "2"]) // Overrides B
                MockResponse.empty()
            }
        }

        let resp = try #require(mockQueues.first?.value.first)
        #expect(resp.headers == ["A": "1", "B": "2"])
    }

    @Test
    func headersApplyRegardlessOfPositionWithinBlock() throws {
        httpMock.registerResponses {
            Path("/pos") {
                MockResponse.empty()
                Headers(["K": "V"]) // Placed after
            }
        }

        let resp = try #require(mockQueues[makeKey(path: "/pos")]?.first)
        #expect(resp.headers == ["K": "V"]) // Still applied
    }

    // MARK: - Query params via result builder (Path init)

    @Test
    func itRegistersExactQueryParamsOnPath() throws {
        httpMock.registerResponses {
            Path("/search", queryItems: ["q": "swift", "page": "1"], queryMatching: .exact) {
                .plaintext("ok-exact")
            }
        }

        // Find the key that matches host + path
        let key = try #require(mockQueues.keys.first { $0.host == httpMock.defaultDomain && $0.path == "/search" })
        #expect(key.queryMatching == .exact)
        #expect(key.queryItems == ["q": "swift", "page": "1"])

        // Ensure the queued response is present
        let queued = try #require(mockQueues[key])
        #expect(queued.count == 1)
    }

    @Test
    func query_exact_inResultBuilder_mustMatchAllAndOnlyThoseParams() async throws {
        httpMock.registerResponses {
            Path("/search", queryItems: ["q": "swift", "page": "1"], queryMatching: .exact) {
                .plaintext("ok-exact")
            }
        }

        // Same params, different order -> matches
        let url1 = try #require(URL(string: "https://\(httpMock.defaultDomain)/search?page=1&q=swift"))
        let (data1, response1) = try await httpMock.urlSession.data(from: url1)
        #expect(response1.httpStatusCode == 200)
        #expect(data1.toString == "ok-exact")

        // Extra param present -> should NOT match .exact, expect 404
        let url2 = try #require(URL(string: "https://\(httpMock.defaultDomain)/search?page=1&q=swift&foo=bar"))
        let (_, response2) = try await httpMock.urlSession.data(from: url2)
        #expect(response2.httpStatusCode == 404)
    }

    @Test
    func query_contains_inResultBuilder_allSpecifiedMustMatch_extrasIgnored() async throws {
        httpMock.registerResponses {
            Path("/search", queryItems: ["q": "swift"], queryMatching: .contains) {
                MockResponse.plaintext("ok-contains-1")
                MockResponse.plaintext("ok-contains-2")
            }
        }

        // Has extra params -> still matches (.contains)
        let url1 = try #require(URL(string: "https://\(httpMock.defaultDomain)/search?q=swift&page=2&sort=asc"))
        let (data1, response1) = try await httpMock.urlSession.data(from: url1)
        #expect(response1.httpStatusCode == 200)
        #expect(data1.toString == "ok-contains-1")

        // Only specified key present -> also matches, and consumes second queued response
        let url2 = try #require(URL(string: "https://\(httpMock.defaultDomain)/search?q=swift"))
        let (data2, response2) = try await httpMock.urlSession.data(from: url2)
        #expect(response2.httpStatusCode == 200)
        #expect(data2.toString == "ok-contains-2")
    }

    // MARK: - Helpers

    private func makeKey(
        host: String = "example.com",
        path: String = "/",
        queryItems: [String : String]? = nil,
        queryMatching: QueryMatching = .exact
    ) -> HTTPMockURLProtocol.Key {
        HTTPMockURLProtocol.Key(
            host: host,
            path: path,
            queryItems: queryItems,
            queryMatching: queryMatching
        )
    }
}

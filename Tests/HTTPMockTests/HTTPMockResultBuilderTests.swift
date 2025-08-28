import Testing
import Foundation
@testable import HTTPMock

struct HTTPMockResultBuilderTests {
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
            createMockKey(host: "domain.com", path: "/"),
            createMockKey(host: "other-domain.com", path: "/")
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
            createMockKey(path: "/root"),
            createMockKey(path: "/root/child"),
            createMockKey(path: "/root/child/grand-child"),
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
            createMockKey(host: "example.com", path: "/"),
            createMockKey(host: "example.com", path: "/some-other-path")
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
            createMockKey(path: "/root")
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
            createMockKey(host: "a", path: "/"),
            createMockKey(host: "b", path: "/"),
            createMockKey(host: "c", path: "/"),
            createMockKey(host: "d", path: "/root"),
            createMockKey(host: "e", path: "/root//////roooooot"),
        ]
        #expect(Set(mockQueues.keys) == Set(expectedQueues))
    }

    @Test
    func itDoesNotFlattenNestedRootPaths() {
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
            createMockKey(path: "////")
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

        let resp = try #require(mockQueues[createMockKey(host: "example.com", path: "/conflict")]?.first)
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

        let resp = try #require(mockQueues[createMockKey(path: "/pos")]?.first)
        #expect(resp.headers == ["K": "V"]) // Still applied
    }
}

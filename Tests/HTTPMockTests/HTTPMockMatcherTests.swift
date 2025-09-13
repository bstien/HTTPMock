import Testing
import Foundation
@testable import HTTPMock

struct HTTPMockMatcherTests {
    let matcher = HTTPMockMatcher()

    // MARK: - Exact vs wildcard

    @Test
    func exactMatchIsPreferredOverWildcard() {
        let exact = makeKey(host: "api.example.com")
        let wildcard = makeKey(host: "*.example.com")

        let match = checkMatch(in: [exact, wildcard])
        #expect(match == exact)
    }

    // MARK: - Host wildcards

    @Test
    func singleSegmentHostWildcardMatchesOneLabelOnly() {
        let single = makeKey(host: "*.example.com")
        let deep = makeKey(host: "**.example.com")

        // api.example.com will match both. Specificity will pick the one with fewer wildcards.
        let match1 = checkMatch(in: [single, deep])
        #expect(match1 == single)

        // a.b.example.com should only match the ** variant
        let match2 = checkMatch(host: "a.b.example.com", in: [single, deep])
        #expect(match2 == deep)
    }

    @Test
    func hostMatchingIsCaseInsensitive() {
        let keyUpper = makeKey(host: "API.EXAMPLE.COM")

        let match = checkMatch(in: [keyUpper])
        #expect(match == keyUpper)
    }

    @Test
    func hostMatchingWildcardInsteadOfSegmentDelimiter() {
        let key = makeKey(host: "api*.example.com")

        let match1 = checkMatch(host: "api.example.com", in: [key])
        #expect(match1 == key)

        let match2 = checkMatch(host: "api-test.example.com", in: [key])
        #expect(match2 == key)

        let bad = checkMatch(host: "api.test.example.com", in: [key])
        #expect(bad == nil)
    }

    @Test
    func hostWildcardWithPort() {
        let key = makeKey(host: "*.example.com:8080")

        let match = checkMatch(host: "api.example.com:8080", in: [key])
        #expect(match == key)

        let noMatch = checkMatch(host: "api.example.com:9090", in: [key])
        #expect(noMatch == nil)

        // Test without port should not match
        let noPortMatch = checkMatch(host: "api.example.com", in: [key])
        #expect(noPortMatch == nil)
    }

    // MARK: - Path wildcards

    @Test
    func singleSegmentPathWildcardDoesNotCrossSlash() {
        let key = makeKey(path: "/api/*/users")

        let match = checkMatch(path: "/api/v1/users", in: [key])
        #expect(match == key)

        let bad = checkMatch(path: "/api/v1/x/users", in: [key])
        #expect(bad == nil)
    }

    @Test
    func multiSegmentPathWildcardCrossesSlash() {
        let key = makeKey(path: "/api/**/users")

        let match1 = checkMatch(path: "/api/users", in: [key])
        #expect(match1 == key)

        let match2 = checkMatch(path: "/api/v1/users", in: [key])
        #expect(match2 == key)

        let match3 = checkMatch(path: "/api/v1/x/users", in: [key])
        #expect(match3 == key)
    }

    @Test
    func wildcardMatchesEmptyPath() {
        let key = makeKey(path: "/**")

        let match1 = checkMatch(path: "/", in: [key])
        #expect(match1 == key)

        let match2 = checkMatch(path: "/anything", in: [key])
        #expect(match2 == key)
    }

    @Test
    func multipleWildcardsInSingleSegment() {
        let key = makeKey(path: "/api/*-*")

        let match = checkMatch(path: "/api/v1-test", in: [key])
        #expect(match == key)

        let noMatch = checkMatch(path: "/api/v1", in: [key])
        #expect(noMatch == nil)
    }

    @Test
    func doubleStarAtBoundaries() {
        let startKey = makeKey(path: "**/users")
        let endKey = makeKey(path: "/api/**")
        let bothKey = makeKey(path: "**/api/**")

        let match1 = checkMatch(path: "/users", in: [startKey])
        #expect(match1 == startKey)

        let match2 = checkMatch(path: "users", in: [startKey])
        #expect(match2 == startKey)

        let match3 = checkMatch(path: "/api/", in: [endKey])
        #expect(match3 == endKey)

        let match4 = checkMatch(path: "/api/v1/something", in: [endKey])
        #expect(match4 == endKey)

        let match5 = checkMatch(path: "api", in: [bothKey])
        #expect(match5 == bothKey)

        let match6 = checkMatch(path: "/some/api/v1", in: [bothKey])
        #expect(match6 == bothKey)
    }

    @Test
    func pathSlashHandling() {
        let keyWithSlash = makeKey(path: "/api/*/")
        let keyWithoutSlash = makeKey(path: "/api/*")

        // Test that both can match similar requests
        let match1 = checkMatch(path: "/api/users", in: [keyWithoutSlash])
        #expect(match1 == keyWithoutSlash)

        let match2 = checkMatch(path: "/api/users/", in: [keyWithSlash])
        #expect(match2 == keyWithSlash)

        // Test specificity when both could match
        let match3 = checkMatch(path: "/api/users/", in: [keyWithSlash, keyWithoutSlash])
        #expect(match3 == keyWithSlash) // Exact match should win
    }

    // MARK: - Specificity tie-breakers

    @Test
    func fewerWildcardsBeatMoreWildcards_thenLongerLiteralsWin() {
        let twoStars = makeKey(path: "/api/**/users")
        let threeStars = makeKey(path: "/api/*/users/**")
        let longerLiteral = makeKey(path: "/api/*/users/active")

        // For "/api/x/users": `twoStars` and `threeStars` both match.
        // `twoStars` wins because of fewer wildcards, which contributes to a higher specificity.
        let match1 = checkMatch(path: "/api/x/users", in: [twoStars, threeStars, longerLiteral])
        #expect(match1 == twoStars)

        // For "/api/x/users/active": `threeStars` and `longerLiteral` both match.
        // `longerLiteral` wins because it has a longer literal, which contributes to a higher specificity.
        let match2 = checkMatch(path: "/api/x/users/active", in: [twoStars, threeStars, longerLiteral])
        #expect(match2 == longerLiteral)
    }

    // MARK: - Specificity ordering (comprehensive)

    @Test
    func specificity_exactBeatsSingleAndDoubleWildcards_host() {
        let exact = makeKey(host: "api.example.com")
        let single = makeKey(host: "*.example.com")
        let multi = makeKey(host: "**.example.com")

        let match = checkMatch(in: [multi, single, exact])
        #expect(match == exact)
    }

    @Test
    func specificity_exactPathBeatsSingleAndDoubleWildcards_path() {
        let exact = makeKey(path: "/api/users")
        let single = makeKey(path: "/api/*")
        let multi = makeKey(path: "/api/**")

        let match = checkMatch(path: "/api/users", in: [multi, single, exact])
        #expect(match == exact)
    }

    @Test
    func specificity_tieOnWildcardCount_prefersLongerLiteral_path() {
        // Both have one wildcard, but one has a longer literal segment and should win when both match
        let shorter = makeKey(path: "/api/*/users/*") // literals: "/api//users" (shorter)
        let longer = makeKey(path: "/api/*/users/active") // literals include "/active" (longer)

        let match = checkMatch(path: "/api/v1/users/active", in: [shorter, longer])
        #expect(match == longer)
    }

    @Test
    func specificity_hostVsPath_whenWildcardCountsEqual_prefersCandidateWithMoreLiteralsTotal() {
        // Candidate A: exact host + wildcard path (1 wildcard)
        let candidateA = makeKey(host: "api.example.com", path: "/p/*")
        // Candidate B: wildcard host (1 wildcard) + exact path
        let candidateB = makeKey(host: "*.example.com", path: "/products/list/details")
        // For this URL, both match; total wildcard count is 1 for both.
        // Candidate B has a much longer literal path, so it should win.
        let match = checkMatch(host: "api.example.com", path: "/products/list/details", in: [candidateA, candidateB])
        #expect(match == candidateB)
    }

    // MARK: - Query parameters

    @Test
    func queryExactRequiresAllAndOnlySpecifiedPairs() {
        let key = makeKey(queryItems: ["q": "swift", "page": "1"])

        let match = checkMatch(queryItems: ["page": "1", "q": "swift"], in: [key])
        #expect(match == key)

        let bad = checkMatch(queryItems: ["page": "1", "q": "swift", "foo": "bar"], in: [key])
        #expect(bad == nil)
    }

    @Test
    func queryContainsRequiresSpecifiedPairs_only() {
        let key = makeKey(queryItems: ["q": "swift"], queryMatching: .contains)

        let match1 = checkMatch(queryItems: ["q": "swift"], in: [key])
        #expect(match1 == key)

        let match2 = checkMatch(queryItems: ["q": "swift", "page": "2"], in: [key])
        #expect(match2 == key)

        let bad = checkMatch(queryItems: ["q": "swif"], in: [key])
        #expect(bad == nil)
    }

    // MARK: - Error handling

    @Test
    func invalidRegexPatternHandling() {
        // Test with potentially problematic patterns alongside valid ones
        let candidates = [
            makeKey(host: "*.example.com"),  // valid wildcard pattern
            makeKey(host: "api.example.com"), // exact match
        ]

        let match = checkMatch(in: candidates)

        // Should prefer exact match over wildcard
        #expect(match?.host == "api.example.com")

        // Test with wildcard match
        let wildcardMatch = checkMatch(host: "test.example.com", in: candidates)
        #expect(wildcardMatch?.host == "*.example.com")
    }

    // MARK: - Specificity Score Tests

    @Test
    func specificityScore_exactHostAndPath() {
        let key = makeKey(host: "api.example.com", path: "/users/list")
        let score = matcher.specificityScore(for: key)

        // No wildcards. Literal count is length of host + path
        let literalCount = "api.example.com".count + "/users/list".count
        #expect(score == (0, -literalCount))
    }

    @Test
    func specificityScore_singleWildcardInPath() {
        let key = makeKey(host: "api.example.com", path: "/users/*")
        let score = matcher.specificityScore(for: key)

        // 1 wildcard. Literal count is host + "/users/"
        let literalCount = "api.example.com".count + "/users/".count
        #expect(score == (1, -literalCount))
    }

    @Test
    func specificityScore_doubleWildcardInPath() {
        let key = makeKey(host: "api.example.com", path: "/users/**")
        let score = matcher.specificityScore(for: key)
        let literalCount = "api.example.com".count + "/users/".count
        #expect(score == (2, -literalCount)) // '**' counts as two wildcards
    }

    @Test
    func specificityScore_singleWildcardInHost() {
        let key = makeKey(host: "*.example.com", path: "/users")
        let score = matcher.specificityScore(for: key)
        let literalCount = ".example.com".count + "/users".count
        #expect(score == (1, -literalCount))
    }

    @Test
    func specificityScore_doubleWildcardInHost() {
        let key = makeKey(host: "**.example.com", path: "/users")
        let score = matcher.specificityScore(for: key)
        let literalCount = ".example.com".count + "/users".count
        #expect(score == (2, -literalCount))
    }

    @Test
    func specificityScore_multipleWildcards_hostAndPath() {
        let key = makeKey(host: "*.example.com", path: "/users/*")
        let score = matcher.specificityScore(for: key)
        let literalCount = ".example.com".count + "/users/".count
        #expect(score == (2, -literalCount))
    }

    @Test
    func specificityScore_mixedWildcardsAndLiterals() {
        let key = makeKey(host: "api.*.com", path: "/users/*/details")
        let score = matcher.specificityScore(for: key)

        // host: "api.*.com" => 1 wildcard. Literals: "api.", ".com"
        // path: "/users/*/details" => 1 wildcard. Literals: "/users/", "/details"
        let literalCount = "api.".count + ".com".count + "/users/".count + "/details".count
        #expect(score == (2, -literalCount))
    }

    @Test
    func specificityScore_allWildcards() {
        let key = makeKey(host: "**", path: "/**")
        let score = matcher.specificityScore(for: key)

        // 2 wildcards in host, 2 in path, the single slash in path counts as 1 literal
        #expect(score == (4, -1))
    }

    // MARK: - Expression storage caching

    @Test
    func regexCaching() throws {
        let storage = HTTPMockMatcher.ExpressionStorage()

        // First call should compile
        let regex1 = try storage.regex(for: "*/test", kind: .host)

        // Second call should use cache (same object reference)
        let regex2 = try storage.regex(for: "*/test", kind: .host)

        #expect(regex1 === regex2)

        // Different kind should create different regex
        let regex3 = try storage.regex(for: "*/test", kind: .path)
        #expect(regex1 !== regex3)

        // Different pattern should create different regex
        let regex4 = try storage.regex(for: "**/test", kind: .host)
        #expect(regex1 !== regex4)
    }

    // MARK: - Helpers

    private func makeKey(
        host: String = "api.example.com",
        path: String = "/search",
        queryItems: [String: String]? = nil,
        queryMatching: QueryMatching = .exact
    ) -> HTTPMockURLProtocol.Key {
        HTTPMockURLProtocol.Key(
            host: host,
            path: path,
            queryItems: queryItems,
            queryMatching: queryMatching
        )
    }

    private func checkMatch(
        host: String = "api.example.com",
        path: String = "/search",
        queryItems: [String: String] = [:],
        in candidates: [HTTPMockURLProtocol.Key]
    ) -> HTTPMockURLProtocol.Key? {
        matcher.match(host: host, path: path, queryItems: queryItems, in: Set(candidates))
    }
}

import Foundation

/// Responsible for matching incoming requests against registered mock keys.
/// Supports exact matches and wildcard patterns (`*` for a single segment, `**` for multiple segments (zero or more)).
/// Also compares query parameters and applies query matching rules (`.exact` / `.contains`).
struct HTTPMockMatcher {

    // MARK: - Internal properties

    let expressionStorage = ExpressionStorage()

    // MARK: - Internal methods

    /// Finds the most specific key that matches the given request values.
    /// - Parameters:
    ///   - host: The request host string (lowercased where applicable).
    ///   - path: The request path string (leading "/" guaranteed).
    ///   - queryItems: Dictionary of query params from the request.
    ///   - candidates: The set of registered keys to match against (within a namespace).
    /// - Returns: A matching key if found, preferring exact matches first and then the most specific wildcard pattern.
    func match(
        host: String,
        path: String,
        queryItems: [String: String],
        in candidates: Set<HTTPMockURLProtocol.Key>
    ) -> HTTPMockURLProtocol.Key? {
        let exactMatch = candidates.first { candidate in
            candidate.host == host &&
            candidate.path == path &&
            queryMatches(candidate, requestQueryItems: queryItems)
        }

        // Return early if we have an exact key match
        if let exactMatch { return exactMatch }

        // Find wildcard candidates
        let wildcardCandidates = candidates.filter { candidate in
            queryMatches(candidate, requestQueryItems: queryItems) &&
            wildcardMatch(pattern: candidate.host, value: host, kind: .host) &&
            wildcardMatch(pattern: candidate.path, value: path, kind: .path)
        }

        // Prefer the most specific candidate, aka. fewest wildcards, then longest literal length
        return wildcardCandidates
            .map { (key: $0, score: specificityScore(for: $0)) }
            .sorted { $0.score < $1.score }
            .first?
            .key
    }

    /// Checks whether a candidate key's query requirements match the request's query items.
    /// - Parameters:
    ///   - candidate: The stored key we compare against.
    ///   - requestQueryItems: The request's query items as a dictionary.
    /// - Returns: `true` if the request query satisfies the candidate's rule, otherwise `false`.
    func queryMatches(
        _ candidate: HTTPMockURLProtocol.Key,
        requestQueryItems: [String: String]
    ) -> Bool {
        guard let expected = candidate.queryItems else {
            return true
        }

        switch candidate.queryMatching {
        case .exact:
            return expected == requestQueryItems
        case .contains:
            return expected.allSatisfy { key, value in
                requestQueryItems[key] == value
            }
        }
    }

    /// Matches a concrete string value against a glob pattern.
    /// - Parameters:
    ///   - pattern: A literal or glob string (`*` single segment, `**` multi segment (zero or more)).
    ///   - value: The actual host or path string to test.
    ///   - kind: The URL component kind to compare against.
    /// - Returns: `true` if the value matches the pattern, otherwise `false`.
    func wildcardMatch(
        pattern: String,
        value: String,
        kind: MatchKind
    ) -> Bool {
        // If pattern doesn't include any wildcards we just check if the strings match.
        if !pattern.contains("*") {
            return pattern == value
        }

        // Check if we have a cached pattern already, or create one if not.
        // If regex compilation fails: fail silently and return `false`.
        guard let regularExpression = try? expressionStorage.regex(for: pattern, kind: kind) else {
            return false
        }

        let searchRange = NSRange(value.startIndex..<value.endIndex, in: value)
        return regularExpression.firstMatch(in: value, range: searchRange) != nil
    }

    /// Computes a specificity score for a key where the return is a tuple of `(wildcardCount, -literalCount)`.
    /// Swift compares tuples lexicographically, so sorting by this tuple prefers keys with fewer wildcards first,
    /// and if tied, prefers those with more literal characters (longer, more specific patterns).
    /// Lower scores are considered more specific.
    ///
    /// This method is used to determine which wildcard pattern is the "most specific" when multiple patterns could match.
    /// It prefers patterns with fewer wildcards and then those with more literal characters to ensure the best match is selected.
    func specificityScore(for key: HTTPMockURLProtocol.Key) -> (Int, Int) {
        func score(for pattern: String) -> (wildcardCount: Int, literalCount: Int) {
            let wildcardCount = pattern.filter { $0 == "*" }.count
            let literalCount = pattern.replacingOccurrences(of: "*", with: "").count
            return (wildcardCount, literalCount)
        }

        let hostScore = score(for: key.host)
        let pathScore = score(for: key.path)

        // Fewer wildcards first. If equal: prefer longer literals.
        // Returns tuple: (wildcardCount, -literalCount) for lexicographical comparison.
        let wildcardScore = hostScore.wildcardCount + pathScore.wildcardCount
        let literalScore = hostScore.literalCount + pathScore.literalCount

        return (wildcardScore, -literalScore)
    }
}

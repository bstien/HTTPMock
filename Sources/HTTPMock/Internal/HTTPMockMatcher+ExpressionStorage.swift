import Foundation

extension HTTPMockMatcher {
    /// Shared cache for compiled wildcard regular expressions.
    /// Compiles lazily on first use and reuses across instances and namespaces.
    class ExpressionStorage {

        // MARK: - Internal properties

        var hostExpressions = [String: NSRegularExpression]()
        var pathExpressions = [String: NSRegularExpression]()

        // MARK: - Private properties

        private let lock = NSLock()

        // MARK: - Init

        init() {}

        // MARK: - Internal methods

        /// Returns (and caches) a compiled `NSRegularExpression` for the given glob pattern.
        ///
        /// For path patterns, the `/**/` segment is treated as optional to allow matching zero segments.
        /// This means `/api/**/users` will match both `/api/users` and `/api/x/users`.
        /// - Parameters:
        ///   - pattern: The glob pattern to compile.
        ///   - kind: The URL component kind to create regex for.
        /// - Throws: Any compilation error from `NSRegularExpression` if the pattern is invalid.
        func regex(for pattern: String, kind: MatchKind) throws -> NSRegularExpression {
            lock.lock()
            defer { lock.unlock() }

            // Check if we have a cached regex already
            switch kind {
            case .host:
                if let cached = hostExpressions[pattern] {
                    return cached
                }
            case .path:
                if let cached = pathExpressions[pattern] {
                    return cached
                }
            }

            let compiled = try compile(pattern: pattern, kind: kind)

            switch kind {
            case .host: hostExpressions[pattern] = compiled
            case .path: pathExpressions[pattern] = compiled
            }

            return compiled
        }

        // MARK: - Private methods

        /// Compiles a glob pattern into a regular expression.
        /// `*` matches a single segment, `**` matches across segments.
        ///
        /// For path patterns, `/**/` is made optional to allow zero segments between slashes.
        /// - Parameters:
        ///   - pattern: The glob pattern.
        ///   - kind: The URL component kind to create regex for.
        /// - Returns: A compiled regular expression anchored to the start and end of the string.
        private func compile(pattern: String, kind: MatchKind) throws -> NSRegularExpression {
            // Escape regex meta characters first.
            var escaped = NSRegularExpression.escapedPattern(for: pattern)

            if case .path = kind {
                // Make "/**/" optional so `**` can match zero segments between slashes.
                // Example: `/api/**/users` should match both `/api/users` and `/api/v1/users`.
                escaped = escaped.replacingOccurrences(of: "\\/\\*\\*\\/", with: "(?:/.*)?")

                // If the pattern starts with `**/`, make the leading prefix optional.
                escaped = escaped.replacingOccurrences(of: "\\*\\*\\/", with: "(?:.*/)?")

                // If the pattern ends with `/**`, make the trailing suffix optional.
                escaped = escaped.replacingOccurrences(of: "\\/\\*\\*", with: "(?:/.*)?")
            }

            // Replace glob tokens. Order matters: handle `**` before `*`.
            escaped = escaped.replacingOccurrences(of: "\\*\\*", with: ".*")
            escaped = escaped.replacingOccurrences(of: "\\*", with: kind.singleSegmentClass)

            return try NSRegularExpression(
                pattern: "^" + escaped + "$",
                options: kind.regexOptions
            )
        }
    }
}

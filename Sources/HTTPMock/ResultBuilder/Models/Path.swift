import Foundation

public struct Path {
    let path: String
    let responses: [MockResponse]
    let children: [Path]
    let localHeaders: [Headers]

    public init(_ path: String, @PathBuilder _ content: () -> [PathElement]) {
        var responses: [MockResponse] = []
        var children: [Path] = []
        var localHeaders: [Headers] = []

        for element in content() {
            switch element {
            case .response(let response): responses.append(response)
            case .child(let path): children.append(path)
            case .headers(let headers): localHeaders.append(headers)
            }
        }

        self.path = path
        self.responses = responses
        self.children = children
        self.localHeaders = localHeaders
    }

    /// Recursively converts the path tree into an array of `Registration` objects.
    /// Each registration's path is prefixed with its parent paths to form the full path.
    ///  
    /// - Parameter parents: An array of parent path segments used to build the full path. Defaults to an empty array.
    /// - Returns: An array of `Registration` objects representing all paths and their associated responses.
    func flatten(into parents: [String] = [], inheritedHeaders: [String: String] = [:]) -> [Registration] {
        // Apply this path's header declarations in order:
        // keep a running "current" header map, but only pass along the ones marked cascade
        var headersForSelf = inheritedHeaders
        var cascadingHeaders = inheritedHeaders

        for headers in localHeaders {
            headersForSelf.mergeInOther(headers.values)

            if headers.shouldCascade {
                cascadingHeaders.mergeInOther(headers.values)
            }
        }

        let fullPath = joinPaths(parents + [path])
        var registrations = [Registration]()

        // Register this node, if it has a list of responses.
        if !responses.isEmpty {
            let selfRegistration = Registration(
                path: fullPath,
                headers: headersForSelf,
                responses: responses
            )
            registrations.append(selfRegistration)
        }

        // Iterate through all children and create registrations for those.
        for child in children {
            let parentPaths = parents + [path]
            let childRegistrations = child.flatten(into: parentPaths, inheritedHeaders: cascadingHeaders)
            registrations.append(contentsOf: childRegistrations)
        }

        return registrations
    }

    /// Joins and normalizes path segments into a single valid path string.
    /// This method trims leading and trailing slashes from each segment,
    /// removes empty segments, and avoids duplicate slashes in the resulting path.
    ///
    /// - Parameter segments: An array of path segments to join.
    /// - Returns: A normalized path string starting with a single slash.
    func joinPaths(_ segments: [String]) -> String {
        let trimmed = segments.compactMap {
            if $0 == "/" {
                return ""
            }

            let trimmed = $0.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return trimmed.isEmpty ? nil : trimmed
        }
        return "/" + trimmed.joined(separator: "/")
    }
}

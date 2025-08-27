import Foundation

public struct Path {
    let node: Node

    public init(_ path: String, @PathBuilder _ content: () -> [PathElement]) {
        var responses: [MockResponse] = []
        var children: [Node] = []

        for element in content() {
            switch element {
            case .response(let value): responses.append(value)
            case .child(let value): children.append(value.node)
            }
        }

        node = Node(path: path, responses: responses, children: children)
    }
}

extension Path {
    struct Node {
        let path: String
        let responses: [MockResponse]
        let children: [Node]

        func flatten(into parents: [String] = []) -> [Registration] {
            let fullPath = joinPaths(parents + [path])
            var registrations = [Registration]()

            if !responses.isEmpty {
                registrations.append(Registration(path: fullPath, responses: responses))
            }

            for child in children {
                registrations.append(contentsOf: child.flatten(into: parents + [path]))
            }

            return registrations
        }

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
}

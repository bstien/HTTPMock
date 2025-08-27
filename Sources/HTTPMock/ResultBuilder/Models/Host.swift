import Foundation

public struct Host {
    let node: Node

    public init(_ host: String, @HostBuilder _ content: () -> [Path]) {
        node = Node(host: host, paths: content())
    }
}

extension Host {
    struct Node {
        let host: String
        let paths: [Path]

        func flatten() -> [Registration] {
            paths.flatMap { $0.node.flatten() }
        }
    }
}

import Foundation

public struct Host {
    let host: String
    let paths: [Path]

    public init(_ host: String, @HostBuilder _ content: () -> [Path]) {
        self.host = host
        self.paths = content()
    }

    func flatten() -> [Registration] {
        paths.flatMap { $0.flatten() }
    }
}

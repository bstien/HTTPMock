import Foundation

public struct Host {
    let host: String
    let paths: [Path]
    let baseHeaders: [Headers]

    public init(_ host: String, @HostBuilder _ content: () -> [HostElement]) {
        self.host = host
        var paths = [Path]()
        var baseHeaders = [Headers]()

        for element in content() {
            switch element {
            case .path(let path): paths.append(path)
            case .headers(let headers): baseHeaders.append(headers)
            }
        }

        self.paths = paths
        self.baseHeaders = baseHeaders
    }

    func flatten() -> [Registration] {
        // Compute host-level inherited headers with cascade handling
        var topLevelHeaders: [String: String] = [:]

        for headers in baseHeaders {
            topLevelHeaders.mergeInOther(headers.values)
        }

        return paths.flatMap { $0.flatten(into: [], inheritedHeaders: topLevelHeaders) }
    }
}

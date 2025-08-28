import Foundation

extension [URLQueryItem]? {
    var toDictionary: [String: String] {
        guard let self else { return [:] }
        return self.reduce(into: [:]) { $0[$1.name] = $1.value }
    }
}

import Foundation

extension MockResponse {
    public enum Status: Hashable {
        case ok
        case unauthorized
        case notFound
        case other(Int)

        var code: Int {
            switch self {
            case .ok: 200
            case .unauthorized: 401
            case .notFound: 404
            case .other(let code): code
            }
        }
    }
}

import Foundation

extension MockResponse {
    public enum Lifetime: Hashable {
        case single
        case multiple(Int)
        case eternal
    }
}

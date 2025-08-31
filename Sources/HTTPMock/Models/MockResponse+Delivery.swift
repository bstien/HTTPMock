import Foundation

extension MockResponse {
    public enum Delivery: Hashable {
        case instant
        case delayed(TimeInterval)
    }
}

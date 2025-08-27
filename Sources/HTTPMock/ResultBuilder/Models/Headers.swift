import Foundation

public struct Headers: Equatable {
    public let values: [String: String]
    public let shouldCascade: Bool

    public init(_ values: [String: String], shouldCascade: Bool = false) {
        self.values = values
        self.shouldCascade = shouldCascade
    }
}

import Foundation

extension Dictionary {
    mutating func mergeInOther(_ other: Dictionary) {
        self.merge(other) { (_, new) in new }
    }

    func mergedInOther(_ other: Dictionary) -> Dictionary {
        var result = self
        result.mergeInOther(other)
        return result
    }
}

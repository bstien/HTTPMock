import Foundation

extension Data {
    var toString: String {
        String(decoding: self, as: UTF8.self)
    }
}

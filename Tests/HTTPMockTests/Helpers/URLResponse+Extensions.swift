import Foundation

extension URLResponse {
    var httpStatusCode: Int? {
        (self as? HTTPURLResponse)?.statusCode
    }
}

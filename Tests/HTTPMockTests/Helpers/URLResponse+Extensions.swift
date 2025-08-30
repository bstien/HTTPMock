import Foundation

extension URLResponse {
    var httpStatusCode: Int? {
        (self as? HTTPURLResponse)?.statusCode
    }

    func headerValue(for headerName: String) -> String? {
        (self as? HTTPURLResponse)?.value(forHTTPHeaderField: headerName)
    }
}

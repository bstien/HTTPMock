import Foundation

public struct MockResponse: Hashable {

    // MARK: - Public properties

    public let payload: Payload
    public let status: Status
    public let headers: [String: String]

    // MARK: - Init

    public init(
        payload: Payload,
        status: Status = .ok,
        headers: [String: String] = [:]
    ) {
        self.payload = payload
        self.status = status

        if let contentType = payload.contentType {
            // Merge the headers, allowing the user to overwrite any we set.
            var defaultHeaders = ["Content-Type": contentType]
            defaultHeaders.merge(headers, uniquingKeysWith: { _, new in new })
            self.headers = defaultHeaders
        } else {
            self.headers = headers
        }
    }
}

// MARK: - Convenience initializers

extension MockResponse {
    public static func encodable<T: Encodable>(
        _ payload: T,
        status: Status = .ok,
        headers: [String: String] = [:],
        jsonEncoder: JSONEncoder = .mockDefault
    ) throws -> MockResponse {
        let data = try jsonEncoder.encode(payload)
        return Self.init(
            payload: .data(data, contentType: "application/json"),
            status: status,
            headers: headers
        )
    }

    public static func dictionary(
        _ payload: [String: Any],
        status: Status = .ok,
        headers: [String: String] = [:]
    ) throws -> MockResponse {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return Self.init(
            payload: .data(data, contentType: "application/json"),
            status: status,
            headers: headers
        )
    }

    public static func plaintext(
        _ payload: String,
        status: Status = .ok,
        headers: [String: String] = [:]
    ) -> MockResponse {
        let data = Data(payload.utf8)
        return Self.init(
            payload: .data(data, contentType: "text/plain"),
            status: status,
            headers: headers
        )
    }

    public static func empty(
        status: Status = .ok,
        headers: [String: String] = [:]
    ) -> MockResponse {
        Self.init(
            payload: .empty,
            status: status,
            headers: headers
        )
    }
}

// MARK: - Internal methods

extension MockResponse {
    func payloadData() throws -> Data {
        switch payload {
        case .data(let data, _):
            return data
        case .empty:
            return Data()
        }
    }
}

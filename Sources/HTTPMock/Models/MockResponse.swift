import Foundation
import UniformTypeIdentifiers

public struct MockResponse: Hashable {

    // MARK: - Public properties

    public let payload: Payload
    public let status: Status
    public let lifetime: Lifetime
    public let delivery: Delivery
    public let headers: [String: String]

    // MARK: - Init

    public init(
        payload: Payload,
        status: Status = .ok,
        lifetime: Lifetime = .single,
        delivery: Delivery = .instant,
        headers: [String: String] = [:]
    ) {
        self.payload = payload
        self.status = status
        self.lifetime = lifetime
        self.delivery = delivery

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
        lifetime: Lifetime = .single,
        delivery: Delivery = .instant,
        headers: [String: String] = [:],
        jsonEncoder: JSONEncoder = .mockDefault
    ) throws -> MockResponse {
        let data = try jsonEncoder.encode(payload)
        return Self.init(
            payload: .data(data, contentType: "application/json"),
            status: status,
            lifetime: lifetime,
            delivery: delivery,
            headers: headers
        )
    }

    public static func dictionary(
        _ payload: [String: Any],
        status: Status = .ok,
        lifetime: Lifetime = .single,
        delivery: Delivery = .instant,
        headers: [String: String] = [:]
    ) throws -> MockResponse {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return Self.init(
            payload: .data(data, contentType: "application/json"),
            status: status,
            lifetime: lifetime,
            delivery: delivery,
            headers: headers
        )
    }

    public static func plaintext(
        _ payload: String,
        status: Status = .ok,
        lifetime: Lifetime = .single,
        delivery: Delivery = .instant,
        headers: [String: String] = [:]
    ) -> MockResponse {
        let data = Data(payload.utf8)
        return Self.init(
            payload: .data(data, contentType: "text/plain"),
            status: status,
            lifetime: lifetime,
            delivery: delivery,
            headers: headers
        )
    }

    public static func empty(
        status: Status = .ok,
        lifetime: Lifetime = .single,
        delivery: Delivery = .instant,
        headers: [String: String] = [:]
    ) -> MockResponse {
        Self.init(
            payload: .empty,
            status: status,
            lifetime: lifetime,
            delivery: delivery,
            headers: headers
        )
    }

    /// Load a file from a Bundle (e.g. `Bundle.module`) and queue it as a response.
    /// Fails fast in tests if the file is missing or unreadable.
    /// - Parameters:
    ///   - name: The name of the file to serve.
    ///   - fileExtension: The extension of the file to serve.
    ///   - bundle: The bundle to search for the file.
    ///   - status: The HTTP status to return for this response.
    ///   - headers: Headers to include in this response.
    ///   - contentType: The `Content-Type` for this response. Leave as `nil` to infer the content type from the file.
    /// - Returns: A mocked response.
    public static func file(
        named name: String,
        extension fileExtension: String? = nil,
        in bundle: Bundle = .main,
        status: Status = .ok,
        lifetime: Lifetime = .single,
        delivery: Delivery = .instant,
        headers: [String: String] = [:],
        contentType: String? = nil
    ) -> MockResponse {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
            preconditionFailure("HTTPMock: file '\(name)\(fileExtension.map {".\($0)"} ?? "")' not found in bundle \(bundle).")
        }
        return file(
            url: url,
            status: status,
            lifetime: lifetime,
            delivery: delivery,
            headers: headers,
            contentType: contentType
        )
    }

    /// Load file from a URL.
    /// Fails fast in tests if the file is missing or unreadable.
    /// - Parameters:
    ///   - url: A URL pointing to the file to serve.
    ///   - status: The HTTP status to return for this response.
    ///   - headers: Headers to include in this response.
    ///   - contentType: The `Content-Type` for this response. Leave as `nil` to infer the content type from the file.
    /// - Returns: A mocked response.
    public static func file(
        url: URL,
        status: Status = .ok,
        lifetime: Lifetime = .single,
        delivery: Delivery = .instant,
        headers: [String: String] = [:],
        contentType: String? = nil
    ) -> MockResponse {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            preconditionFailure("HTTPMock: failed reading file at \(url): \(error)")
        }

        let contentType = contentType ?? inferredMIMEType(for: url) ?? "application/octet-stream"

        return MockResponse(
            payload: .data(data, contentType: contentType),
            status: status,
            lifetime: lifetime,
            delivery: delivery,
            headers: headers
        )
    }

    // MARK: - Private methods

    /// Best-effort MIME inference from the file extension.
    private static func inferredMIMEType(for url: URL) -> String? {
        UTType(filenameExtension: url.pathExtension.lowercased())?.preferredMIMEType
    }
}

// MARK: - Internal properties/methods

extension MockResponse {
    var isEternal: Bool {
        lifetime == .eternal
    }

    var hasValidLifetime: Bool {
        switch lifetime {
        case .single, .eternal: true
        case .multiple(let count): count > 0
        }
    }

    func payloadData() throws -> Data {
        switch payload {
        case .data(let data, _):
            return data
        case .empty:
            return Data()
        }
    }

    func addingHeaders(_ extra: [String: String]) -> MockResponse {
        // Headers set on this response should override inherited ones on conflict.
        MockResponse(
            payload: self.payload,
            status: self.status,
            lifetime: lifetime,
            delivery: delivery,
            headers: extra.mergedInOther(self.headers)
        )
    }

    func copyWithNewLifetime(_ newLifetime: Lifetime) -> MockResponse {
        MockResponse(
            payload: payload,
            status: status,
            lifetime: newLifetime,
            delivery: delivery,
            headers: headers
        )
    }
}

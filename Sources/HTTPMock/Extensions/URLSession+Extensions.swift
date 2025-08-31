import Foundation
import ObjectiveC.runtime

private var MockIdentifierKey: UInt8 = 0

extension URLSession {
    /// Attach/read a UUID on a URLSession instance.
    var mockIdentifier: UUID? {
        get { objc_getAssociatedObject(self, &MockIdentifierKey) as? UUID }
        set { objc_setAssociatedObject(self, &MockIdentifierKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    static func identifiedSession(with identifier: UUID) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPMockURLProtocol.self]

        let urlSession = URLSession(configuration: configuration)
        urlSession.mockIdentifier = identifier

        return urlSession
    }
}

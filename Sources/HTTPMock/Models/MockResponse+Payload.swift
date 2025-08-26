import Foundation

extension MockResponse {
    public enum Payload: Hashable {
        case data(Data, contentType: String?)
        case empty

        var contentType: String? {
            switch self {
            case .data(_, let contentType):
                return contentType
            case .empty:
                return nil
            }
        }
    }
}

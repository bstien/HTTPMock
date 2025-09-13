import Foundation

extension HTTPMockMatcher {
    enum MatchKind {
        case host
        case path

        var singleSegmentClass: String {
            switch self {
            case .host: "[^.]*" // Segment delimiter is `.`
            case .path: "[^/]*" // Segment delimiter is `/`
            }
        }

        var regexOptions: NSRegularExpression.Options {
            switch self {
            case .host: [.caseInsensitive]
            case .path: []
            }
        }
    }
}

import Foundation

public enum QueryMatching {
    /// All query params must match.
    case exact
    /// Only the provided query params must match. Others are ignored.
    case contains
}

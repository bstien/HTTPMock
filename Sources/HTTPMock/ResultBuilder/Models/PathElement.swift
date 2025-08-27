import Foundation

public enum PathElement {
    case response(MockResponse)
    case child(Path)
}

import Foundation

@resultBuilder
public enum PathBuilder {
    public static func buildBlock(_ components: [PathElement]...) -> [PathElement] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: MockResponse) -> [PathElement] {
        [.response(expression)]
    }

    public static func buildExpression(_ expression: [MockResponse]) -> [PathElement] {
        expression.map { .response($0) }
    }

    public static func buildExpression(_ expression: Path) -> [PathElement] {
        [.child(expression)]
    }

    public static func buildExpression(_ expression: Headers) -> [PathElement] {
        [.headers(expression)]
    }

    public static func buildExpression(_ expression: [PathElement]) -> [PathElement] {
        expression
    }

    public static func buildOptional(_ component: [PathElement]?) -> [PathElement] {
        component ?? []
    }

    public static func buildEither(first component: [PathElement]) -> [PathElement] {
        component
    }

    public static func buildEither(second component: [PathElement]) -> [PathElement] {
        component
    }

    public static func buildArray(_ components: [[PathElement]]) -> [PathElement] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ component: [PathElement]) -> [PathElement] {
        component
    }
}

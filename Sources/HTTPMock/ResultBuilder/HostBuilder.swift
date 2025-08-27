import Foundation

@resultBuilder
public enum HostBuilder {
    public static func buildBlock(_ components: [HostElement]...) -> [HostElement] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: Path) -> [HostElement] {
        [.path(expression)]
    }

    public static func buildExpression(_ expression: [Path]) -> [HostElement] {
        expression.map { .path($0) }
    }

    public static func buildExpression(_ expression: Headers) -> [HostElement] {
        [.headers(expression)]
    }

    public static func buildOptional(_ component: [HostElement]?) -> [HostElement] {
        component ?? []
    }

    public static func buildEither(first component: [HostElement]) -> [HostElement] {
        component
    }

    public static func buildEither(second component: [HostElement]) -> [HostElement] {
        component
    }

    public static func buildArray(_ components: [[HostElement]]) -> [HostElement] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ component: [HostElement]) -> [HostElement] {
        component
    }
}

import Foundation

@resultBuilder
public enum HostBuilder {
    public static func buildBlock(_ components: [Path]...) -> [Path] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: Path) -> [Path] {
        [expression]
    }

    public static func buildExpression(_ expression: [Path]) -> [Path] {
        expression
    }

    public static func buildOptional(_ component: [Path]?) -> [Path] {
        component ?? []
    }

    public static func buildEither(first component: [Path]) -> [Path] {
        component
    }

    public static func buildEither(second component: [Path]) -> [Path] {
        component
    }

    public static func buildArray(_ components: [[Path]]) -> [Path] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ component: [Path]) -> [Path] {
        component
    }
}

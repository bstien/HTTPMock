import Foundation

@resultBuilder
public enum RegistrationBuilder {
    public static func buildBlock(_ components: [Host]...) -> [Host] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: Host) -> [Host] {
        [expression]
    }

    public static func buildExpression(_ expression: [Host]) -> [Host] {
        expression
    }

    public static func buildOptional(_ component: [Host]?) -> [Host] {
        component ?? []
    }

    public static func buildEither(first component: [Host]) -> [Host] {
        component
    }

    public static func buildEither(second component: [Host]) -> [Host] {
        component
    }

    public static func buildArray(_ components: [[Host]]) -> [Host] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ component: [Host]) -> [Host] {
        component
    }
}

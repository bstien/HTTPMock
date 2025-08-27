import Foundation

extension HTTPMock {
    /// Register hosts/paths/responses using a hierarchical builder.
    public func registerResponses(@RegistrationBuilder _ content: () -> [Host]) {
        for host in content() {
            for registration in host.node.flatten() {
                addResponses(
                    forPath: registration.path,
                    host: host.node.host,
                    responses: registration.responses
                )
            }
        }
    }

    /// Register paths/responses for a single host using a path-only builder.
    public func registerResponses(host: String, @PathBuilder _ content: () -> [PathElement]) {
        let node = Path("", content).node
        for registration in node.flatten() {
            addResponses(
                forPath: registration.path,
                host: host,
                responses: registration.responses
            )
        }
    }

    /// Register paths/responses for the `HTTPMock.shared.defaultDomain` using a path-only builder.
    public func registerResponses(@PathBuilder _ content: () -> [PathElement]) {
        registerResponses(host: defaultDomain, content)
    }
}

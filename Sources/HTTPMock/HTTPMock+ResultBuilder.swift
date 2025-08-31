import Foundation

extension HTTPMock {
    /// Register hosts/paths/responses using a hierarchical builder.
    public func registerResponses(@RegistrationBuilder _ content: () -> [Host]) {
        for host in content() {
            for registration in host.flatten() {
                // Map each registration to a new `MockResponse` using the inherited headers.
                let finalResponses = registration.responses.map {
                    $0.addingHeaders(registration.headers)
                }

                // Register the responses for the given host and path.
                let key = HTTPMockURLProtocol.Key(
                    host: host.host,
                    path: registration.path,
                    queryItems: registration.queryItems,
                    queryMatching: registration.queryMatching ?? .exact
                )
                HTTPMockURLProtocol.add(responses: finalResponses, forKey: key, forMockIdentifier: mockIdentifier)
            }
        }
    }

    /// Register paths/responses for a single host using a path-only builder.
    public func registerResponses(host: String, @PathBuilder _ content: () -> [PathElement]) {
        let node = Path("", content)
        for registration in node.flatten() {
            // Map each registration to a new `MockResponse` using the inherited headers.
            let finalResponses = registration.responses.map {
                $0.addingHeaders(registration.headers)
            }

            // Register the responses for the given host and path.
            let key = HTTPMockURLProtocol.Key(
                host: host,
                path: registration.path,
                queryItems: registration.queryItems,
                queryMatching: registration.queryMatching ?? .exact
            )
            HTTPMockURLProtocol.add(responses: finalResponses, forKey: key, forMockIdentifier: mockIdentifier)
        }
    }

    /// Register paths/responses for the `HTTPMock.shared.defaultDomain` using a path-only builder.
    public func registerResponses(@PathBuilder _ content: () -> [PathElement]) {
        registerResponses(host: defaultDomain, content)
    }
}

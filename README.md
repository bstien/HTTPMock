<p align="center">
    <img width="1280px" src="assets/logo.png">
</p>

A tiny, test-first way to mock `URLSession` — **fast to set up, easy to read, zero test servers**. Queue responses for specific hosts/paths (and optional query params), then run your code against a regular `URLSession` that returns exactly what you told it to.

> **Design goals**: simple, explicit and ergonomic for everyday tests or prototyping. No fixtures or external servers. Just say what a request should get back.

## Highlights
- **Two ways to add mocks**: a **clean DSL** or **single registration methods** — use whichever reads best for your use case.
- **Singleton API**: `HTTPMock.shared` is the only instance you need. No global state leaks between tests: clear with `clearQueues()`.
- **Works with real `URLSession`**: inject `HTTPMock.shared.urlSession` into the code under test. 
- **Precise matching**: host + path, plus optional **query matching** (`.exact` or `.contains`).
- **Headers support**: define headers at the host or path, with optional **cascade** to children when using the DSL.
- **FIFO responses**: queue multiple responses and they'll be served in order.
- **Passthrough networking**: configure unmocked requests to either return a hardcoded 404 or be passed through to the network.
- **File-based responses**: serve response data directly from a file on disk.

## Installation (SPM)
Add this package to your test target:

```swift
.package(url: "https://github.com/bstien/HTTPMock.git", from: "1.0.0")
```

## Quick start

### Option 1 — Imperative
```swift
import HTTPMock

// 1) Queue responses for a specific host + path
HTTPMock.shared.addResponses(
    forPath: "/user",
    host: "api.example.com",
    responses: [
        .encodable(User(id: 1, name: "Alice")), // defaults to .ok + application/json
        .empty(status: .notFound)               // the second call gets 404
    ]
)

// 2) Use the session in your code under test
let session = HTTPMock.shared.urlSession
let url = URL(string: "https://api.example.com/user")!
let (data, response) = try await session.data(from: url)
```

You can also use the imperative **builder** variant for readability:
```swift
HTTPMock.shared.addResponses(forPath: "/user", host: "api.example.com") {
    MockResponse.encodable(User(id: 1, name: "Alice"))
    MockResponse.empty(status: .notFound)
}
```

### Option 2 — Declarative DSL via result builder
```swift
HTTPMock.registerResponses {
    Host("api.example.com") {
        Path("/user") {
            MockResponse.encodable(User(id: 1, name: "Alice"))
            MockResponse.empty(status: .notFound)
        }
    }
}
```

Both approaches are equivalent — pick what suits your use case. **Responses are consumed FIFO** for each queue matching host, path and query parameters.

## Headers (with optional cascade)
```swift
HTTPMock.registerResponses {
    Host("api.example.com") {
        Headers(["X-Env": "Test"], cascade: true) // cascades to all child paths

        Path("/profile") {
            MockResponse.encodable(Profile(...)) // inherits X-Env
        }

        Path("/admin") {
            Headers(["X-Env": "AdminOnly"], cascade: false)
            MockResponse.empty(status: .unauthorized) // X-Env applies only here

            Path("/audit") {
                MockResponse.encodable(Audit(...)) // does NOT inherit AdminOnly
            }
        }
    }
}
```
- Later headers in the **same scope** override earlier ones on the same key.
- **Response headers** override inherited headers on conflict.

## Query parameters
Queries are **path-local** (not inherited). You can require exact matches or require a set of params to exist on the request.

```swift
// Exact: only these params are accepted.
Path("/search", query: ["q": "swift", "page": "1"], matching: .exact) {
    MockResponse.plaintext("ok-exact")
}

// Contains: these params must match; others are ignored
Path("/search", query: ["q": "swift"], matching: .contains) {
    MockResponse.plaintext("ok-contains-1")
    MockResponse.plaintext("ok-contains-2")
}
```

## File-based responses
Serve response data directly from a file on disk. Useful for pre-recorded and/or large responses. Either specify the `Content-Type` manually, or let it be inferred from the file.

```swift
HTTPMock.registerResponses {
    Host("api.example.com") {
        Path("/data") {
            // Point to a file in the specified `Bundle`.
            MockResponse.file(named: "response", extension: "json", in: Bundle.main)
            
            // Load the contents of a file from a `URL`.
            MockResponse.file(url: urlToFile)
        }
    }
}
```

The file path is relative to the current working directory or absolute. This allows you to serve JSON, images, or any other file content as the response body.

## Handling unmocked requests
By default, unmocked requests return a hardcoded 404 response with a small body. You can configure `HTTPMock.unmockedPolicy` to control this behavior, choosing between returning a 404 or allowing the request to pass through to the real network. The default is `notFound`, aka. the hardoced 404 response.

```swift
// Default: return a hardcoded 404 response when no mock is registered for the incoming URL.
HTTPMock.unmockedPolicy = .notFound

// Alternative: let unmocked requests hit the real network.
// This can be useful if you're doing integration testing and only want to mock certain endpoints. 
HTTPMock.unmockedPolicy = .passthrough
```

Passthrough is useful for integration-style tests where only some endpoints need mocking, but it is not recommended for strict unit tests.

## Resetting between tests
Use these in `tearDown()` or in individual tests:
```swift
// Remove all queued responses and registrations.
HTTPMock.shared.clearQueues()

// Remove all paths/responses for a host you've already registered.
HTTPMock.shared.clearQueue(forHost: "domain.com")
```

## FAQs
**Can I run tests that use `HTTPMock` in parallel?**  
No, currently only a single instance of `HTTPMock` can exist, so tests must be run sequentially.

**Can I use my own `URLSession`?**  
Yes — most tests just use `HTTPMock.shared.urlSession`. If your code constructs its own session, inject `HTTPMock.shared.urlSession` into the component under test.

**Is order guaranteed?**  
Yes, per (host, path, [query]) responses are popped in **FIFO** order.

**What happens if a request is not mocked?**  
By default, unmocked requests return a hardcoded "404 Not Found" response. You can configure `HTTPMock`'s `UnmockedPolicy` to instead pass such requests through to the real network, allowing unmocked calls to succeed.

## Example response helpers
These are available as static factory methods on `MockResponse` and can be used directly inside a `Path` or `addResponses` builder:

```swift
MockResponse.encodable(T, status: .ok, headers: [:])
MockResponse.dictionary([String: Any], status: .ok, headers: [:])
MockResponse.plaintext(String, status: .ok, headers: [:])
MockResponse.file(named: String, extension: String, in: Bundle, status: .ok, headers: [:])
MockResponse.file(URL, status: .ok, headers: [:])
MockResponse.empty(status: .ok, headers: [:])
```

For example:

```swift
Path("/user") {
    MockResponse.encodable(User(id: 1, name: "Alice"))
    MockResponse.empty(status: .notFound)
}
```

## Notes
- Intended for **tests** (unit/integration/UI previews), not production networking.
- Internally uses a custom `URLProtocol` to intercept requests and match incoming requests to a specific mocked response.
- Thread-safe queueing and matching by host + path + optional query.
- Supports passthrough networking or 404 for unmocked requests, configurable via `HTTPMock.unmockedPolicy`.

## Goals
- [X] Allow for passthrough networking when mock hasn't been registered for the incoming URL.
- [X] Let user point to a file that should be served.
- [ ] Set delay on requests.
- [ ] Let user configure a default "not found" response. Will be used either when no matching mocks are found or if queue is empty.
- [ ] Create separate instances of `HTTPMock`. The current single instance requires tests to be run in sequence, instead of parallel.
- [ ] Does arrays in query parameters work? I think they're being overwritten with the current setup.

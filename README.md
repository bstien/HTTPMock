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

## Resetting between tests
Use these in `tearDown()` or in individual tests:
```swift
// Remove everything.
HTTPMock.shared.clearQueues()

// Remove all paths/responses for a host you've already registered.
HTTPMock.shared.clearQueue(forHost: "domain.com")
```

## FAQs
**Can I run tests that use `HTTPMock` in parallell?**  
No, not with the current setup. Currently only a single instance of `HTTPMock` can exist, since it uses passes on the static `HTTPMockURLProtocol` when configuring the `URLSession`.

**Can I use my own `URLSession`?**  
Yes — most tests just use `HTTPMock.shared.urlSession`. If your code constructs its own session, inject `HTTPMock.shared.urlSession` into the component under test.

**Is order guaranteed?**  
Yes, per (host, path, [query]) responses are popped in **FIFO** order.

## Example response helpers
Available response builders include:
```swift
MockResponse.encodable(T, status: .ok, headers: [:])
MockResponse.dictionary([String: Any], status: .ok, headers: [:])
MockResponse.plaintext(String, status: .ok, headers: [:])
MockResponse.empty(status: .ok, headers: [:])
```
They set sensible defaults (e.g., `Content-Type` for JSON/plaintext) and let explicit headers override defaults.

## Notes
- Intended for **tests** (unit/integration/UI previews), not production networking.
- Internally uses a custom `URLProtocol` to intercept requests and match incoming requests to a specific mocked response.
- Thread-safe queueing and matching by host + path + optional query.

## Goals
- [ ] Set delay on requests.
- [ ] Let user point to a file that should be served.
- [ ] Let user configure a default "not found" response. Will be used either when no matching mocks are found or if queue is empty.
- [ ] Create separate instances of `HTTPMock`. The current single instance requires tests to be run in sequence, instead of paralell.
- [ ] Does arrays in query parameters work? I think they're being overwritten with the current setup
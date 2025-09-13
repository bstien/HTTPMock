<p align="center">
    <img width="1280px" src="assets/logo.png">
</p>

<p align="center">
    <!-- Unit Tests CI -->
    <a href="https://github.com/bstien/HTTPMock/actions/workflows/unit-tests.yml">
        <img src="https://github.com/bstien/HTTPMock/actions/workflows/unit-tests.yml/badge.svg" alt="Unit Tests">
    </a>
    <!-- License -->
    <a href="https://github.com/bstien/HTTPMock/blob/main/LICENSE">
        <img src="https://img.shields.io/github/license/bstien/HTTPMock.svg" alt="License">
    </a>
    <!-- SwiftPM -->
    <img src="https://img.shields.io/badge/SwiftPM-compatible-orange.svg" alt="SwiftPM Compatible">
    <!-- Swift Version -->
    <img src="https://img.shields.io/badge/Swift-6.0+-brightgreen.svg" alt="Swift 6.0+">
</p>

A tiny, test-first way to mock `URLSession` — **fast to set up, easy to read, zero test servers**. Queue responses for specific hosts/paths (and optional query params), then run your code against a regular `URLSession` that returns exactly what you told it to.

> **Design goals**: simple, explicit and ergonomic for everyday tests or prototyping. No fixtures or external servers. Just say what a request should get back.

## Highlights
- **Two ways to add mocks**: a **clean DSL** or **single registration methods** — use whichever reads best for your use case.
- **Instance or singleton**: you can either use the singleton `HTTPMock.shared` or create separate instances with `HTTPMock()`. Different instances have separate response queues.
- **Provides a real `URLSession`**: inject `HTTPMock.shared.urlSession` or your own instance's `urlSession` into the code under test.
- **Flexible matching**: exact strings, **wildcard patterns** (`*` and `**`), plus optional **query matching** (`.exact` or `.contains`).
- **Headers support**: define headers at the host or path, with optional **cascade** to children when using the DSL.
- **FIFO responses**: queue multiple responses and they'll be served in order.
- **Passthrough networking**: configure unmocked requests to either return a hardcoded 404 or be passed through to the network.
- **File-based responses**: serve response data directly from a file on disk.

## Installation (SPM)
Add this package to your test target:

```swift
.package(url: "https://github.com/bstien/HTTPMock.git", from: "0.0.4")
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
HTTPMock.shared.registerResponses {
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
HTTPMock.shared.registerResponses {
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

## Wildcard patterns
Both hosts and paths support wildcard matching using glob-style patterns. This is useful for mocking multiple similar endpoints without registering each variation individually.

### Single segment wildcards (`*`)
Match within a single segment only. Segments are separated by `.` for hosts and `/` for paths.

#### Host wildcards
```swift
HTTPMock.shared.registerResponses {
    Host("*.example.com") { // Single host pattern wildcard.
        Path("/users") {
            MockResponse.plaintext("wildcard host")
        }
    }
}
```

The host pattern (`*.example.com`) matches i.e.:
- `api.example.com`
- `staging.example.com`.

Since `*` only matches on a single segment this means the pattern will **NOT** match i.e. `api.staging.example.com`.

#### Path wildcards
```swift
HTTPMock.shared.addResponses(
    forPath: "/api/*/users", // Single path pattern wildcard.
    host: "api.example.com",
    responses: [.encodable(users)]
)
```

The path pattern (`/api/*/users`) matches i.e.:
- `/api/v1/users`
- `/api/v2/users`.

Since `*` only matches on a single segment this means the pattern will **NOT** match i.e. `/api/v1/beta/users`

### Multi-segment wildcards (`**`)
Match across multiple segments (zero or more). Useful for flexible host/path matching.

#### Multi-segment host wildcards
```swift
HTTPMock.shared.registerResponses {
    Host("**.example.com") {
        Path("/api/**/data") {
            MockResponse.plaintext("flexible matching")
        }
    }
}
```

The host pattern (`**.example.com`) matches i.e.:
- `api.example.com`
- `api.staging.example.com`.

The path pattern (`/api/**/data`) matches i.e.:
- `/api/data`
- `/api/v1/data`
- `/api/v1/beta/data`.

#### Complex patterns
```swift
HTTPMock.shared.addResponses(
    forPath: "/api/**/users/*",
    host: "api-*.example.com",
    responses: [.encodable(users)]
)
```

The combination of host and path pattern will match i.e. `api-staging.example.com/api/v1/beta/users/123`.

### Pattern specificity
When multiple patterns could match the same request, HTTPMock automatically chooses the most specific:

1. **Exact matches** always win over wildcards.
2. **Fewer wildcards** beat more wildcards.
3. **Longer literal content** wins ties.

Given the registered patterns in the code block below, the table explains which pattern(s) would match, and win, on an incoming request.

```swift
Host("api.example.com")     // exact - highest priority
Host("*.example.com")       // single wildcard
Host("**.example.com")      // multi wildcard - lowest priority
```

| Incoming request | Pattern matches | Winning pattern | Why? |
| :- | - | - | - |
| `api.example.com` | Matches on all three registered patterns | The exact pattern | It has no wildcards (lowest score). |
| `api-test.example.com` | Matches on both the single- and multi wildcard patterns | The single wildcard pattern | It has the fewest wildcards (lowest score). |
| `api.staging.example.com` | Matches only on the multi wildcard pattern | The multi wildcard pattern | The only pattern that matches. |

#### Specificity tie-breaker

Here's an example to provide more context to the specificity score when a tie between two patterns occurs. Given the registered patterns:

```swift
Host("*.example.*")         // two single wildcard
Host("**.example.com")      // multi wildcard
```

An incoming request to **`api.example.com`** would match on both of the patterns above, but the winning pattern will be the **multi wildcard pattern**. Both patterns have exactly two wildcards, but the multi wildcard pattern has a **longer matching literal** which gives it a higher score.

## File-based responses
Serve response data directly from a file on disk. Useful for pre-recorded and/or large responses. Either specify the `Content-Type` manually, or let it be inferred from the file.

```swift
HTTPMock.shared.registerResponses {
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

## Response lifetime
Each response can be configured with a `lifetime` parameter to control how many times it is served before being removed from the queue. The default value of the parameter is `.single`.

- `.single`: The response is served once, then removed from the queue. This is the default.
- `.multiple(Int)`: The response is served the specified number of times, then removed from the queue.
- `.eternal`: The response is never removed and is served indefinitely.

Example:

```swift
MockResponse.plaintext("served once", lifetime: .single)
MockResponse.plaintext("served three times", lifetime: .multiple(3))
MockResponse.plaintext("served forever", lifetime: .eternal)
```

## Response delivery
Each response can optionally be given a `delivery` parameter that controls when the response is delivered to the client. The default value of the parameter is `.instant`.

- `.instant`: The response is delivered immediately (default behavior).
- `.delayed(TimeInterval)`: The response is delayed and delivered after the specified number of seconds.

Example:

```swift
MockResponse.plaintext("immediate response", delivery: .instant)
MockResponse.plaintext("delayed response", delivery: .delayed(2.0)) // delivered after 2 seconds
```

## Handling unmocked requests
By default, unmocked requests return a hardcoded 404 response with a small body. You can configure `HTTPMock.unmockedPolicy` to control this behavior with four options:

```swift
// Default: return a hardcoded 404 response when no mock is registered for the incoming URL.
HTTPMock.shared.unmockedPolicy = .notFound

// Alternative: let unmocked requests hit the real network.
// This can be useful if you're doing integration testing and only want to mock certain endpoints.
HTTPMock.shared.unmockedPolicy = .passthrough

// Custom: provide your own MockResponse for unmocked requests
HTTPMock.shared.unmockedPolicy = .mock(.plaintext("Service temporarily unavailable", status: .other(503)))

// Fatal: trigger a fatalError for unmocked requests (strict testing mode)
HTTPMock.shared.unmockedPolicy = .fatalError
```

### Custom unmocked responses
The `.mock(MockResponse)` option allows you to define exactly what unmocked requests should return. This is useful for simulating service outages, maintenance modes, or providing consistent fallback responses during testing.

```swift
// Simple custom response
HTTPMock.shared.unmockedPolicy = .mock(.plaintext("API is down for maintenance", status: .other(503)))

// JSON error response with headers
HTTPMock.shared.unmockedPolicy = .mock(
    .dictionary(
        ["error": "endpoint_not_found", "code": 404], 
        status: .notFound, 
        headers: ["X-Error-Source": "HTTPMock"]
    )
)

// File-based fallback response
HTTPMock.shared.unmockedPolicy = .mock(.file(named: "fallback", extension: "json", in: Bundle.main))

// Delayed response to simulate slow networks
HTTPMock.shared.unmockedPolicy = .mock(.plaintext("Slow response", delivery: .delayed(2.0)))
```

**Note:** Custom unmocked responses support all `MockResponse` features (status codes, headers, delivery timing, file serving), but they don't maintain queue state like regular mocked responses. The `MockResponse` provided here will be used for all subsequent incoming unmocked requests. This means the **`lifetime` property is NOT used/honored** for these responses. Consider the `lifetime` to be `MockResponse.Lifetime.eternal`.

### Strict testing with fatalError
The `.fatalError` option provides the strictest testing mode by triggering a `fatalError()` whenever an unmocked request is encountered. This is useful for:

- **Catching missing mocks** during development.
- **Ensuring complete test coverage** of all network interactions.

```swift
// Enable strict mode - any unmocked request will crash the app
HTTPMock.shared.unmockedPolicy = .fatalError

// Use during test development to find missing mocks:
func testMyFeature() {
    HTTPMock.shared.unmockedPolicy = .fatalError
    
    // If this test makes any unmocked network requests, it will crash
    // and tell you exactly which endpoints need mocking.
    myFeature.performNetworkOperations()
}
```

**Warning:** Only use `.fatalError` during development and testing. It will crash your app on unmocked requests.

Passthrough is useful for integration-style tests where only some endpoints need mocking, but it is not recommended for strict unit tests.

### Custom passthrough sessions
When using `.passthrough` policy you can provide a custom `URLSession` for handling unmocked requests. This allows you to configure timeouts, caching policies, and other networking behavior for passthrough requests.

**Note:** By using `.passthrough` any unmocked requests will be sent to actual network. If this isn't your intention: either set `unmockedPolicy` to another value or configure and pass your own `URLSession` when instantiating HTTPMock.

```swift
// Create a custom configuration for passthrough requests
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 10.0
config.timeoutIntervalForResource = 30.0
let passthroughSession = URLSession(configuration: config)

// Use it when creating HTTPMock instance
let httpMock = HTTPMock(passthroughSession: passthroughSession)
httpMock.unmockedPolicy = .passthrough

// Unmocked requests will now use your custom session configuration
```

If you don't provide a custom passthrough session, HTTPMock uses a default ephemeral session. Each HTTPMock instance maintains its own isolated passthrough session, so multiple instances can have different passthrough configurations.

## Resetting between tests
Use these in `tearDown()` or in individual tests:
```swift
// Remove all queued responses and registrations.
HTTPMock.shared.clearQueues()

// Remove all paths/responses for a host you've already registered.
HTTPMock.shared.clearQueue(forHost: "domain.com")
```

## Singleton vs. separate instances
You can use the global singleton `HTTPMock.shared` for simplicity in most cases. However, if you need isolated queues to, for example, run parallel tests or maintain different mock configurations you can create separate instances with `HTTPMock()`.

Each instance maintains their own queue and properties, and they have no connection to each other.

Example:

```swift
// Using the singleton
HTTPMock.shared.registerResponses {
    Host("api.example.com") {
        Path("/user") {
            MockResponse.plaintext("Hello from singleton!")
        }
    }
}
let singletonSession = HTTPMock.shared.urlSession

// Using a separate instance.
let mockInstance = HTTPMock()
mockInstance.registerResponses {
    Host("api.example.com") {
        Path("/user") {
            MockResponse.plaintext("Hello from instance!")
        }
    }
}
let instanceSession = mockInstance.urlSession
```


## FAQs
**Can I run tests that use `HTTPMock` in parallel?**  
Yes. You can create multiple independent `HTTPMock` instances, which allows for parallel tests or separate mock configurations. If you don't need separate instances you can use the singleton `HTTPMock.shared`.

Be aware that the singleton will exist for the whole duration of the app or tests, so call `HTTPMock.shared.clearQueues()` if you need to reset it.

**Can I use my own `URLSession`?**  
Yes. Most tests just use `HTTPMock.shared.urlSession`. If your code constructs its own session, inject `HTTPMock.shared.urlSession` or your own instance's `urlSession` into the component under test.

**Is order guaranteed?**  
Yes. Responses per (host, path, [query]) are queued and popped in **FIFO** order.

**What happens if a request is not mocked?**  
By default, unmocked requests return a hardcoded "404 Not Found" response. You can configure `HTTPMock`'s `UnmockedPolicy` to instead pass such requests through to the real network, allowing unmocked calls to succeed.

**Can I mix exact and wildcard patterns for the same endpoint?**  
Yes. You can register multiple patterns that could match the same request. HTTPMock will automatically choose the most specific pattern using a score ranking (exact beats wildcards, fewer wildcards beat more wildcards).

**What characters are supported in wildcard patterns?**  
Use `*` for single-segment wildcards and `**` for multi-segment wildcards. All other characters are treated as literals. Special regex characters are automatically escaped, so patterns like `api-*.example.com` work as expected.

**Can I customize what happens when no mock is found?**  
Yes. Use `HTTPMock.unmockedPolicy` to choose between `.notFound` (hardcoded 404), `.passthrough` (real network), `.mock(MockResponse)` (your custom response), or `.fatalError` (crash on unmocked requests). The custom option supports all `MockResponse` features, while `.fatalError` is useful for strict testing to catch missing mocks.

**Can I customize the URLSession used for passthrough requests?**  
Yes. When creating an `HTTPMock` instance, you can provide a custom `passthroughSession` parameter with your own `URLSession` configuration. This allows you to control timeouts, caching policies, and other networking behavior for unmocked requests when using `.passthrough` policy. Each HTTPMock instance maintains its own isolated passthrough session.

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
- [X] Set delay on requests.
- [X] Create separate instances of `HTTPMock`. The current single instance requires tests to be run in sequence, instead of parallel.
- [X] Support wildcard patterns in host and path matching (`*` and `**` glob-style patterns).
- [X] Let user configure a default "not found" response. Will be used either when no matching mocks are found or if queue is empty.
- [ ] Does arrays in query parameters work? I think they're being overwritten with the current setup.

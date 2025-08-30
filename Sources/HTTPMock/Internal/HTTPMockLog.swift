import os

public enum HTTPMockLog {
    public static var logger = Logger(subsystem: "httpmock", category: "HTTPMock")
    public static var isEnabled = true
    public static var level: Level = .info

    public static func error(_ message: String) {
        if should(.error) {
            logger.error("[HTTPMock] \(message, privacy: .public)")
        }
    }

    public static func warning(_ message: String) {
        if should(.warning) {
            logger.warning("[HTTPMock] \(message, privacy: .public)")
        }
    }

    public static func info(_ message: String) {
        if should(.info) {
            logger.info("[HTTPMock] \(message, privacy: .public)")
        }
    }

    public static func debug(_ message: String) {
        if should(.debug) {
            logger.debug("[HTTPMock] \(message, privacy: .public)")
        }
    }

    public static func trace(_ message: String) {
        if should(.trace) {
            logger.log("[HTTPMock] \(message, privacy: .public)")
        }
    }

    // MARK: - Private methods

    @inline(__always)
    private static func should(_ l: Level) -> Bool {
        isEnabled && l.rawValue <= level.rawValue
    }
}

extension HTTPMockLog {
    public enum Level: Int {
        case error = 0
        case warning
        case info
        case debug
        case trace
    }
}

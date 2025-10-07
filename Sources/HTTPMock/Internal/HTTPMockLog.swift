import Foundation
import os

public enum HTTPMockLog {
    public static var logger = Logger(subsystem: "httpmock", category: "HTTPMock")
    public static var isEnabled = true
    public static var level: Level = .trace

    public static func error(_ message: @autoclosure () -> String) {
        let level = Level.error
        if shouldLog(level) {
            let message = message()
            logger.error("[HTTPMock][\(level.description)] \(message, privacy: .public)")
            printToConsole("⛔️ \(message)", level: level)
        }
    }

    public static func warning(_ message: @autoclosure () -> String) {
        let level = Level.warning
        if shouldLog(level) {
            let message = message()
            logger.warning("[HTTPMock][\(level.description)] \(message, privacy: .public)")
            printToConsole("⚠️ \(message)", level: level)
        }
    }

    public static func info(_ message: @autoclosure () -> String) {
        let level = Level.info
        if shouldLog(level) {
            let message = message()
            logger.info("[HTTPMock][\(level.description)] \(message, privacy: .public)")
            printToConsole(message, level: level)
        }
    }

    public static func debug(_ message: @autoclosure () -> String) {
        let level = Level.debug
        if shouldLog(level) {
            let message = message()
            logger.debug("[HTTPMock][\(level.description)] \(message, privacy: .public)")
            printToConsole(message, level: level)
        }
    }

    public static func trace(_ message: @autoclosure () -> String) {
        let level = Level.trace
        if shouldLog(level) {
            let message = message()
            logger.log("[HTTPMock][\(level.description)] \(message, privacy: .public)")
            printToConsole(message, level: level)
        }
    }

    // MARK: - Private methods

    @inline(__always)
    private static func shouldLog(_ l: Level) -> Bool {
        isEnabled && l.rawValue <= level.rawValue
    }

    @inline(__always)
    private static var isXcodePreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static func printToConsole(_ message: String, level: Level) {
        #if DEBUG
        Swift.print("[HTTPMock][\(level.description)] \(message)")
        #else
        if isXcodePreview {
            Swift.print("[HTTPMock][\(level.description)] \(message)")
        }
        #endif
    }
}

extension HTTPMockLog {
    public enum Level: Int {
        case error = 0
        case warning
        case info
        case debug
        case trace

        var description: String {
            switch self {
            case .error: "ERROR"
            case .warning: "WARNING"
            case .info: "INFO"
            case .debug: "DEBUG"
            case .trace: "TRACE"
            }
        }
    }
}

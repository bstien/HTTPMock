import Foundation
import os

public enum HTTPMockLog {
    public static var logger = Logger(subsystem: "httpmock", category: "HTTPMock")
    public static var isEnabled = true
    public static var level: Level = .trace

    public static func error(_ message: @autoclosure () -> String) {
        if should(.error) {
            let message = message()
            logger.error("[HTTPMock][\(level.description)] \(message, privacy: .public)")
            printToConsole("⛔️ \(message)", level: .error)
        }
    }

    public static func warning(_ message: @autoclosure () -> String) {
        if should(.warning) {
            let message = message()
            logger.warning("[HTTPMock][\(level.description)] \(message, privacy: .public)")
            printToConsole("⚠️ \(message)", level: .warning)
        }
    }

    public static func info(_ message: @autoclosure () -> String) {
        if should(.info) {
            let message = message()
            logger.info("[HTTPMock][\(level.description)] \(message, privacy: .public)")
            printToConsole(message, level: .info)
        }
    }

    public static func debug(_ message: @autoclosure () -> String) {
        if should(.debug) {
            let message = message()
            logger.debug("[HTTPMock][\(level.description)] \(message, privacy: .public)")
            printToConsole(message, level: .debug)
        }
    }

    public static func trace(_ message: @autoclosure () -> String) {
        if should(.trace) {
            let message = message()
            logger.log("[HTTPMock][\(level.description)] \(message, privacy: .public)")
            printToConsole(message, level: .trace)
        }
    }

    // MARK: - Private methods

    @inline(__always)
    private static func should(_ l: Level) -> Bool {
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

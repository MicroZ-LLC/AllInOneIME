import Foundation
#if canImport(os)
import os
#endif

/// The core's log: `os.Logger` on Apple platforms (Console, `log stream`), standard error elsewhere. Messages
/// are logged whole and public: the core logs names and statuses, never keys or what was typed.
public struct CoreLog: Sendable {
    #if canImport(os)
    private let logger: Logger
    #else
    private let label: String
    #endif

    public init(subsystem: String, category: String) {
        #if canImport(os)
        logger = Logger(subsystem: subsystem, category: category)
        #else
        label = "\(subsystem) [\(category)]"
        #endif
    }

    public func debug(_ message: String) {
        #if canImport(os)
        logger.debug("\(message, privacy: .public)")
        #else
        write("debug", message)
        #endif
    }

    public func info(_ message: String) {
        #if canImport(os)
        logger.info("\(message, privacy: .public)")
        #else
        write("info", message)
        #endif
    }

    public func notice(_ message: String) {
        #if canImport(os)
        logger.notice("\(message, privacy: .public)")
        #else
        write("notice", message)
        #endif
    }

    public func error(_ message: String) {
        #if canImport(os)
        logger.error("\(message, privacy: .public)")
        #else
        write("error", message)
        #endif
    }

    #if !canImport(os)
    private func write(_ level: String, _ message: String) {
        FileHandle.standardError.write(Data("\(label) \(level): \(message)\n".utf8))
    }
    #endif
}

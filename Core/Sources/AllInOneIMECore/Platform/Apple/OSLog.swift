#if canImport(Darwin)  // not canImport(os): the Linux tests' shim of os (Tests/LinuxShims) would count
import Foundation
import os

extension CoreLog {
    /// `os.Logger`.
    static func writer(subsystem: String, category: String) -> @Sendable (Level, String) -> Void {
        let logger = Logger(subsystem: subsystem, category: category)
        return { level, message in
            switch level {
            case .debug: logger.debug("\(message, privacy: .public)")
            case .info: logger.info("\(message, privacy: .public)")
            case .notice: logger.notice("\(message, privacy: .public)")
            case .error: logger.error("\(message, privacy: .public)")
            }
        }
    }
}
#endif

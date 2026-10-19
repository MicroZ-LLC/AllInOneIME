import Foundation
#if os(Windows)
import WinSDK
#endif

/// The core's log: `os.Logger` on Apple platforms (Console, `log stream`; `Platform/Apple/OSLog.swift`), standard error
/// elsewhere. Messages are logged whole and public: the core logs names and statuses, never keys or what was typed.
public struct CoreLog: Sendable {
    enum Level: String, Sendable {
        case debug, info, notice, error
    }

    private let write: @Sendable (Level, String) -> Void

    public init(subsystem: String, category: String) {
        write = Self.writer(subsystem: subsystem, category: category)
    }

    public func debug(_ message: String) { write(.debug, message) }
    public func info(_ message: String) { write(.info, message) }
    public func notice(_ message: String) { write(.notice, message) }
    public func error(_ message: String) { write(.error, message) }

    #if !canImport(Darwin)  // as OSLog.swift: not canImport(os), which the Linux tests' shim of os answers
    static func writer(subsystem: String, category: String) -> @Sendable (Level, String) -> Void {
        let label = "\(subsystem) [\(category)]"
        return { level, message in write("\(label) \(level.rawValue): \(message)\n") }
    }

    /// To standard error, if there is one. On Windows a program without a console has none (the engine, a GUI program
    /// started at logon or by the text service or the Settings app), and `FileHandle.standardError` traps on a write to
    /// a missing one: written with WriteFile there, or not at all.
    static func write(_ line: String) {
        #if os(Windows)
        guard let handle = GetStdHandle(STD_ERROR_HANDLE), handle != INVALID_HANDLE_VALUE else { return }
        var bytes = Array(line.utf8)
        var written: DWORD = 0
        _ = WriteFile(handle, &bytes, DWORD(bytes.count), &written, nil)
        #else
        FileHandle.standardError.write(Data(line.utf8))
        #endif
    }
    #endif
}

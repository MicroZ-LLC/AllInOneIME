import Foundation

/// The core's log: `os.Logger` on Apple platforms (Console, `log stream`; `Platform/Apple/OSLog.swift`), standard error
/// elsewhere. Messages are logged whole and public: the core logs names and statuses, never keys or what was typed.
public struct CoreLog: Sendable {
    enum Level: String, Sendable {
        case debug, info, notice, error
    }

    private let write: @Sendable (Level, String) -> Void

    public init(subsystem: String, category: String) {
        let written = Self.writer(subsystem: subsystem, category: category)
        write = { level, message in
            written(level, message)
            Self.heard(message)
        }
    }

    /// Hears every message logged from now on, as written, until the returned closure is called: the tests', that no
    /// key, token or text typed is ever in one.
    static func listen(_ listener: @escaping @Sendable (String) -> Void) -> @Sendable () -> Void {
        let id = UUID()
        listeners.withLock { $0[id] = listener }
        return { listeners.withLock { $0[id] = nil } }
    }

    private static let listeners = Locked<[UUID: @Sendable (String) -> Void]>(initialState: [:])

    private static func heard(_ message: String) {
        let listening = listeners.withLock { $0.isEmpty ? [] : Array($0.values) }
        for listener in listening { listener(message) }
    }

    public func debug(_ message: String) { write(.debug, message) }
    public func info(_ message: String) { write(.info, message) }
    public func notice(_ message: String) { write(.notice, message) }
    public func error(_ message: String) { write(.error, message) }

    #if !canImport(Darwin)  // as OSLog.swift: not canImport(os), which the Linux tests' shim of os answers
    static func writer(subsystem: String, category: String) -> @Sendable (Level, String) -> Void {
        let label = "\(subsystem) [\(category)]"
        return { level, message in FileHandle.standardError.write(Data("\(label) \(level.rawValue): \(message)\n".utf8)) }
    }
    #endif
}

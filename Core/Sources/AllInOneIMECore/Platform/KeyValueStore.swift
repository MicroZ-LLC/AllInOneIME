import Foundation

/// Small values a shell keeps between launches, by key, like `UserDefaults`: which command was used when, what a panel
/// remembers. Not for secrets (`SecretStore`) nor files (the config, notes). `UserDefaults` on Apple platforms
/// (`UserDefaultsStore`, Platform/Apple/); elsewhere, until the shell installs its own (Windows: the registry or a file
/// in %APPDATA%), only memory (`MemoryKeyValueStore`).
public protocol KeyValueStore: Sendable {
    func data(forKey key: String) -> Data?
    func string(forKey key: String) -> String?
    /// False when there's none, as `UserDefaults.bool(forKey:)`.
    func bool(forKey key: String) -> Bool
    func set(_ data: Data, forKey key: String)
    func set(_ string: String, forKey key: String)
    func set(_ bool: Bool, forKey key: String)
    func removeValue(forKey key: String)
}

/// Values kept in memory only, for as long as the process runs: the neutral stand-in, and the tests'. A value read as
/// another type reads as `UserDefaults` reads it: a Boolean as the string "1" or "0", a string as true when it is
/// "true" or "yes" (in any case) or "1", data as no string and no Boolean, and no string as data.
public final class MemoryKeyValueStore: KeyValueStore {
    private enum Value {
        case data(Data), string(String), bool(Bool)
    }

    private let values = Locked(initialState: [String: Value]())

    public init() {}

    public func data(forKey key: String) -> Data? {
        if case let .data(data)? = values.withLock({ $0[key] }) { return data }
        return nil
    }

    public func string(forKey key: String) -> String? {
        switch values.withLock({ $0[key] }) {
        case let .string(string)?: return string
        case let .bool(bool)?: return bool ? "1" : "0"
        case .data?, nil: return nil
        }
    }

    public func bool(forKey key: String) -> Bool {
        switch values.withLock({ $0[key] }) {
        case let .bool(bool)?: return bool
        case let .string(string)?: return ["true", "yes"].contains(string.lowercased()) || string == "1"
        case .data?, nil: return false
        }
    }

    public func set(_ data: Data, forKey key: String) { values.withLock { $0[key] = .data(data) } }
    public func set(_ string: String, forKey key: String) { values.withLock { $0[key] = .string(string) } }
    public func set(_ bool: Bool, forKey key: String) { values.withLock { $0[key] = .bool(bool) } }
    public func removeValue(forKey key: String) { _ = values.withLock { $0.removeValue(forKey: key) } }
}

#if canImport(Darwin)
import Foundation

/// `UserDefaults`: the standard one (the app's domain), or a suite's.
public struct UserDefaultsStore: KeyValueStore, @unchecked Sendable {  // UserDefaults is thread-safe
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The suite named `suiteName`; nil when UserDefaults refuses the name (the app's own bundle ID, the global domain).
    public init?(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    public func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    public func set(_ data: Data, forKey key: String) { defaults.set(data, forKey: key) }
    public func set(_ string: String, forKey key: String) { defaults.set(string, forKey: key) }
    public func set(_ bool: Bool, forKey key: String) { defaults.set(bool, forKey: key) }
    public func removeValue(forKey key: String) { defaults.removeObject(forKey: key) }
}
#endif

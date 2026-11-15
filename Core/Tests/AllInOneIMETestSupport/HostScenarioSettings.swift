import Foundation
import AllInOneIMECore

/// The settings a host scenario (Core/Tests/HostScenarios) runs with, shared by the core's runner (AllInOneIMEHostTests)
/// and the Mac's replayer (AllInOneIMEMacTests/HostScenarios), so a scenario means the same in both: Chinese and English
/// typed, the field's starting language first, the interface in English; autocomplete on with the on-device model, which
/// suggests nothing (`SilentModel`): it runs and keeps what was typed (`EXPECT context`, `EXPECT fallback`), and nothing
/// leaves the process. A scenario's `SET <configKey> <value>` lines change it from there (`applying`).
public enum HostScenarioSettings {
    /// The config a scenario starting in `language` runs with, its `SET` lines applied in order.
    public static func config(startingIn language: Language, set settings: [(key: String, value: String)] = []) throws -> Config {
        var config = Config.default
        config.uiLanguage = "en"
        config.inputLanguages = [.chinese, .english]
        config.defaultInput = language
        config.autocomplete = true
        config.provider = .apple
        for (key, value) in settings { config = try applying(key, value, to: config) }
        return config
    }

    /// `config` with its key `key` (the config file's name for it, `Config.allKeys`) set to `written`: JSON where it reads
    /// as JSON (`true`, `3`, `["en"]`), else a string (`capsLock`). Refused where the config doesn't take the value as
    /// written (a choice it doesn't have: it would read its default in its place).
    public static func applying(_ key: String, _ written: String, to config: Config) throws -> Config {
        guard Config.allKeys.contains(key) else {
            throw HostSettingError("no config key \(key)")
        }
        let value = (try? JSONSerialization.jsonObject(with: Data(written.utf8), options: .fragmentsAllowed)) ?? written
        guard var file = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any] else {
            throw HostSettingError("the config doesn't encode as an object")
        }
        file[key] = value
        let changed = try JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: file))
        guard took(key, value, written, in: changed) else { throw HostSettingError("\(key) doesn't take \(written)") }
        return changed
    }

    /// The config holds `value` for `key`: written back as it was set, or left out of the file as the default it is.
    private static func took(_ key: String, _ value: Any, _ written: String, in config: Config) -> Bool {
        guard let file = (try? JSONEncoder().encode(config)).flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any]
        else { return false }
        if let stored = file[key] { return (stored as AnyObject).isEqual(value) }
        // Left out: the default. Its value as the config holds it (a choice's name, a number, a switch).
        guard let held = Mirror(reflecting: config).children.first(where: { $0.label == key })?.value else { return false }
        let name = (held as? any RawRepresentable).map { "\($0.rawValue)" } ?? "\(held)"
        return name == written
    }

    /// The on-device model as a scenario has it: there, and with nothing to suggest (autocomplete runs, shows nothing, says
    /// nothing); nothing leaves the process.
    public struct SilentModel: AppleModelBackend {
        public init() {}

        public var availability: AppleModelAvailability { .available }
        public var contextSize: Int { 4096 }
        public var supportedLanguages: Set<String> { ["en", "zh"] }

        public func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }
}

/// A `SET` line the config doesn't take, and why.
public struct HostSettingError: Error, CustomStringConvertible, Equatable {
    public var description: String

    public init(_ description: String) { self.description = description }
}

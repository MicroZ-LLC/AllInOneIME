import Foundation

/// Settings for one app, by its bundle id (`Config.appProfiles`, e.g. "com.tinyspeck.slackmacgap"): each is optional,
/// and where it's unset the app follows the setting for every app.
public struct AppProfile: Codable, Equatable, Sendable {
    /// The input language a text field of the app starts in (else `Config.defaultInput`; one that isn't among the
    /// input languages, or whose pack isn't there, is passed over too).
    public var inputLanguage: Language?
    /// The rewrite styles @improve offers in the app (else `Config.rewriteStyles`), names from `RewriteStyle.catalog`;
    /// empty: the main versions only.
    public var rewriteStyles: [String]?
    /// Results typed out character by character in the app, or not (else `Config.typeOut`).
    public var typeOut: Bool?
    /// No AI in the app: the commands that send its text to a model (`Command.usesAI`) refuse with a notice;
    /// typing and the other commands work as anywhere.
    public var noAI: Bool?

    public init(inputLanguage: Language? = nil, rewriteStyles: [String]? = nil, typeOut: Bool? = nil, noAI: Bool? = nil) {
        self.inputLanguage = inputLanguage
        self.rewriteStyles = rewriteStyles
        self.typeOut = typeOut
        self.noAI = noAI
    }

    /// Sets nothing: the app follows every setting.
    public var isEmpty: Bool { inputLanguage == nil && rewriteStyles == nil && typeOut == nil && noAI != true }

    private enum CodingKeys: String, CodingKey {
        case inputLanguage, rewriteStyles, typeOut, noAI
    }

    /// Each key on its own: one of the wrong type, or a language code this version doesn't know, is left unset;
    /// other keys are ignored.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputLanguage = (try? c.decodeIfPresent(String.self, forKey: .inputLanguage)).flatMap { $0 }.flatMap(Language.init(rawValue:))
        rewriteStyles = (try? c.decodeIfPresent([String].self, forKey: .rewriteStyles)).flatMap { $0 }
        typeOut = (try? c.decodeIfPresent(Bool.self, forKey: .typeOut)).flatMap { $0 }
        noAI = (try? c.decodeIfPresent(Bool.self, forKey: .noAI)).flatMap { $0 }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(inputLanguage, forKey: .inputLanguage)
        try c.encodeIfPresent(rewriteStyles, forKey: .rewriteStyles)
        try c.encodeIfPresent(typeOut, forKey: .typeOut)
        try c.encodeIfPresent(noAI, forKey: .noAI)
    }

    /// `Config.appProfiles` from a config file: an entry that isn't an object, or whose key is no bundle id (empty, or
    /// with spaces), is left out; a value that isn't an object at all reads as none.
    static func decodeAll<Key: CodingKey>(_ c: KeyedDecodingContainer<Key>, forKey key: Key) -> [String: AppProfile] {
        guard let entries = (try? c.decodeIfPresent([String: Lenient].self, forKey: key)).flatMap({ $0 }) else { return [:] }
        var profiles: [String: AppProfile] = [:]
        for (app, entry) in entries {
            guard let profile = entry.profile, isBundleID(app) else { continue }
            profiles[app] = profile
        }
        return profiles
    }

    /// Whether `id` can be an app's bundle id ("com.apple.mail"): not empty, no spaces or line breaks.
    public static func isBundleID(_ id: String) -> Bool {
        !id.isEmpty && !id.contains(where: { $0.isWhitespace || $0.isNewline })
    }

    /// A profile, or nil for an entry that isn't one (never an error).
    private struct Lenient: Decodable {
        let profile: AppProfile?
        init(from decoder: Decoder) throws { profile = try? AppProfile(from: decoder) }
    }

    /// Why an AI request wasn't sent (`Converter`, a request that got past the composer's check).
    public enum Refusal: Error, LocalizedError, Equatable {
        case noAI

        public var errorDescription: String? { "AI is off in this app (per-app settings)" }
    }
}

extension Config {
    /// The profile of `app` (a bundle id), if it has one.
    public func profile(for app: String?) -> AppProfile? {
        guard let app, !app.isEmpty else { return nil }
        return appProfiles[app]
    }

    /// These settings as they apply in `app`: its rewrite styles and typing out where its profile sets them, the
    /// others as they are. Without a profile, exactly these settings.
    public func applying(app: String?) -> Config {
        guard let profile = profile(for: app) else { return self }
        var config = self
        if let styles = profile.rewriteStyles { config.rewriteStyles = styles }
        if let typeOut = profile.typeOut { config.typeOut = typeOut }
        return config
    }

    /// The input language a new text field of `app` starts in, among `usable` (the input languages that can be typed
    /// now, in order): the app's own, else the default one, else the first.
    public func startingInput(in app: String?, among usable: [Language]) -> Language {
        if let own = profile(for: app)?.inputLanguage, usable.contains(own) { return own }
        return usable.contains(defaultInput) ? defaultInput : usable.first ?? defaultInput
    }

    /// Whether AI commands may run in `app` (its profile doesn't say "no AI").
    public func allowsAI(in app: String?) -> Bool { profile(for: app)?.noAI != true }
}

extension Command {
    /// Sends its text to a model: @improve, @translate, @question, a custom prompt command, editing a selection, and
    /// @claude (Claude Code). Refused in an app with no AI (`AppProfile.noAI`); the others (@open, @note, a program,
    /// a script, a link …) work.
    public var usesAI: Bool { kind == .convert || kind == .generate || self == .claude }
}

import Foundation

/// Settings for one app, by its bundle id (`Config.appProfiles`, e.g. "com.tinyspeck.slackmacgap"): each is optional,
/// and where it's unset the app follows the setting for every app.
public struct AppProfile: Codable, Equatable, Sendable {
    /// The input a text field of the app starts in: an input language, or Code (else `Config.defaultInput`; one that
    /// isn't among the inputs, or whose pack isn't there, is passed over too). Written as `inputLanguage`, Code as "code".
    public var startingInput: Input?
    /// The input language a text field of the app starts in, where that's one (`startingInput`); set, the app starts in
    /// it (nil: as everywhere).
    public var inputLanguage: Language? {
        get { startingInput?.language }
        set { startingInput = newValue.map(Input.language) }
    }
    /// The rewrite styles @improve offers in the app (else `Config.rewriteStyles`), names from `RewriteStyle.catalog`;
    /// empty: the main versions only.
    public var rewriteStyles: [String]?
    /// Results typed out character by character in the app, or not (else `Config.typeOut`).
    public var typeOut: Bool?
    /// No AI in the app: the commands that send its text to a model (`Command.usesAI`) refuse with a notice;
    /// typing and the other commands work as anywhere.
    public var noAI: Bool?
    /// Translate as You Type (`TranslateMode`) whenever the app is typed in: switching to it turns the mode on, and
    /// doesn't leave it (Settings → Apps: 「总是边打边译」).
    public var translateAlways: Bool?
    /// Autocomplete (`Autocomplete`) in the app always (true) or never (false), whatever the switch and what was
    /// learned there (Settings → Apps: 「续写」); nil: as everywhere. This Mac's own, as the switch is: never synced
    /// (`ICloudSync.thisMacsOwnAppFields`).
    public var autocomplete: Bool?
    /// Suggestions (plugin completions, Code's rows) in the app (Settings → Apps: 「建议」): off (false), or as
    /// everywhere (nil, or true). This Mac's own, as the switch is: never synced (`ICloudSync.thisMacsOwnAppFields`).
    public var suggestions: Bool?
    /// What a suggestion row inserts in the app (Settings → Apps: 「插入」, decision 28): the source's own, ID only, with
    /// title, with title and link; nil: as everywhere (`Config.suggestionsInsert`). Synced as the app's other fields are
    /// (what goes in there is the same on every Mac), unlike its Suggestions switch.
    public var suggestionsInsert: SuggestionsInsert?

    public init(inputLanguage: Language? = nil, rewriteStyles: [String]? = nil, typeOut: Bool? = nil, noAI: Bool? = nil,
                translateAlways: Bool? = nil, autocomplete: Bool? = nil, suggestions: Bool? = nil,
                suggestionsInsert: SuggestionsInsert? = nil) {
        self.startingInput = inputLanguage.map(Input.language)
        self.rewriteStyles = rewriteStyles
        self.typeOut = typeOut
        self.noAI = noAI
        self.translateAlways = translateAlways
        self.autocomplete = autocomplete
        self.suggestions = suggestions
        self.suggestionsInsert = suggestionsInsert
    }

    /// Sets nothing: the app follows every setting.
    public var isEmpty: Bool {
        startingInput == nil && rewriteStyles == nil && typeOut == nil && noAI != true && translateAlways != true && autocomplete == nil
            && suggestions == nil && suggestionsInsert == nil
    }

    private enum CodingKeys: String, CodingKey {
        case inputLanguage, rewriteStyles, typeOut, noAI, translateAlways, autocomplete, suggestions, suggestionsInsert
    }

    /// Each key on its own: one of the wrong type, or an input (or a choice of what a row inserts) this version doesn't
    /// know, is left unset; other keys are ignored.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startingInput = (try? c.decodeIfPresent(String.self, forKey: .inputLanguage)).flatMap { $0 }.flatMap(Input.init(rawValue:))
        rewriteStyles = (try? c.decodeIfPresent([String].self, forKey: .rewriteStyles)).flatMap { $0 }
        typeOut = (try? c.decodeIfPresent(Bool.self, forKey: .typeOut)).flatMap { $0 }
        noAI = (try? c.decodeIfPresent(Bool.self, forKey: .noAI)).flatMap { $0 }
        translateAlways = (try? c.decodeIfPresent(Bool.self, forKey: .translateAlways)).flatMap { $0 }
        autocomplete = (try? c.decodeIfPresent(Bool.self, forKey: .autocomplete)).flatMap { $0 }
        suggestions = (try? c.decodeIfPresent(Bool.self, forKey: .suggestions)).flatMap { $0 }
        suggestionsInsert = (try? c.decodeIfPresent(String.self, forKey: .suggestionsInsert)).flatMap { $0 }.flatMap(SuggestionsInsert.init(rawValue:))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(startingInput?.rawValue, forKey: .inputLanguage)
        try c.encodeIfPresent(rewriteStyles, forKey: .rewriteStyles)
        try c.encodeIfPresent(typeOut, forKey: .typeOut)
        try c.encodeIfPresent(noAI, forKey: .noAI)
        try c.encodeIfPresent(translateAlways, forKey: .translateAlways)
        try c.encodeIfPresent(autocomplete, forKey: .autocomplete)
        try c.encodeIfPresent(suggestions, forKey: .suggestions)
        try c.encodeIfPresent(suggestionsInsert?.rawValue, forKey: .suggestionsInsert)
    }

    /// `Config.appProfiles` from a config file: an entry that isn't an object, or whose key is no bundle id (empty, or
    /// with spaces), is left out; a value that isn't an object at all reads as none. Bundle ids are matched ignoring
    /// case (`Config.profile(for:)`): of keys that differ only in case, one is kept, the others left out: one that sets
    /// something over one that doesn't (an empty one would be dropped on the next save), and among those the first in
    /// sorted order (always the same one, "com.apple.Mail" before "com.apple.mail").
    static func decodeAll<Key: CodingKey>(_ c: KeyedDecodingContainer<Key>, forKey key: Key) -> [String: AppProfile] {
        guard let entries = (try? c.decodeIfPresent([String: Lenient].self, forKey: key)).flatMap({ $0 }) else { return [:] }
        var profiles: [String: AppProfile] = [:]
        for (app, entry) in entries {
            guard let profile = entry.profile, isBundleID(app) else { continue }
            profiles[app] = profile
        }
        // The spellings of each id together, in one pass; one kept of each (a file of thousands reads at once).
        let spellings = Dictionary(grouping: profiles.keys, by: { $0.lowercased() })
        let kept = Set(spellings.values.compactMap { winner(of: $0, in: profiles) })
        return profiles.filter { kept.contains($0.key) }
    }

    /// Of the keys of `profiles` that are `app` ignoring case, the one that counts (`winner`), whatever the spelling
    /// asked for. Only those keys are sorted.
    static func preferredKey(for app: String, in profiles: [String: AppProfile]) -> String? {
        winner(of: profiles.keys.filter { $0.caseInsensitiveCompare(app) == .orderedSame }, in: profiles)
    }

    /// Of `keys`, spellings of one id: one that sets something before one that doesn't, and among those the first in
    /// sorted order (always the same one).
    private static func winner(of keys: [String], in profiles: [String: AppProfile]) -> String? {
        let sorted = keys.sorted()
        return sorted.first { profiles[$0]?.isEmpty == false } ?? sorted.first
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
    /// The profile of `app` (a bundle id), if it has one, its id matched ignoring case ("com.apple.Mail" written by hand
    /// is Mail's "com.apple.mail").
    public func profile(for app: String?) -> AppProfile? {
        profileKey(for: app).flatMap { appProfiles[$0] }
    }

    /// The key of `appProfiles` that holds the profile of `app`, by the rule a config file is read with when two differ
    /// only in case (`AppProfile.preferredKey`): one that sets something, else the first in sorted order.
    public func profileKey(for app: String?) -> String? {
        guard let app, !app.isEmpty else { return nil }
        return AppProfile.preferredKey(for: app, in: appProfiles)
    }

    /// Changes the profile of `app` (a new one if it has none) where it is, under the key it already has in whatever
    /// case: never a second key for the same app (any other spelling of it goes). `dropsEmpty`: one left setting
    /// nothing is removed.
    public mutating func changeProfile(for app: String, dropsEmpty: Bool = false, _ change: (inout AppProfile) -> Void) {
        let key = profileKey(for: app) ?? app
        var profile = appProfiles[key] ?? AppProfile()
        change(&profile)
        removeProfile(for: app)
        if !(dropsEmpty && profile.isEmpty) { appProfiles[key] = profile }
    }

    /// Removes the profile of `app`, in every spelling of its id.
    public mutating func removeProfile(for app: String) {
        for key in appProfiles.keys where key.caseInsensitiveCompare(app) == .orderedSame { appProfiles[key] = nil }
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

    /// The input a new text field of `app` starts in: Code where the app's own is Code and Code can be typed now
    /// (`code`: it is among the inputs, its pack installed), else a language as `startingInput(in:among:)` has it.
    public func startingInput(in app: String?, among usable: [Language], code: Bool) -> Input {
        if code, profile(for: app)?.startingInput == .code { return .code }
        return .language(startingInput(in: app, among: usable))
    }

    /// Whether AI commands may run in `app` (its profile doesn't say "no AI").
    public func allowsAI(in app: String?) -> Bool { profile(for: app)?.noAI != true }
}

extension Command {
    /// Sends its text to a model: @improve, @translate, @question, a custom prompt command, editing a selection, and
    /// @agent (a coding agent). Refused in an app with no AI (`AppProfile.noAI`); the others (@open, @note, a program,
    /// a script, a link …) work.
    public var usesAI: Bool { kind == .convert || kind == .generate || self == .agent }
}

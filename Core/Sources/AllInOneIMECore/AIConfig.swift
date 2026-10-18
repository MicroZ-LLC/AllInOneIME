import Foundation

/// Settings → Assistant's "Change settings in a sentence": settings changed by describing them ("output languages English
/// and French", "微信里用中文").
/// One AI request turns the sentence into changes (`AIConfigPrompt`, `AIConfigService`); the answer is JSON only, a list of
/// `{ "key": <setting>, "value": <JSON> }` and an optional `"note"`, read strictly (`parse`). Each change is checked with
/// the rules Settings uses (`preview`) and shown as a row, old → new, or refused with the reason; the user confirms, and
/// the changes go through the config's save path (`apply`), which hands back what puts them back (`Edit`s, for undo).
///
/// Only the settings on the allowlist (`Setting`, `AppField`) can change. Every other key of the config, and anything that
/// looks like a secret, is refused (`Key.forbidden`); a key that isn't a setting at all makes the whole answer unreadable.
public enum AIConfig {
    /// At most this many output (translation) languages.
    public static let maxOutputLanguages = 5
    /// Undo restores the last changes within this many seconds.
    public static let undoWindow: TimeInterval = 10 * 60

    // MARK: - The allowlist

    /// A setting the AI may change, by its path in the config file.
    public enum Setting: String, CaseIterable, Sendable {
        case outputLanguages, inputLanguages, defaultInput, rewriteStyles, candidateLayout
        case typeOut, typeOutRate, typeOutVaries, typeOutMistakes
        case useSelection, rememberQuestions
        case redactionEnabled = "redaction.enabled", redactionEmails = "redaction.emails", redactionPhones = "redaction.phones"
        case redactionCards = "redaction.cards", redactionKeys = "redaction.keys", redactionIPs = "redaction.ips"
        /// Words added to the ones hidden; never removed or cleared here.
        case redactionWordsAdd = "redaction.customWords.add"
        case checkForUpdates
        /// The provider and its non-secret settings (the keys are only ever entered in Settings).
        case provider, awsProfile, region, modelId
        case anthropicModel = "anthropic.model", geminiModel = "gemini.model", openaiModel = "openai.model"
        case openaiBaseURL = "openai.baseURL"

        public var path: String { rawValue }

        /// An on/off setting.
        public var isFlag: Bool {
            switch self {
            case .typeOut, .typeOutVaries, .typeOutMistakes, .useSelection, .rememberQuestions, .redactionEnabled,
                 .redactionEmails, .redactionPhones, .redactionCards, .redactionKeys, .redactionIPs, .checkForUpdates:
                return true
            default:
                return false
            }
        }

        /// The model setting of `provider` (nil for those without one to choose).
        public static func model(of provider: Provider) -> Setting? {
            switch provider {
            case .bedrock: return .modelId
            case .anthropic: return .anthropicModel
            case .gemini: return .geminiModel
            case .openai: return .openaiModel
            case .hosted, .apple: return nil
            }
        }

        var modelProvider: Provider? {
            switch self {
            case .modelId: return .bedrock
            case .anthropicModel: return .anthropic
            case .geminiModel: return .gemini
            case .openaiModel: return .openai
            default: return nil
            }
        }
    }

    /// A setting of one app's profile (`AppProfile`): `appProfiles.<app>.<field>`, the app by name or bundle id.
    public enum AppField: String, CaseIterable, Sendable {
        case inputLanguage, rewriteStyles, typeOut, noAI
    }

    /// A key as the answer names it.
    public enum Key: Hashable, Sendable {
        case setting(Setting)
        /// The app as written (a name or a bundle id), resolved later (`Environment.resolveApp`).
        case app(String, AppField)
        /// A key of the config (or a secret) that can't be set here.
        case forbidden(String, secret: Bool)
        /// Sync through iCloud on or off (`iCloudSync.enabled`); what syncs is only set in Settings.
        case iCloudSync

        public var path: String {
            switch self {
            case .iCloudSync: return "iCloudSync.enabled"
            case let .setting(setting): return setting.path
            case let .app(app, field): return "appProfiles.\(app).\(field.rawValue)"
            case let .forbidden(path, _): return path
            }
        }

        /// The key `path` names, or nil when it is no setting at all (the answer is then unreadable).
        public static func parse(_ path: String) -> Key? {
            let path = path.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty, !path.contains(where: \.isNewline) else { return nil }
            if looksSecret(path) { return .forbidden(path, secret: true) }
            if let setting = Setting(rawValue: path) { return .setting(setting) }
            if path == Key.iCloudSync.path { return .iCloudSync }
            if path.hasPrefix("appProfiles.") {
                let rest = path.dropFirst("appProfiles.".count)
                guard let dot = rest.lastIndex(of: "."), dot > rest.startIndex else { return .forbidden(path, secret: false) }
                let app = String(rest[..<dot]), name = String(rest[rest.index(after: dot)...])
                guard let field = AppField(rawValue: name), AppProfile.isBundleID(app) || !app.trimmingCharacters(in: .whitespaces).isEmpty
                else { return .forbidden(path, secret: false) }
                return .app(app, field)
            }
            let root = String(path.prefix { $0 != "." })
            return knownRoots.contains(root) ? .forbidden(path, secret: false) : nil
        }

        /// A key, a token, a password or credentials: never set (nor shown) here, whatever its root.
        static func looksSecret(_ path: String) -> Bool {
            // By each part of the path: "maxTokens" and "redaction.keys" (a switch) aren't secrets, "anthropic.apiKey" is.
            path.lowercased().split(separator: ".").contains { part in
                part == "key" || ["apikey", "api_key", "apikeys", "secret", "token", "password", "credential", "credentials", "keychain",
                                  "access_key", "accesskey", "access_key_id", "secret_access_key"].contains { part == $0 || part.hasSuffix("_" + $0) }
                    || part.hasSuffix("apikey") || part.hasSuffix("secret") || part.hasSuffix("password") || part.hasSuffix("token")
            }
        }

        /// The config's own keys (and a few names of what it holds elsewhere): one not on the allowlist is refused, not
        /// unreadable.
        static let knownRoots: Set<String> = Set(Config.allKeys).union([
            "extensionSources", "plugins", "extensions", "hosted", "apple", "bedrock", "jargon",
        ])
    }

    /// The AWS regions Bedrock runs in (a region must be one of them).
    public static let regions = [
        "us-east-1", "us-east-2", "us-west-1", "us-west-2", "ca-central-1", "sa-east-1", "eu-central-1", "eu-central-2",
        "eu-west-1", "eu-west-2", "eu-west-3", "eu-north-1", "eu-south-1", "eu-south-2", "ap-northeast-1", "ap-northeast-2",
        "ap-northeast-3", "ap-south-1", "ap-south-2", "ap-southeast-1", "ap-southeast-2", "ap-southeast-3", "ap-southeast-4",
        "ap-east-2", "me-central-1", "il-central-1", "us-gov-west-1", "us-gov-east-1",
    ]

    // MARK: - The answer

    /// A JSON value as the answer has it.
    public indirect enum JSONValue: Equatable, Sendable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])

        init?(_ any: Any) {
            switch any {
            case is NSNull: self = .null
            case let number as NSNumber:
                self = number.isBoolean ? .bool(number.boolValue) : .number(number.doubleValue)
            case let string as String: self = .string(string)
            case let array as [Any]:
                var items: [JSONValue] = []
                for item in array {
                    guard let value = JSONValue(item) else { return nil }
                    items.append(value)
                }
                self = .array(items)
            case let object as [String: Any]:
                var fields: [String: JSONValue] = [:]
                for (key, item) in object {
                    guard let value = JSONValue(item) else { return nil }
                    fields[key] = value
                }
                self = .object(fields)
            default: return nil
            }
        }

        var foundation: Any {
            switch self {
            case .null: return NSNull()
            case let .bool(value): return value
            case let .number(value): return value
            case let .string(value): return value
            case let .array(items): return items.map(\.foundation)
            case let .object(fields): return fields.mapValues(\.foundation)
            }
        }

        /// As JSON text (keys sorted).
        public var json: String {
            guard let data = try? JSONSerialization.data(withJSONObject: foundation,
                                                         options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
            else { return "null" }
            return String(decoding: data, as: UTF8.self)
        }

        var strings: [String]? {
            guard case let .array(items) = self else { return nil }
            var out: [String] = []
            for item in items {
                guard case let .string(text) = item else { return nil }
                out.append(text)
            }
            return out
        }
    }

    /// One change the answer asks for.
    public struct Change: Equatable, Sendable {
        public var key: Key
        public var value: JSONValue

        public init(key: Key, value: JSONValue) {
            self.key = key
            self.value = value
        }
    }

    /// What the model answered: the changes, in its order (a key written twice: the last), and its note.
    public struct Proposal: Equatable, Sendable {
        public var changes: [Change]
        public var note: String?

        public init(changes: [Change], note: String? = nil) {
            self.changes = changes
            self.note = note
        }
    }

    public enum ParseError: Error, Equatable, Sendable {
        /// Not a JSON object of the right shape.
        case unreadable
        /// A key that is no setting.
        case unknownKey(String)
    }

    /// The answer read strictly: a JSON object `{"changes": [{"key": …, "value": …}, …], "note": …}` with nothing else in
    /// it (one Markdown code fence around it is allowed), each change exactly a key and a value, each key a setting
    /// (allowed or not: `Key.parse`). Anything else throws: the panel then says it couldn't turn that into a setting.
    public static func parse(_ text: String) throws -> Proposal {
        let body = unfenced(text)
        guard let data = body.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(object.keys).isSubset(of: ["changes", "note"]),
              let list = object["changes"] as? [Any] else { throw ParseError.unreadable }
        var note: String?
        switch object["note"] {
        case nil, is NSNull: note = nil
        case let text as String: note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        default: throw ParseError.unreadable
        }
        var changes: [Change] = []
        for item in list {
            guard let fields = item as? [String: Any], Set(fields.keys) == ["key", "value"],
                  let path = fields["key"] as? String, let raw = fields["value"], let value = JSONValue(raw)
            else { throw ParseError.unreadable }
            guard let key = Key.parse(path) else { throw ParseError.unknownKey(path) }
            // The same key again replaces what it said before.
            changes.removeAll { $0.key.path.caseInsensitiveCompare(key.path) == .orderedSame }
            changes.append(Change(key: key, value: value))
        }
        return Proposal(changes: changes, note: note?.isEmpty == true ? nil : note)
    }

    /// `text` without whitespace around it and one Markdown code fence around the JSON, if it has one.
    static func unfenced(_ text: String) -> String {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```"), body.hasSuffix("```"), body.count >= 6 {
            body = String(body.dropFirst(3).dropLast(3))
            if let newline = body.firstIndex(of: "\n"), body[..<newline].allSatisfy({ $0.isLetter }) {
                body = String(body[body.index(after: newline)...])  // "```json"
            }
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return body
    }

    // MARK: - Edits

    /// One setting's new value, as applied (`apply`); also what undoes a change (the value before).
    public enum Edit: Equatable, Sendable {
        case outputLanguages([OutputLanguage])
        case inputLanguages([Language])
        case defaultInput(Language)
        case rewriteStyles([String])
        case candidateLayout(CandidateArrangement)
        case flag(Setting, Bool)
        case typeOutRate(Double)
        /// Words added to `redaction.customWords` (those already there are skipped).
        case addWords([String])
        /// `redaction.customWords` as a whole: only what undoes `addWords`.
        case customWords([String])
        case app(String, AppValue)
        case provider(Provider)
        case awsProfile(String)
        /// Nil: the profile's own region.
        case region(String?)
        /// Nil: the provider's default model.
        case model(Provider, String?)
        /// Nil: the default base URL.
        case baseURL(String?)
        /// Sync through iCloud on or off.
        case iCloudSync(Bool)
    }

    /// What applying a preview does besides the settings: a finding's fixes.
    public enum Action: Equatable, Sendable {
        /// The repeated languages taken out of the config file, nothing else (`Doctor.removeRepeatedLanguages`).
        case resaveConfig
        case enableInputMethod
        case openPrivacy(Doctor.PrivacyPane)
        case downloadPack(Language)
        case openAppleIntelligenceSettings
        case checkForUpdates
        /// A command put on the clipboard, for Terminal (`Doctor.Fix.copyCommand`).
        case copyCommand(String)
    }

    /// One field of an app's profile; nil: as everywhere.
    public enum AppValue: Equatable, Sendable {
        case inputLanguage(Language?)
        case rewriteStyles([String]?)
        case typeOut(Bool?)
        case noAI(Bool?)
    }

    /// `edits` made to `config`, in order, the way Settings makes them (languages through `setOrder`, a profile left
    /// setting nothing removed); what puts each back is returned, last first, so applying it restores exactly the values
    /// these keys had (`undo`).
    @discardableResult
    public static func apply(_ edits: [Edit], to config: inout Config) -> [Edit] {
        applyRecording(edits, to: &config).map(\.undo)
    }

    /// `apply`, with each key's value right after its edit (`written`, in the order of the undo edits): undo only puts
    /// back a key still holding what was written (`undoing`).
    static func applyRecording(_ edits: [Edit], to config: inout Config) -> [(undo: Edit, written: Edit)] {
        var out: [(undo: Edit, written: Edit)] = []
        for edit in edits {
            let before = inverse(of: edit, in: config)
            applyOne(edit, to: &config)
            out.append((before, inverse(of: edit, in: config)))
        }
        return out.reversed()
    }

    private static func applyOne(_ edit: Edit, to config: inout Config) {
        switch edit {
        case let .outputLanguages(languages): config.setOrder(languages)
        case let .inputLanguages(languages): config.setOrder(languages)
        case let .defaultInput(language):
            config.setOrder([language] + config.inputLanguages.filter { $0 != language })
        case let .rewriteStyles(names): config.rewriteStyles = names
        case let .candidateLayout(layout): config.candidateLayout = layout
        case let .flag(setting, on): setFlag(setting, on, in: &config)
        case let .typeOutRate(rate): config.typeOutRate = rate
        case let .addWords(words):
            let have = Set(config.redaction.customWords.map { $0.lowercased() })
            config.redaction.customWords += words.filter { !have.contains($0.lowercased()) }
        case let .customWords(words): config.redaction.customWords = words
        case let .app(app, value):
            config.changeProfile(for: app, dropsEmpty: true) { profile in
                switch value {
                case let .inputLanguage(language): profile.inputLanguage = language
                case let .rewriteStyles(names): profile.rewriteStyles = names
                case let .typeOut(on): profile.typeOut = on
                case let .noAI(on): profile.noAI = on == true ? true : nil
                }
            }
        case let .provider(provider): config.provider = provider
        case let .awsProfile(profile): config.awsProfile = profile
        case let .region(region): config.region = region
        case let .model(provider, model): setModel(model, of: provider, in: &config)
        case let .baseURL(url): config.openai.baseURL = url
        case let .iCloudSync(on): config.iCloudSync.enabled = on
        }
    }

    /// What `edit` changes, as it is in `config` now.
    static func inverse(of edit: Edit, in config: Config) -> Edit {
        switch edit {
        case .outputLanguages: return .outputLanguages(config.outputLanguages)
        // The default input leads the input languages: both come back with their list.
        case .inputLanguages, .defaultInput: return .inputLanguages(config.inputLanguages)
        case .rewriteStyles: return .rewriteStyles(config.rewriteStyles)
        case .candidateLayout: return .candidateLayout(config.candidateLayout)
        case let .flag(setting, _): return .flag(setting, flag(setting, in: config))
        case .typeOutRate: return .typeOutRate(config.typeOutRate)
        case .addWords, .customWords: return .customWords(config.redaction.customWords)
        case let .app(app, value):
            let profile = config.profile(for: app)
            switch value {
            case .inputLanguage: return .app(app, .inputLanguage(profile?.inputLanguage))
            case .rewriteStyles: return .app(app, .rewriteStyles(profile?.rewriteStyles))
            case .typeOut: return .app(app, .typeOut(profile?.typeOut))
            case .noAI: return .app(app, .noAI(profile?.noAI))
            }
        case .provider: return .provider(config.provider)
        case .awsProfile: return .awsProfile(config.awsProfile)
        case .region: return .region(config.region)
        case let .model(provider, _): return .model(provider, storedModel(of: provider, in: config))
        case .baseURL: return .baseURL(config.openai.baseURL)
        case .iCloudSync: return .iCloudSync(config.iCloudSync.enabled)
        }
    }

    /// The edits that undo `applied` (from `apply`), as one value with when it was applied: Undo within
    /// `undoWindow`.
    public struct Applied: Equatable, Sendable {
        public var undo: [Edit]
        public var date: Date
        /// The rows that were applied, for the confirmation ("Undone: …").
        public var count: Int
        /// What each key of `undo` held right after it was applied (same order; empty: not checked): a key changed since
        /// is left as it is.
        public var written: [Edit]

        public init(undo: [Edit], date: Date, count: Int, written: [Edit] = []) {
            self.undo = undo
            self.date = date
            self.count = count
            self.written = written
        }

        public func canUndo(at now: Date) -> Bool { now.timeIntervalSince(date) <= AIConfig.undoWindow && now >= date.addingTimeInterval(-1) }
    }

    /// Reads the config file, makes `edits` and writes back the keys they changed (`writing`): the input method and the
    /// settings window read it again from there; every other key of the file, one this version doesn't know too, stays
    /// as it was. What undoes them, with now.
    public static func applying(_ edits: [Edit], at url: URL = Config.defaultURL, now: Date = Date()) throws -> Applied {
        let before = try Config.load(from: url)
        var config = before
        let recorded = applyRecording(edits, to: &config)
        try writing(config, from: before, keys: changedKeys(before, config), at: url)
        return Applied(undo: recorded.map(\.undo), date: now, count: edits.count, written: recorded.map(\.written))
    }

    /// What an undo did: how many keys it put back, and the edits it skipped because their key changed since.
    public struct UndoReport: Equatable, Sendable {
        public var undone: Int
        /// The keys left as they are (changed since the Assistant wrote them), as the edits that would have put them back.
        public var skipped: [Edit]
    }

    /// Puts back what `applied` changed, if it is recent enough (nil: nothing to undo): each key still holding what was
    /// written; one changed since (in Settings, by hand) is left as it is, and reported.
    public static func undoing(_ applied: Applied, at url: URL = Config.defaultURL, now: Date = Date()) throws -> UndoReport? {
        guard applied.canUndo(at: now) else { return nil }
        let before = try Config.load(from: url)
        var config = before
        var report = UndoReport(undone: 0, skipped: [])
        for (index, edit) in applied.undo.enumerated() {
            if applied.written.indices.contains(index), inverse(of: edit, in: config) != applied.written[index] {
                report.skipped.append(edit)
                continue
            }
            applyOne(edit, to: &config)
            report.undone += 1
        }
        try writing(config, from: before, keys: changedKeys(before, config), at: url)
        return report
    }

    /// Puts back what `applied` changed, if it is recent enough (false: nothing to undo).
    public static func undo(_ applied: Applied, at url: URL = Config.defaultURL, now: Date = Date()) throws -> Bool {
        try undoing(applied, at: url, now: now) != nil
    }

    // MARK: - Writing only what changed

    /// Keys written with each other: the one in use leads its list.
    static let companions: [String: [String]] = [
        "outputLanguages": ["outputLanguage"], "outputLanguage": ["outputLanguages"],
        "inputLanguages": ["defaultInput"], "defaultInput": ["inputLanguages"],
    ]

    /// The top-level keys whose encoded values differ between `old` and `new`.
    public static func changedKeys(_ old: Config, _ new: Config) -> Set<String> {
        let a = encoded(old), b = encoded(new)
        return Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }
    }

    /// `config` written into the file at `url` key by key: only `keys` (and their companions) take `config`'s values, a
    /// key `config` no longer writes goes; every other key of the file stays as it was, its text untouched, one this
    /// version doesn't know too. Inside an object-valued key (`appProfiles` per app, `redaction` per field, `openai` …)
    /// only what changed from `old` to `config` is written (`merged`): a field written meanwhile by something else (a
    /// Settings window's save over the Assistant's write, or the other way round) and fields this version doesn't know stay.
    /// `old` is the config the writer last read or wrote. A missing file is written whole (`Config.write`).
    public static func writing(_ config: Config, from old: Config, keys: Set<String>, at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return try config.write(to: url) }
        try writing(encoded(config), from: encoded(old), keys: keys, at: url)
    }

    /// `writing` with the config and the one read before as the file holds them (`encoded`), into a file that exists.
    static func writing(_ values: [String: JSONValue], from before: [String: JSONValue], keys: Set<String>, at url: URL) throws {
        guard !keys.isEmpty else { return }
        try patchingFile(at: url) { file in
            for key in keys.union(keys.flatMap { companions[$0] ?? [] }) {
                file[key] = merged(file: file[key], old: before[key], new: values[key])
            }
        }
    }

    /// The new value of a key over what the file holds: objects field by field, at every depth, with only the fields that
    /// changed from `old` to `new` written (one `new` has with another value takes it, one `old` had and `new` doesn't
    /// goes); a field the writer left as it was keeps the file's value, and so does one neither knows. Anything else is
    /// `new`'s.
    static func merged(file: JSONValue?, old: JSONValue?, new: JSONValue?) -> JSONValue? {
        guard case let .object(newFields)? = new, case var .object(fields)? = file else { return new }
        let oldFields: [String: JSONValue]
        if case let .object(known)? = old { oldFields = known } else { oldFields = [:] }
        for key in Set(newFields.keys).union(oldFields.keys) where newFields[key] != oldFields[key] {
            fields[key] = newFields[key].flatMap { merged(file: fields[key], old: oldFields[key], new: $0) }
        }
        return .object(fields)
    }

    /// The config file at `url` as a JSON object, `change` made to its top-level keys, and written back with only the
    /// keys that changed rewritten (`JSONFileText.patched`): every other key keeps its text as it was, numbers too (a
    /// large integer isn't turned into a float). Throws when it isn't a JSON object (nothing is written then).
    public static func patchingFile(at url: URL, _ change: (inout [String: JSONValue]) throws -> Void) throws {
        let data = try Data(contentsOf: url)
        guard case var .object(file)? = (try? JSONSerialization.jsonObject(with: data)).flatMap(JSONValue.init) else {
            throw ConfigError.malformed(path: url.path, detail: "not a JSON object")
        }
        let before = file
        try change(&file)
        let changed = Set(before.keys).union(file.keys).filter { before[$0] != file[$0] }
        guard !changed.isEmpty else { return }
        if let text = JSONFileText.patched(String(decoding: data, as: UTF8.self), setting: file, keys: changed) {
            return try Data(text.utf8).write(to: url, options: .atomic)
        }
        // Text it can't patch in place (it parses, but not as expected): written whole, as `Config.write` does.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(JSONValue.object(file)).write(to: url, options: .atomic)
    }

    /// `config` as its file holds it, key by key.
    static func encoded(_ config: Config) -> [String: JSONValue] {
        guard let data = try? JSONEncoder().encode(config), case let .object(object)? = (try? JSONSerialization.jsonObject(with: data))
            .flatMap(JSONValue.init) else { return [:] }
        return object
    }

    static func flag(_ setting: Setting, in config: Config) -> Bool {
        switch setting {
        case .typeOut: return config.typeOut
        case .typeOutVaries: return config.typeOutVaries
        case .typeOutMistakes: return config.typeOutMistakes
        case .useSelection: return config.useSelection
        case .rememberQuestions: return config.rememberQuestions
        case .redactionEnabled: return config.redaction.enabled
        case .redactionEmails: return config.redaction.emails
        case .redactionPhones: return config.redaction.phones
        case .redactionCards: return config.redaction.cards
        case .redactionKeys: return config.redaction.keys
        case .redactionIPs: return config.redaction.ips
        case .checkForUpdates: return config.checkForUpdates
        default: return false
        }
    }

    static func setFlag(_ setting: Setting, _ on: Bool, in config: inout Config) {
        switch setting {
        case .typeOut: config.typeOut = on
        case .typeOutVaries: config.typeOutVaries = on
        case .typeOutMistakes: config.typeOutMistakes = on
        case .useSelection: config.useSelection = on
        case .rememberQuestions: config.rememberQuestions = on
        case .redactionEnabled: config.redaction.enabled = on
        case .redactionEmails: config.redaction.emails = on
        case .redactionPhones: config.redaction.phones = on
        case .redactionCards: config.redaction.cards = on
        case .redactionKeys: config.redaction.keys = on
        case .redactionIPs: config.redaction.ips = on
        case .checkForUpdates: config.checkForUpdates = on
        default: break
        }
    }

    /// The model as stored for `provider` (nil: its default).
    static func storedModel(of provider: Provider, in config: Config) -> String? {
        switch provider {
        case .bedrock: return config.modelId
        case .anthropic: return config.anthropic.model
        case .gemini: return config.gemini.model
        case .openai: return config.openai.model
        case .hosted, .apple: return nil
        }
    }

    static func setModel(_ model: String?, of provider: Provider, in config: inout Config) {
        switch provider {
        case .bedrock: if let model { config.modelId = model }
        case .anthropic: config.anthropic.model = model
        case .gemini: config.gemini.model = model
        case .openai: config.openai.model = model
        case .hosted, .apple: break
        }
    }

    // MARK: - Keys typed into the sentence

    /// `sentence` without the API keys and tokens in it (`Redaction`'s detection of keys), and whether there were any:
    /// a key typed here is never sent to the AI. The provider its shape belongs to, if it tells.
    public static func droppingKeys(_ sentence: String) -> (text: String, dropped: Bool, provider: Provider?) {
        let found = Redaction.find(sentence, settings: keysOnly).filter { $0.kind == .key }
        guard !found.isEmpty else { return (sentence, false, nil) }
        let ns = sentence as NSString
        let keys = found.map { ns.substring(with: $0.range) }
        let out = NSMutableString(string: sentence)
        for item in found.reversed() { out.replaceCharacters(in: item.range, with: "") }
        let text = (out as String).split(whereSeparator: { $0 == " " }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let provider: Provider? = keys.lazy.compactMap { key -> Provider? in
            if key.hasPrefix("sk-ant-") { return .anthropic }
            if key.hasPrefix("AIza") { return .gemini }
            if key.hasPrefix("sk-") { return .openai }
            return nil
        }.first
        return (text, true, provider)
    }

    /// `Redaction`'s detection of API keys and tokens alone, whatever the user's hiding settings.
    static let keysOnly = RedactionSettings(enabled: true, emails: false, phones: false, cards: false, keys: true, ips: false)

    /// Whether `text` holds something that looks like an API key or a token (`Redaction`'s key detection).
    public static func looksLikeKey(_ text: String) -> Bool {
        Redaction.find(text, settings: keysOnly).contains { $0.kind == .key }
    }

    /// `text` with what looks like a key replaced by `mask`: never shown, never sent.
    public static func maskingKeys(_ text: String, with mask: String = "•••") -> String {
        let found = Redaction.find(text, settings: keysOnly).filter { $0.kind == .key }
        guard !found.isEmpty else { return text }
        let out = NSMutableString(string: text)
        for item in found.reversed() { out.replaceCharacters(in: item.range, with: mask) }
        return out as String
    }

    /// Whether any string in `value` looks like a key.
    static func holdsKey(_ value: JSONValue) -> Bool {
        switch value {
        case let .string(text): return looksLikeKey(text)
        case let .array(items): return items.contains(where: holdsKey)
        case let .object(fields): return fields.keys.contains(where: looksLikeKey) || fields.values.contains(where: holdsKey)
        case .null, .bool, .number: return false
        }
    }
}

extension AIConfig.JSONValue: Encodable {
    /// As JSON: whole numbers without a fraction (as `Config` writes its counts), the rest as they are.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(value): try c.encode(value)
        case let .number(value):
            if value == value.rounded(), abs(value) < 1e15 { try c.encode(Int64(value)) } else { try c.encode(value) }
        case let .string(value): try c.encode(value)
        case let .array(items): try c.encode(items)
        case let .object(fields): try c.encode(fields)
        }
    }
}

import Foundation

/// A plugin.json's `completions` and `preferences` read (spec 1.1, 6.8, 6.9): each completion entry on its own, one that
/// breaks the rules refused with a reason Settings shows (the plugin and its command still load); the defaults filled in.
enum CompletionDeclaration {
    typealias JSON = AIConfig.JSONValue

    /// The longest a prefix may be ("PROJ-", "#").
    static let maxPrefix = 16
    /// The most characters a token may need after its prefix (`minChars`, `queryMinChars`).
    static let maxChars = 32
    /// `refresh`: 5 minutes to 7 days.
    static let refreshRange: ClosedRange<TimeInterval> = 300...604_800

    /// The sources `value` declares and the entries refused, for a plugin of `type` with `timeoutSeconds`.
    static func read(_ value: JSON?, type: PluginManifest.PluginType, timeoutSeconds: Double?)
        -> (sources: [CompletionSource], refused: [CompletionRefusal]) {
        guard let value, value != .null else { return ([], []) }
        guard case let .array(entries) = value else {
            return ([], [CompletionRefusal(name: nil, reason: "completions must be a list")])
        }
        // A completion's script exports load and query: only a script plugin has one.
        if type != .script {
            return ([], entries.map { CompletionRefusal(name: declaredName($0), reason: "only a script plugin can have completions") })
        }
        // A load may take 20 s at most: a plugin that needs more has none.
        if let timeoutSeconds, timeoutSeconds > PluginManifest.maxTimeout {
            return ([], entries.map {
                CompletionRefusal(name: declaredName($0), reason: "timeoutSeconds is over \(Int(PluginManifest.maxTimeout)): a list must load within that")
            })
        }
        var sources: [CompletionSource] = []
        var refused: [CompletionRefusal] = []
        for entry in entries {
            switch source(entry) {
            case let .success(source):
                if sources.contains(where: { $0.name == source.name }) {
                    refused.append(CompletionRefusal(name: source.name, reason: "the name \(source.name) is there twice"))
                } else {
                    sources.append(source)
                }
            case let .failure(refusal):
                refused.append(refusal)
            }
        }
        return (sources, refused)
    }

    /// The entry's `name` as declared, when it is text.
    static func declaredName(_ entry: JSON) -> String? {
        guard case let .object(fields) = entry, case let .string(name)? = fields["name"] else { return nil }
        return name
    }

    /// One entry, or why it is refused.
    static func source(_ entry: JSON) -> Result<CompletionSource, CompletionRefusal> {
        guard case let .object(fields) = entry else {
            return .failure(CompletionRefusal(name: nil, reason: "a completion must be an object"))
        }
        let declared = declaredName(entry)
        func refuse(_ reason: String) -> Result<CompletionSource, CompletionRefusal> {
            .failure(CompletionRefusal(name: declared, reason: reason))
        }
        guard let name = declared else { return refuse("a completion needs a name") }
        guard isName(name) else { return refuse("the name must be 1–24 small letters or digits") }
        guard let title = fields["title"].flatMap(localized) else { return refuse("a completion needs a title") }

        var prefix: String?
        switch fields["prefix"] {
        case nil, .null?: break
        case let .string(text)?:
            let normalized = SuggestionsToken.normalized(text)
            guard !normalized.isEmpty, normalized.count <= maxPrefix, normalized.allSatisfy(SuggestionsToken.isTokenCharacter),
                  normalized.first != "@" else {
                return refuse("the prefix must be up to \(maxPrefix) letters, digits or . _ - #, not starting with @")
            }
            prefix = normalized
        default: return refuse("the prefix must be text")
        }

        var compare: CompletionSource.Compare?
        switch fields["compare"] {
        case nil, .null?: break
        case let .string(text)?:
            guard let value = CompletionSource.Compare(rawValue: text) else { return refuse("compare must be prefix or exact") }
            compare = value
        default: return refuse("compare must be prefix or exact")
        }
        if prefix == nil, compare == .prefix { return refuse("a completion without a prefix must compare exact") }

        guard let minChars = integer(fields["minChars"], in: (prefix == nil ? 1 : 0)...maxChars, or: prefix == nil ? 3 : 1) else {
            return refuse("minChars must be a whole number from \(prefix == nil ? 1 : 0) to \(maxChars)")
        }
        guard let list = flag(fields["list"]), let query = flag(fields["query"]) else {
            return refuse("list and query must be true or false")
        }
        // Every number typed anywhere (a card's, in a browser) would be sent as it grows: v1 looks up only after a prefix.
        if prefix == nil, query { return refuse("a completion without a prefix can't query: give it a prefix, or a list only") }
        var refresh: TimeInterval = 3600
        switch fields["refresh"] {
        case nil, .null?: break
        case let .string(text)?:
            guard let seconds = duration(text), refreshRange.contains(seconds) else {
                return refuse("refresh must be from 5m to 7d (like 15m, 1h, 1d)")
            }
            refresh = seconds
        default: return refuse("refresh must be from 5m to 7d (like 15m, 1h, 1d)")
        }
        guard let queryMinChars = integer(fields["queryMinChars"], in: 1...maxChars, or: 3) else {
            return refuse("queryMinChars must be a whole number from 1 to \(maxChars)")
        }
        let insert: CompletionInsert
        switch self.insert(fields["insert"]) {
        case let .success(read): insert = read
        case let .failure(reason): return refuse(reason.reason)
        }
        return .success(CompletionSource(name: name, title: title, prefix: prefix, minChars: minChars, compare: compare,
                                         list: list, refresh: refresh, query: query, queryMinChars: queryMinChars,
                                         insert: insert))
    }

    /// `[a-z0-9]{1,24}`.
    static func isName(_ name: String) -> Bool {
        (1...24).contains(name.count) && name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
    }

    /// `"…"` or `{"en": "…", "zh": "…"}`, not empty.
    static func localized(_ value: JSON) -> LocalizedText? {
        switch value {
        case let .string(text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : LocalizedText(en: text)
        case let .object(fields):
            guard case let .string(en)? = fields["en"], !en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            if case let .string(zh)? = fields["zh"] { return LocalizedText(en: en, zh: zh) }
            return LocalizedText(en: en)
        default:
            return nil
        }
    }

    /// A whole number in `range`, `fallback` when left out; nil when it is anything else.
    static func integer(_ value: JSON?, in range: ClosedRange<Int>, or fallback: Int) -> Int? {
        switch value {
        case nil, .null?: return fallback
        case let .number(number)?:
            guard let whole = Int(exactly: number), range.contains(whole) else { return nil }
            return whole
        default: return nil
        }
    }

    static func flag(_ value: JSON?) -> Bool? {
        switch value {
        case nil, .null?: return false
        case let .bool(flag)?: return flag
        default: return nil
        }
    }

    /// "90s", "15m", "1h", "7d" in seconds; nil for anything else.
    static func duration(_ text: String) -> TimeInterval? {
        guard let unit = text.last, let count = Int(text.dropLast()), count > 0, text.dropLast().allSatisfy(\.isASCII) else { return nil }
        switch unit {
        case "s": return TimeInterval(count)
        case "m": return TimeInterval(count) * 60
        case "h": return TimeInterval(count) * 3600
        case "d": return TimeInterval(count) * 86400
        default: return nil
        }
    }

    /// `seconds` as `duration` reads it, in the largest unit that fits whole.
    static func durationText(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        if whole % 86400 == 0 { return "\(whole / 86400)d" }
        if whole % 3600 == 0 { return "\(whole / 3600)h" }
        if whole % 60 == 0 { return "\(whole / 60)m" }
        return "\(whole)s"
    }

    struct Problem: Error {
        var reason: String
    }

    /// `insert`: an object of `default`, `chat` and `terminal`, each a template, a list of them or null.
    static func insert(_ value: JSON?) -> Result<CompletionInsert, Problem> {
        guard let value, value != .null else { return .success(.standard) }
        guard case let .object(fields) = value else { return .failure(Problem(reason: "insert must be an object of templates")) }
        var read: [String: CompletionInsert.Templates] = [:]
        for key in ["default", "chat", "terminal"] {
            guard let entry = fields[key] else { continue }
            switch entry {
            case .null:
                read[key] = .off
            case let .string(text):
                guard isTemplate(text) else { return .failure(Problem(reason: "insert.\(key) isn't a template")) }
                read[key] = .templates([text])
            case let .array(items):
                var templates: [String] = []
                for item in items {
                    guard case let .string(text) = item, isTemplate(text) else {
                        return .failure(Problem(reason: "insert.\(key) must be templates (text)"))
                    }
                    templates.append(text)
                }
                guard !templates.isEmpty else { return .failure(Problem(reason: "insert.\(key) is an empty list")) }
                read[key] = .templates(templates)
            default:
                return .failure(Problem(reason: "insert.\(key) must be a template, a list of them or null"))
            }
        }
        return .success(CompletionInsert(default: read["default"] ?? .templates(["{arg}"]), chat: read["chat"], terminal: read["terminal"]))
    }

    /// Text with each `{` opening a variable's name (letters, digits, `_`) closed by `}`, and no `}` on its own; not empty,
    /// no line breaks or other control characters.
    static func isTemplate(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 256, !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { return false }
        return CompletionTemplate.parts(text) != nil
    }

    /// `source` as plugin.json writes it.
    static func json(_ source: CompletionSource) -> JSON {
        var fields: [String: JSON] = [
            "name": .string(source.name), "title": title(source.title), "minChars": .number(Double(source.minChars)),
            "compare": .string(source.compare.rawValue), "list": .bool(source.list), "query": .bool(source.query),
            "refresh": .string(durationText(source.refresh)), "queryMinChars": .number(Double(source.queryMinChars)),
        ]
        if let prefix = source.prefix { fields["prefix"] = .string(prefix) }
        func templates(_ value: CompletionInsert.Templates) -> JSON {
            switch value {
            case .off: return .null
            case let .templates(list): return list.count == 1 ? .string(list[0]) : .array(list.map(JSON.string))
            }
        }
        var insert: [String: JSON] = ["default": templates(source.insert.default)]
        if let chat = source.insert.chat { insert["chat"] = templates(chat) }
        if let terminal = source.insert.terminal { insert["terminal"] = templates(terminal) }
        fields["insert"] = .object(insert)
        return .object(fields)
    }

    static func title(_ text: LocalizedText) -> JSON {
        text.zh.map { .object(["en": .string(text.en), "zh": .string($0)]) } ?? .string(text.en)
    }
}

extension PluginPreference {
    /// `preferences` read: each a `text` or `password` with a name (letters, digits, `_`, `-`) and a title; another type,
    /// one without a name or a title, or a name twice is the plugin's problem.
    static func read(_ value: AIConfig.JSONValue?) -> Result<[PluginPreference], CompletionDeclaration.Problem> {
        typealias Problem = CompletionDeclaration.Problem
        guard let value, value != .null else { return .success([]) }
        guard case let .array(entries) = value else { return .failure(Problem(reason: "preferences must be a list")) }
        var read: [PluginPreference] = []
        for entry in entries {
            guard case let .object(fields) = entry else { return .failure(Problem(reason: "a preference must be an object")) }
            guard case let .string(name)? = fields["name"], (1...32).contains(name.count),
                  name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else {
                return .failure(Problem(reason: "a preference needs a name of letters, digits, _ or -"))
            }
            guard case let .string(type)? = fields["type"], let kind = Kind(rawValue: type) else {
                return .failure(Problem(reason: "the preference \(name) must be of type text or password"))
            }
            guard let title = fields["title"].flatMap(CompletionDeclaration.localized) else {
                return .failure(Problem(reason: "the preference \(name) needs a title"))
            }
            guard !read.contains(where: { $0.name == name }) else {
                return .failure(Problem(reason: "the preference \(name) is there twice"))
            }
            func text(_ key: String) -> String? { if case let .string(text)? = fields[key] { text } else { nil } }
            read.append(PluginPreference(name: name, kind: kind, title: title, placeholder: text("placeholder"),
                                         defaultValue: kind == .password ? nil : text("default")))
        }
        return .success(read)
    }

    /// As plugin.json writes it.
    var json: AIConfig.JSONValue {
        var fields: [String: AIConfig.JSONValue] = ["name": .string(name), "type": .string(kind.rawValue),
                                                    "title": CompletionDeclaration.title(title)]
        if let placeholder { fields["placeholder"] = .string(placeholder) }
        if let defaultValue { fields["default"] = .string(defaultValue) }
        return .object(fields)
    }
}

/// An entry refused is what reading it failed with.
extension CompletionRefusal: Error {}

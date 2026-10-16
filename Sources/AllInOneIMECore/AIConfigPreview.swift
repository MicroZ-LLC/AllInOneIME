import Foundation

extension AIConfig {
    // MARK: - What the checks need

    /// What a check needs besides the config: which language packs are installed, the apps, the AWS profiles, the
    /// models the app knows, the providers offered, which providers have a key saved, and the interface language of the
    /// rows. The tests give their own.
    public struct Environment: Sendable {
        public var packInstalled: @Sendable (Language) -> Bool
        public var apps: AppCatalog
        public var awsProfiles: @Sendable () -> [String]
        /// The models offered for a provider (Settings' list); a model ID must be one of them.
        public var knownModels: @Sendable (Provider) -> [String]
        public var offeredProviders: [Provider]
        /// Whether a key is saved for the provider (or the hosted service is signed in to); asked without reading it.
        public var hasKey: @Sendable (Provider) -> Bool
        public var chinese: Bool

        public init(packInstalled: @escaping @Sendable (Language) -> Bool = { _ in true }, apps: AppCatalog = AppCatalog(),
                    awsProfiles: @escaping @Sendable () -> [String] = { [] },
                    knownModels: @escaping @Sendable (Provider) -> [String] = { _ in [] },
                    offeredProviders: [Provider] = [.bedrock, .anthropic, .gemini, .openai],
                    hasKey: @escaping @Sendable (Provider) -> Bool = { _ in false }, chinese: Bool = false) {
            self.packInstalled = packInstalled
            self.apps = apps
            self.awsProfiles = awsProfiles
            self.knownModels = knownModels
            self.offeredProviders = offeredProviders
            self.hasKey = hasKey
            self.chinese = chinese
        }
    }

    /// The apps an app name in the answer can be ("WeChat", "微信", "com.tencent.xinWeChat"): the installed ones, the
    /// ones typed in lately and those with settings of their own, each by its bundle id and its names.
    public struct AppCatalog: Equatable, Sendable {
        public struct App: Equatable, Sendable {
            public var bundleID: String
            /// Its names: as Finder shows it, its bundle's name, and in other languages ("WeChat", "微信").
            public var names: [String]

            public init(bundleID: String, names: [String]) {
                self.bundleID = bundleID
                self.names = names
            }

            public var name: String { names.first ?? bundleID }
        }

        public enum Match: Equatable, Sendable {
            case found(bundleID: String, name: String)
            case none
            /// More than one app has that name: which (by name).
            case ambiguous([String])
        }

        public var apps: [App]

        public init(apps: [App] = []) { self.apps = apps }

        /// The app `query` names: its bundle id (in any case); else the one app with that name (ignoring case, spaces and
        /// ".app"); else the one app with it as a word of its name ("Word" → Microsoft Word). None when nothing matches,
        /// ambiguous when several do: never a guess.
        public func resolve(_ query: String) -> Match {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return .none }
            if let app = apps.first(where: { $0.bundleID.caseInsensitiveCompare(text) == .orderedSame }) {
                return .found(bundleID: app.bundleID, name: app.name)
            }
            let wanted = Self.normalized(text)
            let exact = unique(apps.filter { $0.names.contains { Self.normalized($0) == wanted } })
            if let match = Self.match(exact) { return match }
            let words = unique(apps.filter { app in
                app.names.contains { name in
                    name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { String($0) == wanted }
                }
            })
            return Self.match(words) ?? .none
        }

        /// The apps whose names contain `query` (for the on-device model's lookup tool), at most `limit`.
        public func search(_ query: String, limit: Int = 8) -> [App] {
            let wanted = Self.normalized(query)
            guard !wanted.isEmpty else { return [] }
            return Array(unique(apps.filter { app in
                app.bundleID.lowercased().contains(wanted) || app.names.contains { Self.normalized($0).contains(wanted) }
            }).prefix(limit))
        }

        private func unique(_ found: [App]) -> [App] {
            var seen = Set<String>()
            return found.filter { seen.insert($0.bundleID.lowercased()).inserted }
        }

        private static func match(_ found: [App]) -> Match? {
            switch found.count {
            case 0: return nil
            case 1: return .found(bundleID: found[0].bundleID, name: found[0].name)
            default: return .ambiguous(found.map(\.name))
            }
        }

        static func normalized(_ name: String) -> String {
            var text = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasSuffix(".app") { text = String(text.dropLast(4)) }
            return text.filter { !$0.isWhitespace }
        }
    }

    // MARK: - The preview

    /// One row of the preview: a change (old → new), or a part refused with the reason, or the key a provider needs.
    public struct Row: Equatable, Sendable {
        public enum Status: Equatable, Sendable {
            case change
            case refused(String)
            /// The provider needs a key (or a sign-in): applying opens Settings at its key field.
            case needsKey(Provider)
            /// Something applying does besides the settings (`@doctor`'s fixes: a pack downloaded, a pane opened).
            case action
        }

        /// The key as resolved ("appProfiles.com.tencent.xinWeChat.inputLanguage").
        public var key: String
        public var label: String
        public var old: String?
        public var new: String?
        public var status: Status
        /// What applying it does (nil for a refused row and a key row).
        public var edit: Edit?
        /// What an action row does.
        public var action: Action?

        public init(key: String, label: String, old: String? = nil, new: String? = nil, status: Status, edit: Edit? = nil,
                    action: Action? = nil) {
            self.key = key
            self.label = label
            self.old = old
            self.new = new
            self.status = status
            self.edit = edit
            self.action = action
        }

        /// The row as the panel shows it: "Translation languages: English, Japanese → English, French"; a refused part
        /// "✕ Model ID: not one the app knows".
        public func text(chinese: Bool) -> String {
            let colon = chinese ? "：" : ": "
            switch status {
            case .change: return label + colon + (old ?? "") + " → " + (new ?? "")
            case let .refused(reason): return "✕ " + label + colon + reason
            case .needsKey: return label + colon + (new ?? "")
            case .action: return "→ " + label
            }
        }

        public var isRefused: Bool { if case .refused = status { return true } else { return false } }
    }

    /// The changes a proposal makes to the settings as they are, row by row, and what can be applied.
    public struct Preview: Equatable, Sendable {
        public var rows: [Row]
        /// The model's note, if it wrote one.
        public var note: String?
        /// A key was typed into the sentence and dropped before the request (`droppingKeys`).
        public var droppedKey = false

        public init(rows: [Row], note: String? = nil, droppedKey: Bool = false) {
            self.rows = rows
            self.note = note
            self.droppedKey = droppedKey
        }

        /// What applying does, in order.
        public var edits: [Edit] { rows.compactMap(\.edit) }
        /// The provider whose key field applying opens.
        public var needsKey: Provider? {
            rows.lazy.compactMap { if case let .needsKey(provider) = $0.status { return provider } else { return nil } }.first
        }
        /// What applying does besides the settings, in order.
        public var actions: [Action] { rows.compactMap(\.action) }
        /// Something to apply (⏎ / 1): a change, a key to enter, an action.
        public var canApply: Bool { !edits.isEmpty || needsKey != nil || !actions.isEmpty }
        /// The provider changes: Test Connection runs once it is applied.
        public var changesProvider: Bool {
            edits.contains {
                switch $0 {
                case .provider, .awsProfile, .region, .model, .baseURL: return true
                default: return false
                }
            }
        }
    }

    /// Why nothing can be applied: the one line the panel shows instead of a preview.
    public enum Failure: Error, Equatable, Sendable {
        /// The answer wasn't readable, or asked for nothing.
        case notUnderstood
        /// Everything it asked for is refused: keys that can't be set here.
        case notAllowed
        /// Everything it asked for is already so.
        case alreadySet
    }

    /// `proposal` checked against `config` with the rules Settings uses, a row per change, in the allowlist's order (the
    /// input languages before the default one, an app's settings after the others). A change to what is already set is
    /// left out. Nil, with the reason, when nothing can be applied.
    public static func preview(_ proposal: Proposal, config: Config, environment env: Environment,
                               droppedKey: (dropped: Bool, provider: Provider?) = (false, nil)) -> Result<Preview, Failure> {
        let (rows, unchanged) = check(proposal, config: config, environment: env, droppedKey: droppedKey)
        let preview = Preview(rows: rows, note: proposal.note, droppedKey: droppedKey.dropped)
        guard preview.canApply else {
            if rows.contains(where: \.isRefused) { return .failure(.notAllowed) }
            return .failure(unchanged > 0 ? .alreadySet : .notUnderstood)
        }
        return .success(preview)
    }

    /// The one line when nothing can be applied: the refused part's own when there is one (its reason), else `failure`'s.
    public static func failureLine(_ failure: Failure, proposal: Proposal?, config: Config, environment env: Environment) -> String {
        let text = Text(chinese: env.chinese)
        if failure == .notAllowed, let proposal {
            let refused = check(proposal, config: config, environment: env).rows.filter(\.isRefused)
            if refused.count == 1 { return refused[0].text(chinese: env.chinese) }
        }
        return text.failure(failure)
    }

    /// Every row of `proposal` (refused ones too, none for what is already so), and how many changes were already so.
    public static func check(_ proposal: Proposal, config: Config, environment env: Environment,
                             droppedKey: (dropped: Bool, provider: Provider?) = (false, nil)) -> (rows: [Row], unchanged: Int) {
        let text = Text(chinese: env.chinese)
        var working = config
        var rows: [Row] = []
        let order = Setting.allCases
        let sorted = proposal.changes.enumerated().sorted { a, b in
            func rank(_ key: Key) -> Int {
                switch key {
                case let .setting(setting): return order.firstIndex(of: setting) ?? 0
                case .app: return order.count
                case .forbidden: return order.count + 1
                }
            }
            return (rank(a.element.key), a.offset) < (rank(b.element.key), b.offset)
        }.map(\.element)
        var unchanged = 0
        for change in sorted {
            guard let row = check(change, in: working, env: env, text: text) else {
                unchanged += 1
                continue
            }
            if let edit = row.edit { apply([edit], to: &working) }
            rows.append(row)
        }
        // A provider that needs a key it hasn't got: a row that opens Settings at its key field. Also when a key typed into
        // the sentence was dropped.
        let wanted = droppedKey.provider ?? (working.provider != config.provider ? working.provider : nil)
            ?? (droppedKey.dropped ? config.provider : nil)
        if let provider = wanted, [.anthropic, .gemini, .openai, .hosted].contains(provider),
           !env.hasKey(provider) || droppedKey.dropped {
            rows.append(Row(key: "\(provider.rawValue).apiKey", label: text.keyLabel(provider), new: text.enterKey(provider),
                            status: .needsKey(provider)))
        }
        return (rows, unchanged)
    }

    /// The row for `change` in `config` (as the changes before it left it); nil when it changes nothing.
    static func check(_ change: Change, in config: Config, env: Environment, text: Text) -> Row? {
        switch change.key {
        case let .forbidden(path, secret):
            // A secret's value is never shown, nor anything about it.
            return Row(key: path, label: secret ? text.keyLabel(nil) : path,
                       status: .refused(secret ? text.secretRefused : text.notHere))
        case let .setting(setting):
            return checkSetting(setting, change.value, in: config, env: env, text: text)
        case let .app(name, field):
            return checkApp(name, field, change.value, in: config, env: env, text: text)
        }
    }

    private static func checkSetting(_ setting: Setting, _ value: JSONValue, in config: Config, env: Environment, text: Text) -> Row? {
        let label = text.label(setting)
        func refused(_ reason: String) -> Row { Row(key: setting.path, label: label, status: .refused(reason)) }
        func row(_ old: String, _ new: String, _ edit: Edit) -> Row? {
            Row(key: setting.path, label: label, old: old, new: new, status: .change, edit: edit)
        }
        if setting.isFlag {
            guard case let .bool(on) = value else { return refused(text.notValid) }
            let before = flag(setting, in: config)
            return on == before ? nil : row(text.onOff(before), text.onOff(on), .flag(setting, on))
        }
        switch setting {
        case .outputLanguages:
            guard let codes = value.strings else { return refused(text.notValid) }
            var languages: [OutputLanguage] = []
            for code in codes {
                guard let language = outputLanguage(code) else { return refused(text.unknownLanguage(code)) }
                if !languages.contains(language) { languages.append(language) }
            }
            guard !languages.isEmpty else { return refused(text.atLeastOne) }
            guard languages.count <= maxOutputLanguages else { return refused(text.tooMany(maxOutputLanguages)) }
            guard languages != config.outputLanguages else { return nil }
            return row(text.outputs(config.outputLanguages), text.outputs(languages), .outputLanguages(languages))
        case .inputLanguages:
            guard let codes = value.strings else { return refused(text.notValid) }
            var languages: [Language] = []
            for code in codes {
                guard let language = inputLanguage(code) else { return refused(text.unknownLanguage(code)) }
                if !languages.contains(language) { languages.append(language) }
            }
            guard !languages.isEmpty else { return refused(text.atLeastOne) }
            guard languages.count <= Config.maxInputLanguages else { return refused(text.tooMany(Config.maxInputLanguages)) }
            // A language whose pack isn't here: Settings downloads it first; here it is refused, pointing there.
            if let missing = languages.first(where: {
                !config.inputLanguages.contains($0) && LanguagePack.for($0) != nil && !env.packInstalled($0)
            }) {
                return refused(text.needsPack(missing))
            }
            guard languages != config.inputLanguages else { return nil }
            return row(text.inputs(config.inputLanguages), text.inputs(languages), .inputLanguages(languages))
        case .defaultInput:
            guard case let .string(code) = value else { return refused(text.notValid) }
            guard let language = inputLanguage(code) else { return refused(text.unknownLanguage(code)) }
            guard config.inputLanguages.contains(language) else { return refused(text.notAnInputLanguage(language)) }
            guard language != config.defaultInput else { return nil }
            return row(text.input(config.defaultInput), text.input(language), .defaultInput(language))
        case .rewriteStyles:
            guard let names = styleNames(value) else { return refused(text.notValid) }
            switch names {
            case let .failure(error): return refused(text.unknownStyle(error.name))
            case let .success(names):
                guard names != RewriteStyle.resolve(config.rewriteStyles).map(\.name) else { return nil }
                return row(text.styles(config.rewriteStyles), text.styles(names), .rewriteStyles(names))
            }
        case .candidateLayout:
            guard case let .string(name) = value, let layout = CandidateArrangement(rawValue: name.lowercased()) else {
                return refused(text.notValid)
            }
            return layout == config.candidateLayout ? nil : row(text.layout(config.candidateLayout), text.layout(layout), .candidateLayout(layout))
        case .typeOutRate:
            guard case let .number(rate) = value else { return refused(text.notValid) }
            guard rate >= TypeOut.slowestRate * 0.999, rate <= TypeOut.fastestRate else { return refused(text.outOfRange) }
            let rounded = roundedRate(rate)
            return rounded == config.typeOutRate ? nil : row(text.rate(config.typeOutRate), text.rate(rounded), .typeOutRate(rounded))
        case .redactionWordsAdd:
            guard let words = value.strings else { return refused(text.notValid) }
            let have = Set(config.redaction.customWords.map { $0.lowercased() })
            var seen = Set<String>()
            let new = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !have.contains($0.lowercased()) && seen.insert($0.lowercased()).inserted }
            guard !new.isEmpty else { return nil }
            return row(text.wordCount(config.redaction.customWords.count), text.added(new), .addWords(new))
        case .provider:
            guard case let .string(name) = value, let provider = Provider(rawValue: name.lowercased()) else {
                return refused(text.notValid)
            }
            guard env.offeredProviders.contains(provider) else { return refused(text.notOffered) }
            return provider == config.provider ? nil
                : row(text.provider(config.provider), text.provider(provider), .provider(provider))
        case .awsProfile:
            guard case let .string(name) = value, !name.isEmpty else { return refused(text.notValid) }
            guard env.awsProfiles().contains(name) else { return refused(text.unknownProfile) }
            return name == config.awsProfile ? nil : row(config.awsProfile, name, .awsProfile(name))
        case .region:
            var region: String?
            switch value {
            case .null: region = nil
            case let .string(name): region = name.isEmpty ? nil : name.lowercased()
            default: return refused(text.notValid)
            }
            if let region, !regions.contains(region) { return refused(text.unknownRegion) }
            return region == config.region ? nil : row(config.region ?? text.profileRegion, region ?? text.profileRegion, .region(region))
        case .modelId, .anthropicModel, .geminiModel, .openaiModel:
            let provider = setting.modelProvider!
            guard case let .string(id) = value, !id.isEmpty else { return refused(text.notValid) }
            guard env.knownModels(provider).contains(id) else { return refused(text.unknownModel) }
            let current = config.settings(for: provider).model
            return id == current ? nil : row(current ?? text.byDefault, id, .model(provider, id))
        case .openaiBaseURL:
            var url: String?
            switch value {
            case .null: url = nil
            case let .string(text): url = text.isEmpty ? nil : text
            default: return refused(text.notValid)
            }
            if let url {
                guard let parsed = URL(string: url), parsed.scheme?.lowercased() == "https", parsed.host?.isEmpty == false,
                      parsed.user == nil, parsed.password == nil else { return refused(text.httpsOnly) }
            }
            let current = config.openai.baseURL
            return url == current ? nil : row(current ?? text.byDefault, url ?? text.byDefault, .baseURL(url))
        default:
            return refused(text.notValid)
        }
    }

    private static func checkApp(_ name: String, _ field: AppField, _ value: JSONValue, in config: Config, env: Environment,
                                 text: Text) -> Row? {
        let path = "appProfiles.\(name).\(field.rawValue)"
        let bundleID: String, appName: String
        // An app that already has settings of its own is found by its key as well.
        let profiled = AppCatalog(apps: config.appProfiles.keys.map { AppCatalog.App(bundleID: $0, names: [$0]) })
        switch env.apps.resolve(name) {
        case let .found(id, shown): (bundleID, appName) = (id, shown)
        case let .ambiguous(names):
            return Row(key: path, label: text.appLabel(name, field), status: .refused(text.ambiguousApp(names)))
        case .none:
            guard case let .found(id, _) = profiled.resolve(name) else {
                return Row(key: path, label: text.appLabel(name, field), status: .refused(text.unknownApp))
            }
            (bundleID, appName) = (id, name)
        }
        let key = config.profileKey(for: bundleID) ?? bundleID
        let label = text.appLabel(appName, field)
        let resolved = "appProfiles.\(key).\(field.rawValue)"
        func refused(_ reason: String) -> Row { Row(key: resolved, label: label, status: .refused(reason)) }
        let profile = config.profile(for: bundleID) ?? AppProfile()
        func row(_ old: String, _ new: String, _ edit: AppValue) -> Row {
            Row(key: resolved, label: label, old: old, new: new, status: .change, edit: .app(key, edit))
        }
        switch field {
        case .inputLanguage:
            var language: Language?
            switch value {
            case .null: language = nil
            case let .string(code):
                guard let found = inputLanguage(code) else { return refused(text.unknownLanguage(code)) }
                language = found
            default: return refused(text.notValid)
            }
            // As in Settings → Apps: one of the input languages added.
            if let language, !config.inputLanguages.contains(language) { return refused(text.notAnInputLanguage(language)) }
            guard language != profile.inputLanguage else { return nil }
            return row(text.appInput(profile.inputLanguage), text.appInput(language), .inputLanguage(language))
        case .rewriteStyles:
            var names: [String]?
            if value != .null {
                switch styleNames(value) {
                case nil: return refused(text.notValid)
                case let .failure(error)?: return refused(text.unknownStyle(error.name))
                case let .success(found)?: names = found
                }
            }
            guard names != profile.rewriteStyles.map({ RewriteStyle.resolve($0).map(\.name) }) else { return nil }
            return row(text.appStyles(profile.rewriteStyles), text.appStyles(names), .rewriteStyles(names))
        case .typeOut, .noAI:
            var on: Bool?
            switch value {
            case .null: on = nil
            case let .bool(flag): on = flag
            default: return refused(text.notValid)
            }
            if field == .noAI {
                if on == false { on = nil }  // as the switch in Settings: off is "not set"
                guard on != profile.noAI else { return nil }
                return row(text.onOff(profile.noAI == true), text.onOff(on == true), .noAI(on))
            }
            guard on != profile.typeOut else { return nil }
            return row(text.appFlag(profile.typeOut), text.appFlag(on), .typeOut(on))
        }
    }

    /// An output language by its code ("fr", "zh-Hant", case aside).
    static func outputLanguage(_ code: String) -> OutputLanguage? {
        OutputLanguage.catalog.first { $0.code.caseInsensitiveCompare(code.trimmingCharacters(in: .whitespaces)) == .orderedSame }
    }

    static func inputLanguage(_ code: String) -> Language? { Language(rawValue: code.lowercased().trimmingCharacters(in: .whitespaces)) }

    /// Style names from the answer, as the config keeps them ("简洁"), each once; nil if it isn't a list of strings, the
    /// first unknown name as the failure.
    static func styleNames(_ value: JSONValue) -> Result<[String], StyleError>? {
        guard let names = value.strings else { return nil }
        var out: [String] = []
        for name in names {
            guard let style = RewriteStyle.named(name) ?? RewriteStyle.catalog.first(where: {
                Text.englishStyle($0).caseInsensitiveCompare(name) == .orderedSame
            }) else { return .failure(StyleError(name: name)) }
            if !out.contains(style.name) { out.append(style.name) }
        }
        return .success(out)
    }

    struct StyleError: Error, Equatable { let name: String }

    /// A typing speed as the slider in Settings rounds it: whole characters a second, or whole (tenth) seconds each.
    static func roundedRate(_ rate: Double) -> Double {
        if rate >= 1 { return rate.rounded() }
        let seconds = 1 / rate
        return 1 / (seconds < 2 ? (seconds * 10).rounded() / 10 : seconds.rounded())
    }
}

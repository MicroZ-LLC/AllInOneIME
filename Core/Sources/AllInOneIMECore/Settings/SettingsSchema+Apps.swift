import Foundation

/// Per-app settings (`Config.appProfiles`) in the settings document: the apps with settings of their own, each with
/// them as its own fields, and an app added by its id (the apps typed in lately offered). What only the Mac's input
/// method does yet (results typed out, Translate as You Type always on) is the Mac's.
extension SettingsSchema {
    mutating func apps() -> [Field] {
        var fields: [Field] = []
        let store = store
        let added = addedApps
        added.apps.removeAll { app in config.profile(for: app) != nil }
        let apps = (Array(config.appProfiles.keys) + added.apps)
            .sorted { Self.appName($0).localizedCaseInsensitiveCompare(Self.appName($1)) == .orderedAscending }
        var list = Field(id: "apps.profiles", kind: .items, label: tr("按 App 设置", "Per-App Settings"),
                         help: tr("在不同的 App 里用不同的设置：比如 Slack 里用英文开始、改写得口语一些，邮件里改写得正式一些，某个 App 里完全不用 AI。没设的跟全局设置一样。",
                                  "Different settings in different apps: say Slack starts in English with casual rewrites, Mail rewrites formally, and one app gets no AI at all. Anything not set follows the settings for every app."))
        (list.actions, list.textActions) = ([SettingsAction.add], [SettingsAction.add])
        list.placeholder = platform == .windows ? tr("程序名，比如 notepad.exe", "Its program, e.g. notepad.exe") : "com.apple.Safari"
        let offered = recentApps.filter { app in
            config.profile(for: app) == nil && !added.apps.contains { $0.lowercased() == app.lowercased() }
        }
        if !offered.isEmpty { list.choices = offered.map { Choice($0, Self.appName($0)) } }
        list.items = apps.map { app in
            SettingsDocument.Item(id: app, title: Self.appName(app), detail: summary(config.profile(for: app) ?? AppProfile()),
                                  actions: [SettingsAction.remove], fields: appFields(app))
        }
        add(list, to: &fields)
        let platform = platform
        handlers[list.id] = { action in
            switch action.name {
            case SettingsAction.add:
                guard let app = action.value?.string.flatMap({ Self.appID($0, platform: platform) }) else {
                    return .failure(SettingsProblem(.badValue, field: action.field,
                                                    message: tr("写上 App 的程序名，不带空格", "Write the app's program name, without spaces")))
                }
                if store.config.profile(for: app) == nil, !added.apps.contains(where: { $0.lowercased() == app.lowercased() }) {
                    added.apps.append(app)
                }
                return .success(SettingsActionOutcome())
            case SettingsAction.remove:
                guard let app = action.item else { return .failure(SettingsService.unknown(action.field)) }
                added.apps.removeAll { $0.lowercased() == app.lowercased() }
                store.removeProfile(app)
                return store.saveError.map { .failure(SettingsProblem(.failed, field: action.field, message: $0)) }
                    ?? .success(SettingsActionOutcome())
            default:
                return .failure(SettingsProblem(.notChangeable, field: action.field, message: SettingsService.notChangeable))
            }
        }
        return fields
    }

    /// An app's own settings: where it starts, its rewrite styles, AI off; results typed out and Translate as You Type
    /// always on are the Mac's.
    mutating func appFields(_ app: String) -> [Field] {
        var fields: [Field] = []
        let store = store
        let added = addedApps
        let profile = config.profile(for: app) ?? AppProfile()
        /// A change of the app's profile; an app whose profile ends up setting nothing stays listed.
        func change(_ body: @escaping (inout AppProfile, JSON) -> Void) -> (JSON) throws -> Void {
            { value in
                if !added.apps.contains(where: { $0.lowercased() == app.lowercased() }) { added.apps.append(app) }
                store.changeProfile(app) { body(&$0, value) }
            }
        }
        let prefix = "apps." + app + "."
        let everywhere = Self.inputName(config.defaultInput)
        var starts = choice(prefix + "inputLanguage", tr("开始的输入语言", "Starts in"),
                            value: profile.inputLanguage.map { .string($0.rawValue) } ?? .null,
                            choices: [(Choice(nil, tr("跟全局一样（\(everywhere)）", "Same as everywhere (\(everywhere))")), nil)]
                                + config.inputLanguages.map { (Choice($0.rawValue, Self.inputName($0)), nil) })
        if let own = profile.inputLanguage, !config.inputLanguages.contains(own) {
            starts.choices?.append(Choice(value: .string(own.rawValue), label: Self.inputName(own), disabled: true))
        }
        add(starts, to: &fields, set: change { $0.inputLanguage = $1.string.flatMap(Language.init(rawValue:)) })
        let global = RewriteStyle.resolve(config.rewriteStyles)
        let globalNames = global.isEmpty ? tr("无", "None") : global.map(UIText.name).joined(separator: tr("、", ", "))
        add(toggle(prefix + "ownStyles", tr("自己的改写风格", "Rewrite styles of its own"),
                   profile.rewriteStyles == nil ? tr("跟全局一样（\(globalNames)）", "Same as everywhere (\(globalNames))") : nil,
                   profile.rewriteStyles != nil),
            to: &fields, set: change { profile, on in profile.rewriteStyles = Self.bool(on) ? global.map(\.name) : nil })
        if let own = profile.rewriteStyles {
            var styles = Field(id: prefix + "rewriteStyles", kind: .choices, label: tr("改写风格", "Rewrite styles"),
                               value: .array(own.map(JSON.string)))
            styles.choices = RewriteStyle.catalog.map { Choice($0.name, UIText.name($0), note: UIText.summary($0)) }
            add(styles, to: &fields, set: change { $0.rewriteStyles = Self.strings($1) })
        }
        let typed = config.typeOut ? tr("跟全局一样（开）", "Same as everywhere (on)") : tr("跟全局一样（关）", "Same as everywhere (off)")
        add(choice(prefix + "typeOut", tr("逐字上屏", "Type results out"), value: profile.typeOut.map(JSON.bool) ?? .null,
                   choices: [(Choice(value: .null, label: typed), nil), (Choice(value: .bool(true), label: tr("开", "On")), nil),
                             (Choice(value: .bool(false), label: tr("关", "Off")), nil)],
                   platforms: [.mac]),
            to: &fields, set: change { $0.typeOut = $1.bool })
        add(toggle(prefix + "noAI", tr("这个 App 里不用 AI", "No AI in this app"),
                   UIText.triggered(tr("@improve、@translate、@question、@agent 等不会发给 AI，打字和别的命令照常。",
                      "@improve, @translate, @question, @agent and the like send nothing to the AI; typing and the other commands work.")),
                   profile.noAI == true),
            to: &fields, set: change { $0.noAI = Self.bool($1) ? true : nil })
        add(toggle(prefix + "translateAlways", tr("总是边打边译", "Always Translate as You Type"), nil, profile.translateAlways == true,
                   platforms: [.mac]),
            to: &fields, set: change { $0.translateAlways = Self.bool($1) ? true : nil })
        // Suggestions (plugins' completions, coding mode's rows): off here, or as everywhere.
        let suggestions = config.suggestions != false ? tr("跟全局一样（开）", "Same as everywhere (on)") : tr("跟全局一样（关）", "Same as everywhere (off)")
        add(choice(prefix + "suggestions", tr("建议", "Suggestions"), value: profile.suggestions == false ? .bool(false) : .null,
                   choices: [(Choice(value: .null, label: suggestions), nil), (Choice(value: .bool(false), label: tr("关", "Off")), nil)]),
            to: &fields, set: change { $0.suggestions = $1.bool == false ? false : nil })
        return fields
    }

    /// What an app's settings change, in a line: "Starts in English · No AI".
    func summary(_ profile: AppProfile) -> String {
        var parts: [String] = []
        if let language = profile.inputLanguage {
            let name = Self.inputName(language)
            parts.append(tr("用\(name)开始", "Starts in \(name)"))
        }
        if let styles = profile.rewriteStyles {
            let names = RewriteStyle.resolve(styles).map(UIText.name)
            parts.append(tr("改写：", "Rewrites: ") + (names.isEmpty ? tr("无", "none") : names.joined(separator: tr("、", ", "))))
        }
        if platform == .mac, let typeOut = profile.typeOut {
            parts.append(typeOut ? tr("逐字上屏", "Typed out") : tr("不逐字上屏", "Not typed out"))
        }
        if profile.noAI == true { parts.append(tr("不用 AI", "No AI")) }
        if platform == .mac, profile.translateAlways == true { parts.append(tr("总是边打边译", "Always Translate as You Type")) }
        if profile.suggestions == false { parts.append(tr("不显示建议", "No suggestions")) }
        return parts.isEmpty ? tr("和全局设置一样", "Same as everywhere", key: "appProfile.sameAsEverywhere") : parts.joined(separator: " · ")
    }

    /// An input language as the settings name it, in the document's language: "中文（拼音）", "English".
    static func inputName(_ input: Language) -> String { SessionText.inputName(input, language: UIText.language) }

    /// An app as a person reads it: Windows' program name ("notepad.exe") or packaged app, a Mac app's bundle id.
    static func appName(_ app: String) -> String {
        app.lowercased().hasPrefix(windowsPrefix) ? String(app.dropFirst(windowsPrefix.count)) : app
    }

    static let windowsPrefix = "win:"

    /// The id an app typed in the window has, as the input method names it (wire protocol §4): on Windows "win:" and the
    /// program's file name in lower case ("Notepad.exe", or its path, → "win:notepad.exe"), or a packaged app's id; a
    /// Mac app's bundle id as it is. Nil when it can't be one (empty, or with spaces).
    static func appID(_ typed: String, platform: SettingsPlatform) -> String? {
        var app = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard platform == .windows else { return AppProfile.isBundleID(app) ? app : nil }
        if app.lowercased().hasPrefix(windowsPrefix) { app = String(app.dropFirst(windowsPrefix.count)) }
        if app.lowercased().hasSuffix(".exe") {
            app = String(app.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last ?? Substring(app)).lowercased()
        }
        guard !app.isEmpty, AppProfile.isBundleID(app) else { return nil }
        return windowsPrefix + app
    }
}

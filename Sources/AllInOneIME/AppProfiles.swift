import AllInOneIMECore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The apps last typed in, most recent first, for Settings → Apps' "Add App…" (bundle ids only, kept in this app's
/// defaults: `defaults delete com.aipinyin.inputmethod.AIPinyin recentApps` forgets them).
@MainActor
enum RecentApps {
    /// Where they're kept (the self-test leaves the user's alone).
    static var defaults = UserDefaults.standard
    static let key = "recentApps"
    static let limit = 12

    static var apps: [String] { defaults.stringArray(forKey: key) ?? [] }

    /// `app` first (not this input method's own windows); written only when it wasn't first already.
    static func record(_ app: String) {
        guard AppProfile.isBundleID(app), !app.hasPrefix("com.aipinyin."), apps.first != app else { return }
        defaults.set(Array(([app] + apps.filter { $0 != app }).prefix(limit)), forKey: key)
    }
}

/// An app's name and icon by its bundle id, from where macOS has it installed; one that isn't installed goes by its
/// bundle id, with the generic app icon.
@MainActor
enum AppNames {
    private static var names: [String: String] = [:]

    static func url(for app: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) }

    static func name(for app: String) -> String {
        if let name = names[app] { return name }
        var name = app
        if let url = url(for: app) {
            name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        }
        names[app] = name
        return name
    }

    /// The icon at `size` points (a copy: the workspace's own is shared).
    static func icon(for app: String, size: CGFloat = 16) -> NSImage {
        let icon = url(for: app).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application)
        let copy = (icon.copy() as? NSImage) ?? icon
        copy.size = NSSize(width: size, height: size)
        return copy
    }
}

/// Profiles for the settings page's images (`--settings-image`, the self-test) when there are none: apps any Mac has
/// (Mail, Terminal) and WeChat.
enum AppProfileSamples {
    static let profiles: [String: AppProfile] = [
        "com.apple.mail": AppProfile(rewriteStyles: ["正式", "委婉"]),
        "com.tencent.xinWeChat": AppProfile(inputLanguage: .chinese, rewriteStyles: ["口语"], typeOut: false),
        "com.apple.Terminal": AppProfile(inputLanguage: .english, noAI: true),
    ]
}

/// What the settings and the menu say about an app's profile.
@MainActor
enum AppProfileText {
    static func inputName(_ language: Language) -> String { SessionText.inputName(language, language: UIText.language) }

    /// An input as the settings name it: a language, or Code with `config`'s coding language ("Code (Python)").
    static func inputName(_ input: Input, _ config: Config) -> String {
        SessionText.inputName(input, language: UIText.language, coding: config.codingLanguage.map { CodingLanguagePack.title(of: $0) })
    }

    /// "Starts in English · Rewrites: Formal · Typed out · No AI"; "Same as everywhere" when it sets nothing. Code is named
    /// with `config`'s coding language.
    static func summary(_ profile: AppProfile, config: Config = LiveConfig.current) -> String {
        var parts: [String] = []
        if let input = profile.startingInput {
            let name = inputName(input, config)
            parts.append(tr("用\(name)开始", "Starts in \(name)"))
        }
        if let names = profile.rewriteStyles {
            let styles = RewriteStyle.resolve(names).map(UIText.name)
            parts.append(tr("改写：", "Rewrites: ") + (styles.isEmpty ? tr("无", "none") : styles.joined(separator: tr("、", ", "))))
        }
        if let typeOut = profile.typeOut { parts.append(typeOut ? tr("逐字上屏", "Typed out") : tr("不逐字上屏", "Not typed out")) }
        if profile.noAI == true { parts.append(tr("不用 AI", "No AI")) }
        if profile.translateAlways == true { parts.append(tr("总是边打边译", "Always Translate as You Type")) }
        if let autocomplete = profile.autocomplete { parts.append(autocomplete ? tr("总是续写", "Always autocomplete") : tr("不续写", "No autocomplete")) }
        if profile.suggestions == false { parts.append(tr("不显示建议", "No suggestions")) }
        return parts.isEmpty ? tr("和全局设置一样", "Same as everywhere", key: "appProfile.sameAsEverywhere") : parts.joined(separator: " · ")
    }

    /// The notice of an AI command refused in an app with no AI (`InputSession.aiRefusal`).
    static var refusal: String { InputSession.aiRefusal }

    /// 「跟全局一样（开）」, and where it stopped for want of use there, that it did; in a code editor, that it's off there
    /// unless set to always (`Autocomplete.isCodeEditor`).
    static func autocompleteEverywhere(_ config: Config, app: String) -> String {
        if Autocomplete.isCodeEditor(app) { return tr("默认（代码编辑器里关）", "Default (off in code editors)") }
        if config.autocomplete, AutocompleteSwitch.store.stopped(in: app) {
            return tr("跟全局一样（在这里没用上，已停）", "Same as everywhere (stopped here: not used)")
        }
        return config.autocomplete ? tr("跟全局一样（开）", "Same as everywhere (on)") : tr("跟全局一样（关）", "Same as everywhere (off)")
    }
}

extension SettingsModel {
    /// The apps with settings of their own, by name.
    var profiledApps: [String] {
        config.appProfiles.keys.sorted { AppNames.name(for: $0).localizedStandardCompare(AppNames.name(for: $1)) == .orderedAscending }
    }

    /// Changes the profile of `app` (added if it has none, under the key it has in another case if so) and saves. One
    /// that sets nothing stays in the list while the window is open, and isn't saved.
    func changeProfile(_ app: String, _ change: (inout AppProfile) -> Void) {
        store.changeProfile(app, change)
    }

    func removeProfile(_ app: String) {
        store.removeProfile(app)
    }
}

/// Settings → Apps: the apps with settings of their own, each with its icon and name and what it sets differently
/// (the input language a field starts in, the rewrite styles, typing out, no AI), and adding one: an app typed in
/// lately, or one picked in /Applications.
struct AppProfilesSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section {
            Text(tr("在不同的 App 里用不同的设置：比如 Slack 里用英文开始、改写得口语一些，邮件里改写得正式一些，某个 App 里完全不用 AI。没设的跟全局设置一样。",
                    "Different settings in different apps: say Slack starts in English with casual rewrites, Mail rewrites formally, and one app gets no AI at all. Anything not set follows the settings for every app."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            addMenu
        } header: {
            Text(tr("按 App 设置", "Per-App Settings")).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary).padding(.top, 6)
        }
        .disabled(!model.canSave)
        ForEach(model.profiledApps, id: \.self) { app in
            appSection(app)
        }
    }

    /// "Add App…": the apps typed in lately that have no settings yet, then picking one in /Applications.
    private var addMenu: some View {
        let recent = RecentApps.apps.filter { model.config.profileKey(for: $0) == nil }
        return HStack {
            Menu(tr("添加 App…", "Add App…")) {
                if !recent.isEmpty {
                    Section(tr("最近打过字的", "Typed in lately")) {
                        ForEach(recent, id: \.self) { app in
                            Button {
                                model.changeProfile(app) { _ in }
                            } label: {
                                Label { Text(AppNames.name(for: app)) } icon: { Image(nsImage: AppNames.icon(for: app)) }
                            }
                        }
                    }
                }
                Button(tr("从「应用程序」里选…", "Choose from Applications…")) { chooseApp() }
            }
            .fixedSize()
            Spacer()
        }
    }

    /// An app picked in /Applications, by its bundle id.
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = tr("添加", "Add")
        guard panel.runModal() == .OK, let url = panel.url, let app = Bundle(url: url)?.bundleIdentifier,
              AppProfile.isBundleID(app) else { return }
        model.changeProfile(app) { _ in }
    }

    private func profile(_ app: String) -> AppProfile { model.config.appProfiles[app] ?? AppProfile() }

    @ViewBuilder private func appSection(_ app: String) -> some View {
        let profile = profile(app)
        Section {
            HStack(spacing: 10) {
                Image(nsImage: AppNames.icon(for: app, size: 32)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppNames.name(for: app)).font(.body.weight(.medium))
                    Text(AppProfileText.summary(profile, config: model.config)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button(tr("移除", "Remove")) { model.removeProfile(app) }
            }
            // The inputs: the languages, then Code where it's among them (decision 22); one no longer there, as it is.
            Picker(tr("开始的输入语言", "Starts in"), selection: Binding(
                get: { profile.startingInput },
                set: { input in model.changeProfile(app) { $0.startingInput = input } })) {
                Text(tr("跟全局一样（\(AppProfileText.inputName(model.config.defaultInput))）",
                        "Same as everywhere (\(AppProfileText.inputName(model.config.defaultInput)))")).tag(Input?.none)
                ForEach(model.config.inputs + (profile.startingInput.map { model.config.inputs.contains($0) ? [] : [$0] } ?? []),
                        id: \.self) { input in
                    Text(AppProfileText.inputName(input, model.config)).tag(Input?.some(input))
                }
            }
            LabeledContent(tr("改写风格", "Rewrite styles")) { stylesMenu(app, profile) }
            Picker(tr("逐字上屏", "Type results out"), selection: Binding(
                get: { profile.typeOut },
                set: { value in model.changeProfile(app) { $0.typeOut = value } })) {
                Text(model.config.typeOut ? tr("跟全局一样（开）", "Same as everywhere (on)")
                     : tr("跟全局一样（关）", "Same as everywhere (off)")).tag(Bool?.none)
                Text(tr("开", "On")).tag(Bool?.some(true))
                Text(tr("关", "Off")).tag(Bool?.some(false))
            }
            Toggle(isOn: Binding(get: { profile.noAI == true },
                                 set: { on in model.changeProfile(app) { $0.noAI = on ? true : nil } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("这个 App 里不用 AI", "No AI in this app"))
                    Text(model.triggered(tr("@improve、@translate、@question、@agent 等不会发给 AI，打字和别的命令照常。",
                            "@improve, @translate, @question, @agent and the like send nothing to the AI; typing and the other commands work.")))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Picker(selection: Binding(
                get: { profile.autocomplete },
                set: { value in model.changeProfile(app) { $0.autocomplete = value } })) {
                Text(AppProfileText.autocompleteEverywhere(model.config, app: app)).tag(Bool?.none)
                Text(tr("总是续写", "Always", key: "autocomplete.always")).tag(Bool?.some(true))
                Text(tr("不续写", "Never", key: "autocomplete.never")).tag(Bool?.some(false))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("续写", "Autocomplete"))
                    Text(tr("停一下，光标后出现灰字，按 Tab 接受。「总是」在这里不管全局开关，也不会因为没用上而停下。代码编辑器（Xcode、VS Code、Cursor、JetBrains 等）里默认关，设成「总是」才开。",
                            "Pause, and the rest of the sentence shows in gray after the caret; Tab takes it. Always: here whatever the switch, and it doesn't stop for want of use. Off in code editors (Xcode, VS Code, Cursor, JetBrains…) unless set to Always."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    // Where the text goes, as under the main switch: Always sends it from this app whatever the switch.
                    if let destination = AutocompleteSwitch.destination(model.config) {
                        Text(destination).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // Suggestions as everywhere (the input menu's switch), or none in the app.
            Picker(selection: Binding(
                get: { profile.suggestions == false ? false : nil },
                set: { value in model.changeProfile(app) { $0.suggestions = value == false ? false : nil } })) {
                Text(model.config.suggestions != false ? tr("跟全局一样（开）", "Same as everywhere (on)")
                     : tr("跟全局一样（关）", "Same as everywhere (off)")).tag(Bool?.none)
                Text(tr("关", "Off")).tag(Bool?.some(false))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("建议", "Suggestions"))
                    Text(tr("插件的补全（比如 #12 → GitHub issue）和代码输入的关键字、代码片段，按 Tab 插入。关掉后这个 App 里不列出。",
                            "Plugins' completions (#12 → a GitHub issue, say) and Code's keywords and snippets, Tab inserts. Off: none in this app."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle(isOn: Binding(get: { profile.translateAlways == true },
                                 set: { on in model.changeProfile(app) { $0.translateAlways = on ? true : nil } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("总是边打边译", "Always Translate as You Type"))
                    Text(tr("切到这个 App 就打开边打边译（平时长按 Shift 开关）：⏎ 直接翻译成小标签上选的语言（还没选过时是所打语言能译成的第一种翻译语言）并上屏，⇧⏎ 原文上屏。",
                            "Translate as You Type comes on when you switch to this app (elsewhere a long press of Shift turns it on and off): ⏎ translates into the language picked on its chip (until you pick one, the first translation language the language you type can be translated into) and inserts it, ⇧⏎ inserts as typed."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .disabled(!model.canSave)
    }

    /// The rewrite styles @improve offers in the app: the global ones, or its own (checked in the menu).
    private func stylesMenu(_ app: String, _ profile: AppProfile) -> some View {
        let own = profile.rewriteStyles.map { RewriteStyle.resolve($0) }
        let shown = (own ?? RewriteStyle.resolve(model.config.rewriteStyles)).map(UIText.name).joined(separator: tr("、", ", "))
        let label = own == nil ? tr("跟全局一样（\(shown)）", "Same as everywhere (\(shown))") : shown.isEmpty ? tr("无", "None") : shown
        return Menu(label) {
            Button(tr("跟全局一样", "Same as everywhere")) { model.changeProfile(app) { $0.rewriteStyles = nil } }
            Divider()
            ForEach(RewriteStyle.catalog, id: \.tag) { style in
                Toggle(UIText.name(style), isOn: Binding(
                    get: { (own ?? RewriteStyle.resolve(model.config.rewriteStyles)).contains(style) },
                    set: { _ in
                        model.changeProfile(app) {
                            $0.rewriteStyles = SessionText.toggled(style.name, in: $0.rewriteStyles ?? model.config.rewriteStyles)
                        }
                    }))
            }
        }
        .fixedSize()
    }
}

// MARK: - The input menu

extension AllInOneIMEInputController {
    /// "This App: Slack": no AI, typing out, autocomplete (with where its text goes, as under the main switch) and the
    /// input language a field starts in, for the app being typed in (`AppProfile`), and its page in the settings. Nil
    /// without an app.
    @MainActor
    func appMenuItem(config: Config?, app: String?) -> NSMenuItem? {
        guard let app, AppProfile.isBundleID(app) else { return nil }
        let current = config ?? .default
        let profile = current.profile(for: app) ?? AppProfile()
        let item = NSMenuItem(title: tr("这个 App：", "This App: ") + AppNames.name(for: app), action: nil, keyEquivalent: "")
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, value: String = "", on: Bool) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            entry.representedObject = ["app": app, "value": value]
            entry.state = on ? .on : .off
            entry.isEnabled = config != nil  // don't overwrite a config file that failed to parse
            menu.addItem(entry)
        }
        add(tr("不用 AI", "No AI"), #selector(toggleAppNoAI(_:)), on: profile.noAI == true)
        add(tr("逐字上屏", "Type Results Out"), #selector(toggleAppTypeOut(_:)), on: current.applying(app: app).typeOut)
        menu.addItem(.separator())
        let continues = NSMenuItem(title: tr("续写：", "Autocomplete:"), action: nil, keyEquivalent: "")
        continues.isEnabled = false
        menu.addItem(continues)
        add(AppProfileText.autocompleteEverywhere(current, app: app), #selector(setAppAutocomplete(_:)), on: profile.autocomplete == nil)
        add(tr("总是续写", "Always", key: "autocomplete.always"), #selector(setAppAutocomplete(_:)), value: "on", on: profile.autocomplete == true)
        add(tr("不续写", "Never", key: "autocomplete.never"), #selector(setAppAutocomplete(_:)), value: "off", on: profile.autocomplete == false)
        // Where the text goes, as under the main switch: Always sends it from this app whatever the switch.
        if let line = AutocompleteSwitch.destinationItem(current) { menu.addItem(line) }
        menu.addItem(.separator())
        let note = NSMenuItem(title: tr("开始的输入语言：", "Starts In:"), action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
        let everywhere = AppProfileText.inputName(current.defaultInput)
        add(tr("跟全局一样（\(everywhere)）", "Same as Everywhere (\(everywhere))"),
            #selector(setAppInput(_:)), on: profile.startingInput == nil)
        for input in current.inputs {
            add(AppProfileText.inputName(input, current), #selector(setAppInput(_:)), value: input.rawValue, on: profile.startingInput == input)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: tr("按 App 设置…", "Per-App Settings…"), action: #selector(showAppSettings(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        item.submenu = menu
        return item
    }

    /// Changes the profile of the menu item's app in the config file, only that (`Config.change`); one left setting
    /// nothing is removed. The field takes it at once (its starting language too).
    @MainActor
    private func changeAppProfile(_ sender: Any?, _ what: String, _ change: (inout AppProfile, Config, String) -> Void) {
        guard let info = Self.menuItem(from: sender)?.representedObject as? [String: String], let app = info["app"] else {
            log.error("app menu action without an app")
            return
        }
        do {
            let config = try Config.change { config in
                let before = config  // what the change reads (typing out everywhere)
                config.changeProfile(for: app, dropsEmpty: true) { change(&$0, before, info["value"] ?? "") }
            }
            NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
            log.notice("app profile changed: \(what, privacy: .public) (\(config.appProfiles.count) apps with their own settings)")
            applySettings()
        } catch {
            log.error("could not update the app's settings: \(String(describing: error), privacy: .public)")
        }
    }

    @objc func toggleAppNoAI(_ sender: Any?) {
        MainActor.assumeIsolated {
            changeAppProfile(sender, "no AI") { profile, _, _ in profile.noAI = profile.noAI == true ? nil : true }
        }
    }

    /// Typing out the other way from now; the same as everywhere again, it's no longer set for the app.
    @objc func toggleAppTypeOut(_ sender: Any?) {
        MainActor.assumeIsolated {
            changeAppProfile(sender, "type out") { profile, config, _ in
                let now = !(profile.typeOut ?? config.typeOut)
                profile.typeOut = now == config.typeOut ? nil : now
            }
        }
    }

    /// Autocomplete in the app always, never, or as everywhere.
    @objc func setAppAutocomplete(_ sender: Any?) {
        MainActor.assumeIsolated {
            changeAppProfile(sender, "autocomplete") { profile, _, value in
                profile.autocomplete = value == "on" ? true : value == "off" ? false : nil
            }
        }
    }

    @objc func setAppInput(_ sender: Any?) {
        MainActor.assumeIsolated {
            changeAppProfile(sender, "starting input") { profile, _, value in profile.startingInput = Input(rawValue: value) }
        }
    }

    @objc func showAppSettings(_ sender: Any?) {
        MainActor.assumeIsolated {
            perform(composer.commitAll(), client: nil)  // the window takes focus from the text field
            openSettings(.apps, nil)
        }
    }
}

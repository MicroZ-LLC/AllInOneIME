import AllInOneIMECore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The apps last typed in, most recent first, for the "Add App…" of Settings' lists of apps (Insert's, Apps without AI;
/// bundle ids only, kept in this app's defaults: `defaults delete com.aipinyin.inputmethod.AIPinyin recentApps` forgets
/// them).
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

/// Profiles for the settings pages' images (`--settings-image`, the self-test) when there are none: apps any Mac has
/// (Mail, Terminal) and WeChat. Mail inserts with title and link, Terminal has no AI; WeChat and Mail keep settings of
/// an earlier version (where they start, their rewrite styles, typing out).
enum AppProfileSamples {
    static let profiles: [String: AppProfile] = [
        "com.apple.mail": AppProfile(rewriteStyles: ["正式", "委婉"], suggestionsInsert: .titleAndLink),
        "com.tencent.xinWeChat": AppProfile(inputLanguage: .chinese, typeOut: false),
        "com.apple.Terminal": AppProfile(noAI: true),
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

    /// 「跟全局一样（带标题）」: what a suggestion row inserts in an app without its own choice (decision 28).
    static func insertEverywhere(_ config: Config) -> String {
        let label = config.suggestionsInsert.map(\.label) ?? tr("默认", "Default")
        return tr("跟全局一样（\(label)）", "Same as everywhere (\(label))")
    }

    /// The notice of an AI command refused in an app with no AI (`InputSession.aiRefusal`).
    static var refusal: String { InputSession.aiRefusal }
}

extension SettingsModel {
    /// The apps whose profile `has` it, by name.
    func appsWith(_ has: (AppProfile) -> Bool) -> [String] {
        config.appProfiles.filter { has($0.value) }.keys
            .sorted { AppNames.name(for: $0).localizedStandardCompare(AppNames.name(for: $1)) == .orderedAscending }
    }

    /// Changes the profile of `app` (added if it has none, under the key it has in another case if so) and saves. One
    /// that sets nothing isn't saved.
    func changeProfile(_ app: String, _ change: (inout AppProfile) -> Void) {
        store.changeProfile(app, change)
    }

    /// General → "Previous per-app settings": a row for each app whose profile still sets one of what no setting sets
    /// any more (`Config.previousAppSettings`), apps by name.
    var previousAppSettings: [PreviousAppSettings] { config.previousAppSettings(appName: AppNames.name) }

    /// "Previous per-app settings" → Remove: those of `app` cleared, its Insert (an insert, or Off) and No AI kept
    /// (`Config.removePreviousAppSettings`).
    func removePreviousSettings(_ app: String) {
        config.removePreviousAppSettings(for: app)
        save()
    }
}

/// An app as the lists show it: its icon and name.
struct AppLabel: View {
    let app: String

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppNames.icon(for: app, size: 20)).accessibilityHidden(true)
            Text(AppNames.name(for: app))
        }
    }
}

/// "Add App…" of a list of apps: the apps typed in lately that aren't in it (`has`), then one picked in /Applications.
struct AddAppMenu: View {
    @ObservedObject var model: SettingsModel
    /// Whether an app's profile already puts it in the list.
    let has: (AppProfile) -> Bool
    let add: (String) -> Void

    var body: some View {
        let recent = RecentApps.apps.filter { app in !(model.config.profile(for: app).map(has) ?? false) }
        Menu(tr("添加 App…", "Add App…")) {
            if !recent.isEmpty {
                Section(tr("最近打过字的", "Typed in lately")) {
                    ForEach(recent, id: \.self) { app in
                        Button {
                            add(app)
                        } label: {
                            Label { Text(AppNames.name(for: app)) } icon: { Image(nsImage: AppNames.icon(for: app)) }
                        }
                    }
                }
            }
            Button(tr("从「应用程序」里选…", "Choose from Applications…")) { chooseApp() }
        }
        .fixedSize()
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
        add(app)
    }
}

/// Privacy → Apps without AI (`AppProfile.noAI`): the apps, each with Remove (its other settings untouched), and Add
/// App….
struct AppsWithoutAISection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let apps = model.appsWith { $0.noAI == true }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsSpot.appsWithoutAI.title)
                    Text(SettingsSpot.appsWithoutAI.note ?? "").font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                AddAppMenu(model: model, has: { $0.noAI == true }) { app in model.changeProfile(app) { $0.noAI = true } }
            }
            ForEach(apps, id: \.self) { app in
                HStack {
                    AppLabel(app: app)
                    Spacer()
                    Button(tr("移除", "Remove")) { model.changeProfile(app) { $0.noAI = nil } }
                }
                .padding(.leading, 4)
            }
        }
        .settingsRow(.appsWithoutAI, shown: model.spot)
    }
}

/// General → "Previous per-app settings" (Settings v2, 2): only while an app's profile sets one of what no setting sets
/// any more (`Config.previousAppSettings`), a row per app saying what it sets ("Slack: starts in English, Always
/// Translate as You Type"), and Remove, which clears those of that app (its Insert and No AI untouched). Each is honored
/// until then: an "always autocomplete" sends text from the app even with autocomplete off, so it is listed here, never
/// kept out of sight.
struct PreviousAppSettingsSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let rows = model.previousAppSettings
        if !rows.isEmpty {
            Section {
                ForEach(rows, id: \.app) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Image(nsImage: AppNames.icon(for: row.app, size: 20)).accessibilityHidden(true)
                        Text(row.text).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(tr("移除", "Remove")) { model.removePreviousSettings(row.app) }
                    }
                }
            } header: {
                SectionTitle(SettingsSpot.previousAppSettings.title, icon: CandidateView.Icon(symbol: "square.grid.2x2.fill", color: .systemIndigo))
                    .settingsRow(.previousAppSettings, shown: model.spot)
            } footer: {
                Text(SettingsSpot.previousNote).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
            }
            .disabled(!model.canSave)
        }
    }
}

// MARK: - The input menu

extension AllInOneIMEInputController {
    /// "This App: Slack", for the app being typed in: the input it learned to start in (Settings v2, 3.1), with Forget;
    /// then its two settings (Settings v2, 4, `AppProfile`): No AI, and, where there is a suggestion source (a plugin's
    /// turned on, a custom command), what a suggestion row inserts there (decision 28), or Off, no suggestions there
    /// (`AppProfile.insertChoice`, as General's "In these apps"). Nothing sets where it starts. Nil without an app.
    @MainActor
    func appMenuItem(config: Config?, app: String?) -> NSMenuItem? {
        guard let app, AppProfile.isBundleID(app) else { return nil }
        let current = config ?? .default
        let profile = current.profile(for: app) ?? AppProfile()
        let item = NSMenuItem(title: tr("这个 App：", "This App: ") + AppNames.name(for: app), action: nil, keyEquivalent: "")
        let menu = NSMenu()
        // Learned on this Mac, not a setting (`LearnedShared`): Forget is Privacy → Learned…'s, for this app.
        if let learned = LearnedShared.store.startingInput(in: app) {
            let name = AppProfileText.inputName(learned, current)
            let starts = NSMenuItem(title: tr("用\(name)开始（学到的）", "Starts in \(name) (learned)"), action: nil, keyEquivalent: "")
            starts.isEnabled = false
            menu.addItem(starts)
            let forget = NSMenuItem(title: tr("忘掉", "Forget"), action: #selector(forgetAppStartingInput(_:)), keyEquivalent: "")
            forget.target = self
            forget.representedObject = ["app": app, "value": learned.rawValue]
            menu.addItem(forget)
            menu.addItem(.separator())
        }
        func add(_ title: String, _ action: Selector?, value: String = "", on: Bool) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            entry.representedObject = ["app": app, "value": value]
            entry.state = on ? .on : .off
            entry.isEnabled = config != nil && action != nil  // don't overwrite a config file that failed to parse
            menu.addItem(entry)
        }
        add(tr("不用 AI", "No AI"), #selector(toggleAppNoAI(_:)), on: profile.noAI == true)
        // A source approved, a custom command that is one, or a script extension's (on by default, 0.6.7.2).
        if !current.completionSources.isEmpty || current.customCommands.contains(where: { $0.type == .suggestions })
            || LiveExtensions.current(current).commands.contains(where: { if case .success? = $0.completion { return true } else { return false } }) {
            menu.addItem(.separator())
            let inserts = NSMenuItem(title: tr("建议插入：", "Suggestions Insert:"), action: nil, keyEquivalent: "")
            inserts.isEnabled = false
            menu.addItem(inserts)
            let own = profile.insertChoice
            add(AppProfileText.insertEverywhere(current), #selector(setAppSuggestionsInsert(_:)), on: own == nil)
            for choice in AppInsertChoice.offered {
                add(choice.label, #selector(setAppSuggestionsInsert(_:)), value: choice.rawValue, on: own == choice)
            }
            // One that can't be chosen any more ("ID only"), kept in the config: shown checked, Same as Everywhere undoes it.
            if let own, !AppInsertChoice.offered.contains(own) {
                add(own.label, nil, on: true)
            }
        }
        item.submenu = menu
        return item
    }

    /// Changes the profile of the menu item's app in the config file, only that (`Config.change`); one left setting
    /// nothing is removed. The field takes it at once.
    @MainActor
    private func changeAppProfile(_ sender: Any?, _ what: String, _ change: (inout AppProfile, String) -> Void) {
        guard let info = Self.menuItem(from: sender)?.representedObject as? [String: String], let app = info["app"] else {
            log.error("app menu action without an app")
            return
        }
        do {
            let config = try Config.change { config in
                config.changeProfile(for: app, dropsEmpty: true) { change(&$0, info["value"] ?? "") }
            }
            NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
            log.notice("app profile changed: \(what, privacy: .public) (\(config.appProfiles.count) apps with their own settings)")
            applySettings()
        } catch {
            log.error("could not update the app's settings: \(String(describing: error), privacy: .public)")
        }
    }

    /// Forgets the input the menu item's app learned to start in (with its streak): its next fields start in its own
    /// starting input, else the default one, until it learns one again. The field being typed in stays as it is.
    @objc func forgetAppStartingInput(_ sender: Any?) {
        MainActor.assumeIsolated {
            guard let info = Self.menuItem(from: sender)?.representedObject as? [String: String], let app = info["app"],
                  let input = info["value"].flatMap(Input.init(rawValue:)) else {
                log.error("app menu action without an app's learned starting input")
                return
            }
            LearnedShared.store.forget(LearnedItem(kind: .startingInput(app: app, input: input)))
            log.notice("an app's learned starting input forgotten")
        }
    }

    @objc func toggleAppNoAI(_ sender: Any?) {
        MainActor.assumeIsolated {
            changeAppProfile(sender, "no AI") { profile, _ in profile.noAI = profile.noAI == true ? nil : true }
        }
    }

    /// What a suggestion row inserts in the app: its own choice, Off (no suggestions there), or as everywhere (none:
    /// both cleared), as "In these apps" sets it (`AppProfile.insertChoice`).
    @objc func setAppSuggestionsInsert(_ sender: Any?) {
        MainActor.assumeIsolated {
            changeAppProfile(sender, "suggestions insert") { profile, value in profile.insertChoice = AppInsertChoice(rawValue: value) }
        }
    }
}

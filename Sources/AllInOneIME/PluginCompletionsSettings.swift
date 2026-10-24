import AllInOneIMECore
import SwiftUI

// Settings → Plugins: each plugin's completion sources (suggestions: rows as you type a token like #12, Tab inserts) and
// its preferences, under its row (spec suggestions v1, 1.5 and 3).

extension SettingsModel {
    /// `source` of `plugin` turned on (enabling what it is now: the plugin's hosts, whether it queries, its script, its
    /// prefix and when its query is first asked) or off, and saved; the field being typed in takes it at once (one turned
    /// off is forgotten, its cached list deleted).
    func setCompletionSource(_ source: CompletionSource, of plugin: InstalledPlugin, enabled: Bool) {
        config.setCompletionSource(source, of: plugin, enabled: enabled)
        save()
        if store.persists { SuggestionsShared.settingsChanged() }
    }

    /// "Refresh Now": the source's list loaded again at once, paused or not.
    func refreshNow(_ source: CompletionSource, of plugin: InstalledPlugin) {
        guard store.persists else { return }
        SuggestionsShared.refreshNow(plugin: plugin.name, source: source.name)
    }

    /// Suggestions on or off everywhere, as the input menu's "Suggestions" switches them (on is the default, written as
    /// none).
    func setSuggestions(_ on: Bool) {
        config.suggestions = on ? nil : false
        save()
        if store.persists { SuggestionsShared.settingsChanged() }
    }

    /// What a suggestion row inserts everywhere (decision 28; nil: the source's own), and saved; the field being typed in
    /// takes it with its next key.
    func setSuggestionsInsert(_ insert: SuggestionsInsert?) {
        config.suggestionsInsert = insert == .source ? nil : insert
        save()
    }

    /// A plugin's text preference as saved, else its default.
    func pluginPreference(_ plugin: InstalledPlugin, _ preference: PluginPreference) -> String {
        config.pluginPreferences[plugin.name]?[preference.name] ?? preference.defaultValue ?? ""
    }

    /// Saves a plugin's preference: a password in the keychain, as an extension's is (an empty one does nothing:
    /// `removePluginPassword` removes it), a text in the config file (an empty one goes: the default applies). The
    /// plugin's lists that are on load again with it. What went wrong (nil: nothing).
    func setPluginPreference(_ plugin: InstalledPlugin, _ preference: PluginPreference, _ value: String) -> String? {
        guard store.persists else { return nil }
        if preference.kind == .password {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            do {
                try APIKeys.save(value, account: PluginPreference.keychainAccount(plugin: plugin.name, name: preference.name),
                                 label: "AllInOneIME: \(plugin.name) – \(preference.title.text(chinese: UIText.chinese))")
            } catch {
                return tr("没有存进钥匙串：", "Couldn't save it in the keychain: ") + error.localizedDescription
            }
        } else {
            var values = config.pluginPreferences[plugin.name] ?? [:]
            values[preference.name] = value.isEmpty ? nil : value
            config.pluginPreferences[plugin.name] = values.isEmpty ? nil : values
            save()
        }
        reloadLists(of: plugin)
        return nil
    }

    /// Removes a plugin's password preference from the keychain: Remove…, confirmed. What went wrong (nil: nothing).
    func removePluginPassword(_ plugin: InstalledPlugin, _ preference: PluginPreference) -> String? {
        guard store.persists, preference.kind == .password else { return nil }
        do {
            try APIKeys.remove(account: PluginPreference.keychainAccount(plugin: plugin.name, name: preference.name))
        } catch {
            return tr("没能从钥匙串里删除：", "Couldn't remove it from the keychain: ", key: "extensionKey.removeFailed")
                + error.localizedDescription
        }
        reloadLists(of: plugin)
        return nil
    }

    /// The lists of `plugin`'s sources that are on, loaded again (a preference changed: another repository, a token).
    private func reloadLists(of plugin: InstalledPlugin) {
        for source in plugin.manifest.completions where source.list && config.approval(of: source, in: plugin) != nil {
            SuggestionsShared.refreshNow(plugin: plugin.name, source: source.name)
        }
    }
}

/// What a suggestion row inserts everywhere (decision 28), in Settings → Plugins: the source's own (a plugin's `insert`, a
/// custom command's Insert), ID only, with title, with title and link; for every source, plugins' and custom commands',
/// never Code's. An app's own is in Apps.
struct SuggestionsInsertPicker: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Picker(selection: Binding(get: { model.config.suggestionsInsert ?? .source }, set: { model.setSuggestionsInsert($0) })) {
            ForEach(SuggestionsInsert.allCases, id: \.self) { insert in Text(insert.label).tag(insert) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("插入", "Insert"))
                Text(SuggestionsInsert.help).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A plugin's suggestions and preferences, under its row in Settings → Plugins: each completion source with its switch
/// (off until turned on here), what it does and, for one that queries, what it sends where; how it is doing (its items,
/// when its list was loaded, its last error) and Refresh Now; one turned on before an update that changed its hosts,
/// prefix, queries or script says it needs turning on again, and one the command trigger shadows says why it can't show. The
/// completion entries the plugin.json declares that were refused, with why. Its preferences: text in the config file,
/// passwords in the keychain.
struct PluginCompletionsView: View {
    @ObservedObject var model: SettingsModel
    let plugin: InstalledPlugin
    /// How each source (by name) is doing this launch, read again whenever suggestions report a change.
    @State private var statuses: [String: CompletionSourceStatus] = [:]
    /// The password preferences (by name) saved in the keychain, only whether they are, and their last 4 characters
    /// where kept.
    @State private var passwordsSaved: Set<String> = []
    @State private var passwordEndings: [String: String] = [:]
    @State private var error: String?

    var body: some View {
        let manifest = plugin.manifest
        if !manifest.completions.isEmpty || !manifest.refusedCompletions.isEmpty || !manifest.preferences.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(manifest.completions, id: \.name) { source in sourceRow(source) }
                ForEach(manifest.refusedCompletions, id: \.self) { refused in
                    Label((refused.name.map { tr("补全 \($0) 没有加载：", "Completion \($0) not loaded: ") }
                           ?? tr("补全没有加载：", "Completions not loaded: ")) + refused.reason,
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).padding(.leading, 28)
                }
                ForEach(manifest.preferences, id: \.name) { preference in
                    PluginPreferenceField(preference: preference, value: model.pluginPreference(plugin, preference),
                                          saved: passwordsSaved.contains(preference.name), ending: passwordEndings[preference.name],
                                          save: { value in
                                              error = model.setPluginPreference(plugin, preference, value)
                                              readPasswords()
                                          },
                                          remove: {
                                              error = model.removePluginPassword(plugin, preference)
                                              readPasswords()
                                          })
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .onAppear {
                readStatuses()
                readPasswords()
            }
            .onChange(of: plugin) { readPasswords() }
            .onReceive(NotificationCenter.default.publisher(for: .allInOneIMESuggestionsChanged)) { _ in readStatuses() }
        }
    }

    /// A source: its title and prefix, Refresh Now while its list is on, its switch; under them what it does, then why it
    /// can't show, that it changed since it was turned on, or (on) that Suggestions are off and how it is doing.
    @ViewBuilder private func sourceRow(_ source: CompletionSource) -> some View {
        let approval = model.config.approval(of: source, in: plugin)
        // Turned on before an update that changed its hosts, prefix, queries or script: off until turned on again.
        let changed = approval.map { !$0.holds(for: source, of: plugin) } ?? false
        let on = approval != nil && !changed
        let title = source.title.text(chinese: UIText.chinese)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "text.append").foregroundStyle(.secondary).frame(width: 20)
                Text(title).fontWeight(.medium)
                if let prefix = source.prefix { Text(prefix).font(.body.monospaced()).foregroundStyle(.secondary) }
                Spacer()
                if on, source.list {
                    Button(tr("立即刷新", "Refresh Now")) { model.refreshNow(source, of: plugin) }
                }
                Toggle("", isOn: Binding(get: { on }, set: { model.setCompletionSource(source, of: plugin, enabled: $0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel(title)
            }
            Group {
                Text(source.summary(hosts: plugin.manifest.hosts)).foregroundStyle(.secondary)
                if let reason = source.inactiveReason(model.config) {
                    Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if changed {
                    Label(tr("插件更新后变了（联系的网址、前缀、查询或脚本），已经关掉：要用的话再打开一次。",
                             "Changed since you turned it on (its hosts, prefix, queries or script), so it's off: turn it on again to use it."),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if on {
                    // On, but every suggestion is off (General, or the input menu): nothing of it shows.
                    if model.config.suggestions == false {
                        Label(tr("建议关着，这些补全不会出现：在「通用」里打开。", "Suggestions are off, so these completions don't show: turn them on in General."),
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if let summary = statuses[source.name]?.summary() {
                        Text(summary).foregroundStyle(.secondary)
                    } else if source.list {
                        Text(tr("还没加载过：第一次用到时加载。", "Not loaded yet: it loads the first time you use it."))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption).fixedSize(horizontal: false, vertical: true).padding(.leading, 28)
        }
        .padding(.leading, 28)
    }

    private func readStatuses() {
        statuses = Dictionary(plugin.manifest.completions.compactMap { source in
            SuggestionsShared.store.status(plugin: plugin.name, source: source.name).map { (source.name, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Whether each password is saved, not its value (that could ask for the keychain); none in a preview or the
    /// self-test.
    private func readPasswords() {
        guard model.store.persists, SettingsModel.looksUpKeys else { return }
        let passwords = plugin.manifest.preferences.filter { $0.kind == .password }
        func account(_ preference: PluginPreference) -> String {
            PluginPreference.keychainAccount(plugin: plugin.name, name: preference.name)
        }
        passwordsSaved = Set(passwords.filter { APIKeys.hasKeychainKey(account: account($0)) }.map(\.name))
        passwordEndings = Dictionary(passwords.compactMap { preference in
            APIKeys.keyEnding(account: account(preference)).map { (preference.name, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }
}

/// A plugin's preference (`PluginPreference`), as an extension bundle's: a text field, saved on Return and when it loses
/// focus (emptied: the plugin's default applies), or a password, saved in the keychain and never shown again.
private struct PluginPreferenceField: View {
    let preference: PluginPreference
    /// The text saved, else the default.
    let value: String
    /// A password: one is in the keychain.
    let saved: Bool
    /// A saved password's last 4 characters, where kept.
    var ending: String? = nil
    let save: (String) -> Void
    /// A password's Remove…, once confirmed.
    let remove: () -> Void
    @State private var text = ""
    /// The text field was edited since it last showed `value`.
    @State private var edited = false
    @State private var editingPassword = false
    @FocusState private var focused: Bool

    var body: some View {
        let title = preference.title.text(chinese: UIText.chinese)
        LabeledContent {
            switch preference.kind {
            case .password:
                // As an API key's row: whether it is saved, in the row; the field only after Replace… (or when not set).
                KeyRowContent(state: saved ? .saved(ending: ending) : .missing, missing: tr("还没有设置", "Not set yet"),
                              prompt: preference.placeholder ?? tr("粘贴", "Paste it"),
                              removeTitle: { everywhere in
                                  everywhere ? tr("从你所有的 Mac 上删除「\(title)」？", "Remove “\(title)” from all your Macs?")
                                      : tr("从这台 Mac 上删除「\(title)」？", "Remove “\(title)” from this Mac?")
                              },
                              save: save, remove: remove, editing: $editingPassword)
                    .frame(maxWidth: 360)
            case .text:
                // Saved only when edited here; not being edited, it follows the value (read again after a write elsewhere).
                TextField("", text: Binding(get: { text }, set: { if $0 != text { text = $0; edited = true } }),
                          prompt: (preference.placeholder ?? preference.defaultValue).map { Text($0) })
                    .labelsHidden().focused($focused)
                    .onSubmit(commitText)
                    .onChange(of: focused) { if !focused { commitText() } }
                    .onAppear { text = value }
                    .onChange(of: value) { if !edited { text = value } }
                    .frame(maxWidth: 220)
            }
        } label: {
            Text(title)
        }
        .padding(.leading, 28)
    }

    /// The text field's edit, if there was one and it changed the value: saved. Emptied, it shows the default again.
    private func commitText() {
        guard edited else { return }
        edited = false
        if text != value { save(text) }
        if text.isEmpty { text = value }
    }
}

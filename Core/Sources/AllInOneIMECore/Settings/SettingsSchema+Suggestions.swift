import Foundation

/// Suggestions in the settings document (spec 3): a plugin's completion sources (a switch each, saying what it does and
/// sends where, why it is inactive or needs enabling again; the entries refused, with their reasons) and its
/// preferences (texts, passwords in the secret store); Coding languages, a section of its own: Suggestions' switch, coding
/// mode, the packs installed and the library's.
extension SettingsSchema {
    /// The fields of `plugin`'s item in the plugins' list: its completion sources and its preferences.
    mutating func pluginFields(_ plugin: InstalledPlugin) -> [Field] {
        var fields: [Field] = []
        let store = store
        for source in plugin.manifest.completions {
            let id = "plugins.completion." + plugin.name + "." + source.name
            let approval = config.approval(of: source, in: plugin)
            let holds = approval?.holds(for: source, of: plugin) ?? false
            var field = toggle(id, source.title.text(chinese: UIText.chinese), source.summary(hosts: plugin.manifest.hosts), holds)
            if let reason = source.inactiveReason(config) {
                field.status = reason
            } else if approval != nil, !holds {
                field.status = tr("插件更新后改了联网的主机、前缀、实时查询或脚本：要再打开一次",
                                  "The plugin changed its hosts, its prefix, its live query or its script since you turned this on: turn it on again")
            } else if holds, let status = suggestionStatuses.first(where: { $0.plugin == plugin.name && $0.source == source.name }) {
                field.status = status.summary()
            }
            add(field, to: &fields) { store.config.setCompletionSource(source, of: plugin, enabled: Self.bool($0)) }
        }
        if !plugin.manifest.refusedCompletions.isEmpty {
            var refused = Field(id: "plugins.refused." + plugin.name, kind: .info, label: tr("没有用上的补全", "Completions not used"))
            refused.help = plugin.manifest.refusedCompletions.map { ($0.name.map { $0 + tr("：", ": ") } ?? "") + $0.reason }
                .joined(separator: "\n")
            add(refused, to: &fields)
        }
        for preference in plugin.manifest.preferences {
            let id = "plugins.preference." + plugin.name + "." + preference.name
            let label = preference.title.text(chinese: UIText.chinese)
            switch preference.kind {
            case .text:
                let value = config.pluginPreferences[plugin.name]?[preference.name]
                var field = text(id, label, value: value.flatMap { $0.isEmpty ? nil : $0 }, placeholder: preference.placeholder ?? preference.defaultValue)
                field.optional = nil
                add(field, to: &fields) { store.config.pluginPreferences[plugin.name, default: [:]][preference.name] = $0.string ?? "" }
            case .password:
                let account = PluginPreference.keychainAccount(plugin: plugin.name, name: preference.name)
                let saved = APIKeys.hasKeychainKey(account: account)
                add(secret(id, label, nil, state: saved ? .saved(ending: APIKeys.keyEnding(account: account)) : .missing,
                           missing: tr("还没有设置", "Not set yet"), removable: saved), to: &fields)
                handlers[id] = { action in
                    if action.name == SettingsAction.setKey, (action.key ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return .failure(SettingsProblem(.badValue, field: action.field, message: SettingsService.noKey))
                    }
                    do {
                        if action.name == SettingsAction.setKey {
                            try APIKeys.save(action.key ?? "", account: account, label: "AllInOneIME: \(plugin.name) – \(preference.title.en)")
                        } else {
                            try APIKeys.remove(account: account)
                        }
                        return .success(SettingsActionOutcome())
                    } catch {
                        return .failure(SettingsProblem(.failed, field: action.field, message: error.localizedDescription))
                    }
                }
            }
        }
        return fields
    }

    // MARK: Coding languages

    /// Suggestions' switch, coding mode (what holding Shift does), the coding packs installed (each removable) and, once
    /// browsed, the library's (each installable). Never with the input languages.
    mutating func codingLanguages() -> [Field] {
        var fields: [Field] = []
        let store = store
        add(toggle("suggestions", tr("建议", "Suggestions"),
                   tr("插件的补全（比如 # 后面的 GitHub issue）和编码模式的行，在候选框里显示，按 Tab 插入。每个插件的补全要先在「插件」里打开。",
                      "Plugins' completions (GitHub issues after #, say) and coding mode's rows, in the candidate panel; Tab inserts. Turn each plugin's on first, in Plugins."),
                   config.suggestions != false), to: &fields) { store.config.suggestions = Self.bool($0) ? nil : false }
        var mode = Field(id: "codingLanguages.mode", kind: .info, label: tr("编码模式", "Coding mode"))
        mode.help = tr("按住 Shift 一秒，选「编码模式」（或 2）打开，再选一次关闭；在所有 App 里一直开着，直到关掉。开着时每个输入框从英文开始，打两个字母起显示关键字、代码片段和输入框里已有的词，Tab 插入。和边打边译不能同时开。",
                       "Hold Shift for a second and pick Coding mode (or 2) to turn it on, again to turn it off; it stays on in every app until then. While it's on each text field starts in English, and from two letters on the rows offer keywords, snippets and the words already in the field: Tab inserts. It can't be on with Translate as You Type.")
        add(mode, to: &fields)
        let packs = codingPacks.installed()
        var installed = Field(id: "codingLanguages.installed", kind: .items, label: tr("已安装的编程语言", "Installed coding languages"))
        installed.items = packs.map { pack in
            SettingsDocument.Item(id: pack.language, title: pack.title,
                                  detail: [pack.version, tr("\(pack.keywords.count) 个关键字", "\(pack.keywords.count) keywords"),
                                           tr("\(pack.snippets.count) 个代码片段", "\(pack.snippets.count) snippets")].joined(separator: " · "),
                                  actions: [SettingsAction.remove])
        }
        if packs.isEmpty {
            installed.help = tr("还没有安装编程语言：从下面的语言库里下载你写的语言。", "No coding languages yet: download the ones you write from the library below.")
        }
        add(installed, to: &fields)
        let codingPacks = codingPacks
        handlers[installed.id] = { action in
            guard action.name == SettingsAction.remove, let language = action.item else {
                return .failure(SettingsProblem(.notChangeable, field: action.field, message: SettingsService.notChangeable))
            }
            do {
                try codingPacks.remove(language)
                return .success(SettingsActionOutcome())
            } catch {
                return .failure(SettingsProblem(.failed, field: action.field, message: UIText.describe(error)))
            }
        }
        var library = Field(id: "codingLanguages.library", kind: .items, label: tr("编程语言库", "Coding language library"))
        library.help = tr("编程语言包经过签名和校验；打开时才会联网（languages.allinoneime.com）。",
                          "Coding language packs are signed and verified; the library is fetched only when you open it (languages.allinoneime.com).")
        library.actions = [SettingsAction.browse]
        if let entries = codingEntries {
            library.items = entries.map { entry in
                let have = packs.first { $0.language == entry.language }
                let state = have == nil ? tr("下载", "Download")
                    : SemVer.compare(entry.version, have?.version ?? "") > 0 ? tr("更新（当前 \(have?.version ?? "")）", "Update (from \(have?.version ?? ""))")
                    : tr("已安装", "Installed")
                return SettingsDocument.Item(id: entry.language, title: entry.title + " " + entry.version, detail: state,
                                             actions: have == nil || SemVer.compare(entry.version, have?.version ?? "") > 0
                                                 ? [SettingsAction.install] : [])
            }
        }
        add(library, to: &fields)
        return fields
    }
}

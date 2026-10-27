import Foundation

/// Suggestions in the settings document (spec 3): their switch and what a row inserts, in General (plugins' completions
/// and Code's rows alike); a plugin's completion sources (a switch each, saying what it does and sends where, why it is
/// inactive, needs enabling again or shows nothing; then whether the plugin is in the @ list; the entries refused, with
/// their reasons) and its preferences (texts, passwords in the secret store); the Code input, in Input (decision 22): its
/// coding language, the packs installed and the library's.
extension SettingsSchema {
    // MARK: Suggestions' switch

    /// Suggestions on or off everywhere (`Config.suggestions`: on unless turned off), General's: what it covers (plugins'
    /// completions, Code's rows), in one sentence as the Mac's window says it.
    func suggestionsSwitch() -> Field {
        toggle("suggestions", tr("建议", "Suggestions"),
               tr("插件的补全和代码输入的关键字、代码片段：光标下面列出几行，按 Tab 插入。",
                  "Plugins' completions and Code's keywords and snippets, a few rows under the caret; Tab inserts."),
               config.suggestions != false)
    }

    /// What a suggestion row inserts everywhere (`Config.suggestionsInsert`, decision 28), General's, under the switch,
    /// for every source, plugins' and custom commands': unset (the source's own) or one of those Settings offers
    /// (`SuggestionsInsert.offered`, Settings v2 §4). An old value a config has (ID only, the source's own set
    /// explicitly) is the field's value, shown under its name and not to be picked again; Restore Default unsets it.
    func suggestionsInsert() -> Field {
        choice("suggestionsInsert", tr("插入", "Insert"), SuggestionsInsert.help,
               value: config.suggestionsInsert.map { .string($0.rawValue) } ?? .null,
               choices: Self.insertChoices(unset: tr("默认（各来源自己的）", "Default (each source's own)"),
                                           now: config.suggestionsInsert.map(AppInsertChoice.insert)))
    }

    /// Insert's choices (everywhere's, an app's): unset as `unset` says, those Settings offers, then Off where `off` (an
    /// app's: `AppInsertChoice.offered`), and `now` where it is an old value, `disabled`: kept, never picked anew.
    static func insertChoices(unset: String, now: AppInsertChoice?, off: Bool = false) -> [(Choice, [SettingsPlatform]?)] {
        let offered = off ? AppInsertChoice.offered : SuggestionsInsert.offered.map(AppInsertChoice.insert)
        var choices = [(Choice(nil, unset), nil)] + offered.map { (Choice($0.rawValue, $0.label), [SettingsPlatform]?.none) }
        if let now, !offered.contains(now) {
            choices.append((Choice(value: .string(now.rawValue), label: now.label, disabled: true), nil))
        }
        return choices
    }

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
            } else if holds, config.suggestions == false {
                field.status = tr("建议关着，这些补全不会出现：在「通用」里打开。", "Suggestions are off, so these completions don't show: turn them on in General.")
            } else if holds, let status = suggestionStatuses.first(where: { $0.plugin == plugin.name && $0.source == source.name }) {
                field.status = status.summary()
            }
            add(field, to: &fields) { store.config.setCompletionSource(source, of: plugin, enabled: Self.bool($0)) }
        }
        if plugin.hasSuggestions { commandListSwitch("plugins.commandList." + plugin.name, id: plugin.name, to: &fields) }
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

    /// "Show in the @ list" (`UIText.showInCommandList`) under a plugin or script extension command with suggestions,
    /// after their switch: its `id` (a plugin's name, a command's id) kept in `Config.hiddenFromCommandList` while off. On
    /// by default; off, the command is out of the @ command list and its name after the magic key is text like any other,
    /// its suggestions as they were (`Command.catalog`). None for a command without a suggestion source, a custom one or
    /// a built-in.
    mutating func commandListSwitch(_ fieldID: String, id: String, to fields: inout [Field]) {
        let store = store
        add(toggle(fieldID, UIText.showInCommandList(trigger: config.commandTrigger),
                   UIText.showInCommandListHelp(trigger: config.commandTrigger), config.showsInCommandList(id)), to: &fields) {
            store.config.setShownInCommandList(id, Self.bool($0))
        }
    }

    // MARK: Code

    /// The Code input (decision 22), in Input after the languages, a kind of its own: its coding language (none: no Code;
    /// one whose pack isn't installed says so, and is Code's once it is), the coding packs installed (each removable) and,
    /// once browsed, the library's (each installable). Never among the input languages.
    mutating func code(_ fields: inout [Field]) {
        let store = store
        let packs = codingPacks.installed()
        let enter = terms.enter
        // Windows' engine has no Code yet (as it shows no rows): what is set there is kept for when it does.
        var code = choice("codingLanguage", tr("代码", "Code"),
                          platform == .windows
                              ? tr("Windows 上还不能切到代码输入：这里的设置先保存着。", "Windows doesn't type in Code yet: what you set here is kept for when it does.")
                              : tr("排在输入语言后面，单按 Shift 切到它：打字母，光标下面列出这种编程语言的关键字、代码片段和输入框里已有的词，\(enter) 或 Tab 插入。",
                                   "An input after the languages, a tap of Shift away: you type letters, and the rows under the caret offer this coding language's keywords and snippets and the words already in the field; \(enter) or Tab inserts."),
                          value: config.codingLanguage.map(JSON.string) ?? .null,
                          choices: [(Choice(nil, tr("不用", "Not added")), nil)] + CodingLanguagePack.offered.map { offered in
                              (Choice(offered.language, offered.title), nil)
                          })
        if let language = config.codingLanguage, !packs.contains(where: { $0.language == language }) {
            code.status = tr("\(CodingLanguagePack.title(of: language)) 的语言包还没安装：从下面的编程语言库装好以后才能切到代码。",
                             "The \(CodingLanguagePack.title(of: language)) pack isn't installed: Code can be typed once it is (from the coding language library below).")
        } else if config.codingLanguage != nil, config.suggestions == false {
            code.status = tr("建议关着，代码输入不会列出什么：在「通用」里打开。", "Suggestions are off, so Code shows no rows: turn them on in General.")
        }
        add(code, to: &fields) { value in store.config.codingLanguage = value.string }
        var installed = Field(id: "code.installed", kind: .items, label: tr("已安装的编程语言", "Installed coding languages"))
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
                // Code goes with the pack of its language, as an input language goes with its pack.
                if store.config.codingLanguage == language { store.config.codingLanguage = nil }
                return .success(SettingsActionOutcome())
            } catch {
                return .failure(SettingsProblem(.failed, field: action.field, message: UIText.describe(error)))
            }
        }
        var library = Field(id: Self.codingLibraryField, kind: .items, label: tr("编程语言库", "Coding language library"))
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
    }

    /// The coding language library's field: its actions (browse, install) take a while (`SettingsService`).
    static let codingLibraryField = "code.library"
}

import Foundation

extension Config {
    /// The switches suggestions follow, as the settings have them (`SuggestionsSettings`): the input menu's
    /// (`suggestions`), the apps' (`AppProfile.suggestions`), the completion sources approved and those turned off, the
    /// custom commands that are sources (not one from another Mac awaiting confirmation here: `awaitsConfirmation`), what
    /// a row inserts everywhere and in each app (`suggestionsInsert`, `AppProfile.suggestionsInsert`); "Refresh now" is the
    /// shell's (`refreshes`).
    public func suggestionsSettings(refreshes: [CompletionSourceRefresh] = []) -> SuggestionsSettings {
        SuggestionsSettings(master: suggestions, apps: appProfiles.compactMapValues(\.suggestions), enabled: completionSources,
                            refreshes: refreshes, commands: customCommands.filter { $0.type == .suggestions && !awaitsConfirmation($0) },
                            insert: suggestionsInsert, appInserts: appProfiles.compactMapValues(\.suggestionsInsert),
                            off: completionSourcesOff)
    }

    /// Whether the user turned the completion source `key` off (`completionSourcesOff`): off whatever else.
    public func turnedOff(_ key: CompletionSourceKey) -> Bool { completionSourcesOff.contains(key) }

    /// `key` turned off by the user (kept so, `completionSourcesOff`), or turned on (taken off the list).
    mutating func setTurnedOff(_ key: CompletionSourceKey, _ off: Bool) {
        completionSourcesOff.removeAll { $0 == key }
        if off { completionSourcesOff.append(key) }
    }

    /// The approval `source` of `plugin` was approved with (nil: none).
    public func approval(of source: CompletionSource, in plugin: InstalledPlugin) -> CompletionSourceApproval? {
        completionSources.first { $0.plugin == plugin.name && $0.source == source.name }
    }

    /// `source` of `plugin` turned on with what it is now (`CompletionSourceApproval(enabling:of:)`), or off: kept off
    /// (`completionSourcesOff`) through its updates and restarts until turned on again, which takes it off that list.
    public mutating func setCompletionSource(_ source: CompletionSource, of plugin: InstalledPlugin, enabled: Bool) {
        completionSources.removeAll { $0.plugin == plugin.name && $0.source == source.name }
        setTurnedOff(CompletionSourceKey(plugin: plugin.name, source: source.name), !enabled)
        if enabled, let approval = CompletionSourceApproval(enabling: source, of: plugin) { completionSources.append(approval) }
    }

    /// Whether `plugins` (as installed now) has one this Mac hasn't found before (`pluginsSeen`): nothing read.
    public func hasNewPlugins(_ plugins: [InstalledPlugin]) -> Bool {
        plugins.contains { !pluginsSeen.contains($0.name) }
    }

    /// The plugins of `plugins` (as installed now) this Mac hasn't found before (`pluginsSeen`: just installed, from the
    /// library or put in the plugins folder, or there before this version) found now (0.6.7.2): each completion source
    /// they declare approved as it is now (`CompletionSourceApproval(enabling:of:)`: its hosts, query, script and terms),
    /// but one approved already (or marked lapsed: off until turned on again) and one turned off; then noted, so that a
    /// source a later update adds stays off until turned on. Whether anything changed.
    @discardableResult
    public mutating func approveNewPlugins(_ plugins: [InstalledPlugin]) -> Bool {
        var changed = false
        for plugin in plugins where !pluginsSeen.contains(plugin.name) {
            for source in plugin.manifest.completions {
                guard approval(of: source, in: plugin) == nil, !turnedOff(CompletionSourceKey(plugin: plugin.name, source: source.name)),
                      let approval = CompletionSourceApproval(enabling: source, of: plugin) else { continue }
                completionSources.append(approval)
            }
            pluginsSeen.append(plugin.name)
            changed = true
        }
        return changed
    }

    /// What this Mac kept of the plugin `name`'s completion sources forgotten: their approvals, those turned off, that it
    /// was found here (removed in Settings, or about to be installed anew from the library, its folder gone): installed
    /// again, its sources are on as they are then. Whether anything changed.
    @discardableResult
    public mutating func forgetPlugin(_ name: String) -> Bool {
        let before = (completionSources.count, completionSourcesOff.count, pluginsSeen.count)
        completionSources.removeAll { $0.plugin == name }
        completionSourcesOff.removeAll { $0.plugin == name }
        pluginsSeen.removeAll { $0 == name }
        return before != (completionSources.count, completionSourcesOff.count, pluginsSeen.count)
    }

    /// The approvals `lapsed` found (`CompletionSourceApproval.lapsed`) marked so, kept: off until enabled again, which
    /// Settings says. Whether any changed.
    @discardableResult
    public mutating func markLapsed(_ lapsed: [CompletionSourceApproval]) -> Bool {
        var changed = false
        for index in completionSources.indices where !completionSources[index].lapsed && lapsed.contains(completionSources[index]) {
            completionSources[index].lapsed = true
            changed = true
        }
        return changed
    }
}

extension SuggestionsSettings {
    /// The sources there are: those enabled (approved, lapsed or not) and the custom commands' (`commands`). What isn't
    /// among them is forgotten, its cached list deleted (`SuggestionsStore.prune`).
    public var sourceKeys: Set<CompletionSourceKey> {
        Set(enabled.map { CompletionSourceKey(plugin: $0.plugin, source: $0.source) } + commands.map { CompletionSourceKey(command: $0.name) })
    }

    /// `sourceKeys` and those of the script extensions' sources `commands` (as loaded) declare that aren't turned off
    /// (`off`): one on with no approval (0.6.7.2: the user's own, a trusted source's) keeps its cached list.
    public func sourceKeys(extensions commands: [ScriptCommand]) -> Set<CompletionSourceKey> {
        sourceKeys.union(commands.compactMap { command in
            guard case .success? = command.completion else { return nil }
            let key = CompletionSourceKey(extension: command)
            return off.contains(key) ? nil : key
        })
    }
}

extension CompletionSourceApproval {
    /// What enabling `source` of `plugin` approves now: the plugin's hosts, whether the source queries, its script's
    /// SHA-256, what else its switch says (its prefix, when its query is first asked, how it compares). Nil: the plugin
    /// has no script to read.
    public init?(enabling source: CompletionSource, of plugin: InstalledPlugin) {
        guard let script = plugin.scriptURL, let sha = PluginStore.sha256(of: script) else { return nil }
        self.init(plugin: plugin.name, source: source.name, hosts: plugin.manifest.hosts, query: source.query, scriptSHA256: sha,
                  terms: Terms(source))
    }

    /// Whether it still holds for `source` of `plugin` as they are now: the same hosts (in any order or case), query,
    /// script and terms (one without terms never does). Else the source needs enabling again (spec 1.5).
    public func holds(for source: CompletionSource, of plugin: InstalledPlugin) -> Bool {
        guard let script = plugin.scriptURL, let sha = PluginStore.sha256(of: script) else { return false }
        return holds(for: source, hosts: plugin.manifest.hosts, scriptSHA256: sha)
    }

    /// The approvals of `enabled` not marked lapsed yet that no longer hold for `plugins` as they are installed now: their
    /// plugin and source are there, changed since (`holds`). One whose plugin, source or script isn't there has nothing
    /// to compare with (a scan that read none, a plugin skipped for its minAppVersion): it doesn't lapse. `sha256`: a
    /// script's SHA-256 (nil: none to read).
    public static func lapsed(_ enabled: [CompletionSourceApproval], plugins: [InstalledPlugin],
                              sha256: (URL) -> String? = PluginStore.sha256(of:)) -> [CompletionSourceApproval] {
        enabled.filter { approval in
            guard !approval.lapsed, let plugin = plugins.first(where: { $0.name == approval.plugin }),
                  let source = plugin.manifest.completions.first(where: { $0.name == approval.source }),
                  let sha = plugin.scriptURL.flatMap(sha256) else { return false }
            return !approval.holds(for: source, hosts: plugin.manifest.hosts, scriptSHA256: sha)
        }
    }

    /// `holds(for:of:)` with the plugin's hosts and its script's SHA-256 as they are now. Never once marked lapsed, nor
    /// without terms.
    func holds(for source: CompletionSource, hosts: [String], scriptSHA256 sha: String) -> Bool {
        !lapsed && self.source == source.name && query == source.query && scriptSHA256 == sha
            && Set(self.hosts.map { $0.lowercased() }) == Set(hosts.map { $0.lowercased() })
            && terms == Terms(source)
    }
}

extension PluginPreference {
    /// A password preference's item in the secret store (as extensions' are): "plugin.<plugin>.<name>".
    public static func keychainAccount(plugin: String, name: String) -> String { "plugin.\(plugin).\(name)" }

    /// `plugin`'s preferences as the user set them: `texts` (from the settings, `Config.pluginPreferences`), and its
    /// passwords from the secret store. Not on a thread a key is handled on: the secret store may take a while.
    public static func stored(for plugin: InstalledPlugin, texts: [String: String]) -> [String: String] {
        var values = texts
        for preference in plugin.manifest.preferences where preference.kind == .password {
            values[preference.name] = APIKeys.keychainKey(account: keychainAccount(plugin: plugin.name, name: preference.name))
        }
        return values
    }

    /// What `plugin`'s script gets (`ctx.preferences`): those `set` (not empty), else the manifest's defaults; only those
    /// it declares.
    public static func values(for plugin: InstalledPlugin, set: [String: String]) -> [String: String] {
        var values: [String: String] = [:]
        for preference in plugin.manifest.preferences {
            if let value = set[preference.name], !value.isEmpty {
                values[preference.name] = value
            } else if let value = preference.defaultValue {
                values[preference.name] = value
            }
        }
        return values
    }
}

extension CompletionSource {
    /// What its switch says it does, in the interface language: where its rows come from, and for a source that queries,
    /// what it sends where (spec 1.5): "Rows after # from the plugin's list, refreshed every 15 min; sends what you type
    /// after # to api.github.com".
    public func summary(hosts: [String], in t: InterfaceWords = InterfaceWords(language: UIText.language)) -> String {
        let after = prefix ?? ""
        let start = prefix.map { t.tr("在 \($0) 后面", "after \($0)") } ?? t.tr("打完整个号码后", "once the whole number is typed")
        var parts: [String] = []
        if list {
            let every = Self.interval(refresh, in: t)
            parts.append(t.tr("\(start)显示插件列表里的行（每 \(every)更新一次，只在你用到时）",
                              "Rows \(start) from the plugin's list (refreshed every \(every), while you use it)"))
        }
        if query {
            let places = hosts.isEmpty ? t.tr("插件", "the plugin") : hosts.joined(separator: ", ")
            parts.append(after.isEmpty
                         ? t.tr("会把你打的号码发给 \(places)", "sends what you type to \(places)")
                         : t.tr("会把你在 \(after) 后面打的字发给 \(places)", "sends what you type after \(after) to \(places)"))
        }
        if parts.isEmpty { parts.append(t.tr("\(start)显示插件的行", "Rows \(start) from the plugin")) }
        return parts.joined(separator: t.tr("；", "; "))
    }

    /// "15 min", "1 h", "1 d".
    public static func interval(_ seconds: TimeInterval, in t: InterfaceWords = InterfaceWords(language: UIText.language)) -> String {
        let whole = Int(seconds)
        if whole % 86400 == 0 { return t.tr("\(whole / 86400) 天", "\(whole / 86400) d") }
        if whole % 3600 == 0 { return t.tr("\(whole / 3600) 小时", "\(whole / 3600) h") }
        return t.tr("\(max(whole / 60, 1)) 分钟", "\(max(whole / 60, 1)) min")
    }
}

extension CompletionSourceStatus {
    /// How it is doing, for Settings: its items and when its list was last loaded, why it failed, whether it is paused;
    /// nil: nothing known yet this launch.
    public func summary(now: Date = Date(), in t: InterfaceWords = InterfaceWords(language: UIText.language)) -> String? {
        var parts: [String] = []
        if let refreshed {
            parts.append(t.tr("\(items) 项", "\(items) items"))
            parts.append(t.tr("更新于 ", "refreshed ") + RelativeTime.ago(refreshed, now: now, language: t.language, style: .short))
        }
        if paused {
            parts.append(t.tr("已暂停（连续失败）：", "Paused (failed in a row): ") + (error ?? ""))
        } else if let error {
            parts.append(t.tr("上次出错：", "Last error: ") + error)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension CustomCommand {
    /// How a `suggestions` command is doing, as Settings says it under it (the Mac's editor and command list, the
    /// settings document's): that it came from another Mac and runs nothing until allowed here (decision 26), why it
    /// isn't used (`problem`: refused by a source's rules, its prefix the magic key's), that Suggestions are off, or its
    /// source's status (its items, when it last updated, its last error, a pause); not loaded yet. `problem`: what is said
    /// is why nothing of it shows. Nil: not a `suggestions` command.
    public func suggestionsState(_ config: Config, status: CompletionSourceStatus?, now: Date = Date(),
                                 in t: InterfaceWords = InterfaceWords(language: UIText.language)) -> (text: String, problem: Bool)? {
        guard let read = suggestionSource else { return nil }
        if config.awaitsConfirmation(self) {
            return (UIText.fromAnotherMac(self, in: t) + t.tr("。", ". ") + UIText.runsNothingUntilAllowed(in: t), true)
        }
        switch read {
        case .failure:
            // What the source's rules refused, as the editor says it (the magic key is the next case's).
            return (suggestionProblem(trigger: "").map(UIText.describe) ?? t.tr("不能作为建议来源", "Can't be a suggestion source"), true)
        case let .success(source):
            if let reason = source.inactiveReason(config) { return (reason, true) }
            if config.suggestions == false {
                return (t.tr("建议关着，这个来源不会出现：在「通用」里打开。", "Suggestions are off, so this source doesn't show: turn them on in General."), true)
            }
            if let summary = status?.summary(now: now, in: t) { return (summary, status?.error != nil) }
            return (t.tr("还没加载过：下次有输入框获得焦点时加载。", "Not loaded yet: it loads when a text field next gets the focus."), false)
        }
    }
}

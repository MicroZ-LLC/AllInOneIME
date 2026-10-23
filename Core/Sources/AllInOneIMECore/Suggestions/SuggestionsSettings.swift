import Foundation

extension Config {
    /// The switches suggestions follow, as the settings have them (`SuggestionsSettings`): the input menu's
    /// (`suggestions`), the apps' (`AppProfile.suggestions`), the completion sources enabled; "Refresh now" is the shell's
    /// (`refreshes`).
    public func suggestionsSettings(refreshes: [CompletionSourceRefresh] = []) -> SuggestionsSettings {
        SuggestionsSettings(master: suggestions, apps: appProfiles.compactMapValues(\.suggestions), enabled: completionSources,
                            refreshes: refreshes)
    }

    /// The approval `source` of `plugin` was enabled with (nil: not enabled).
    public func approval(of source: CompletionSource, in plugin: InstalledPlugin) -> CompletionSourceApproval? {
        completionSources.first { $0.plugin == plugin.name && $0.source == source.name }
    }

    /// `source` of `plugin` enabled with what it is now (`CompletionSourceApproval(enabling:of:)`), or disabled.
    public mutating func setCompletionSource(_ source: CompletionSource, of plugin: InstalledPlugin, enabled: Bool) {
        completionSources.removeAll { $0.plugin == plugin.name && $0.source == source.name }
        if enabled, let approval = CompletionSourceApproval(enabling: source, of: plugin) { completionSources.append(approval) }
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
    /// script and terms. Else the source needs enabling again (spec 1.5).
    public func holds(for source: CompletionSource, of plugin: InstalledPlugin) -> Bool {
        guard let script = plugin.scriptURL, let sha = PluginStore.sha256(of: script) else { return false }
        return holds(for: source, hosts: plugin.manifest.hosts, scriptSHA256: sha)
    }

    /// `holds(for:of:)` with the plugin's hosts and its script's SHA-256 as they are now.
    func holds(for source: CompletionSource, hosts: [String], scriptSHA256 sha: String) -> Bool {
        self.source == source.name && query == source.query && scriptSHA256 == sha
            && Set(self.hosts.map { $0.lowercased() }) == Set(hosts.map { $0.lowercased() })
            && terms.map { $0 == Terms(source) } ?? true
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
    static func interval(_ seconds: TimeInterval, in t: InterfaceWords) -> String {
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

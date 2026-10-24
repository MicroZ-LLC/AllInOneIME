import Foundation

/// What a suggestion row inserts, as the user chooses it (spec Suggestions v1, decision 28; Settings v2 §4): everywhere
/// (Settings → General, `Config.suggestionsInsert`) and per app (`AppProfile.suggestionsInsert`), an app's own over the
/// one everywhere. Every suggestion source follows it, a plugin's and a custom command's; Code's packs never do. A class
/// of app the source has no rows in (`null` in its `insert`) still has none: this is what a row puts in, not where rows
/// show. Written in the config as its raw value; the source's own is none everywhere, `"source"` for an app whose own it
/// is. Settings offers two of them anew (`offered`); ID only, and `"source"` set explicitly, are still honored where a
/// config has them.
public enum SuggestionsInsert: String, CaseIterable, Codable, Sendable {
    /// The source's own templates for the app's class: a plugin's `insert`, a custom command's Insert.
    case source
    /// "ID only": `{arg}`.
    case id
    /// "With title": `{arg} {title}`, else `{arg}`.
    case title
    /// "With title and link": `{arg} {title} {url}`, else `{arg} {title}`, else `{arg}`.
    case titleAndLink

    /// Its templates, tried in turn (the first whose variables the item all has), in every class of app; nil: the
    /// source's own (`PluginRows.templates`). `{title}` is the item's `title` variable.
    public var templates: [String]? {
        switch self {
        case .source: return nil
        case .id: return ["{arg}"]
        case .title: return ["{arg} {title}", "{arg}"]
        case .titleAndLink: return ["{arg} {title} {url}", "{arg} {title}", "{arg}"]
        }
    }

    /// As Settings names it.
    public var label: String {
        switch self {
        case .source: return tr("来源的默认", "Source's default")
        case .id: return tr("只有 ID", "ID only")
        case .title: return tr("带标题", "With title")
        case .titleAndLink: return tr("带标题和链接", "With title and link")
        }
    }

    /// What Settings offers to choose, everywhere and per app, in this order (Settings v2 §4): With title, With title and
    /// link. Unset is the source's own; ID only and "source" set explicitly can't be chosen anew, one a config has is
    /// still honored.
    public static var offered: [SuggestionsInsert] { [.title, .titleAndLink] }

    /// What Settings says of it, with GitHub's issues for an example.
    public static var help: String {
        tr("建议的行插入什么（插件的补全和建议类的自定义命令，不管代码输入）：比如 GitHub issue #1234，带标题是「#1234 Fix login」，带标题和链接是「#1234 Fix login https://github.com/…/issues/1234」，不设就用插件或命令自己定的。",
           "What a suggestion row inserts (plugins' completions and Suggestions commands, not Code): for GitHub issue #1234, with title is \"#1234 Fix login\", with title and link \"#1234 Fix login https://github.com/…/issues/1234\", and unset, what the plugin or the command says.")
    }

    /// Where it is chosen, for Settings → Plugins, where a plugin's completions are turned on.
    public static var chosenIn: String {
        tr("建议的行插入什么：设置 →「通用」", "What a row inserts: Settings → General")
    }
}

extension SuggestionsSettings {
    /// What a row inserts in `app` (its id, in any case): its own choice, else the one everywhere, else the source's own.
    public func insert(for app: String?) -> SuggestionsInsert {
        if let app, let own = appInserts.first(where: { $0.key.caseInsensitiveCompare(app) == .orderedSame })?.value { return own }
        return insert ?? .source
    }
}

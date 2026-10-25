import Foundation

/// What a suggestion row inserts, as the user chooses it (spec Suggestions v1, decision 28; Settings v2 §4): everywhere
/// (Settings → General, `Config.suggestionsInsert`) and per app (`AppProfile.suggestionsInsert`), an app's own over the
/// one everywhere. Every suggestion source follows it, a plugin's and a custom command's; Code's packs never do. A class
/// of app the source has no rows in (`null` in its `insert`) still has none: this is what a row puts in, not where rows
/// show. Written in the config as its raw value; the source's own is none everywhere, `"source"` for an app whose own it
/// is. Settings offers three of them anew (`offered`); ID only, and `"source"` set explicitly, are still honored where a
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
    /// "Markdown link": `[{title}]({url})`, else `{arg}`. The link doesn't start with what was typed: it takes the token's
    /// place where the field reports ranges, and elsewhere (a terminal) `{arg}` goes in (`PluginRows.RowMaker`).
    case markdownLink

    /// Its templates, tried in turn (the first whose variables the item all has), in every class of app; nil: the
    /// source's own (`PluginRows.templates`). `{title}` is the item's `title` variable.
    public var templates: [String]? {
        switch self {
        case .source: return nil
        case .id: return ["{arg}"]
        case .title: return ["{arg} {title}", "{arg}"]
        case .titleAndLink: return ["{arg} {title} {url}", "{arg} {title}", "{arg}"]
        case .markdownLink: return ["[{title}]({url})", "{arg}"]
        }
    }

    /// As Settings names it.
    public var label: String {
        switch self {
        case .source: return tr("来源的默认", "Source's default")
        case .id: return tr("只有 ID", "ID only")
        case .title: return tr("带标题", "With title")
        case .titleAndLink: return tr("带标题和链接", "With title and link")
        case .markdownLink: return tr("Markdown 链接", "Markdown link")
        }
    }

    /// What Settings offers to choose, everywhere and per app, in this order (Settings v2 §4, 0.6.7.1): With title, With
    /// title and link, Markdown link. Unset is the source's own; ID only and "source" set explicitly can't be chosen anew,
    /// one a config has is still honored.
    public static var offered: [SuggestionsInsert] { [.title, .titleAndLink, .markdownLink] }

    /// What Settings says of it, with GitHub's issues for an example: one sentence, the same on every platform.
    public static var help: String {
        tr("建议的行插入什么：默认按插件或命令自己定的；比如 GitHub issue，带标题是「#1234 Fix login」，带标题和链接再加上它的链接，Markdown 链接是「[Fix login](https://…)」，替换掉打的 #1234。",
           "What a suggestion row puts in: by default what its plugin or command says; for a GitHub issue, with title is \"#1234 Fix login\", with title and link adds its link, and Markdown link puts \"[Fix login](https://…)\" in place of the #1234 typed.")
    }

    /// Where it is chosen, for Settings → Plugins, where a plugin's completions are turned on.
    public static var chosenIn: String {
        tr("建议的行插入什么：设置 →「通用」", "What a row inserts: Settings → General")
    }
}

/// An app's own choice in Settings → General → Suggestions → "In these apps" and in the input menu's This App ▸ Insert
/// (the owner's decision of 2026-10-24): what a suggestion row inserts there, or Off, no suggestion rows there at all.
/// It has no key of its own: it is the app's `suggestions` and `suggestionsInsert` (`AppProfile.insertChoice`). Written
/// in the settings document as its raw value: the insert's, or "off".
public enum AppInsertChoice: Hashable, Sendable, RawRepresentable {
    /// What a row inserts there (`AppProfile.suggestionsInsert`).
    case insert(SuggestionsInsert)
    /// No suggestions there (`AppProfile.suggestions` false): no plugin's or command's rows, no Code's.
    case off

    public init?(rawValue: String) {
        if rawValue == "off" {
            self = .off
        } else if let insert = SuggestionsInsert(rawValue: rawValue) {
            self = .insert(insert)
        } else {
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case let .insert(insert): return insert.rawValue
        case .off: return "off"
        }
    }

    /// What Settings and the input menu offer an app, in this order: With title, With title and link, Markdown link
    /// (`SuggestionsInsert.offered`), Off. An old insert a config has (ID only, the source's own) is still honored.
    public static var offered: [AppInsertChoice] { SuggestionsInsert.offered.map(AppInsertChoice.insert) + [.off] }

    /// As Settings names it.
    public var label: String {
        switch self {
        case let .insert(insert): return insert.label
        case .off: return tr("关闭", "Off", key: "suggestionsInsert.off")
        }
    }
}

extension AppProfile {
    /// Its choice in "In these apps" (`AppInsertChoice`): Off while its suggestions are off, else what its rows insert;
    /// nil: none of its own, as everywhere. Set to Off, its suggestions go off and what its rows insert stays (for when
    /// they're back; it syncs, the switch is this Mac's own); to an insert, they're back (as everywhere) with it; to nil
    /// (Remove, Restore Default, Same as everywhere), both are cleared.
    public var insertChoice: AppInsertChoice? {
        get { suggestions == false ? .off : suggestionsInsert.map(AppInsertChoice.insert) }
        set {
            switch newValue {
            case .off?: suggestions = false
            case let .insert(insert)?: (suggestions, suggestionsInsert) = (nil, insert)
            case nil: (suggestions, suggestionsInsert) = (nil, nil)
            }
        }
    }
}

extension SuggestionsSettings {
    /// What a row inserts in `app` (its id, in any case): its own choice, else the one everywhere, else the source's own.
    public func insert(for app: String?) -> SuggestionsInsert {
        if let app, let own = appInserts.first(where: { $0.key.caseInsensitiveCompare(app) == .orderedSame })?.value { return own }
        return insert ?? .source
    }
}

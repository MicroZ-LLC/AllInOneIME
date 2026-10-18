import Foundation

/// The tone of what the AI writes for an app: the app's first rewrite style (`AppProfile.rewriteStyles`), else one for the
/// kind of app (`AppClass`). Translate as You Type translates in it (`rule`), `@reply` writes its replies in it
/// (`replyRule`); `TranslateMode.tone(app:config:)` picks it.
public enum AppTone: String, CaseIterable, Equatable, Sendable {
    case natural, casual, formal, concise, tactful, jargon

    /// The tone of a rewrite style (`RewriteStyle.catalog`): Polish is natural.
    public init(style: RewriteStyle) {
        switch style.tag {
        case "CASUAL": self = .casual
        case "FORMAL": self = .formal
        case "CONCISE": self = .concise
        case "TACTFUL": self = .tactful
        case RewriteStyle.jargonTag: self = .jargon
        default: self = .natural
        }
    }

    /// The tone itself, as the rules below say it.
    var wording: String {
        switch self {
        case .natural: return "natural and neutral, as a native speaker would normally write it"
        case .casual: return "casual and friendly, like chatting with a friend or a close colleague: relaxed everyday words, nothing stiff"
        case .formal: return "formal and polite, as for a manager, a client or an email: professional, courteous wording"
        case .concise: return "concise: as short as possible while keeping every point"
        case .tactful: return "tactful and considerate: bluntness, criticism or a refusal softened, the point kept"
        case .jargon: return "playful big-tech corporate jargon where it fits naturally, the point still recognizable"
        }
    }

    /// What a translation's request adds to its rules (`Prompt.translateModeRequest`).
    public var rule: String {
        "Tone of the translation: \(wording). The tone changes only the wording: keep the meaning, the facts and the intent."
    }

    /// What `@reply`'s request says about the replies' tone (`Prompt.replySystem`), unless the user asks for another.
    public var replyRule: String {
        "Tone of the replies: \(wording), unless the user's intent asks for another tone."
    }
}

/// What kind of app a bundle id is, for the tone it gets by default (`AppTone`) and the shape of a reply (`@reply`: a chat
/// message, or an email body).
public enum AppClass: Equatable, Sendable {
    /// Messaging (WeChat, Slack, Messages, Telegram, Discord, Teams): casual.
    case chat
    /// Email (Mail, Outlook, Spark): formal.
    case mail
    /// Everything else: natural.
    case other

    static let chatApps: Set<String> = [
        "com.tencent.xinwechat", "com.tinyspeck.slackmacgap", "com.apple.mobilesms", "com.apple.ichat",
        "ru.keepcoder.telegram", "org.telegram.desktop", "com.tdesktop.telegram", "com.hnc.discord",
        "com.microsoft.teams", "com.microsoft.teams2",
    ]
    static let mailApps: Set<String> = [
        "com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail-mac", "com.readdle.sparkdesktop",
        "com.readdle.spark",
    ]

    /// The class of `app` (a bundle id, any case).
    public init(app: String?) {
        let id = app?.lowercased() ?? ""
        self = Self.chatApps.contains(id) ? .chat : Self.mailApps.contains(id) ? .mail : .other
    }

    public var tone: AppTone {
        switch self {
        case .chat: return .casual
        case .mail: return .formal
        case .other: return .natural
        }
    }
}

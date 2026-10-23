import Foundation

/// What suggestions' rows do in an app (spec 1.4, 6.11), by its id (the Mac's bundle id, Windows' "win:<program>") and
/// whether the field is a terminal's (`FieldInfo.terminal`).
public enum SuggestionsAppClass: Equatable, Sendable {
    /// Tab inserts the highlighted row (the first), ↓ ↑ move it, Return inserts it once moved, Esc hides the rows.
    case ordinary
    /// Chat apps and browsers (Return sends): Tab inserts the first row with the `chat` template; every other key is the
    /// app's.
    case chat
    /// Terminals and code editors: Tab completes the rows' common prefix only, with `{match}`; every other key is the app's.
    case codeEditor
    /// Launchers, remote desktops, virtual machines, SSH clients: no rows.
    case none

    public init(app: String?, terminal: Bool) {
        let id = app?.lowercased() ?? ""
        if Self.isLauncher(id) || EnglishWords.isRemote(id) {
            self = .none
        } else if terminal || Self.isCodeEditor(id) {
            self = .codeEditor
        } else if Self.isChat(id) {
            self = .chat
        } else {
            self = .ordinary
        }
    }

    /// Raycast, Alfred, Spotlight, LaunchBar; PowerToys Run, Flow Launcher, Wox.
    static let launchers = ["com.raycast.macos", "com.runningwithcrayons.alfred", "com.apple.spotlight", "at.obdev.launchbar"]
    static let launcherPrograms: Set<String> = ["powertoys.powerlauncher.exe", "flow.launcher.exe", "wox.exe"]

    /// The chat apps (`AppClass`'s: WeChat, Slack, Messages, Telegram, Discord, Teams), Electron chat apps, and the
    /// Chromium browsers (Chrome, Edge, Brave, Arc, Vivaldi, Opera), whose web apps send on Return; by the beginning of
    /// their ids, in small letters.
    static let chatApps = AppClass.chatApps.map { $0 } + [
        "com.google.chrome", "com.microsoft.edgemac", "com.brave.browser", "company.thebrowser.browser", "com.vivaldi.vivaldi",
        "com.operasoftware.opera", "org.whispersystems.signal-desktop", "im.riot.app", "mattermost.desktop",
        "org.zulip.zulip-electron", "chat.rocket", "com.electron.lark", "com.bytedance.lark", "com.alibaba.dingtalkmac",
        "com.skype.skype", "net.whatsapp.whatsapp", "desktop.whatsapp",
    ]
    static let chatPrograms: Set<String> = [
        "chrome.exe", "msedge.exe", "brave.exe", "arc.exe", "vivaldi.exe", "opera.exe", "slack.exe", "discord.exe", "teams.exe",
        "ms-teams.exe", "wechat.exe", "weixin.exe", "telegram.exe", "signal.exe", "whatsapp.exe", "element.exe",
        "mattermost.exe", "feishu.exe", "lark.exe", "dingtalk.exe", "skype.exe",
    ]

    static func isLauncher(_ id: String) -> Bool {
        matches(id, launchers, launcherPrograms)
    }

    static func isChat(_ id: String) -> Bool {
        matches(id, chatApps, chatPrograms)
    }

    /// The code editors autocomplete goes by too (`CodeEditors`).
    static func isCodeEditor(_ id: String) -> Bool {
        CodeEditors.contains(id)
    }

    /// A Windows app id by its program's name; a bundle id that is one of `prefixes` or starts with one and a dot (or
    /// one ending in a dot itself).
    private static func matches(_ id: String, _ prefixes: [String], _ programs: Set<String>) -> Bool {
        if id.hasPrefix("win:") { return programs.contains(String(id.dropFirst(4))) }
        return prefixes.contains { prefix in
            prefix.hasSuffix(".") ? id.hasPrefix(prefix) : id == prefix || id.hasPrefix(prefix + ".")
        }
    }
}

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

    /// Xcode, VS Code, Cursor, Windsurf, Zed, Nova, Sublime Text, JetBrains' IDEs, Android Studio; the same on Windows,
    /// and Visual Studio.
    static let codeEditors = [
        "com.apple.dt.xcode", "com.microsoft.vscode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "dev.zed.zed",
        "com.panic.nova", "com.sublimetext.", "com.jetbrains.", "com.google.android.studio",
    ]
    static let codeEditorPrograms: Set<String> = [
        "code.exe", "code - insiders.exe", "cursor.exe", "windsurf.exe", "zed.exe", "sublime_text.exe", "devenv.exe",
        "idea64.exe", "pycharm64.exe", "webstorm64.exe", "clion64.exe", "goland64.exe", "rider64.exe", "phpstorm64.exe",
        "rubymine64.exe", "datagrip64.exe", "studio64.exe",
    ]

    static func isLauncher(_ id: String) -> Bool {
        matches(id, launchers, launcherPrograms)
    }

    static func isChat(_ id: String) -> Bool {
        matches(id, chatApps, chatPrograms)
    }

    static func isCodeEditor(_ id: String) -> Bool {
        matches(id, codeEditors, codeEditorPrograms)
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

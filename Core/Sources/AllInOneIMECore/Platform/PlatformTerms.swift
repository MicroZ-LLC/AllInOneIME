import Foundation

/// What the interface calls the keys and the places of the system it runs on (`Platform.terms`), so that the core's text
/// names them as that system does: on the Mac its symbols (⌘C, ⌃V, right ⌥, ⌥Space), "this Mac", Terminal and `.app`
/// bundles; on Windows the keys' names (Ctrl+C, Ctrl+V, right Ctrl, Ctrl+Space), "this PC", a terminal and the apps of
/// the Start menu (`.lnk`, `.exe`). Return, ⇧Return, Delete, Esc, Tab and the arrows are written the same everywhere
/// (⏎, ⇧⏎, ⌫, Esc, Tab, ↑↓), as are the digits that pick a row.
///
/// The keys follow `roles` (`ModifierRoles`, the composer's): what the text names is the key that does it there.
public struct PlatformTerms: Hashable, Sendable {
    /// How a key with modifiers is written: the Mac's symbols, run together ("⌘C"), or the modifiers' names with "+"
    /// ("Ctrl+C").
    public enum KeyStyle: Hashable, Sendable { case symbols, names }

    /// What "this device" is: the Mac, or a PC.
    public enum Device: Hashable, Sendable { case mac, pc }

    /// Where a command line runs: the Mac's Terminal app, or a terminal (Windows' console window).
    public enum Terminal: Hashable, Sendable { case terminalApp, window }

    public var keyStyle: KeyStyle
    /// Which modifier does what: the shortcuts', pasting into a draft's, the voice key's, the action tap's.
    public var roles: ModifierRoles
    public var device: Device
    public var terminal: Terminal
    /// The extensions of the files that are apps, lowercased ("app"; "lnk", "exe"): `@open` calls those 「应用」 / "app".
    public var appExtensions: [String]

    public init(keyStyle: KeyStyle, roles: ModifierRoles, device: Device, terminal: Terminal, appExtensions: [String]) {
        self.keyStyle = keyStyle
        self.roles = roles
        self.device = device
        self.terminal = terminal
        self.appExtensions = appExtensions
    }

    public static let mac = PlatformTerms(keyStyle: .symbols, roles: .mac, device: .mac, terminal: .terminalApp,
                                          appExtensions: ["app"])
    public static let windows = PlatformTerms(keyStyle: .names, roles: .windows, device: .pc, terminal: .window,
                                              appExtensions: ["lnk", "exe"])

    // MARK: - Keys

    /// A modifier: "⌘", "⌃", "⌥", "⇧"; "Win", "Ctrl", "Alt", "Shift".
    public func name(_ modifier: Key.ModifierKind) -> String {
        switch (keyStyle, modifier) {
        case (.symbols, .command): return "⌘"
        case (.symbols, .control): return "⌃"
        case (.symbols, .option): return "⌥"
        case (.symbols, .shift): return "⇧"
        case (.names, .command): return "Win"
        case (.names, .control): return "Ctrl"
        case (.names, .option): return "Alt"
        case (.names, .shift): return "Shift"
        }
    }

    /// `key` pressed with `modifier`: "⌘C", "⌥Space"; "Ctrl+C", "Ctrl+Space".
    public func shortcut(_ modifier: Key.ModifierKind, _ key: String) -> String {
        name(modifier) + (keyStyle == .names ? "+" : "") + key
    }

    /// `key` with the shortcuts' modifier (`roles.primary`): "⌘R", "Ctrl+R".
    public func command(_ key: String) -> String { shortcut(roles.primary, key) }

    /// What copies a result: "⌘C", "Ctrl+C".
    public var copy: String { command("C") }

    /// What pastes into a draft: "⌃V" on the Mac (pasted there in every app, `roles.pasteAnywhere`), "Ctrl+V" on Windows.
    public var paste: String { shortcut(roles.pasteAnywhere ?? roles.primary, "V") }

    /// What asks again (a saved answer) or writes more (`@reply`): "⌘R", "Ctrl+R".
    public var again: String { command("R") }

    /// What picks the `number`th of a list of shortcuts (where a conversation can go on): "⌘2", "Ctrl+2".
    public func pick(_ number: Int) -> String { command(String(number)) }

    /// What picks one of the first `count`: "⌘1", "⌘1–⌘3"; "Ctrl+1", "Ctrl+1–3".
    public func picks(_ count: Int) -> String {
        guard count > 1 else { return pick(1) }
        return pick(1) + "–" + (keyStyle == .symbols ? pick(count) : String(count))
    }

    /// The key held to dictate, which the text says is the right one ("right ⌥"): "⌥", "Ctrl".
    public var voiceKey: String { name(roles.voiceHold.kind) }

    /// The key tapped on its own as the action key (`ActionKey.optionTap`): "⌥", "Ctrl".
    public var actionTap: String { name(roles.actionTap) }

    // MARK: - Places

    /// Whether `path` is an app (its extension one of `appExtensions`, in any case).
    public func isApp(_ path: String) -> Bool {
        let name = path.lowercased()
        return appExtensions.contains { name.hasSuffix("." + $0) }
    }
}

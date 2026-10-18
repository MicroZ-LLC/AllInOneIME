import Foundation

/// The key that runs the @ command at the start of a finished sentence (config `actionKey`), e.g.
/// `@improve`: translate or polish it, with rewrites.
public enum ActionKey: Hashable, Sendable, CaseIterable {
    /// Return (the default). ⇧Return then inserts the sentence as typed.
    case enter
    /// Either Option key pressed and released on its own (holding the right one still dictates).
    /// Space keeps its usual meaning: it picks candidates, and in a draft it is a space.
    case optionTap
    /// ⌥Space. Space keeps its usual meaning, as with `optionTap`.
    case optionSpace
    /// Space on a finished sentence, a double Space in English mode (the original behavior).
    case space
    /// A key the user recorded in the settings (⌃⏎, ⌘⏎, F5…). Return runs @ commands too.
    case shortcut(KeyShortcut)

    /// The keys with their own handling; anything else is recorded as a `shortcut`.
    public static var allCases: [ActionKey] { [.enter, .optionTap, .optionSpace, .space] }

    /// What a recorded key press becomes: Return, Space and ⌥Space are the keys with their own
    /// handling; a key that types text needs ⌃, ⌥ or ⌘ (else it couldn't be typed any more).
    /// Nil: not usable (Esc, a plain letter). The Mac's key code.
    public static func recorded(keyCode: UInt16, modifiers: KeyModifiers, name: String) -> ActionKey? {
        recorded(KeyShortcut(keyCode: keyCode, modifiers: modifiers, name: name), key: MacKeyCodes.key(keyCode))
    }

    /// `recorded(keyCode:…)` from another system's key: its `Key` and usage, with `roles.primary` (Ctrl on Windows)
    /// kept as ⌘, so the shortcut is the same one on every system (`KeyShortcut.matches`).
    public static func recorded(key: Key, usage: UInt16, modifiers: Modifiers, name: String,
                                roles: ModifierRoles = .mac) -> ActionKey? {
        var modifiers = modifiers
        let primary = Modifiers.kind(roles.primary)
        if primary != .command, modifiers.contains(primary) {
            modifiers.remove(primary)
            modifiers.insert(.command)
        }
        return recorded(KeyShortcut(usage: usage, modifiers: modifiers, name: name), key: key)
    }

    private static func recorded(_ shortcut: KeyShortcut, key: Key) -> ActionKey? {
        let modifiers = shortcut.modifiers.intersection([.shift, .control, .option, .command])
        switch (key, modifiers) {
        case (.enter, []), (.keypadEnter, []): return .enter
        case (.space, []): return .space
        case (.space, [.option]): return .optionSpace
        case (.escape, _): return nil
        default: break
        }
        if !typesNothing(key), modifiers.isDisjoint(with: [.control, .option, .command]) { return nil }
        var recorded = shortcut
        recorded.modifiers = modifiers
        return .shortcut(recorded)
    }

    /// Keys that type nothing: fine on their own (Return, Tab, ⌫, arrows, F1–F20…).
    static func typesNothing(_ key: Key) -> Bool {
        switch key {
        case .enter, .keypadEnter, .tab, .backspace, .forwardDelete, .f, .arrow, .home, .end, .pageUp, .pageDown: return true
        default: return false
        }
    }

    /// Name in hints and settings ("⏎ → 翻译成英文": ⏎ → translate into English).
    public var displayName: String {
        switch self {
        case .enter: return "⏎"
        case .optionSpace: return "⌥空格"
        case .optionTap: return "单按 ⌥"
        case .space: return "空格"
        case let .shortcut(key): return key.name
        }
    }

    /// How to press it, in Chinese, as in "打中文按 ⏎" (type Chinese, press ⏎): "按 ⏎", "按 ⌥空格",
    /// "单按 ⌥", "按空格". `UIText.howToPress` has the English.
    public func howToPress() -> String {
        switch self {
        case .enter: return "按 ⏎"
        case .optionSpace: return "按 ⌥空格"
        case .optionTap: return "单按 ⌥"
        case .space: return "按空格"
        case let .shortcut(key): return "按 " + key.name
        }
    }
}

/// A recorded key: where it is, the modifiers held, and how it reads ("⌃⏎", "⌘J", "F5"). In the config it has both the
/// Mac's key code and the key's usage, so a Mac that only reads `keyCode` (0.6.4 and before) and another system can
/// both use it; either one is enough to read it.
public struct KeyShortcut: Hashable, Codable, Sendable {
    /// The Mac's key code (`KeyEvent.noKeyCode` for a key the Mac doesn't have).
    public var keyCode: UInt16
    /// Where the key is (`KeyEvent.usage`), which it matches by; 0 for one the tables don't have, matched by `keyCode`.
    public var usage: UInt16
    /// Recorded with ⌘ means with `ModifierRoles.primary` (Ctrl on Windows).
    public var modifiers: KeyModifiers
    public var name: String

    public init(keyCode: UInt16, modifiers: KeyModifiers, name: String) {
        self.keyCode = keyCode
        usage = MacKeyCodes.usage(keyCode)
        self.modifiers = modifiers
        self.name = name
    }

    public init(usage: UInt16, modifiers: KeyModifiers, name: String) {
        keyCode = MacKeyCodes.code(usage: usage) ?? KeyEvent.noKeyCode
        self.usage = usage
        self.modifiers = modifiers
        self.name = name
    }

    private enum CodingKeys: String, CodingKey { case keyCode, usage, modifiers, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let modifiers = KeyModifiers(rawValue: try c.decode(UInt16.self, forKey: .modifiers))
        let name = try c.decode(String.self, forKey: .name)
        switch (try c.decodeIfPresent(UInt16.self, forKey: .keyCode), try c.decodeIfPresent(UInt16.self, forKey: .usage)) {
        case let (keyCode?, usage?):
            self.init(keyCode: keyCode, modifiers: modifiers, name: name)
            self.usage = usage
        case let (keyCode?, nil): self.init(keyCode: keyCode, modifiers: modifiers, name: name)
        case let (nil, usage?): self.init(usage: usage, modifiers: modifiers, name: name)
        case (nil, nil):
            throw DecodingError.keyNotFound(CodingKeys.keyCode, .init(codingPath: c.codingPath, debugDescription: "neither keyCode nor usage"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(usage, forKey: .usage)
        try c.encode(modifiers.rawValue, forKey: .modifiers)
        try c.encode(name, forKey: .name)
    }

    /// Whether `event` is this key (Caps Lock aside), ⌘ being `roles.primary`.
    public func matches(_ event: KeyEvent, roles: ModifierRoles = .mac) -> Bool {
        var wanted = modifiers
        let primary = Modifiers.kind(roles.primary)
        if primary != .command, wanted.contains(.command) {
            wanted.remove(.command)
            wanted.insert(primary)
        }
        let sameKey = usage != 0 ? event.usage == usage : event.keyCode == keyCode
        return sameKey && event.modifiers.intersection([.shift, .control, .option, .command]) == wanted
    }
}

/// In the config: a name for the keys with their own handling ("enter", "optionTap", …), an object
/// for a recorded one (`{"keyCode": 36, "usage": 40, "modifiers": 2, "name": "⌃⏎"}`).
extension ActionKey: Codable {
    var rawName: String? {
        switch self {
        case .enter: return "enter"
        case .optionTap: return "optionTap"
        case .optionSpace: return "optionSpace"
        case .space: return "space"
        case .shortcut: return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let name = try? c.decode(String.self) {
            guard let key = Self.allCases.first(where: { $0.rawName == name }) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown action key \(name)")
            }
            self = key
        } else {
            self = .shortcut(try c.decode(KeyShortcut.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if case let .shortcut(key) = self { try c.encode(key) } else { try c.encode(rawName) }
    }
}

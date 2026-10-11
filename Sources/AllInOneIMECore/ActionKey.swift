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
    /// Nil: not usable (Esc, a plain letter).
    public static func recorded(keyCode: UInt16, modifiers: KeyModifiers, name: String) -> ActionKey? {
        let modifiers = modifiers.intersection([.shift, .control, .option, .command])
        switch (keyCode, modifiers) {
        case (VirtualKey.returnKey, []), (VirtualKey.keypadEnter, []): return .enter
        case (VirtualKey.space, []): return .space
        case (VirtualKey.space, [.option]): return .optionSpace
        case (VirtualKey.escape, _): return nil
        default: break
        }
        let typesText = !Self.functionKeys.contains(keyCode)
        if typesText, modifiers.isDisjoint(with: [.control, .option, .command]) { return nil }
        return .shortcut(KeyShortcut(keyCode: keyCode, modifiers: modifiers, name: name))
    }

    /// Keys that type nothing: fine on their own (Return, Tab, ⌫, arrows, F1–F20…).
    static let functionKeys: Set<UInt16> = [
        VirtualKey.returnKey, VirtualKey.keypadEnter, VirtualKey.tab, VirtualKey.delete, VirtualKey.forwardDelete,
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
        0x7B, 0x7C, 0x7D, 0x7E, 0x73, 0x77, 0x74, 0x79,
    ]
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

/// A recorded key: its code, the modifiers held, and how it reads ("⌃⏎", "⌘J", "F5").
public struct KeyShortcut: Hashable, Codable, Sendable {
    public var keyCode: UInt16
    public var modifiers: KeyModifiers
    public var name: String

    public init(keyCode: UInt16, modifiers: KeyModifiers, name: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.name = name
    }

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        modifiers = KeyModifiers(rawValue: try c.decode(UInt8.self, forKey: .modifiers))
        name = try c.decode(String.self, forKey: .name)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(modifiers.rawValue, forKey: .modifiers)
        try c.encode(name, forKey: .name)
    }

    /// Whether `event` is this key (Caps Lock aside).
    public func matches(_ event: KeyEvent) -> Bool {
        event.keyCode == keyCode && event.modifiers.intersection([.shift, .control, .option, .command]) == modifiers
    }
}

/// In the config: a name for the keys with their own handling ("enter", "optionTap", …), an object
/// for a recorded one (`{"keyCode": 36, "modifiers": 2, "name": "⌃⏎"}`).
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

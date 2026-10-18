import Foundation

/// A key by what it does, the same on every system and keyboard layout: Return is `.enter` whatever the Mac's key code
/// or Windows' virtual key. Keys that type text are all `.character` (what they type is the event's `characters`); where
/// the key sits on the keyboard is its `usage` (`KeyEvent.usage`). Each shell maps its own codes to these
/// (`MacKeyCodes`, `WindowsKeyCodes`).
public enum Key: Hashable, Sendable {
    /// A key that types text: a letter, digit or punctuation, the keypad's too.
    case character
    case enter
    /// The keypad's Enter (⌤).
    case keypadEnter
    case tab
    case space
    /// ⌫ (the Mac's Delete).
    case backspace
    /// ⌦
    case forwardDelete
    case escape
    case arrow(Arrow)
    case home, end, pageUp, pageDown
    /// Insert (the Mac's Help key sits there).
    case insert
    /// F1, F2 …
    case f(Int)
    /// Shift, Control, Option (Alt) or Command (the Windows key), and which of the two.
    case modifier(ModifierKind, Side)
    case capsLock
    /// fn (🌐), the Mac's.
    case function
    /// Any other (volume, Print Screen, the Japanese keyboards' Eisu and Kana …): only its `usage` tells it.
    case other

    public enum Arrow: Hashable, Sendable { case left, right, up, down }
    public enum ModifierKind: Hashable, Sendable, CaseIterable { case shift, control, option, command }
    public enum Side: Hashable, Sendable { case left, right }

    /// Shift, Control, Option or Command, either side.
    public var modifierKind: ModifierKind? {
        if case let .modifier(kind, _) = self { return kind }
        return nil
    }
}

/// A key as its name, the form it is written in (`Codable`, the same on every system and in any wire protocol): "enter",
/// "keypadEnter", "tab", "space", "backspace", "forwardDelete", "escape", "arrowLeft" … "arrowDown", "home", "end",
/// "pageUp", "pageDown", "insert", "f1" … "f24", "shiftLeft" … "commandRight" (kind, then side), "capsLock",
/// "function", "character" (what it types is the event's text, where it is its usage) and "other". A name this version
/// doesn't know (a later one's key) reads as "other".
extension Key: Codable {
    public var name: String {
        switch self {
        case .character: return "character"
        case .enter: return "enter"
        case .keypadEnter: return "keypadEnter"
        case .tab: return "tab"
        case .space: return "space"
        case .backspace: return "backspace"
        case .forwardDelete: return "forwardDelete"
        case .escape: return "escape"
        case let .arrow(arrow): return "arrow" + Self.capitalized(arrow.name)
        case .home: return "home"
        case .end: return "end"
        case .pageUp: return "pageUp"
        case .pageDown: return "pageDown"
        case .insert: return "insert"
        case let .f(n): return "f\(n)"
        case let .modifier(kind, side): return kind.name + Self.capitalized(side.name)
        case .capsLock: return "capsLock"
        case .function: return "function"
        case .other: return "other"
        }
    }

    /// The key named `name` (`name`); `.other` for a name this version doesn't know.
    public init(name: String) {
        if let key = Self.byName[name] {
            self = key
        } else if name.hasPrefix("f"), let n = Int(name.dropFirst()), n >= 1, String(n) == name.dropFirst() {
            self = .f(n)
        } else {
            self = .other
        }
    }

    /// Every key but the function keys, by name.
    private static let byName: [String: Key] = {
        var keys: [Key] = [.character, .enter, .keypadEnter, .tab, .space, .backspace, .forwardDelete, .escape,
                           .home, .end, .pageUp, .pageDown, .insert, .capsLock, .function, .other]
        keys += [Arrow.left, .right, .up, .down].map(Key.arrow)
        for kind in ModifierKind.allCases { keys += [Side.left, .right].map { .modifier(kind, $0) } }
        return Dictionary(uniqueKeysWithValues: keys.map { ($0.name, $0) })
    }()

    private static func capitalized(_ word: String) -> String { word.prefix(1).uppercased() + word.dropFirst() }

    public init(from decoder: Decoder) throws { self.init(name: try decoder.singleValueContainer().decode(String.self)) }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(name)
    }
}

extension Key.Arrow {
    var name: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        case .up: return "up"
        case .down: return "down"
        }
    }
}

extension Key.ModifierKind {
    var name: String {
        switch self {
        case .shift: return "shift"
        case .control: return "control"
        case .option: return "option"
        case .command: return "command"
        }
    }
}

extension Key.Side {
    var name: String { self == .left ? "left" : "right" }
}

/// The modifiers held with a key. The kinds (Shift … Command, Caps Lock, fn) are on every event; which side's key is
/// down only on modifier changes, and only where the system tells (the Mac tells it for Option only).
public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    /// Option, Alt on Windows.
    public static let option = Modifiers(rawValue: 1 << 2)
    /// Command, the Windows key on Windows.
    public static let command = Modifiers(rawValue: 1 << 3)
    public static let capsLock = Modifiers(rawValue: 1 << 4)
    /// Which Option key is down (device-dependent bits, only set for modifier-change events).
    public static let leftOption = Modifiers(rawValue: 1 << 5)
    public static let rightOption = Modifiers(rawValue: 1 << 6)
    /// fn (🌐) is down: only set for Translate as You Type's long press of Shift (`TranslateMode.ShiftHold`); the
    /// system sets it on arrow and function keys too, so key-downs don't carry it.
    public static let function = Modifiers(rawValue: 1 << 7)
    /// The other sides, as `leftOption` and `rightOption` (the Mac's events set none of them).
    public static let leftShift = Modifiers(rawValue: 1 << 8)
    public static let rightShift = Modifiers(rawValue: 1 << 9)
    public static let leftControl = Modifiers(rawValue: 1 << 10)
    public static let rightControl = Modifiers(rawValue: 1 << 11)
    public static let leftCommand = Modifiers(rawValue: 1 << 12)
    public static let rightCommand = Modifiers(rawValue: 1 << 13)
    /// AltGr is down: Windows reports it as Ctrl+Alt, which a shell marks with this (`WindowsKeyCodes.markingAltGraph`).
    /// A key that types with it is text, not a ⌃⌥ shortcut (`KeyEvent.init(key:usage:…)`, which takes the mark off).
    public static let altGraph = Modifiers(rawValue: 1 << 14)

    /// Every side bit.
    public static let sides: Modifiers = [.leftShift, .rightShift, .leftControl, .rightControl,
                                          .leftOption, .rightOption, .leftCommand, .rightCommand]

    /// The bit of a kind, either side: `.option` for Option.
    public static func kind(_ kind: Key.ModifierKind) -> Modifiers {
        switch kind {
        case .shift: return .shift
        case .control: return .control
        case .option: return .option
        case .command: return .command
        }
    }

    /// The bit of one side's key: `.rightOption` for the right Option.
    public static func side(_ side: Key.Side, of kind: Key.ModifierKind) -> Modifiers {
        switch (kind, side) {
        case (.shift, .left): return .leftShift
        case (.shift, .right): return .rightShift
        case (.control, .left): return .leftControl
        case (.control, .right): return .rightControl
        case (.option, .left): return .leftOption
        case (.option, .right): return .rightOption
        case (.command, .left): return .leftCommand
        case (.command, .right): return .rightCommand
        }
    }

    /// Both sides' bits of a kind.
    public static func sides(of kind: Key.ModifierKind) -> Modifiers { [side(.left, of: kind), side(.right, of: kind)] }

    /// Each bit's name, in the bits' order (bit 0 first): the names the modifiers are written with (`Codable`).
    public static let names: [(name: String, modifier: Modifiers)] = [
        ("shift", .shift), ("control", .control), ("option", .option), ("command", .command), ("capsLock", .capsLock),
        ("leftOption", .leftOption), ("rightOption", .rightOption), ("function", .function),
        ("leftShift", .leftShift), ("rightShift", .rightShift), ("leftControl", .leftControl),
        ("rightControl", .rightControl), ("leftCommand", .leftCommand), ("rightCommand", .rightCommand),
        ("altGraph", .altGraph),
    ]
}

/// Written as a list of names (`Modifiers.names`, in the bits' order: `["shift", "command"]`), the same on every
/// system. Read from that, names this version doesn't know left out, or from the number of the bits (the bit layout
/// above, which config.json's recorded shortcuts use: `KeyShortcut`).
extension Modifiers: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let raw = try? c.decode(UInt16.self) {
            self.init(rawValue: raw)
            return
        }
        let names = try c.decode([String].self)
        self = Modifiers(Self.names.filter { names.contains($0.name) }.map(\.modifier))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(Self.names.filter { contains($0.modifier) }.map(\.name))
    }
}

/// One modifier key: its kind and which side's (the right Option).
public struct ModifierKey: Hashable, Sendable {
    public var kind: Key.ModifierKind
    public var side: Key.Side

    public init(_ kind: Key.ModifierKind, _ side: Key.Side) {
        self.kind = kind
        self.side = side
    }

    /// The key (`.modifier(kind, side)`), as a modifier change names it.
    public var key: Key { .modifier(kind, side) }
}

/// What each modifier is for, which a shell sets to its system's habits (`mac`, `windows`). The core asks these, never
/// ⌘ or ⌥ by name: what a modifier does with a key is the system's, not the key's.
public struct ModifierRoles: Hashable, Sendable {
    /// Shortcuts' modifier: ⌘ on the Mac, Ctrl on Windows. The input method's own are with it (⌘C on a result, ⌘V
    /// into a draft, ⌘⏎ and ⌘1 … in a conversation, ⌘R on a saved answer); any other key with it is the app's. A
    /// shortcut recorded with ⌘ (`KeyShortcut`) is pressed with it (`swappingPrimary`).
    public var primary: Key.ModifierKind
    /// With ← →, a word at a time: ⌥ on the Mac, Ctrl on Windows.
    public var word: Key.ModifierKind
    /// With ← →, to the start or end of the text: ⌘ on the Mac. Nil on Windows, which has Home and End for it (they do
    /// it everywhere).
    public var lineEdge: Key.ModifierKind?
    /// With V, pastes into the draft in every app, also where the app pastes on `primary` V itself: ⌃V on the Mac (no
    /// app pastes on it). Nil on Windows, where Ctrl+V is `primary`'s.
    public var pasteAnywhere: Key.ModifierKind?
    /// Held on its own to dictate: the right Option on the Mac.
    public var voiceHold: ModifierKey
    /// Either key of this kind pressed and released on its own is the `optionTap` action key, and held with Space the
    /// `optionSpace` one: Option on the Mac.
    public var actionTap: Key.ModifierKind

    public init(primary: Key.ModifierKind, word: Key.ModifierKind, lineEdge: Key.ModifierKind?,
                pasteAnywhere: Key.ModifierKind?, voiceHold: ModifierKey, actionTap: Key.ModifierKind) {
        self.primary = primary
        self.word = word
        self.lineEdge = lineEdge
        self.pasteAnywhere = pasteAnywhere
        self.voiceHold = voiceHold
        self.actionTap = actionTap
    }

    public static let mac = ModifierRoles(primary: .command, word: .option, lineEdge: .command, pasteAnywhere: .control,
                                          voiceHold: ModifierKey(.option, .right), actionTap: .option)

    /// Windows' habits: Ctrl for shortcuts and a word at a time (Home and End go to the start and end); a tap of either
    /// Ctrl is the `optionTap` action key and Ctrl+Space `optionSpace` (a tap of Alt opens the window's menu bar, and
    /// Alt+Space its system menu); the right Ctrl held dictates. Not the right Alt: on the layouts with AltGr (German,
    /// French, Polish …) it is AltGr, which types characters (Windows reports it as Ctrl+Alt: `Modifiers.altGraph`).
    public static let windows = ModifierRoles(primary: .control, word: .control, lineEdge: nil, pasteAnywhere: nil,
                                              voiceHold: ModifierKey(.control, .right), actionTap: .control)

    /// A recorded shortcut's modifiers (`KeyShortcut`, in the Mac's terms) as this system's, or back: `primary` and ⌘
    /// change places (on Windows Ctrl and the Windows key), so each of them stays a key of its own. Its own inverse.
    public func swappingPrimary(_ modifiers: Modifiers) -> Modifiers {
        let primary = Modifiers.kind(self.primary)
        guard primary != .command else { return modifiers }
        var swapped = modifiers.subtracting([primary, .command])
        if modifiers.contains(primary) { swapped.insert(.command) }
        if modifiers.contains(.command) { swapped.insert(primary) }
        return swapped
    }
}

/// The Mac's key codes (Carbon's `kVK_*`, HIToolbox/Events.h): each one's `Key` and USB HID usage (page 7, the
/// keyboard page). Plain data; the usages agree with Chromium's dom_code_data.inc.
public enum MacKeyCodes {
    /// Every key code the Mac has, with its key and usage. kVK_Function (fn) has no usage on page 7 (Apple's is vendor
    /// page 0xFF): 0, as for an unknown key.
    public static let entries: [(code: UInt16, key: Key, usage: UInt16)] = [
        (0x00, .character, 0x04), (0x0B, .character, 0x05), (0x08, .character, 0x06), (0x02, .character, 0x07),  // A B C D
        (0x0E, .character, 0x08), (0x03, .character, 0x09), (0x05, .character, 0x0A), (0x04, .character, 0x0B),  // E F G H
        (0x22, .character, 0x0C), (0x26, .character, 0x0D), (0x28, .character, 0x0E), (0x25, .character, 0x0F),  // I J K L
        (0x2E, .character, 0x10), (0x2D, .character, 0x11), (0x1F, .character, 0x12), (0x23, .character, 0x13),  // M N O P
        (0x0C, .character, 0x14), (0x0F, .character, 0x15), (0x01, .character, 0x16), (0x11, .character, 0x17),  // Q R S T
        (0x20, .character, 0x18), (0x09, .character, 0x19), (0x0D, .character, 0x1A), (0x07, .character, 0x1B),  // U V W X
        (0x10, .character, 0x1C), (0x06, .character, 0x1D),                                                      // Y Z
        (0x12, .character, 0x1E), (0x13, .character, 0x1F), (0x14, .character, 0x20), (0x15, .character, 0x21),  // 1 2 3 4
        (0x17, .character, 0x22), (0x16, .character, 0x23), (0x1A, .character, 0x24), (0x1C, .character, 0x25),  // 5 6 7 8
        (0x19, .character, 0x26), (0x1D, .character, 0x27),                                                      // 9 0
        (0x24, .enter, 0x28), (0x35, .escape, 0x29), (0x33, .backspace, 0x2A), (0x30, .tab, 0x2B), (0x31, .space, 0x2C),
        (0x1B, .character, 0x2D), (0x18, .character, 0x2E), (0x21, .character, 0x2F), (0x1E, .character, 0x30),  // - = [ ]
        (0x2A, .character, 0x31), (0x29, .character, 0x33), (0x27, .character, 0x34), (0x32, .character, 0x35),  // \ ; ' `
        (0x2B, .character, 0x36), (0x2F, .character, 0x37), (0x2C, .character, 0x38),                            // , . /
        (0x39, .capsLock, 0x39),
        (0x7A, .f(1), 0x3A), (0x78, .f(2), 0x3B), (0x63, .f(3), 0x3C), (0x76, .f(4), 0x3D), (0x60, .f(5), 0x3E),
        (0x61, .f(6), 0x3F), (0x62, .f(7), 0x40), (0x64, .f(8), 0x41), (0x65, .f(9), 0x42), (0x6D, .f(10), 0x43),
        (0x67, .f(11), 0x44), (0x6F, .f(12), 0x45),
        (0x72, .insert, 0x49),  // Help, where PC keyboards have Insert
        (0x73, .home, 0x4A), (0x74, .pageUp, 0x4B), (0x75, .forwardDelete, 0x4C), (0x77, .end, 0x4D),
        (0x79, .pageDown, 0x4E),
        (0x7C, .arrow(.right), 0x4F), (0x7B, .arrow(.left), 0x50), (0x7D, .arrow(.down), 0x51), (0x7E, .arrow(.up), 0x52),
        (0x47, .other, 0x53),  // the keypad's Clear, where PC keyboards have Num Lock
        (0x4B, .character, 0x54), (0x43, .character, 0x55), (0x4E, .character, 0x56), (0x45, .character, 0x57),  // keypad / * - +
        (0x4C, .keypadEnter, 0x58),
        (0x53, .character, 0x59), (0x54, .character, 0x5A), (0x55, .character, 0x5B), (0x56, .character, 0x5C),  // keypad 1 2 3 4
        (0x57, .character, 0x5D), (0x58, .character, 0x5E), (0x59, .character, 0x5F), (0x5B, .character, 0x60),  // keypad 5 6 7 8
        (0x5C, .character, 0x61), (0x52, .character, 0x62), (0x41, .character, 0x63),                            // keypad 9 0 .
        // kVK_ISO_Section: the HID's Non-US \ (next to the left Shift on ISO keyboards). On Apple's ISO keyboards macOS
        // reports that key as kVK_ANSI_Grave and the § left of 1 as this: the Mac shell swaps the two before the usage
        // (`MacKeyboard`, AllInOneIMEMac), as Chromium and Firefox do.
        (0x0A, .character, 0x64),
        (0x6E, .other, 0x65),  // the context-menu key
        (0x51, .character, 0x67),  // keypad =
        (0x69, .f(13), 0x68), (0x6B, .f(14), 0x69), (0x71, .f(15), 0x6A), (0x6A, .f(16), 0x6B), (0x40, .f(17), 0x6C),
        (0x4F, .f(18), 0x6D), (0x50, .f(19), 0x6E), (0x5A, .f(20), 0x6F),
        (0x4A, .other, 0x7F), (0x48, .other, 0x80), (0x49, .other, 0x81),  // mute, volume up, volume down
        (0x5F, .character, 0x85),  // JIS keypad ,
        (0x5E, .character, 0x87),  // JIS _ (International1, Ro)
        (0x5D, .character, 0x89),  // JIS ¥ (International3)
        (0x68, .other, 0x90), (0x66, .other, 0x91),  // JIS かな and 英数 (LANG1, LANG2)
        (0x3B, .modifier(.control, .left), 0xE0), (0x38, .modifier(.shift, .left), 0xE1),
        (0x3A, .modifier(.option, .left), 0xE2), (0x37, .modifier(.command, .left), 0xE3),
        (0x3E, .modifier(.control, .right), 0xE4), (0x3C, .modifier(.shift, .right), 0xE5),
        (0x3D, .modifier(.option, .right), 0xE6), (0x36, .modifier(.command, .right), 0xE7),
        (0x3F, .function, 0),
    ]

    private static let byCode: [UInt16: (key: Key, usage: UInt16)] =
        Dictionary(uniqueKeysWithValues: entries.map { ($0.code, ($0.key, $0.usage)) })
    private static let byUsage: [UInt16: UInt16] =
        Dictionary(uniqueKeysWithValues: entries.filter { $0.usage != 0 }.map { ($0.usage, $0.code) })

    /// A key code's key: `.other` for one the table doesn't have.
    public static func key(_ code: UInt16) -> Key { byCode[code]?.key ?? .other }
    /// A key code's usage: 0 for one the table doesn't have.
    public static func usage(_ code: UInt16) -> UInt16 { byCode[code]?.usage ?? 0 }
    /// The key code at a usage: nil where the Mac has no such key.
    public static func code(usage: UInt16) -> UInt16? { byUsage[usage] }
}

/// Windows' codes: the scan code a key sends (set 1, as `WM_KEYDOWN`'s lParam and TSF's key events give it) → its USB
/// HID usage, and the virtual key (`VK_*`) → its `Key`. Plain data, from Microsoft's "USB HID to PS/2 Scan Code
/// Translation Table" and the Virtual-Key Codes reference; the scan codes agree with Chromium's dom_code_data.inc.
public enum WindowsKeyCodes {
    /// An extended key's scan code carries 0xE0 above it (lParam bit 24): the keypad's Enter is 0xE01C, Return 0x1C.
    /// Num Lock is 0xE045 and Pause 0x0045, as Windows reports them (Chromium's convention), though the scan-code
    /// table writes Pause as E1 1D 45.
    public static let usageByScanCode: [UInt16: UInt16] = [
        0x001E: 0x04, 0x0030: 0x05, 0x002E: 0x06, 0x0020: 0x07, 0x0012: 0x08, 0x0021: 0x09, 0x0022: 0x0A,  // A–G
        0x0023: 0x0B, 0x0017: 0x0C, 0x0024: 0x0D, 0x0025: 0x0E, 0x0026: 0x0F, 0x0032: 0x10, 0x0031: 0x11,  // H–N
        0x0018: 0x12, 0x0019: 0x13, 0x0010: 0x14, 0x0013: 0x15, 0x001F: 0x16, 0x0014: 0x17, 0x0016: 0x18,  // O–U
        0x002F: 0x19, 0x0011: 0x1A, 0x002D: 0x1B, 0x0015: 0x1C, 0x002C: 0x1D,                              // V–Z
        0x0002: 0x1E, 0x0003: 0x1F, 0x0004: 0x20, 0x0005: 0x21, 0x0006: 0x22, 0x0007: 0x23, 0x0008: 0x24,  // 1–7
        0x0009: 0x25, 0x000A: 0x26, 0x000B: 0x27,                                                          // 8 9 0
        0x001C: 0x28, 0x0001: 0x29, 0x000E: 0x2A, 0x000F: 0x2B, 0x0039: 0x2C,  // Enter Esc Backspace Tab Space
        0x000C: 0x2D, 0x000D: 0x2E, 0x001A: 0x2F, 0x001B: 0x30, 0x002B: 0x31,  // - = [ ] \ (ISO #, the same key)
        0x0027: 0x33, 0x0028: 0x34, 0x0029: 0x35, 0x0033: 0x36, 0x0034: 0x37, 0x0035: 0x38,  // ; ' ` , . /
        0x003A: 0x39,  // Caps Lock
        0x003B: 0x3A, 0x003C: 0x3B, 0x003D: 0x3C, 0x003E: 0x3D, 0x003F: 0x3E, 0x0040: 0x3F, 0x0041: 0x40,  // F1–F7
        0x0042: 0x41, 0x0043: 0x42, 0x0044: 0x43, 0x0057: 0x44, 0x0058: 0x45,                              // F8–F12
        0xE037: 0x46, 0x0046: 0x47, 0x0045: 0x48,  // Print Screen, Scroll Lock, Pause
        0xE052: 0x49, 0xE047: 0x4A, 0xE049: 0x4B, 0xE053: 0x4C, 0xE04F: 0x4D, 0xE051: 0x4E,  // Insert Home PgUp Del End PgDn
        0xE04D: 0x4F, 0xE04B: 0x50, 0xE050: 0x51, 0xE048: 0x52,  // → ← ↓ ↑
        0xE045: 0x53, 0xE035: 0x54, 0x0037: 0x55, 0x004A: 0x56, 0x004E: 0x57, 0xE01C: 0x58,  // Num Lock, keypad / * - + Enter
        0x004F: 0x59, 0x0050: 0x5A, 0x0051: 0x5B, 0x004B: 0x5C, 0x004C: 0x5D, 0x004D: 0x5E,  // keypad 1–6
        0x0047: 0x5F, 0x0048: 0x60, 0x0049: 0x61, 0x0052: 0x62, 0x0053: 0x63,                // keypad 7 8 9 0 .
        0x0056: 0x64, 0xE05D: 0x65, 0x0059: 0x67,  // ISO \ (next to left Shift), the context-menu key, keypad =
        0x0064: 0x68, 0x0065: 0x69, 0x0066: 0x6A, 0x0067: 0x6B, 0x0068: 0x6C, 0x0069: 0x6D,  // F13–F18
        0x006A: 0x6E, 0x006B: 0x6F, 0x006C: 0x70, 0x006D: 0x71, 0x006E: 0x72, 0x0076: 0x73,  // F19–F24
        0xE020: 0x7F, 0xE030: 0x80, 0xE02E: 0x81,  // mute, volume up, volume down
        0x007E: 0x85, 0x0073: 0x87, 0x0070: 0x88, 0x007D: 0x89, 0x0079: 0x8A, 0x007B: 0x8B,  // keypad , Ro かな ¥ 変換 無変換
        0x0072: 0x90, 0x0071: 0x91, 0x0078: 0x92, 0x0077: 0x93,  // LANG1 (한/영, かな), LANG2 (한자, 英数), LANG3, LANG4
        0x001D: 0xE0, 0x002A: 0xE1, 0x0038: 0xE2, 0xE05B: 0xE3,  // left Ctrl Shift Alt Win
        0xE01D: 0xE4, 0x0036: 0xE5, 0xE038: 0xE6, 0xE05C: 0xE7,  // right Ctrl Shift Alt Win
    ]

    /// AltGr, as Windows reports it: Ctrl and Alt down, the right Alt among them (on the layouts with AltGr, Windows adds a
    /// left Ctrl of its own to the right Alt). Marked `altGraph`, a key that types with it is text (`KeyEvent`), so
    /// AltGr+Q's "@" on a German layout is an "@", not a Ctrl+Alt shortcut.
    public static func markingAltGraph(_ modifiers: Modifiers, rightAltDown: Bool) -> Modifiers {
        rightAltDown && modifiers.isSuperset(of: [.control, .option]) ? modifiers.union(.altGraph) : modifiers
    }

    /// A scan code's usage (`extended`: lParam bit 24): 0 for one the table doesn't have.
    public static func usage(scanCode: UInt8, extended: Bool) -> UInt16 {
        usageByScanCode[(extended ? 0xE000 : 0) | UInt16(scanCode)] ?? 0
    }

    /// The Shift Windows sends of its own around a keypad key pressed with Shift while Num Lock is on, to make it the
    /// navigation key (E0 2A or E0 36, and E0 AA or E0 B6 as its release: Shift's scan code with the extended bit). No
    /// key was pressed: the shell drops it, so it is never a tap of Shift (and `key(virtualKey:usage:)`, its usage
    /// being 0, makes it no Shift either).
    public static func isFakeShift(scanCode: UInt8, extended: Bool) -> Bool {
        extended && (scanCode == 0x2A || scanCode == 0x36)
    }

    /// A virtual key's `Key`. The keys Windows gives one code for both of (`VK_RETURN`, `VK_SHIFT`, `VK_CONTROL`,
    /// `VK_MENU`) are told apart by the key's `usage` (`usage(scanCode:extended:)`); a `VK_SHIFT` at neither Shift's
    /// usage (`isFakeShift`'s) is `.other`.
    public static func key(virtualKey vk: UInt16, usage: UInt16) -> Key {
        switch vk {
        case 0x08: return .backspace                                   // VK_BACK
        case 0x09: return .tab                                         // VK_TAB
        case 0x0D: return usage == 0x58 ? .keypadEnter : .enter        // VK_RETURN
        case 0x10:                                                     // VK_SHIFT
            return usage == 0xE1 ? .modifier(.shift, .left) : usage == 0xE5 ? .modifier(.shift, .right) : .other
        case 0x11: return .modifier(.control, usage == 0xE4 ? .right : .left)  // VK_CONTROL
        case 0x12: return .modifier(.option, usage == 0xE6 ? .right : .left)   // VK_MENU (Alt)
        case 0x14: return .capsLock                                    // VK_CAPITAL
        case 0x1B: return .escape                                      // VK_ESCAPE
        case 0x20: return .space                                       // VK_SPACE
        case 0x21: return .pageUp                                      // VK_PRIOR
        case 0x22: return .pageDown                                    // VK_NEXT
        case 0x23: return .end
        case 0x24: return .home
        case 0x25: return .arrow(.left)
        case 0x26: return .arrow(.up)
        case 0x27: return .arrow(.right)
        case 0x28: return .arrow(.down)
        case 0x2D: return .insert
        case 0x2E: return .forwardDelete                               // VK_DELETE
        case 0x30...0x39, 0x41...0x5A: return .character               // 0–9, A–Z
        case 0x5B: return .modifier(.command, .left)                   // VK_LWIN
        case 0x5C: return .modifier(.command, .right)                  // VK_RWIN
        case 0x60...0x6F: return .character                            // VK_NUMPAD0 … VK_DIVIDE
        case 0x70...0x87: return .f(Int(vk) - 0x6F)                    // VK_F1 … VK_F24
        case 0xA0: return .modifier(.shift, .left)                     // VK_LSHIFT
        case 0xA1: return .modifier(.shift, .right)
        case 0xA2: return .modifier(.control, .left)                   // VK_LCONTROL
        case 0xA3: return .modifier(.control, .right)
        case 0xA4: return .modifier(.option, .left)                    // VK_LMENU
        case 0xA5: return .modifier(.option, .right)
        case 0xBA...0xC2, 0xDB...0xDF, 0xE2: return .character         // VK_OEM_1 … VK_ABNT_C2, VK_OEM_4 … 8, VK_OEM_102
        default: return .other
        }
    }
}

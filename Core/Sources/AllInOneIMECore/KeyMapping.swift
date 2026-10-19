import Foundation

/// The modifiers' first name, kept for the code written before `Modifiers` (Session/KeyInput.swift) told sides apart.
public typealias KeyModifiers = Modifiers

/// A key-down as the input method receives it from AppKit (or another system's shell: `init(key:usage:…)`).
public struct KeyEvent: Equatable, Sendable {
    /// The Mac's key code (`kVK_*`); `key` and `usage` follow it (`MacKeyCodes`), set or changed: they are never set
    /// apart from it (another key for the engine: `replacingKey`).
    public var keyCode: UInt16 {
        didSet { (key, usage) = (MacKeyCodes.key(keyCode), MacKeyCodes.usage(keyCode)) }
    }
    /// What the key does (Return, an arrow, a key that types), whatever the system and layout.
    public private(set) var key: Key
    /// Where the key is: its USB HID usage (page 7), the same key on every layout (0: unknown).
    public private(set) var usage: UInt16
    /// `NSEvent.characters`
    public var characters: String
    /// `NSEvent.charactersIgnoringModifiers` (still reflects Shift)
    public var charactersIgnoringModifiers: String
    public var modifiers: KeyModifiers
    /// Sent again because the key is held (`NSEvent.isARepeat`).
    public var isRepeat: Bool
    /// A dead key (⌥E, AZERTY's ^): `characters` is its accent, which goes on the next key (`DeadKeyComposer`).
    public var isDeadKey = false
    /// What this key types after a dead key ("é" for E after ⌥E; "´n" where the accent doesn't combine).
    public var composed: String?

    /// The Mac's: `key` and `usage` from the key code (`MacKeyCodes`), unless the shell knows the key's place better
    /// (`usage`: an ISO keyboard's two keys whose codes macOS swaps, `MacKeyboard` in AllInOneIMEMac).
    public init(
        keyCode: UInt16, usage: UInt16? = nil, characters: String, charactersIgnoringModifiers: String? = nil,
        modifiers: KeyModifiers = [], isRepeat: Bool = false
    ) {
        self.keyCode = keyCode
        key = MacKeyCodes.key(keyCode)
        self.usage = usage ?? MacKeyCodes.usage(keyCode)
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers ?? characters
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }

    /// Another system's: its key and usage (`WindowsKeyCodes`), and the Mac's key code at that usage (`noKeyCode` where
    /// the Mac has none). With `Modifiers.altGraph`, a key that types is text: its Ctrl and Alt (AltGr's, as Windows
    /// reports it) go, so it is never a ⌃⌥ shortcut; one that types nothing keeps them. The mark itself goes either way.
    public init(
        key: Key, usage: UInt16, characters: String, charactersIgnoringModifiers: String? = nil,
        modifiers: Modifiers = [], isRepeat: Bool = false
    ) {
        keyCode = MacKeyCodes.code(usage: usage) ?? Self.noKeyCode
        self.key = key
        self.usage = usage
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers ?? characters
        var modifiers = modifiers
        if modifiers.contains(.altGraph) {
            modifiers.remove(.altGraph)
            if !characters.isEmpty, characters.unicodeScalars.allSatisfy(Self.isPrintable) { modifiers.subtract([.control, .option]) }
        }
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }

    /// The key code of a key the Mac doesn't have.
    public static let noKeyCode: UInt16 = 0xFFFF

    /// The same event as another key, one the tables have (the row of candidates' ← sent to the engine as ↑): that key's
    /// usage and Mac code.
    public func replacingKey(_ key: Key) -> KeyEvent {
        var event = self
        if let entry = MacKeyCodes.entries.first(where: { $0.key == key }) {
            event.keyCode = entry.code
        } else {
            event.keyCode = Self.noKeyCode
            (event.key, event.usage) = (key, 0)
        }
        return event
    }

    /// The text this key types, if it is printable and not a shortcut.
    public var printableText: String? {
        guard modifiers.isDisjoint(with: [.control, .command]), !characters.isEmpty,
              characters.unicodeScalars.allSatisfy(Self.isPrintable)
        else { return nil }
        return characters
    }

    static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.generalCategory == .control { return false }
        if (0xF700...0xF8FF).contains(scalar.value) { return false }  // AppKit function-key range
        return true
    }
}

/// Carbon `kVK_*` virtual key codes, duplicated so Core does not depend on Carbon. The Mac shell's and its tests': the
/// core goes by `KeyEvent.key` and `usage` (`MacKeyCodes` has every code).
public enum VirtualKey {
    public static let returnKey: UInt16 = 0x24
    public static let keypadEnter: UInt16 = 0x4C
    public static let tab: UInt16 = 0x30
    public static let space: UInt16 = 0x31
    public static let delete: UInt16 = 0x33
    public static let escape: UInt16 = 0x35
    public static let forwardDelete: UInt16 = 0x75
    public static let home: UInt16 = 0x73
    public static let end: UInt16 = 0x77
    public static let pageUp: UInt16 = 0x74
    public static let pageDown: UInt16 = 0x79
    public static let left: UInt16 = 0x7B
    public static let right: UInt16 = 0x7C
    public static let down: UInt16 = 0x7D
    public static let up: UInt16 = 0x7E
    public static let leftShift: UInt16 = 0x38
    public static let rightShift: UInt16 = 0x3C
    public static let leftOption: UInt16 = 0x3A
    public static let rightOption: UInt16 = 0x3D
    /// F1–F12 in order.
    public static let functionKeys: [UInt16] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
}

/// X11 keysyms and modifier masks: the key encoding librime expects.
public enum RimeKey {
    public static let shiftMask: Int32 = 1 << 0
    public static let lockMask: Int32 = 1 << 1
    public static let controlMask: Int32 = 1 << 2
    public static let altMask: Int32 = 1 << 3
    public static let superMask: Int32 = 1 << 26
    /// librime's flag for key-up events.
    public static let releaseMask: Int32 = 1 << 30

    public static let shiftL: Int32 = 0xFFE1
    public static let space: Int32 = 0x0020
    public static let backSpace: Int32 = 0xFF08
    public static let tab: Int32 = 0xFF09
    public static let returnKey: Int32 = 0xFF0D
    public static let escape: Int32 = 0xFF1B
    public static let home: Int32 = 0xFF50
    public static let left: Int32 = 0xFF51
    public static let up: Int32 = 0xFF52
    public static let right: Int32 = 0xFF53
    public static let down: Int32 = 0xFF54
    public static let pageUp: Int32 = 0xFF55
    public static let pageDown: Int32 = 0xFF56
    public static let end: Int32 = 0xFF57
    public static let delete: Int32 = 0xFFFF
    public static let f1: Int32 = 0xFFBE

    /// The keysym of a key that types nothing (F1–F12 only, as before the key model: F13 and up are nil, as other
    /// function keys).
    static func special(_ key: Key) -> Int32? {
        switch key {
        case .enter, .keypadEnter: return returnKey
        case .tab: return tab
        case .space: return space
        case .backspace: return backSpace
        case .forwardDelete: return delete
        case .escape: return escape
        case .home: return home
        case .end: return end
        case .pageUp: return pageUp
        case .pageDown: return pageDown
        case .arrow(.left): return left
        case .arrow(.right): return right
        case .arrow(.up): return up
        case .arrow(.down): return down
        case let .f(n) where (1...12).contains(n): return f1 + Int32(n - 1)
        default: return nil
        }
    }

    public static func mask(for modifiers: KeyModifiers) -> Int32 {
        var mask: Int32 = 0
        if modifiers.contains(.shift) { mask |= shiftMask }
        if modifiers.contains(.capsLock) { mask |= lockMask }
        if modifiers.contains(.control) { mask |= controlMask }
        if modifiers.contains(.option) { mask |= altMask }
        if modifiers.contains(.command) { mask |= superMask }
        return mask
    }

    /// Maps a key-down to (keysym, mask), or nil when librime has no use for the key
    /// (non-ASCII characters, dead keys, unknown function keys). Follows Squirrel's mapping.
    public static func map(_ event: KeyEvent) -> (keycode: Int32, mask: Int32)? {
        let mask = mask(for: event.modifiers)
        if let special = special(event.key) { return (special, mask) }

        var chars = event.charactersIgnoringModifiers
        let capitalOnly = event.modifiers.isSubset(of: [.shift, .capsLock])
        if let first = chars.unicodeScalars.first {
            if capitalOnly && !first.properties.isAlphabetic {
                chars = event.characters
            } else if !capitalOnly && !first.isASCII {
                chars = event.characters
            }
        }
        guard chars.unicodeScalars.count == 1, let scalar = chars.unicodeScalars.first,
              (0x20...0x7E).contains(scalar.value)
        else { return nil }
        var value = scalar.value
        if !event.modifiers.isDisjoint(with: [.shift, .capsLock]), (0x61...0x7A).contains(value) {
            value -= 0x20  // lowercase → uppercase keysym
        }
        return (Int32(value), mask)
    }
}

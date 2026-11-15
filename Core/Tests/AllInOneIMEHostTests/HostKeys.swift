import Foundation
import AllInOneIMECore

/// Keys as a host hands them over on a U.S. keyboard (the Mac's key codes, `MacKeyCodes`): what a character typed is,
/// whether Shift is held for it, and the named keys.
enum HostKeys {
    /// The key a character is typed with, and whether Shift is held for it; nil: no key types it (it goes in as a key of
    /// its own, code 0, as `FakeHost.type` sends it).
    static func key(typing character: Character) -> (code: UInt16, shift: Bool)? {
        let lower = Character(character.lowercased())
        if let code = unshifted[lower], lower == character || character.isUppercase { return (code, character.isUppercase) }
        if let base = shifted[character], let code = unshifted[base] { return (code, true) }
        return nil
    }

    /// `character` typed (Shift held for it where it needs it), as AppKit hands it over.
    static func event(typing character: Character, modifiers: Modifiers = []) -> KeyEvent {
        let text = String(character)
        guard let (code, shift) = key(typing: character) else { return KeyEvent(keyCode: 0, characters: text, modifiers: modifiers) }
        return KeyEvent(keyCode: code, characters: text, charactersIgnoringModifiers: text,
                        modifiers: shift ? modifiers.union(.shift) : modifiers)
    }

    /// `named` with `modifiers` held, as AppKit hands it over: ⌘ keeps the letter, ⌃ makes it a control character, ⌥ the
    /// U.S. layout's character on its digits and some letters.
    static func event(_ named: NamedKey, modifiers held: [Key.ModifierKind]) -> KeyEvent {
        var modifiers = Modifiers(held.map { Modifiers.kind($0) })
        switch named {
        case let .character(character):
            let base = event(typing: character)
            modifiers.formUnion(base.modifiers)
            let characters = characters(for: character, modifiers: modifiers)
            return KeyEvent(keyCode: base.keyCode, characters: characters, charactersIgnoringModifiers: String(character),
                            modifiers: modifiers)
        case let .function(number):
            let code = VirtualKey.functionKeys[min(max(number, 1), 12) - 1]
            let scalar = Unicode.Scalar(0xF704 + UInt32(number - 1)).map(String.init) ?? ""
            return KeyEvent(keyCode: code, characters: scalar, modifiers: modifiers)
        default:
            let (code, text) = named.keyCodeAndText
            return KeyEvent(keyCode: code, characters: text, modifiers: modifiers)
        }
    }

    private static func characters(for character: Character, modifiers: Modifiers) -> String {
        if modifiers.contains(.command) { return String(character) }
        if modifiers.contains(.control), let ascii = character.lowercased().unicodeScalars.first?.value, (0x61...0x7A).contains(ascii),
           let control = Unicode.Scalar(ascii - 0x60) {
            return String(control)
        }
        if modifiers.contains(.option), !modifiers.contains(.shift), let typed = optionLayer[character] { return String(typed) }
        return String(character)
    }

    /// The modifier keys' codes (the left ones).
    static func code(of kind: Key.ModifierKind) -> UInt16 {
        switch kind {
        case .shift: 0x38
        case .control: 0x3B
        case .option: 0x3A
        case .command: 0x37
        }
    }

    static let capsLockCode: UInt16 = 0x39

    /// The left key of `kind` down: its kind and its side.
    static func left(_ kind: Key.ModifierKind) -> Modifiers { [Modifiers.kind(kind), Modifiers.side(.left, of: kind)] }

    private static let unshifted: [Character: UInt16] = [
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E, "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
        "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F, "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
        "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10, "z": 0x06,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
        "-": 0x1B, "=": 0x18, "[": 0x21, "]": 0x1E, "\\": 0x2A, ";": 0x29, "'": 0x27, "`": 0x32, ",": 0x2B, ".": 0x2F,
        "/": 0x2C, " ": 0x31,
    ]

    /// The characters Shift types, by the key's own.
    private static let shifted: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "~": "`", "<": ",", ">": ".", "?": "/",
    ]

    /// What ⌥ types on the U.S. layout's digits and the letters that aren't dead keys.
    private static let optionLayer: [Character: Character] = [
        "1": "¡", "2": "™", "3": "£", "4": "¢", "5": "∞", "6": "§", "7": "¶", "8": "•", "9": "ª", "0": "º",
        "a": "å", "b": "∫", "c": "ç", "d": "∂", "f": "ƒ", "g": "©", "h": "˙", "j": "∆", "k": "˚", "l": "¬", "m": "µ",
        "o": "ø", "p": "π", "q": "œ", "r": "®", "s": "ß", "t": "†", "v": "√", "w": "∑", "x": "≈", "y": "¥", "z": "Ω",
    ]
}

extension NamedKey {
    /// The key's code and what AppKit says it types (its function-key character where it types none).
    var keyCodeAndText: (UInt16, String) {
        switch self {
        case .space: (VirtualKey.space, " ")
        case .enter: (VirtualKey.returnKey, "\r")
        case .escape: (VirtualKey.escape, "\u{1B}")
        case .tab: (VirtualKey.tab, "\t")
        case .backspace: (VirtualKey.delete, "\u{7F}")
        case .forwardDelete: (VirtualKey.forwardDelete, "\u{F728}")
        case .left: (VirtualKey.left, "\u{F702}")
        case .right: (VirtualKey.right, "\u{F703}")
        case .up: (VirtualKey.up, "\u{F700}")
        case .down: (VirtualKey.down, "\u{F701}")
        case .home: (VirtualKey.home, "\u{F729}")
        case .end: (VirtualKey.end, "\u{F72B}")
        case .pageUp: (VirtualKey.pageUp, "\u{F72C}")
        case .pageDown: (VirtualKey.pageDown, "\u{F72D}")
        case .function, .character: (0, "")
        }
    }
}

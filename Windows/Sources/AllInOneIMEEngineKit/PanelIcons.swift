import AllInOneIMECore
import Foundation

/// The core's icons (`IconToken`) as the candidate window draws them: a glyph of Segoe Fluent Icons (the code points
/// Segoe MDL2 Assets has too, for Windows 10) white on a rounded square of the icon's color, an emoji, or an image file.
/// A symbol named in SF Symbols' vocabulary (a custom command's, a plugin's, a script extension's) is drawn as the glyph
/// Windows has for it, where this knows one, else as the icon's fallback.
public enum PanelIcons {
    /// What the window is given for an icon (`AioPanelIcon`).
    public struct Flat: Equatable, Sendable {
        /// `AIO_ICON_GLYPH`, `AIO_ICON_EMOJI`, `AIO_ICON_IMAGE` (1, 2, 3).
        public var kind: Int32
        /// The glyph, the emoji or the image's path.
        public var text: String
        /// The glyph drawn instead where the emoji or the image can't be.
        public var fallback: String
        /// The square's color, 0xRRGGBB.
        public var color: UInt32
    }

    public static let glyphKind: Int32 = 1, emojiKind: Int32 = 2, imageKind: Int32 = 3

    public static func flat(_ icon: IconToken) -> Flat {
        let fallback = glyph(icon.fallback), color = rgb(icon.color)
        switch icon.glyph {
        case let .builtin(builtin): return Flat(kind: glyphKind, text: glyph(builtin), fallback: fallback, color: color)
        case let .symbol(name, _): return Flat(kind: glyphKind, text: glyph(symbol: name) ?? fallback, fallback: fallback, color: color)
        case let .emoji(emoji, _): return Flat(kind: emojiKind, text: emoji, fallback: fallback, color: color)
        case let .image(path, _): return Flat(kind: imageKind, text: path, fallback: fallback, color: color)
        }
    }

    /// The glyph for each of the core's own icons (Segoe Fluent Icons' names after each).
    public static func glyph(_ builtin: IconToken.Builtin) -> String {
        let code: UInt32
        switch builtin {
        case .improve: code = 0xE70F  // Edit
        case .translate: code = 0xE8C1  // Characters
        case .question: code = 0xE897  // Help
        case .reply: code = 0xE97A  // Reply
        case .agent, .scriptSilent: code = 0xE945  // LightningBolt
        case .open: code = 0xE721  // Search
        case .read: code = 0xE8A5  // Document
        case .note: code = 0xE70B  // QuickNote
        case .reminder: code = 0xEA8F  // Ringer
        case .python, .javascript, .run: code = 0xE943  // Code
        case .webSearch: code = 0xE774  // Globe
        case .tasks: code = 0xE9D5  // CheckList
        case .settings: code = 0xE713  // Settings
        case .message: code = 0xE8BD  // Message
        case .reportIssue: code = 0xED15  // Feedback
        case .command, .terminal: code = 0xE756  // CommandPrompt
        case .plugin: code = 0xEA86  // Puzzle
        case .link: code = 0xE71B  // Link
        case .prompt: code = 0xE8F2  // ChatBubbles
        case .snippet, .scriptInsert: code = 0xE8AC  // Rename
        case .scriptShow: code = 0xE8E4  // AlignLeft
        case .scriptList: code = 0xE8FD  // BulletedList
        case .scriptBackground: code = 0xE81C  // History
        case .scriptStatus: code = 0xE9D9  // Diagnostic
        case .done: code = 0xE73E  // CheckMark
        case .working: code = 0xE916  // Stopwatch
        case .needsYou: code = 0xE8C9  // Important
        }
        return String(Character(Unicode.Scalar(code)!))
    }

    /// The glyph for an SF Symbol's name, by its base name (".fill", ".circle", ".square" … taken off), for the ones this
    /// knows; nil for the others (the icon's fallback is drawn).
    public static func glyph(symbol name: String) -> String? {
        var base = name.lowercased()
        for suffix in [".fill", ".circle", ".square", ".rectangle", ".badge.plus"] {
            while base.hasSuffix(suffix) { base = String(base.dropLast(suffix.count)) }
        }
        let known: [String: UInt32] = [
            "star": 0xE734, "heart": 0xEB51, "envelope": 0xE715, "globe": 0xE774, "network": 0xE774, "link": 0xE71B,
            "terminal": 0xE756, "apple.terminal": 0xE756, "command": 0xE756, "doc": 0xE8A5, "doc.text": 0xE8A5,
            "doc.richtext": 0xE8A5, "doc.on.doc": 0xE8C8, "folder": 0xE8B7, "gear": 0xE713, "gearshape": 0xE713,
            "magnifyingglass": 0xE721, "bell": 0xEA8F, "calendar": 0xE787, "clock": 0xE823, "trash": 0xE74D,
            "pencil": 0xE70F, "square.and.pencil": 0xE70F, "camera": 0xE722, "photo": 0xE8B9, "music.note": 0xE8D6,
            "bolt": 0xE945, "sparkles": 0xE945, "wand.and.stars": 0xE70F, "message": 0xE8BD, "bubble.left": 0xE8BD,
            "text.bubble": 0xE8F2, "bubble.left.and.bubble.right": 0xE8F2, "checkmark": 0xE73E, "checklist": 0xE9D5,
            "list.bullet": 0xE8FD, "person": 0xE77B, "house": 0xE80F, "cart": 0xE7BF, "book": 0xE82D, "lock": 0xE72E,
            "key": 0xE8D7, "chevron.left.forwardslash.chevron.right": 0xE943, "curlybraces": 0xE943, "translate": 0xE8C1,
            "questionmark": 0xE897, "exclamationmark": 0xE8C9, "puzzlepiece": 0xEA86, "puzzlepiece.extension": 0xEA86,
            "hourglass": 0xE916, "note.text": 0xE70B, "arrowshape.turn.up.left": 0xE97A, "lightbulb": 0xE82F,
            "flag": 0xE7C1, "tag": 0xE8EC, "paperplane": 0xE724, "square.and.arrow.up": 0xE72D, "scissors": 0xE8C6,
            "mic": 0xE720, "speaker": 0xE767, "speaker.wave.2": 0xE767, "play": 0xE768, "mappin": 0xE707,
            "location": 0xE81D, "cloud": 0xE753, "sun.max": 0xE706, "moon": 0xE708, "info": 0xE946,
            "exclamationmark.triangle": 0xE7BA, "printer": 0xE749, "phone": 0xE717, "video": 0xE714,
        ]
        return known[base].map { String(Character(Unicode.Scalar($0)!)) }
    }

    /// The icon's color as the Mac's system colors are (light appearance), a gray by its brightness, or as given.
    public static func rgb(_ color: IconToken.Color) -> UInt32 {
        switch color {
        case .red: return 0xFF3B30
        case .orange: return 0xFF9500
        case .yellow: return 0xFFCC00
        case .green: return 0x34C759
        case .mint: return 0x00C7BE
        case .teal: return 0x30B0C7
        case .cyan: return 0x32ADE6
        case .blue: return 0x007AFF
        case .indigo: return 0x5856D6
        case .purple: return 0xAF52DE
        case .pink: return 0xFF2D55
        case .brown: return 0xA2845E
        case .gray: return 0x8E8E93
        case let .grayscale(level):
            let value = UInt32((min(max(level, 0), 1) * 255).rounded())
            return value << 16 | value << 8 | value
        case let .rgb(red, green, blue): return UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
        }
    }
}

extension PanelModel.Input {
    /// The caret in UTF-16 units of `text` (what DirectWrite's positions count), from the core's in characters; nil:
    /// none.
    public var utf16Caret: Int? {
        guard let caret else { return nil }
        let index = text.index(text.startIndex, offsetBy: min(max(caret, 0), text.count))
        return text.utf16.distance(from: text.utf16.startIndex, to: index)
    }
}

import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Punctuation right after a digit stays ASCII in Chinese mode (0.7.5, owner-approved 2026-11-15). In Chinese (pinyin)
/// mode, idle (no pinyin being typed), with an ASCII digit 0-9 just before the caret, `.` `,` `:` put in the ASCII
/// character, not 。，：, so 3.14, 10:30 and 1,000 come out as typed. "Just before the caret": the field's text before it
/// where the field can be read (`FieldText.before`); where it can't, the input method's own memory of what it last
/// committed or let through, cleared by a click, a caret move (arrows, ⌘ arrows), a focus change, a selection, a paste,
/// or any committed character that isn't a digit. Not affected: other punctuation after a digit (`?` `!` `;`), any
/// punctuation after a non-digit (好. → 好。), English mode, full-width digits (１２３), and a digit that picks a candidate
/// while pinyin is typed. No setting; the same on every host.
///
/// Through a field's session (`FakeHost`), typed as the user types it. The stand-in engine punctuates as librime's default
/// Chinese punctuation does (`.` → 。, `,` → ，, `:` → ：, `?` → ？, `!` → ！, `;` → ；) and lets every other key through
/// while idle; the app types what the session lets through (`FakeHost.appTypesKeys`). A readable field tells everything
/// with each key (`FakeHost.context`); an unreadable one tells nothing of its text (no `FieldText`, the character before
/// the caret unknown), as WeChat's field or a terminal. What the user sees is the field's text afterwards.
@Suite(.serialized)
struct DigitPunctuationAcceptanceTests {
    typealias Suite = DigitPunctuationAcceptanceTests

    // MARK: - The rig

    /// Librime's default Chinese punctuation, and a tiny dictionary: letters compose, Space or a digit picks a candidate,
    /// every other key goes to the app while idle.
    final class PunctuationEngine: PinyinEngine {
        static let punctuation: [Character: String] = [".": "。", ",": "，", ":": "：", "?": "？", "!": "！", ";": "；"]
        var dictionary = ["hao": ["好", "号"], "nihao": ["你好", "拟好"], "jintian": ["今天", "金天"]]
        private var input = ""
        private var ascii = false
        private var pending: String?

        private var words: [String] { input.isEmpty ? [] : dictionary[input] ?? [input] }

        func processKey(_ keycode: Int32, mask: Int32) -> Bool {
            if ascii || mask & RimeKey.releaseMask != 0 { return false }
            let composing = !input.isEmpty
            switch keycode {
            case 0x61...0x7A:
                input.append(Character(Unicode.Scalar(UInt8(keycode))))
                return true
            case RimeKey.space where composing:
                emit(words[0])
                input = ""
                return true
            case 0x31...0x39 where composing:
                let index = Int(keycode - 0x31)
                if words.indices.contains(index) {
                    emit(words[index])
                    input = ""
                }
                return true
            case RimeKey.returnKey where composing:
                emit(input)
                input = ""
                return true
            case RimeKey.backSpace where composing:
                input.removeLast()
                return true
            case RimeKey.escape where composing:
                input = ""
                return true
            default:
                if (0x20...0x7E).contains(keycode),
                   let mark = Self.punctuation[Character(Unicode.Scalar(UInt8(keycode)))] {
                    if composing { emit(words[0]) }
                    input = ""
                    emit(mark)
                    return true
                }
                return composing
            }
        }

        private func emit(_ text: String) { pending = (pending ?? "") + text }

        func takeCommit() -> String? {
            defer { pending = nil }
            return pending
        }

        func snapshot() -> EngineSnapshot {
            EngineSnapshot(isComposing: !input.isEmpty, preedit: input, cursor: input.count,
                           candidates: words.enumerated().map { EngineCandidate(label: String($0.offset + 1), text: $0.element) },
                           highlighted: 0, isAsciiMode: ascii)
        }

        func selectCandidate(onPage index: Int) -> Bool {
            guard words.indices.contains(index) else { return false }
            emit(words[index])
            input = ""
            return true
        }

        func deleteCandidate(onPage index: Int) -> Bool { false }
        func setRemovedCandidates(_ texts: [String]) {}

        func commitComposition() -> String? {
            guard !input.isEmpty else { return nil }
            emit(words[0])
            input = ""
            return takeCommit()
        }

        var rawInput: String { input }
        func clearComposition() { input = "" }
        func setAsciiMode(_ on: Bool) { ascii = on }
        var language: Language { .chinese }
        func selectSchema(_ id: String) -> Bool { true }
    }

    /// The settings as loaded, and whether the mouse was used (a click: `SessionServices.buttonUsedWithin`).
    final class World: @unchecked Sendable {
        var config: Config
        var clicked = false
        init(_ config: Config) { self.config = config }
    }

    /// How the field tells its text.
    enum Field: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// Everything with each key: the text before the caret (`FieldText.before`), the character there.
        case readable
        /// Nothing of its text (WeChat's): the input method goes by its own memory.
        case unreadable
        /// A terminal: tells nothing of its text either.
        case terminal
        var testDescription: String { rawValue }
        var readable: Bool { self == .readable }
    }

    /// A text field with the focus, typed in as the user types; the app types what the session lets through.
    struct Rig {
        let host: FakeHost
        let world: World
        let field: Field

        /// Chinese and English the input languages, `start` the one a field starts in; autocomplete off (nothing asked of
        /// any AI); `document` already in the field, the caret at its end.
        init(_ field: Field, start: Language = .chinese, document: String = "") {
            var config = Config.default
            config.inputLanguages = [.chinese, .english]
            config.defaultInput = start
            config.autocomplete = false
            let world = World(config)
            var services = SessionServices(loadSettings: { world.config })
            let engine = PunctuationEngine()
            services.levelOne = { .engine(engine) }
            services.buttonUsedWithin = { _ in world.clicked }
            services.pointerUsedWithin = { _ in world.clicked }
            let host = FakeHost(services: services)
            host.app = field == .unreadable ? "com.tencent.xinWeChat" : "com.example.editor"
            host.terminal = field == .terminal
            host.tellsNoText = !field.readable
            host.appTypesKeys = true
            host.document = document
            host.focus()
            (self.host, self.world, self.field) = (host, world, field)
        }

        /// What the field tells with a key: all of it where it can be read, else nothing of its text.
        var context: FieldContext {
            if field.readable { return host.context }
            return FieldContext(read: [.secure, .markedText], secure: false, beforeCaret: .unknown, text: nil)
        }

        var document: String { host.document }

        @discardableResult
        func press(_ key: KeyEvent) -> Bool { host.press(key, with: context) }

        /// Types `text`, a key a character (" " the space bar).
        func type(_ text: String) {
            for character in text {
                press(character == " " ? FakeHost.space : KeyEvent(keyCode: 0, characters: String(character)))
            }
        }

        /// Pinyin `letters`, then Space: its first candidate goes in.
        func pinyin(_ letters: String) {
            type(letters)
            press(FakeHost.space)
        }
    }

    static func key(_ code: UInt16, _ characters: String, ignoring: String? = nil, _ modifiers: KeyModifiers = []) -> KeyEvent {
        KeyEvent(keyCode: code, characters: characters, charactersIgnoringModifiers: ignoring ?? characters, modifiers: modifiers)
    }

    // MARK: - 3.14, 10:30 and 1,000 typed in full

    static let numbers = ["3.14", "10:30", "1,000", "0.5", "2,3", "12:00:59", "1,234.56"]

    /// Each number typed in full in Chinese mode comes out as typed, in every kind of field.
    @Test(arguments: Field.allCases, numbers)
    func numbersComeOutAsTyped(field: Field, number: String) {
        let rig = Rig(field)
        rig.type(number)
        #expect(rig.document == number)
        #expect(rig.host.marked.isEmpty)
    }

    /// After Chinese committed from pinyin, a number typed in full still comes out as typed: 今天10:30, 好3.14.
    @Test(arguments: Field.allCases)
    func numberAfterChinese(field: Field) {
        let rig = Rig(field)
        rig.pinyin("jintian")
        rig.type("10:30")
        #expect(rig.document == "今天10:30")
        rig.pinyin("hao")
        rig.type("3.14")
        #expect(rig.document == "今天10:30好3.14")
    }

    /// Each of `.` `,` `:` right after any ASCII digit stays ASCII.
    @Test(arguments: Field.allCases, ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])
    func everyDigitKeepsEachMarkASCII(field: Field, digit: String) {
        for mark in [".", ",", ":"] {
            let rig = Rig(field)
            rig.type(digit + mark)
            #expect(rig.document == digit + mark, "\(digit)\(mark)")
        }
    }

    // MARK: - Readable fields: the text before the caret

    /// A digit already in a readable field (typed before the input method saw anything: another session, the app's own
    /// text) is what's before the caret: `.` `,` `:` stay ASCII.
    @Test(arguments: [".", ",", ":"])
    func readableDigitAlreadyThere(mark: String) {
        let rig = Rig(.readable, document: "价格 42")
        rig.type(mark)
        #expect(rig.document == "价格 42" + mark)
    }

    /// The field's text wins over the memory: after a click (which clears the memory) a readable field that still has a
    /// digit before the caret keeps `.` ASCII.
    @Test func readableDigitAfterClick() {
        let rig = Rig(.readable)
        rig.type("3")
        rig.world.clicked = true
        rig.host.send(.commit)
        rig.type(".")
        #expect(rig.document == "3.")
    }

    /// The field's text wins the other way too: a digit last typed, but the field now has 元 before the caret (the app
    /// changed its text) → 。.
    @Test func readableNonDigitBeatsMemory() {
        let rig = Rig(.readable)
        rig.type("3")
        rig.host.document = "3元"
        rig.type(".")
        #expect(rig.document == "3元。")
    }

    /// A readable field with nothing before the caret (empty) → 。.
    @Test func readableEmptyField() {
        let rig = Rig(.readable)
        rig.type(".")
        #expect(rig.document == "。")
    }

    // MARK: - Unreadable fields: what the memory clears

    /// How the memory of a digit last typed is cleared in a field that can't be read.
    enum Clearing: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case click
        case left, right, up, down
        case commandLeft, commandRight, commandUp, commandDown
        case focusChange
        case newFieldFocus
        case shiftLeftSelection
        case selectAll
        case commandVPaste
        case spaceTyped
        case letterViaPinyin
        case chinesePunctuation
        case asciiPunctuation
        case digitPicksCandidate
        var testDescription: String { rawValue }

        /// Does it to the rig after "3" was typed.
        func apply(_ rig: Rig) {
            switch self {
            case .click:
                rig.world.clicked = true
                rig.host.send(.commit)
            case .left: rig.press(Suite.key(VirtualKey.left, "\u{F702}"))
            case .right: rig.press(Suite.key(VirtualKey.right, "\u{F703}"))
            case .up: rig.press(Suite.key(VirtualKey.up, "\u{F700}"))
            case .down: rig.press(Suite.key(VirtualKey.down, "\u{F701}"))
            case .commandLeft: rig.press(Suite.key(VirtualKey.left, "\u{F702}", .command))
            case .commandRight: rig.press(Suite.key(VirtualKey.right, "\u{F703}", .command))
            case .commandUp: rig.press(Suite.key(VirtualKey.up, "\u{F700}", .command))
            case .commandDown: rig.press(Suite.key(VirtualKey.down, "\u{F701}", .command))
            case .focusChange:
                rig.host.send(.blur)
                rig.host.focus()
            case .newFieldFocus:
                rig.host.send(.focus(FieldInfo(app: "com.example.other", terminal: rig.field == .terminal)))
            case .shiftLeftSelection: rig.press(Suite.key(VirtualKey.left, "\u{F702}", .shift))
            case .selectAll: rig.press(Suite.key(0x00, "a", .command))
            case .commandVPaste:
                rig.host.clipboard = .text("abc")
                if !rig.press(Suite.key(0x09, "v", .command)) { rig.host.document += "abc" }  // the app pastes
            case .spaceTyped: rig.press(FakeHost.space)
            case .letterViaPinyin: rig.pinyin("hao")
            case .chinesePunctuation: rig.type("?")  // ？ committed
            case .asciiPunctuation: rig.type(".")  // "3." — the "." itself is not a digit
            case .digitPicksCandidate:
                rig.type("hao")
                rig.type("1")  // picks 好: not a digit in the field
            }
        }
    }

    /// In a field that can't be read, a digit typed is remembered: `.` right after it stays ASCII ...
    @Test(arguments: [Field.unreadable, .terminal])
    func unreadableRemembersDigit(field: Field) {
        let rig = Rig(field)
        rig.type("3")
        rig.type(".")
        #expect(rig.document == "3.")
    }

    /// ... until something clears the memory; then `.` is 。 again.
    @Test(arguments: [Field.unreadable, .terminal], Clearing.allCases)
    func unreadableMemoryCleared(field: Field, clearing: Clearing) {
        let rig = Rig(field)
        rig.type("3")
        clearing.apply(rig)
        rig.world.clicked = false  // the next key isn't a click
        let before = rig.document
        rig.type(".")
        #expect(rig.document == before + "。", "\(clearing): \(before) then .")
        #expect(rig.host.marked.isEmpty)
    }

    /// A selection the field tells with the key (but not its text) clears it too: `.` over it is 。.
    @Test func unreadableToldSelection() {
        let rig = Rig(.unreadable)
        rig.type("3")
        rig.host.selection = 0..<1
        let told = FieldContext(read: [.secure, .markedText, .selectedRange, .selection], secure: false,
                                selectedRange: 0..<1, selection: Composer.Selection(text: "3", range: 0..<1),
                                beforeCaret: .unknown, text: nil)
        rig.host.press(KeyEvent(keyCode: 0, characters: "."), with: told)
        #expect(rig.document == "。")
    }

    /// A digit typed again after the memory was cleared counts once more: 3 ← 5. → "35."
    @Test(arguments: [Field.unreadable, .terminal])
    func unreadableDigitAfterClearing(field: Field) {
        let rig = Rig(field)
        rig.type("3")
        rig.press(Suite.key(VirtualKey.left, "\u{F702}"))
        rig.type("5.")
        #expect(rig.document == "35.")
    }

    // MARK: - Not affected

    /// Other punctuation after a digit stays as today: 3？ 3！ 3；
    @Test(arguments: Field.allCases, [("?", "？"), ("!", "！"), (";", "；")])
    func otherPunctuationAfterDigit(field: Field, mark: (String, String)) {
        let rig = Rig(field)
        rig.type("3" + mark.0)
        #expect(rig.document == "3" + mark.1)
    }

    /// Punctuation after a non-digit: 好. → 好。, 好, → 好，, 好: → 好：
    @Test(arguments: Field.allCases, [(".", "。"), (",", "，"), (":", "：")])
    func punctuationAfterChinese(field: Field, mark: (String, String)) {
        let rig = Rig(field)
        rig.pinyin("hao")
        rig.type(mark.0)
        #expect(rig.document == "好" + mark.1)
    }

    /// 好. in a readable field where 好 was already there.
    @Test func punctuationAfterChineseAlreadyThere() {
        let rig = Rig(.readable, document: "好")
        rig.type(".")
        #expect(rig.document == "好。")
    }

    /// English mode: punctuation is ASCII as today, after a digit or not.
    @Test(arguments: Field.allCases, ["3.14", "10:30", "1,000", "ok.", "3?"])
    func englishMode(field: Field, text: String) {
        let rig = Rig(field, start: .english)
        rig.type(text)
        #expect(rig.document == text)
    }

    /// Full-width digits count as non-ASCII: １２３. → １２３。 (readable: already there; any field: let through as typed).
    @Test(arguments: Field.allCases)
    func fullWidthDigits(field: Field) {
        let readable = Rig(.readable, document: "１２３")
        readable.type(".")
        #expect(readable.document == "１２３。")

        let rig = Rig(field)
        rig.type("３")
        rig.type(".")
        #expect(rig.document == "３。")
    }

    /// A digit that picks a candidate while pinyin is typed isn't "after a digit": hao 2 . → 号。
    @Test(arguments: Field.allCases)
    func digitPickingCandidate(field: Field) {
        let rig = Rig(field)
        rig.type("hao2")
        rig.type(".")
        #expect(rig.document == "号。")
    }

    /// Pinyin being typed: `.` ends it as today (the word, then 。), whatever came before.
    @Test(arguments: Field.allCases)
    func punctuationWhileComposing(field: Field) {
        let rig = Rig(field)
        rig.type("3")
        rig.type("hao.")
        #expect(rig.document == "3好。")
    }
}

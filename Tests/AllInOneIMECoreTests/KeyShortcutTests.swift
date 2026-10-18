import Foundation
import Testing
@testable import AllInOneIMECore

/// A recorded action key in config.json: read from the Mac's `keyCode` or the key's `usage`, written with both.
struct KeyShortcutTests {
    /// `KeyShortcut` as 0.6.4 and before read it: the Mac's code and the modifiers as a byte, both required.
    struct OldKeyShortcut: Decodable {
        var keyCode: UInt16
        var modifiers: UInt8
        var name: String
    }

    /// The config as 0.6.4 read the action key: a name, or the old shortcut.
    struct OldConfig: Decodable {
        enum OldActionKey: Decodable {
            case named(String)
            case shortcut(OldKeyShortcut)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let name = try? c.decode(String.self) { self = .named(name) } else { self = .shortcut(try c.decode(OldKeyShortcut.self)) }
            }
        }
        var actionKey: OldActionKey
    }

    let controlReturn = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .control)

    @Test func anOldConfigStillLoads() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"actionKey": {"keyCode": 36, "modifiers": 2, "name": "⌃⏎"}}"#.utf8))
        let shortcut = KeyShortcut(keyCode: VirtualKey.returnKey, modifiers: .control, name: "⌃⏎")
        #expect(config.actionKey == .shortcut(shortcut))
        #expect(shortcut.usage == 0x28)
        #expect(shortcut.matches(controlReturn))
        #expect(!shortcut.matches(KeyEvent(keyCode: VirtualKey.keypadEnter, characters: "\u{3}", modifiers: .control)))
        #expect(!shortcut.matches(KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .command)))
    }

    @Test func aWrittenConfigIsReadByTheOldReader() throws {
        var config = Config.default
        config.actionKey = .shortcut(KeyShortcut(keyCode: 0x26, modifiers: .command, name: "⌘J"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keyshortcut-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try config.write(to: url)
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"keyCode\" : 38") && text.contains("\"usage\" : 13"))  // J: kVK_ANSI_J, HID 0x0D
        let old = try JSONDecoder().decode(OldConfig.self, from: data)
        guard case let .shortcut(shortcut) = old.actionKey else {
            Issue.record("not a shortcut: \(old.actionKey)")
            return
        }
        #expect(shortcut.keyCode == 0x26)
        #expect(shortcut.modifiers == 8)
        #expect(shortcut.name == "⌘J")
        #expect(try Config.load(from: url).actionKey == config.actionKey)
    }

    @Test func readFromTheUsageAlone() throws {
        // Written where there is no Mac key code (another system's config): the Mac's code comes from the usage.
        let shortcut = try JSONDecoder().decode(KeyShortcut.self, from: Data(#"{"usage": 40, "modifiers": 2, "name": "Ctrl+Enter"}"#.utf8))
        #expect(shortcut.keyCode == VirtualKey.returnKey)
        #expect(shortcut.matches(controlReturn))
        // A key the Mac doesn't have: it keeps its usage, and the Mac's code says so.
        let printScreen = try JSONDecoder().decode(KeyShortcut.self, from: Data(#"{"usage": 70, "modifiers": 8, "name": "PrtSc"}"#.utf8))
        #expect(printScreen.keyCode == KeyEvent.noKeyCode)
        #expect(printScreen.usage == 0x46)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KeyShortcut.self, from: Data(#"{"modifiers": 2, "name": "?"}"#.utf8))
        }
    }

    @Test func matchesByWhereTheKeyIs() {
        // The same physical key, as another system's event: its usage is what counts.
        let j = KeyShortcut(keyCode: 0x26, modifiers: .command, name: "⌘J")
        #expect(j.matches(KeyEvent(keyCode: 0x26, characters: "j", modifiers: .command)))
        #expect(j.matches(KeyEvent(key: .character, usage: 0x0D, characters: "j", modifiers: .command)))
        #expect(!j.matches(KeyEvent(key: .character, usage: 0x0E, characters: "j", modifiers: .command)))  // K's key, typing j
        // A key code the tables don't have (usage 0) still matches by its code.
        let unknown = KeyShortcut(keyCode: 0x34, modifiers: .control, name: "?")
        #expect(unknown.usage == 0)
        #expect(unknown.matches(KeyEvent(keyCode: 0x34, characters: "", modifiers: .control)))
        #expect(!unknown.matches(KeyEvent(keyCode: 0x6C, characters: "", modifiers: .control)))
    }

    @Test func commandMeansThePrimaryRole() {
        var pc = ModifierRoles.mac
        pc.primary = .control
        let j = KeyShortcut(keyCode: 0x26, modifiers: [.command, .shift], name: "⌘⇧J")
        #expect(j.matches(KeyEvent(keyCode: 0x26, characters: "J", modifiers: [.command, .shift])))
        #expect(!j.matches(KeyEvent(keyCode: 0x26, characters: "J", modifiers: [.control, .shift])))
        #expect(j.matches(KeyEvent(keyCode: 0x26, characters: "J", modifiers: [.control, .shift]), roles: pc))
        #expect(!j.matches(KeyEvent(keyCode: 0x26, characters: "J", modifiers: [.command, .shift]), roles: pc))
        // Recorded there with Ctrl, it is kept as ⌘: the same shortcut on the Mac.
        let recorded = ActionKey.recorded(key: .character, usage: 0x0D, modifiers: [.control, .shift], name: "Ctrl+Shift+J", roles: pc)
        #expect(recorded == .shortcut(KeyShortcut(usage: 0x0D, modifiers: [.command, .shift], name: "Ctrl+Shift+J")))
        #expect(recorded == .shortcut(KeyShortcut(keyCode: 0x26, modifiers: [.command, .shift], name: "Ctrl+Shift+J")))
    }

    @Test func recordedFromAKey() {
        #expect(ActionKey.recorded(key: .enter, usage: 0x28, modifiers: [], name: "Enter") == .enter)
        #expect(ActionKey.recorded(key: .keypadEnter, usage: 0x58, modifiers: [], name: "Enter") == .enter)
        #expect(ActionKey.recorded(key: .space, usage: 0x2C, modifiers: .option, name: "Alt+Space") == .optionSpace)
        #expect(ActionKey.recorded(key: .escape, usage: 0x29, modifiers: .control, name: "Ctrl+Esc") == nil)
        #expect(ActionKey.recorded(key: .character, usage: 0x0D, modifiers: .shift, name: "Shift+J") == nil)
        #expect(ActionKey.recorded(key: .f(5), usage: 0x3E, modifiers: [], name: "F5")
            == .shortcut(KeyShortcut(keyCode: 0x60, modifiers: [], name: "F5")))
        #expect(ActionKey.recorded(key: .f(24), usage: 0x73, modifiers: [], name: "F24") != nil)  // a PC's, no Mac code
        // ⇧Space types a space: not on its own.
        #expect(ActionKey.recorded(keyCode: VirtualKey.space, modifiers: .shift, name: "⇧Space") == nil)
        #expect(ActionKey.recorded(keyCode: 0x72, modifiers: [], name: "Help") == nil)  // as before: only the keys listed type nothing
    }
}

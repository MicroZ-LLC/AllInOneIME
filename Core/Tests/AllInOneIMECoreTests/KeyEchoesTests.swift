import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// MARK: - A key down handed over again

/// `KeyEchoes` as the shell asks it: a key down that is no copy answered `handled` (what the session would have said),
/// then kept. What it answers: the first one's answer for a copy, nil for a new key.
final class KeyProbe {
    var echoes = KeyEchoes()
    /// The clock's time as the key is handed over (the shell's `systemUptime`).
    var now: TimeInterval = 10

    @discardableResult
    func key(_ keyCode: UInt16, _ characters: String, _ modifiers: UInt = 0, repeat isRepeat: Bool = false,
             at timestamp: TimeInterval, handled: Bool = false) -> Bool? {
        let key = KeyEchoes.Key(keyCode: keyCode, characters: characters, modifiers: modifiers, isRepeat: isRepeat, timestamp: timestamp)
        if let answer = echoes.copy(of: key, now: now) { return answer }
        echoes.answered(key, now: now, handled: handled)
        return nil
    }
}

struct KeyEchoesTests {
    // "1" (0x12), "7" (0x1A) and "a" (0x00) on a US keyboard; NSEvent's flags for none (0x100) and for left Shift.
    static let none: UInt = 0x100, shift: UInt = 0x20102

    /// The same key down again (the same key, characters, modifiers and time): a copy, answered as the first was, taken
    /// or the app's; and a third time.
    @Test func theSameKeyDownAgainIsACopy() {
        let e = KeyProbe()
        #expect(e.key(0x12, "1", Self.none, at: 1.0, handled: false) == nil)
        e.now = 10.01
        #expect(e.key(0x12, "1", Self.none, at: 1.0) == false)
        #expect(e.key(0x12, "1", Self.none, at: 1.0) == false)
        #expect(e.key(0x00, "a", Self.none, at: 1.2, handled: true) == nil)
        #expect(e.key(0x00, "a", Self.none, at: 1.2, handled: false) == true)
    }

    /// A held key's repeats: the same key, characters and modifiers, each at a later time and saying it is a repeat.
    /// Every one new; a repeat handed over again is a copy of it.
    @Test func aHeldKeysRepeatsAreKept() {
        let e = KeyProbe()
        #expect(e.key(0x00, "a", Self.none, at: 1.0, handled: true) == nil)
        for n in 0..<30 {
            #expect(e.key(0x00, "a", Self.none, repeat: true, at: 1.5 + Double(n) / 30, handled: true) == nil, "repeat \(n)")
        }
        #expect(e.key(0x00, "a", Self.none, repeat: true, at: 1.5 + 29.0 / 30) == true)
    }

    /// The same key pressed again, at a later time: new, however soon after (the clock ticks every few tens of
    /// nanoseconds); and at an earlier time than the first (a tool's own times): new too, never a copy.
    @Test func aLaterTimeIsANewKey() {
        let e = KeyProbe()
        #expect(e.key(0x12, "1", Self.none, at: 1.0) == nil)
        #expect(e.key(0x12, "1", Self.none, at: 1.0 + 1e-7) == nil)
        #expect(e.key(0x12, "1", Self.none, at: 1.08) == nil)
        #expect(e.key(0x12, "1", Self.none, at: 0.5) == nil)
    }

    /// Another key between the first and its copy (a busy page hands the copy over after the keys typed meanwhile): the
    /// copy is still one, answered as its own first was; the key pressed again after them is new.
    @Test func aCopyAfterAnotherKeyIsStillOne() {
        let e = KeyProbe()
        #expect(e.key(0x12, "1", Self.none, at: 1.0, handled: true) == nil)
        #expect(e.key(0x1A, "7", Self.none, at: 1.1, handled: false) == nil)
        e.now = 10.3
        #expect(e.key(0x12, "1", Self.none, at: 1.0) == true)
        #expect(e.key(0x1A, "7", Self.none, at: 1.1) == false)
        #expect(e.key(0x12, "1", Self.none, at: 1.2) == nil)
    }

    /// Unlike the first in anything but its time (another key, what it types, its modifiers, a repeat or not): new.
    @Test func anythingElseAtTheSameTimeIsNew() {
        let e = KeyProbe()
        #expect(e.key(0x14, "3", Self.none, at: 1.0) == nil)
        #expect(e.key(0x12, "3", Self.none, at: 1.0) == nil)
        #expect(e.key(0x14, "#", Self.none, at: 1.0) == nil)
        #expect(e.key(0x14, "3", Self.shift, at: 1.0) == nil)
        #expect(e.key(0x14, "3", Self.none, repeat: true, at: 1.0) == nil)
    }

    /// A copy comes within `window` of the first: one that comes later is a key of its own, and answered, it is the one
    /// kept.
    @Test func aCopyComesWithinTheWindow() {
        let e = KeyProbe()
        #expect(e.key(0x12, "1", Self.none, at: 1.0, handled: true) == nil)
        e.now = 10 + KeyEchoes.window - 0.01
        #expect(e.key(0x12, "1", Self.none, at: 1.0) == true)
        e.now = 10 + KeyEchoes.window + 0.01
        #expect(e.key(0x12, "1", Self.none, at: 1.0, handled: false) == nil)
        #expect(e.key(0x12, "1", Self.none, at: 1.0) == false)
    }

    /// No time (0), or a time still to come (a tool's, in another unit or from another clock): never a copy, nor kept.
    @Test func aKeyWithNoTimeOrOneToComeIsNeverACopy() {
        let e = KeyProbe()
        #expect(e.key(0x12, "1", Self.none, at: 0, handled: true) == nil)
        #expect(e.key(0x12, "1", Self.none, at: 0, handled: true) == nil)
        #expect(e.key(0x12, "1", Self.none, at: 1e9, handled: true) == nil)
        #expect(e.key(0x12, "1", Self.none, at: 1e9, handled: true) == nil)
        e.now = 2e9
        #expect(e.key(0x12, "1", Self.none, at: 1e9) == nil)
    }

    /// It keeps `kept` key downs: one more, and the one that came first is forgotten.
    @Test func itForgetsTheKeyThatCameFirst() {
        let e = KeyProbe()
        #expect(e.key(0x12, "1", Self.none, at: 1.0, handled: true) == nil)
        for n in 1..<KeyEchoes.kept {
            #expect(e.key(0x00, "a", Self.none, at: 1.0 + Double(n) / 1000) == nil)
        }
        #expect(e.key(0x12, "1", Self.none, at: 1.0) == true)
        #expect(e.key(0x1A, "7", Self.none, at: 1.5) == nil)
        #expect(e.key(0x12, "1", Self.none, at: 1.0, handled: false) == nil)
    }
}

// MARK: - Through the session

/// A field's keys as the Mac's shell hands them to its session (`AllInOneIMEInputController.handleKeyDown`): each at its
/// event's time, a key down handed over again dropped first (`KeyEchoes`), answered as the first was, before the session
/// sees it. `press` hands a new key on (the app types it if the session didn't take it); `again` the last key's event a
/// second time, which the app doesn't type again (the field has it once, as the owner's had "#17"): what it reaches,
/// when it isn't dropped, is the session only (`session`).
final class KeyFeed {
    private var echoes = KeyEchoes()
    private let press: (KeyEvent) -> Bool
    private let session: (KeyEvent) -> Bool
    /// The clock's time (the shell's `systemUptime`): each key typed 80 ms after the one before.
    private(set) var now: TimeInterval = 100
    private var last: (key: KeyEvent, timestamp: TimeInterval)?
    /// How many keys reached the session.
    private(set) var reached = 0

    init(press: @escaping (KeyEvent) -> Bool, session: @escaping (KeyEvent) -> Bool) {
        (self.press, self.session) = (press, session)
    }

    convenience init(_ host: FakeHost) {
        self.init(press: { host.press($0) }, session: { host.press($0) })
    }

    convenience init(_ field: SuggestionsField) {
        self.init(press: { field.press($0) }, session: { key in
            defer { field.noteTimers() }
            return field.host.press(key)
        })
    }

    /// A new key down, now.
    @discardableResult
    func key(_ key: KeyEvent) -> Bool {
        now += 0.08
        last = (key, now - 0.001)
        return deliver(key, at: now - 0.001, new: true)
    }

    /// Types `text`, a key a character (`SuggestionKeys.key`).
    func type(_ text: String) {
        for character in text { key(SuggestionKeys.key(character)) }
    }

    /// The last key's event handed over again, `after` seconds later: what it was answered.
    @discardableResult
    func again(after: TimeInterval = 0.01) -> Bool {
        guard let last else { return false }
        now += after
        return deliver(last.key, at: last.timestamp, new: false)
    }

    private func deliver(_ key: KeyEvent, at timestamp: TimeInterval, new: Bool) -> Bool {
        let echo = KeyEchoes.Key(keyCode: key.keyCode, characters: key.characters, modifiers: UInt(key.modifiers.rawValue),
                                 isRepeat: key.isRepeat, timestamp: timestamp)
        if let answer = echoes.copy(of: echo, now: now) { return answer }
        reached += 1
        let handled = new ? press(key) : session(key)
        echoes.answered(echo, now: now, handled: handled)
        return handled
    }
}

extension KeyEchoesTests {
    /// Pinyin typed, its last letter handed over again: the copy is answered as the letter was (taken) and the session
    /// never sees it: "ni", not "nii".
    @Test func aLetterHandedOverTwiceWhileComposing() async {
        await withInterfaceLanguage("en") {
            let engine = FakeEngine()
            var config = Config.default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
            var services = SessionServices(loadSettings: { config })
            services.levelOne = { .engine(engine) }
            let host = FakeHost(services: services)
            host.focus()
            let keys = KeyFeed(host)
            keys.type("ni")
            let outputs = host.outputs.count
            #expect(keys.again() == true)
            #expect(host.marked == "ni" && engine.input == "ni", "\(host.marked), \(engine.input)")
            #expect(host.outputs.count == outputs && keys.reached == 2)
            keys.type("hao")
            #expect(host.marked == "nihao" && host.panel?.rows.first?.text == "你好", "\(host.marked)")
        }
    }

    /// A key the session lets go by (a digit in English), handed over again: answered as the app's again, the session
    /// untouched.
    @Test func aKeyLetGoByHandedOverTwice() async {
        await withInterfaceLanguage("en") {
            var config = Config.default
            config.uiLanguage = "en"
            config.defaultInput = .english
            config.setOrder([Language.chinese, .english])
            let host = FakeHost(services: SessionServices(loadSettings: { config }))
            host.focus()
            let keys = KeyFeed(host)
            #expect(keys.key(SuggestionKeys.key("1")) == false)
            let outputs = host.outputs.count
            #expect(keys.again() == false)
            #expect(host.outputs.count == outputs && keys.reached == 1)
        }
    }
}

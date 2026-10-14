import Foundation
import Testing
@testable import AllInOneIMECore

/// Typing on a real keyboard layout (the system's own `uchr` tables) through `DeadKeyComposer` and the
/// composer, the way `InputController.handleKeyDown` wires them.
@MainActor
final class Typist {
    let layout: KeyboardLayout
    let composer: Composer
    var deadKeys = DeadKeyComposer()

    init(_ layoutID: String, english: Bool = true) throws {
        layout = try #require(KeyboardLayout(id: layoutID), "\(layoutID) is installed with macOS")
        composer = Composer(engine: FakeEngine(), actionKey: .enter)
        if english { composer.setInputMode(.english) }
    }

    /// The key as the input method receives it: a dead key alone types its accent ("´", "^").
    func event(_ code: UInt16, _ modifiers: KeyModifiers) -> KeyEvent {
        var state: UInt32 = 0
        let characters = layout.translate(code, modifiers, state: &state, deadKeys: false)
        state = 0
        let ignoring = layout.translate(code, modifiers.intersection(.shift), state: &state, deadKeys: false)
        return KeyEvent(keyCode: code, characters: characters, charactersIgnoringModifiers: ignoring, modifiers: modifiers)
    }

    @discardableResult
    func press(_ code: UInt16, _ modifiers: KeyModifiers = []) -> Composer.Response {
        if composer.pendingAccent == nil { deadKeys.reset() }
        let response = composer.handleKeyDown(deadKeys.compose(event(code, modifiers), in: layout))
        if composer.pendingAccent == nil { deadKeys.reset() }
        return response
    }

    /// Types `text` with the plain or Shift keys that type each character on this layout.
    func type(_ text: String) {
        for ch in text {
            guard let (code, modifiers) = key(for: String(ch)) else {
                Issue.record("no key types \(ch) on \(layout.id)")
                return
            }
            press(code, modifiers)
        }
    }

    func key(for text: String, with options: [KeyModifiers] = [[], .shift, .option, [.option, .shift]]) -> (UInt16, KeyModifiers)? {
        for modifiers in options {
            for code in UInt16(0)..<0x33 where event(code, modifiers).characters == text {
                var state: UInt32 = 0
                if layout.translate(code, modifiers, state: &state).isEmpty { continue }  // a dead key
                return (code, modifiers)
            }
        }
        return nil
    }
}

/// Text Input Sources may only be used on the main thread.
@MainActor @Suite(.serialized)
struct KeyboardLayoutTests {
    // Key codes (positions, the same on every layout).
    let keyE: UInt16 = 0x0E, keyN: UInt16 = 0x2D, keyA: UInt16 = 0x00, keyL: UInt16 = 0x25
    let keyQuote: UInt16 = 0x27, key2: UInt16 = 0x13, keyISO: UInt16 = 0x0A, keyBracket: UInt16 = 0x21

    @Test func whereEachLayoutHasTheAtSign() throws {
        // "@" is recognized by its character, so it is wherever the layout has it.
        let at: [(String, UInt16, KeyModifiers)] = [
            ("com.apple.keylayout.US", key2, .shift),
            ("com.apple.keylayout.French", keyISO, []),  // AZERTY: the key left of 1
            ("com.apple.keylayout.German", keyL, .option),  // QWERTZ: ⌥L
        ]
        for (id, code, modifiers) in at {
            let t = try Typist(id)
            #expect(t.event(code, modifiers).characters == "@", "\(id)")
            let r = t.press(code, modifiers)
            #expect(r.handled && t.composer.draft == "@", "\(id)")
        }
    }

    @Test func usDeadKeysOutsideACommand() throws {
        let t = try Typist("com.apple.keylayout.US")
        let dead = t.press(keyE, .option)
        #expect(dead.handled && t.composer.markedText == "´" && commits(dead).isEmpty)
        #expect(commits(t.press(keyE)) == ["é"] && t.composer.markedText.isEmpty)
        t.press(keyN, .option)
        #expect(commits(t.press(keyN)) == ["ñ"])
        // A letter the accent doesn't go on: both, as macOS types them.
        t.press(keyE, .option)
        #expect(commits(t.press(keyN)) == ["´n"])
        // ⌫ takes the accent back; the next E is a plain e (the app types it).
        t.press(keyE, .option)
        #expect(t.press(VirtualKey.delete).handled && t.composer.markedText.isEmpty)
        #expect(t.press(keyE) == .passThrough)
        // Return after an accent: the accent goes in, then the app gets the Return.
        t.press(keyE, .option)
        let enter = t.press(VirtualKey.returnKey)
        #expect(!enter.handled && commits(enter) == ["´"])
    }

    @Test func usDeadKeysInACommand() throws {
        let t = try Typist("com.apple.keylayout.US")
        t.type("@improve caf")
        t.press(keyE, .option)
        #expect(t.composer.markedText.hasSuffix(" caf´"))  // shown as "improve › caf´"
        t.press(keyE)
        t.type(" ma")
        t.press(keyN, .option)
        t.press(keyN)
        t.type("ana")
        #expect(t.composer.draft == "@improve café mañana")
    }

    @Test func azertyCommandText() throws {
        let t = try Typist("com.apple.keylayout.French")
        t.type("@translate o")
        // ù has its own key; ê is ^ (a dead key without modifiers) then e.
        t.type("ù est la gare, f")
        t.press(keyBracket)  // ^
        #expect(t.composer.markedText.hasSuffix("f^"))
        t.press(keyE)
        t.type("te")
        #expect(t.composer.draft == "@translate où est la gare, fête")
    }

    @Test func azertyOutsideACommand() throws {
        let t = try Typist("com.apple.keylayout.French")
        #expect(t.press(keyBracket).handled)
        #expect(commits(t.press(keyE)) == ["ê"])
        // Plain keys still go straight to the app (q where US has a).
        #expect(t.event(keyA, []).characters == "q" && t.press(keyA) == .passThrough)
    }

    @Test func qwertzCommandText() throws {
        let t = try Typist("com.apple.keylayout.German")
        t.press(keyL, .option)  // @
        t.type("improve Übermorgen im Caf")
        t.press(0x18)  // ´, a dead key
        t.press(keyE)
        #expect(t.composer.draft == "@improve Übermorgen im Café")
    }

    @Test func usInternationalQuotes() throws {
        let t = try Typist("com.apple.keylayout.USInternational-PC")
        t.type("@improve don")
        t.press(keyQuote)  // ' is a dead key here
        t.press(0x11)  // t: no accent goes on it, both are typed
        t.type(" ol")
        t.press(keyQuote)
        t.press(keyA)
        t.press(keyQuote)
        t.press(VirtualKey.space)  // ' then Space: just the apostrophe
        #expect(t.composer.draft == "@improve don't olá'")
    }

    @Test func chineseModeKeepsDeadKeysAsBefore() throws {
        let t = try Typist("com.apple.keylayout.US", english: false)
        // Nothing pending in Chinese mode: the key is the app's, as it always was; pinyin is untouched.
        #expect(t.press(keyE, .option) == .passThrough && t.composer.pendingAccent == nil)
        t.type("ni")
        t.press(keyE, .option)
        #expect(t.composer.pendingAccent == nil && !t.composer.markedText.contains("´"))
    }

    @Test func pendingAccentGoesInWhenTheFieldIsLeft() throws {
        let t = try Typist("com.apple.keylayout.US")
        t.type("@improve caf")
        t.press(keyE, .option)
        #expect(commits(t.composer.commitAll()) == ["@improve caf´"])
        t.press(keyE, .option)
        #expect(commits(t.composer.commitAll()) == ["´"] && t.composer.pendingAccent == nil)
    }

    /// An accent waiting for its letter is a composition, like a Hangul syllable: the language doesn't switch under it.
    @Test func aPendingAccentIsAComposition() throws {
        let t = try Typist("com.apple.keylayout.US")
        t.press(keyE, .option)
        #expect(t.composer.pendingAccent == "´" && t.composer.isComposing)
        t.composer.setInputMode(.chinese)
        #expect(t.composer.inputLanguage == .english)  // refused while it waits
        #expect(commits(t.press(keyE)) == ["é"])
        #expect(!t.composer.isComposing)
        t.press(keyE, .option)
        t.press(VirtualKey.escape)  // takes it back
        #expect(t.composer.pendingAccent == nil && !t.composer.isComposing)
        // AZERTY's ^.
        let french = try Typist("com.apple.keylayout.French")
        french.press(0x21)
        #expect(french.composer.pendingAccent == "^" && french.composer.isComposing)
        french.type("e")
        #expect(french.composer.pendingAccent == nil && !french.composer.isComposing)
    }

    /// An accent waiting when the language switches or dictation starts goes in as is: none is left marked before
    /// Hangul or after the transcript.
    @Test func aWaitingAccentGoesInOnShiftAndDictation() throws {
        let t = try Typist("com.apple.keylayout.US")
        t.composer.hangulTables = PackData.hangul
        t.composer.inputLanguages = [.english, .korean]
        t.press(keyE, .option)
        _ = t.composer.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 1)
        let shift = t.composer.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1)
        #expect(commits(shift) == ["´"] && t.composer.pendingAccent == nil)
        #expect(t.composer.inputLanguage == .korean)
        t.press(5)  // g: ㅎ
        t.press(40)  // k: ㅏ
        #expect(t.composer.markedText == "하")
        // Dictation in a command's text: the accent, then what was said.
        let d = try Typist("com.apple.keylayout.US")
        d.type("@improve caf")
        d.press(keyE, .option)
        _ = d.composer.handleFlagsChanged(keyCode: VirtualKey.rightOption, modifiers: [.option, .rightOption], timestamp: 2)
        _ = d.composer.voiceHoldElapsed()
        #expect(d.composer.pendingAccent == nil && d.composer.draft == "@improve caf´")
        _ = d.composer.voiceFinished("hello", id: 1)
        #expect(d.composer.draft.hasPrefix("@improve caf´") && d.composer.draft.hasSuffix("hello") && !d.composer.markedText.hasSuffix("´"))
    }

    @Test func aLayoutOtherThanTheKeysLeavesThemAlone() throws {
        // The keys say "q" where the layout has "a": not this layout's keys, nothing is composed.
        let us = try #require(KeyboardLayout(id: "com.apple.keylayout.US"))
        var composer = DeadKeyComposer()
        let q = KeyEvent(keyCode: keyA, characters: "q")
        #expect(composer.compose(q, in: us) == q)
    }
}

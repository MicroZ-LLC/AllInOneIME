import Foundation
import Testing
@testable import AllInOneIMECore

/// A clock the tests move by hand (`TranslateMode.ShiftHold`'s), with the pointer and Sticky Keys it reads.
final class HandClock: @unchecked Sendable {
    var now: TimeInterval = 100
    var pointer = CGPoint(x: 500, y: 300)
    var stickyKeys = false
}

// MARK: - The long press of Shift

/// `TranslateMode.ShiftHold` on a clock moved by hand, through a class (its mutating calls inside `#expect`).
final class HoldProbe {
    let clock = HandClock()
    lazy var hold = TranslateMode.ShiftHold(now: { [clock] in clock.now }, pointer: { [clock] in clock.pointer },
                                            stickyKeys: { [clock] in clock.stickyKeys })

    /// A modifier change; true: armed.
    func flags(_ keyCode: UInt16 = VirtualKey.leftShift, _ modifiers: KeyModifiers) -> Bool {
        hold.flagsChanged(keyCode: keyCode, modifiers: modifiers)
    }
    func down(_ keyCode: UInt16 = VirtualKey.leftShift) -> Bool { flags(keyCode, .shift) }
    func up(_ keyCode: UInt16 = VirtualKey.leftShift) -> Bool { flags(keyCode, []) }
    func key() { hold.keyDown() }
    func wait(_ seconds: TimeInterval) { clock.now += seconds }
    func move(_ dx: CGFloat, _ dy: CGFloat = 0) { clock.pointer.x += dx; clock.pointer.y += dy }
    func poll(pointerUsed: Bool = false) -> TranslateMode.ShiftHold.Due? { hold.poll(pointerUsed: pointerUsed) }
}

struct ShiftHoldTests {
    @Test func aLongPressHintsAtAboutHalfwayThenTogglesOnce() {
        let h = HoldProbe()
        #expect(h.down())
        h.wait(0.25)
        #expect(h.poll() == nil)
        h.wait(0.25)  // 0.5 s
        #expect(h.poll() == .hint)
        #expect(h.poll() == nil)  // once
        h.wait(0.4)  // 0.9 s
        #expect(h.poll() == nil)
        h.wait(0.1)  // 1.0 s
        #expect(h.poll() == .toggle)
        h.wait(2)  // held on: still the one toggle
        #expect(h.poll() == nil)
        #expect(!h.up())  // released
        #expect(h.hold.held == nil)
        #expect(h.poll() == nil)
    }

    @Test func aLateTimerStillGetsTheToggle() {
        // Both timers late: the toggle is due, and the hint, now past, isn't shown after it.
        let h = HoldProbe()
        #expect(h.down(VirtualKey.rightShift))
        h.wait(1.4)
        #expect(h.poll() == .toggle)
        #expect(h.poll() == nil)
    }

    @Test func aTapIsNoLongPress() {
        let h = HoldProbe()
        #expect(h.down())
        h.wait(0.15)
        #expect(!h.up())
        h.wait(1)  // the tap's timers go off later
        #expect(h.poll() == nil)
        #expect(h.poll() == nil)
    }

    @Test func releasedBeforeTheToggleNothingHappens() {
        let h = HoldProbe()
        #expect(h.down())
        h.wait(0.6)
        #expect(h.poll() == .hint)
        h.wait(0.3)  // 0.9 s: let go
        #expect(!h.up())
        h.wait(0.3)
        #expect(h.poll() == nil)
    }

    @Test func shiftWithALetterNeverToggles() {
        let h = HoldProbe()
        // A capital typed quickly.
        #expect(h.down())
        h.wait(0.1)
        h.key()
        h.wait(1)
        #expect(h.poll() == nil)
        // A capital typed slowly, after the hint: still no toggle, even held on.
        _ = h.up()
        #expect(h.down())
        h.wait(0.55)
        #expect(h.poll() == .hint)
        h.key()
        h.wait(1)
        #expect(h.poll() == nil)
    }

    @Test func otherModifiersAreShortcutsNotALongPress() {
        let h = HoldProbe()
        // ⌘ already down, then Shift: ⌘⇧ something.
        #expect(!h.flags(VirtualKey.leftShift, [.shift, .command]))
        h.wait(1)
        #expect(h.poll() == nil)
        // Shift, then ⌥ joins.
        _ = h.up()
        #expect(h.down())
        #expect(!h.flags(VirtualKey.leftOption, [.shift, .option, .leftOption]))
        h.wait(1)
        #expect(h.poll() == nil)
        // ⌃ with Shift: no. Both Shifts: no.
        #expect(!h.flags(VirtualKey.rightShift, [.shift, .control]))
        _ = h.up()
        #expect(h.down())
        #expect(!h.down(VirtualKey.rightShift))
        h.wait(1)
        #expect(h.poll() == nil)
        // Caps Lock on doesn't count.
        _ = h.flags(VirtualKey.leftShift, [.capsLock])
        #expect(h.flags(VirtualKey.rightShift, [.shift, .capsLock]))
        h.wait(1.0)
        #expect(h.poll() == .toggle)
    }

    @Test func aShiftClickIsNoLongPress() {
        let h = HoldProbe()
        #expect(h.down())
        h.wait(1.1)
        #expect(h.poll(pointerUsed: true) == nil)
        #expect(h.poll() == nil)
    }

    /// Shift held while the mouse moves to where a Shift-click will go: no hint, no toggle. A hand resting on the
    /// mouse (a point or two) is still a long press.
    @Test func aShiftClickBeingAimedIsNoLongPress() {
        let h = HoldProbe()
        #expect(h.down())
        h.move(40, -25)
        h.wait(0.5)
        #expect(h.poll() == nil)
        h.wait(0.5)
        #expect(h.poll() == nil && h.hold.held == nil)
        // Moved after the hint: no toggle.
        _ = h.up()
        #expect(h.down())
        h.wait(0.5)
        #expect(h.poll() == .hint)
        h.move(0, 120)
        h.wait(0.5)
        #expect(h.poll() == nil && h.hold.held == nil)
        // Barely moved: on as ever.
        _ = h.up()
        #expect(h.down())
        h.move(2, 2)
        h.wait(0.5)
        #expect(h.poll() == .hint)
        h.move(-1, 1)
        h.wait(0.5)
        #expect(h.poll() == .toggle)
        #expect(TranslateMode.ShiftHold.pointerSlack < 10)
    }

    /// Only Shift going down from no Shift starts a press: the other Shift pressed and let go while one is held starts
    /// none, held on.
    @Test func theOtherShiftLetGoStartsNoPress() {
        let h = HoldProbe()
        #expect(h.down())
        h.wait(0.2)
        #expect(!h.flags(VirtualKey.rightShift, .shift))  // the right one down too
        h.wait(0.1)
        #expect(!h.flags(VirtualKey.rightShift, .shift))  // …and up, the left one still down
        h.wait(1)
        #expect(h.poll() == nil && h.hold.held == nil)
        // Let go of both: the next press counts again.
        #expect(!h.up())
        #expect(h.down(VirtualKey.rightShift))
        h.wait(1)
        #expect(h.poll() == .toggle)
        // A capital typed, then the other Shift pressed and let go: still no press.
        _ = h.up(VirtualKey.rightShift)
        #expect(h.down())
        h.key()
        #expect(!h.flags(VirtualKey.rightShift, .shift) && !h.flags(VirtualKey.rightShift, .shift))
        h.wait(1)
        #expect(h.poll() == nil)
    }

    /// Shift's release gone unseen (let go in another app, a password field): synced again with Shift as it really is
    /// (`resync`, a field becoming active), the next press is timed.
    @Test func aReleaseGoneUnseenIsSyncedAgain() {
        let h = HoldProbe()
        #expect(h.down())
        h.hold.cancel()  // another field became active; Shift let go where it went unseen
        h.hold.resync(shiftDown: false)
        #expect(h.down())
        h.wait(1)
        #expect(h.poll() == .toggle)
        // Still down, as it really is: no press until it's let go and pressed again.
        h.hold.resync(shiftDown: true)
        #expect(h.hold.held == nil && !h.down())
        #expect(!h.up() && h.down())
    }

    /// fn (🌐) held with Shift, before or after it, is no long press; neither is a Shift that Sticky Keys latches.
    @Test func fnOrStickyKeysNeverToggle() {
        let fnKey: UInt16 = 0x3F
        let h = HoldProbe()
        #expect(!h.flags(VirtualKey.leftShift, [.shift, .function]))
        h.wait(1)
        #expect(h.poll() == nil)
        _ = h.up()
        #expect(h.down())
        #expect(!h.flags(fnKey, [.shift, .function]))
        h.wait(1)
        #expect(h.poll() == nil)
        _ = h.up()
        // Sticky Keys on: Shift pressed once stays down until the next key, as if held.
        let sticky = HoldProbe()
        sticky.clock.stickyKeys = true
        #expect(!sticky.down())
        sticky.wait(1.5)
        #expect(sticky.poll() == nil)
        _ = sticky.up()
        sticky.clock.stickyKeys = false
        #expect(sticky.down())
    }

    @Test func theTimesOfTheSpec() {
        #expect(TranslateMode.ShiftHold.hintAfter == 0.5 && TranslateMode.ShiftHold.toggleAfter == 1.0)
    }

    /// The same Shift presses through the composer (its tap logic, unchanged) and the detector: a tap switches the input
    /// language and is no long press; a long press switches nothing and toggles.
    @Test func aTapStillSwitchesTheInputLanguage() {
        let h = HoldProbe()
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        func switched(_ down: Bool) -> Bool {
            let effects = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: down ? .shift : [], timestamp: h.clock.now)
            return effects.contains { if case .inputLanguageChanged = $0 { return true } else { return false } }
        }
        #expect(!switched(true))
        #expect(h.down())
        h.wait(0.2)
        #expect(switched(false) && c.inputLanguage == .english)
        #expect(!h.up())
        h.wait(1)
        #expect(h.poll() == nil)

        #expect(!switched(true))
        #expect(h.down())
        h.wait(1.0)
        #expect(h.poll() == .toggle)
        h.wait(0.1)
        #expect(!switched(false) && c.inputLanguage == .english)
        #expect(!h.up())
    }
}

// MARK: - The composer in the mode

struct TranslateModeComposerTests {
    let english = TranslateMode.Session(target: .english)
    let shiftEnter = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift)
    let hello = ConversionResult(translations: [Translation(language: .english, line: CandidateLine("Hello"))])

    /// A composer with Translate as You Type on into English (pinyin first), ⏎ as the action key.
    func composer(_ session: TranslateMode.Session? = TranslateMode.Session(target: .english)) -> (Composer, FakeEngine) {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        c.commands = Command.builtins
        if let session { _ = c.setTranslateMode(session) }
        return (c, engine)
    }

    /// `text` typed, a space as the Space key.
    @discardableResult
    func type(_ text: String, _ c: Composer) -> [Composer.Effect] {
        text.flatMap { c.handleKeyDown($0 == " " ? spaceKey : k(String($0))).effects }
    }

    func request(_ effects: [Composer.Effect]) -> (input: String, session: TranslateMode.Session, id: Int)? {
        for effect in effects {
            if case let .startTranslateMode(input, session, id) = effect { return (input, session, id) }
        }
        return nil
    }

    func notices(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .notice(text) = $0 { return text } else { return nil } }
    }

    /// "nihao", Space: 「你好」 in the mode's draft.
    func draftNihao(_ c: Composer) {
        type("nihao", c)
        _ = c.handleKeyDown(spaceKey)
    }

    @Test func pinyinCollectsIntoADraftShownAsTyped() {
        let (c, _) = composer()
        type("nihao", c)
        #expect(c.markedText == "nihao" && c.wantsPanel)  // the candidates
        let space = c.handleKeyDown(spaceKey)
        #expect(commits(space).isEmpty && c.draft == "你好" && c.phase == .drafting)
        #expect(c.markedText == "你好" && c.inModeComposition && !c.wantsPanel)
        type("wo", c)
        _ = c.handleKeyDown(spaceKey)
        #expect(c.draft == "你好我" && c.markedText == "你好我")
    }

    @Test func returnTranslatesAndInsertsWithNoCandidates() {
        let (c, _) = composer()
        draftNihao(c)
        let enter = c.handleKeyDown(enterKey)
        let sent = request(enter.effects)
        #expect(enter.handled && sent?.input == "你好" && sent?.session == english && commits(enter).isEmpty)
        #expect(c.markedText == "你好 · 翻译中…" && c.choices.isEmpty && !c.wantsPanel)
        // Partial results don't go in.
        #expect(commits(c.receive(hello, isFinal: false, id: sent!.id)).isEmpty && c.markedText == "你好 · 翻译中…")
        let done = c.receive(hello, isFinal: true, id: sent!.id)
        #expect(commits(done) == ["Hello"] && c.phase == .idle && c.draft.isEmpty && c.markedText.isEmpty && c.choices.isEmpty)
        // Not sent: the next ⏎ is the app's.
        #expect(!c.handleKeyDown(enterKey).handled)
        // The mode stays on: the next sentence collects again.
        draftNihao(c)
        #expect(c.draft == "你好")
    }

    @Test func returnWhilePinyinIsTypedPicksItFirst() {
        let (c, _) = composer()
        type("nihao", c)
        let enter = c.handleKeyDown(enterKey)
        #expect(request(enter.effects)?.input == "你好" && commits(enter).isEmpty)
    }

    @Test func aModelThatIgnoredTheFormatStillGoesIn() {
        let (c, _) = composer()
        draftNihao(c)
        let id = request(c.handleKeyDown(enterKey).effects)!.id
        #expect(commits(c.receive(ConversionResult(versions: [CandidateLine("Hi")]), isFinal: true, id: id)) == ["Hi"])
    }

    @Test func shiftReturnInsertsAsTyped() {
        let (c, _) = composer()
        draftNihao(c)
        let asTyped = c.handleKeyDown(shiftEnter)
        #expect(commits(asTyped) == ["你好"] && request(asTyped.effects) == nil && c.phase == .idle)
        // Pinyin still being typed is picked first, as ⏎ does.
        type("nihao", c)
        let typed = c.handleKeyDown(shiftEnter)
        #expect(commits(typed) == ["你好"] && request(typed.effects) == nil)
    }

    @Test func escapeWhileTranslatingCancelsAndKeepsTheDraft() {
        let (c, _) = composer()
        draftNihao(c)
        let id = request(c.handleKeyDown(enterKey).effects)!.id
        let esc = c.handleKeyDown(escKey)
        #expect(esc.effects.contains(.cancelConversion) && commits(esc).isEmpty)
        #expect(c.phase == .drafting && c.draft == "你好" && c.markedText == "你好")
        // An answer arriving late goes nowhere.
        #expect(c.receive(hello, isFinal: true, id: id).isEmpty && c.draft == "你好")
        // ⏎ translates it again.
        #expect(request(c.handleKeyDown(enterKey).effects)?.input == "你好")
    }

    @Test func typingOnWhileTranslatingStopsItAndGoesOn() {
        let (c, _) = composer()
        draftNihao(c)
        _ = c.handleKeyDown(enterKey)
        let typed = c.handleKeyDown(k("w"))
        #expect(typed.effects.contains(.cancelConversion) && c.phase == .drafting && c.markedText == "你好w")
        // ⇧⏎ while it's translating: as typed.
        type("o", c)
        _ = c.handleKeyDown(spaceKey)
        _ = c.handleKeyDown(enterKey)
        let asTyped = c.handleKeyDown(shiftEnter)
        #expect(commits(asTyped) == ["你好我"] && asTyped.effects.contains(.cancelConversion))
    }

    /// ⌫ while it's translating: stopped, and one character deleted, as ⌫ does on the draft.
    @Test func deleteWhileTranslatingStopsItAndDeletes() {
        let (onDraft, _) = composer()
        draftNihao(onDraft)
        _ = onDraft.handleKeyDown(backspaceKey)
        #expect(onDraft.draft == "你")
        let (c, _) = composer()
        draftNihao(c)
        let id = request(c.handleKeyDown(enterKey).effects)!.id
        let delete = c.handleKeyDown(backspaceKey)
        #expect(delete.handled && delete.effects.contains(.cancelConversion) && commits(delete).isEmpty)
        #expect(c.phase == .drafting && c.draft == onDraft.draft && c.markedText == "你")
        // The answer arriving late goes nowhere; ⏎ translates what's left.
        #expect(c.receive(hello, isFinal: true, id: id).isEmpty && c.draft == "你")
        #expect(request(c.handleKeyDown(enterKey).effects)?.input == "你")
    }

    @Test func aFailureKeepsTheDraftAndReturnRetries() {
        let (c, _) = composer()
        draftNihao(c)
        let first = request(c.handleKeyDown(enterKey).effects)!.id
        let failed = c.fail("网络连接失败", id: first)
        #expect(notices(failed) == [TranslateMode.Messages.chinese.failed("网络连接失败")] && commits(failed).isEmpty)
        #expect(notices(failed).first?.contains("网络连接失败") == true && notices(failed).first?.contains("\n") == false)
        #expect(c.phase == .drafting && c.draft == "你好" && c.markedText == "你好")
        let retry = request(c.handleKeyDown(enterKey).effects)
        #expect(retry?.input == "你好" && retry!.id != first)
        // No translation at all: the same.
        let none = c.receive(.empty, isFinal: true, id: retry!.id)
        #expect(notices(none) == [TranslateMode.Messages.chinese.failed(c.messages.noResult)] && c.draft == "你好")
    }

    @Test func typingInTheTargetLanguageGoesInAsTyped() {
        let (c, _) = composer()
        c.setInputMode(.english)
        let letter = c.handleKeyDown(k("h"))
        #expect(!letter.handled && c.draft.isEmpty && c.markedText.isEmpty && !c.inModeComposition)
        #expect(!c.handleKeyDown(enterKey).handled)
    }

    @Test func aDraftAlreadyInTheTargetLanguageGoesInAsTyped() {
        let (c, _) = composer()
        type("2026", c)  // digits, in pinyin mode
        #expect(c.draft == "2026")
        let enter = c.handleKeyDown(enterKey)
        #expect(commits(enter) == ["2026"] && request(enter.effects) == nil)
    }

    @Test func fromEnglishIntoChinese() {
        let (c, _) = composer(TranslateMode.Session(target: .chinese))
        c.setInputMode(.english)
        // A space before anything goes in as usual.
        #expect(!c.handleKeyDown(spaceKey).handled && c.draft.isEmpty)
        type("hello world", c)
        #expect(c.draft == "hello world" && c.markedText == "hello world")
        #expect(request(c.handleKeyDown(enterKey).effects)?.input == "hello world")
    }

    @Test func noAIInsertsAsTypedSecureInputKeepsTheDraft() {
        let (c, _) = composer()
        c.aiRefusal = { "AI is off in this app" }
        draftNihao(c)
        let refused = c.handleKeyDown(enterKey)
        #expect(commits(refused) == ["你好"] && notices(refused.effects) == ["AI is off in this app"] && request(refused.effects) == nil)

        c.aiRefusal = { nil }
        draftNihao(c)
        c.secureInputActive = { true }
        let secure = c.handleKeyDown(enterKey)
        #expect(commits(secure).isEmpty && request(secure.effects) == nil && c.draft == "你好" && c.phase == .drafting)
        #expect(notices(secure.effects) == [c.translateModeMessages.failed(c.translateModeMessages.secureInput)])
        c.secureInputActive = { false }
        #expect(request(c.handleKeyDown(enterKey).effects)?.input == "你好")  // ⏎ tries again
        _ = c.handleKeyDown(escKey)
        _ = c.handleKeyDown(escKey)
        c.secureInputActive = { true }
        // Secure input on from the start: nothing collects, words go in as usual.
        type("nihao", c)
        #expect(commits(c.handleKeyDown(spaceKey)) == ["你好"] && c.draft.isEmpty)
    }

    @Test func turnedOffItsDraftGoesInAndTypingIsAsBefore() {
        let (c, _) = composer()
        draftNihao(c)
        type("wo", c)
        #expect(commits(c.setTranslateMode(nil)) == ["你好我"] && c.translateMode == nil && c.phase == .idle)
        type("nihao", c)
        #expect(commits(c.handleKeyDown(spaceKey)) == ["你好"] && c.markedText.isEmpty)
        // A command's draft isn't the mode's: it stays when the mode goes.
        let (d, _) = composer()
        type("@impr", d)
        _ = d.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        #expect(commits(d.setTranslateMode(nil)).isEmpty && d.draft == "@improve ")
    }

    /// The target comes from the state (the last pick, else the first output language), never from the language typed:
    /// with Chinese and English typed, turned on while English is typed it still translates into English, and English
    /// goes in as typed.
    @Test func theLanguageTypedHasNoSayInTheTarget() {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.setOrder([OutputLanguage.english, .chinese])
        var state = TranslateMode.State()
        let (c, _) = composer(nil)
        c.setInputMode(.english)
        let session = state.enter(last: nil, config: config)
        #expect(session == english)
        _ = c.setTranslateMode(session)
        #expect(!c.handleKeyDown(k("h")).handled && c.draft.isEmpty && c.markedText.isEmpty)
        // Chinese typed collects, into English.
        c.setInputMode(.chinese)
        draftNihao(c)
        #expect(c.markedText == "你好")
    }

    /// The chip (「中 → 英」): none while it's off; its source is the language typed (a click on it, a tap of Shift,
    /// switches it), its target the session's; its list the output languages, the target checked.
    @Test func theChip() throws {
        #expect(composer(nil).0.translateModeChip() == nil)
        let (c, _) = composer()
        let chip = try #require(c.translateModeChip())
        #expect(chip.text == "中 → 英" && chip.sourceText == "中" && chip.targetText == "英" && chip.choices == nil)
        #expect(c.shiftTapped().contains(.inputLanguageChanged(.english)) && c.translateModeChip()?.text == "英 → 英")
        _ = c.shiftTapped()
        #expect(c.translateModeChip()?.text == "中 → 英")
        let ja = OutputLanguage("ja")
        let list = try #require(c.translateModeChip(choices: [.english, ja, .chinese]))
        #expect(list.choices == [.english, ja, .chinese] && list.checks(.english) && !list.checks(ja) && !list.checks(.chinese))
        #expect(list.choice(at: 1) == ja && list.choice(at: 3) == nil && list.choice(at: -1) == nil && chip.choice(at: 0) == nil)
        #expect(TranslateMode.Chip(source: .english, target: .chinese).text == "英 → 中")
        #expect(TranslateMode.Chip(source: .chinese, target: OutputLanguage("zh-Hant")).text == "中 → 繁")
    }

    /// A click on the chip's source part does what a tap of Shift does, to the letter.
    @Test func aClickOnTheSourceIsATapOfShift() {
        let (a, _) = composer(), (b, _) = composer()
        draftNihao(a)
        draftNihao(b)
        type("wo", a)
        type("wo", b)
        let tap = a.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 1)
            + a.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1)
        let click = b.shiftTapped()
        #expect(!tap.isEmpty && tap == click)
        #expect(a.inputLanguage == .english && b.inputLanguage == .english && a.markedText == b.markedText && a.draft == b.draft)
        // One input language: nothing, as for Shift.
        let (one, _) = composer()
        one.inputLanguages = [.chinese]
        #expect(one.shiftTapped().isEmpty && one.inputLanguage == .chinese)
    }

    /// Another target picked on the chip: the draft stays, the chip names the new one, and ⏎ translates into it.
    @Test func anotherTargetKeepsTheDraft() {
        let (c, _) = composer()
        draftNihao(c)
        let japanese = TranslateMode.Session(target: OutputLanguage("ja"))
        let picked = c.setTranslateMode(japanese)
        #expect(commits(picked).isEmpty && picked.contains(.updateMarkedText))
        #expect(c.draft == "你好" && c.markedText == "你好" && c.translateModeChip()?.text == "中 → 日")
        let sent = request(c.handleKeyDown(enterKey).effects)
        #expect(sent?.session == japanese && sent?.input == "你好")
    }

    @Test func typedOutWhereResultsAre() {
        let (c, _) = composer()
        c.typesResults = true
        draftNihao(c)
        let id = request(c.handleKeyDown(enterKey).effects)!.id
        #expect(c.receive(hello, isFinal: true, id: id).contains(.typeOut("Hello")))
    }

    @Test func offNothingChanges() {
        let (c, _) = composer(nil)
        type("nihao", c)
        #expect(c.markedText == "nihao" && !c.inModeComposition)
        #expect(commits(c.handleKeyDown(spaceKey)) == ["你好"])
        #expect(!c.handleKeyDown(enterKey).handled)
    }

    /// No command turns it on or off: only a long press of Shift, an app's setting, and switching apps.
    @Test func noCommandForIt() {
        #expect(!Command.builtins.contains { $0.name == "mode" || $0.name == "exit" })
    }
}

// MARK: - The tone

struct TranslateModeToneTests {
    func config(_ profiles: [String: AppProfile] = [:]) -> Config {
        var config = Config.default
        config.appProfiles = profiles
        return config
    }

    @Test func theAppsFirstRewriteStyle() {
        let app = "com.example.notes"
        #expect(TranslateMode.tone(app: app, config: config([app: AppProfile(rewriteStyles: ["正式", "口语"])])) == .formal)
        #expect(TranslateMode.tone(app: app, config: config([app: AppProfile(rewriteStyles: ["口语"])])) == .casual)
        #expect(TranslateMode.tone(app: app, config: config([app: AppProfile(rewriteStyles: ["CONCISE"])])) == .concise)
        #expect(TranslateMode.tone(app: app, config: config([app: AppProfile(rewriteStyles: ["委婉"])])) == .tactful)
        #expect(TranslateMode.tone(app: app, config: config([app: AppProfile(rewriteStyles: ["黑话"])])) == .jargon)
        #expect(TranslateMode.tone(app: app, config: config([app: AppProfile(rewriteStyles: ["润色"])])) == .natural)
        // Its bundle id in any case; an unknown name passed over.
        #expect(TranslateMode.tone(app: "COM.EXAMPLE.NOTES", config: config([app: AppProfile(rewriteStyles: ["nope", "正式"])])) == .formal)
        // No styles there: by the kind of app.
        #expect(TranslateMode.tone(app: "com.apple.mail", config: config(["com.apple.mail": AppProfile(rewriteStyles: [])])) == .formal)
        // A chat app's own style beats its kind.
        #expect(TranslateMode.tone(app: "com.tencent.xinWeChat", config: config(["com.tencent.xinWeChat": AppProfile(rewriteStyles: ["正式"])])) == .formal)
    }

    @Test func byTheKindOfApp() {
        let chats = ["com.tencent.xinWeChat", "com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "ru.keepcoder.Telegram",
                     "com.hnc.Discord", "com.microsoft.teams2"]
        let mail = ["com.apple.mail", "com.microsoft.Outlook", "com.readdle.SparkDesktop"]
        #expect(chats.allSatisfy { TranslateMode.tone(app: $0, config: config()) == .casual })
        #expect(mail.allSatisfy { TranslateMode.tone(app: $0, config: config()) == .formal })
        #expect(TranslateMode.tone(app: "com.apple.TextEdit", config: config()) == .natural)
        #expect(TranslateMode.tone(app: nil, config: config()) == .natural)
    }

    @Test func theRequestSaysTheTone() {
        let request = Prompt.translateModeRequest(for: "你好", target: .english, tone: .casual, config: .default)
        #expect(request.system[0].text.hasSuffix("- " + AppTone.casual.rule))
        #expect(AppTone.allCases.map(\.rule).count == Set(AppTone.allCases.map(\.rule)).count)
    }
}

// MARK: - App switches and translateAlways

/// `TranslateMode.State` through a class (its mutating calls inside `#expect`), with `last` the language picked last.
final class StateProbe {
    var state = TranslateMode.State()
    let config: Config
    var last: OutputLanguage?
    init(_ config: Config) { self.config = config }

    func activated(_ app: String?) -> TranslateMode.State.Transition { state.activated(app: app, last: last, config: config) }
    @discardableResult
    func enter() -> TranslateMode.Session? { state.enter(last: last, config: config) }
    func leave() { state.leave() }
    func retarget(_ target: OutputLanguage) -> TranslateMode.Session? { state.retarget(target) }
    func appActivated(_ app: String?) -> TranslateMode.State.Transition { state.appActivated(app, config: config) }
    var isOn: Bool { state.isOn }
}

struct TranslateModeStateTests {
    let wechat = "com.tencent.xinWeChat", notes = "com.apple.Notes", mail = "com.apple.mail", slack = "com.tinyspeck.slackmacgap"
    let finder = "com.apple.finder"
    let english = TranslateMode.Session(target: .english)

    /// Chinese and English typed, into English and Chinese.
    var config: Config {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.setOrder([OutputLanguage.english, .chinese])
        return config
    }

    @Test func anotherAppLeavesTheMode() {
        let s = StateProbe(config)
        #expect(s.activated(notes) == .unchanged)
        #expect(s.enter() == english && s.isOn)
        // Another field of the same app (its id in any case).
        #expect(s.activated(notes) == .unchanged && s.isOn)
        #expect(s.activated("COM.APPLE.NOTES") == .unchanged && s.isOn)
        // Another app.
        #expect(s.activated(mail) == .left(english) && !s.isOn)
        #expect(s.activated(notes) == .unchanged && !s.isOn)
    }

    /// Another app becoming active (`appActivated`) leaves it, a text field in it or not, whichever of the app and its
    /// field comes first; coming back doesn't turn it on again.
    @Test func anotherAppActiveLeavesTheModeFieldOrNot() {
        let s = StateProbe(config)
        _ = s.activated(notes)
        s.enter()
        // Its own app, after its field: nothing changes.
        #expect(s.appActivated(notes) == .unchanged && s.isOn)
        // Finder, with no text field: off.
        #expect(s.appActivated(finder) == .left(english) && !s.isOn)
        // Back: still off.
        #expect(s.appActivated(notes) == .unchanged && s.activated(notes) == .unchanged && !s.isOn)
        // Another app, its field first: off; its activation then changes nothing.
        s.enter()
        #expect(s.activated(mail) == .left(english) && s.appActivated(mail) == .unchanged && !s.isOn)
        // …or the app first.
        s.enter()
        #expect(s.appActivated(notes) == .left(english) && s.activated(notes) == .unchanged && !s.isOn)
        // Off: nothing to leave.
        #expect(s.appActivated(finder) == .unchanged)
    }

    /// An app that translates always: becoming active doesn't leave it (its field keeps it on, or turns it on).
    @Test func anAppThatTranslatesAlwaysBecomingActive() {
        var config = config
        config.appProfiles = [wechat: AppProfile(translateAlways: true)]
        let s = StateProbe(config)
        _ = s.activated(notes)
        s.enter()
        // Switched to, the app first: on as it was.
        #expect(s.appActivated(wechat) == .unchanged && s.activated(wechat) == .unchanged && s.state.session == english)
        // To Finder: off. Back: on again once its field is active.
        #expect(s.appActivated(finder) == .left(english) && !s.isOn)
        #expect(s.appActivated(wechat) == .unchanged && !s.isOn)
        #expect(s.activated(wechat) == .entered(english))
        // Turned off there by hand: it becoming active again (from the input method's own window) leaves it off.
        s.leave()
        #expect(s.appActivated(wechat) == .unchanged && s.activated(wechat) == .unchanged && !s.isOn)
    }

    /// Through an app that translates always and back, its text field active there or not: that was switching to
    /// another app all the same, off whichever of the app and its field comes first.
    @Test func throughAnAppThatTranslatesAlwaysAndBack() {
        var config = config
        config.appProfiles = [wechat: AppProfile(translateAlways: true)]
        let s = StateProbe(config)
        _ = s.activated(notes)
        s.enter()
        #expect(s.appActivated(wechat) == .unchanged && s.isOn)
        #expect(s.activated(notes) == .left(english) && !s.isOn)
        // The app first.
        s.enter()
        #expect(s.appActivated(wechat) == .unchanged && s.isOn)
        #expect(s.appActivated(notes) == .left(english) && s.activated(notes) == .unchanged && !s.isOn)
        // Its field active there.
        s.enter()
        #expect(s.appActivated(wechat) == .unchanged && s.activated(wechat) == .unchanged && s.isOn)
        #expect(s.activated(notes) == .left(english) && !s.isOn)
    }

    /// The target removed from the output languages in the settings while it's on: the first of them something typed is
    /// translated into at once (none left: off), the draft kept and the chip following.
    @Test func aTargetRemovedInTheSettingsGivesWayToTheFirst() throws {
        let ja = OutputLanguage("ja")
        var state = TranslateMode.State()
        #expect(!state.follow(outputs: [.english]) && !state.isOn)  // off: nothing
        var config = Config.default
        config.setOrder([OutputLanguage.english, ja, .chinese])
        state.enter(last: ja, config: config)
        #expect(!state.follow(outputs: [.chinese, ja]) && state.session?.target == ja)  // still offered
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        _ = c.setTranslateMode(state.session)
        type("nihao", c)
        _ = c.handleKeyDown(spaceKey)
        #expect(state.follow(outputs: [.english, .chinese], inputs: [.chinese, .english]) && state.session == english)
        #expect(commits(c.setTranslateMode(state.session)).isEmpty && c.draft == "你好" && c.translateModeChip()?.text == "中 → 英")
        #expect(state.follow(outputs: []) && !state.isOn)  // none left
        // English alone typed (the config's): not to English, where it would only put text in as typed, but Chinese.
        state.enter(last: ja, config: config)
        #expect(state.follow(outputs: [.english, .chinese], inputs: config.inputLanguages) && state.session?.target == .chinese)
    }

    func type(_ text: String, _ c: Composer) {
        for ch in text { _ = c.handleKeyDown(k(String(ch))) }
    }

    @Test func anAppThatTranslatesAlways() {
        var config = config
        config.appProfiles = [wechat: AppProfile(translateAlways: true), slack: AppProfile(translateAlways: true)]
        let s = StateProbe(config)
        #expect(s.activated(notes) == .unchanged && !s.isOn)
        // Switched to: on.
        #expect(s.activated(wechat) == .entered(english) && s.isOn)
        // Turned off there by hand: another field of the app leaves it off…
        s.leave()
        #expect(s.activated(wechat) == .unchanged && !s.isOn)
        // …and coming back from another app turns it on again.
        #expect(s.activated(notes) == .unchanged)
        #expect(s.activated(wechat) == .entered(english))
        // Already on: another app that translates always keeps it as it is.
        #expect(s.activated(slack) == .unchanged && s.state.session == english)
        // One that doesn't: off.
        #expect(s.activated(notes) == .left(english) && !s.isOn)
    }

    @Test func aProfileThatDoesntSaySoIsAnyApp() {
        var config = config
        config.appProfiles = [wechat: AppProfile(rewriteStyles: ["口语"], translateAlways: false)]
        let s = StateProbe(config)
        _ = s.activated(notes)
        s.enter()
        #expect(s.activated(wechat) == .left(english))
    }

    @Test func theTargetIsTheLastPickElseTheFirstOutputLanguage() {
        let ja = OutputLanguage("ja")
        // Nothing picked yet: the first output language, whichever it is.
        #expect(TranslateMode.target(last: nil, outputs: [.english, .chinese]) == .english)
        #expect(TranslateMode.target(last: nil, outputs: [.chinese, .english]) == .chinese)
        #expect(TranslateMode.target(last: nil, outputs: [OutputLanguage("zh-Hant")]) == OutputLanguage("zh-Hant"))
        // The last pick, wherever it is among them.
        #expect(TranslateMode.target(last: ja, outputs: [.english, ja, .chinese]) == ja)
        #expect(TranslateMode.target(last: .chinese, outputs: [.english, .chinese]) == .chinese)
        // A pick no longer offered: the first again.
        #expect(TranslateMode.target(last: ja, outputs: [.english, .chinese]) == .english)
        #expect(TranslateMode.target(last: ja, outputs: []) == nil && TranslateMode.target(last: nil, outputs: []) == nil)
        // Turned on: the same.
        let s = StateProbe(config)
        #expect(s.enter() == english)
        s.leave()
        s.last = .chinese
        #expect(s.enter() == TranslateMode.Session(target: .chinese))
        s.leave()
        s.last = ja
        #expect(s.enter() == english)
        // Only Chinese to translate into: on, into Chinese (Chinese typed goes in as typed).
        var only = Config.default
        only.setOrder([OutputLanguage.chinese])
        #expect(StateProbe(only).enter() == TranslateMode.Session(target: .chinese))
    }

    @Test func anAppThatTranslatesAlwaysUsesTheLastPick() {
        var config = config
        config.appProfiles = [wechat: AppProfile(translateAlways: true)]
        let s = StateProbe(config)
        s.last = .chinese
        _ = s.activated(notes)
        #expect(s.activated(wechat) == .entered(TranslateMode.Session(target: .chinese)))
    }

    @Test func anotherTargetPickedWhileOn() {
        let s = StateProbe(config)
        #expect(s.retarget(.chinese) == nil && !s.isOn)  // off: nothing to change
        s.enter()
        let japanese = TranslateMode.Session(target: OutputLanguage("ja"))
        #expect(s.retarget(OutputLanguage("ja")) == japanese && s.state.session == japanese)
        // The state doesn't keep the pick: turned on again, it goes by `last` (the controller keeps that).
        s.leave()
        #expect(s.enter() == english)
    }

    @Test func translateAlwaysIsKeptInTheConfig() throws {
        #expect(AppProfile().isEmpty && !AppProfile(translateAlways: true).isEmpty && AppProfile(translateAlways: false).isEmpty)
        let data = try JSONEncoder().encode(AppProfile(translateAlways: true))
        #expect(String(decoding: data, as: UTF8.self) == #"{"translateAlways":true}"#)
        #expect(try JSONDecoder().decode(AppProfile.self, from: data) == AppProfile(translateAlways: true))
        // The wrong type is left unset, as for the other keys; nothing is written without it.
        #expect(try JSONDecoder().decode(AppProfile.self, from: Data(#"{"translateAlways":"yes","noAI":true}"#.utf8)) == AppProfile(noAI: true))
        #expect(String(decoding: try JSONEncoder().encode(AppProfile(noAI: true)), as: UTF8.self) == #"{"noAI":true}"#)
        var config = Config.default
        config.appProfiles = [wechat: AppProfile(translateAlways: true)]
        let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(again.profile(for: wechat)?.translateAlways == true)
    }

    /// The chip's languages: short Chinese names in the Chinese interface, tags in the English one ("ZH → EN").
    @Test func theChipsNamesAndTags() {
        #expect(TranslateMode.short(OutputLanguage("bn")) == "孟加拉" && TranslateMode.short(OutputLanguage("zh-Hant")) == "繁")
        #expect(TranslateMode.tag(.english) == "EN" && TranslateMode.tag(.chinese) == "ZH" && TranslateMode.tag(OutputLanguage("zh-Hant")) == "ZH-HANT")
        let chip = TranslateMode.Chip(source: .chinese, target: .english)
        #expect(chip.text == "中 → 英" && chip.sourceTag == "ZH" && chip.targetTag == "EN")
        #expect(TranslateMode.Chip(source: .korean, target: OutputLanguage("ja")).sourceTag == "KO")
    }
}

// MARK: - The request

struct TranslateModeRequestTests {
    var english: Config {
        var config = Config.default
        config.setOrder([OutputLanguage.english, .chinese])
        return config
    }

    @Test func aRequestOfItsOwnNextToEveryOther() throws {
        let input = "我今天有点不舒服"
        let request = Prompt.translateModeRequest(for: input, target: .english, tone: .natural, config: english)
        let golden = PromptGolden.requests()
        #expect(!golden.values.contains(request))
        #expect(golden.values.allSatisfy { $0.system.first?.text != request.system.first?.text })
        // The translate prompt's machinery, for one line in the target language, then the tone: no examples.
        let plan = WritingPlan(versions: nil, translations: [.english], styles: [], input: .chinese)
        #expect(request.system.count == 1 && request.system[0].text == Prompt.system(plan) + "\n- " + AppTone.natural.rule)
        #expect(request.system[0].text.contains("EN: <the sentence in English, as a native speaker would most naturally say it>"))
        #expect(request.messages.count == 1 && request.messages[0].role == "user" && request.messages[0].content.first?.text == input)
        // @translate's own request is still what it was, and so is every request the fixture holds, byte for byte.
        #expect(Prompt.request(for: input, mode: .translate, config: english) == golden["en-zh-translate"])
        let url = try #require(Bundle.module.url(forResource: "prompts-release-0.6.3", withExtension: "json", subdirectory: "Fixtures"))
        #expect(try PromptGolden.json(withoutLiveDataRule: true) == Data(contentsOf: url))
    }

    @Test func throughTheConverterWithHiddenValues() async throws {
        var settings = english
        settings.provider = .apple
        settings.redaction = RedactionSettings(enabled: true)
        let config = settings
        let model = StubAppleModel(answer: ["EN: Email [EMAIL_1] tomorrow"])
        let converter = Converter(loadConfig: { config }, appleModel: model)
        var updates: [ConversionUpdate] = []
        for try await update in converter.translateMode("明天给 bob@example.com 发邮件", target: .english, app: "com.tencent.xinWeChat") {
            updates.append(update)
        }
        #expect(updates.count == 1 && updates.first?.isFinal == true && updates.first?.hidden == 1)
        #expect(updates.first?.result.translations.first?.line.text == "Email bob@example.com tomorrow")
        let sent = try #require(model.requests.first)
        #expect(!sent.prompt.contains("bob@example.com") && sent.prompt.contains("[EMAIL_1]") && sent.examples.isEmpty)
        // WeChat: casual.
        #expect(sent.instructions.contains(AppTone.casual.rule) && !sent.instructions.contains(AppTone.natural.rule))
        // Asked again: from the cache, its own (not @translate's).
        var again: ConversionUpdate?
        for try await update in converter.translateMode("明天给 bob@example.com 发邮件", target: .english, app: "com.tencent.xinWeChat") {
            again = update
        }
        #expect(again?.fromCache == true && model.requests.count == 1)
        for try await _ in converter.convert("明天给 bob@example.com 发邮件", mode: .translate) {}
        #expect(model.requests.count == 2 && !(model.requests.last?.instructions.contains("Tone of the translation") ?? true))
    }

    @Test func nothingIsSentFromAnAppWithNoAI() async {
        var settings = english
        settings.provider = .apple
        settings.appProfiles = ["com.example.secret": AppProfile(noAI: true)]
        let config = settings
        let model = StubAppleModel(answer: ["EN: Hi"])
        let converter = Converter(loadConfig: { config }, appleModel: model)
        await #expect(throws: AppProfile.Refusal.noAI) {
            for try await _ in converter.translateMode("你好", target: .english, app: "com.example.secret") {}
        }
        #expect(model.requests.isEmpty)
    }
}

extension ShiftHoldTests {
    /// With the side bits the Mac's shell passes for every modifier (and Windows' will): still Shift on its own.
    @Test func sideBitsAreNoOtherModifier() {
        let h = HoldProbe()
        #expect(h.flags(VirtualKey.leftShift, [.shift, .leftShift]))
        let k = HoldProbe()
        #expect(!k.flags(VirtualKey.leftShift, [.shift, .leftShift, .command, .leftCommand]))
    }
}

// MARK: - Every modifier change twice (Chromium and Electron apps)

/// What Slack, VS Code or Chrome hand the input method for Shift, as the Electron harness recorded it
/// (Sources/AllInOneIME/ElectronSelfTest.swift): every modifier change twice, the second 5–20 ms after the first and the
/// same (Chromium sends a key event the page didn't handle through the app again, and AppKit hands a modifier change to
/// the input method there). With the side bits the Mac's shell passes.
extension HoldProbe {
    /// A modifier change as such an app hands it over: once, then again a moment later. Whether each armed a press.
    @discardableResult
    func twice(_ keyCode: UInt16, _ modifiers: KeyModifiers) -> (first: Bool, again: Bool) {
        let first = flags(keyCode, modifiers)
        wait(0.015)
        return (first, flags(keyCode, modifiers))
    }
    func downTwice(_ keyCode: UInt16 = VirtualKey.leftShift) -> (first: Bool, again: Bool) {
        twice(keyCode, keyCode == VirtualKey.rightShift ? [.shift, .rightShift] : [.shift, .leftShift])
    }
    func upTwice(_ keyCode: UInt16 = VirtualKey.leftShift) -> (first: Bool, again: Bool) { twice(keyCode, []) }
}

extension ShiftHoldTests {
    /// Held: the second Shift down, the same as the first, changes nothing: the hint at 0.5 s and the toggle at 1.0 s,
    /// once; the release twice ends it, and nothing comes later.
    @Test func aLongPressInAnElectronApp() {
        let h = HoldProbe()
        #expect(h.downTwice() == (true, false))
        #expect(h.hold.held != nil)
        h.wait(0.485)  // 0.5 s
        #expect(h.poll() == .hint)
        h.wait(0.5)  // 1.0 s
        #expect(h.poll() == .toggle)
        h.wait(0.28)
        #expect(h.poll() == nil)
        #expect(h.upTwice() == (false, false))
        #expect(h.hold.held == nil)
        h.wait(1)
        #expect(h.poll() == nil)
        // And again, the same: the next long press toggles too.
        #expect(h.downTwice() == (true, false))
        h.wait(1.0)
        #expect(h.poll() == .toggle)
    }

    /// A tap, each change twice: no long press; through the composer too, the input language switched once.
    @Test func aTapInAnElectronApp() {
        let h = HoldProbe()
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        var switches = 0
        func both(_ keyCode: UInt16, _ modifiers: KeyModifiers, at timestamp: TimeInterval) {
            _ = h.flags(keyCode, modifiers)
            switches += c.handleFlagsChanged(keyCode: keyCode, modifiers: modifiers, timestamp: timestamp)
                .filter { if case .inputLanguageChanged = $0 { return true } else { return false } }.count
        }
        let pressed = h.clock.now
        both(VirtualKey.leftShift, [.shift, .leftShift], at: pressed)
        h.wait(0.015)
        both(VirtualKey.leftShift, [.shift, .leftShift], at: pressed)  // the same event again
        h.wait(0.1)
        let released = h.clock.now
        both(VirtualKey.leftShift, [], at: released)
        h.wait(0.015)
        both(VirtualKey.leftShift, [], at: released)
        h.wait(1)
        #expect(h.poll() == nil && h.hold.held == nil)
        #expect(switches == 1 && c.inputLanguage == .english)
    }

    /// Shift with a letter (a capital), the Shift down handed over again before or after the letter: no toggle.
    @Test func shiftWithALetterInAnElectronApp() {
        let h = HoldProbe()
        #expect(h.downTwice() == (true, false))
        h.wait(0.2)
        h.key()
        h.wait(1)
        #expect(h.poll() == nil)
        _ = h.upTwice()
        // The letter typed before Shift's down came the second time.
        #expect(h.down())
        h.key()
        #expect(!h.down())
        h.wait(1.2)
        #expect(h.poll() == nil && h.hold.held == nil)
        _ = h.upTwice()
    }

    /// A Shift-click (the pointer used, or moved to where the click goes) while Shift is held, each change twice: no
    /// toggle.
    @Test func aShiftClickInAnElectronApp() {
        let h = HoldProbe()
        _ = h.downTwice()
        h.wait(1.0)
        #expect(h.poll(pointerUsed: true) == nil)
        #expect(h.poll() == nil)
        _ = h.upTwice()
        _ = h.downTwice()
        h.move(60, 10)
        h.wait(0.5)
        #expect(h.poll() == nil && h.hold.held == nil)
        h.wait(0.5)
        #expect(h.poll() == nil)
        _ = h.upTwice()
    }

    /// ⌘ with Shift, each change twice, in either order, and ⌘ let go while Shift is still held: a shortcut, no toggle.
    @Test func shortcutsInAnElectronApp() {
        let leftCommand: UInt16 = 0x37
        let h = HoldProbe()
        _ = h.downTwice()
        #expect(h.twice(leftCommand, [.shift, .leftShift, .command, .leftCommand]) == (false, false))
        #expect(h.twice(leftCommand, [.shift, .leftShift]) == (false, false))  // ⌘ up, Shift still held
        h.wait(1.2)
        #expect(h.poll() == nil && h.hold.held == nil)
        _ = h.upTwice()
        // ⌘ first, then Shift.
        #expect(h.twice(leftCommand, [.command, .leftCommand]) == (false, false))
        #expect(h.twice(VirtualKey.leftShift, [.shift, .leftShift, .command, .leftCommand]) == (false, false))
        h.wait(1.2)
        #expect(h.poll() == nil)
        #expect(h.twice(leftCommand, [.shift, .leftShift]) == (false, false))
        h.wait(1.2)
        #expect(h.poll() == nil)
    }

    /// Sticky Keys on: a Shift it latches, handed over twice, is no press either.
    @Test func stickyKeysInAnElectronApp() {
        let h = HoldProbe()
        h.clock.stickyKeys = true
        #expect(h.downTwice() == (false, false))
        h.wait(1.5)
        #expect(h.poll() == nil)
        _ = h.upTwice()
    }

    /// The other Shift pressed and let go while one is held, each change twice: no press; both let go, the next one
    /// counts again.
    @Test func theOtherShiftInAnElectronApp() {
        let h = HoldProbe()
        _ = h.downTwice()
        #expect(h.twice(VirtualKey.rightShift, [.shift, .leftShift, .rightShift]) == (false, false))
        #expect(h.twice(VirtualKey.rightShift, [.shift, .leftShift]) == (false, false))
        h.wait(1.2)
        #expect(h.poll() == nil && h.hold.held == nil)
        _ = h.upTwice()
        #expect(h.downTwice(VirtualKey.rightShift) == (true, false))
        h.wait(1.0)
        #expect(h.poll() == .toggle)
    }

    /// The page slow to let a tap go by: Shift's down and up come again after the release, with their times. On its
    /// own, the press they seem to start ends with the second release; nothing toggles. As the shell hands them on (the
    /// copies dropped first, `ModifierFeed`), the composer too: the input language switched once, not back again.
    @Test func aTapHandedOverAgainLate() {
        let h = HoldProbe()
        #expect(h.flags(VirtualKey.leftShift, [.shift, .leftShift]))
        h.wait(0.1)
        #expect(!h.up())
        h.wait(0.2)
        _ = h.flags(VirtualKey.leftShift, [.shift, .leftShift])
        h.wait(0.01)
        #expect(!h.up())
        h.wait(1.2)
        #expect(h.poll() == nil && h.hold.held == nil)

        let f = ModifierFeed()
        let (pressed, released) = (f.now, f.now + 0.1)
        #expect(f.change(VirtualKey.leftShift, [.shift, .leftShift], at: pressed) == [])
        #expect(f.hold.hold.held != nil)
        f.wait(0.1)
        #expect(f.change(VirtualKey.leftShift, [], at: released)?.contains(.inputLanguageChanged(.english)) == true)
        f.wait(0.2)
        #expect(f.change(VirtualKey.leftShift, [.shift, .leftShift], at: pressed) == nil)
        f.wait(0.01)
        #expect(f.change(VirtualKey.leftShift, [], at: released) == nil)
        f.wait(1.2)
        #expect(f.hold.poll() == nil && f.hold.hold.held == nil)
        #expect(f.switches == 1 && f.composer.inputLanguage == .english)
    }

    /// Modifier changes gone unseen (another field, another app, secure input: `resync`): the next change counts, even
    /// one that looks like the last one seen.
    @Test func aChangeAfterAResyncCountsEvenTheSameAgain() {
        let h = HoldProbe()
        #expect(h.flags(VirtualKey.leftShift, [.shift, .leftShift]))
        h.hold.resync(shiftDown: false)  // let go where it went unseen
        #expect(h.flags(VirtualKey.leftShift, [.shift, .leftShift]))
        h.wait(1.0)
        #expect(h.poll() == .toggle)
    }
}

import Foundation
import Testing
@testable import AllInOneIMECore

/// A clock the tests move by hand (`TranslateMode.ShiftHold`'s).
final class HandClock: @unchecked Sendable {
    var now: TimeInterval = 100
}

// MARK: - The long press of Shift

/// `TranslateMode.ShiftHold` on a clock moved by hand, through a class (its mutating calls inside `#expect`).
final class HoldProbe {
    let clock = HandClock()
    lazy var hold = TranslateMode.ShiftHold(now: { [clock] in clock.now })

    /// A modifier change; true: armed.
    func flags(_ keyCode: UInt16 = VirtualKey.leftShift, _ modifiers: KeyModifiers) -> Bool {
        hold.flagsChanged(keyCode: keyCode, modifiers: modifiers)
    }
    func down(_ keyCode: UInt16 = VirtualKey.leftShift) -> Bool { flags(keyCode, .shift) }
    func up(_ keyCode: UInt16 = VirtualKey.leftShift) -> Bool { flags(keyCode, []) }
    func key() { hold.keyDown() }
    func wait(_ seconds: TimeInterval) { clock.now += seconds }
    func poll(pointerUsed: Bool = false) -> TranslateMode.ShiftHold.Due? { hold.poll(pointerUsed: pointerUsed) }
}

struct ShiftHoldTests {
    @Test func aLongPressHintsAtAboutHalfwayThenTogglesOnce() {
        let h = HoldProbe()
        #expect(h.down())
        h.wait(0.2)
        #expect(h.poll() == nil)
        h.wait(0.2)  // 0.4 s
        #expect(h.poll() == .hint)
        #expect(h.poll() == nil)  // once
        h.wait(0.3)  // 0.7 s
        #expect(h.poll() == nil)
        h.wait(0.1)  // 0.8 s
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
        h.wait(1.2)
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
        h.wait(0.5)
        #expect(h.poll() == .hint)
        h.wait(0.2)  // 0.7 s: let go
        #expect(!h.up())
        h.wait(0.2)
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
        h.wait(0.45)
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
        h.wait(0.8)
        #expect(h.poll() == .toggle)
    }

    @Test func aShiftClickIsNoLongPress() {
        let h = HoldProbe()
        #expect(h.down())
        h.wait(0.9)
        #expect(h.poll(pointerUsed: true) == nil)
        #expect(h.poll() == nil)
    }

    @Test func theTimesOfTheSpec() {
        #expect(TranslateMode.ShiftHold.hintAfter == 0.4 && TranslateMode.ShiftHold.toggleAfter == 0.8)
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
        h.wait(0.8)
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

    /// A composer with translation mode on into English (pinyin first), ⏎ as the action key.
    func composer(_ session: TranslateMode.Session? = TranslateMode.Session(target: .english)) -> (Composer, FakeEngine) {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        c.commands = Command.builtins + [.translationMode, .exitMode]
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

    @Test func pinyinCollectsIntoADraftAfterTheIndicator() {
        let (c, _) = composer()
        type("nihao", c)
        #expect(c.markedText == "中→英 › nihao" && c.wantsPanel)  // the candidates
        let space = c.handleKeyDown(spaceKey)
        #expect(commits(space).isEmpty && c.draft == "你好" && c.phase == .drafting)
        #expect(c.markedText == "中→英 › 你好" && c.inModeComposition && !c.wantsPanel)
        type("wo", c)
        _ = c.handleKeyDown(spaceKey)
        #expect(c.draft == "你好我" && c.markedText == "中→英 › 你好我")
    }

    @Test func returnTranslatesAndInsertsWithNoCandidates() {
        let (c, _) = composer()
        draftNihao(c)
        let enter = c.handleKeyDown(enterKey)
        let sent = request(enter.effects)
        #expect(enter.handled && sent?.input == "你好" && sent?.session == english && commits(enter).isEmpty)
        #expect(c.markedText == "中→英 › 你好 · 翻译中…" && c.choices.isEmpty && !c.wantsPanel)
        // Partial results don't go in.
        #expect(commits(c.receive(hello, isFinal: false, id: sent!.id)).isEmpty && c.markedText == "中→英 › 你好 · 翻译中…")
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
        #expect(c.phase == .drafting && c.draft == "你好" && c.markedText == "中→英 › 你好")
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
        #expect(typed.effects.contains(.cancelConversion) && c.phase == .drafting && c.markedText == "中→英 › 你好w")
        // ⇧⏎ while it's translated: as typed.
        type("o", c)
        _ = c.handleKeyDown(spaceKey)
        _ = c.handleKeyDown(enterKey)
        let asTyped = c.handleKeyDown(shiftEnter)
        #expect(commits(asTyped) == ["你好我"] && asTyped.effects.contains(.cancelConversion))
    }

    @Test func aFailureKeepsTheDraftAndReturnRetries() {
        let (c, _) = composer()
        draftNihao(c)
        let first = request(c.handleKeyDown(enterKey).effects)!.id
        let failed = c.fail("网络连接失败", id: first)
        #expect(notices(failed) == [TranslateMode.Messages.chinese.failed("网络连接失败")] && commits(failed).isEmpty)
        #expect(notices(failed).first?.contains("网络连接失败") == true && notices(failed).first?.contains("\n") == false)
        #expect(c.phase == .drafting && c.draft == "你好" && c.markedText == "中→英 › 你好")
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
        #expect(c.draft == "hello world" && c.markedText == "英→中 › hello world")
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
        type("@mo", d)
        _ = d.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        #expect(commits(d.setTranslateMode(nil)).isEmpty && d.draft == "@mode ")
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
}

// MARK: - @mode and @exit

struct TranslateModeCommandTests {
    let japanese = OutputLanguage("ja")

    func composer(on: Bool = false) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.commands = Command.builtins + [.translationMode] + (on ? [.exitMode] : [])
        if on { _ = c.setTranslateMode(TranslateMode.Session(target: .english)) }
        return c
    }

    /// `text` typed (a space as the Space key), then ⏎.
    func run(_ text: String, _ c: Composer) -> [Composer.Effect] {
        text.forEach { _ = c.handleKeyDown($0 == " " ? spaceKey : k(String($0))) }
        return c.handleKeyDown(enterKey).effects
    }

    func changes(_ effects: [Composer.Effect]) -> [TranslateMode.Change] {
        effects.compactMap { if case let .translateMode(change) = $0 { return change } else { return nil } }
    }

    @Test func parsing() {
        let enFormal = TranslateMode.Parsed.change(.enter(target: .english, tone: .formal))
        #expect(TranslateMode.parse("en formal") == enFormal)
        #expect(TranslateMode.parse("英文 正式") == enFormal)
        #expect(TranslateMode.parse("formal  EN") == enFormal)
        #expect(TranslateMode.parse("English, formal") == enFormal)
        #expect(TranslateMode.parse("英，正式") == enFormal)
        #expect(TranslateMode.parse("ja") == .change(.enter(target: japanese, tone: nil)))
        #expect(TranslateMode.parse("日语 口语") == .change(.enter(target: japanese, tone: .casual)))
        #expect(TranslateMode.parse("Japanese casual") == .change(.enter(target: japanese, tone: .casual)))
        #expect(TranslateMode.parse("日") == .change(.enter(target: japanese, tone: nil)))
        #expect(TranslateMode.parse("jp") == .change(.enter(target: japanese, tone: nil)))
        #expect(TranslateMode.parse("zh-Hant") == .change(.enter(target: OutputLanguage("zh-Hant"), tone: nil)))
        #expect(TranslateMode.parse("繁体中文") == .change(.enter(target: OutputLanguage("zh-Hant"), tone: nil)))
        #expect(TranslateMode.parse("中文") == .change(.enter(target: .chinese, tone: nil)))
        #expect(TranslateMode.parse("de 委婉") == .change(.enter(target: OutputLanguage("de"), tone: .tactful)))
        #expect(TranslateMode.parse("") == .change(.enter(target: nil, tone: nil)))
        #expect(TranslateMode.parse("casual") == .change(.enter(target: nil, tone: .casual)))
        #expect(TranslateMode.parse("off") == .change(.leave) && TranslateMode.parse("OFF") == .change(.leave))
        #expect(TranslateMode.parse("关闭") == .change(.leave))
        #expect(TranslateMode.parse("en xyz") == .unknown("xyz"))
        #expect(TranslateMode.parse("off en") == .unknown("off"))
    }

    @Test func modeTurnsItOnTypedInLetters() {
        let c = composer()
        _ = c.handleKeyDown(k("@"))
        "mo".forEach { _ = c.handleKeyDown(k(String($0))) }
        _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        #expect(c.draft == "@mode " && c.inputLanguage == .english)  // letters for the language and tone
        let effects = run("en formal", c)
        #expect(changes(effects) == [.enter(target: .english, tone: .formal)] && c.draft.isEmpty && c.phase == .idle)
        #expect(effects.contains(.commandUsed("mode")) && c.inputLanguage == .chinese)
    }

    @Test func modeAloneTakesTheDefaults() {
        let c = composer()
        #expect(changes(run("@mode ", c)) == [.enter(target: nil, tone: nil)])
    }

    @Test func modeOffAndExitLeaveIt() {
        let c = composer(on: true)
        let off = run("@mode off", c)
        #expect(changes(off) == [.leave] && commits(off).isEmpty)
        // "@ex" ⏎ in the command list: at once.
        let d = composer(on: true)
        "@ex".forEach { _ = d.handleKeyDown(k(String($0))) }
        let exit = d.handleKeyDown(enterKey).effects
        #expect(changes(exit) == [.leave] && d.draft.isEmpty)
        // Typed in full.
        let e = composer(on: true)
        #expect(changes(run("@exit ", e)) == [.leave])
    }

    @Test func aWordItCantReadKeepsTheDraft() {
        let c = composer()
        let effects = run("@mode klingon", c)
        #expect(changes(effects).isEmpty && c.draft == "@mode klingon")
        #expect(effects.contains(.notice(TranslateMode.Messages.chinese.unknown("klingon"))))
    }

    @Test func inTheModeACommandIsNoDraftOfIt() {
        let c = composer(on: true)
        "@mode".forEach { _ = c.handleKeyDown(k(String($0))) }
        _ = c.handleKeyDown(spaceKey)
        #expect(c.draft == "@mode " && !c.inModeComposition && c.markedText == "mode › ")
        "ja".forEach { _ = c.handleKeyDown(k(String($0))) }
        let effects = c.handleKeyDown(enterKey).effects
        #expect(changes(effects) == [.enter(target: japanese, tone: nil)]
                && !effects.contains { if case .startTranslateMode = $0 { return true } else { return false } })
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

    @Test func anExplicitToneWins() {
        let wechat = "com.tencent.xinWeChat"
        #expect(TranslateMode.tone(app: wechat, config: config(), explicit: .formal) == .formal)
        #expect(TranslateMode.tone(app: wechat, config: config([wechat: AppProfile(rewriteStyles: ["口语"])]), explicit: .concise) == .concise)
    }

    @Test func theRequestSaysTheTone() {
        let request = Prompt.translateModeRequest(for: "你好", target: .english, tone: .casual, config: .default)
        #expect(request.system[0].text.hasSuffix("- " + TranslateMode.Tone.casual.rule))
        #expect(TranslateMode.Tone.allCases.map(\.rule).count == Set(TranslateMode.Tone.allCases.map(\.rule)).count)
    }
}

// MARK: - App switches and translateAlways

/// `TranslateMode.State` through a class (its mutating calls inside `#expect`).
final class StateProbe {
    var state = TranslateMode.State()
    let config: Config
    init(_ config: Config) { self.config = config }

    func activated(_ app: String?) -> TranslateMode.State.Transition { state.activated(app: app, source: .chinese, config: config) }
    @discardableResult
    func enter(_ target: OutputLanguage? = nil, tone: TranslateMode.Tone? = nil) -> TranslateMode.Session? {
        state.enter(target: target, tone: tone, source: .chinese, config: config)
    }
    func leave() { state.leave() }
    var isOn: Bool { state.isOn }
}

struct TranslateModeStateTests {
    let wechat = "com.tencent.xinWeChat", notes = "com.apple.Notes", mail = "com.apple.mail", slack = "com.tinyspeck.slackmacgap"
    let english = TranslateMode.Session(target: .english)

    var config: Config {
        var config = Config.default
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
        // On with a language and tone of its own: another app that translates always keeps it as it is.
        let japanese = s.enter(OutputLanguage("ja"), tone: .formal)
        #expect(s.activated(slack) == .unchanged && s.state.session == japanese && japanese != nil)
        // One that doesn't: off.
        #expect(s.activated(notes) == .left(japanese!) && !s.isOn)
    }

    @Test func aProfileThatDoesntSaySoIsAnyApp() {
        var config = config
        config.appProfiles = [wechat: AppProfile(rewriteStyles: ["口语"], translateAlways: false)]
        let s = StateProbe(config)
        _ = s.activated(notes)
        s.enter()
        #expect(s.activated(wechat) == .left(english))
    }

    @Test func theTargetIsTheFirstOutputLanguageThatIsntTheOneTyped() {
        #expect(TranslateMode.target(source: .chinese, outputs: [.english, .chinese]) == .english)
        #expect(TranslateMode.target(source: .chinese, outputs: [.chinese, .english]) == .english)
        #expect(TranslateMode.target(source: .english, outputs: [.english, .chinese]) == .chinese)
        #expect(TranslateMode.target(source: .chinese, outputs: [OutputLanguage("zh-Hant")]) == OutputLanguage("zh-Hant"))
        #expect(TranslateMode.target(source: .chinese, outputs: [.chinese]) == nil)
        var only = Config.default
        only.setOrder([OutputLanguage.chinese])
        let s = StateProbe(only)
        #expect(s.enter() == nil && !s.isOn)
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

    @Test func theIndicator() {
        #expect(TranslateMode.indicator(from: .chinese, to: .english) == "中→英")
        #expect(TranslateMode.indicator(from: .chinese, to: OutputLanguage("ja")) == "中→日")
        #expect(TranslateMode.indicator(from: .english, to: .chinese) == "英→中")
        #expect(TranslateMode.indicator(from: .chinese, to: OutputLanguage("zh-Hant")) == "中→繁")
        #expect(TranslateMode.indicator(from: .english, to: .english) == "→英" && TranslateMode.indicator(from: nil, to: .english) == "→英")
        #expect(TranslateMode.short(OutputLanguage("bn")) == "孟加拉")
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
        #expect(request.system.count == 1 && request.system[0].text == Prompt.system(plan) + "\n- " + TranslateMode.Tone.natural.rule)
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
        #expect(sent.instructions.contains(TranslateMode.Tone.casual.rule) && !sent.instructions.contains(TranslateMode.Tone.natural.rule))
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

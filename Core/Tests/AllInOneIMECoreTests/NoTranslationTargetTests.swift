import Foundation
import Testing
@testable import AllInOneIMECore

/// Nothing to translate into but the language typed (a new user whose Mac has English alone): `@translate`'s failure is
/// put right in the settings, and ⏎ on its notice takes the user there; Translate as You Type doesn't turn on.
struct NoTranslationTargetTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    let message = "No language to translate into yet"

    /// "@translate good morning" run with the action key `key`, in English (on `selection`, "@translate politely": an
    /// instruction about it): its request (id 1) failed as the controller fails it with nothing to translate into.
    func failedTranslate(key: ActionKey, selection: Composer.Selection? = nil) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: key)
        c.setInputMode(.english)
        c.readSelection = { selection }
        _ = c.handleKeyDown(at)
        for ch in "t" { _ = c.handleKeyDown(k(String(ch))) }
        _ = c.handleKeyDown(tab)
        let text = selection == nil ? "good morning" : "politely"
        for ch in text { _ = c.handleKeyDown(k(String(ch))) }
        #expect(c.draft == "@translate " + text)
        _ = c.handleKeyDown(enterKey)
        #expect(c.phase == .translating(id: 1))
        #expect(c.fail(message, id: 1, fixedIn: .translationLanguages) == [.showPanel])
        return c
    }

    @Test func returnOnTheNoticeOpensTheSettingsThereWithTheSentenceAsTyped() {
        for key in [ActionKey.enter, .optionTap, .optionSpace, .space] {
            let c = failedTranslate(key: key)
            #expect(c.phase == .failed(message) && c.failureFixedIn == .translationLanguages, "\(key)")
            // Not another try (it would fail the same way): the sentence in as typed, never the command, and the settings.
            let r = c.handleKeyDown(enterKey)
            #expect(r.handled && commits(r) == ["good morning"] && r.effects.contains(.openSettingsAt(.translationLanguages)), "\(key): \(r.effects)")
            #expect(!r.effects.contains { if case .startConversion = $0 { return true } else { return false } }, "\(key)")
            #expect(c.phase == .idle && c.draft.isEmpty && c.failureFixedIn == nil, "\(key)")
        }
    }

    @Test func spaceAndTheActionKeyOpenThemToo() {
        let c = failedTranslate(key: .enter)
        let r = c.handleKeyDown(spaceKey)
        #expect(commits(r) == ["good morning"] && r.effects.contains(.openSettingsAt(.translationLanguages)), "\(r.effects)")
        let o = failedTranslate(key: .optionSpace)
        let s = o.handleKeyDown(optionSpace)
        #expect(commits(s) == ["good morning"] && s.effects.contains(.openSettingsAt(.translationLanguages)), "\(s.effects)")
    }

    @Test func escAndZeroStillDoWhatTheyDoOnAnyFailure() {
        let c = failedTranslate(key: .enter)
        _ = c.handleKeyDown(escKey)
        #expect(c.draft == "@translate good morning" && !c.isLevelTwo && c.failureFixedIn == nil)
        let z = failedTranslate(key: .enter)
        let r = z.handleKeyDown(k("0"))
        #expect(commits(r) == ["good morning"] && !r.effects.contains(.openSettingsAt(.translationLanguages)))
    }

    /// On a selection, the instruction typed after the command ("politely") never takes its place: ⏎ or Space opens the
    /// settings, nothing goes in, and the selection stays as it was.
    @Test func onASelectionItStaysAsItWas() {
        let selection = Composer.Selection(text: "good morning", range: 0..<12)
        for (name, key) in [("⏎", enterKey), ("Space", spaceKey)] {
            let c = failedTranslate(key: .enter, selection: selection)
            #expect(c.sentText == "politely")
            let r = c.handleKeyDown(key)
            #expect(r.effects.contains(.openSettingsAt(.translationLanguages)), "\(name): \(r.effects)")
            #expect(commits(r).allSatisfy(\.isEmpty) && !r.effects.contains { if case .replaceSelection = $0 { return true } else { return false } },
                    "\(name): \(r.effects)")
        }
    }

    @Test func anyOtherFailureStillTriesAgain() {
        let c = failedTranslate(key: .enter)
        _ = c.handleKeyDown(escKey)
        _ = c.handleKeyDown(enterKey)  // id 2
        #expect(c.fail("Timed out", id: 2) == [.showPanel])
        #expect(c.failureFixedIn == nil)
        #expect(c.handleKeyDown(enterKey).effects.first == .startConversion(input: "good morning", id: 3))
        // …and so does a later failure with the same words but nothing to put right.
        _ = c.handleKeyDown(escKey)
        _ = c.handleKeyDown(enterKey)  // id 4
        _ = c.fail(message, id: 4)
        #expect(c.failureFixedIn == nil)
        #expect(c.handleKeyDown(enterKey).effects.first == .startConversion(input: "good morning", id: 5))
    }

    @Test func aConfigWithOnlyTheLanguagesTypedHasNothingToTranslateInto() {
        #expect(!Config.default.hasLanguageToTranslateInto)  // English alone, as a new user whose Mac has no other language
        var config = Config.default
        config.setOrder([OutputLanguage.english, OutputLanguage("fr")])
        #expect(config.hasLanguageToTranslateInto)
        config.setOrder([Language.chinese, .english])
        config.setOrder([OutputLanguage.english])
        #expect(config.hasLanguageToTranslateInto)  // Chinese typed goes into English
        config.setOrder([Language.chinese])
        config.setOrder([OutputLanguage.chinese])
        #expect(!config.hasLanguageToTranslateInto)
        config.setOrder([OutputLanguage("zh-Hant")])
        #expect(config.hasLanguageToTranslateInto)  // pinyin comes out simplified: traditional is another language
        #expect(Config.fresh(preferring: ["en-US"]).hasLanguageToTranslateInto == false)
        #expect(Config.fresh(preferring: ["en-US", "ja-JP"]).hasLanguageToTranslateInto)
    }

    @Test func translateAsYouTypeDoesntTurnOnWithNothingToTranslateInto() {
        var state = TranslateMode.State()
        #expect(state.enter(last: nil, config: Config.default) == nil && !state.isOn)
        #expect(state.enter(last: .english, config: Config.default) == nil && !state.isOn)
        // Nor in an app that translates always.
        var always = Config.default
        always.appProfiles = ["com.tinyspeck.slackmacgap": AppProfile(translateAlways: true)]
        _ = state.activated(app: "com.apple.TextEdit", last: nil, config: always)
        #expect(state.activated(app: "com.tinyspeck.slackmacgap", last: nil, config: always) == .unchanged && !state.isOn)
        // Another language added: on, into that one (`withALanguageAddedItTranslatesIntoThatOne`).
        var added = Config.default
        added.setOrder([OutputLanguage.english, OutputLanguage("fr")])
        #expect(state.enter(last: nil, config: added) == TranslateMode.Session(target: OutputLanguage("fr")))
    }

    /// French added after English as the notice says (English alone typed): Translate as You Type comes on into French
    /// at once, English typed collecting into a draft that ⏎ translates, not "on: English" with everything going in as
    /// typed until French is picked on the chip. In an app that translates always too.
    @Test func withALanguageAddedItTranslatesIntoThatOne() {
        let french = OutputLanguage("fr")
        var added = Config.default
        added.setOrder([OutputLanguage.english, french])
        var state = TranslateMode.State()
        let session = state.enter(last: nil, config: added)
        #expect(session == TranslateMode.Session(target: french))
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        _ = c.setTranslateMode(session)
        for ch in "good morning" { _ = c.handleKeyDown(k(String(ch))) }
        #expect(c.draft == "good morning" && c.translateModeChip()?.text == "英 → 法")
        let r = c.handleKeyDown(enterKey)
        #expect(r.effects.contains { if case let .startTranslateMode(input, session, _) = $0 { return input == "good morning" && session.target == french } else { return false } },
                "\(r.effects)")
        var always = added
        always.appProfiles = ["com.tinyspeck.slackmacgap": AppProfile(translateAlways: true)]
        var elsewhere = TranslateMode.State()
        _ = elsewhere.activated(app: "com.apple.TextEdit", last: nil, config: always)
        #expect(elsewhere.activated(app: "com.tinyspeck.slackmacgap", last: nil, config: always) == .entered(TranslateMode.Session(target: french)))
    }

    /// Only the language typed is passed over, and only with none picked: English picked on the chip is still English, and
    /// with Chinese typed too it's the first output language as before (Chinese typed goes into English).
    @Test func aPickAndAnotherLanguageTypedStillHaveTheirSay() {
        var added = Config.default
        added.setOrder([OutputLanguage.english, OutputLanguage("fr")])
        var state = TranslateMode.State()
        #expect(state.enter(last: .english, config: added)?.target == .english)
        state.leave()
        #expect(state.enter(last: OutputLanguage("ja"), config: added)?.target == OutputLanguage("fr"))  // no longer offered
        state.leave()
        var both = added
        both.setOrder([Language.chinese, .english])
        #expect(state.enter(last: nil, config: both)?.target == .english)
    }
}

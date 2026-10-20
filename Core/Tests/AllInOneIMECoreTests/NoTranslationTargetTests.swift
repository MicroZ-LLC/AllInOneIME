import Foundation
import Testing
@testable import AllInOneIMECore

/// Nothing to translate into but the language typed (a new user whose Mac has English alone): `@translate`'s failure is
/// put right in the settings, and ⏎ on its notice takes the user there.
struct NoTranslationTargetTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    let message = "No language to translate into yet"

    /// "@translate good morning" run with the action key `key`, in English: its request (id 1) failed as the controller
    /// fails it with nothing to translate into.
    func failedTranslate(key: ActionKey, selection: Composer.Selection? = nil) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: key)
        c.setInputMode(.english)
        c.readSelection = { selection }
        _ = c.handleKeyDown(at)
        for ch in "t" { _ = c.handleKeyDown(k(String(ch))) }
        _ = c.handleKeyDown(tab)
        for ch in selection == nil ? "good morning" : "" { _ = c.handleKeyDown(k(String(ch))) }
        #expect(c.draft == (selection == nil ? "@translate good morning" : "@translate "))
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

    @Test func onASelectionItStaysAsItWas() {
        let selection = Composer.Selection(text: "good morning", range: 0..<12)
        let c = failedTranslate(key: .enter, selection: selection)
        let r = c.handleKeyDown(enterKey)
        #expect(r.effects.contains(.openSettingsAt(.translationLanguages)))
        #expect(commits(r).allSatisfy(\.isEmpty) && !r.effects.contains { if case .replaceSelection = $0 { return true } else { return false } },
                "\(r.effects)")
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
}

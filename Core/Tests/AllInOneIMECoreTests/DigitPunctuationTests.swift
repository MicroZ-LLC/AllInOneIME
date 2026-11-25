import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

struct DigitPunctuationTests {
    @Test(arguments: [".", ",", ":"])
    func asciiDigitKeepsFollowingPunctuationASCII(_ mark: String) {
        let composer = Composer(engine: FakeEngine())
        composer.characterBeforeCaret = { "3" }

        let response = composer.handleKeyDown(k(mark))

        #expect(response.effects.contains(.commit(mark)), "\(mark): \(response.effects)")
    }

    private func host(terminal: Bool = false) -> FakeHost {
        let engine = FakeEngine()
        var services = SessionServices(loadSettings: { .default })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.terminal = terminal
        host.appTypesKeys = true
        host.readsWhatIsWanted = true
        host.focus()
        host.composer.setInputMode(.chinese)
        return host
    }

    @Test func readableFieldTakesPriorityOverMemory() {
        let host = host()
        host.document = "8"
        host.press(k(","))
        #expect(host.document == "8,")

        host.document = "好3"
        host.press(k(":"))
        #expect(host.document == "好3:")

        host.document = "好"
        host.press(k(","))
        #expect(host.document == "好，")
    }

    @Test func unreadableFieldUsesLastPassedThroughDigit() {
        let host = host(terminal: true)
        host.type("3")
        host.press(k("."))
        host.type("14")
        #expect(host.document == "3.14")
    }

    @Test func anUnreliableCaretClearsFallbackMemory() {
        for invalidation in ["click", "arrow", "paste", "focus", "selection"] {
            let host = host(terminal: true)
            host.type("3")
            switch invalidation {
            case "click": host.send(.commit)
            case "arrow": host.press(KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}"))
            case "paste": host.press(k("v", mods: .command))
            case "focus":
                host.send(.blur)
                host.focus()
                host.composer.setInputMode(.chinese)
            case "selection": host.selection = 0..<1
            default: break
            }
            host.press(k(","))
            #expect(host.document.hasSuffix("，"), "\(invalidation): \(host.document)")
        }
    }

    @Test func onlyAsciiDigitsAndThreeMarksChange() {
        for before in ["好", "１２３", "3。"] {
            let host = host()
            host.document = before
            host.press(k(","))
            #expect(host.document == before + "，")
        }
        let composer = Composer(engine: FakeEngine())
        composer.characterBeforeCaret = { "3" }
        for mark in ["?", "!", ";"] {
            #expect(!composer.handleKeyDown(k(mark)).effects.contains(.commit(mark)))
        }
        composer.setInputMode(.english)
        #expect(!composer.handleKeyDown(k(",")).effects.contains(.commit(",")))
    }

    @Test func pinyinCandidateDigitDoesNotTriggerPunctuationRule() {
        let engine = FakeEngine()
        let composer = Composer(engine: engine)
        composer.characterBeforeCaret = { "3" }
        _ = composer.handleKeyDown(k("n"))
        #expect(composer.handleKeyDown(k("1")).effects.contains(.commit("n")))
    }

    @Test func committedDigitsAreRememberedWithoutChangingCommandWordTracking() {
        var typed = LastTyped()
        typed.answered(k("2"), passedOn: false, inserted: "391", at: 1)
        #expect(typed.character == nil && typed.fieldCharacter == "1")
        typed.committed("100", at: 2)
        #expect(typed.character == nil && typed.fieldCharacter == "0")
        typed.committed("好", at: 3)
        #expect(typed.fieldCharacter == nil)
    }

    @Test func punctuationContextDoesNotChangeCommandTriggerAfterCommittedText() {
        let host = host()
        host.document = "好"
        host.press(FakeHost.at)
        #expect(host.composer.draft == "@")
    }
}

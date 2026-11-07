import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A suggestion kept for the text as it is now shows on the key that made that text, with no pause, no read of the field
/// and no request, where the text is known for sure: as the last pause read it, with what went in since, no click since
/// (`InputSession.autocompleteKeptAtOnce`). Anything that may have changed the text otherwise leaves it to the pause.
@Suite(.serialized)
struct AutocompleteAtOnceTests {
    final class Pointer: @unchecked Sendable {
        var used = false
    }

    static let backspace = KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}")
    static let left = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")

    /// A field with autocomplete on, the on-device model answering "See you" and what follows it with the rest of
    /// "See you tomorrow at noon.", anything else with " and more.".
    func field(pointer: Pointer = Pointer()) -> (host: FakeHost, model: ContinuingModel, clock: Uptime) {
        var config = Config.default
        config.provider = .apple
        config.uiLanguage = "en"
        config.setOrder([Language.english])
        config.setOrder([OutputLanguage.english, .chinese])
        config.autocomplete = true
        let fixed = config
        let model = ContinuingModel { prompt in
            let before = prompt.components(separatedBy: "</before>")[0].replacingOccurrences(of: "<before>", with: "")
            let sentence = "See you tomorrow at noon."
            return before.hasPrefix("See you") ? String(sentence.dropFirst(before.count)) : " and more."
        }
        let clock = Uptime()
        var services = SessionServices(converter: Converter(loadConfig: { fixed }, appleModel: model), loadSettings: { fixed })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.uptime = { clock.now }
        services.buttonUsedWithin = { _ in pointer.used }
        services.pointerUsedWithin = { _ in pointer.used }
        let host = FakeHost(services: services)
        host.appTypesKeys = true
        host.focus()
        return (host, model, clock)
    }

    func pauseEnds(_ host: FakeHost, _ clock: Uptime) {
        clock.advance(1)
        host.fireTimers { if case .autocomplete = $0 { true } else { false } }
        host.settle(timeout: 5) { host.session.autocomplete.reading == nil && host.session.autocomplete.asked == nil }
    }

    /// ⌫ the app had (one character, as the field took it back too).
    func backspace(_ host: FakeHost) {
        host.press(Self.backspace)
        host.document.removeLast()
    }

    /// Typed past the suggestion and back, then on as it goes: its rest at once, nothing read or asked again.
    @Test func aKeptSuggestionIsUpOnTheKey() async {
        await withInterfaceLanguage("en") {
            let (host, model, clock) = field()
            host.type("See you")
            pauseEnds(host, clock)
            #expect(host.ghost == " tomorrow at noon." && model.requests.count == 1 && host.fieldReads == 1)
            host.type("x")
            #expect(host.ghost == nil)
            backspace(host)
            #expect(host.ghost == nil, "⌫ asks for nothing")
            host.type(" ")
            #expect(host.ghost == "tomorrow at noon.", "at once, on the key")
            #expect(model.requests.count == 1 && host.fieldReads == 1)
            // Typed along from there, as any suggestion up.
            host.type("to")
            #expect(host.ghost == "morrow at noon.")
        }
    }

    /// A click or the wheel since the read: the caret may be elsewhere, so the pause reads the field again.
    @Test func notAfterAClick() async {
        await withInterfaceLanguage("en") {
            let pointer = Pointer()
            let (host, model, clock) = field(pointer: pointer)
            host.type("See you")
            pauseEnds(host, clock)
            host.type("x")
            backspace(host)
            pointer.used = true
            host.type(" ")
            #expect(host.ghost == nil && host.fieldReads == 1)
            pointer.used = false
            pauseEnds(host, clock)
            #expect(host.fieldReads == 2 && host.ghost == "tomorrow at noon." && model.requests.count == 1, "the pause finds it kept")
        }
    }

    /// A key the app had that typed nothing (← may move the caret), or ⌫ of a character of several code points (an app
    /// may take back one of them): the text isn't known any more.
    @Test func notAfterAKeyThatMayHaveChangedMore() async {
        await withInterfaceLanguage("en") {
            let (host, _, clock) = field()
            host.type("See you")
            pauseEnds(host, clock)
            host.type("x")
            host.press(Self.left)
            host.press(KeyEvent(keyCode: 0x7C, characters: "\u{F703}"))  // → back to the end
            backspace(host)
            host.type(" ")
            #expect(host.ghost == nil && host.fieldReads == 1)

            let (other, _, otherClock) = field()
            other.type("See you")
            pauseEnds(other, otherClock)
            other.type("e\u{301}")  // é as e and a combining accent, one character
            backspace(other)
            other.document = "See you"
            other.type(" ")
            #expect(other.ghost == nil && other.fieldReads == 1)
        }
    }

    /// Text that went in some other way than at the caret (a result over the selection, a paste): not known.
    @Test func notAfterTextPutInElsewhere() async {
        await withInterfaceLanguage("en") {
            let (host, _, clock) = field()
            host.type("See you")
            pauseEnds(host, clock)
            host.type("x")
            backspace(host)
            host.session.autocompleteFollow(.replace("later", range: 0..<3))
            host.type(" ")
            #expect(host.ghost == nil && host.fieldReads == 1)
        }
    }
}

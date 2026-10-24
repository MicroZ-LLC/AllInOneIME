import AllInOneIMECore
import Testing
@testable import AllInOneIMERime

extension RimeEngineTests {
    /// A suggestion source's prefix of letters and a dash typed in pinyin with real Rime (rime-ice): the "-" after the
    /// letters ends the composition as typed, case kept, and the digits after it go through to the app, typed. Without
    /// such a source, "-" is Rime's (no page before the first) and a digit picks a candidate, as before.
    @Test func aSuggestionPrefixFinishedInPinyinGoesInAsTypedWithRealRime() throws {
        let dash = KeyEvent(keyCode: 0x1B, characters: "-")
        let one = KeyEvent(keyCode: 0x12, characters: "1")
        for (letters, shifted) in [("cr", false), ("CR", true)] {
            let composer = Composer(engine: try RimeFixture.session())
            defer { composer.engine?.clearComposition() }
            composer.finishesSuggestionPrefix = { $0.lowercased() == "cr-" }
            for letter in letters {
                _ = composer.handleKeyDown(key(letter, modifiers: shifted ? .shift : []))
            }
            #expect(composer.isComposing && composer.engine?.rawInput == letters, "\(String(describing: composer.engine?.rawInput))")
            let ended = composer.handleKeyDown(dash)
            #expect(ended.handled && ended.effects.contains(.commit(letters + "-")) && !composer.isComposing, "\(ended)")
            let digit = composer.handleKeyDown(one)
            #expect(!digit.handled && digit.effects.isEmpty, "the digit is typed: \(digit)")
        }

        let plain = Composer(engine: try RimeFixture.session())
        defer { plain.engine?.clearComposition() }
        for letter in "cr" { _ = plain.handleKeyDown(key(letter)) }
        #expect(plain.handleKeyDown(dash).handled && plain.isComposing, "no source: Rime's \"-\"")
        let picked = plain.handleKeyDown(one)
        #expect(picked.effects.contains { if case let .commit(text) = $0 { text.containsHan } else { false } }, "\(picked)")
    }
}

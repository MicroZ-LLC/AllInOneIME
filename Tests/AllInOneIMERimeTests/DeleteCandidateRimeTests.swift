@testable import AllInOneIMECore
import Foundation
import Testing
@testable import AllInOneIMERime

/// A candidate deleted with the real librime and rime-ice (librime's `delete_candidate`, rime-ice's Control+Delete): a row
/// right-clicked (`Composer.deleteCandidate(index:)`) or ⌃⌦ on the highlighted one. A phrase librime learned, one made of
/// characters picked one by one too, is forgotten; a dictionary word learning moved up goes back to where the dictionary
/// puts it. Nothing is committed, the letters stay. English words put in among librime's candidates
/// (`EnglishWordsEngine`) aren't librime's to delete. In the serialized suite: librime's user dictionary is the
/// process's, so each test types letters no other test types, and none counts on another having run.
extension RimeEngineTests {

    /// 鸡 then 虎 for "jihu": librime learns 鸡虎 and offers it first; a right-click on another row leaves it, one on its
    /// row forgets it.
    @Test func aPhrasePickedCharacterByCharacterIsForgotten() throws {
        let session = try RimeFixture.session()
        let composer = Composer(engine: session, actionKey: .enter)
        let before = candidatesOnPages("jihu", composer)
        #expect(before.first != "鸡虎", "\(before.prefix(8))")
        try learn(["鸡", "虎"], for: "jihu", composer)
        typeIn("jihu", composer)
        #expect(texts(composer).first == "鸡虎", "learned: \(texts(composer))")
        // Another row (librime's highlight on the first): that one, not the phrase.
        #expect(composer.engineState.highlighted == 0)
        #expect(committed(composer.deleteCandidate(index: 1)).isEmpty)
        #expect(texts(composer).first == "鸡虎", "\(texts(composer))")
        let effects = composer.deleteCandidate(index: 0)
        #expect(committed(effects).isEmpty, "nothing committed: \(effects)")
        #expect(composer.engineState.isComposing && session.rawInput == "jihu", "the letters stay: \(session.rawInput)")
        // The page laid out again, without it.
        #expect(!texts(composer).contains("鸡虎"), "\(texts(composer))")
        #expect(effects.contains(.showPanel), "\(effects)")
        escape(composer)
        let after = candidatesOnPages("jihu", composer)
        #expect(!after.contains("鸡虎"), "forgotten: \(after.prefix(12))")
        #expect(after.first == before.first, "\(after.prefix(4)) \(before.prefix(4))")
    }

    /// ⌃⌦ through the composer's keys: the highlighted candidate (↓ onto another row deletes that one), consumed, nothing
    /// committed; with nothing composed the app's.
    @Test func controlForwardDeleteForgetsTheHighlightedPhrase() throws {
        let session = try RimeFixture.session()
        let composer = Composer(engine: session, actionKey: .enter)
        #expect(!composer.handleKeyDown(controlForwardDelete).handled, "nothing composed: the app's")
        try learn(["鸭", "虎"], for: "yahu", composer)
        typeIn("yahu", composer)
        #expect(texts(composer).first == "鸭虎", "learned: \(texts(composer))")
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.down, characters: "\u{F701}"))
        #expect(composer.engineState.highlighted == 1)
        let other = composer.handleKeyDown(controlForwardDelete)
        #expect(other.handled && committed(other).isEmpty && texts(composer).first == "鸭虎", "\(texts(composer))")
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.up, characters: "\u{F700}"))
        #expect(composer.engineState.highlighted == 0)
        let response = composer.handleKeyDown(controlForwardDelete)
        #expect(response.handled, "consumed")
        #expect(committed(response).isEmpty, "nothing committed: \(response.effects)")
        #expect(composer.engineState.isComposing && session.rawInput == "yahu", "the letters stay: \(session.rawInput)")
        #expect(!texts(composer).contains("鸭虎"), "\(texts(composer))")
        escape(composer)
        let after = candidatesOnPages("yahu", composer)
        #expect(!after.contains("鸭虎"), "forgotten: \(after.prefix(12))")
    }

    /// 减淡 for "jiandan", picked twice, comes up; deleted, it goes back to where rime-ice's dictionary has it.
    @Test func aDictionaryWordMovedUpGoesBack() throws {
        let session = try RimeFixture.session()
        let composer = Composer(engine: session, actionKey: .enter)
        let before = try #require(candidatesOnPages("jiandan", composer).firstIndex(of: "减淡"))
        #expect(before > 0)
        try learn(["减淡"], for: "jiandan", composer)
        try learn(["减淡"], for: "jiandan", composer)
        let learned = try #require(candidatesOnPages("jiandan", composer).firstIndex(of: "减淡"))
        #expect(learned < before, "moved up: \(learned) from \(before)")
        typeIn("jiandan", composer)
        let row = try #require(texts(composer).firstIndex(of: "减淡"))
        let effects = composer.deleteCandidate(index: row)
        #expect(committed(effects).isEmpty && composer.engineState.isComposing && session.rawInput == "jiandan")
        escape(composer)
        let after = candidatesOnPages("jiandan", composer)
        #expect(after.firstIndex(of: "减淡") == before, "back where the dictionary puts it: \(after.prefix(8))")
    }

    /// The user's English word among librime's candidates (`EnglishWordsEngine`): its row, and ⌃⌦ on it, change nothing.
    /// A librime row on that page deletes librime's candidate shown there: "yaji" with 压机 and 鸭鸡 learned shows
    /// 压机, Yaji, 鸭鸡 …; the third row is librime's second, 鸭鸡.
    @Test func englishWordsAreNotLibrimesToDelete() throws {
        let session = try RimeFixture.session()
        let plain = Composer(engine: session, actionKey: .enter)
        try learn(["鸭", "鸡"], for: "yaji", plain)
        try learn(["压", "机"], for: "yaji", plain)
        let librimes = candidatesOnPages("yaji", plain)
        #expect(Array(librimes.prefix(2)) == ["压机", "鸭鸡"], "\(librimes.prefix(6))")

        let dictionary = try #require(RimeService.shared.englishDictionary)
        let mixed = EnglishWordsEngine(base: session, dictionary: dictionary, words: ["bedrock", "Yaji"])
        let composer = Composer(engine: mixed, actionKey: .enter)
        typeIn("bedrock", composer)
        let shown = texts(composer)
        #expect(shown.first == "bedrock" && composer.engineState.highlighted == 0, "\(shown)")
        #expect(committed(composer.deleteCandidate(index: 0)).isEmpty)
        #expect(texts(composer) == shown && session.rawInput == "bedrock", "\(texts(composer))")
        let pressed = composer.handleKeyDown(controlForwardDelete)
        #expect(pressed.handled && committed(pressed).isEmpty, "consumed, nothing committed")
        #expect(texts(composer) == shown && composer.engineState.highlighted == 0, "\(texts(composer))")
        escape(composer)

        typeIn("yaji", composer)
        #expect(Array(texts(composer).prefix(3)) == ["压机", "Yaji", "鸭鸡"], "\(texts(composer))")
        _ = composer.deleteCandidate(index: 1)
        #expect(Array(texts(composer).prefix(3)) == ["压机", "Yaji", "鸭鸡"], "the word's row: nothing (\(texts(composer)))")
        let effects = composer.deleteCandidate(index: 2)
        #expect(committed(effects).isEmpty && composer.engineState.isComposing && session.rawInput == "yaji")
        #expect(texts(composer).first == "压机" && !texts(composer).contains("鸭鸡"), "鸭鸡 forgotten: \(texts(composer))")
        escape(composer)
        let after = candidatesOnPages("yaji", plain)
        #expect(after.first == "压机" && !after.prefix(10).contains("鸭鸡"), "\(after.prefix(6))")
    }
}

private let controlForwardDelete = KeyEvent(keyCode: VirtualKey.forwardDelete, characters: "\u{F728}", modifiers: .control)
private let pageDown = KeyEvent(keyCode: VirtualKey.pageDown, characters: "\u{F72D}")

private func typeIn(_ letters: String, _ composer: Composer) {
    for ch in letters { _ = composer.handleKeyDown(key(ch)) }
}

private func texts(_ composer: Composer) -> [String] { composer.engineState.candidates.map(\.text) }

private func escape(_ composer: Composer) {
    _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}"))
}

private func committed(_ effects: [Composer.Effect]) -> [String] {
    effects.compactMap { if case let .commit(text) = $0 { return text } else { return nil } }
}

private func committed(_ response: Composer.Response) -> [String] { committed(response.effects) }

/// The candidates for `letters`, page after page (six at most), the composition then cleared.
private func candidatesOnPages(_ letters: String, _ composer: Composer) -> [String] {
    typeIn(letters, composer)
    var all: [String] = []
    for _ in 0..<6 {
        all += texts(composer)
        if composer.engineState.isLastPage { break }
        _ = composer.handleKeyDown(pageDown)
    }
    escape(composer)
    return all
}

/// Types `letters` and picks `words` one after another, each where it is on the pages: librime learns what they make.
private func learn(_ words: [String], for letters: String, _ composer: Composer) throws {
    typeIn(letters, composer)
    var put: [String] = []
    for word in words {
        var picked = false
        for _ in 0..<15 where !picked {
            if let index = texts(composer).firstIndex(of: word) {
                put += committed(composer.choose(index: index))
                picked = true
            } else {
                _ = composer.handleKeyDown(pageDown)
            }
        }
        try #require(picked, "\(word) not among the candidates for \(letters)")
    }
    #expect(put == [words.joined()], "\(put)")
    #expect(!composer.engineState.isComposing)
}

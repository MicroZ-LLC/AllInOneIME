import Foundation
import Testing
@testable import AllInOneIMECore

/// The English words offered among pinyin's candidates, made ahead off the main thread at launch
/// (`EnglishWordsEngine.Words.prepare`): the first field takes them for the same settings and jargon list, and makes
/// its own for any other.
@Suite(.serialized)
struct EnglishWordsAheadTests {
    @Test func madeAheadForWhatTheyAreMadeOf() {
        var config = Config.default
        config.englishWords = ["Bedrock", "SageMaker"]
        let jargon = [JargonEntry(term: "north star", meaning: "the goal"), JargonEntry(term: "抓手")]
        EnglishWordsEngine.Words.prepare(config, jargon: jargon)
        let ahead = EnglishWordsEngine.Words.ahead(for: EnglishWordsEngine.Words.madeOf(config, jargon: jargon))
        #expect(ahead?.words == EnglishWords.offered(config, jargon: jargon))
        #expect(ahead?.keys.contains("northstar") == true && ahead?.keys.contains("bedrock") == true)
        // Another word since, or another list: none made for it.
        var more = config
        more.englishWords.append("Kiro")
        #expect(EnglishWordsEngine.Words.ahead(for: EnglishWordsEngine.Words.madeOf(more, jargon: jargon)) == nil)
        #expect(EnglishWordsEngine.Words.ahead(for: EnglishWordsEngine.Words.madeOf(config, jargon: [])) == nil)
    }

    /// Given whole, they are what the engine offers, as if set word by word.
    @Test func theEngineOffersThemAsGiven() {
        let words = ["Bedrock", "bedrock", "SageMaker"]
        let engine = EnglishWordsEngine(base: FakeEngine(), dictionary: EnglishDictionary([]))
        engine.made = EnglishWordsEngine.Words(words)
        let other = EnglishWordsEngine(base: FakeEngine(), dictionary: EnglishDictionary([]), words: words)
        #expect(engine.words == other.words && engine.keys == other.keys && engine.keys == ["bedrock", "sagemaker"])
        engine.words = ["Kiro"]
        #expect(engine.keys == ["kiro"])
    }
}

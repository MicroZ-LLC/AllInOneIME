@testable import AllInOneIMECore
import Foundation
import Testing
@testable import AllInOneIMERime

/// English words among the real librime's candidates (`EnglishWordsEngine`), with rime-ice's own English dictionary. In
/// the serialized suite: the learned words' sync drops every session.
extension RimeEngineTests {

    @Test func rimeIcesDictionaryIsReadFromThePack() throws {
        let started = Date()
        let read = try #require(EnglishDictionary.load(rimeData: RimeFixture.sharedData))
        print("rime-ice's English dictionary: \(read.count) words in \(String(format: "%.3f", Date().timeIntervalSince(started)))s")
        #expect(read.count > 20000)
        #expect(read.contains("hello") && read.contains("OpenRouter") && read.contains("GitHub Pages"))
        #expect(!read.contains("bedrock"))
        #expect(try englishDictionary().count == read.count)
    }

    /// The list shipped is what rime-ice lacks, each a word the user could add, of three letters or more.
    @Test func theCuratedWordsAreWhatRimeIceLacks() throws {
        let dictionary = try englishDictionary()
        let curated = EnglishWords.curated
        #expect(curated.count <= 300)
        #expect(Set(curated.map(EnglishWords.key)).count == curated.count, "each once")
        for word in curated {
            #expect(!dictionary.contains(word), "\(word): rime-ice has it")
            #expect(EnglishWords.word(word) == word, "\(word)")
            #expect(EnglishWords.key(word).count >= 3, "\(word)")
        }
    }

    @Test func bedrockComesUpOnceLearned() throws {
        let session = try RimeFixture.session()
        let engine = EnglishWordsEngine(base: session, dictionary: try englishDictionary())
        var learned: [String] = []
        let once = EnglishWords.TypedOnce()
        engine.rawCommitted = { word in
            if EnglishWords.learnable(word, known: Set(engine.words.map(EnglishWords.key)), dictionary: engine.dictionary, hidden: []),
               once.again(word) {
                engine.words.append(word)
                learned.append(word)
            }
        }
        let composer = Composer(engine: engine, actionKey: .enter)
        typeLetters("bedrock", composer)
        #expect(!shown(composer).contains("bedrock"), "pinyin only: \(shown(composer))")
        // ⏎ puts the letters in as typed: remembered the first time, learned the second.
        #expect(commits(composer.handleKeyDown(enter)) == ["bedrock"])
        #expect(learned.isEmpty)
        typeLetters("bedrock", composer)
        #expect(commits(composer.handleKeyDown(enter)) == ["bedrock"])
        #expect(learned == ["bedrock"])
        typeLetters("bedrock", composer)
        #expect(shown(composer).first == "bedrock", "\(shown(composer))")
        #expect(commits(composer.handleKeyDown(space)) == ["bedrock"])
        typeLetters("bedro", composer)
        #expect(shown(composer).dropFirst().first == "bedrock", "second while longer: \(shown(composer))")
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}"))
        // What rime-ice has, and pinyin, aren't learned.
        for _ in 0..<2 {
            typeLetters("hello", composer)
            #expect(commits(composer.handleKeyDown(enter)) == ["hello"])
            typeLetters("nihao", composer)
            #expect(commits(composer.handleKeyDown(enter)) == ["nihao"])
        }
        #expect(learned == ["bedrock"])
    }

    @Test func theCuratedWordsAmongLibrimesOwn() throws {
        let engine = EnglishWordsEngine(base: try RimeFixture.session(), dictionary: try englishDictionary(),
                                        words: EnglishWords.offered(.default, jargon: []))
        let composer = Composer(engine: engine, actionKey: .enter)
        typeLetters("bedrock", composer)
        #expect(shown(composer).first == "Bedrock", "\(shown(composer))")
        #expect(commits(composer.handleKeyDown(space)) == ["Bedrock"])
        // Letters pinyin may still go on with (sa-ge-m): after librime's page.
        typeLetters("sagem", composer)
        #expect(shown(composer).last == "SageMaker", "\(shown(composer))")
        // A digit picks it where it is shown.
        let place = try #require(composer.engineState.candidates.firstIndex { $0.text == "SageMaker" })
        #expect(commits(composer.handleKeyDown(key(Character(String(place + 1))))) == ["SageMaker"])
        typeLetters("kuberne", composer)
        #expect(shown(composer).first == "Kubernetes", "rime-ice's: \(shown(composer))")
        _ = composer.handleKeyDown(enter)
        typeLetters("kubef", composer)
        #expect(shown(composer).dropFirst().first == "Kubeflow", "second: \(shown(composer))")
        _ = composer.handleKeyDown(enter)
        // rime-ice's own English words stay as they were, once each; pinyin too.
        typeLetters("openrouter", composer)
        #expect(shown(composer).first == "OpenRouter")
        #expect(shown(composer).filter { $0.lowercased() == "openrouter" }.count == 1)
        _ = composer.handleKeyDown(enter)
        typeLetters("nihao", composer)
        #expect(shown(composer).first == "你好")
        #expect(commits(composer.handleKeyDown(space)) == ["你好"])
    }
}

/// rime-ice's English dictionary, as librime's service read it once it started.
private func englishDictionary() throws -> EnglishDictionary {
    _ = try RimeFixture.startup.get()
    return try #require(RimeService.shared.englishDictionary)
}

private func shown(_ composer: Composer) -> [String] { composer.engineState.candidates.map(\.text) }

private func typeLetters(_ letters: String, _ composer: Composer) {
    for ch in letters { _ = composer.handleKeyDown(key(ch)) }
}

/// What the composer put in the field.
private func commits(_ response: Composer.Response) -> [String] {
    response.effects.compactMap { if case let .commit(text) = $0 { return text } else { return nil } }
}

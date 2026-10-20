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

    /// Pinyin as `EnglishWords` reads it is rime-ice's: every syllable of its character table, and its speller's rules.
    @Test func pinyinIsRimeIces() throws {
        // Its entries (after the header's "..."): a character, its syllable, its weight.
        let table = try String(contentsOf: RimeFixture.sharedData.appendingPathComponent("cn_dicts/8105.dict.yaml"), encoding: .utf8)
        var syllables = Set<String>(), body = false
        for line in table.split(whereSeparator: \.isNewline) {
            if !body { body = line.trimmingCharacters(in: .whitespaces) == "..."; continue }
            let columns = line.split(separator: "\t")
            guard !line.hasPrefix("#"), columns.count > 1 else { continue }
            syllables.formUnion(columns[1].split(separator: " ").map(String.init))
        }
        #expect(syllables.count > 400)
        #expect(syllables.subtracting(Pinyin.syllables).isEmpty, "\(syllables.subtracting(Pinyin.syllables).sorted())")
        let schema = try String(contentsOf: RimeFixture.sharedData.appendingPathComponent("rime_ice.schema.yaml"), encoding: .utf8)
        #expect(unmodeledRules(schema).isEmpty, "\(unmodeledRules(schema))")
        // What it catches: rules of a kind Pinyin doesn't model (fuzz/: spellings only for whole words; xform/: one
        // spelling turned into another), and those of its kinds it lacks.
        let more = schema.replacingOccurrences(of: "\n  algebra:\n", with: "\n  algebra:\n    - fuzz/^zh/z/\n    - xform/^([nl])ue$/$1ve/\n")
        #expect(unmodeledRules(more) == ["fuzz/^zh/z/", "xform/^([nl])ue$/$1ve/"])
        let fewer = schema.replacingOccurrences(of: "    - erase/^m$/", with: "    # - erase/^m$/")
        #expect(unmodeledRules(fewer) == ["lacks erase/^m$/"])
        // Its abbreviations are what Pinyin reads as initials (or spellings: a, e, o).
        for (pattern, template) in Pinyin.abbreviations {
            let regex = try NSRegularExpression(pattern: pattern)
            for spelling in Pinyin.spellings {
                let abbreviated = regex.stringByReplacingMatches(in: spelling, range: NSRange(location: 0, length: spelling.utf16.count),
                                                                 withTemplate: template)
                #expect(Pinyin.initials.contains(abbreviated) || Pinyin.spellings.contains(abbreviated), "\(spelling): \(abbreviated)")
            }
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

    /// librime's preedit follows its highlighted candidate's syllables: ↓↓ from Bedrock to librime's second candidate
    /// changes it, and Space picks that candidate, not Bedrock.
    @Test func arrowsOntoLibrimesCandidatesStayThere() throws {
        let engine = EnglishWordsEngine(base: try RimeFixture.session(), dictionary: try englishDictionary(),
                                        words: EnglishWords.offered(.default, jargon: []))
        let composer = Composer(engine: engine, actionKey: .enter)
        typeLetters("bedrock", composer)
        #expect(shown(composer).first == "Bedrock" && composer.engineState.highlighted == 0, "\(shown(composer))")
        let down = KeyEvent(keyCode: VirtualKey.down, characters: "\u{F701}")
        _ = composer.handleKeyDown(down)
        _ = composer.handleKeyDown(down)
        #expect(composer.engineState.highlighted == 2, "\(composer.engineState.preedit)")
        let second = try #require(composer.engineState.candidates.dropFirst(2).first?.text)
        let response = composer.handleKeyDown(space)
        // Picked: put in, or the start of the composition when it reads only some of the letters.
        let picked = commits(response).first ?? composer.engineState.preedit
        #expect(picked.hasPrefix(second) && !picked.contains("Bedrock"), "\(second): \(picked)")
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}"))
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

/// The rules of a Rime schema's `speller/algebra` (`FuzzyPinyin.algebra`: as written, the commented-out ones left out)
/// that `Pinyin` doesn't model, and those it models that the schema lacks ("lacks …"). It models the derivations
/// (`Pinyin.algebra`: the same, in the same order, each applied to what the ones before it gave), the interjections
/// erased (`Pinyin.erased`) and the abbreviations (`Pinyin.abbreviations`); any other kind (fuzz/, xform/, xlit/ …)
/// isn't.
private func unmodeledRules(_ schema: String) -> [String] {
    let rules = FuzzyPinyin.algebra(ofSchema: schema)
    let derived = Pinyin.algebra.map { "derive/\($0.pattern)/\($0.template)/" }
    let others = Pinyin.erased.sorted().map { "erase/^\($0)$/" } + Pinyin.abbreviations.map { "abbrev/\($0.pattern)/\($0.template)/" }
    let modeled = Set(derived + others)
    var out = rules.filter { !modeled.contains($0) }
    out += others.filter { !rules.contains($0) }.map { "lacks " + $0 }
    if rules.filter({ $0.hasPrefix("derive/") }) != derived { out.append("derive/ rules other than Pinyin.algebra's, in its order") }
    return out
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

import AllInOneIMETestSupport
@testable import AllInOneIMECore
import Foundation
import Testing
@testable import AllInOneIMERime

/// The candidates' keys with the real librime, as macOS's own panel has them (`Config.candidateLayout`): in a row ← → move
/// the highlight, on from a page's last candidate to the next page's first and back from its first to the previous page's
/// last, and ↑↓ turn the page; in a column ↑↓ move so and ← → turn the page; - = turn it in either. Nothing is put in on
/// the way, and the pinyin stays as typed. Full pinyin here (the serialized suite's librime): librime alone, with English
/// words (`EnglishWordsEngine`), through a session (`FakeHost`) and one @'s line of pills; Shuangpin and Zhuyin, deployed as
/// the app deploys them, in a process of their own (`CandidateKeysSchemeTests`).
enum CandidateKeys {
    static let right = KeyEvent(keyCode: VirtualKey.right, characters: "\u{F703}")
    static let left = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")
    static let down = KeyEvent(keyCode: VirtualKey.down, characters: "\u{F701}")
    static let up = KeyEvent(keyCode: VirtualKey.up, characters: "\u{F700}")
    static let equal = KeyEvent(keyCode: 0x18, characters: "=")
    static let minus = KeyEvent(keyCode: 0x1B, characters: "-")

    /// What is typed with, and how a key is pressed there.
    struct Typing {
        var composer: Composer
        /// Presses a key: whether it was taken.
        var press: (KeyEvent) -> Bool
        /// What went into the field so far.
        var committed: () -> [String]
    }

    /// A composer of its own over `engine`.
    static func typing(_ engine: PinyinEngine, scheme: PinyinScheme = .full, horizontal: Bool) -> Typing {
        let composer = Composer(engine: engine, actionKey: .enter)
        composer.pinyinScheme = scheme
        composer.horizontalCandidates = horizontal
        var committed: [String] = []
        return Typing(composer: composer, press: { event in
            let response = composer.handleKeyDown(event)
            committed += commits(response.effects)
            return response.handled
        }, committed: { committed })
    }

    /// Checks every key on `typed`'s candidates (pages of them), each from a composition `make` starts afresh. `minusOnFirstPage`:
    /// "-" on the first page turns none (Zhuyin's types ㄦ there: its key; after a page on it turns back).
    static func check(_ label: String, horizontal: Bool, typed: String, minusOnFirstPage: Bool = true,
                      make: () throws -> Typing) throws {
        let (move, back) = horizontal ? (right, left) : (down, up)
        let (pageOn, pageBack) = horizontal ? (down, up) : (right, left)
        let layout = horizontal ? "in a row" : "in a column"
        func fresh() throws -> Typing {
            let typing = try make()
            for character in typed { _ = typing.press(key(character)) }
            let state = typing.composer.engineState
            try #require(state.isComposing && state.candidates.count > 2 && !state.isLastPage, "\(label): \(typed) \(state)")
            return typing
        }
        func press(_ typing: Typing, _ event: KeyEvent, _ times: Int = 1, _ what: String) {
            for _ in 0..<times { #expect(typing.press(event), "\(label) \(layout): \(what) taken") }
        }
        func at(_ typing: Typing) -> [Int] { [typing.composer.engineState.pageNumber, typing.composer.engineState.highlighted] }
        func asTyped(_ typing: Typing, _ what: String) {
            #expect(typing.committed().isEmpty && typing.composer.engineState.isComposing && typing.composer.engine?.rawInput == typed,
                    "\(label) \(layout): \(what) puts nothing in (\(typing.committed()), \(typing.composer.engine?.rawInput ?? "-"))")
        }

        // Along the page, on to the next one's first from its last, back to its last from the next one's first.
        let typing = try fresh()
        let size = typing.composer.engineState.candidates.count
        let firstPage = typing.composer.engineState.candidates.map(\.text)
        press(typing, move, 1, "the next")
        #expect(at(typing) == [0, 1], "\(label) \(layout): the next candidate")
        press(typing, move, size - 2, "the next")
        #expect(at(typing) == [0, size - 1], "\(label) \(layout): the page's last")
        press(typing, move, 1, "the next")
        #expect(at(typing) == [1, 0], "\(label) \(layout): from the last on to the next page's first (\(at(typing)))")
        #expect(typing.composer.engineState.candidates.map(\.text) != firstPage)
        press(typing, back, 1, "the previous")
        #expect(at(typing) == [0, size - 1], "\(label) \(layout): back to the previous page's last (\(at(typing)))")
        press(typing, back, size - 1, "the previous")
        #expect(at(typing) == [0, 0], "\(label) \(layout): the first")
        press(typing, back, 1, "the previous")
        #expect(at(typing) == [0, 0] && typing.composer.engineState.candidates.map(\.text) == firstPage,
                "\(label) \(layout): nothing before the first, the pinyin as it was")
        asTyped(typing, "moving")

        // The page keys: on and back, nothing before the first page, the highlight on the page's first.
        let pages = [(pageOn, pageBack, horizontal ? "↓ ↑" : "→ ←"), (equal, minus, "= -")]
        for (on, back, name) in pages {
            let typing = try fresh()
            press(typing, on, 1, name)
            #expect(at(typing) == [1, 0] && typing.composer.engineState.candidates.map(\.text) != firstPage,
                    "\(label) \(layout): \(name) turns the page on (\(at(typing)))")
            press(typing, back, 1, name)
            #expect(at(typing) == [0, 0] && typing.composer.engineState.candidates.map(\.text) == firstPage,
                    "\(label) \(layout): \(name) turns it back (\(at(typing)))")
            asTyped(typing, name)
            guard back != minus || minusOnFirstPage else { continue }
            let first = try fresh()
            press(first, back, 1, name)
            #expect(at(first) == [0, 0] && first.composer.engineState.candidates.map(\.text) == firstPage,
                    "\(label) \(layout): \(name) on the first page turns none, the pinyin as it was")
            asTyped(first, name)
        }
    }
}

extension RimeEngineTests {
    @Test(arguments: [true, false])
    func candidateKeysInFullPinyin(horizontal: Bool) throws {
        _ = try RimeFixture.startup.get()
        let dictionary = try #require(RimeService.shared.englishDictionary)
        for typed in ["nihao", "shi"] {
            try CandidateKeys.check("librime \(typed)", horizontal: horizontal, typed: typed) {
                CandidateKeys.typing(try RimeFixture.session(), horizontal: horizontal)
            }
            try CandidateKeys.check("English words \(typed)", horizontal: horizontal, typed: typed) {
                let engine = EnglishWordsEngine(base: try RimeFixture.session(), dictionary: dictionary,
                                                words: EnglishWords.offered(.default, jargon: []))
                return CandidateKeys.typing(engine, horizontal: horizontal)
            }
        }
    }

    /// A first page with English words on it (`EnglishWordsEngine`'s own): ← in a row (↑ in a column) from the next page's
    /// first goes back to its last row shown, not to the word that comes first; → (↓) from its last row on to the next
    /// page's first.
    @Test(arguments: [true, false])
    func candidateKeysOnAPageWithEnglishWords(horizontal: Bool) throws {
        _ = try RimeFixture.startup.get()
        let dictionary = try #require(RimeService.shared.englishDictionary)
        let (move, back) = horizontal ? (CandidateKeys.right, CandidateKeys.left) : (CandidateKeys.down, CandidateKeys.up)
        for typed in ["bedrock", "bedro"] {
            let engine = EnglishWordsEngine(base: try RimeFixture.session(), dictionary: dictionary,
                                            words: EnglishWords.offered(.default, jargon: []))
            let typing = CandidateKeys.typing(engine, horizontal: horizontal)
            for character in typed { _ = typing.press(key(character)) }
            let first = typing.composer.engineState.candidates.map(\.text)
            try #require(first.contains("Bedrock") && !typing.composer.engineState.isLastPage, "\(typed): \(first)")
            for _ in 0..<(first.count - 1) { _ = typing.press(move) }
            #expect(typing.composer.engineState.highlighted == first.count - 1 && typing.composer.engineState.pageNumber == 0)
            _ = typing.press(move)
            let second = typing.composer.engineState
            #expect(second.pageNumber == 1 && second.highlighted == 0, "\(typed): on to the next page's first")
            _ = typing.press(back)
            let state = typing.composer.engineState
            #expect(state.pageNumber == 0 && state.highlighted == first.count - 1 && state.candidates.map(\.text) == first,
                    "\(typed): back to the last row shown (\(state.highlighted): \(state.candidates.map(\.text)))")
            for _ in 0..<(first.count - 1) { _ = typing.press(back) }
            #expect(typing.composer.engineState.highlighted == 0 && typing.composer.engineState.candidates.first?.text == first.first)
            #expect(typing.committed().isEmpty && engine.rawInput == typed)
            // Space picks the row highlighted: the first, the word.
            _ = typing.press(space)
            #expect(typing.committed() == [first[0]], "\(typed)")
        }
    }

    /// The same keys through a session (`InputSession`, as the shell hands it the keys): plain typing's candidates are the
    /// panel's rows, laid out as the setting says.
    @Test(arguments: [CandidateArrangement.horizontal, .vertical])
    func candidateKeysThroughASession(layout: CandidateArrangement) throws {
        _ = try RimeFixture.startup.get()
        let dictionary = try #require(RimeService.shared.englishDictionary)
        for typed in ["nihao", "shi"] {
            try CandidateKeys.check("session \(typed)", horizontal: layout == .horizontal, typed: typed) {
                let host = try Self.host(layout: layout, dictionary: dictionary)
                return CandidateKeys.Typing(composer: host.composer, press: {
                    let handled = host.press($0)
                    #expect(host.panel?.horizontal == (layout == .horizontal) && host.panel?.highlighted == host.composer.engineState.highlighted)
                    return handled
                }, committed: { host.document.isEmpty ? [] : [host.document] })
            }
        }
    }

    /// One @'s pinyin candidates, a line of pills beside its rows: a row in either layout. ← → move along it, on to the next
    /// page from its last and back; - = turn its page; ↑↓ move one @'s rows. The pill highlighted is what Space picks.
    @Test(arguments: [CandidateArrangement.horizontal, .vertical])
    func candidateKeysInOneAtsLine(layout: CandidateArrangement) throws {
        _ = try RimeFixture.startup.get()
        let dictionary = try #require(RimeService.shared.englishDictionary)
        let host = try Self.host(layout: layout, dictionary: dictionary)
        host.press(FakeHost.at)
        host.type("shi")
        let composer = host.composer
        try #require(composer.oneAt != nil && composer.engineState.isComposing && host.panel?.candidates != nil)
        let size = composer.engineState.candidates.count, first = composer.engineState.candidates.map(\.text)
        for _ in 0..<(size - 1) { host.press(CandidateKeys.right) }
        #expect(composer.engineState.pageNumber == 0 && composer.engineState.highlighted == size - 1)
        #expect(host.panel?.candidatesHighlighted == size - 1)
        host.press(CandidateKeys.right)
        #expect(composer.engineState.pageNumber == 1 && composer.engineState.highlighted == 0 && host.panel?.candidatesHighlighted == 0)
        host.press(CandidateKeys.left)
        #expect(composer.engineState.pageNumber == 0 && composer.engineState.highlighted == size - 1)
        host.press(CandidateKeys.equal)
        #expect(composer.engineState.pageNumber == 1)
        host.press(CandidateKeys.minus)
        #expect(composer.engineState.pageNumber == 0 && composer.engineState.candidates.map(\.text) == first)
        // ↑↓: one @'s rows; the pinyin stays.
        let row = host.panel?.highlighted
        host.press(CandidateKeys.down)
        #expect(host.panel?.highlighted == row.map { $0 + 1 } && composer.engineState.pageNumber == 0 && composer.engine?.rawInput == "shi")
        #expect(host.document.isEmpty && composer.oneAt != nil)
        // Space picks the pill highlighted (the last of the first page) into the text after the magic key.
        host.press(CandidateKeys.up)
        host.press(FakeHost.space)
        #expect(composer.draft.hasSuffix(first[size - 1]), "\(composer.draft)")
    }

    /// A session whose level one is the real librime (English words among its candidates), Chinese first, the candidates
    /// laid out as `layout`.
    static func host(layout: CandidateArrangement, dictionary: EnglishDictionary) throws -> FakeHost {
        var config = Config.default
        config.candidateLayout = layout
        config.inputLanguages = [.chinese, .english]
        config.defaultInput = .chinese
        let fixed = config
        let rime = try RimeFixture.session()
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(rime) }
        services.englishDictionary = { dictionary }
        let host = FakeHost(services: services)
        host.focus()
        return host
    }
}

/// Shuangpin (Xiaohe) and Zhuyin, deployed as the app sets them up (`ShuangpinSchemaTests`, `ZhuyinSchemaTests`), each in a
/// process of its own (`RimeWorker`): the same keys as full pinyin's. Zhuyin's "-" is ㄦ (its key) until a page was turned on.
struct CandidateKeysSchemeTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rime-candidate-keys-\(UUID().uuidString)")

    @Test(.enabled(if: ShuangpinSchemaTests.runs, "needs rime-ice and OpenCC's data (make deps)"))
    func shuangpin() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("candidate-keys-shuangpin", root: root)
    }

    @Test(.enabled(if: ZhuyinSchemaTests.runs, "needs rime-ice, the Zhuyin data and OpenCC's data (make deps)"))
    func zhuyin() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("candidate-keys-zhuyin", root: root)
    }

    /// Each key in both layouts on `typed` (one syllable, pages of candidates; and two), librime alone and with English words.
    static func checkScheme(_ scheme: PinyinScheme, typed: [String], minusOnFirstPage: Bool) throws {
        let dictionary = try #require(RimeService.shared.englishDictionary)
        for horizontal in [true, false] {
            for typed in typed {
                for english in [false, true] {
                    try CandidateKeys.check("\(scheme.rawValue)\(english ? " with English words" : "") \(typed)", horizontal: horizontal,
                                            typed: typed, minusOnFirstPage: minusOnFirstPage) {
                        let session = try #require(RimeService.shared.makeSession())
                        let engine: PinyinEngine = english ? EnglishWordsEngine(base: session, dictionary: dictionary) : session
                        #expect(engine.selectSchema(scheme.schema))
                        return CandidateKeys.typing(engine, scheme: scheme, horizontal: horizontal)
                    }
                }
            }
        }
    }

    static let scenarios: [String: @Sendable (URL) throws -> Void] = [
        "candidate-keys-shuangpin": { root in
            let pack = try RemovedCandidatesFilterRimeTests.pack(root, code: "rime-lua",
                                                                 script: String(contentsOf: RemovedCandidatesFilterRimeTests.script, encoding: .utf8))
            let user = root.appendingPathComponent("Rime")
            _ = try FuzzyPinyin.apply([], characters: .simplified, scheme: .xiaohe,
                                      schema: pack.appendingPathComponent("rime_ice.schema.yaml"), userDir: user)
            #expect(try PinyinScheme.applySchemaList(.xiaohe, userDir: user) == .written)
            try RimeService.shared.start(sharedDataDir: pack, userDataDir: user, logDir: nil, fullCheck: true,
                                         openCCDir: TraditionalChineseRimeTests.openCC)
            try #require(RimeService.shared.waitUntilReady(timeout: 180))
            // ni hao; shi.
            try checkScheme(.xiaohe, typed: ["nihc", "ui"], minusOnFirstPage: true)
        },
        "candidate-keys-zhuyin": { root in
            let pack = try RemovedCandidatesFilterRimeTests.pack(root, code: "rime-lua",
                                                                 script: String(contentsOf: RemovedCandidatesFilterRimeTests.script, encoding: .utf8))
            for name in PinyinScheme.zhuyinData { try? FileManager.default.removeItem(at: pack.appendingPathComponent(name)) }
            let store = LanguagePackStore(directory: root.appendingPathComponent("LanguagePacks"))
            try store.linkData(.chinesePinyin, from: ZhuyinSchemaTests.data, names: PinyinScheme.zhuyinData)
            let user = root.appendingPathComponent("Rime")
            _ = try FuzzyPinyin.apply([], characters: .taiwan, scheme: .zhuyin,
                                      schema: pack.appendingPathComponent("rime_ice.schema.yaml"), userDir: user)
            #expect(try PinyinScheme.applySchemaList(.zhuyin, userDir: user) == .written)
            try RimeService.shared.start(sharedDataDir: pack, userDataDir: user, logDir: nil, fullCheck: true,
                                         openCCDir: TraditionalChineseRimeTests.openCC)
            try #require(RimeService.shared.waitUntilReady(timeout: 180))
            // ㄋㄧˇ ㄏㄠˇ; ㄕˋ.
            try checkScheme(.zhuyin, typed: ["su3cl3", "g4"], minusOnFirstPage: false)
        },
    ]
}

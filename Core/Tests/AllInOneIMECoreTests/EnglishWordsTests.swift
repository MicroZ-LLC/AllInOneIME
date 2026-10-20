import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// librime as `EnglishWordsEngine` sees it: a page of five candidates numbered 1–5, a highlight ↑↓ move (on to the next
/// page from the last), Space and the digits pick, ⏎ and a tap of Shift put the letters in as typed, a punctuation key the
/// highlighted candidate and its mark (rime-ice's 「，」), = the next page.
final class PagedEngine: PinyinEngine {
    var pages: [String: [String]] = [
        "bed": ["博尔顿", "波尔多", "把耳朵", "贝尔德", "巴尔德", "比尔"],
        "github": ["GitHub", "GitHub Pages", "给他", "隔天", "个头"],
        "xiaomi": ["小米", "小蜜", "晓米", "笑眯", "小觅"],
    ]
    var input = ""
    var highlighted = 0
    var page = 0
    var ascii = false
    /// Something picked of the input already, as librime shows it ("你好ma"): the preedit isn't the letters any more.
    var confirmed = ""
    /// The preedit split as the highlighted candidate reads the letters, as librime's is ("be drock", "bed rock").
    var preeditFollowsHighlight = false
    private var commit: String?
    static let pageSize = 5

    var all: [String] { pages[input.lowercased()] ?? ["比尔", "笔", "币", "必", "逼", "壁", "闭"] }
    var onPage: [String] { Array(all.dropFirst(page * Self.pageSize).prefix(Self.pageSize)) }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        guard !ascii, mask & RimeKey.releaseMask == 0 else {
            if keycode == RimeKey.shiftL, !input.isEmpty { emit(input); input = "" }  // commit_code on release
            return !ascii
        }
        let composing = !input.isEmpty
        switch keycode {
        case 0x41...0x5A, 0x61...0x7A:
            input.append(Character(Unicode.Scalar(UInt8(keycode))))
            (highlighted, page) = (0, 0)
            return true
        case RimeKey.shiftL: return composing
        case _ where !composing: break
        case RimeKey.space: pick(highlighted)
        case 0x31...0x35: pick(Int(keycode - 0x31))
        case RimeKey.returnKey: emit(input); input = ""
        case RimeKey.escape: input = ""
        case RimeKey.backSpace: input.removeLast(); (highlighted, page) = (0, 0)
        case RimeKey.down, RimeKey.pageDown, 0x3D:
            if keycode == RimeKey.down, highlighted < onPage.count - 1 { highlighted += 1 }
            else if (page + 1) * Self.pageSize < all.count { (page, highlighted) = (page + 1, 0) }
        case RimeKey.up: if highlighted > 0 { highlighted -= 1 }
        case 0x2C: pick(highlighted); emit("，")
        default: break
        }
        if keycode == 0x2C, !composing { emit("，"); return true }
        return composing
    }

    private func pick(_ i: Int) {
        guard onPage.indices.contains(i) else { return }
        emit(onPage[i])
        input = ""
    }

    private func emit(_ text: String) { commit = (commit ?? "") + text }

    func takeCommit() -> String? {
        defer { commit = nil }
        return commit
    }

    func snapshot() -> EngineSnapshot {
        guard !input.isEmpty else { return EngineSnapshot(isAsciiMode: ascii) }
        var preedit = input
        if preeditFollowsHighlight, highlighted + 2 < input.count {
            preedit.insert(" ", at: preedit.index(preedit.startIndex, offsetBy: highlighted + 2))
        }
        return EngineSnapshot(isComposing: true, preedit: confirmed + preedit, cursor: input.count,
                              candidates: onPage.enumerated().map { EngineCandidate(label: String($0.offset + 1), text: $0.element) },
                              highlighted: highlighted, pageNumber: page, isLastPage: (page + 1) * Self.pageSize >= all.count,
                              isAsciiMode: ascii)
    }

    func selectCandidate(onPage index: Int) -> Bool {
        guard onPage.indices.contains(index) else { return false }
        pick(index)
        return true
    }

    func commitComposition() -> String? {
        guard !input.isEmpty else { return nil }
        pick(highlighted)
        return takeCommit()
    }

    var rawInput: String { input }
    func clearComposition() { input = "" }
    func setAsciiMode(_ on: Bool) { ascii = on }
}

struct EnglishWordsTests {
    func engine(_ words: [String], dictionary: [String] = ["hello", "docker"]) -> (EnglishWordsEngine, PagedEngine) {
        let base = PagedEngine()
        return (EnglishWordsEngine(base: base, dictionary: EnglishDictionary(dictionary), words: words), base)
    }

    func type(_ letters: String, _ engine: PinyinEngine) {
        for scalar in letters.unicodeScalars {
            let upper = scalar.properties.isUppercase
            _ = engine.processKey(Int32(scalar.value), mask: upper ? RimeKey.shiftMask : 0)
        }
    }

    func texts(_ engine: PinyinEngine) -> [String] { engine.snapshot().candidates.map(\.text) }

    // MARK: Words

    @Test func wordsAreMatchedByTheirLettersInAnyCase() {
        #expect(EnglishWords.key("Next.js") == "nextjs")
        #expect(EnglishWords.key("Hugging Face") == "huggingface")
        #expect(EnglishWords.word("  Bedrock ") == "Bedrock")
        #expect(EnglishWords.word("Hugging   Face") == "Hugging Face")
        #expect(EnglishWords.word("北京") == nil && EnglishWords.word("b") == nil && EnglishWords.word("1Password") == nil)
        #expect(EnglishWords.word("a\u{0}b") == nil && EnglishWords.word(String(repeating: "x", count: 41)) == nil)
    }

    @Test func pinyinAsRimeIceReadsIt() {
        for pinyin in ["nihao", "xiaomi", "zhongguoren", "rug", "mac", "llm", "yyds"] { #expect(Pinyin.isPinyin(pinyin), "\(pinyin)") }
        for english in ["bedrock", "openrouter", "hello", "github", "kubernetes", "anthropic"] { #expect(!Pinyin.isPinyin(english), "\(english)") }
        // Up to four letters, initials too: rime-ice reads "bed" as b-e-d (博尔顿).
        for typing in ["zhon", "openr", "nihaom", "bed", "hel"] { #expect(Pinyin.isPinyinBeingTyped(typing), "\(typing)") }
        for english in ["bedro", "hello", "kuber"] { #expect(!Pinyin.isPinyinBeingTyped(english), "\(english)") }
    }

    @Test func pinyinAsRimeIcesSpellerReadsItCorrectedToo() {
        // Syllables the system's list lacks (这个 zhei-ge, 得了 dei-le, biangbiang 面), ü typed u or v, and rime-ice's
        // corrections of letters typed in the wrong order (中 zhogn, 上 shagn, 为 wie, 只 zih).
        #expect(Pinyin.syllables.isSuperset(of: ["zhei", "tei", "dei", "cei", "biang", "nia"]))
        for pinyin in ["zheige", "deile", "biangbiang", "zhogn", "shagn", "wie", "zih", "hzi", "jei", "lue", "nve", "jv", "qvan",
                       "nihaozhogn"] {
            #expect(Pinyin.isPinyin(pinyin), "\(pinyin)")
        }
        for english in ["bedrock", "openrouter", "frobnicate", "kubernetes", "anthropic"] { #expect(!Pinyin.isPinyin(english), "\(english)") }
        for typed in ["zhogn", "zheige", "deile", "shagn", "nihaozhogn"] {
            #expect(!EnglishWords.learnable(typed, known: [], dictionary: EnglishDictionary([]), hidden: []), "\(typed)")
        }
    }

    // MARK: Among the candidates

    @Test func aWordWhoseLettersAreTypedComesFirstAsItIsWritten() {
        let (e, _) = engine(["Bedrock"])
        type("bedrock", e)
        let snap = e.snapshot()
        #expect(snap.candidates.first?.text == "Bedrock")
        #expect(snap.candidates.map(\.label) == ["1", "2", "3", "4", "5", "6"])
        #expect(snap.highlighted == 0 && snap.preedit == "bedrock")
        _ = e.processKey(RimeKey.space, mask: 0)
        #expect(e.takeCommit() == "Bedrock")
        #expect(!e.snapshot().isComposing)
        type("bedrock", e)
        _ = e.processKey(RimeKey.space, mask: RimeKey.shiftMask)
        #expect(e.takeCommit() == "Bedrock", "⇧Space as Space")
        // In any case.
        type("BedRock", e)
        #expect(texts(e).first == "Bedrock")
    }

    @Test func aLongerWordComesSecondOnceItCantBePinyin() {
        let (e, _) = engine(["Bedrock"])
        type("be", e)
        #expect(!texts(e).contains("Bedrock"), "two letters start too many")
        // Three letters rime-ice reads as pinyin (b-e-d): after its page.
        type("d", e)
        #expect(texts(e) == ["博尔顿", "波尔多", "把耳朵", "贝尔德", "巴尔德", "Bedrock"])
        type("ro", e)
        #expect(texts(e) == ["比尔", "Bedrock", "笔", "币", "必", "逼"])
        #expect(e.snapshot().highlighted == 0, "librime's first stays highlighted")
        _ = e.processKey(RimeKey.space, mask: 0)
        #expect(e.takeCommit() == "比尔")
    }

    @Test func pinyinComesFirstWherePinyinReadsTheLettersToo() {
        // All of a word's letters, but pinyin: second, as rime-ice's reduce_english_filter puts "rug".
        let (e, _) = engine(["Xiaomi", "Zhongshan Park"])
        type("xiaomi", e)
        #expect(texts(e).prefix(2) == ["小米", "Xiaomi"])
        #expect(e.snapshot().highlighted == 0)
        e.clearComposition()
        // Pinyin still being typed: a longer word after the page.
        type("zhon", e)
        #expect(texts(e).last == "Zhongshan Park" && texts(e).first != "Zhongshan Park")
    }

    @Test func threeAtMostTheShorterFirst() {
        let (e, _) = engine(["CloudWatch", "CloudTrail", "CloudFormation", "Cloud", "CloudKit"], dictionary: [])
        type("clou", e)
        let words = texts(e).filter { $0.hasPrefix("Cloud") }
        #expect(words == ["Cloud", "CloudKit", "CloudTrail"])
    }

    @Test func notWhatThePageOrRimeIceHasAlready() {
        let (e, _) = engine(["github", "GitHub Pages", "githubactions", "Docker", "Dockerfile"], dictionary: ["docker"])
        type("github", e)
        #expect(texts(e) == ["GitHub", "githubactions", "GitHub Pages", "给他", "隔天", "个头"], "on the page already, in another case")
        e.clearComposition()
        type("docker", e)
        #expect(!texts(e).contains("Docker"), "rime-ice's dictionary has it: librime offers it itself")
        #expect(texts(e).contains("Dockerfile"))
    }

    @Test func noneWhenNoLettersAloneAreTypedOrOnOtherPages() {
        let (e, base) = engine(["Bedrock"])
        type("bed", e)
        #expect(texts(e).contains("Bedrock"))
        _ = e.processKey(0x3D, mask: 0)  // = : the next page
        #expect(e.snapshot().pageNumber == 1 && !texts(e).contains("Bedrock"))
        e.clearComposition()
        // Something of it picked already.
        type("bed", e)
        base.confirmed = "你"
        #expect(!texts(e).contains("Bedrock"))
        base.confirmed = ""
        e.clearComposition()
        e.setAsciiMode(true)
        type("bed", e)
        #expect(texts(e).isEmpty)
    }

    @Test func digitsAndClicksPickByThePlaceShown() {
        let (e, _) = engine(["Bedrock"])
        type("bedro", e)
        _ = e.processKey(0x32, mask: 0)  // 2
        #expect(e.takeCommit() == "Bedrock")
        type("bedro", e)
        _ = e.processKey(0x33, mask: 0)  // 3: librime's second
        #expect(e.takeCommit() == "笔")
        type("bedro", e)
        #expect(e.selectCandidate(onPage: 1))
        #expect(e.takeCommit() == "Bedrock")
        type("bedro", e)
        #expect(e.selectCandidate(onPage: 5))
        #expect(e.takeCommit() == "逼")
    }

    @Test func arrowsMoveThroughWordsAndLibrimesCandidates() {
        let (e, base) = engine(["Bedrock"])
        type("bedro", e)
        _ = e.processKey(RimeKey.down, mask: 0)
        #expect(e.snapshot().highlighted == 1 && e.snapshot().candidates[1].text == "Bedrock")
        #expect(e.snapshot().preedit == "bedro")
        _ = e.processKey(RimeKey.down, mask: 0)
        #expect(e.snapshot().highlighted == 2 && base.highlighted == 1)
        _ = e.processKey(RimeKey.up, mask: 0)
        #expect(e.snapshot().highlighted == 1)
        _ = e.processKey(RimeKey.up, mask: 0)
        #expect(e.snapshot().highlighted == 0 && base.highlighted == 0)
        _ = e.processKey(RimeKey.down, mask: 0)
        _ = e.processKey(RimeKey.space, mask: 0)
        #expect(e.takeCommit() == "Bedrock")
        // Past the page's end: librime's next page.
        type("bedro", e)
        for _ in 0..<6 { _ = e.processKey(RimeKey.down, mask: 0) }
        #expect(e.snapshot().pageNumber == 1 && texts(e) == ["壁", "闭"])
    }

    @Test func theHighlightStaysOnLibrimesCandidateItWasMovedTo() {
        // librime's preedit follows its highlighted candidate's syllables: moved onto its second, the preedit changes, and
        // the highlight stays there (it went back to the word, and Space put Bedrock in).
        let (e, base) = engine(["Bedrock"])
        base.preeditFollowsHighlight = true
        type("bedrock", e)
        #expect(texts(e).first == "Bedrock" && e.snapshot().highlighted == 0)
        _ = e.processKey(RimeKey.down, mask: 0)
        _ = e.processKey(RimeKey.down, mask: 0)
        #expect(base.highlighted == 1 && e.snapshot().highlighted == 2 && texts(e)[2] == "笔")
        _ = e.processKey(RimeKey.space, mask: 0)
        #expect(e.takeCommit() == "笔")
        // Back up onto the word, and the highlight set anew for new letters.
        type("bedrock", e)
        _ = e.processKey(RimeKey.down, mask: 0)
        _ = e.processKey(RimeKey.down, mask: 0)
        _ = e.processKey(RimeKey.up, mask: 0)
        _ = e.processKey(RimeKey.up, mask: 0)
        #expect(e.snapshot().highlighted == 0)
        _ = e.processKey(RimeKey.down, mask: 0)
        _ = e.processKey(RimeKey.down, mask: 0)
        _ = e.processKey(RimeKey.backSpace, mask: 0)
        type("k", e)
        #expect(e.snapshot().highlighted == 0)
        #expect(e.commitComposition() == "Bedrock")
    }

    @Test func aPunctuationMarkPutsTheWordInFirst() {
        let (e, _) = engine(["Bedrock"])
        type("bedrock", e)
        _ = e.processKey(0x2C, mask: 0)  // ,
        #expect(e.takeCommit() == "Bedrock，")
        // ' between syllables is librime's.
        type("bedrock", e)
        _ = e.processKey(0x27, mask: 0)
        #expect(e.takeCommit() == nil && e.rawInput == "bedrock")
    }

    @Test func theWordHighlightedIsTheComposition() {
        let (e, _) = engine(["Bedrock"])
        type("bedrock", e)
        #expect(e.commitComposition() == "Bedrock")
        type("bed", e)
        #expect(e.commitComposition() == "博尔顿")
    }

    @Test func lettersPutInAsTypedAreTold() {
        let (e, _) = engine([])
        var told: [String] = []
        e.rawCommitted = { told.append($0) }
        type("frobnicate", e)
        _ = e.processKey(RimeKey.returnKey, mask: 0)
        #expect(e.takeCommit() == "frobnicate")
        type("Zorblax", e)
        _ = e.processKey(RimeKey.shiftL, mask: 0)
        _ = e.processKey(RimeKey.shiftL, mask: RimeKey.releaseMask)
        #expect(e.takeCommit() == "Zorblax")
        #expect(told == ["frobnicate", "Zorblax"])
        // A candidate picked, a word picked: not as typed.
        e.words = ["Bedrock"]
        type("bed", e)
        _ = e.processKey(RimeKey.space, mask: 0)
        _ = e.takeCommit()
        type("bedrock", e)
        _ = e.processKey(RimeKey.space, mask: 0)
        _ = e.takeCommit()
        #expect(told == ["frobnicate", "Zorblax"])
    }

    @Test func theComposerShowsAndPicksThem() {
        let (e, _) = engine(["Bedrock"])
        let composer = Composer(engine: e, actionKey: .enter)
        for ch in "bedr" { _ = composer.handleKeyDown(k(String(ch))) }
        #expect(composer.engineState.candidates.map(\.text).contains("Bedrock"))
        for ch in "ock" { _ = composer.handleKeyDown(k(String(ch))) }
        #expect(composer.engineState.candidates.first?.text == "Bedrock")
        #expect(commits(composer.handleKeyDown(spaceKey)) == ["Bedrock"])
    }

    // MARK: Learning

    let dictionary = EnglishDictionary(["hello", "world", "docker"])

    @Test func learnedOnlyWhenItMayBeAWord() {
        func learnable(_ typed: String, known: Set<String> = [], hidden: [String] = []) -> Bool {
            EnglishWords.learnable(typed, known: known, dictionary: dictionary, hidden: hidden)
        }
        #expect(learnable("frobnicate") && learnable("Bedrock") && learnable("OpenRouterX"))
        #expect(!learnable("ab"), "fewer than three letters")
        #expect(!learnable("hello") && !learnable("Docker"), "rime-ice has it")
        #expect(!learnable("frobnicate", known: ["frobnicate"]), "offered already")
        #expect(!learnable("nihao") && !learnable("yyds") && !learnable("xiaomi"), "pinyin")
        #expect(!learnable("bcdfg"), "no vowel")
        #expect(!learnable("ab1cd") && !learnable("frob nicate"), "letters only")
        #expect(!learnable(String(repeating: "abcde", count: 5)), "too long for a word")
    }

    @Test func secretsAreNeverLearned() {
        #expect(!EnglishWords.learnable("qwrtzpsdf", known: [], dictionary: dictionary, hidden: []), "random letters")
        #expect(!EnglishWords.learnable("aaargh", known: [], dictionary: dictionary, hidden: []), "a letter three times")
        #expect(!EnglishWords.learnable("Phoenix", known: [], dictionary: dictionary, hidden: ["phoenix"]), "a hidden word")
        // What the jargon list may hold.
        for secret in ["sk-ant-api03-abcdefghijklmnopqrstuvwx", "ghp_" + String(repeating: "aB3", count: 12), "AKIAIOSFODNN7EXAMPLE",
                       "zhang@example.com", "4111 1111 1111 1111", "192.168.1.20", "AB12CD34EF56", "x7Kq9PzR2mW4"] {
            #expect(EnglishWords.looksSecret(secret, hidden: []), "\(secret)")
        }
        for word in ["OKR", "LGTM", "circle back", "Bedrock", "HTTPS", "Kubernetes"] {
            #expect(!EnglishWords.looksSecret(word, hidden: []), "\(word)")
        }
    }

    @Test func remoteDesktopsAndVirtualMachinesByTheirBundleIds() {
        for app in ["com.microsoft.rdc.macos", "com.microsoft.rdc.osx.beta", "com.apple.ScreenSharing", "com.edovia.screens5.mac",
                    "com.p5sys.jump.mac.viewer.web", "com.parallels.desktop.console", "com.parallels.winapp.notepad",
                    "com.vmware.fusion", "com.utmapp.UTM", "org.virtualbox.app.VirtualBoxVM", "com.citrix.receiver.icaviewer.mac",
                    "com.philandro.anydesk", "com.teamviewer.TeamViewer", "com.realvnc.vncviewer", "COM.MICROSOFT.RDC.MACOS"] {
            #expect(EnglishWords.isRemote(app), "\(app)")
        }
        for app in ["com.microsoft.VSCode", "com.apple.TextEdit", "com.google.Chrome", "com.vmware.horizonx", nil] {
            #expect(!EnglishWords.isRemote(app), "\(app ?? "none")")
        }
    }

    @Test func aHiddenWordAnywhereInTheLettersIsNeverLearned() {
        func learnable(_ typed: String, hidden: [String]) -> Bool {
            EnglishWords.learnable(typed, known: [], dictionary: dictionary, hidden: hidden)
        }
        // In any case, inside the letters, by its own letters ("Project Phoenix", "Acme-Corp").
        #expect(!learnable("phoenixapi", hidden: ["Phoenix"]) && !learnable("myphoenix", hidden: ["PHOENIX"]))
        #expect(!learnable("projectphoenix", hidden: ["Project Phoenix"]) && !learnable("acmecorpx", hidden: ["Acme-Corp"]))
        #expect(learnable("frobnicate", hidden: ["Phoenix", "李明", " "]), "none of them in it")
    }

    @Test func offeredAreTheUsersThenTheJargonListsThenTheCurated() {
        var config = Config.default
        config.englishWords = ["bedrock", "北京", "Frobnicate"]
        let jargon = [JargonEntry(term: "circle back", meaning: "回头再说"), JargonEntry(term: "抓手"),
                      JargonEntry(term: "sk-ant-api03-abcdefghijklmnopqrstuvwx"), JargonEntry(term: "frobnicate")]
        let offered = EnglishWords.offered(config, jargon: jargon)
        #expect(Array(offered.prefix(3)) == ["bedrock", "Frobnicate", "circle back"])
        #expect(!offered.contains("Bedrock"), "the user's spelling")
        #expect(offered.contains("SageMaker") && offered.count == 3 + EnglishWords.curated.count - 1)
    }

    @Test func learnedIntoTheConfigFileAlone() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("englishwords-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.json")
        // No file yet: one is written.
        #expect(try EnglishWords.learn("frobnicate", at: url))
        #expect(try Config.load(from: url).englishWords == ["frobnicate"])
        // A file of the user's: only the key changes, a key this version doesn't know stays.
        try Data(#"{"futureKey": {"a": 1}, "typeOut": true, "englishWords": ["Bedrock"]}"#.utf8).write(to: url)
        #expect(try EnglishWords.learn("frobnicate", at: url))
        #expect(try !EnglishWords.learn("FROBNICATE", at: url), "the same letters")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(Set(object?.keys ?? [:].keys) == ["futureKey", "typeOut", "englishWords"])
        #expect(object?["englishWords"] as? [String] == ["Bedrock", "frobnicate"])
    }

    @Test func theListInSettings() {
        var config = Config.default
        #expect(EnglishWords.add("Bedrock, SageMaker；北京\nbedrock", to: &config).words == ["Bedrock", "SageMaker"])
        #expect(config.englishWords == ["Bedrock", "SageMaker"] && config.addedEnglishWords == ["Bedrock", "SageMaker"])
        #expect(EnglishWords.add("BEDROCK", to: &config) == EnglishWords.Added(), "there already")
        EnglishWords.remove("BEDROCK", from: &config)
        #expect(config.englishWords == ["SageMaker"] && config.addedEnglishWords == ["SageMaker"])
    }

    @Test func aWordAddedByHandThatHidingSensitiveInformationHidesIsRefused() {
        // Words (a letter first, then letters, digits, - . + & ' _ / and spaces) that are a key, a card or phone number, an
        // address: the list syncs through iCloud and shows on screen.
        let secrets = ["sk-ant-api03-abcdefghijklmnopqrstuvwx", "AKIAIOSFODNN7EXAMPLE", "ghp_" + String(repeating: "aB3", count: 12),
                       "x7Kq9PzR2mW4AbCdEfGh", "card 4111 1111 1111 1111", "tel 13800138000", "call +1 415 555 0134", "IP 192.168.1.20"]
        for secret in secrets { #expect(EnglishWords.word(secret) != nil && EnglishWords.isSensitive(secret), "\(secret)") }
        var config = Config.default
        let result = EnglishWords.add((secrets + ["Bedrock"]).joined(separator: "\n"), to: &config)
        #expect(result.words == ["Bedrock"] && result.refused == secrets)
        #expect(config.englishWords == ["Bedrock"] && config.addedEnglishWords == ["Bedrock"])
        // Not the user's hidden words, nor what only looks random to learning: the user added them.
        config.redaction.customWords = ["Phoenix"]
        let words = ["Phoenix", "qwrtzpsdf", "aaargh", "vLLM", "cuDNN", "Auth0", "x7Kq9", "K8s", "Web3"]
        #expect(EnglishWords.add(words.joined(separator: ", "), to: &config) == EnglishWords.Added(words: words))
    }

    @Test func overTheLimitTheOldestLearnedGoFirst() throws {
        // Words learned, but for the second one: added in Settings.
        var config = Config.default
        config.englishWords = (0..<EnglishWords.maxWords).map { "word\($0)x" }
        config.addedEnglishWords = ["word1x"]
        EnglishWords.add("Bedrock", to: &config)
        #expect(config.englishWords.count == EnglishWords.maxWords && config.englishWords.prefix(2) == ["word1x", "word2x"])
        #expect(config.englishWords.last == "Bedrock" && config.addedEnglishWords == ["word1x", "Bedrock"])
        // Learned into the file: an added word stays there too.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("englishwords-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.json")
        try config.write(to: url)
        #expect(try EnglishWords.learn("frobnicate", at: url))
        let learned = try Config.load(from: url)
        #expect(learned.englishWords.count == EnglishWords.maxWords && learned.englishWords.prefix(2) == ["word1x", "word3x"])
        #expect(learned.englishWords.suffix(2) == ["Bedrock", "frobnicate"] && learned.addedEnglishWords == ["word1x", "Bedrock"])
        // All added: the oldest go.
        let all = (0..<EnglishWords.maxWords).map { "word\($0)x" }
        #expect(EnglishWords.capped(all + ["newest"], added: all + ["newest"]) == Array(all.dropFirst()) + ["newest"])
        #expect(EnglishWords.capped(["a", "b"], added: []) == ["a", "b"])
    }

    @Test func theSettingsKeepTheWords() throws {
        var config = Config.default
        #expect(config.englishWords.isEmpty && config.learnsEnglishWords)
        config.englishWords = ["Bedrock", "frobnicate"]
        config.addedEnglishWords = ["Bedrock"]
        config.learnsEnglishWords = false
        let read = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(read.englishWords == ["Bedrock", "frobnicate"] && read.addedEnglishWords == ["Bedrock"] && !read.learnsEnglishWords)
        let odd = try JSONDecoder().decode(Config.self, from: Data(#"{"englishWords": "Bedrock", "addedEnglishWords": 1}"#.utf8))
        #expect(odd.englishWords.isEmpty && odd.addedEnglishWords.isEmpty && odd.learnsEnglishWords)
        // Written only when there are some.
        let none = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Config.default)) as? [String: Any]
        #expect(none?["englishWords"] == nil && none?["addedEnglishWords"] == nil && none?["learnsEnglishWords"] == nil)
        #expect(Config.allKeys.contains("englishWords") && Config.allKeys.contains("addedEnglishWords")
            && Config.allKeys.contains("learnsEnglishWords"))
    }

    @Test func rimeIcesDictionaryIsReadFromItsTables() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("englishdict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("en_dicts"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("""
            ---
            name: melt_eng
            import_tables:
              - en_dicts/en_ext # comment
              - en_dicts/en
            ...
            """.utf8).write(to: folder.appendingPathComponent("melt_eng.dict.yaml"))
        try Data("# header\n---\nname: en\n...\n# a\ta\nhello\thello\nOpenRouter\tOpenRouter\n".utf8)
            .write(to: folder.appendingPathComponent("en_dicts/en.dict.yaml"))
        try Data("---\nname: en_ext\n...\niPhone 17\tiPhone17\t4\n".utf8).write(to: folder.appendingPathComponent("en_dicts/en_ext.dict.yaml"))
        let dictionary = try #require(EnglishDictionary.load(rimeData: folder))
        #expect(dictionary.contains("Hello") && dictionary.contains("openrouter") && dictionary.contains("iphone17"))
        #expect(!dictionary.contains("a") && dictionary.count == 3)
        #expect(EnglishDictionary.load(rimeData: folder.appendingPathComponent("none")) == nil)
    }
}

/// The session's English words (`InputSession`): mixed in when the shell has rime-ice's dictionary, learned where that
/// may be.
@Suite(.serialized)
struct EnglishWordsSessionTests {
    final class Learned: @unchecked Sendable { var words: [String] = [] }

    func host(_ config: Config = Self.settings, learned: Learned = Learned(), dictionary: Bool = true,
              secure: @escaping () -> Bool = { false }, jargon: [JargonEntry] = [], app: String? = "com.example.editor",
              terminal: Bool = false, engine: PinyinEngine = FakeEngine()) -> FakeHost {
        var services = SessionServices(loadSettings: { config })
        services.levelOne = { .engine(engine) }
        if dictionary { services.englishDictionary = { EnglishDictionary(["hello"]) } }
        services.learnEnglishWord = { learned.words.append($0) }
        services.secureInputActive = secure
        services.jargon = { _ in jargon }
        let host = FakeHost(services: services)
        host.app = app
        host.terminal = terminal
        host.focus()
        return host
    }

    /// `letters` put in as typed twice, as a word is learned.
    func putInTwice(_ letters: String, _ host: FakeHost) {
        for _ in 0..<2 {
            host.type(letters)
            host.press(FakeHost.enter)
        }
    }

    static var settings: Config {
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.chinese, .english])
        return config
    }

    func candidates(_ host: FakeHost) -> [String] { host.composer.engineState.candidates.map(\.text) }

    @Test func lettersPutInAsTypedTwiceAreLearnedAndOfferedAtOnce() {
        withInterfaceLanguage("en") {
            let learned = Learned()
            let host = host(learned: learned)
            // The first time only remembered (a password typed once is never kept), in memory: not offered, not kept.
            host.type("frobnicate")
            host.press(FakeHost.enter)
            #expect(host.document == "frobnicate")
            #expect(learned.words.isEmpty)
            host.type("frobn")
            #expect(!candidates(host).contains("frobnicate"))
            host.press(FakeHost.escape)
            // The second time: learned.
            host.type("frobnicate")
            host.press(FakeHost.enter)
            #expect(learned.words == ["frobnicate"])
            host.type("frobn")
            #expect(candidates(host).contains("frobnicate"))
            // Pinyin and words rime-ice has aren't.
            host.press(FakeHost.escape)
            putInTwice("nihao", host)
            putInTwice("hello", host)
            #expect(learned.words == ["frobnicate"])
        }
    }

    @Test func theFirstTimeIsRememberedForEveryFieldUntilTheAppQuits() {
        withInterfaceLanguage("en") {
            let learned = Learned()
            var services = SessionServices(loadSettings: { Self.settings })
            services.levelOne = { .engine(FakeEngine()) }
            services.englishDictionary = { EnglishDictionary(["hello"]) }
            services.learnEnglishWord = { learned.words.append($0) }
            let mail = FakeHost(services: services)
            mail.focus()
            mail.type("zorblax")
            mail.press(FakeHost.enter)
            let notes = FakeHost(services: services)
            notes.app = "com.example.notes"
            notes.focus()
            notes.type("zorblax")
            notes.press(FakeHost.enter)
            #expect(learned.words == ["zorblax"], "once in each of two fields")
            // Another launch (services of their own) starts afresh.
            let later = host(learned: learned)
            later.type("quuxify")
            later.press(FakeHost.enter)
            #expect(learned.words == ["zorblax"])
        }
    }

    @Test func typedOnceKeepsTheLatestByTheirLetters() {
        let once = EnglishWords.TypedOnce()
        #expect(!once.again("Frobnicate") && once.again("FROBNICATE"), "the same letters, in any case")
        #expect(!once.again("frobnicate"), "forgotten once it came again")
        for i in 0..<EnglishWords.TypedOnce.limit { _ = once.again("word\(i)") }
        #expect(!once.again("zorblax") && !once.again("word0"), "the oldest forgotten beyond the limit")
    }

    @Test func neverDuringSecureInputInAnAppWithNoAIOrWithLearningOff() {
        withInterfaceLanguage("en") {
            let learned = Learned()
            var secure = false
            let anywhere = host(learned: learned, secure: { secure })
            for _ in 0..<2 {
                anywhere.type("frobnicate")
                secure = true
                anywhere.press(FakeHost.enter)
                secure = false
            }
            #expect(anywhere.document == "frobnicatefrobnicate" && learned.words.isEmpty, "secure input elsewhere")
            // A password field takes the keys.
            let field = host(learned: learned)
            for _ in 0..<2 {
                field.type("frobnicate")
                field.secure = true
                field.press(FakeHost.enter)
                field.secure = false
            }
            #expect(learned.words.isEmpty, "a password field")
            var noAI = Self.settings
            noAI.appProfiles["com.example.editor"] = AppProfile(noAI: true)
            let app = host(noAI, learned: learned)
            putInTwice("frobnicate", app)
            var off = Self.settings
            off.learnsEnglishWords = false
            let notLearning = host(off, learned: learned)
            putInTwice("frobnicate", notLearning)
            #expect(app.document == "frobnicatefrobnicate" && notLearning.document == "frobnicatefrobnicate" && learned.words.isEmpty)
        }
    }

    @Test func neverInATerminalARemoteDesktopOrAVirtualMachine() {
        withInterfaceLanguage("en") {
            let learned = Learned()
            // A terminal's password prompts (sudo, ssh, git) don't turn secure input on in every terminal.
            let terminal = host(learned: learned, app: "com.googlecode.iterm2", terminal: true)
            putInTwice("frobnicate", terminal)
            #expect(terminal.document == "frobnicatefrobnicate")
            // What is typed there goes to another computer, whose password fields this one can't tell.
            for app in ["com.microsoft.rdc.macos", "com.parallels.desktop.console", "com.vmware.fusion", "com.utmapp.UTM",
                        "com.citrix.receiver.icaviewer.mac", "com.teamviewer.TeamViewer"] {
                let remote = host(learned: learned, app: app)
                putInTwice("frobnicate", remote)
                #expect(remote.document == "frobnicatefrobnicate", "\(app)")
            }
            #expect(learned.words.isEmpty)
            putInTwice("frobnicate", host(learned: learned))
            #expect(learned.words == ["frobnicate"], "anywhere else")
        }
    }

    @Test func secretsInLettersAloneAreNeverLearned() {
        withInterfaceLanguage("en") {
            // Letters only, a vowel, no six consonants in a row nor a letter three times, not pinyin: only what hiding
            // sensitive information hides (`Redaction`'s keys, the user's hidden words) tells them from a word.
            let secrets = ["XoBuKiVaZeNu", "hTqeWobAsuKelPimRaVo", "kTzQaWmPeLvR", "Phoenix", "phoenixapi"]
            for secret in secrets {
                #expect(!EnglishWords.looksRandom(secret) && !Pinyin.isPinyin(EnglishWords.key(secret)), "\(secret)")
            }
            let learned = Learned()
            var config = Self.settings
            config.redaction.customWords = ["phoenix"]
            let host = host(config, learned: learned, engine: PagedEngine())
            for secret in secrets { putInTwice(secret, host) }
            #expect(host.document == secrets.map { $0 + $0 }.joined())
            #expect(learned.words.isEmpty)
            putInTwice("frobnicate", host)
            #expect(learned.words == ["frobnicate"], "a word is")
        }
    }

    @Test func theUsersWordsAndTheJargonListsAreOffered() {
        withInterfaceLanguage("en") {
            var config = Self.settings
            config.englishWords = ["Frobnicate"]
            let host = host(config, jargon: [JargonEntry(term: "circle back", meaning: "回头再说")])
            host.type("frob")
            #expect(candidates(host) == ["frob", "Frobnicate"])
            host.press(KeyEvent(keyCode: 0x13, characters: "2"))
            #expect(host.document == "Frobnicate")
            host.type("circleb")
            #expect(candidates(host).contains("circle back"))
            host.type("ack")
            #expect(candidates(host).first == "circle back")
            host.press(FakeHost.space)
            #expect(host.document == "Frobnicatecircle back")
        }
    }

    @Test func noneWithoutRimeIcesDictionary() {
        withInterfaceLanguage("en") {
            let learned = Learned()
            var config = Self.settings
            config.englishWords = ["Frobnicate"]
            let host = host(config, learned: learned, dictionary: false)
            host.type("frob")
            #expect(candidates(host) == ["frob"])
            host.press(FakeHost.enter)
            putInTwice("zorblax", host)
            #expect(learned.words.isEmpty)
        }
    }
}

/// The English words through iCloud (`ICloudSync`): with the words pinyin learned, merged as the hidden words are.
@Suite(.serialized)
struct EnglishWordsSyncTests {
    func t(_ minutes: Double) -> Date { SyncRig.t0.addingTimeInterval(minutes * 60) }

    @Test func theyGoWithTheLearnedWordsMergedWhenAMacJoins() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") { $0.englishWords = ["Bedrock", "frobnicate"] }
        a.sync(at: t(0))
        let b = try rig.mac("B") { $0.englishWords = ["FROBNICATE", "zorblax"] }
        b.sync(at: t(1))
        a.sync(at: t(2))
        for mac in [a, b] { #expect(try mac.config().englishWords == ["Bedrock", "frobnicate", "zorblax"]) }
        // One learned on a Mac (the key written alone) gets to the other; one removed goes from both.
        try EnglishWords.learn("quuxify", at: a.configURL)
        try a.touch(a.configURL, at: t(3))
        a.sync(at: t(4))
        b.sync(at: t(5))
        #expect(try b.config().englishWords == ["Bedrock", "frobnicate", "zorblax", "quuxify"])
        try b.edit(at: t(6)) { EnglishWords.remove("bedrock", from: &$0) }
        b.sync(at: t(7))
        a.sync(at: t(8))
        #expect(try a.config().englishWords == ["frobnicate", "zorblax", "quuxify"])
    }

    @Test func mergedByTheirLettersWithinTheLimitTheAddedKept() throws {
        let rig = try SyncRig()
        // Each Mac with words learned (more than the limit together) and some added in Settings; one spelled two ways.
        let half = EnglishWords.maxWords * 3 / 4
        let a = try rig.mac("A") {
            $0.englishWords = (0..<half).map { "alpha\($0)x" } + ["Hugging Face", "Bedrock"]
            $0.addedEnglishWords = ["Hugging Face", "Bedrock"]
        }
        a.sync(at: t(0))
        let b = try rig.mac("B") {
            $0.englishWords = ["Kiro"] + (0..<half).map { "beta\($0)x" } + ["HuggingFace"]
            $0.addedEnglishWords = ["Kiro", "HuggingFace"]
        }
        b.sync(at: t(1))
        a.sync(at: t(2))
        b.sync(at: t(3))
        let configs = try [a, b].map { try $0.config() }
        #expect(configs[0].englishWords == configs[1].englishWords, "settled")
        #expect((try rig.settingsJSON()[ICloudSync.englishWordsKey] as? [String: Any])?["value"] as? [String] == configs[0].englishWords)
        for config in configs {
            #expect(config.englishWords.count == EnglishWords.maxWords)
            #expect(config.englishWords.filter { EnglishWords.key($0) == "huggingface" } == ["Hugging Face"], "once, iCloud's")
            #expect(Set(config.addedEnglishWords) == ["Hugging Face", "Bedrock", "Kiro"])
            #expect(config.englishWords.contains("Bedrock") && config.englishWords.contains("Kiro"), "the added kept")
            // The learned words iCloud lacked gave way, the oldest first.
            #expect(config.englishWords.contains("alpha0x") && !config.englishWords.contains("beta0x")
                && config.englishWords.contains("beta\(half - 1)x"))
        }
        #expect(ICloudSync.category(of: ICloudSync.addedEnglishWordsKey) == .learnedWords)
    }

    @Test func notWithTheLearnedWordsOff() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") {
            $0.englishWords = ["Bedrock"]
            $0.iCloudSync.learnedWords = false
        }
        a.sync(at: t(0))
        #expect(try rig.settingsJSON()[ICloudSync.englishWordsKey] == nil)
        #expect(ICloudSync.category(of: ICloudSync.englishWordsKey) == .learnedWords)
        #expect(ICloudSync.category(of: "learnsEnglishWords") == .settings)
        #expect(ICloudSync.problem(ICloudSync.englishWordsKey, .string("Bedrock"), environment: .init()) == .wrongType)
        #expect(ICloudSync.problem("learnsEnglishWords", .bool(false), environment: .init()) == nil)
    }
}

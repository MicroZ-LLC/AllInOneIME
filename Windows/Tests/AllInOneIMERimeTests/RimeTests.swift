import AllInOneIMECore
import Foundation
import Testing
import WinSDK
@testable import AllInOneIMERime

/// Uses the real librime (its Windows build) and the rime-ice data Scripts/build-rime-data.sh prepares (rime-data in
/// ThirdParty). The macOS shell's Rime tests (the root's Tests/AllInOneIMERimeTests), on Windows, with what only
/// Windows has: rime.dll loaded from ThirdParty.
enum RimeFixture {
    /// Windows/, the package.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    /// Where Scripts/fetch-librime.sh and Scripts/build-rime-data.sh put librime and rime-ice: $ALLINONEIME_THIRDPARTY if
    /// it is set, else Windows/ThirdParty. The one rule, as Package.swift and the scripts have it.
    static let thirdParty: URL = {
        if let given = ProcessInfo.processInfo.environment["ALLINONEIME_THIRDPARTY"], !given.isEmpty {
            return URL(fileURLWithPath: given, isDirectory: true)
        }
        return root.appendingPathComponent("ThirdParty", isDirectory: true)
    }()
    static let sharedData = thirdParty.appendingPathComponent("rime-data")
    static let rimeDLL = thirdParty.appendingPathComponent("librime/dist/lib/rime.dll")
    /// ALLINONEIME_REQUIRE_RIME_DATA=1 (as the macOS shell's `make test` sets it): missing data is a failure, not a skip.
    static var dataRequired: Bool { ProcessInfo.processInfo.environment["ALLINONEIME_REQUIRE_RIME_DATA"] == "1" }
    /// librime's user folder: one per test process, so that runs in two checkouts at once don't use (and
    /// delete) the same one. Removed when the process exits.
    static let userData = FileManager.default.temporaryDirectory
        .appendingPathComponent("allinoneime-rime-tests-\(ProcessInfo.processInfo.processIdentifier)")

    /// installation.yaml as librime wrote it when it deployed, before a test changed it.
    static var deployedInstallation: String?

    /// rime.dll, delay-loaded (Package.swift): loaded here by its full path, before anything calls into librime, so that
    /// the delay-load finds it already in the process (a test runner has no rime.dll beside it or on PATH).
    static func loadLibrary() throws {
        let path = rimeDLL.path.replacingOccurrences(of: "/", with: "\\")
        guard FileManager.default.fileExists(atPath: rimeDLL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: path + " (run Scripts/fetch-librime.sh)"])
        }
        let module = path.withCString(encodedAs: UTF16.self) {
            LoadLibraryExW($0, nil, DWORD(LOAD_WITH_ALTERED_SEARCH_PATH))
        }
        guard module != nil else {
            let error = GetLastError()
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "LoadLibraryExW(\(path)): error \(error)"])
        }
    }

    /// Starts librime once per test process; returns the deployment time.
    static let startup: Result<TimeInterval, Error> = {
        do {
            guard FileManager.default.fileExists(atPath: sharedData.appendingPathComponent("build/rime_ice.table.bin").path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: sharedData.path + " (run Scripts/build-rime-data.sh)"])
            }
            try loadLibrary()
            // Left by an earlier process with the same id that didn't get to exit (a crash): start fresh.
            try? FileManager.default.removeItem(at: userData)
            // Registered before librime starts: exit handlers run last first, so what librime sets up from here
            // on is torn down before its folder goes.
            atexit { try? FileManager.default.removeItem(at: RimeFixture.userData) }
            let started = Date()
            try RimeService.shared.start(sharedDataDir: sharedData, userDataDir: userData, logDir: nil)
            guard RimeService.shared.waitUntilReady(timeout: 120) else {
                throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "deployment timed out"])
            }
            deployedInstallation = try? String(contentsOf: userData.appendingPathComponent("installation.yaml"), encoding: .utf8)
            return .success(Date().timeIntervalSince(started))
        } catch {
            return .failure(error)
        }
    }()

    static func session() throws -> RimeSession {
        _ = try startup.get()
        return try #require(RimeService.shared.makeSession())
    }
}

func key(_ char: Character, code: UInt16 = 0, modifiers: KeyModifiers = []) -> KeyEvent {
    KeyEvent(keyCode: code, characters: String(char), modifiers: modifiers)
}

let space = KeyEvent(keyCode: VirtualKey.space, characters: " ")
let enter = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r")

/// "@i" and Tab: an @improve draft ("@improve "), whose sentence the action key then sends.
func startImprove(_ composer: Composer) {
    _ = composer.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", modifiers: .shift))
    _ = composer.handleKeyDown(key("i"))
    _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
}

/// Sends text through the same keysym mapping the input method uses.
func type(_ text: String, into session: RimeSession) {
    for ch in text {
        let event = ch == " " ? space : key(ch)
        let mapped = RimeKey.map(event)!
        _ = session.processKey(mapped.keycode, mask: mapped.mask)
    }
}

@Suite(.serialized)
struct RimeEngineTests {
    @Test func deploysQuicklyFromPrebuiltData() throws {
        let seconds = try RimeFixture.startup.get()
        print("rime deployment took \(String(format: "%.2f", seconds))s")
        #expect(seconds < 30)
        #expect(RimeService.shared.currentSchemaName() == "rime_ice")
        #expect(RimeService.shared.version == "1.16.1")
    }

    @Test func convertsAWord() throws {
        let s = try RimeFixture.session()
        type("nihao", into: s)
        let snap = s.snapshot()
        #expect(snap.isComposing)
        #expect(snap.candidates.first?.text == "你好")
        #expect(snap.candidates.first?.label == "1")
        #expect(s.rawInput == "nihao")
        _ = s.processKey(RimeKey.space, mask: 0)
        #expect(s.takeCommit() == "你好")
        #expect(!s.snapshot().isComposing)
    }

    @Test func convertsAWholeSentence() throws {
        let s = try RimeFixture.session()
        type("wojintianyoudianbushufu", into: s)
        let texts = s.snapshot().candidates.map(\.text)
        #expect(texts.first == "我今天有点不舒服", "candidates: \(texts)")
    }

    /// Page Down and Page Up, and rime-ice's own paging keys ("=" and "-"), through the candidates of one syllable.
    @Test func pagesThroughTheCandidates() throws {
        let s = try RimeFixture.session()
        type("shi", into: s)
        let first = s.snapshot()
        #expect(first.pageNumber == 0 && !first.isLastPage && first.candidates.count > 1)
        #expect(s.processKey(RimeKey.pageDown, mask: 0))
        let second = s.snapshot()
        #expect(second.pageNumber == 1 && !second.candidates.isEmpty)
        #expect(Set(second.candidates.map(\.text)).isDisjoint(with: first.candidates.map(\.text)),
                "page 1: \(first.candidates.map(\.text)), page 2: \(second.candidates.map(\.text))")
        #expect(second.candidates.first?.label == "1", "labels start again on each page")
        #expect(s.processKey(RimeKey.pageUp, mask: 0))
        #expect(s.snapshot().pageNumber == 0 && s.snapshot().candidates.map(\.text) == first.candidates.map(\.text))
        #expect(s.processKey(0x3D, mask: 0))  // '='
        #expect(s.snapshot().pageNumber == 1)
        #expect(s.processKey(0x2D, mask: 0))  // '-'
        #expect(s.snapshot().pageNumber == 0)
        s.clearComposition()
    }

    /// A candidate picked by its place on the page (a click), by its number key, and on the second page.
    @Test func picksACandidate() throws {
        let s = try RimeFixture.session()
        type("zhong", into: s)
        let texts = s.snapshot().candidates.map(\.text)
        try #require(texts.count >= 3, "candidates: \(texts)")
        #expect(s.selectCandidate(onPage: 1))
        #expect(s.takeCommit() == texts[1])
        #expect(!s.snapshot().isComposing)

        type("zhong", into: s)
        let again = s.snapshot().candidates.map(\.text)
        #expect(s.processKey(0x33, mask: 0))  // '3'
        #expect(s.takeCommit() == again[2])

        type("zhong", into: s)
        _ = s.processKey(RimeKey.pageDown, mask: 0)
        let page2 = s.snapshot().candidates.map(\.text)
        try #require(!page2.isEmpty)
        #expect(s.selectCandidate(onPage: 0))
        #expect(s.takeCommit() == page2[0])
    }

    /// librime learns what is picked (rime-ice's user dictionary, rime_ice.userdb in the user folder): a word picked from
    /// the second page comes up front the next time.
    @Test func learnsPickedWords() throws {
        let s = try RimeFixture.session()
        type("yinyue", into: s)
        let before = s.snapshot().candidates.map(\.text)
        _ = s.processKey(RimeKey.pageDown, mask: 0)
        let page2 = s.snapshot().candidates.map(\.text)
        // A word of the whole input (two characters), so that picking it commits it.
        let index = try #require(page2.firstIndex { $0.count == 2 }, "second page: \(page2)")
        let word = page2[index]
        #expect(!before.contains(word))
        #expect(s.selectCandidate(onPage: index))
        #expect(s.takeCommit() == word)

        type("yinyue", into: s)
        let after = s.snapshot().candidates.map(\.text)
        #expect(after.prefix(3).contains(word), "\(word) picked once: \(after)")
        s.clearComposition()
        #expect(FileManager.default.fileExists(atPath: RimeFixture.userData.appendingPathComponent("rime_ice.userdb").path))
    }

    @Test func punctuationRawInputAndLatinMode() throws {
        let s = try RimeFixture.session()
        #expect(s.processKey(0x2C, mask: 0))  // ','
        #expect(s.takeCommit() == "，")

        type("hello", into: s)
        _ = s.processKey(RimeKey.returnKey, mask: 0)
        #expect(s.takeCommit() == "hello")

        s.setAsciiMode(true)
        #expect(s.snapshot().isAsciiMode)
        #expect(!s.processKey(0x61, mask: 0))  // 'a' goes to the application
        s.setAsciiMode(false)
        #expect(!s.snapshot().isAsciiMode)
    }

    /// rime-ice's date translator is a Lua script: this proves librime-lua, built into rime.dll, loads it.
    @Test func luaPluginsLoad() throws {
        let s = try RimeFixture.session()
        type("rq", into: s)
        let year = String(Calendar(identifier: .gregorian).component(.year, from: Date()))
        let texts = s.snapshot().candidates.map(\.text)
        #expect(texts.contains { $0.contains(year) }, "candidates: \(texts)")
        s.clearComposition()
    }

    @Test func composerDraftsChineseAndTranslatesOnSecondSpace() throws {
        let composer = Composer(engine: try RimeFixture.session(), actionKey: .space)
        startImprove(composer)
        #expect(composer.draft == "@improve ")
        for ch in "wojintianyoudianbushufu" { _ = composer.handleKeyDown(key(ch)) }
        #expect(composer.markedText.hasSuffix("fu"))
        let confirm = composer.handleKeyDown(space)
        #expect(confirm.handled)
        #expect(!confirm.effects.contains { if case .commit = $0 { return true } else { return false } })
        #expect(composer.draft == "@improve 我今天有点不舒服")
        #expect(composer.phase == .drafting)

        _ = composer.handleKeyDown(key(","))
        #expect(composer.draft == "@improve 我今天有点不舒服，")
        for ch in "xiangqingjia" { _ = composer.handleKeyDown(key(ch)) }
        _ = composer.handleKeyDown(space)
        #expect(composer.draft == "@improve 我今天有点不舒服，想请假")

        let translate = composer.handleKeyDown(space)
        #expect(translate.effects.first == .startConversion(input: "我今天有点不舒服，想请假", id: 1))
        #expect(composer.phase == .translating(id: 1))
    }

    /// ⌥Space with real librime: it converts the pinyin still being typed and sends the sentence;
    /// Space picks words and, once nothing is left to convert, types a space.
    @Test func optionSpaceActsWithTheRealEngine() throws {
        let optionSpace = KeyEvent(keyCode: VirtualKey.space, characters: "\u{A0}", charactersIgnoringModifiers: " ",
                                   modifiers: .option)
        let composer = Composer(engine: try RimeFixture.session(), actionKey: .optionSpace)
        startImprove(composer)
        for ch in "wojintianyoudianbushufu" { _ = composer.handleKeyDown(key(ch)) }
        let r = composer.handleKeyDown(optionSpace)
        #expect(r.handled && r.effects.first == .startConversion(input: "我今天有点不舒服", id: 1))
        #expect(composer.phase == .translating(id: 1) && !composer.engineState.isComposing)
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}"))  // back to the draft

        for ch in "xiangqingjia" { _ = composer.handleKeyDown(key(ch)) }
        _ = composer.handleKeyDown(space)  // picks the words
        let typed = composer.draft
        #expect(typed.hasPrefix("@improve 我今天有点不舒服") && !composer.engineState.isComposing)
        _ = composer.handleKeyDown(space)  // nothing left to convert: a space
        #expect(composer.draft == typed + " " && composer.phase == .drafting)
        #expect(composer.handleKeyDown(optionSpace).effects.first
                == .startConversion(input: String(typed.dropFirst("@improve ".count)), id: 2))
        composer.engine?.clearComposition()
    }

    /// The defaults with real librime: a regular input method, and ⏎ runs an @ command.
    @Test func regularInputMethodWithAtCommandsWithTheRealEngine() throws {
        let composer = Composer(engine: try RimeFixture.session())
        #expect(composer.actionKey == .enter)
        for ch in "nihao" { _ = composer.handleKeyDown(key(ch)) }
        #expect(composer.handleKeyDown(space).effects.contains(.commit("你好")) && composer.draft.isEmpty)
        _ = composer.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", modifiers: .shift))
        _ = composer.handleKeyDown(key("q"))
        _ = composer.handleKeyDown(enter)
        #expect(composer.draft == "@question ")
        for ch in "liangzijisuan" { _ = composer.handleKeyDown(key(ch)) }
        #expect(composer.handleKeyDown(enter).effects.first == .startCommand(.question, input: "量子计算", id: 1))
        composer.engine?.clearComposition()
    }

    /// With real librime: a second "@" inside a command's text brings up the commands that run there,
    /// letters for the symbol, Chinese again after it.
    @Test func commandInsideATextWithTheRealEngine() throws {
        let engine = try RimeFixture.session()
        let composer = Composer(engine: engine)
        composer.commands = Command.catalog([CustomCommand(name: "stock", type: .run, argv: ["stock", "{input}"])])
        let at = KeyEvent(keyCode: 0x13, characters: "@", modifiers: .shift)
        _ = composer.handleKeyDown(at)
        _ = composer.handleKeyDown(key("q"))
        _ = composer.handleKeyDown(enter)
        for ch in "nihao" { _ = composer.handleKeyDown(key(ch)) }
        _ = composer.handleKeyDown(space)
        _ = composer.handleKeyDown(at)
        #expect(composer.draft == "@question 你好@")
        #expect(composer.paletteMatches.map(\.name) == ["py", "js", "stock"])
        for ch in "st" { _ = composer.handleKeyDown(key(ch)) }
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        #expect(composer.draft == "@question 你好@stock " && composer.engineState.isAsciiMode)
        for ch in "AAPL" { _ = composer.handleKeyDown(KeyEvent(keyCode: 0, characters: String(ch), modifiers: .shift)) }
        _ = composer.handleKeyDown(space)
        #expect(composer.draft == "@question 你好@stock AAPL " && !composer.engineState.isAsciiMode)
        for ch in "zenmeyang" { _ = composer.handleKeyDown(key(ch)) }
        let effects = composer.handleKeyDown(enter).effects
        guard case let .startPlan(outer, plan, _)? = effects.first else {
            Issue.record("expected a plan: \(effects)")
            return
        }
        #expect(outer == .question && plan.inner.map(\.argument) == ["AAPL"])
        #expect(plan.input(outputs: ["QUOTE"]) == "你好QUOTE 怎么样")
        composer.engine?.clearComposition()
    }

    /// An @improve command with real librime: Return converts the pinyin still being typed and sends
    /// it; ⇧Return keeps the letters as typed.
    @Test func returnActsWithTheRealEngine() throws {
        let composer = Composer(engine: try RimeFixture.session())
        #expect(composer.actionKey == .enter)
        startImprove(composer)
        for ch in "wojintianyoudianbushufu" { _ = composer.handleKeyDown(key(ch)) }
        let r = composer.handleKeyDown(enter)
        #expect(r.handled && r.effects.first == .startConversion(input: "我今天有点不舒服", id: 1))
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}"))
        let shiftReturn = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift)
        let asTyped = composer.handleKeyDown(shiftReturn)
        #expect(asTyped.effects.contains(.commit("@improve 我今天有点不舒服")) && composer.phase == .idle)
        startImprove(composer)
        for ch in "nihao" { _ = composer.handleKeyDown(key(ch)) }
        _ = composer.handleKeyDown(shiftReturn)
        #expect(composer.draft == "@improve nihao")  // librime's Return: the letters as typed
        composer.engine?.clearComposition()
    }

    /// An Option tap with real librime: it converts the pinyin and sends it.
    @Test func optionTapActsWithTheRealEngine() throws {
        let composer = Composer(engine: try RimeFixture.session(), actionKey: .optionTap)
        #expect(composer.actionKey == .optionTap)
        startImprove(composer)
        for ch in "wojintianyoudianbushufu" { _ = composer.handleKeyDown(key(ch)) }
        _ = composer.handleFlagsChanged(keyCode: VirtualKey.leftOption, modifiers: [.option, .leftOption], timestamp: 1)
        let tap = composer.handleFlagsChanged(keyCode: VirtualKey.leftOption, modifiers: [], timestamp: 1.08)
        #expect(tap.first == .startConversion(input: "我今天有点不舒服", id: 1))
        #expect(composer.phase == .translating(id: 1) && !composer.engineState.isComposing)
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}"))
        composer.engine?.clearComposition()
    }

    /// ⇧Space with real librime is Space: it picks the candidate, in a command too, and with nothing
    /// pending it is the app's.
    @Test func shiftSpaceIsSpaceWithTheRealEngine() throws {
        let composer = Composer(engine: try RimeFixture.session())
        let shiftSpace = KeyEvent(keyCode: VirtualKey.space, characters: " ", modifiers: .shift)
        for ch in "nihao" { _ = composer.handleKeyDown(key(ch)) }
        let r = composer.handleKeyDown(shiftSpace)
        #expect(r.handled && r.effects.contains(.commit("你好")) && composer.phase == .idle)
        #expect(composer.handleKeyDown(shiftSpace) == .passThrough)
        startImprove(composer)
        for ch in "nihao" { _ = composer.handleKeyDown(key(ch)) }
        _ = composer.handleKeyDown(shiftSpace)
        _ = composer.handleKeyDown(shiftSpace)
        #expect(composer.draft == "@improve 你好 " && composer.phase == .drafting)
        composer.engine?.clearComposition()
    }

    /// English mode in real librime: letters, capitals and punctuation collect into an @improve
    /// command, a double Space sends it (`space` action key), ⇧Return inserts it as typed.
    @Test func englishModeDraftsWithTheRealEngine() throws {
        let composer = Composer(engine: try RimeFixture.session(), actionKey: .space)
        composer.setInputMode(.english)
        #expect(composer.engineState.isAsciiMode)
        startImprove(composer)
        for ch in "Hi" {
            _ = composer.handleKeyDown(KeyEvent(keyCode: 0, characters: String(ch),
                                                modifiers: ch.isUppercase ? .shift : []))
        }
        _ = composer.handleKeyDown(key(","))
        _ = composer.handleKeyDown(space)
        for ch in "team" { _ = composer.handleKeyDown(key(ch)) }
        #expect(composer.draft == "@improve Hi, team" && composer.isLatinDraft)
        _ = composer.handleKeyDown(space)
        #expect(composer.handleKeyDown(space).effects.first == .startConversion(input: "Hi, team", id: 1))
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}"))  // back to the draft
        let r = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift))
        #expect(r.handled && r.effects.contains(.commit("@improve Hi, team ")))
        composer.setInputMode(.chinese)
        #expect(!composer.engineState.isAsciiMode)
    }

    /// rime-ice rejects keys carrying the Caps Lock mask; turning Caps Lock on mid-word must not freeze it.
    @Test func capsLockMidCompositionKeepsEditing() throws {
        let composer = Composer(engine: try RimeFixture.session())
        for ch in "nihao" { _ = composer.handleKeyDown(key(ch)) }
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}", modifiers: .capsLock))
        #expect(composer.markedText.replacingOccurrences(of: " ", with: "") == "niha")
        _ = composer.handleKeyDown(KeyEvent(keyCode: 0x1F, characters: "O", charactersIgnoringModifiers: "o", modifiers: .capsLock))
        #expect(composer.markedText.replacingOccurrences(of: " ", with: "") == "nihao")
        let r = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.space, characters: " ", modifiers: .capsLock))
        #expect(r.effects.contains(.commit("你好")))
    }

    /// A Shift tap after picking part of the input keeps the picked word (librime's commit_code).
    @Test func shiftTapKeepsPickedWords() throws {
        let composer = Composer(engine: try RimeFixture.session())
        for ch in "nihaoma" { _ = composer.handleKeyDown(key(ch)) }
        var picked = false
        for _ in 0..<6 where !picked {
            if let i = composer.engineState.candidates.firstIndex(where: { $0.text == "你好" }) {
                _ = composer.choose(index: i)
                picked = true
            } else {
                _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.pageDown, characters: "\u{F72D}"))
            }
        }
        try #require(picked, "你好 not among the candidates for nihaoma")
        #expect(composer.markedText.hasPrefix("你好"))
        _ = composer.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 1)
        let tap = composer.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1)
        #expect(tap.contains(.commit("你好ma")))
        #expect(composer.engineState.isAsciiMode)
        #expect(!composer.engineState.isComposing)
    }

    /// librime reuses session ids after a redeploy; an old session must never act on a new one.
    @Test func redeployInvalidatesOldSessions() throws {
        var old: RimeSession? = try RimeFixture.session()
        RimeService.shared.redeploy()
        #expect(old?.isValid == false)
        #expect(RimeService.shared.waitUntilReady(timeout: 120))
        let fresh = try #require(RimeService.shared.makeSession())
        #expect(old?.isValid == false)
        old = nil  // its deinit must not destroy `fresh`, even if librime reused the id
        #expect(fresh.isValid)
        type("nihao", into: fresh)
        #expect(fresh.snapshot().candidates.first?.text == "你好")
    }

    /// Fuzzy pinyin: with n ↔ l, "lan" also offers the nan words (难, 南, 男); off again, it doesn't.
    @Test func fuzzyPinyinWithTheRealEngine() throws {
        _ = try RimeFixture.startup.get()
        let schema = RimeFixture.sharedData.appendingPathComponent("rime_ice.schema.yaml")
        func candidates(_ input: String) throws -> [String] {
            let s = try RimeFixture.session()
            type(input, into: s)
            return s.snapshot().candidates.map(\.text)
        }
        let nan: Set = ["难", "南", "男"]
        defer {
            _ = try? FuzzyPinyin.apply([], schema: schema, userDir: RimeFixture.userData)
            RimeService.shared.redeploy()
            RimeService.shared.waitUntilReady(timeout: 120)
        }
        #expect(try FuzzyPinyin.apply(["n-l"], schema: schema, userDir: RimeFixture.userData) == .written)
        RimeService.shared.redeploy()
        #expect(RimeService.shared.waitUntilReady(timeout: 120))
        let fuzzy = try candidates("lan")
        #expect(fuzzy.contains { nan.contains($0) }, "lan with n ↔ l: \(fuzzy)")
        #expect(try FuzzyPinyin.apply([], schema: schema, userDir: RimeFixture.userData) == .removed)
        RimeService.shared.redeploy()
        #expect(RimeService.shared.waitUntilReady(timeout: 120))
        let plain = try candidates("lan")
        #expect(!plain.contains { nan.contains($0) }, "lan without fuzzy pinyin: \(plain)")
    }
}

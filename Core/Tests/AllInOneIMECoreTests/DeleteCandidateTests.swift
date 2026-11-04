import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// ⌃⌦ as AppKit hands it over (⌃Fn⌫ on a laptop's keyboard), and the other delete keys that are no delete of a candidate.
enum DeleteKeys {
    static let controlForwardDelete = KeyEvent(keyCode: VirtualKey.forwardDelete, characters: "\u{F728}", modifiers: .control)
    static let forwardDelete = KeyEvent(keyCode: VirtualKey.forwardDelete, characters: "\u{F728}")
    static let shiftForwardDelete = KeyEvent(keyCode: VirtualKey.forwardDelete, characters: "\u{F728}", modifiers: .shift)
    static let controlBackspace = KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}", modifiers: .control)
}

/// A candidate removed for good through the composer: a row right-clicked (`Composer.deleteCandidate(index:)`, the row
/// among those the panel shows) or ⌃⌦ on the highlighted one, while pinyin is typed. The engine is told the candidate
/// (librime's `delete_candidate`: what it learned forgotten), and it is on the list of those removed
/// (`Composer.removedCandidates`, `Effect.candidateRemoved`); nothing is committed, the letters stay and the page is laid
/// out again without it. On rows that aren't the engine's (level two's results, the command list, voice input) and with
/// nothing composed, nothing; ⌃⌦ is then the app's. (RemovedCandidatesTests.swift has the rest.)
struct DeleteCandidateTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    func type(_ s: String, _ c: Composer) {
        for ch in s { _ = c.handleKeyDown(ch == "@" ? at : ch == " " ? spaceKey : k(String(ch))) }
    }

    func texts(_ c: Composer) -> [String] { c.engineState.candidates.map(\.text) }

    // MARK: - The engine's candidates

    @Test func aRowsCandidateIsRemovedAndNothingCommitted() {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        type("nihao", c)
        #expect(texts(c) == ["你好", "拟好"])
        let effects = c.deleteCandidate(index: 0)
        #expect(engine.deleted == [0])
        #expect(commits(effects).isEmpty, "nothing committed: \(effects)")
        #expect(c.engineState.isComposing && engine.input == "nihao" && c.markedText == "nihao", "the letters stay (\(c.markedText))")
        // The page laid out again, without it; kept on the list.
        #expect(texts(c) == ["拟好"], "\(texts(c))")
        #expect(effects.contains(.updateMarkedText) && effects.contains(.showPanel) && effects.contains(.candidateRemoved("你好")),
                "\(effects)")
        #expect(c.removedCandidates == ["你好"])
        // Past the page's rows (one now): nothing removed, nothing committed, still composing.
        #expect(c.deleteCandidate(index: 1).isEmpty && engine.deleted == [0])
        let past = c.deleteCandidate(index: 7)
        #expect(past.isEmpty && commits(past).isEmpty && c.engineState.isComposing && engine.input == "nihao")
        // The second row: the second candidate.
        _ = c.handleKeyDown(escKey)
        type("wo", c)
        #expect(c.deleteCandidate(index: 1).contains(.candidateRemoved("窝")) && engine.deleted == [0, 1], "\(engine.deleted)")
        #expect(texts(c) == ["我"] && c.removedCandidates == ["你好", "窝"])
    }

    /// Pinyin typed in a command's text: its candidates too; the draft stays as it is.
    @Test func inACommandsText() {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        type("@imp", c)
        _ = c.handleKeyDown(tab)
        type("nihao", c)
        let draft = c.draft
        let effects = c.deleteCandidate(index: 1)
        #expect(engine.deleted == [1] && commits(effects).isEmpty)
        #expect(c.draft == draft && c.engineState.isComposing && engine.input == "nihao", "\(c.draft)")
    }

    /// ⌃⌦ deletes the highlighted candidate and is consumed (the app never has it); deleted once: librime isn't given
    /// the key as well (its own Control+Delete would delete its highlight again).
    @Test func controlForwardDeleteDeletesTheHighlightedOne() {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        type("nihao", c)
        _ = c.handleKeyDown(downKey)
        #expect(c.engineState.highlighted == 1)
        let keysBefore = engine.keys.count
        let response = c.handleKeyDown(DeleteKeys.controlForwardDelete)
        #expect(response.handled, "consumed")
        #expect(engine.deleted == [1], "the highlighted one: \(engine.deleted)")
        #expect(engine.keys.count == keysBefore, "librime never had the key")
        #expect(commits(response).isEmpty && c.engineState.isComposing && engine.input == "nihao")
        // With Caps Lock on, the same.
        let capsLock = KeyEvent(keyCode: VirtualKey.forwardDelete, characters: "\u{F728}", modifiers: [.control, .capsLock])
        #expect(c.handleKeyDown(capsLock).handled && engine.deleted == [1, 0], "\(engine.deleted)")
    }

    @Test func withNothingComposedControlForwardDeleteIsTheApps() {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        #expect(!c.handleKeyDown(DeleteKeys.controlForwardDelete).handled)
        #expect(c.deleteCandidate(index: 0).isEmpty)
        // After a pick: nothing composed any more.
        type("nihao", c)
        #expect(commits(c.handleKeyDown(spaceKey)) == ["你好"] && !c.isComposing)
        #expect(!c.handleKeyDown(DeleteKeys.controlForwardDelete).handled)
        #expect(c.deleteCandidate(index: 0).isEmpty)
        #expect(engine.deleted.isEmpty, "\(engine.deleted)")
    }

    /// ⌦ without Control (and ⇧⌦, ⌃⌫) deletes no candidate.
    @Test func otherDeleteKeysAreNoDelete() {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        type("nihao", c)
        _ = c.handleKeyDown(DeleteKeys.forwardDelete)
        _ = c.handleKeyDown(DeleteKeys.shiftForwardDelete)
        #expect(engine.deleted.isEmpty && c.engineState.isComposing, "\(engine.deleted)")
        _ = c.handleKeyDown(DeleteKeys.controlBackspace)
        #expect(engine.deleted.isEmpty, "\(engine.deleted)")
    }

    // MARK: - English words among the candidates

    /// An English word put in among the engine's candidates (`EnglishWordsEngine`) is removed the same way, by its
    /// letters (the same word spelled otherwise goes too); the engine isn't told (it has no such candidate). A row of
    /// the engine's removes its candidate, the engine told its place on the engine's page, not the row's.
    @Test func englishWordsAmongTheCandidatesAreRemovedToo() {
        let base = FakeEngine()
        base.dictionary["xiaomi"] = ["小米", "小蜜", "晓米"]
        let mixed = EnglishWordsEngine(base: base, dictionary: EnglishDictionary(["hello"]), words: ["Xiaomi"])
        let c = Composer(engine: mixed, actionKey: .enter)
        type("xiaomi", c)
        // Pinyin too: the word second.
        #expect(texts(c) == ["小米", "Xiaomi", "小蜜", "晓米"], "\(texts(c))")
        // The third row is the engine's second candidate.
        let row = c.deleteCandidate(index: 2)
        #expect(row.contains(.candidateRemoved("小蜜")) && base.deleted == [1] && commits(row).isEmpty, "\(base.deleted)")
        #expect(texts(c) == ["小米", "Xiaomi", "晓米"], "\(texts(c))")
        let word = c.deleteCandidate(index: 1)
        #expect(word.contains(.candidateRemoved("Xiaomi")) && base.deleted == [1], "the engine isn't told: \(base.deleted)")
        #expect(texts(c) == ["小米", "晓米"] && commits(word).isEmpty && c.engineState.isComposing && base.input == "xiaomi",
                "\(texts(c))")
        #expect(c.removedCandidates == ["小蜜", "Xiaomi"])
        _ = c.deleteCandidate(index: 0)
        #expect(base.deleted == [1, 0] && texts(c) == ["晓米"], "\(base.deleted) \(texts(c))")
        // Spelled otherwise, by the user later: not shown either.
        mixed.words = ["xiaomi", "XIAOMI"]
        _ = c.handleKeyDown(escKey)
        type("xiaomi", c)
        #expect(texts(c) == ["晓米"], "\(texts(c))")

        // ⌃⌦ on the word (highlighted first when it is all the letters and no pinyin): it goes; on the engine's row under
        // it, that candidate.
        let other = FakeEngine()
        other.dictionary["bedrock"] = ["被的rock", "北的rock"]
        let d = Composer(engine: EnglishWordsEngine(base: other, dictionary: EnglishDictionary(["hello"]), words: ["Bedrock"]),
                         actionKey: .enter)
        type("bedrock", d)
        #expect(texts(d) == ["Bedrock", "被的rock", "北的rock"] && d.engineState.highlighted == 0, "\(texts(d))")
        let first = d.handleKeyDown(DeleteKeys.controlForwardDelete)
        #expect(first.handled && first.effects.contains(.candidateRemoved("Bedrock")) && other.deleted.isEmpty, "\(first.effects)")
        #expect(texts(d) == ["被的rock", "北的rock"] && d.engineState.highlighted == 0 && d.engineState.isComposing, "\(texts(d))")
        _ = d.handleKeyDown(downKey)
        #expect(d.engineState.highlighted == 1, "\(d.engineState.highlighted)")
        let second = d.handleKeyDown(DeleteKeys.controlForwardDelete)
        #expect(second.handled && second.effects.contains(.candidateRemoved("北的rock")) && other.deleted == [1],
                "the engine's second: \(other.deleted)")
        #expect(texts(d) == ["被的rock"] && commits(d.handleKeyDown(spaceKey)) == ["被的rock"])
    }

    // MARK: - Rows that aren't the engine's

    @Test func levelTwosResultsAreNone() {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        type("@imp", c)
        _ = c.handleKeyDown(tab)
        type("nihao", c)
        _ = c.handleKeyDown(spaceKey)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("Hi."), CandidateLine("Hello.")]), isFinal: true, id: 1)
        let choices = c.choices.map(\.text)
        #expect(choices.count == 3 && c.isLevelTwo, "\(choices)")
        for index in choices.indices { #expect(c.deleteCandidate(index: index).isEmpty) }
        #expect(c.choices.map(\.text) == choices && c.isLevelTwo)
        _ = c.handleKeyDown(DeleteKeys.controlForwardDelete)
        #expect(engine.deleted.isEmpty && c.removedCandidates.isEmpty, "\(engine.deleted)")
    }

    @Test func theCommandListIsNone() {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        type("@", c)
        #expect(c.paletteQuery != nil)
        let (draft, visible) = (c.draft, c.paletteVisible.map(\.name))
        #expect(c.deleteCandidate(index: 1).isEmpty)
        #expect(c.draft == draft && c.paletteVisible.map(\.name) == visible)
        _ = c.handleKeyDown(DeleteKeys.controlForwardDelete)
        #expect(engine.deleted.isEmpty, "\(engine.deleted)")
    }

    @Test func nothingWhileListening() {
        let engine = FakeEngine()
        let c = Composer(engine: engine, voiceEnabled: true, actionKey: .enter)  // as if voice input were on
        type("@imp", c)
        _ = c.handleKeyDown(tab)
        type("nihao", c)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.rightOption, modifiers: [.option, .rightOption], timestamp: 0)
        _ = c.voiceHoldElapsed()
        #expect(c.voice != .off)
        #expect(c.deleteCandidate(index: 0).isEmpty && engine.deleted.isEmpty, "\(engine.deleted)")
    }
}

/// The same through a text field's session (`InputSession`, driven as the Mac's shell drives it: `FakeHost`): a
/// right-click is `SessionEvent.delete` with the row's index in the panel shown, mapped to the composer's (the row's
/// `choice`); ⌃⌦ is a key. Clipboard history's rows are none of the engine's, even over pinyin being typed.
@Suite(.serialized)
struct DeleteCandidateSessionTests {
    final class Settings: @unchecked Sendable {
        var config: Config
        init() {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
            config.setOrder([OutputLanguage.english, .chinese])
            config.claudeInBackground = false
        }
    }

    /// A session in a field that has the focus, on `engine`, its shell keeping clipboard history (`history`, newest first).
    func host(_ engine: FakeEngine, history: [String] = []) -> FakeHost {
        let settings = Settings()
        var services = SessionServices(loadSettings: { settings.config })
        services.levelOne = { .engine(engine) }
        services.programInstalled = { _ in true }
        let host = FakeHost(services: services)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        host.clipboardNow = now
        host.clipboardHistory = history.enumerated().map { ClipboardHistoryItem(text: $1, copiedAt: now - 300 - Double($0) * 60) }
        host.clipboard = history.first.map(ClipboardContent.text) ?? .none
        host.keepClipboardHistory()
        host.focus()
        return host
    }

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    func texts(_ host: FakeHost) -> [String] { host.panel?.rows.map(\.text) ?? [] }

    @Test func aRightClickedRowsCandidateIsRemoved() async {
        await inEnglish {
            let engine = FakeEngine()
            let host = host(engine)
            host.type("nihao")
            #expect(texts(host) == ["你好", "拟好"] && host.panel?.rows.map(\.choice) == [0, 1], "\(texts(host))")
            host.send(.delete(1))
            #expect(engine.deleted == [1], "\(engine.deleted)")
            #expect(host.document.isEmpty && host.marked == "nihao", "nothing committed (\(host.document)), the letters marked (\(host.marked))")
            #expect(texts(host) == ["你好"] && host.panel?.rows.map(\.choice) == [0], "the panel laid out again without it: \(texts(host))")
            // Past the rows: nothing.
            host.send(.delete(1))
            host.send(.delete(5))
            #expect(engine.deleted == [1] && host.document.isEmpty && host.marked == "nihao")
            // A click still picks.
            host.send(.pick(0))
            #expect(host.document == "你好" && host.marked.isEmpty, "\(host.document)")
            // Never again.
            host.type("nihao")
            #expect(texts(host) == ["你好"], "\(texts(host))")
            host.send(.delete(0))
            #expect(engine.deleted == [1, 0] && host.document == "你好" && host.marked == "nihao", "\(engine.deleted)")
        }
    }

    @Test func controlForwardDeleteIsTakenWhileComposing() async {
        await inEnglish {
            let engine = FakeEngine()
            let host = host(engine)
            #expect(!host.press(DeleteKeys.controlForwardDelete), "nothing composed: the app's")
            host.type("nihao")
            // The candidates in a row (the settings' default): → moves the highlight.
            host.press(host.composer.horizontalCandidates ? FakeHost.right : FakeHost.down)
            #expect(host.composer.engineState.highlighted == 1 && host.panel?.highlighted == 1)
            #expect(host.press(DeleteKeys.controlForwardDelete), "taken: the app never has it")
            #expect(engine.deleted == [1] && host.document.isEmpty && host.marked == "nihao", "\(engine.deleted) \(host.document)")
            #expect(texts(host) == ["你好"] && host.panel?.highlighted == 0, "\(texts(host))")
            // Plain ⌦ is no delete.
            host.press(DeleteKeys.forwardDelete)
            #expect(engine.deleted == [1] && texts(host) == ["你好"])
        }
    }

    @Test func nothingWhenNotComposing() async {
        await inEnglish {
            let engine = FakeEngine()
            let host = host(engine)
            host.send(.delete(0))
            host.type("nihao")
            host.press(FakeHost.space)
            #expect(host.document == "你好" && host.marked.isEmpty)
            host.send(.delete(0))
            #expect(!host.press(DeleteKeys.controlForwardDelete))
            #expect(engine.deleted.isEmpty && host.document == "你好", "\(engine.deleted)")
        }
    }

    /// Clipboard history (⌃V in a command, over the pinyin of its text being typed): a right-click on its rows deletes
    /// none of the engine's candidates, and the history stays up.
    @Test func clipboardHistorysRowsAreNone() async {
        await inEnglish {
            let engine = FakeEngine()
            let host = host(engine, history: ["gamma", "beta", "alpha"])
            host.press(FakeHost.at)
            host.type("i")
            host.press(FakeHost.tab)
            host.type("nihao")
            #expect(host.composer.engineState.isComposing && host.composer.draftCommand != nil)
            host.press(FakeHost.controlV)
            #expect(texts(host) == ["gamma", "beta", "alpha"], "clipboard history: \(texts(host))")
            for row in 0..<3 { host.send(.delete(row)) }
            #expect(engine.deleted.isEmpty, "\(engine.deleted)")
            #expect(texts(host) == ["gamma", "beta", "alpha"] && host.session.clipboardShown, "\(texts(host))")
        }
    }

    /// ⌃⌦ over clipboard history (⌃V in a command, over the pinyin of its text being typed) only hides it: the key is
    /// taken (the app never has it) and the engine's highlighted candidate, which the history hid, isn't deleted. With
    /// the history gone and the pinyin still typed, ⌃⌦ deletes the highlighted one.
    @Test func controlForwardDeleteOverClipboardHistoryDeletesNothing() async {
        await inEnglish {
            let engine = FakeEngine()
            let host = host(engine, history: ["gamma", "beta", "alpha"])
            host.press(FakeHost.at)
            host.type("i")
            host.press(FakeHost.tab)
            host.type("nihao")
            #expect(host.composer.engineState.isComposing && host.composer.draftCommand != nil)
            let (draft, highlighted) = (host.composer.draft, host.composer.engineState.highlighted)
            host.press(FakeHost.controlV)
            #expect(texts(host) == ["gamma", "beta", "alpha"] && host.session.clipboardShown, "clipboard history: \(texts(host))")
            #expect(host.press(DeleteKeys.controlForwardDelete), "taken: the app never has it")
            #expect(!host.session.clipboardShown && !texts(host).contains("gamma"), "the history hidden: \(texts(host))")
            #expect(engine.deleted.isEmpty, "no candidate deleted: \(engine.deleted)")
            #expect(host.composer.engineState.isComposing && engine.input == "nihao" && host.composer.draft == draft,
                    "still composing: \(engine.input) \(host.composer.draft)")
            #expect(host.document.isEmpty, "nothing put in: \(host.document)")
            // The history gone: ⌃⌦ deletes the highlighted candidate, once.
            #expect(host.composer.engineState.highlighted == highlighted)
            #expect(host.press(DeleteKeys.controlForwardDelete), "taken")
            #expect(engine.deleted == [highlighted], "the highlighted one: \(engine.deleted)")
            #expect(host.composer.engineState.isComposing && engine.input == "nihao" && host.document.isEmpty)
        }
    }
}

/// Suggestions' rows (a GitHub issue's, as "#7" is typed) are none of the engine's: a right-click does nothing, and ⌃⌦
/// with nothing composed is the app's.
@Suite(.serialized, SuggestionsOneAtATime())
struct DeleteCandidateSuggestionsTests {
    @Test func suggestionsRowsAreNone() async throws {
        try await withInterfaceLanguage("en") {
            let world = SuggestionsWorld()
            try world.github()
            let engine = FakeEngine()
            let field = world.field(engine: engine)
            field.type("#7")
            let issues = ["#7001", "#7002", "#7090", "#7100", "#789"]
            #expect(field.waitForIssues(issues), "\(field.issuesShown)")
            for row in 0..<issues.count { field.host.send(.delete(row)) }
            #expect(engine.deleted.isEmpty && field.document == "#7", "\(engine.deleted) \(field.document)")
            #expect(field.issuesShown == issues, "the rows stay: \(field.issuesShown)")
            #expect(!field.press(DeleteKeys.controlForwardDelete), "the app's")
            #expect(engine.deleted.isEmpty)
        }
    }
}

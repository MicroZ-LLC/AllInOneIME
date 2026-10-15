import Foundation
import Testing
@testable import AllInOneIMECore

/// The recent `@question`s as kept: newest first, five at most, the same question once, matched by what's typed.
struct QuestionHistoryTests {
    func entry(_ question: String, _ answer: String = "answer", minute: Double = 0) -> QuestionHistory.Entry {
        QuestionHistory.Entry(question: question, answer: answer, date: Date(timeIntervalSince1970: 1_800_000_000 + minute * 60))
    }

    @Test func newestFirstAtMostFiveTheSameQuestionOnce() {
        var history = QuestionHistory()
        for n in 1...6 { history.record(entry("q\(n)", minute: Double(n))) }
        #expect(history.entries.map(\.question) == ["q6", "q5", "q4", "q3", "q2"])  // q1, the oldest, went
        history.record(entry("  q3 \n", "new answer", minute: 7))
        #expect(history.entries.map(\.question) == ["q3", "q6", "q5", "q4", "q2"] && history.entries[0].answer == "new answer")
        history.record(entry("   ", "no question"))
        history.record(entry("no answer", ""))
        #expect(history.entries.count == 5 && history.entries[0].question == "q3")
        #expect(QuestionHistory(entries: (1...8).map { entry("x\($0)") }).entries.count == QuestionHistory.limit)
    }

    @Test func matchesAnywhereInAnyCaseAndWidthCJKToo() {
        #expect(QuestionHistory.matches("What is Quantum computing?", "QUANTUM"))
        #expect(QuestionHistory.matches("What is Quantum computing?", "comp what"))  // every word, in any order
        #expect(!QuestionHistory.matches("What is Quantum computing?", "quantum biology"))
        #expect(QuestionHistory.matches("量子计算是什么", "计算"))
        #expect(QuestionHistory.matches("什么是 AI 芯片", "AI芯片"))  // no spaces between words in Chinese
        #expect(QuestionHistory.matches("ＡＩ是什么", "ai"))  // full-width letters
        #expect(QuestionHistory.matches("Café au lait", "cafe"))
        #expect(QuestionHistory.matches("anything", "  "))
        let history = QuestionHistory(entries: [entry("量子计算是什么"), entry("What is AI"), entry("AI 芯片")])
        #expect(history.matching("ai").map(\.question) == ["What is AI", "AI 芯片"])
        #expect(history.matching("").count == 3 && history.matching("nothing").isEmpty)
    }

    @Test func keptInAFileOnlyTheUserReads() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("qhistory-\(UUID().uuidString)/AllInOneIME")
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let url = folder.appendingPathComponent("recent-questions.json")
        #expect(QuestionHistory.load(from: url).entries.isEmpty)  // none yet
        let history = QuestionHistory(entries: [entry("你好吗", "很好\n第二行", minute: 2), entry("why", minute: 1)])
        try history.write(to: url)  // the folder is made
        #expect(QuestionHistory.load(from: url) == history)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        // Cleared: the file goes.
        try QuestionHistory().write(to: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try QuestionHistory().write(to: url)  // and nothing to delete is no error
        // A file that isn't one reads as none; one with more than five keeps five.
        try Data("not json".utf8).write(to: url)
        #expect(QuestionHistory.load(from: url).entries.isEmpty)
        let many = (1...7).map { #"{"question":"q\#($0)","answer":"a","date":"2026-10-14T10:00:00Z"}"# }.joined(separator: ",")
        try Data(#"{"entries":[\#(many)]}"#.utf8).write(to: url)
        #expect(QuestionHistory.load(from: url).entries.map(\.question) == ["q1", "q2", "q3", "q4", "q5"])
    }

    @Test func theSameQuestionInAnotherCaseOrSpacingIsOneEntryTheNewestWording() {
        var history = QuestionHistory()
        history.record(entry("What is Rust", "old", minute: 1))
        history.record(entry("why", minute: 2))
        history.record(entry("  what   IS\nrust ", "new", minute: 3))
        #expect(history.entries.map(\.question) == ["what   IS\nrust", "why"] && history.entries[0].answer == "new")
        #expect(QuestionHistory.key(" What  is\trust\n") == "what is rust")
        #expect(QuestionHistory.key("whatis rust") != QuestionHistory.key("what is rust"))  // a space missing is another question
        // A hand-edited file with them: one, the newest, first.
        let edited = QuestionHistory(entries: [entry("why", minute: 2), entry("What is Rust", "older", minute: 1),
                                               entry("what is rust ", "newest", minute: 5), entry("WHAT IS RUST", "oldest", minute: 0)])
        #expect(edited.entries.map(\.answer) == ["newest", "answer"] && edited.entries[0].question == "what is rust ")
    }

    @Test func aFileReadableByOthersIsReplacedNeverWidened() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("qhistory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("recent-questions.json")
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int
        try QuestionHistory(entries: [entry("secret question")]).write(to: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        #expect(attributes[.systemFileNumber] as? Int != before)  // a new file renamed into place, not the old one rewritten
        #expect(QuestionHistory.load(from: url).entries.map(\.question) == ["secret question"])
        // Written again: still 0600, and no temporary file left beside it.
        try QuestionHistory(entries: [entry("another")]).write(to: url)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["recent-questions.json"])
    }

    @Test func theSettingIsOnByDefaultAndKept() throws {
        #expect(Config.default.rememberQuestions)
        let old = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(old.rememberQuestions)  // a file from before the setting
        var config = Config.default
        config.rememberQuestions = false
        let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(!back.rememberQuestions)
    }
}

extension ConverterTests {
    /// A recent question asked again (R) gets a fresh answer, not the one kept from the last time it was asked.
    @Test func aFreshAnswerIsAskedPastTheCache() async throws {
        let region = "us-test-qh"
        StubURLProtocol.register(host: host(region), .init(
            status: 200, headers: ["Content-Type": "application/vnd.amazon.eventstream"],
            chunks: chunks(try fixture("bedrock-converse-stream"), size: 64)))
        let converter = makeConverter(region: region)
        let first = try await collect(converter.generate(.question, input: "why is the sky blue"))
        #expect(first.last?.fromCache == false && first.last?.isFinal == true)
        let again = try await collect(converter.generate(.question, input: "why is the sky blue"))
        #expect(again.last?.fromCache == true)
        let fresh = try await collect(converter.generate(.question, input: "why is the sky blue", fresh: true))
        #expect(fresh.last?.fromCache == false && fresh.last?.result == first.last?.result)
    }
}

/// `@question` lists the recent questions: filter by typing, pick one to see its saved answer (nothing is asked), R asks
/// it again; a new question is kept with its answer, five at most, never during secure input or on a selection.
extension ComposerTests {
    var savedQuestions: QuestionHistory {
        var history = QuestionHistory()
        history.record(QuestionHistory.Entry(question: "what is rust", answer: "A language.", date: Date(timeIntervalSince1970: 1)))
        history.record(QuestionHistory.Entry(question: "你好怎么说", answer: "Hello.", date: Date(timeIntervalSince1970: 2)))
        history.record(QuestionHistory.Entry(question: "What is Swift", answer: "Also a language.", date: Date(timeIntervalSince1970: 3)))
        return history
    }

    /// "@question " picked from the list (Return as the action key), the recent questions set.
    func questionDraft(english: Bool = true, history: QuestionHistory? = nil) -> Composer {
        let (c, _) = composer(key: .enter)
        if english { c.setInputMode(.english) }
        c.questionHistory = history ?? savedQuestions
        _ = c.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        type("q", c)
        _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        #expect(c.draft == "@question ")
        return c
    }

    func requests(_ effects: [Composer.Effect]) -> [Composer.Effect] {
        effects.filter {
            switch $0 {
            case .startCommand, .startConversion, .startPlan, .reask: return true
            default: return false
            }
        }
    }

    func remembered(_ effects: [Composer.Effect]) -> [QuestionHistory.Entry] {
        effects.compactMap { if case let .rememberQuestion(entry) = $0 { return entry } else { return nil } }
    }

    func answer(_ text: String) -> ConversionResult { ConversionResult(versions: [CandidateLine(text)]) }

    @Test func nothingTypedListsTheRecentQuestionsNewestFirst() {
        let c = questionDraft()
        #expect(c.questionQuery == "" && c.questionMatches.map(\.question) == ["What is Swift", "你好怎么说", "what is rust"])
        #expect(c.questionDigitsPick && c.questionHighlight == nil)
        #expect(c.wantsPanel)
        // None kept, or the setting off: no list, as before.
        #expect(questionDraft(history: QuestionHistory()).questionMatches.isEmpty)
        let off = questionDraft()
        off.remembersQuestions = false
        #expect(off.questionQuery == nil && off.questionMatches.isEmpty)
        // Another command lists nothing.
        let (other, _) = composer(key: .enter)
        other.questionHistory = savedQuestions
        _ = other.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        type("i", other)
        _ = other.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        #expect(other.draft == "@improve " && other.questionMatches.isEmpty)
    }

    @Test func typingFiltersTheListAnywhereInAnyCase() {
        let c = questionDraft()
        type("IS", c)
        #expect(c.questionMatches.map(\.question) == ["What is Swift", "what is rust"] && !c.questionDigitsPick)
        type(" ru", c)
        #expect(c.questionMatches.map(\.question) == ["what is rust"])
        // Digits in the text are text: "2" doesn't pick the second.
        type("2", c)
        #expect(c.draft == "@question IS ru2" && c.questionMatches.isEmpty && !c.isLevelTwo)
        // Chinese typed as pinyin: the list follows the words picked.
        let z = questionDraft(english: false)
        type("nihao", z)
        #expect(z.questionMatches.isEmpty)  // pinyin being typed: its candidates show
        _ = z.handleKeyDown(spaceKey)
        #expect(z.draft == "@question 你好" && z.questionMatches.map(\.question) == ["你好怎么说"])
    }

    @Test func aDigitShowsTheSavedAnswerWithoutAsking() {
        let c = questionDraft()
        let effects = c.handleKeyDown(k("2")).effects
        #expect(requests(effects).isEmpty && remembered(effects).isEmpty)
        #expect(c.phase == .choosing && c.showsSavedAnswer && c.activeCommand == .question)
        #expect(c.choices.map(\.text) == ["你好怎么说", "Hello."] && c.highlighted == 1)
        #expect(c.markedText == "question › 你好怎么说" && c.savedAnswerDate == Date(timeIntervalSince1970: 2))
        // ⌘C copies it, ⏎ inserts it, as any answer.
        #expect(c.handleKeyDown(k("c", mods: .command)).effects.first == .copy("Hello."))
        #expect(commits(c.handleKeyDown(enterKey)) == ["Hello."] && c.phase == .idle && !c.showsSavedAnswer)
        #expect(c.questionHistory == savedQuestions)  // shown, not asked: the order stays
    }

    @Test func arrowsPickThenTheActionKeyShowsItAndEscGoesBack() {
        let c = questionDraft()
        _ = c.handleKeyDown(downKey)
        _ = c.handleKeyDown(downKey)
        #expect(c.questionHighlight == 1)
        _ = c.handleKeyDown(upKey)
        _ = c.handleKeyDown(upKey)
        #expect(c.questionHighlight == 2)  // round from the first to the last
        let shown = c.handleKeyDown(enterKey).effects
        #expect(requests(shown).isEmpty && c.showsSavedAnswer && c.choices.last?.text == "A language.")
        // Esc: back to the list it was picked from, still on it.
        _ = c.handleKeyDown(escKey)
        #expect(c.phase == .drafting && c.draft == "@question " && c.questionHighlight == 2 && !c.showsSavedAnswer)
        // Typing changes the text: nothing is picked, and ⏎ asks what's typed, even with questions that match.
        type("what", c)
        #expect(c.questionHighlight == nil && c.questionMatches.count == 2)
        #expect(requests(c.handleKeyDown(enterKey).effects) == [.startCommand(.question, input: "what", id: 1)])
        // ↑ goes to the last.
        let d = questionDraft()
        _ = d.handleKeyDown(upKey)
        #expect(d.questionHighlight == 2)
        // Typing on a saved answer goes back to the list and types there.
        _ = d.handleKeyDown(enterKey)
        _ = d.handleKeyDown(k("s"))
        #expect(d.draft == "@question s" && !d.isLevelTwo && d.questionMatches.map(\.question) == ["What is Swift", "what is rust"])
    }

    @Test func aClickShowsTheSavedAnswer() {
        let c = questionDraft()
        type("swift", c)
        let effects = c.choose(index: 0)
        #expect(requests(effects).isEmpty && c.showsSavedAnswer && c.choices.map(\.text) == ["What is Swift", "Also a language."])
        _ = c.handleKeyDown(escKey)
        #expect(c.draft == "@question swift")
    }

    @Test func rAsksItAgainForAFreshAnswerThatTakesItsPlace() {
        let c = questionDraft()
        c.now = { Date(timeIntervalSince1970: 100) }
        _ = c.handleKeyDown(k("3"))
        let again = c.handleKeyDown(k("r")).effects
        #expect(requests(again) == [.reask(.question, input: "what is rust", id: 1)])
        #expect(c.phase == .translating(id: 1) && !c.showsSavedAnswer && c.draft == "@question what is rust")
        let done = c.receive(answer("A systems language."), isFinal: true, id: 1)
        let entry = QuestionHistory.Entry(question: "what is rust", answer: "A systems language.", date: Date(timeIntervalSince1970: 100))
        #expect(remembered(done) == [entry])
        #expect(c.questionHistory.entries.map(\.question) == ["what is rust", "What is Swift", "你好怎么说"])
        #expect(c.questionHistory.entries.first == entry)
        // R in an answer just asked is a letter: back to the text, typed on.
        _ = c.handleKeyDown(k("r"))
        #expect(c.draft == "@question what is rustr" && !c.isLevelTwo)
        // ⇧R too; ⌘R isn't the input method's.
        let s = questionDraft()
        _ = s.handleKeyDown(k("1"))
        #expect(requests(s.handleKeyDown(k("R", mods: .shift)).effects).count == 1)
        let t = questionDraft()
        _ = t.handleKeyDown(k("1"))
        #expect(requests(t.handleKeyDown(k("r", mods: .command)).effects).isEmpty && t.showsSavedAnswer)
    }

    @Test func aNewQuestionIsAskedAndKept() {
        let c = questionDraft()
        c.now = { Date(timeIntervalSince1970: 50) }
        type("why is the sky blue", c)
        #expect(c.questionMatches.isEmpty)
        #expect(requests(c.handleKeyDown(enterKey).effects) == [.startCommand(.question, input: "why is the sky blue", id: 1)])
        #expect(remembered(c.receive(answer("Rayleigh"), isFinal: false, id: 1)).isEmpty)  // not while it streams
        let done = c.receive(answer("Rayleigh scattering."), isFinal: true, id: 1)
        #expect(remembered(done) == [QuestionHistory.Entry(question: "why is the sky blue", answer: "Rayleigh scattering.",
                                                           date: Date(timeIntervalSince1970: 50))])
        #expect(c.questionHistory.entries.first?.question == "why is the sky blue" && c.questionHistory.entries.count == 4)
        // A failure keeps nothing.
        let f = questionDraft()
        type("nothing back", f)
        _ = f.handleKeyDown(enterKey)
        #expect(remembered(f.receive(.empty, isFinal: true, id: 1)).isEmpty && f.questionHistory == savedQuestions)
        // Neither does another command's answer.
        let (other, _) = composer(key: .enter)
        other.setInputMode(.english)
        _ = other.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        type("i", other)
        _ = other.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        type("hi", other)
        _ = other.handleKeyDown(enterKey)
        #expect(remembered(other.receive(answer("Hi."), isFinal: true, id: 1)).isEmpty)
    }

    @Test func atMostFiveTheOldestGoes() {
        let c = questionDraft(history: QuestionHistory())
        for n in 1...6 {
            type("question \(n)", c)
            _ = c.handleKeyDown(enterKey)
            _ = c.receive(answer("answer \(n)"), isFinal: true, id: n)
            #expect(commits(c.handleKeyDown(enterKey)) == ["answer \(n)"])
            _ = c.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
            type("q", c)
            _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        }
        #expect(c.questionMatches.map(\.question) == ["question 6", "question 5", "question 4", "question 3", "question 2"])
    }

    @Test func nothingIsKeptDuringSecureInputOnASelectionOrWithTheSettingOff() {
        let secure = questionDraft()
        secure.secureInputActive = { true }
        type("secret", secure)
        _ = secure.handleKeyDown(enterKey)
        #expect(remembered(secure.receive(answer("No."), isFinal: true, id: 1)).isEmpty && secure.questionHistory == savedQuestions)
        let off = questionDraft()
        off.remembersQuestions = false
        type("forget me", off)
        _ = off.handleKeyDown(enterKey)
        #expect(remembered(off.receive(answer("Ok."), isFinal: true, id: 1)).isEmpty && off.questionHistory == savedQuestions)
        // On selected text: no list (the question is about it), and nothing kept.
        let (s, _) = composer(key: .enter)
        s.setInputMode(.english)
        s.questionHistory = savedQuestions
        s.readSelection = { Composer.Selection(text: "someone else's document") }
        _ = s.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        type("q", s)
        _ = s.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        #expect(s.draft == "@question " && s.questionMatches.isEmpty)
        type("summarize", s)
        _ = s.handleKeyDown(enterKey)
        #expect(remembered(s.receive(answer("A summary."), isFinal: true, id: 1)).isEmpty && s.questionHistory == savedQuestions)
    }

    /// A row picked in one draft isn't picked in the next, even with the same text.
    @Test func aPickIsForgottenWithItsDraft() {
        let c = questionDraft()
        type("rust", c)
        _ = c.handleKeyDown(downKey)
        _ = c.handleKeyDown(enterKey)
        #expect(c.showsSavedAnswer)
        #expect(commits(c.handleKeyDown(enterKey)) == ["A language."])  // inserted: the draft is done
        _ = c.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        type("q", c)
        _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        type("rust", c)
        #expect(c.questionHighlight == nil)
        #expect(requests(c.handleKeyDown(enterKey).effects) == [.startCommand(.question, input: "rust", id: 1)])
        // Esc twice (the answer, then the draft): the same.
        let d = questionDraft()
        type("rust", d)
        _ = d.handleKeyDown(downKey)
        _ = d.handleKeyDown(enterKey)
        _ = d.handleKeyDown(escKey)
        #expect(d.questionHighlight == 0)  // back in the same draft: still on it
        _ = d.handleKeyDown(escKey)
        #expect(d.draft.isEmpty)
        _ = d.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        type("q", d)
        _ = d.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        type("rust", d)
        #expect(d.questionHighlight == nil && !requests(d.handleKeyDown(enterKey).effects).isEmpty && !d.showsSavedAnswer)
        // ↑ on a new list starts from the last row, not one picked before; so after the app took the text.
        let e = questionDraft()
        _ = e.handleKeyDown(downKey)
        _ = e.handleKeyDown(escKey)
        _ = e.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        type("q", e)
        _ = e.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        #expect(e.questionHighlight == nil)
        _ = e.handleKeyDown(upKey)
        #expect(e.questionHighlight == 2)
        _ = e.appTookMarkedText()
        _ = e.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        type("q", e)
        _ = e.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        #expect(e.questionHighlight == nil)
    }

    @Test func clearedTheListIsGone() {
        let c = questionDraft()
        #expect(!c.questionMatches.isEmpty)
        c.questionHistory = QuestionHistory()  // what the controller sets after Clear in the settings
        #expect(c.questionMatches.isEmpty && !c.questionDigitsPick)
        // Digits are text again.
        _ = c.handleKeyDown(k("1"))
        #expect(c.draft == "@question 1" && !c.isLevelTwo)
    }
}

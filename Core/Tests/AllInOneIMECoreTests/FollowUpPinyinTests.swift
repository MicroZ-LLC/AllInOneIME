import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A follow-up typed in pinyin after results (an @question conversation's next question, a refine instruction after
/// @improve): the panel keeps its rows, the pinyin's candidates on a line of their own as one @'s (`PanelModel.candidates`);
/// digits and Space pick a candidate, ⏎ / ⇧⏎ / Esc as before, ↑↓ move among the results, a click picks a result.
@Suite(MacTerms())
struct FollowUpPinyinTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    let en = PanelPresenter(config: .default, language: "en")
    let zh = PanelPresenter(config: .default, language: "zh-Hans")

    func type(_ s: String, _ c: Composer) {
        for ch in s { _ = c.handleKeyDown(ch == " " ? spaceKey : k(String(ch))) }
    }

    func toChinese(_ c: Composer, at time: TimeInterval = 1) {
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: time)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: time + 0.1)
        #expect(c.inputLanguage == .chinese)
    }

    func started(_ effects: [Composer.Effect]) -> (Refinement, Int)? {
        effects.lazy.compactMap { if case let .startRefine(r, id) = $0 { return (r, id) } else { return nil } }.first
    }

    func answer(_ text: String) -> ConversionResult { ConversionResult(versions: [CandidateLine(text)]) }

    /// "@question what is rust" ⏎ and "who made it" ⏎, both answered: two rounds, the latest selected; Chinese input on.
    func conversation(rounds: Int = 5, horizontal: Bool = false) throws -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.remembersQuestions = false
        c.questionRounds = rounds
        c.horizontalCandidates = horizontal
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("question", c)
        _ = c.handleKeyDown(tab)
        type("what is rust", c)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(answer("A language."), isFinal: true, id: 1)
        type("who made it", c)
        let run = try #require(started(c.handleKeyDown(enterKey).effects))
        _ = c.receive(answer("Graydon Hoare."), isFinal: true, id: run.1)
        try #require(c.chatRounds.count == 2 && c.canRefine)
        toChinese(c)
        return c
    }

    /// "@improve hello" ⏎ with three versions in; Chinese input on.
    func improved() throws -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("i", c)
        _ = c.handleKeyDown(tab)
        type("hello", c)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("Hi."), CandidateLine("Howdy."), CandidateLine("Hey.")]), isFinal: true, id: 1)
        try #require(c.canRefine && c.choices.count == 4, "\(c.choices.map(\.text))")
        toChinese(c)
        return c
    }

    // MARK: - A conversation

    @Test func theConversationStaysWithThePinyinOnALineOfItsOwn() throws {
        let c = try conversation()
        let shown = (en: en.model(for: c), zh: zh.model(for: c))
        type("nihao", c)
        try #require(c.refineIsComposing)
        for (presenter, shown) in [(en, shown.en), (zh, shown.zh)] {
            let model = presenter.model(for: c)
            #expect(model.transcript && !model.horizontal && model.rows == shown.rows && model.highlighted == 3)
            #expect(model.candidates == "1 你好   2 拟好" && model.status == .none && model.handoff == nil)
        }
        let before = shown.en
        let model = en.model(for: c)
        #expect(model.input == PanelModel.Input(prompt: "question 3/5 › ", text: "nihao", caret: 5))
        #expect(model.candidatesHint == PanelModel.Hint("Space", "picks a word"))
        // The footer says it all; its keys leave Space to the candidates' line.
        #expect(model.footer == "Space picks · ⏎ ask · ⇧⏎ insert the answer · Esc clear the pinyin")
        #expect(model.footerHints.hints == [PanelModel.Hint("⏎", "ask"), PanelModel.Hint("⇧⏎", "insert the answer")])
        #expect(zh.model(for: c).footerHints.hints == [PanelModel.Hint("⏎", "追问"), PanelModel.Hint("⇧⏎", "上屏答案")])
        // A digit picks a candidate into the line, not an answer; the line goes on.
        _ = c.handleKeyDown(k("2"))
        #expect(c.refineText == "拟好" && !c.refineIsComposing && c.isLevelTwo)
        let picked = en.model(for: c)
        #expect(picked.rows == before.rows && picked.candidates == nil && picked.candidatesHint == nil)
        #expect(picked.footer == "⏎ ask · ⇧⏎ insert · 1–5 pick · ⌘C copy · Esc back")
    }

    /// Before any answer, pinyin in the question is the draft's: its candidates are the rows, as in any command's text.
    @Test func noConversationYetTheCandidatesAreTheRows() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.remembersQuestions = false
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("question", c)
        _ = c.handleKeyDown(tab)
        toChinese(c)
        type("nihao", c)
        #expect(!c.isQuestionChat && !c.refineIsComposing && c.engineState.isComposing)
        let model = en.model(for: c)
        #expect(model.rows.map(\.text) == ["你好", "拟好"] && model.candidates == nil && model.candidatesHint == nil && !model.transcript)
    }

    @Test func shiftReturnWhileComposingInsertsTheAnswerSelectedAndDropsThePinyin() throws {
        let c = try conversation()
        type("nihao", c)
        // ↑ selects the first answer; the pinyin stays.
        _ = c.handleKeyDown(upKey)
        #expect(c.refineIsComposing && c.refineLine == "nihao" && en.model(for: c).highlighted == 1)
        let effects = c.handleKeyDown(shiftEnterKey).effects
        #expect(commits(effects) == ["A language."] && started(effects) == nil)
        #expect(!c.engineState.isComposing && c.phase == .idle)
    }

    @Test func returnWhileComposingConvertsAndAsks() throws {
        let c = try conversation()
        type("nihao", c)
        let run = try #require(started(c.handleKeyDown(enterKey).effects))
        #expect(run.0.turns.last?.instruction == "你好" && !c.engineState.isComposing)
        // While it's answered the conversation shows, the next question typed meanwhile on its line.
        let answering = en.model(for: c)
        #expect(answering.transcript && answering.status == .loading("Answering…") && answering.candidates == nil)
        type("wo", c)
        let meanwhile = en.model(for: c)
        #expect(c.refineIsComposing && meanwhile.transcript && meanwhile.rows == answering.rows && meanwhile.status == answering.status)
        #expect(meanwhile.candidates == "1 我   2 窝" && meanwhile.input?.text == "wo")
    }

    @Test func escWhileComposingClearsOnlyThePinyinThenGoesBackARound() throws {
        let c = try conversation()
        let before = en.model(for: c)
        type("nihao", c)
        _ = c.handleKeyDown(escKey)
        #expect(!c.engineState.isComposing && c.refineLine == nil && c.chatRounds.count == 2)
        let cleared = en.model(for: c)
        #expect(cleared == before, "the conversation as it was before the pinyin")
        // Pinyin after words picked: Esc clears the pinyin, the words stay.
        type("wo", c)
        _ = c.handleKeyDown(spaceKey)
        type("nihao", c)
        _ = c.handleKeyDown(escKey)
        #expect(c.refineText == "我" && c.refineLine == "我" && en.model(for: c).candidates == nil)
        _ = c.handleKeyDown(escKey)
        #expect(c.refineLine == nil && c.chatRounds.count == 2)
        // The next Esc goes back a round, as before.
        _ = c.handleKeyDown(escKey)
        #expect(c.chatRounds.count == 1 && c.isQuestionChat)
    }

    /// The candidates' layout (in a row or a column) is that of plain typing's candidates: here they are a line of their
    /// own either way, the conversation a column, ↑↓ moving among its answers and Space picking the first candidate.
    @Test(arguments: [false, true])
    func theCandidatesAreALineInEitherLayout(horizontal: Bool) throws {
        let c = try conversation(horizontal: horizontal)
        let before = en.model(for: c)
        type("nihao", c)
        let model = en.model(for: c)
        #expect(!model.horizontal && model.rows == before.rows && model.candidates == "1 你好   2 拟好")
        _ = c.handleKeyDown(upKey)
        #expect(c.highlighted == 0 && en.model(for: c).highlighted == 1 && c.refineLine == "nihao")
        _ = c.handleKeyDown(downKey)
        #expect(c.highlighted == 1 && en.model(for: c).highlighted == 3 && c.refineLine == "nihao")
        _ = c.handleKeyDown(spaceKey)
        #expect(c.refineText == "你好" && !c.refineIsComposing)
    }

    @Test func aClickedRowIsAnAnswerNotACandidate() throws {
        let c = try conversation()
        type("nihao", c)
        // A right-click on an answer removes no candidate.
        #expect(c.deleteClicked(1).isEmpty && c.removedCandidates.isEmpty && c.engineState.candidates.map(\.text) == ["你好", "拟好"])
        // A click on the first answer inserts it, the pinyin dropped with the line.
        let effects = c.pickClicked(0)
        #expect(commits(effects) == ["A language."] && !c.engineState.isComposing && c.phase == .idle)
    }

    @Test func atTheLastRoundTheHandoffStaysWithThePinyin() throws {
        let c = try conversation(rounds: 2)
        try #require(c.showsHandoff)
        type("nihao", c)
        let model = en.model(for: c)
        #expect(model.handoff != nil && model.input == PanelModel.Input(prompt: "then › ", text: "nihao", caret: 5))
        #expect(model.candidates == "1 你好   2 拟好" && model.footer.contains("continue, with what you typed"))
        #expect(!model.footer.contains("ask"))
    }

    // MARK: - A refine

    @Test func aRefinesResultsStayWhileItsPinyinIsComposed() throws {
        let c = try improved()
        let before = en.model(for: c)
        type("nihao", c)
        let model = en.model(for: c)
        #expect(model.rows == before.rows && model.highlighted == before.highlighted && !model.horizontal)
        #expect(model.input == PanelModel.Input(prompt: "refine › ", text: "nihao", caret: 5) && model.candidates == "1 你好   2 拟好")
        #expect(model.footer == "Space picks · ⇧⏎ refine · ⏎ insert · Esc clear the pinyin")
        #expect(model.footerHints.hints == [PanelModel.Hint("⇧⏎", "refine"), PanelModel.Hint("⏎", "insert")])
        // ↓ moves among the results; ⏎ inserts the one selected, the pinyin dropped.
        _ = c.handleKeyDown(downKey)
        #expect(en.model(for: c).highlighted == (before.highlighted ?? 0) + 1 && c.refineLine == "nihao")
        #expect(commits(c.handleKeyDown(enterKey).effects) == ["Howdy."] && !c.engineState.isComposing)
    }

    @Test func pinyinTypedWhileARefineRunsKeepsItsRows() throws {
        let c = try improved()
        type("wo", c)
        _ = c.handleKeyDown(spaceKey)
        let run = try #require(started(c.handleKeyDown(shiftEnterKey).effects))
        _ = c.receive(ConversionResult(versions: [CandidateLine("Hi!", isComplete: false)]), isFinal: false, id: run.1)
        let running = en.model(for: c)
        type("nihao", c)
        try #require(c.isRefining && c.refineIsComposing)
        let model = en.model(for: c)
        #expect(model.rows == running.rows && model.status == running.status && model.candidates == "1 你好   2 拟好")
        #expect(model.footerHints.hints == [PanelModel.Hint("⇧⏎", "refine"), PanelModel.Hint("⏎", "insert")])
    }

    // MARK: - Through a field's session

    private final class CannedModel: AppleModelBackend, @unchecked Sendable {
        let availability = AppleModelAvailability.available
        let contextSize = 4096
        let supportedLanguages: Set<String> = ["en", "zh"]

        func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(AppleModelSnapshot(text: "OK"))
                continuation.finish()
            }
        }
    }

    /// A click on a conversation's answer row while its next question's pinyin is composed inserts that answer (what
    /// the row shows), a right-click removes nothing.
    @Test func aClickInTheFieldsPanelPicksTheAnswer() async throws {
        try await withInterfaceLanguage("en") {
            var config = Config.default
            config.uiLanguage = "en"
            config.provider = .apple
            config.setOrder([Language.chinese, .english])
            let fixed = config
            let engine = FakeEngine()
            var services = SessionServices(converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: CannedModel()),
                                           loadSettings: { fixed })
            services.levelOne = { .engine(engine) }
            let host = FakeHost(services: services)
            host.focus()
            host.composer.setInputMode(.english)
            host.type("@q")
            host.press(FakeHost.tab)
            host.type("what is rust")
            host.press(FakeHost.enter)
            try #require(host.settle(timeout: 5) { host.composer.canRefine && host.composer.chatRounds.first?.answer == "OK" })
            host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: 100))
            host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: 100.1))
            host.type("nihao")
            try #require(host.composer.refineIsComposing && host.panel?.candidates != nil,
                         "\(host.composer.inputLanguage) \(host.composer.refineLine ?? "-")")
            host.send(.delete(1))
            #expect(host.composer.refineIsComposing && host.composer.removedCandidates.isEmpty)
            host.send(.pick(1))
            #expect(host.document == "OK" && !host.composer.isComposing && host.panel == nil)
        }
    }
}

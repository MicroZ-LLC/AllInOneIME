import AllInOneIMECore
import AppKit

/// Canned answers for the @question conversation's self-test, behind the on-device model's interface: nothing is sent
/// anywhere, and a small context makes a long conversation shortened (`QuestionChat.fit`).
final class CannedChatModel: AppleModelBackend, @unchecked Sendable {
    let contextSize: Int
    let answers: [String: String]
    private let lock = NSLock()
    private var _requests: [AppleModelRequest] = []
    var requests: [AppleModelRequest] { lock.withLock { _requests } }

    init(contextSize: Int = 4096, answers: [String: String]) {
        self.contextSize = contextSize
        self.answers = answers
    }

    var availability: AppleModelAvailability { .available }
    var supportedLanguages: Set<String> { ["en", "zh"] }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        lock.withLock { _requests.append(request) }
        let text = answers[request.prompt] ?? "An answer to: \(request.prompt)"
        return AsyncThrowingStream { continuation in
            continuation.yield(AppleModelSnapshot(text: text))
            continuation.finish()
        }
    }
}

extension SelfTest {
    /// An @question conversation through the controller, with canned answers (`CannedChatModel`): typing after the
    /// answer is the next question, ⇧⏎ asks it as user and assistant turns, the panel grows into 问/答 rows with the next
    /// question's line on top and its round, every answer can be picked (↑, ⌘C), Esc goes back a round, the third
    /// round (`questionRounds` 3 here) offers where to go on (⌘1 Claude Code, ⌘2 Claude on the web, ⌘4 copy; nothing
    /// is started or opened here), a long conversation is shortened for a small context and the panel scrolls within
    /// half the screen, and the thread is kept whole. Images: question-chat*.png, question-chat-handoff*.png.
    static func testQuestionChat(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        print("— @question: a conversation in the panel (canned answers)")
        let answers = [
            "what is rust": "Rust is a systems programming language focused on safety, speed and concurrency.",
            "who made it": "Graydon Hoare started it in 2006; Mozilla sponsored it from 2009.",
            "why is it safe": "Its ownership rules and borrow checker catch memory errors when the code is compiled, not when it runs.",
        ]
        let model = CannedChatModel(answers: answers)
        var started: [String] = [], opened: [String] = [], copied: [String] = []
        let saved = (converter: controller.converter, settings: settings, open: controller.openItem, copy: controller.copyText,
                     claude: controller.continueInClaudeCode)
        defer {
            controller.commitComposition(client)
            (controller.converter, settings, controller.openItem, controller.copyText, controller.continueInClaudeCode)
                = (saved.converter, saved.settings, saved.open, saved.copy, saved.claude)
            controller.applySettings()
            controller.composer.setInputMode(settings.defaultInput)
        }
        settings.provider = .apple
        settings.questionRounds = 3
        settings.rememberQuestions = true
        let fixed = settings
        controller.converter = Converter(loadConfig: { fixed }, appleModel: model)
        controller.openItem = { opened.append($0) }
        controller.copyText = { copied.append($0) }
        controller.continueInClaudeCode = { started.append($0) }
        controller.applySettings()
        controller.composer.setInputMode(.english)
        QuestionHistoryStore.clear()
        func ask(_ question: String) {
            _ = press(controller, client, "@", code: 0x13, flags: .shift)
            type("question", controller, client)
            _ = press(controller, client, "\t", code: VirtualKey.tab)
            type(question, controller, client)
            _ = enter(controller, client)
        }
        func followUp(_ question: String) -> Bool {
            type(question, controller, client)
            _ = shiftEnter(controller, client)
            return finishConversion(controller, "follow-up: \(question)")
        }
        func command(_ characters: String, code: UInt16) -> Bool {
            press(controller, client, characters, code: code, flags: .command)
        }

        ask("what is rust")
        guard finishConversion(controller, "@question, round 1") else { return }
        var panel = controller.panelModel()
        check(panel.transcript && panel.rows.map(\.text) == ["问：what is rust", "答：" + answers["what is rust"]!]
              && panel.rows.map(\.label) == ["", "1"] && panel.highlighted == 1,
              "round 1: the question and its answer, numbered (\(panel.rows.map(\.text)))")
        check(panel.input == "追问 2/3 › ▏" && panel.footer == "⇧⏎ 追问 · ⏎ 上屏 · 1–5 选 · ⌘C 复制 · Esc 返回",
              "the next question's line on top, with its round; the footer's keys (\(panel.input ?? "-") | \(panel.footer))")

        type("who made", controller, client)
        check(controller.panelModel().input == "追问 2/3 › who made▏" && controller.composer.phase == .choosing,
              "typing goes into the next question (\(controller.panelModel().input ?? "-"))")
        type(" it", controller, client)
        _ = shiftEnter(controller, client)
        check(controller.composer.isQuestionChat && controller.composer.chatRound == 2, "⇧⏎ asks it as round 2")
        guard finishConversion(controller, "@question, round 2") else { return }
        if let request = model.requests.last {
            check(request.examples.map(\.prompt) == ["what is rust"] && request.examples.map(\.response) == [answers["what is rust"]!]
                  && request.prompt == "who made it" && request.instructions == Prompt.commandRequest(.question, input: "", config: fixed).system.map(\.text).joined(separator: "\n\n"),
                  "round 2 is sent as turns: the first question and answer, then the new question, plainly")
        }
        panel = controller.panelModel()
        check(panel.rows.count == 4 && panel.rows[0].style == .original && panel.rows[1].style == .original
              && panel.rows[3].style == .translation && panel.highlighted == 3 && panel.rows[0].pickable == false,
              "the earlier round dimmed, the latest answer selected; questions aren't picked")
        readmeSnapshot("question-chat", controller, client, in: snapshotDirectory)

        // ↑ picks the earlier answer; ⌘C copies it.
        _ = press(controller, client, "", code: VirtualKey.up)
        _ = command("c", code: 0x08)
        check(controller.composer.highlighted == 0 && copied.last == answers["what is rust"], "↑ selects round 1's answer, ⌘C copies it")
        _ = press(controller, client, "", code: VirtualKey.down)

        // ⌘⏎ shows where it can go on, before the last round; Esc hides it.
        _ = command("\r", code: VirtualKey.returnKey)
        check(controller.composer.showsHandoff && (controller.panelModel().input ?? "").contains("⌘1 "), "⌘⏎ shows where to go on")
        _ = escape(controller, client)
        check(!controller.composer.showsHandoff && controller.composer.chatRound == 2, "Esc hides it again")

        // Round 3, the last here: the hand-off row in place of the next question.
        guard followUp("why is it safe") else { return }
        panel = controller.panelModel()
        let choices = controller.composer.handoffChoices
        check(controller.composer.showsHandoff && (panel.input ?? "").hasPrefix("已经聊了 3 轮：在 Claude 或别的 AI 里接着聊\n⌘1 ")
              && panel.footer.hasPrefix("⌘1–⌘\(choices.count) 接着聊"),
              "after round 3: where to go on (\(panel.input?.replacingOccurrences(of: "\n", with: " / ") ?? "-") | \(panel.footer))")
        readmeSnapshot("question-chat-handoff", controller, client, in: snapshotDirectory)
        let kept = QuestionHistoryStore.history.entries.first
        check(kept?.thread.map(\.question) == ["what is rust", "who made it", "why is it safe"] && kept?.question == "what is rust",
              "the whole thread is kept under its first question (\(kept?.thread.count ?? 0) rounds)")

        // ⌘ and the copy choice's number: the conversation on the clipboard, in Markdown; nothing inserted.
        if let copy = choices.firstIndex(of: .copy) {
            let inserted = client.inserted.count
            _ = command(String(copy + 1), code: keyCodes[Character(String(copy + 1))] ?? 0)
            check(copied.last?.hasPrefix("**Q:** what is rust\n\n**A:** Rust is") == true && copied.last?.contains("**Q:** why is it safe") == true
                  && !controller.composer.isComposing && client.inserted.count == inserted,
                  "⌘\(copy + 1) copies the conversation in Markdown, nothing inserted")
        }

        // Picked again from the recent questions: the rounds, to go on with (or hand over).
        _ = press(controller, client, "@", code: 0x13, flags: .shift)
        type("question", controller, client)
        _ = press(controller, client, "\t", code: VirtualKey.tab)
        type("1", controller, client)
        check(controller.composer.showsSavedAnswer && controller.composer.chatRounds.count == 3 && controller.composer.showsHandoff,
              "the saved thread shows its 3 rounds and where to go on")
        type("go deeper", controller, client)
        if choices.first == .claudeCode {
            _ = command("1", code: 0x12)
            check(started.count == 1 && started[0].hasPrefix("**Q:** what is rust") && started[0].hasSuffix("Let's continue this discussion.\n\ngo deeper"),
                  "⌘1 hands it to Claude Code with the follow-up as its first message (nothing started here)")
        } else {
            _ = command("1", code: 0x12)
            check(opened.last?.hasPrefix("https://claude.ai/new?q=") == true, "⌘1 opens Claude with the conversation (nothing opened here)")
        }

        // Esc goes back a round; ⏎ inserts the answer selected, dropping a half-typed question.
        ask("what is rust")
        guard finishConversion(controller, "@question, from the cache") else { return }
        guard followUp("who made it") else { return }
        _ = escape(controller, client)
        check(controller.composer.chatRound == 1, "Esc with nothing typed goes back a round")
        type("half typed", controller, client)
        _ = enter(controller, client)
        check(client.inserted.last == answers["what is rust"] && !controller.composer.isComposing, "⏎ inserts the selected answer, the half-typed question dropped")

        // A long conversation for a small context: shortened, and said so; the panel scrolls within half the screen.
        let long = String(repeating: "This answer goes on and on to fill the model's small context. ", count: 30)
        let small = CannedChatModel(contextSize: 1800, answers: ["one": long, "two": long, "three": long])
        controller.converter = Converter(loadConfig: { fixed }, appleModel: small)
        settings.questionRounds = 5
        controller.applySettings()
        ask("one")
        guard finishConversion(controller, "a long answer, round 1") else { return }
        guard followUp("two"), followUp("three") else { return }
        // (The hand-off's notice may still be up in its place for a moment.)
        _ = pump(timeout: 8) { (controller.panelModel().detail ?? "").contains("前面几轮已缩短") }
        check(controller.lastShortened && (controller.panelModel().detail ?? "").contains("前面几轮已缩短"),
              "earlier rounds shortened to fit, said in the footer (\(controller.panelModel().detail ?? "-"))")
        CandidatePanel.shared.show(controller.panelModel(), anchor: client.caretRect)
        let height = CandidatePanel.shared.frame.height
        let half = floor((CandidatePanel.screen(for: client.caretRect)?.visibleFrame.height ?? 900) / 2)
        check(height <= half + 1, "the panel grows up to half the screen, then scrolls (\(Int(height)) of \(Int(half)) points)")
        readmeSnapshot("question-chat-long", controller, client, in: snapshotDirectory)
        controller.commitComposition(client)
    }
}

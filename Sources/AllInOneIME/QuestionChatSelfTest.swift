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
    /// Settings → General → "Continue a conversation in" with an agent that isn't installed right now (Kiro CLI here): its
    /// entry is no chip, and an edit (a drag, a chip taken out) keeps it where it was in the file. "@agent's agent" is a
    /// chip by that agent's name, standing for its own entry; taken out, it takes that entry with it, and is offered to
    /// add again.
    static func testContinueListKeepsAgentsNotInstalled(snapshotDirectory: URL) {
        section("Continue a conversation in: an agent not installed keeps its place")
        let url = snapshotDirectory.appendingPathComponent("continue-config.json")
        defer {
            try? FileManager.default.removeItem(at: url)
            AgentAvailability.forget()
        }
        for (program, installed) in [("claude", true), ("gemini", true), ("kiro-cli", false)] {
            AgentAvailability.pretend(program, installed: installed)
        }
        var config = Config.default
        config.agent = .claude
        config.questionContinueIn = [.atAgent, .kiroCLI, .geminiCLI, .claudeCode, .chatgpt, .copy]
        try? config.write(to: url)
        let model = SettingsModel(configURL: url)
        let chips = model.continueChoices
        let names = chips.map { AllInOneIMEInputController.shortName($0, picked: model.config.agent) }
        check(chips == [.atAgent, .geminiCLI, .chatgpt, .copy] && names.first == tr("@agent 的 agent（Claude Code）", "@agent's agent (Claude Code)"),
              "the chips: @agent's agent by its name, standing for Claude Code's own; Kiro CLI not installed, no chip (\(names))")
        model.setContinueIn([.copy, .atAgent, .geminiCLI, .chatgpt])  // dragged
        let dragged = (try? Config.load(from: url))?.questionContinueIn ?? []
        check(dragged == [.copy, .kiroCLI, .atAgent, .claudeCode, .geminiCLI, .chatgpt],
              "a drag keeps Kiro CLI and Claude Code's own entry where they were (\(dragged.map(\.rawValue)))")
        model.removeContinueIn(.atAgent)
        let removed = (try? Config.load(from: url))?.questionContinueIn ?? []
        check(removed == [.copy, .kiroCLI, .geminiCLI, .chatgpt] && model.continueChoices == [.copy, .geminiCLI, .chatgpt]
              && model.missingContinueChoices.first == .atAgent,
              "taken out, @agent's agent takes Claude Code's own entry with it, and is offered to add (\(removed.map(\.rawValue)))")
    }

    /// An @question conversation through the controller, with canned answers (`CannedChatModel`): typing after the
    /// answer is the next question, ⇧⏎ asks it as user and assistant turns, the panel grows into 问/答 rows with the next
    /// question's line on top and its round, every answer can be picked (↑, ⌘C), Esc goes back a round, the third
    /// round (`questionRounds` 3 here) offers where to go on (⌘1 the agent `@agent` hands to, then the other agents
    /// "installed", the web and copying; nothing is started or opened here), a long conversation is shortened for a small
    /// context and the panel scrolls within half the screen, and the thread is kept whole. Images: question-chat*.png,
    /// question-chat-handoff*.png.
    static func testQuestionChat(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("@question: a conversation in the panel (canned answers)", needs: .composing)
        let answers = [
            "what is rust": "Rust is a systems programming language focused on safety, speed and concurrency.",
            "who made it": "Graydon Hoare started it in 2006; Mozilla sponsored it from 2009.",
            "why is it safe": "Its ownership rules and borrow checker catch memory errors when the code is compiled, not when it runs.",
        ]
        let model = CannedChatModel(answers: answers)
        var started: [String] = [], opened: [String] = [], copied: [String] = [], agentArguments: [[String]] = []
        let saved = (converter: controller.converter, settings: settings, open: controller.openItem, copy: controller.copyText,
                     agent: controller.continueInAgent, installed: controller.agentInstalled)
        defer {
            controller.commitComposition(client)
            (controller.converter, settings, controller.openItem, controller.copyText, controller.continueInAgent, controller.agentInstalled)
                = (saved.converter, saved.settings, saved.open, saved.copy, saved.agent, saved.installed)
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
        controller.continueInAgent = { agentArguments.append($0); started.append($1) }
        // The agents "installed" here, whatever is on this Mac: Claude Code and Gemini CLI, and the custom one once set.
        controller.agentInstalled = { kind, custom in kind == .claude || kind == .gemini || (kind == .custom && !custom.isEmpty) }
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
        check(panel.input == "追问 2/3 › ▏" && panel.footer == "⇧⏎ 追问 · ⏎ 上屏 · 1–3 选 · ⌘C 复制 · Esc 返回",
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
        check(choices == [.claudeCode, .geminiCLI, .claudeWeb, .chatgpt, .copy] && (panel.input ?? "").contains("⌘1 Claude Code")
              && (panel.input ?? "").contains("⌘2 Gemini CLI"),
              "the agent @agent hands to first, then the other agents installed, then the web and Copy (\(choices.map(\.rawValue)))")
        _ = pump(timeout: 3) { controller.panelModel().detail == nil }  // the image without round 2's "copied"
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
        _ = command("1", code: 0x12)
        check(started.count == 1 && started[0].hasPrefix("**Q:** what is rust") && started[0].hasSuffix("Let's continue this discussion.\n\ngo deeper"),
              "⌘1 hands it to Claude Code with the follow-up as its first message (nothing started here)")
        check(agentArguments == [["claude", "--"]], "…started as @agent starts it, `claude -- <conversation>` (\(agentArguments))")
        // Another agent picked for @agent (a custom one, `/bin/echo --`): it's ⌘1, by its name; the others follow, more
        // than 5 choices now, each started as @agent starts it.
        (settings.agent, settings.agentCommand) = (.custom, ["/bin/echo", "--"])
        controller.applySettings()
        controller.composer.setInputMode(.english)
        func recall() {
            _ = press(controller, client, "@", code: 0x13, flags: .shift)
            type("question", controller, client)
            _ = press(controller, client, "\t", code: VirtualKey.tab)
            type("1", controller, client)
        }
        recall()
        let six = controller.panelModel()
        _ = command("3", code: 0x14)
        check(controller.composer.handoffChoices.count == 6 && (six.input ?? "").contains("⌘1 echo") && (six.input ?? "").contains("⌘2 Claude Code")
              && (six.input ?? "").contains("⌘6 复制") && six.footer.hasPrefix("⌘1–⌘6 接着聊") && agentArguments.last == ["gemini", "-i"],
              "another agent picked: ⌘1 is it, the others after it, ⌘3 starts Gemini CLI as `gemini -i` "
              + "(\(six.input?.replacingOccurrences(of: "\n", with: " / ") ?? "-") | \(six.footer) | \(agentArguments.last ?? []))")
        recall()
        _ = command("1", code: 0x12)
        check(agentArguments.last == ["/bin/echo", "--"] && started.last?.hasSuffix("Let's continue this discussion.") == true,
              "…and ⌘1 gives the custom agent the conversation as its last argument (\(agentArguments.last ?? []))")
        // A configured list with "@agent's agent" follows the agent picked: the custom one here, in its place.
        settings.questionContinueIn = [.chatgpt, .atAgent, .copy]
        controller.applySettings()
        check(controller.composer.handoffChoices == [.chatgpt, .customAgent, .copy],
              "a list with @agent's agent offers the agent picked in its place (\(controller.composer.handoffChoices.map(\.rawValue)))")
        settings.questionContinueIn = nil
        (settings.agent, settings.agentCommand) = (.claude, [])
        controller.applySettings()
        controller.composer.setInputMode(.english)

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
        testChatScroll(controller.panelModel(), anchor: client.caretRect)
        controller.commitComposition(client)
    }

    /// The wheel scrolls a conversation taller than the panel: while it's scrolled up, an answer coming in leaves the
    /// rows where they are; scrolled back to the bottom, they follow the answer's end again.
    static func testChatScroll(_ model: CandidateView.Model, anchor: NSRect) {
        let panel = CandidatePanel.shared
        var streaming = model
        func comeIn(_ text: String) {
            streaming.rows[streaming.rows.count - 1].text += text
            panel.show(streaming, anchor: anchor)
        }
        func wheel(_ points: Int32) {
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: points, wheel2: 0,
                                      wheel3: 0).flatMap(NSEvent.init(cgEvent:)) else { return }
            panel.view.scrollWheel(with: event)
        }
        defer { panel.hide() }
        let more = String(repeating: " More of the answer comes in, a line or two at a time.", count: 12)
        comeIn(more + more)  // taller than half of any screen
        let end = panel.view.rowsShift
        wheel(120)
        let up = panel.view.rowsShift
        comeIn(more)
        check(end > 0 && up < end && panel.view.rowsShift == up,
              "scrolled up, the conversation stays put while the answer comes in (\(Int(end)) → \(Int(up)) → \(Int(panel.view.rowsShift)))")
        wheel(-100_000)
        let bottom = panel.view.rowsShift
        comeIn(more)
        check(bottom > end && panel.view.rowsShift > bottom,
              "at the bottom, it follows the answer's end (\(Int(bottom)) → \(Int(panel.view.rowsShift)))")
    }
}

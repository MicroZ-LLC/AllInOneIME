import Foundation

// MARK: - An @question conversation

/// `@question` answered, what is typed is the next question, not a refine: the panel grows into a conversation of up to
/// `questionRounds` rounds (`QuestionChat`). The rounds are kept in the refine plumbing: `refineRequest` is the first
/// question, each of `refinements` an answer and the question typed after it, `result` the latest answer. Every round's
/// answer can be picked (digits 1–5, ↑↓ then ⏎, a click; the latest is selected), ⇧⏎ asks the question typed, Esc with
/// nothing typed goes back a round. After the last round, or with ⌘⏎ at any round, the panel offers to go on in the
/// agent `@agent` hands to (Claude Code by default), Claude, ChatGPT or Gemini, or to copy the conversation
/// (`handoffChoices`, ⌘1 …; `ChatHandoff`).
extension Composer {
    /// What a hand-off says near the caret, in the interface language.
    public struct ChatMessages: Equatable, Sendable {
        /// Opened on the web without the conversation in the address (too long, or Gemini): it's on the clipboard.
        public var pasteIt: String
        public var copiedConversation: String
        /// Secure input is on: nothing is handed over (copying still works).
        public var secureInput: String

        public static let chinese = ChatMessages(
            pasteIt: "对话已复制到剪贴板：粘贴进去接着聊", copiedConversation: "已复制对话",
            secureInput: "系统安全输入已开启（密码框或锁屏），对话没有发出去")
        public static let english = ChatMessages(
            pasteIt: "The conversation is on the clipboard: paste it", copiedConversation: "Copied the conversation",
            secureInput: "Secure input is on (a password field or the lock screen): the conversation wasn't sent")
    }

    /// The results shown are an @question conversation (asked, or a saved one picked), up and answering or answered.
    public var isQuestionChat: Bool {
        guard activeCommand == .question, case .command(.question, _)? = refineRequest else { return false }
        switch phase {
        case .choosing, .translating: return true
        case .idle, .drafting, .failed: return false
        }
    }

    /// The conversation's rounds, oldest first, as the panel shows them: the first question as typed (the selection,
    /// when nothing was), the latest answer as far as it has come (empty while asked). None outside one.
    public var chatRounds: [QuestionChat.Round] {
        guard isQuestionChat else { return [] }
        let first = sentText.isEmpty ? selection?.text ?? "" : sentText
        return QuestionChat.rounds(first: first, turns: refinements, latest: result.versions.first?.text)
    }

    /// The rounds as they were sent: the first question with the selection it was about, if any.
    var sentRounds: [QuestionChat.Round] {
        guard case let .command(_, input)? = refineRequest else { return [] }
        return QuestionChat.rounds(first: input, turns: refinements, latest: result.versions.first?.text)
    }

    /// The round the latest answer is of (1 for the first question).
    public var chatRound: Int { refinements.count + 1 }

    /// The last round `questionRounds` allows is answered: no more questions in the panel.
    public var chatAtLimit: Bool { isQuestionChat && phase == .choosing && chatRound >= QuestionChat.rounds(questionRounds) }

    /// Where the conversation can go on is shown, in place of the next question's line: after the last round, or ⌘⏎.
    public var showsHandoff: Bool { isQuestionChat && phase == .choosing && (chatAtLimit || handoffRequested) }

    /// The answers, numbered from 1: what digits, ↑↓ and clicks pick (the latest can't be while it's coming in).
    var chatChoices: [Choice]? {
        guard isQuestionChat else { return nil }
        let rounds = chatRounds
        let latestComplete = result.versions.first?.isComplete ?? false
        return rounds.enumerated().map { index, round in
            Choice(label: String(index + 1), kind: .answer, text: round.answer, isComplete: index < rounds.count - 1 || latestComplete)
        }
    }

    /// ⌘R on a saved answer asks it again, for a fresh answer: a single question as it was asked (`reaskQuestion`), a
    /// conversation's latest question with the rounds before it. What was typed goes; the fresh answer takes the saved
    /// one's place (`rememberAnswer`). Letters always start the next question.
    func reaskSaved() -> [Effect] {
        guard showsSavedAnswer, let entry = recalled?.entry else { return [] }
        guard entry.thread.count > 1, let last = refinements.last else { return reaskQuestion() }
        if let refusal = aiRefusal() { return [.notice(refusal), .showPanel] }
        // Pinyin being typed goes (`convertComposition` on nothing left only reads the engine's state again).
        if let engine, engine.snapshot().isComposing {
            engine.clearComposition()
            _ = convertComposition(engine)
        }
        refinements.removeLast()
        result = last.answer
        refineText = last.instruction
        handoffRequested = false
        return runRefine(fresh: true)
    }

    /// A saved question picked (`showSavedAnswer`): its rounds, to go on with; the latest answer is `result`.
    func loadThread(_ entry: QuestionHistory.Entry, command: Command) {
        let (first, turns, latest) = QuestionChat.turns(entry.thread)
        refineRequest = .command(command, input: first)
        refinements = turns
        result = ConversionResult(versions: [CandidateLine(latest, isComplete: true)])
        refineText = ""
        refineError = nil
        handoffRequested = false
    }

    /// ⌘⏎ shows where the conversation can go on (at any round, once an answer is in); while it's shown ⌘1, ⌘2 … pick
    /// one. ⌘R on a saved answer asks it again (`reaskSaved`). Nil: the key acts as usual.
    func handleHandoffKey(_ event: KeyEvent) -> Response? {
        let modifiers = event.modifiers.subtracting(.capsLock)
        // ⌘R (⌘⇧R too) on a saved answer: asked again.
        if showsSavedAnswer, modifiers.contains(.command), modifiers.isSubset(of: [.command, .shift]),
           event.charactersIgnoringModifiers.lowercased() == "r" {
            return .consumed(reaskSaved())
        }
        let isReturn = event.keyCode == VirtualKey.returnKey || event.keyCode == VirtualKey.keypadEnter
        // ⌘⏎ never reaches the app while an @question panel is up (a chat app would send what's in its field): while
        // the answer comes in (or after a failure) it does nothing; once it's in, it shows the choices.
        if isReturn, modifiers == .command, isLevelTwo, activeCommand == .question, !(isQuestionChat && phase == .choosing) {
            return .consumed()
        }
        guard isQuestionChat, phase == .choosing, modifiers == .command else { return nil }
        if isReturn {
            // At the last round they're up anyway: nothing to hide later with Esc.
            if !chatAtLimit { handoffRequested = true }
            return .consumed([.showPanel])
        }
        guard showsHandoff, let digit = event.charactersIgnoringModifiers.first?.wholeNumberValue,
              event.charactersIgnoringModifiers.count == 1, digit >= 1 else { return nil }
        guard handoffChoices.indices.contains(digit - 1) else { return .consumed() }
        return .consumed(handOff(to: handoffChoices[digit - 1]))
    }

    /// Goes on with the conversation in `destination`: the selected text the first question was about (if any), the rounds
    /// so far as they were shown, "Let's continue this discussion." and the next question typed, if any (`ChatHandoff`). The
    /// panel closes and nothing is inserted (a selection stays as it is). Only copying works during secure input or in an
    /// app with no AI.
    public func handOff(to destination: ChatHandoff.Destination) -> [Effect] {
        guard isQuestionChat, phase == .choosing else { return [] }
        // Pinyin still being typed goes in the follow-up first.
        if let engine, engine.snapshot().isComposing { _ = convertComposition(engine) }
        if destination != .copy {
            if secureInputActive() { return [.notice(chatMessages.secureInput), .showPanel] }
            if let refusal = aiRefusal() { return [.notice(refusal), .showPanel] }
        }
        // A question about the selection: the selected text as a block of its own, the question as typed.
        var rounds = sentRounds
        let selected = selectionInUse.flatMap { sentText.isEmpty ? nil : $0 }
        if selected != nil, !rounds.isEmpty { rounds[0].question = sentText }
        let followUp = refineText
        let action = ChatHandoff.action(destination, prompt: ChatHandoff.prompt(rounds, followUp: followUp, selection: selected),
                                        copied: ChatHandoff.copied(rounds, followUp: followUp, selection: selected))
        let done = finish(committing: "", selection: .kept)
        switch action {
        case let .claudeCode(prompt):
            return done + [.continueInClaudeCode(prompt: prompt), .notice(messages.openedTerminal)]
        case let .open(url, clipboard?):
            return done + [.copy(clipboard), .openLink(url), .notice(chatMessages.pasteIt)]
        case let .open(url, nil):
            return done + [.openLink(url)]
        case let .copy(text):
            return done + [.copy(text), .notice(chatMessages.copiedConversation)]
        }
    }
}

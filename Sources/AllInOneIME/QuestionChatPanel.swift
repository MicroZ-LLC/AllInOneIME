import AllInOneIMECore
import AppKit

/// The panel of an `@question` conversation (`Composer.isQuestionChat`): the next question's line at the top (or where
/// the conversation can go on, after its last round or ⌘⏎), then the rounds, oldest first, as 问/答 (Q/A) rows, the
/// earlier ones dimmed and shortened, the latest answer in full. The panel grows with them up to about half the
/// screen, then scrolls, the latest at the bottom (`CandidateView.Model.transcript`).
extension AllInOneIMEInputController {
    /// Whether the `claude` command is on this Mac (where Terminal finds it, else on the login shell's PATH): Claude
    /// Code is offered to go on in. Looked for once.
    static let claudeCodeInstalled: Bool = TerminalLauncher.claudePath != nil
        || CommandRunner.resolve("claude", path: ShellEnvironment.current["PATH"]) != nil

    /// The rounds and where a conversation can go on, from the settings; what the hand-off says in the interface language.
    @MainActor
    func applyChatSettings(_ config: Config) {
        composer.questionRounds = config.questionRounds
        composer.handoffChoices = ChatHandoff.choices(config.questionContinueIn, claudeCode: Self.claudeCodeInstalled)
        composer.chatMessages = UIText.chinese ? .chinese : .english
    }

    /// The answer a click on row `row` of a conversation picks (rows alternate: a question, then its answer).
    static func chatChoice(row: Int) -> Int? { row % 2 == 1 ? row / 2 : nil }

    /// A destination's name in the panel and the settings.
    static func name(_ destination: ChatHandoff.Destination) -> String {
        switch destination {
        case .claudeCode: return "Claude Code"
        case .claudeWeb: return tr("Claude 网页版", "Claude (web)")
        case .chatgpt: return tr("ChatGPT 网页版", "ChatGPT (web)")
        case .gemini: return tr("Gemini 网页版", "Gemini (web)")
        case .copy: return tr("复制对话", "Copy the conversation")
        }
    }

    /// The most of an earlier question or answer shown (the latest answer is shown whole, up to `latestLimit`).
    static let earlierLimit = 160
    static let latestLimit = 4000

    @MainActor
    func chatPanelModel() -> CandidateView.Model {
        var model = CandidateView.Model()
        model.transcript = true
        let rounds = composer.chatRounds
        let choices = composer.choices
        let answering: Bool
        if case .translating = composer.phase { answering = true } else { answering = false }
        func line(_ text: String) -> String { text.split(whereSeparator: \.isNewline).joined(separator: " ↵ ") }
        for (index, round) in rounds.enumerated() {
            let latest = index == rounds.count - 1
            model.rows.append(CandidateView.Row(label: "", text: tr("问：", "Q: ") + Self.preview(line(round.question), limit: Self.earlierLimit),
                                                style: .original, pickable: false))
            let answer = latest ? Self.preview(round.answer, limit: Self.latestLimit) : Self.preview(line(round.answer), limit: Self.earlierLimit)
            let choice = choices.indices.contains(index) ? choices[index] : nil
            model.rows.append(CandidateView.Row(label: String(index + 1), text: tr("答：", "A: ") + answer,
                                                style: latest ? .translation : .original, isComplete: choice?.isComplete ?? true,
                                                pickable: choice.map(Composer.picks) ?? false))
        }
        model.highlighted = 2 * composer.highlighted + 1
        // The values hidden from the AI, and an answer whose placeholder it changed past telling.
        if lastHidden > 0 {
            let original = rounds.first?.question ?? ""
            for (index, choice) in choices.enumerated() where choice.isComplete && Redaction.isAltered(choice.text, original: original) {
                let row = 2 * index + 1
                if model.rows.indices.contains(row) { model.rows[row].comment = RedactionPanel.changed }
            }
        }
        // The line on top: where the conversation can go on, or the next question.
        let typed = composer.refineLine.map { $0 + "▏" } ?? "▏"
        if composer.showsHandoff {
            let choices = composer.handoffChoices.enumerated().map { "⌘\($0.offset + 1) " + Self.name($0.element) }.joined(separator: "   ")
            let title = composer.chatAtLimit
                ? tr("已经聊了 \(composer.chatRound) 轮：在 Claude 或别的 AI 里接着聊", "\(composer.chatRound) rounds in: continue in Claude or another AI")
                : tr("在 Claude 或别的 AI 里接着聊", "Continue in Claude or another AI")
            model.input = title + "\n" + choices + (composer.refineLine == nil ? "" : "\n" + tr("接着说 › ", "then › ") + typed)
        } else if composer.typesRefine {
            let next = min(composer.chatRound + 1, QuestionChat.rounds(composer.questionRounds))
            model.input = tr("追问 \(next)/\(QuestionChat.rounds(composer.questionRounds)) › ", "question \(next)/\(QuestionChat.rounds(composer.questionRounds)) › ")
                + typed
        }
        model.header = selectionHeader()
        if let error = composer.refineError { model.status = .error(error) }
        if answering, rounds.last?.answer.isEmpty ?? true { model.status = .loading(tr("AI 回答中…", "Answering…")) }
        let count = composer.handoffChoices.count
        let first = composer.handoffChoices.first.map(Self.name) ?? ""
        if answering {
            model.footer = composer.refinements.isEmpty ? tr("回答中… · Esc 返回", "Answering… · Esc back")
                : tr("回答中… · 可以接着打下一个问题 · Esc 回到上一轮", "Answering… · type the next question meanwhile · Esc previous round")
        } else if composer.showsHandoff {
            model.footer = (count > 1 ? "⌘1–⌘\(count) " : "⌘1 ") + tr("接着聊", "continue")
                + (composer.refineLine == nil ? "" : tr(" · ⇧⏎ 发到 \(first)", " · ⇧⏎ send to \(first)"))
                + tr(" · ⏎ 上屏 · 1–5 选 · ⌘C 复制 · Esc 返回", " · ⏎ insert · 1–5 pick · ⌘C copy · Esc back")
        } else if composer.showsSavedAnswer, composer.refinements.isEmpty, composer.refineLine == nil {
            // A saved answer of one question: R asks it again for a fresh one (letters otherwise start the next question).
            model.footer = tr("⇧⏎ 追问 · ⏎ 上屏 · R 重新问 · ⌘C 复制 · Esc 返回", "⇧⏎ ask · ⏎ insert · R re-ask · ⌘C copy · Esc back")
        } else {
            model.footer = tr("⇧⏎ 追问 · ⏎ 上屏 · 1–5 选 · ⌘C 复制 · Esc 返回", "⇧⏎ ask · ⏎ insert · 1–5 pick · ⌘C copy · Esc back")
        }
        // When it was saved, or how long the answer took; that earlier rounds were shortened to fit the model.
        var details: [String] = []
        if lastHidden > 0, !composer.showsSavedAnswer { details.append(RedactionPanel.hiddenLine(lastHidden)) }
        if lastShortened, !composer.showsSavedAnswer { details.append(tr("前面几轮已缩短", "earlier rounds shortened")) }
        if !answering {
            if let date = composer.savedAnswerDate {
                details.append(tr("保存于", "saved ") + UIText.ago(date))
            } else if let time = lastFromCache ? tr("缓存", "cached") : lastElapsed.map({ String(format: "%.1fs", $0) }) {
                details.append(time)
            }
        }
        model.detail = details.isEmpty ? nil : details.joined(separator: " · ")
        if let notice { model.detail = notice }
        return model
    }
}

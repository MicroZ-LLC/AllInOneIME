import AllInOneIMECore
import SwiftUI

/// Settings → AI → where `@question` is answered (`Config.questionBackend`): Automatic (`Config.questionSessionAgent`),
/// the input method's own session on Claude Code, Codex, Gemini CLI or Kiro CLI (`ClaudeSessionMac`), or the provider.
/// Each session is listed always, with why it can't answer now when it can't, as last looked at. Each one's sign-in is
/// looked at again as the pane shows with a session or Automatic picked, and when one of them is picked here; with the
/// AI provider picked, none is (no agent's program runs). "Start over" makes a new session of the one the questions go
/// to (the only way to: no @ command does).
struct QuestionBackendSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var availability: [SessionAgent: ClaudeSession.Availability] = ClaudeSessionMac.managers.mapValues(\.availability)
    @State private var startedOver = false

    /// The session the questions go to now, as the converter decides it.
    private var current: SessionAgent? {
        model.config.questionSessionAgent(availability: { availability[$0] ?? .notInstalled })
    }

    var body: some View {
        Picker(selection: Binding(get: { model.config.questionBackend }, set: { backend in
            model.config.questionBackend = backend
            model.save()
            startedOver = false
            for session in ClaudeSessionMac.managers.values { session.stop() }  // the next question starts the one picked
            if backend != .provider { lookAgain() }  // a session or Automatic picked: each one's sign-in looked at
        })) {
            Text(automatic).tag(QuestionBackend?.none)
            ForEach(QuestionBackend.sessionAgents, id: \.self) { agent in
                Text(agent.sessionTitle + suffix(agent)).tag(QuestionBackend?.some(QuestionBackend(agent)))
            }
            Text(tr("AI 服务", "The AI provider")).tag(QuestionBackend?.some(.provider))
        } label: {
            titled(model.triggered(tr("提问（@question）", "Questions (@question)")), QuestionBackend.help)
        }
        .settingsRow(.questionBackend, shown: model.spot)
        .onAppear {
            // The AI provider picked: no agent's program is run to say so (only once a session or Automatic is picked).
            guard model.config.questionBackend != .provider else { return }
            ClaudeSessionMac.checkAvailability(done: shown)
        }
        if let current {
            LabeledContent {
                Button(tr("重新开始", "Start Over")) {
                    startedOver = (try? ClaudeSessionMac.manager(current).startOver()) != nil
                }
            } label: {
                let name = current.displayName
                titled(current.sessionTitle,
                       startedOver ? tr("✓ 下一个问题开始一个新会话", "✓ The next question starts a new session")
                           : tr("开始一个新会话：之前的问题它就不记得了（旧会话还在 \(name) 的历史里）。",
                                "A new session: it no longer remembers the earlier questions (the old one stays in \(name)'s history)."))
            }
        }
    }

    /// Each agent's sign-in looked at again (its program run, `ClaudeSessionMac.checkAvailability`), then `shown`.
    private func lookAgain() {
        ClaudeSessionMac.checkAvailability(done: shown)
    }

    /// What each agent's sign-in was found to be, shown.
    private func shown() {
        availability = ClaudeSessionMac.managers.mapValues(\.availability)
    }

    /// Why `agent`'s session can't answer now, after its name; empty when it can (or isn't looked at yet).
    private func suffix(_ agent: SessionAgent) -> String {
        switch availability[agent] ?? .unknown {
        case .notInstalled:
            let program = agent.program
            return tr(" — 没装 \(program)", " — \(program) isn't installed")
        case .signedOut: return tr(" — 没登录", " — not signed in")
        case .cannotStart: return tr(" — 启动不了", " — can't start")
        case .ready, .unknown: return ""
        }
    }

    /// "Automatic", with what it is now.
    private var automatic: String {
        guard availability.values.contains(where: { $0 != .unknown }) else { return tr("自动", "Automatic") }
        var config = model.config
        config.questionBackend = nil
        let now = config.questionSessionAgent(availability: { availability[$0] ?? .notInstalled })
        return tr("自动（现在：\(now?.sessionTitle ?? "AI 服务")）", "Automatic (now: \(now?.sessionTitle ?? "the AI provider"))")
    }
}

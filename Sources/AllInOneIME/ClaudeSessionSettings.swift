import AllInOneIMECore
import SwiftUI

/// Settings → AI → where `@question` is answered (`Config.questionBackend`): Automatic (`Config.questionSessionAgent`),
/// the input method's own Claude Code session, its own Kiro CLI session (`ClaudeSessionMac`), or the provider. Each
/// session is listed always, with why it can't answer now when it can't. "Start over" makes a new session of the one the
/// questions go to (the only way to: no @ command does).
struct QuestionBackendSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var availability: [AgentKind: ClaudeSession.Availability] = ClaudeSessionMac.managers.mapValues(\.availability)
    @State private var startedOver = false

    /// The session the questions go to now, as the converter decides it.
    private var current: AgentKind? {
        model.config.questionSessionAgent(availability: { availability[$0] ?? .notInstalled })
    }

    var body: some View {
        Picker(selection: Binding(get: { model.config.questionBackend }, set: { backend in
            model.config.questionBackend = backend
            model.save()
            startedOver = false
            for session in ClaudeSessionMac.managers.values { session.stop() }  // the next question starts the one picked
        })) {
            Text(automatic).tag(QuestionBackend?.none)
            Text(Self.name(.claude) + suffix(.claude)).tag(QuestionBackend?.some(.claudeSession))
            Text(Self.name(.kiro) + suffix(.kiro)).tag(QuestionBackend?.some(.kiroSession))
            Text(tr("AI 服务", "The AI provider")).tag(QuestionBackend?.some(.provider))
        } label: {
            titled(model.triggered(tr("提问（@question）", "Questions (@question)")),
                   tr("输入法自己的一个 Claude Code 或 Kiro CLI 会话，记得以前问过的问题；⌘⏎ 可以在终端里接着聊。改写、翻译、补全总是用上面的 AI 服务。",
                      "The input method's own Claude Code or Kiro CLI session, which remembers earlier questions; ⌘⏎ continues it in Terminal. Rewriting, translating and autocomplete always use the provider above."))
        }
        .onAppear {
            ClaudeSessionMac.checkAvailability {
                availability = ClaudeSessionMac.managers.mapValues(\.availability)
            }
        }
        if let current {
            LabeledContent {
                Button(tr("重新开始", "Start Over")) {
                    startedOver = (try? ClaudeSessionMac.manager(current).startOver()) != nil
                }
            } label: {
                titled(Self.name(current),
                       startedOver ? tr("✓ 下一个问题开始一个新会话", "✓ The next question starts a new session")
                           : current == .kiro ? tr("开始一个新会话：之前的问题它就不记得了（旧会话还在 Kiro CLI 的历史里）。",
                                                   "A new session: it no longer remembers the earlier questions (the old one stays in Kiro CLI's history).")
                           : tr("开始一个新会话：之前的问题它就不记得了（旧会话还在 Claude Code 的历史里）。",
                                "A new session: it no longer remembers the earlier questions (the old one stays in Claude Code's history)."))
            }
        }
    }

    static func name(_ agent: AgentKind) -> String {
        agent == .kiro ? tr("Kiro CLI 会话", "Kiro CLI session") : tr("Claude Code 会话", "Claude Code session")
    }

    /// Why `agent`'s session can't answer now, after its name; empty when it can (or isn't looked at yet).
    private func suffix(_ agent: AgentKind) -> String {
        switch availability[agent] ?? .unknown {
        case .notInstalled:
            return agent == .kiro ? tr(" — 没装 kiro-cli", " — kiro-cli isn't installed") : tr(" — 没装 claude", " — claude isn't installed")
        case .signedOut: return tr(" — 没登录", " — not signed in")
        case .ready, .unknown: return ""
        }
    }

    /// "Automatic", with what it is now.
    private var automatic: String {
        guard availability.values.contains(where: { $0 != .unknown }) else { return tr("自动", "Automatic") }
        var config = model.config
        config.questionBackend = nil
        let now = config.questionSessionAgent(availability: { availability[$0] ?? .notInstalled })
        return tr("自动（现在：\(now.map(Self.name) ?? "AI 服务")）", "Automatic (now: \(now.map(Self.name) ?? "the AI provider"))")
    }
}

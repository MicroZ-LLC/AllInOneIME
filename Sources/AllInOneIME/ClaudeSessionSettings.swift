import AllInOneIMECore
import SwiftUI

/// Settings → AI → where `@question` is answered (`Config.questionBackend`): the input method's own Claude Code session
/// (`ClaudeSessionMac`), the provider, or (not picked) the session when `claude` is installed and signed in. "Start
/// over" makes a new session (the only way to: no @ command does).
struct QuestionBackendSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var availability = ClaudeSessionMac.manager.availability
    @State private var startedOver = false

    var body: some View {
        Picker(selection: Binding(get: { model.config.questionBackend }, set: { backend in
            model.config.questionBackend = backend
            model.save()
            ClaudeSessionMac.manager.stop()  // the next question starts it again if it's still the one
        })) {
            Text(automatic).tag(QuestionBackend?.none)
            Text(tr("Claude 会话（你的 Claude 订阅）", "Claude session (your Claude subscription)")).tag(QuestionBackend?.some(.claudeSession))
            Text(tr("AI 服务", "The AI provider")).tag(QuestionBackend?.some(.provider))
        } label: {
            titled(model.triggered(tr("提问（@question）", "Questions (@question)")),
                   model.triggered(tr("Claude 会话：输入法自己的一个 Claude Code 会话，用你的 Claude 订阅，记得以前问过的问题；⌘⏎ 可以在终端里接着聊。改写、翻译、补全总是用上面的 AI 服务。",
                                      "Claude session: the input method's own Claude Code session, on your Claude subscription, which remembers earlier questions; ⌘⏎ continues it in Terminal. Rewriting, translating and autocomplete always use the provider above.")))
        }
        .onAppear { ClaudeSessionMac.checkAvailability { availability = ClaudeSessionMac.manager.availability } }
        if model.config.questionBackend != .provider {
            LabeledContent {
                Button(tr("重新开始", "Start Over")) {
                    startedOver = (try? ClaudeSessionMac.manager.startOver()) != nil
                }
            } label: {
                titled(tr("Claude 会话", "Claude session"),
                       startedOver ? tr("✓ 下一个问题开始一个新会话", "✓ The next question starts a new session")
                           : tr("开始一个新会话：之前的问题它就不记得了（旧会话还在 Claude Code 的历史里）。",
                                "A new session: it no longer remembers the earlier questions (the old one stays in Claude Code's history)."))
            }
        }
    }

    /// "Automatic", with what it is now.
    private var automatic: String {
        switch availability {
        case .ready: return tr("自动（现在：Claude 会话）", "Automatic (now: the Claude session)")
        case .notInstalled: return tr("自动（现在：AI 服务，没装 claude）", "Automatic (now: the AI provider; claude isn't installed)")
        case .signedOut: return tr("自动（现在：AI 服务，claude 没登录）", "Automatic (now: the AI provider; claude isn't signed in)")
        case .unknown: return tr("自动", "Automatic")
        }
    }
}

import AllInOneIMECore
import SwiftUI

/// Settings → AI's choice (`Config.ai`, the owner's design): collapsed, the AI chosen (`AIChosenRow`); open (Change ▾),
/// every choice as a card by how it connects (`AIChoicesGrid`), the chosen one outlined. A CLI's card says whether it is
/// installed and signed in, as last looked at. Each CLI's sign-in is looked at again (its program run,
/// `ClaudeSessionMac.checkAvailability`) as this shows with a CLI chosen, as the cards open, and as a CLI is chosen
/// (`SettingsModel.cli`); with a provider chosen and the cards closed, none is (no agent's program runs).
struct AIChoiceSettings: View {
    @ObservedObject var model: SettingsModel
    /// The cards shown (Change ▾), not only the one chosen.
    @Binding var choosing: Bool

    var body: some View {
        let facts = model.aiFacts
        let chosen = model.config.ai
        Group {
            if choosing {
                AIChoicesGrid(chosen: chosen,
                              groups: AIChoice.groups(apple: facts.apple, keeping: chosen),
                              status: { facts.status($0, config: model.config) },
                              pick: { choice in
                                  model.choose(choice)
                                  if model.spot == .provider { model.spot = nil }
                                  withAnimation(.easeOut(duration: 0.15)) { choosing = false }
                              },
                              cancel: { withAnimation(.easeOut(duration: 0.15)) { choosing = false } })
            } else {
                AIChosenRow(choice: chosen, status: facts.status(chosen, config: model.config)) {
                    withAnimation(.easeOut(duration: 0.15)) { choosing = true }
                }
            }
        }
        .settingsRow(.provider, shown: model.spot)
        .onAppear {
            // A provider chosen, the cards closed: no agent's program is run to say so (a preview: nothing of this Mac's).
            guard model.persists, choosing || model.config.ai.agent != nil else { return }
            ClaudeSessionMac.checkAvailability(done: shown)
        }
        .onChange(of: choosing) { if choosing { model.refreshSessions() } }  // the cards opened: each CLI's sign-in
    }

    /// What each CLI's sign-in was found to be, shown.
    private func shown() {
        model.sessionAvailability = ClaudeSessionMac.managers.mapValues(\.availability)
    }
}

extension SettingsModel {
    /// The AI chosen (`Config.ai`), saved: a provider is set as the provider and no CLI is (`cli`); a CLI is set, the
    /// provider kept as it was (the fast fallback, `Config.fastProvider`).
    func choose(_ choice: AIChoice) {
        if let provider = choice.provider { config.provider = provider }
        cli.wrappedValue = choice.agent.map(QuestionBackend.init)
    }

    /// The CLI chosen as the AI (`Config.questionBackend`; nil: the provider is), saved as it is set. Another one than
    /// before (or none) ends every session's process: the next question starts the one chosen. A CLI chosen, each one's
    /// sign-in is looked at again (`refreshSessions`).
    var cli: Binding<QuestionBackend?> {
        Binding(get: { self.config.questionBackend }, set: { backend in
            let before = self.config.questionSessionAgent
            self.config.questionBackend = backend
            self.save()
            guard self.persists, self.config.questionSessionAgent != before else { return }
            for session in ClaudeSessionMac.managers.values { session.stop() }  // the next question starts the one chosen
            if backend != nil { self.refreshSessions() }
        })
    }

    /// Looks again whether each CLI is installed and signed in (`ClaudeSessionMac.checkAvailability`: each one's program
    /// run), then shows it. A preview shows what it was given: nothing of this Mac's.
    func refreshSessions() {
        guard persists else { return }
        ClaudeSessionMac.checkAvailability { [weak self] in
            self?.sessionAvailability = ClaudeSessionMac.managers.mapValues(\.availability)
        }
    }
}

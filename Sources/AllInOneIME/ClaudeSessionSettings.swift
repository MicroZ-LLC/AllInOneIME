import AllInOneIMECore
import SwiftUI

/// Settings → AI's choices (`Config.ai`, the owner's design; #121): every choice as a card by how it connects
/// (`AIChoicesGrid`), always shown, the chosen one outlined; one click chooses. A CLI's card says whether it is installed
/// and signed in, as last looked at: every CLI is looked at as the page shows (`SettingsModel.aiPageShown`), each as last
/// found unless that is too old (`ClaudeSessionMac.checkAvailability`: its program runs only then).
struct AIChoiceSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let facts = model.aiFacts
        let chosen = model.config.ai
        AIChoicesGrid(chosen: chosen,
                      groups: AIChoice.groups(apple: facts.apple, keeping: chosen),
                      status: { facts.status($0, config: model.config) },
                      pick: { choice in
                          model.choose(choice)
                          if model.spot == .provider { model.spot = nil }
                      })
            .settingsRow(.provider, shown: model.spot)
            .onAppear { model.aiPageShown() }
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

    /// The AI page shown: every CLI's sign-in looked at for its card, as last found unless that is too old (a signed-in
    /// one kept until quit, the others for `ClaudeSessionManager.recheckInterval`): shown again within it, nothing runs.
    /// Never at launch or while typing; a preview shows what it was given.
    func aiPageShown() { refreshSessions() }

    /// Looks whether each CLI is installed and signed in (`ClaudeSessionMac.checkAvailability`: as last found unless that
    /// is too old; `force`: each one's program run now), then shows it. A preview shows what it was given: nothing of this
    /// Mac's.
    func refreshSessions(force: Bool = false) {
        guard persists else { return }
        ClaudeSessionMac.checkAvailability(SessionAgent.allCases, force: force) { [weak self] in
            self?.sessionAvailability = ClaudeSessionMac.managers.mapValues(\.availability)
        }
    }
}

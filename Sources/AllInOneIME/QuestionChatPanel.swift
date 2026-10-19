import AllInOneIMECore
import AppKit

/// An `@question` conversation's settings in the composer; its panel is the core's (`PanelPresenter.chatModel`).
extension AllInOneIMEInputController {
    /// The rounds and where a conversation can go on, from the settings: the agents installed (`agentInstalled`), the one
    /// `@agent` hands to first; what the hand-off says in the interface language.
    @MainActor
    func applyChatSettings(_ config: Config) {
        composer.questionRounds = config.questionRounds
        let installed = services.agentInstalled
        composer.handoffChoices = ChatHandoff.choices(config.questionContinueIn, picked: config.agent,
                                                      installed: { installed($0, config.agentCommand) })
        composer.pickedAgent = installed(config.agent, config.agentCommand) ? config.agent : nil
        composer.chatMessages = .make(language: UIText.language)
    }

    /// A destination's short name (`SessionText.shortName`).
    static func shortName(_ destination: ChatHandoff.Destination, picked: AgentKind = .claude, custom: [String] = []) -> String {
        SessionText.shortName(destination, picked: picked, custom: custom)
    }
}

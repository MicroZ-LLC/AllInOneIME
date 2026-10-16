import AllInOneIMECore
import Foundation

/// General → "Continue a conversation in" (`Config.questionContinueIn`): where an @question conversation can go on
/// (`ChatHandoff`), in order, the first the default (⌘1; the choices show after the last round or with ⌘⏎). The agents
/// only where their program is installed (`AgentAvailability`); "@agent's agent" (`.atAgent`) follows the agent picked.
/// An edit keeps the entries not shown now (an agent not installed) where they were.
extension SettingsModel {
    /// The list as configured (the default one until it's edited), with the entries not shown now.
    private var continueList: [ChatHandoff.Destination] { config.questionContinueIn ?? ChatHandoff.defaultList }

    private var shownContinueIndices: [Int] {
        ChatHandoff.shownIndices(continueList, picked: config.agent, installed: agentInstalled)
    }

    /// The chips: the entries offered now, in order, "@agent's agent" as itself.
    var continueChoices: [ChatHandoff.Destination] { shownContinueIndices.map { continueList[$0] } }

    /// The ones that can be added: "@agent's agent" when the list has none; the agents installed (not the one it stands
    /// for) and the web ones not offered yet.
    var missingContinueChoices: [ChatHandoff.Destination] {
        let on = continueChoices, follows = continueList.contains(.atAgent)
        return ChatHandoff.Destination.allCases.filter { destination in
            if destination == .atAgent { return !follows && agentInstalled(config.agent) }
            guard !on.contains(destination) else { return false }
            guard let kind = destination.agent else { return true }
            return agentInstalled(kind) && !(follows && kind == config.agent)
        }
    }

    private func agentInstalled(_ kind: AgentKind) -> Bool { AgentAvailability.installed(kind, custom: config.agentCommand) }

    /// The chips in this order (dragged, added or removed in the window): saved into the list, its entries not shown now
    /// kept where they were (`ChatHandoff.edited`).
    func setContinueIn(_ choices: [ChatHandoff.Destination]) {
        config.questionContinueIn = ChatHandoff.edited(continueList, shown: shownContinueIndices, to: choices)
        save()
    }

    func addContinueIn(_ destination: ChatHandoff.Destination) { setContinueIn(continueChoices + [destination]) }

    func removeContinueIn(_ destination: ChatHandoff.Destination) {
        let rest = continueChoices.filter { $0 != destination }
        if !rest.isEmpty { setContinueIn(rest) }
    }
}

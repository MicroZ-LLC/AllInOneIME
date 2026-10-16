import AllInOneIMECore
import Foundation

/// General → "Continue a conversation in" (`Config.questionContinueIn`): where an @question conversation can go on
/// (`ChatHandoff`), in order, the first the default (⌘1; the choices show after the last round or with ⌘⏎). Claude Code
/// only where the `claude` command is installed.
extension SettingsModel {
    /// The choices as the panel offers them now.
    var continueChoices: [ChatHandoff.Destination] {
        ChatHandoff.choices(config.questionContinueIn, claudeCode: AllInOneIMEInputController.claudeCodeInstalled)
    }

    /// The ones that can be added.
    var missingContinueChoices: [ChatHandoff.Destination] {
        let on = continueChoices
        return ChatHandoff.Destination.allCases.filter {
            !on.contains($0) && ($0 != .claudeCode || AllInOneIMEInputController.claudeCodeInstalled)
        }
    }

    /// The choices in this order (dragged, added or removed in the window).
    func setContinueIn(_ choices: [ChatHandoff.Destination]) {
        config.questionContinueIn = choices
        save()
    }

    func addContinueIn(_ destination: ChatHandoff.Destination) { setContinueIn(continueChoices + [destination]) }

    func removeContinueIn(_ destination: ChatHandoff.Destination) {
        let rest = continueChoices.filter { $0 != destination }
        if !rest.isEmpty { setContinueIn(rest) }
    }
}

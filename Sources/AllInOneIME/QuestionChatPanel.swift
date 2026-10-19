import AllInOneIMECore
import AppKit

/// An `@question` conversation: its settings in the composer are the session's (`InputSession`), its panel the core's
/// (`PanelPresenter.chatModel`).
extension AllInOneIMEInputController {
    /// A destination's short name (`SessionText.shortName`).
    static func shortName(_ destination: ChatHandoff.Destination, picked: AgentKind = .claude, custom: [String] = []) -> String {
        SessionText.shortName(destination, picked: picked, custom: custom, language: UIText.language)
    }
}

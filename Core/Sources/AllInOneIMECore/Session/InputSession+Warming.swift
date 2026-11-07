import Foundation

/// The model made ready before a request goes to it, so that ⏎ doesn't wait for it: the on-device model loaded (it takes
/// about half a second after a short idle, up to 1.5 s). Nothing is sent.
extension InputSession {
    /// What the model would be asked for next, as the draft is now: the AI command it is (its name typed out or picked,
    /// "@improve …"), else the AI command highlighted in the command list ("@imp"), else Translate as You Type, on in this
    /// field. Nil: nothing that asks the model.
    var modelAhead: String? {
        if let command = composer.draftCommand, Self.asksTheModel(command) { return command.name }
        if composer.paletteQuery != nil {
            let (matches, row) = (composer.paletteMatches, composer.paletteHighlighted)
            if matches.indices.contains(row), Self.asksTheModel(matches[row]) { return matches[row].name }
        }
        return composer.translateMode != nil ? "\u{0}translate as you type" : nil
    }

    /// Whether `command` sends its text to the model the settings pick: `@improve`, `@translate`, `@question`, `@reply`
    /// and the custom commands that write with it (not `@agent`: the agent has its own).
    static func asksTheModel(_ command: Command) -> Bool { command.kind == .convert || command.kind == .generate }

    /// After the composer answered: what the model would be asked for next changed (`modelAhead`) to something, so it is
    /// made ready now (`warmModel`), once while it stays the same.
    func warmModelAhead() {
        let ahead = modelAhead
        guard ahead != modelWarmedFor else { return }
        modelWarmedFor = ahead
        if ahead != nil { warmModel() }
    }

    /// The model the AI commands go to made ready for a request: the on-device one loaded, once a minute at most
    /// (`AutocompleteStore.prewarmDue`). Nothing during secure input, nor in an app with no AI.
    func warmModel() {
        let config = services.loadSettings()
        guard !secureInputActive(), config.allowsAI(in: app), config.provider == .apple,
              services.autocomplete.prewarmDue(at: services.uptime()) else { return }
        services.converter.prewarmOnDevice()
    }
}

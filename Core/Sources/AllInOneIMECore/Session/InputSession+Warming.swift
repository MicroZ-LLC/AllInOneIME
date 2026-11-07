import Foundation

/// The model made ready before a request goes to it, so that ⏎ doesn't wait for it: the on-device model loaded (it takes
/// about half a second after a short idle, up to 1.5 s), a cloud provider's connection opened (after two or three minutes
/// idle a new one takes 50 to 300 ms). Nothing of the user's is sent: the on-device model's loading sends nothing, and a
/// cloud provider that is set up gets a HEAD to its origin with no key and no body (`ConnectionWarmth`), never the hosted
/// service.
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
        return composer.translateMode != nil ? Self.translateAsYouType : nil
    }

    /// `modelAhead` for Translate as You Type.
    static let translateAsYouType = "\u{0}translate as you type"

    /// Whether `command` sends its text to the model the settings pick: `@improve`, `@translate`, `@question`, `@reply`
    /// and the custom commands that write with it (not `@agent`: the agent has its own).
    static func asksTheModel(_ command: Command) -> Bool { command.kind == .convert || command.kind == .generate }

    /// After the composer answered: what the model would be asked for next changed (`modelAhead`) to something, so it is
    /// made ready now (`warmModel`), once while it stays the same. Translate as You Type loads the on-device model only:
    /// a cloud provider's connection is opened for an AI command and autocomplete, as the owner approved, not for it.
    func warmModelAhead() {
        let ahead = modelAhead
        guard ahead != modelWarmedFor else { return }
        modelWarmedFor = ahead
        if let ahead { warmModel(connection: ahead != Self.translateAsYouType) }
    }

    /// The model the AI commands go to made ready for a request: the on-device one loaded, once a minute at most
    /// (`AutocompleteStore.prewarmDue`), else (`connection`) the provider's connection opened where nothing went to it
    /// lately and it is set up (`Converter.warmConnection`, `SessionServices.providerSetUp`; where the shell does:
    /// `SessionServices.warmsConnections`). Nothing during secure input, nor in an app with no AI, nor for the hosted
    /// service.
    func warmModel(connection: Bool = true) {
        let config = services.loadSettings()
        guard !secureInputActive(), config.allowsAI(in: app) else { return }
        switch config.provider {
        case .apple:
            guard services.autocomplete.prewarmDue(at: services.uptime()) else { return }
            services.converter.prewarmOnDevice()
        case .hosted:
            return
        case .bedrock, .anthropic, .gemini, .openai:
            if connection, services.warmsConnections {
                services.converter.warmConnection(to: config.provider, config: config, isSetUp: services.providerSetUp)
            }
        }
    }
}

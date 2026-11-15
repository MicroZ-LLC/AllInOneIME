import Foundation

/// What autocomplete's tasks hand the session (`TaskUpdate.suggested`).
public enum AutocompleteUpdate: Sendable {
    /// Request `request` answered (`Converter.autocomplete`), or failed.
    case answered(Result<Autocomplete.Answer, any Error>, request: Int)
    /// With a CLI chosen as the AI, the model its fast fallback gives autocomplete (`Converter.fast`) by lookup `lookup`;
    /// nil: none.
    case routed(Autocomplete.Route?, lookup: Int)
}

extension InputSession {
    /// The model a pause asks in this field: with a provider chosen as the AI, its own (`Autocomplete.route`); with a CLI,
    /// its fast fallback's (`Config.fastProvider`, as `Converter.autocomplete` goes by it), looked up as the field takes
    /// the focus or the settings change (`autocompleteLookUpRoute`). Nil, and autocomplete doesn't run (nothing read,
    /// nothing asked): a CLI with no faster AI (never the CLI itself, a second or more an answer), or not looked up yet.
    func autocompleteRoute(_ config: Config) -> Autocomplete.Route? {
        guard case .cli = config.ai else { return Autocomplete.route(config) }
        return autocomplete.fastRoute ?? nil
    }

    /// With a CLI chosen and autocomplete on in this field: its fast fallback looked up off the main thread (it reads the
    /// keychain and the AWS profile's files). Until the answer comes the last one stands (none in a new field).
    func autocompleteLookUpRoute(_ config: Config) {
        autocomplete.routeLookup += 1
        guard autocomplete.active, case .cli = config.ai else {
            autocomplete.fastRoute = nil
            return
        }
        let (converter, app, lookup) = (services.converter, self.app, autocomplete.routeLookup)
        tasks.start(nil) { post in
            let fast = try? converter.fastSettings(app: app)
            post(.suggested(.routed(fast.flatMap { $0.slow ? nil : Autocomplete.route($0.config) }, lookup: lookup)))
        }
    }

    func autocompleteUpdate(_ update: AutocompleteUpdate) {
        switch update {
        case let .answered(result, request):
            autocompleteAnswered(result, request: request)
        case let .routed(route, lookup):
            guard lookup == autocomplete.routeLookup else { return }
            autocomplete.fastRoute = .some(route)
            if route == nil {
                log.notice("autocomplete: no faster AI than the CLI chosen; off")
            } else if route == .onDevice, autocompleteMayRun(), services.autocomplete.prewarmDue(at: services.uptime()) {
                services.converter.prewarmOnDevice()
            }
        }
    }
}

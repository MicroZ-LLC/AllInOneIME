extension Review076P2Harness {
    static let swiftC = #"""
        // MARK: Items 21 to 24

        static func provider(_ shown: AutocompleteSwitch.Shown) -> String { shown.fast?.provider.rawValue ?? "none" }

        /// A CLI chosen as the AI, `provider` its fast fallback.
        static func cli(_ provider: Provider, autocomplete: Bool = true) -> Config {
            var config = Config.default
            config.uiLanguage = "en"
            config.provider = provider
            config.ai = .cli(.claude)
            config.autocomplete = autocomplete
            return config
        }

        static func useKeys() {
            APIKeys.keychain = keys.store
            Platform.current.onDeviceModel = P2AppleModel()
            _ = NSApplication.shared
            (GhostOverlay.invisible, CandidatePanel.invisible) = (true, true)
            KeyGuard.shared.disabled = true
        }

        /// Item 21: the fast fallback changed from OpenAI to Gemini (both with a key), and the switch shown at once.
        static func menuSwitch() {
            useKeys()
            keys.keep(.openai, host: "api.openai.com")
            keys.keep(.gemini, host: "generativelanguage.googleapis.com")
            let url = home.appendingPathComponent("menu-config.json")
            let before = cli(.openai)
            write(before, to: url)
            _ = AutocompleteSwitch.shown(before)
            pump(5) { AutocompleteSwitch.shown(before).fast != nil }
            let first = AutocompleteSwitch.shown(before)
            say("beforeProvider", provider(first))
            say("beforeLine", first.line ?? "")
            let after = cli(.gemini)
            write(after, to: url)
            let atOnce = AutocompleteSwitch.shown(after)
            say("atOnceProvider", provider(atOnce))
            say("atOnceLine", atOnce.line ?? "")
            say("atOnceModel", atOnce.model ?? "")
            pump(5) { AutocompleteSwitch.shown(after).fast?.provider == .gemini }
            let later = AutocompleteSwitch.shown(after)
            say("laterProvider", provider(later))
            say("laterLine", later.line ?? "")
            say("route", sharedConverter.fastConfig(after)?.provider.rawValue ?? "none")
        }

        /// Item 22: a look for the settings of before (OpenAI, its keychain item slow to answer) comes back after the look
        /// for the settings of now (Anthropic).
        static func menuRace() {
            useKeys()
            keys.keep(.openai, host: "api.openai.com")
            var answers = 0
            AutocompleteSwitch.foundAnother = { answers += 1 }
            let before = cli(.openai), now = cli(.anthropic)
            keys.hold(Provider.openai.rawValue)
            _ = AutocompleteSwitch.shown(before)
            pump(0.3)
            _ = AutocompleteSwitch.shown(now)
            let nowAnswered = pump(8) { answers >= 1 }
            let own = AutocompleteSwitch.shown(now)
            say("nowAnswered", nowAnswered)
            say("nowProvider", provider(own))
            keys.release()
            let beforeAnswered = pump(8) { answers >= 2 }
            let stale = AutocompleteSwitch.shown(now)
            say("beforeAnswered", beforeAnswered)
            say("afterLateAnswerProvider", provider(stale))
            say("afterLateAnswerLine", stale.line ?? "")
            // The look for the settings of now, unhindered: where its requests go.
            let route = sharedConverter.fastConfig(now)?.provider.rawValue ?? "none"
            say("route", route)
        }

        /// Item 23: a CLI chosen, autocomplete off, a key in the keychain for the fast fallback: launch, then the input
        /// menu asked for. The keys read (not their attributes) are counted.
        static func menuOff(launch: Bool) {
            useKeys()
            keys.keep(.openai, host: "api.openai.com")
            let url = home.appendingPathComponent("off-config.json")
            write(cli(.openai, autocomplete: false), to: url)
            keys.forgetReads()
            if launch {
                LaunchWarmUp.run()
                pump(1.5)
            }
            say("readsAtLaunch", keys.keyReads.joined(separator: ","))
            guard let made = AllInOneIMEInputController(server: nil, delegate: nil, client: nil) else {
                print("FAIL no input controller")
                exit(3)
            }
            controller = made
            controller.clientOverride = FakeTextClient()
            let menu = controller.addingAutocomplete(to: NSMenu())
            pump(1.5)
            say("readsAtMenu", keys.keyReads.joined(separator: ","))
            say("menu", menu.items.map(\.title).joined(separator: "|"))
        }

        /// Item 24: a key saved for api.openai.com, the base URL now another host's (a relay): what Settings shows of
        /// it (`SettingsModel.keyState`, `fastConfig`) and where a request goes (`Converter.fastConfig`).
        static func boundKey() {
            useKeys()
            SettingsModel.looksUpKeys = true
            keys.keep(.openai, host: "api.openai.com")
            var config = cli(.openai)
            config.openai.baseURL = "https://relay.example.com/v1"
            let url = home.appendingPathComponent("bound-config.json")
            write(config, to: url)
            let model = SettingsModel(configURL: url, persists: true)
            model.refreshKeys()
            let looked = pump(8) { model.keyState(.openai) != .loading }
            say("looked", looked)
            say("settingsKeySet", model.keyState(.openai).isSet)
            say("settingsReady", model.aiFacts.isReady(.openai, config: model.config))
            say("settingsFast", model.fastConfig?.provider.rawValue ?? "none")
            say("routeFast", sharedConverter.fastConfig(model.config)?.provider.rawValue ?? "none")
            var refused = "none"
            do { _ = try APIKeys.load(.openai, for: "relay.example.com") } catch { refused = String(describing: error) }
            say("requestRefused", refused)
            // The same key with the base URL it was saved for: set and ready everywhere (the control).
            config.openai.baseURL = nil
            write(config, to: url)
            model.reloadIfChanged()
            say("controlSettingsFast", model.fastConfig?.provider.rawValue ?? "none")
            say("controlRouteFast", sharedConverter.fastConfig(model.config)?.provider.rawValue ?? "none")
        }

        static func run(_ way: String) {
            let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
            guard !home.isEmpty, URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
                .hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
                print("FAIL home outside the test's folder: \(NSHomeDirectory())")
                exit(3)
            }
            APIKeys.keychain = .inMemory()
            (GhostOverlay.invisible, CandidatePanel.invisible) = (true, true)
            KeyGuard.shared.disabled = true  // no key tap, no pointer monitor: the child's keys are its own
            switch way {
            case "leave": _ = NSApplication.shared; leave()
            case "held-control": _ = NSApplication.shared; heldControl()
            case "held-keys": _ = NSApplication.shared; heldKeysReplayed()
            case "words": words()
            case "config-read": configRead()
            case "copy-back-listed": copyBack(marker: .copyingBack([Provider.openai.rawValue]))
            case "copy-back-done": copyBack(marker: .done)
            case "terminal-rollback": terminalRollbackTimeout()
            case "menu-switch": menuSwitch()
            case "menu-race": menuRace()
            case "menu-off": menuOff(launch: true)
            case "menu-only": menuOff(launch: false)
            case "bound-key": boundKey()
            default:
                print("FAIL unknown way \(way)")
                exit(2)
            }
            fflush(stdout)
            _exit(0)
        }
    }

    MainActor.assumeIsolated { P2.run(arguments.first ?? "") }
    """#
}

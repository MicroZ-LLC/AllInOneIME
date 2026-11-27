// The ways of Review076ThirdPassTests in the child process of Review076SecondPassChild (compiled into it, after the
// acceptance harness's `P2` and before that suite's dispatch, which asks `P2.third` for a way it doesn't know): what the
// third review of the 0.7.6 review's fixes found in the input method's own code.

enum Review076ThirdPassChild {
    static let ways = #"""

    extension P2 {
        // MARK: A key removed or saved here after a copy-back that couldn't make its list

        /// Key sync off, iCloud Keychain's copies still to copy back (the marker "done"). The first run can't list iCloud
        /// Keychain (locked at login). Only then OpenAI's key is removed here, and another saved for Gemini; the next run
        /// lists it.
        static func copyBackChangedAfterFailedListing() {
            let sync = ICloudSyncController.shared
            let configURL = home.appendingPathComponent("sync-config.json")
            var config = Config.default
            config.iCloudSync.keys = false
            write(config, to: configURL)
            sync.engine = ICloudSyncEngine(folder: ICloudSyncFolder(url: home.appendingPathComponent("drive", isDirectory: true)),
                                           configURL: configURL, stateURL: home.appendingPathComponent("sync/state.json"),
                                           questionsURL: home.appendingPathComponent("sync/questions.json"))
            var (login, synced, replaced) = (APIKeys.Keychain.inMemory(), APIKeys.Keychain.inMemory(), APIKeys.Keychain.inMemory())
            let (removed, saved) = (Provider.openai.rawValue, Provider.gemini.rawValue)
            let then = Date(timeIntervalSinceNow: -3600)
            for account in [removed, saved] {
                _ = login.write(account, "sk-test-EXAMPLE", "AllInOneIME: \(account)", "", "MPLE", then)
                _ = synced.write(account, "sk-test-EXAMPLE", "AllInOneIME: \(account)", "", "MPLE", then)
            }
            let failures = Locked(initialState: 1)
            let accounts = synced.accounts
            synced.listing = {
                if failures.withLock({ left in defer { left -= 1 }; return left > 0 }) { throw APIKeys.KeychainError(status: -25308, message: nil) }
                return accounts()
            }
            let stores = KeySync.Stores(login: login, synced: synced, replaced: replaced)
            sync.keys = stores
            try? FileManager.default.createDirectory(at: sync.keysSyncedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(KeySync.Marker.done.text.utf8).write(to: sync.keysSyncedURL)
            sync.start()
            sync.queue.sync {}
            pump(0.2)
            say("notListedYet", failures.withLock { $0 } <= 0 && KeySync.Marker.read(at: sync.keysSyncedURL) == .done)
            // Only now, with no key sync asked for or running.
            say("removed", stores.store.delete(removed) == .ok && login.read(removed) == nil)
            say("saved", stores.store.write(saved, "sk-test-new-EXAMPLE", "AllInOneIME: Gemini", "", "MPLE", Date()) == .ok)
            // The next run (`ICloudSyncController.run` asks for the keys first).
            sync.keySyncOnQueue()
            sync.queue.sync {}
            pump(0.2)
            say("listed", failures.withLock { $0 } < 0)
            say("removedKey", login.read(removed) ?? "none")
            say("savedKey", login.read(saved) ?? "none")
            say("marker", KeySync.Marker.read(at: sync.keysSyncedURL).map { $0.text.replacingOccurrences(of: "\n", with: "|") } ?? "none")
        }

        // MARK: A fast fallback just chosen, not looked at yet

        /// A CLI chosen, OpenAI its fast fallback with a key, looked up. Then `provider` chosen instead: the switch shown
        /// at once, and again once the look for it came back.
        static func menuNotLookedAtYet(_ chosen: Provider, key: Bool) {
            useKeys()
            keys.keep(.openai, host: "api.openai.com")
            if key { keys.keep(chosen, host: HTTPProviders.host(of: .defaults(for: chosen)) ?? "") }
            var answers = 0
            AutocompleteSwitch.foundAnother = { answers += 1 }
            let before = cli(.openai), after = cli(chosen)
            _ = AutocompleteSwitch.shown(before)
            pump(5) { AutocompleteSwitch.shown(before).fast != nil }
            let first = AutocompleteSwitch.shown(before)
            say("before", "\(provider(first)) \(first.available) \(first.on)")
            let looks = answers
            let atOnce = AutocompleteSwitch.shown(after)
            say("atOnceProvider", provider(atOnce))
            say("atOnceAvailable", atOnce.available)
            say("atOnceOn", atOnce.on)
            say("atOnceLine", atOnce.line ?? "")
            say("atOnceModel", atOnce.model ?? "")
            say("destination", AutocompleteSwitch.destination(after) ?? "")
            say("answered", pump(8) { answers > looks })
            let later = AutocompleteSwitch.shown(after)
            say("laterProvider", provider(later))
            say("laterAvailable", later.available)
            say("laterOn", later.on)
            say("route", sharedConverter.fastConfig(after)?.provider.rawValue ?? "none")
        }

        // MARK: Settings told the config changed, or to show a key's field

        /// Settings open on the AI page; the config file changed elsewhere and the window told (`allInOneIMEConfigChanged`),
        /// then changed again and the window asked for the key field of the provider in use (`allInOneIMEFocusAPIKey`). The
        /// hook tells which thread reads the file between each step's two marks; the input method's own read of the
        /// changed config (`LiveConfig`) is made before the first of them.
        static func settingsTold() {
            _ = NSApplication.shared
            SettingsModel.looksUpKeys = false
            let url = home.appendingPathComponent("config.json")
            var config = Config.default
            config.uiLanguage = "en"
            write(config, to: url)
            SettingsWindow.shared.show(page: .ai, spot: nil, card: nil)
            let model = SettingsWindow.shared.settings
            pump(1)
            say("shown", SettingsWindow.shared.isVisible)
            func mark(_ name: String) -> String {
                let folder = home.appendingPathComponent(name, isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                _ = try? Data(contentsOf: folder.appendingPathComponent("config.json"))  // a line of the hook's own
                return folder.appendingPathComponent("config.json").path
            }
            let tellings: [(AIChoice, () -> Void)] = [
                (.provider(.openai), { NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil) }),
                (.provider(.gemini), {
                    NotificationCenter.default.post(name: .allInOneIMEFocusAPIKey, object: nil, userInfo: ["provider": Provider.gemini.rawValue])
                }),
            ]
            for (step, (ai, tell)) in tellings.enumerated() {
                config.ai = ai
                write(config, to: url)
                _ = LiveConfig.current
                say("from\(step)", mark("from\(step)"))
                tell()
                say("reloaded\(step)", pump(3) { model.config.ai == ai })
                pump(0.5)
                say("to\(step)", mark("to\(step)"))
            }
            say("config", url.path)
        }

        /// This suite's way `way`; false: none of that name.
        static func third(_ way: String) -> Bool {
            switch way {
            case "copy-back-changed-later": copyBackChangedAfterFailedListing()
            case "menu-no-key-yet": menuNotLookedAtYet(.anthropic, key: false)
            case "menu-key-not-looked-at": menuNotLookedAtYet(.gemini, key: true)
            case "settings-told": settingsTold()
            default: return false
            }
            return true
        }
    }
    """#
}

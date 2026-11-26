extension Review076P2Harness {
    static let swiftB = #"""
        // MARK: Item 12

        /// What launch does (`LaunchWarmUp.run`, and the moment after it), then an English word learned on the main
        /// thread, as a key learns one (`InputSession.learnTypedInEnglish` → `EnglishWords.learnsTypedInEnglish`). The
        /// hook tells which thread opened the word list.
        static func words() {
            _ = NSApplication.shared
            write(Config.default, to: home.appendingPathComponent("words-config.json"))
            LaunchWarmUp.run()
            pump(3)
            let typedOnce = EnglishWords.TypedOnce()
            let config = Config.default
            var learned: [Bool] = []
            for _ in 0..<2 {
                learned.append(EnglishWords.learnsTypedInEnglish("gizmotronic", in: FieldInfo(app: "com.example.editor"), secureInput: false,
                                                                 config: { config }, known: [], dictionary: EnglishDictionary([]),
                                                                 typedOnce: typedOnce))
            }
            say("learned", learned.map { $0 ? "1" : "0" }.joined())
            say("marker", "word-list lookup completed")
        }

        // MARK: Item 17

        /// Settings pointed at an AI's card (`SettingsModel.point(at:card:)`, the start's "Use My Own AI…" and the
        /// Doctor's) after the config file changed elsewhere: the hook tells which thread reads the file.
        static func configRead() {
            _ = NSApplication.shared
            SettingsModel.looksUpKeys = false
            let url = home.appendingPathComponent("config.json")
            var config = Config.default
            config.uiLanguage = "en"
            write(config, to: url)
            let model = SettingsModel(configURL: url, persists: true)
            pump(0.3)
            say("marker", "made")
            // Changed elsewhere (the Assistant, another Mac through iCloud): the model hasn't read it.
            config.ai = .provider(.openai)
            write(config, to: url)
            let mark = home.appendingPathComponent("mark", isDirectory: true)
            try? FileManager.default.createDirectory(at: mark, withIntermediateDirectories: true)
            // A line of the hook's own between what was read before and what the pointing reads.
            _ = try? Data(contentsOf: mark.appendingPathComponent("config.json"))
            model.point(at: nil, card: .provider(.anthropic))
            pump(1.5) { model.config.ai == .provider(.openai) }
            say("reloaded", model.config.ai == .provider(.openai))
            say("mark", mark.appendingPathComponent("config.json").path)
            say("config", url.path)
        }

        // MARK: Item 19

        /// The input method starts with key sync off and iCloud Keychain's copies still to copy back (`marker`: "copying
        /// back" with the account, or "done": key sync turned off while the input method wasn't running); the sync queue
        /// is busy; the user removes the key on this Mac (Settings → Remove…) before the queue gets to the keys.
        static func copyBack(marker: KeySync.Marker) {
            let sync = ICloudSyncController.shared
            let configURL = home.appendingPathComponent("sync-config.json")
            var config = Config.default
            config.iCloudSync.keys = false
            write(config, to: configURL)
            sync.engine = ICloudSyncEngine(folder: ICloudSyncFolder(url: home.appendingPathComponent("drive", isDirectory: true)),
                                           configURL: configURL, stateURL: home.appendingPathComponent("sync/state.json"),
                                           questionsURL: home.appendingPathComponent("sync/questions.json"))
            let (login, synced, replaced) = (APIKeys.Keychain.inMemory(), APIKeys.Keychain.inMemory(), APIKeys.Keychain.inMemory())
            let account = Provider.openai.rawValue
            _ = login.write(account, "sk-test-EXAMPLE", "AllInOneIME: OpenAI", "api.openai.com", "MPLE", Date())
            _ = synced.write(account, "sk-test-EXAMPLE", "AllInOneIME: OpenAI", "api.openai.com", "MPLE", Date())
            let stores = KeySync.Stores(login: login, synced: synced, replaced: replaced)
            sync.keys = stores
            try? FileManager.default.createDirectory(at: sync.keysSyncedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(marker.text.utf8).write(to: sync.keysSyncedURL)
            // The sync queue busy as the input method starts (a run, the keychain slow to answer).
            let busy = DispatchSemaphore(value: 0)
            sync.queue.async { busy.wait() }
            sync.start()
            // Remove… in Settings, through the store everything uses (`KeySync.Stores.store`).
            let removed = stores.store.delete(account)
            say("removed", removed == .ok && login.read(account) == nil)
            busy.signal()
            sync.queue.sync {}
            pump(0.2)
            say("loginHasKey", login.read(account) != nil)
            say("syncedHasKey", synced.read(account) != nil)
            say("marker", KeySync.Marker.read(at: sync.keysSyncedURL).map { $0.text.replacingOccurrences(of: "\n", with: "|") } ?? "none")
        }

        // MARK: Item 20

        static func terminalRollbackTimeout() {
            var platform = Platform.current
            platform.processes = P2TerminalProcess()
            Platform.current = platform
            let script = home.appendingPathComponent("agent.command")
            let marker = home.appendingPathComponent("agent.started")
            say("launched", TerminalLauncher.runWhenReady(script, marker: marker))
            say("markerExists", FileManager.default.fileExists(atPath: marker.path))
        }

    """#
}

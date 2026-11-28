import AllInOneIMETestSupport
import Foundation

// The child process of Review076SecondPassTests: what the second review of the 0.7.6 review's fixes found in the input
// method's own code (Sources/AllInOneIME, an executable target that can't be imported). As ControllerOffMainTests and the
// Review076P2 acceptance suite do it, all of it is compiled once into a child with main.swift's dispatch replaced: here
// by that suite's harness (its fields, its keychain, its helpers: `Review076P2Harness.swift`, read, not changed) with the
// ways below in place of its own dispatch. The child's home is a folder of the test's, its keychain in memory; nothing
// is typed into an app, nothing leaves the Mac.

enum Review076SecondPassChild {
    typealias Failure = Review076P2Child.Failure

    static let repository = Review076P2Child.repository
    static let compiled: Result<(executable: URL, hook: URL), Error> = Result { try compile() }

    /// What the child told in `way`: its "KV key value" lines, and each watched file opened ("main" or "other", its path).
    static func run(_ way: String, timeout: TimeInterval = 90) throws -> Review076P2Child.Report {
        let (executable, hook) = try compiled.get()
        let fm = FileManager.default
        let home = TestScratch.temporary("review076second-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let (opens, log) = (home.appendingPathComponent("opened.log"), home.appendingPathComponent("output.log"))
        let run = try command(executable.path, [way], timeout: timeout, log: log, environment: [
            "CFFIXED_USER_HOME": home.path, "HOME": home.path,
            "AWS_CONFIG_FILE": "/nonexistent", "AWS_SHARED_CREDENTIALS_FILE": "/nonexistent",
            "ALLINONEIME_LOGIN_SHELL_TIMEOUT": "2", "DYLD_INSERT_LIBRARIES": hook.path, "REVIEW076_OPEN_LOG": opens.path,
        ])
        guard run.status == 0 else { throw Failure(description: "the child (\(way)) failed (\(run.status)):\n\(run.output)") }
        var values: [String: String] = [:]
        for line in run.output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, fields[0] == "KV", let decoded = Data(base64Encoded: fields[2]) else { continue }
            values[fields[1]] = String(decoding: decoded, as: UTF8.self)
        }
        guard !values.isEmpty else { throw Failure(description: "the child (\(way)) told nothing:\n\(run.output)") }
        let opened = ((try? String(contentsOf: opens, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { line -> (Bool, String)? in
            let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return fields.count == 2 ? (fields[0] == "main", fields[1]) : nil
        }
        return Review076P2Child.Report(values: values, opened: opened, output: run.output)
    }

    private static func compile() throws -> (executable: URL, hook: URL) {
        let fm = FileManager.default
        let scratch = TestScratch.temporary("review076second-child-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        // The acceptance harness with its last line, its own dispatch, replaced by this suite's.
        let theirs = "MainActor.assumeIsolated { P2.run(arguments.first ?? \"\") }"
        guard let last = Review076P2Harness.swift.range(of: theirs, options: .backwards) else {
            throw Failure(description: "the Review076P2 harness has no `\(theirs)`")
        }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + String(Review076P2Harness.swift[..<last.lowerBound]) + Review076ThirdPassChild.ways
             + AboutOffMainReviewChild.ways + ways)
            .write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.sorted { $0.path < $1.path }
            .map { source -> String in
                // As the acceptance child has it: its harness calls `TerminalLauncher.runWhenReady`.
                guard source.lastPathComponent == "TerminalLauncher.swift" else { return source.path }
                let text = try String(contentsOf: source, encoding: .utf8)
                    .replacingOccurrences(of: "private static func runWhenReady(", with: "static func runWhenReady(")
                let copy = scratch.appendingPathComponent("TerminalLauncher.swift")
                try text.write(to: copy, atomically: true, encoding: .utf8)
                return copy.path
            }
        let executable = scratch.appendingPathComponent("review076second")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else {
            let errors = swift.output.split(separator: "\n").filter { $0.contains("error:") }
            throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n"
                          + (errors.isEmpty ? swift.output : errors.joined(separator: "\n")))
        }
        // The library that tells which thread opens a watched file (the acceptance harness's).
        let hookSource = scratch.appendingPathComponent("opens.c"), hook = scratch.appendingPathComponent("opens.dylib")
        try Review076P2Harness.opens.write(to: hookSource, atomically: true, encoding: .utf8)
        let clang = try command("/usr/bin/xcrun", ["clang", "-dynamiclib", "-O1", hookSource.path, "-o", hook.path], timeout: 120,
                                log: scratch.appendingPathComponent("clang.log"), environment: [:])
        guard clang.status == 0 else { throw Failure(description: "compiling the open hook:\n\(clang.output)") }
        return (executable, hook)
    }

    private static func command(_ program: String, _ arguments: [String], timeout: TimeInterval, log: URL,
                                environment: [String: String]) throws -> (status: Int32, output: String) {
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        let output = { (try? String(contentsOf: log, encoding: .utf8)) ?? "" }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw Failure(description: "timed out (\(arguments.first ?? program), \(Int(timeout)) s):\n\(output())")
        }
        let status = process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus
        return (status, output())
    }

    /// After the acceptance harness's `P2`: this suite's ways, and the dispatch.
    static let ways = #"""

    /// A keychain in memory whose first two looks at an account in `slow` wait, each for its own `release`, after the
    /// item was looked at: the answer is the one of when it was asked, come back late.
    final class SecondKeys: @unchecked Sendable {
        private let lock = NSLock()
        private var looks = 0
        private let gates = [DispatchSemaphore(value: 0), DispatchSemaphore(value: 0)]
        let items = APIKeys.Keychain.inMemory()
        var slow: Set<String> = []

        var store: APIKeys.Keychain {
            var store = items
            let items = items
            store.read = { [self] account in
                let key = items.read(account)
                wait(account)
                return key
            }
            store.attributes = { [self] account in
                let attributes = items.attributes(account)
                wait(account)
                return attributes
            }
            return store
        }

        func release(_ look: Int) { gates[look].signal() }
        private func wait(_ account: String) {
            let look: Int? = lock.withLock {
                guard slow.contains(account), looks < gates.count else { return nil }
                looks += 1
                return looks - 1
            }
            if let look { gates[look].wait() }
        }
    }

    extension P2 {
        // MARK: Item 2 (the switch's look, come back after the same settings were asked about again)

        /// A CLI chosen, OpenAI its fast fallback, no key yet: a look that answers late (none). Another fast fallback
        /// chosen and looked up; then OpenAI's key saved and OpenAI chosen again: a new look for the same settings as the
        /// first. The first comes back while that one runs, then that one.
        static func menuSameSettingsAgain() {
            let slow = SecondKeys()
            slow.slow = [Provider.openai.rawValue]
            APIKeys.keychain = slow.store
            Platform.current.onDeviceModel = P2AppleModel()
            _ = NSApplication.shared
            var answers = 0
            AutocompleteSwitch.foundAnother = { answers += 1 }
            let openai = cli(.openai), other = cli(.anthropic)
            _ = AutocompleteSwitch.shown(openai)  // look 1: no key, its answer held
            pump(0.3)
            _ = AutocompleteSwitch.shown(other)
            say("otherAnswered", pump(8) { answers >= 1 })
            _ = slow.items.write(Provider.openai.rawValue, "sk-test-openai-EXAMPLE", "AllInOneIME: OpenAI", "api.openai.com", "MPLE", Date())
            _ = AutocompleteSwitch.shown(openai)  // look 3: the key is there, its answer held too
            pump(0.3)
            slow.release(0)
            say("firstAnswered", pump(8) { answers >= 2 })
            slow.release(1)
            say("lastAnswered", pump(8) { answers >= 3 })
            say("shownProvider", provider(AutocompleteSwitch.shown(openai)))
            say("route", sharedConverter.fastConfig(openai)?.provider.rawValue ?? "none")
        }

        // MARK: Item 3 (a copy-back whose list can't be made the first time)

        /// As the acceptance harness's `copyBack(marker: .done)`: key sync off, iCloud Keychain's copies still to copy
        /// back, the key removed here before the queue gets to the keys. iCloud Keychain can't be listed that time (locked
        /// at login); the next run lists it.
        static func copyBackListedLater() {
            let sync = ICloudSyncController.shared
            let configURL = home.appendingPathComponent("sync-config.json")
            var config = Config.default
            config.iCloudSync.keys = false
            write(config, to: configURL)
            sync.engine = ICloudSyncEngine(folder: ICloudSyncFolder(url: home.appendingPathComponent("drive", isDirectory: true)),
                                           configURL: configURL, stateURL: home.appendingPathComponent("sync/state.json"),
                                           questionsURL: home.appendingPathComponent("sync/questions.json"))
            var (login, synced, replaced) = (APIKeys.Keychain.inMemory(), APIKeys.Keychain.inMemory(), APIKeys.Keychain.inMemory())
            let account = Provider.openai.rawValue
            _ = login.write(account, "sk-test-EXAMPLE", "AllInOneIME: OpenAI", "api.openai.com", "MPLE", Date())
            _ = synced.write(account, "sk-test-EXAMPLE", "AllInOneIME: OpenAI", "api.openai.com", "MPLE", Date())
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
            let busy = DispatchSemaphore(value: 0)
            sync.queue.async { busy.wait() }
            sync.start()
            let removed = stores.store.delete(account)
            say("removed", removed == .ok && login.read(account) == nil)
            busy.signal()
            sync.queue.sync {}
            say("notListedYet", failures.withLock { $0 } <= 0 && login.read(account) == nil)
            // The next run (`ICloudSyncController.run` asks for the keys first).
            sync.keySyncOnQueue()
            sync.queue.sync {}
            pump(0.2)
            say("loginHasKey", login.read(account) != nil)
            say("marker", KeySync.Marker.read(at: sync.keysSyncedURL).map { $0.text.replacingOccurrences(of: "\n", with: "|") } ?? "none")
        }

        // MARK: Item 4 (a stop settling, its rest to go in, and the field left or the composition cancelled)

        /// A type-out with a typo the field doesn't tell yet, a click outside (the rest to go in once the stop settles),
        /// the field tells the typo; then `then`, and the stop left to settle. The stop looks at the field again only once
        /// `then` has run (its sleep waits for that), not after a time of its own: timed (0.6 s, the field's telling
        /// waited for 0.4 s), on a loaded Mac the field told the typo late and the test failed as if the stop had never
        /// been reached ("caught" false, 3 runs in 14 with the machine busy).
        static func settlingStop(then: (P2Field) -> Void) {
            make()
            let field = P2Field()
            let caught = typeOutToATypo(field)
            let thenRan = Locked(initialState: false)
            controller.typeOutSleep = { _ in
                while !thenRan.withLock({ $0 }) { try? await Task.sleep(nanoseconds: 10_000_000) }
            }
            controller.pointerDown()
            let settling = controller.stopsInsertingRest == true && controller.isTypingOut
            let told = pump(10) { field.told == field.document }
            field.lag = 0
            then(field)
            thenRan.withLock { $0 = true }
            let settled = pump(5) { !controller.isTypingOut }
            pump(0.2)
            // Each part of the premise on its own too, for a run that fails.
            say("typoCaught", caught)
            say("stopSettling", settling)
            say("typoTold", told)
            say("caught", caught && settling && told)
            say("settled", settled)
            say("typed", field.document)
            say("intended", intended)
        }

        // MARK: Item 7 (Settings opened on an AI's card)

        /// The settings built (the start's step 2 shows them), the config file changed elsewhere, and Settings opened on
        /// an AI's card (the start's "Use My Own AI…"); closed, the file changed again, and opened again. The hook tells
        /// which thread reads the file between each step's two marks. The input method's own read of a changed config
        /// (`LiveConfig`, as its next key makes it wherever Settings is) is made before the first of them: what is read
        /// between them is the window's.
        static func settingsOpened() {
            _ = NSApplication.shared
            SettingsModel.looksUpKeys = false
            let url = home.appendingPathComponent("config.json")
            var config = Config.default
            config.uiLanguage = "en"
            write(config, to: url)
            let model = SettingsWindow.shared.settings
            pump(0.3)
            func mark(_ name: String) -> String {
                let folder = home.appendingPathComponent(name, isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                _ = try? Data(contentsOf: folder.appendingPathComponent("config.json"))  // a line of the hook's own
                return folder.appendingPathComponent("config.json").path
            }
            for (step, ai) in [AIChoice.provider(.openai), .provider(.gemini)].enumerated() {
                config.ai = ai
                write(config, to: url)
                _ = LiveConfig.current
                say("from\(step)", mark("from\(step)"))
                SettingsWindow.shared.show(page: .ai, spot: nil, card: .provider(.anthropic))
                say("reloaded\(step)", pump(3) { model.config.ai == ai })
                pump(0.5)
                // Closed as its close button closes it: kept, to be opened again.
                NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }.forEach { $0.close() }
                say("closed\(step)", !SettingsWindow.shared.isVisible)
                pump(0.3)
                say("to\(step)", mark("to\(step)"))
            }
            say("sameModel", SettingsWindow.shared.settings === model)
            say("config", url.path)
        }

        // MARK: Item 8 (the Assistant's and the Doctor's providers with a key)

        static func assistantKeys() {
            let keychain = APIKeys.Keychain.inMemory()
            _ = keychain.write(Provider.openai.rawValue, "sk-test-openai-EXAMPLE", "AllInOneIME: OpenAI", "api.openai.com", "MPLE", Date())
            APIKeys.keychain = keychain
            var config = Config.default
            say("own", AIConfigSession.providersWithKey({ APIKeys.source($0) }, config: config).contains(.openai))
            config.openai.baseURL = "https://relay.example.com/v1"
            say("relayed", AIConfigSession.providersWithKey({ APIKeys.source($0) }, config: config).contains(.openai))
        }

        static func second(_ way: String) {
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
            case "menu-same-again": menuSameSettingsAgain()
            case "copy-back-listed-later": copyBackListedLater()
            case "settling-left": _ = NSApplication.shared; settlingStop { controller.deactivateServer($0) }
            case "settling-cancelled": _ = NSApplication.shared; settlingStop { _ in controller.cancelComposition() }
            case "settings-opened": settingsOpened()
            case "assistant-keys": assistantKeys()
            default:
                // The third pass's ways (Review076ThirdPassChild.swift), then the About review's (AboutOffMainReviewChild.swift).
                guard third(way) || aboutReview(way) else {
                    print("FAIL unknown way \(way)")
                    exit(2)
                }
            }
            fflush(stdout)
            _exit(0)
        }
    }

    MainActor.assumeIsolated { P2.second(arguments.first ?? "") }
    """#
}

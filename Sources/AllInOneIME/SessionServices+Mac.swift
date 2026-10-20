import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMERime
import AppKit

extension SessionServices {
    /// The letters put in as typed once (an English word is learned the second time), every field's, until the input
    /// method quits.
    @MainActor
    private static let lettersTypedOnce = EnglishWords.TypedOnce()

    /// This Mac's: the config file as of now, what UserDefaults keeps, Spotlight, Terminal, Notes or a folder or Notion,
    /// Reminders, Contacts and Messages, the keychain. Main thread only, but for the `@Sendable` ones.
    @MainActor
    static var mac: SessionServices {
        var services = SessionServices(converter: sharedConverter, loadSettings: { LiveConfig.current })
        // librime's session once it has deployed; without the Chinese pack it never starts (Latin letters).
        services.levelOne = {
            if let session = RimeService.shared.makeSession() { return .engine(session) }
            return RimeService.shared.isStarted ? .starting : .none
        }
        services.engineIsValid = { ($0 as? RimeSession)?.isValid ?? true }
        // English words among pinyin's candidates; a word learned goes into the config file (the self-test's own while it runs).
        services.englishDictionary = { RimeService.shared.englishDictionary }
        services.englishTypedOnce = lettersTypedOnce
        services.learnEnglishWord = { word in
            do {
                try EnglishWords.learn(word, at: Config.defaultURL)
            } catch {
                log.error("could not keep an English word: \(String(describing: error), privacy: .public)")
            }
        }
        services.hangulTables = { LanguagePackManager.shared.hangulTables() }
        services.hindiTables = { LanguagePackManager.shared.hindiTables() }
        services.usableLanguages = { LanguagePackManager.shared.usable($0) }
        services.voiceSupported = { VoiceInput.isSupported }
        services.plugins = { LivePlugins.current(rescan: $0) }
        services.scriptStatus = { command in MainActor.assumeIsolated { ScriptStatus.shared.text(for: command) } }
        services.refreshStatuses = { shown, environment, ended in
            MainActor.assumeIsolated { ScriptStatus.shared.refresh(shown, environment: environment, ended: ended) }
        }
        services.jargon = { LiveJargon.entries(for: $0) }
        services.issueDiagnostics = { config, plugins, extensions in
            MainActor.assumeIsolated { IssueReporting.diagnostics(config: config, plugins: plugins, extensions: extensions) }
        }
        services.needsTheUser = { error in
            switch error {
            case NotesBridge.NotesError.notPermitted, RemindersBridge.RemindersError.notPermitted,
                 RemindersBridge.RemindersError.noAccount:
                return true
            case let error as NoteError:
                return error.needsTheUser
            default:
                return false
            }
        }
        services.errorKind = { macErrorKind($0) }
        // The menu bar panel lists the saved notes it can open.
        services.noteSaved = { saved in
            guard let id = saved.id else { return }
            let title = saved.title
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .allInOneIMENoteSaved, object: nil, userInfo: ["id": id, "title": title])
            }
        }
        services.loadCommandUsage = { CommandUsageStore.usage }
        services.saveCommandUsage = { CommandUsageStore.save($0) }
        services.loadQuestionHistory = { QuestionHistoryStore.history }
        services.recordQuestion = { QuestionHistoryStore.record($0) }
        services.loadOpenHistory = { OpenHistoryStore.history }
        services.recordOpen = { OpenHistoryStore.record($0) }
        services.loadRecentHandles = { RecentRecipients.handles }
        services.saveRecentHandles = { RecentRecipients.handles = $0 }
        services.secureInputActive = { SecureInput.isOn }
        services.pointerUsedWithin = { seconds in
            let kinds: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
                                        .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
            return kinds.contains { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) < seconds }
        }
        // An Option key still down with no mouse button pressed, as a sanity check when the hold timer fires (the
        // composer tracks which key from the events).
        services.isVoiceKeyHeld = { NSEvent.modifierFlags.contains(.option) && NSEvent.pressedMouseButtons == 0 }
        services.recognizeText = Platform.current.text
        services.searchFiles = { await FileSearch.run($0, history: $1) }
        services.runInTerminal = { try TerminalLauncher.agent($0, prompt: $1) }
        services.continueInAgent = { try TerminalLauncher.agent($0, prompt: $1) }
        services.agentInstalled = { AgentAvailability.installed($0, custom: $1) }
        services.launchInTerminal = { try TerminalLauncher.launch($0) }
        services.programInstalled = { program in
            if program.isEmpty { return false }  // a custom agent without a command
            if program == "claude", TerminalLauncher.claudePath != nil { return true }
            if program.hasSuffix(".app") { return FileManager.default.fileExists(atPath: program) }  // a send command's app
            return CommandRunner.isInstalled(program, path: ShellEnvironment.current["PATH"])
        }
        services.startAgent = { try await AgentMonitor.shared.start($0) }
        services.listAgents = { try await AgentMonitor.shared.list() }
        services.runProgram = { CommandRunner.run($0, input: $1) }
        services.runPlugin = { PluginRunner.run($0, input: $1, language: $2) }
        services.loadExtensions = { config, rescan in
            if rescan { LiveExtensions.discoverIfDue(config) }
            return LiveExtensions.current(config, rescan: rescan)
        }
        services.extensionPreferences = { LiveExtensions.preferences(of: $0, config: $1) }
        // Script extensions run where the menu bar panel lists those that go on in the background (`ScriptTasks`).
        services.startScript = { script, arguments, environment, event in
            MainActor.assumeIsolated {
                ScriptTasks.shared.start(script, arguments: arguments, environment: environment, detached: false) { update in
                    switch update {
                    case let .update(update): event(.update(update))
                    case let .failed(error): event(.failed(error))
                    }
                }
            }
        }
        services.cancelScript = { run in MainActor.assumeIsolated { ScriptTasks.shared.cancel(run) } }
        services.detachScript = { run in MainActor.assumeIsolated { ScriptTasks.shared.detach(run) } }
        services.startScriptInBackground = { script, arguments, prepare, say in
            MainActor.assumeIsolated { ScriptTasks.shared.startInBackground(script, arguments: arguments, prepare: prepare, say: say) }
        }
        services.loadSearchKey = { WebSearch.loadKey() }
        services.takeRenameNotice = { BuiltinRenames.takeNotice($0) }
        services.noteDestination = { settings in MainActor.assumeIsolated { NoteSaving.destination(settings) } }
        services.parseReminder = { ReminderParser().parse($0, now: Date()) }
        services.addReminder = { _ = try await RemindersBridge.add($0) }
        services.loadContacts = {
            if case let .contacts(contacts) = await ContactBook.load() { return contacts }
            return nil
        }
        services.messageSender = AppleScriptMessageSender()
        return services
    }

    /// The kind of this Mac's own errors (Notes, Reminders) for the public log, without their text; nil: another's.
    static func macErrorKind(_ error: Error) -> String? {
        switch error {
        case NotesBridge.NotesError.notPermitted: return "notes not permitted"
        case let NotesBridge.NotesError.failed(number): return "notes error \(number)"
        case RemindersBridge.RemindersError.notPermitted: return "reminders not permitted"
        case RemindersBridge.RemindersError.noAccount: return "reminders no account"
        case RemindersBridge.RemindersError.notFound: return "reminder not found"
        case let RemindersBridge.RemindersError.failed(code): return "reminders error \(code)"
        default: return nil
        }
    }
}

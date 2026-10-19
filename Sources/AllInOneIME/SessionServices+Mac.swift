import AllInOneIMECore
import AllInOneIMEMac
import AppKit

extension SessionServices {
    /// This Mac's: the config file as of now, what UserDefaults keeps, Spotlight, Terminal, Notes or a folder or Notion,
    /// Reminders, Contacts and Messages, the keychain. Main thread only, but for the `@Sendable` ones.
    @MainActor
    static var mac: SessionServices {
        var services = SessionServices(converter: sharedConverter, loadSettings: { LiveConfig.current })
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
}

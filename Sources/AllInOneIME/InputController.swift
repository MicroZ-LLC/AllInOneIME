import AllInOneIMECore
import AllInOneIMERime
import AppKit
import Carbon
import InputMethodKit
import os

let log = Logger(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "ime")

/// One converter (one URLSession, one cache) shared by every input session in the process.
let sharedConverter = Converter()

/// Carries a main-thread-only object out of `MainActor.assumeIsolated` (we never leave the main thread).
struct MainThreadBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// An error already described for the user (`UIText.describe`), passed on as its message.
struct DescribedError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The installed plugins, scanned again when a text field becomes active (installing or removing one
/// shows up there) and at most every 30 seconds otherwise.
enum LivePlugins {
    private static var cached: (at: Date, result: (plugins: [InstalledPlugin], skipped: [PluginStore.Skipped]))?

    static func current(rescan: Bool = false) -> [InstalledPlugin] {
        if !rescan, let cached, Date().timeIntervalSince(cached.at) < 30 { return cached.result.plugins }
        let result = PluginStore.load()
        cached = (Date(), result)
        return result.plugins
    }
}

/// How much each @ command is used (the order of the command list), shared by every text field and kept
/// across launches.
enum CommandUsageStore {
    private static let key = "commandUsage"
    static var usage: CommandUsage = {
        guard let data = UserDefaults.standard.data(forKey: key),
              let usage = try? JSONDecoder().decode(CommandUsage.self, from: data) else { return CommandUsage() }
        return usage
    }()

    static func save(_ new: CommandUsage) {
        usage = new
        if let data = try? JSONEncoder().encode(new) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// The config file as of now, re-read only when it changed (checked by modification date).
/// A file that doesn't parse reads as the defaults here; conversions report the error.
enum LiveConfig {
    private static var cached: (date: Date?, config: Config)?

    static var current: Config {
        let url = Config.defaultURL
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let cached, cached.date == date { return cached.config }
        let config = (try? Config.load(from: url)) ?? .default
        cached = (date, config)
        return config
    }
}

/// The user's jargon list (for explaining the terms a jargon (黑话) line uses), re-read when the file changes.
enum LiveJargon {
    private static var cached: (url: URL, date: Date?, entries: [JargonEntry])?

    static func entries(for config: Config) -> [JargonEntry] {
        let url = config.jargonURL
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let cached, cached.url == url, cached.date == date { return cached.entries }
        let entries = date == nil ? [] : JargonLibrary.load(from: url)
        cached = (url, date, entries)
        return entries
    }
}

/// IMK creates one controller per client text session. All IMK callbacks arrive on the main
/// thread, so entry points hop into main-actor code with `MainActor.assumeIsolated`.
@objc(AllInOneIMEInputController)
final class AllInOneIMEInputController: IMKInputController {
    /// The input state machine. It asks `secureInputActive` before starting Claude Code.
    lazy var composer: Composer = {
        let composer = Composer()
        composer.secureInputActive = { [weak self] in self?.secureInputActive() ?? false }
        return composer
    }()
    private var session: RimeSession?
    /// Whether the app still has the text being typed (Slack may take it into a mention on its own).
    private var markedWatch = MarkedTextWatch()
    private var conversionTask: Task<Void, Never>?
    private var lastElapsed: TimeInterval?
    private var lastFromCache = false
    private var notice: String?
    /// Whether this text session has delivered a key yet (logged once, without the key).
    private var receivedKeys = false
    /// A dead key typed before the next key (`DeadKeyComposer`).
    private var deadKeys = DeadKeyComposer()
    /// Shown once each time composing gets paused for secure input.
    private var secureNoticeShown = false
    var converter: Converter = sharedConverter
    /// The command usage as kept, and keeping it (the self-test leaves the user's alone).
    var loadCommandUsage: () -> CommandUsage = { CommandUsageStore.usage }
    var saveCommandUsage: (CommandUsage) -> Void = { CommandUsageStore.save($0) }
    /// Whether secure event input is on anywhere; no text is sent to the model then.
    /// (The self-test replaces this to exercise both states.)
    var secureInputActive: () -> Bool = { SecureInput.isOn }
    /// Only set by the self-test: IMK refuses to create a controller for anything but its own
    /// client proxies, so the test injects its fake text field here.
    var clientOverride: IMKTextInput?
    /// The settings the controller follows (the self-test supplies its own).
    var loadSettings: () -> Config = { LiveConfig.current }
    /// `@open`: finds files and apps, what it opened before first (`loadOpenHistory`), and opens the one
    /// picked, which `recordOpen` keeps. The self-test opens nothing and keeps its history in memory.
    var searchFiles: @MainActor (_ query: String, _ history: OpenHistory) async -> [SearchResult] = {
        await FileSearch.run($0, history: $1)
    }
    /// Opens an `@open` result: a web address in the default browser, anything else as a file.
    var openItem: (String) -> Void = {
        NSWorkspace.shared.open(SearchResult(name: "", path: $0).webURL ?? URL(fileURLWithPath: $0))
    }
    var loadOpenHistory: () -> OpenHistory = { OpenHistoryStore.history }
    var recordOpen: (String) -> Void = { OpenHistoryStore.record($0) }
    /// `@claude`: starts Claude Code in Terminal (the self-test starts nothing).
    var runInTerminal: (String) throws -> Void = { try TerminalLauncher.claude($0) }
    /// A custom `terminal` command: runs its arguments in Terminal (the self-test starts nothing).
    var launchInTerminal: ([String]) throws -> Void = { try TerminalLauncher.launch($0) }
    /// `@note`: saves the text to Apple Notes (the self-test saves nothing).
    var saveNote: @MainActor (String) async throws -> Void = { _ = try await NotesBridge.save($0) }
    /// `@reminder`: reads the reminder in a text by the real clock (the self-test may supply its own), and
    /// adds a confirmed one to Apple Reminders (the self-test adds nothing).
    var parseReminder: (String) -> ReminderDraft = { ReminderParser().parse($0, now: Date()) }
    var addReminder: @MainActor (ReminderDraft) async throws -> Void = { _ = try await RemindersBridge.add($0) }
    /// Counts this controller's activations and deactivations: a save to Notes or Reminders that comes back to
    /// another count is no longer in the text field it came from (a failed one's text then goes to the
    /// clipboard instead of back into the draft).
    private(set) var fieldSession = 0
    /// The controller of the text field being typed in, if any: where the outcome of a save is told once the
    /// field it came from is gone.
    private(set) static weak var activeController: AllInOneIMEInputController?
    /// Whether a command's program is on this Mac (the self-test supplies its own). Called off the main thread.
    var programInstalled: @Sendable (String) -> Bool = { program in
        if program == "claude", TerminalLauncher.claudePath != nil { return true }
        if program.hasSuffix(".app") { return FileManager.default.fileExists(atPath: program) }  // a send command's app
        return CommandRunner.isInstalled(program, path: ShellEnvironment.current["PATH"])
    }
    /// The commands whose programs were last checked (`setCommands`), and those whose program is missing.
    private var checkedCommands: [Command] = []
    private var missingCommands: Set<String> = []
    /// The latest check (an older one that finishes later is ignored).
    private var programCheck = 0
    /// Background `@claude` tasks: starting one, the list, opening one (the self-test supplies its own).
    var startAgent: (String) async throws -> String = { try await AgentMonitor.shared.start($0) }
    var listAgents: () async throws -> [(session: AgentSession, reply: String?)] = { try await AgentMonitor.shared.list() }
    var openAgent: (String) -> Void = { id in MainActor.assumeIsolated { AgentMonitor.shared.open(id) } }
    /// A custom `run` command: runs its program in the background (the self-test supplies its own).
    var runProgram: (CustomCommand, String) -> AsyncThrowingStream<ConversionUpdate, Error> = { CommandRunner.run($0, input: $1) }
    /// A Raycast script: runs in the background with its arguments (the self-test supplies its own).
    var runScript: (RaycastScript, [String]) -> AsyncThrowingStream<ConversionUpdate, Error> = { CommandRunner.run($0, arguments: $1) }
    /// The Raycast scripts the command list offers for these settings (`rescan`: a text field became active,
    /// and Spotlight may look for script folders again). The self-test supplies its own: never the user's.
    var loadScripts: (Config, _ rescan: Bool) -> [RaycastScript] = { config, rescan in
        if rescan { LiveScripts.discoverIfDue(config) }
        return LiveScripts.current(config, rescan: rescan)
    }
    /// A script plugin: runs in this program's own child process (`--run-plugin`).
    var runPlugin: (InstalledPlugin, String) -> AsyncThrowingStream<ConversionUpdate, Error> = { PluginRunner.run($0, input: $1) }
    /// `@search`'s key: the keychain's, else the login shell's (the self-test supplies its own: it never reads
    /// the user's keychain). Called in the search's own task, off the main thread.
    var loadSearchKey: @Sendable () -> String? = { WebSearch.loadKey() }
    /// ⌘C on a result (the self-test leaves the clipboard alone).
    var copyText: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    /// ⌘V in a draft: the clipboard's text, or nil to let the app paste as usual (the self-test
    /// supplies its own and never reads the real clipboard).
    var readClipboard: () -> String? = { AllInOneIMEInputController.clipboardText(NSPasteboard.general) }

    /// Text on `pasteboard` to take into a draft. Nil for none, for what password managers mark as
    /// concealed or transient (nspasteboard.org, and the older markers), and when pasting from other
    /// apps is denied to this one.
    static func clipboardText(_ pasteboard: NSPasteboard) -> String? {
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny { return nil }
        let types = pasteboard.types ?? []
        let hidden = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword",
                      "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping", "Pasteboard generator type",
                      "net.antelle.keeweb"].map { NSPasteboard.PasteboardType(rawValue: $0) }
        guard types.contains(.string), hidden.allSatisfy({ !types.contains($0) }) else { return nil }
        return pasteboard.string(forType: .string)
    }
    /// `@imessage`: the address book (nil: no access), and sending (the self-test supplies stand-ins:
    /// never the real Contacts or Messages).
    var loadContacts: () async -> [Contact]? = {
        if case let .contacts(contacts) = await ContactBook.load() { return contacts }
        return nil
    }
    var messageSender: MessageSender = AppleScriptMessageSender()
    /// The handles last messaged, and keeping them (the self-test leaves the user's alone).
    var loadRecentHandles: () -> [String] = { RecentRecipients.handles }
    var saveRecentHandles: ([String]) -> Void = { RecentRecipients.handles = $0 }
    /// The recipient text last searched, and the search in flight for it.
    private var recipientSearchQuery: String?
    private var recipientSearchTask: Task<Void, Never>?
    /// The `@open` text last searched as it was typed, and the search in flight for it.
    private var liveSearchQuery: String?
    private var liveSearchTask: Task<Void, Never>?
    /// The default input mode last applied to this session (re-applied when the setting changes).
    private var appliedDefaultInput: Language?
    /// The keyboard layout this text field was last told to type with (`applyKeyboardLayout`).
    private var appliedLayout: String?
    /// The recording in progress (a `DictationSession`, which needs macOS 26).
    private var voiceSession: AnyObject?
    /// Identifies the latest press of the voice key (older hold timers are ignored).
    private var voiceArmToken = 0
    /// Self-test only: recognize this audio file instead of the microphone.
    var voiceFile: (url: URL, speed: Double)?
    /// False in the self-test: the microphone (and its permission prompt) is never touched.
    static var microphoneAllowed = true
    /// Whether marked text this controller set may be in the document. Empty marked text is only sent
    /// to clear it: with nothing marked, NSTextView puts (empty) marked text in place of the selection,
    /// deleting the selected text (a Shift tap, a focus change).
    private var hasMarkedText = false
    /// Whether a mouse button, a drag or the scroll wheel was used in the last `seconds`, anywhere: a
    /// Shift-click or ⌥-click is no tap of the key. The self-test replaces this.
    var pointerUsedWithin: (_ seconds: TimeInterval) -> Bool = { seconds in
        let kinds: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
                                    .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
        return kinds.contains { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) < seconds }
    }

    static let notFound = NSRange(location: NSNotFound, length: NSNotFound)

    // MARK: - IMK entry points

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        let client = sender as? IMKTextInput
        switch event.type {
        case .keyDown:
            return MainActor.assumeIsolated { handleKeyDown(event, client: client) }
        case .flagsChanged:
            MainActor.assumeIsolated { handleFlagsChanged(event, client: client) }
            return false  // the application must see modifier changes too
        default:
            return false
        }
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        MainActor.assumeIsolated {
            markedWatch.reset()  // another text field, maybe another app
            hasMarkedText = false
            appliedLayout = nil  // the layout is told to each text field
            fieldSession += 1
            Self.activeController = self
            ensureEngine()
            applySettings()
            // Terminals paste on ⌘V whatever the input method does: there ⌘V stays theirs.
            let app = (sender as? IMKTextInput)?.bundleIdentifier()
            composer.pastesIntoDraft = !(app.map(SecureInput.terminals.contains) ?? false)
        }
    }

    override func commitComposition(_ sender: Any!) {
        MainActor.assumeIsolated {
            stopTyping(insertingRest: true)  // the app wants everything in now (a click elsewhere in it)
            perform(composer.commitAll(), client: sender as? IMKTextInput)
        }
    }

    // MARK: - Typing a result out

    /// `Config.typeOutRate`, `typeOutVaries`: how fast (the self-test waits less).
    var typeOutRate = TypeOut.defaultRate
    var typeOutVaries = false
    var typeOutSleep: @Sendable (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    private var typingTask: Task<Void, Never>?
    private var typingRest: [Character] = []
    private var typingClient: IMKTextInput?
    /// Line breaks go in as a paste (a terminal; `TerminalPaste`).
    private var typingPastes = false

    /// Whether line breaks can go into a terminal as a paste, and pasting there (`TerminalPaste`; the
    /// self-test supplies its own and never posts keys or touches the clipboard).
    var canPasteInTerminal: @MainActor () -> Bool = { TerminalPaste.isAllowed() }
    var pasteInTerminal: @MainActor (String) async -> Void = { await TerminalPaste.paste($0) }

    /// Inserts `text` into `client`; into a terminal, text with line breaks goes in as a paste, so the
    /// line breaks don't run (or send) anything.
    @MainActor
    private func insert(_ text: String, into client: IMKTextInput?) {
        if text.contains("\n"), Self.isTerminal(client), canPasteInTerminal() {
            let paste = pasteInTerminal
            Task { @MainActor in await paste(text) }
        } else {
            client?.insertText(text, replacementRange: Self.notFound)
            hasMarkedText = false  // the inserted text took the marked text's place
        }
    }

    /// Types `text` into `client` character by character, like a person typing (`TypeOut.delays`).
    @MainActor
    private func typeOut(_ text: String, into client: IMKTextInput) {
        stopTyping(insertingRest: true)
        typingRest = Array(text)
        typingClient = client
        typingPastes = text.contains("\n") && Self.isTerminal(client) && canPasteInTerminal()
        let delays = TypeOut.delays(for: text, rate: typeOutRate, varies: typeOutVaries)
        let sleep = typeOutSleep
        log.notice("typing out \(text.count) characters")
        typingTask = Task { @MainActor [weak self] in
            for delay in delays {
                await sleep(delay)
                guard let self, !Task.isCancelled, let client = self.typingClient, !self.typingRest.isEmpty else { return }
                let character = self.typingRest.removeFirst()
                if character == "\n", self.typingPastes {
                    await self.pasteInTerminal("\n")
                } else {
                    client.insertText(String(character), replacementRange: Self.notFound)
                }
            }
            self?.typingTask = nil
            self?.typingClient = nil
        }
    }

    /// Stops typing out: the rest goes in at once, or (Esc, the field lost) isn't typed.
    @MainActor
    func stopTyping(insertingRest: Bool) {
        guard let task = typingTask else { return }
        task.cancel()
        if insertingRest, !typingRest.isEmpty { insert(String(typingRest), into: typingClient) }
        log.notice("typing out stopped (\(insertingRest ? "the rest inserted" : "the rest dropped"), privacy: .public)")
        (typingTask, typingRest, typingClient, typingPastes) = (nil, [], nil, false)
    }

    /// Whether a result is being typed out now (the self-test).
    var isTypingOut: Bool { typingTask != nil }

    override func deactivateServer(_ sender: Any!) {
        MainActor.assumeIsolated {
            stopTyping(insertingRest: false)  // another field has the focus now: the rest isn't typed anywhere
            perform(composer.commitAll(), client: sender as? IMKTextInput)
            fieldSession += 1
            if Self.activeController === self { Self.activeController = nil }
        }
        super.deactivateServer(sender)
    }

    override func composedString(_ sender: Any!) -> Any! {
        composer.markedText
    }

    override func inputControllerWillClose() {
        MainActor.assumeIsolated {
            conversionTask?.cancel()
            conversionTask = nil
            cancelVoiceSession()
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(noticeExpired), object: nil)
            hidePanelIfOwned()
            composer.engine = nil
            session = nil
            fieldSession += 1  // a save still on its way tells its outcome elsewhere
            if Self.activeController === self { Self.activeController = nil }
        }
        super.inputControllerWillClose()
    }

    override func menu() -> NSMenu! {
        log.notice("input menu requested")
        return MainActor.assumeIsolated { MainThreadBox(makeMenu()) }.value
    }

    // MARK: - Level one engine

    /// Creates the Rime session once librime has finished deploying (and again after a re-deploy).
    /// Without the Chinese pack librime never starts: English letters (`LatinEngine`), so typing and
    /// commands work; while it deploys, keys go through as before.
    @MainActor
    func ensureEngine() {
        if let session, session.isValid { return }
        guard let fresh = RimeService.shared.makeSession() else {
            session = nil
            if RimeService.shared.isStarted {
                composer.engine = nil
            } else if !(composer.primaryEngine is LatinEngine) {  // `engine` is Hindi's while Hindi is typed
                composer.engine = LatinEngine()
                appliedDefaultInput = nil
                applySettings()
            }
            return
        }
        session = fresh
        composer.engine = fresh
        appliedDefaultInput = nil  // a new session starts in the default input mode
        applySettings()
    }

    /// Takes over the current settings: voice key, action key, and the default input mode (applied to
    /// new sessions, and again when the setting changes; a Shift toggle otherwise sticks).
    @MainActor
    func applySettings() {
        let config = loadSettings()
        composer.voiceEnabled = config.voiceInput && VoiceInput.isSupported
        composer.actionKey = config.actionKey
        composer.claudeInBackground = config.claudeInBackground
        composer.typesResults = config.typeOut
        (typeOutRate, typeOutVaries) = (config.typeOutRate, config.typeOutVaries)
        setCommands(Command.catalog(config.customCommands, plugins: LivePlugins.current(rescan: true),
                                    scripts: loadScripts(config, true)), recheck: true)
        // The interface language (config `uiLanguage`, else the system's) for the panel, notices and menu.
        UIText.choice = config.uiLanguage
        composer.messages = UIText.chinese ? .chinese : .english
        composer.messages.actionKeyName = UIText.name(config.actionKey)
        // Only the languages whose pack is installed: Chinese is no input mode while its pack downloads.
        // The Korean and Hindi packs' data, for their input (nil without the pack).
        composer.hangulTables = LanguagePackManager.shared.hangulTables()
        composer.hindiTables = LanguagePackManager.shared.hindiTables()
        let languages = LanguagePackManager.shared.usable(config.inputLanguages)
        let defaultInput = languages.contains(config.defaultInput) ? config.defaultInput : languages[0]
        composer.inputLanguages = languages
        // With one input language, a field is always in it (it may have been switched before it was the only one).
        let onlyOne = languages.count == 1
        if appliedDefaultInput != defaultInput || onlyOne, composer.engine != nil, !composer.isComposing {
            composer.setInputMode(defaultInput)
            appliedDefaultInput = defaultInput
        }
        applyKeyboardLayout(config: config)
    }

    /// Types with the keyboard layout of the input language in effect: French with its own (AZERTY by
    /// default, `Config.keyboardLayouts`), the others with the one the user picked in the system (or for
    /// English). macOS translates the keys with it for this text field, typing and shortcuts alike.
    @MainActor
    private func applyKeyboardLayout(config: Config? = nil, client: IMKTextInput? = nil) {
        let config = config ?? loadSettings()
        let language = composer.inputLanguage
        let id = config.keyboardLayout(for: language.isLatin ? language : .english) ?? Self.systemLayoutID
        guard let id, id != appliedLayout, let target = client ?? clientOverride ?? self.client() else { return }
        target.overrideKeyboard(withKeyboardNamed: id)
        appliedLayout = id
    }

    /// The layout the user types Latin letters with in the system's input sources (U.S., ABC, AZERTY …).
    private static var systemLayoutID: String? {
        TISCopyCurrentASCIICapableKeyboardLayoutInputSource().flatMap { KeyboardLayout(source: $0.takeRetainedValue())?.id }
    }

    /// Takes over the commands "@" offers, without those whose program isn't on this Mac (`@claude`
    /// without Claude Code, a custom command's missing `argv[0]`): "@claude …" is then just text, like
    /// "@name". Which are missing is checked in the background when the commands changed, or with
    /// `recheck` (a text field became active: something may have been installed meanwhile).
    @MainActor
    func setCommands(_ commands: [Command], recheck: Bool = false) {
        composer.commands = commands.filter { !missingCommands.contains($0.name) }
        guard recheck || commands != checkedCommands else { return }
        checkedCommands = commands
        programCheck += 1
        let check = programCheck
        let needed = commands.compactMap { command in command.program.map { (command.name, $0) } }
        let installed = programInstalled
        DispatchQueue.global().async { [weak self] in
            // The first check asks the user's shell for its PATH, which takes a moment.
            let missing = Set(needed.filter { !installed($0.1) }.map(\.0))
            DispatchQueue.main.async {
                guard let self, self.programCheck == check else { return }
                if !missing.isEmpty { log.notice("commands hidden, their program isn't installed: \(missing.count)") }
                self.missingCommands = missing
                // Not while a command is being written: the draft keeps the commands it started with.
                if !self.composer.isComposing { self.composer.commands = commands.filter { !missing.contains($0.name) } }
            }
        }
    }

    // MARK: - Keys

    @MainActor
    func handleKeyDown(_ event: NSEvent, client: IMKTextInput?) -> Bool {
        // A result still being typed out: Esc stops it there; any other key types the rest at once,
        // then goes on as usual.
        if TerminalPaste.isOurs(event) { return false }  // a line break being pasted into a terminal
        if typingTask != nil {
            if event.keyCode == VirtualKey.escape {
                stopTyping(insertingRest: false)
                return true
            }
            // In a terminal the rest is pasted, after this key would arrive: the key only finishes typing.
            let pastesRest = typingPastes && typingRest.contains("\n")
            stopTyping(insertingRest: true)
            if pastesRest { return true }
        }
        if !receivedKeys {
            receivedKeys = true
            log.notice("receiving keys (engine ready: \(RimeService.shared.isReady))")
        }
        // Password fields and prompts turn on secure event input. Never compose (so nothing can be
        // sent to the model) in the app that turned it on; anything already typed goes in as typed.
        let target: IMKTextInput? = client ?? clientOverride ?? self.client()
        if SecureInput.blocksComposing(target) {
            if composer.isComposing {
                let ended = composer.commitAsTyped()
                perform(ended, client: client)
                // A note that couldn't go in as typed says its text is on the clipboard: that notice stays up.
                if ended.contains(where: { if case .notice = $0 { return true } else { return false } }) { secureNoticeShown = true }
            }
            if !secureNoticeShown, let chars = event.characters, !chars.isEmpty,
               event.modifierFlags.isDisjoint(with: [.command, .control]) {
                secureNoticeShown = true
                perform([.notice(tr("安全输入中：输入法暂停，按键直接输入", "Secure input: the input method is paused, keys go straight in"))],
                        client: client)
            }
            return false
        }
        secureNoticeShown = false
        // The app took the text being typed without saying so (Slack, on an "@…"): start over rather than
        // show the draft again, doubled. This key is dropped, so ⏎ doesn't send half a sentence.
        if composer.isComposing, let target,
           markedWatch.appTookText(expected: composer.markedText, reportedLength: Self.markedLength(target)) {
            log.notice("the app took the marked text: starting over")
            perform(composer.appTookMarkedText(), client: client)
            return true
        }
        ensureEngine()
        // Commands added to the config apply from the next sentence on (the file is re-read only when it changed).
        if !composer.isComposing {
            let config = loadSettings()
            setCommands(Command.catalog(config.customCommands, plugins: LivePlugins.current(), scripts: loadScripts(config, false)))
            composer.commandUsage = loadCommandUsage()  // another text field may have run commands
            composer.claudeInBackground = loadSettings().claudeInBackground
        }
        // Dead keys aren't composed for an input method: done here, from the layout the keys come from.
        if composer.pendingAccent == nil { deadKeys.reset() }
        let key = deadKeys.compose(KeyEvent(
            keyCode: event.keyCode, characters: event.characters ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            modifiers: Self.modifiers(event.modifierFlags), isRepeat: event.isARepeat),
            in: appliedLayout.flatMap(KeyboardLayout.init(id:)) ?? KeyboardLayout.current())
        let response = composer.handleKeyDown(key)
        if composer.pendingAccent == nil { deadKeys.reset() }
        perform(response.effects, client: client)
        return response.handled
    }

    @MainActor
    func handleFlagsChanged(_ event: NSEvent, client: IMKTextInput?) {
        guard !SecureInput.blocksComposing(client ?? clientOverride ?? self.client()) else {
            // A password field took over: stop any recording (its release may never arrive here).
            if composer.voice != .off { perform(composer.commitAsTyped(), client: client) }
            return
        }
        ensureEngine()
        // The key was held up to the event; the pointer is asked later, so look back that much further.
        let late = max(ProcessInfo.processInfo.systemUptime - event.timestamp, 0)
        composer.pointerUsedWithin = { [pointerUsedWithin] in pointerUsedWithin($0 + late) }
        perform(composer.handleFlagsChanged(keyCode: event.keyCode, modifiers: Self.flagsChangedModifiers(event.modifierFlags),
                                            timestamp: event.timestamp),
                client: client)
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.capsLock) { result.insert(.capsLock) }
        return result
    }

    /// Device-dependent bits of NSEvent.modifierFlags (NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK).
    static let leftOptionBit: UInt = 0x20, rightOptionBit: UInt = 0x40

    /// Modifiers of a modifier-change event, including which Option key is down.
    static func flagsChangedModifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var result = modifiers(flags)
        if flags.rawValue & leftOptionBit != 0 { result.insert(.leftOption) }
        if flags.rawValue & rightOptionBit != 0 { result.insert(.rightOption) }
        return result
    }

    /// Whether an Option key is still down with no mouse button pressed, as a sanity check when the
    /// hold timer fires (the composer tracks which key from the events). The self-test replaces this.
    var isVoiceKeyHeld: () -> Bool = {
        NSEvent.modifierFlags.contains(.option) && NSEvent.pressedMouseButtons == 0
    }

    // MARK: - Effects

    @MainActor
    func perform(_ effects: [Composer.Effect], client: IMKTextInput?) {
        let target: IMKTextInput? = client ?? clientOverride ?? self.client()
        for effect in effects {
            switch effect {
            case .updateMarkedText:
                updateMarkedText(target)
            case .inputLanguageChanged:
                applyKeyboardLayout(client: target)
            case let .commit(text):
                insert(text, into: target)
            case let .typeOut(text):
                if let target { typeOut(text, into: target) }
            case let .startConversion(input, id):
                if refusedForSecureInput(id: id, client: target) { break }
                // @improve / @translate: the mode (and a second one written inside) comes from the command.
                startConversion(input, id: id, command: composer.activeCommand?.kind == .convert ? composer.activeCommand : nil)
            case let .startCommand(command, input, id):
                if refusedForSecureInput(id: id, client: target) { break }
                startConversion(input, id: id, command: command)
            case let .startPlan(outer, plan, id):
                // Inner commands run programs or reach the network: refused during secure input like any.
                if refusedForSecureInput(id: id, client: target, running: true) { break }
                startConversion("", id: id, command: outer, plan: plan)
            case let .startRun(command, input, id):
                if refusedForSecureInput(id: id, client: target, running: true) { break }
                startConversion(input, id: id, command: command)
            case let .startScript(command, arguments, id):
                if refusedForSecureInput(id: id, client: target, running: true) { break }
                startConversion("", id: id, command: command, arguments: arguments)
            case let .search(query, id):
                conversionTask?.cancel()
                conversionTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    let results = await self.searchFiles(query, self.loadOpenHistory())
                    guard !Task.isCancelled else { return }
                    log.notice("search \(id): \(results.count) results")
                    self.perform(self.composer.receiveSearch(results, id: id), client: nil)
                }
            case let .open(path):
                if let agent = SearchResult(name: "", path: path).agentID {
                    openAgent(agent)  // a background task: in Terminal
                    break
                }
                log.notice("opening an @open result")
                openItem(path)
                // Listed first by the next searches (files only: a web address is typed again).
                if SearchResult(name: "", path: path).webURL == nil { recordOpen(path) }
            case let .openLink(url):
                // The site is public (a plugin's or the user's own template); the text in it is not.
                log.notice("link command: opening \(url.host ?? "-", privacy: .public) in the browser")
                openItem(url.absoluteString)
            case let .startBackgroundAgent(prompt):
                Task { @MainActor [weak self] in
                    do {
                        _ = try await self?.startAgent(prompt)
                    } catch {
                        log.error("@claude in the background failed: \(String(describing: error), privacy: .public)")
                        self?.showNotice(UIText.describe(error), client: nil)
                    }
                }
            case .openSettings:
                SettingsWindow.shared.show()
            case let .listAgents(id):
                conversionTask?.cancel()
                conversionTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    let results: [SearchResult]
                    do {
                        results = try await self.listAgents().map { session, reply in
                            let mark = session.progress == .done ? "✓" : session.progress == .needsYou ? "⚠︎" : "…"
                            return SearchResult(name: "\(mark) \(session.name ?? session.shortID)",
                                                path: SearchResult.agentPrefix + session.shortID, detail: reply)
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        self.perform(self.composer.fail(UIText.describe(error), id: id), client: nil)
                        return
                    }
                    guard !Task.isCancelled else { return }
                    self.perform(self.composer.receiveSearch(results, id: id), client: nil)
                }
            case let .runInTerminal(prompt):
                do {
                    try runInTerminal(prompt)
                    log.notice("@claude: Terminal session started (\(prompt.count) chars)")
                } catch {
                    log.error("@claude: could not start Terminal: \(String(describing: error), privacy: .public)")
                    showNotice(UIText.describe(error), client: target)
                }
            case .commandUsed:
                saveCommandUsage(composer.commandUsage)
            case let .launchInTerminal(argv):
                do {
                    try launchInTerminal(argv)
                    log.notice("custom command: Terminal started (\(argv.count) arguments)")
                } catch {
                    log.error("custom command: could not start Terminal: \(String(describing: error), privacy: .public)")
                    showNotice(UIText.describe(error), client: target)
                }
            case let .saveNote(text):
                // Kept on this Mac, nothing goes to a model: not refused while secure input is on, unlike the
                // requests above (the field that turned it on doesn't compose at all).
                saveToNotes(text)
            case let .previewReminder(input, id):
                // Read here by the real clock (NSDataDetector and the parser's own rules), quick enough for
                // a keystroke. Nothing leaves the Mac, so secure input doesn't hold it back either.
                perform(composer.receiveReminder(parseReminder(input), id: id), client: target)
            case let .addReminder(reminder, input):
                addToReminders(reminder, input: input)
            case let .copy(text):
                copyText(text)
            case let .sendMessage(recipient, text, command):
                sendMessage(text, to: recipient, command: command, client: target)
            case let .readClipboard(id):
                // After the key has been answered: if macOS asks whether this may read the clipboard,
                // the app isn't left waiting for the key (and doesn't paste on its own meanwhile).
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let text = self.readClipboard()
                    // Only how much: never the text itself.
                    log.notice("clipboard for a command: \(text.map { "\($0.count) chars" } ?? "no usable text", privacy: .public)")
                    self.perform(self.composer.pasted(text, id: id), client: nil)
                }
            case .cancelConversion:
                conversionTask?.cancel()
                conversionTask = nil
            case .showPanel:
                showPanel(target)
            case .hidePanel:
                hidePanelIfOwned()
            case let .notice(text):
                // A note left unsaved, its text on the clipboard: up as long as the other "on the clipboard" notices.
                showNotice(text, client: target, long: text == composer.messages.noteNotSaved)
            case let .armVoice(delay):
                voiceArmToken += 1
                let token = voiceArmToken
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, token == self.voiceArmToken else { return }
                    self.perform(self.composer.voiceHoldElapsed(stillHeld: self.isVoiceKeyHeld()), client: nil)
                }
            case let .startVoice(id, language):
                startVoice(id: id, language: language)
            case let .stopVoice(id):
                stopVoice(id: id)
            case let .cancelVoice(id):
                cancelVoiceSession(id: id)
            }
        }
        scheduleLiveSearch()
        scheduleRecipientSearch()
    }

    /// A send command's recipient as it is typed: a short pause, then the contacts that match (Contacts
    /// access is asked for here, the first time).
    @MainActor
    private func scheduleRecipientSearch() {
        let query = composer.recipientQuery
        guard query != recipientSearchQuery else { return }
        recipientSearchQuery = query
        recipientSearchTask?.cancel()
        guard let query else { return }
        let recent = loadRecentHandles()
        recipientSearchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard let self, !Task.isCancelled else { return }
            let contacts = await self.loadContacts()
            guard !Task.isCancelled else { return }
            let found = await Task.detached { RecipientSearch.results(query, contacts: contacts ?? [], recent: recent) }.value
            guard !Task.isCancelled else { return }
            let note = contacts == nil
                ? tr("没有通讯录权限：系统设置 → 隐私与安全性 → 通讯录 → 打开 AllInOneIME；也可以直接输入手机号或邮箱",
                     "No access to Contacts: System Settings → Privacy & Security → Contacts → turn on AllInOneIME; or type a phone number or email")
                : found.isEmpty ? (query.isEmpty ? tr("输入名字、拼音、手机号或邮箱", "Type a name, phone number or email")
                                                 : tr("没有找到联系人；也可以输入完整的手机号或邮箱", "No contact found; or type a full phone number or email"))
                : nil
            self.perform(self.composer.receiveRecipients(found, note: note, for: query), client: nil)
        }
    }

    /// Sends a confirmed message off the main thread; a notice says how it went. The log keeps no
    /// names, handles or text.
    @MainActor
    private func sendMessage(_ text: String, to recipient: Recipient, command: Command, client: IMKTextInput?) {
        guard !secureInputActive() else {
            showNotice(tr("系统安全输入已开启（密码框或锁屏），没有发送", "Secure input is on (a password field or the lock screen): nothing was sent"),
                       client: client)
            return
        }
        log.notice("@\(command.name, privacy: .public): sending (\(text.count) chars)")
        let sender = messageSender
        Task { @MainActor [weak self] in
            do {
                try await sender.send(text, to: recipient)
                log.notice("@\(command.name, privacy: .public): sent")
                guard let self else { return }
                self.saveRecentHandles(RecipientSearch.remember(recipient.handle, in: self.loadRecentHandles()))
                self.showNotice(tr("已发送给 ", "Sent to ") + recipient.displayName, client: nil)
            } catch {
                let code: String
                switch error {
                case MessageSendError.notPermitted: code = "-1743"
                case let MessageSendError.failed(number): code = String(number)
                default: code = String(describing: type(of: error))
                }
                log.error("@\(command.name, privacy: .public): sending failed (\(code, privacy: .public))")
                self?.showNotice(UIText.describe(error), client: nil)
            }
        }
    }

    /// `@open` as you type: a short pause after the text changes, then a search for it. Not for a single
    /// letter (`FileSearchRanking.searchesAsYouType`): that takes seconds; ⏎ searches it.
    @MainActor
    private func scheduleLiveSearch() {
        let query = composer.liveQuery
        guard query != liveSearchQuery else { return }
        liveSearchQuery = query
        liveSearchTask?.cancel()
        guard let query, FileSearchRanking.searchesAsYouType(query) else { return }
        liveSearchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            let results = await self.searchFiles(query, self.loadOpenHistory())
            guard !Task.isCancelled else { return }
            self.perform(self.composer.receiveLive(results, for: query), client: nil)
        }
    }

    // MARK: - Notes and Reminders

    /// `@note`: the text goes to Notes in the background (the first time, macOS asks whether this may
    /// control Notes, and the save waits for the answer). 「正在存到备忘录…」 at once, up until a notice says it is
    /// saved, or why not (`progressNoticeLimit` at most); a text that couldn't be saved is never lost
    /// (`SaveOutcome`). Only its length is logged.
    @MainActor
    private func saveToNotes(_ text: String) {
        log.notice("@note: saving \(text.count) chars")
        let progress = tr("正在存到备忘录…", "Saving to Notes…")
        showNotice(progress, client: nil, lasting: Self.progressNoticeLimit)
        let (save, outcome) = (saveNote, SaveOutcome(from: self, progress: progress))
        Task { @MainActor in
            do {
                try await save(text)
                log.notice("@note: saved")
                outcome.saved(tr("已存到备忘录", "Saved to Notes"))
            } catch {
                log.error("@note: not saved: \(Self.errorKind(error), privacy: .public)")
                outcome.failed(error, command: .note, text: text)
            }
        }
    }

    /// A confirmed `@reminder`: added to Reminders in the background (the first time, macOS asks for
    /// access, and this waits for the answer). 「正在加到提醒事项…」 at once, up until the notice says when it is
    /// due (「已加到提醒事项：明天 15:00」), or why it wasn't added (`progressNoticeLimit` at most): then `input`, the
    /// text it was read from, comes back (`SaveOutcome`).
    @MainActor
    private func addToReminders(_ reminder: ReminderDraft, input: String) {
        let kind = reminder.due == nil ? "no date" : reminder.hasTime ? "a time" : "a day"
        log.notice("@reminder: adding one with \(kind, privacy: .public)")
        let progress = tr("正在加到提醒事项…", "Adding to Reminders…")
        showNotice(progress, client: nil, lasting: Self.progressNoticeLimit)
        let (add, outcome) = (addReminder, SaveOutcome(from: self, progress: progress))
        Task { @MainActor in
            do {
                try await add(reminder)
                log.notice("@reminder: added")
                let when = reminder.due == nil ? "" : tr("：", ": ") + UIText.when(reminder)
                outcome.saved(tr("已加到提醒事项", "Added to Reminders") + when)
            } catch {
                log.error("@reminder: not added: \(Self.errorKind(error), privacy: .public)")
                outcome.failed(error, command: .reminder, text: input)
            }
        }
    }

    /// How a save to Notes or Reminders went, told where the user is when it comes back, even if the text field
    /// it came from (and its controller) is gone by then; made when the save starts, without keeping the
    /// controller alive. A failed save loses nothing: its text is back in the draft when that field is still
    /// there with nothing being typed, else on the clipboard; on the clipboard as well when the user has to fix
    /// something first (`needsTheUser`): going to System Settings takes the focus, which commits the draft.
    @MainActor
    struct SaveOutcome {
        private weak var origin: AllInOneIMEInputController?
        private let session: Int
        private let copy: (String) -> Void
        /// The notice shown while the save is under way (「正在存到备忘录…」), replaced by the outcome.
        private let progress: String

        init(from controller: AllInOneIMEInputController, progress: String) {
            origin = controller
            session = controller.fieldSession
            copy = controller.copyText
            self.progress = progress
        }

        /// The field the save came from, while it is still the same one.
        private var field: AllInOneIMEInputController? { origin.flatMap { $0.fieldSession == session ? $0 : nil } }

        func saved(_ notice: String) { tell(notice, long: false) }

        func failed(_ error: Error, command: Command, text: String) {
            let reason = UIText.describe(error)
            let needsTheUser = AllInOneIMEInputController.needsTheUser(error)
            if let field, let effects = field.composer.restoreDraft(command, text: text) {
                field.perform(effects, client: nil)
                if needsTheUser { copy(text) }
                field.showNotice(needsTheUser ? tr("原文也复制到了剪贴板。", "The text is on the clipboard too. ") + reason : reason,
                                 client: nil, long: needsTheUser)
                return
            }
            copy(text)
            tell(tr("没有存上，原文已复制到剪贴板。", "Not saved; the text is on the clipboard. ") + reason, long: true)
        }

        /// In the field it came from, else the one being typed in now, else near the pointer. The progress
        /// notice, if still up where the save started, goes then.
        private func tell(_ notice: String, long: Bool) {
            let target = field ?? AllInOneIMEInputController.activeController
            if let origin, origin !== target { origin.endNotice(progress) }
            if let target {
                target.showNotice(notice, client: nil, long: long)
            } else {
                AllInOneIMEInputController.showLooseNotice(notice, long: long)
            }
        }
    }

    /// The longest 「正在存到备忘录…」 / 「正在加到提醒事项…」 stays up: the outcome replaces it, but that can take a
    /// while (Notes launching, the first permission prompt waiting for an answer). The self-test shortens it.
    static var progressNoticeLimit: TimeInterval = 20

    /// Errors only the user can fix (a permission, an account): their notice stays up longer.
    static func needsTheUser(_ error: Error) -> Bool {
        switch error {
        case NotesBridge.NotesError.notPermitted, RemindersBridge.RemindersError.notPermitted,
             RemindersBridge.RemindersError.noAccount:
            return true
        default:
            return false
        }
    }

    /// Owns the candidate panel while it shows a notice no text field is there for.
    private static let looseNoticeOwner = NSObject()

    /// A notice with no text field to show it at: on its own, near the pointer.
    @MainActor
    static func showLooseNotice(_ text: String, long: Bool) {
        let panel = CandidatePanel.shared
        panel.owner = looseNoticeOwner
        panel.onSelect = nil
        var model = CandidateView.Model()
        model.status = .hint(text)
        panel.show(model, anchor: .zero)  // an empty anchor: at the mouse pointer
        DispatchQueue.main.asyncAfter(deadline: .now() + noticeDuration(text, long: long)) {
            if panel.owner === looseNoticeOwner { panel.hide() }
        }
    }

    /// How long a notice stays up: by its length, and longer for what the user has to act on.
    static func noticeDuration(_ text: String, long: Bool) -> TimeInterval {
        long ? 12 : min(5, 1.2 + Double(text.count) * 0.06)
    }

    // MARK: - Voice

    @MainActor
    private func startVoice(id: Int, language: Language) {
        guard #available(macOS 26.0, *), VoiceInput.isSupported else {
            perform(composer.voiceFailed(UIText.describe(VoiceError.unsupportedSystem), id: id), client: nil)
            return
        }
        if voiceFile == nil {
            guard Self.microphoneAllowed else {
                perform(composer.voiceFailed(tr("（自检）没有音频文件，不使用麦克风", "(self-test) no audio file; the microphone stays off"),
                                             id: id), client: nil)
                return
            }
            switch VoiceInput.microphoneAccess {
            case .granted:
                break
            case .notDetermined:
                perform(composer.voiceFailed(tr("请在弹窗里允许使用麦克风，然后再按住右 ⌥ 说话",
                                                "Allow the microphone in the dialog, then hold right ⌥ again"), id: id),
                        client: nil)
                Task { _ = await VoiceInput.requestMicrophoneAccess() }
                return
            case .denied:
                perform(composer.voiceFailed(tr("没有麦克风权限：系统设置 → 隐私与安全性 → 麦克风 → 打开 AllInOneIME",
                                                "No microphone access: System Settings → Privacy & Security → Microphone → turn on AllInOneIME"),
                                             id: id),
                        client: nil)
                return
            }
        }
        if let progress = VoiceInput.downloads[language] {
            perform(composer.voiceFailed(String(format: tr("%@语音模型下载中 %.0f%%，好了会提示",
                                                           "Downloading the %@ speech model: %.0f%%. You'll be told when it's ready"),
                                                UIText.name(language), progress * 100), id: id), client: nil)
            return
        }
        cancelVoiceSession()  // never two recordings at once
        let session = DictationSession(
            id: id, language: language,
            onText: { [weak self] text in
                guard let self else { return }
                self.perform(self.composer.voiceText(text, id: id), client: nil)
            },
            onFinish: { [weak self] result in
                self?.voiceDidFinish(result, id: id, language: language)
            })
        voiceSession = session
        log.notice("voice \(id) started (\(language.rawValue, privacy: .public))")
        session.start(source: voiceFile.map { .file($0.url, speed: $0.speed) } ?? .microphone)
    }

    @MainActor
    private func stopVoice(id: Int) {
        guard #available(macOS 26.0, *), let session = voiceSession as? DictationSession, session.id == id else { return }
        session.stop()
        scheduleVoiceFallback(id: id, heard: composer.voice.text, waited: 0)
    }

    /// If recognition never finishes, keep what was heard so far. While text is still coming in
    /// (e.g. the model was loading when the key was released) it waits longer, up to 20 s.
    @MainActor
    private func scheduleVoiceFallback(id: Int, heard: String, waited: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.composer.voice.id == id else { return }
            let now = self.composer.voice.text
            if now != heard || now.isEmpty, waited < 15 {
                self.scheduleVoiceFallback(id: id, heard: now, waited: waited + 5)
                return
            }
            log.error("voice \(id): no final transcript after \(waited + 5)s")
            self.cancelVoiceSession(id: id)
            self.perform(self.composer.voiceFinished(now, id: id), client: nil)
        }
    }

    /// Stops the recording `id` (any recording when nil) and discards its result.
    @MainActor
    private func cancelVoiceSession(id: Int? = nil) {
        guard #available(macOS 26.0, *), let session = voiceSession as? DictationSession,
              id == nil || session.id == id else { return }
        session.cancel()
        voiceSession = nil
    }

    @MainActor
    private func voiceDidFinish(_ result: Result<String, Error>, id: Int, language: Language) {
        if #available(macOS 26.0, *), (voiceSession as? DictationSession)?.id == id { voiceSession = nil }
        switch result {
        case let .success(text):
            log.notice("voice \(id) finished (\(text.count) chars)")
            perform(composer.voiceFinished(text, id: id), client: nil)
        case let .failure(VoiceError.modelMissing(missing)):
            let name = UIText.name(missing)
            perform(composer.voiceFailed(tr("首次使用：正在下载\(name)语音模型，好了会提示",
                                            "First use: downloading the \(name) speech model. You'll be told when it's ready"),
                                         id: id), client: nil)
            VoiceInput.startDownload(missing) { [weak self] error in
                self?.showNotice(error.map { tr("语音模型下载失败：", "Speech model download failed: ") + UIText.describe($0) }
                                 ?? tr("\(name)语音模型已就绪：按住右 ⌥ 说话", "\(name) speech model ready: hold right ⌥ to talk"),
                                 client: nil)
            }
        case let .failure(error):
            log.error("voice \(id) failed: \(String(describing: error), privacy: .public)")
            perform(composer.voiceFailed(UIText.describe(error), id: id), client: nil)
        }
    }

    @MainActor
    private func updateMarkedText(_ client: IMKTextInput?) {
        guard let client else { return }
        let text = composer.markedText
        guard !text.isEmpty else {
            // Nothing of ours is marked: leave the document (and any selection in it) alone.
            guard hasMarkedText || (Self.markedLength(client) ?? 0) > 0 else { return }
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: Self.notFound)
            hasMarkedText = false
            return
        }
        let length = (text as NSString).length
        let style = composer.isLevelTwo ? kTSMHiliteSelectedConvertedText : kTSMHiliteRawText
        let attributed = NSAttributedString(
            string: text, attributes: markAttributes(style: style, range: NSRange(location: 0, length: length)))
        let cursor = String(text.prefix(composer.markedCursor)).utf16.count
        client.setMarkedText(
            attributed, selectionRange: NSRange(location: cursor, length: 0), replacementRange: Self.notFound)
        hasMarkedText = true
        markedWatch.didSet(expected: text, reportedLength: Self.markedLength(client))
    }

    /// The length of the app's marked text, or nil when it reports none.
    static func markedLength(_ client: IMKTextInput) -> Int? {
        let range = client.markedRange()
        return range.location == NSNotFound ? nil : range.length
    }

    private func markAttributes(style: Int, range: NSRange) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        for (key, value) in mark(forStyle: style, at: range) ?? [:] {
            if let name = key as? String {
                attributes[NSAttributedString.Key(name)] = value
            } else if let name = key as? NSAttributedString.Key {
                attributes[name] = value
            }
        }
        if attributes.isEmpty {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    // MARK: - Level two

    /// While secure input is on anywhere (a password field or prompt may be active), nothing is sent
    /// off the Mac: the request fails at once. True if refused.
    @MainActor
    private func refusedForSecureInput(id: Int, client: IMKTextInput?, running: Bool = false) -> Bool {
        guard secureInputActive() else { return false }
        log.info("conversion \(id) not sent: secure input \(SecureInput.ownerDescription(), privacy: .public)")
        let message = running
            ? tr("系统安全输入已开启（密码框或锁屏），没有运行命令",
                 "Secure input is on (a password field or the lock screen): the command was not run")
            : tr("系统安全输入已开启（密码框或锁屏），未发送给 AI",
                 "Secure input is on (a password field or the lock screen): nothing was sent to the AI")
        perform(composer.fail(message, id: id), client: client)
        return true
    }

    /// Streams level two for `input`: the improve conversion, a `.generate` command's answer, or what a
    /// `.run` command's program printed.
    /// Whether `config` has a language to translate `input` into other than its own.
    static func hasTranslationTarget(for input: String, config: Config) -> Bool {
        let own = OutputLanguage(config.language(of: input))
        return config.outputLanguages.contains { $0 != own }
    }

    /// Opens the settings window on `page` (the self-test records it instead).
    var openSettings: @MainActor (SettingsPage) -> Void = { SettingsWindow.shared.show(page: $0) }

    @MainActor
    private func startConversion(_ input: String, id: Int, command: Command? = nil, plan: CommandPlan? = nil,
                                 arguments: [String] = []) {
        conversionTask?.cancel()
        lastElapsed = nil
        lastFromCache = false
        // Plugin names are public (from the library); custom command and script names are the user's own.
        func logged(_ command: Command) -> String {
            command.script != nil ? "script" : command.custom == nil || command.plugin != nil ? command.name : "custom"
        }
        let inner = plan.map { ", inside: " + $0.inner.map { "@" + logged($0.command) }.joined(separator: " ") } ?? ""
        log.notice("conversion \(id) started (\(input.count) chars\(command.map { ", @\(logged($0))" } ?? "")\(inner), privacy: .public))")
        // @translate with no language to translate into but the sentence's own (a new user whose system has no
        // other language): nothing is sent; the settings open where languages are added.
        if command == .translate, !Self.hasTranslationTarget(for: input, config: loadSettings()) {
            log.notice("conversion \(id): no language to translate into")
            perform(composer.fail(tr("还没有要翻译成的语言：在设置的「翻译与改写」里加一种", "No language to translate into yet: add one under Translate & Rewrite in the settings"),
                                  id: id), client: nil)
            openSettings(.writing)
            return
        }
        // An @calculate inside the text is worked out here first: a mistake in it is reported at once and in the
        // interface language (from inside the pipeline only its English description would arrive).
        if let plan, let error = Calculator.failure(in: plan) {
            log.notice("conversion \(id): @calculate inside the text failed")
            perform(composer.fail("@calculate" + tr("：", ": ") + UIText.describe(error), id: id), client: nil)
            return
        }
        let (runPlugin, runProgram, converter, loadSearchKey) = (self.runPlugin, self.runProgram, self.converter, self.loadSearchKey)
        let runScript = self.runScript
        let improveTranslates = loadSettings().improveTranslates
        // A terminal runs each line it is given: there @search's list, and any command's output, goes in
        // as one line.
        let terminal = Self.isTerminal(clientOverride ?? client())
        let searchList: WebSearch.Output = terminal ? .line : .list
        // Not tied to the main actor: the pipeline calls it from its own task.
        let streamFor: @Sendable (Command?, String) -> AsyncThrowingStream<ConversionUpdate, Error> = { command, input in
            if command == .read { return WebReader.stream(input) }
            if command == .calc { return Calculator.stream(input) }
            // @py, @js: the code runs in a child process, like a custom program (never in this one).
            if let command, let code = InlineCode.definition(for: command) { return runProgram(code, input) }
            if command == .webSearch { return WebSearch.stream(input, output: searchList, loadKey: loadSearchKey) }
            // A link opens once the commands inside its text have run: their outputs go in it as they are.
            if let command, command.kind == .link { return LinkTemplate.passThrough(input) }
            if command?.kind == .message { return CommandPipeline.unchanged(input) }  // sent as written, after confirming
            if let command, command.kind == .run, let plugin = command.plugin { return runPlugin(plugin, input) }
            if let script = command?.script { return runScript(script, arguments) }
            if let command, command.kind == .run, let custom = command.custom { return runProgram(custom, input) }
            // @improve, @translate, or both written together: one request (`WritingMode`).
            if command == nil || command?.kind == .convert {
                let (mode, text) = WritingMode.parse(command, input, improveTranslates: improveTranslates)
                return converter.convert(text, mode: mode)
            }
            return command.map { converter.generate($0, input: input) } ?? converter.convert(input)
        }
        let stream: AsyncThrowingStream<ConversionUpdate, Error>
        if let plan, !plan.isEmpty {
            // @search inside a text is context for the AI, but not where the text goes out as written: into a
            // web page (a link) or to a person (a message).
            let innerSearch = WebSearch.Output.inside(command)
            // The commands inside the text first (together), then this one on the text with their outputs.
            stream = CommandPipeline.run(plan, inner: { command, argument in
                // Its errors (no key, say) in the interface language.
                command == .webSearch ? Self.described(WebSearch.stream(argument, output: innerSearch, loadKey: loadSearchKey))
                    : streamFor(command, argument)
            }, outer: { streamFor(command, $0) })
        } else {
            stream = streamFor(command, input)
        }
        // A terminal runs each line it is given: a program's output goes in as one line there, and so does
        // an answer with line breaks (code) unless they can go in as a paste (`insert`, `TerminalPaste`).
        let oneLine = terminal && (command?.kind == .run || (command?.kind == .generate && !canPasteInTerminal()))
        let inserted = oneLine ? Self.oneLine(stream) : stream
        conversionTask = Task { @MainActor [weak self] in
            do {
                for try await update in inserted {
                    guard let self, !Task.isCancelled else { return }
                    if update.isFinal {
                        self.lastElapsed = update.elapsed
                        self.lastFromCache = update.fromCache
                        log.notice("conversion \(id) done in \(update.elapsed, format: .fixed(precision: 2))s cache=\(update.fromCache)")
                    }
                    self.perform(self.composer.receive(update.result, isFinal: update.isFinal, id: id), client: nil)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                log.error("conversion \(id) failed: \(Self.errorKind(error), privacy: .public) \(String(describing: error), privacy: .private)")
                self.perform(self.composer.fail(UIText.describe(error), id: id), client: nil)
            }
        }
    }

    /// Whether `client` is a terminal, which runs every line it is given.
    static func isTerminal(_ client: IMKTextInput?) -> Bool {
        client?.bundleIdentifier().map(SecureInput.terminals.contains) ?? false
    }

    /// `stream` with each result on one line (`CommandRunner.oneLine`): what goes into a terminal.
    static func oneLine(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await update in stream {
                        var update = update
                        update.result = CommandRunner.oneLine(update.result)
                        continuation.yield(update)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `stream` with its error described in the interface language: inside a text, an inner command's
    /// error reaches the panel only as its message (`CommandPipelineError.inner`).
    static func described(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await update in stream { continuation.yield(update) }
                    continuation.finish()
                } catch {
                    let message = await MainActor.run { UIText.describe(error) }
                    continuation.finish(throwing: DescribedError(message: message))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Error category without any server-provided text (safe for the public log).
    static func errorKind(_ error: Error) -> String {
        switch error {
        case let BedrockError.http(status, type, _): return "http \(status) \(type ?? "-")"
        case let BedrockError.stream(type, _): return "stream \(type)"
        case BedrockError.invalidResponse: return "invalid response"
        case BedrockError.invalidRegion: return "invalid region"
        case let ProviderError.http(provider, status, type, _): return "\(provider.rawValue) http \(status) \(type ?? "-")"
        case let ProviderError.stream(provider, type, _): return "\(provider.rawValue) stream \(type)"
        case let ProviderError.missingKey(provider): return "\(provider.rawValue) no key"
        case let ProviderError.refused(provider): return "\(provider.rawValue) refused"
        case ProviderError.signedOut: return "hosted signed out"
        case ProviderError.quotaExhausted: return "hosted quota exhausted"
        case NotesBridge.NotesError.notPermitted: return "notes not permitted"
        case let NotesBridge.NotesError.failed(number): return "notes error \(number)"
        case RemindersBridge.RemindersError.notPermitted: return "reminders not permitted"
        case RemindersBridge.RemindersError.noAccount: return "reminders no account"
        case RemindersBridge.RemindersError.notFound: return "reminder not found"
        case let RemindersBridge.RemindersError.failed(code): return "reminders error \(code)"
        case let urlError as URLError: return "url \(urlError.code.rawValue)"
        default: return String(describing: type(of: error))
        }
    }

    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "请求超时"
            case .notConnectedToInternet, .networkConnectionLost: return "网络连接失败"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "无法连接 AI 服务"
            default: return urlError.localizedDescription
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    // MARK: - Candidate panel

    @MainActor
    private func anchor(_ client: IMKTextInput) -> NSRect {
        var lineRect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        return lineRect
    }

    @MainActor
    private func showPanel(_ client: IMKTextInput?) {
        guard let client, composer.wantsPanel else {
            hidePanelIfOwned()
            return
        }
        let panel = CandidatePanel.shared
        panel.owner = self
        panel.onSelect = { [weak self] index in
            guard let self else { return }
            self.perform(self.composer.choose(index: index), client: nil)
        }
        panel.onScroll = { [weak self] steps in
            guard let self else { return }
            self.perform(self.composer.scrollPalette(by: steps), client: nil)
        }
        panel.show(panelModel(), anchor: anchor(client))
    }

    @MainActor
    private func hidePanelIfOwned() {
        let panel = CandidatePanel.shared
        if panel.owner == nil || panel.owner === self {
            panel.hide()
        }
    }

    /// Short status message ("英" English mode, "已复制" copied, …): its own small
    /// panel when nothing else is shown, otherwise the right side of the footer. `long`: something the
    /// user has to act on (a permission), up longer; `lasting`: up this long instead, unless another notice
    /// replaces it first (a save under way, until its outcome).
    @MainActor
    private func showNotice(_ text: String, client: IMKTextInput?, long: Bool = false, lasting: TimeInterval? = nil) {
        let client = client ?? clientOverride ?? self.client()
        notice = text
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(noticeExpired), object: nil)
        perform(#selector(noticeExpired), with: nil, afterDelay: lasting ?? Self.noticeDuration(text, long: long))
        if composer.wantsPanel {
            showPanel(client)
        } else if let client {
            let panel = CandidatePanel.shared
            panel.owner = self
            panel.onSelect = nil
            var model = CandidateView.Model()
            model.status = .hint(text)
            panel.show(model, anchor: anchor(client))
        }
    }

    /// Takes `text` down if it is still the notice here: a save's progress, once its outcome is told in another
    /// text field.
    @MainActor
    private func endNotice(_ text: String) {
        guard notice == text else { return }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(noticeExpired), object: nil)
        noticeExpired()
    }

    @objc private func noticeExpired() {
        MainActor.assumeIsolated {
            notice = nil
            if composer.wantsPanel {
                showPanel(clientOverride ?? client())
            } else {
                hidePanelIfOwned()
            }
        }
    }

    /// What the action key does to a sentence in `input`: "翻译成英文", "英文润色" …, plus " / 改写"
    /// when rewrite styles are on.
    static func actionText(input: Language, config: Config) -> String {
        let output = config.outputLanguage
        let name = output.name(chinese: true)
        let action = input.matches(output) ? "\(name)润色" : "翻译成\(name)"
        return action + (RewriteStyle.resolve(config.rewriteStyles).isEmpty ? "" : " / 改写")
    }

    /// The hint under a pending draft: "单按 ⌥ → 翻译成英文 / 改写", "Tap ⌥ → translate to English / rewrite" …
    @MainActor
    func draftHint(config: Config) -> String {
        guard let command = composer.draftCommand else { return "" }  // a draft always starts with one
        let key = composer.actionKey
        let how = key != .space ? UIText.name(key)
            : composer.spaceActs ? UIText.name(ActionKey.space) : tr("连按两次空格", "Space twice")
        // A command with nothing after it yet: what to do (the action key alone only hints).
        if composer.sentText.isEmpty {
            return tr("写点内容，或按 ⌃V 粘贴", "Write something, or ⌃V to paste")
        }
        return "\(how) → " + UIText.action(command, input: config.language(of: composer.sentText), config: config, draft: composer.draft)
    }

    /// A long answer as the panel shows it (the whole text is inserted).
    static func preview(_ text: String, limit: Int = 280) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// An `@open` result's row, as you type and after ⏎: its name in the interface language (计算器 in a
    /// Chinese one), and where it is: 「应用」, or its folder (a folder's ends in "/"), after 「内容 · 」 when it
    /// was found by what is in it. A web address says it opens in the browser.
    static func openRow(_ result: SearchResult) -> (text: String, comment: String) {
        if result.webURL != nil { return (result.name, tr("在浏览器中打开", "open in the browser")) }
        let folder = ((result.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        let place = result.path.hasSuffix(".app") ? tr("应用", "app")
            : result.isFolder && !folder.hasSuffix("/") ? folder + "/" : folder
        return (UIText.chinese ? result.chineseName ?? result.name : result.name,
                result.matchedContent ? tr("内容", "content") + " · " + place : place)
    }

    @MainActor
    func panelModel() -> CandidateView.Model {
        var model = CandidateView.Model()
        let config = loadSettings()
        if composer.isLevelTwo {
            let choices = composer.choices
            model.rows = choices.map { choice in
                // Long rows (a pasted paragraph and its versions) are shortened here; the full text goes in.
                switch choice.kind {
                case .original:
                    return CandidateView.Row(label: choice.label, text: Self.preview(choice.text), comment: tr("原文", "original"),
                                             style: .original)
                case .version:
                    return CandidateView.Row(label: choice.label, text: Self.preview(choice.text), style: .translation,
                                             isComplete: choice.isComplete)
                case let .translation(code):
                    return CandidateView.Row(label: choice.label, text: Self.preview(choice.text),
                                             comment: UIText.name(OutputLanguage(code)), style: .translation,
                                             isComplete: choice.isComplete)
                case let .rewrite(style):
                    // A jargon (黑话) line notes what the terms from the user's jargon list in it mean.
                    let note = style == RewriteStyle.jargonName
                        ? JargonLibrary.annotation(for: choice.text, entries: LiveJargon.entries(for: config), chinese: UIText.chinese) : nil
                    let name = RewriteStyle.named(style).map(UIText.name) ?? style
                    return CandidateView.Row(label: choice.label, text: Self.preview(choice.text),
                                             comment: note.map { "\(name) · \($0)" } ?? name,
                                             style: .translation, isComplete: choice.isComplete)
                case .answer:
                    // A program's output may have several lines; they are inserted as printed.
                    let text = choice.text.replacingOccurrences(of: "\n", with: " ↵ ")
                    return CandidateView.Row(label: choice.label, text: Self.preview(text),
                                             comment: UIText.answerLabel(composer.activeCommand),
                                             style: .translation, isComplete: choice.isComplete)
                case let .file(path) where path.hasPrefix(SearchResult.agentPrefix):
                    // A background task: its last reply, shortened.
                    let reply = composer.searchResults.first { $0.path == path }?.detail ?? ""
                    let preview = reply.replacingOccurrences(of: "\n", with: " ")
                    // Its state as an icon instead of the mark before its name.
                    let marks: [(String, AgentSession.Progress)] = [("✓ ", .done), ("⚠︎ ", .needsYou), ("… ", .working)]
                    let state = marks.first { choice.text.hasPrefix($0.0) }
                    return CandidateView.Row(label: choice.label, text: state.map { String(choice.text.dropFirst($0.0.count)) } ?? choice.text,
                                             comment: preview.count > 60 ? String(preview.prefix(60)) + "…" : preview, style: .candidate,
                                             icon: state.map { CommandIcons.icon(for: $0.1) })
                case .send:
                    // 「发给 张三（+1 555…）：…」: who it goes to and the text, to confirm.
                    let to = composer.messageRecipient.map { $0.name.isEmpty ? $0.handle : "\($0.name)（\($0.handle)）" } ?? ""
                    return CandidateView.Row(label: choice.label,
                                             text: tr("发给 \(to)：", "Send to \(to): ") + Self.preview(choice.text.replacingOccurrences(of: "\n", with: " ↵ ")),
                                             style: .translation, isComplete: choice.isComplete,
                                             icon: composer.activeCommand.map(CommandIcons.icon(for:)))
                case let .file(path):
                    // A file, folder, app or web address: drawn as when typing.
                    let row = Self.openRow(composer.searchResults.first { $0.path == path } ?? SearchResult(name: choice.text, path: path))
                    return CandidateView.Row(label: choice.label, text: row.text, comment: row.comment, style: .candidate)
                case let .reminder(reminder):
                    // To confirm: what to be reminded of, and when as read from the text (「明天 15:00」).
                    return CandidateView.Row(label: choice.label, text: Self.preview(choice.text),
                                             comment: UIText.when(reminder), style: .candidate)
                }
            }
            model.highlighted = composer.highlighted
            let command = composer.activeCommand
            switch composer.phase {
            case .translating:
                let polishing = config.language(of: composer.sentText).matches(config.outputLanguage)
                let loading = command?.kind == .generate ? tr("AI 回答中…", "Answering…")
                    : command == .webSearch ? tr("搜索中…", "Searching…")
                    : command?.script.map { tr("正在运行 \($0.title)…", "Running \($0.title)…") }
                    ?? (command?.kind == .run ? tr("运行中…", "Running…")
                    : command?.kind == .link ? tr("运行句中的命令，然后在浏览器打开…", "Running the commands inside, then opening the browser…")
                    : command == .open ? tr("搜索中…", "Searching…")
                    : command == .tasks ? tr("读取后台任务…", "Reading the background tasks…")
                    : command?.kind == .message ? tr("运行句中的命令…", "Running the commands in the message…")
                    : polishing ? tr("AI 润色中…", "Polishing…") : tr("AI 翻译中…", "Translating…"))
                model.status = choices.count <= 1 ? .loading(loading) : .none
                model.footer = command == .open ? tr("搜索中… · Esc 返回", "Searching… · Esc back")
                    : command?.kind == .link ? tr("完成后在浏览器打开 · Esc 返回", "Opens in the browser when done · Esc back")
                    : tr("生成中… · 0 原文 · Esc 返回", "Generating… · 0 original · Esc back")
            case .choosing where command?.kind == .message:
                model.footer = tr("⏎ 发送 · Esc 返回修改", "⏎ send · Esc back to editing")
            case .choosing where command == .tasks:
                model.footer = tr("⏎ 在终端打开 · 数字选择 · ⌘C 复制回复 · Esc 返回",
                                  "⏎ open in Terminal · digits pick · ⌘C copy the reply · Esc back")
            case .choosing:
                model.footer = command == .open
                    ? tr("空格 / ⏎ 打开 · 数字选择 · ⌘C 复制路径 · Esc 返回", "Space / ⏎ open · digits pick · ⌘C copy path · Esc back")
                    : command == .reminder
                    ? tr("⏎ / 空格 加到提醒事项 · Esc 返回修改 · ⌘C 复制", "⏎ / Space add to Reminders · Esc back to edit · ⌘C copy")
                    : tr("空格 / ⏎ 上屏 · 数字选择 · 0 原文 · ⌘C 复制 · Esc 返回",
                         "Space / ⏎ insert · digits pick · 0 original · ⌘C copy · Esc back")
                if command != .open && command != .reminder {
                    model.detail = lastFromCache ? tr("缓存", "cached") : lastElapsed.map { String(format: "%.1fs", $0) }
                }
            case let .failed(message):
                model.status = .error(message)
                model.highlighted = nil  // Space retries; nothing is selected
                // A reminder without anything to be reminded of: write it in.
                model.footer = command == .reminder ? tr("Esc 返回修改", "Esc back to edit")
                    : composer.actionKey == .enter
                    ? tr("空格 / ⏎ 重试 · 0 原文 · Esc 返回", "Space / ⏎ retry · 0 original · Esc back")
                    : tr("空格 重试 · ⏎ 上屏原文 · Esc 返回", "Space retry · ⏎ insert original · Esc back")
            case .idle, .drafting:
                break
            }
        } else if composer.voice != .off {
            let heard = composer.voice.text
            if case .listening = composer.voice {
                model.status = .hint("🎙 " + (heard.isEmpty ? tr("正在听…", "Listening…") : heard))
                // The action key while right ⌥ is still held (⌥Return, or Space = ⌥Space): stop and run it.
                let key = composer.actionKey
                let runs = composer.draftCommand != nil
                model.footer = runs && (key == .optionSpace || key == .enter)
                    ? (key == .enter ? tr("松开右 ⌥ 结束 · ⏎ 直接执行 · Esc 取消", "Release right ⌥ to stop · ⏎ run now · Esc cancel")
                                     : tr("松开右 ⌥ 结束 · 空格 直接执行 · Esc 取消", "Release right ⌥ to stop · Space run now · Esc cancel"))
                    : tr("松开右 ⌥ 结束 · Esc 取消", "Release right ⌥ to stop · Esc cancel")
            } else {
                model.status = .hint("🎙 " + (heard.isEmpty ? tr("识别中…", "Recognizing…") : heard))
                model.footer = composer.actsAfterVoice
                    ? tr("识别完就发送 · Esc 取消", "Sends once recognized · Esc cancel")
                    : tr("识别中… · Esc 取消", "Recognizing… · Esc cancel")
            }
            model.detail = composer.messages.mode(composer.inputLanguage)
        } else if composer.engineState.isComposing {
            let state = composer.engineState
            model.rows = state.candidates.map {
                CandidateView.Row(label: $0.label, text: $0.text, comment: $0.comment, style: .candidate)
            }
            model.highlighted = state.highlighted
            let key = composer.actionKey
            if let command = composer.draftCommand {
                // Pinyin (or Hindi) in an @ command: the action key converts it and runs the command.
                let action = UIText.action(command, input: composer.textLanguage(config: config), config: config, draft: composer.draft)
                model.footer = tr("空格 选词 · \(UIText.name(key)) \(action)", "Space picks · \(UIText.name(key)) to \(action)")
            } else {
                model.footer = tr("空格 选词 · 开头打 @ 用命令", "Space picks · type @ first for commands")
            }
            if state.pageNumber > 0 || !state.isLastPage {
                model.detail = tr("第 \(state.pageNumber + 1) 页", "page \(state.pageNumber + 1)")
            }
        } else if composer.paletteQuery != nil {
            // "@…": the commands that start with what was typed.
            // Five at a time; the rest scroll into view (the position on the right).
            let first = composer.paletteFirstVisible, total = composer.paletteMatches.count
            model.rows = composer.paletteVisible.enumerated().map {
                CandidateView.Row(label: String($0.offset + 1), text: "@" + $0.element.name,
                                  comment: UIText.summary($0.element), style: .candidate,
                                  icon: CommandIcons.icon(for: $0.element))
            }
            model.highlighted = composer.paletteHighlighted - first
            if total > Composer.paletteRows { model.detail = "\(first + 1)–\(first + model.rows.count) / \(total)" }
            // A Raycast script without arguments runs as it is picked.
            let matches = composer.paletteMatches
            model.footer = matches.indices.contains(composer.paletteHighlighted) && matches[composer.paletteHighlighted].script?.runsWhenPicked == true
                ? tr("⏎ / Tab / 空格 运行 · Esc 取消", "⏎ / Tab / Space run · Esc cancel")
                : tr("⏎ / Tab / 空格 选择 · Esc 取消", "⏎ / Tab / Space choose · Esc cancel")
        } else if !composer.currentLiveResults.isEmpty {
            // "@open …" as you type: what matches now.
            model.rows = composer.currentLiveResults.map { result in
                let row = Self.openRow(result)
                return CandidateView.Row(label: result.isFolder ? "›" : "", text: row.text, comment: row.comment, style: .candidate)
            }
            model.highlighted = composer.liveHighlight
            // Only content matches: ⏎ lists them to pick from rather than open the first (`opensLiveResult`).
            model.footer = composer.opensLiveResult
                ? tr("⏎ 打开 · Tab 补全路径 · ↑↓ 选择 · ⌘C 复制路径 · Esc 取消",
                     "⏎ open · Tab complete path · ↑↓ choose · ⌘C copy path · Esc cancel")
                : tr("⏎ 列出来选 · Tab 补全路径 · ↑↓ 选择 · ⌘C 复制路径 · Esc 取消",
                     "⏎ pick from a list · Tab complete path · ↑↓ choose · ⌘C copy path · Esc cancel")
        } else if composer.recipientQuery != nil {
            // "@imessage zs": the contacts that match, to pick the recipient.
            let found = composer.currentRecipients
            model.rows = found.enumerated().map { index, recipient in
                CandidateView.Row(label: String(index + 1), text: recipient.displayName,
                                  comment: recipient.name.isEmpty ? tr("直接发送到这个号码 / 邮箱", "send to this number / email") : recipient.handle,
                                  style: .candidate)
            }
            model.highlighted = found.isEmpty ? nil : composer.recipientHighlight
            if let note = composer.recipientNote { model.status = .hint(note) }
            model.footer = tr("⏎ / Tab 选择收件人 · ↑↓ · Esc 取消", "⏎ / Tab pick the recipient · ↑↓ · Esc cancel")
        } else if !composer.draft.isEmpty {
            // An @ command with what follows it (a command being typed is the palette, above).
            model.status = .hint(draftHint(config: config))
            model.footer = tr("⌃V 粘贴 · ⌫ 删字 · Esc 清除", "⌃V paste · ⌫ delete · Esc clear")
        }
        if let notice { model.detail = notice }
        return model
    }

    // MARK: - Menu

    @MainActor
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let config = try? Config.load()
        UIText.choice = loadSettings().uiLanguage  // the menu can open before any text field in this process
        let settings = NSMenuItem(title: tr("设置…", "Settings…"), action: #selector(showPreferences(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let model = config.map { tr("模型：", "Model: ") + ($0.settings(for: $0.provider).model ?? "") } ?? tr("配置文件有误", "The config file has an error")
        let info = NSMenuItem(title: model, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        menu.addItem(.separator())
        // Output and input languages in submenus like the styles: each lists only the languages the user
        // added (a new user has one), with "Add Languages…" opening the settings.
        let current = config ?? .default
        // @translate writes in every language added, in this order (one picked here moves to the front).
        let outputItem = NSMenuItem(title: tr("翻译成：", "Translate to: ") + current.outputLanguages.map(UIText.name).joined(separator: tr("、", ", ")),
                                    action: nil, keyEquivalent: "")
        let outputs = NSMenu()
        for language in current.outputLanguages {
            let item = NSMenuItem(title: UIText.name(language), action: #selector(setOutputLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.code
            item.state = .on
            item.isEnabled = config != nil  // don't overwrite a config file that failed to parse
            outputs.addItem(item)
        }
        outputs.addItem(.separator())
        let addOutput = NSMenuItem(title: tr("添加 / 排序语言…", "Add or Reorder Languages…"), action: #selector(showPreferences(_:)), keyEquivalent: "")
        addOutput.target = self
        outputs.addItem(addOutput)
        outputItem.submenu = outputs
        menu.addItem(outputItem)

        let inputItem = NSMenuItem(title: tr("输入：", "Input: ") + current.inputLanguages.map(Self.inputName).joined(separator: " + "),
                                   action: nil, keyEquivalent: "")
        let inputs = NSMenu()
        // The added input languages, the default one checked (a new text field starts in it).
        for language in current.inputLanguages {
            // One whose pack isn't there yet can't be typed: shown, greyed, with why.
            let usable = LanguagePackManager.shared.isUsable(language)
            let title = Self.inputName(language) + (usable ? "" : tr("（还没有语言包）", " (no language pack yet)"))
            let item = NSMenuItem(title: title, action: #selector(setDefaultInput(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = current.defaultInput == language ? .on : .off
            item.isEnabled = config != nil && usable
            inputs.addItem(item)
        }
        inputs.addItem(.separator())
        if current.inputLanguages.count > 1 {
            let shiftNote = NSMenuItem(title: tr("✓ 是默认；Shift 切换", "✓ is the default; Shift switches"), action: nil, keyEquivalent: "")
            shiftNote.isEnabled = false
            inputs.addItem(shiftNote)
        }
        let addInput = NSMenuItem(title: tr("添加语言…", "Add Languages…"), action: #selector(showPreferences(_:)), keyEquivalent: "")
        addInput.target = self
        inputs.addItem(addInput)
        inputItem.submenu = inputs
        menu.addItem(inputItem)

        // The styles in a submenu: six rows with summaries made the menu too long. Its title says which
        // are on, so the menu still shows the state without opening it.
        let enabledStyles = RewriteStyle.resolve(config?.rewriteStyles ?? Config.default.rewriteStyles)
        let enabled = Set(enabledStyles.map(\.name))
        let on = enabledStyles.map(UIText.name).joined(separator: tr("、", ", "))
        let stylesItem = NSMenuItem(title: tr("改写风格", "Rewrite Styles") + tr("：", ": ") + (on.isEmpty ? tr("无", "none") : on),
                                    action: nil, keyEquivalent: "")
        let styles = NSMenu()
        for style in RewriteStyle.catalog {
            let item = NSMenuItem(title: UIText.name(style) + tr("　", "  ") + UIText.summary(style),
                                  action: #selector(toggleStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.name
            item.state = enabled.contains(style.name) ? .on : .off
            item.isEnabled = config != nil  // don't overwrite a config file that failed to parse
            styles.addItem(item)
        }
        stylesItem.submenu = styles
        menu.addItem(stylesItem)
        let improveTranslates = NSMenuItem(title: tr("@improve 同时翻译", "@improve Also Translates"),
                                           action: #selector(toggleImproveTranslates(_:)), keyEquivalent: "")
        improveTranslates.target = self
        improveTranslates.state = current.improveTranslates ? .on : .off
        improveTranslates.isEnabled = config != nil
        menu.addItem(improveTranslates)
        menu.addItem(.separator())
        let rimeDir = NSMenuItem(title: tr("打开 Rime 用户目录", "Open Rime User Folder"), action: #selector(openRimeDirectory(_:)),
                                 keyEquivalent: "")
        rimeDir.target = self
        menu.addItem(rimeDir)
        let deploy = NSMenuItem(title: tr("重新部署词库", "Redeploy Dictionaries"), action: #selector(redeploy(_:)), keyEquivalent: "")
        deploy.target = self
        menu.addItem(deploy)
        return menu
    }

    /// IMK hands menu actions an info dictionary holding the chosen item (a plain NSMenuItem when
    /// called directly).
    static func menuItem(from sender: Any?) -> NSMenuItem? {
        if let item = sender as? NSMenuItem { return item }
        guard let info = sender as? NSDictionary else { return nil }
        return info[kIMKCommandMenuItemName as Any] as? NSMenuItem
    }

    @objc func toggleStyle(_ sender: Any?) {
        MainActor.assumeIsolated {
            guard let name = Self.menuItem(from: sender)?.representedObject as? String else {
                log.error("style menu action without a style")
                return
            }
            do {
                var config = try Config.load()
                config.rewriteStyles = Self.toggled(name, in: config.rewriteStyles)
                try config.write()
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                log.notice("rewrite styles now \(config.rewriteStyles.joined(separator: ","), privacy: .public)")
            } catch {
                log.error("could not update rewrite styles: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Turns a preset on or off, keeping the user's order: one turned on goes last.
    static func toggled(_ name: String, in current: [String]) -> [String] {
        let enabled = RewriteStyle.resolve(current).map(\.name)
        if enabled.contains(name) { return enabled.filter { $0 != name } }
        return enabled + [name]
    }

    @objc func setOutputLanguage(_ sender: Any?) {
        MainActor.assumeIsolated {
            guard let raw = Self.menuItem(from: sender)?.representedObject as? String else {
                log.error("output menu action without a language")
                return
            }
            do {
                var config = try Config.load()
                config.outputLanguage = OutputLanguage(raw)
                config.normalizeLanguages()
                try config.write()
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                log.notice("output language now \(raw, privacy: .public)")
            } catch {
                log.error("could not update the output language: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// An input language as the menu and the settings name it: "中文（拼音）", "英文".
    static func inputName(_ language: Language) -> String {
        language == .chinese ? tr("中文（拼音）", "Chinese (pinyin)") : UIText.name(language)
    }

    @objc func toggleImproveTranslates(_ sender: Any?) {
        MainActor.assumeIsolated {
            do {
                var config = try Config.load()
                config.improveTranslates.toggle()
                try config.write()
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                log.notice("@improve also translates: \(config.improveTranslates, privacy: .public)")
            } catch {
                log.error("could not update @improve: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Makes an added input language the default: a new text field starts in it.
    @objc func setDefaultInput(_ sender: Any?) {
        MainActor.assumeIsolated {
            guard let raw = Self.menuItem(from: sender)?.representedObject as? String, let language = Language(rawValue: raw) else {
                log.error("input menu action without a language")
                return
            }
            do {
                var config = try Config.load()
                config.defaultInput = language
                config.normalizeLanguages()
                try config.write()
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                log.notice("default input now \(config.defaultInput.rawValue, privacy: .public)")
                applySettings()
            } catch {
                log.error("could not update the default input: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// `languages` with `language` removed, or added at the end; the last one stays.
    static func toggled(_ language: Language, in languages: [Language]) -> [Language] {
        if languages.contains(language) { return languages == [language] ? languages : languages.filter { $0 != language } }
        return languages + [language]
    }

    @objc func openConfig(_ sender: Any?) {
        MainActor.assumeIsolated { Self.openConfigFile() }
    }

    override func showPreferences(_ sender: Any!) {
        MainActor.assumeIsolated {
            perform(composer.commitAll(), client: nil)  // the window takes focus from the text field
            SettingsWindow.shared.show()
        }
    }

    @objc func openRimeDirectory(_ sender: Any?) {
        MainActor.assumeIsolated {
            if let dir = RimeService.shared.userDataDir { NSWorkspace.shared.open(dir) }
        }
    }

    @objc func redeploy(_ sender: Any?) {
        MainActor.assumeIsolated {
            perform(composer.commitAll(), client: nil)
            composer.engine = nil
            session = nil
            RimeService.shared.redeploy()
        }
    }

    @MainActor
    static func openConfigFile() {
        let url = Config.defaultURL
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try Config.default.write(to: url)
            } catch {
                log.error("could not create config: \(String(describing: error), privacy: .public)")
            }
        }
        if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

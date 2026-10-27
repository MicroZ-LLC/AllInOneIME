import Foundation

/// What a text field's session asks of the system it runs on, or has it do: the settings as they are now, what is kept
/// between fields and launches, programs and terminals, notes, reminders, contacts and messages, the files `@open`
/// finds. The shell fills it in (the Mac's: `SessionServices.mac`, in the app); a test, or the Mac's self-test, puts
/// stand-ins in that never reach the user's own.
///
/// Called on the session's thread, except those marked `@Sendable`: `SessionTasks` runs them off it. The defaults do
/// nothing and keep nothing.
public struct SessionServices {
    /// Level two: the AI requests (one `Converter`, one cache, shared by every field).
    public var converter: Converter
    /// The settings as they are now (re-read when the file changed).
    public var loadSettings: () -> Config

    // MARK: Level one

    /// Level one's engine for a field: librime's once it has deployed (`.engine`), none while it deploys (`.starting`: keys
    /// go to the application), none at all (`.none`: no Chinese pack, Latin letters: `LatinEngine`).
    public var levelOne: () -> LevelOne
    /// Whether an engine `levelOne` gave is still good (librime deployed again: its sessions are gone).
    public var engineIsValid: (PinyinEngine) -> Bool
    /// The keyboard layout the keys come from, for dead keys (`DeadKeyComposer`; nil: the platform composes them).
    public var keyTranslator: () -> (any KeyTranslator)?
    /// The Korean and Hindi packs' tables (nil: not installed), and which of the input languages can be typed (a pack
    /// still downloading can't).
    public var hangulTables: () -> HangulTables?
    public var hindiTables: () -> HindiTables?
    public var usableLanguages: ([Language]) -> [Language]
    /// Whether voice input can work here (the system's speech recognition).
    public var voiceSupported: () -> Bool
    /// rime-ice's English dictionary, for the English words put among librime's candidates (`EnglishWordsEngine`); nil:
    /// none are (no Chinese pack, a test's engine).
    public var englishDictionary: () -> EnglishDictionary?
    /// An English word learned from letters put in as typed (`EnglishWords.learnable`): kept in the settings
    /// (`EnglishWords.learn`, `Config.englishWords`).
    public var learnEnglishWord: (String) -> Void
    /// The letters put in as typed once (learned the second time), shared by every field of a launch: the shell gives one
    /// for them all; the default is these services' own.
    public var englishTypedOnce: EnglishWords.TypedOnce

    // MARK: What is kept

    /// The command usage as kept (the order of the command list), and keeping it.
    public var loadCommandUsage: () -> CommandUsage
    public var saveCommandUsage: (CommandUsage) -> Void
    /// The recent `@question`s as kept, and keeping one.
    public var loadQuestionHistory: () -> QuestionHistory
    public var recordQuestion: (QuestionHistory.Entry) -> Void
    /// What `@open` opened before (listed first), and keeping one it opened.
    public var loadOpenHistory: () -> OpenHistory
    public var recordOpen: (String) -> Void
    /// The handles last messaged (`@imessage`), and keeping them.
    public var loadRecentHandles: () -> [String]
    public var saveRecentHandles: ([String]) -> Void

    // MARK: The system

    /// Whether secure input is on anywhere (a password field, the lock screen): nothing is sent to a model or run then.
    public var secureInputActive: () -> Bool
    /// Whether a mouse button, a drag or the scroll wheel was used in the last `seconds`, anywhere: a Shift-click is no
    /// tap of Shift.
    public var pointerUsedWithin: (_ seconds: TimeInterval) -> Bool
    /// Whether the voice key is still held with no mouse button down, when its hold timer fires.
    public var isVoiceKeyHeld: () -> Bool
    /// What reads a screenshot's text on the device (`Platform.current.text` by default).
    public var recognizeText: any TextRecognizer
    /// Whether line breaks can go into a terminal as a paste (the Mac's `TerminalPaste`: it may ask for a permission, so
    /// it's asked only for an answer that has them): an answer then keeps them there.
    public var pastesInTerminal: () -> Bool
    /// The web page the field is in, for `@agent` and `@reply` (`PageSource`; nil: none, or not to be read: the setting,
    /// no permission).
    public var page: (_ app: String?) -> PageSource?
    /// Errors only the user can fix (a permission, an account): their notice stays up longer, the text on the clipboard
    /// too. Called off the session's thread.
    public var needsTheUser: @Sendable (Error) -> Bool
    /// An error's kind for the log, without any server-provided text (a shell's own errors; nil: the core's
    /// `InputSession.errorKind`). Called off the session's thread.
    public var errorKind: @Sendable (Error) -> String?

    // MARK: Commands

    /// `@open`: the files and apps named like the query, what it opened before first.
    public var searchFiles: @Sendable (_ query: String, _ history: OpenHistory) async -> [SearchResult]
    /// `@agent`: starts the agent's arguments (`AgentKind.terminalArguments`) with the prompt in a terminal window.
    public var runInTerminal: (_ arguments: [String], _ prompt: String) throws -> Void
    /// An `@question` conversation going on in a coding agent (`ChatHandoff`): its arguments with the conversation.
    public var continueInAgent: (_ arguments: [String], _ prompt: String) throws -> Void
    /// Whether an agent is installed (a custom one by its command), for the `@question` hand-off's choices.
    public var agentInstalled: (AgentKind, _ custom: [String]) -> Bool
    /// A custom `terminal` command: runs its arguments in a terminal window.
    public var launchInTerminal: ([String]) throws -> Void
    /// Whether a command's program is installed (`@agent`'s agent, a custom command's `argv[0]`).
    public var programInstalled: @Sendable (String) -> Bool
    /// `@agent` in the background (Claude Code's): starting one (its id back), and the list (`@tasks`).
    public var startAgent: @Sendable (String) async throws -> String
    public var listAgents: @Sendable () async throws -> [(session: AgentSession, reply: String?)]
    /// A custom `run` command's program (and `@py`, `@js`), and a script plugin told the interface language.
    public var runProgram: @Sendable (CustomCommand, String) -> AsyncThrowingStream<ConversionUpdate, Error>
    public var runPlugin: @Sendable (InstalledPlugin, String, Language) -> AsyncThrowingStream<ConversionUpdate, Error>
    /// The script extensions for these settings (`rescan`: a text field became active, the index is built again in the
    /// background), and the values a bundle's commands get (passwords from the secret store: never while a key is
    /// handled).
    public var loadExtensions: (Config, _ rescan: Bool) -> ExtensionIndex
    public var extensionPreferences: @Sendable (ExtensionBundle, Config) -> [String: String]
    /// Script extensions run for a field's request (the Mac's `ScriptTasks`: its menu bar panel lists those that go on in
    /// the background): started with their environment, `event` told what they print, from any thread (nil: not
    /// started); stopped; left to go on in the background (the field was left while a `show` runs).
    public var startScript: (ScriptCommand, _ arguments: [String], _ environment: [String: String],
                             _ event: @escaping @Sendable (ScriptRunEvent) -> Void) -> Int?
    public var cancelScript: (Int) -> Void
    public var detachScript: (Int) -> Void
    /// A `background` script extension: started on its own once `prepare` made its environment, even if the field is
    /// gone by then; `say` tells why it didn't start.
    public var startScriptInBackground: (ScriptCommand, _ arguments: [String],
                                         _ prepare: @escaping @Sendable () async -> Result<[String: String], DescribedError>,
                                         _ say: @escaping (String) -> Void) -> Void
    /// The installed plugins (`rescan`: a text field became active: looked for again).
    public var plugins: (_ rescan: Bool) -> [InstalledPlugin]
    /// The status line of a script extension the command list shows (`ScriptCommand.status`), and running those that are
    /// due: `environment` gives each its environment, `ended` (from any thread) says one ended.
    public var scriptStatus: (ScriptCommand) -> String?
    public var refreshStatuses: (_ shown: [ScriptCommand], _ environment: @escaping @Sendable (ScriptCommand) async -> [String: String]?,
                                 _ ended: @escaping @Sendable () -> Void) -> Void
    /// The user's jargon list, for a jargon (黑话) result's explanations.
    public var jargon: (Config) -> [JargonEntry]
    /// What `@reportissue` says about this system and the settings, with how many plugins and extensions there are.
    public var issueDiagnostics: (Config, _ plugins: Int, _ extensions: Int) -> IssueReport.Diagnostics
    /// Translate as You Type's chip in this field, when the shell shows one (`TranslateMode.Chip`).
    public var translateChip: () -> TranslateMode.Chip?
    /// Autocomplete's suggestions kept, what it learned per app and what it counted (`AutocompleteStore`): the shell
    /// gives one for every field; the default is these services' own, in memory.
    public var autocomplete: AutocompleteStore
    /// What is learned on this device: a field starts in what its app learned, and its switches teach it (Settings v2
    /// §3.1). The shell gives one for every field; the default is these services' own, in memory.
    public var learned: LearnedStore
    /// The time now, in seconds from any fixed point (the system's uptime): what autocomplete's Tab and its metrics go by.
    /// A test sets its own.
    public var uptime: () -> TimeInterval
    /// An app's name as the user knows it, from its id (the Mac: its bundle id; nil: none known), for what is said of it.
    public var appName: (String) -> String?
    /// `@search`'s key.
    public var loadSearchKey: @Sendable () -> String?
    /// The notice of the custom commands renamed for the built-in ones, once (`Config.freeBuiltinNames`).
    public var takeRenameNotice: (Composer.ReplyMessages) -> String?

    // MARK: Notes, reminders, messages

    /// `@note`: where the text is saved (`Config.notes`), made for each save; a saved note with an id told (from any
    /// thread: the Mac's menu bar panel lists them).
    public var noteDestination: (NoteSettings) -> any NoteDestination
    public var noteSaved: @Sendable (SavedNoteRef) -> Void
    /// `@reminder`: the reminder in a text, by the clock now; adding a confirmed one.
    public var parseReminder: (String) -> ReminderDraft
    public var addReminder: @Sendable (ReminderDraft) async throws -> Void
    /// `@imessage`: the address book (nil: no access), and sending.
    public var loadContacts: @Sendable () async -> [Contact]?
    public var messageSender: any MessageSender

    // MARK: Suggestions

    /// Plugin completions, Code's rows and the long press of Shift (`SuggestionsServices`, Suggestions/SuggestionsContract.swift).
    public var suggestions: SuggestionsServices

    /// Clipboard history: what the shell keeps (`ClipboardHistoryServices`, Session/ClipboardHistory.swift); none by default.
    public var clipboardHistory: ClipboardHistoryServices

    public init(converter: Converter = Converter(), loadSettings: @escaping () -> Config = { .default }) {
        self.converter = converter
        self.loadSettings = loadSettings
        levelOne = { .none }
        engineIsValid = { _ in true }
        keyTranslator = { nil }
        hangulTables = { nil }
        hindiTables = { nil }
        usableLanguages = { $0.filter { $0 != .korean && $0 != .hindi } }
        voiceSupported = { false }
        englishDictionary = { nil }
        learnEnglishWord = { _ in }
        englishTypedOnce = EnglishWords.TypedOnce()
        page = { _ in nil }
        pastesInTerminal = { false }
        needsTheUser = { ($0 as? NoteError)?.needsTheUser ?? false }
        errorKind = { _ in nil }
        plugins = { _ in [] }
        scriptStatus = { _ in nil }
        refreshStatuses = { _, _, _ in }
        jargon = { _ in [] }
        issueDiagnostics = { config, plugins, extensions in
            IssueReport.Diagnostics(config: config, macOS: "-", architecture: "-", interfaceLanguage: config.uiLanguage ?? UIText.language,
                                    languagePacks: [], plugins: plugins, extensions: extensions)
        }
        translateChip = { nil }
        autocomplete = AutocompleteStore()
        learned = LearnedStore(file: nil, autocomplete: autocomplete, temperature: TemperatureSupport(file: nil))
        uptime = { ProcessInfo.processInfo.systemUptime }
        appName = { _ in nil }
        noteSaved = { _ in }
        loadCommandUsage = { CommandUsage() }
        saveCommandUsage = { _ in }
        loadQuestionHistory = { QuestionHistory() }
        recordQuestion = { _ in }
        loadOpenHistory = { OpenHistory() }
        recordOpen = { _ in }
        loadRecentHandles = { [] }
        saveRecentHandles = { _ in }
        secureInputActive = { false }
        pointerUsedWithin = { _ in false }
        isVoiceKeyHeld = { false }
        recognizeText = Platform.current.text
        searchFiles = { _, _ in [] }
        runInTerminal = { _, _ in throw SessionServicesError.unsupported }
        continueInAgent = { _, _ in throw SessionServicesError.unsupported }
        agentInstalled = { _, _ in false }
        launchInTerminal = { _ in throw SessionServicesError.unsupported }
        programInstalled = { _ in false }
        startAgent = { _ in throw SessionServicesError.unsupported }
        listAgents = { [] }
        runProgram = { command, input in CommandRunner.run(command, input: input) }
        runPlugin = { _, _, _ in AsyncThrowingStream { $0.finish(throwing: SessionServicesError.unsupported) } }
        loadExtensions = { _, _ in .empty }
        extensionPreferences = { _, _ in [:] }
        startScript = { _, _, _, _ in nil }
        cancelScript = { _ in }
        detachScript = { _ in }
        startScriptInBackground = { _, _, _, say in say(UIText.describe(SessionServicesError.unsupported)) }
        loadSearchKey = { nil }
        takeRenameNotice = { _ in nil }
        noteDestination = { _ in NoDestination() }
        parseReminder = { ReminderParser().parse($0, now: Platform.current.clock.now) }
        addReminder = { _ in throw SessionServicesError.unsupported }
        loadContacts = { nil }
        messageSender = NoMessageSender()
        suggestions = SuggestionsServices()
        clipboardHistory = ClipboardHistoryServices()
    }

    /// Where a default can't do what was asked.
    struct NoDestination: NoteDestination {
        var name: String { "-" }
        var leavesDevice: Bool { false }
        func save(_ draft: NoteDraft) async throws -> SavedNoteRef { throw SessionServicesError.unsupported }
        func check() async throws -> String { throw SessionServicesError.unsupported }
    }

    struct NoMessageSender: MessageSender {
        func send(_ text: String, to recipient: Recipient) async throws { throw SessionServicesError.unsupported }
    }
}

/// Level one's engine for a field, as `SessionServices.levelOne` gives it.
public enum LevelOne {
    case engine(PinyinEngine)
    case starting
    case none
}

/// The web page a text field is in (the Mac's: Chrome's, read with Accessibility), as `@agent` and `@reply` take it along.
public struct PageSource {
    /// Asked for ahead of time (`@agent …` being written): the browser makes what is read, ready by ⏎.
    public var wake: () -> Void
    /// What `wake` asked for, given back (the draft given up, the field left).
    public var release: () -> Void
    /// What reads the page, made now (where the pointer is now, say), run off the session's thread (it blocks, up to
    /// seconds); it gives back what `wake` asked for once it has read.
    public var reader: () -> @Sendable () -> PageContext?

    public init(wake: @escaping () -> Void, release: @escaping () -> Void, reader: @escaping () -> @Sendable () -> PageContext?) {
        self.wake = wake
        self.release = release
        self.reader = reader
    }
}

/// What a default service says when it is asked to do something its shell gave it no way to do.
public enum SessionServicesError: Error, Equatable, Sendable {
    case unsupported
}

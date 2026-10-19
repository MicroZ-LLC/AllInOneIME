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
    /// `@search`'s key.
    public var loadSearchKey: @Sendable () -> String?
    /// The notice of the custom commands renamed for the built-in ones, once (`Config.freeBuiltinNames`).
    public var takeRenameNotice: (Composer.ReplyMessages) -> String?

    // MARK: Notes, reminders, messages

    /// `@note`: where the text is saved (`Config.notes`), made for each save.
    public var noteDestination: (NoteSettings) -> any NoteDestination
    /// `@reminder`: the reminder in a text, by the clock now; adding a confirmed one.
    public var parseReminder: (String) -> ReminderDraft
    public var addReminder: @Sendable (ReminderDraft) async throws -> Void
    /// `@imessage`: the address book (nil: no access), and sending.
    public var loadContacts: @Sendable () async -> [Contact]?
    public var messageSender: any MessageSender

    public init(converter: Converter = Converter(), loadSettings: @escaping () -> Config = { .default }) {
        self.converter = converter
        self.loadSettings = loadSettings
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
        loadSearchKey = { nil }
        takeRenameNotice = { _ in nil }
        noteDestination = { _ in NoDestination() }
        parseReminder = { ReminderParser().parse($0, now: Platform.current.clock.now) }
        addReminder = { _ in throw SessionServicesError.unsupported }
        loadContacts = { nil }
        messageSender = NoMessageSender()
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

/// What a default service says when it is asked to do something its shell gave it no way to do.
public enum SessionServicesError: Error, Equatable, Sendable {
    case unsupported
}

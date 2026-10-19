import Foundation

/// One piece of work a session started that answers later: what its updates (`SessionEvent.task`) belong to. Work in a
/// slot is one at a time there: starting another stops it, and what it still sends is dropped (`SessionTasks.isCurrent`).
public struct TaskID: Hashable, Sendable {
    public enum Slot: Hashable, Sendable {
        /// A level-two request (the AI, a command's program, `@open`'s search, `@tasks`): what Esc cancels.
        case request
        /// A `list` command run as its text is typed.
        case list
        /// `@open` searched as its text is typed.
        case liveSearch
        /// A send command's recipient looked up as it is typed.
        case recipients
        /// The script extension of the request in level two, run by the shell (`SessionServices.startScript`).
        case script
    }

    public let slot: Slot?
    public let serial: Int
}

/// What a session's work answers with, on whatever thread it ran: the shell hands it back on the session's own
/// (`SessionEvent.task`).
public enum TaskUpdate: Sendable {
    /// Level two's stream for request `request`: the conversion, a command's answer, a program's output.
    case converted(ConversionUpdate, request: Int)
    /// Request `request` failed (`DescribedError`: already said in the interface language).
    case failed(any Error, request: Int)
    /// `@open`'s results, or `@tasks`' list, for request `request`.
    case searched([SearchResult], request: Int)
    /// A script extension's environment is ready for request `request`: it can start now.
    case environment([String: String], request: Int)
    /// What a script extension printed for request `request`, so far or all of it.
    case script(CommandRunner.ScriptUpdate, request: Int)
    /// What a `list` command printed for the text `query`.
    case list(ScriptOutput, query: String)
    /// `@open`'s results for the text as typed.
    case live([SearchResult], query: String)
    /// The recipients found for the text typed after a send command, and what the panel says about them.
    case recipients([Recipient], note: String?, query: String)
}

/// What a session hears from outside a key: its work's answers (`task`), for now. The shell gets these on any thread
/// (`SessionTasks.deliver`) and hands each to the session on the session's own.
public enum SessionEvent: Sendable {
    case task(TaskID, TaskUpdate)
}

/// An error already said in the interface language (`UIText.describe`), passed on as its message.
public struct DescribedError: LocalizedError, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// What a script extension's run tells the session of the field it belongs to.
public enum ScriptRunEvent: Sendable {
    case update(CommandRunner.ScriptUpdate)
    case failed(any Error)
}

/// The work a text field's session starts that answers later: level two's requests and their streams, script
/// extensions, `list` commands run as they're typed, `@open`'s searches, the recipients of a send command. It runs off the
/// session's thread (no actor) and answers through `deliver`, which the shell turns into a call of the session on its
/// own thread: the Mac's main queue, the Windows engine's session queue. What is typed fast is waited for (a `list`'s
/// `queryDelay`, `@open` and the recipients a moment); a newer one stops the one before, in its slot.
///
/// Used from the session's thread only.
public final class SessionTasks {
    /// Where the answers go: to the shell, which hands them to the session on its thread.
    public let deliver: @Sendable (SessionEvent) -> Void
    private var serial = 0
    private var running: [TaskID.Slot: (id: TaskID, task: Task<Void, Never>?)] = [:]
    /// What the `list`, `@open` and recipient slots run (or wait to run) for: a text that stays the same isn't run again.
    private var listKey: String?
    private var liveQuery: String?
    private var recipientQuery: String?

    static let log = CoreLog(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "ime")

    public init(deliver: @escaping @Sendable (SessionEvent) -> Void) {
        self.deliver = deliver
    }

    /// Whether `id`'s updates still count: work in a slot until it's stopped or another takes its place.
    public func isCurrent(_ id: TaskID) -> Bool {
        guard let slot = id.slot else { return true }
        return running[slot]?.id == id
    }

    /// Stops the work in `slot`; nothing more of it counts.
    public func cancel(_ slot: TaskID.Slot) {
        running[slot]?.task?.cancel()
        running[slot] = nil
    }

    /// An id in `slot` for work the shell runs (a script extension's run), stopping what ran there: what it tells counts
    /// until it is stopped too, or another takes its place.
    public func token(_ slot: TaskID.Slot) -> TaskID {
        cancel(slot)
        serial += 1
        let id = TaskID(slot: slot, serial: serial)
        running[slot] = (id, nil)
        return id
    }

    /// Starts `work` (in `slot`, stopping what ran there); `post` hands an update on unless the work was stopped.
    @discardableResult
    func start(_ slot: TaskID.Slot?, _ work: @escaping @Sendable (_ post: @escaping @Sendable (TaskUpdate) -> Void) async -> Void)
        -> TaskID {
        if let slot { cancel(slot) }
        serial += 1
        let id = TaskID(slot: slot, serial: serial)
        let deliver = deliver
        let task = Task {
            await work { update in
                guard !Task.isCancelled else { return }
                deliver(.task(id, update))
            }
        }
        if let slot { running[slot] = (id, task) }
        return id
    }

    // MARK: - Level two

    /// A level-two request as the session starts it (`Composer.Effect.startConversion` and the like).
    public struct Request: Sendable {
        public var input: String
        /// The command (nil: improve).
        public var command: Command?
        /// The commands inside the text, run first (`CommandPlan`).
        public var plan: CommandPlan?
        /// Past any answer kept from before (`@question`'s re-ask).
        public var fresh: Bool
        /// `@reply`'s web page (`Prompt.replyMessage(_:page:)` of nothing), added after its message once the commands
        /// inside it have run.
        public var replyPage: String
        /// `@reply`'s context (`Composer.replyContext`).
        public var replyContext: ReplyContext?

        public init(input: String, command: Command? = nil, plan: CommandPlan? = nil, fresh: Bool = false, replyPage: String = "",
                    replyContext: ReplyContext? = nil) {
            self.input = input
            self.command = command
            self.plan = plan
            self.fresh = fresh
            self.replyPage = replyPage
            self.replyContext = replyContext
        }
    }

    /// Where a request runs, as the session finds it when the request starts.
    public struct Place: Sendable {
        /// The app's own rewrite styles, or no AI at all (`AppProfile`).
        public var app: String?
        /// A terminal runs each line it is given: there `@search`'s list, and a program's output, goes in as one line.
        public var terminal: Bool
        /// Line breaks can go into the terminal as a paste (the Mac's `TerminalPaste`): an answer keeps them.
        public var pastesInTerminal: Bool
        /// `Config.improveTranslates`.
        public var improveTranslates: Bool
        /// The language script plugins are told (`UIText.pluginLanguage`).
        public var pluginLanguage: Language

        public init(app: String?, terminal: Bool, pastesInTerminal: Bool, improveTranslates: Bool, pluginLanguage: Language) {
            self.app = app
            self.terminal = terminal
            self.pastesInTerminal = pastesInTerminal
            self.improveTranslates = improveTranslates
            self.pluginLanguage = pluginLanguage
        }
    }

    /// Streams level two for `request` (request `id`): the improve conversion, a `.generate` command's answer, what a
    /// `.run` command's program printed, a text with commands inside it.
    public func convert(_ request: Request, id: Int, in place: Place, services: SessionServices) {
        consume(Self.stream(for: request, in: place, services: services), id: id)
    }

    /// The stream for `request` (`convert`).
    public static func stream(for request: Request, in place: Place, services: SessionServices)
        -> AsyncThrowingStream<ConversionUpdate, Error> {
        let (runPlugin, runProgram, converter, loadSearchKey) = (services.runPlugin, services.runProgram, services.converter,
                                                                 services.loadSearchKey)
        let (app, fresh, improveTranslates, pluginLanguage) = (place.app, request.fresh, place.improveTranslates, place.pluginLanguage)
        let searchList: WebSearch.Output = place.terminal ? .line : .list
        let streamFor: @Sendable (Command?, String) -> AsyncThrowingStream<ConversionUpdate, Error> = { command, input in
            if command == .read { return WebReader.stream(input) }
            // @py, @js: the code runs in a child process, like a custom program (never in this one).
            if let command, let code = InlineCode.definition(for: command) { return runProgram(code, input) }
            if command == .webSearch { return WebSearch.stream(input, output: searchList, loadKey: loadSearchKey) }
            // A link opens once the commands inside its text have run: their outputs go in it as they are.
            if let command, command.kind == .link { return LinkTemplate.passThrough(input) }
            if command?.kind == .message { return CommandPipeline.unchanged(input) }  // sent as written, after confirming
            if let command, command.kind == .run, let plugin = command.plugin { return runPlugin(plugin, input, pluginLanguage) }
            if let command, command.kind == .run, let custom = command.custom { return runProgram(custom, input) }
            // @improve, @translate, or both written together: one request (`WritingMode`).
            if command == nil || command?.kind == .convert {
                let (mode, text) = WritingMode.parse(command, input, improveTranslates: improveTranslates)
                return converter.convert(text, mode: mode, app: app)
            }
            return command.map { converter.generate($0, input: input, app: app, fresh: fresh) } ?? converter.convert(input, app: app)
        }
        let command = request.command
        let stream: AsyncThrowingStream<ConversionUpdate, Error>
        if let plan = request.plan, !plan.isEmpty {
            // @search inside a text is context for the AI, but not where the text goes out as written: into a
            // web page (a link) or to a person (a message).
            let innerSearch = WebSearch.Output.inside(command)
            let (replyContext, replyPage) = (request.replyContext, request.replyPage)
            // The commands inside the text first (together), then this one on the text with their outputs.
            stream = CommandPipeline.run(plan, inner: { command, argument in
                // Its errors (no key, say) in the interface language.
                command == .webSearch ? described(WebSearch.stream(argument, output: innerSearch, loadKey: loadSearchKey))
                    : streamFor(command, argument)
            }, outer: { text in
                // @reply: the text with the commands' outputs is what to reply (capped as what's typed is), sent with the
                // rest of its context, and the page if it goes along.
                guard let context = replyContext else { return streamFor(command, text) }
                return streamFor(command, Prompt.replyMessage(context.withIntent(text)) + replyPage)
            })
        } else {
            stream = streamFor(command, request.input)
        }
        // A terminal runs each line it is given: a program's output goes in as one line there, and so does
        // an answer with line breaks (code) unless they can go in as a paste.
        let oneLine = place.terminal && (command?.kind == .run || (command?.kind == .generate && !place.pastesInTerminal))
        return oneLine ? Self.oneLine(stream) : stream
    }

    /// Asks again for the results shown, revised as the refinement's last instruction says ("shorter"): the same request
    /// as before (`WritingMode` from the command, as `stream(for:)` works it out), with the conversation after it.
    /// `sent`: what a command's request is sent with (`@reply`'s with its page).
    public func refine(_ refinement: Refinement, id: Int, sent: String?, in place: Place, converter: Converter) {
        let stream: AsyncThrowingStream<ConversionUpdate, Error>
        var generates = false
        switch refinement.request {
        case let .writing(command, input):
            let (mode, text) = WritingMode.parse(command?.kind == .convert ? command : nil, input, improveTranslates: place.improveTranslates)
            stream = converter.convert(text, mode: mode, app: place.app, turns: refinement.turns)
        case let .command(command, input):
            stream = converter.generate(command, input: sent ?? input, app: place.app, fresh: refinement.fresh, turns: refinement.turns)
            generates = true
        }
        // In a terminal an answer goes in on one line unless it can be pasted, as the first time.
        let oneLine = generates && place.terminal && !place.pastesInTerminal
        consume(oneLine ? Self.oneLine(stream) : stream, id: id)
    }

    /// Translate as You Type's request for `input` (`Composer.Effect.startTranslateMode`), in the app's settings; in a
    /// terminal on one line.
    public func translate(_ input: String, session: TranslateMode.Session, id: Int, in place: Place, converter: Converter) {
        let stream = converter.translateMode(input, target: session.target, app: place.app)
        consume(place.terminal ? Self.oneLine(stream) : stream, id: id)
    }

    /// Hands `stream`'s updates for request `id` on, and its error if it fails.
    public func consume(_ stream: AsyncThrowingStream<ConversionUpdate, Error>, id: Int) {
        start(.request) { post in
            do {
                for try await update in stream {
                    guard !Task.isCancelled else { return }
                    post(.converted(update, request: id))
                }
            } catch {
                guard !Task.isCancelled else { return }
                post(.failed(error, request: id))
            }
        }
    }

    /// `stream` with each result on one line (`CommandRunner.oneLine`): what goes into a terminal.
    public static func oneLine(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) -> AsyncThrowingStream<ConversionUpdate, Error> {
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

    /// `stream` with its error said in the interface language: inside a text, an inner command's error reaches the panel
    /// only as its message (`CommandPipelineError.inner`).
    public static func described(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await update in stream { continuation.yield(update) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: DescribedError(message: UIText.describe(error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - @open and @tasks

    /// `@open` after ⏎: the files and apps for `query`, what it opened before first.
    public func search(_ query: String, id: Int, history: OpenHistory,
                       with searchFiles: @escaping @Sendable (String, OpenHistory) async -> [SearchResult]) {
        start(.request) { post in
            let results = await searchFiles(query, history)
            guard !Task.isCancelled else { return }
            Self.log.notice("search \(id): \(results.count) results")
            post(.searched(results, request: id))
        }
    }

    /// `@tasks`: the background agents, newest first, each with its last reply.
    public func listAgents(id: Int, with list: @escaping @Sendable () async throws -> [(session: AgentSession, reply: String?)]) {
        start(.request) { post in
            let results: [SearchResult]
            do {
                results = try await list().map { session, reply in
                    let mark = session.progress == .done ? "✓" : session.progress == .needsYou ? "⚠︎" : "…"
                    return SearchResult(name: "\(mark) \(session.name ?? session.shortID)",
                                        path: SearchResult.agentPrefix + session.shortID, detail: reply)
                }
            } catch {
                post(.failed(DescribedError(message: UIText.describe(error)), request: id))
                return
            }
            post(.searched(results, request: id))
        }
    }

    /// `@open` as you type: a short pause after the text changes, then a search for it. Not for a single letter
    /// (`FileSearchRanking.searchesAsYouType`): that takes seconds; ⏎ searches it. Nil: no `@open` text.
    public func searchAsTyped(_ query: String?, history: @escaping () -> OpenHistory,
                              with searchFiles: @escaping @Sendable (String, OpenHistory) async -> [SearchResult]) {
        guard query != liveQuery else { return }
        liveQuery = query
        cancel(.liveSearch)
        guard let query, FileSearchRanking.searchesAsYouType(query) else { return }
        let history = history()
        start(.liveSearch) { post in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let results = await searchFiles(query, history)
            post(.live(results, query: query))
        }
    }

    // MARK: - Recipients

    /// A send command's recipient as it is typed: a short pause, then the contacts that match (access to the address book
    /// is asked for there, the first time). Nil: no recipient being typed.
    public func findRecipients(_ query: String?, recent: @escaping () -> [String],
                               contacts loadContacts: @escaping @Sendable () async -> [Contact]?) {
        guard query != recipientQuery else { return }
        recipientQuery = query
        cancel(.recipients)
        guard let query else { return }
        let recent = recent()
        start(.recipients) { post in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let contacts = await loadContacts()
            guard !Task.isCancelled else { return }
            let found = await Task.detached { RecipientSearch.results(query, contacts: contacts ?? [], recent: recent) }.value
            let note = contacts == nil
                ? tr("没有通讯录权限：系统设置 → 隐私与安全性 → 通讯录 → 打开 AllInOneIME；也可以直接输入手机号或邮箱",
                     "No access to Contacts: System Settings → Privacy & Security → Contacts → turn on AllInOneIME; or type a phone number or email")
                : found.isEmpty ? (query.isEmpty ? tr("输入名字、拼音、手机号或邮箱", "Type a name, phone number or email")
                                                 : tr("没有找到联系人；也可以输入完整的手机号或邮箱", "No contact found; or type a full phone number or email"))
                : nil
            post(.recipients(found, note: note, query: query))
        }
    }

    // MARK: - Script extensions

    /// What builds `command`'s environment, with what it needs of the text field taken now (`context`): it needs nothing
    /// of the field afterwards, which may be gone by the time it runs. The secret store (password preferences) and the
    /// platform's environment (the login shell's PATH on the Mac) are read off the session's thread: never while a key is
    /// handled. A required preference of its bundle not set yet keeps it from running: the message says so.
    public static func environmentMaker(_ command: ScriptCommand, bundle: ExtensionBundle?, config: Config, context: ScriptContext,
                                        preferences: @escaping @Sendable (ExtensionBundle, Config) -> [String: String],
                                        status: Bool = false, action: Bool = false)
        -> @Sendable () async -> Result<[String: String], DescribedError> {
        let missingMessage = { @Sendable (missing: ExtensionBundle.Preference, bundle: ExtensionBundle) in
            tr("先在设置里填好「\(missing.title)」（\(bundle.title)）", "Set “\(missing.title)” for \(bundle.title) in the settings first")
        }
        return {
            await Task.detached(priority: .userInitiated) { () -> Result<[String: String], DescribedError> in
                let values = bundle.map { preferences($0, config) } ?? [:]
                if let bundle, let missing = bundle.preferences.first(where: { $0.required && (values[$0.name] ?? "").isEmpty }) {
                    return .failure(DescribedError(message: missingMessage(missing, bundle)))
                }
                return .success(context.environment(for: command, base: Platform.current.processes.environment, preferences: values,
                                                    status: status, action: action))
            }.value
        }
    }

    /// A script extension for request `id`: its environment first (`environmentMaker`); it's ready as
    /// `TaskUpdate.environment`, or why not as `failed`. The session starts it then, if the request is still on.
    public func prepareScript(id: Int, environment: @escaping @Sendable () async -> Result<[String: String], DescribedError>) {
        start(nil) { post in
            switch await environment() {
            case let .success(environment): post(.environment(environment, request: id))
            case let .failure(error): post(.failed(error, request: id))
            }
        }
    }

    /// A `list` command as it's typed (`Composer.listQuery`): run after its `queryDelay` once the text stops changing (the
    /// run before stopped), and again after the list's `rerun` while the same text is shown. `now`: without the delay
    /// (`Composer.Effect.refreshList`). Not while secure input is on.
    public func runList(_ query: String?, command: Command?, now: Bool = false, secureInput: Bool,
                        environment: (ScriptCommand, String) -> @Sendable () async -> Result<[String: String], DescribedError>) {
        if now { listKey = nil }
        let key = query.flatMap { query in command.map { $0.name + "\u{0}" + query } }
        guard key != listKey else { return }
        listKey = key
        cancel(.list)
        guard let query, let command, let script = command.script else { return }
        guard !secureInput, case let .success(arguments) = script.arguments(from: query) else { return }
        let makeEnvironment = environment(script, query)
        start(.list) { post in
            var delay = now ? 0 : script.queryDelay
            var environment: [String: String]?
            while true {
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                guard !Task.isCancelled else { return }
                if environment == nil {
                    switch await makeEnvironment() {
                    case let .success(env): environment = env
                    case let .failure(error):
                        // A required preference isn't set: the list says so.
                        post(.list(.text(error.message), query: query))
                        return
                    }
                }
                guard !Task.isCancelled, let env = environment else { return }
                var output: ScriptOutput?
                do {
                    for try await update in CommandRunner.run(script, arguments: arguments, environment: env) where update.isFinal {
                        output = update.output
                    }
                } catch {
                    output = .text(UIText.describe(error))
                }
                guard !Task.isCancelled, let output else { return }
                post(.list(output, query: query))
                guard case let .list(list) = output, let rerun = list.rerun else { return }
                delay = rerun
            }
        }
    }
}

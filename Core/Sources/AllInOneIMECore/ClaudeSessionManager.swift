import Foundation

/// A running `claude` process of the input method's session, as `ClaudeSessionManager` drives it.
public protocol ClaudeSessionProcess: AnyObject, Sendable {
    /// Writes one stream-json line to its standard input.
    func send(_ line: Data) throws
    /// Closes its standard input: nothing more is written (a command that reads it to its end goes on).
    func closeInput()
    /// Ends it (and what it started): asked to (SIGTERM).
    func terminate()
    /// Ends it and what it started at once (SIGKILL): what `terminate` didn't end.
    func kill()
    /// Whether it, or anything it started, still runs.
    var isRunning: Bool { get }
}

extension ClaudeSessionProcess {
    public func closeInput() {}
    public func kill() { terminate() }
    public var isRunning: Bool { false }
}

/// Starts the session's process: the real one (`ProcessClaudeSessionLauncher`), or a test's.
public protocol ClaudeSessionLauncher: Sendable {
    /// Starts `claude` with `arguments` in `directory`. Each line it writes to its standard output goes to `output`, in
    /// order, on one thread; then `exited`, once, with its status and the end of what it wrote to standard error.
    /// Throws `ClaudeSessionError.notInstalled` when there is no `claude`.
    func start(_ arguments: [String], in directory: URL, output: @escaping @Sendable (Data) -> Void,
               exited: @escaping @Sendable (Int32, String) -> Void) throws -> any ClaudeSessionProcess
    /// Whether there is a program to start (`start` throws `notInstalled` when there isn't).
    func installed() -> Bool
    /// The environment it starts the program with.
    func startEnvironment() -> [String: String]
}

extension ClaudeSessionLauncher {
    public func installed() -> Bool { true }
    public func startEnvironment() -> [String: String] { ProcessInfo.processInfo.environment }
}

/// Keeps the input method's session on an agent (`backend`: Claude Code, `ClaudeSession`, or an ACP agent such as Kiro
/// CLI, `ACPBackend`; one manager per agent) running and asks it questions. One process at a time,
/// for every text field: started ahead of the first question (`prewarm`, when the command trigger is typed), so the
/// answer doesn't wait for Claude Code to start; reused for each question; ended after `idleTimeout` without one. Each
/// `@question` conversation in the panel goes into a new conversation of the agent (`enter`), its follow-ups into that
/// one: `prewarm` gets the new one ready (Codex and an ACP agent open it in the process they have, Claude Code's process
/// is started again on it), so that it is warm when the question comes. A process that ended (a crash, killed) is
/// started again on the same conversation (`--resume`) by its next question. A question asked while another
/// is answered waits for it; stopping one (`ask`'s stream given up: Esc) interrupts its turn and the process stays.
/// Handing the session to Terminal (`handOff`) ends the process; while the Terminal one runs (its id in
/// `ClaudeSessionStore.terminalPIDFile`), no process starts here and questions fail with `.openInTerminal`.
/// A question with no sign of an answer within `firstAnswerTimeout` (Claude Code stuck starting, an `awsAuthRefresh`
/// sign-in waiting in a browser) fails with `.noResponse`, which falls back to the provider, and the process ends; one
/// whose agent begins compacting the conversation before answering fails with `.compacting` at once (not waited for); so
/// does one answering that says nothing more (not a line) for `answerIdleTimeout`, and one stopped while it answered
/// that doesn't end within `interruptTimeout` (an agent deaf to the interrupt): the process is stuck, the next question
/// starts it again. A question waiting behind one being answered waits `firstAnswerTimeout` at most, then fails with
/// `.busy` (the provider answers). A process that ends before its session starts, twice, fails the question with
/// `.failedToStart` (the provider answers) and the agent is `.cannotStart` until its sign-in is looked at again.
/// It also keeps what one long session needs across questions: the values hidden (`redacting`), so that a placeholder
/// never stands for two values, and which answers the session saw (`missing`, `remember`).
/// Whether the agent can answer at all (`availability`) is looked at only once the session could answer a question
/// (`checkAvailability`), never at launch: with the provider picked for questions no sign-in check runs.
public final class ClaudeSessionManager: @unchecked Sendable {
    /// Without a question for this long, the process ends.
    public static let idleTimeout: Duration = .seconds(15 * 60)
    /// A question's longest wait for the first sign of its answer (the model's message starting; a web search after
    /// that may take longer), and a question's longest wait behind another being answered.
    public static let firstAnswerTimeout: Duration = .seconds(30)
    /// Once the answer started, the longest time without a line of the process (a web page read, the model thinking
    /// say something every few seconds).
    public static let answerIdleTimeout: Duration = .seconds(180)
    /// A turn stopped (Esc) while it answered: how long it has to end before its process counts as stuck.
    public static let interruptTimeout: Duration = .seconds(5)
    /// The sign-in check's longest run; past it, it counts as signed out.
    public static let checkTimeout: Duration = .seconds(15)
    /// A sign-in check that didn't find the agent ready stands this long (seconds) before the next one may run.
    public static let recheckInterval: TimeInterval = 60

    public let store: ClaudeSessionStore
    /// The agent the session runs on, and how its process is talked to.
    public let backend: any SessionBackend
    private let launcher: any ClaudeSessionLauncher
    private let idleTimeout: Duration
    private let clock: any Clock<Duration>
    private let firstAnswerTimeout: Duration
    private let answerIdleTimeout: Duration
    private let interruptTimeout: Duration
    private let answerClock: any Clock<Duration>
    private let isAlive: @Sendable (Int32) -> Bool
    private let userSettings: @Sendable () -> URL?
    private let uptime: @Sendable () -> TimeInterval
    private let state = Locked(initialState: State())
    private let kept = Locked<Kept?>(initialState: nil)

    /// `isAlive`: whether a process id is a running process (the hand-off's Terminal one). `userSettings`: the user's
    /// Claude Code settings.json (`ClaudeSession.userSettingsFile`), whose provider settings the session gets; nil: none.
    /// `answerClock`: what `firstAnswerTimeout`, `answerIdleTimeout`, `interruptTimeout` and `checkTimeout` are timed
    /// with; `uptime`: seconds, what `recheckInterval` is. `store`: nil, the backend's own folder.
    public init(backend: any SessionBackend = ClaudeCodeBackend(), launcher: any ClaudeSessionLauncher, store: ClaudeSessionStore? = nil,
                idleTimeout: Duration = ClaudeSessionManager.idleTimeout, clock: any Clock<Duration> = ContinuousClock(),
                firstAnswerTimeout: Duration = ClaudeSessionManager.firstAnswerTimeout,
                answerIdleTimeout: Duration = ClaudeSessionManager.answerIdleTimeout,
                interruptTimeout: Duration = ClaudeSessionManager.interruptTimeout,
                answerClock: any Clock<Duration> = ContinuousClock(),
                isAlive: @escaping @Sendable (Int32) -> Bool = { _ in false },
                userSettings: @escaping @Sendable () -> URL? = { ClaudeSession.userSettingsFile() },
                uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.backend = backend
        self.launcher = launcher
        self.store = store ?? ClaudeSessionStore(backend)
        self.idleTimeout = idleTimeout
        self.clock = clock
        self.firstAnswerTimeout = firstAnswerTimeout
        self.answerIdleTimeout = answerIdleTimeout
        self.interruptTimeout = interruptTimeout
        self.answerClock = answerClock
        self.isAlive = isAlive
        self.userSettings = userSettings
        self.uptime = uptime
    }

    /// What is kept of the session `session`: `memory` as saved, and the values hidden so far (in memory only).
    private struct Kept {
        var memory: ClaudeSessionStore.Memory
        var known: [Redaction.Hidden] = []
    }

    /// A question being answered, or waiting for the one before it.
    private final class Turn: @unchecked Sendable {
        let id: Int
        let message: String
        let continuation: AsyncThrowingStream<String, Error>.Continuation
        /// The answer so far (of the model's latest message: after a web search the answer starts again).
        var text = ""
        var restarts = false
        var error: ClaudeSessionError?
        /// Written to the process.
        var sent = false
        /// Given up (interrupted): what still comes for it is dropped.
        var done = false
        /// Started again once already after the process couldn't start the session.
        var retried = false
        /// Some sign of the answer came (the model's message started, text, the turn's end): no `firstAnswerTimeout`,
        /// `answerIdleTimeout` from then on.
        var answering = false
        /// How long ago it was written; once it answers, since the process's latest line; once given up while it
        /// answered, since then (`ClaudeSessionManager.mark`).
        var since: @Sendable () -> Duration = { .zero }
        /// Ends it when it is overdue (`overdue`), or, waiting, after `firstAnswerTimeout` behind one that answers.
        var watchdog: Task<Void, Never>?
        var attempt = 0

        init(id: Int, message: String, continuation: AsyncThrowingStream<String, Error>.Continuation) {
            self.id = id
            self.message = message
            self.continuation = continuation
        }
    }

    private struct Running: @unchecked Sendable {
        var process: any ClaudeSessionProcess
        /// What talks to it (`SessionDriver`), used under the lock only.
        var driver: any SessionDriver
        var generation: Int
        var resume: Bool
        /// The agent conversation it is on (`store`'s id when it started, or moved: `follow`).
        var conversation: String
        /// The session started (its "init" came): a failure before that is the start's.
        var started = false
    }

    private struct State {
        var running: Running?
        var generation = 0
        /// The turn written (first) and the ones waiting, in order.
        var turns: [Turn] = []
        var serial = 0
        var idle: Task<Void, Never>?
        var availability = ClaudeSession.Availability.unknown
        /// When `availability` was last found (`uptime`), nil: never; the sign-in check running, if one is.
        var checkedAt: TimeInterval?
        var checking: Task<ClaudeSession.Availability, Never>?
        /// The sign-in check's run, while its command runs (ended with the rest when the input method quits).
        var signInCheck: SignInCheck?
        /// The panel conversation (`QuestionConversation.id`) whose questions go into the agent conversation now
        /// (`store`'s id: `enter`); nil: none said.
        var owner: String?
        /// A question went into the agent conversation now; nil: not looked at yet (`asked`).
        var asked: Bool?
    }

    /// What is done once the lock is let go (finishing a stream runs its consumer's code).
    private enum Action {
        case send(any ClaudeSessionProcess, Data)
        case yield(AsyncThrowingStream<String, Error>.Continuation, String)
        case finish(AsyncThrowingStream<String, Error>.Continuation, Error?)
        case terminate(any ClaudeSessionProcess)
    }

    // MARK: - What it's asked

    /// Whether the agent can answer here, as last found (`checkAvailability`; each answer, or failure, tells too). Set:
    /// found now.
    public var availability: ClaudeSession.Availability {
        get { state.withLock { $0.availability } }
        set {
            let now = uptime()
            state.withLock { ($0.availability, $0.checkedAt) = (newValue, now) }
        }
    }

    /// Whether the agent can answer here, its sign-in check run (`signInCheck`) if it is still to be: the first time it is
    /// asked (an `@question` about to be asked or asked while Automatic picks the session: `Converter
    /// .questionSessionChecked`; Settings), never before. Ready is kept for the launch (an answer that fails says
    /// otherwise); anything else (not installed, signed out, a question that failed so) is looked at again when next
    /// asked, `recheckInterval` after the last look at the earliest. `force`: looked at now. A check running is waited for.
    public func checkAvailability(force: Bool = false) async -> ClaudeSession.Availability {
        let now = uptime()
        let check = state.withLock { state -> Task<ClaudeSession.Availability, Never>? in
            if let checking = state.checking { return checking }
            if !force, state.availability == .ready || state.checkedAt.map({ now - $0 < Self.recheckInterval }) == true {
                return nil
            }
            let task = Task { [weak self] in await self?.lookAtSignIn() ?? .unknown }
            state.checking = task
            return task
        }
        guard let check else { return availability }
        return await check.value
    }

    private func lookAtSignIn() async -> ClaudeSession.Availability {
        let found = await signInCheck()
        let now = uptime()
        return state.withLock { state in
            (state.availability, state.checkedAt, state.checking, state.signInCheck) = (found, now, nil, nil)
            return found
        }
    }

    /// Runs the agent's sign-in check (`backend.availabilityArguments`, its `availabilityInput` written to it) as the
    /// session will find it (`authStatusArguments`): ready when its answer (a line, or its exit) says signed in; not
    /// installed when there's no program; else (signed out, can't tell, no answer within `checkTimeout`) signed out. An
    /// agent whose settings and files say it (`SessionBackend.signedIn(environment:home:)`) isn't run.
    private func signInCheck() async -> ClaudeSession.Availability {
        if let signedIn = backend.signedIn(environment: launcher.startEnvironment(), home: CorePaths.home) {
            guard launcher.installed() else { return .notInstalled }
            return signedIn ? .ready : .signedOut
        }
        let arguments = authStatusArguments()
        let (backend, launcher, directory, clock) = (backend, launcher, store.directory, answerClock)
        return await withCheckedContinuation { continuation in
            let check = SignInCheck(backend: backend, continuation: continuation)
            state.withLock { $0.signInCheck = check }
            do {
                let process = try launcher.start(arguments, in: directory, output: { check.line($0) },
                                                 exited: { status, _ in check.exited(status) })
                check.started(process)
                for line in backend.availabilityInput { try process.send(line) }
                if backend.availabilityInput.isEmpty { process.closeInput() }
            } catch ClaudeSessionError.notInstalled {
                check.finish(.notInstalled)
                return
            } catch {
                check.finish(.signedOut)
                return
            }
            check.timeout(Task {
                do { try await clock.sleep(for: Self.checkTimeout) } catch { return }
                check.finish(.signedOut)
            })
        }
    }

    /// Whether `@question` goes to this session with `config` as far as this session can tell (`Config
    /// .questionSessionAgent`, the other agents' sessions taken as not ready); the converter asks with all of them.
    public func answersQuestions(_ config: Config) -> Bool {
        let own = availability
        return config.questionSessionAgent(availability: { $0 == backend.agent ? own : .unknown }) == backend.agent
    }

    /// Whether the process runs now.
    public var isRunning: Bool { state.withLock { $0.running != nil } }

    /// Gets a new agent conversation ready for the question about to be asked (an `@question` typed: a new conversation
    /// in the panel), its process started now if it isn't running, so that the answer doesn't wait for the agent to
    /// start; it ends after `idleTimeout` unless a question comes. One that has had no question yet is kept; one that has
    /// is left (it stays in the agent's history) and the process moves to the new one (`follow`).
    public func prewarm() {
        let actions = state.withLock { state -> [Action] in
            guard state.turns.isEmpty else { return [] }
            if asked(&state) { rollOver(&state) }
            var actions = follow(&state)
            if state.running == nil {
                guard !terminalOpen(), let (_, opening) = try? start(&state) else { return actions }
                actions += opening
            }
            scheduleIdle(&state)
            return actions
        }
        perform(actions)
    }

    /// The questions of `conversation` (an `@question` conversation in the panel) go into the agent conversation from now
    /// on; asked before `redacting`, `missing` and `ask`, which go by it. The agent conversation its earlier questions
    /// went into, or, for another one, a new agent conversation, unless the one now has had no question yet (the one
    /// `prewarm` made ready for it). Nil: the one now, whichever.
    public func enter(_ conversation: QuestionConversation?) {
        guard let conversation else { return }
        state.withLock { state in
            guard state.owner != conversation.id else { return }
            if asked(&state) { rollOver(&state) }
            state.owner = conversation.id
        }
    }

    /// Asks `question` (one user message: the text as the provider would get it, already redacted). The stream gives
    /// the answer so far each time more of it comes, and ends with the turn; given up (cancelled), it interrupts the turn.
    public func ask(_ question: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let id = state.withLock { state -> Int in
                state.serial += 1
                return state.serial
            }
            continuation.onTermination = { [weak self] termination in
                if case .cancelled = termination { self?.cancel(id) }
            }
            let actions = state.withLock { state -> [Action] in
                if terminalOpen() { return [.finish(continuation, ClaudeSessionError.openInTerminal)] }
                let turn = Turn(id: id, message: question, continuation: continuation)
                state.turns.append(turn)
                let actions = pump(&state)
                // Behind one being answered: it waits so long at most.
                if !turn.sent, state.turns.first?.answering == true { waitAtMost(turn) }
                return actions
            }
            perform(actions)
        }
    }

    /// Stops the turn being answered (its stream ends with `CancellationError`); the process stays.
    public func interrupt() {
        let actions = state.withLock { state -> [Action] in
            guard let turn = state.turns.first, turn.sent, !turn.done else { return [] }
            givenUp(turn)
            return [.finish(turn.continuation, CancellationError())] + interruptAction(&state)
        }
        perform(actions)
    }

    /// Hands the session to Terminal: the process ends (a question being answered stops), and what Terminal is to run
    /// (`SessionBackend.terminalArguments`, `program` being where the agent is) in the session's folder; `followUp`: a
    /// follow-up goes after them as the last argument.
    public func handOff(program: String, followUp: Bool = false) throws -> (arguments: [String], directory: URL) {
        stop()
        let id = try store.sessionID()
        return (backend.terminalArguments(program: program, sessionID: id, agentSessionID: store.agentSessionID(),
                                          resume: store.resumable, followUp: followUp), store.directory)
    }

    public func handOff(claude: String) throws -> (arguments: [String], directory: URL) { try handOff(program: claude) }

    /// Ends the process, and the questions it was answering (the app quits, the settings changed).
    public func stop() {
        let actions = state.withLock { state -> [Action] in
            state.idle?.cancel()
            state.idle = nil
            let turns = state.turns
            state.turns = []
            for turn in turns { turn.watchdog?.cancel() }
            let process = state.running?.process
            state.running = nil  // what it still says, its exit too, is of no session now
            return turns.filter { !$0.done }.map { .finish($0.continuation, CancellationError()) } + (process.map { [.terminate($0)] } ?? [])
        }
        perform(actions)
    }

    /// Ends the processes of `managers` and what each started, a sign-in check's too: the input method quits (an
    /// update, logging out). Each is asked to end, then what is left after `grace` seconds is killed; returns once
    /// they're gone, or then.
    public static func stop(_ managers: [ClaudeSessionManager], grace: TimeInterval) {
        let processes = managers.flatMap { $0.end() }
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline, processes.contains(where: \.isRunning) { Thread.sleep(forTimeInterval: 0.02) }
        for process in processes { process.kill() }
    }

    /// `stop`, and the sign-in check's command ended too: the processes asked to end.
    private func end() -> [any ClaudeSessionProcess] {
        let (process, check) = state.withLock { ($0.running?.process, $0.signInCheck) }
        stop()
        return [process, check?.end()].compactMap { $0 }
    }

    /// A new conversation from now on ("start over" in the settings): the process ends, a new id is made.
    public func startOver() throws {
        stop()
        try state.withLock { state in
            try kept.withLock { kept in
                kept = nil
                try store.startOver()
            }
            (state.owner, state.asked) = (nil, false)
        }
    }

    /// The arguments of the command that says whether the agent is signed in, as the session will find it (Claude
    /// Code's `claude auth status`, `ClaudeSession.authStatusArguments`; `kiro-cli whoami`), run in `store.directory`;
    /// the folder and its provider settings are written first. Its exit status and output: `backend.signedIn`.
    public func authStatusArguments() -> [String] {
        try? store.prepare()
        return backend.availabilityArguments(settings: providerSettings())
    }

    /// The user's provider settings written into the session's folder, nil when there are none (or the agent takes none).
    private func providerSettings() -> URL? {
        guard backend.usesProviderSettings else { return nil }
        return userSettings().flatMap { store.writeProviderSettings(from: $0) }
    }

    // MARK: - What the session was told

    /// Runs `body` (the hiding of a question's texts, `Redaction.hide`) with a `Redaction` for `settings` that goes on
    /// from the session's earlier questions: a value hidden before keeps its placeholder, a new one gets a number none
    /// had, and the answers put back the earlier values too. One question's hiding at a time; what it hid is kept for the
    /// next (the numbers on disk, the values in memory). Hiding off: `body` gets nil.
    public func redacting<T>(_ settings: RedactionSettings, _ body: (inout Redaction?) -> T) -> (redaction: Redaction?, result: T) {
        kept.withLock { kept in
            guard settings.enabled, let id = try? store.sessionID() else {
                var none = Redaction(settings)
                let result = body(&none)
                return (none, result)
            }
            var current = load(&kept, id: id)
            let numbers = Dictionary(uniqueKeysWithValues: current.memory.numbers.compactMap { key, value in
                Redaction.Kind(rawValue: key).map { ($0, value) }
            })
            var redaction = Redaction(settings, known: current.known, numbers: numbers)
            let result = body(&redaction)
            if let redaction {
                current.known = redaction.hidden
                let saved = Dictionary(uniqueKeysWithValues: redaction.numbers.map { ($0.rawValue, $1) })
                if saved != current.memory.numbers {
                    current.memory.numbers = saved
                    store.save(current.memory)
                }
            }
            kept = current
            return (redaction, result)
        }
    }

    /// Of a conversation's `rounds` (before the question asked now), the ones whose answer the session neither gave nor
    /// was told (`remember`): the provider answered them, or they came from the saved history.
    public func missing(_ rounds: [QuestionChat.Round]) -> [QuestionChat.Round] {
        guard !rounds.isEmpty else { return [] }
        return kept.withLock { kept in
            guard let id = try? store.sessionID() else { return rounds }
            let answered = Set(load(&kept, id: id).memory.answered)
            return rounds.filter { !answered.contains(ClaudeSession.fingerprint($0.answer)) }
        }
    }

    /// `answers` are in the session now: it gave them, or was told them as context.
    public func remember(answers: [String]) {
        let prints = answers.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(ClaudeSession.fingerprint)
        guard !prints.isEmpty else { return }
        kept.withLock { kept in
            guard let id = try? store.sessionID() else { return }
            var current = load(&kept, id: id)
            current.memory.answered = current.memory.answered.filter { !prints.contains($0) } + prints
            current.memory.answered = Array(current.memory.answered.suffix(ClaudeSessionStore.Memory.maxAnswered))
            store.save(current.memory)
            kept = current
        }
    }

    /// What is kept of the session `id`: read from disk the first time (and after "start over").
    private func load(_ kept: inout Kept?, id: String) -> Kept {
        if let current = kept, current.memory.session == id { return current }
        let loaded = Kept(memory: store.memory(of: id))
        kept = loaded
        return loaded
    }

    // MARK: - The process

    /// Whether the session is open in Terminal (handed off) and that Claude Code still runs.
    private func terminalOpen() -> Bool {
        guard let pid = store.terminalPID() else { return false }
        if isAlive(pid) { return true }
        store.clearTerminalPID()
        return false
    }

    /// Whether a question went into the agent conversation now: one from before the launch counts as asked once it has
    /// begun (Claude Code's started on a question; an agent's session id given).
    private func asked(_ state: inout State) -> Bool {
        if let asked = state.asked { return asked }
        let asked = store.resumable || store.agentSessionID() != nil
        state.asked = asked
        return asked
    }

    /// A new agent conversation from now on (`ClaudeSessionStore.startOver`: a new id; the old one stays in the agent's
    /// history, and what was kept of it goes). The process, if it runs, moves to it once a question or `prewarm` needs
    /// it (`follow`).
    private func rollOver(_ state: inout State) {
        _ = try? store.startOver()
        (state.owner, state.asked) = (nil, false)
    }

    /// The running process on the agent conversation now: as it is when it's on it; moved to it when the agent can open
    /// another conversation in the same process (`SessionDriver.newConversation`); else ended, for `start` to start one
    /// on it.
    private func follow(_ state: inout State) -> [Action] {
        guard let running = state.running, let id = try? store.sessionID(), running.conversation != id else { return [] }
        if running.started, let lines = running.driver.newConversation() {
            state.running?.conversation = id
            return lines.map { .send(running.process, $0) }
        }
        state.running = nil  // its exit is of no session now
        state.idle?.cancel()
        state.idle = nil
        return [.terminate(running.process)]
    }

    /// Starts the process (with `--resume` once the session has a conversation), and what it is sent first (an ACP
    /// handshake).
    private func start(_ state: inout State) throws -> (Running, opening: [Action]) {
        if let running = state.running { return (running, []) }
        do {
            try store.prepare()
            let id = try store.sessionID()
            let resume = store.resumable
            state.generation += 1
            let generation = state.generation
            let arguments = backend.arguments(sessionID: id, resume: resume, settings: providerSettings())
            let driver = backend.driver(sessionID: id, agentSessionID: store.agentSessionID(), resume: resume,
                                        directory: store.directory)
            let process = try launcher.start(arguments, in: store.directory,
                                             output: { [weak self] in self?.received($0, generation: generation) },
                                             exited: { [weak self] in self?.exited(generation: generation, status: $0, message: $1) })
            let running = Running(process: process, driver: driver, generation: generation, resume: resume, conversation: id)
            state.running = running
            return (running, driver.opening().map { .send(process, $0) })
        } catch ClaudeSessionError.notInstalled {
            (state.availability, state.checkedAt) = (.notInstalled, uptime())
            throw ClaudeSessionError.notInstalled
        }
    }

    /// The first turn written to the process (started if it isn't running), unless one is being answered.
    private func pump(_ state: inout State) -> [Action] {
        while let first = state.turns.first, first.done, !first.sent { state.turns.removeFirst() }
        guard let turn = state.turns.first, !turn.sent else { return [] }
        // On another agent conversation (`enter` began a new one): moved to this one, or started again on it.
        let moved = follow(&state)
        let running: Running
        let opening: [Action]
        do {
            (running, opening) = try start(&state)
        } catch {
            let turns = state.turns
            state.turns = []
            let failure = error as? ClaudeSessionError ?? .failed(error.localizedDescription)
            return moved + turns.filter { !$0.done }.map { .finish($0.continuation, failure) }
        }
        state.idle?.cancel()
        state.idle = nil
        turn.sent = true
        state.asked = true
        watch(turn)
        return moved + opening + running.driver.message(turn.message).map { .send(running.process, $0) }
    }

    /// Now on `answerClock`, as how long ago it is (`Turn.since`).
    private func mark() -> @Sendable () -> Duration { Self.mark(answerClock) }

    private static func mark<C: Clock<Duration>>(_ clock: C) -> @Sendable () -> Duration {
        let start = clock.now
        return { start.duration(to: clock.now) }
    }

    /// `turn`, just written, is watched: it fails with `.noResponse` unless a sign of its answer comes within
    /// `firstAnswerTimeout` (then `overdue`).
    private func watch(_ turn: Turn) {
        turn.answering = false
        turn.since = mark()
        rewatch(turn)
    }

    /// `turn`'s watchdog started (again): it wakes when the turn may be overdue (`overdue`), and again until it ends.
    private func rewatch(_ turn: Turn) {
        turn.watchdog?.cancel()
        turn.attempt += 1
        let (id, attempt, clock, first) = (turn.id, turn.attempt, answerClock, left(turn))
        turn.watchdog = Task { [weak self] in
            var wait = first
            while true {
                do { try await clock.sleep(for: wait) } catch { return }
                guard let next = self?.overdue(id, attempt: attempt) else { return }
                wait = next
            }
        }
    }

    /// How long the sent `turn` may still take before it is overdue: its first sign within `firstAnswerTimeout` of being
    /// written, then a line at least each `answerIdleTimeout`; given up while it answered, its end within
    /// `interruptTimeout`.
    private func left(_ turn: Turn) -> Duration {
        let limit = !turn.answering ? firstAnswerTimeout : turn.done ? interruptTimeout : answerIdleTimeout
        return limit - turn.since()
    }

    /// `turn` (sent) was given up (Esc): once it answers, it has `interruptTimeout` to end.
    private func givenUp(_ turn: Turn) {
        turn.done = true
        guard turn.answering else { return }
        turn.since = mark()
        rewatch(turn)
    }

    /// The watchdog of the turn `id` woke: how much longer it waits (nil: no longer), or, the turn overdue (no sign of
    /// its answer, its answer stalled, deaf to the interrupt), the turn fails (falling back, while none of the answer
    /// came) and the process, stuck, ends; the next question starts one again.
    private func overdue(_ id: Int, attempt: Int) -> Duration? {
        var wait: Duration?
        let actions = state.withLock { state -> [Action] in
            guard let turn = state.turns.first, turn.id == id, turn.attempt == attempt, turn.sent,
                  let running = state.running else { return [] }
            let left = left(turn)
            guard left <= .zero else {
                wait = left
                return []
            }
            state.turns.removeFirst()
            state.running = nil  // its exit is of no session now
            state.idle?.cancel()
            state.idle = nil
            let failure: [Action] = turn.done ? [] : [.finish(turn.continuation, ClaudeSessionError.noResponse)]
            turn.done = true
            return failure + [.terminate(running.process)] + pump(&state)
        }
        perform(actions)
        return wait
    }

    /// `turn`, waiting behind one being answered, fails with `.busy` (the provider answers) unless it is sent within
    /// `firstAnswerTimeout` (`watch` replaces this watchdog).
    private func waitAtMost(_ turn: Turn) {
        guard turn.watchdog == nil, !turn.sent, !turn.done else { return }
        turn.attempt += 1
        let (id, attempt, clock, timeout) = (turn.id, turn.attempt, answerClock, firstAnswerTimeout)
        turn.watchdog = Task { [weak self] in
            do { try await clock.sleep(for: timeout) } catch { return }
            self?.waitedTooLong(id, attempt: attempt)
        }
    }

    private func waitedTooLong(_ id: Int, attempt: Int) {
        let actions = state.withLock { state -> [Action] in
            guard let index = state.turns.firstIndex(where: { $0.id == id }) else { return [] }
            let turn = state.turns[index]
            guard turn.attempt == attempt, !turn.sent, !turn.done else { return [] }
            state.turns.remove(at: index)
            turn.done = true
            return [.finish(turn.continuation, ClaudeSessionError.busy)]
        }
        perform(actions)
    }

    /// The process ends after `idleTimeout` unless a question comes first.
    private func scheduleIdle(_ state: inout State) {
        state.idle?.cancel()
        guard let generation = state.running?.generation else { return }
        let (clock, timeout) = (clock, idleTimeout)
        state.idle = Task { [weak self] in
            do { try await clock.sleep(for: timeout) } catch { return }
            self?.idleElapsed(generation: generation)
        }
    }

    private func idleElapsed(generation: Int) {
        let process = state.withLock { state -> (any ClaudeSessionProcess)? in
            guard let running = state.running, running.generation == generation, state.turns.isEmpty else { return nil }
            state.running = nil
            state.idle = nil
            return running.process
        }
        process?.terminate()
    }

    private func interruptAction(_ state: inout State) -> [Action] {
        guard let running = state.running else { return [] }
        return running.driver.interrupt().map { .send(running.process, $0) }
    }

    /// The turn `id`'s stream was given up: interrupted if it's being answered, else dropped.
    private func cancel(_ id: Int) {
        let actions = state.withLock { state -> [Action] in
            guard let index = state.turns.firstIndex(where: { $0.id == id }) else { return [] }
            let turn = state.turns[index]
            guard !turn.done else { return [] }
            guard turn.sent else {
                turn.done = true
                turn.watchdog?.cancel()
                state.turns.remove(at: index)
                return []
            }
            givenUp(turn)
            return interruptAction(&state)
        }
        perform(actions)
    }

    /// A line of the process's output: what it says (`SessionDriver.received`), and the lines written back. Each line
    /// while a turn answers puts its `answerIdleTimeout` off.
    private func received(_ line: Data, generation: Int) {
        let actions = state.withLock { state -> [Action] in
            guard let running = state.running, running.generation == generation else { return [] }
            let (events, replies) = running.driver.received(line)
            let actions = replies.map { .send(running.process, $0) }
                + events.flatMap { handle($0, generation: generation, &state) }
            if let turn = state.turns.first, turn.sent, turn.answering, !turn.done { turn.since = mark() }
            return actions
        }
        perform(actions)
    }

    /// What one event of the process does to the turn being answered and the process.
    private func handle(_ event: ClaudeSession.Event, generation: Int, _ state: inout State) -> [Action] {
        guard let running = state.running, running.generation == generation else { return [] }
        let turn = state.turns.first.flatMap { $0.sent ? $0 : nil }
        switch event {
        case .messageStarted, .text, .apiError, .result, .working:
            // Answering from now on: `answerIdleTimeout` (`interruptTimeout`, given up already); the questions waiting
            // behind it wait `firstAnswerTimeout` at most.
            if let turn, !turn.answering {
                turn.answering = true
                turn.since = mark()
                if turn.done { rewatch(turn) }
                for waiting in state.turns.dropFirst() { waitAtMost(waiting) }
            }
        default:
            break
        }
        switch event {
        case .started:
            // The session has its conversation from here on (the question is in its transcript): resumed from now on.
            state.running?.started = true
            store.markResumable()
            return []
        case let .sessionID(id):
            // A session the agent made in place of the one it had (gone): it knows none of the earlier answers.
            let previous = store.agentSessionID()
            store.setAgentSessionID(id)
            if let previous, previous != id { forgetAnswers() }
            return []
        case .permissionRequest, .working, .other:
            return []  // a permission request is answered by the driver
        case .compacting:
            // The conversation's context compacted first, before any of the answer: that may take minutes. The provider
            // answers now (`fallsBack`), the turn is stopped as Esc stops it, and the process stays. Once the answer is
            // coming in, it goes on.
            guard let turn, !turn.done, turn.text.isEmpty else { return [] }
            givenUp(turn)
            return [.finish(turn.continuation, ClaudeSessionError.compacting)] + interruptAction(&state)
        case .messageStarted:
            if let turn, !turn.text.isEmpty { turn.restarts = true }
            return []
        case let .text(text):
            guard let turn, !turn.done else { return [] }
            if turn.restarts { (turn.text, turn.restarts) = ("", false) }
            turn.text += text
            return [.yield(turn.continuation, turn.text)]
        case let .apiError(code, message):
            turn?.error = ClaudeSessionError.from(code: code, status: nil, message: message)
            return []
        case let .failed(error, endsProcess):
            if error == .signedOut { (state.availability, state.checkedAt) = (.signedOut, uptime()) }
            // Not to be asked as it is (not kept to the web): Automatic passes it by until it is looked at again.
            if error == .notWebOnly { (state.availability, state.checkedAt) = (.cannotStart, uptime()) }
            var actions: [Action] = []
            if let turn {
                state.turns.removeFirst()
                turn.watchdog?.cancel()
                if !turn.done { actions.append(.finish(turn.continuation, error)) }
                turn.done = true
            }
            if endsProcess {
                state.running = nil  // its exit is of no session now
                state.idle?.cancel()
                state.idle = nil
                actions.append(.terminate(running.process))
            }
            actions += pump(&state)
            if state.turns.isEmpty { scheduleIdle(&state) }
            return actions
        case let .result(isError, interrupted, text, status):
            // A failure before the session started is the start's: its exit says what to do (`exited`).
            guard running.started, let turn else { return [] }
            state.turns.removeFirst()
            turn.watchdog?.cancel()
            var actions: [Action] = []
            if !isError { state.availability = .ready }
            if !turn.done {
                if interrupted {
                    actions.append(.finish(turn.continuation, CancellationError()))
                } else if isError {
                    // The result's text may say more than the error line did (an AWS credential error).
                    let ended = ClaudeSessionError.from(code: nil, status: status, message: text)
                    let error = ended == .awsSignInExpired ? ended : turn.error ?? ended
                    if error == .signedOut { (state.availability, state.checkedAt) = (.signedOut, uptime()) }
                    actions.append(.finish(turn.continuation, error))
                } else {
                    if turn.text.isEmpty, !text.isEmpty { actions.append(.yield(turn.continuation, text)) }
                    actions.append(.finish(turn.continuation, nil))
                }
            }
            actions += pump(&state)
            if state.turns.isEmpty { scheduleIdle(&state) }
            return actions
        }
    }

    /// The session holds none of the answers it was given or told (`remember`) any more.
    private func forgetAnswers() {
        kept.withLock { kept in
            guard let id = try? store.sessionID() else { return }
            var current = load(&kept, id: id)
            current.memory.answered = []
            store.save(current.memory)
            kept = current
        }
    }

    /// The process ended (not by `stop` or the idle time: those let go of it first).
    private func exited(generation: Int, status: Int32, message: String) {
        let actions = state.withLock { state -> [Action] in
            guard let running = state.running, running.generation == generation else { return [] }
            state.running = nil
            state.idle?.cancel()
            state.idle = nil
            guard let turn = state.turns.first, turn.sent else { return pump(&state) }
            turn.watchdog?.cancel()
            // It couldn't start the session (no "init"): once more the other way, `--session-id` ↔ `--resume` (the id in
            // use already, or with no conversation after all).
            if !running.started, !turn.retried, !turn.done {
                turn.retried = true
                turn.sent = false
                if backend.retryTogglesResume { store.setResumable(!running.resume) }
                return pump(&state)
            }
            state.turns.removeFirst()
            let error: ClaudeSessionError
            if ClaudeSessionError.isAWSCredentialError(message) {
                // Credentials Claude Code couldn't get (an `awsCredentialExport` that failed) end it before it answers.
                error = .awsSignInExpired
            } else if !running.started, turn.retried {
                // Ended twice before its session started: it can't start (an older version that doesn't know a flag, a
                // broken install). The provider answers, saying why; Automatic passes it by until it is looked at again.
                (state.availability, state.checkedAt) = (.cannotStart, uptime())
                error = .failedToStart(status, message)
            } else {
                error = .exited(status, message)
            }
            let failure: [Action] = turn.done ? [] : [.finish(turn.continuation, error)]
            return failure + pump(&state)
        }
        perform(actions)
    }

    private func perform(_ actions: [Action]) {
        for action in actions {
            switch action {
            case let .send(process, line):
                // It can't be written to (it ended, or closed its input): ended, its exit says the rest (`exited`, with
                // its status and what it said on stderr).
                do { try process.send(line) } catch { process.terminate() }
            case let .yield(continuation, text):
                continuation.yield(text)
            case let .finish(continuation, error?):
                continuation.finish(throwing: error)
            case let .finish(continuation, nil):
                continuation.finish()
            case let .terminate(process):
                process.terminate()
            }
        }
    }
}

// MARK: - The real process

/// Starts `claude` with the core's `ProcessLauncher` (`Platform.current.processes`): its standard input and output
/// piped, the output read line by line on a thread of its own; its end told by its termination handler
/// (`LaunchSpec.onExit`), never `waitUntilExit` on a dispatch thread, which sometimes never returns (a program that
/// exited would count as running: a sign-in check found signed out, a question waiting for a process long gone).
/// `executable`: where `claude` is (nil: not installed); `environment`: what it runs with (on the Mac the login shell's);
/// `processes`: nil, the platform's as it starts.
public struct ProcessClaudeSessionLauncher: ClaudeSessionLauncher {
    public var processes: (any ProcessLauncher)?
    public var executable: @Sendable () -> URL?
    public var environment: @Sendable () -> [String: String]

    public init(processes: (any ProcessLauncher)? = nil, executable: @escaping @Sendable () -> URL?,
                environment: @escaping @Sendable () -> [String: String]) {
        self.processes = processes
        self.executable = executable
        self.environment = environment
    }

    public func installed() -> Bool { (processes ?? Platform.current.processes).canLaunch && executable() != nil }

    public func startEnvironment() -> [String: String] { environment() }

    public func start(_ arguments: [String], in directory: URL, output: @escaping @Sendable (Data) -> Void,
                      exited: @escaping @Sendable (Int32, String) -> Void) throws -> any ClaudeSessionProcess {
        let processes = processes ?? Platform.current.processes
        guard processes.canLaunch, let executable = executable() else { throw ClaudeSessionError.notInstalled }
        let input = Pipe(), out = Pipe(), errors = Pipe()
        let ended = DispatchSemaphore(value: 0)
        let launched = try processes.launch(LaunchSpec(executable: executable, arguments: arguments, environment: environment(),
                                                       directory: directory, standardInput: .pipe(input),
                                                       standardOutput: .pipe(out), standardError: .pipe(errors),
                                                       onExit: { _ in ended.signal() }))
        let errorTail = Locked(initialState: Data())
        let errorsRead = DispatchSemaphore(value: 0)
        // Threads of their own: each blocks reading for as long as the process runs (a session's, many minutes).
        Thread.detachNewThread {
            let handle = errors.fileHandleForReading
            while case let chunk = handle.availableData, !chunk.isEmpty {
                errorTail.withLock { $0 = ($0 + chunk).suffix(600) }
            }
            errorsRead.signal()
        }
        Thread.detachNewThread {
            let handle = out.fileHandleForReading
            var buffer = Data()
            while case let chunk = handle.availableData, !chunk.isEmpty {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if !line.isEmpty { output(Data(line)) }
                }
            }
            ended.wait()
            _ = errorsRead.wait(timeout: .now() + 2)
            let message = String(decoding: errorTail.withLock { $0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            exited(launched.terminationStatus, String(message.split(whereSeparator: \.isNewline).last ?? ""))
        }
        return PipedClaudeProcess(process: launched, input: input.fileHandleForWriting)
    }
}

private final class PipedClaudeProcess: ClaudeSessionProcess, @unchecked Sendable {
    let process: any LaunchedProcess
    let input: FileHandle
    private let lock = NSLock()
    private var closed = false

    init(process: any LaunchedProcess, input: FileHandle) {
        self.process = process
        self.input = input
    }

    func send(_ line: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { throw CocoaError(.fileWriteUnknown) }
        try input.write(contentsOf: line)
    }

    func closeInput() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        try? input.close()
    }

    func terminate() {
        closeInput()
        process.terminate()
    }

    func kill() {
        closeInput()
        process.kill()
    }

    var isRunning: Bool { process.treeIsRunning }
}

/// One run of a session's sign-in check (`ClaudeSessionManager.signInCheck`): what says first counts (a line of its
/// output, its exit, the timeout), and the command is ended then.
private final class SignInCheck: @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<ClaudeSession.Availability, Never>?
        var process: (any ClaudeSessionProcess)?
        var output = Data()
        var timer: Task<Void, Never>?
    }

    private let backend: any SessionBackend
    private let state: Locked<State>

    init(backend: any SessionBackend, continuation: CheckedContinuation<ClaudeSession.Availability, Never>) {
        self.backend = backend
        state = Locked(initialState: State(continuation: continuation))
    }

    /// The command started: ended at once if it already said.
    func started(_ process: any ClaudeSessionProcess) {
        let said = state.withLock { state -> Bool in
            if state.continuation != nil { state.process = process }
            return state.continuation == nil
        }
        if said { process.terminate() }
    }

    /// What ends it after `ClaudeSessionManager.checkTimeout` (cancelled at once if it already said).
    func timeout(_ timer: Task<Void, Never>) {
        let said = state.withLock { state -> Bool in
            state.timer = timer
            return state.continuation == nil
        }
        if said { timer.cancel() }
    }

    func line(_ line: Data) {
        if let signedIn = backend.signedIn(line: line) { return finish(signedIn ? .ready : .signedOut) }
        state.withLock { state in
            state.output.append(line)
            state.output.append(0x0A)
        }
    }

    func exited(_ status: Int32) {
        let output = state.withLock { $0.output }
        finish(backend.signedIn(status: status, output: output) == true ? .ready : .signedOut)
    }

    /// Ended now (the input method quits): the command asked to end, returned (nil: none running).
    func end() -> (any ClaudeSessionProcess)? {
        let process = state.withLock { $0.process }
        finish(.unknown)
        return process
    }

    func finish(_ availability: ClaudeSession.Availability) {
        let said = state.withLock { state -> State in
            let said = state
            (state.continuation, state.process, state.timer) = (nil, nil, nil)
            return said
        }
        guard let continuation = said.continuation else { return }
        said.timer?.cancel()
        said.process?.terminate()
        continuation.resume(returning: availability)
    }
}

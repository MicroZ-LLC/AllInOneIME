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

private func terminateAfterGrace(_ process: any ClaudeSessionProcess) {
    process.terminate()
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + ClaudeSessionManager.handOffGrace) {
        if process.isRunning { process.kill() }
    }
}

/// Starts the session's process: the real one (`ProcessClaudeSessionLauncher`), or a test's.
public protocol ClaudeSessionLauncher: Sendable {
    /// Starts `claude` with `arguments` in `directory`. Each line it writes to its standard output goes to `output`, in
    /// order, on one thread; then `exited`, once, with its status and the end of what it wrote to standard error.
    /// Throws `ClaudeSessionError.notInstalled` when there is no `claude`, `.cannotLaunch` when it is there but couldn't
    /// be launched.
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
/// request (`request`: an `@question` or a writing task) carries the conversation it is of and what its web tools may
/// reach, as it was made: each `@question` conversation in the panel goes into a new conversation of the agent, its
/// follow-ups into that one, a writing task into one of its own; `prewarm` gets the new one ready (Codex and an ACP agent
/// open it in the process they have, Claude Code's process is started again on it), so that it is warm when the question
/// comes. A process that ended (a crash, killed) is started again on the same conversation (`--resume`) by its next
/// question. A question asked while another is answered waits for it, and is sent into its own conversation with its
/// own web tools whatever was asked meanwhile; stopping one (`ask`'s stream given up: Esc) interrupts its turn and the
/// process stays.
/// One process writes a conversation at a time. Handing the conversation to Terminal (`handOffOnceEnded`) ends our
/// process first, and waits for it; the conversation is Terminal's from then on, and questions after it go into a new
/// one. Our process holds its conversation's lock (`ConversationLock`) while it runs, which Terminal waits for and then
/// holds while its CLI runs (`terminalCommand`).
/// A question with no sign of an answer within `firstAnswerTimeout` (Claude Code stuck starting, an `awsAuthRefresh`
/// sign-in waiting in a browser) fails with `.noResponse`, which falls back to the provider, and the process ends; one
/// whose agent begins compacting the conversation before answering fails with `.compacting` at once (not waited for); so
/// does one answering that says nothing more (not a line) for `answerIdleTimeout`, and one stopped while it answered
/// that doesn't end within `interruptTimeout` (an agent deaf to the interrupt): the process is stuck, the next question
/// starts it again. A question waiting behind one being answered waits `firstAnswerTimeout` at most, then fails with
/// `.busy` (the provider answers); so does one waiting for its process to start while ours before it is still ending
/// (with `.noResponse`). A process that ends before its session starts, twice, fails the question with
/// `.failedToStart` (the provider answers) and the agent is `.cannotStart` until its sign-in is looked at again; so is
/// one whose program won't launch at all (`.cannotLaunch`: gone since it was found, not executable).
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
    /// The hand-off's longest wait for our process to end once asked to (SIGTERM), before it is killed (⌘⏎:
    /// `handOffOnceEnded` waits for it); a process stopped is killed after it too.
    public static let handOffGrace: TimeInterval = 0.5
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
    private let userSettings: @Sendable () -> URL?
    private let uptime: @Sendable () -> TimeInterval
    private let state = Locked(initialState: State())
    private let kept = Locked<Kept?>(initialState: nil)
    /// The locks of the conversations our processes are on.
    private let locks = ConversationLocks()

    /// `userSettings`: the user's Claude Code settings.json (`ClaudeSession.userSettingsFile`), whose provider settings the session gets; nil: none.
    /// `answerClock`: what `firstAnswerTimeout`, `answerIdleTimeout`, `interruptTimeout` and `checkTimeout` are timed
    /// with; `uptime`: seconds, what `recheckInterval` is. `store`: nil, the backend's own folder.
    public init(backend: any SessionBackend = ClaudeCodeBackend(), launcher: any ClaudeSessionLauncher, store: ClaudeSessionStore? = nil,
                idleTimeout: Duration = ClaudeSessionManager.idleTimeout, clock: any Clock<Duration> = ContinuousClock(),
                firstAnswerTimeout: Duration = ClaudeSessionManager.firstAnswerTimeout,
                answerIdleTimeout: Duration = ClaudeSessionManager.answerIdleTimeout,
                interruptTimeout: Duration = ClaudeSessionManager.interruptTimeout,
                answerClock: any Clock<Duration> = ContinuousClock(),
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
        self.userSettings = userSettings
        self.uptime = uptime
    }

    /// What is kept of the session `session`: `memory` as saved, and the values hidden so far (in memory only).
    private struct Kept {
        var memory: ClaudeSessionStore.Memory
        var known: [Redaction.Hidden] = []
    }

    /// A question being answered, or waiting for the one before it; from the moment its request is made (`Request`),
    /// before its message comes.
    fileprivate final class Turn: @unchecked Sendable {
        let id: Int
        /// The panel conversation it is of (`Request.conversation`); nil: the agent conversation now, whichever.
        let owner: String?
        /// What its web tools may reach (`Request.web`); nil: as the agent conversation now has them (`State.web`).
        let web: SessionWeb?
        /// It goes on in the agent conversation now (`Request.continues`); else into a new one.
        let continues: Bool
        /// What is written: none until its request has its message (`Request.answer`); nothing behind it goes first.
        var message: String?
        var continuation: AsyncThrowingStream<SessionReply, Error>.Continuation?
        /// How it ended before it had its message (the session stopped, it waited too long): its stream ends so.
        var ended: Error?
        /// In its agent conversation (`place`): a new one made for it, or the one it goes on in.
        var placed = false
        /// The agent conversation (`store`'s id) it went into.
        var conversation: String?
        /// What its hiding numbered (`redacting(_:for:_:)`), for the new agent conversation it goes into.
        var hidden: (numbers: [Redaction.Kind: Int], values: [Redaction.Hidden])?
        /// The answer so far (of the model's latest message: after a web search the answer starts again).
        var text = ""
        /// It went into an agent conversation with no question before it (`SessionReply.newConversation`).
        var newConversation = false
        /// The tokens it used so far, as the agent says.
        var tokens: Int?
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

        init(id: Int, owner: String?, web: SessionWeb?, continues: Bool) {
            self.id = id
            self.owner = owner
            self.web = web
            self.continues = continues
        }

        /// What the stream gives now.
        var reply: SessionReply { SessionReply(text: text, newConversation: newConversation, tokens: tokens) }
    }

    private struct Running: @unchecked Sendable {
        var process: any ClaudeSessionProcess
        /// What talks to it (`SessionDriver`), used under the lock only.
        var driver: any SessionDriver
        var generation: Int
        var resume: Bool
        /// The agent conversation it is on (`store`'s id when it started, or moved: `follow`).
        var conversation: String
        /// That conversation's lock, held until it ends.
        var lock: HeldLock
        /// What its web tools may reach (`SessionBackend.effective`): for the whole process.
        var web: SessionWeb
        /// The session started (its "init" came): a failure before that is the start's.
        var started = false
    }

    private struct State {
        var running: Running?
        /// Processes being stopped; no replacement starts until their exit callbacks run (a question waits for that
        /// `firstAnswerTimeout` at most: `waitForStart`).
        var retiring: [Int: Running] = [:]
        /// A `prewarm` came while one of `retiring` still ran: its process starts once they have all ended (`exited`).
        var prewarmWaiting = false
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
        /// (`store`'s id), as the latest request sent there was of (`place`); nil: none said.
        var owner: String?
        /// A question went into the agent conversation now; nil: not looked at yet (`asked`).
        var asked: Bool?
        /// What the web tools may reach in it, as the latest request sent there may: what a request of no conversation
        /// (`Request.web` nil) gets.
        var web = SessionWeb.open
        /// The processes started before the agent was found signed in again after it wasn't (`generation` up to this)
        /// are started again by the next question (`follow`): theirs may be the sign-in from before.
        var staleThrough = 0
    }

    /// What is done once the lock is let go (finishing a stream runs its consumer's code).
    private enum Action {
        case send(any ClaudeSessionProcess, Data)
        case yield(AsyncThrowingStream<SessionReply, Error>.Continuation, SessionReply)
        case finish(AsyncThrowingStream<SessionReply, Error>.Continuation, Error?)
        /// Ended, and its conversation's lock let go once it has (`start`'s `exited`; at once if it has).
        case terminate(any ClaudeSessionProcess, HeldLock?)
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
    /// asked (Settings → AI, as it shows the choices), never before. Ready is kept for the launch (an answer that fails says
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

    /// Signed in now after it wasn't (signed out, not installed, its session couldn't start), the process running is
    /// started again by the next question (`State.staleThrough`).
    private func lookAtSignIn() async -> ClaudeSession.Availability {
        let found = await signInCheck()
        let now = uptime()
        return state.withLock { state in
            if found == .ready, [.signedOut, .notInstalled, .cannotStart].contains(state.availability) {
                state.staleThrough = state.generation
            }
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
            } catch ClaudeSessionError.cannotLaunch {
                check.finish(.cannotStart)
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

    /// Whether `@question` goes to this session with `config`: its CLI is the AI chosen (`Config.questionSessionAgent`).
    public func answersQuestions(_ config: Config) -> Bool { config.questionSessionAgent == backend.agent }

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
            // With the web tools as they are: a question with text the user didn't type starts it again kept to the web
            // it may reach (`Request.web`).
            var actions = follow(&state, web: .open)
            // Never two processes: one still ending (the conversation it was on left just now) is waited for.
            guard state.running != nil || state.retiring.isEmpty else {
                state.prewarmWaiting = true
                return actions
            }
            return actions + startPrewarmed(&state)
        }
        perform(actions)
    }

    /// `prewarm`'s process started, unless one runs (its idle time counted from now).
    private func startPrewarmed(_ state: inout State) -> [Action] {
        state.prewarmWaiting = false
        var actions: [Action] = []
        if state.running == nil {
            guard let (_, opening) = try? start(&state, web: .open) else { return [] }
            actions = opening
        }
        scheduleIdle(&state)
        return actions
    }

    /// A request to the session: an `@question` of a conversation in the panel, or a writing task (its own conversation,
    /// `QuestionConversation.oneOff`), with the agent conversation it goes into and what its web tools may reach, both
    /// fixed as it is made (`request`) and kept until it is sent: a request made meanwhile (another field's) changes
    /// neither. It takes its place in the queue as it is made, so that what goes by its agent conversation (`missing`,
    /// `redacting`) is of the one it goes into; its message comes once that is done (`answer`), and nothing behind it is
    /// sent before. Let go of without its message, its place goes.
    public final class Request: @unchecked Sendable {
        /// The panel conversation it is of (`QuestionConversation.id`); nil: none said, the agent conversation now.
        public let conversation: String?
        /// What its web tools may reach (`QuestionConversation.web`); nil: as the agent conversation now has them. Its
        /// process is started again for it when the one running has others.
        public let web: SessionWeb?
        /// It goes on in the agent conversation now: that one is its conversation's, and no request of another is before
        /// it in the queue. Else it goes into a new one, which saw none of its conversation's rounds.
        public let continues: Bool
        fileprivate let turn: Turn
        private weak var manager: ClaudeSessionManager?

        fileprivate init(_ turn: Turn, manager: ClaudeSessionManager) {
            (conversation, web, continues) = (turn.owner, turn.web, turn.continues)
            self.turn = turn
            self.manager = manager
        }

        /// Asks it, once, with `message` (one user message: the text as the provider would get it, already redacted).
        /// The stream gives the answer so far each time more of it comes, with what the panel tells of it
        /// (`SessionReply`), and ends with the turn; given up (cancelled), it interrupts the turn.
        public func answer(_ message: String) -> AsyncThrowingStream<SessionReply, Error> {
            guard let manager else { return AsyncThrowingStream { $0.finish(throwing: CancellationError()) } }
            return manager.answer(turn, message)
        }

        /// `answer`, its text alone.
        public func ask(_ message: String) -> AsyncThrowingStream<String, Error> { ClaudeSessionManager.texts(answer(message)) }

        deinit { manager?.release(turn) }
    }

    /// A request of `conversation` (`Request`), in the queue from now on: it goes on in the agent conversation now when
    /// that is its conversation's and nothing of another conversation is before it; else into a new agent conversation
    /// (the one now when no question went into it yet: the one `prewarm` made ready). Nil: the agent conversation now,
    /// whichever, with the web tools it has.
    public func request(_ conversation: QuestionConversation?) -> Request {
        state.withLock { state in
            state.serial += 1
            let owner = conversation?.id
            // In the queue before it (not yet in an agent conversation): another conversation's, or a new one's.
            let continues = owner.map { owner in
                state.owner == owner
                    && state.turns.allSatisfy { $0.done || $0.placed || ($0.continues && ($0.owner ?? owner) == owner) }
            } ?? true
            let turn = Turn(id: state.serial, owner: owner, web: conversation?.web, continues: continues)
            state.turns.append(turn)
            // Behind one being answered: it waits so long at most.
            if state.turns.first !== turn, state.turns.first?.answering == true { waitAtMost(turn) }
            return Request(turn, manager: self)
        }
    }

    /// Asks `question` as a request of `conversation` (`request`, then `Request.ask`).
    public func ask(_ question: String, in conversation: QuestionConversation?) -> AsyncThrowingStream<String, Error> {
        request(conversation).ask(question)
    }

    /// The answer's text from `replies`, each time it changes.
    static func texts(_ replies: AsyncThrowingStream<SessionReply, Error>) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var last: String?
                    for try await reply in replies where reply.text != last {
                        last = reply.text
                        continuation.yield(reply.text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `turn`'s request asked with `message` (`Request.answer`): written once the turns before it are answered. One that
    /// ended before (the session stopped, it waited too long) ends so at once.
    fileprivate func answer(_ turn: Turn, _ message: String) -> AsyncThrowingStream<SessionReply, Error> {
        AsyncThrowingStream { continuation in
            let id = turn.id
            continuation.onTermination = { [weak self] termination in
                if case .cancelled = termination { self?.cancel(id) }
            }
            let actions = state.withLock { state -> [Action] in
                guard turn.message == nil else { return [.finish(continuation, CancellationError())] }  // asked once only
                (turn.message, turn.continuation) = (message, continuation)
                if turn.done { return [.finish(continuation, turn.ended ?? CancellationError())] }
                let actions = pump(&state)
                // Behind one being answered: it waits so long at most.
                if !turn.sent, state.turns.first?.answering == true { waitAtMost(turn) }
                return actions
            }
            perform(actions)
        }
    }

    /// `turn`'s request was let go of: without its message, its place goes, and what waited behind it goes on.
    fileprivate func release(_ turn: Turn) {
        let actions = state.withLock { state -> [Action] in
            guard turn.message == nil, !turn.done else { return [] }
            turn.done = true
            turn.watchdog?.cancel()
            state.turns.removeAll { $0 === turn }
            return pump(&state)
        }
        perform(actions)
    }

    /// Stops the turn being answered (its stream ends with `CancellationError`); the process stays.
    public func interrupt() {
        let actions = state.withLock { state -> [Action] in
            guard let turn = state.turns.first, turn.sent, !turn.done else { return [] }
            givenUp(turn)
            return finish(turn, CancellationError()) + interruptAction(&state)
        }
        perform(actions)
    }

    /// Hands the conversation now to Terminal (⌘⏎), never two processes writing it: our process is asked to end (a
    /// question being answered stops; killed after `handOffGrace`) and holds the conversation's lock until it has; from
    /// then on the conversation is Terminal's, and questions here go into a new one (a prewarm meanwhile too: one step
    /// under the lock), never that one again. Returns at once what Terminal is to run (`SessionBackend.terminalArguments`,
    /// `program` being where the agent is; `followUp`: a follow-up goes after them as the last argument) in the session's
    /// folder, and the conversation's lock file, for Terminal to hold while it runs (`terminalCommand`), which waits for
    /// ours. `handOffOnceEnded` returns once our process has ended.
    public func handOff(program: String, followUp: Bool = false) throws -> (arguments: [String], directory: URL, lock: URL) {
        let (handed, running) = try handOver(program: program, followUp: followUp)
        if let running { perform([.terminate(running.process, running.lock)]) }
        return handed
    }

    /// `handOff`, returning once our process has ended: asked to end, given `handOffGrace`, then killed with what it
    /// started. Whether it has is the process's own state (`ClaudeSessionProcess.isRunning`), not its exit told, which
    /// may come later; its conversation's lock is let go then. Waited for on the task (`Task.sleep`), never holding a
    /// thread: the hand-off runs off the key's thread, on Swift's shared pool. Throws when it is still running a moment
    /// after it was killed.
    public func handOffOnceEnded(program: String, followUp: Bool = false) async throws
        -> (arguments: [String], directory: URL, lock: URL) {
        let (handed, running) = try handOver(program: program, followUp: followUp)
        if let running {
            guard await Self.ended(running.process, grace: Self.handOffGrace) else {
                throw ClaudeSessionError.failed("The previous session process has not exited")
            }
            running.lock.release()
        }
        return handed
    }

    /// `process` asked to end (SIGTERM), given `grace` seconds, then killed with what it started (SIGKILL); whether it has
    /// ended (`isRunning`) by half a second after.
    private static func ended(_ process: any ClaudeSessionProcess, grace: TimeInterval) async -> Bool {
        process.terminate()
        if await ended(process, within: grace) { return true }
        process.kill()
        return await ended(process, within: 0.5)
    }

    private static func ended(_ process: any ClaudeSessionProcess, within seconds: TimeInterval) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while process.isRunning {
            guard ContinuousClock.now < deadline else { return false }
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return !process.isRunning }
        }
        return true
    }

    /// The hand-off under the lock: what Terminal is to run, of the conversation now (its id); our process let go of
    /// (`retiring` until its exit is told), with the questions it was answering; a new conversation from now on.
    private func handOver(program: String, followUp: Bool)
        throws -> (handed: (arguments: [String], directory: URL, lock: URL), running: Running?) {
        let (handed, running, actions) = try state.withLock { state -> ((arguments: [String], id: String), Running?, [Action]) in
            let id = try store.sessionID()
            let arguments = backend.terminalArguments(program: program, sessionID: id, agentSessionID: store.agentSessionID(),
                                                      resume: store.resumable, followUp: followUp)
            state.idle?.cancel()
            state.idle = nil
            let turns = state.turns
            state.turns = []
            for turn in turns { turn.watchdog?.cancel() }
            let running = state.running
            if let running { state.retiring[running.generation] = running }
            state.running = nil  // what it still says, its exit too, is of no session now
            rollOver(&state)
            return ((arguments, id), running, turns.filter { !$0.done }.flatMap { finish($0, CancellationError()) })
        }
        perform(actions)
        return ((handed.arguments, store.directory, store.lockFile(handed.id)), running)
    }

    /// What Terminal runs for a hand-off: `arguments` (the CLI's) under `lockf`, which holds `lock` (the conversation's,
    /// `handOff`) while the CLI runs, waiting up to 10 seconds for it to be let go; as they are where there is no
    /// `/usr/bin/lockf`. A shell's `exec` keeps the window's process the CLI's (or lockf's, which waits for it).
    public static func terminalCommand(_ arguments: [String], lock: URL) -> [String] {
        let script = #"lock="$1"; shift; if [ -x /usr/bin/lockf ]; then exec /usr/bin/lockf -k -t 10 "$lock" "$@"; fi; exec "$@""#
        return ["/bin/sh", "-c", script, "sh", lock.path] + arguments
    }

    /// Ends the process, and the questions it was answering (the app quits, the settings changed).
    public func stop() {
        let actions = state.withLock { state -> [Action] in
            state.idle?.cancel()
            state.idle = nil
            state.prewarmWaiting = false
            let turns = state.turns
            state.turns = []
            for turn in turns { turn.watchdog?.cancel() }
            let running = state.running
            if let running { state.retiring[running.generation] = running }
            state.running = nil  // what it still says, its exit too, is of no session now
            return turns.filter { !$0.done }.flatMap { finish($0, CancellationError()) }
                + (running.map { [.terminate($0.process, $0.lock)] } ?? [])
        }
        perform(actions)
    }

    /// Ends the processes of `managers` and what each started, a sign-in check's too: the input method quits (an
    /// update, logging out). Each is asked to end, then what is left after `grace` seconds is killed; returns once
    /// they're gone, or then.
    public static func stop(_ managers: [ClaudeSessionManager], grace: TimeInterval) {
        end(managers.flatMap { $0.end() }, grace: grace)
    }

    /// `processes`, asked to end, given `grace` seconds, then killed with what they started; returns once they're gone,
    /// or a moment after they're killed.
    private static func end(_ processes: [any ClaudeSessionProcess], grace: TimeInterval) {
        for process in processes { process.terminate() }
        var deadline = Date().addingTimeInterval(grace)
        while Date() < deadline, processes.contains(where: \.isRunning) { Thread.sleep(forTimeInterval: 0.02) }
        for process in processes where process.isRunning { process.kill() }
        deadline = Date().addingTimeInterval(0.2)
        while Date() < deadline, processes.contains(where: \.isRunning) { Thread.sleep(forTimeInterval: 0.02) }
    }

    /// `stop`, and the sign-in check's command ended too: the processes asked to end.
    private func end() -> [any ClaudeSessionProcess] {
        let (processes, check) = state.withLock { state in
            ([state.running?.process].compactMap { $0 } + state.retiring.values.map(\.process), state.signInCheck)
        }
        stop()
        return processes + [check?.end()].compactMap { $0 }
    }

    /// A new conversation from now on ("start over" in the settings): the process ends, a new id is made.
    public func startOver() throws {
        stop()
        try state.withLock { state in
            try kept.withLock { kept in
                kept = nil
                try store.startOver()
            }
            (state.owner, state.asked, state.web) = (nil, false, .open)
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
            return rounds.filter { !answered.contains(Self.turnIdentity($0)) }
        }
    }

    /// `redacting` for `request`: what it numbered is kept for the agent conversation it goes into too (a new one gets
    /// it as the request goes in), so that a later question there never gives one of its placeholders another value.
    public func redacting<T>(_ settings: RedactionSettings, for request: Request,
                             _ body: (inout Redaction?) -> T) -> (redaction: Redaction?, result: T) {
        let done: (redaction: Redaction?, result: T)
        if request.continues {
            done = redacting(settings, body)
        } else {
            // A new panel conversation must not inherit values hidden in another one.
            var fresh = Redaction(settings)
            let result = body(&fresh)
            done = (fresh, result)
        }
        if let redaction = done.redaction {
            state.withLock { _ in request.turn.hidden = (redaction.numbers, redaction.hidden) }
        }
        return done
    }

    /// `missing` for `request`: every round when it goes into a new agent conversation, which saw none of them.
    public func missing(_ rounds: [QuestionChat.Round], for request: Request) -> [QuestionChat.Round] {
        request.continues ? missing(rounds) : rounds
    }

    /// `remember` for `request`'s answer: kept while the agent conversation it went into is the one now (one left since
    /// is never gone on in).
    public func remember(rounds: [QuestionChat.Round], for request: Request) {
        guard let id = state.withLock({ _ in request.turn.conversation }), id == (try? store.sessionID()) else { return }
        remember(rounds: rounds)
    }

    /// What a request's hiding numbered (`redacting(_:for:_:)`; nil: nothing), kept for the agent conversation now, which
    /// it goes into as the first of its panel conversation (`place`): in place of anything kept for it before. A new one
    /// has nothing; the one now, never asked, may have what a request that failed before it was asked hid there (another
    /// panel conversation's, numbered from 1 as this one's is), which must never be put back in this one's answers.
    private func keepOnly(_ hidden: (numbers: [Redaction.Kind: Int], values: [Redaction.Hidden])?) {
        kept.withLock { kept in
            guard let id = try? store.sessionID() else { return }
            var current = load(&kept, id: id)
            let numbers = Dictionary(uniqueKeysWithValues: (hidden?.numbers ?? [:]).map { ($0.rawValue, $1) })
            let values = hidden?.values ?? []
            guard numbers != current.memory.numbers || values != current.known else { return }
            (current.memory.numbers, current.known) = (numbers, values)
            store.save(current.memory)
            kept = current
        }
    }

    /// A turn is identified by both its question and answer, so identical answers to different questions stay distinct.
    private static func turnIdentity(_ round: QuestionChat.Round) -> String {
        ClaudeSession.fingerprint(round.question + "\u{1F}" + round.answer)
    }

    /// `rounds` are in the session now: it gave them, or was told them as context.
    public func remember(rounds: [QuestionChat.Round]) {
        let prints = rounds.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(Self.turnIdentity)
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
        let id = try? store.startOver()
        (state.owner, state.asked, state.web) = (nil, false, .open)
        // The locks of conversations no process holds any more go.
        if let id { ConversationLock.prune(store.locks, keeping: store.lockFile(id)) }
    }

    /// The running process on the agent conversation now, with the web tools `wanted` (the request's about to be sent,
    /// `prewarm`'s): as it is when it's on it with them; moved to it when the agent can open another conversation in the
    /// same process (`SessionDriver.newConversation`) and the web tools are the same; else ended, for `start` to start
    /// one on it. One started before the agent was found signed in again is ended too (`State.staleThrough`).
    private func follow(_ state: inout State, web wanted: SessionWeb) -> [Action] {
        guard let running = state.running, let id = try? store.sessionID() else { return [] }
        let web = backend.effective(wanted) ?? .only([])
        let stale = running.generation <= state.staleThrough
        guard running.conversation != id || running.web != web || stale else { return [] }
        if !stale, running.web == web, running.started, let lines = running.driver.newConversation() {
            state.running?.conversation = id
            running.lock.hold(locks.hold(store.lockFile(id)))
            return lines.map { .send(running.process, $0) }
        }
        state.retiring[running.generation] = running
        state.running = nil  // its exit is of no session now
        state.idle?.cancel()
        state.idle = nil
        return [.terminate(running.process, running.lock)]
    }

    /// Starts the process (with `--resume` once the session has a conversation), and what it is sent first (an ACP
    /// handshake), with the web tools `wanted` (as for `follow`); one whose agent can't be kept to them isn't started
    /// (`notWebOnly`: the provider answers). Its conversation's lock is held until it ends (`ConversationLocks`).
    private func start(_ state: inout State, web wanted: SessionWeb) throws -> (Running, opening: [Action]) {
        if let running = state.running { return (running, []) }
        guard let web = backend.effective(wanted) else { throw ClaudeSessionError.notWebOnly }
        let held = HeldLock()
        do {
            try store.prepare()
            let id = try store.sessionID()
            held.hold(locks.hold(store.lockFile(id)))
            let resume = store.resumable
            state.generation += 1
            let generation = state.generation
            let arguments = backend.arguments(sessionID: id, resume: resume, settings: providerSettings(), web: web)
            let driver = backend.driver(sessionID: id, agentSessionID: store.agentSessionID(), resume: resume,
                                        directory: store.directory, web: web)
            let process = try launcher.start(arguments, in: store.directory,
                                             output: { [weak self] in self?.received($0, generation: generation) },
                                             exited: { [weak self] in
                                                 held.release()
                                                 self?.exited(generation: generation, status: $0, message: $1)
                                             })
            let running = Running(process: process, driver: driver, generation: generation, resume: resume, conversation: id,
                                  lock: held, web: web)
            state.running = running
            return (running, driver.opening().map { .send(process, $0) })
        } catch ClaudeSessionError.notInstalled {
            held.release()
            (state.availability, state.checkedAt) = (.notInstalled, uptime())
            throw ClaudeSessionError.notInstalled
        } catch let ClaudeSessionError.cannotLaunch(reason) {
            // Found, but its program wouldn't launch: the provider answers, saying why; Settings → AI says it can't start
            // until it is looked at again (`checkAvailability`), and the next question tries again.
            held.release()
            (state.availability, state.checkedAt) = (.cannotStart, uptime())
            throw ClaudeSessionError.cannotLaunch(reason)
        } catch {
            held.release()
            throw error
        }
    }

    /// The first turn written to the process (started if it isn't running), unless one is being answered or the first
    /// still waits for its message (`Request`): into its own agent conversation, with its own web tools (`place`).
    private func pump(_ state: inout State) -> [Action] {
        while let first = state.turns.first, first.done, !first.sent { state.turns.removeFirst() }
        guard state.retiring.isEmpty else {
            waitForStart(&state)
            return []
        }
        guard let turn = state.turns.first, !turn.sent, let message = turn.message else { return [] }
        let web = place(turn, &state)
        // On another agent conversation, or with other web tools: moved to this one, or started again on it.
        let moved = follow(&state, web: web)
        if !state.retiring.isEmpty {
            waitForStart(&state)
            return moved
        }
        let running: Running
        let opening: [Action]
        do {
            (running, opening) = try start(&state, web: web)
        } catch {
            let failure = error as? ClaudeSessionError ?? .failed(error.localizedDescription)
            // Its web tools can't be kept to what it may reach: it alone isn't asked; the next has its own.
            if failure == .notWebOnly {
                state.turns.removeFirst()
                turn.watchdog?.cancel()
                return moved + finish(turn, failure) + pump(&state)
            }
            let turns = state.turns
            state.turns = []
            for turn in turns { turn.watchdog?.cancel() }
            return moved + turns.filter { !$0.done }.flatMap { finish($0, failure) }
        }
        state.idle?.cancel()
        state.idle = nil
        turn.sent = true
        state.prewarmWaiting = false  // the process a prewarm waited for is this one
        // Not to be asked as it is now (Antigravity's files that keep it to its tools changed): the question fails so,
        // its process ends.
        if let refusal = running.driver.refusal() {
            return moved + opening + handle(.failed(refusal, endsProcess: true), generation: running.generation, &state)
        }
        turn.newConversation = !asked(&state)
        state.asked = true
        watch(turn)
        return moved + opening + running.driver.message(message).map { .send(running.process, $0) }
    }

    /// `turn`, about to be written, put in its agent conversation (once: sent again after a failed start, it is there):
    /// a new one, what its hiding numbered kept for it alone, unless it goes on in the one now (`Request.continues`, and
    /// that is still its conversation's); the one now when no question went into it yet, what was kept for it before
    /// gone (`keepOnly`). The web tools it may have: its own (`Request.web`), or the conversation's.
    private func place(_ turn: Turn, _ state: inout State) -> SessionWeb {
        if !turn.placed {
            if !turn.continues || (turn.owner != nil && turn.owner != state.owner) {
                if asked(&state) { rollOver(&state) }
                state.owner = turn.owner
                keepOnly(turn.hidden)
            }
            if let web = turn.web { state.web = web }
            turn.conversation = try? store.sessionID()
            turn.placed = true
        }
        return turn.web ?? state.web
    }

    /// `turn` ends with `error` (nil: answered): its stream finishes; one whose request has no message yet ends so once
    /// it has (`answer(_:_:)`).
    private func finish(_ turn: Turn, _ error: Error?) -> [Action] {
        turn.done = true
        guard let continuation = turn.continuation else {
            turn.ended = error ?? CancellationError()
            return []
        }
        return [.finish(continuation, error)]
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
            state.retiring[running.generation] = running
            state.running = nil  // its exit is of no session now
            state.idle?.cancel()
            state.idle = nil
            let failure = turn.done ? [] : finish(turn, ClaudeSessionError.noResponse)
            turn.done = true
            return failure + [.terminate(running.process, running.lock)] + pump(&state)
        }
        perform(actions)
        return wait
    }

    /// `turn`, waiting behind one being answered, fails with `failure` (`.busy`: the provider answers) unless it is sent
    /// within `firstAnswerTimeout` (`watch` replaces this watchdog).
    private func waitAtMost(_ turn: Turn, failing failure: ClaudeSessionError = .busy) {
        guard turn.watchdog == nil, !turn.sent, !turn.done else { return }
        turn.attempt += 1
        let (id, attempt, clock, timeout) = (turn.id, turn.attempt, answerClock, firstAnswerTimeout)
        turn.watchdog = Task { [weak self] in
            do { try await clock.sleep(for: timeout) } catch { return }
            self?.waitedTooLong(id, attempt: attempt, failure)
        }
    }

    /// The questions asked (their message in) while a process of ours is still ending (`State.retiring`), waiting for
    /// theirs to start: each fails with `.noResponse` (the provider answers) unless it is sent within
    /// `firstAnswerTimeout`, so that one whose end is never told holds none of them for longer.
    private func waitForStart(_ state: inout State) {
        for turn in state.turns where turn.message != nil { waitAtMost(turn, failing: .noResponse) }
    }

    private func waitedTooLong(_ id: Int, attempt: Int, _ failure: ClaudeSessionError) {
        let actions = state.withLock { state -> [Action] in
            guard let index = state.turns.firstIndex(where: { $0.id == id }) else { return [] }
            let turn = state.turns[index]
            guard turn.attempt == attempt, !turn.sent, !turn.done else { return [] }
            state.turns.remove(at: index)
            return finish(turn, failure)
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
        let actions = state.withLock { state -> [Action] in
            guard let running = state.running, running.generation == generation, state.turns.isEmpty else { return [] }
            state.retiring[running.generation] = running
            state.running = nil
            state.idle = nil
            return [.terminate(running.process, running.lock)]
        }
        perform(actions)
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
            // A session the agent made in place of the one it had (gone): it knows none of the earlier answers, and the
            // question goes into a new conversation.
            let previous = store.agentSessionID()
            store.setAgentSessionID(id)
            if let previous, previous != id {
                forgetAnswers()
                turn?.newConversation = true
            }
            return []
        case let .usage(tokens):
            guard let turn, !turn.done, let continuation = turn.continuation else { return [] }
            turn.tokens = tokens
            return turn.text.isEmpty ? [] : [.yield(continuation, turn.reply)]
        case .permissionRequest, .working, .other:
            return []  // a permission request is answered by the driver
        case .compacting:
            // The conversation's context compacted first, before any of the answer: that may take minutes. The provider
            // answers now, the turn is stopped as Esc stops it, and the process stays. Once the answer is coming in, it
            // goes on.
            guard let turn, !turn.done, turn.text.isEmpty else { return [] }
            givenUp(turn)
            return finish(turn, ClaudeSessionError.compacting) + interruptAction(&state)
        case .messageStarted:
            if let turn, !turn.text.isEmpty { turn.restarts = true }
            return []
        case let .text(text):
            guard let turn, !turn.done, let continuation = turn.continuation else { return [] }
            if turn.restarts { (turn.text, turn.restarts) = ("", false) }
            turn.text += text
            return [.yield(continuation, turn.reply)]
        case let .apiError(code, message):
            turn?.error = ClaudeSessionError.from(code: code, status: nil, message: message)
            return []
        case let .failed(error, endsProcess):
            if error == .signedOut { (state.availability, state.checkedAt) = (.signedOut, uptime()) }
            // Not to be asked as it is (not kept to the web): Settings → AI says so until it is looked at again.
            if error == .notWebOnly { (state.availability, state.checkedAt) = (.cannotStart, uptime()) }
            var actions: [Action] = []
            if let turn {
                state.turns.removeFirst()
                turn.watchdog?.cancel()
                if !turn.done { actions += finish(turn, error) }
                turn.done = true
            }
            if endsProcess {
                state.retiring[running.generation] = running
                state.running = nil  // its exit is of no session now
                state.idle?.cancel()
                state.idle = nil
                actions.append(.terminate(running.process, running.lock))
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
            if !turn.done, let continuation = turn.continuation {
                if interrupted {
                    actions.append(.finish(continuation, CancellationError()))
                } else if isError {
                    // The result's text may say more than the error line did (an AWS credential error).
                    let ended = ClaudeSessionError.from(code: nil, status: status, message: text)
                    let error = ended == .awsSignInExpired ? ended : turn.error ?? ended
                    if error == .signedOut { (state.availability, state.checkedAt) = (.signedOut, uptime()) }
                    actions.append(.finish(continuation, error))
                } else {
                    if turn.text.isEmpty, !text.isEmpty {
                        turn.text = text
                        actions.append(.yield(continuation, turn.reply))
                    }
                    actions.append(.finish(continuation, nil))
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
            if state.retiring.removeValue(forKey: generation) != nil {
                let pumped = pump(&state)
                // The last one ended, nothing asked meanwhile: a prewarm that waited for it starts its process now.
                guard state.prewarmWaiting, state.retiring.isEmpty, state.turns.isEmpty else { return pumped }
                return pumped + startPrewarmed(&state)
            }
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
                if backend.retryTogglesResume {
                    store.setResumable(!running.resume)
                    // Its conversation couldn't be resumed: a new one, without the rounds before.
                    if running.resume { state.asked = false }
                }
                return pump(&state)
            }
            state.turns.removeFirst()
            let error: ClaudeSessionError
            if ClaudeSessionError.isAWSCredentialError(message) {
                // Credentials Claude Code couldn't get (an `awsCredentialExport` that failed) end it before it answers.
                error = .awsSignInExpired
            } else if !running.started, turn.retried {
                // Ended twice before its session started: it can't start (an older version that doesn't know a flag, a
                // broken install). The fast fallback answers, saying why; Settings → AI says so until it is looked at again.
                (state.availability, state.checkedAt) = (.cannotStart, uptime())
                error = .failedToStart(status, message)
            } else {
                error = .exited(status, message)
            }
            let failure = turn.done ? [] : finish(turn, error)
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
                do { try process.send(line) } catch { terminateAfterGrace(process) }
            case let .yield(continuation, text):
                continuation.yield(text)
            case let .finish(continuation, error?):
                continuation.finish(throwing: error)
            case let .finish(continuation, nil):
                continuation.finish()
            case let .terminate(process, lock):
                terminateAfterGrace(process)
                if !process.isRunning { lock?.release() }
            }
        }
    }
}

// MARK: - The real process

/// Starts `claude` with the core's `ProcessLauncher` (`Platform.current.processes`): its standard input and output
/// piped, the output read line by line on a thread of its own; its end told by its termination handler
/// (`LaunchSpec.onExit`), never `waitUntilExit` on a dispatch thread, which sometimes never returns (a program that
/// exited would count as running: a sign-in check found signed out, a question waiting for a process long gone).
/// Its end (`exited`) is told once it has ended and its output has been read to its end; once it was killed (SIGKILL
/// to its group, `ClaudeSessionProcess.kill`; one asked to end is, after `ClaudeSessionManager.handOffGrace`, unless its
/// end was told by then), as soon as it has ended itself: something it started that left its group may hold its output
/// open for as long as it runs, which the signal doesn't reach (`PipedEnd`).
/// `executable`: where `claude` is (nil: not installed); `environment`: what it runs with (on the Mac the login shell's);
/// `processes`: nil, the platform's as it starts. One found that won't launch (gone since, not executable) throws
/// `ClaudeSessionError.cannotLaunch`, saying why (`launchFailure`).
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
        let errorTail = Locked(initialState: Data())
        let errorsRead = DispatchSemaphore(value: 0)
        let end = PipedEnd { status, givenUp in
            // Its output given up, standard error likely is too (held open by the same process): what it said by now.
            _ = errorsRead.wait(timeout: .now() + (givenUp ? 0.1 : 2))
            let message = String(decoding: errorTail.withLock { $0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            exited(status, String(message.split(whereSeparator: \.isNewline).last ?? ""))
        }
        let launched: any LaunchedProcess
        do {
            launched = try processes.launch(LaunchSpec(executable: executable, arguments: arguments, environment: environment(),
                                                       directory: directory, standardInput: .pipe(input),
                                                       standardOutput: .pipe(out), standardError: .pipe(errors),
                                                       onExit: { end.processEnded(status: $0.terminationStatus) }))
        } catch {
            throw ClaudeSessionError.cannotLaunch(Self.launchFailure(executable, error))
        }
        // Threads of their own: each blocks reading for as long as the process runs (a session's, many minutes). Once
        // its output is given up (`PipedEnd`), what they still read is dropped and they stop at their next read's end;
        // the pipes are left to them, never closed under a read (the descriptor could be another file's by then).
        Thread.detachNewThread {
            let handle = errors.fileHandleForReading
            while !end.givenUp, case let chunk = handle.availableData, !chunk.isEmpty {
                errorTail.withLock { $0 = ($0 + chunk).suffix(600) }
            }
            errorsRead.signal()
        }
        Thread.detachNewThread {
            let handle = out.fileHandleForReading
            var buffer = Data()
            while !end.givenUp, case let chunk = handle.availableData, !chunk.isEmpty {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if !line.isEmpty, !end.givenUp { output(Data(line)) }
                }
            }
            end.outputEnded()
        }
        return PipedClaudeProcess(process: launched, input: input.fileHandleForWriting, end: end)
    }

    /// Why `executable` didn't launch (`error`, the launcher's): not there, not executable, else what the launcher said
    /// (Foundation's `Process` says a file that is there but not executable "doesn't exist").
    static func launchFailure(_ executable: URL, _ error: Error) -> String {
        let path = executable.path
        if !FileManager.default.fileExists(atPath: path) { return tr("找不到程序 \(path)", "Program not found: \(path)") }
        if !FileManager.default.isExecutableFile(atPath: path) { return tr("\(path) 没有执行权限", "\(path) isn't executable") }
        return error.localizedDescription
    }
}

/// How a process `ProcessClaudeSessionLauncher` started has ended, told once (its `exited`): once the process has ended
/// and its output was read to its end; once it was killed (`killed`), as soon as the process itself has ended (its
/// termination handler ran: it was reaped), whatever still holds its output open: something it started that left its
/// group, which the SIGKILL didn't reach and which may run for ever. Its output (and standard error) is given up then:
/// not read any further.
private final class PipedEnd: @unchecked Sendable {
    private struct State {
        var status: Int32?
        var outputEnded = false
        var killed = false
        var told = false
        var givenUp = false
    }

    private let state = Locked(initialState: State())
    /// Tells it (on a thread of its own): its exit status, and whether its output was given up.
    private let tell: @Sendable (_ status: Int32, _ givenUp: Bool) -> Void

    init(tell: @escaping @Sendable (_ status: Int32, _ givenUp: Bool) -> Void) {
        self.tell = tell
    }

    /// Its end is told already.
    var told: Bool { state.withLock { $0.told } }
    /// Its output (and standard error) isn't read any more: its end was told before they ended.
    var givenUp: Bool { state.withLock { $0.givenUp } }

    /// The process itself ended (its termination handler), with `status`.
    func processEnded(status: Int32) { update { $0.status = status } }
    /// Its output was read to its end.
    func outputEnded() { update { $0.outputEnded = true } }
    /// It was killed, with what it started (SIGKILL to its group).
    func killed() { update { $0.killed = true } }

    private func update(_ change: (inout State) -> Void) {
        let told = state.withLock { state -> (status: Int32, givenUp: Bool)? in
            change(&state)
            guard !state.told, let status = state.status, state.outputEnded || state.killed else { return nil }
            state.told = true
            state.givenUp = !state.outputEnded
            return (status, state.givenUp)
        }
        guard let told else { return }
        Thread.detachNewThread { [tell] in tell(told.status, told.givenUp) }
    }
}

private final class PipedClaudeProcess: ClaudeSessionProcess, @unchecked Sendable {
    let process: any LaunchedProcess
    let input: FileHandle
    private let end: PipedEnd
    private let lock = NSLock()
    private var closed = false

    init(process: any LaunchedProcess, input: FileHandle, end: PipedEnd) {
        self.process = process
        self.input = input
        self.end = end
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

    /// Asked to end (SIGTERM to its group); killed after `ClaudeSessionManager.handOffGrace` unless its end was told by
    /// then: it may have ended at once while something it started that left its group holds its output open, and its
    /// end, which waits for that output's end until it is killed (`PipedEnd`), would never be told.
    func terminate() {
        closeInput()
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + ClaudeSessionManager.handOffGrace) { [self] in
            if !end.told { kill() }
        }
    }

    /// Killed with what is in its group (SIGKILL); its end is told as soon as it has ended itself (`PipedEnd`).
    func kill() {
        closeInput()
        process.kill()
        end.killed()
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
        if said { terminateAfterGrace(process) }
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
        if let process = said.process { terminateAfterGrace(process) }
        continuation.resume(returning: availability)
    }
}

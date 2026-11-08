import Foundation

/// A running `claude` process of the input method's session, as `ClaudeSessionManager` drives it.
public protocol ClaudeSessionProcess: AnyObject, Sendable {
    /// Writes one stream-json line to its standard input.
    func send(_ line: Data) throws
    /// Ends it (and what it started).
    func terminate()
}

/// Starts the session's process: the real one (`ProcessClaudeSessionLauncher`), or a test's.
public protocol ClaudeSessionLauncher: Sendable {
    /// Starts `claude` with `arguments` in `directory`. Each line it writes to its standard output goes to `output`, in
    /// order, on one thread; then `exited`, once, with its status and the end of what it wrote to standard error.
    /// Throws `ClaudeSessionError.notInstalled` when there is no `claude`.
    func start(_ arguments: [String], in directory: URL, output: @escaping @Sendable (Data) -> Void,
               exited: @escaping @Sendable (Int32, String) -> Void) throws -> any ClaudeSessionProcess
}

/// Keeps the input method's Claude Code session (`ClaudeSession`) running and asks it questions. One process at a time,
/// for every text field: started ahead of the first question (`prewarm`, when the command trigger is typed), so the
/// answer doesn't wait for Claude Code to start; reused for each question; ended after `idleTimeout` without one. One
/// that ended (a crash, killed) is started again with `--resume` by the next question. A question asked while another
/// is answered waits for it; stopping one (`ask`'s stream given up: Esc) interrupts its turn and the process stays.
/// Handing the session to Terminal (`handOff`) ends the process; while the Terminal one runs (its id in
/// `ClaudeSessionStore.terminalPIDFile`), no process starts here and questions fail with `.openInTerminal`.
/// A question with no sign of an answer within `firstAnswerTimeout` (Claude Code stuck starting, an `awsAuthRefresh`
/// sign-in waiting in a browser) fails with `.noResponse`, which falls back to the provider, and the process ends.
/// It also keeps what one long session needs across questions: the values hidden (`redacting`), so that a placeholder
/// never stands for two values, and which answers the session saw (`missing`, `remember`).
public final class ClaudeSessionManager: @unchecked Sendable {
    /// Without a question for this long, the process ends.
    public static let idleTimeout: Duration = .seconds(15 * 60)
    /// A question's longest wait for the first sign of its answer (the model's message starting; a web search after
    /// that may take longer).
    public static let firstAnswerTimeout: Duration = .seconds(30)

    public let store: ClaudeSessionStore
    private let launcher: any ClaudeSessionLauncher
    private let idleTimeout: Duration
    private let clock: any Clock<Duration>
    private let firstAnswerTimeout: Duration
    private let answerClock: any Clock<Duration>
    private let isAlive: @Sendable (Int32) -> Bool
    private let userSettings: @Sendable () -> URL?
    private let state = Locked(initialState: State())
    private let kept = Locked<Kept?>(initialState: nil)

    /// `isAlive`: whether a process id is a running process (the hand-off's Terminal one). `userSettings`: the user's
    /// Claude Code settings.json (`ClaudeSession.userSettingsFile`), whose provider settings the session gets; nil: none.
    /// `answerClock`: what `firstAnswerTimeout` is timed with.
    public init(launcher: any ClaudeSessionLauncher, store: ClaudeSessionStore = ClaudeSessionStore(),
                idleTimeout: Duration = ClaudeSessionManager.idleTimeout, clock: any Clock<Duration> = ContinuousClock(),
                firstAnswerTimeout: Duration = ClaudeSessionManager.firstAnswerTimeout,
                answerClock: any Clock<Duration> = ContinuousClock(),
                isAlive: @escaping @Sendable (Int32) -> Bool = { _ in false },
                userSettings: @escaping @Sendable () -> URL? = { ClaudeSession.userSettingsFile() }) {
        self.launcher = launcher
        self.store = store
        self.idleTimeout = idleTimeout
        self.clock = clock
        self.firstAnswerTimeout = firstAnswerTimeout
        self.answerClock = answerClock
        self.isAlive = isAlive
        self.userSettings = userSettings
    }

    /// What is kept of the session `session`: `memory` as saved, and the values hidden so far (in memory only).
    private struct Kept {
        var memory: ClaudeSessionStore.Memory
        var known: [Redaction.Hidden] = []
    }

    /// A question being answered, or waiting for the one before it.
    private final class Turn: @unchecked Sendable {
        let id: Int
        let message: Data
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
        /// Some sign of the answer came (the model's message started, text, the turn's end): no `firstAnswerTimeout`.
        var answering = false
        /// Ends it after `firstAnswerTimeout` without a sign of the answer; one per time it is written.
        var watchdog: Task<Void, Never>?
        var attempt = 0

        init(id: Int, message: Data, continuation: AsyncThrowingStream<String, Error>.Continuation) {
            self.id = id
            self.message = message
            self.continuation = continuation
        }
    }

    private struct Running {
        var process: any ClaudeSessionProcess
        var generation: Int
        var resume: Bool
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
    }

    /// What is done once the lock is let go (finishing a stream runs its consumer's code).
    private enum Action {
        case send(any ClaudeSessionProcess, generation: Int, Data)
        case yield(AsyncThrowingStream<String, Error>.Continuation, String)
        case finish(AsyncThrowingStream<String, Error>.Continuation, Error?)
        case terminate(any ClaudeSessionProcess)
    }

    // MARK: - What it's asked

    /// Whether `claude` can answer here, as last found (the shell looks at launch, `claude auth status`; each answer, or
    /// failure, tells too).
    public var availability: ClaudeSession.Availability {
        get { state.withLock { $0.availability } }
        set { state.withLock { $0.availability = newValue } }
    }

    /// Whether `@question` goes to the session with `config`: picked in the settings, or (not picked) when `claude` is
    /// installed and signed in.
    public func answersQuestions(_ config: Config) -> Bool {
        switch config.questionBackend {
        case .claudeSession?: return true
        case .provider?: return false
        case nil: return availability == .ready
        }
    }

    /// Whether the process runs now.
    public var isRunning: Bool { state.withLock { $0.running != nil } }

    /// Starts the process now, if it isn't running, so that the next question doesn't wait for it; it ends after
    /// `idleTimeout` unless a question comes.
    public func prewarm() {
        state.withLock { state in
            guard state.turns.isEmpty else { return }
            if state.running == nil {
                guard !terminalOpen(), (try? start(&state)) != nil else { return }
            }
            scheduleIdle(&state)
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
                state.turns.append(Turn(id: id, message: ClaudeSession.userMessage(question), continuation: continuation))
                return pump(&state)
            }
            perform(actions)
        }
    }

    /// Stops the turn being answered (its stream ends with `CancellationError`); the process stays.
    public func interrupt() {
        let actions = state.withLock { state -> [Action] in
            guard let turn = state.turns.first, turn.sent, !turn.done else { return [] }
            turn.done = true
            return [.finish(turn.continuation, CancellationError())] + interruptAction(&state)
        }
        perform(actions)
    }

    /// Hands the session to Terminal: the process ends (a question being answered stops), and what Terminal is to run
    /// (`ClaudeSession.terminalArguments`, `claude` being where Claude Code is) in the session's folder.
    public func handOff(claude: String) throws -> (arguments: [String], directory: URL) {
        stop()
        let id = try store.sessionID()
        return (ClaudeSession.terminalArguments(claude: claude, sessionID: id, resume: store.resumable), store.directory)
    }

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

    /// A new session from now on ("start over" in the settings): the process ends, a new id is made.
    public func startOver() throws {
        stop()
        try kept.withLock { kept in
            kept = nil
            try store.startOver()
        }
    }

    /// The arguments for `claude auth status` that say what the session will find (`ClaudeSession.authStatusArguments`),
    /// run in `store.directory`; the folder and its provider settings are written first.
    public func authStatusArguments() -> [String] {
        try? store.prepare()
        return ClaudeSession.authStatusArguments(settings: providerSettings())
    }

    /// The user's provider settings written into the session's folder, nil when there are none.
    private func providerSettings() -> URL? {
        userSettings().flatMap { store.writeProviderSettings(from: $0) }
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

    /// Starts the process (with `--resume` once the session has a conversation).
    @discardableResult
    private func start(_ state: inout State) throws -> Running {
        if let running = state.running { return running }
        do {
            try store.prepare()
            let id = try store.sessionID()
            let resume = store.resumable
            state.generation += 1
            let generation = state.generation
            let arguments = ClaudeSession.arguments(sessionID: id, resume: resume, settings: providerSettings())
            let process = try launcher.start(arguments, in: store.directory,
                                             output: { [weak self] in self?.received($0, generation: generation) },
                                             exited: { [weak self] in self?.exited(generation: generation, status: $0, message: $1) })
            let running = Running(process: process, generation: generation, resume: resume)
            state.running = running
            return running
        } catch ClaudeSessionError.notInstalled {
            state.availability = .notInstalled
            throw ClaudeSessionError.notInstalled
        }
    }

    /// The first turn written to the process (started if it isn't running), unless one is being answered.
    private func pump(_ state: inout State) -> [Action] {
        while let first = state.turns.first, first.done, !first.sent { state.turns.removeFirst() }
        guard let turn = state.turns.first, !turn.sent else { return [] }
        let running: Running
        do {
            running = try start(&state)
        } catch {
            let turns = state.turns
            state.turns = []
            let failure = error as? ClaudeSessionError ?? .failed(error.localizedDescription)
            return turns.filter { !$0.done }.map { .finish($0.continuation, failure) }
        }
        state.idle?.cancel()
        state.idle = nil
        turn.sent = true
        watch(turn)
        return [.send(running.process, generation: running.generation, turn.message)]
    }

    /// `turn`, just written, fails with `.noResponse` unless a sign of its answer comes within `firstAnswerTimeout`.
    private func watch(_ turn: Turn) {
        turn.watchdog?.cancel()
        turn.answering = false
        turn.attempt += 1
        let (id, attempt, clock, timeout) = (turn.id, turn.attempt, answerClock, firstAnswerTimeout)
        turn.watchdog = Task { [weak self] in
            do { try await clock.sleep(for: timeout) } catch { return }
            self?.noResponse(id, attempt: attempt)
        }
    }

    /// No sign of the answer to the turn `id` in time: it fails (falling back) and the process ends; the next question
    /// starts one again.
    private func noResponse(_ id: Int, attempt: Int) {
        let actions = state.withLock { state -> [Action] in
            guard let turn = state.turns.first, turn.id == id, turn.attempt == attempt, turn.sent, !turn.answering,
                  let running = state.running else { return [] }
            state.turns.removeFirst()
            state.running = nil  // its exit is of no session now
            state.idle?.cancel()
            state.idle = nil
            let failure: [Action] = turn.done ? [] : [.finish(turn.continuation, ClaudeSessionError.noResponse)]
            turn.done = true
            return failure + [.terminate(running.process)] + pump(&state)
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
        state.serial += 1
        return [.send(running.process, generation: running.generation, ClaudeSession.interrupt(requestID: "interrupt-\(state.serial)"))]
    }

    /// The turn `id`'s stream was given up: interrupted if it's being answered, else dropped.
    private func cancel(_ id: Int) {
        let actions = state.withLock { state -> [Action] in
            guard let index = state.turns.firstIndex(where: { $0.id == id }) else { return [] }
            let turn = state.turns[index]
            guard !turn.done else { return [] }
            turn.done = true
            guard turn.sent else {
                state.turns.remove(at: index)
                return []
            }
            return interruptAction(&state)
        }
        perform(actions)
    }

    /// A line of the process's output.
    private func received(_ line: Data, generation: Int) {
        let event = ClaudeSession.event(line)
        let actions = state.withLock { state -> [Action] in
            guard let running = state.running, running.generation == generation else { return [] }
            let turn = state.turns.first.flatMap { $0.sent ? $0 : nil }
            switch event {
            case .messageStarted, .text, .apiError, .result:
                turn?.answering = true
                turn?.watchdog?.cancel()
            default:
                break
            }
            switch event {
            case .started:
                // The session has its conversation from here on (the question is in its transcript): resumed from now on.
                state.running?.started = true
                store.markResumable()
                return []
            case let .permissionRequest(id):
                return [.send(running.process, generation: generation, ClaudeSession.deny(requestID: id))]
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
            case let .result(isError, interrupted, text, status):
                // A failure before the session started is the start's: its exit says what to do (`exited`).
                guard running.started, let turn else { return [] }
                state.turns.removeFirst()
                var actions: [Action] = []
                if !isError { state.availability = .ready }
                if !turn.done {
                    if interrupted {
                        actions.append(.finish(turn.continuation, CancellationError()))
                    } else if isError {
                        // The result's text may say more than the error line did (an AWS credential error).
                        let ended = ClaudeSessionError.from(code: nil, status: status, message: text)
                        let error = ended == .awsSignInExpired ? ended : turn.error ?? ended
                        if error == .signedOut { state.availability = .signedOut }
                        actions.append(.finish(turn.continuation, error))
                    } else {
                        if turn.text.isEmpty, !text.isEmpty { actions.append(.yield(turn.continuation, text)) }
                        actions.append(.finish(turn.continuation, nil))
                    }
                }
                actions += pump(&state)
                if state.turns.isEmpty { scheduleIdle(&state) }
                return actions
            case .other:
                return []
            }
        }
        perform(actions)
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
                store.setResumable(!running.resume)
                return pump(&state)
            }
            state.turns.removeFirst()
            // Credentials Claude Code couldn't get (an `awsCredentialExport` that failed) end it before it answers.
            let error = ClaudeSessionError.isAWSCredentialError(message) ? ClaudeSessionError.awsSignInExpired : .exited(status, message)
            let failure: [Action] = turn.done ? [] : [.finish(turn.continuation, error)]
            return failure + pump(&state)
        }
        perform(actions)
    }

    private func perform(_ actions: [Action]) {
        for action in actions {
            switch action {
            case let .send(process, generation, line):
                do {
                    try process.send(line)
                } catch {
                    exited(generation: generation, status: -1, message: error.localizedDescription)
                }
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
/// piped, the output read line by line on a thread of its own. `executable`: where `claude` is (nil: not installed);
/// `environment`: what it runs with (on the Mac the login shell's); `processes`: nil, the platform's as it starts.
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

    public func start(_ arguments: [String], in directory: URL, output: @escaping @Sendable (Data) -> Void,
                      exited: @escaping @Sendable (Int32, String) -> Void) throws -> any ClaudeSessionProcess {
        let processes = processes ?? Platform.current.processes
        guard processes.canLaunch, let executable = executable() else { throw ClaudeSessionError.notInstalled }
        let input = Pipe(), out = Pipe(), errors = Pipe()
        let launched = try processes.launch(LaunchSpec(executable: executable, arguments: arguments, environment: environment(),
                                                       directory: directory, standardInput: .pipe(input),
                                                       standardOutput: .pipe(out), standardError: .pipe(errors)))
        let errorTail = Locked(initialState: Data())
        let errorsRead = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let handle = errors.fileHandleForReading
            while case let chunk = handle.availableData, !chunk.isEmpty {
                errorTail.withLock { $0 = ($0 + chunk).suffix(600) }
            }
            errorsRead.signal()
        }
        DispatchQueue.global().async {
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
            launched.waitUntilExit()
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

    init(process: any LaunchedProcess, input: FileHandle) {
        self.process = process
        self.input = input
    }

    func send(_ line: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        try input.write(contentsOf: line)
    }

    func terminate() {
        try? input.close()
        process.terminate()
    }
}

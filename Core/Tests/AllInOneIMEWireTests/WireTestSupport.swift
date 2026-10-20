import AllInOneIMECore
@testable import AllInOneIMEWire
import Foundation

extension WirePeer {
    /// A desktop app's client as the pipe finds it: medium integrity, not in an AppContainer (§8).
    static let trustedClient = WirePeer(integrity: .medium)
}

/// A queue that runs its work only when told (`drain`, or `sync`, which runs what is queued first): the goldens'
/// task runner, run until idle after each step.
final class ManualQueue: WireQueue, @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [@Sendable () -> Void] = []

    func sync<T>(_ work: () throws -> T) rethrows -> T {
        drain()
        return try work()
    }

    func async(_ work: @escaping @Sendable () -> Void) {
        lock.lock()
        jobs.append(work)
        lock.unlock()
    }

    func drain() { _ = drained() }

    /// Runs what is queued, and what that queues; how many jobs ran.
    func drained() -> Int {
        var ran = 0
        while let job = next() {
            job()
            ran += 1
        }
        return ran
    }

    private func next() -> (@Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return jobs.isEmpty ? nil : jobs.removeFirst()
    }

    var busyFor: Double { 0 }
}

/// The engine's side in the tests: level two from a `ScriptedProvider`, everything else recorded.
final class TestHost: WireHost, @unchecked Sendable {
    var provider: ScriptedProvider?
    /// Whether the client owns the foreground (§8).
    var foreground = true
    private let lock = NSLock()
    private var log: [String] = []
    private var known: [UInt32: ComposerSession] = [:]

    /// The sessions the host has seen (a panel shown or hidden, a caret report), by sid.
    var sessions: [UInt32: ComposerSession] {
        lock.lock()
        defer { lock.unlock() }
        return known
    }

    private func remember(_ session: ComposerSession) {
        lock.lock()
        known[session.sid] = session
        lock.unlock()
    }

    /// What the engine did, in order: "sid 1: notice", "sid 1: panel shown" …
    var performed: [String] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    private func record(_ entry: String) {
        lock.lock()
        log.append(entry)
        lock.unlock()
    }

    func perform(_ effect: Composer.Effect, in session: ComposerSession) {
        if effect == .cancelConversion { provider?.cancel(in: session) }
        if let provider, provider.start(effect, in: session) {
            record("sid \(session.sid): request")
            return
        }
        if case let .notice(text) = effect {
            record("sid \(session.sid): notice \(text)")
            return
        }
        record("sid \(session.sid): \(ComposerSession.kind(of: effect))")
    }

    func panel(shown: Bool, in session: ComposerSession) { remember(session) }

    func caretMoved(in session: ComposerSession) { remember(session) }

    func ownsForeground(_ peer: WirePeer) -> Bool { foreground }

    func sessionClosed(_ session: ComposerSession) { provider?.cancel(in: session) }
}

/// A server on a manual clock and manual queues, with a `TestHost`, as the goldens run it.
final class TestEngine: @unchecked Sendable {
    let clock = ManualClock()
    let host = TestHost()
    let server: WireServer
    private let lock = NSLock()
    private var queues: [ManualQueue] = []
    private var pushed: [(ConnectionID, Data)] = []

    static let enginePid: UInt32 = 3100

    init(fixture: ScriptedProvider.Fixture? = nil, inputLanguage: Language = .english,
         configure: (inout WireServer.Configuration) -> Void = { _ in }, log: @escaping @Sendable (String) -> Void = { _ in }) {
        var configuration = WireServer.Configuration()
        configuration.enginePid = Self.enginePid
        configuration.engineVersion = "test"
        configure(&configuration)
        let queuesBox = QueueBox()
        let environment = WireEnvironment(
            host: host, clock: clock,
            makeQueue: { _ in queuesBox.make() },
            makeComposer: { _, _ in
                let composer = Composer(engine: LatinEngine())
                composer.setInputMode(inputLanguage)
                return composer
            },
            log: log)
        server = WireServer(configuration: configuration, environment: environment)
        queuesBox.owner = self
        if let fixture { host.provider = ScriptedProvider(fixture: fixture, clock: clock) }
        server.push = { [unowned self] id, data in
            lock.lock()
            pushed.append((id, data))
            lock.unlock()
        }
    }

    fileprivate func add(_ queue: ManualQueue) {
        lock.lock()
        queues.append(queue)
        lock.unlock()
    }

    /// Runs every queue until nothing is left to run (a job may queue one on another queue: the settings' notices).
    func runUntilIdle() {
        var ran: Int
        repeat {
            lock.lock()
            let all = queues
            lock.unlock()
            ran = all.reduce(0) { $0 + $1.drained() }
        } while ran > 0
    }

    /// The frames pushed to `id` since the last call.
    func takePushes(for id: ConnectionID) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        let mine = pushed.filter { $0.0 == id }.map(\.1)
        pushed.removeAll { $0.0 == id }
        return mine
    }

    /// Sends a body and returns everything the engine sent, pushes first (they are written as they happen), until idle.
    func send(_ body: Data, on id: ConnectionID) -> [Data] {
        let answers = server.receive(body, on: id)
        let before = takePushes(for: id)
        runUntilIdle()
        return before + answers + takePushes(for: id)
    }

    func send(_ frame: ClientFrame, on id: ConnectionID) -> [EngineFrame] {
        send(try! WireJSON.encode(frame), on: id).map { try! WireJSON.decode(EngineFrame.self, from: $0) }
    }
}

private final class QueueBox: @unchecked Sendable {
    weak var owner: TestEngine?
    func make() -> WireQueue {
        let queue = ManualQueue()
        owner?.add(queue)
        return queue
    }
}

extension Language {
    /// A golden's `#! inputLanguage` name.
    init?(goldenName: String) {
        switch goldenName {
        case "english": self = .english
        case "chinese": self = .chinese
        case "french": self = .french
        case "korean": self = .korean
        case "hindi": self = .hindi
        default: return nil
        }
    }
}

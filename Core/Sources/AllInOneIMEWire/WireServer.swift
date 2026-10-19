import AllInOneIMECore
import Foundation

/// A connection's number, the server's own.
public typealias ConnectionID = UInt64

/// What a `WireServer` needs of the engine around it.
public struct WireEnvironment: Sendable {
    /// What the engine does itself (§6): level two, its panel, opening things.
    public var host: WireHost
    public var clock: WireClock
    /// A serial queue for each connection.
    public var makeQueue: @Sendable (_ label: String) -> WireQueue
    /// A field's Composer, made when the field first takes the focus (§4): its level-one engine, languages, commands.
    public var makeComposer: @Sendable (_ field: FieldInfo, _ peer: WirePeer) -> Composer
    /// Sizes and kinds only, never a payload (§8).
    public var log: @Sendable (String) -> Void

    public init(host: WireHost, clock: WireClock = SystemClock(),
                makeQueue: @escaping @Sendable (String) -> WireQueue = { DispatchWireQueue(label: $0) },
                makeComposer: @escaping @Sendable (FieldInfo, WirePeer) -> Composer = WireEnvironment.latinComposer,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.host = host
        self.clock = clock
        self.makeQueue = makeQueue
        self.makeComposer = makeComposer
        self.log = log
    }

    /// A Composer typing Latin letters (`LatinEngine`: no language pack, as on Windows until librime comes), in English.
    public static let latinComposer: @Sendable (FieldInfo, WirePeer) -> Composer = { _, _ in
        let composer = Composer(engine: LatinEngine())
        composer.setInputMode(.english)
        return composer
    }
}

/// The engine's side of the protocol, whatever carries it (a Windows pipe, a byte stream in a test, JNI later): the
/// connections, their sessions, trust, the rate limits and one serial queue per connection (§11). The transport hands
/// it each frame's body (`receive`, which answers) and writes what it pushes on its own (`push`).
public final class WireServer: @unchecked Sendable {
    public struct Configuration: Sendable {
        /// `welcome.engine`.
        public var engineVersion = AppVersion.string
        public var enginePid: UInt32 = 0
        /// `welcome.capabilities`.
        public var capabilities: [String] = []
        public var limits = WireLimits()
        public var sessionsPerConnection = 64
        public var connectionsPerProcess = 64
        public var connections = 256
        /// New connections a process may open per second.
        public var connectsPerProcessPerSecond = 32
        /// Key-downs and key-ups per connection per second.
        public var keysPerSecond = 200
        /// A connection whose unacknowledged pushes pass these is dropped (§7).
        public var unackedFrames = 256
        public var unackedBytes = 4 * 1024 * 1024
        /// Accept `x-test` frames (the goldens' directives over a real transport): the engine's test mode only.
        public var testControl = false
        /// `receive` hands its answers to `push`, on the connection's queue, instead of returning them: for a transport
        /// that writes the answers on another thread than the pushes (a pipe's reader thread), where a push made on
        /// the queue between the answer and its write would otherwise reach the client first.
        public var answersThroughPush = false

        public init() {}
    }

    public let configuration: Configuration
    public let environment: WireEnvironment
    /// Writes a frame the engine sends on its own (`apply`, `bye`) to a connection: set by the transport. Called on the
    /// connection's queue.
    public var push: @Sendable (ConnectionID, Data) -> Void = { _, _ in }
    /// Asks the transport to close a connection the engine dropped on its own (too much unacknowledged data).
    public var drop: @Sendable (ConnectionID) -> Void = { _ in }
    /// In test mode, the `x-test` directives `perform` doesn't know (the engine's: `provider`, `inputLanguage`): true if
    /// done.
    public var testDirective: @Sendable (_ directive: String, _ frame: TestFrame) -> Bool = { _, _ in false }

    private let lock = NSLock()
    private var connections: [ConnectionID: Connection] = [:]
    private var lastID: ConnectionID = 0
    private var connects: [UInt32: [Double]] = [:]
    private var settingsService: SettingsService?
    /// A test's settings (`#! settings`): their folder, removed when they are replaced.
    private var testSettingsFolder: URL?

    /// The settings a settings window may read and change over the wire (§12); nil (the default): none, and a client
    /// that asks for them gets no `settings` capability. Setting it makes the server tell the clients that have them of
    /// every change (`settingsChanged`).
    public var settings: SettingsService? {
        get { lock.guarded { settingsService } }
        set {
            newValue?.changed = { [weak self] revision in self?.settingsChanged(revision) }
            lock.guarded { settingsService = newValue }
        }
    }

    public init(configuration: Configuration = Configuration(), environment: WireEnvironment) {
        self.configuration = configuration
        self.environment = environment
    }

    // MARK: - Connections

    /// A client connected (its checks passed, §2.1): its number, or nil when a limit refuses it (§8).
    public func connect(_ peer: WirePeer) -> ConnectionID? {
        lock.guarded {
            guard connections.count < configuration.connections else {
                environment.log("connection refused: \(connections.count) open")
                return nil
            }
            if let pid = peer.pid {
                guard connections.values.filter({ $0.peer.pid == pid }).count < configuration.connectionsPerProcess else {
                    environment.log("connection refused: process \(pid) has \(configuration.connectionsPerProcess) open")
                    return nil
                }
                let now = environment.clock.now
                connects = connects.filter { $0.value.contains { now - $0 < 1 } }
                var recent = connects[pid, default: []].filter { now - $0 < 1 }
                guard recent.count < configuration.connectsPerProcessPerSecond else {
                    environment.log("connection refused: process \(pid) connects too often")
                    return nil
                }
                recent.append(now)
                connects[pid] = recent
            }
            lastID += 1
            connections[lastID] = Connection(id: lastID, peer: peer, queue: environment.makeQueue("allinoneime.wire.\(lastID)"))
            return lastID
        }
    }

    /// The client is gone (a broken pipe, the transport closed): its sessions close and their tasks stop, with no
    /// outputs (§4 "Disconnects").
    public func disconnect(_ id: ConnectionID) {
        guard let connection = lock.guarded({ connections.removeValue(forKey: id) }) else { return }
        connection.queue.sync { shut(connection) }
    }

    /// Whether the connection is still open: false after a fatal error (§3), when the transport closes it.
    public func isOpen(_ id: ConnectionID) -> Bool {
        lock.guarded { connections[id] }?.isOpen ?? false
    }

    public var connectionCount: Int { lock.guarded { connections.count } }

    /// The longest any connection's queue has been busy with one piece of work: the watchdog's (§2.5).
    public var longestBusy: Double {
        lock.guarded { Array(connections.values) }.map(\.queue.busyFor).max() ?? 0
    }

    /// Before the engine exits: `bye` to every client (§2.5).
    public func bye(reason: String = "update", retryMs: Int = 500) {
        for connection in lock.guarded({ Array(connections.values) }) {
            connection.queue.sync {
                guard connection.isOpen, connection.version != nil else { return }
                if let data = encode(connection.frame(.bye(reason: reason, retryMs: retryMs))) { push(connection.id, data) }
            }
        }
    }

    // MARK: - Frames

    /// A frame's body from the client: the engine's answers, to write in order. Then, if `isOpen` is false, the
    /// transport closes the connection.
    public func receive(_ body: Data, on id: ConnectionID) -> [Data] {
        guard let connection = lock.guarded({ connections[id] }), connection.isOpen else { return [] }
        do {
            guard body.count <= WireFrame.clientLimit else { throw WireFrame.Failure.tooLarge(body.count) }
            try WireFrame.check(body)
        } catch {
            return refusing(error, on: connection)
        }
        if configuration.testControl, let test = try? WireJSON.decode(TestFrame.self, from: body), test.type == TestFrame.type {
            let answer = testAnswer(test, on: connection)
            return connection.queue.sync { deliver([answer], on: connection) }
        }
        let frame: ClientFrame
        do {
            frame = try WireJSON.decode(ClientFrame.self, from: body)
        } catch let error as DecodingError {
            if case let .dataCorrupted(context) = error, context.codingPath.isEmpty {
                return refusing(WireFrame.Failure.badFrame("invalid JSON"), on: connection)
            }
            let re = (try? WireJSON.decode(Envelope.self, from: body))?.id
            return connection.queue.sync {
                guard connection.version != nil else {
                    return deliver(closing(connection, re: re, .badMessage, "the first frame must be hello"), on: connection)
                }
                return deliver(encodeAll(connection, [connection.error(re: re, .badMessage, Self.describe(error))]), on: connection)
            }
        } catch {
            return refusing(WireFrame.Failure.badFrame("invalid JSON"), on: connection)
        }
        return connection.queue.sync { deliver(handle(frame, on: connection), on: connection) }
    }

    /// A frame the transport refused before reading it (§2.2: its length, its size): the error, and the connection
    /// closes.
    public func refuse(_ failure: WireFrame.Failure, on id: ConnectionID) -> [Data] {
        guard let connection = lock.guarded({ connections[id] }), connection.isOpen else { return [] }
        return refusing(failure, on: connection)
    }

    private func refusing(_ failure: Error, on connection: Connection) -> [Data] {
        let failure = failure as? WireFrame.Failure ?? .badFrame("unreadable frame")
        return connection.queue.sync { deliver(closing(connection, re: nil, failure.code, failure.message), on: connection) }
    }

    /// The answers to return, or with `answersThroughPush` pushed now (on the queue, in order with the pushes).
    private func deliver(_ answers: [Data], on connection: Connection) -> [Data] {
        guard configuration.answersThroughPush else { return answers }
        for answer in answers { push(connection.id, answer) }
        return []
    }

    /// A fatal error: the frame, then the connection closes.
    private func closing(_ connection: Connection, re: UInt32?, _ code: WireErrorCode, _ message: String,
                         versions: [Int]? = nil) -> [Data] {
        environment.log("connection \(connection.id): \(code): \(message): closing")
        let data = encodeAll(connection, [connection.error(re: re, code, message, versions: versions)])
        shut(connection)
        return data
    }

    private func handle(_ frame: ClientFrame, on connection: Connection) -> [Data] {
        let id = frame.id
        guard let version = connection.version else {
            guard case let .hello(hello) = frame.message else {
                return closing(connection, re: id, .badMessage, "the first frame must be hello")
            }
            guard let common = Set(hello.versions).intersection(WireVersion.supported).max() else {
                return closing(connection, re: id, .unsupportedVersion, "no common version", versions: WireVersion.supported)
            }
            if let problem = Self.check(hello) { return closing(connection, re: id, .badMessage, problem) }
            connection.version = common
            connection.capabilities = Set(hello.capabilities)
            // The settings only for a client that asks for them and may have them (§12, §8), when there are any.
            connection.settings = hello.capabilities.contains(Hello.settings) && connection.peer.trusted && settings != nil
            environment.log("connection \(connection.id): hello from \(hello.client.prefix(32)), v\(common)"
                + (connection.settings ? ", settings" : ""))
            let welcome = Welcome(version: common, engine: configuration.engineVersion, enginePid: configuration.enginePid,
                                  capabilities: configuration.capabilities + (connection.settings ? [Hello.settings] : []),
                                  limits: configuration.limits)
            return encodeAll(connection, [connection.frame(.welcome(re: id, welcome))])
        }
        guard frame.v == version else {
            return encodeAll(connection, [connection.error(re: id, .badMessage, "v \(frame.v) isn't the version agreed (\(version))")])
        }
        return encodeAll(connection, answer(frame.message, id: id, on: connection))
    }

    private func answer(_ message: ClientMessage, id: UInt32, on connection: Connection) -> [EngineFrame] {
        func error(_ code: WireErrorCode, _ text: String) -> [EngineFrame] { [connection.error(re: id, code, text)] }
        func result(_ handled: Bool, _ outputs: [Output]) -> [EngineFrame] {
            [connection.frame(.result(re: id, handled: handled, outputs: outputs))]
        }
        switch message {
        case .hello:
            return error(.badMessage, "hello again")

        case let .open(sid, field):
            if let problem = Self.check(field) { return error(.badMessage, problem) }
            if let record = connection.sessions[sid] {
                record.field = field  // opened again: the field as it is now
                return []
            }
            guard connection.sessions.count < configuration.sessionsPerConnection else {
                return error(.limit, "more than \(configuration.sessionsPerConnection) sessions")
            }
            connection.sessions[sid] = SessionRecord(field: field)
            return []

        case let .focus(sid, serial, field):
            guard let record = connection.sessions[sid] else { return error(.noSession, "no session \(sid)") }
            if let field {
                if let problem = Self.check(field) { return error(.badMessage, problem) }
                record.field = field
            }
            if let other = connection.focused, other != sid, let session = connection.sessions[other]?.session {
                // Focused elsewhere without a blur first: the other field is left as it is, what it had pending dropped.
                environment.log("connection \(connection.id): session \(sid) focused without a blur of \(other)")
                _ = session.blur()
                connection.held[other] = nil
            }
            let session = record.session ?? makeSession(sid, record, on: connection)
            record.session = session
            connection.focused = sid
            let outputs = session.focus(serial: serial, field: field)
            if !outputs.isEmpty { pushApply(outputs, for: session, on: connection) }
            return []

        case let .blur(sid):
            guard let record = connection.sessions[sid] else { return error(.noSession, "no session \(sid)") }
            if connection.focused == sid { connection.focused = nil }
            let held = connection.held.removeValue(forKey: sid) ?? []
            return result(false, held + (record.session?.blur() ?? []))

        case let .close(sid):
            guard let record = connection.sessions.removeValue(forKey: sid) else { return error(.noSession, "no session \(sid)") }
            if connection.focused == sid { connection.focused = nil }
            connection.held[sid] = nil
            record.session?.close()
            return []

        case let .keyDown(frame), let .keyUp(frame):
            let now = environment.clock.now
            connection.keyTimes.removeAll { now - $0 >= 1 }
            guard connection.keyTimes.count < configuration.keysPerSecond else {
                return error(.limit, "more than \(configuration.keysPerSecond) keys a second")
            }
            connection.keyTimes.append(now)
            if let problem = check(frame) { return error(.badMessage, problem) }
            guard let record = connection.sessions[frame.sid] else { return error(.noSession, "no session \(frame.sid)") }
            guard connection.focused == frame.sid, let session = record.session else {
                return error(.notFocused, "session \(frame.sid) isn't focused")
            }
            let held = connection.held.removeValue(forKey: frame.sid) ?? []
            let answer: (handled: Bool, outputs: [Output])
            if case .keyDown = message { answer = session.keyDown(frame) } else { answer = session.keyUp(frame) }
            return result(answer.handled, held + answer.outputs)

        case let .endComposition(sid, reason):
            guard let record = connection.sessions[sid] else { return error(.noSession, "no session \(sid)") }
            let held = connection.held.removeValue(forKey: sid) ?? []
            return result(false, held + (record.session?.endComposition(reason: reason) ?? []))

        case .ping:
            return [connection.frame(.pong(re: id))]

        case let .caret(sid, rect, hwnd, exact):
            guard rect.count == 4 else { return error(.badMessage, "rect isn't [x, y, width, height]") }
            guard let record = connection.sessions[sid] else { return error(.noSession, "no session \(sid)") }
            record.session?.caretReported(rect: rect, hwnd: hwnd, exact: exact)
            return []

        case let .applied(re, ok, reason, ctx):
            if let ctx, let problem = check(ctx) { return error(.badMessage, problem) }
            guard let sent = connection.unacked.removeValue(forKey: re) else { return [] }
            connection.unackedBytes -= sent.bytes
            if !ok { environment.log("connection \(connection.id): apply \(re) refused: \((reason ?? "-").prefix(16))") }
            guard let session = connection.sessions[sent.sid]?.session else { return [] }
            session.applied(context: ctx)
            if !connection.unacked.values.contains(where: { $0.sid == sent.sid }),
               let held = connection.held.removeValue(forKey: sent.sid) {
                send(held, for: session, on: connection)
            }
            return []

        case .settingsGet, .settingsSet, .settingsAction:
            return answerSettings(message, id: id, on: connection)

        case let .unknown(type):
            environment.log("connection \(connection.id): unknown type (\(type.count) chars)")
            return error(.unknownType, "unknown type")
        }
    }

    // MARK: - Settings (§12)

    /// A settings request: answered with the settings as they now are, and what was refused or said. An action that
    /// takes a while (a test, a download) is answered when it is done, through `push`; meanwhile the connection goes on.
    private func answerSettings(_ message: ClientMessage, id: UInt32, on connection: Connection) -> [EngineFrame] {
        guard connection.settings, let service = settings else {
            // Not asked for: the type is unknown to this client, as before §12. Asked for and refused: not allowed.
            guard connection.capabilities.contains(Hello.settings) else {
                return [connection.error(re: id, .unknownType, "unknown type")]
            }
            return [connection.error(re: id, .notAllowed, "the settings are for a trusted client only")]
        }
        func answer(_ problem: SettingsProblem? = nil, message: String? = nil) -> EngineFrame {
            Self.settingsAnswer(service, re: id, on: connection, problem: problem, message: message)
        }
        switch message {
        case .settingsGet:
            return [answer()]
        case let .settingsSet(field, value, revision, shown):
            guard field.utf16.count <= FieldLimits.app else { return [connection.error(re: id, .badMessage, "field over its limit")] }
            environment.log("connection \(connection.id): settingsSet \(field.prefix(64))")
            if case let .failure(problem) = service.set(field, to: value, revision: revision, shown: shown) { return [answer(problem)] }
            return [answer()]
        case let .settingsAction(action):
            guard action.field.utf16.count <= FieldLimits.app, action.name.utf16.count <= FieldLimits.app else {
                return [connection.error(re: id, .badMessage, "field or action over its limit")]
            }
            // The field and the action, never the key or a value.
            environment.log("connection \(connection.id): settingsAction \(action.name.prefix(16)) on \(action.field.prefix(64))")
            guard SettingsService.takesAWhile(action) else {
                switch service.performNow(action) {
                case let .success(outcome): return [answer(message: outcome.message)]
                case let .failure(problem): return [answer(problem)]
                }
            }
            Task {
                let result = await service.perform(action)
                connection.queue.async {
                    guard connection.isOpen else { return }
                    let frame: EngineFrame
                    switch result {
                    case let .success(outcome): frame = Self.settingsAnswer(service, re: id, on: connection, message: outcome.message)
                    case let .failure(problem): frame = Self.settingsAnswer(service, re: id, on: connection, problem: problem)
                    }
                    if let data = self.encode(frame) { self.push(connection.id, data) }
                }
            }
            return []
        default:
            return []
        }
    }

    /// The answer to the settings request `re`: the settings now, and what was refused or said.
    private static func settingsAnswer(_ service: SettingsService, re: UInt32, on connection: Connection,
                                       problem: SettingsProblem? = nil, message: String? = nil) -> EngineFrame {
        connection.frame(.settings(re: re, SettingsAnswer(revision: service.revision, document: service.document(),
                                                          problem: problem, message: message)))
    }

    /// Tells every client that has the settings that they changed (`settingsChanged`), on its queue.
    private func settingsChanged(_ revision: UInt64) {
        for connection in lock.guarded({ Array(connections.values) }) where connection.settings {
            connection.queue.async { [weak self] in
                guard let self, connection.isOpen else { return }
                if let data = self.encode(connection.frame(.settingsChanged(revision: revision))) { self.push(connection.id, data) }
            }
        }
    }

    /// Test mode (`#! settings <file>`): settings of their own, from `config` (a config file's text) in a folder of their
    /// own, with their keys in memory and their plugins in that folder: never the user's.
    public func useTestSettings(config: String) -> Bool {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("allinoneime-wire-settings-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("config.json")
            try Data(config.utf8).write(to: url)
            let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
            let service = SettingsService(store: SettingsStore(configURL: url), platform: .windows, library: library,
                                          secrets: .inMemory())
            // Keys from the test's store only, never the environment's.
            service.keySource = { APIKeys.hasKeychainKey(account: $0.rawValue) ? .keychain : .none }
            let previous = lock.guarded { () -> URL? in
                defer { testSettingsFolder = folder }
                return testSettingsFolder
            }
            if let previous { try? FileManager.default.removeItem(at: previous) }
            settings = service
            return true
        } catch {
            environment.log("test settings: \(error)")
            return false
        }
    }

    // MARK: - Sessions

    private func makeSession(_ sid: UInt32, _ record: SessionRecord, on connection: Connection) -> ComposerSession {
        let composer = environment.makeComposer(record.field, connection.peer)
        let queue = connection.queue
        let session = ComposerSession(
            sid: sid, field: record.field, peer: connection.peer, composer: composer, host: environment.host,
            allowsForeground: connection.capabilities.contains(Hello.allowForeground),
            enqueue: { queue.async($0) }, log: environment.log)
        session.pushOutputs = { [unowned self, unowned session, unowned connection] outputs in
            self.pushApply(outputs, for: session, on: connection)
        }
        return session
    }

    /// Outputs for a session the engine sends on its own (§7): only to the focused session, with its focus serial.
    /// While an earlier push to it is unacknowledged, a push of compositions only waits, and a later one replaces it.
    private func pushApply(_ outputs: [Output], for session: ComposerSession, on connection: Connection) {
        guard connection.isOpen, connection.focused == session.sid, session.isFocused else { return }
        let compositionsOnly = outputs.allSatisfy { if case .composition = $0 { return true } else { return false } }
        if compositionsOnly, connection.unacked.values.contains(where: { $0.sid == session.sid }) {
            connection.held[session.sid] = outputs
            return
        }
        if let held = connection.held.removeValue(forKey: session.sid) { send(held, for: session, on: connection) }
        send(outputs, for: session, on: connection)
    }

    private func send(_ outputs: [Output], for session: ComposerSession, on connection: Connection) {
        guard connection.isOpen else { return }
        let frame = connection.frame(.apply(sid: session.sid, focus: session.focusSerial, outputs: outputs))
        guard let data = encode(frame) else { return }
        connection.unacked[frame.id] = (session.sid, data.count)
        connection.unackedBytes += data.count
        guard connection.unacked.count <= configuration.unackedFrames, connection.unackedBytes <= configuration.unackedBytes else {
            environment.log("connection \(connection.id): \(connection.unacked.count) pushes unacknowledged: dropped")
            shut(connection)
            drop(connection.id)
            return
        }
        push(connection.id, data)
    }

    /// Closes the connection's sessions, with no outputs; the transport closes the connection.
    private func shut(_ connection: Connection) {
        connection.isOpen = false
        for record in connection.sessions.values { record.session?.close() }
        connection.sessions = [:]
        connection.focused = nil
        connection.held = [:]
    }

    // MARK: - Checks (§8)

    static func check(_ hello: Hello) -> String? {
        if hello.client.utf16.count > FieldLimits.app || hello.capabilities.count > FieldLimits.scopes {
            return "hello over its limits"
        }
        return nil
    }

    static func check(_ field: FieldInfo) -> String? {
        if field.app.utf16.count > FieldLimits.app { return "field.app over \(FieldLimits.app) units" }
        if field.process.utf16.count > FieldLimits.app { return "field.process over \(FieldLimits.app) units" }
        if field.layout.utf16.count > FieldLimits.app { return "field.layout over \(FieldLimits.app) units" }
        if field.scopes.count > FieldLimits.scopes { return "field.scopes over \(FieldLimits.scopes) entries" }
        return nil
    }

    func check(_ frame: KeyFrame) -> String? {
        if frame.key.text.utf16.count > FieldLimits.keyText { return "key.text over \(FieldLimits.keyText) units" }
        if (frame.key.textIgnoringModifiers?.utf16.count ?? 0) > FieldLimits.keyText {
            return "key.textIgnoringModifiers over \(FieldLimits.keyText) units"
        }
        return frame.ctx.flatMap(check)
    }

    func check(_ ctx: FieldContext) -> String? {
        if ctx.before.utf16.count > FieldLimits.before { return "ctx.before over \(FieldLimits.before) units" }
        if ctx.selText.utf16.count > configuration.limits.selection {
            return "ctx.selText over \(configuration.limits.selection) units"
        }
        if let sel = ctx.sel, sel.count != 2 { return "ctx.sel isn't [start, end]" }
        return nil
    }

    /// A decoding error, for the error's message: where and what, never a value.
    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case let .keyNotFound(key, context):
            let at = path(context)
            return "missing \(at.isEmpty ? "" : at + ".")\(key.stringValue)"
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            return "wrong type or value at \(path(context))"
        @unknown default:
            return "bad message"
        }
    }

    // MARK: - Encoding

    private func encodeAll(_ connection: Connection, _ frames: [EngineFrame]) -> [Data] {
        frames.compactMap(encode)
    }

    private func encode(_ frame: EngineFrame) -> Data? {
        do {
            let data = try WireJSON.encode(frame)
            guard data.count <= WireFrame.engineLimit else {
                environment.log("a \(frame.message.type) frame of \(data.count) bytes is over the limit: not sent")
                return nil
            }
            return data
        } catch {
            environment.log("a \(frame.message.type) frame couldn't be encoded")
            return nil
        }
    }

    // MARK: - Test control

    /// Runs one of the goldens' directives (§10, "Spec notes"): "advance <ms>" and "run tasks" (the clock must be a
    /// `ManualClock`), "click row <n>" (the focused session's panel), "idle" (only waits until every queue is idle).
    /// False for one it doesn't know.
    @discardableResult
    public func perform(_ directive: String, on id: ConnectionID) -> Bool {
        let words = directive.split(separator: " ").map(String.init)
        let clock = environment.clock as? ManualClock
        switch (words.first, words.count) {
        case ("advance", 2):
            guard let clock, let ms = Double(words[1]) else { return false }
            let target = clock.now + ms / 1000
            repeat {
                clock.advance(to: target)
                drainAll()
            } while clock.nextDue.map { $0 <= target } == true
            return true
        case ("run", 2) where words[1] == "tasks":
            guard let clock else { drainAll(); return true }
            drainAll()
            for _ in 0..<100_000 {
                guard let due = clock.nextDue else { break }
                clock.advance(to: due)
                drainAll()
            }
            return true
        case ("idle", 1):
            drainAll()
            return true
        case ("click", 3) where words[1] == "row":
            guard let row = Int(words[2]), let connection = lock.guarded({ connections[id] }) else { return false }
            connection.queue.sync {
                guard let sid = connection.focused, let session = connection.sessions[sid]?.session else { return }
                session.run(from: .click) { $0.choose(index: row) }
            }
            drainAll()
            return true
        default:
            return false
        }
    }

    private func drainAll() {
        for connection in lock.guarded({ Array(connections.values) }) { connection.queue.drain() }
    }

    private func testAnswer(_ test: TestFrame, on connection: Connection) -> Data {
        let directive = test.directive ?? ""
        let ok: Bool
        if directive.hasPrefix("settings "), let config = test.config {
            ok = useTestSettings(config: config)
        } else {
            ok = perform(directive, on: connection.id) || testDirective(directive, test)
        }
        let answer = TestFrame(v: connection.version ?? WireVersion.current, id: 0, re: test.id, type: TestFrame.type,
                               directive: nil, ok: ok)
        return (try? WireJSON.encode(answer)) ?? Data()
    }
}

/// `x-test`: a golden's directive over a real transport, in the engine's test mode only. Outside the ids' count on
/// both sides (its `id` is 0). `#! provider <file>` carries the file's fixture.
public struct TestFrame: Codable, Sendable {
    public static let type = "x-test"
    public var v: Int?
    public var id: UInt32
    public var re: UInt32?
    public var type: String
    public var directive: String?
    public var fixture: ScriptedProvider.Fixture?
    /// `#! settings <file>`: the file's text, the test's config (§12).
    public var config: String?
    public var ok: Bool?

    public init(v: Int? = WireVersion.current, id: UInt32 = 0, re: UInt32? = nil, type: String = TestFrame.type,
                directive: String?, fixture: ScriptedProvider.Fixture? = nil, config: String? = nil, ok: Bool? = nil) {
        self.v = v
        self.id = id
        self.re = re
        self.type = type
        self.directive = directive
        self.fixture = fixture
        self.config = config
        self.ok = ok
    }
}

/// Just enough of a frame to answer it when the rest can't be read.
struct Envelope: Decodable {
    var id: UInt32?
}

/// A session the client opened: its field, and its Composer once it has had the focus.
final class SessionRecord {
    var field: FieldInfo
    var session: ComposerSession?

    init(field: FieldInfo) { self.field = field }
}

/// One client connection. Its state is only touched on its queue (`isOpen` also from the transport's thread, `settings`
/// from any).
final class Connection: @unchecked Sendable {
    let id: ConnectionID
    let peer: WirePeer
    let queue: WireQueue
    /// The version agreed in `hello`; nil before it.
    var version: Int?
    var capabilities: Set<String> = []
    /// It has the settings (§12): it asked for them, may have them, and the engine has some. Set on its queue (`hello`),
    /// read on any thread (a change's notice, from the thread that made it).
    var settings: Bool {
        get { lock.guarded { hasSettings } }
        set { lock.guarded { hasSettings = newValue } }
    }
    var sessions: [UInt32: SessionRecord] = [:]
    var focused: UInt32?
    /// When the keys of the last second came.
    var keyTimes: [Double] = []
    /// Pushes not acknowledged yet: their session and size.
    var unacked: [UInt32: (sid: UInt32, bytes: Int)] = [:]
    var unackedBytes = 0
    /// Composition pushes waiting for the session's last push to be acknowledged: only the latest.
    var held: [UInt32: [Output]] = [:]
    private var lastID: UInt32 = 0
    private let lock = NSLock()
    private var open = true
    private var hasSettings = false

    init(id: ConnectionID, peer: WirePeer, queue: WireQueue) {
        self.id = id
        self.peer = peer
        self.queue = queue
    }

    var isOpen: Bool {
        get { lock.guarded { open } }
        set { lock.guarded { open = newValue } }
    }

    /// A frame with the connection's next id (each side counts its own from 1, §3).
    func frame(_ message: EngineMessage) -> EngineFrame {
        lastID += 1
        return EngineFrame(v: version ?? WireVersion.current, id: lastID, message)
    }

    func error(re: UInt32?, _ code: WireErrorCode, _ message: String, versions: [Int]? = nil) -> EngineFrame {
        frame(.error(re: re, code: code, message: message, versions: versions))
    }
}

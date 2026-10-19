#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import AllInOneIMEWire
import Foundation
import Testing
import WinSDK

/// Windows/, the package.
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// A folder of its own for a test, removed by the caller (`defer`).
func temporaryFolder(_ name: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("aio-engine-\(name)-\(GetCurrentProcessId())-\(UInt32.random(in: 0...UInt32.max))", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// A queue that runs its work only when told: the tests run it until what they wait for is there.
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

    func drain() {
        while let job = next() { job() }
    }

    private func next() -> (@Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return jobs.isEmpty ? nil : jobs.removeFirst()
    }

    var busyFor: Double { 0 }
}

/// The panel as the host asked for it: the last model shown, hidden or not, the notices.
final class RecordingPanel: PanelPresenter, @unchecked Sendable {
    private let lock = NSLock()
    private var _model: PanelModel?
    private var _owner: PanelOwner?
    private var _notices: [String] = []
    private var _caret: CaretRect?
    private var _shows = 0

    var model: PanelModel? { lock.lock(); defer { lock.unlock() }; return _model }
    var owner: PanelOwner? { lock.lock(); defer { lock.unlock() }; return _owner }
    var notices: [String] { lock.lock(); defer { lock.unlock() }; return _notices }
    var caret: CaretRect? { lock.lock(); defer { lock.unlock() }; return _caret }
    var shows: Int { lock.lock(); defer { lock.unlock() }; return _shows }

    func show(_ model: PanelModel, owner: PanelOwner, caret: CaretRect?) {
        lock.lock()
        _model = model
        _owner = owner
        _shows += 1
        if let caret { _caret = caret }
        lock.unlock()
    }

    func hide(owner: PanelOwner) {
        lock.lock()
        if _owner === owner { _model = nil }
        lock.unlock()
    }

    func move(owner: PanelOwner, caret: CaretRect) {
        lock.lock()
        _caret = caret
        lock.unlock()
    }

    func notice(_ text: String, owner: PanelOwner, caret: CaretRect?) {
        lock.lock()
        _notices.append(text)
        lock.unlock()
    }
}

/// The system as the host used it: nothing is opened or started, the clipboard is a string here.
final class RecordingSystem: SystemActions, @unchecked Sendable {
    private let lock = NSLock()
    private var _clipboard: String?
    private var _opened: [String] = []
    private var _launched: [[String]] = []
    var searchResults: [SearchResult] = []

    var clipboard: String? {
        get { lock.lock(); defer { lock.unlock() }; return _clipboard }
        set { lock.lock(); _clipboard = newValue; lock.unlock() }
    }
    var opened: [String] { lock.lock(); defer { lock.unlock() }; return _opened }
    var launched: [[String]] { lock.lock(); defer { lock.unlock() }; return _launched }

    func copy(_ text: String) -> Bool {
        clipboard = text
        return true
    }

    func readClipboard() -> String? { clipboard }

    func open(_ target: String) throws {
        lock.lock()
        _opened.append(target)
        lock.unlock()
    }

    func launchInTerminal(_ argv: [String]) throws {
        lock.lock()
        _launched.append(argv)
        lock.unlock()
    }

    func search(_ query: String) -> [SearchResult] { searchResults }
}

/// librime, started once per test process from ThirdParty's build, in a user folder of its own.
enum RimeFixture {
    static let userData = FileManager.default.temporaryDirectory.appendingPathComponent("aio-engine-rime-\(GetCurrentProcessId())")

    static let rime: Result<EngineRime, Error> = {
        let executable = packageRoot.appendingPathComponent(".build/debug/AllInOneIMEEngine.exe")
        guard let location = EngineRime.locate(executable: executable) else {
            return .failure(CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey:
                "no rime.dll and rime-data in ThirdParty: run Scripts/build-rime-data.sh"]))
        }
        try? FileManager.default.removeItem(at: userData)
        atexit { try? FileManager.default.removeItem(at: RimeFixture.userData) }
        let rime = EngineRime(location: location, userData: userData, log: { _ in })
        do {
            try rime.start()
        } catch {
            return .failure(error)
        }
        guard rime.waitUntilReady(timeout: 120) else {
            return .failure(CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "librime didn't deploy in 120 s"]))
        }
        return .success(rime)
    }()
}

/// A settings file with `json` in it.
func settingsFile(_ json: String, in folder: URL) throws -> EngineSettings {
    let url = folder.appendingPathComponent("config.json")
    try Data(json.utf8).write(to: url)
    return EngineSettings(url: url)
}

/// A client of the real wire server whose host is the engine's (`EngineHost`), its connection's queue run by hand:
/// what a DLL in Notepad sends, and what comes back.
final class EngineClient: @unchecked Sendable {
    let host: EngineHost
    let server: WireServer
    let panel: RecordingPanel
    let system: RecordingSystem
    let connection: ConnectionID
    private let lock = NSLock()
    private let queues = QueueBox()
    private var pushed: [Data] = []
    private(set) var nextID: UInt32 = 1
    var t: UInt64 = 10_000
    /// The document as the outputs left it (commits only).
    private(set) var committed = ""
    /// The composition as the outputs left it.
    private(set) var composition = ""

    init(settings: EngineSettings, rime: EngineRime?, converter: Converter? = nil, executable: String? = nil,
         field: FieldInfo = FieldInfo(app: "win:notepad.exe", process: "notepad.exe", scopes: [0], layout: "00000409")) {
        panel = RecordingPanel()
        system = RecordingSystem()
        var options = EngineHost.Options(system: system)
        options.settings = settings
        options.rime = rime
        options.panel = panel
        options.converter = converter
        if let executable { options.executable = executable }
        let host = EngineHost(options: options, log: { _ in })
        self.host = host
        let box = queues
        let environment = WireEnvironment(host: host, makeQueue: { _ in box.make() }, makeComposer: { host.makeComposer($0, $1) })
        server = WireServer(environment: environment)
        connection = server.connect(WirePeer(pid: GetCurrentProcessId(), integrity: .medium))!
        server.push = { [weak self] _, data in
            guard let self else { return }
            self.lock.lock()
            self.pushed.append(data)
            self.lock.unlock()
        }
        send(.hello(Hello(client: "test", capabilities: ["allowForeground"])))
        send(.open(sid: 1, field: field))
        send(.focus(sid: 1, focus: 1, field: nil))
    }

    func runQueues() {
        for queue in queues.all { queue.drain() }
    }

    /// The frames pushed since the last call.
    func takePushes() -> [EngineFrame] {
        lock.lock()
        let data = pushed
        pushed.removeAll()
        lock.unlock()
        return data.map { try! WireJSON.decode(EngineFrame.self, from: $0) }
    }

    /// The pushes so far applied to the document, each answered `applied` as a DLL does.
    func applyPushes() {
        for frame in takePushes() {
            guard case let .apply(_, _, outputs) = frame.message else { continue }
            apply(outputs)
            send(.applied(re: frame.id, ok: true, reason: nil, ctx: context))
        }
    }

    @discardableResult
    func send(_ message: ClientMessage) -> [EngineMessage] {
        let id = nextID
        nextID += 1
        let answers = server.receive(try! WireJSON.encode(ClientFrame(id: id, message)), on: connection)
        runQueues()
        let messages = answers.map { try! WireJSON.decode(EngineFrame.self, from: $0).message }
        for message in messages { if case let .result(_, _, outputs) = message { apply(outputs) } }
        return messages
    }

    /// Applies outputs to the document as a DLL would (commits and the composition).
    func apply(_ outputs: [Output]) {
        for output in outputs {
            switch output {
            case let .commit(text, _, _, _):
                committed += text
                composition = ""
            case let .composition(text, _, _, _):
                composition = text
            default:
                break
            }
        }
    }

    /// A key-down; its result's outputs.
    @discardableResult
    func press(vk: UInt16, scan: UInt16, text: String, ignoringModifiers: String? = nil, modifiers: Modifiers = []) -> [Output] {
        t += 120
        let key = WireKey(vk: vk, scan: scan, text: text, textIgnoringModifiers: ignoringModifiers ?? text, modifiers: modifiers)
        guard case let .result(_, _, outputs) = send(.keyDown(KeyFrame(sid: 1, t: t, key: key, ctx: context))).first else { return [] }
        return outputs
    }

    /// What the DLL would say of the document.
    var context: FieldContext {
        let units = committed.utf16.count
        return FieldContext(sel: [units, units], before: String(committed.suffix(32)),
                            comp: composition.isEmpty ? nil : composition.utf16.count)
    }

    /// A tap of the left Shift key: its key-down and key-up, nothing between.
    func tapShift() {
        t += 120
        let down = WireKey(vk: 0xA0, scan: 0x2A, modifiers: [.shift, .leftShift])
        send(.keyDown(KeyFrame(sid: 1, t: t, key: down, ctx: context)))
        t += 80
        let up = WireKey(vk: 0xA0, scan: 0x2A)
        send(.keyUp(KeyFrame(sid: 1, t: t, key: up, ctx: context)))
    }

    /// Each character's key on a US layout (Shift around the shifted ones); the last one's outputs.
    @discardableResult
    func type(_ text: String) -> [Output] {
        var last: [Output] = []
        for c in text {
            let key = Self.usKey(c)!
            last = press(vk: key.vk, scan: key.scan, text: String(c), modifiers: key.shift ? [.shift, .leftShift] : [])
        }
        return last
    }

    func enter() -> [Output] { press(vk: 0x0D, scan: 0x1C, text: "\r") }
    func space() -> [Output] { press(vk: 0x20, scan: 0x39, text: " ") }
    func escape() -> [Output] { press(vk: 0x1B, scan: 0x01, text: "\u{1B}") }

    /// Runs the queue (and the pushes it makes) until `condition` holds, for up to `timeout` seconds.
    func wait(_ timeout: TimeInterval = 10, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            runQueues()
            applyPushes()
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        } while Date() < deadline
        return condition()
    }

    var composer: Composer { host.liveSessions.first!.composer }

    static func usKey(_ c: Character) -> (vk: UInt16, scan: UInt16, shift: Bool)? {
        let letters: [UInt16] = [0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26, 0x32,
                                 0x31, 0x18, 0x19, 0x10, 0x13, 0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D, 0x15, 0x2C]
        if let ascii = c.asciiValue, c.isLetter {
            let lower = ascii | 0x20
            return (UInt16(lower - 0x20), letters[Int(lower - 0x61)], c.isUppercase)
        }
        if let digit = c.wholeNumberValue, c.isASCII {
            return (UInt16(0x30 + digit), digit == 0 ? 0x0B : UInt16(digit + 1), false)
        }
        switch c {
        case " ": return (0x20, 0x39, false)
        case "@": return (0x32, 0x03, true)
        case ".": return (0xBE, 0x34, false)
        case ",": return (0xBC, 0x33, false)
        case "(": return (0x39, 0x0A, true)
        case ")": return (0x30, 0x0B, true)
        case "+": return (0xBB, 0x0D, true)
        case "*": return (0x38, 0x09, true)
        default: return nil
        }
    }
}

/// The connections' queues, run by hand.
final class QueueBox: @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [ManualQueue] = []

    var all: [ManualQueue] { lock.lock(); defer { lock.unlock() }; return queues }

    func make() -> WireQueue {
        let queue = ManualQueue()
        lock.lock()
        queues.append(queue)
        lock.unlock()
        return queue
    }
}

/// The stub provider (Scripts/stub-provider.py) on a port of its own: the AI tests' only server. Never a paid API.
final class StubProvider {
    let process: Process
    let port: Int
    let log: URL
    let key: String

    init(folder: URL, key: String = "stub-key", versions: String = "Hello there.|Hi!|Greetings.", status: Int = 200) throws {
        let portFile = folder.appendingPathComponent("stub.port")
        log = folder.appendingPathComponent("stub.log")
        self.key = key
        let script = packageRoot.appendingPathComponent("Scripts/stub-provider.py")
        process = Process()
        process.executableURL = try Self.python()
        process.arguments = ["-I", script.path, "--port-file", portFile.path, "--log", log.path, "--key", key,
                             "--versions", versions, "--status", String(status), "--lifetime", "300"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(20)
        var found: Int?
        while found == nil, Date() < deadline {
            found = (try? String(contentsOf: portFile, encoding: .utf8)).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if found == nil { Thread.sleep(forTimeInterval: 0.05) }
        }
        guard let found else {
            process.terminate()
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "the stub provider didn't start"])
        }
        port = found
    }

    deinit { if process.isRunning { process.terminate() } }

    var baseURL: String { "http://127.0.0.1:\(port)" }

    /// The requests it got, one JSON object each.
    var requests: [[String: Any]] {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
    }

    /// Python: on PATH as python.exe (python.org's), else the launcher.
    static func python() throws -> URL {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ProcessInfo.processInfo.environment["Path"] ?? ""
        for folder in path.split(separator: ";") {
            for name in ["python.exe", "py.exe"] {
                let candidate = URL(fileURLWithPath: String(folder)).appendingPathComponent(name)
                // The Store's "python.exe" in WindowsApps is a stub that opens the Store.
                if FileManager.default.fileExists(atPath: candidate.path), !candidate.path.contains("WindowsApps") { return candidate }
            }
        }
        throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "no python.exe on PATH for the stub provider"])
    }
}
#endif

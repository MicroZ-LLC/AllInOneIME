#if os(Windows)
import AllInOneIMEWire
import Foundation
import WinSDK

/// The engine's end of the pipe (§2.1): `\\.\pipe\AllInOneIME-<UserSID>-v1`, created with the protocol's security
/// descriptor, `FILE_FLAG_FIRST_PIPE_INSTANCE` on the first instance (the engine exits when that fails: something else
/// holds the name), message mode, remote clients refused, 64 KiB buffers and overlapped I/O. At least
/// `pendingInstances` instances wait in `ConnectNamedPipe` at any time: each one that a client takes is replaced at
/// once. A client is served only if it is in the engine's session and its process runs as the engine's user; its
/// integrity level and AppContainer flag become the connection's trust (§8), its executable and AUMID its `app`.
///
/// Each connection has one thread, which reads its frames and hands them to the `WireServer`. Everything the server
/// sends goes out one write at a time; its configuration should have `answersThroughPush`, so that answers and pushes
/// are written in the order the connection's queue made them (answers it returns are written after the fact).
public final class PipeListener: @unchecked Sendable {
    public struct Options: Sendable {
        /// Instances kept waiting for a client (§2.1: at least 4).
        public var pendingInstances = 4
        /// The pipe's in and out buffers.
        public var bufferSize: DWORD = 64 * 1024
        /// How long a write may wait for a client that doesn't read before the connection is dropped, in ms. Writes
        /// happen on the connection's queue: well under the watchdog's 2 s, so that a client that stops reading loses
        /// its connection instead of stalling the engine.
        public var writeTimeout: DWORD = 500

        public init() {}
    }

    public let server: WireServer
    public let pipeName: String
    public let sid: String
    public let options: Options
    let session: DWORD
    let log: @Sendable (String) -> Void

    private let attributes: UnsafeMutablePointer<SECURITY_ATTRIBUTES>
    private let lock = NSLock()
    private var connected: [ConnectionID: PipeChannel] = [:]
    private var waiting: [ObjectIdentifier: PipeChannel] = [:]
    private var stopped = false

    /// Fails if the security descriptor can't be built.
    public init(server: WireServer, sid: String, options: Options = Options(),
                log: @escaping @Sendable (String) -> Void = { _ in }) throws {
        self.server = server
        self.sid = sid
        self.options = options
        self.log = log
        pipeName = PipeNames.pipe(sid: sid)
        session = Win32.currentSession()
        var descriptor: PSECURITY_DESCRIPTOR?
        let made = PipeNames.sddl(sid: sid).withWide {
            ConvertStringSecurityDescriptorToSecurityDescriptorW($0, DWORD(SDDL_REVISION_1), &descriptor, nil)
        }
        guard made, let descriptor else { throw Win32Error("ConvertStringSecurityDescriptorToSecurityDescriptorW") }
        attributes = .allocate(capacity: 1)
        attributes.initialize(to: SECURITY_ATTRIBUTES(nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size),
                                                      lpSecurityDescriptor: descriptor, bInheritHandle: false))
        server.push = { [weak self] id, data in self?.write(data, to: id) }
        server.drop = { [weak self] id in self?.channel(id)?.shutdown() }
    }

    /// Creates the instances and starts waiting for clients. Throws when the first instance can't be created, as when
    /// another process holds the pipe's name.
    public func start() throws {
        let first = try makeInstance(first: true)
        wait(on: first)
        for _ in 1..<max(options.pendingInstances, 1) { wait(on: try makeInstance(first: false)) }
    }

    /// Closes every connection and stops waiting for new ones.
    public func stop() {
        let channels = lock.locked {
            stopped = true
            return Array(connected.values) + Array(waiting.values)
        }
        for channel in channels { channel.shutdown() }
    }

    /// The instances waiting for a client now.
    public var waitingCount: Int { lock.locked { waiting.count } }

    // MARK: - Instances

    private func makeInstance(first: Bool) throws -> HANDLE {
        // PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED (| FILE_FLAG_FIRST_PIPE_INSTANCE)
        let openMode: DWORD = 0x0000_0003 | 0x4000_0000 | (first ? 0x0008_0000 : 0)
        // PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS
        let pipeMode: DWORD = 0x4 | 0x2 | 0x0 | 0x8
        let handle = pipeName.withWide {
            CreateNamedPipeW($0, openMode, pipeMode, DWORD(PIPE_UNLIMITED_INSTANCES), options.bufferSize, options.bufferSize,
                             0, attributes)
        }
        guard let handle, handle != invalidHandle else { throw Win32Error(first ? "CreateNamedPipeW (first instance)" : "CreateNamedPipeW") }
        return handle
    }

    /// A thread that waits for a client on `handle`, replaces the instance once one comes, then serves it.
    private func wait(on handle: HANDLE) {
        let channel = PipeChannel(handle: handle)
        let key = ObjectIdentifier(channel)
        lock.locked { waiting[key] = channel }
        let thread = Thread { [self] in
            do {
                try channel.waitForClient()
            } catch {
                lock.locked { waiting[key] = nil }
                channel.release()
                if !isStopped {
                    log("pipe: waiting for a client failed (\(error)): a new instance")
                    replace()
                }
                return
            }
            lock.locked { waiting[key] = nil }
            if !isStopped { replace() }
            serve(channel)
        }
        thread.name = "allinoneime.pipe"
        thread.start()
    }

    private var isStopped: Bool { lock.locked { stopped } }

    private func replace() {
        do {
            wait(on: try makeInstance(first: false))
        } catch {
            log("pipe: \(error)")
        }
    }

    // MARK: - Connections

    private func channel(_ id: ConnectionID) -> PipeChannel? { lock.locked { connected[id] } }

    private func write(_ body: Data, to id: ConnectionID) {
        guard let channel = channel(id) else { return }
        do {
            try channel.write(WireFrame.frame(body), timeout: options.writeTimeout)
        } catch {
            log("connection \(id): write failed (\(error)): closing")
            channel.shutdown()
        }
    }

    private func serve(_ channel: PipeChannel) {
        defer { channel.release() }
        guard let peer = check(channel.handle) else { return }
        guard let id = server.connect(peer) else { return }
        let added = lock.locked { () -> Bool in
            guard !stopped else { return false }
            connected[id] = channel
            return true
        }
        guard added else {
            server.disconnect(id)
            return
        }
        log("connection \(id): pid \(peer.pid ?? 0), \(peer.integrity), \(peer.appContainer ? "AppContainer, " : "")"
            + (peer.trusted ? "trusted" : "untrusted"))
        defer {
            lock.locked { connected[id] = nil }
            server.disconnect(id)
            log("connection \(id): closed")
        }
        let limit = WireFrame.clientLimit + WireFrame.prefixSize
        while true {
            let answers: [Data]
            do {
                let message = try channel.readMessage(limit: limit)
                do {
                    answers = server.receive(try WireFrame.body(ofMessage: message, limit: WireFrame.clientLimit), on: id)
                } catch {
                    answers = server.refuse(error, on: id)
                }
            } catch PipeChannel.Failure.tooLarge(let size) {
                answers = server.refuse(.tooLarge(size - WireFrame.prefixSize), on: id)
            } catch {
                return  // the client is gone (§4 "Disconnects")
            }
            for answer in answers { write(answer, to: id) }
            if !server.isOpen(id) {
                // A fatal error (§3): the error is written, then the connection closes. The client is given a moment
                // to read it and close its end; what it sends meanwhile is ignored.
                linger(channel, ms: 1000)
                return
            }
        }
    }

    /// Reads and drops what the client sends until it closes its end, for at most `ms`.
    private func linger(_ channel: PipeChannel, ms: Int) {
        let deadline = Date().addingTimeInterval(Double(ms) / 1000)
        while case let left = deadline.timeIntervalSinceNow, left > 0 {
            do {
                _ = try channel.readMessage(limit: WireFrame.clientLimit + WireFrame.prefixSize, timeout: DWORD(left * 1000) + 1)
            } catch PipeChannel.Failure.tooLarge {
                continue
            } catch {
                return
            }
        }
    }

    // MARK: - The client check (§2.1)

    /// Who the client is, if it may connect: in this session, and its process run by this user.
    private func check(_ handle: HANDLE) -> WirePeer? {
        var clientSession: ULONG = 0
        guard GetNamedPipeClientSessionId(handle, &clientSession) else {
            log("pipe: refused a client: its session is unknown (error \(GetLastError()))")
            return nil
        }
        guard clientSession == session else {
            log("pipe: refused a client from session \(clientSession) (the engine's is \(session))")
            return nil
        }
        var pid: ULONG = 0
        guard GetNamedPipeClientProcessId(handle, &pid) else {
            log("pipe: refused a client: its process is unknown (error \(GetLastError()))")
            return nil
        }
        let token: TokenFacts
        do {
            token = try Win32.token(ofProcess: pid)
        } catch {
            log("pipe: refused process \(pid): \(error)")
            return nil
        }
        guard token.sid.caseInsensitiveCompare(sid) == .orderedSame else {
            log("pipe: refused process \(pid): another user's")
            return nil
        }
        let integrity: WirePeer.Integrity
        switch token.integrityRID {
        case ..<TokenFacts.lowRID: integrity = .untrusted
        case ..<TokenFacts.mediumRID: integrity = .low
        case ..<TokenFacts.highRID: integrity = .medium
        case ..<TokenFacts.systemRID: integrity = .high
        default: integrity = .system
        }
        // The engine's own `app` and `process` (§4): the executable's name, lowercased (Windows' names aren't
        // case-sensitive), and a packaged app's AUMID.
        let process = Win32.imagePath(ofProcess: pid).flatMap { $0.split(separator: "\\").last.map { $0.lowercased() } }
        let app = Win32.appUserModelID(ofProcess: pid).map { "win:" + $0 } ?? process.map { "win:" + $0 }
        return WirePeer(pid: pid, process: process, app: app, integrity: integrity, appContainer: token.appContainer)
    }
}
#endif

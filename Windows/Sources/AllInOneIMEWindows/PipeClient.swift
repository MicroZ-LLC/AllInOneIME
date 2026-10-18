#if os(Windows)
import AllInOneIMEWire
import Foundation
import WinSDK

/// A client's end of the engine's pipe, as the DLL opens it (§2.1): message mode, overlapped, the server checked
/// before `hello`. The replay CLI's (`allinoneime-cli wire-replay`); the TSF DLL has its own in C++.
public final class PipeClient: @unchecked Sendable {
    public let channel: PipeChannel
    public let name: String

    private init(channel: PipeChannel, name: String) {
        self.channel = channel
        self.name = name
    }

    /// Opens the pipe `name`, waiting for it to appear for up to `timeout` seconds (`ERROR_FILE_NOT_FOUND`: the engine
    /// is starting) and for an instance to be free (`ERROR_PIPE_BUSY`: `WaitNamedPipe` 100 ms, again).
    public static func connect(name: String, timeout: Double) throws -> PipeClient {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            // GENERIC_READ | GENERIC_WRITE; OPEN_EXISTING; FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT |
            // SECURITY_IDENTIFICATION (the engine may identify the client, never impersonate it).
            let handle = name.withWide {
                CreateFileW($0, 0x8000_0000 | 0x4000_0000, 0, nil, 3, 0x4000_0000 | 0x0010_0000 | 0x0001_0000, nil)
            }
            if let handle, handle != invalidHandle {
                var mode: DWORD = 0x2  // PIPE_READMODE_MESSAGE
                guard SetNamedPipeHandleState(handle, &mode, nil, nil) else {
                    let error = Win32Error("SetNamedPipeHandleState")
                    CloseHandle(handle)
                    throw error
                }
                return PipeClient(channel: PipeChannel(handle: handle), name: name)
            }
            let code = GetLastError()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Win32Error("CreateFileW", code: code) }
            switch code {
            case Win32Code.pipeBusy: _ = name.withWide { WaitNamedPipeW($0, 100) }
            case Win32Code.fileNotFound: _ = SwitchToThread()
            default: throw Win32Error("CreateFileW", code: code)
            }
        }
    }

    // MARK: - The server check (§2.1)

    /// What the client finds out about the server before `hello`.
    public struct ServerFacts: Sendable {
        public var session: DWORD?
        public var pid: DWORD?
        /// The pipe object's owner and mandatory label RID (`GetSecurityInfo`).
        public var owner: String?
        public var labelRID: DWORD?
        /// The server process's token.
        public var token: TokenFacts?
    }

    public func serverFacts() -> ServerFacts {
        var facts = ServerFacts()
        var session: ULONG = 0
        if GetNamedPipeServerSessionId(channel.handle, &session) { facts.session = session }
        var pid: ULONG = 0
        if GetNamedPipeServerProcessId(channel.handle, &pid) {
            facts.pid = pid
            facts.token = try? Win32.token(ofProcess: pid)
        }
        var owner: PSID?
        var sacl: PACL?
        var descriptor: PSECURITY_DESCRIPTOR?
        let information = SECURITY_INFORMATION(OWNER_SECURITY_INFORMATION) | SECURITY_INFORMATION(LABEL_SECURITY_INFORMATION)
        if GetSecurityInfo(channel.handle, SE_KERNEL_OBJECT, information, &owner, nil, nil, &sacl, &descriptor) == 0 {
            facts.owner = try? Win32.sidString(owner)
            facts.labelRID = sacl.flatMap(Self.labelRID)
            LocalFree(descriptor)
        }
        return facts
    }

    /// The RID of a SACL's mandatory label, if it has one.
    static func labelRID(_ sacl: PACL) -> DWORD? {
        for index in 0..<DWORD(sacl.pointee.AceCount) {
            var ace: LPVOID?
            guard GetAce(sacl, index, &ace), let ace else { continue }
            let header = ace.assumingMemoryBound(to: ACE_HEADER.self).pointee
            guard header.AceType == 0x11 else { continue }  // SYSTEM_MANDATORY_LABEL_ACE_TYPE
            let label = ace.assumingMemoryBound(to: SYSTEM_MANDATORY_LABEL_ACE.self)
            let sid = UnsafeMutableRawPointer(mutating: label).advanced(by: MemoryLayout<SYSTEM_MANDATORY_LABEL_ACE>.offset(of: \.SidStart)!)
            let count = GetSidSubAuthorityCount(sid).pointee
            guard count > 0 else { continue }
            return GetSidSubAuthority(sid, DWORD(count - 1)).pointee
        }
        return nil
    }

    /// The check's failures (empty: the server is the user's engine): the server in this session, its process run by
    /// this user at medium integrity or higher, and the pipe owned by this user.
    ///
    /// The spec (§2.1) asks for the pipe's own label to be medium or higher, but its SDDL gives the pipe a low label (so
    /// that low-integrity clients can write): the server process's integrity is checked instead (Spec notes).
    public func checkServer(sid: String) -> [String] {
        let facts = serverFacts()
        var problems: [String] = []
        if facts.session != Win32.currentSession() { problems.append("the server is in another session") }
        if let token = facts.token {
            if token.sid.caseInsensitiveCompare(sid) != .orderedSame { problems.append("the server runs as another user") }
            if token.integrityRID < TokenFacts.mediumRID { problems.append("the server runs below medium integrity") }
        } else {
            problems.append("the server's process can't be read")
        }
        if facts.owner?.caseInsensitiveCompare(sid) != .orderedSame { problems.append("the pipe is owned by \(facts.owner ?? "nobody known")") }
        return problems
    }

    // MARK: - Frames

    /// Sends one frame: `body` with its length prefix, as one pipe message.
    public func send(_ body: Data, timeout: DWORD = 5000) throws {
        try channel.write(WireFrame.frame(body), timeout: timeout)
    }

    /// The next frame's body, waiting at most `timeout` ms.
    public func receive(timeout: DWORD) throws -> Data {
        let message = try channel.readMessage(limit: WireFrame.engineLimit + WireFrame.prefixSize, timeout: timeout)
        return try WireFrame.body(ofMessage: message, limit: WireFrame.engineLimit)
    }

    public func close() { channel.release() }
}
#endif

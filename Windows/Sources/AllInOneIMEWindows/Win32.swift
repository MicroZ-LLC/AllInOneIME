#if os(Windows)
import WinSDK

// What the pipe's two ends share of Win32: wide strings, errors, handles, and who a process is (its user, integrity
// level, AppContainer flag, executable and AUMID).

/// A Win32 failure: the call and `GetLastError()`.
public struct Win32Error: Error, CustomStringConvertible, Sendable {
    public var call: String
    public var code: DWORD

    public init(_ call: String, code: DWORD = GetLastError()) {
        self.call = call
        self.code = code
    }

    public var description: String { "\(call) failed: error \(code)" }
}

/// The error codes the pipe code tells apart.
public enum Win32Code {
    public static let fileNotFound: DWORD = 2
    public static let accessDenied: DWORD = 5
    public static let brokenPipe: DWORD = 109
    public static let alreadyExists: DWORD = 183
    public static let pipeBusy: DWORD = 231
    public static let noData: DWORD = 232
    public static let pipeNotConnected: DWORD = 233
    public static let moreData: DWORD = 234
    public static let pipeConnected: DWORD = 535
    public static let operationAborted: DWORD = 995
    public static let ioPending: DWORD = 997
    public static let semaphoreTimeout: DWORD = 121
}

/// `INVALID_HANDLE_VALUE`, which Swift doesn't import.
nonisolated(unsafe) public let invalidHandle = HANDLE(bitPattern: -1)!

extension String {
    /// `self` as a NUL-terminated UTF-16 string for the duration of `body`.
    func withWide<T>(_ body: (UnsafePointer<WCHAR>) throws -> T) rethrows -> T {
        try withCString(encodedAs: UTF16.self) { try body($0) }
    }

    /// A NUL-terminated UTF-16 string.
    init(wide pointer: UnsafePointer<WCHAR>) {
        self = String(decodingCString: pointer, as: UTF16.self)
    }
}

/// An access token's facts that the pipe checks (§2.1, §8).
public struct TokenFacts: Equatable, Sendable {
    /// The user, as "S-1-5-21-…".
    public var sid: String
    /// The mandatory label's RID: 0x1000 low, 0x2000 medium, 0x3000 high, 0x4000 system.
    public var integrityRID: DWORD
    public var appContainer: Bool

    public static let lowRID: DWORD = 0x1000
    public static let mediumRID: DWORD = 0x2000
    public static let highRID: DWORD = 0x3000
    public static let systemRID: DWORD = 0x4000
}

public enum Win32 {
    /// The current process's token facts.
    public static func currentToken() throws -> TokenFacts {
        var token: HANDLE?
        guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token), let token else {
            throw Win32Error("OpenProcessToken")
        }
        defer { CloseHandle(token) }
        return try facts(of: token)
    }

    /// The token facts of process `pid`, if it can be opened.
    public static func token(ofProcess pid: DWORD) throws -> TokenFacts {
        guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else {
            throw Win32Error("OpenProcess")
        }
        defer { CloseHandle(process) }
        var token: HANDLE?
        guard OpenProcessToken(process, DWORD(TOKEN_QUERY), &token), let token else { throw Win32Error("OpenProcessToken") }
        defer { CloseHandle(token) }
        return try facts(of: token)
    }

    /// The current user's SID string, for the pipe's and the mutex's names and the SDDL.
    public static func currentUserSID() throws -> String { try currentToken().sid }

    /// The session the current process runs in.
    public static func currentSession() -> DWORD {
        var session: DWORD = 0
        _ = ProcessIdToSessionId(GetCurrentProcessId(), &session)
        return session
    }

    static func facts(of token: HANDLE) throws -> TokenFacts {
        let user = try information(token, TokenUser)
        let sid = try user.withUnsafeBytes { raw -> String in
            let tokenUser = raw.baseAddress!.assumingMemoryBound(to: TOKEN_USER.self)
            return try sidString(tokenUser.pointee.User.Sid)
        }
        let label = try information(token, TokenIntegrityLevel)
        let rid = label.withUnsafeBytes { raw -> DWORD in
            let mandatory = raw.baseAddress!.assumingMemoryBound(to: TOKEN_MANDATORY_LABEL.self)
            guard let labelSid = mandatory.pointee.Label.Sid else { return 0 }
            let count = GetSidSubAuthorityCount(labelSid).pointee
            guard count > 0 else { return 0 }
            return GetSidSubAuthority(labelSid, DWORD(count - 1)).pointee
        }
        var isAppContainer: DWORD = 0
        var size: DWORD = 0
        if !GetTokenInformation(token, TokenIsAppContainer, &isAppContainer, DWORD(MemoryLayout<DWORD>.size), &size) {
            isAppContainer = 0
        }
        return TokenFacts(sid: sid, integrityRID: rid, appContainer: isAppContainer != 0)
    }

    /// `GetTokenInformation`'s bytes for `kind`.
    static func information(_ token: HANDLE, _ kind: TOKEN_INFORMATION_CLASS) throws -> [UInt8] {
        var size: DWORD = 0
        _ = GetTokenInformation(token, kind, nil, 0, &size)
        guard size > 0 else { throw Win32Error("GetTokenInformation") }
        var bytes = [UInt8](repeating: 0, count: Int(size))
        let ok = bytes.withUnsafeMutableBytes { GetTokenInformation(token, kind, $0.baseAddress, size, &size) }
        guard ok else { throw Win32Error("GetTokenInformation") }
        return bytes
    }

    /// "S-1-5-…" for a SID.
    public static func sidString(_ sid: PSID?) throws -> String {
        var text: LPWSTR?
        guard let sid, ConvertSidToStringSidW(sid, &text), let text else { throw Win32Error("ConvertSidToStringSidW") }
        defer { LocalFree(text) }
        return String(wide: text)
    }

    /// The full path of process `pid`'s executable.
    public static func imagePath(ofProcess pid: DWORD) -> String? {
        guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else { return nil }
        defer { CloseHandle(process) }
        var buffer = [WCHAR](repeating: 0, count: 32768)
        var size = DWORD(buffer.count)
        guard QueryFullProcessImageNameW(process, 0, &buffer, &size) else { return nil }
        return String(decoding: buffer[0..<Int(size)], as: UTF16.self)
    }

    /// Process `pid`'s Application User Model ID, if it is a packaged app.
    public static func appUserModelID(ofProcess pid: DWORD) -> String? {
        guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else { return nil }
        defer { CloseHandle(process) }
        var length: UINT32 = 0
        // APPMODEL_ERROR_NO_APPLICATION (15703) for a process that isn't packaged; ERROR_INSUFFICIENT_BUFFER (122) else.
        guard GetApplicationUserModelId(process, &length, nil) == 122, length > 0 else { return nil }
        var buffer = [WCHAR](repeating: 0, count: Int(length))
        guard GetApplicationUserModelId(process, &length, &buffer) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
    }

    /// Seconds on the high-resolution counter (`QueryPerformanceCounter`), for measuring: `ProcessInfo`'s uptime moves
    /// in steps of the system timer (15.6 ms) on Windows.
    public static func preciseNow() -> Double {
        var counter = LARGE_INTEGER()
        var frequency = LARGE_INTEGER()
        QueryPerformanceCounter(&counter)
        QueryPerformanceFrequency(&frequency)
        return Double(counter.QuadPart) / Double(frequency.QuadPart)
    }
}

/// The names both ends derive from the user's SID (§2.1, §2.5).
public enum PipeNames {
    /// `\\.\pipe\AllInOneIME-<UserSID>-v1`: `-v1` is the framing's generation (§2.2), not the messages' version.
    public static func pipe(sid: String) -> String { #"\\.\pipe\AllInOneIME-"# + sid + "-v1" }

    /// The engine's single-instance mutex, `Local\AllInOneIME-Engine-<SID>`.
    public static func mutex(sid: String) -> String { #"Local\AllInOneIME-Engine-"# + sid }

    /// The pipe's security descriptor: the user as its owner, the user and SYSTEM full access, AppContainers (all and
    /// restricted) read/write, and a low mandatory label so that low-integrity processes can write. The owner is named
    /// because the DLL's server check (§2.1) requires it to be the user, and without it the owner is the token's
    /// default, which is Administrators for an elevated engine.
    public static func sddl(sid: String) -> String {
        "O:\(sid)D:P(A;;GA;;;\(sid))(A;;GA;;;SY)(A;;GRGW;;;AC)(A;;GRGW;;;S-1-15-2-2)S:(ML;;NW;;;LW)"
    }
}
#endif

#if os(Windows)
import Foundation

extension NSLock {
    /// `body` with the lock held.
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
#endif

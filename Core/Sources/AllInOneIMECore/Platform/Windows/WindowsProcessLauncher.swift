#if os(Windows)
import Foundation
import WinSDK

/// Windows' own: `CreateProcessW`, each program in a job object of its own, so that stopping it (`terminate`, `kill`:
/// `TerminateJobObject`) stops what it started too, as a process group does on macOS and Linux. The job is given at
/// creation (`PROC_THREAD_ATTRIBUTE_JOB_LIST`, Windows 10 1607 and later; before, the program starts suspended and is
/// put in it before it runs), and kills what is in it when it is closed (`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`): when the
/// input method ends, however it ends, nothing it started is left running. What a program started in the background
/// and left running outlives it as on the Mac: once the program is let go of (`WindowsProcess` released), its job no
/// longer kills on closing.
///
/// What runs a file (cmd.exe for a batch file, an interpreter for a script) and how its command line is written are
/// `WindowsPrograms`' and `WindowsCommandLine`'s. The program gets the three standard handles asked for and no other
/// (`PROC_THREAD_ATTRIBUTE_HANDLE_LIST`: not another program's pipe, whose end it would keep open), and no console
/// window.
public struct WindowsProcessLauncher: ProcessLauncher {
    public init() {}

    public var canLaunch: Bool { true }
    public var environment: [String: String] { ProcessInfo.processInfo.environment }
    public var loginEnvironment: [String: String] { ProcessInfo.processInfo.environment }

    /// Whether `program` is a program Windows starts, or a script whose interpreter is installed.
    public func isRunnable(_ program: URL) -> Bool {
        (try? WindowsPrograms.invocation(of: program, arguments: [], environment: nil)) != nil
    }

    public func launch(_ spec: LaunchSpec) throws -> any LaunchedProcess {
        let invocation = try WindowsPrograms.invocation(of: spec.executable, arguments: spec.arguments, environment: spec.environment)
        let environment = try spec.environment.map(Self.environmentBlock)
        let directory = spec.directory.map(WindowsPrograms.windowsPath)

        // The job, killing what is in it when it is closed.
        guard let job = CreateJobObjectW(nil, nil) else { throw Self.lastError("CreateJobObjectW") }
        var limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
        limits.BasicLimitInformation.LimitFlags = DWORD(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
        guard SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits,
                                      DWORD(MemoryLayout<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>.size)) else {
            let error = Self.lastError("SetInformationJobObject")
            CloseHandle(job)
            throw error
        }

        // The standard handles, as inheritable copies of the caller's (closed once the program has its own).
        var copies: [HANDLE] = []
        defer { copies.forEach { CloseHandle($0) } }
        func handle(_ io: ProcessIO, _ standard: DWORD, input: Bool) throws -> HANDLE? {
            let source: HANDLE?
            switch io {
            case .inherit: source = GetStdHandle(standard)
            case .null: return try Self.nullDevice(&copies)
            case let .pipe(pipe): source = (input ? pipe.fileHandleForReading : pipe.fileHandleForWriting)._handle
            case let .file(file): source = file._handle
            }
            guard let source, source != INVALID_HANDLE_VALUE else { return nil }  // none to give (a GUI program's own)
            var copy: HANDLE?
            guard DuplicateHandle(GetCurrentProcess(), source, GetCurrentProcess(), &copy, 0, true, DWORD(DUPLICATE_SAME_ACCESS)),
                  let copy else { throw Self.lastError("DuplicateHandle") }
            copies.append(copy)
            return copy
        }
        let standardHandles: [HANDLE?]
        do {
            standardHandles = [try handle(spec.standardInput, STD_INPUT_HANDLE, input: true),
                               try handle(spec.standardOutput, STD_OUTPUT_HANDLE, input: false),
                               try handle(spec.standardError, STD_ERROR_HANDLE, input: false)]
        } catch {
            CloseHandle(job)
            throw error
        }
        let inherited = standardHandles.compactMap { $0 }

        // What the program is started with: those handles alone, and the job.
        let attributes = AttributeList(count: 2)
        let handleList = UnsafeMutablePointer<HANDLE?>.allocate(capacity: max(inherited.count, 1))
        let jobList = UnsafeMutablePointer<HANDLE?>.allocate(capacity: 1)
        defer {
            handleList.deallocate()
            jobList.deallocate()
        }
        for (index, handle) in inherited.enumerated() { handleList[index] = handle }
        jobList.pointee = job
        if !inherited.isEmpty {
            guard attributes.update(Self.handleListAttribute, handleList, size: inherited.count * MemoryLayout<HANDLE>.size) else {
                CloseHandle(job)
                throw Self.lastError("UpdateProcThreadAttribute")
            }
        }
        let jobAtCreation = attributes.update(Self.jobListAttribute, jobList, size: MemoryLayout<HANDLE>.size)

        var startup = STARTUPINFOEXW()
        startup.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        startup.StartupInfo.dwFlags = DWORD(STARTF_USESTDHANDLES)
        startup.StartupInfo.hStdInput = standardHandles[0]
        startup.StartupInfo.hStdOutput = standardHandles[1]
        startup.StartupInfo.hStdError = standardHandles[2]
        startup.lpAttributeList = attributes.list
        var flags = DWORD(EXTENDED_STARTUPINFO_PRESENT) | DWORD(CREATE_UNICODE_ENVIRONMENT) | DWORD(CREATE_NO_WINDOW)
        if !jobAtCreation { flags |= DWORD(CREATE_SUSPENDED) }
        var information = PROCESS_INFORMATION()
        var commandLine = Array(invocation.commandLine.utf16) + [0]
        let created = invocation.application.withCString(encodedAs: UTF16.self) { application in
            withOptionalWide(directory) { directory in
                withUnsafeMutablePointer(to: &startup) { startup in
                    startup.withMemoryRebound(to: STARTUPINFOW.self, capacity: 1) { startupInfo in
                        if var environment {
                            return environment.withUnsafeMutableBufferPointer {
                                CreateProcessW(application, &commandLine, nil, nil, !inherited.isEmpty, flags, $0.baseAddress,
                                               directory, startupInfo, &information)
                            }
                        }
                        return CreateProcessW(application, &commandLine, nil, nil, !inherited.isEmpty, flags, nil, directory,
                                              startupInfo, &information)
                    }
                }
            }
        }
        guard created, let process = information.hProcess else {
            let error = Self.lastError("CreateProcessW")
            CloseHandle(job)
            throw error
        }
        if !jobAtCreation {
            // Before Windows 10 1607: put in the job while it is suspended, before it can start anything.
            guard AssignProcessToJobObject(job, process) else {
                let error = Self.lastError("AssignProcessToJobObject")
                TerminateProcess(process, 1)
                CloseHandle(information.hThread)
                CloseHandle(process)
                CloseHandle(job)
                throw error
            }
            ResumeThread(information.hThread)
        }
        CloseHandle(information.hThread)

        // The program has its ends of the pipes: the caller keeps its own only (as Foundation's `Process` does), so that
        // the reading end sees the end once the program and what it started are done writing.
        if case let .pipe(pipe) = spec.standardInput { try? pipe.fileHandleForReading.close() }
        if case let .pipe(pipe) = spec.standardOutput { try? pipe.fileHandleForWriting.close() }
        if case let .pipe(pipe) = spec.standardError { try? pipe.fileHandleForWriting.close() }

        let child = WindowsProcess(process: process, job: job, identifier: Int32(bitPattern: information.dwProcessId),
                                   keeping: [spec.standardInput, spec.standardOutput, spec.standardError].compactMap(Self.object))
        if let onExit = spec.onExit { child.whenEnded(onExit) }
        return child
    }

    // PROC_THREAD_ATTRIBUTE_HANDLE_LIST and PROC_THREAD_ATTRIBUTE_JOB_LIST (ProcThreadAttributeValue's, a macro Swift
    // doesn't import: the attribute's number, and "an input").
    private static let handleListAttribute = DWORD_PTR(2 | 0x20000)
    private static let jobListAttribute = DWORD_PTR(13 | 0x20000)

    /// `environment` as `CreateProcessW` takes it: "name=value" strings, each ended by a NUL, sorted by name in any case,
    /// a NUL after the last. SystemRoot is added when it isn't there (a caller's short list, PATH alone): without it
    /// Windows' own libraries (sockets, cryptography) fail in the program.
    static func environmentBlock(_ environment: [String: String]) throws -> [WCHAR] {
        var environment = environment
        if WindowsPrograms.variable("SystemRoot", in: environment) == nil,
           let root = WindowsPrograms.variable("SystemRoot", in: ProcessInfo.processInfo.environment) {
            environment["SystemRoot"] = root
        }
        var block: [WCHAR] = []
        var names = Set<String>()
        // Windows' names are in any case: of two that differ only in it ("Path", "PATH"), one is passed, the first in
        // code-unit order ("PATH"), so the program never sees two.
        let sorted = environment.sorted { ($0.key.uppercased(), $0.key) < ($1.key.uppercased(), $1.key) }
        for (name, value) in sorted where names.insert(name.uppercased()).inserted {
            // A name may start with "=" (cmd.exe's "=C:", a drive's folder), have none after.
            guard !name.isEmpty, !name.dropFirst().contains("="), !name.contains("\0"), !value.contains("\0") else {
                throw WindowsLaunchError.invalidArgument("an environment variable that can't be passed")
            }
            block += Array("\(name)=\(value)".utf16)
            block.append(0)
        }
        if block.isEmpty { block.append(0) }
        block.append(0)
        return block
    }

    /// An inheritable handle to the NUL device, read and written (`FileHandle.nullDevice` has none on Windows), kept in
    /// `copies` to be closed.
    private static func nullDevice(_ copies: inout [HANDLE]) throws -> HANDLE {
        var security = SECURITY_ATTRIBUTES(nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size), lpSecurityDescriptor: nil,
                                           bInheritHandle: true)
        let handle = "NUL".withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), &security,
                        DWORD(OPEN_EXISTING), 0, nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { throw lastError("CreateFileW") }
        copies.append(handle)
        return handle
    }

    static func lastError(_ call: String) -> WindowsLaunchError { .system(call, GetLastError()) }

    /// The pipe or file `io` is, which the program keeps (as Foundation's `Process` does): the caller's ends of its pipes
    /// stay open while it runs, though the caller let go of them.
    private static func object(_ io: ProcessIO) -> AnyObject? {
        switch io {
        case .inherit, .null: return nil
        case let .pipe(pipe): return pipe
        case let .file(file): return file
        }
    }
}

/// `text` as a wide string for the length of `body`; nil stays nil.
private func withOptionalWide<T>(_ text: String?, _ body: (UnsafePointer<WCHAR>?) -> T) -> T {
    guard let text else { return body(nil) }
    return text.withCString(encodedAs: UTF16.self) { body($0) }
}

/// A process thread attribute list (`InitializeProcThreadAttributeList`), deleted with it.
private final class AttributeList {
    let list: LPPROC_THREAD_ATTRIBUTE_LIST?
    private let memory: UnsafeMutableRawPointer

    init(count: Int) {
        var size: SIZE_T = 0
        _ = InitializeProcThreadAttributeList(nil, DWORD(count), 0, &size)
        memory = UnsafeMutableRawPointer.allocate(byteCount: max(Int(size), 1), alignment: 16)
        let list = LPPROC_THREAD_ATTRIBUTE_LIST(memory)
        self.list = InitializeProcThreadAttributeList(list, DWORD(count), 0, &size) ? list : nil
    }

    /// Sets `attribute` to the `size` bytes at `value` (which must last as long as the list); whether it could be.
    func update(_ attribute: DWORD_PTR, _ value: UnsafeMutableRawPointer, size: Int) -> Bool {
        guard let list else { return false }
        return UpdateProcThreadAttribute(list, 0, attribute, value, SIZE_T(size), nil, nil)
    }

    deinit {
        if let list { DeleteProcThreadAttributeList(list) }
        memory.deallocate()
    }
}

/// A program started by `WindowsProcessLauncher`, with its job: what it started is in the job too.
final class WindowsProcess: LaunchedProcess, @unchecked Sendable {
    let processIdentifier: Int32
    private let process: HANDLE
    private let job: HANDLE
    /// The wait for its end (`whenEnded`), unregistered once it is let go of.
    private let wait = Locked<HANDLE?>(initialState: nil)
    private let ended = Locked<(@Sendable (any LaunchedProcess) -> Void)?>(initialState: nil)
    /// Its standard input, output and error's pipes and files.
    private let io: [AnyObject]

    init(process: HANDLE, job: HANDLE, identifier: Int32, keeping io: [AnyObject]) {
        self.process = process
        self.job = job
        processIdentifier = identifier
        self.io = io
    }

    deinit {
        if let wait = wait.withLock({ $0 }) { UnregisterWait(wait) }
        // Let go of: what it left running in the background goes on, as on the Mac (the job no longer kills it on closing).
        var limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
        _ = SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, DWORD(MemoryLayout<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>.size))
        CloseHandle(job)
        CloseHandle(process)
    }

    var isRunning: Bool { WaitForSingleObject(process, 0) == DWORD(WAIT_TIMEOUT) }

    /// Whether anything in its job (it, or what it started) is still running.
    var treeIsRunning: Bool {
        var accounting = JOBOBJECT_BASIC_ACCOUNTING_INFORMATION()
        guard QueryInformationJobObject(job, JobObjectBasicAccountingInformation, &accounting,
                                        DWORD(MemoryLayout<JOBOBJECT_BASIC_ACCOUNTING_INFORMATION>.size), nil) else { return isRunning }
        return accounting.ActiveProcesses > 0
    }

    var terminationStatus: Int32 {
        var code: DWORD = 0
        GetExitCodeProcess(process, &code)
        return Int32(bitPattern: code)
    }

    func waitUntilExit() { WaitForSingleObject(process, INFINITE) }

    // Windows has no SIGTERM for a program without a console or a window to ask: both end its whole tree at once, with
    // exit status 1 (as Rust's `Child::kill`).
    func terminate() -> Bool { end() }
    func kill() -> Bool { end() }

    private func end() -> Bool {
        guard treeIsRunning else { return false }
        return TerminateJobObject(job, 1)
    }

    /// Calls `onExit` once it has ended, on a thread of the system's pool (`RegisterWaitForSingleObject`).
    func whenEnded(_ onExit: @escaping @Sendable (any LaunchedProcess) -> Void) {
        ended.withLock { $0 = onExit }
        // Kept until then: the wait holds it.
        let context = Unmanaged.passRetained(self).toOpaque()
        var handle: HANDLE?
        let registered = RegisterWaitForSingleObject(&handle, process, { context, _ in
            guard let context else { return }
            let child = Unmanaged<WindowsProcess>.fromOpaque(context).takeRetainedValue()
            child.ended.withLock { $0 }?(child)
        }, context, INFINITE, ULONG(WT_EXECUTEONLYONCE))
        if registered {
            wait.withLock { $0 = handle }
        } else {
            // No wait: a thread of its own waits.
            Unmanaged<WindowsProcess>.fromOpaque(context).release()
            Thread.detachNewThread { [self] in
                waitUntilExit()
                onExit(self)
            }
        }
    }
}
#endif

#if os(Windows)
import Foundation
import WinSDK

/// The engine's thread for what it asks of the system (`SystemActions`): `ShellExecuteExW`, `CreateProcessW`, the
/// clipboard. None of it runs on a session's queue or on a key's way (§5.4: the reply to a key never waits on it): a
/// path on a share that is offline keeps the shell tens of seconds (past the 2 s watchdog), and reading the clipboard
/// can wait on the program that put a format there to render it, which may be the very app whose key is waiting.
///
/// A COM single-threaded apartment (`CoInitializeEx`, as the shell asks of its callers) with a message loop, as such a
/// thread must have: what COM and the windows of this thread are sent is answered while it waits for work. Work runs
/// one piece at a time, in the order given. It lives as long as the engine.
public final class SystemThread: SystemQueue, @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [@Sendable () -> Void] = []
    /// Set when there is work.
    private let wake: HANDLE
    public private(set) var threadId: DWORD = 0
    /// The thread's message-only window: the clipboard's owner while what the engine copied is on it.
    public private(set) var window: HWND?

    public init() {
        wake = CreateEventW(nil, false, false, nil)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in run(ready) }
        thread.name = "AllInOneIME system"
        thread.start()
        ready.wait()
    }

    public func async(_ work: @escaping @Sendable () -> Void) {
        lock.lock()
        jobs.append(work)
        lock.unlock()
        SetEvent(wake)
    }

    /// `work` on this thread, waited for (at once when called on it).
    public func sync<T>(_ work: @escaping () -> T) -> T {
        if isCurrent { return work() }
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: T?
        nonisolated(unsafe) let work = work
        async {
            result = work()
            done.signal()
        }
        done.wait()
        return result!
    }

    /// `sync`, for work that throws: its error comes back with it.
    public func syncThrowing<T>(_ work: @escaping () throws -> T) throws -> T {
        try sync { Result { try work() } }.get()
    }

    /// Whether the caller is this thread.
    public var isCurrent: Bool { GetCurrentThreadId() == threadId }

    private func run(_ ready: DispatchSemaphore) {
        _ = CoInitializeEx(nil, DWORD(COINIT_APARTMENTTHREADED.rawValue | COINIT_DISABLE_OLE1DDE.rawValue))
        threadId = GetCurrentThreadId()
        var message = MSG()
        // The thread's message queue, before anything is sent to it.
        _ = PeekMessageW(&message, nil, UINT(WM_USER), UINT(WM_USER), UINT(PM_NOREMOVE))
        window = Self.makeWindow()
        ready.signal()
        var handles: [HANDLE?] = [wake]
        while true {
            let woken = MsgWaitForMultipleObjectsEx(1, &handles, INFINITE, DWORD(QS_ALLINPUT), DWORD(MWMO_INPUTAVAILABLE))
            if woken == WAIT_OBJECT_0 {
                while let job = next() { job() }
            }
            while PeekMessageW(&message, nil, 0, 0, UINT(PM_REMOVE)) {
                TranslateMessage(&message)
                DispatchMessageW(&message)
            }
        }
    }

    /// A message-only window (`HWND_MESSAGE`) of a class of its own, whose messages are the default's.
    private static func makeWindow() -> HWND? {
        let instance = GetModuleHandleW(nil)
        return "AllInOneIME.SystemThread".withCString(encodedAs: UTF16.self) { name in
            var windowClass = WNDCLASSEXW()
            windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            windowClass.lpfnWndProc = { DefWindowProcW($0, $1, $2, $3) }
            windowClass.hInstance = instance
            windowClass.lpszClassName = name
            _ = RegisterClassExW(&windowClass)  // fails harmlessly for a second thread: the class is there
            // HWND_MESSAGE, (HWND)-3: a macro Swift doesn't import.
            return CreateWindowExW(0, name, name, 0, 0, 0, 0, 0, HWND(bitPattern: -3), nil, instance, nil)
        }
    }

    private func next() -> (@Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return jobs.isEmpty ? nil : jobs.removeFirst()
    }
}
#endif

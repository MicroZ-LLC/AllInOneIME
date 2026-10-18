#if os(Windows)
import Foundation
import WinSDK

/// One end of a named pipe opened for overlapped I/O in message mode (§2.1): whole messages in, whole messages out.
/// One thread reads (`readMessage`); any thread writes (`write`, one at a time); any thread may `shutdown`, after which
/// both fail. The thread that owns it calls `release` when it is done with it.
public final class PipeChannel: @unchecked Sendable {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// The other end is gone, or the channel was shut down.
        case closed(DWORD)
        case timeout
        /// A message longer than the limit: at least this many bytes.
        case tooLarge(Int)
        case failed(String, DWORD)

        public var description: String {
            switch self {
            case let .closed(code): return "closed (error \(code))"
            case .timeout: return "timed out"
            case let .tooLarge(size): return "a message of \(size) bytes or more is over the limit"
            case let .failed(call, code): return "\(call) failed: error \(code)"
            }
        }
    }

    public static let infinite: DWORD = 0xFFFF_FFFF
    static let waitTimeout: DWORD = 258

    public let handle: HANDLE
    private let readOverlapped: UnsafeMutablePointer<OVERLAPPED>
    private let writeOverlapped: UnsafeMutablePointer<OVERLAPPED>
    private var buffer: UnsafeMutableRawPointer
    private var capacity: Int
    private let writeLock = NSLock()
    private let stateLock = NSLock()
    private var isShut = false
    private var isReleased = false

    public init(handle: HANDLE) {
        self.handle = handle
        readOverlapped = Self.makeOverlapped()
        writeOverlapped = Self.makeOverlapped()
        capacity = 4096
        buffer = .allocate(byteCount: capacity, alignment: 16)
    }

    private static func makeOverlapped() -> UnsafeMutablePointer<OVERLAPPED> {
        let overlapped = UnsafeMutablePointer<OVERLAPPED>.allocate(capacity: 1)
        overlapped.initialize(to: OVERLAPPED())
        overlapped.pointee.hEvent = CreateEventW(nil, true, false, nil)
        return overlapped
    }

    public var isOpen: Bool { stateLock.locked { !isShut } }

    /// Stops what is pending on the handle (a read, a write, a wait for a client): they fail with `.closed`.
    public func shutdown() {
        stateLock.locked {
            guard !isShut else { return }
            isShut = true
            CancelIoEx(handle, nil)
        }
    }

    /// Closes the handle and frees what the I/O used: by the thread that owns the channel, once it no longer reads.
    public func release() {
        shutdown()
        writeLock.locked {
            stateLock.locked {
                guard !isReleased else { return }
                isReleased = true
                CloseHandle(handle)
                for overlapped in [readOverlapped, writeOverlapped] {
                    CloseHandle(overlapped.pointee.hEvent)
                    overlapped.deallocate()
                }
                buffer.deallocate()
            }
        }
    }

    // MARK: - The server's end

    /// Waits for a client to connect to this instance (`ConnectNamedPipe`).
    public func waitForClient() throws {
        while true {
            guard isOpen else { throw Failure.closed(Win32Code.operationAborted) }
            if ConnectNamedPipe(handle, readOverlapped) { return }
            switch GetLastError() {
            case Win32Code.pipeConnected:
                return
            case Win32Code.ioPending:
                _ = WaitForSingleObject(readOverlapped.pointee.hEvent, Self.infinite)
                var transferred: DWORD = 0
                if GetOverlappedResult(handle, readOverlapped, &transferred, false) { return }
                let code = GetLastError()
                throw isOpen ? Failure.failed("ConnectNamedPipe", code) : Failure.closed(code)
            case Win32Code.noData:
                // A client came and went before the wait: free the instance for the next one.
                DisconnectNamedPipe(handle)
            case let code:
                throw Failure.failed("ConnectNamedPipe", code)
            }
        }
    }

    // MARK: - Messages

    /// The next whole message, at most `limit` bytes; its buffer grows on `ERROR_MORE_DATA` (§2.2).
    public func readMessage(limit: Int, timeout: DWORD = PipeChannel.infinite) throws -> Data {
        var total = 0
        while true {
            guard isOpen else { throw Failure.closed(Win32Code.operationAborted) }
            if total == capacity {
                let grown = min(capacity * 2, limit + 1)
                guard grown > capacity else { throw Failure.tooLarge(total) }
                let bigger = UnsafeMutableRawPointer.allocate(byteCount: grown, alignment: 16)
                bigger.copyMemory(from: buffer, byteCount: total)
                buffer.deallocate()
                buffer = bigger
                capacity = grown
            }
            if !ReadFile(handle, buffer + total, DWORD(capacity - total), nil, readOverlapped) {
                let code = GetLastError()
                guard code == Win32Code.ioPending || code == Win32Code.moreData else { throw Self.failure("ReadFile", code) }
                if code == Win32Code.ioPending, WaitForSingleObject(readOverlapped.pointee.hEvent, timeout) == Self.waitTimeout {
                    CancelIoEx(handle, readOverlapped)
                    var transferred: DWORD = 0
                    _ = GetOverlappedResult(handle, readOverlapped, &transferred, true)
                    throw Failure.timeout
                }
            }
            var transferred: DWORD = 0
            if GetOverlappedResult(handle, readOverlapped, &transferred, false) {
                total += Int(transferred)
                guard total <= limit else { throw Failure.tooLarge(total) }
                return Data(bytes: buffer, count: total)
            }
            let code = GetLastError()
            guard code == Win32Code.moreData else { throw Self.failure("ReadFile", code) }
            total += Int(transferred)
            guard total <= limit else { throw Failure.tooLarge(total) }
        }
    }

    /// Writes `message` as one pipe message, waiting at most `timeout` ms for the other end to make room.
    public func write(_ message: Data, timeout: DWORD = 5000) throws {
        try writeLock.locked {
            guard isOpen else { throw Failure.closed(Win32Code.operationAborted) }
            try message.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                if !WriteFile(handle, raw.baseAddress, DWORD(raw.count), nil, writeOverlapped) {
                    let code = GetLastError()
                    guard code == Win32Code.ioPending else { throw Self.failure("WriteFile", code) }
                    if WaitForSingleObject(writeOverlapped.pointee.hEvent, timeout) == Self.waitTimeout {
                        CancelIoEx(handle, writeOverlapped)
                        var transferred: DWORD = 0
                        _ = GetOverlappedResult(handle, writeOverlapped, &transferred, true)
                        throw Failure.timeout
                    }
                }
                var transferred: DWORD = 0
                guard GetOverlappedResult(handle, writeOverlapped, &transferred, false) else {
                    throw Self.failure("WriteFile", GetLastError())
                }
            }
        }
    }

    static func failure(_ call: String, _ code: DWORD) -> Failure {
        switch code {
        case Win32Code.brokenPipe, Win32Code.pipeNotConnected, Win32Code.noData, Win32Code.operationAborted, 6:
            return .closed(code)
        default:
            return .failed(call, code)
        }
    }
}
#endif

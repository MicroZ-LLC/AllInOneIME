import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An HTTP response read as it arrives, like `URLSession.bytes(for:)`, which only Apple's Foundation has: here a
/// data delegate reads it, which works with every Foundation. The body comes byte by byte, or line by line
/// (`Body.lines`, split as Foundation's `AsyncLineSequence` splits). Cancelling the task that reads cancels the
/// request, and so does dropping the body before its end. The errors are the request's own: `URLError(.cancelled)`,
/// `.timedOut` (the request's and the session's timeouts apply as they are), and so on.
public enum HTTPStream {
    /// Sends `request` on `session` and returns when the response's headers are in. `redirect` decides each
    /// redirect: the request to send instead, or nil to refuse it (the redirect itself is then the response);
    /// without it, redirects are followed.
    public static func bytes(for request: URLRequest, session: URLSession,
                             redirect: (@Sendable (URLRequest) -> URLRequest?)? = nil) async throws -> (Body, URLResponse) {
        let receiver = Receiver(redirect: redirect)
        #if canImport(Darwin)
        // On the caller's session, so that its connections are reused; the task has a delegate of its own.
        let task = session.dataTask(with: request)
        task.delegate = receiver
        task.resume()
        #else
        // Corelibs Foundation tells a task's data only to its session's delegate: a session of its own, with the
        // same configuration, that goes away when the task is done.
        let own = URLSession(configuration: session.configuration, delegate: receiver, delegateQueue: nil)
        let task = own.dataTask(with: request)
        task.resume()
        own.finishTasksAndInvalidate()
        #endif
        let body = Body(reader: Reader(receiver: receiver, task: task))
        let response = try await withTaskCancellationHandler {
            try await receiver.response()
        } onCancel: {
            task.cancel()
        }
        return (body, response)
    }

    /// The response's body, as it arrives.
    public struct Body: AsyncSequence, Sendable {
        public typealias Element = UInt8
        fileprivate let reader: Reader

        public struct AsyncIterator: AsyncIteratorProtocol {
            fileprivate let reader: Reader
            private var chunk = Data()
            private var index = 0

            fileprivate init(reader: Reader) {
                self.reader = reader
            }

            public mutating func next() async throws -> UInt8? {
                if index < chunk.endIndex {
                    defer { index += 1 }
                    return chunk[index]
                }
                guard let next = try await reader.next() else { return nil }
                chunk = next
                index = chunk.startIndex + 1
                return chunk[chunk.startIndex]
            }
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(reader: reader)
        }

        /// The body's lines (UTF-8).
        public var lines: Lines<Body> { Lines(self) }
    }

    /// Lines of UTF-8 text, split as Foundation's `AsyncLineSequence` (Apple-only) splits them: at LF, CR, CR LF,
    /// VT, FF, NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR; empty lines are left out.
    public struct Lines<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
        public typealias Element = String
        let base: Base

        public init(_ base: Base) {
            self.base = base
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            var bytes: Base.AsyncIterator
            var buffer: [UInt8] = []
            var leftover: UInt8?

            public mutating func next() async throws -> String? {
                while let first = try await nextByte() {
                    switch first {
                    case 0x0D:  // CR, and the LF after it
                        let line = take()
                        guard let next = try await bytes.next() else { return line }
                        if next != 0x0A { leftover = next }
                        if let line { return line }
                    case 0x0A...0x0C:  // LF, VT, FF
                        if let line = take() { return line }
                    case 0xC2:  // NEL is C2 85
                        guard let next = try await bytes.next() else {
                            buffer.append(first)
                            return take()
                        }
                        guard next == 0x85 else {
                            buffer += [first, next]
                            continue
                        }
                        if let line = take() { return line }
                    case 0xE2:  // LINE and PARAGRAPH SEPARATOR are E2 80 A8 and E2 80 A9
                        guard let next = try await bytes.next() else {
                            buffer.append(first)
                            return take()
                        }
                        guard next == 0x80 else {
                            buffer += [first, next]
                            continue
                        }
                        guard let last = try await bytes.next() else {
                            buffer += [first, next]
                            return take()
                        }
                        guard last == 0xA8 || last == 0xA9 else {
                            buffer += [first, next, last]
                            continue
                        }
                        if let line = take() { return line }
                    default:
                        buffer.append(first)
                    }
                }
                return take()
            }

            private mutating func nextByte() async throws -> UInt8? {
                if let byte = leftover {
                    leftover = nil
                    return byte
                }
                return try await bytes.next()
            }

            /// The line so far, if any, and an empty buffer.
            private mutating func take() -> String? {
                defer { buffer.removeAll(keepingCapacity: true) }
                return buffer.isEmpty ? nil : String(decoding: buffer, as: UTF8.self)
            }
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(bytes: base.makeAsyncIterator())
        }
    }

    /// The request, for its body: dropping the body cancels it (nothing happens once it's done).
    fileprivate final class Reader: @unchecked Sendable {
        let receiver: Receiver
        let task: URLSessionDataTask

        init(receiver: Receiver, task: URLSessionDataTask) {
            self.receiver = receiver
            self.task = task
        }

        deinit {
            task.cancel()
        }

        func next() async throws -> Data? {
            try await withTaskCancellationHandler {
                try await receiver.next()
            } onCancel: { [task] in
                task.cancel()
            }
        }
    }

    /// The task's delegate: keeps what arrives until it's read.
    fileprivate final class Receiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private struct State {
            var response: URLResponse?
            var data = Data()
            var done = false
            var error: Error?
            var waiting: CheckedContinuation<Void, Never>?
        }

        private let state = Locked(initialState: State())
        private let redirect: (@Sendable (URLRequest) -> URLRequest?)?

        init(redirect: (@Sendable (URLRequest) -> URLRequest?)?) {
            self.redirect = redirect
        }

        func response() async throws -> URLResponse {
            while true {
                let (response, error, done) = state.withLock { ($0.response, $0.error, $0.done) }
                if let response { return response }
                if let error { throw error }
                if done { throw URLError(.badServerResponse) }
                await wait { $0.response != nil || $0.done }
            }
        }

        /// What arrived since the last call (never empty), or nil at the end; the request's error after its data.
        func next() async throws -> Data? {
            while true {
                let next: Result<Data?, Error>? = state.withLock { state in
                    if !state.data.isEmpty {
                        defer { state.data = Data() }
                        return .success(state.data)
                    }
                    if let error = state.error { return .failure(error) }
                    return state.done ? .success(nil) : nil
                }
                if let next { return try next.get() }
                await wait { !$0.data.isEmpty || $0.done }
            }
        }

        private func wait(until ready: (State) -> Bool) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let now = state.withLock { state in
                    if ready(state) { return true }
                    state.waiting = continuation
                    return false
                }
                if now { continuation.resume() }
            }
        }

        private func update(_ change: (inout State) -> Void) {
            let waiting = state.withLock { state in
                change(&state)
                defer { state.waiting = nil }
                return state.waiting
            }
            waiting?.resume()
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
            update { $0.response = response }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            update { $0.data.append(data) }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(redirect.map { $0(request) } ?? request)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            update {
                $0.done = true
                $0.error = error
            }
        }
    }
}

extension HTTPStream.Lines: Sendable where Base: Sendable {}

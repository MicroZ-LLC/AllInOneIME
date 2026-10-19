import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import AllInOneIMECore

/// Plays a script for each test host (a host per test, so the tests run in parallel): a response, data, waits for
/// the test, failures, a redirect. Notes when the request is started and when it is stopped.
final class StreamStub: URLProtocol, @unchecked Sendable {
    enum Step: Sendable {
        case respond(Int)
        case send(String)
        /// Until the test signals (or the request is stopped).
        case wait(DispatchSemaphore)
        case fail(URLError.Code)
        /// A 302 to this address. A followed redirect stops this request; a refused one (the test's `redirect` closure
        /// signals `refused` as it refuses) goes on with the 302 as the response.
        case redirect(String, refused: DispatchSemaphore? = nil)
        case finish
    }

    private struct State {
        var scripts: [String: [Step]] = [:]
        var started: Set<String> = []
        var stopped: Set<String> = []
    }

    private static let state = Locked(initialState: State())
    private let isStopped = Locked(initialState: false)

    static func serve(_ host: String, _ steps: [Step]) {
        state.withLock { $0.scripts[host] = steps }
    }

    static func started(_ host: String) -> Bool {
        state.withLock { $0.started.contains(host) }
    }

    static func stopped(_ host: String) -> Bool {
        state.withLock { $0.stopped.contains(host) }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host else { return }
        let steps = Self.state.withLock { state in
            state.started.insert(host)
            return state.scripts[host] ?? [.fail(.cannotFindHost)]
        }
        #if canImport(Darwin)
        let stub = self
        #else
        nonisolated(unsafe) let stub = self  // URLProtocol isn't Sendable off Apple platforms
        #endif
        // On a thread of its own, not the global queues': in a busy test run their threads can all be taken for many
        // seconds (synchronous tests), long past the request's timeout.
        Thread { stub.play(steps, url: url) }.start()
    }

    private func play(_ steps: [Step], url: URL) {
        for step in steps {
            if isStopped.withLock({ $0 }) { return }
            switch step {
            case let .respond(status):
                // With a type, so that URLSession doesn't hold the response back to sniff the body.
                let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                               headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            case let .send(text):
                client?.urlProtocol(self, didLoad: Data(text.utf8))
            case let .wait(gate):
                if !wait(for: gate) { return }
            case let .fail(code):
                client?.urlProtocol(self, didFailWithError: URLError(code))
                return
            case let .redirect(location, refused):
                let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                               headerFields: ["Location": location, "Content-Type": "application/json"])!
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: location)!), redirectResponse: response)
                // Followed, this request is stopped (and nothing more comes from it); refused, the 302 is the response.
                guard let refused, wait(for: refused) else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            case .finish:
                client?.urlProtocolDidFinishLoading(self)
                return
            }
        }
    }

    /// Waits for `gate`: false if the request is stopped first.
    private func wait(for gate: DispatchSemaphore) -> Bool {
        while gate.wait(timeout: .now() + 0.05) == .timedOut {
            if isStopped.withLock({ $0 }) { return false }
        }
        return true
    }

    override func stopLoading() {
        isStopped.withLock { $0 = true }
        if let host = request.url?.host { Self.state.withLock { _ = $0.stopped.insert(host) } }
    }
}

struct HTTPStreamTests {
    #if canImport(Darwin)
    static let stubsCanRedirect = true
    #else
    static let stubsCanRedirect = false
    #endif

    let session = StreamStub.session()

    /// The request's timeout only catches a hang: in a busy test run, the test can take seconds to read what came.
    func request(_ host: String) -> URLRequest {
        URLRequest(url: URL(string: "https://\(host)/stream")!, timeoutInterval: TimeInterval(Timing.longSleep))
    }

    @Test func linesComeAsTheyArrive() async throws {
        let gate = DispatchSemaphore(value: 0)
        StreamStub.serve("lines.test", [.respond(200), .send("data: one\n\n"), .wait(gate), .send("data: two\r\n"), .finish])
        let (body, response) = try await HTTPStream.bytes(for: request("lines.test"), session: session)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        var lines = body.lines.makeAsyncIterator()
        // The first line is read while the server still holds back the second.
        #expect(try await lines.next() == "data: one")
        gate.signal()
        #expect(try await lines.next() == "data: two")
        #expect(try await lines.next() == nil)
    }

    @Test func anErrorStatusComesWithItsBody() async throws {
        StreamStub.serve("status.test", [.respond(500), .send("{\"message\":"), .send("\"oops\"}"), .finish])
        let (body, response) = try await HTTPStream.bytes(for: request("status.test"), session: session)
        #expect((response as? HTTPURLResponse)?.statusCode == 500)
        var bytes: [UInt8] = []
        for try await byte in body { bytes.append(byte) }
        #expect(String(decoding: bytes, as: UTF8.self) == "{\"message\":\"oops\"}")
    }

    @Test func aFailureBeforeTheResponseIsThrown() async throws {
        StreamStub.serve("unreachable.test", [.fail(.cannotConnectToHost)])
        let error = await #expect(throws: URLError.self) {
            _ = try await HTTPStream.bytes(for: request("unreachable.test"), session: session)
        }
        #expect(error?.code == .cannotConnectToHost)
    }

    @Test func aFailureComesAfterTheDataBeforeIt() async throws {
        let gate = DispatchSemaphore(value: 0)
        StreamStub.serve("lost.test", [.respond(200), .send("partial"), .wait(gate), .fail(.timedOut)])
        let (body, _) = try await HTTPStream.bytes(for: request("lost.test"), session: session)
        var bytes = body.makeAsyncIterator(), read: [UInt8] = []
        for _ in 0..<7 { read.append(try #require(try await bytes.next())) }
        #expect(String(decoding: read, as: UTF8.self) == "partial")
        gate.signal()
        let error = await #expect(throws: URLError.self) { _ = try await bytes.next() }
        #expect(error?.code == .timedOut)
    }

    @Test func cancellingTheReaderCancelsTheRequest() async throws {
        let gate = DispatchSemaphore(value: 0)
        StreamStub.serve("cancel.test", [.respond(200), .send("first\n"), .wait(gate), .send("never\n"), .finish])
        let (body, _) = try await HTTPStream.bytes(for: request("cancel.test"), session: session)
        let firstLine = Locked(initialState: false)
        let reading = Task {
            for try await line in body.lines where line == "first" { firstLine.withLock { $0 = true } }
        }
        #expect(await Timing.eventually { firstLine.withLock { $0 } })
        reading.cancel()
        let error = await #expect(throws: URLError.self) { try await reading.value }
        #expect(error?.code == .cancelled)
        #expect(await Timing.eventually { StreamStub.stopped("cancel.test") })
    }

    @Test func cancellingBeforeTheResponseCancelsTheRequest() async throws {
        let gate = DispatchSemaphore(value: 0)
        StreamStub.serve("slow.test", [.wait(gate), .respond(200), .finish])
        let session = session, slow = request("slow.test")
        let opening = Task { try await HTTPStream.bytes(for: slow, session: session) }
        // Started, so that it has something to stop (the response is held back until the gate, never signalled).
        #expect(await Timing.eventually { StreamStub.started("slow.test") })
        opening.cancel()
        let error = await #expect(throws: URLError.self) { _ = try await opening.value }
        #expect(error?.code == .cancelled)
        #expect(await Timing.eventually { StreamStub.stopped("slow.test") })
    }

    @Test func droppingTheBodyCancelsTheRequest() async throws {
        let gate = DispatchSemaphore(value: 0)
        StreamStub.serve("dropped.test", [.respond(200), .send("x"), .wait(gate), .finish])
        do {
            let (body, _) = try await HTTPStream.bytes(for: request("dropped.test"), session: session)
            var bytes = body.makeAsyncIterator()
            #expect(try await bytes.next() == UInt8(ascii: "x"))
        }
        #expect(await Timing.eventually { StreamStub.stopped("dropped.test") })
    }

    /// Apple's URLSession only: corelibs' (Linux, Windows) stops the process when a URLProtocol stub redirects.
    @Test(.enabled(if: HTTPStreamTests.stubsCanRedirect)) func redirectsAreFollowedUnlessRefused() async throws {
        StreamStub.serve("moved.test", [.redirect("https://new.moved.test/"), .finish])
        StreamStub.serve("new.moved.test", [.respond(200), .send("here"), .finish])
        let (followed, response) = try await HTTPStream.bytes(for: request("moved.test"), session: session)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(response.url?.host == "new.moved.test")
        var text: [UInt8] = []
        for try await byte in followed { text.append(byte) }
        #expect(String(decoding: text, as: UTF8.self) == "here")

        let refusal = DispatchSemaphore(value: 0)
        StreamStub.serve("kept.test", [.redirect("https://new.kept.test/", refused: refusal), .finish])
        StreamStub.serve("new.kept.test", [.respond(200), .finish])
        let asked = Locked(initialState: [String]())
        let (_, refused) = try await HTTPStream.bytes(for: request("kept.test"), session: session) { request in
            asked.withLock { $0.append(request.url?.host ?? "") }
            refusal.signal()
            return nil
        }
        #expect((refused as? HTTPURLResponse)?.statusCode == 302)
        #expect(asked.withLock { $0 } == ["new.kept.test"])
    }

    // MARK: Lines

    func lines(_ bytes: [UInt8]) async throws -> [String] {
        var lines: [String] = []
        for try await line in HTTPStream.Lines(stream(bytes)) { lines.append(line) }
        return lines
    }

    func stream(_ bytes: [UInt8]) -> AsyncStream<UInt8> {
        AsyncStream { continuation in
            for byte in bytes { continuation.yield(byte) }
            continuation.finish()
        }
    }

    @Test func linesBreakWhereFoundationBreaksThem() async throws {
        #expect(try await lines(Array("a\r\nb\n\nc\rd\u{2028}e\u{2029}f\u{85}g\u{0B}h\u{0C}i\n".utf8))
            == ["a", "b", "c", "d", "e", "f", "g", "h", "i"])
        #expect(try await lines(Array("\n\r\n\r".utf8)).isEmpty)
        #expect(try await lines(Array("last".utf8)) == ["last"])
        #expect(try await lines(Array("中文\n".utf8)) == ["中文"])
    }

    #if canImport(Darwin)
    /// The same lines as Foundation's `AsyncLineSequence`, including its quirks with broken sequences, for these
    /// inputs and a few thousand made of line-break bytes and their prefixes.
    @Test func linesAreFoundationsLines() async throws {
        func foundation(_ bytes: [UInt8]) async throws -> [String] {
            var lines: [String] = []
            for try await line in stream(bytes).lines { lines.append(line) }
            return lines
        }
        var inputs: [[UInt8]] = [
            [], [0x0D], [0x0D, 0x0A], [0x0D, 0x0D, 0x0A], [0x61, 0xC2], [0x61, 0xC2, 0x41], [0x61, 0xC2, 0x0A, 0x62],
            [0xE2], [0xE2, 0x80], [0xE2, 0x80, 0x41], [0xE2, 0x41, 0x0A], [0xE2, 0x80, 0x0D, 0x0A, 0x62], [0x0D, 0xE2, 0x80, 0xA8],
            Array("data: {\"text\":\"a\u{2028}b\"}\r\n\r\n".utf8),
        ]
        let alphabet: [UInt8] = [0x0A, 0x0B, 0x0C, 0x0D, 0xC2, 0x85, 0xE2, 0x80, 0xA8, 0xA9, 0x61]
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        for _ in 0..<3000 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let count = Int(seed >> 60)
            inputs.append((0..<count).map { index in
                alphabet[Int((seed >> UInt64(4 * (index % 15))) & 0xF) % alphabet.count]
            })
        }
        for input in inputs {
            let ours = try await lines(input), theirs = try await foundation(input)
            #expect(ours == theirs, "\(input.map { String($0, radix: 16) })")
        }
    }
    #endif
}

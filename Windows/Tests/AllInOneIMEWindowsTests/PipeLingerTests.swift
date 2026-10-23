#if os(Windows)
import AllInOneIMECore
import AllInOneIMEWindows
import AllInOneIMEWire
import Foundation
import Testing
import WinSDK

/// What a client sends after a fatal error, while the engine gives it a moment to read the error (§3): read with the
/// limit the connection had (a DLL's 64 KiB, a settings window's 1 MiB once it has the settings: §2.2), never more, and
/// dropped.
@Suite(.serialized)
struct PipeLingerTests {
    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
    }

    /// A listener on a pipe of the test's own (the user's name with a suffix: never the real engine's), its log in `lines`.
    func listener(_ server: WireServer, _ lines: Lines) throws -> (PipeListener, String) {
        let sid = try Win32.currentUserSID()
        var options = PipeListener.Options()
        let name = PipeNames.pipe(sid: sid) + "-linger-\(GetCurrentProcessId())-\(UUID().uuidString.prefix(8))"
        options.pipeName = name
        let listener = try PipeListener(server: server, sid: sid, options: options, log: { lines.add($0) })
        try listener.start()
        return (listener, name)
    }

    /// Hello with `capabilities`, a frame that isn't JSON (badFrame: fatal), then a frame of `size` bytes while the engine
    /// lingers: what the welcome granted, and the log once the connection closed.
    func afterAFatalError(_ server: WireServer, capabilities: [String], size: Int) throws -> (granted: [String], log: [String]) {
        let lines = Lines()
        let (listener, name) = try listener(server, lines)
        defer { listener.stop() }
        let client = try PipeClient.connect(name: name, timeout: 2)
        try client.send(try WireJSON.encode(ClientFrame(id: 1, .hello(Hello(client: "linger/test", capabilities: capabilities)))))
        guard case let .welcome(_, welcome) = try WireJSON.decode(EngineFrame.self, from: client.receive(timeout: 2000)).message else {
            Issue.record("no welcome")
            return ([], lines.all)
        }
        try client.send(Data("not JSON".utf8))
        _ = try client.receive(timeout: 2000)  // the error
        try client.send(Data(repeating: UInt8(ascii: "x"), count: size))
        // Its end closed after a moment: the engine's linger ends, and so does the connection.
        Thread.sleep(forTimeInterval: 0.3)
        client.close()
        let deadline = Date().addingTimeInterval(5)
        while !lines.all.contains(where: { $0.hasSuffix(": closed") }), Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        return (welcome.capabilities, lines.all)
    }

    final class NullHost: WireHost, @unchecked Sendable {
        func perform(_ effect: Composer.Effect, in session: ComposerSession) {}
        func panel(shown: Bool, in session: ComposerSession) {}
    }

    @Test func aDLLsConnectionIsReadUpToItsLimit() throws {
        let server = WireServer(environment: WireEnvironment(host: NullHost()))
        let (_, lines) = try afterAFatalError(server, capabilities: [], size: 200 * 1024)
        #expect(lines.contains { $0.contains("a frame over its limit (\(WireFrame.clientLimit) bytes) as it closes: dropped") },
                "\(lines)")
        #expect(lines.contains { $0.hasSuffix(": closed") }, "\(lines)")
    }

    @Test func aSettingsWindowsConnectionUpToItsOwn() throws {
        let server = WireServer(environment: WireEnvironment(host: NullHost()))
        #expect(server.useTestSettings(config: #"{"provider": "anthropic"}"#))
        let (granted, lines) = try afterAFatalError(server, capabilities: [Hello.settings], size: 200 * 1024)
        #expect(granted == [Hello.settings])
        #expect(!lines.contains { $0.contains("over its limit") }, "\(lines)")
        #expect(lines.contains { $0.hasSuffix(": closed") }, "\(lines)")
    }
}
#endif

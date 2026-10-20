import AllInOneIMECore
@testable import AllInOneIMEWire
import Foundation
import Testing

/// What the Windows DLL and the engine agreed on where the spec's text left room (Spec notes): each composition carries
/// the draft as typed, a key the client gave up on leaves the document as the client left it, re-sending `focus` keeps
/// the draft and the serial, and a caret report counts only while the panel it anchors is shown.
struct ComposerSessionTests {
    /// A client with session 1 open and focused in Notepad.
    final class Client {
        let engine = TestEngine()
        let connection: ConnectionID
        private(set) var nextID: UInt32 = 1
        var t: UInt64 = 1000

        init() {
            connection = engine.server.connect(WirePeer.trustedClient)!
            send(.hello(Hello(client: "test", capabilities: ["allowForeground"])))
            send(.open(sid: 1, field: GoldenWriter.notepad))
            send(.focus(sid: 1, focus: 1, field: nil))
        }

        @discardableResult
        func send(_ message: ClientMessage) -> [EngineMessage] {
            let id = nextID
            nextID += 1
            return engine.send(ClientFrame(id: id, message), on: connection).map(\.message)
        }

        /// A key-down; its result's outputs.
        @discardableResult
        func press(vk: UInt16, scan: UInt16, text: String, shift: Bool = false) -> [Output] {
            t += 100
            let key = WireKey(vk: vk, scan: scan, text: text, textIgnoringModifiers: text,
                              modifiers: shift ? [.shift, .leftShift] : [])
            guard case let .result(_, _, outputs) = send(.keyDown(KeyFrame(sid: 1, t: t, key: key))).first else { return [] }
            return outputs
        }

        /// Each character's key on a US layout; the last one's outputs.
        @discardableResult
        func type(_ text: String) -> [Output] {
            var last: [Output] = []
            for c in text {
                let key = GoldenWriter.usKey(c)!
                last = press(vk: key.vk, scan: key.scan, text: String(c), shift: key.shift)
            }
            return last
        }
    }

    static func draft(_ text: String, caret: Int, typed: String? = nil) -> Output {
        .composition(text: text, caret: caret, segments: [Segment(from: 0, to: text.utf16.count, style: Segment.Style.draft)],
                     typed: typed)
    }

    @Test func compositionsCarryTheDraftAsTyped() {
        let client = Client()
        // "@" is shown as typed: no `typed`.
        #expect(client.type("@") == [Self.draft("@", caret: 1), .panel(shown: true)])
        #expect(client.type("i") == [Self.draft("i", caret: 1, typed: "@i")])
        #expect(client.type("mprove h") == [Self.draft("improve › h", caret: 11, typed: "@improve h")])
    }

    @Test func aTimeoutLeavesTheDocumentAlone() {
        let client = Client()
        client.type("@im")
        // The client gave up on "p": it ended the composition leaving "@im", and the app typed "p".
        client.type("p")
        let id = client.nextID
        #expect(client.send(.endComposition(sid: 1, reason: "timeout")) == [.result(re: id, outputs: [.panel(shown: false)])])
        // Back in step: plain typing, and a new draft starts as before.
        #expect(client.type(" x ") == [])
        #expect(client.type("@") == [Self.draft("@", caret: 1), .panel(shown: true)])
    }

    @Test func aTimeoutAtLevelTwoStopsTheRequest() throws {
        let client = Client()
        let fixture = ScriptedProvider.Fixture(steps: [.init(after: 100, versions: ["Hello."], final: true)])
        client.engine.host.provider = ScriptedProvider(fixture: fixture, clock: client.engine.clock)
        client.type("@improve helo")
        client.press(vk: 0x0D, scan: 0x1C, text: "\r")
        #expect(client.engine.host.provider?.requests.count == 1)
        let id = client.nextID
        #expect(client.send(.endComposition(sid: 1, reason: "timeout")) == [.result(re: id, outputs: [.panel(shown: false)])])
        // The stream that was due is cancelled: nothing more comes for that draft.
        client.engine.clock.advance(by: 1)
        client.engine.runUntilIdle()
        #expect(client.engine.takePushes(for: client.connection).isEmpty)
        #expect(client.type("x") == [])
    }

    @Test func theCaretIsForgottenWhenThePanelHides() throws {
        let client = Client()
        client.type("@")
        client.send(.caret(sid: 1, rect: [812, 440, 9, 20], hwnd: 1, exact: true))
        let session = try #require(client.engine.host.sessions[1])
        #expect(session.caret?.rect == [812, 440, 9, 20])
        // Esc gives the draft up: the panel goes, and the caret it was anchored at with it.
        #expect(client.press(vk: 0x1B, scan: 0x01, text: "\u{1B}") == [.composition(text: ""), .panel(shown: false)])
        #expect(session.caret == nil)
        // The next panel waits for its own report.
        client.type("@")
        #expect(session.caret == nil)
        client.send(.caret(sid: 1, rect: [900, 440, 9, 20], hwnd: 1, exact: true))
        #expect(session.caret?.rect == [900, 440, 9, 20])
    }

    @Test func refocusingKeepsTheDraftAndTheSerial() throws {
        let client = Client()
        client.type("@imp")
        // Focus re-sent with a new layout and the same serial: nothing is blurred, committed or pushed.
        var layout = GoldenWriter.notepad
        layout.layout = "00000804"
        #expect(client.send(.focus(sid: 1, focus: 1, field: layout)) == [])
        let session = try #require(client.engine.host.sessions[1])
        #expect(session.focusSerial == 1)
        #expect(session.field.layout == "00000804")
        #expect(client.type("r") == [Self.draft("impr", caret: 4, typed: "@impr")])
    }
}

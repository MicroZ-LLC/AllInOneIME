#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import AllInOneIMEWire
import Foundation
import Testing
import WinSDK

/// What a client may make the engine do (§8), through the real wire server and the engine's host: the panel and its
/// notices only for a process that owns the foreground, the panel only at a caret inside the client's own window.
@Suite(.serialized)
struct TrustTests {
    static let english = #"{"inputLanguages": ["en"], "outputLanguages": ["en"], "outputLanguage": "en"}"#

    func client(peer: WirePeer = WirePeer(pid: GetCurrentProcessId(), integrity: .medium),
                configure: (inout EngineHost.Options) -> Void = { _ in }) throws -> (EngineClient, URL) {
        let folder = try temporaryFolder("trust")
        return (EngineClient(settings: try settingsFile(Self.english, in: folder), rime: nil, peer: peer, configure: configure), folder)
    }

    /// A process in the background (or one that sends keys while another app is in front) can't show the engine's
    /// topmost window, its text in it, over another app: no panel, no notice. Once it owns the foreground, it can.
    @Test func aClientWithoutTheForegroundGetsNoPanelNorNotice() throws {
        let inFront = Flag(false)
        let (client, folder) = try client { $0.foreground = { _ in inFront.value } }
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = try #require(client.host.liveSessions.first)
        client.type("@impr")
        #expect(client.composer.isComposing)
        #expect(client.panel.shows == 0 && client.panel.model == nil)
        client.host.perform(.notice("Pwned: type your password here"), in: session)
        #expect(client.panel.notices.isEmpty)
        inFront.value = true
        client.type("o")
        #expect(client.panel.shows == 1 && client.panel.model != nil)
        client.host.perform(.notice("中"), in: session)
        #expect(client.panel.notices == ["中"])
        // In the background again: the panel goes with the next key.
        inFront.value = false
        client.type("v")
        #expect(client.panel.model == nil)
    }

    /// A caret report (§6) places the panel only inside the window it names, and only if that window is the client's
    /// process's (`Foreground.caretBounds`): one outside it is cut to it, one in another process's window is ignored.
    @Test func aCaretGoesOnlyInsideTheClientsOwnWindow() throws {
        let clientWindow: UInt64 = 0x4242
        let bounds = CaretRect(x: 100, y: 100, width: 400, height: 300)
        let pid = GetCurrentProcessId()
        let (client, folder) = try client { options in
            options.caretBounds = { hwnd, owner in hwnd == clientWindow && owner == pid ? bounds : nil }
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        client.type("@")
        #expect(client.panel.model != nil)
        client.send(.caret(sid: 1, rect: [150, 200, 2, 20], hwnd: clientWindow, exact: true))
        #expect(client.panel.caret == CaretRect(x: 150, y: 200, width: 2, height: 20))
        // Over another monitor, far from the client's window: cut to the window's edge.
        client.send(.caret(sid: 1, rect: [5000, -900, 2, 20], hwnd: clientWindow, exact: true))
        #expect(client.panel.caret == CaretRect(x: 500, y: 100, width: 0, height: 0))
        // Another process's window (or none the client owns): ignored, the panel stays where it was.
        let moves = client.panel.moves
        client.send(.caret(sid: 1, rect: [10, 10, 2, 20], hwnd: 0x9999, exact: true))
        client.send(.caret(sid: 1, rect: [10, 10, 2, 20], hwnd: nil, exact: false))
        #expect(client.panel.moves == moves)
        #expect(client.panel.caret == CaretRect(x: 500, y: 100, width: 0, height: 0))
        // And the next draw doesn't take it either.
        client.type("i")
        #expect(client.panel.caret == CaretRect(x: 500, y: 100, width: 0, height: 0))
    }

    /// An untrusted client (low integrity, or in an AppContainer: §8) only types and rewrites its own text. Through the
    /// real wire server and the engine's host (not `host.perform`, which is past the check): `@open`'s search, Ctrl+V's
    /// clipboard and `@agent`'s terminal are refused with a notice, and nothing reaches the system.
    @Test(arguments: [WirePeer(pid: GetCurrentProcessId(), integrity: .low),
                      WirePeer(pid: GetCurrentProcessId(), integrity: .medium, appContainer: true)])
    func anUntrustedClientIsRefusedWhatRunsOpensOrReads(peer: WirePeer) throws {
        let refused = "Not available in this app (it runs sandboxed)"
        let (client, folder) = try client(peer: peer)
        defer { try? FileManager.default.removeItem(at: folder) }
        client.system.searchResults = [SearchResult(name: "Notepad", path: #"C:\Windows\notepad.exe"#)]
        client.system.clipboard = "a password on the clipboard"
        client.type("@open notepad")
        client.enter()
        #expect(client.wait {
            if case .failed = client.composer.phase { return true }
            return false
        })
        #expect(client.panel.model?.status == .error(refused))
        client.escape()
        client.escape()
        // Ctrl+V in a draft: nothing read.
        client.type("@improve ")
        client.press(vk: 0x56, scan: 0x2F, text: "\u{16}", ignoringModifiers: "v", modifiers: [.control, .leftControl])
        _ = client.wait(0.3) { false }
        #expect(!client.composer.draft.contains("password"))
        client.escape()
        client.escape()
        client.type("@agent fix the bug")
        client.enter()
        _ = client.wait(0.3) { false }
        #expect(client.panel.notices.filter { $0 == refused }.count >= 2)
        #expect(client.system.opened.isEmpty && client.system.launched.isEmpty && client.system.threads.isEmpty)
        // Typing a draft still works (a rewrite of its own text is allowed).
        client.type("@improve hello")
        #expect(client.composition.hasSuffix("hello"))
    }

    @Test func aCaretIsCutToItsWindow() {
        let window = CaretRect(x: 0, y: 0, width: 100, height: 50)
        #expect(CaretRect(x: 10, y: 10, width: 2, height: 20).clamped(to: window) == CaretRect(x: 10, y: 10, width: 2, height: 20))
        #expect(CaretRect(x: 90, y: 40, width: 20, height: 20).clamped(to: window) == CaretRect(x: 90, y: 40, width: 10, height: 10))
        #expect(CaretRect(x: -500, y: -500, width: 2, height: 20).clamped(to: window) == CaretRect(x: 0, y: 0, width: 0, height: 0))
        #expect(CaretRect(x: 9_000_000, y: 9_000_000, width: -5, height: 20).clamped(to: window) == CaretRect(x: 100, y: 50, width: 0, height: 0))
        #expect(CaretRect(x: 10, y: 10, width: 2, height: 20, exact: false).clamped(to: window).exact == false)
    }
}
#endif

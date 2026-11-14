import AllInOneIMECore
@testable import AllInOneIMEWire
import Foundation
import Testing

/// Windows' sessions start a command on the selection the client reads only where the field's text may leave: never in
/// a password manager or a terminal (`ComposerSession.textStaysHere`, the Mac's `FieldInfo.textStaysHere`, 0.7.5),
/// whatever the field says of itself. The command starts there with no selection, as typed.
struct PasswordManagerSelectionTests {
    /// "@" pressed in a field of `process` (its app id `app`, else "win:<process>") with "secret" selected, as the client
    /// reads the document: the session, its draft started.
    func at(process: String, app: String? = nil) throws -> ComposerSession {
        let engine = TestEngine()
        let connection = try #require(engine.server.connect(WirePeer.trustedClient))
        var id: UInt32 = 0
        func send(_ message: ClientMessage) {
            id += 1
            _ = engine.send(ClientFrame(id: id, message), on: connection)
        }
        send(.hello(Hello(client: "test", capabilities: ["allowForeground"])))
        send(.open(sid: 1, field: WireField(app: app ?? "win:" + process, process: process, scopes: [0], layout: "00000409")))
        send(.focus(sid: 1, focus: 1, field: nil))
        let key = try #require(GoldenWriter.usKey("@"))
        let wire = WireKey(vk: key.vk, scan: key.scan, text: "@", textIgnoringModifiers: "@", modifiers: [.shift, .leftShift])
        send(.keyDown(KeyFrame(sid: 1, t: 1100, key: wire, ctx: WireContext(sel: [0, 6], before: "", selText: "secret"))))
        let session = try #require(engine.host.sessions[1])
        #expect(session.composer.draft == "@", "\(process): \(session.composer.draft)")
        return session
    }

    @Test func aPasswordManagersSelectionIsNeverTaken() throws {
        let notepad = try at(process: "notepad.exe")
        #expect(!notepad.textStaysHere && notepad.composer.selection?.text == "secret" && notepad.composer.draftInPanel)
        for process in ["1Password.exe", "Bitwarden.exe", "KeePassXC.exe"] {
            let vault = try at(process: process)
            #expect(vault.textStaysHere && vault.composer.selection == nil && !vault.composer.draftInPanel, "\(process)")
        }
        // A packaged app is known by its program too, whatever its app id.
        let packaged = try at(process: "bitwarden.exe", app: "win:8bitSolutionsLLC.bitwardendesktop_h4e712dmw3xyy!bitwardendesktop")
        #expect(packaged.textStaysHere && packaged.composer.selection == nil)
        let terminal = try at(process: "WindowsTerminal.exe")
        #expect(terminal.textStaysHere && terminal.composer.selection == nil)
    }
}

import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// ⌃V's panel shown anew as the history changes under it (`SessionEvent.clipboardHistoryChanged`, 0.7.6: an image copied
/// just before ⌃V is kept after the panel opened): the rows say what ⏎ does with an image as a panel opened with them
/// would, and a longer history's filter work for the rows before stops.
@Suite(.serialized)
struct ClipboardHistoryRefreshTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let shot = ClipboardHistoryImage(id: "def456", width: 800, height: 600, bytes: 1_048_576, thumbnail: "/tmp/def456-thumb.png")

    /// A session whose shell keeps `texts` (newest first, a minute apart), the clipboard the newest of them.
    func host(_ texts: [String]) -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.chinese, .english])
        var services = SessionServices(loadSettings: { [config] in config })
        services.levelOne = { .engine(FakeEngine()) }
        let host = FakeHost(services: services)
        host.clipboardNow = Self.now
        host.clipboardHistory = texts.enumerated().map { ClipboardHistoryItem(text: $1, copiedAt: Self.now - Double(60 * ($0 + 1))) }
        host.clipboardImages = [Self.shot.id: Data([0x89, 0x50, 0x4E, 0x47])]
        host.clipboard = .text(texts[0])
        host.keepClipboardHistory()
        host.focus()
        return host
    }

    /// An image copied, then a text, then ⌃V: the image, slow to make ready, isn't kept yet, so the panel opens with texts
    /// only; it is kept after, its row in where it was copied. Where the paste key can go to the app (the Mac's
    /// Accessibility), that row says nothing of the clipboard and ⏎ pastes it, as in a panel opened with it.
    @Test func anImageKeptAfterThePanelOpenedIsPastedByReturn() async {
        await withInterfaceLanguage("en") {
            let host = host(["newest text", "older text"])
            host.press(FakeHost.controlV)
            #expect(host.panel?.rows.map(\.text) == ["newest text", "older text"], "\(host.panel?.rows.map(\.text) ?? [])")
            host.clipboardHistory.insert(ClipboardHistoryItem(image: Self.shot, copiedAt: Self.now - 90), at: 1)
            host.send(.clipboardHistoryChanged)
            let rows = host.panel?.rows ?? []
            #expect(rows.map(\.text) == ["newest text", "Image 800 × 600", "older text"], "\(rows.map(\.text))")
            #expect(rows.count == 3 && !rows[1].comment.contains("clipboard"), "\(rows.map(\.comment))")
            host.press(FakeHost.down)
            host.press(FakeHost.enter)
            #expect(host.imagesPasted == [Self.shot.id])
        }
    }

    /// Without the paste key (no Accessibility), the kept image's row says ⏎ puts it on the clipboard, as at the panel's
    /// opening.
    @Test func withoutThePasteKeyTheImageKeptLaterSaysItGoesOnTheClipboard() async {
        await withInterfaceLanguage("en") {
            let host = host(["newest text", "older text"])
            host.passesPasteKey = false
            host.press(FakeHost.controlV)
            host.clipboardHistory.insert(ClipboardHistoryItem(image: Self.shot, copiedAt: Self.now - 90), at: 1)
            host.send(.clipboardHistoryChanged)
            let rows = host.panel?.rows ?? []
            #expect(rows.count == 3 && rows[1].comment.hasSuffix("⏎ puts it on the clipboard"), "\(rows.map(\.comment))")
        }
    }

    /// A longer history (its filter's keys worked out off the session's thread from the panel's opening): shown anew, the
    /// work for the rows before stops, as when the panel goes.
    @Test func theRowsBeforeStopTheirFilterWork() async {
        await withInterfaceLanguage("en") {
            let long = (0..<40).map { "copy \($0) " + String(repeating: "x", count: 1000) }
            let host = host(long)
            host.press(FakeHost.controlV)
            let before = host.session.clipboard.index
            #expect(before != nil, "a history this long is filtered off the session's thread")
            host.clipboardHistory.insert(ClipboardHistoryItem(image: Self.shot, copiedAt: Self.now - 30), at: 0)
            host.send(.clipboardHistoryChanged)
            #expect(host.session.clipboard.index !== before && host.session.clipboard.index != nil)
            #expect(before?.stopped == true, "the rows before still have their keys worked out")
        }
    }
}

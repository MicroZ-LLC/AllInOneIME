import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The 0.7.6 review's finding on clipboard history shown anew while its panel is up (`SessionEvent
/// .clipboardHistoryChanged`, `InputSession.clipboardHistoryChanged`), item 14: the rows shown are a page of the list
/// (`ListPage.size` at a time, from `clipboard.top`), and a click on a shown row puts in the row counted from `top`
/// (`clipboardPick`). Shown anew with a row more above, the chosen row moves down one and the page drawn follows it
/// (`ListPage.first`), but `top` stays where it was: the first row drawn is no longer the row a click on it puts in.
@Suite("0.7.6 review: clipboard history shown anew", .serialized)
struct Review076ClipboardRefreshTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

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
        host.clipboard = .text(texts[0])
        host.keepClipboardHistory()
        host.focus()
        return host
    }

    /// Item 14 (InputSession+ClipboardRefresh.swift:19). A history longer than a page, the last row of the first page
    /// chosen (↓ four times), and a copy kept after the panel opened comes in above everything: the page drawn starts a
    /// row further down, so that the chosen row is still on it. A click on the first row drawn puts that row in.
    /// (Today it puts in the row above it, the new one, which the panel doesn't show.)
    @Test func aClickOnTheFirstRowShownAfterARefreshPutsThatRowIn() async {
        await withInterfaceLanguage("en") {
            let texts = (1...8).map { "copy \($0)" }
            let host = host(texts)
            host.press(FakeHost.controlV)
            #expect(host.panel?.rows.map(\.text) == Array(texts.prefix(ListPage.size)), "\(host.panel?.rows.map(\.text) ?? [])")
            for _ in 1..<ListPage.size { host.press(FakeHost.down) }
            // Kept after the panel opened (an image slow to make ready is; a text stands for it here), newest of all.
            host.clipboardHistory.insert(ClipboardHistoryItem(text: "kept later", copiedAt: Self.now - 1), at: 0)
            host.clipboard = .text("kept later")
            host.send(.clipboardHistoryChanged)
            let shown = host.panel?.rows.map(\.text) ?? []
            guard shown.count == ListPage.size, shown.first != "kept later" else {
                Issue.record("the page shown after the refresh isn't the one the finding is about: \(shown)")
                return
            }
            #expect(shown.contains(texts[ListPage.size - 1]), "the chosen row is no longer shown: \(shown)")
            host.send(.pick(0))
            #expect(host.document == shown[0],
                    "a click on the first row shown (\"\(shown[0])\") put in \"\(host.document)\"")
        }
    }

    /// The same panel, the keys: a number key's row and ⏎'s are the rows drawn (they go by the chosen row and the page
    /// drawn already; a guard for the fix).
    @Test func returnAfterARefreshPutsTheChosenRowIn() async {
        await withInterfaceLanguage("en") {
            let texts = (1...8).map { "copy \($0)" }
            let host = host(texts)
            host.press(FakeHost.controlV)
            for _ in 1..<ListPage.size { host.press(FakeHost.down) }
            host.clipboardHistory.insert(ClipboardHistoryItem(text: "kept later", copiedAt: Self.now - 1), at: 0)
            host.clipboard = .text("kept later")
            host.send(.clipboardHistoryChanged)
            host.press(FakeHost.enter)
            #expect(host.document == texts[ListPage.size - 1], "⏎ put in \"\(host.document)\"")
        }
    }
}

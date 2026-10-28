import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Clipboard history's images (0.6.8.2, the owner: "我们能支持下图片吗？"): a kept image is a row of its own (its size, how
/// large it is, when it was copied, its thumbnail as the row's icon), ⏎ pastes it (`PlatformAction.pasteImage`), a command
/// takes it as a screenshot, ⇧↓ ⇧↑ put in the texts selected only; an image on the clipboard that is the history's newest
/// has its kept row only.
@Suite(.serialized)
struct ClipboardHistoryImageTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let shot = ClipboardHistoryImage(id: "abc123", width: 1280, height: 720, bytes: 2_516_582, thumbnail: "/tmp/abc123-thumb.png")

    /// A session whose shell keeps a screenshot (2 minutes ago) between two texts, the clipboard `clipboard`.
    func host(clipboard: ClipboardContent = .text("newest text"), newest: Bool = false) -> FakeHost {
        let engine = FakeEngine()
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.chinese, .english])
        var services = SessionServices(loadSettings: { [config] in config })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.clipboardNow = Self.now
        host.clipboardHistory = [ClipboardHistoryItem(text: "newest text", copiedAt: Self.now - 60),
                                 ClipboardHistoryItem(image: Self.shot, copiedAt: Self.now - 120),
                                 ClipboardHistoryItem(text: "older text", copiedAt: Self.now - 600)]
        host.clipboardImages = [Self.shot.id: Data([0x89, 0x50, 0x4E, 0x47])]
        host.clipboardIsNewest = newest
        host.clipboard = clipboard
        host.keepClipboardHistory()
        host.focus()
        return host
    }

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    @Test func aKeptImageIsARowWithItsSizeAndThumbnail() async {
        await inEnglish {
            let host = host()
            host.press(FakeHost.controlV)
            let rows = host.panel?.rows ?? []
            #expect(rows.map(\.text) == ["newest text", "Image 1280 × 720", "older text"], "\(rows.map(\.text))")
            #expect(rows[1].comment == "2.4 MB · 2 min ago", "\(rows[1].comment)")
            #expect(rows[1].icon?.glyph == .image(path: "/tmp/abc123-thumb.png", fallback: .image))
            #expect(rows[0].icon == nil && rows[2].icon == nil, "texts have no icon")
        }
    }

    @Test func returnPastesTheKeptImage() async {
        await inEnglish {
            let host = host()
            host.press(FakeHost.controlV)
            host.press(FakeHost.down)
            #expect(host.press(FakeHost.enter))
            #expect(host.imagesPasted == [Self.shot.id] && host.document.isEmpty && host.panel == nil)
        }
    }

    @Test func withoutThePasteKeyTheRowSaysItGoesOnTheClipboard() async {
        await inEnglish {
            let host = host()
            host.passesPasteKey = false
            host.press(FakeHost.controlV)
            #expect(host.panel?.rows[1].comment == "2.4 MB · 2 min ago · ⏎ puts it on the clipboard", "\(host.panel?.rows[1].comment ?? "-")")
            host.press(FakeHost.down)
            host.press(FakeHost.enter)
            #expect(host.imagesPasted == [Self.shot.id], "the shell leaves it on the clipboard then")
        }
    }

    @Test func aCommandTakesTheKeptImageAsAScreenshot() async {
        await inEnglish {
            let host = host()
            host.press(FakeHost.at)
            host.type("i")
            host.press(FakeHost.tab)
            host.press(FakeHost.controlV)
            host.press(FakeHost.down)
            let before = host.outputs.count
            host.press(FakeHost.enter)
            #expect(host.imagesPasted.isEmpty)
            #expect(host.composer.attachment != nil, "read as a screenshot: \(Array(host.outputs[before...]))")
        }
    }

    @Test func severalSelectedPutInTheirTextsOnly() async {
        await inEnglish {
            let host = host()
            host.press(FakeHost.controlV)
            host.press(FakeHost.shiftDown)
            host.press(FakeHost.shiftDown)
            #expect(host.press(FakeHost.enter))
            #expect(host.document == "older text\nnewest text" && host.imagesPasted.isEmpty, "\(host.document.debugDescription)")
        }
    }

    @Test func theClipboardsImageWhenItIsTheNewestHasItsKeptRowOnly() async {
        await inEnglish {
            let host = host(clipboard: .image(Data([0x89])), newest: true)
            host.clipboardHistory.insert(ClipboardHistoryItem(image: Self.shot, copiedAt: Self.now - 5), at: 0)
            host.clipboardHistory.remove(at: 2)
            host.press(FakeHost.controlV)
            #expect(host.panel?.rows.map(\.text) == ["Image 1280 × 720", "newest text", "older text"], "\(host.panel?.rows.map(\.text) ?? [])")
            let other = self.host(clipboard: .image(Data([0x89])), newest: false)
            other.press(FakeHost.controlV)
            #expect(other.panel?.rows.first?.text == "Image on the clipboard" && other.panel?.rows.first?.icon?.glyph == .builtin(.image))
        }
    }
}

import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A command's result rows turn in five-row pages with ← →. The command chooser and pinyin
/// candidates keep their own arrow keys. All keys go through a focused FakeHost field.
@Suite(.serialized)
struct ListPagingTests {
    private let left = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")

    private func listHost(count: Int) -> FakeHost {
        let folder = ScriptFolder()
        let items = (1...count).map { #"{"title":"Row \#(String(format: "%02d", $0))","arg":"\#($0)"}"# }
        let output = #"{"items":[\#(items.joined(separator: ","))]}"#
        folder.add("pages.sh", """
            #!/bin/sh
            # @allinoneime.schemaVersion 1
            # @allinoneime.title Pages
            # @allinoneime.output list
            # @allinoneime.argument1 {"type": "text", "optional": true}
            printf '%s' '\(output)'
            """)
        var services = SessionServices(loadSettings: { .default })
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        services.loadExtensions = { _, _ in folder.load() }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(.english)
        host.type("@pages")
        #expect(host.press(FakeHost.tab))
        #expect(host.composer.draftCommand?.name == "pages", "\(folder.load().commands.map(\.name)) / \(host.composer.draft)")
        #expect(host.composer.listQuery != nil, "\(String(describing: host.composer.draftCommand?.script?.output))")
        #expect(host.settle(timeout: 15) { host.composer.currentList?.items.count == count },
                "\(String(describing: host.composer.currentList?.items.map(\.title))) / \(output)")
        return host
    }

    private func clipboardHost(count: Int) -> FakeHost {
        let composer = Composer()
        composer.setInputMode(.english)
        let host = FakeHost(services: SessionServices(loadSettings: { .default }), composer: composer)
        host.clipboardNow = Date(timeIntervalSince1970: 1_000_000)
        host.clipboard = .text("Copy 01")
        host.clipboardHistory = (1...count).map { n in
            ClipboardHistoryItem(text: String(format: "Copy %02d", n),
                                 copiedAt: host.clipboardNow.addingTimeInterval(-Double(n) * 60))
        }
        host.keepClipboardHistory()
        host.focus()
        #expect(host.press(FakeHost.controlV))
        return host
    }

    private func texts(_ prefix: String, _ range: ClosedRange<Int>) -> [String] {
        range.map { String(format: "%@ %02d", prefix, $0) }
    }

    @Test func scriptListTurnsPagesAndEscapeHides() async {
        await withInterfaceLanguage("en") {
            let host = listHost(count: 12)
            #expect(host.panel?.rows.map(\.text) == texts("Row", 1...5))
            #expect(host.panel?.highlighted == 0)
            #expect(host.panel?.detail?.contains("1–5 / 12") == true)
            #expect(host.panel?.footer.contains("← → page") == true)

            #expect(host.press(FakeHost.right))
            #expect(host.panel?.rows.map(\.text) == texts("Row", 6...10))
            #expect(host.panel?.highlighted == 0)  // Row 06 is the choice.
            #expect(host.composer.listItem?.title == "Row 06")
            #expect(host.panel?.detail?.contains("6–10 / 12") == true)

            #expect(host.press(left))
            #expect(host.panel?.rows.map(\.text) == texts("Row", 1...5))
            #expect(host.panel?.highlighted == 0)
            #expect(host.press(left))
            #expect(host.panel?.rows.map(\.text) == texts("Row", 1...5))

            #expect(host.press(FakeHost.right))
            #expect(host.press(FakeHost.right))
            #expect(host.panel?.rows.map(\.text) == texts("Row", 11...12))
            #expect(host.panel?.highlighted == 0)
            #expect(host.composer.listItem?.title == "Row 11")
            #expect(host.panel?.detail?.contains("11–12 / 12") == true)
            #expect(host.press(FakeHost.right))
            #expect(host.panel?.rows.map(\.text) == texts("Row", 11...12))
            #expect(host.panel?.highlighted == 0)
            #expect(host.press(FakeHost.escape))
            #expect(host.panel == nil)
        }
    }

    @Test func clipboardHistoryTurnsPagesAndEscapeHides() async {
        await withInterfaceLanguage("en") {
            let host = clipboardHost(count: 12)
            #expect(host.panel?.rows.map(\.text) == texts("Copy", 1...5))
            #expect(host.panel?.detail?.contains("1–5 / 12") == true)
            #expect(host.panel?.footer.contains("← → page") == true)
            #expect(host.press(FakeHost.right))
            #expect(host.panel?.rows.map(\.text) == texts("Copy", 6...10))
            #expect(host.panel?.highlighted == 0)
            #expect(host.press(left))
            #expect(host.panel?.rows.map(\.text) == texts("Copy", 1...5))
            #expect(host.press(FakeHost.right))
            #expect(host.press(FakeHost.right))
            #expect(host.panel?.rows.map(\.text) == texts("Copy", 11...12))
            #expect(host.panel?.highlighted == 0)
            #expect(host.press(FakeHost.right))
            #expect(host.panel?.rows.map(\.text) == texts("Copy", 11...12))
            #expect(host.press(FakeHost.escape))
            #expect(host.panel == nil)
        }
    }

    @Test func chineseFooterNamesPagingKeys() async {
        await withInterfaceLanguage("zh") {
            let list = listHost(count: 12)
            #expect(list.panel?.footer.contains("← → 翻页") == true)
            let history = clipboardHost(count: 12)
            #expect(history.panel?.footer.contains("← → 翻页") == true)
        }
    }

    @Test func onePageListStillLetsRightHideThePanel() async {
        await withInterfaceLanguage("en") {
            let host = clipboardHost(count: 3)
            #expect(host.panel?.rows.map(\.text) == texts("Copy", 1...3))
            #expect(host.press(FakeHost.right))
            #expect(host.panel == nil)
        }
    }

    @Test func onePageScriptListStillLetsRightHideThePanel() async {
        await withInterfaceLanguage("en") {
            let host = listHost(count: 3)
            #expect(host.panel?.rows.map(\.text) == texts("Row", 1...3))
            #expect(host.press(FakeHost.right))
            #expect(host.panel == nil)
        }
    }

    @Test func firstLevelOneAtRightStillGivesTheKeyBackToTheApp() async {
        await withInterfaceLanguage("en") {
            let host = FakeHost(services: SessionServices(loadSettings: { .default }))
            host.appTypesKeys = true
            host.focus()
            host.composer.setInputMode(.english)
            host.type("@")
            #expect(host.panel != nil)
            #expect(!host.press(FakeHost.right))
            #expect(host.panel == nil)
            #expect(host.document == "@")
        }
    }

    @Test func pinyinCandidateArrowsStillReachTheEngine() async {
        await withInterfaceLanguage("en") {
            let engine = FakeEngine()
            var services = SessionServices(loadSettings: { .default })
            services.levelOne = { .engine(engine) }
            let host = FakeHost(services: services)
            host.focus()
            host.composer.setInputMode(.chinese)
            host.type("@nihao")
            #expect(host.composer.engineState.isComposing)
            #expect(host.composer.engineState.candidates.map(\.text) == ["你好", "拟好"])
            let before = engine.keys.count
            #expect(host.press(left))
            #expect(host.press(FakeHost.right))
            #expect(engine.keys.count == before + 2)
            #expect(host.composer.engineState.isComposing)
            #expect(host.composer.engineState.candidates.map(\.text) == ["你好", "拟好"])
        }
    }
}

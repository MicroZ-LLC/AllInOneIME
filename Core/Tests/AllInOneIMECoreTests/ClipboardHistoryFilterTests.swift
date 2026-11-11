import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Clipboard history's filter and pages beyond the acceptance tests: pinyin in mixed text, a long text, Chinese input
/// with marks typed, pages of what a filter keeps, ⇧↓ past a page's end and a page turned with a selection, where typing
/// doesn't filter (a page of rows, a command), and the footers that say so.
@Suite(.serialized)
struct ClipboardHistoryFilterTests {
    private let backspace = KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}")
    private let left = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")

    /// A focused field, its history `texts` (newest first, the clipboard the newest), ⌃V pressed.
    private func host(_ texts: [String], chinese: Bool = false) -> FakeHost {
        let composer = Composer()
        composer.setInputMode(chinese ? .chinese : .english)
        var services = SessionServices(loadSettings: { .default })
        if chinese { services.levelOne = { .engine(FakeEngine()) } }
        let host = FakeHost(services: services, composer: composer)
        host.clipboardNow = Date(timeIntervalSince1970: 1_000_000)
        host.clipboardHistory = texts.enumerated().map { index, text in
            ClipboardHistoryItem(text: text, copiedAt: host.clipboardNow.addingTimeInterval(-Double(index + 1) * 60))
        }
        host.clipboard = .text(texts[0])
        host.keepClipboardHistory()
        host.focus()
        #expect(host.press(FakeHost.controlV))
        return host
    }

    private func key(_ text: String) -> ClipboardFilter.Key {
        ClipboardFilter.key(.text(text, copiedAt: nil), language: "en")!
    }

    @Test func mixedTextIsFoundByItsPinyinWithTheRestAsItIs() {
        let mixed = key("发布 v2 Release，好的")
        #expect(ClipboardFilter.pinyin("发布 v2 Release，好的")?.spelled == "fabuv2release，haode")
        for found in ["fabu", "fb", "fbv2", "fabu v2 rel", "fb v2", "RELEASE", "v2 rel", "haode", "hd", "发布"] {
            #expect(ClipboardFilter.matches(mixed, found), "\(found)")
        }
        for missed in ["fbx", "fabuv3", "zz", "releasex"] {
            #expect(!ClipboardFilter.matches(mixed, missed), "\(missed)")
        }
        // Traditional characters too; a text without Chinese only by its text.
        #expect(ClipboardFilter.matches(key("發佈說明"), "fbsm") && ClipboardFilter.matches(key("發佈說明"), "fabushuo"))
        #expect(key("git status").spelled == nil && !ClipboardFilter.matches(key("git status"), "gitstatus"))
        // The permission row is never found.
        #expect(ClipboardFilter.key(.permission, language: "en") == nil)
    }

    @Test func aLongTextIsFoundByItsPinyinInItsStartAndByItsTextAnywhere() {
        let long = String(repeating: "a", count: ClipboardFilter.pinyinLength) + "你好"
        #expect(!ClipboardFilter.matches(key(long), "nihao"))
        #expect(ClipboardFilter.matches(key(long), "你好"))
        #expect(ClipboardFilter.matches(key("你好" + long), "nihao"))
    }

    @Test func chineseInputTypesMarksAsTheyAreIntoTheFilter() async throws {
        try await withInterfaceLanguage("en") {
            let texts = ["release: 42", "发布：v2", "memo 1", "memo 2", "memo 3", "memo 4", "memo 5"]
            let h = host(texts, chinese: true)
            h.type(": 4")
            try #require(h.panel?.input?.text == ": 4")
            #expect(h.panel?.rows.map(\.text) == ["release: 42"])
            #expect(h.marked.isEmpty && !h.composer.engineState.isComposing && h.panel?.candidates == nil)
            // Letters right after: still the filter's, never pinyin.
            let pinyin = host(texts, chinese: true)
            pinyin.type("fabu")
            #expect(pinyin.panel?.input?.text == "fabu" && pinyin.panel?.rows.map(\.text) == ["发布：v2"])
            #expect(!pinyin.composer.engineState.isComposing && pinyin.composer.draft.isEmpty)
            #expect(pinyin.press(FakeHost.enter) && pinyin.document == "发布：v2")
        }
    }

    @Test func aFiltersRowsTurnPagesAndBackspaceStartsAgainOnTheFirst() async throws {
        try await withInterfaceLanguage("en") {
            let h = host((1...8).map { "memo \($0)" } + (1...4).map { "note \($0)" })
            h.type("memo")
            try #require(h.panel?.detail == "Clipboard · 8 matches · 1–5 / 8")
            #expect(h.press(FakeHost.right))
            #expect(h.panel?.rows.map(\.text) == ["memo 6", "memo 7", "memo 8"] && h.panel?.highlighted == 0)
            #expect(h.press(FakeHost.right) && h.panel?.rows.first?.text == "memo 6")  // the last page: → stays
            #expect(h.press(FakeHost.down) && h.press(FakeHost.enter) && h.document == "memo 7")

            let widened = host((1...8).map { "memo \($0)" } + (1...4).map { "note \($0)" })
            widened.type("memo 8")
            #expect(widened.panel?.rows.map(\.text) == ["memo 8"])
            #expect(widened.press(FakeHost.right) && widened.panel == nil)  // one page: → hides, as Esc
            let back = host((1...8).map { "memo \($0)" } + (1...4).map { "note \($0)" })
            back.type("memo")
            _ = back.press(FakeHost.right)
            #expect(back.press(backspace) && back.panel?.input?.text == "mem")
            #expect(back.panel?.rows.first?.text == "memo 1" && back.panel?.highlighted == 0 && back.panel?.detail?.contains("1–5 / 8") == true)
        }
    }

    @Test func shiftDownPastAPagesEndKeepsTheSelectionAndAPageTurnEndsIt() async throws {
        try await withInterfaceLanguage("en") {
            let texts = (1...12).map { String(format: "Copy %02d", $0) }
            let h = host(texts)
            for _ in 0..<5 { #expect(h.press(FakeHost.shiftDown)) }
            #expect(h.panel?.rows.map(\.text) == (2...6).map { String(format: "Copy %02d", $0) })
            #expect(h.panel?.rows.map(\.label) == ["✓", "✓", "✓", "✓", "✓"] && h.panel?.detail?.contains("6 selected") == true)
            #expect(h.press(FakeHost.enter))
            #expect(h.document == (1...6).reversed().map { String(format: "Copy %02d", $0) }.joined(separator: "\n"))

            let turned = host(texts)
            _ = turned.press(FakeHost.shiftDown)
            #expect(turned.press(FakeHost.right))
            #expect(turned.panel?.rows.first?.text == "Copy 06" && turned.panel?.highlighted == 0)
            #expect(turned.panel?.rows.contains { $0.label == "✓" } == false && turned.panel?.detail?.contains("selected") == false)
            #expect(turned.press(left) && turned.panel?.rows.first?.text == "Copy 01")
        }
    }

    @Test func aPageOfRowsOrACommandKeepsTypingAsBefore() async throws {
        try await withInterfaceLanguage("en") {
            let few = host(["one", "two", "three", "four", "five"])
            #expect(few.panel?.footer == "⏎ inserts · ↑↓ to pick · ⇧↓ selects more · → or Esc hides")
            few.appTypesKeys = true
            few.press(KeyEvent(keyCode: 0, characters: "t"))
            #expect(few.panel == nil && few.document == "t")

            let command = host((1...8).map { "memo \($0)" })
            command.press(FakeHost.escape)
            command.type("@improve ")
            #expect(command.press(FakeHost.controlV))
            #expect(command.panel?.footer.contains("type to filter") == false && command.panel?.footer.contains("← → page") == true)
            command.type("m")
            #expect(command.composer.draft == "@improve m")
        }
    }

    @Test func theFooterSaysTypingFiltersAndWhatIsLeft() async throws {
        try await withInterfaceLanguage("en") {
            let h = host((1...8).map { "memo \($0)" })
            #expect(h.panel?.footer == "⏎ inserts · ↑↓ to pick · ← → page · type to filter · ⇧↓ selects more · Esc hides")
            #expect(h.panel?.footerHints.hints.map(\.key) == ["⏎", "← →", ""])
            h.type("memo 1")
            #expect(h.panel?.footer == "⏎ inserts · ↑↓ to pick · ⇧↓ selects more · → or Esc hides")
            #expect(h.panel?.input == PanelModel.Input(prompt: "filter › ", text: "memo 1", caret: 6))
            h.type("x")
            #expect(h.panel?.footer == "⌫ deletes · Esc hides" && h.panel?.detail == "Clipboard · no match")
            #expect(h.press(FakeHost.down) && h.press(FakeHost.tab) && h.document.isEmpty && h.panel?.rows.isEmpty == true)
        }
        try await withInterfaceLanguage("zh") {
            let h = host((1...8).map { "memo \($0)" })
            #expect(h.panel?.footer.contains("打字筛选") == true)
            h.type("memo")
            #expect(h.panel?.input?.prompt == "筛选 › " && h.panel?.detail?.contains("8 条匹配") == true)
        }
    }
}

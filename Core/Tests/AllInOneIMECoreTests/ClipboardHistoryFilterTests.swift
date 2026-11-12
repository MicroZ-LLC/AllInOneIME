import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Clipboard history's filter and pages beyond the acceptance tests: pinyin in mixed text, a long text, Chinese input
/// with marks typed, pages of what a filter keeps, ⇧↓ past a page's end and a page turned with a selection, a page of rows
/// filtered as more, where typing doesn't filter (a command), and the footers that say so.
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

    @Test func aPageOfRowsFiltersAsMoreAndACommandKeepsTypingAsBefore() async throws {
        try await withInterfaceLanguage("en") {
            let few = host(["one", "two", "three", "four", "five"])
            #expect(few.panel?.footer == "⏎ inserts · ↑↓ to pick · type to filter · ⇧↓ selects more · → or Esc hides")
            few.appTypesKeys = true
            #expect(few.press(KeyEvent(keyCode: 0, characters: "t")))
            #expect(few.panel?.input?.text == "t" && few.panel?.rows.map(\.text) == ["two", "three"] && few.document.isEmpty)
            #expect(few.panel?.footer == "⏎ inserts · ↑↓ to pick · ⇧↓ selects more · → or Esc hides")
            #expect(few.press(backspace) && few.panel?.rows.count == 5)
            few.press(backspace)
            #expect(few.panel == nil)  // nothing typed: ⌫ hides it and goes on, as on more rows

            let command = host((1...8).map { "memo \($0)" })
            command.press(FakeHost.escape)
            command.type("@improve ")
            #expect(command.press(FakeHost.controlV))
            #expect(command.panel?.footer.contains("type to filter") == false && command.panel?.footer.contains("← → page") == true)
            command.type("m")
            #expect(command.composer.draft == "@improve m")
        }
    }

    /// A longer history (more text than `ClipboardFilter.atOnceLength`) is never read on a key: what its rows are found
    /// by is worked out off the session's thread from when the panel opens, and each key's rows are found there too.
    /// The filter shows at once, the rows it keeps once they're found, for what is typed by then (no count before); an
    /// earlier panel's never land on one opened after. A short history is filtered on the key, as before.
    @Test func aLongerHistoryIsFilteredOffTheKey() async throws {
        try await withInterfaceLanguage("en") {
            let long = String(repeating: "长文本 long text ", count: 800)
            #expect(long.utf8.count > ClipboardFilter.atOnceLength)
            let texts = ["你好世界", long, "memo 1", "nihao"]
            let h = host(texts)
            #expect(h.session.clipboard.index != nil && host(["你好世界", "nihao"]).session.clipboard.index == nil)
            h.type("niha")
            // Nothing worked out on the keys: the filter shows, the rows are those before, without a count yet.
            #expect(h.session.clipboard.keys == nil)
            #expect(h.panel?.input?.text == "niha" && h.panel?.rows.count == 4 && h.panel?.detail == "Clipboard")
            h.type("o")
            #expect(h.settle { h.panel?.detail == "Clipboard · 2 matches" })
            #expect(h.panel?.rows.map(\.text) == ["你好世界", "nihao"] && h.panel?.highlighted == 0)
            // ⌫ to no filter: every row at once.
            for _ in 0..<5 { #expect(h.press(backspace)) }
            #expect(h.panel?.rows.count == 4 && h.panel?.input == nil)
            h.settle(timeout: 0.2) { false }  // what the keys before asked for, if any comes: not shown
            #expect(h.panel?.rows.count == 4 && h.panel?.input == nil)

            // Hidden before its rows are in, opened again on a short history: the earlier panel's never show there.
            let held = host(texts)
            held.type("nihao")
            #expect(held.waitForAnswer { if case .task(_, .clipboardFiltered) = $0 { true } else { false } })
            held.press(FakeHost.escape)
            held.clipboardHistory = ["memo 2", "nihao 2"].enumerated().map { index, text in
                ClipboardHistoryItem(text: text, copiedAt: held.clipboardNow.addingTimeInterval(-Double(index + 1) * 60))
            }
            held.clipboard = .text("memo 2")
            #expect(held.press(FakeHost.controlV) && held.session.clipboard.index == nil)
            held.settle { true }
            #expect(held.panel?.rows.map(\.text) == ["memo 2", "nihao 2"] && held.panel?.input == nil)
            held.type("nihao")
            held.settle { true }
            #expect(held.panel?.rows.map(\.text) == ["nihao 2"])
        }
    }

    /// A longer history (`aLongerHistoryIsFilteredOffTheKey`), its rows for what is typed not in yet: ⏎ or Tab is taken and
    /// puts in nothing then, never a row shown for what was typed before, and the first of the rows found goes in once
    /// they're in (none: the panel stays, "no match"); what is typed after it follows that row, never the filter's
    /// (`keysTypedAfterALongerHistorysEnterFollowItsRow`); a click on a row shown meanwhile puts nothing in.
    @Test func aLongerHistorysEnterPutsInARowOfWhatIsTypedOnly() async throws {
        try await withInterfaceLanguage("en") {
            let long = String(repeating: "长文本 long text ", count: 800)
            let texts = ["你好世界", long, "memo 1", "nihao"]
            for key in [FakeHost.enter, FakeHost.tab] {
                let h = host(texts)
                h.type("memo")
                let before = h.outputs.count
                #expect(h.press(key))
                #expect(h.document.isEmpty && h.panel?.input?.text == "memo", "\(h.document)")
                #expect(h.outputs[before...].contains(.rowsTookKey))
                #expect(h.settle { !h.document.isEmpty })
                #expect(h.document == "memo 1" && h.panel == nil)
            }

            let none = host(texts)
            none.type("zzz")
            #expect(none.press(FakeHost.enter) && none.document.isEmpty)
            #expect(none.settle { none.panel?.detail == "Clipboard · no match" })
            none.settle(timeout: 0.2) { false }
            #expect(none.document.isEmpty && none.panel?.input?.text == "zzz")

            let typedOn = host(texts)
            typedOn.type("memo")
            #expect(typedOn.press(FakeHost.enter))
            typedOn.type(" 1")
            #expect(typedOn.settle { !typedOn.document.isEmpty })
            typedOn.settle(timeout: 0.2) { false }
            #expect(typedOn.document == "memo 1 1" && typedOn.panel == nil, "\(typedOn.document)")

            let clicked = host(texts)
            clicked.type("memo")
            clicked.send(.pick(0))
            #expect(clicked.document.isEmpty && clicked.panel?.input?.text == "memo", "\(clicked.document)")
            #expect(clicked.settle { clicked.panel?.detail == "Clipboard · 1 match" })
            #expect(clicked.document.isEmpty)
            clicked.send(.pick(0))
            #expect(clicked.document == "memo 1" && clicked.panel == nil)
        }
    }

    /// A longer history, ⏎ or Tab pressed before its rows for what is typed are in, then more typed at once ("memo", ⏎,
    /// " 1"): the keys are taken, never the filter's, and follow the row once it goes in, in the order typed (the app's
    /// text as the app types it, pinyin composed with Chinese input). A key without text after it (⌫, ⏎ again) waits for
    /// the rows there and then goes on to the app, after the row and what was typed before it. Rows found for none: the
    /// panel stays, and the keys after ⏎ are its keys then (they filter).
    @Test func keysTypedAfterALongerHistorysEnterFollowItsRow() async throws {
        try await withInterfaceLanguage("en") {
            let long = String(repeating: "长文本 long text ", count: 800)
            let texts = ["你好世界", long, "memo 1", "nihao"]
            for key in [FakeHost.enter, FakeHost.tab] {
                let h = host(texts)
                h.type("memo")
                #expect(h.press(key))
                let before = h.outputs.count
                for character in " 1" { #expect(h.press(KeyEvent(keyCode: 0, characters: String(character)))) }
                #expect(h.outputs[before...].filter { $0 == .rowsTookKey }.count == 2)
                #expect(h.document.isEmpty && h.panel?.input?.text == "memo", "\(h.document)")
                let answered = h.outputs.count
                #expect(h.settle { !h.document.isEmpty })
                #expect(h.document == "memo 1 1" && h.panel == nil, "\(h.document)")
                // Handed on with no key being answered: none says the rows took one.
                #expect(!h.outputs[answered...].contains(.rowsTookKey) && !h.outputs[answered...].contains(.rowByKey))
            }

            // ⌫ after: the row and " 1" in first, then ⌫ to the app (the fake app types text only).
            let erased = host(texts)
            erased.type("memo")
            #expect(erased.press(FakeHost.enter))
            erased.type(" 1")
            #expect(!erased.press(backspace))
            #expect(erased.document == "memo 1 1" && erased.panel == nil, "\(erased.document)")
            // ⏎ right after ⏎: the row in, then ⏎ to the app (a chat app sends it).
            let sent = host(texts)
            sent.type("memo")
            #expect(sent.press(FakeHost.enter))
            #expect(!sent.press(FakeHost.enter))
            #expect(sent.document == "memo 1" && sent.panel == nil, "\(sent.document)")
            sent.settle(timeout: 0.2) { false }
            #expect(sent.document == "memo 1")

            // Chinese input: the letters after ⏎ are pinyin after the row.
            let chinese = host(texts, chinese: true)
            chinese.composer.setInputMode(.chinese)  // the field's own starting language took over at its focus
            chinese.type("memo")
            #expect(chinese.press(FakeHost.enter))
            chinese.type("ni")
            #expect(chinese.document.isEmpty && !chinese.composer.engineState.isComposing)
            #expect(chinese.settle { !chinese.document.isEmpty })
            #expect(chinese.document == "memo 1" && chinese.composer.engineState.isComposing && chinese.marked == "ni",
                    "\(chinese.document) \(chinese.marked)")

            // No row for the filter: nothing goes in, the panel stays, and what was typed after ⏎ filters.
            let none = host(texts)
            none.type("zzz")
            #expect(none.press(FakeHost.enter))
            none.type("y")
            #expect(none.panel?.input?.text == "zzz")
            #expect(none.settle { none.panel?.input?.text == "zzzy" })
            #expect(none.settle { none.panel?.detail == "Clipboard · no match" })
            #expect(none.document.isEmpty)
        }
    }

    /// A longer history's keys stop being worked out once its panel is gone (hidden, a row put in, clicked, the field
    /// left), never left to run on; and a long text's pinyin stops partway once its work is stopped.
    @Test func aLongerHistorysWorkStopsWithItsPanel() async throws {
        try await withInterfaceLanguage("en") {
            let long = String(repeating: "长文本 long text ", count: 800)
            let texts = ["你好世界", long, "memo 1", "nihao"]
            for close in ["Esc", "⏎", "click", "blur", "⌃V", "other key"] {
                let h = host(texts)
                let index = try #require(h.session.clipboard.index)
                #expect(!index.stopped)
                switch close {
                case "Esc": h.press(FakeHost.escape)
                case "⏎": h.press(FakeHost.enter)
                case "click": h.send(.pick(1))
                case "blur": h.send(.blur)
                case "⌃V": h.press(FakeHost.controlV)
                default: h.press(KeyEvent(keyCode: 0x01, characters: "s", charactersIgnoringModifiers: "s", modifiers: .command))
                }
                #expect(h.panel == nil && h.session.clipboard.index == nil, "\(close)")
                #expect(index.stopped, "\(close)")
            }
        }
        let chinese = String(repeating: "长文本", count: ClipboardFilter.pinyinLength / 3)
        #expect(ClipboardFilter.pinyin(chinese) != nil)
        let stopped = Task { () -> String? in
            withUnsafeCurrentTask { $0?.cancel() }
            return ClipboardFilter.pinyin(chinese)?.spelled
        }
        #expect(await stopped.value == nil)
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

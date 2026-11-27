import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// GitHub #178 (owner decision): one behaviour for → on every row list (clipboard history opened with ⌃V, the @ list
/// after the magic key, any other list longer than a page). Written from the issue's text by a separate agent; the
/// implementer doesn't edit it (AGENTS.md rule 11). Every key goes through a focused FakeHost field.
///
/// The spec:
/// 1. More than one page and no filter text typed: → turns to the next page (← back), as today.
/// 2. Text typed (the magic key and anything after it, e.g. "@abc", or a filter typed in the clipboard history): →
///    inserts what was typed, exactly as typed (e.g. "@abc"), closes the list and gives the keys back to the app (the →
///    itself goes to the app / the field gets no list anymore).
/// 3. A list of one page or less: → gives the keys back, as today (whatever was typed goes in as typed, as today).
@Suite(.serialized)
struct Issue178Tests {
    private let left = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")
    private let backspace = KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}")

    // MARK: - Helpers

    /// A focused field in English, where the app types the keys the input method gives back.
    private func atHost() -> FakeHost {
        let host = FakeHost(services: SessionServices(loadSettings: { .default }))
        host.appTypesKeys = true
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    /// Clipboard history open on `texts` (newest first), the newest on the clipboard.
    private func clipboardHost(_ texts: [String], chinese: Bool = false) -> FakeHost {
        let composer = Composer()
        composer.setInputMode(chinese ? .chinese : .english)
        var services = SessionServices(loadSettings: { .default })
        if chinese { services.levelOne = { .engine(FakeEngine()) } }
        let host = FakeHost(services: services, composer: composer)
        host.appTypesKeys = true
        host.clipboardNow = Date(timeIntervalSince1970: 1_000_000)
        host.clipboard = texts.first.map { .text($0) } ?? .none
        host.clipboardHistory = texts.enumerated().map { index, text in
            ClipboardHistoryItem(text: text, copiedAt: host.clipboardNow.addingTimeInterval(-Double(index + 1) * 60))
        }
        host.keepClipboardHistory()
        host.focus()
        #expect(host.press(FakeHost.controlV))
        #expect(host.panel != nil, "clipboard history opens on ⌃V")
        return host
    }

    private func copies(_ range: ClosedRange<Int>) -> [String] { range.map { String(format: "Copy %02d", $0) } }

    /// Eight "memo" rows (more than a page) among twelve.
    private var memosAndNotes: [String] { (1...8).map { "memo \($0)" } + (1...4).map { "note \($0)" } }

    // MARK: - The @ list

    /// "Text typed (the magic key and anything after it, e.g. "@abc" …): → inserts what was typed, exactly as typed
    /// (e.g. "@abc"), closes the list and gives the keys back to the app (the → itself goes to the app …)."
    /// The @ list has more rows than a page here: it is never turned by →.
    @Test func atListWithManyRowsAndLettersTypedRightInsertsItAsTyped() async throws {
        try await withInterfaceLanguage("en") {
            let host = atHost()
            host.type("@t")
            try #require(host.composer.oneAt != nil, "the @ list shows after the magic key")
            #expect(ListPage.turns(host.composer.oneAtRows.count), "more rows than a page: \(host.composer.oneAtRows.count)")
            let rows = host.panel?.rows.map(\.text)
            #expect(host.document.isEmpty)

            #expect(!host.press(FakeHost.right), "→ itself goes to the app")
            #expect(host.document == "@t", "as typed: \(host.document)")
            #expect(host.panel == nil, "the list is closed, not turned: \(String(describing: host.panel?.rows.map(\.text))) after \(String(describing: rows))")
            #expect(host.marked.isEmpty && host.composer.draft.isEmpty && host.composer.oneAt == nil)

            // The keys are the app's again: the next letter is typed by it, after the text.
            host.type("x")
            #expect(host.document == "@tx" && host.panel == nil, "\(host.document)")
        }
    }

    /// "… exactly as typed (e.g. "@abc") …": the owner's own example, whatever rows it has, and whichever row ↓ chose.
    @Test func atListRightInsertsTheOwnersExampleAsTypedWhateverRowIsChosen() async throws {
        try await withInterfaceLanguage("en") {
            for downs in [0, 2] {
                let host = atHost()
                host.type("@abc")
                try #require(host.composer.oneAt != nil)
                for _ in 0..<downs { #expect(host.press(FakeHost.down)) }
                #expect(!host.press(FakeHost.right), "→ itself goes to the app (↓ × \(downs))")
                #expect(host.document == "@abc", "as typed, never the chosen row's result (↓ × \(downs)): \(host.document)")
                #expect(host.panel == nil && host.marked.isEmpty && host.composer.oneAt == nil)
            }
        }
    }

    /// "Text typed (the magic key and anything after it …)": the magic key alone is text typed. With the @ list on more
    /// than a page and nothing after "@", → inserts "@" and gives the keys back; it doesn't turn the list.
    @Test func atListWithNothingAfterTheMagicKeyRightInsertsTheKeyAlone() async throws {
        try await withInterfaceLanguage("en") {
            let host = atHost()
            host.type("@")
            try #require(host.composer.oneAt != nil, "the @ list shows after the magic key")
            #expect(ListPage.turns(host.composer.oneAtRows.count), "more rows than a page: \(host.composer.oneAtRows.count)")
            let first = host.panel?.rows.first?.text

            #expect(!host.press(FakeHost.right), "→ itself goes to the app")
            #expect(host.document == "@", "the magic key as typed: \(host.document)")
            #expect(host.panel == nil, "not turned: \(String(describing: host.panel?.rows.first?.text)) after \(String(describing: first))")
            #expect(host.marked.isEmpty && host.composer.draft.isEmpty && host.composer.oneAt == nil)
        }
    }

    // MARK: - Clipboard history

    /// "More than one page and no filter text typed: → turns to the next page (← back), as today."
    @Test func clipboardHistoryOnMorePagesWithNoFilterRightAndLeftTurnThePage() async throws {
        try await withInterfaceLanguage("en") {
            let host = clipboardHost(copies(1...12))
            try #require(host.panel?.rows.map(\.text) == copies(1...5))
            #expect(host.press(FakeHost.right), "→ is the list's")
            #expect(host.panel?.rows.map(\.text) == copies(6...10))
            #expect(host.panel?.detail?.contains("6–10 / 12") == true)
            #expect(host.press(FakeHost.right))
            #expect(host.panel?.rows.map(\.text) == copies(11...12))
            #expect(host.press(left), "← is the list's")
            #expect(host.panel?.rows.map(\.text) == copies(6...10))
            #expect(host.press(left))
            #expect(host.panel?.rows.map(\.text) == copies(1...5))
            #expect(host.document.isEmpty, "nothing goes in: \(host.document)")
        }
    }

    /// "More than one page and no filter text typed: → turns to the next page": a filter typed and deleted again is no
    /// filter text typed.
    @Test func clipboardHistoryWithItsFilterDeletedAgainTurnsThePage() async throws {
        try await withInterfaceLanguage("en") {
            let host = clipboardHost(copies(1...12))
            host.type("co")
            try #require(host.panel?.input?.text == "co")
            #expect(host.press(backspace) && host.press(backspace))
            try #require(host.panel?.input == nil, "no filter left")
            #expect(host.panel?.rows.map(\.text) == copies(1...5))
            #expect(host.press(FakeHost.right))
            #expect(host.panel?.rows.map(\.text) == copies(6...10))
            #expect(host.document.isEmpty, "nothing goes in: \(host.document)")
        }
    }

    /// "Text typed (… a filter typed in the clipboard history): → inserts what was typed, exactly as typed …, closes the
    /// list and gives the keys back to the app". The filter keeps more rows than a page: → doesn't turn it.
    @Test func clipboardHistoryWithAFilterAndMorePagesRightInsertsTheFilterAsTyped() async throws {
        try await withInterfaceLanguage("en") {
            let host = clipboardHost(memosAndNotes)
            host.type("memo")
            try #require(host.panel?.input?.text == "memo")
            try #require(host.panel?.detail?.contains("1–5 / 8") == true, "the filter keeps more than a page: \(String(describing: host.panel?.detail))")

            host.press(FakeHost.right)
            #expect(host.document == "memo", "the filter as typed, no row: \(host.document)")
            #expect(host.panel == nil, "the list is closed, not turned: \(String(describing: host.panel?.rows.map(\.text)))")

            // The keys are the app's again: no list takes them.
            host.type("x")
            #expect(host.document == "memox" && host.panel == nil, "\(host.document)")
        }
    }

    /// "… exactly as typed …": capitals, a space and a mark in the filter go in as they were typed, whichever row ↓ chose.
    @Test func clipboardHistoryFilterGoesInExactlyAsTyped() async throws {
        try await withInterfaceLanguage("en") {
            let host = clipboardHost((1...8).map { "Memo: \($0)" } + ["other"])
            host.type("Memo: ")
            try #require(host.panel?.input?.text == "Memo: ")
            try #require(host.panel?.rows.count == 5 && host.panel?.detail?.contains("/ 8") == true)
            #expect(host.press(FakeHost.down))

            host.press(FakeHost.right)
            #expect(host.document == "Memo: ", "as typed, never the chosen row: \(host.document.debugDescription)")
            #expect(host.panel == nil)
        }
    }

    /// "… inserts what was typed, exactly as typed …": in Chinese the filter is the letters typed (no pinyin is
    /// composed in it), and they go in as letters.
    @Test func clipboardHistoryFilterTypedInChineseGoesInAsItsLetters() async throws {
        try await withInterfaceLanguage("en") {
            let host = clipboardHost((1...8).map { "你好 \($0)" } + ["other"], chinese: true)
            host.type("nihao")
            try #require(host.panel?.input?.text == "nihao")
            try #require(host.panel?.detail?.contains("1–5 / 8") == true, "\(String(describing: host.panel?.detail))")

            host.press(FakeHost.right)
            #expect(host.document == "nihao", "the letters typed: \(host.document)")
            #expect(host.panel == nil && host.marked.isEmpty && host.composer.draft.isEmpty)
        }
    }

    /// "Text typed (… a filter typed in the clipboard history): → inserts what was typed, exactly as typed, closes the
    /// list and gives the keys back": on one page of matches too, and where the filter keeps no row at all.
    @Test func clipboardHistoryWithAFilterOnOnePageOrNoMatchRightInsertsTheFilterAsTyped() async throws {
        try await withInterfaceLanguage("en") {
            let onePage = clipboardHost(memosAndNotes)
            onePage.type("note")
            try #require(onePage.panel?.rows.map(\.text) == ["note 1", "note 2", "note 3", "note 4"])
            onePage.press(FakeHost.right)
            #expect(onePage.document == "note", "the filter as typed: \(onePage.document)")
            #expect(onePage.panel == nil)

            let none = clipboardHost(memosAndNotes)
            none.type("zzz")
            try #require(none.panel?.input?.text == "zzz" && none.panel?.rows.isEmpty == true)
            none.press(FakeHost.right)
            #expect(none.document == "zzz", "the filter as typed: \(none.document)")
            #expect(none.panel == nil)
        }
    }

    /// "A list of one page or less: → gives the keys back, as today": no filter typed, nothing goes in, the list is gone
    /// and the next key is the app's.
    @Test func clipboardHistoryOnOnePageWithNoFilterRightGivesTheKeysBack() async throws {
        try await withInterfaceLanguage("en") {
            for count in [1, ListPage.size] {
                let host = clipboardHost(copies(1...count))
                try #require(host.panel?.rows.count == count)
                host.press(FakeHost.right)
                #expect(host.panel == nil, "\(count) rows: the list is closed")
                #expect(host.document.isEmpty, "\(count) rows: nothing goes in: \(host.document)")
                host.type("x")
                #expect(host.document == "x" && host.panel == nil, "\(count) rows: the keys are the app's: \(host.document)")
            }
        }
    }

    /// "A list of one page or less: → gives the keys back, as today (whatever was typed goes in as typed, as today)":
    /// the @ list on one page.
    @Test func atListOnOnePageRightGivesTheKeysBackWithTheTextAsTyped() async throws {
        try await withInterfaceLanguage("en") {
            let host = atHost()
            host.type("@abc")
            try #require(host.composer.oneAt != nil)
            try #require(!ListPage.turns(host.composer.oneAtRows.count), "one page: \(host.composer.oneAtRows.count) rows")
            #expect(!host.press(FakeHost.right), "→ itself goes to the app")
            #expect(host.document == "@abc" && host.panel == nil, "\(host.document)")
            host.type("x")
            #expect(host.document == "@abcx" && host.panel == nil, "\(host.document)")
        }
    }
}

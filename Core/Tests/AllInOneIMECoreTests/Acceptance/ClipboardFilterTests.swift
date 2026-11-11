import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Owner feedback #1 (2026-11-10): typing in clipboard history searches its kept rows.
/// Every test drives a focused field through FakeHost, including the shell's kept image.
@Suite(.serialized)
struct ClipboardFilterTests {
    private static let image = ClipboardHistoryImage(
        id: "filter-image", width: 1280, height: 720, bytes: 2_516_582,
        thumbnail: "/tmp/filter-image-thumb.png")
    private let backspace = KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}")
    private let left = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")

    private func host(chinese: Bool = false) -> FakeHost {
        let composer = Composer()
        composer.setInputMode(chinese ? .chinese : .english)
        var services = SessionServices(loadSettings: { .default })
        if chinese { services.levelOne = { .engine(FakeEngine()) } }
        let host = FakeHost(services: services, composer: composer)
        host.clipboardNow = Date(timeIntervalSince1970: 1_000_000)
        let texts = ["git status", "gist notes", "Git log", "memo 1", "memo 2", "memo 3",
                     "memo 4", "memo 5", "memo 6", "你好世界", "", "release: 42"]
        host.clipboardHistory = texts.enumerated().map { index, text in
            let copiedAt = host.clipboardNow.addingTimeInterval(-Double(index + 1) * 60)
            return index == 10 ? ClipboardHistoryItem(image: Self.image, copiedAt: copiedAt)
                : ClipboardHistoryItem(text: text, copiedAt: copiedAt)
        }
        host.clipboardImages = [Self.image.id: Data([0x89, 0x50, 0x4E, 0x47])]
        host.clipboard = .text("git status")
        host.keepClipboardHistory()
        host.focus()
        #expect(host.press(FakeHost.controlV))
        #expect(host.panel?.rows.count == 5)
        #expect(host.panel?.detail?.contains("1–5 / 12") == true)
        return host
    }

    @Test func typingFiltersCaseInsensitivelyAndReturnInsertsChosenRow() async throws {
        try await withInterfaceLanguage("en") {
            let h = host()
            let readsBefore = h.outputs.filter { if case .readClipboard = $0 { true } else { false } }.count
            h.type("git")
            try #require(h.panel?.input?.text == "git")
            #expect(h.panel?.rows.map(\.text) == ["git status", "Git log"])
            #expect(h.panel?.rows.map(\.choice) == [0, 1])
            #expect(h.panel?.detail?.contains("2 matches") == true)
            #expect(h.document.isEmpty)
            #expect(h.outputs.filter { if case .readClipboard = $0 { true } else { false } }.count == readsBefore)
            #expect(h.press(FakeHost.down))
            #expect(h.panel?.highlighted == 1)
            #expect(h.press(FakeHost.enter))
            #expect(h.document == "Git log")
            #expect(h.panel == nil)
        }
    }

    @Test func chineseInputFiltersPinyinSpellingAndInitialsWithoutComposition() async throws {
        try await withInterfaceLanguage("en") {
            for query in ["nh", "nihao"] {
                let h = host(chinese: true)
                h.type(query)
                try #require(h.panel?.input?.text == query)
                #expect(h.panel?.rows.map(\.text) == ["你好世界"])
                #expect(h.panel?.detail?.contains("1 match") == true)
                #expect(h.panel?.candidates == nil)
                #expect(h.marked.isEmpty && h.composer.draft.isEmpty)
                #expect(h.press(FakeHost.enter))
                #expect(h.document == "你好世界")
            }
        }
    }

    @Test func imageMatchesBothNamesAndSizeAndKeepsItsPreview() async throws {
        try await withInterfaceLanguage("en") {
            for query in ["image", "图片", "1280"] {
                let h = host()
                h.type(query)
                try #require(h.panel?.input?.text == query)
                #expect(h.panel?.rows.map(\.text) == ["Image 1280 × 720"])
                #expect(h.panel?.rows.first?.icon?.glyph == .image(path: Self.image.thumbnail!, fallback: .image))
                #expect(h.panel?.detail?.contains("1 match") == true)
            }
        }
    }

    @Test func backspaceBroadensResultsAndEmptyBackspaceHasOldBehavior() async throws {
        try await withInterfaceLanguage("en") {
            let h = host()
            h.type("git")
            try #require(h.panel?.input?.text == "git")
            #expect(h.press(backspace))
            #expect(h.panel?.input?.text == "gi")
            #expect(h.panel?.rows.map(\.text) == ["git status", "gist notes", "Git log"])
            #expect(h.panel?.detail?.contains("3 matches") == true)
            #expect(h.press(backspace))
            #expect(h.press(backspace))
            #expect(h.panel?.rows.count == 5)
            #expect(h.panel?.detail?.contains("1–5 / 12") == true)
            h.press(backspace)
            #expect(h.panel == nil)
        }
    }

    @Test func spacePunctuationAndDigitsArePartOfAnExistingFilter() async throws {
        try await withInterfaceLanguage("en") {
            let spaced = host()
            spaced.type("git ")
            try #require(spaced.panel?.input?.text == "git ")
            #expect(spaced.panel?.rows.map(\.text) == ["git status", "Git log"])

            let punctuation = host()
            punctuation.type(": 42")
            try #require(punctuation.panel?.input?.text == ": 42")
            #expect(punctuation.panel?.rows.map(\.text) == ["release: 42"])

            let empty = host()
            empty.press(FakeHost.space)
            #expect(empty.panel == nil)
        }
    }

    @Test func filteredRowsPageAndClickTabAndShiftSelectionUseFilteredIndices() async throws {
        try await withInterfaceLanguage("en") {
            let paged = host()
            paged.type("memo")
            try #require(paged.panel?.input?.text == "memo")
            #expect(paged.panel?.rows.map(\.text) == ["memo 1", "memo 2", "memo 3", "memo 4", "memo 5"])
            #expect(paged.panel?.detail?.contains("1–5 / 6") == true)
            #expect(paged.press(FakeHost.right))
            #expect(paged.panel?.rows.map(\.text) == ["memo 6"])
            #expect(paged.panel?.rows.map(\.choice) == [5])
            #expect(paged.panel?.detail?.contains("6–6 / 6") == true)
            #expect(paged.press(left))
            #expect(paged.panel?.rows.first?.text == "memo 1")

            let clicked = host()
            clicked.type("git")
            try #require(clicked.panel?.input?.text == "git")
            clicked.send(.pick(1))
            #expect(clicked.document == "Git log" && clicked.panel == nil)

            let tabbed = host()
            tabbed.type("git")
            try #require(tabbed.panel?.input?.text == "git")
            #expect(tabbed.press(FakeHost.down))
            #expect(tabbed.press(FakeHost.tab))
            #expect(tabbed.document == "Git log")

            let selected = host()
            selected.type("git")
            try #require(selected.panel?.input?.text == "git")
            #expect(selected.press(FakeHost.shiftDown))
            #expect(selected.panel?.rows.map(\.label) == ["✓", "✓"])
            #expect(selected.press(FakeHost.enter))
            #expect(selected.document == "Git log\ngit status")
        }
    }

    @Test func noMatchCannotInsertAndEscapeHidesFilter() async throws {
        try await withInterfaceLanguage("en") {
            let h = host()
            h.type("zzz")
            try #require(h.panel?.input?.text == "zzz")
            #expect(h.panel?.rows.isEmpty == true)
            #expect(h.panel?.detail?.contains("no match") == true)
            let before = h.outputs.count
            h.press(FakeHost.enter)
            #expect(h.document.isEmpty)
            #expect(!h.outputs.dropFirst(before).contains { if case .commit = $0 { true } else { false } })

            let escaped = host()
            escaped.type("git")
            try #require(escaped.panel?.input?.text == "git")
            #expect(escaped.press(FakeHost.escape))
            #expect(escaped.panel == nil && escaped.document.isEmpty)
        }
    }

    @Test func commandControlVKeepsExistingTypingAndPasteBehavior() async {
        await withInterfaceLanguage("en") {
            let h = host()
            h.press(FakeHost.escape)
            h.type("@improve ")
            #expect(h.composer.draft == "@improve ")
            #expect(h.press(FakeHost.controlV))
            h.type("g")
            #expect(h.panel?.rows.isEmpty == true)
            #expect(h.composer.draft == "@improve g")

            let pasted = host()
            pasted.press(FakeHost.escape)
            pasted.type("@improve ")
            #expect(pasted.press(FakeHost.controlV))
            #expect(pasted.press(FakeHost.controlV))
            #expect(pasted.composer.draft == "@improve git status")
        }
    }
}

import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Owner decisions 2026-11-14 (0.7.5), part 4: the wheel turns pages in every list shown a page at a time, as that list's
/// page keys do. A wheel notch or a trackpad's ~24 points reaches the session as `SessionEvent.scroll(steps)`, steps ≠ 0
/// (down positive). In a command's list in level two shown a page at a time (`Composer.choicesArePaged`: `@open`'s
/// results here) wheel down is →, wheel up ←; in a list as the text is typed that pages with ← → (a script extension's
/// list, `@open`'s results as you type, `@imessage`'s recipients) the same, and the cursor in the draft never moves by
/// the wheel. One page per wheel event, whatever its step count; nothing at the first or the last page; a list on one
/// page: nothing moves. Unchanged: lists that scroll a row at a time (the command list, one @'s rows, clipboard history)
/// move a row per step and stop at the ends; an AI's results and pinyin candidates on one page (the stand-in engine has
/// one; Hindi's spellings are one): nothing happens. Pinyin candidates on several pages: WheelPagingRimeTests (librime).
///
/// Through a field's session (`FakeHost`), the input on English, nothing reaching outside it: what Spotlight, the app
/// index and the address book find are stand-ins; a script extension is a real script in a folder of its own. Written
/// from the spec by a separate agent; the implementer doesn't edit it (AGENTS.md rule 11).
@Suite(.serialized)
struct OwnerDecisions075WheelTests {
    typealias Suite = OwnerDecisions075WheelTests

    static let left = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")

    /// What a list looks like in the panel: its rows, the one highlighted, which rows show ("6–10 / 12").
    struct Look: Equatable, CustomStringConvertible {
        var rows: [String]
        var highlighted: Int?
        var detail: String?

        var description: String { "\(rows) ⟨\(highlighted.map(String.init) ?? "-")⟩ \(detail ?? "")" }
    }

    static func look(_ host: FakeHost) -> Look {
        Look(rows: host.panel?.rows.map(\.text) ?? [], highlighted: host.panel?.highlighted, detail: host.panel?.detail)
    }

    /// The panel's detail says which rows show: "6–10 / 12".
    static func shows(_ host: FakeHost, _ range: String) -> Bool { host.panel?.detail?.contains(range) == true }

    /// A session in a field with the focus, letters typed as they are (English), English the interface language.
    static func host(_ configure: (inout SessionServices) -> Void = { _ in }) -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        let fixed = config
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        configure(&services)
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    /// "@" and `letters`, Tab: the command picked ("@open ").
    static func pick(_ host: FakeHost, _ letters: String) {
        host.press(FakeHost.at)
        host.type(letters)
        host.press(FakeHost.tab)
    }

    // MARK: - A command's list in level two: @open's results

    /// `@open file`, ⏎ before anything was found as it was typed: Spotlight's `count` results listed in level two (it
    /// lists nine at most: two pages).
    static func openResults(count: Int) -> FakeHost {
        let found = (1...count).map { SearchResult(name: String(format: "file %02d.txt", $0), path: String(format: "/tmp/w075/file %02d.txt", $0)) }
        let host = Suite.host { $0.searchFiles = { _, _ in found } }
        pick(host, "ope")
        host.type("file")
        #expect(host.composer.draft == "@open file", "\(host.composer.draft)")
        host.press(FakeHost.enter)
        #expect(host.settle(timeout: 10) { host.composer.isLevelTwo && host.composer.choices.count == count },
                "\(host.composer.choices.map(\.text))")
        #expect(host.composer.choicesArePaged)
        return host
    }

    /// Wheel down is →, wheel up ←: the next or previous page, its first row highlighted; nothing at the first page or
    /// the last; nothing is opened.
    @Test func levelTwoResultsTurnPagesWithTheWheel() async {
        await withInterfaceLanguage("en") {
            let host = Suite.openResults(count: 9)
            #expect(Suite.shows(host, "1–5 / 9") && host.composer.highlighted == 0, "\(Suite.look(host))")
            let first = Suite.look(host)

            host.send(.scroll(1))
            #expect(Suite.shows(host, "6–9 / 9") && host.panel?.highlighted == 0 && host.composer.highlighted == 5,
                    "wheel down: the next page, its first row (\(Suite.look(host)))")
            let right = Suite.openResults(count: 9)
            right.press(FakeHost.right)
            #expect(Suite.look(host) == Suite.look(right), "wheel down is →: \(Suite.look(host)) / \(Suite.look(right))")
            let last = Suite.look(host)
            host.send(.scroll(1))
            #expect(Suite.look(host) == last && host.composer.highlighted == 5, "the last page: nothing (\(Suite.look(host)))")

            host.send(.scroll(-1))
            #expect(Suite.look(host) == first && host.composer.highlighted == 0, "wheel up: the previous page (\(Suite.look(host)))")
            let left = Suite.openResults(count: 9)
            left.press(FakeHost.right)
            left.press(Suite.left)
            #expect(Suite.look(host) == Suite.look(left), "wheel up is ←: \(Suite.look(host)) / \(Suite.look(left))")
            host.send(.scroll(-1))
            #expect(Suite.look(host) == first && host.composer.highlighted == 0, "the first page: nothing (\(Suite.look(host)))")
            #expect(host.opened.isEmpty && host.composer.isLevelTwo, "\(host.opened)")
        }
    }

    /// A fast spin's event of 3 steps turns a page, not three rows.
    @Test func oneWheelEventTurnsOnePageInLevelTwo() async {
        await withInterfaceLanguage("en") {
            let host = Suite.openResults(count: 9)
            host.send(.scroll(3))
            #expect(Suite.shows(host, "6–9 / 9") && host.composer.highlighted == 5, "\(Suite.look(host))")
            host.send(.scroll(-3))
            #expect(Suite.shows(host, "1–5 / 9") && host.composer.highlighted == 0, "\(Suite.look(host))")
        }
    }

    /// A list of one page: nothing moves.
    @Test func aLevelTwoListOnOnePageDoesntMove() async {
        await withInterfaceLanguage("en") {
            let host = Suite.openResults(count: 3)
            let before = Suite.look(host)
            for steps in [1, -1, 3, -3] {
                host.send(.scroll(steps))
                #expect(Suite.look(host) == before && host.composer.highlighted == 0, "\(steps): \(Suite.look(host))")
            }
            #expect(host.opened.isEmpty)
        }
    }

    // MARK: - A script extension's list as you type

    /// A script extension that lists `count` rows ("Row 01" …), picked, its rows in.
    static func scriptList(count: Int) -> FakeHost {
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
        let host = Suite.host { $0.loadExtensions = { _, _ in folder.load() } }
        host.type("@pages")
        #expect(host.press(FakeHost.tab))
        #expect(host.composer.draftCommand?.name == "pages", "\(host.composer.draft)")
        #expect(host.settle(timeout: 15) { host.composer.currentList?.items.count == count },
                "\(String(describing: host.composer.currentList?.items.map(\.title)))")
        return host
    }

    static func rows(_ prefix: String, _ range: ClosedRange<Int>) -> [String] {
        range.map { String(format: "%@ %02d", prefix, $0) }
    }

    /// Wheel down and up turn its page as → and ← do; the draft and its cursor stay.
    @Test func aScriptListAsYouTypeTurnsPagesWithTheWheel() async {
        await withInterfaceLanguage("en") {
            let host = Suite.scriptList(count: 12)
            let (draft, cursor) = (host.composer.draft, host.composer.cursorTailCount)
            #expect(Suite.look(host).rows == Suite.rows("Row", 1...5), "\(Suite.look(host))")

            host.send(.scroll(1))
            #expect(Suite.look(host).rows == Suite.rows("Row", 6...10) && host.panel?.highlighted == 0
                    && host.composer.listItem?.title == "Row 06", "wheel down: \(Suite.look(host))")
            let right = Suite.scriptList(count: 12)
            right.press(FakeHost.right)
            #expect(Suite.look(host) == Suite.look(right), "wheel down is →: \(Suite.look(host)) / \(Suite.look(right))")

            host.send(.scroll(-1))
            #expect(Suite.look(host).rows == Suite.rows("Row", 1...5) && host.composer.listItem?.title == "Row 01",
                    "wheel up: \(Suite.look(host))")
            let leftTwin = Suite.scriptList(count: 12)
            leftTwin.press(FakeHost.right)
            leftTwin.press(Suite.left)
            #expect(Suite.look(host) == Suite.look(leftTwin), "wheel up is ←: \(Suite.look(host)) / \(Suite.look(leftTwin))")
            host.send(.scroll(-1))
            #expect(Suite.look(host).rows == Suite.rows("Row", 1...5) && host.composer.listItem?.title == "Row 01",
                    "the first page: nothing (\(Suite.look(host)))")

            host.send(.scroll(3))
            #expect(Suite.look(host).rows == Suite.rows("Row", 6...10), "one page per event: \(Suite.look(host))")
            host.send(.scroll(1))
            #expect(Suite.look(host).rows == Suite.rows("Row", 11...12) && host.composer.listItem?.title == "Row 11", "\(Suite.look(host))")
            host.send(.scroll(1))
            #expect(Suite.look(host).rows == Suite.rows("Row", 11...12) && host.composer.listItem?.title == "Row 11",
                    "the last page: nothing (\(Suite.look(host)))")
            #expect(host.composer.draft == draft && host.composer.cursorTailCount == cursor, "\(host.composer.draft)")
        }
    }

    /// On one page nothing moves: not the highlight, not the cursor in the draft, and the rows stay up.
    @Test func aScriptListOnOnePageDoesntMove() async {
        await withInterfaceLanguage("en") {
            let host = Suite.scriptList(count: 3)
            let (draft, cursor, before) = (host.composer.draft, host.composer.cursorTailCount, Suite.look(host))
            for steps in [1, -1, 3, -3] {
                host.send(.scroll(steps))
                #expect(Suite.look(host) == before && host.composer.listItem?.title == "Row 01", "\(steps): \(Suite.look(host))")
                #expect(host.composer.draft == draft && host.composer.cursorTailCount == cursor, "\(steps): \(host.composer.draft)")
            }
        }
    }

    // MARK: - @open's results as you type

    /// `@open sun`: `count` results known at once (the app index's), on the key.
    static func openAsYouType(count: Int) -> FakeHost {
        let found = (1...count).map { SearchResult(name: "sun \($0).txt", path: "/Users/me/w075/sun \($0).txt") }
        let host = Suite.host { $0.instantResults = { _, _ in found } }
        pick(host, "ope")
        host.type("sun")
        #expect(host.composer.draft == "@open sun" && host.composer.currentLiveResults.count == min(count, Composer.liveRowLimit),
                "\(host.composer.draft): \(host.composer.currentLiveResults.map(\.name))")
        return host
    }

    @Test func openAsYouTypeTurnsPagesWithTheWheel() async {
        await withInterfaceLanguage("en") {
            let host = Suite.openAsYouType(count: 8)
            let (draft, cursor) = (host.composer.draft, host.composer.cursorTailCount)
            #expect(Suite.shows(host, "1–5 / 8") && host.composer.liveHighlight == 0, "\(Suite.look(host))")
            let first = Suite.look(host)

            host.send(.scroll(1))
            #expect(Suite.shows(host, "6–8 / 8") && host.composer.liveHighlight == 5 && host.composer.liveFirstShown == 5,
                    "wheel down: \(Suite.look(host))")
            let right = Suite.openAsYouType(count: 8)
            right.press(FakeHost.right)
            #expect(Suite.look(host) == Suite.look(right), "wheel down is →: \(Suite.look(host)) / \(Suite.look(right))")
            host.send(.scroll(1))
            #expect(Suite.shows(host, "6–8 / 8") && host.composer.liveHighlight == 5, "the last page: nothing (\(Suite.look(host)))")

            host.send(.scroll(-1))
            #expect(Suite.look(host) == first && host.composer.liveHighlight == 0, "wheel up: \(Suite.look(host))")
            host.send(.scroll(-1))
            #expect(Suite.look(host) == first && host.composer.liveHighlight == 0, "the first page: nothing (\(Suite.look(host)))")
            #expect(host.composer.draft == draft && host.composer.cursorTailCount == cursor && host.opened.isEmpty)
        }
    }

    // MARK: - @imessage's recipients

    /// `@imessage person`: `count` people in the address book as last read, found on the key.
    static func recipients(count: Int) -> FakeHost {
        let book = (1...count).map { Contact(name: String(format: "Person %02d", $0), handles: [String(format: "+1 555 01%02d", $0)]) }
        let host = Suite.host {
            $0.loadContacts = { book }
            $0.cachedContacts = { book }
        }
        host.type("@imessage")
        host.press(FakeHost.tab)
        host.type("person")
        #expect(host.settle(timeout: 5) { host.composer.currentRecipients.count == count },
                "\(host.composer.draft): \(host.composer.currentRecipients.map(\.name))")
        return host
    }

    /// Eight recipients (the most listed): two pages.
    @Test func recipientsTurnPagesWithTheWheel() async {
        await withInterfaceLanguage("en") {
            let host = Suite.recipients(count: 8)
            let (draft, cursor) = (host.composer.draft, host.composer.cursorTailCount)
            #expect(Suite.shows(host, "1–5 / 8") && host.composer.recipientHighlight == 0, "\(Suite.look(host))")
            let first = Suite.look(host)

            host.send(.scroll(1))
            #expect(host.composer.recipientHighlight == 5 && host.composer.recipientFirstShown == 5 && Suite.shows(host, "6–8 / 8"),
                    "wheel down: \(Suite.look(host))")
            let right = Suite.recipients(count: 8)
            right.press(FakeHost.right)
            #expect(Suite.look(host) == Suite.look(right), "wheel down is →: \(Suite.look(host)) / \(Suite.look(right))")
            host.send(.scroll(1))
            #expect(host.composer.recipientHighlight == 5 && Suite.shows(host, "6–8 / 8"), "the last page: nothing (\(Suite.look(host)))")

            host.send(.scroll(-1))
            #expect(Suite.look(host) == first && host.composer.recipientHighlight == 0, "wheel up: \(Suite.look(host))")
            host.send(.scroll(-1))
            #expect(Suite.look(host) == first && host.composer.recipientHighlight == 0, "the first page: nothing (\(Suite.look(host)))")
            host.send(.scroll(3))
            #expect(host.composer.recipientHighlight == 5 && Suite.shows(host, "6–8 / 8"), "a page per event, not rows: \(Suite.look(host))")
            #expect(host.composer.draft == draft && host.composer.cursorTailCount == cursor && host.composer.messageRecipient == nil,
                    "\(host.composer.draft)")
        }
    }

    /// Recipients on one page: nothing moves, the cursor stays.
    @Test func recipientsOnOnePageDontMove() async {
        await withInterfaceLanguage("en") {
            let host = Suite.recipients(count: 3)
            let (draft, cursor, before) = (host.composer.draft, host.composer.cursorTailCount, Suite.look(host))
            for steps in [1, -1, 3] {
                host.send(.scroll(steps))
                #expect(Suite.look(host) == before && host.composer.recipientHighlight == 0, "\(steps): \(Suite.look(host))")
                #expect(host.composer.draft == draft && host.composer.cursorTailCount == cursor, "\(steps): \(host.composer.draft)")
            }
        }
    }

    // MARK: - Unchanged: lists that scroll a row at a time

    /// The command list (the magic key alone): a row per step, stopping at the first.
    @Test func theCommandListStillMovesARowPerStep() async {
        await withInterfaceLanguage("en") {
            let host = Suite.host()
            host.press(FakeHost.at)
            #expect((host.panel?.rows.count ?? 0) > 3 && host.panel?.highlighted == 0, "\(Suite.look(host))")
            let first = host.panel?.rows.first?.text
            host.send(.scroll(1))
            #expect(host.panel?.highlighted == 1, "\(Suite.look(host))")
            host.send(.scroll(2))
            #expect(host.panel?.highlighted == 3, "\(Suite.look(host))")
            host.send(.scroll(-10))
            #expect(host.panel?.highlighted == 0 && host.panel?.rows.first?.text == first, "stops at the first: \(Suite.look(host))")
        }
    }

    /// One @'s rows for a text: a row per step, stopping at the ends.
    @Test func oneAtsRowsStillMoveARowPerStep() async {
        await withInterfaceLanguage("en") {
            let host = Suite.host()
            host.press(FakeHost.at)
            host.type("thank you for the gift")
            let count = host.panel?.rows.count ?? 0
            #expect(count >= 2 && host.panel?.highlighted == 0, "\(Suite.look(host))")
            host.send(.scroll(1))
            #expect(host.panel?.highlighted == 1, "\(Suite.look(host))")
            host.send(.scroll(20))
            #expect(host.panel?.highlighted == count - 1, "stops at the last: \(Suite.look(host))")
            host.send(.scroll(-20))
            #expect(host.panel?.highlighted == 0, "stops at the first: \(Suite.look(host))")
        }
    }

    /// Clipboard history: a row per step (not a page), stopping at the last.
    @Test func clipboardHistoryStillMovesARowPerStep() async {
        await withInterfaceLanguage("en") {
            let composer = Composer()
            composer.setInputMode(.english)
            let host = FakeHost(services: SessionServices(loadSettings: { .default }), composer: composer)
            host.clipboardNow = Date(timeIntervalSince1970: 1_000_000)
            host.clipboard = .text("item 0")
            host.clipboardHistory = (0..<8).map { ClipboardHistoryItem(text: "item \($0)", copiedAt: host.clipboardNow.addingTimeInterval(-Double($0) * 60)) }
            host.keepClipboardHistory()
            host.focus()
            #expect(host.press(FakeHost.controlV))
            #expect(Suite.look(host).rows == (0..<5).map { "item \($0)" } && host.panel?.highlighted == 0, "\(Suite.look(host))")
            host.send(.scroll(1))
            #expect(host.panel?.highlighted == 1 && Suite.look(host).rows.first == "item 0", "a row: \(Suite.look(host))")
            host.send(.scroll(2))
            #expect(host.panel?.highlighted == 3 && Suite.look(host).rows.first == "item 0", "two rows: \(Suite.look(host))")
            host.send(.scroll(20))
            #expect(host.panel?.highlighted == 4 && Suite.look(host).rows.last == "item 7", "stops at the last: \(Suite.look(host))")
            #expect(host.document.isEmpty)
        }
    }

    // MARK: - Unchanged: nothing to page

    /// The on-device model stand-in: answers every request with one line.
    final class Model: AppleModelBackend, @unchecked Sendable {
        let availability = AppleModelAvailability.available
        let contextSize = 4096
        let supportedLanguages: Set<String> = ["en", "zh"]

        func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(AppleModelSnapshot(text: "EN: Hello there.\nEN: Hi there.\nEN: Hey there."))
                continuation.finish()
            }
        }
    }

    /// An AI's results (`@improve`'s versions) aren't paged: the wheel does nothing there.
    @Test func anAIsResultsDontMoveWithTheWheel() async {
        await withInterfaceLanguage("en") {
            var config = Config.default
            config.uiLanguage = "en"
            config.provider = .apple
            config.setOrder([OutputLanguage.english])
            let fixed = config
            let host = Suite.host {
                $0.converter = Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: Model())
                $0.loadSettings = { fixed }
            }
            Suite.pick(host, "imp")
            host.type("hello there")
            host.press(FakeHost.enter)
            #expect(host.settle(timeout: 5) { host.composer.phase == .choosing && !(host.panel?.rows.isEmpty ?? true) },
                    "\(host.composer.phase) \(Suite.look(host))")
            #expect(!host.composer.choicesArePaged)
            let (before, highlighted) = (Suite.look(host), host.composer.highlighted)
            for steps in [1, -1, 3] {
                host.send(.scroll(steps))
                #expect(Suite.look(host) == before && host.composer.highlighted == highlighted, "\(steps): \(Suite.look(host))")
            }
            #expect(host.document.isEmpty, "nothing put in: \(host.document)")
        }
    }

    /// Pinyin candidates on one page (the stand-in engine's): nothing is committed, the composition stays.
    @Test func pinyinCandidatesOnOnePageDontMove() async {
        await withInterfaceLanguage("en") {
            let host = Suite.host()
            host.composer.setInputMode(.chinese)
            host.type("nihao")
            let state = host.composer.engineState
            #expect(state.isComposing && state.candidates.map(\.text) == ["你好", "拟好"], "\(state)")
            for steps in [1, -1, 3] {
                host.send(.scroll(steps))
                let now = host.composer.engineState
                #expect(now.isComposing && now.candidates == state.candidates && now.highlighted == state.highlighted
                        && host.composer.engine?.rawInput == "nihao" && host.document.isEmpty, "\(steps): \(now)")
            }
        }
    }

    /// Hindi's spellings are one page: nothing happens.
    @Test func hindiSpellingsDontMove() async {
        await withInterfaceLanguage("en") {
            var config = Config.default
            config.uiLanguage = "en"
            config.setOrder([Language.english, .hindi])
            let fixed = config
            let host = Suite.host {
                $0.loadSettings = { fixed }
                $0.hindiTables = { PackData.hindi }
            }
            host.composer.setInputMode(.hindi)
            host.type("kamra")
            let state = host.composer.engineState
            #expect(state.isComposing && state.candidates.count > 1, "\(state)")
            for steps in [1, -1, 3] {
                host.send(.scroll(steps))
                let now = host.composer.engineState
                #expect(now.isComposing && now.candidates == state.candidates && now.highlighted == state.highlighted
                        && host.document.isEmpty, "\(steps): \(now)")
            }
        }
    }
}

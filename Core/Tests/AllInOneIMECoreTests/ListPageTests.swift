import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A command's result list a page at a time (`ListPage`): the pages themselves, a script's list with a row of
/// information where a page starts, the cursor's ← → on one page, a list in level two (digits and clicks still pick the
/// row they name), the recipients, and the footer's keycaps.
struct ListPageTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    let left = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")
    let right = KeyEvent(keyCode: VirtualKey.right, characters: "\u{F703}")

    func type(_ s: String, _ c: Composer) {
        for ch in s { _ = c.handleKeyDown(ch == "@" ? at : ch == " " ? spaceKey : k(String(ch))) }
    }

    func panel(_ c: Composer) -> PanelModel { PanelPresenter(config: .default, language: "en").model(for: c) }

    @Test func pagesTurnFromWhereTheListWasLeft() {
        #expect(ListPage.first(top: 0, chosen: 3, count: 4) == 0)
        #expect(ListPage.first(top: 0, chosen: 5, count: 12) == 1)  // ↓ past the page: scrolled by a row
        #expect(ListPage.first(top: 10, chosen: 11, count: 12) == 10)  // a short last page stays while the choice is on it
        #expect(ListPage.first(top: 10, chosen: 9, count: 12) == 7)  // ↑ off it: a whole page again
        #expect(ListPage.first(top: 7, chosen: 0, count: 12) == 0)  // round the end
        #expect(ListPage.turned(1, first: 1, count: 12) == 6 && ListPage.turned(-1, first: 1, count: 12) == 0)
        #expect(ListPage.turned(1, first: 7, count: 12) == nil)  // the last row shown: no page after
        #expect(ListPage.turned(-1, first: 0, count: 12) == nil && ListPage.turned(1, first: 0, count: 5) == nil)
        #expect(ListPage.window(first: 10, count: 12) == 10..<12)
        #expect(ListPage.position(10..<12, count: 12) == "11–12 / 12" && ListPage.position(0..<5, count: 5) == nil)
    }

    @Test func aScriptListPageStartsOnItsFirstRowToPickAndKeepsTheCursor() throws {
        let folder = ScriptFolder()
        folder.add("people.sh", script(["output list", "input optional"], "echo"))
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.commands = Command.catalog([], scripts: folder.load().commands)
        type("@people x", c)
        let query = try #require(c.listQuery)
        // Row 6, where the second page starts, is information: → goes on to row 7.
        let items = (1...12).map { ScriptItem(title: "Row \($0)", arg: String($0), valid: $0 != 6) }
        _ = c.receiveList(.list(ScriptList(items: items)), for: query)
        #expect(panel(c).rows.map(\.text) == (1...5).map { "Row \($0)" })
        #expect(c.handleKeyDown(right).effects == [.showPanel])
        #expect(c.listItem?.title == "Row 7" && c.draft == "@people x" && c.cursorTailCount == 0)
        let second = panel(c)
        #expect(second.rows.map(\.text) == (6...10).map { "Row \($0)" } && second.highlighted == 1)
        #expect(second.rows.map(\.choice) == [5, 6, 7, 8, 9] && second.detail == "6–10 / 12")
        #expect(second.footer.contains("↑↓ choose · ← → page · Tab complete"))
        // A click picks the row clicked, by its place in the whole list.
        let picked = c.choose(index: try #require(second.rows[3].choice))
        #expect(commits(picked) == ["9"])
    }

    @Test func oneScriptPageKeepsTheCursorsArrowsAndRightAtTheEndHides() throws {
        let folder = ScriptFolder()
        folder.add("people.sh", script(["output list", "input optional"], "echo"))
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.commands = Command.catalog([], scripts: folder.load().commands)
        type("@people xy", c)
        _ = c.receiveList(.list(ScriptList(items: [ScriptItem(title: "Jane", arg: "jane")])), for: try #require(c.listQuery))
        #expect(c.handleKeyDown(left).effects == [.updateMarkedText] && c.cursorTailCount == 1)
        // → in the text moves the cursor; at its end it hides the rows, as Esc.
        #expect(c.handleKeyDown(right).effects == [.updateMarkedText] && c.cursorTailCount == 0 && c.draft == "@people xy")
        let hidden = c.handleKeyDown(right)
        #expect(hidden.handled && hidden.effects.contains(.hidePanel) && c.draft.isEmpty)
    }

    @Test func aListInLevelTwoTurnsPagesAndDigitsStillPickTheirRow() throws {
        let found = (1...9).map { SearchResult(name: "file \($0).txt", path: "/tmp/file \($0).txt") }
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        type("@o", c)
        _ = c.handleKeyDown(tab)
        type("file", c)
        _ = c.handleKeyDown(enterKey)
        _ = c.receiveSearch(found, id: 1)
        #expect(c.choicesArePaged && panel(c).rows.map(\.label) == ["1", "2", "3", "4", "5"])
        #expect(c.handleKeyDown(left).effects.isEmpty)  // the first page: ← stays
        _ = c.handleKeyDown(right)
        let second = panel(c)
        #expect(c.highlighted == 5 && second.highlighted == 0 && second.rows.map(\.label) == ["6", "7", "8", "9"])
        #expect(second.rows.map(\.choice) == [5, 6, 7, 8] && second.detail == "6–9 / 9")
        #expect(second.footer.contains("← → page") && second.hints.map(\.key).contains("← →"))
        #expect(c.handleKeyDown(right).effects.isEmpty && c.highlighted == 5)  // the last page: → stays
        // ↑ from the page's first row scrolls back a row; a digit picks its row wherever the page is.
        _ = c.handleKeyDown(upKey)
        #expect(panel(c).rows.first?.label == "5" && panel(c).highlighted == 0)
        #expect(c.handleKeyDown(k("2")).effects.last == .open(path: found[1].path))
    }

    @Test func anAIsResultsKeepTheirArrows() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        type("@imp", c)
        _ = c.handleKeyDown(tab)
        type("nihao", c)
        _ = c.handleKeyDown(spaceKey)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: (1...7).map { CandidateLine("Version \($0).") }), isFinal: true, id: 1)
        #expect(c.choices.count == 8 && !c.choicesArePaged && panel(c).rows.count == 8)
        #expect(c.handleKeyDown(right).effects.isEmpty && !panel(c).footer.contains("← →"))
    }

    @Test func recipientsTurnPagesAndKeepTheirNumbers() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        type("@ime", c)
        _ = c.handleKeyDown(tab)
        type("zs", c)
        let found = (1...8).map { Recipient(name: "张\($0)", handle: "+1 555 010\($0)") }
        _ = c.receiveRecipients(found, for: "zs")
        _ = c.handleKeyDown(right)
        let second = panel(c)
        #expect(c.recipientHighlight == 5 && second.rows.map(\.label) == ["6", "7", "8"] && second.highlighted == 0)
        #expect(second.footer.contains("↑↓ · ← → page · Esc cancel") && second.detail == "6–8 / 8")
        _ = c.handleKeyDown(tab)
        #expect(c.messageRecipient == found[5])
    }

    @Test func theFootersArrowsAreOneKeycap() {
        let model = PanelModel(footer: "⏎ pick · ↑↓ choose · ← → page · Tab complete · Esc cancel")
        #expect(model.footerHints.hints == [PanelModel.Hint("⏎", "pick"), PanelModel.Hint("← →", "page"), PanelModel.Hint("Tab", "complete")])
    }
}

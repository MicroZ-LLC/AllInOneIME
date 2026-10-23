import CoreGraphics
import Foundation
import Testing
@testable import AllInOneIMECore

/// A row clicked in the candidate panel (`Composer.choose`): picked as its digit, or the action key on it
/// highlighted, would pick it, whatever the panel shows.
struct ClickPickTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    func type(_ s: String, _ c: Composer) {
        for ch in s { _ = c.handleKeyDown(ch == "@" ? at : ch == " " ? spaceKey : k(String(ch))) }
    }

    @Test func aPinyinCandidate() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        type("nihao", c)
        let picked = c.choose(index: 1)
        #expect(commits(picked) == ["拟好"] && !c.isComposing && picked.contains(.hidePanel))
        // In a command's text, the word goes into it.
        type("@imp", c)
        _ = c.handleKeyDown(tab)
        type("nihao", c)
        #expect(commits(c.choose(index: 0)).isEmpty && c.draft == "@improve 你好")
        // Past the candidates: nothing.
        type("wo", c)
        #expect(c.choose(index: 7).isEmpty && c.engineState.isComposing)
    }

    @Test func aHindiSpelling() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.hindiTables = PackData.hindi
        c.inputLanguages = [.english, .hindi]
        c.setInputMode(.hindi)
        type("kamra", c)
        let spellings = c.engineState.candidates.map(\.text)
        #expect(spellings.count > 1)
        #expect(commits(c.choose(index: 1)) == [spellings[1]] && !c.isComposing)
    }

    @Test func aCommandOfTheList() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        type("@", c)
        let second = c.paletteVisible[c.paletteFirstVisible + 1]
        _ = c.choose(index: 1)
        #expect(c.draft == "@\(second.name) ")
        // Scrolled down the list: the row clicked among those shown.
        let d = Composer(engine: FakeEngine(), actionKey: .enter)
        type("@", d)
        for _ in 0..<6 { _ = d.handleKeyDown(downKey) }
        let shown = Array(d.paletteVisible)
        _ = d.choose(index: 0)
        #expect(d.draft == "@\(shown[0].name) ")
    }

    @Test func aResultInLevelTwo() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        type("@imp", c)
        _ = c.handleKeyDown(tab)
        type("nihao", c)
        _ = c.handleKeyDown(spaceKey)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("Hi."), CandidateLine("Hello.")]), isFinal: true, id: 1)
        #expect(c.choices.map(\.label) == ["0", "1", "2"])
        #expect(commits(c.choose(index: 2)) == ["Hello."] && c.phase == .idle)
    }

    @Test func onlyRowsThatCanBePickedLightUp() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        type("@imp", c)
        _ = c.handleKeyDown(tab)
        type("nihao", c)
        _ = c.handleKeyDown(spaceKey)
        _ = c.handleKeyDown(enterKey)
        // Still coming in: the row isn't picked by a click, nor highlighted under the pointer.
        _ = c.receive(ConversionResult(versions: [CandidateLine("Hi", isComplete: false)]), isFinal: false, id: 1)
        #expect(c.choices.map(Composer.picks) == [true, false] && c.choose(index: 1).isEmpty && c.isLevelTwo)
        _ = c.receive(ConversionResult(versions: [CandidateLine("Hi.")]), isFinal: true, id: 1)
        #expect(c.choices.map(Composer.picks) == [true, true])
        // A row of information, a line a script printed: never; the issue to open: also without a title.
        let info = Composer.Choice(label: "", kind: .item(ScriptItem(title: "People", valid: false)), text: "People", isComplete: true)
        let shown = Composer.Choice(label: "", kind: .shown, text: "50%", isComplete: true)
        let issue = Composer.Choice(label: "⏎", kind: .issue(URL(string: IssueReport.newIssueAddress)!), text: "", isComplete: true)
        #expect(!Composer.picks(info) && !Composer.picks(shown) && Composer.picks(issue))
    }

    @Test func aFileFoundByOpen() {
        let report = SearchResult(name: "report.pdf", path: "/Users/me/report.pdf")
        let notes = SearchResult(name: "notes.md", path: "/Users/me/notes.md")
        // As you type: opens the result clicked, the highlight wherever it was.
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        type("@o", c)
        _ = c.handleKeyDown(tab)
        type("re", c)
        _ = c.receiveLive([report, notes], for: "re")
        let opened = c.choose(index: 1)
        #expect(opened.last == .open(path: notes.path) && commits(opened).isEmpty && c.phase == .idle)
        // Listed after ⏎ (level two): the same.
        let d = Composer(engine: FakeEngine(), actionKey: .enter)
        type("@o", d)
        _ = d.handleKeyDown(tab)
        type("xyz", d)
        _ = d.handleKeyDown(enterKey)
        _ = d.receiveSearch([report, notes], id: 1)
        #expect(d.choose(index: 0).last == .open(path: report.path))
    }

    @Test func aRecipient() {
        let zhang = Recipient(name: "张三", handle: "+1 555 0100"), si = Recipient(name: "张思", handle: "zs@example.com")
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        type("@ime", c)
        _ = c.handleKeyDown(tab)
        type("zs", c)
        _ = c.receiveRecipients([zhang, si], for: "zs")
        _ = c.choose(index: 1)
        #expect(c.messageRecipient == si && c.draft == "@imessage ")
    }

    @Test func aRowOfAScriptsList() throws {
        let folder = ScriptFolder()
        folder.add("people.sh", script(["output list", "input optional"], "echo"))
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.commands = Command.catalog([], scripts: folder.load().commands)
        type("@people x", c)
        let query = try #require(c.listQuery)
        _ = c.receiveList(.list(ScriptList(items: [ScriptItem(title: "People", valid: false),
                                                   ScriptItem(title: "Jane", arg: "jane@example.com"),
                                                   ScriptItem(title: "John", arg: "john@example.com")])), for: query)
        // A row of information does nothing; a row to pick does its action (here insert its arg).
        #expect(c.choose(index: 0).isEmpty && c.draft == "@people x")
        let inserted = c.choose(index: 2)
        #expect(commits(inserted) == ["john@example.com"] && inserted.contains(.commandUsed("people")) && !c.isComposing)
    }

    @Test func nothingWhileListening() {
        let c = Composer(engine: FakeEngine(), voiceEnabled: true, actionKey: .enter)  // as if voice input were on
        type("@imp", c)
        _ = c.handleKeyDown(tab)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.rightOption, modifiers: [.option, .rightOption], timestamp: 0)
        _ = c.voiceHoldElapsed()
        #expect(c.voice != .off && c.choose(index: 0).isEmpty)
    }

    @Test func hitTesting() {
        let frames = [CGRect(x: 6, y: 6, width: 200, height: 24), CGRect(x: 6, y: 30, width: 200, height: 24),
                      CGRect(x: 6, y: 54, width: 200, height: 24)]
        #expect(CandidateLayout.row(at: CGPoint(x: 50, y: 40), frames: frames, pickable: [true, true, true]) == 1)
        #expect(CandidateLayout.row(at: CGPoint(x: 50, y: 10), frames: frames, pickable: [true, true, true]) == 0)
        // Outside every row (the padding, the footer), or on a row nothing picks.
        #expect(CandidateLayout.row(at: CGPoint(x: 2, y: 40), frames: frames, pickable: [true, true, true]) == nil)
        #expect(CandidateLayout.row(at: CGPoint(x: 50, y: 90), frames: frames, pickable: [true, true, true]) == nil)
        #expect(CandidateLayout.row(at: CGPoint(x: 50, y: 60), frames: frames, pickable: [true, true, false]) == nil)
        #expect(CandidateLayout.row(at: CGPoint(x: 50, y: 60), frames: frames, pickable: [true]) == nil)
    }
}

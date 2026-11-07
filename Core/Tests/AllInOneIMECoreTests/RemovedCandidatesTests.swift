import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// librime as a candidate the user removed meets it: pages of five, numbered 1–5; ↑↓ move the highlight, on to the next
/// page past the last (its first) or the previous past the first (its last); Page Up and Down, - and =, turn the page
/// (the highlight on its first); Space and the digits pick on the page, , and . the highlighted one and their mark, [ and ]
/// its first or last character (rime-ice's `select_character`), ⏎ the letters as typed, the composition the highlighted
/// one. A candidate deleted (`deleteCandidate`: a word of the dictionary never learned) stays where it is, recorded; with
/// `resetsOnDelete`, as librime's `delete_candidate` does, the composition is laid out anew from its first page.
final class PagesEngine: PinyinEngine {
    var pages: [String: [String]]
    var input = ""
    var highlighted = 0
    var page = 0
    /// Every key given, in order.
    var keys: [Int32] = []
    /// Every candidate deleted, by its page, its place on it and its text.
    var deleted: [String] = []
    /// A candidate deleted puts the page and the highlight back on the first, as librime's `delete_candidate`.
    var resetsOnDelete = false
    private var commit: String?
    static let pageSize = 5

    init(_ pages: [String: [String]]) { self.pages = pages }

    var all: [String] { pages[input] ?? [input] }
    var onPage: [String] { Array(all.dropFirst(page * Self.pageSize).prefix(Self.pageSize)) }
    var lastPage: Int { max(0, (all.count - 1) / Self.pageSize) }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        keys.append(keycode)
        guard mask & RimeKey.releaseMask == 0 else { return !input.isEmpty }
        let composing = !input.isEmpty
        switch keycode {
        case 0x61...0x7A:
            input.append(Character(Unicode.Scalar(UInt8(keycode))))
            (highlighted, page) = (0, 0)
            return true
        case _ where !composing:
            if keycode == 0x2C { emit("，"); return true }
            if keycode == 0x2E { emit("。"); return true }
            return false
        case RimeKey.space: pick(highlighted)
        case 0x31...0x35: pick(Int(keycode - 0x31))
        case RimeKey.returnKey: emit(input); input = ""
        case RimeKey.escape: input = ""
        case RimeKey.backSpace: input.removeLast(); (highlighted, page) = (0, 0)
        case RimeKey.down:
            if highlighted < onPage.count - 1 { highlighted += 1 } else if page < lastPage { (page, highlighted) = (page + 1, 0) }
        case RimeKey.up:
            if highlighted > 0 { highlighted -= 1 } else if page > 0 { page -= 1; highlighted = onPage.count - 1 }
        case RimeKey.pageDown, 0x3D: if page < lastPage { (page, highlighted) = (page + 1, 0) }
        case RimeKey.pageUp, 0x2D: if page > 0 { (page, highlighted) = (page - 1, 0) }
        case 0x2C: pick(highlighted); emit("，")
        case 0x2E: pick(highlighted); emit("。")
        case 0x5B, 0x5D:
            let text = onPage[highlighted]
            emit(String(keycode == 0x5B ? text.first! : text.last!))
            input = ""
        default: break
        }
        return true
    }

    private func pick(_ i: Int) {
        guard onPage.indices.contains(i) else { return }
        emit(onPage[i])
        input = ""
        (highlighted, page) = (0, 0)
    }

    private func emit(_ text: String) { commit = (commit ?? "") + text }

    func takeCommit() -> String? {
        defer { commit = nil }
        return commit
    }

    func snapshot() -> EngineSnapshot {
        guard !input.isEmpty else { return EngineSnapshot() }
        return EngineSnapshot(isComposing: true, preedit: input, cursor: input.count,
                              candidates: onPage.enumerated().map { EngineCandidate(label: String($0.offset + 1), text: $0.element) },
                              highlighted: highlighted, pageNumber: page, isLastPage: page == lastPage)
    }

    func selectCandidate(onPage index: Int) -> Bool {
        guard onPage.indices.contains(index) else { return false }
        pick(index)
        return true
    }

    func deleteCandidate(onPage index: Int) -> Bool {
        guard onPage.indices.contains(index) else { return false }
        deleted.append(onPage[index])
        if resetsOnDelete { (highlighted, page) = (0, 0) }
        return true
    }

    func commitComposition() -> String? {
        guard !input.isEmpty else { return nil }
        pick(highlighted)
        return takeCommit()
    }

    var rawInput: String { input }
    func clearComposition() { input = "" }
    func setAsciiMode(_ on: Bool) {}
}

/// A candidate removed for good (a right-click on its row, ⌃⌦ on the highlighted one: `Composer.deleteCandidate(index:)`)
/// and those on the list (`Composer.removedCandidates`, the settings' `Config.removedCandidates`): never shown again, by
/// their whole text, on any page; the rows shown numbered 1… as shown, and only a row shown is ever put in, whatever the
/// key; a page with nothing shown skipped in the way the pages were turned (5 at most); nothing shown: Space puts the
/// letters in as typed. With nothing removed, as before.
struct RemovedCandidatesTests {
    static let dian = ["点", "电", "店", "垫", "殿", "典", "淀", "惦"]
    static let shiyan = ["实验", "试验", "事宴", "石砚", "誓言", "失言"]
    /// Three pages of five.
    static let zhong = ["中", "种", "重", "众", "钟", "忠", "终", "肿", "仲", "衷", "踵", "冢", "锺", "盅", "螽"]
    /// Eight pages of five.
    static let yi = (0..<40).map { "一\($0)" }

    let pageDown = KeyEvent(keyCode: VirtualKey.pageDown, characters: "\u{F72D}")
    let pageUp = KeyEvent(keyCode: VirtualKey.pageUp, characters: "\u{F72C}")
    let right = KeyEvent(keyCode: VirtualKey.right, characters: "\u{F703}")
    let left = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")

    func composer(_ removed: [String] = []) -> (Composer, PagesEngine) {
        let engine = PagesEngine(["dian": Self.dian, "shiyan": Self.shiyan, "zhong": Self.zhong, "yi": Self.yi])
        let c = Composer(engine: engine, actionKey: .enter)
        c.removedCandidates = removed
        return (c, engine)
    }

    func type(_ s: String, _ c: Composer) -> [Composer.Effect] {
        s.flatMap { c.handleKeyDown(k(String($0))).effects }
    }

    func press(_ key: KeyEvent, _ c: Composer, times: Int = 1) -> [Composer.Effect] {
        (0..<times).flatMap { _ in c.handleKeyDown(key).effects }
    }

    func rows(_ c: Composer) -> [String] { c.engineState.candidates.map(\.text) }
    func labels(_ c: Composer) -> [String] { c.engineState.candidates.map(\.label) }
    /// The row shown highlighted.
    func highlighted(_ c: Composer) -> String? {
        let rows = rows(c)
        return rows.indices.contains(c.engineState.highlighted) ? rows[c.engineState.highlighted] : nil
    }

    func removed(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .candidateRemoved(text) = $0 { return text } else { return nil } }
    }

    // MARK: - Removing one

    /// A row's candidate removed: gone from the page at once, librime told by its place on librime's page; nothing
    /// committed, the letters stay; the effect carries its text as shown, once; the composer's list has it.
    @Test func aRowsCandidateIsRemovedAndNothingCommitted() {
        let (c, engine) = composer()
        _ = type("shiyan", c)
        #expect(rows(c) == ["实验", "试验", "事宴", "石砚", "誓言"])
        let effects = c.deleteCandidate(index: 1)
        #expect(removed(effects) == ["试验"], "\(effects)")
        #expect(engine.deleted == ["试验"], "librime's delete too: \(engine.deleted)")
        #expect(commits(effects).isEmpty && c.engineState.isComposing && engine.input == "shiyan" && c.markedText == "shiyan")
        #expect(effects.contains(.updateMarkedText) && effects.contains(.showPanel), "\(effects)")
        #expect(rows(c) == ["实验", "事宴", "石砚", "誓言"] && labels(c) == ["1", "2", "3", "4"], "\(rows(c)) \(labels(c))")
        #expect(c.removedCandidates == ["试验"])
        // The second row now: librime's third.
        #expect(removed(c.deleteCandidate(index: 1)) == ["事宴"] && engine.deleted == ["试验", "事宴"])
        #expect(rows(c) == ["实验", "石砚", "誓言"] && c.removedCandidates == ["试验", "事宴"])
        // Past the rows shown: nothing.
        let past = c.deleteCandidate(index: 3)
        #expect(past.isEmpty && engine.deleted == ["试验", "事宴"] && c.removedCandidates == ["试验", "事宴"], "\(past)")
        // Never again, whatever comes later.
        _ = press(escKey, c)
        _ = type("shiyan", c)
        #expect(rows(c) == ["实验", "石砚", "誓言"], "\(rows(c))")
        _ = press(pageDown, c)
        #expect(rows(c) == ["失言"])
    }

    /// The highlighted one's ⌃⌦ removes the row shown highlighted, once (librime never has the key).
    @Test func controlForwardDeleteRemovesTheRowShownHighlighted() {
        let (c, engine) = composer(["实验"])
        _ = type("shiyan", c)
        #expect(rows(c) == ["试验", "事宴", "石砚", "誓言"] && highlighted(c) == "试验")
        _ = press(downKey, c)
        #expect(highlighted(c) == "事宴")
        let keys = engine.keys.count
        let response = c.handleKeyDown(DeleteKeys.controlForwardDelete)
        #expect(response.handled && removed(response.effects) == ["事宴"] && engine.deleted == ["事宴"], "\(response.effects)")
        #expect(engine.keys.count == keys, "librime never had the key")
        #expect(commits(response).isEmpty && rows(c) == ["试验", "石砚", "誓言"])
        #expect(highlighted(c).map { !c.removedCandidates.contains($0) } == true, "the highlight on a row shown: \(c.engineState)")
    }

    // MARK: - Only a row shown is put in

    /// The rows numbered as shown; a digit picks the row shown with that number, a click the row; one with no row
    /// (librime's own candidate there removed) picks nothing.
    @Test func digitsAndClicksPickTheRowShown() {
        let (c, engine) = composer(["电"])
        _ = type("dian", c)
        #expect(rows(c) == ["点", "店", "垫", "殿"] && labels(c) == ["1", "2", "3", "4"], "\(rows(c)) \(labels(c))")
        #expect(commits(type("2", c)) == ["店"])
        _ = type("dian", c)
        #expect(commits(type("4", c)) == ["殿"])
        _ = type("dian", c)
        let five = type("5", c)
        #expect(commits(five).isEmpty && c.engineState.isComposing && rows(c) == ["点", "店", "垫", "殿"], "\(five)")
        #expect(!engine.keys.contains(0x35), "librime's 5 would put in 殿, a row it has, not 5 shown")
        #expect(commits(c.choose(index: 2)) == ["垫"])
        _ = type("dian", c)
        #expect(c.choose(index: 4).isEmpty && c.engineState.isComposing, "no fifth row")
        _ = press(escKey, c)
    }

    /// ↑↓ go from row shown to row shown, past those removed, on to the next page and back; the highlight never rests
    /// on a removed one, also where librime's would (its last on the page before).
    @Test func arrowsSkipTheRemoved() {
        let (c, engine) = composer(["店", "殿"])
        _ = type("dian", c)
        #expect(rows(c) == ["点", "电", "垫"] && highlighted(c) == "点")
        _ = press(downKey, c, times: 2)
        #expect(highlighted(c) == "垫" && c.engineState.highlighted == 2 && engine.highlighted == 3, "\(engine.highlighted)")
        _ = press(upKey, c)
        #expect(highlighted(c) == "电" && engine.highlighted == 1)
        _ = press(downKey, c, times: 2)
        #expect(c.engineState.pageNumber == 1 && rows(c) == ["典", "淀", "惦"] && highlighted(c) == "典", "\(rows(c))")
        // Back: librime's highlight on its last of the page before, 殿, which is removed.
        _ = press(upKey, c)
        #expect(c.engineState.pageNumber == 0 && rows(c) == ["点", "电", "垫"])
        #expect(highlighted(c) == "垫", "the last shown, never 殿: \(c.engineState)")
        #expect(commits(press(spaceKey, c)) == ["垫"])
    }

    /// Candidates in a row: ← → go from row shown to row shown.
    @Test func inARowLeftAndRightSkipTheRemoved() {
        let (c, _) = composer(["电"])
        c.horizontalCandidates = true
        _ = type("dian", c)
        _ = press(right, c)
        #expect(highlighted(c) == "店", "\(c.engineState)")
        _ = press(right, c)
        _ = press(left, c)
        #expect(highlighted(c) == "店")
        _ = press(left, c)
        #expect(highlighted(c) == "点")
        #expect(commits(press(spaceKey, c)) == ["点"])
    }

    /// The first candidate removed: whatever makes librime commit its highlighted one puts in the row shown highlighted.
    @Test func everyKeyThatCommitsPutsInARowShown() {
        let (c, _) = composer(["实验"])
        func fresh() {
            _ = type("shiyan", c)
            #expect(rows(c).first == "试验" && highlighted(c) == "试验" && c.engineState.highlighted == 0, "\(c.engineState)")
        }
        fresh()
        #expect(commits(press(spaceKey, c)) == ["试验"], "Space")
        fresh()
        #expect(commits(press(shiftSpace, c)) == ["试验"], "⇧Space")
        fresh()
        #expect(commits(type("1", c)) == ["试验"], "1")
        fresh()
        #expect(commits(type(",", c)).joined() == "试验，", ",")
        fresh()
        #expect(commits(type(".", c)).joined() == "试验。", ".")
        fresh()
        #expect(commits(type("[", c)) == ["试"], "[")
        fresh()
        #expect(commits(type("]", c)) == ["验"], "]")
        fresh()
        #expect(commits(c.commitAll()) == ["试验"], "the field left")
        fresh()
        #expect(commits(c.choose(index: 0)) == ["试验"], "a click")
        // ⏎ is as typed.
        fresh()
        #expect(commits(press(enterKey, c)) == ["shiyan"])
    }

    /// Two removed after the highlight moved past them: still only rows shown go in.
    @Test func theHighlightMovedOntoARowShownBeforeLibrimeCommits() {
        let (c, _) = composer(["试验", "事宴"])
        _ = type("shiyan", c)
        _ = press(downKey, c)
        #expect(highlighted(c) == "石砚")
        #expect(commits(type(",", c)).joined() == "石砚，")
        _ = type("shiyan", c)
        _ = press(downKey, c)
        #expect(commits(type("]", c)) == ["砚"])
    }

    // MARK: - Pages with nothing shown

    /// A page every candidate of which is removed is skipped in the way the pages were turned: forward with Page Down,
    /// = and ↓ from the last row, back with Page Up and -.
    @Test func aPageWithEverythingRemovedIsSkipped() {
        let (c, _) = composer(Array(Self.zhong[5..<10]))
        _ = type("zhong", c)
        #expect(c.engineState.pageNumber == 0 && rows(c) == Array(Self.zhong[0..<5]))
        _ = press(pageDown, c)
        #expect(c.engineState.pageNumber == 2 && rows(c) == Array(Self.zhong[10..<15]), "\(c.engineState)")
        _ = press(pageUp, c)
        #expect(c.engineState.pageNumber == 0 && rows(c) == Array(Self.zhong[0..<5]), "\(c.engineState)")
        _ = type("=", c)
        #expect(c.engineState.pageNumber == 2, "=")
        _ = type("-", c)
        #expect(c.engineState.pageNumber == 0, "-")
        _ = press(downKey, c, times: 5)
        #expect(c.engineState.pageNumber == 2 && highlighted(c) == "踵", "↓ past the last row: \(c.engineState)")
        _ = press(upKey, c)
        #expect(c.engineState.pageNumber == 0 && highlighted(c).map(Self.zhong[0..<5].contains) == true, "\(c.engineState)")
        #expect(c.engineState.isComposing && c.markedText == "zhong")
    }

    /// The first page with everything removed: on to the next, also when the pages were turned back onto it.
    @Test func theFirstPageWithEverythingRemovedGoesForward() {
        let (c, _) = composer(Array(Self.zhong[0..<5]))
        _ = type("zhong", c)
        #expect(c.engineState.pageNumber == 1 && rows(c) == Array(Self.zhong[5..<10]), "\(c.engineState)")
        #expect(labels(c) == ["1", "2", "3", "4", "5"] && highlighted(c) == "忠")
        _ = press(pageUp, c)
        #expect(c.engineState.pageNumber == 1 && rows(c) == Array(Self.zhong[5..<10]), "\(c.engineState)")
        #expect(commits(press(spaceKey, c)) == ["忠"])
    }

    /// Five pages are turned at most: with the first five empty, the sixth; with six, nothing is shown, and Space puts the
    /// letters in as typed (as ⏎); digits and [ ] put in nothing; Page Down goes on to a page with something shown.
    @Test func atMostFivePagesAreSkipped() {
        let (five, _) = composer(Array(Self.yi[0..<25]))
        _ = type("yi", five)
        #expect(five.engineState.pageNumber == 5 && rows(five) == Array(Self.yi[25..<30]), "\(five.engineState)")

        let (c, engine) = composer(Array(Self.yi[0..<30]))
        _ = type("yi", c)
        #expect(rows(c).isEmpty && engine.page == 5, "nothing shown: \(rows(c)), librime's page \(engine.page)")
        #expect(c.engineState.isComposing && c.markedText == "yi")
        for key in ["1", "5", "[", "]"] {
            #expect(commits(type(key, c)).isEmpty && c.engineState.isComposing, "\(key)")
        }
        #expect(commits(press(spaceKey, c)) == ["yi"], "the letters as typed")
        _ = type("yi", c)
        let comma = commits(type(",", c)).joined()
        #expect(comma.hasPrefix("yi") && !Self.yi.contains { comma.contains($0) }, "\(comma)")
        _ = type("yi", c)
        #expect(commits(c.commitAll()) == ["yi"], "the field left: the letters")
        _ = type("yi", c)
        _ = press(pageDown, c)
        #expect(c.engineState.pageNumber == 6 && rows(c) == Array(Self.yi[30..<35]), "\(c.engineState)")
    }

    /// Candidates in a row, where ↑↓ are the page keys: from a page with nothing shown, ↓ goes on to the next page with
    /// something shown, ↑ back, as Page Down and Page Up do.
    @Test func inARowTheArrowsTurnPagesWithNothingShownToo() {
        let (c, engine) = composer(Array(Self.yi[0..<30]))
        c.horizontalCandidates = true
        _ = type("yi", c)
        #expect(rows(c).isEmpty && engine.page == 5)
        _ = press(downKey, c)
        #expect(c.engineState.pageNumber == 6 && rows(c) == Array(Self.yi[30..<35]), "↓ as Page Down: \(c.engineState)")
        _ = press(downKey, c)
        #expect(c.engineState.pageNumber == 7)
        _ = press(upKey, c)
        #expect(c.engineState.pageNumber == 6, "\(c.engineState)")
    }

    /// Every candidate of a one-page spelling removed: nothing shown; Space puts the letters in as typed.
    @Test func noneShownSpacePutsInTheLetters() {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        c.removedCandidates = ["你好", "拟好"]
        _ = type("nihao", c)
        #expect(rows(c).isEmpty && c.engineState.isComposing && c.markedText == "nihao", "\(rows(c))")
        #expect(commits(press(spaceKey, c)) == ["nihao"])
        _ = type("nihao", c)
        #expect(c.deleteCandidate(index: 0).isEmpty, "no row to remove")
        #expect(commits(c.commitAll()) == ["nihao"])
    }

    /// One removed leaves a page with nothing shown: the next one at once.
    @Test func removingTheLastShownTurnsThePage() {
        let (c, _) = composer(Array(Self.zhong[0..<4]))
        _ = type("zhong", c)
        #expect(rows(c) == ["钟"])
        let effects = c.deleteCandidate(index: 0)
        #expect(removed(effects) == ["钟"] && commits(effects).isEmpty)
        #expect(c.engineState.pageNumber == 1 && rows(c) == Array(Self.zhong[5..<10]), "\(c.engineState)")
    }

    /// ↑ on a page's first row, the page before with nothing shown: that page skipped, the highlight on the last row shown
    /// of the page reached (librime's last there removed: the one shown before it), which Space puts in. Page Up there:
    /// where the engine's page keys put it (this one's: on the first row). With no page before that shows anything, ↑
    /// stays on the first row shown, also when librime's first there is removed.
    @Test func upOverASkippedPageLandsOnTheLastRowShown() {
        for (list, last) in [(Array(Self.zhong[5..<10]), "钟"), (Array(Self.zhong[5..<10]) + ["钟"], "众")] {
            let (c, _) = composer(list)
            _ = type("zhong", c)
            _ = press(pageDown, c)
            #expect(c.engineState.pageNumber == 2 && highlighted(c) == "踵", "\(c.engineState)")
            _ = press(upKey, c)
            #expect(c.engineState.pageNumber == 0 && highlighted(c) == last, "\(list.count) removed: \(c.engineState)")
            #expect(commits(press(spaceKey, c)) == [last])
            _ = type("zhong", c)
            _ = press(pageDown, c)
            _ = press(pageUp, c)
            #expect(c.engineState.pageNumber == 0 && highlighted(c) == "中", "Page Up: \(c.engineState)")
            _ = press(escKey, c)
        }
        for (list, first) in [(Array(Self.zhong[0..<5]), "忠"), (Array(Self.zhong[0..<6]), "终")] {
            let (c, _) = composer(list)
            _ = type("zhong", c)
            #expect(c.engineState.pageNumber == 1 && highlighted(c) == first, "\(c.engineState)")
            _ = press(upKey, c)
            #expect(c.engineState.pageNumber == 1 && highlighted(c) == first, "\(list.count) removed: \(c.engineState)")
            _ = press(downKey, c)
            _ = press(upKey, c, times: 2)
            #expect(c.engineState.pageNumber == 1 && highlighted(c) == first, "\(c.engineState)")
            #expect(commits(press(spaceKey, c)) == [first])
        }
    }

    // MARK: - An emptied last page

    /// The last page with nothing shown (every candidate on it removed): Page Down, = and ↓ past the last row shown
    /// land back on the page before, never on an empty panel; after ↓ (→ in a row) the highlight is on its last row
    /// shown, also when librime's last there is removed. librime gets page and arrow keys only, nothing that puts
    /// anything in or changes the letters. Two pages ("dian") the same.
    @Test func anEmptiedLastPageGoesBackToThePageBefore() {
        let moves = [RimeKey.pageDown, RimeKey.pageUp, RimeKey.down, RimeKey.up, 0x3D]
        for (extra, horizontal) in [([String](), false), (["一34"], false), ([], true), (["一34"], true)] {
            let (c, engine) = composer(Array(Self.yi[35..<40]) + extra)
            c.horizontalCandidates = horizontal
            let next = horizontal ? right : downKey
            let shown = Array(Self.yi[30..<35]).filter { !extra.contains($0) }
            _ = type("yi", c)
            _ = press(pageDown, c, times: 6)
            #expect(c.engineState.pageNumber == 6 && rows(c) == shown, "\(extra) \(horizontal): \(c.engineState)")
            let keys = engine.keys.count
            _ = press(pageDown, c)
            #expect(c.engineState.pageNumber == 6 && rows(c) == shown, "\(extra) \(horizontal): Page Down: \(c.engineState)")
            #expect(highlighted(c).map(shown.contains) == true, "a row shown: \(c.engineState)")
            _ = type("=", c)
            #expect(c.engineState.pageNumber == 6 && rows(c) == shown, "\(extra) \(horizontal): =: \(c.engineState)")
            _ = press(next, c, times: shown.count - 1)
            #expect(highlighted(c) == shown.last, "\(extra) \(horizontal): \(c.engineState)")
            _ = press(next, c)
            #expect(c.engineState.pageNumber == 6 && rows(c) == shown && highlighted(c) == shown.last,
                    "\(extra) \(horizontal): past the last row: \(c.engineState)")
            #expect(labels(c) == shown.indices.map { String($0 + 1) })
            let others = engine.keys[keys...].filter { !moves.contains($0) }
            #expect(others.isEmpty, "only page and arrow keys: \(others)")
            #expect(c.engineState.isComposing && c.markedText == "yi" && engine.input == "yi")
            #expect(commits(press(spaceKey, c)) == [shown.last!], "\(extra) \(horizontal)")
        }
        let (c, _) = composer(Array(Self.dian[5...]))
        _ = type("dian", c)
        _ = press(pageDown, c)
        #expect(c.engineState.pageNumber == 0 && rows(c) == Array(Self.dian[0..<5]), "\(c.engineState)")
        _ = press(downKey, c, times: 5)
        #expect(c.engineState.pageNumber == 0 && highlighted(c) == "殿", "\(c.engineState)")
    }

    /// The only candidate shown on the last page removed (a right-click, ⌃⌦), librime laying the composition out anew
    /// from its first page as its `delete_candidate` does: back on the page before, the highlight on its last row shown
    /// (librime's last there removed: the one before it), which Space puts in. librime gets page and arrow keys only.
    @Test func removingTheOnlyShownOfTheLastPageGoesBack() {
        for (byKey, extra) in [(false, [String]()), (true, []), (false, ["一34"]), (true, ["一33", "一34"])] {
            let (c, engine) = composer(Array(Self.yi[36..<40]) + extra)
            engine.resetsOnDelete = true
            _ = type("yi", c)
            _ = press(pageDown, c, times: 7)
            #expect(c.engineState.pageNumber == 7 && rows(c) == ["一35"], "\(extra): \(c.engineState)")
            let keys = engine.keys.count
            let effects = byKey ? c.handleKeyDown(DeleteKeys.controlForwardDelete).effects : c.deleteCandidate(index: 0)
            #expect(removed(effects) == ["一35"] && commits(effects).isEmpty, "\(byKey) \(extra): \(effects)")
            let shown = Array(Self.yi[30..<35]).filter { !extra.contains($0) }
            #expect(c.engineState.pageNumber == 6 && rows(c) == shown, "\(byKey) \(extra): \(c.engineState)")
            #expect(highlighted(c) == shown.last, "\(byKey) \(extra): on its last row shown: \(c.engineState)")
            #expect(labels(c) == shown.indices.map { String($0 + 1) })
            #expect(engine.deleted == ["一35"] && engine.input == "yi" && c.markedText == "yi" && c.removedCandidates.last == "一35")
            let others = engine.keys[keys...].filter { ![RimeKey.pageDown, RimeKey.pageUp, RimeKey.down, RimeKey.up].contains($0) }
            #expect(others.isEmpty, "only page and arrow keys: \(others)")
            #expect(commits(press(spaceKey, c)) == [shown.last!])
        }
    }

    /// Pages emptied up to the last: Page Down goes on over them to the last, then back over them to the page it came
    /// from; ↓ past that page's last row the same, the highlight on its last row.
    @Test func severalEmptiedPagesAtTheEndAreGoneOverBack() {
        let (c, engine) = composer(Array(Self.yi[20..<40]))
        _ = type("yi", c)
        _ = press(pageDown, c, times: 3)
        #expect(c.engineState.pageNumber == 3 && rows(c) == Array(Self.yi[15..<20]), "\(c.engineState)")
        let keys = engine.keys.count
        _ = press(pageDown, c)
        #expect(c.engineState.pageNumber == 3 && rows(c) == Array(Self.yi[15..<20]), "\(c.engineState)")
        #expect(engine.keys[keys...].filter { $0 == RimeKey.pageDown }.count == 4, "on to the last: \(engine.keys[keys...])")
        _ = press(downKey, c, times: 5)
        #expect(c.engineState.pageNumber == 3 && highlighted(c) == "一19", "\(c.engineState)")
        #expect(engine.page == 3 && c.engineState.isComposing)
    }

    /// Back from the last page: `maxSkipped` pages at most past those just turned on. Five emptied before it: the fifth
    /// back, which shows nothing either (Space puts the letters in as typed); four: the one before them, the highlight on
    /// its last row.
    @Test func backFromTheLastPageFivePagesAtMost() {
        for (emptied, shown) in [(Array(Self.yi[10..<35]), [String]()), (Array(Self.yi[15..<35]), Array(Self.yi[10..<15]))] {
            let (c, engine) = composer()
            _ = type("yi", c)
            _ = press(pageDown, c, times: 7)
            c.removedCandidates = emptied + Array(Self.yi[36..<40])
            let keys = engine.keys.count
            #expect(removed(c.deleteCandidate(index: 0)) == ["一35"])
            let back = engine.keys[keys...].filter { $0 == RimeKey.pageUp }.count
            #expect(back == EnglishWordsEngine.maxSkipped && engine.page == 2, "\(back) back, on \(engine.page)")
            #expect(c.engineState.pageNumber == 2 && rows(c) == shown && c.engineState.isComposing, "\(c.engineState)")
            if shown.isEmpty {
                #expect(commits(press(spaceKey, c)) == ["yi"], "nothing shown: the letters")
            } else {
                #expect(highlighted(c) == shown.last, "\(c.engineState)")
            }
        }
    }

    // MARK: - After a removal: the page and the highlight

    /// librime's `delete_candidate` lays the composition out anew from its first page (`PagesEngine.resetsOnDelete`): one
    /// removed on the third page leaves the user on the third, laid out again without it. The highlighted one removed:
    /// the highlight on the next one shown, else (the last shown) the one before; another row removed, before it or after
    /// it: the highlight stays on the candidate it was on. librime gets only page and arrow keys meanwhile, none that puts
    /// anything in or changes the letters.
    @Test func aRemovalOnTheThirdPageStaysThereTheHighlightAsItWas() {
        let (c, engine) = composer()
        engine.resetsOnDelete = true
        _ = type("zhong", c)
        _ = press(pageDown, c, times: 2)
        #expect(c.engineState.pageNumber == 2 && rows(c) == Array(Self.zhong[10..<15]), "\(c.engineState)")
        _ = press(downKey, c)
        #expect(highlighted(c) == "冢")
        let keys = engine.keys.count
        let response = c.handleKeyDown(DeleteKeys.controlForwardDelete)
        #expect(removed(response.effects) == ["冢"] && commits(response).isEmpty, "\(response.effects)")
        #expect(c.engineState.pageNumber == 2 && rows(c) == ["踵", "锺", "盅", "螽"], "\(c.engineState)")
        #expect(highlighted(c) == "锺", "the next shown: \(c.engineState)")
        #expect(labels(c) == ["1", "2", "3", "4"])
        #expect(removed(c.deleteCandidate(index: 0)) == ["踵"])
        #expect(c.engineState.pageNumber == 2 && rows(c) == ["锺", "盅", "螽"] && highlighted(c) == "锺", "a row before: \(c.engineState)")
        #expect(removed(c.deleteCandidate(index: 2)) == ["螽"])
        #expect(c.engineState.pageNumber == 2 && rows(c) == ["锺", "盅"] && highlighted(c) == "锺", "a row after: \(c.engineState)")
        _ = press(downKey, c)
        #expect(highlighted(c) == "盅")
        #expect(removed(c.handleKeyDown(DeleteKeys.controlForwardDelete).effects) == ["盅"])
        #expect(c.engineState.pageNumber == 2 && rows(c) == ["锺"] && highlighted(c) == "锺", "the one before: \(c.engineState)")
        #expect(engine.deleted == ["冢", "踵", "螽", "盅"] && engine.input == "zhong" && c.markedText == "zhong")
        let others = engine.keys[keys...].filter { ![RimeKey.pageDown, RimeKey.pageUp, RimeKey.down, RimeKey.up].contains($0) }
        #expect(others.isEmpty, "only page and arrow keys: \(others)")
        #expect(commits(press(spaceKey, c)) == ["锺"])
    }

    /// A page far on: back on it after the removal, turned on to it once each page (at most `maxReturned`); a page the
    /// removal leaves with nothing shown: on to the next with something, the highlight on its first.
    @Test func aRemovalFarOnStaysOnItsPageOrGoesOnWhenItEmptiesIt() {
        let (c, engine) = composer()
        engine.resetsOnDelete = true
        _ = type("yi", c)
        _ = press(pageDown, c, times: 7)
        #expect(c.engineState.pageNumber == 7 && rows(c) == Array(Self.yi[35..<40]), "\(c.engineState)")
        let keys = engine.keys.count
        #expect(removed(c.deleteCandidate(index: 2)) == ["一37"])
        #expect(c.engineState.pageNumber == 7 && rows(c) == ["一35", "一36", "一38", "一39"], "\(c.engineState)")
        #expect(highlighted(c) == "一35", "the highlight where it was: \(c.engineState)")
        let paged = engine.keys[keys...].filter { $0 == RimeKey.pageDown }.count
        #expect(paged == 7 && paged <= EnglishWordsEngine.maxReturned, "\(paged) pages turned")
        _ = press(escKey, c)

        let (d, other) = composer(Array(Self.yi[25..<29]))
        other.resetsOnDelete = true
        _ = type("yi", d)
        _ = press(pageDown, d, times: 5)
        #expect(d.engineState.pageNumber == 5 && rows(d) == ["一29"], "\(d.engineState)")
        #expect(removed(d.deleteCandidate(index: 0)) == ["一29"])
        #expect(d.engineState.pageNumber == 6 && rows(d) == Array(Self.yi[30..<35]) && highlighted(d) == "一30", "\(d.engineState)")
    }

    /// The highlight on an English word put on the page: another row removed, it stays on the word; the word removed
    /// (⌃⌦), on the one shown after it, which Space puts in.
    @Test func theHighlightOnAWordStaysWhenAnotherRowIsRemoved() {
        let base = PagesEngine(["xiaomi": ["小米", "小蜜", "晓米", "笑眯", "小觅"]])
        let mixed = EnglishWordsEngine(base: base, dictionary: EnglishDictionary([]), words: ["Xiaomi"])
        let c = Composer(engine: mixed, actionKey: .enter)
        _ = type("xiaomi", c)
        #expect(rows(c) == ["小米", "Xiaomi", "小蜜", "晓米", "笑眯", "小觅"], "\(rows(c))")
        _ = press(downKey, c)
        #expect(highlighted(c) == "Xiaomi")
        #expect(removed(c.deleteCandidate(index: 3)) == ["晓米"])
        #expect(rows(c) == ["小米", "Xiaomi", "小蜜", "笑眯", "小觅"] && highlighted(c) == "Xiaomi", "\(c.engineState)")
        #expect(removed(c.deleteCandidate(index: 0)) == ["小米"])
        #expect(rows(c) == ["小蜜", "Xiaomi", "笑眯", "小觅"] && highlighted(c) == "Xiaomi", "\(c.engineState)")
        #expect(removed(c.handleKeyDown(DeleteKeys.controlForwardDelete).effects) == ["Xiaomi"])
        #expect(rows(c) == ["小蜜", "笑眯", "小觅"] && highlighted(c) == "笑眯", "the next shown: \(c.engineState)")
        #expect(commits(press(spaceKey, c)) == ["笑眯"])
    }

    // MARK: - Nothing removed: as before

    /// With nothing removed on the page (none at all, or only what isn't on it), and no English words, the composer shows
    /// librime's page as it is and librime gets exactly the keys pressed.
    @Test func nothingRemovedIsAsBefore() {
        let keys: [KeyEvent] = [k("z"), k("h"), k("o"), k("n"), k("g"), downKey, downKey, pageDown, upKey, upKey, k("-"),
                                k("="), pageUp, downKey, k("2")]
        for removed in [[], ["不在任何一页"]] {
            let (c, engine) = composer(removed)
            for (n, key) in keys.enumerated() {
                let response = c.handleKeyDown(key)
                #expect(c.engineState == engine.snapshot(), "\(removed) after key \(n): \(c.engineState) \(engine.snapshot())")
                #expect(engine.keys.count == n + 1, "\(removed) after key \(n): librime had \(engine.keys)")
                if n == keys.count - 1 { #expect(commits(response) == ["种"], "\(response.effects)") }
            }
        }
        // Words on the list, none for these letters.
        let base = PagesEngine(["zhong": Self.zhong])
        let mixed = EnglishWordsEngine(base: base, dictionary: EnglishDictionary([]), words: ["Bedrock"], removedCandidates: ["Zorblax"])
        let c = Composer(engine: mixed, actionKey: .enter)
        _ = type("zhong", c)
        _ = press(downKey, c, times: 6)
        #expect(c.engineState == base.snapshot() && base.keys.count == 11, "\(c.engineState)")
    }

    // MARK: - English words among the candidates

    // (One removed among English words, and an English word removed: DeleteCandidateTests.englishWordsAmongTheCandidatesAreRemovedToo.)

    /// Words on the page and a librime candidate removed: the rows numbered as shown, digits and Space by the place shown.
    @Test func wordsAndRemovedCandidatesOnOnePage() {
        let base = PagesEngine(["xiaomi": ["小米", "小蜜", "晓米", "笑眯", "小觅"]])
        let mixed = EnglishWordsEngine(base: base, dictionary: EnglishDictionary([]), words: ["Xiaomi"], removedCandidates: ["小米"])
        let c = Composer(engine: mixed, actionKey: .enter)
        _ = type("xiaomi", c)
        #expect(!rows(c).contains("小米") && rows(c).contains("Xiaomi") && rows(c).count == 5, "\(rows(c))")
        #expect(labels(c) == ["1", "2", "3", "4", "5"])
        #expect(highlighted(c).map { $0 != "小米" } == true)
        let shown = rows(c)
        #expect(commits(type("3", c)) == [shown[2]], "\(shown)")
        _ = type("xiaomi", c)
        let space = commits(press(spaceKey, c))
        #expect(space == [shown[c.engineState.highlighted]] || space == [shown[0]], "\(space)")
        #expect(!space.contains("小米"))
    }

    // MARK: - The engines level one has

    /// Any engine the controller sets that isn't one with English words is put in one without (so it leaves out those
    /// removed all the same); `primaryEngine` stays the one set. One with words, and `LatinEngine`, are as they are.
    @Test func everyPinyinEngineLeavesThemOut() {
        let fake = FakeEngine()
        let c = Composer(engine: fake, actionKey: .enter)
        #expect(c.engine is EnglishWordsEngine && c.primaryEngine === fake)
        let mixed = EnglishWordsEngine(base: FakeEngine(), dictionary: EnglishDictionary([]))
        c.engine = mixed
        #expect(c.engine === mixed && c.primaryEngine === mixed)
        let latin = LatinEngine()
        c.engine = latin
        #expect(c.engine === latin && c.primaryEngine === latin)
        c.engine = nil
        #expect(c.engine == nil)
    }

    /// The list stays with the composer when its engine is set again (librime deployed again): from the settings, or one
    /// removed here.
    @Test func aNewEngineLeavesThemOutToo() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.removedCandidates = ["拟好"]
        c.engine = FakeEngine()
        _ = type("nihao", c)
        #expect(rows(c) == ["你好"], "\(rows(c))")
        _ = c.deleteCandidate(index: 0)
        _ = press(escKey, c)
        c.engine = FakeEngine()
        _ = type("wo", c)
        _ = c.deleteCandidate(index: 1)
        _ = press(escKey, c)
        c.engine = FakeEngine()
        #expect(c.removedCandidates == ["拟好", "你好", "窝"], "\(c.removedCandidates)")
        _ = type("nihao", c)
        #expect(rows(c).isEmpty, "\(rows(c))")
        _ = press(escKey, c)
        _ = type("wo", c)
        #expect(rows(c) == ["我"], "\(rows(c))")
    }

    /// Hindi's engine in librime's place: its rows are no candidates removed for good.
    @Test func hindisRowsAreNone() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.hindiTables = PackData.hindi
        c.inputLanguages = [.english, .hindi]
        c.setInputMode(.hindi)
        _ = type("kamra", c)
        let shown = rows(c)
        #expect(!shown.isEmpty, "\(shown)")
        let effects = c.deleteCandidate(index: 0)
        #expect(removed(effects).isEmpty && c.removedCandidates.isEmpty && commits(effects).isEmpty, "\(effects)")
    }

    // MARK: - Rows that aren't candidates

    /// A refine instruction's pinyin at level two: its candidates are librime's, removed as anywhere; the results stay.
    /// Level two's results themselves, the command list, voice input and nothing composed: nothing.
    @Test func onlyTheEnginesCandidates() {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        _ = c.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        _ = type("i", c)
        _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        c.setInputMode(.english)
        _ = type("hello", c)
        c.setInputMode(.chinese)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("Hi."), CandidateLine("Hello.")]), isFinal: true, id: 1)
        #expect(c.isLevelTwo)
        let results = c.choices.map(\.text)
        for index in results.indices { #expect(c.deleteCandidate(index: index).isEmpty) }
        #expect(c.removedCandidates.isEmpty && c.choices.map(\.text) == results)
        _ = type("nihao", c)
        #expect(c.refineIsComposing && rows(c) == ["你好", "拟好"])
        let effects = c.deleteCandidate(index: 1)
        #expect(removed(effects) == ["拟好"] && rows(c) == ["你好"] && c.isLevelTwo && c.refineLine == "nihao", "\(effects)")
        #expect(c.choices.map(\.text) == results || c.isLevelTwo)

        // The command list.
        let d = Composer(engine: FakeEngine(), actionKey: .enter)
        _ = d.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        #expect(d.paletteQuery != nil)
        #expect(d.deleteCandidate(index: 0).isEmpty && d.deleteCandidate(index: 1).isEmpty && d.removedCandidates.isEmpty)
        // Nothing composed.
        let e = Composer(engine: FakeEngine(), actionKey: .enter)
        #expect(e.deleteCandidate(index: 0).isEmpty && e.removedCandidates.isEmpty)
        #expect(!e.handleKeyDown(DeleteKeys.controlForwardDelete).handled && e.removedCandidates.isEmpty)
        // Voice input.
        let f = Composer(engine: FakeEngine(), voiceEnabled: true, actionKey: .enter)
        _ = f.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        _ = type("i", f)
        _ = f.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        _ = type("nihao", f)
        _ = f.handleFlagsChanged(keyCode: VirtualKey.rightOption, modifiers: [.option, .rightOption], timestamp: 0)
        _ = f.voiceHoldElapsed()
        #expect(f.voice != .off)
        #expect(f.deleteCandidate(index: 0).isEmpty && f.removedCandidates.isEmpty)
    }
}

// MARK: - Through a field's session

/// The same through a text field's session (`InputSession`, as the Mac's shell drives it: `FakeHost`): a candidate
/// removed reaches the shell (`SessionServices.removeCandidate`), which keeps it in the settings a moment later; the
/// settings' list reaches the composer, and one removed stays out while the file hasn't caught up.
@Suite(.serialized)
struct RemovedCandidatesSessionTests {
    final class Settings: @unchecked Sendable {
        var config: Config
        var removed: [String] = []
        var learned: [String] = []
        init(_ change: (inout Config) -> Void = { _ in }) {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
            config.setOrder([OutputLanguage.english, .chinese])
            config.claudeInBackground = false
            change(&config)
        }
    }

    /// `removing`: what the shell does with a candidate removed besides telling `settings` (the writer's write, done).
    func host(_ settings: Settings, engine: PinyinEngine = FakeEngine(), dictionary: Bool = false,
              load: (() -> Config)? = nil, removing: ((String) -> Void)? = nil) -> FakeHost {
        var services = SessionServices(loadSettings: load ?? { settings.config })
        services.levelOne = { .engine(engine) }
        services.programInstalled = { _ in true }
        services.removeCandidate = {
            settings.removed.append($0)
            removing?($0)
        }
        services.learnEnglishWord = { settings.learned.append($0) }
        if dictionary { services.englishDictionary = { EnglishDictionary(["hello"]) } }
        let host = FakeHost(services: services)
        host.app = "com.example.editor"
        host.focus()
        return host
    }

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    func rows(_ host: FakeHost) -> [String] { host.panel?.rows.map(\.text) ?? [] }
    func candidates(_ host: FakeHost) -> [String] { host.composer.engineState.candidates.map(\.text) }

    @Test func aRemovedCandidateReachesTheShell() async {
        await inEnglish {
            let settings = Settings()
            let engine = FakeEngine()
            let host = host(settings, engine: engine)
            host.type("nihao")
            #expect(rows(host) == ["你好", "拟好"])
            host.send(.delete(1))
            #expect(settings.removed == ["拟好"] && engine.deleted == [1], "\(settings.removed) \(engine.deleted)")
            #expect(rows(host) == ["你好"] && host.document.isEmpty && host.marked == "nihao", "\(rows(host)) \(host.document)")
            #expect(host.press(DeleteKeys.controlForwardDelete))
            #expect(settings.removed == ["拟好", "你好"] && engine.deleted == [1, 0], "\(settings.removed)")
            #expect(candidates(host).isEmpty && host.document.isEmpty && host.marked == "nihao")
            // Nothing shown: Space puts the letters in as typed.
            host.press(FakeHost.space)
            #expect(host.document == "nihao", "\(host.document)")
            // Nothing composed: nothing.
            host.send(.delete(0))
            #expect(!host.press(DeleteKeys.controlForwardDelete))
            #expect(settings.removed == ["拟好", "你好"])
        }
    }

    /// One @, pinyin composed after the magic key: a right-click (or Control-click) on its third row removes nothing, the
    /// pinyin's candidates on their line above the rows as they were, the shell told nothing; ⌃⌦ removes the line's
    /// first, the one the rows are for. Without one @, a right-click on the third row removes its candidate.
    @Test func aRightClickOnOneAtsRowRemovesNoCandidate() async {
        await inEnglish {
            let settings = Settings()
            let engine = FakeEngine()
            engine.dictionary["nihao"] = ["你好", "拟好", "泥好"]
            let host = host(settings, engine: engine)
            host.press(FakeHost.at)
            host.type("nihao")
            #expect(host.composer.oneAt?.text == "你好" && host.composer.engineState.isComposing)
            let (shown, line) = (rows(host), host.panel?.candidates)
            #expect(shown.count >= 3 && host.panel?.rows[2].choice == 2 && !shown.contains("泥好"), "\(shown)")
            #expect(line?.contains("泥好") == true, "the line: \(line ?? "none")")
            host.send(.delete(2))
            #expect(settings.removed.isEmpty && engine.deleted.isEmpty && host.composer.removedCandidates.isEmpty,
                    "\(settings.removed) \(engine.deleted)")
            #expect(candidates(host) == ["你好", "拟好", "泥好"] && host.panel?.candidates == line && rows(host) == shown,
                    "\(host.panel?.candidates ?? "none") \(rows(host))")
            #expect(host.document.isEmpty && host.composer.oneAt?.text == "你好", "\(host.document)")
            // ⌃⌦: the line's first.
            #expect(host.press(DeleteKeys.controlForwardDelete))
            #expect(settings.removed == ["你好"] && engine.deleted == [0], "\(settings.removed) \(engine.deleted)")
            #expect(candidates(host) == ["拟好", "泥好"] && host.composer.oneAt?.text == "拟好" && host.document.isEmpty,
                    "\(candidates(host)) \(host.document)")

            let other = Settings()
            let plain = FakeEngine()
            plain.dictionary["nihao"] = ["你好", "拟好", "泥好"]
            let field = self.host(other, engine: plain)
            field.type("nihao")
            #expect(rows(field) == ["你好", "拟好", "泥好"], "\(rows(field))")
            field.send(.delete(2))
            #expect(other.removed == ["泥好"] && plain.deleted == [2], "\(other.removed) \(plain.deleted)")
            #expect(rows(field) == ["你好", "拟好"] && field.document.isEmpty && field.marked == "nihao", "\(rows(field))")
        }
    }

    @Test func theSettingsListReachesTheComposer() async {
        await inEnglish {
            let settings = Settings { $0.removedCandidates = ["你好"] }
            let host = host(settings)
            host.type("nihao")
            #expect(rows(host) == ["拟好"], "\(rows(host))")
            host.press(FakeHost.space)
            #expect(host.document == "拟好")
            // Restored (Settings' ✕, another Mac's through iCloud): back.
            settings.config.removedCandidates = []
            host.send(.configChanged)
            host.type("nihao")
            #expect(rows(host) == ["你好", "拟好"], "\(rows(host))")
        }
    }

    /// Removed here, written a moment later: another change of the settings meanwhile doesn't bring it back; the file
    /// caught up, it stays out; restored there, it comes back.
    @Test func oneRemovedStaysOutWhileTheFileHasntCaughtUp() async {
        await inEnglish {
            let settings = Settings()
            let host = host(settings)
            host.type("nihao")
            host.send(.delete(1))
            host.press(FakeHost.escape)
            settings.config.typeOut = true
            settings.config.fuzzyPinyin = ["zh=z"]
            host.send(.configChanged)
            host.type("nihao")
            #expect(rows(host) == ["你好"], "not back with another setting: \(rows(host))")
            host.press(FakeHost.escape)
            settings.config.removedCandidates = settings.removed
            host.send(.configChanged)
            host.type("nihao")
            #expect(rows(host) == ["你好"], "\(rows(host))")
            host.press(FakeHost.escape)
            settings.config.removedCandidates = []
            host.send(.configChanged)
            host.type("nihao")
            #expect(rows(host) == ["你好", "拟好"], "restored: \(rows(host))")
        }
    }

    /// librime deployed again while the one removed isn't in the file yet: the new engine leaves it out too.
    @Test func oneRemovedStaysOutWhenLibrimeIsDeployedAgain() async {
        await inEnglish {
            let settings = Settings()
            var valid = true
            var services = SessionServices(loadSettings: { settings.config })
            services.levelOne = { .engine(FakeEngine()) }
            services.engineIsValid = { _ in valid }
            services.removeCandidate = { settings.removed.append($0) }
            services.englishDictionary = { EnglishDictionary(["hello"]) }
            let host = FakeHost(services: services)
            host.focus()
            host.type("nihao")
            host.send(.delete(1))
            host.press(FakeHost.escape)
            #expect(settings.removed == ["拟好"])
            valid = false
            _ = host.session.ensureEngine()
            valid = true
            host.type("nihao")
            #expect(rows(host) == ["你好"], "\(rows(host))")
        }
    }

    /// Settings' ✕ (`SettingsStore.restoreCandidate`) on the file: the session reads it and shows the candidate again.
    @Test func restoredInSettingsItComesBack() async throws {
        try await inEnglish {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("removed-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appendingPathComponent("config.json")
            try Settings { $0.removedCandidates = ["你好", "拟好"] }.config.write(to: url)
            let settings = Settings()
            let host = host(settings, load: { (try? Config.load(from: url)) ?? .default })
            host.type("nihao")
            #expect(rows(host).isEmpty, "\(rows(host))")
            host.press(FakeHost.escape)
            SettingsStore(configURL: url).restoreCandidate("你好")
            #expect(try Config.load(from: url).removedCandidates == ["拟好"])
            host.send(.configChanged)
            host.type("nihao")
            #expect(rows(host) == ["你好"], "\(rows(host))")
        }
    }

    /// Removed here and restored in Settings right after: the file has it by the time the field is left for Settings
    /// (`.blur`), so the field takes the file's list then, and the restore brings it back as the field takes the focus
    /// again. Twice, the same.
    @Test func aRestoreRightAfterARemovalOnceTheFieldLostFocus() async throws {
        try await inEnglish {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("removed-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appendingPathComponent("config.json")
            try Settings().config.write(to: url)
            let settings = Settings()
            let host = host(settings, load: { (try? Config.load(from: url)) ?? .default },
                            removing: { _ = try? RemovedCandidates.remove($0, at: url) })
            for round in 1...2 {
                host.type("nihao")
                #expect(rows(host) == ["你好", "拟好"], "\(round): \(rows(host))")
                host.send(.delete(1))
                #expect(rows(host) == ["你好"], "\(round): \(rows(host))")
                #expect(try Config.load(from: url).removedCandidates == ["拟好"], "the writer done")
                host.press(FakeHost.escape)
                host.send(.blur)
                SettingsStore(configURL: url).restoreCandidate("拟好")
                #expect(try Config.load(from: url).removedCandidates.isEmpty)
                host.focus()
                host.type("nihao")
                #expect(rows(host) == ["你好", "拟好"], "\(round): restored: \(rows(host))")
                host.press(FakeHost.escape)
            }
        }
    }

    /// A field as the Mac's shell makes it (`SessionServices.mac`): a candidate removed goes to `writer`
    /// (`EnglishWords.Writer`), into the config file at `url` a moment later; the settings are read from there, and the
    /// session asks the writer what it hasn't written yet (`SessionServices.unwrittenRemovals`).
    func field(_ url: URL, _ writer: EnglishWords.Writer, dictionary: Bool = false) -> FakeHost {
        var services = SessionServices(loadSettings: { (try? Config.load(from: url)) ?? .default })
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        services.removeCandidate = { writer.remove($0, at: url) }
        services.unwrittenRemovals = { writer.unwrittenRemovals(at: url) }
        if dictionary { services.englishDictionary = { EnglishDictionary(["hello"]) } }
        let host = FakeHost(services: services)
        host.app = "com.example.editor"
        host.focus()
        return host
    }

    /// A config file of these tests' settings (`change`d) in a folder of its own.
    func configFile(_ change: (inout Config) -> Void = { _ in }) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("removed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Settings(change).config.write(to: url)
        return url
    }

    /// What `host` shows for `letters`, the composition then cleared.
    func shown(_ letters: String, _ host: FakeHost) -> [String] {
        host.type(letters)
        defer { host.press(FakeHost.escape) }
        return candidates(host)
    }

    /// Removed, the field left (for Settings, say) before the writer wrote it: out until it is written, through the blur
    /// and a focus again (the file without it then). Written after the blur, restored in Settings (✕), the field takes
    /// the focus again: it shows, though the field never read the file with it.
    @Test func writtenAfterTheFieldWasLeftThenRestoredInSettingsItShows() async throws {
        try await inEnglish {
            let url = try configFile()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let writer = EnglishWords.Writer()
            let host = field(url, writer)
            #expect(shown("nihao", host) == ["你好", "拟好"])
            AIConfig.fileLock.lock()  // another writer holds the file: this one's write waits
            host.type("nihao")
            host.send(.delete(1))
            let removedThere = candidates(host)
            host.press(FakeHost.escape)
            host.send(.blur)
            let unwritten = writer.unwrittenRemovals(at: url)
            let file = (try? Config.load(from: url))?.removedCandidates
            host.focus()
            let focusedAgain = shown("nihao", host)
            host.send(.blur)
            AIConfig.fileLock.unlock()
            #expect(removedThere == ["你好"] && unwritten == ["拟好"] && file == [], "\(unwritten) \(String(describing: file))")
            #expect(focusedAgain == ["你好"], "out until it is written: \(focusedAgain)")
            writer.flush()
            #expect(try Config.load(from: url).removedCandidates == ["拟好"] && writer.unwrittenRemovals(at: url).isEmpty)
            SettingsStore(configURL: url).restoreCandidate("拟好")
            #expect(try Config.load(from: url).removedCandidates.isEmpty)
            host.focus()
            #expect(shown("nihao", host) == ["你好", "拟好"], "restored")
        }
    }

    /// Removed in a field that keeps the focus throughout: written, then restored on another Mac (iCloud sync writes
    /// this Mac's file without it), and the field reads the settings (another setting changed, the file watched): it
    /// shows, whether the field read the settings before the write (with it unwritten) or not at all.
    @Test func focusedThroughoutWhileAnotherMacRestoresItItShows() async throws {
        try await inEnglish {
            for readBeforeTheWrite in [false, true] {
                let url = try configFile()
                defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                let writer = EnglishWords.Writer()
                let host = field(url, writer)
                AIConfig.fileLock.lock()
                host.type("nihao")
                host.send(.delete(1))
                host.press(FakeHost.escape)
                if readBeforeTheWrite { host.send(.configChanged) }
                let before = shown("nihao", host)
                AIConfig.fileLock.unlock()
                #expect(before == ["你好"], "\(readBeforeTheWrite): \(before)")
                writer.flush()
                #expect(try Config.load(from: url).removedCandidates == ["拟好"])
                try AIConfig.patchingFile(at: url) { $0[Config.removedCandidatesKey] = nil }
                #expect(try Config.load(from: url).removedCandidates.isEmpty)
                host.send(.configChanged)
                #expect(shown("nihao", host) == ["你好", "拟好"], "\(readBeforeTheWrite): restored on another Mac")
            }
        }
    }

    /// Two fields: one removed in the first is out in the second before it is written (asked of the writer as the second
    /// takes the focus, and again as it reads the settings); written, the list's; restored in Settings before the second
    /// read the file with it, it shows there and in the first. The other way round the same.
    @Test func aRemovalInOneFieldIsOutInAnotherBeforeTheWrite() async throws {
        try await inEnglish {
            let url = try configFile()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let writer = EnglishWords.Writer()
            let first = field(url, writer), second = field(url, writer)
            #expect(shown("nihao", second) == ["你好", "拟好"])
            second.send(.blur)
            AIConfig.fileLock.lock()
            first.type("nihao")
            first.send(.delete(1))
            first.press(FakeHost.escape)
            first.send(.blur)
            second.focus()
            let focused = shown("nihao", second)
            second.send(.configChanged)
            let read = shown("nihao", second)
            AIConfig.fileLock.unlock()
            #expect(focused == ["你好"] && read == ["你好"], "before the write: \(focused) \(read)")
            writer.flush()
            #expect(try Config.load(from: url).removedCandidates == ["拟好"])
            SettingsStore(configURL: url).restoreCandidate("拟好")
            second.send(.configChanged)
            #expect(shown("nihao", second) == ["你好", "拟好"], "restored")
            second.send(.blur)
            first.focus()
            #expect(shown("nihao", first) == ["你好", "拟好"], "restored, the first field")

            // The other way round, and the list read meanwhile is an old one.
            first.send(.blur)
            second.focus()
            AIConfig.fileLock.lock()
            second.type("wo")
            second.send(.delete(0))
            let there = candidates(second)
            second.press(FakeHost.escape)
            second.send(.blur)
            first.focus()
            let other = shown("wo", first)
            AIConfig.fileLock.unlock()
            #expect(there == ["窝"] && other == ["窝"], "\(there) \(other)")
            writer.flush()
            first.send(.configChanged)
            #expect(shown("wo", first) == ["窝"], "written: the list's")
            #expect(try Config.load(from: url).removedCandidates == ["我"] && writer.unwrittenRemovals(at: url).isEmpty)
        }
    }

    /// One of the user's English words removed, then added again in Settings → English Words (`SettingsStore
    /// .addEnglishWords`): off the list of those removed, it comes up in the field again as it reads the settings.
    @Test func anEnglishWordAddedAgainInSettingsComesUp() async throws {
        try await inEnglish {
            let url = try configFile {
                $0.englishWords = ["Frobnicate"]
                $0.addedEnglishWords = ["Frobnicate"]
            }
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let writer = EnglishWords.Writer()
            let host = field(url, writer, dictionary: true)
            host.type("frobn")
            let before = candidates(host)
            let row = try #require(before.firstIndex(of: "Frobnicate"), "\(before)")
            host.send(.delete(row))
            host.press(FakeHost.escape)
            writer.flush()
            #expect(try Config.load(from: url).removedCandidates == ["Frobnicate"])
            host.send(.configChanged)
            #expect(!shown("frobn", host).contains("Frobnicate"))
            let added = SettingsStore(configURL: url).addEnglishWords("frobnicate")
            #expect(added.words == ["frobnicate"], "\(added)")
            let config = try Config.load(from: url)
            #expect(config.removedCandidates.isEmpty && config.englishWords == ["frobnicate"] && config.addedEnglishWords == ["frobnicate"],
                    "\(config.removedCandidates) \(config.englishWords)")
            host.send(.configChanged)
            #expect(shown("frobn", host).contains("frobnicate"), "comes up again: \(shown("frobn", host))")
        }
    }

    /// Removed here while the file lags (written a moment later): the settings' list changing meanwhile (another Mac's
    /// removal through iCloud), librime deployed again (a new engine, with English words among its candidates or
    /// without) and another setting changed don't bring it back. The file caught up, it is the file's: restored there,
    /// it comes back, the other stays out, also under a new engine after.
    @Test func oneRemovedStaysOutWhileTheListChangesAndTheFileLags() async {
        await inEnglish {
            for dictionary in [false, true] {
                let settings = Settings()
                var valid = true
                var services = SessionServices(loadSettings: { settings.config })
                services.levelOne = { .engine(FakeEngine()) }
                services.engineIsValid = { _ in valid }
                services.programInstalled = { _ in true }
                services.removeCandidate = { settings.removed.append($0) }
                if dictionary { services.englishDictionary = { EnglishDictionary(["hello"]) } }
                let host = FakeHost(services: services)
                host.focus()
                func shown(_ letters: String) -> [String] {
                    host.type(letters)
                    defer { host.press(FakeHost.escape) }
                    return candidates(host)
                }
                func newEngine() {
                    valid = false
                    _ = host.session.ensureEngine()
                    valid = true
                }
                host.type("nihao")
                host.send(.delete(1))
                host.press(FakeHost.escape)
                #expect(settings.removed == ["拟好"])
                settings.config.removedCandidates = ["窝"]
                host.send(.configChanged)
                #expect(shown("nihao") == ["你好"] && shown("wo") == ["我"], "\(dictionary): the list changed")
                newEngine()
                #expect(shown("nihao") == ["你好"] && shown("wo") == ["我"], "\(dictionary): a new engine")
                settings.config.typeOut = true
                host.send(.configChanged)
                host.send(.blur)
                host.focus()
                #expect(shown("nihao") == ["你好"], "\(dictionary): another setting, the field left")
                settings.config.removedCandidates = ["窝", "拟好"]
                host.send(.configChanged)
                #expect(shown("nihao") == ["你好"], "\(dictionary): caught up")
                settings.config.removedCandidates = ["窝"]
                host.send(.configChanged)
                #expect(shown("nihao") == ["你好", "拟好"] && shown("wo") == ["我"], "\(dictionary): restored")
                newEngine()
                #expect(shown("nihao") == ["你好", "拟好"] && shown("wo") == ["我"], "\(dictionary): restored, a new engine")
            }
        }
    }

    /// One of the user's own English words removed (`Config.englishWords`, added in Settings: `addedEnglishWords`): the
    /// file keeps it among their words, as Settings' English Words lists them, and has it on the list; it isn't offered
    /// again, in this field or another; ✕ in Removed candidates brings it back where it was.
    @Test func anEnglishWordOfTheUsersRemovedAndRestored() async throws {
        try await inEnglish {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("removed-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appendingPathComponent("config.json")
            try Settings {
                $0.englishWords = ["Frobnicate"]
                $0.addedEnglishWords = ["Frobnicate"]
            }.config.write(to: url)
            let load = { (try? Config.load(from: url)) ?? .default }
            let settings = Settings()
            let host = host(settings, dictionary: true, load: load, removing: { _ = try? RemovedCandidates.remove($0, at: url) })
            host.type("frobn")
            let before = candidates(host)
            let row = try #require(before.firstIndex(of: "Frobnicate"), "\(before)")
            host.send(.delete(row))
            #expect(settings.removed == ["Frobnicate"] && candidates(host) == before.filter { $0 != "Frobnicate" }, "\(candidates(host))")
            let file = try Config.load(from: url)
            #expect(file.englishWords == ["Frobnicate"] && file.addedEnglishWords == ["Frobnicate"], "\(file.englishWords)")
            #expect(file.removedCandidates == ["Frobnicate"])
            #expect(SettingsStore(configURL: url).config.englishWords == ["Frobnicate"], "Settings' English Words list it")
            host.press(FakeHost.escape)
            host.send(.blur)
            host.focus()
            host.type("frobn")
            #expect(!candidates(host).contains("Frobnicate"), "\(candidates(host))")
            host.press(FakeHost.escape)
            let other = self.host(Settings(), dictionary: true, load: load)
            other.type("frobn")
            #expect(!candidates(other).contains("Frobnicate"), "another field: \(candidates(other))")
            other.press(FakeHost.escape)
            SettingsStore(configURL: url).restoreCandidate("Frobnicate")
            let restored = try Config.load(from: url)
            #expect(restored.removedCandidates.isEmpty && restored.englishWords == ["Frobnicate"] && restored.addedEnglishWords == ["Frobnicate"])
            host.send(.blur)
            host.focus()
            host.type("frobn")
            #expect(candidates(host) == before, "back where it was: \(candidates(host))")
            other.send(.configChanged)
            other.type("frobn")
            #expect(candidates(other) == before, "another field: \(candidates(other))")
        }
    }

    /// One of the user's English words removed: the shell is told it as shown; it isn't offered again, and an English
    /// word on the list is never learned (another is).
    @Test func anEnglishWordRemovedIsNeitherOfferedNorLearned() async {
        await inEnglish {
            let settings = Settings {
                $0.englishWords = ["frobnicate"]
                $0.removedCandidates = ["Zorblax"]
            }
            let host = host(settings, dictionary: true)
            host.type("frobn")
            let row = candidates(host).firstIndex(of: "frobnicate")
            #expect(row != nil, "\(candidates(host))")
            if let row { host.send(.delete(row)) }
            #expect(settings.removed == ["frobnicate"] && !candidates(host).contains("frobnicate"), "\(settings.removed)")
            host.press(FakeHost.escape)
            host.type("frobn")
            #expect(!candidates(host).contains("frobnicate"), "\(candidates(host))")
            host.press(FakeHost.escape)
            for _ in 0..<2 {
                host.type("zorblax")
                host.press(FakeHost.enter)
            }
            #expect(settings.learned.isEmpty, "on the list: \(settings.learned)")
            for _ in 0..<2 {
                host.type("quuxify")
                host.press(FakeHost.enter)
            }
            #expect(settings.learned == ["quuxify"], "\(settings.learned)")
        }
    }
}

// MARK: - Kept in the config file

/// The list in the config file (`Config.removedCandidates`) and how it is written: off the key's thread
/// (`EnglishWords.Writer`), only its keys patched, in order with the words learned, within `RemovedCandidates.maxCount`.
@Suite(.serialized)
struct RemovedCandidatesStorageTests {
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("removed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func decoded(_ json: String) throws -> Config { try JSONDecoder().decode(Config.self, from: Data(json.utf8)) }

    func object(_ url: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test func readFromTheConfig() throws {
        #expect(try decoded("{}").removedCandidates == [])
        #expect(Config.default.removedCandidates == [])
        #expect(try decoded(#"{"removedCandidates": ["鸡虎", "Bedrock", "😂"]}"#).removedCandidates == ["鸡虎", "Bedrock", "😂"])
        // A wrong type reads as none; the other settings as they are.
        for wrong in [#""鸡虎""#, "5", "[1, 2]", #"["鸡虎", 3]"#, #"{"a": "b"}"#, "null", "true"] {
            let config = try decoded(#"{"removedCandidates": \#(wrong), "typeOut": true}"#)
            #expect(config.removedCandidates == [] && config.typeOut, "\(wrong)")
        }
        // Over the limit: the newest kept.
        let many = (0..<(RemovedCandidates.maxCount + 3)).map { "词\($0)" }
        let json = String(decoding: try JSONEncoder().encode(["removedCandidates": many]), as: UTF8.self)
        #expect(try decoded(json).removedCandidates == Array(many.suffix(RemovedCandidates.maxCount)))
    }

    @Test func writtenOnlyWhenThereAreAny() throws {
        let none = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Config.default)) as? [String: Any])
        #expect(none["removedCandidates"] == nil)
        var config = Config.default
        config.removedCandidates = ["鸡虎", "Bedrock"]
        let some = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        #expect(some["removedCandidates"] as? [String] == ["鸡虎", "Bedrock"])
        #expect(Config.removedCandidatesKey == "removedCandidates" && ICloudSync.removedCandidatesKey == Config.removedCandidatesKey)
    }

    @Test func theList() {
        #expect(RemovedCandidates.adding("鸡虎", to: []) == ["鸡虎"])
        #expect(RemovedCandidates.adding("鸡虎", to: ["鸭虎", "鸡虎"]) == ["鸭虎", "鸡虎"], "once")
        #expect(RemovedCandidates.adding("", to: ["鸭虎"]) == ["鸭虎"])
        let full = (0..<RemovedCandidates.maxCount).map { "词\($0)" }
        let more = RemovedCandidates.adding("鸡虎", to: full)
        #expect(more.count == RemovedCandidates.maxCount && more.first == "词1" && more.last == "鸡虎", "the oldest go first")
        #expect(RemovedCandidates.restoring("鸡虎", from: ["鸭虎", "鸡虎", "压机"]) == ["鸭虎", "压机"])
        #expect(RemovedCandidates.restoring("鸡虎", from: ["鸭虎"]) == ["鸭虎"])
        // English words by their letters; nothing else.
        #expect(RemovedCandidates.keys(["Bedrock", "鸡虎", "😂", "GitHub Pages", "2026-11-03"]) == ["bedrock", "githubpages"])
    }

    /// Where librime's filter can't tell (`RimeSession.deleteCandidate` without it), a candidate with no letter or digit
    /// isn't a word to ask librime to delete: an emoji (one of several code points too), a symbol, a radical that is one.
    /// Any with a letter or digit of any script may be, and one this Mac doesn't know yet.
    @Test func whatMayBeAWordByItsTextAlone() {
        for emoji in ["👏", "🔑", "🗝", "👨‍👩‍👧", "✈️", "🇫🇯", "⺁", "·", "→", ""] {
            #expect(!RemovedCandidates.mayBeAWord(emoji), "\(emoji)")
        }
        for word in ["鼓掌", "紐幣", "讠", "January", "Mon.", "1️⃣", "3", "Ⅻ", "ㄅ", "가", "क", "鼓👏", "\u{3347F}", "\u{E000}"] {
            #expect(RemovedCandidates.mayBeAWord(word), "\(word)")
        }
    }

    /// What a field's session gives level one (`RemovedCandidates.Given`): the settings' list when it changed, with those
    /// removed in the field it doesn't have yet; one the list has is the list's from then on, which a restore brings back.
    @Test func whatAFieldGivesLevelOne() {
        var given = RemovedCandidates.Given()
        #expect(given.taking([]) == [])
        #expect(given.taking([]) == nil, "the same list: nothing to give")
        given.removed("拟好")
        given.removed("拟好")
        #expect(given.taking([]) == nil, "level one leaves it out already")
        #expect(given.taking(["窝"]) == ["窝", "拟好"], "the list changed, the file still without it")
        #expect(given.taking(["窝", "拟好"]) == ["窝", "拟好"], "caught up")
        #expect(given.taking(["窝"]) == ["窝"], "restored: the list's")
        #expect(given.taking([]) == [], "and again")
        given.removed("你好")
        given.removed("鸭虎")
        #expect(given.taking(["压机"]) == ["压机", "你好", "鸭虎"], "oldest first")
        #expect(given.taking(["压机", "鸭虎"]) == ["压机", "鸭虎", "你好"], "one caught up, the other not yet")
    }

    /// The same where the shell tells those not written yet (`unwritten`, the Mac's `EnglishWords.Writer`): every one of
    /// them is given, removed in this field or another, whatever list is read meanwhile; once written (no longer told),
    /// the list's: one the list doesn't have then (restored there, before the field read it with it or after) comes
    /// back, also when the list is the one taken last.
    @Test func whatAFieldGivesLevelOneWithWhatIsntWrittenYet() {
        var given = RemovedCandidates.Given()
        #expect(given.taking([], unwritten: []) == [])
        given.removed("拟好")
        #expect(given.taking([], unwritten: ["拟好"]) == nil, "level one leaves it out already")
        #expect(given.taking([], unwritten: ["拟好", "窝"]) == ["拟好", "窝"], "another field's, not written yet")
        #expect(given.taking(["压机"], unwritten: ["拟好", "窝"]) == ["压机", "拟好", "窝"], "an old list or another")
        #expect(given.taking(["压机", "拟好"], unwritten: ["窝"]) == ["压机", "拟好", "窝"], "one written")
        #expect(given.taking(["压机", "拟好", "窝"], unwritten: []) == ["压机", "拟好", "窝"], "both written")
        #expect(given.taking(["压机", "窝"], unwritten: []) == ["压机", "窝"], "restored")
        #expect(given.taking(["压机", "窝"], unwritten: []) == nil)

        // Written while the field didn't read the list, then restored: the list read then is the one taken last.
        var focused = RemovedCandidates.Given()
        #expect(focused.taking(["窝"], unwritten: []) == ["窝"])
        focused.removed("拟好")
        #expect(focused.taking(["窝"], unwritten: ["拟好"]) == nil, "not written yet")
        #expect(focused.taking(["窝"], unwritten: []) == ["窝"], "written and restored before the field read it")
        #expect(focused.taking(["窝"], unwritten: []) == nil)
        // Another field's, not written yet, then written and restored before this one read the list again.
        #expect(focused.taking(["窝"], unwritten: ["你好"]) == ["窝", "你好"])
        #expect(focused.taking(["窝"], unwritten: []) == ["窝"])

        // The shell can't tell (nil): those removed here until the list has them, as before.
        var untold = RemovedCandidates.Given()
        #expect(untold.taking([], unwritten: nil) == [])
        untold.removed("拟好")
        #expect(untold.taking([], unwritten: nil) == nil)
        #expect(untold.taking(["窝"], unwritten: nil) == ["窝", "拟好"])
        #expect(untold.taking(["窝", "拟好"], unwritten: nil) == ["窝", "拟好"])
        #expect(untold.taking(["窝"], unwritten: nil) == ["窝"])
    }

    /// The writer tells the candidates removed it hasn't written into a file yet (`unwrittenRemovals(at:)`), oldest
    /// first, that file's only, never the words learned: waiting (the file held by another writer), kept after their
    /// write failed (a file that doesn't parse), and drops each once it is in the file. Never waits for a write.
    @Test func theWriterTellsTheRemovalsNotWrittenYet() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json"), other = dir.appendingPathComponent("other.json")
        let broken = Data(#"{"typeOut": true,, "englishWords": ["Bedrock"]}"#.utf8)
        try broken.write(to: url)
        try Data(#"{"typeOut": true}"#.utf8).write(to: other)
        let writer = EnglishWords.Writer()
        #expect(writer.unwrittenRemovals(at: url).isEmpty)

        // Waiting: the file held by another writer.
        AIConfig.fileLock.lock()
        writer.remove("鸡虎", at: url)
        writer.learn("zorblax", at: url)
        writer.remove("鸭虎", at: other)
        writer.remove("😂", at: url)
        let waiting = writer.unwrittenRemovals(at: url), elsewhere = writer.unwrittenRemovals(at: other)
        AIConfig.fileLock.unlock()
        #expect(waiting == ["鸡虎", "😂"] && elsewhere == ["鸭虎"], "\(waiting) \(elsewhere)")

        // Written where the file parses; kept where it doesn't, still unwritten.
        writer.flush()
        #expect(try Data(contentsOf: url) == broken)
        #expect(writer.unwrittenRemovals(at: url) == ["鸡虎", "😂"], "kept after a failed write")
        #expect(try writer.unwrittenRemovals(at: other).isEmpty && Config.load(from: other).removedCandidates == ["鸭虎"])
        writer.remove("鸡虎", at: url)  // removed again in another field meanwhile
        writer.flush()
        #expect(writer.unwrittenRemovals(at: url) == ["鸡虎", "😂", "鸡虎"])

        // The file fixed: written, and no longer unwritten.
        try Data(#"{"typeOut": true, "englishWords": ["Bedrock"]}"#.utf8).write(to: url)
        writer.retry()
        writer.flush()
        let config = try Config.load(from: url)
        #expect(config.removedCandidates == ["鸡虎", "😂"] && config.englishWords == ["Bedrock", "zorblax"], "\(config.removedCandidates)")
        #expect(writer.unwrittenRemovals(at: url).isEmpty)
        // One the file has already: nothing written, no longer unwritten either.
        writer.remove("😂", at: url)
        writer.flush()
        #expect(try writer.unwrittenRemovals(at: url).isEmpty && Config.load(from: url).removedCandidates == ["鸡虎", "😂"])
        // Learned only: nothing unwritten.
        AIConfig.fileLock.lock()
        writer.learn("quuxify", at: url)
        let learned = writer.unwrittenRemovals(at: url)
        AIConfig.fileLock.unlock()
        #expect(learned.isEmpty)
        #expect(writer.drain(within: 10))
    }

    /// Read from another thread while the writer's queue writes (as the session asks it, just before it reads the file):
    /// from the moment it is told, each candidate removed is unwritten or in the file, never neither; at the end, all in
    /// the file, none unwritten.
    @Test func eachRemovalIsUnwrittenOrInTheFile() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data(#"{"typeOut": true}"#.utf8).write(to: url)
        let writer = EnglishWords.Writer()
        var told: [String] = []
        var misses: [String] = []
        for i in 0..<60 {
            let text = "词\(i)"
            writer.remove(text, at: url)
            if i.isMultiple(of: 3) { writer.learn("zorb" + String(repeating: "a", count: i / 3 + 1), at: url) }
            told.append(text)
            // The order the session asks in: what isn't written, then the file.
            let unwritten = Set(writer.unwrittenRemovals(at: url))
            let listed = Set((try? Config.load(from: url))?.removedCandidates ?? [])
            misses += told.filter { !unwritten.contains($0) && !listed.contains($0) }
        }
        #expect(misses.isEmpty, "neither unwritten nor in the file: \(misses)")
        writer.flush()
        #expect(writer.unwrittenRemovals(at: url).isEmpty)
        #expect(try Config.load(from: url).removedCandidates == told)
    }

    /// A removal patches the file as it is: only `removedCandidates` changes, every other key keeps its text (spacing,
    /// numbers, a later version's key), nothing of the English words when it isn't one.
    @Test func writtenIntoTheFileAlone() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        let text = """
            {
              "provider" : "anthropic",
              "maxTokens": 1000,
              "aLaterVersionsKey" : {"kept": [1, 2.50, "as is"]},
              "englishWords" : ["Bedrock"],
              "inputLanguages" : ["zh", "en"]
            }

            """
        try Data(text.utf8).write(to: url)
        let before = try object(url)
        let writer = EnglishWords.Writer()
        writer.remove("鸡虎", at: url)
        writer.flush()
        let after = try object(url)
        #expect(after["removedCandidates"] as? [String] == ["鸡虎"])
        #expect(Set(after.keys) == Set(before.keys).union(["removedCandidates"]), "\(after.keys)")
        for (key, value) in before { #expect((after[key] as? NSObject)?.isEqual(value) == true, "\(key)") }
        let written = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        for line in text.split(separator: "\n") where line.contains(":") {
            let kept = line.hasSuffix(",") ? String(line.dropLast()) : String(line)
            #expect(written.contains(kept), "\(kept) in \(written)")
        }
        // A second one at the end; the same again changes nothing.
        writer.remove("😂", at: url)
        writer.remove("鸡虎", at: url)
        writer.flush()
        #expect(try Config.load(from: url).removedCandidates == ["鸡虎", "😂"])
        #expect(try !RemovedCandidates.remove("鸡虎", at: url), "already there")
        // No file yet: one is written.
        let fresh = dir.appendingPathComponent("fresh.json")
        #expect(try RemovedCandidates.remove("鸭虎", at: fresh))
        #expect(try Config.load(from: fresh).removedCandidates == ["鸭虎"])
    }

    /// One of the user's English words removed: on the list, and still among their words, added or learned, as Settings'
    /// English Words lists them (removing only leaves it out; the owner's decision). The engine made from the file doesn't
    /// offer it, a word learned with its letters isn't learned again (also once the user takes it off their words), and a
    /// restore (✕) offers it again as it was.
    @Test func anEnglishWordOfTheUsersStaysInTheirWords() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data(#"{"typeOut": true, "englishWords": ["BEDROCK", "frobnicate"], "addedEnglishWords": ["BEDROCK"], "futureKey": [1]}"#.utf8)
            .write(to: url)
        /// What the engine made from the file shows for "bedrock" (librime's one candidate for it: 贝德).
        func shown() throws -> [String] {
            let config = try Config.load(from: url)
            let mixed = EnglishWordsEngine(base: PagesEngine(["bedrock": ["贝德"]]), dictionary: EnglishDictionary([]),
                                           words: EnglishWords.offered(config, jargon: []), removedCandidates: config.removedCandidates)
            let c = Composer(engine: mixed, actionKey: .enter)
            for letter in "bedrock" { _ = c.handleKeyDown(k(String(letter))) }
            return c.engineState.candidates.map(\.text)
        }
        let before = try shown()
        #expect(before.contains("BEDROCK") && before.contains("贝德"), "\(before)")
        let writer = EnglishWords.Writer()
        writer.remove("Bedrock", at: url)
        writer.flush()
        let after = try object(url)
        #expect(after["englishWords"] as? [String] == ["BEDROCK", "frobnicate"])
        #expect(after["addedEnglishWords"] as? [String] == ["BEDROCK"])
        #expect(after["removedCandidates"] as? [String] == ["Bedrock"])
        #expect(after["typeOut"] as? Bool == true && after["futureKey"] as? [Int] == [1])
        #expect(SettingsStore(configURL: url).config.englishWords == ["BEDROCK", "frobnicate"], "Settings' English Words list it")
        let removed = try shown()
        #expect(removed == before.filter { $0 != "BEDROCK" }, "not offered: \(removed)")
        #expect(try !EnglishWords.learn("Bedrock", at: url))
        // Restored: offered again as it was, the words as they were.
        SettingsStore(configURL: url).restoreCandidate("Bedrock")
        let restored = try Config.load(from: url)
        #expect(restored.removedCandidates.isEmpty && restored.englishWords == ["BEDROCK", "frobnicate"]
                && restored.addedEnglishWords == ["BEDROCK"], "\(restored.englishWords) \(restored.addedEnglishWords)")
        let back = try shown()
        #expect(back == before, "\(back)")
        // Removed, then taken off the user's words in Settings: never learned again.
        writer.remove("frobnicate", at: url)
        writer.flush()
        #expect(try Config.load(from: url).englishWords == ["BEDROCK", "frobnicate"])
        SettingsStore(configURL: url).removeEnglishWord("frobnicate")
        #expect(try Config.load(from: url).englishWords == ["BEDROCK"])
        writer.learn("Frobnicate", at: url)
        writer.flush()
        #expect(try Config.load(from: url).englishWords == ["BEDROCK"], "on the list: not learned")
        // In memory, as Settings would do it.
        var config = Config.default
        config.englishWords = ["Bedrock", "zorblax"]
        config.addedEnglishWords = ["Bedrock"]
        RemovedCandidates.remove("bedrock", from: &config)
        #expect(config.englishWords == ["Bedrock", "zorblax"] && config.addedEnglishWords == ["Bedrock"] && config.removedCandidates == ["bedrock"])
        RemovedCandidates.remove("鸡虎", from: &config)
        #expect(config.englishWords == ["Bedrock", "zorblax"] && config.removedCandidates == ["bedrock", "鸡虎"])
    }

    /// Removed and learned at once, in either order: written in order; one on the list is never learned, also by a write
    /// of its own (another field, another Mac's list); one learned and then removed stays among the words learned
    /// (removing only leaves it out).
    @Test func removedAndLearnedInOrder() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data(#"{"englishWords": ["Bedrock"]}"#.utf8).write(to: url)
        let writer = EnglishWords.Writer()
        // The file held by another writer meanwhile: they wait, and go in in order.
        AIConfig.fileLock.lock()
        writer.remove("Zorblax", at: url)
        writer.learn("zorblax", at: url)
        writer.learn("wibble", at: url)
        writer.remove("wibble", at: url)
        writer.learn("quuxify", at: url)
        AIConfig.fileLock.unlock()
        writer.flush()
        let config = try Config.load(from: url)
        #expect(config.englishWords == ["Bedrock", "wibble", "quuxify"], "\(config.englishWords)")
        #expect(config.removedCandidates == ["Zorblax", "wibble"])
        #expect(try !EnglishWords.learn("ZORBLAX", at: url))
        #expect(try !EnglishWords.learn("Wibble", at: url))
        #expect(try Config.load(from: url).englishWords == ["Bedrock", "wibble", "quuxify"])
        // One by one too.
        writer.remove("Frobnicate", at: url)
        writer.flush()
        writer.learn("frobnicate", at: url)
        writer.flush()
        #expect(try !Config.load(from: url).englishWords.contains { EnglishWords.key($0) == "frobnicate" })
    }

    /// A removal whose write failed (a file that doesn't parse) is kept, never lost: written once the file takes it, and
    /// drained before the process ends.
    @Test func aRemovalWhoseWriteFailedIsKept() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        let broken = Data(#"{"typeOut": true,, "englishWords": ["Bedrock"]}"#.utf8)
        try broken.write(to: url)
        let writer = EnglishWords.Writer()
        writer.remove("鸡虎", at: url)
        writer.flush()
        #expect(try Data(contentsOf: url) == broken)
        try Data(#"{"typeOut": true, "englishWords": ["Bedrock"]}"#.utf8).write(to: url)
        writer.retry()
        writer.flush()
        #expect(try Config.load(from: url).removedCandidates == ["鸡虎"])
        writer.remove("鸭虎", at: url)
        #expect(writer.drain(within: 10))
        #expect(try Config.load(from: url).removedCandidates == ["鸡虎", "鸭虎"])
    }

    @Test func atMostTheLimitTheOldestGoFirst() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        let full = (0..<RemovedCandidates.maxCount).map { "词\($0)" }
        try JSONSerialization.data(withJSONObject: ["removedCandidates": full, "typeOut": true]).write(to: url)
        #expect(try RemovedCandidates.remove("鸡虎", at: url))
        let list = try object(url)["removedCandidates"] as? [String] ?? []
        #expect(list.count == RemovedCandidates.maxCount && list.first == "词1" && list.last == "鸡虎", "\(list.count)")
    }

    /// One on the list (by its letters, `RemovedCandidates.keys`) is never learned; another word is.
    @Test func aRemovedWordIsNeverLearned() {
        let dictionary = EnglishDictionary(["hello"])
        #expect(EnglishWords.learnable("zorblax", known: [], dictionary: dictionary, hidden: []))
        #expect(!EnglishWords.learnable("zorblax", known: [], dictionary: dictionary, hidden: [], removed: ["zorblax"]))
        #expect(!EnglishWords.learnable("Zorblax", known: [], dictionary: dictionary, hidden: [],
                                        removed: RemovedCandidates.keys(["ZORBLAX"])))
        let editor = FieldInfo(app: "com.example.editor")
        let once = EnglishWords.TypedOnce()
        for _ in 0..<2 {
            #expect(!EnglishWords.learns("zorblax", in: editor, secureInput: false, config: { .default }, offered: [],
                                         dictionary: dictionary, removed: ["zorblax"], typedOnce: once))
        }
        let other = EnglishWords.TypedOnce()
        #expect(!EnglishWords.learns("quuxify", in: editor, secureInput: false, config: { .default }, offered: [],
                                     dictionary: dictionary, removed: ["zorblax"], typedOnce: other))
        #expect(EnglishWords.learns("quuxify", in: editor, secureInput: false, config: { .default }, offered: [],
                                    dictionary: dictionary, removed: ["zorblax"], typedOnce: other), "the second time")
        let typed = EnglishWords.TypedOnce()
        for _ in 0..<2 {
            #expect(!EnglishWords.learnsTypedInEnglish("zorblax", in: editor, secureInput: false, config: { .default },
                                                       offered: [], dictionary: dictionary, removed: ["zorblax"], typedOnce: typed))
        }
        // The engine's keys.
        let engine = EnglishWordsEngine(base: FakeEngine(), dictionary: dictionary, removedCandidates: ["Zorblax", "鸡虎"])
        #expect(engine.removedKeys == ["zorblax"])
        engine.removedCandidates.append("Quuxify")
        #expect(engine.removedKeys == ["zorblax", "quuxify"])
    }
}

// MARK: - Settings

/// Settings → Input → Chinese → Removed candidates' ✕ (`SettingsStore.restoreCandidate`): on the list as the file has it
/// then, only that key written.
struct RemovedCandidatesSettingsTests {
    func file(_ text: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("removed-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("config.json")
        try Data(text.utf8).write(to: url)
        return url
    }

    func text(_ url: URL) throws -> String { String(decoding: try Data(contentsOf: url), as: UTF8.self) }

    @Test func restoredFromTheFileAsItIsNow() throws {
        let original = """
            {
              "maxTokens": 1000,
              "aLaterVersionsKey" : {"kept": [1, 2.50, "as is"]},
              "englishWords" : ["frobnicate"],
              "removedCandidates" : ["鸡虎", "Bedrock", "鸭虎"]
            }

            """
        let url = try file(original)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SettingsStore(configURL: url)
        #expect(store.config.removedCandidates == ["鸡虎", "Bedrock", "鸭虎"])
        store.restoreCandidate("Bedrock")
        #expect(try Config.load(from: url).removedCandidates == ["鸡虎", "鸭虎"] && store.config.removedCandidates == ["鸡虎", "鸭虎"])
        let written = try text(url)
        #expect(written.contains("\"maxTokens\": 1000") && written.contains(#""aLaterVersionsKey" : {"kept": [1, 2.50, "as is"]}"#), "\(written)")
        #expect(try Config.load(from: url).englishWords == ["frobnicate"], "an English word restored isn't put back among the user's")
        // One removed meanwhile (the writer, another field) stays.
        try RemovedCandidates.remove("压机", at: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        store.restoreCandidate("鸡虎")
        let meanwhile = try Config.load(from: url).removedCandidates
        #expect(meanwhile == ["鸭虎", "压机"], "\(meanwhile)")
        // One not there: nothing written.
        let now = try text(url)
        store.restoreCandidate("鸡虎")
        #expect(try text(url) == now)
        // The last ones: the key goes.
        store.restoreCandidate("鸭虎")
        store.restoreCandidate("压机")
        let last = try text(url)
        #expect(!last.contains("removedCandidates") && store.config.removedCandidates.isEmpty, "\(last)")
        #expect(try text(url).contains("\"maxTokens\": 1000"))
    }

    /// Settings → English Words' Add (`EnglishWords.add`): each word added comes off the list of those removed by its
    /// letters, whatever its spelling there (one of the user's own removed is added again, a learned one becomes theirs),
    /// so that it comes up again; nothing else on the list does (Chinese, another word, a longer one with its letters
    /// in it). Nothing added (not a word, one of theirs not removed): the list as it was. The settings window's list
    /// (`EnglishWords.edit`, Windows' Settings app) the same for a word it adds.
    @Test func anEnglishWordAddedComesOffTheRemovedList() {
        var config = Config.default
        config.englishWords = ["BEDROCK", "frobnicate"]
        config.addedEnglishWords = ["BEDROCK"]
        config.removedCandidates = ["Bedrock", "鸡虎", "Zorblax", "frobnicate", "Bedrocks", "GitHub Pages"]
        let added = EnglishWords.add("bedrock, zorblax", to: &config)
        #expect(added.words == ["bedrock", "zorblax"] && added.refused.isEmpty, "\(added)")
        #expect(config.removedCandidates == ["鸡虎", "frobnicate", "Bedrocks", "GitHub Pages"], "\(config.removedCandidates)")
        #expect(config.englishWords == ["frobnicate", "bedrock", "zorblax"], "\(config.englishWords)")
        #expect(config.addedEnglishWords == ["bedrock", "zorblax"], "\(config.addedEnglishWords)")
        let before = config
        for nothing in ["鸡虎", "Bedrock", "BEDROCK, zorblax", "2026"] {
            #expect(EnglishWords.add(nothing, to: &config) == EnglishWords.Added() && config == before, "\(nothing)")
        }
        // A learned word of theirs removed: added, theirs now, off the list.
        #expect(EnglishWords.add("Frobnicate", to: &config).words == ["Frobnicate"])
        #expect(config.removedCandidates == ["鸡虎", "Bedrocks", "GitHub Pages"] && config.addedEnglishWords == ["bedrock", "zorblax", "Frobnicate"])
        // The settings window's list.
        var listed = Config.default
        listed.englishWords = ["Bedrock"]
        listed.removedCandidates = ["鸡虎", "Quuxify"]
        #expect(EnglishWords.edit(&listed, to: ["Bedrock", "quuxify"]) == nil)
        #expect(listed.removedCandidates == ["鸡虎"] && listed.englishWords == ["Bedrock", "quuxify"], "\(listed.removedCandidates)")
    }

    /// The same through Settings (`SettingsStore.addEnglishWords`) on the file as it is: Settings' list of those removed
    /// shows it gone at once, the file has it off the list and the other keys as they were, and the engine made from the
    /// file offers it again.
    @Test func addedInSettingsItComesOffTheFileAndComesUp() throws {
        let url = try file("""
            {"typeOut": true, "englishWords": ["Bedrock"], "addedEnglishWords": ["Bedrock"],
             "removedCandidates": ["鸡虎", "Bedrock", "Zorblax"], "futureKey": [1]}
            """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        /// What the engine made from the file shows for "bedrock" (librime's one candidate for it: 贝德).
        func shown() throws -> [String] {
            let config = try Config.load(from: url)
            let mixed = EnglishWordsEngine(base: PagesEngine(["bedrock": ["贝德"]]), dictionary: EnglishDictionary([]),
                                           words: EnglishWords.offered(config, jargon: []), removedCandidates: config.removedCandidates)
            let c = Composer(engine: mixed, actionKey: .enter)
            for letter in "bedrock" { _ = c.handleKeyDown(k(String(letter))) }
            return c.engineState.candidates.map(\.text)
        }
        #expect(try shown() == ["贝德"])
        let store = SettingsStore(configURL: url)
        #expect(store.config.removedCandidates == ["鸡虎", "Bedrock", "Zorblax"])
        #expect(store.addEnglishWords("bedrock").words == ["bedrock"])
        #expect(store.config.removedCandidates == ["鸡虎", "Zorblax"], "Settings' list: \(store.config.removedCandidates)")
        let saved = try Config.load(from: url)
        #expect(saved.removedCandidates == ["鸡虎", "Zorblax"] && saved.englishWords == ["bedrock"] && saved.addedEnglishWords == ["bedrock"])
        #expect(try saved.typeOut && text(url).contains("futureKey"))
        let back = try shown()
        #expect(back.contains("bedrock"), "\(back)")
        #expect(store.addEnglishWords("ZORBLAX").words == ["ZORBLAX"])
        #expect(try store.config.removedCandidates == ["鸡虎"] && Config.load(from: url).removedCandidates == ["鸡虎"])
    }

    /// Another setting saved by a window that read the file before a candidate was removed doesn't put the list back.
    @Test func anotherSettingSavedKeepsOneRemovedMeanwhile() throws {
        let url = try file(#"{"typeOut": false, "removedCandidates": ["鸡虎"]}"#)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SettingsStore(configURL: url)
        try RemovedCandidates.remove("鸭虎", at: url)
        store.config.typeOut = true
        store.save()
        let config = try Config.load(from: url)
        #expect(config.typeOut && config.removedCandidates == ["鸡虎", "鸭虎"], "\(config.removedCandidates)")
    }
}

// MARK: - iCloud

/// The list syncs with the learned words (`ICloudSync.Category.learnedWords`), merged by union when a Mac joins, as the
/// English words added are; afterwards as those keys sync, the newer winning. Nothing else in the merge changes.
@Suite(.serialized)
struct RemovedCandidatesSyncTests {
    func t(_ minutes: Double) -> Date { SyncRig.t0.addingTimeInterval(minutes * 60) }

    @Test func withTheLearnedWords() {
        #expect(ICloudSync.category(of: ICloudSync.removedCandidatesKey) == .learnedWords)
        #expect(ICloudSync.mergedOnJoin.contains(ICloudSync.removedCandidatesKey))
        #expect(!ICloudSync.neverSynced.contains(ICloudSync.removedCandidatesKey))
        var config = Config.default
        config.removedCandidates = ["鸡虎", "Bedrock"]
        #expect(ICloudSync.values(of: config, in: [.learnedWords])[ICloudSync.removedCandidatesKey]
                == .array([.string("鸡虎"), .string("Bedrock")]))
        #expect(ICloudSync.values(of: .default, in: [.learnedWords])[ICloudSync.removedCandidatesKey] == .array([]))
        #expect(ICloudSync.values(of: config, in: [.settings, .jargon, .hiddenWords])[ICloudSync.removedCandidatesKey] == nil)
    }

    @Test func mergedByUnionWhenAMacJoins() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") {
            $0.removedCandidates = ["鸡虎", "Bedrock"]
            $0.englishWords = ["frobnicate"]
            $0.typeOut = true
        }
        a.sync(at: t(0))
        let b = try rig.mac("B") {
            $0.removedCandidates = ["鸭虎", "鸡虎", "bedrock"]
            $0.englishWords = ["zorblax"]
            $0.typeOut = false
        }
        b.sync(at: t(1))
        a.sync(at: t(2))
        for mac in [a, b] {
            let config = try mac.config()
            #expect(Set(config.removedCandidates) == ["鸡虎", "Bedrock", "鸭虎", "bedrock"] && config.removedCandidates.count == 4,
                    "each once, by its whole text: \(config.removedCandidates)")
            // The rest of the join as before: the English words merged, a setting iCloud's.
            #expect(config.englishWords == ["frobnicate", "zorblax"], "\(config.englishWords)")
            #expect(config.typeOut)
        }
        // Joined: one removed on a Mac gets to the other; one restored goes from both (the newer wins).
        try RemovedCandidates.remove("压机", at: a.configURL)
        try a.touch(a.configURL, at: t(3))
        a.sync(at: t(4))
        b.sync(at: t(5))
        #expect(try b.config().removedCandidates.contains("压机"))
        try b.edit(at: t(6)) { $0.removedCandidates = RemovedCandidates.restoring("鸡虎", from: $0.removedCandidates) }
        b.sync(at: t(7))
        a.sync(at: t(8))
        for mac in [a, b] {
            let list = try mac.config().removedCandidates
            #expect(!list.contains("鸡虎") && Set(list) == ["Bedrock", "鸭虎", "bedrock", "压机"], "\(list)")
        }
    }

    /// A Mac that joins with none takes iCloud's list.
    @Test func aMacJoiningWithNoneTakesIcloudsList() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") { $0.removedCandidates = ["鸡虎"] }
        a.sync(at: t(0))
        let b = try rig.mac("B")
        b.sync(at: t(1))
        a.sync(at: t(2))
        for mac in [a, b] { #expect(try mac.config().removedCandidates == ["鸡虎"]) }
    }

    /// Macs that synced before the list (their records, and iCloud, without the key), then upgraded: one removed on one
    /// gets to the other, which never puts its empty list over it, also with its config file last written by sync.
    @Test func aMacUpgradedFromBeforeTheListKeepsOnesRemovedOnAnother() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A"), b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        for mac in [a, b] {
            var state = mac.state
            state.entries[ICloudSync.removedCandidatesKey] = nil
            if mac.dir == a.dir { state.ownConfigWrite = ICloudSyncEngine.modificationDate(mac.configURL) }
            try state.write(to: mac.engine.stateURL)
        }
        var settings = try rig.settingsJSON()
        settings[ICloudSync.removedCandidatesKey] = nil
        try JSONSerialization.data(withJSONObject: settings).write(to: rig.folder.url.appendingPathComponent(ICloudSync.settingsFile))
        try b.edit(at: t(10)) { RemovedCandidates.remove("鸡虎", from: &$0) }
        b.sync(at: t(11))
        a.sync(at: t(20))
        b.sync(at: t(21))
        for mac in [a, b] { #expect(try mac.config().removedCandidates == ["鸡虎"], "\(mac.dir.lastPathComponent)") }
    }

    @Test func notWithTheLearnedWordsOff() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") {
            $0.removedCandidates = ["鸡虎"]
            $0.iCloudSync.learnedWords = false
        }
        a.sync(at: t(0))
        let b = try rig.mac("B")
        b.sync(at: t(1))
        #expect(try b.config().removedCandidates.isEmpty)
    }
}

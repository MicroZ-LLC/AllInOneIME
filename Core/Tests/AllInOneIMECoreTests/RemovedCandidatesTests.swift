import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// librime as a candidate the user removed meets it: pages of five, numbered 1–5; ↑↓ move the highlight, on to the next
/// page past the last (its first) or the previous past the first (its last); Page Up and Down, - and =, turn the page
/// (the highlight on its first); Space and the digits pick on the page, , and . the highlighted one and their mark, [ and ]
/// its first or last character (rime-ice's `select_character`), ⏎ the letters as typed, the composition the highlighted
/// one. A candidate deleted (`deleteCandidate`: a word of the dictionary never learned) stays where it is, recorded.
final class PagesEngine: PinyinEngine {
    var pages: [String: [String]]
    var input = ""
    var highlighted = 0
    var page = 0
    /// Every key given, in order.
    var keys: [Int32] = []
    /// Every candidate deleted, by its page, its place on it and its text.
    var deleted: [String] = []
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

    func host(_ settings: Settings, engine: PinyinEngine = FakeEngine(), dictionary: Bool = false,
              load: (() -> Config)? = nil) -> FakeHost {
        var services = SessionServices(loadSettings: load ?? { settings.config })
        services.levelOne = { .engine(engine) }
        services.programInstalled = { _ in true }
        services.removeCandidate = { settings.removed.append($0) }
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

    /// One of the user's English words removed: out of their words, added or learned (by its letters), and on the list.
    @Test func anEnglishWordOfTheUsersGoesFromTheirWords() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data(#"{"typeOut": true, "englishWords": ["BEDROCK", "frobnicate"], "addedEnglishWords": ["BEDROCK"], "futureKey": [1]}"#.utf8)
            .write(to: url)
        let writer = EnglishWords.Writer()
        writer.remove("Bedrock", at: url)
        writer.flush()
        let after = try object(url)
        #expect(after["englishWords"] as? [String] == ["frobnicate"])
        #expect(after["addedEnglishWords"] == nil, "emptied: gone, as the config writes none")
        #expect(after["removedCandidates"] as? [String] == ["Bedrock"])
        #expect(after["typeOut"] as? Bool == true && after["futureKey"] as? [Int] == [1])
        // The last word: its list goes too.
        writer.remove("frobnicate", at: url)
        writer.flush()
        let last = try object(url)
        #expect(last["englishWords"] == nil && last["removedCandidates"] as? [String] == ["Bedrock", "frobnicate"])
        // In memory, as Settings would do it.
        var config = Config.default
        config.englishWords = ["Bedrock", "zorblax"]
        config.addedEnglishWords = ["Bedrock"]
        RemovedCandidates.remove("bedrock", from: &config)
        #expect(config.englishWords == ["zorblax"] && config.addedEnglishWords.isEmpty && config.removedCandidates == ["bedrock"])
        RemovedCandidates.remove("鸡虎", from: &config)
        #expect(config.englishWords == ["zorblax"] && config.removedCandidates == ["bedrock", "鸡虎"])
    }

    /// Removed and learned at once, in either order: written in order; one on the list is never learned, also by a write
    /// of its own (another field, another Mac's list).
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
        #expect(config.englishWords == ["Bedrock", "quuxify"], "\(config.englishWords)")
        #expect(config.removedCandidates == ["Zorblax", "wibble"])
        #expect(try !EnglishWords.learn("ZORBLAX", at: url))
        #expect(try Config.load(from: url).englishWords == ["Bedrock", "quuxify"])
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

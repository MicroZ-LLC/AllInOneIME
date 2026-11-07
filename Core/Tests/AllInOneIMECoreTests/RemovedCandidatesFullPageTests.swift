import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// librime with AllInOneIME's filter of the candidates removed, as level one meets it: it is given the list
/// (`setRemovedCandidates`), leaves them out itself and lays out anew what is being typed at once, from its first page
/// (the filter does on the list's change); its pages are laid out from what is left, five each. A delete is recorded
/// with the list it was given before it (librime's `delete_candidate` works on the page it is on). The rest as
/// `PagesEngine`: ↑↓ move the highlight, on to the next page past the last row, Page Up and Down turn the page, Space and
/// the digits pick on the page.
final class FilteringEngine: PinyinEngine {
    let lists: [String: [String]]
    var input = ""
    var highlighted = 0
    var page = 0
    /// What it was told, in order: "delete <text>" (librime's delete, on the page it is on), "list <texts>" (the list).
    var told: [String] = []
    private(set) var removed: [String] = []
    private var commit: String?

    init(_ lists: [String: [String]]) { self.lists = lists }

    var all: [String] { (lists[input] ?? [input]).filter { !removed.contains($0) } }
    var onPage: [String] { Array(all.dropFirst(page * 5).prefix(5)) }
    var lastPage: Int { max(0, (all.count - 1) / 5) }

    func setRemovedCandidates(_ texts: [String]) {
        removed = texts
        told.append("list " + texts.joined(separator: " "))
        if !input.isEmpty { (page, highlighted) = (0, 0) }  // laid out anew at once, from the first page
    }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        guard mask & RimeKey.releaseMask == 0 else { return !input.isEmpty }
        switch keycode {
        case 0x61...0x7A:
            input.append(Character(Unicode.Scalar(UInt8(keycode))))
            (highlighted, page) = (0, 0)
            return true
        case _ where input.isEmpty: return false
        case RimeKey.space: pick(highlighted)
        case 0x31...0x35: pick(Int(keycode - 0x31))
        case RimeKey.escape: input = ""
        case RimeKey.down:
            if highlighted < onPage.count - 1 { highlighted += 1 } else if page < lastPage { (page, highlighted) = (page + 1, 0) }
        case RimeKey.up:
            if highlighted > 0 { highlighted -= 1 } else if page > 0 { page -= 1; highlighted = onPage.count - 1 }
        case RimeKey.pageDown, 0x3D: if page < lastPage { (page, highlighted) = (page + 1, 0) }
        case RimeKey.pageUp, 0x2D: if page > 0 { (page, highlighted) = (page - 1, 0) }
        default: break
        }
        return true
    }

    private func pick(_ i: Int) {
        guard onPage.indices.contains(i) else { return }
        commit = onPage[i]
        input = ""
        (highlighted, page) = (0, 0)
    }

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
        told.append("delete " + onPage[index])
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

/// Candidates removed (a right-click, ⌃⌦) where librime leaves them out itself (`FilteringEngine`, AllInOneIME's Lua
/// filter): the page they were on stays full, the ones after them moved up, from the pages after too; every page after
/// it, and back, has each candidate once, none skipped, none removed; the highlight stays on the removed one's row, on
/// what moved up into it, else (the end of the list) on the one before. Where librime doesn't (`PagesEngine`, the Swift
/// fallback: the user's own patch file, Windows), they are left out of librime's pages as before.
struct RemovedCandidatesFullPageTests {
    /// "niubi" as rime-ice gives it: three pages, the last of three.
    static let niubi = ["牛逼", "👍", "牛屄", "牛鼻", "纽币", "牛", "🐮", "扭", "纽", "妞", "钮", "拗", "忸"]
    /// Three pages, the last of one.
    static let fangfa = ["方法", "访法", "放", "房", "防", "方", "仿", "芳", "访", "妨", "牥"]

    let pageDown = KeyEvent(keyCode: VirtualKey.pageDown, characters: "\u{F72D}")
    let pageUp = KeyEvent(keyCode: VirtualKey.pageUp, characters: "\u{F72C}")

    func filtering(_ removed: [String] = []) -> (Composer, FilteringEngine) {
        let engine = FilteringEngine(["niubi": Self.niubi, "fangfa": Self.fangfa])
        let c = Composer(engine: engine, actionKey: .enter)
        c.removedCandidates = removed
        return (c, engine)
    }

    func type(_ s: String, _ c: Composer) { for ch in s { _ = c.handleKeyDown(k(String(ch))) } }
    func press(_ key: KeyEvent, _ c: Composer, times: Int = 1) { for _ in 0..<times { _ = c.handleKeyDown(key) } }
    func rows(_ c: Composer) -> [String] { c.engineState.candidates.map(\.text) }
    func labels(_ c: Composer) -> [String] { c.engineState.candidates.map(\.label) }
    func highlighted(_ c: Composer) -> String? {
        let rows = rows(c)
        return rows.indices.contains(c.engineState.highlighted) ? rows[c.engineState.highlighted] : nil
    }
    func removals(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .candidateRemoved(text) = $0 { return text } else { return nil } }
    }

    /// The pages for what is being typed, from the one shown on to the last (Page Down), then back to the first (Page Up).
    func pagesOnAndBack(_ c: Composer) -> (on: [[String]], back: [[String]]) {
        var on = [rows(c)]
        while !c.engineState.isLastPage {
            let page = c.engineState.pageNumber
            press(pageDown, c)
            guard c.engineState.pageNumber > page else { break }
            on.append(rows(c))
        }
        var back = [rows(c)]
        while c.engineState.pageNumber > 0 {
            let page = c.engineState.pageNumber
            press(pageUp, c)
            guard c.engineState.pageNumber < page else { break }
            back.append(rows(c))
        }
        return (on, back)
    }

    /// `niubi` with two of its first page removed: the page shows five, the next ones moved up; librime deleted each on
    /// the page it was on, then was given the list with it. Its pages on and back: each candidate left once, in order.
    @Test func twoRemovedOfAPageLeaveItFull() {
        let (c, engine) = filtering()
        type("niubi", c)
        #expect(rows(c) == ["牛逼", "👍", "牛屄", "牛鼻", "纽币"])
        #expect(removals(c.deleteCandidate(index: 1)) == ["👍"])
        #expect(rows(c) == ["牛逼", "牛屄", "牛鼻", "纽币", "牛"] && labels(c) == ["1", "2", "3", "4", "5"], "\(rows(c))")
        #expect(removals(c.deleteCandidate(index: 1)) == ["牛屄"])
        #expect(rows(c) == ["牛逼", "牛鼻", "纽币", "牛", "🐮"] && labels(c) == ["1", "2", "3", "4", "5"], "\(rows(c))")
        #expect(engine.told == ["list ", "delete 👍", "list 👍", "delete 牛屄", "list 👍 牛屄"], "\(engine.told)")
        #expect(c.removedCandidates == ["👍", "牛屄"] && c.engineState.isComposing && engine.input == "niubi")

        let left = Self.niubi.filter { $0 != "👍" && $0 != "牛屄" }
        let pages = pagesOnAndBack(c)
        #expect(pages.on == [Array(left[0..<5]), Array(left[5..<10]), Array(left[10...])], "\(pages.on)")
        #expect(pages.back == pages.on.reversed(), "\(pages.back)")
        // Typed again: the same pages.
        press(escKey, c)
        type("niubi", c)
        #expect(pagesOnAndBack(c).on == pages.on)
    }

    /// The same where librime doesn't leave them out (`PagesEngine`, no filter): left out of its pages of five, the page
    /// shows three; its pages on and back have each of the others once all the same.
    @Test func withoutTheFilterTheyAreLeftOutOfLibrimesPages() {
        let engine = PagesEngine(["niubi": Self.niubi])
        let c = Composer(engine: engine, actionKey: .enter)
        type("niubi", c)
        #expect(removals(c.deleteCandidate(index: 1)) == ["👍"] && removals(c.deleteCandidate(index: 1)) == ["牛屄"])
        #expect(rows(c) == ["牛逼", "牛鼻", "纽币"] && labels(c) == ["1", "2", "3"], "\(rows(c))")
        #expect(engine.deleted == ["👍", "牛屄"])
        let pages = pagesOnAndBack(c)
        #expect(pages.on == [["牛逼", "牛鼻", "纽币"], ["牛", "🐮", "扭", "纽", "妞"], ["钮", "拗", "忸"]], "\(pages.on)")
        #expect(pages.back == pages.on.reversed())
    }

    /// A row removed on the second page: librime deletes the one on that page (not the first page's row there), the user
    /// stays on it, full, the first of the third moved up; the pages before and after as they should be.
    @Test func oneRemovedOnTheSecondPageLeavesItFull() {
        let (c, engine) = filtering()
        type("niubi", c)
        press(pageDown, c)
        #expect(rows(c) == ["牛", "🐮", "扭", "纽", "妞"])
        #expect(removals(c.deleteCandidate(index: 2)) == ["扭"])
        #expect(engine.told.suffix(2) == ["delete 扭", "list 扭"], "\(engine.told)")
        #expect(c.engineState.pageNumber == 1 && rows(c) == ["牛", "🐮", "纽", "妞", "钮"], "\(c.engineState.pageNumber): \(rows(c))")
        let pages = pagesOnAndBack(c)
        #expect(pages.on == [["牛", "🐮", "纽", "妞", "钮"], ["拗", "忸"]], "\(pages.on)")
        #expect(pages.back == [["拗", "忸"], ["牛", "🐮", "纽", "妞", "钮"], ["牛逼", "👍", "牛屄", "牛鼻", "纽币"]], "\(pages.back)")
    }

    /// ⌃⌦ on the highlighted one: the highlight stays on its row, on what moved up into it, from the page after too at the
    /// end of a page; at the end of the list, nothing moved up: on the one before. Space puts in the one highlighted.
    @Test func theHighlightStaysOnTheRemovedOnesRow() {
        func removingHighlighted(downs: Int, pages: Int = 0) -> Composer {
            let (c, _) = filtering()
            type("niubi", c)
            press(pageDown, c, times: pages)
            press(downKey, c, times: downs)
            let response = c.handleKeyDown(DeleteKeys.controlForwardDelete)
            #expect(response.handled && removals(response.effects).count == 1, "\(response.effects)")
            return c
        }
        // In the middle of a page.
        let middle = removingHighlighted(downs: 2)
        #expect(rows(middle) == ["牛逼", "👍", "牛鼻", "纽币", "牛"] && highlighted(middle) == "牛鼻", "\(String(describing: highlighted(middle)))")
        // At the end of the first page: the second page's first moved up into it.
        let end = removingHighlighted(downs: 4)
        #expect(rows(end) == ["牛逼", "👍", "牛屄", "牛鼻", "牛"] && end.engineState.highlighted == 4, "\(rows(end)) \(end.engineState.highlighted)")
        #expect(commits(end.handleKeyDown(KeyEvent(keyCode: VirtualKey.space, characters: " "))) == ["牛"])
        // At the end of the second page: the third's first.
        let second = removingHighlighted(downs: 4, pages: 1)
        #expect(second.engineState.pageNumber == 1 && rows(second) == ["牛", "🐮", "扭", "纽", "钮"] && highlighted(second) == "钮",
                "\(rows(second)) \(String(describing: highlighted(second)))")
        // In the middle of the last page.
        let last = removingHighlighted(downs: 1, pages: 2)
        #expect(last.engineState.pageNumber == 2 && rows(last) == ["钮", "忸"] && highlighted(last) == "忸", "\(rows(last))")
        // At the end of the list: the one before.
        let end2 = removingHighlighted(downs: 2, pages: 2)
        #expect(end2.engineState.pageNumber == 2 && rows(end2) == ["钮", "拗"] && highlighted(end2) == "拗",
                "\(rows(end2)) \(String(describing: highlighted(end2)))")
    }

    /// A right-click on another row: the highlight stays on the candidate it was on, which moved up a row.
    @Test func anotherRowRemovedLeavesTheHighlightOnItsCandidate() {
        let (c, _) = filtering()
        type("niubi", c)
        press(downKey, c, times: 2)
        #expect(highlighted(c) == "牛屄")
        #expect(removals(c.deleteCandidate(index: 0)) == ["牛逼"])
        #expect(rows(c) == ["👍", "牛屄", "牛鼻", "纽币", "牛"] && highlighted(c) == "牛屄", "\(String(describing: highlighted(c)))")
        #expect(removals(c.deleteCandidate(index: 4)) == ["牛"])
        #expect(rows(c) == ["👍", "牛屄", "牛鼻", "纽币", "🐮"] && highlighted(c) == "牛屄", "\(String(describing: highlighted(c)))")
    }

    /// The only one on the last page removed: no page there any more, the user on the one before, the highlight on its
    /// last row.
    @Test func theOnlyOneOnTheLastPageRemovedGoesBackAPage() {
        let (c, _) = filtering()
        type("fangfa", c)
        press(pageDown, c, times: 2)
        #expect(rows(c) == ["牥"] && c.engineState.isLastPage)
        #expect(removals(c.deleteCandidate(index: 0)) == ["牥"])
        #expect(c.engineState.pageNumber == 1 && rows(c) == ["方", "仿", "芳", "访", "妨"] && highlighted(c) == "妨",
                "\(c.engineState.pageNumber): \(rows(c)) \(String(describing: highlighted(c)))")
        #expect(c.engineState.isLastPage)
    }

    /// An English word of the user's removed: by its letters (written another way, it isn't offered either), the page
    /// full of librime's; one of librime's removed beside it: its page full, the word still on it.
    @Test func anEnglishWordRemovedByItsLetters() {
        let engine = FilteringEngine(["niubi": Self.niubi])
        let mixed = EnglishWordsEngine(base: engine, dictionary: EnglishDictionary([]), words: ["Niubi"])
        let c = Composer(engine: mixed, actionKey: .enter)
        type("niubi", c)
        #expect(rows(c) == ["牛逼", "Niubi", "👍", "牛屄", "牛鼻", "纽币"], "\(rows(c))")
        #expect(removals(c.deleteCandidate(index: 3)) == ["牛屄"])
        #expect(rows(c) == ["牛逼", "Niubi", "👍", "牛鼻", "纽币", "牛"], "the word and librime's five: \(rows(c))")
        #expect(removals(c.deleteCandidate(index: 1)) == ["Niubi"])
        #expect(rows(c) == ["牛逼", "👍", "牛鼻", "纽币", "牛"] && mixed.removedKeys == ["niubi"], "\(rows(c))")
        press(escKey, c)
        mixed.words = ["niubi", "NIUBI"]
        type("niubi", c)
        #expect(rows(c) == ["牛逼", "👍", "牛鼻", "纽币", "牛"], "by its letters: \(rows(c))")
    }

    // MARK: The patch

    static let schema = """
    schema:
      schema_id: rime_ice
    switches:
      - name: ascii_mode
      - name: traditionalization
        states: [ 简, 繁 ]
    speller:
      algebra:
        - abbrev/^([a-z]).+$/$1/
    """

    /// The filter is in the patch (`rime_ice.custom.yaml`) when the shared data's Lua has the script (the app's, linked
    /// into the pack), last, after Traditional characters' lines (it sees the text as shown); with no fuzzy pinyin or
    /// characters, a patch of the filter alone; without the script (Windows, an app without it), none, as before. The
    /// file stays the app's (its first line), and the user's own is never written over.
    @Test func thePatchHasTheFilterLastWhereTheScriptIs() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("removed-filter-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        let shared = dir.appendingPathComponent("pack"), user = dir.appendingPathComponent("user")
        try fm.createDirectory(at: shared.appendingPathComponent("lua"), withIntermediateDirectories: true)
        let schema = shared.appendingPathComponent("rime_ice.schema.yaml")
        try Self.schema.write(to: schema, atomically: true, encoding: .utf8)
        let file = user.appendingPathComponent(FuzzyPinyin.fileName)
        func patch() throws -> String { try String(contentsOf: file, encoding: .utf8) }
        let filter = "  engine/filters/+:\n    - lua_filter@*allinoneime_removed\n"

        // No script: no patch for nothing, none of the filter with something.
        #expect(try FuzzyPinyin.apply([], schema: schema, userDir: user) == .unchanged && !fm.fileExists(atPath: file.path))
        #expect(try FuzzyPinyin.apply([], characters: .taiwan, schema: schema, userDir: user) == .written)
        #expect(try !patch().contains("allinoneime_removed"))
        #expect(try FuzzyPinyin.apply([], schema: schema, userDir: user) == .removed)

        // The script beside the schema, as the app links its Lua into the pack.
        try Data("return function(input, env) end".utf8).write(to: shared.appendingPathComponent("lua/allinoneime_removed.lua"))
        #expect(try FuzzyPinyin.apply([], schema: schema, userDir: user) == .written)
        let alone = try patch()
        #expect(alone.hasPrefix(FuzzyPinyin.marker + "\n") && alone.hasSuffix("patch:\n" + filter), "\(alone)")
        #expect(try FuzzyPinyin.apply([], schema: schema, userDir: user) == .unchanged)
        // Traditional and fuzzy pinyin: the filter after the Traditional lines, last.
        #expect(try FuzzyPinyin.apply(["n-l"], characters: .taiwan, schema: schema, userDir: user) == .written)
        let text = try patch()
        let traditional = try #require(text.range(of: "traditionalize/opencc_config: s2twp.json"))
        let filterAt = try #require(text.range(of: filter))
        #expect(text.hasPrefix(FuzzyPinyin.marker + "\n") && text.contains("speller/algebra:") && text.contains("switches/@1/reset: 1"))
        #expect(traditional.upperBound < filterAt.lowerBound && filterAt.upperBound == text.endIndex, "\(text)")
        #expect(text.components(separatedBy: "allinoneime_removed").count == 2, "once: \(text)")
        // The script gone (an older app's Lua): the patch without it.
        try fm.removeItem(at: shared.appendingPathComponent("lua/allinoneime_removed.lua"))
        #expect(try FuzzyPinyin.apply(["n-l"], characters: .taiwan, schema: schema, userDir: user) == .written)
        #expect(try !patch().contains("allinoneime_removed"))
        // The user's own file: left as it is, the script there or not.
        try Data("return function(input, env) end".utf8).write(to: shared.appendingPathComponent("lua/allinoneime_removed.lua"))
        try "patch:\n  menu/page_size: 9\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(try FuzzyPinyin.apply([], schema: schema, userDir: user) == .unchanged)
        #expect(try patch() == "patch:\n  menu/page_size: 9\n")
    }
}

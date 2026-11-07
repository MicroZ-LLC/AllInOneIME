import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime

/// A candidate a filter of rime-ice's made from a word, removed, on the real librime and rime-ice set up as the app sets
/// them up (`RemovedCandidatesFilterRimeTests`): its emoji filter puts 👏 after 鼓掌, 🔑 after 钥匙 (鑰匙 in Traditional
/// characters), a radical after its name (讠 after 言部), and librime's delete of one would forget what it learned of
/// the word. Removed, it is only left out: the word stays where the user's picks put it, and the page stays full, the
/// highlight on the removed one's row. A word removed (纽币, 紐幣 in Traditional) is still forgotten, in Simplified too.
/// Without AllInOneIME's filter (the user's own patch), an emoji is not deleted either. In a process of its own each
/// (`RimeWorker`): librime starts once per process, and these start it on shared data and a user folder of their own.
struct RemovedDerivedCandidatesRimeTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rime-derived-\(UUID().uuidString)")

    @Test(.enabled(if: RemovedCandidatesFilterRimeTests.runs, "no rime-ice data in ThirdParty (make deps)"))
    func anEmojiOrARadicalRemovedLeavesItsWordAsItWas() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("removed-derived", root: root)
    }

    @Test(.enabled(if: RemovedCandidatesFilterRimeTests.runs && FileManager.default.fileExists(atPath: TraditionalChineseRimeTests.openCC.path)
                   || RimeWorker.required, "no OpenCC data in ThirdParty/opencc (make deps)"))
    func inTraditionalCharactersTheWordItselfIsStillForgotten() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("removed-derived-traditional", root: root)
        try RimeWorker.run("removed-derived-simplified-after", root: root)
    }

    @Test(.enabled(if: RemovedCandidatesFilterRimeTests.runs, "no rime-ice data in ThirdParty (make deps)"))
    func withoutTheFilterAnEmojiRemovedLeavesItsWordToo() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("removed-derived-without-filter", root: root)
    }

    typealias Filter = RemovedCandidatesFilterRimeTests

    /// The script as the app has it.
    static var script: String { get throws { try String(contentsOf: Filter.script, encoding: .utf8) } }

    /// `word` (on the pages of `letters`, at `place`, with `derived` after it, a filter's of it) picked three times
    /// comes first, `derived` after it. ⌃⌦ on `derived[0]` (↓ onto it) or a right-click on it (`highlighted: false`)
    /// removes it, and only it: the page full, laid out by librime, the one after it moved up into its row, the highlight
    /// there (or still on the word); gone from every page, for good. For a composer without the list, the pages are as
    /// they were with the word learned: librime kept what it learned of the word. The pages learned.
    @discardableResult
    static func removingDerived(_ derived: [String], of word: String, at place: Int, for letters: String,
                                highlighted: Bool = true) throws -> [[String]] {
        let before = Paging.pages(letters, try Filter.levelOne().0, count: 4)
        try #require(Array(before.joined().dropFirst(place).prefix(1 + derived.count)) == [word] + derived, "\(letters): \(before)")
        try Paging.learn(word, for: letters, try Filter.levelOne().0, times: 3)
        let learned = Paging.pages(letters, try Filter.levelOne().0, count: 4)
        try #require(Array(learned[0].prefix(1 + derived.count)) == [word] + derived, "\(letters) learned: \(learned)")
        let all = Array(learned.joined()), left = all.filter { $0 != derived[0] }

        let (c, engine) = try Filter.levelOne()
        Paging.type(letters, c)
        if highlighted {
            Paging.press(Paging.arrowDown, c)
            try #require(Paging.highlighted(c) == derived[0])
            let response = c.handleKeyDown(Paging.controlForwardDelete)
            #expect(response.handled && Paging.removals(response.effects) == [derived[0]], "\(response.effects)")
        } else {
            #expect(Paging.removals(c.deleteCandidate(index: 1)) == [derived[0]])
        }
        #expect(Paging.rows(c) == Array(left.prefix(5)) && engine.base.snapshot().candidates.map(\.text) == Array(left.prefix(5)),
                "\(letters): \(Paging.rows(c))")
        #expect(Paging.highlighted(c) == (highlighted ? left[1] : word) && Paging.numberedAsShown(c), "\(Paging.highlighted(c) ?? "")")
        #expect(c.removedCandidates == [derived[0]])
        let on = Array(Paging.onAndBack(c, count: 4).on.joined())
        #expect(Array(on.prefix(left.count)) == left, "\(letters): \(on)")
        Paging.escape(c)
        let again = Paging.pages(letters, c)
        #expect(again.first?.first == word && !again.joined().contains(derived[0]) && again.dropLast().allSatisfy { $0.count == 5 },
                "\(letters) again: \(again)")
        // librime: the word where the picks put it, the one removed where it was (the list leaves it out).
        let kept = Paging.pages(letters, try Filter.levelOne().0, count: 4)
        #expect(kept == learned, "\(letters): librime kept what it learned of \(word): \(kept)")
        return learned
    }

    /// `word` (on the pages of `letters`, not first; at `place` if given) picked `times` times moves up; removed, librime
    /// forgets it: for a composer without the list, the pages are as they were, the word back where the dictionary puts it.
    static func removingAWordForgetsIt(_ word: String, at place: Int? = nil, for letters: String, times: Int) throws {
        let before = Array(Paging.pages(letters, try Filter.levelOne().0, count: 4).joined())
        let found = try #require(before.firstIndex(of: word), "\(letters): \(before)")
        try #require(found > 0 && found == place ?? found, "\(letters): \(before)")
        try Paging.learn(word, for: letters, try Filter.levelOne().0, times: times)
        let (c, _) = try Filter.levelOne()
        Paging.type(letters, c)
        let row = try #require(Paging.rows(c).firstIndex(of: word), "\(letters): \(Paging.rows(c))")
        try #require(row < found, "moved up: \(Paging.rows(c))")
        #expect(Paging.removals(c.deleteCandidate(index: row)) == [word] && Paging.rows(c).count == 5, "\(Paging.rows(c))")
        Paging.escape(c)
        let after = Array(Paging.pages(letters, try Filter.levelOne().0, count: 4).joined())
        #expect(after.firstIndex(of: word) == found && after == before, "\(word) forgotten: \(after)")
    }

    static let scenarios: [String: @Sendable (URL) throws -> Void] = [
        "removed-derived": { root in
            let pack = try Filter.pack(root, code: "rime-lua", script: script)
            #expect(try Filter.start(pack, user: root.appendingPathComponent("Rime")) == .written)
            // The emoji (the owner's case): ⌃⌦ on it.
            try removingDerived(["👏"], of: "鼓掌", at: 1, for: "guzhang")
            // A radical after its name (rime-ice's others.txt, the emoji filter's too): a right-click on it.
            try removingDerived(["讠", "訁"], of: "言部", at: 3, for: "yanbu", highlighted: false)
            // An emoji whose word was removed before, picked since (which librime learns as the word's): its word as it
            // was too, though nothing before it on the page is of the word now.
            let yaoshi = Paging.pages("yaoshi", try Filter.levelOne().0, count: 4)
            try #require(Array(yaoshi[0].prefix(4)) == ["要是", "钥匙", "🔑", "🗝"], "\(yaoshi)")
            let (key, _) = try Filter.levelOne()
            Paging.type("yaoshi", key)
            #expect(Paging.removals(key.deleteCandidate(index: 1)) == ["钥匙"])
            Paging.escape(key)
            try Paging.learn("🔑", for: "yaoshi", key, times: 3)
            let picked = Paging.pages("yaoshi", try Filter.levelOne().0, count: 4)
            try #require(Array(picked[0].prefix(3)) == ["钥匙", "🔑", "🗝"], "the word learned: \(picked)")
            Paging.type("yaoshi", key)
            try #require(Array(Paging.rows(key).prefix(2)) == ["🔑", "🗝"], "\(Paging.rows(key))")
            #expect(Paging.removals(key.deleteCandidate(index: 0)) == ["🔑"] && Paging.rows(key).first == "🗝" && Paging.rows(key).count == 5)
            Paging.escape(key)
            #expect(Paging.pages("yaoshi", try Filter.levelOne().0, count: 4) == picked, "librime kept what it learned of 钥匙")
            // A word of the dictionary removed: forgotten.
            try removingAWordForgetsIt("减淡", for: "jiandan", times: 2)
        },

        "removed-derived-traditional": { root in
            let pack = try Filter.pack(root, code: "rime-lua", script: script)
            #expect(try Filter.start(pack, user: root.appendingPathComponent("Rime"), characters: .taiwan) == .written)
            // 鑰匙, Traditional for 钥匙, and its emoji: the three of the word 钥匙, none of them its text.
            try removingDerived(["🔑", "🗝"], of: "鑰匙", at: 1, for: "yaoshi")
            // 紐幣 is the word 纽币 in Traditional characters: removed, librime forgets 纽币.
            try removingAWordForgetsIt("紐幣", at: 4, for: "niubi", times: 3)
        },
        // The same user folder in Simplified characters: 纽币 where the dictionary puts it, 钥匙 where the picks put it.
        "removed-derived-simplified-after": { root in
            let pack = try Filter.pack(root, code: "rime-lua-simplified", script: script)
            #expect(try Filter.start(pack, user: root.appendingPathComponent("Rime")) == .written)
            let niubi = Array(Paging.pages("niubi", try Filter.levelOne().0, count: 4).joined())
            #expect(niubi.firstIndex(of: "纽币") == 4, "\(niubi.prefix(10))")
            let (c, _) = try Filter.levelOne(["🔑", "紐幣"])
            let yaoshi = Paging.pages("yaoshi", c, count: 4)
            #expect(Array(yaoshi[0].prefix(3)) == ["钥匙", "🗝", "要是"] && !yaoshi.joined().contains("🔑"), "\(yaoshi)")
            #expect(Array(Paging.pages("niubi", c, count: 4).joined()) == niubi, "a Simplified text isn't the Traditional one removed")
        },

        // No filter of AllInOneIME's in the schema (the user's own patch file): level one leaves the emoji out, and librime
        // isn't asked to delete it.
        "removed-derived-without-filter": { root in
            let pack = try Filter.pack(root, code: "rime-lua-old", script: nil)
            #expect(try Filter.start(pack, user: root.appendingPathComponent("Rime")) == .unchanged)
            try Paging.learn("鼓掌", for: "guzhang", try Filter.levelOne().0, times: 3)
            let learned = Paging.pages("guzhang", try Filter.levelOne().0, count: 4)
            try #require(Array(learned[0].prefix(3)) == ["鼓掌", "👏", "故障"], "learned: \(learned)")
            let (c, _) = try Filter.levelOne()
            Paging.type("guzhang", c)
            #expect(Paging.removals(c.deleteCandidate(index: 1)) == ["👏"])
            #expect(Paging.rows(c).first == "鼓掌" && !Paging.rows(c).contains("👏"), "\(Paging.rows(c))")
            Paging.escape(c)
            #expect(Paging.pages("guzhang", try Filter.levelOne().0, count: 4) == learned, "librime kept what it learned of 鼓掌")
        },
    ]
}

extension Paging {
    /// `word` picked `times` times for `letters`, where it is on the pages: librime learns it.
    static func learn(_ word: String, for letters: String, _ c: Composer, times: Int) throws {
        for _ in 0..<times {
            type(letters, c)
            var put: [String] = []
            for _ in 0..<8 where put.isEmpty {
                if let row = rows(c).firstIndex(of: word) { put = putIn(c.choose(index: row)) } else { press(pageDown, c) }
            }
            try #require(put == [word] && !c.engineState.isComposing, "\(word) for \(letters): \(put)")
        }
    }
}

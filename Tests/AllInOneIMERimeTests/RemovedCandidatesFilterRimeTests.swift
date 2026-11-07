import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime

/// AllInOneIME's filter of the candidates removed (Resources/rime/lua/allinoneime_removed.lua) on the real librime and
/// rime-ice, set up as the app sets it up: the pack's `lua/` a link to the app's scripts, rime-ice's and this one
/// (`LanguagePackStore.linkCode`), the patch the settings write (`FuzzyPinyin.apply`) with the filter last, and a full
/// check when it changed (`RimeStartup`); level one's engine an `EnglishWordsEngine` on a session, given the list. A
/// page with candidates removed stays full, the ones after them moved up, every page after it and back right; in
/// Traditional characters too; the highlight on the removed one's row. In a process of its own each (`RimeWorker`):
/// librime starts once per process, and these start it on shared data and a user folder of their own.
struct RemovedCandidatesFilterRimeTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rime-removed-\(UUID().uuidString)")
    static var runs: Bool { RimeWorker.scenario == nil && (RimeWorker.dataAvailable || RimeWorker.required) }

    @Test(.enabled(if: runs, "no rime-ice data in ThirdParty (make deps)"))
    func pagesStayFullWhateverIsRemoved() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("removed-filter-pages", root: root)
    }

    @Test(.enabled(if: runs, "no rime-ice data in ThirdParty (make deps)"))
    func theHighlightStaysOnTheRemovedOnesRow() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("removed-filter-highlight", root: root)
    }

    @Test(.enabled(if: runs && FileManager.default.fileExists(atPath: TraditionalChineseRimeTests.openCC.path) || RimeWorker.required,
                   "no OpenCC data in ThirdParty/opencc (make deps)"))
    func inTraditionalCharactersByTheTextAsShown() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("removed-filter-traditional", root: root)
    }

    /// The owner's case: an app without the filter deployed rime-ice in the user folder; the update's first start writes
    /// the patch with it and deploys again; a later script is used as it is, with no deploy.
    @Test(.enabled(if: runs, "no rime-ice data in ThirdParty (make deps)"))
    func anUpdateBringsTheFilterToAnExistingUser() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("removed-filter-before-update", root: root)
        try RimeWorker.run("removed-filter-after-update", root: root)
        try RimeWorker.run("removed-filter-script-changed", root: root)
    }

    // MARK: Set up as the app

    static let script = RimeFixture.root.appendingPathComponent("Resources/rime/lua/allinoneime_removed.lua")

    /// The Chinese pack in `root` (rime-ice's data, linked) with its `lua/` linked to the app's scripts in `code`: rime-ice's,
    /// with `script` beside them (the app's own filter, as the Makefile puts it in SharedSupport/rime-lua) unless nil.
    @discardableResult
    static func pack(_ root: URL, code name: String, script: String?) throws -> URL {
        let fm = FileManager.default
        let store = LanguagePackStore(directory: root.appendingPathComponent("LanguagePacks"))
        let pack = store.folder(.chinesePinyin)
        if !fm.fileExists(atPath: pack.path) {
            try fm.createDirectory(at: pack, withIntermediateDirectories: true)
            for item in try fm.contentsOfDirectory(atPath: RimeFixture.sharedData.path) where item != "lua" {
                try fm.createSymbolicLink(at: pack.appendingPathComponent(item),
                                          withDestinationURL: RimeFixture.sharedData.appendingPathComponent(item))
            }
        }
        let code = root.appendingPathComponent(name)
        try fm.copyItem(at: RimeFixture.sharedData.appendingPathComponent("lua"), to: code)
        if let script { try Data(script.utf8).write(to: code.appendingPathComponent(RemovedCandidates.luaFilter + ".lua")) }
        try store.linkCode(.chinesePinyin, from: code)
        return pack
    }

    /// librime started as the app starts it on `pack` (`RimeStartup`): the patch written for `characters`, a full check
    /// when it changed. What the patch's writing came to.
    @discardableResult
    static func start(_ pack: URL, user: URL, characters: ChineseCharacters = .simplified) throws -> FuzzyPinyin.Outcome {
        let outcome = try FuzzyPinyin.apply([], characters: characters, schema: pack.appendingPathComponent("rime_ice.schema.yaml"),
                                            userDir: user)
        try RimeService.shared.start(sharedDataDir: pack, userDataDir: user, logDir: nil,
                                     fullCheck: outcome == .written || outcome == .removed,
                                     openCCDir: TraditionalChineseRimeTests.openCC)
        try #require(RimeService.shared.waitUntilReady(timeout: 120))
        return outcome
    }

    /// Level one as a field's session has it: librime's session under English words, given the list.
    static func levelOne(_ removed: [String] = [], words: [String] = []) throws -> (Composer, EnglishWordsEngine) {
        let dictionary = try #require(RimeService.shared.englishDictionary)
        let engine = EnglishWordsEngine(base: try #require(RimeService.shared.makeSession()), dictionary: dictionary, words: words,
                                        removedCandidates: removed)
        return (Composer(engine: engine, actionKey: .enter), engine)
    }

    static let patchFilter = "  engine/filters/+:\n    - lua_filter@*allinoneime_removed\n"

    // MARK: Scenarios

    static let scenarios: [String: @Sendable (URL) throws -> Void] = [
        "removed-filter-pages": { root in
            let pack = try pack(root, code: "rime-lua", script: String(contentsOf: script, encoding: .utf8))
            let user = root.appendingPathComponent("Rime")
            #expect(try start(pack, user: user) == .written)
            let patch = try String(contentsOf: user.appendingPathComponent(FuzzyPinyin.fileName), encoding: .utf8)
            #expect(patch.hasPrefix(FuzzyPinyin.marker) && patch.hasSuffix(patchFilter), "\(patch)")

            // niubi, the owner's case: two of its first page removed, the page shows five, laid out by librime.
            let pages = Paging.pages("niubi", try levelOne().0)
            try #require(pages.count >= 3 && pages[0].count == 5 && pages.dropLast().allSatisfy { $0.count == 5 }, "\(pages)")
            let all = Array(pages.joined())
            let (c, engine) = try levelOne()
            Paging.type("niubi", c)
            #expect(Paging.rows(c) == pages[0])
            #expect(Paging.removals(c.deleteCandidate(index: 1)) == [all[1]])
            #expect(Paging.rows(c) == Array(all.filter { $0 != all[1] }.prefix(5)), "\(Paging.rows(c))")
            #expect(Paging.removals(c.deleteCandidate(index: 1)) == [all[2]])
            let left = all.filter { $0 != all[1] && $0 != all[2] }
            #expect(Paging.rows(c) == Array(left.prefix(5)) && Paging.numberedAsShown(c), "\(Paging.rows(c))")
            #expect(engine.base.snapshot().candidates.map(\.text) == Array(left.prefix(5)), "librime's own page")
            let list = c.removedCandidates
            #expect(list == [all[1], all[2]])
            // Every page on and back: each left once, none removed, none skipped.
            let after = Paging.onAndBack(c)
            #expect(Array(after.on.joined()) == left && after.on.dropLast().allSatisfy { $0.count == 5 }, "\(after.on)")
            #expect(after.back == after.on.reversed(), "\(after.back)")
            Paging.escape(c)
            Paging.type("niubi", c)
            #expect(Paging.onAndBack(c).on == after.on, "typed again")
            Paging.escape(c)
            // A new session given the list (the app started again, librime deployed again).
            let (later, _) = try levelOne(list)
            Paging.type("niubi", later)
            #expect(Paging.onAndBack(later).on == after.on)
            Paging.escape(later)

            // An engine that never gives librime the list (the property absent): librime leaves nothing out, and level
            // one leaves them out of its pages as without the filter.
            let silent = Silent(try #require(RimeService.shared.makeSession()))
            let fallback = Composer(engine: silent, actionKey: .enter)
            fallback.removedCandidates = list
            Paging.type("niubi", fallback)
            #expect(silent.base.snapshot().candidates.map(\.text) == pages[0], "librime's page as it was")
            #expect(Paging.rows(fallback) == pages[0].filter { !list.contains($0) }, "\(Paging.rows(fallback))")
            Paging.escape(fallback)
            // A property that holds nothing removable (blank lines, a text no candidate has): nothing left out, nothing
            // broken; texts it can't hold (a line break, a NUL) aren't given.
            let odd = try #require(RimeService.shared.makeSession())
            let oddComposer = Composer(engine: odd, actionKey: .enter)
            odd.setRemovedCandidates(["牛逼\n", "a\u{0}b", all[3]])
            var value = [CChar](repeating: 0, count: 64)
            #expect(RimeService.shared.api.pointee.get_property(odd.id, RemovedCandidates.property, &value, 64) != 0)
            #expect(String(cString: value) == all[3], "\(String(cString: value))")
            #expect(Array(Paging.pages("niubi", oddComposer).joined()) == all.filter { $0 != all[3] })
            RimeService.shared.api.pointee.set_property(odd.id, RemovedCandidates.property, "\n\n \n\u{7F}\r\n")
            #expect(Paging.pages("niubi", oddComposer) == pages)

            // An emoji (😄 for kaixin) and librime's own English word (hello: no user dictionary, so its delete lays
            // nothing out anew): the page full at once.
            for (letters, isIt) in [("kaixin", { (s: String) in s.unicodeScalars.first!.properties.isEmojiPresentation }),
                                    ("hello", { (s: String) in s == "hello" })] {
                let before = Array(Paging.pages(letters, try levelOne().0, count: 4).joined())
                let (one, base) = try levelOne()
                Paging.type(letters, one)
                let row = try #require(Paging.rows(one).firstIndex(where: isIt), "\(letters): \(Paging.rows(one))")
                let gone = Paging.rows(one)[row]
                #expect(Paging.removals(one.deleteCandidate(index: row)) == [gone])
                #expect(Paging.rows(one) == Array(before.filter { $0 != gone }.prefix(5)), "\(letters): \(Paging.rows(one))")
                #expect(!base.base.snapshot().candidates.map(\.text).contains(gone))
                let on = Array(Paging.onAndBack(one, count: 4).on.joined())
                #expect(Array(on.prefix(before.count - 1)) == before.filter { $0 != gone }, "\(letters): \(on)")
                Paging.escape(one)
            }

            // One of the user's English words, removed by its letters, beside librime's: librime's page full.
            let (mixed, words) = try levelOne(words: ["Yinyue"])
            Paging.type("yinyue", mixed)
            let shown = Paging.rows(mixed)
            try #require(shown.count == 6 && shown[1] == "Yinyue", "\(shown)")
            let librimes = shown.filter { $0 != "Yinyue" }
            #expect(Paging.removals(mixed.deleteCandidate(index: 3)) == [shown[3]])
            #expect(Paging.rows(mixed).count == 6 && Paging.rows(mixed)[1] == "Yinyue" && !Paging.rows(mixed).contains(shown[3]),
                    "the word and librime's five: \(Paging.rows(mixed))")
            #expect(Paging.removals(mixed.deleteCandidate(index: 1)) == ["Yinyue"])
            #expect(Paging.rows(mixed).count == 5 && Paging.rows(mixed).prefix(3) == librimes.filter { $0 != shown[3] }.prefix(3),
                    "\(Paging.rows(mixed))")
            #expect(words.removedKeys.contains("yinyue"))
            Paging.escape(mixed)
            words.words = ["yinyue", "YINYUE"]
            Paging.type("yinyue", mixed)
            #expect(!Paging.rows(mixed).contains { $0.lowercased() == "yinyue" } && Paging.rows(mixed).count == 5, "\(Paging.rows(mixed))")
            Paging.escape(mixed)

            // A phrase removed that a longer one starts with: gone, the longer one still comes.
            let (phrase, _) = try levelOne()
            Paging.type("guzhang", phrase)
            let row = try #require(Paging.rows(phrase).firstIndex(of: "鼓掌"), "\(Paging.rows(phrase))")
            #expect(Paging.removals(phrase.deleteCandidate(index: row)) == ["鼓掌"] && Paging.rows(phrase).count == 5)
            Paging.escape(phrase)
            let longer = Paging.pages("guzhanghuanying", phrase)
            #expect(longer.first?.first == "鼓掌欢迎" && !longer.joined().contains("鼓掌"), "\(longer.prefix(2))")
            #expect(!Paging.pages("guzhang", phrase).joined().contains("鼓掌"))

            // On the last page: kaixin's last two, the first removed, the other moved up into its row; fangfa's only one
            // on its last page: the page before, the highlight on its last row.
            let kaixin = Paging.pages("kaixin", try levelOne().0, count: 8)
            let (end, _) = try levelOne()
            Paging.type("kaixin", end)
            Paging.press(Paging.pageDown, end, times: kaixin.count - 1)
            try #require(Paging.rows(end) == kaixin.last! && kaixin.last!.count == 2, "\(Paging.rows(end))")
            #expect(Paging.removals(end.deleteCandidate(index: 0)) == [kaixin.last![0]])
            #expect(Paging.rows(end) == [kaixin.last![1]] && Paging.highlighted(end) == kaixin.last![1], "\(Paging.rows(end))")
            Paging.escape(end)
            let fangfa = Paging.pages("fangfa", try levelOne().0, count: 12)
            try #require(fangfa.last?.count == 1, "\(fangfa)")
            let (only, _) = try levelOne()
            Paging.type("fangfa", only)
            Paging.press(Paging.pageDown, only, times: fangfa.count - 1)
            #expect(Paging.removals(only.deleteCandidate(index: 0)) == fangfa.last!)
            #expect(only.engineState.pageNumber == fangfa.count - 2 && Paging.rows(only) == fangfa[fangfa.count - 2]
                    && Paging.highlighted(only) == fangfa[fangfa.count - 2].last, "\(only.engineState.pageNumber): \(Paging.rows(only))")
            #expect(only.engineState.isLastPage)
            Paging.escape(only)
        },

        "removed-filter-highlight": { root in
            let pack = try pack(root, code: "rime-lua", script: String(contentsOf: script, encoding: .utf8))
            #expect(try start(pack, user: root.appendingPathComponent("Rime")) == .written)
            let niubi = Paging.pages("niubi", try levelOne().0)
            try #require(niubi.count >= 3 && niubi[0].count == 5 && niubi[1].count == 5, "\(niubi)")
            let all = Array(niubi.joined())

            /// niubi on `page`, ↓ `downs` times, ⌃⌦ (nothing removed before: a list of its own): the composer, the one
            /// removed.
            func removingHighlighted(downs: Int, page: Int = 0) throws -> (Composer, String) {
                let (c, _) = try levelOne()
                Paging.type("niubi", c)
                Paging.press(Paging.pageDown, c, times: page)
                Paging.press(Paging.arrowDown, c, times: downs)
                let doomed = try #require(Paging.highlighted(c))
                let response = c.handleKeyDown(Paging.controlForwardDelete)
                #expect(response.handled && Paging.removals(response.effects) == [doomed], "\(response.effects)")
                return (c, doomed)
            }
            // In the middle of the first page: the one after moved up into the row.
            let (middle, a) = try removingHighlighted(downs: 2)
            #expect(a == all[2] && Paging.rows(middle) == [all[0], all[1], all[3], all[4], all[5]], "\(Paging.rows(middle))")
            #expect(middle.engineState.highlighted == 2 && Paging.highlighted(middle) == all[3])
            Paging.escape(middle)
            // At the end of the first page: the second page's first moved up into it.
            let (end, b) = try removingHighlighted(downs: 4)
            #expect(b == all[4] && Paging.rows(end) == [all[0], all[1], all[2], all[3], all[5]], "\(Paging.rows(end))")
            #expect(end.engineState.pageNumber == 0 && end.engineState.highlighted == 4 && Paging.highlighted(end) == all[5])
            Paging.escape(end)
            // At the end of the second page: the third page's first. librime deleted the one on that page.
            let recorder = Recorder(try #require(RimeService.shared.makeSession()))
            let second = Composer(engine: EnglishWordsEngine(base: recorder, dictionary: try #require(RimeService.shared.englishDictionary)),
                                  actionKey: .enter)
            Paging.type("niubi", second)
            Paging.press(Paging.pageDown, second)
            Paging.press(Paging.arrowDown, second, times: 4)
            #expect(Paging.removals(second.handleKeyDown(Paging.controlForwardDelete).effects) == [all[9]])
            #expect(recorder.deleted == [all[9]], "librime's delete: \(recorder.deleted)")
            #expect(second.engineState.pageNumber == 1 && Paging.rows(second) == [all[5], all[6], all[7], all[8], all[10]],
                    "\(Paging.rows(second))")
            #expect(second.engineState.highlighted == 4 && Paging.highlighted(second) == all[10])
            // A right-click on its first row then: that one deleted, the highlight on the one it was on.
            #expect(Paging.removals(second.deleteCandidate(index: 0)) == [all[5]] && recorder.deleted == [all[9], all[5]])
            #expect(Paging.rows(second) == [all[6], all[7], all[8], all[10], all[11]] && Paging.highlighted(second) == all[10],
                    "\(Paging.rows(second))")
            Paging.escape(second)
            // At the end of the list: nothing moved up, on the one before.
            let lastPage = niubi.count - 1, lastRows = niubi[lastPage]
            try #require(lastRows.count >= 2, "\(lastRows)")
            let (last, d) = try removingHighlighted(downs: lastRows.count - 1, page: lastPage)
            #expect(d == lastRows.last && last.engineState.pageNumber == lastPage && Paging.rows(last) == Array(lastRows.dropLast()),
                    "\(Paging.rows(last))")
            #expect(Paging.highlighted(last) == lastRows[lastRows.count - 2])
            // Space puts in the one highlighted (last: what is put in is learned).
            let picked = Paging.putIn(last.handleKeyDown(KeyEvent(keyCode: VirtualKey.space, characters: " ")).effects).first
                ?? last.engineState.preedit
            #expect(picked.hasPrefix(lastRows[lastRows.count - 2]), "\(picked)")
            for _ in 0..<3 where last.engineState.isComposing { Paging.escape(last) }
        },

        "removed-filter-traditional": { root in
            let pack = try pack(root, code: "rime-lua", script: String(contentsOf: script, encoding: .utf8))
            let user = root.appendingPathComponent("Rime")
            #expect(try start(pack, user: user, characters: .taiwan) == .written)
            let patch = try String(contentsOf: user.appendingPathComponent(FuzzyPinyin.fileName), encoding: .utf8)
            let traditional = try #require(patch.range(of: "traditionalize/opencc_config: s2twp.json"), "\(patch)")
            #expect(patch.hasSuffix(patchFilter) && traditional.upperBound < patch.range(of: patchFilter)!.lowerBound, "\(patch)")

            let pages = Paging.pages("niubi", try levelOne().0)
            let all = Array(pages.joined())
            try #require(all.prefix(5).contains("紐幣") && all[1] == "👍", "Traditional: \(pages)")
            let (c, engine) = try levelOne()
            Paging.type("niubi", c)
            #expect(Paging.removals(c.deleteCandidate(index: 1)) == ["👍"])
            let row = try #require(Paging.rows(c).firstIndex(of: "紐幣"))
            #expect(Paging.removals(c.deleteCandidate(index: row)) == ["紐幣"])
            let left = all.filter { $0 != "👍" && $0 != "紐幣" }
            #expect(Paging.rows(c) == Array(left.prefix(5)) && engine.base.snapshot().candidates.map(\.text) == Array(left.prefix(5)),
                    "\(Paging.rows(c))")
            // Kept by the text shown: Traditional's.
            #expect(c.removedCandidates == ["👍", "紐幣"])
            let after = Paging.onAndBack(c)
            #expect(Array(after.on.joined()) == left && after.on.dropLast().allSatisfy { $0.count == 5 }, "\(after.on)")
            #expect(after.back == after.on.reversed())
            Paging.escape(c)
            // On the second page: 軟體's spelling's, removed there.
            let ruanjian = Paging.pages("ruanjian", try levelOne().0)
            let (r, _) = try levelOne()
            Paging.type("ruanjian", r)
            Paging.press(Paging.pageDown, r)
            let second = Paging.rows(r)
            #expect(Paging.removals(r.deleteCandidate(index: 1)) == [second[1]])
            let rLeft = ruanjian.joined().filter { $0 != second[1] }
            #expect(r.engineState.pageNumber == 1 && Paging.rows(r) == Array(rLeft[5..<10]), "\(Paging.rows(r))")
            Paging.escape(r)

            // Without the filter's list (the property never given), level one leaves out the same ones: by the same text.
            let silent = Silent(try #require(RimeService.shared.makeSession()))
            let fallback = Composer(engine: silent, actionKey: .enter)
            fallback.removedCandidates = ["👍", "紐幣"]
            Paging.type("niubi", fallback)
            #expect(Paging.rows(fallback) == pages[0].filter { $0 != "👍" && $0 != "紐幣" }, "\(Paging.rows(fallback))")
            Paging.escape(fallback)
            // A Simplified text on the list isn't what is shown: neither leaves 紐幣 out.
            let (simplified, _) = try levelOne(["纽币"])
            Paging.type("niubi", simplified)
            #expect(Paging.rows(simplified) == pages[0], "\(Paging.rows(simplified))")
            Paging.escape(simplified)
            fallback.removedCandidates = ["纽币"]
            Paging.type("niubi", fallback)
            #expect(Paging.rows(fallback) == pages[0], "\(Paging.rows(fallback))")
            Paging.escape(fallback)
        },

        // An app without the filter: no patch, rime-ice deployed as it is; level one leaves them out of librime's pages.
        "removed-filter-before-update": { root in
            let pack = try pack(root, code: "rime-lua-old", script: nil)
            let user = root.appendingPathComponent("Rime")
            #expect(try start(pack, user: user) == .unchanged)
            #expect(!FileManager.default.fileExists(atPath: user.appendingPathComponent(FuzzyPinyin.fileName).path))
            let pages = Paging.pages("niubi", try levelOne().0)
            let (c, engine) = try levelOne([pages[0][1], pages[0][2]])
            Paging.type("niubi", c)
            #expect(Paging.rows(c) == [pages[0][0], pages[0][3], pages[0][4]], "\(Paging.rows(c))")
            #expect(engine.base.snapshot().candidates.map(\.text) == pages[0], "librime leaves nothing out")
            Paging.escape(c)
            try Data(pages[0].joined(separator: "\n").utf8).write(to: root.appendingPathComponent("first-page.txt"))
        },
        // The update: the app's Lua has the script now; its first start writes the patch and deploys again.
        "removed-filter-after-update": { root in
            let pack = try pack(root, code: "rime-lua-new", script: String(contentsOf: script, encoding: .utf8))
            let user = root.appendingPathComponent("Rime")
            #expect(try start(pack, user: user) == .written)
            let built = try String(contentsOf: user.appendingPathComponent("build/rime_ice.schema.yaml"), encoding: .utf8)
            #expect(built.contains("lua_filter@*allinoneime_removed"), "deployed with the filter")
            let first = try String(contentsOf: root.appendingPathComponent("first-page.txt"), encoding: .utf8).components(separatedBy: "\n")
            let all = Array(Paging.pages("niubi", try levelOne().0).joined())
            #expect(Array(all.prefix(5)) == first)
            let (c, engine) = try levelOne([first[1], first[2]])
            Paging.type("niubi", c)
            let left = Array(all.filter { $0 != first[1] && $0 != first[2] }.prefix(5))
            #expect(Paging.rows(c) == left && engine.base.snapshot().candidates.map(\.text) == left, "\(Paging.rows(c))")
            Paging.escape(c)
        },
        // A later script, the patch the same: no deploy, the script as it is now used (librime loads it as it starts).
        "removed-filter-script-changed": { root in
            let changed = try String(contentsOf: script, encoding: .utf8)
                .replacingOccurrences(of: "if not set[cand.text] then", with: "if not set[cand.text] and cand.text ~= \"牛逼\" then")
            let pack = try pack(root, code: "rime-lua-later", script: changed)
            let user = root.appendingPathComponent("Rime")
            #expect(try start(pack, user: user) == .unchanged)
            let first = try String(contentsOf: root.appendingPathComponent("first-page.txt"), encoding: .utf8).components(separatedBy: "\n")
            let (c, _) = try levelOne([first[1]])
            Paging.type("niubi", c)
            #expect(!Paging.rows(c).contains("牛逼") && !Paging.rows(c).contains(first[1]) && Paging.rows(c).count == 5, "\(Paging.rows(c))")
            Paging.escape(c)
        },
    ]
}

/// librime's session wrapped as an engine that never gives it the list (`setRemovedCandidates` not passed on): what
/// level one does where librime has no list.
private final class Silent: PinyinEngine {
    let base: RimeSession
    init(_ base: RimeSession) { self.base = base }
    func processKey(_ keycode: Int32, mask: Int32) -> Bool { base.processKey(keycode, mask: mask) }
    func takeCommit() -> String? { base.takeCommit() }
    func snapshot() -> EngineSnapshot { base.snapshot() }
    func selectCandidate(onPage index: Int) -> Bool { base.selectCandidate(onPage: index) }
    func deleteCandidate(onPage index: Int) -> Bool { base.deleteCandidate(onPage: index) }
    func commitComposition() -> String? { base.commitComposition() }
    var rawInput: String { base.rawInput }
    func clearComposition() { base.clearComposition() }
    func setAsciiMode(_ on: Bool) { base.setAsciiMode(on) }
}

/// librime's session as level one has it, the text of each candidate it deleted recorded (the one on its page then).
private final class Recorder: PinyinEngine {
    let base: RimeSession
    private(set) var deleted: [String] = []
    init(_ base: RimeSession) { self.base = base }
    func processKey(_ keycode: Int32, mask: Int32) -> Bool { base.processKey(keycode, mask: mask) }
    func takeCommit() -> String? { base.takeCommit() }
    func snapshot() -> EngineSnapshot { base.snapshot() }
    func selectCandidate(onPage index: Int) -> Bool { base.selectCandidate(onPage: index) }
    func deleteCandidate(onPage index: Int) -> Bool {
        let page = base.snapshot().candidates
        if page.indices.contains(index) { deleted.append(page[index].text) }
        return base.deleteCandidate(onPage: index)
    }
    func setRemovedCandidates(_ texts: [String]) { base.setRemovedCandidates(texts) }
    func commitComposition() -> String? { base.commitComposition() }
    var rawInput: String { base.rawInput }
    func clearComposition() { base.clearComposition() }
    func setAsciiMode(_ on: Bool) { base.setAsciiMode(on) }
}

/// Typing and turning the pages of a composer.
private enum Paging {
    static let pageDown = KeyEvent(keyCode: VirtualKey.pageDown, characters: "\u{F72D}")
    static let pageUp = KeyEvent(keyCode: VirtualKey.pageUp, characters: "\u{F72C}")
    static let arrowDown = KeyEvent(keyCode: VirtualKey.down, characters: "\u{F701}")
    static let controlForwardDelete = KeyEvent(keyCode: VirtualKey.forwardDelete, characters: "\u{F728}", modifiers: .control)

    static func type(_ letters: String, _ c: Composer) { for ch in letters { _ = c.handleKeyDown(key(ch)) } }
    static func press(_ event: KeyEvent, _ c: Composer, times: Int = 1) { for _ in 0..<times { _ = c.handleKeyDown(event) } }
    static func escape(_ c: Composer) { _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}")) }
    static func rows(_ c: Composer) -> [String] { c.engineState.candidates.map(\.text) }
    static func highlighted(_ c: Composer) -> String? {
        let state = c.engineState
        return state.candidates.indices.contains(state.highlighted) ? state.candidates[state.highlighted].text : nil
    }
    static func numberedAsShown(_ c: Composer) -> Bool {
        c.engineState.candidates.enumerated().allSatisfy { $0.element.label == String(($0.offset + 1) % 10) }
    }
    static func removals(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .candidateRemoved(text) = $0 { return text } else { return nil } }
    }
    static func putIn(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .commit(text) = $0 { return text } else { return nil } }
    }

    /// The pages for `letters` (`count` at most), the composition then cleared.
    static func pages(_ letters: String, _ c: Composer, count: Int = 8) -> [[String]] {
        type(letters, c)
        let pages = onAndBack(c, count: count).on
        escape(c)
        return pages
    }

    /// The pages from the one shown on (Page Down, `count` at most), then back from there to the first (Page Up).
    static func onAndBack(_ c: Composer, count: Int = 8) -> (on: [[String]], back: [[String]]) {
        var on = [rows(c)]
        while on.count < count, !c.engineState.isLastPage {
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
}

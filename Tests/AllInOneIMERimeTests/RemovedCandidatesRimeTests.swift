@testable import AllInOneIMECore
import Foundation
import Testing
@testable import AllInOneIMERime

/// Candidates removed for good with the real librime and rime-ice (`Config.removedCandidates`): a row right-clicked
/// (`Composer.deleteCandidate(index:)`) or ⌃⌦ on the highlighted one. One removed never shows again as a candidate of its
/// own, whatever is typed, matched by its whole text (a longer phrase with it in it still comes; an emoji too); an English
/// word put among librime's candidates by its letters. The rows are numbered as shown, and every key that puts a
/// candidate in puts in one that is shown. A page with nothing shown is skipped, five at most. In the serialized suite:
/// librime's user dictionary is the process's, so each test types letters no other test types, and none counts on
/// another having run.
extension RimeEngineTests {

    /// 鼓掌, a word of rime-ice's dictionary librime never learned, second for "guzhang": its row right-clicked, it is gone
    /// from every page of "guzhang", and of "guzh" (zh for zhang), which gives it too. Nothing is put in, the letters stay,
    /// the rows are numbered again. 鼓掌欢迎, which has it in it, still comes.
    @Test func aRemovedDictionaryWordIsGoneFromEverySpelling() throws {
        let composer = Composer(engine: try RimeFixture.session(), actionKey: .enter)
        #expect(everyPage("guzh", composer).contains("鼓掌"), "another spelling gives it")
        typing("guzhang", composer)
        let row = try #require(rows(composer).firstIndex(of: "鼓掌"), "\(rows(composer))")
        #expect(row > 0, "not first: \(rows(composer))")
        let effects = composer.deleteCandidate(index: row)
        #expect(removals(effects) == ["鼓掌"], "\(effects)")
        #expect(putIn(effects).isEmpty, "nothing put in: \(effects)")
        #expect(composer.engineState.isComposing && composer.engine?.rawInput == "guzhang", "the letters stay")
        #expect(!rows(composer).contains("鼓掌") && rows(composer).first == "故障", "laid out again: \(rows(composer))")
        #expect(numberedAsShown(composer), "\(composer.engineState.candidates.map(\.label))")
        #expect(composer.removedCandidates == ["鼓掌"])
        escaping(composer)
        let again = everyPage("guzhang", composer)
        #expect(!again.contains("鼓掌") && again.contains("故障") && again.contains("股长"), "\(again.prefix(12))")
        let other = everyPage("guzh", composer)
        #expect(!other.contains("鼓掌") && other.contains("故障"), "\(other.prefix(12))")
        let phrase = everyPage("guzhanghuanying", composer)
        #expect(phrase.first == "鼓掌欢迎" && !phrase.contains("鼓掌"), "the whole text: \(phrase.prefix(8))")
    }

    /// The first candidate removed (and those after it), the highlight is on the first shown: every key librime commits
    /// its highlighted candidate on puts in that one, never one removed. Space, the digit 1, a punctuation mark (the
    /// candidate before it), rime-ice's [ (the first character of the one highlighted), and the composition committed
    /// when the field is left.
    @Test func keysAfterTheFirstIsRemovedPutInOnlyWhatIsShown() throws {
        let composer = Composer(engine: try RimeFixture.session(), actionKey: .enter)

        /// `letters` typed and the first row removed `times` times: what was removed, and the first row shown then.
        func removingFirst(_ letters: String, times: Int = 1) throws -> (gone: [String], first: String) {
            typing(letters, composer)
            var gone: [String] = []
            for _ in 0..<times {
                let effects = composer.deleteCandidate(index: 0)
                gone += removals(effects)
                #expect(putIn(effects).isEmpty, "\(effects)")
            }
            #expect(gone.count == times && composer.engineState.isComposing, "\(letters): \(gone)")
            #expect(Set(rows(composer)).isDisjoint(with: gone), "\(letters): \(rows(composer))")
            #expect(composer.engineState.highlighted == 0, "\(letters): on the first shown (\(composer.engineState.highlighted))")
            #expect(numberedAsShown(composer), "\(letters): \(composer.engineState.candidates.map(\.label))")
            return (gone, try #require(rows(composer).first, "\(letters): something shown"))
        }

        // Space.
        let space = try removingFirst("dongtian")
        #expect(space.gone == ["冬天"] && space.first == "洞天", "\(space)")
        #expect(putIn(composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.space, characters: " "))) == [space.first])

        // The digit 1: the row shown first, with three removed before it.
        let digit = try removingFirst("pingguo", times: 3)
        #expect(digit.gone == ["苹果", "🍎", "🍏"] && digit.first == "评过", "\(digit)")
        #expect(putIn(composer.handleKeyDown(key("1"))) == [digit.first])
        #expect(!composer.engineState.isComposing)

        // A punctuation mark: the one highlighted, then the mark.
        let comma = try removingFirst("huoche", times: 2)
        #expect(comma.gone == ["火车", "🚆"] && comma.first == "货车", "\(comma)")
        #expect(putIn(composer.handleKeyDown(key(","))).joined() == comma.first + "，")

        // rime-ice's [: the first character of the one highlighted.
        let bracket = try removingFirst("shiyan")
        #expect(bracket.gone == ["实验"] && bracket.first == "试验", "\(bracket)")
        let first = putIn(composer.handleKeyDown(key("["))).joined()
        #expect(first == "试", "\(first)")
        if composer.engineState.isComposing { escaping(composer) }

        // ⇧Space, as Space.
        let shifted = try removingFirst("maomi", times: 3)
        #expect(shifted.gone == ["猫咪", "🐱", "🐈"] && shifted.first == "茂密", "\(shifted)")
        let shiftSpace = KeyEvent(keyCode: VirtualKey.space, characters: " ", modifiers: .shift)
        #expect(putIn(composer.handleKeyDown(shiftSpace)) == [shifted.first])

        // rime-ice's ]: the last character of the one highlighted.
        let last = try removingFirst("xiaolian", times: 2)
        #expect(last.gone == ["笑脸", "😀"] && last.first == "小脸", "\(last)")
        let character = putIn(composer.handleKeyDown(key("]"))).joined()
        #expect(character == "脸", "\(character)")
        if composer.engineState.isComposing { escaping(composer) }

        // The field left: the composition committed is the one highlighted.
        let left = try removingFirst("dianshi", times: 2)
        #expect(left.gone == ["电视", "📺"] && left.first == "电石", "\(left)")
        #expect(putIn(composer.commitAll()) == [left.first])
    }

    /// ↓ and ↑ (→ and ← in a row) move over the rows shown only: past the last shown onto the next page, back from it
    /// onto the last shown, never onto one removed; Space then puts in the one highlighted. Letters typed one by one with
    /// the first removed: the highlight on the first shown.
    @Test func arrowsMoveOverWhatIsShownOnly() throws {
        let composer = Composer(engine: try RimeFixture.session(), actionKey: .enter)
        let down = KeyEvent(keyCode: VirtualKey.down, characters: "\u{F701}")
        let up = KeyEvent(keyCode: VirtualKey.up, characters: "\u{F700}")
        let spaceKey = KeyEvent(keyCode: VirtualKey.space, characters: " ")
        func highlighted() -> String? {
            let state = composer.engineState
            return state.candidates.indices.contains(state.highlighted) ? state.candidates[state.highlighted].text : nil
        }

        // 窃, the last of the first page, removed.
        typing("qiezi", composer)
        let row = try #require(rows(composer).firstIndex(of: "窃"), "\(rows(composer))")
        #expect(removals(composer.deleteCandidate(index: row)) == ["窃"])
        let first = rows(composer)
        #expect(first == ["茄子", "🍆", "且", "切"], "\(first)")
        for _ in 0..<3 { _ = composer.handleKeyDown(down) }
        #expect(composer.engineState.pageNumber == 0 && highlighted() == "切", "\(String(describing: highlighted()))")
        _ = composer.handleKeyDown(down)
        #expect(composer.engineState.pageNumber == 1 && composer.engineState.highlighted == 0, "on the next page")
        _ = composer.handleKeyDown(up)
        #expect(composer.engineState.pageNumber == 0 && highlighted() == "切",
                "back on the last shown, not 窃: \(String(describing: highlighted())) of \(rows(composer))")
        // Picked: 切 reads "qie" only, the start of the composition then.
        let picked = putIn(composer.handleKeyDown(spaceKey)).first ?? composer.engineState.preedit
        #expect(picked.hasPrefix("切"), "\(picked)")
        for _ in 0..<3 where composer.engineState.isComposing { escaping(composer) }
        #expect(!composer.engineState.isComposing)

        // Two removed after the first: ↓ onto the next shown.
        typing("jiaoshi", composer)
        _ = composer.deleteCandidate(index: 1)
        _ = composer.deleteCandidate(index: 1)
        #expect(Array(rows(composer).prefix(2)) == ["教师", "教室"], "\(rows(composer))")
        _ = composer.handleKeyDown(down)
        #expect(highlighted() == "教室", "\(String(describing: highlighted()))")
        _ = composer.handleKeyDown(up)
        #expect(highlighted() == "教师")
        // In a row: → and ←.
        composer.horizontalCandidates = true
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.right, characters: "\u{F703}"))
        #expect(highlighted() == "教室", "→: \(String(describing: highlighted()))")
        #expect(putIn(composer.handleKeyDown(spaceKey)) == ["教室"])
        composer.horizontalCandidates = false

        // Typed one by one with the first removed, as from the list.
        composer.removedCandidates.append("绿色")
        typing("lvse", composer)
        #expect(!rows(composer).contains("绿色") && composer.engineState.highlighted == 0, "\(rows(composer))")
        let shown = try #require(rows(composer).first)
        #expect(putIn(composer.handleKeyDown(spaceKey)) == [shown])
    }

    /// ⌃⌦ on a row ↓ moved onto: that one removed, the highlight then on a shown one, which Space puts in.
    @Test func theHighlightedOneRemovedLeavesTheHighlightOnAShownOne() throws {
        let composer = Composer(engine: try RimeFixture.session(), actionKey: .enter)
        let down = KeyEvent(keyCode: VirtualKey.down, characters: "\u{F701}")
        let controlForwardDelete = KeyEvent(keyCode: VirtualKey.forwardDelete, characters: "\u{F728}", modifiers: .control)
        func highlighted() -> String? {
            let state = composer.engineState
            return state.candidates.indices.contains(state.highlighted) ? state.candidates[state.highlighted].text : nil
        }
        typing("mabu", composer)
        _ = composer.handleKeyDown(down)
        _ = composer.handleKeyDown(down)
        let doomed = try #require(highlighted())
        #expect(doomed == "麻布", "\(rows(composer))")
        let response = composer.handleKeyDown(controlForwardDelete)
        #expect(response.handled && removals(response.effects) == ["麻布"] && putIn(response).isEmpty, "\(response.effects)")
        let now = try #require(highlighted(), "\(rows(composer)) \(composer.engineState.highlighted)")
        #expect(now != doomed && !rows(composer).contains(doomed), "\(now): \(rows(composer))")
        let picked = putIn(composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.space, characters: " "))).first
            ?? composer.engineState.preedit
        #expect(picked.hasPrefix(now) && !picked.contains(doomed), "\(picked) for \(now)")
        for _ in 0..<3 where composer.engineState.isComposing { escaping(composer) }
    }

    /// A row of the second page removed: that page laid out again without it, where the user is (librime's
    /// `delete_candidate` lays the composition out anew from its first page).
    @Test func aRowOfTheSecondPageRemovedStaysOnThatPage() throws {
        let composer = Composer(engine: try RimeFixture.session(), actionKey: .enter)
        typing("dianying", composer)
        _ = composer.handleKeyDown(pageDownKey)
        #expect(composer.engineState.pageNumber == 1, "\(composer.engineState.pageNumber)")
        let second = rows(composer)
        try #require(second.count == 5, "\(second)")
        let gone = second[2]
        #expect(removals(composer.deleteCandidate(index: 2)) == [gone])
        #expect(composer.engineState.pageNumber == 1 && rows(composer) == second.filter { $0 != gone },
                "the page laid out again: page \(composer.engineState.pageNumber), \(rows(composer))")
        escaping(composer)
    }

    /// The list kept (the config file's, after the app restarts): a new librime session under a new composer given it
    /// leaves the candidate out, whatever is typed for it; one without the list shows it, as librime keeps a word of its
    /// dictionary.
    @Test func theListLeavesItOutAfterARestart() throws {
        let first = Composer(engine: try RimeFixture.session(), actionKey: .enter)
        typing("xigua", first)
        let row = try #require(rows(first).firstIndex(of: "戏骨"), "\(rows(first))")
        #expect(row > 0)
        #expect(removals(first.deleteCandidate(index: row)) == ["戏骨"])
        let list = first.removedCandidates
        #expect(list == ["戏骨"])
        escaping(first)

        let plain = Composer(engine: try RimeFixture.session(), actionKey: .enter)
        let kept = everyPage("xigua", plain)
        #expect(kept.contains("戏骨"), "librime keeps it: \(kept.prefix(8))")

        let later = Composer(engine: try RimeFixture.session(), actionKey: .enter)
        later.removedCandidates = list
        for letters in ["xigua", "xigu"] {
            let pages = everyPage(letters, later)
            #expect(!pages.contains("戏骨") && pages.contains("硒鼓"), "\(letters): \(pages.prefix(8))")
        }
        // The shell's engine, with English words among the candidates, given the list as it is made.
        let dictionary = try #require(RimeService.shared.englishDictionary)
        let mixed = Composer(engine: EnglishWordsEngine(base: try RimeFixture.session(), dictionary: dictionary,
                                                        removedCandidates: list), actionKey: .enter)
        #expect(!everyPage("xigua", mixed).contains("戏骨"))
        #expect(mixed.removedCandidates == list)
        // librime deployed again: a new session put in under the composer that removed it leaves it out still.
        first.engine = try RimeFixture.session()
        #expect(!everyPage("xigua", first).contains("戏骨") && first.removedCandidates == list)
    }

    /// An emoji rime-ice gives (😄 for "kaixin") removed: gone, by its whole text, wherever it comes ("haha" gives it
    /// too); the words it came with stay.
    @Test func anEmojiRemovedIsGoneWhereverItComes() throws {
        let composer = Composer(engine: try RimeFixture.session(), actionKey: .enter)
        #expect(everyPage("haha", composer).contains("😄"))
        typing("kaixin", composer)
        let row = try #require(rows(composer).firstIndex(of: "😄"), "\(rows(composer))")
        let effects = composer.deleteCandidate(index: row)
        #expect(removals(effects) == ["😄"] && putIn(effects).isEmpty, "\(effects)")
        #expect(!rows(composer).contains("😄") && rows(composer).first == "开心", "\(rows(composer))")
        escaping(composer)
        #expect(!everyPage("kaixin", composer).contains("😄"))
        let haha = everyPage("haha", composer)
        #expect(!haha.contains("😄") && haha.contains("哈哈") && haha.contains("🐸"), "\(haha)")
    }

    /// An English word among librime's candidates (`EnglishWordsEngine`): a librime row past it removes librime's
    /// candidate shown on that row; the word's row removes the word, by its letters (written another way, it isn't
    /// offered either; a longer word is). A digit then picks the row shown with that number.
    @Test func anEnglishWordAndLibrimesAmongItAreRemovedByTheirRows() throws {
        let session = try RimeFixture.session()
        let dictionary = try #require(RimeService.shared.englishDictionary)
        let mixed = EnglishWordsEngine(base: session, dictionary: dictionary, words: ["Yinyue"])
        let composer = Composer(engine: mixed, actionKey: .enter)
        typing("yinyue", composer)
        let shown = rows(composer)
        #expect(Array(shown.prefix(2)) == ["音乐", "Yinyue"], "pinyin too: the word second (\(shown))")
        let row = try #require(shown.firstIndex(of: "隐约"), "\(shown)")
        let librime = composer.deleteCandidate(index: row)
        #expect(removals(librime) == ["隐约"] && putIn(librime).isEmpty, "\(librime)")
        #expect(rows(composer) == shown.filter { $0 != "隐约" }, "\(rows(composer)) from \(shown)")
        #expect(numberedAsShown(composer))

        let wordRow = try #require(rows(composer).firstIndex(of: "Yinyue"))
        let word = composer.deleteCandidate(index: wordRow)
        #expect(removals(word) == ["Yinyue"] && putIn(word).isEmpty, "\(word)")
        #expect(rows(composer) == shown.filter { $0 != "隐约" && $0 != "Yinyue" }, "\(rows(composer))")
        #expect(mixed.removedKeys.contains("yinyue") && composer.removedCandidates == ["隐约", "Yinyue"])
        #expect(composer.engineState.isComposing && session.rawInput == "yinyue")
        escaping(composer)

        mixed.words = ["yinyue", "Yinyuefest"]
        typing("yinyue", composer)
        #expect(!rows(composer).contains { $0.lowercased() == "yinyue" } && rows(composer).contains("Yinyuefest"),
                "the other capitalization left out, a longer word offered: \(rows(composer))")
        escaping(composer)
        mixed.words = ["yinyue"]
        typing("yinyue", composer)
        let now = rows(composer)
        #expect(!now.contains { $0.lowercased() == "yinyue" } && !now.contains("隐约"), "\(now)")
        // The fourth row shown (librime's fifth, its fourth removed): 4 picks it.
        let fourth = try #require(now.dropFirst(3).first)
        #expect(fourth == "银月", "\(now)")
        #expect(putIn(composer.handleKeyDown(key("4"))) == [fourth])
    }

    /// A page with every candidate removed is skipped in the way the pages turn (on from the first page), five pages at
    /// most; with none shown the panel has no candidates, a digit picks nothing and Space puts the letters in as typed.
    @Test func aPageWithNothingShownIsSkipped() throws {
        let pages = pagesOf("shu", Composer(engine: try RimeFixture.session(), actionKey: .enter), count: 8)
        try #require(pages.count == 8 && pages.allSatisfy { $0.count == 5 }, "\(pages)")
        let composer = Composer(engine: try RimeFixture.session(), actionKey: .enter)
        composer.removedCandidates = pages[0] + pages[2]
        typing("shu", composer)
        #expect(composer.engineState.pageNumber == 1 && rows(composer) == pages[1], "\(composer.engineState.pageNumber): \(rows(composer))")
        #expect(numberedAsShown(composer))
        _ = composer.handleKeyDown(key("="))
        #expect(composer.engineState.pageNumber == 3 && rows(composer) == pages[3], "on: \(composer.engineState.pageNumber)")
        _ = composer.handleKeyDown(key("-"))
        #expect(composer.engineState.pageNumber == 1 && rows(composer) == pages[1], "back: \(composer.engineState.pageNumber)")
        // Back from the second page: the first has nothing, on from there.
        _ = composer.handleKeyDown(pageUpKey)
        #expect(composer.engineState.pageNumber == 1 && rows(composer) == pages[1], "\(composer.engineState.pageNumber)")
        _ = composer.handleKeyDown(pageDownKey)
        #expect(composer.engineState.pageNumber == 3, "the page keys too: \(composer.engineState.pageNumber)")
        escaping(composer)

        composer.removedCandidates = Array(pages[0..<5].joined())
        typing("shu", composer)
        #expect(composer.engineState.pageNumber == 5 && rows(composer) == pages[5], "five pages: \(composer.engineState.pageNumber)")
        escaping(composer)

        composer.removedCandidates = Array(pages[0..<6].joined())
        typing("shu", composer)
        #expect(rows(composer).isEmpty && composer.engineState.isComposing, "none shown: \(rows(composer))")
        #expect(putIn(composer.handleKeyDown(key("1"))).isEmpty && composer.engineState.isComposing, "a digit picks nothing")
        #expect(putIn(composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.space, characters: " "))) == ["shu"])
        #expect(!composer.engineState.isComposing)
    }

    /// A candidate removed on the third page ("yisheng"'s, words of rime-ice's dictionary librime never learned):
    /// librime's `delete_candidate` lays the composition out anew from its first page, and the user stays on the third,
    /// laid out again without it. The highlighted one removed (⌃⌦): the highlight on the one shown after it; another row
    /// (a right-click), before it or after it: the highlight stays on the candidate it was on, which Space puts in. Only
    /// words of the whole spelling are removed: what librime forgets of a single character would reach other spellings.
    @Test func aRemovalOnTheThirdPageStaysOnIt() throws {
        let pages = pagesOf("yisheng", Composer(engine: try RimeFixture.session(), actionKey: .enter), count: 4)
        try #require(pages.count >= 3 && pages[2].count == 5, "\(pages)")
        let third = pages[2]
        try #require(third.prefix(4).allSatisfy { $0.count == 2 } && Set(third).count == 5, "\(third)")
        let composer = Composer(engine: try RimeFixture.session(), actionKey: .enter)
        typing("yisheng", composer)
        _ = composer.handleKeyDown(pageDownKey)
        _ = composer.handleKeyDown(pageDownKey)
        try #require(composer.engineState.pageNumber == 2 && rows(composer) == third, "\(composer.engineState.pageNumber): \(rows(composer))")
        _ = composer.handleKeyDown(arrowDown)
        #expect(highlightedRow(composer) == third[1])

        let response = composer.handleKeyDown(controlForwardDelete)
        #expect(response.handled && removals(response.effects) == [third[1]] && putIn(response).isEmpty, "\(response.effects)")
        #expect(composer.engineState.pageNumber == 2 && rows(composer) == [third[0], third[2], third[3], third[4]],
                "page \(composer.engineState.pageNumber): \(rows(composer))")
        #expect(highlightedRow(composer) == third[2], "the next shown: \(String(describing: highlightedRow(composer)))")
        #expect(numberedAsShown(composer) && composer.engine?.rawInput == "yisheng")

        #expect(removals(composer.deleteCandidate(index: 0)) == [third[0]])
        #expect(composer.engineState.pageNumber == 2 && rows(composer) == [third[2], third[3], third[4]], "\(rows(composer))")
        #expect(highlightedRow(composer) == third[2], "a row before it: \(String(describing: highlightedRow(composer)))")
        #expect(removals(composer.deleteCandidate(index: 1)) == [third[3]])
        #expect(composer.engineState.pageNumber == 2 && rows(composer) == [third[2], third[4]], "\(rows(composer))")
        #expect(highlightedRow(composer) == third[2], "a row after it: \(String(describing: highlightedRow(composer)))")
        #expect(composer.removedCandidates == [third[1], third[0], third[3]])

        let picked = putIn(composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.space, characters: " "))).first
            ?? composer.engineState.preedit
        #expect(picked.hasPrefix(third[2]), "\(picked) for \(third[2])")
        for _ in 0..<3 where composer.engineState.isComposing { escaping(composer) }
    }

    /// ↑ on a page's first row, the page before with nothing shown ("shenghuo"'s second, every candidate on it removed):
    /// that page skipped, the highlight on the last row shown of the page reached, also when librime's last there is
    /// removed, and Space puts that one in. The page keys there leave it where librime's put it (on the same row of the
    /// page; one removed there: one shown). With nothing shown before, ↑ stays on the first row.
    @Test func upOverAPageWithNothingShownLandsOnTheLastRowShown() throws {
        let pages = pagesOf("shenghuo", Composer(engine: try RimeFixture.session(), actionKey: .enter), count: 4)
        try #require(pages.count >= 3 && pages.prefix(3).allSatisfy { $0.count == 5 }, "\(pages)")

        let none = Composer(engine: try RimeFixture.session(), actionKey: .enter)
        none.removedCandidates = pages[0]
        typing("shenghuo", none)
        #expect(none.engineState.pageNumber == 1 && highlightedRow(none) == pages[1][0], "\(none.engineState.pageNumber)")
        _ = none.handleKeyDown(arrowUp)
        #expect(none.engineState.pageNumber == 1 && highlightedRow(none) == pages[1][0],
                "nothing before: \(none.engineState.pageNumber), \(String(describing: highlightedRow(none)))")
        escaping(none)

        for lastRemoved in [false, true] {
            let composer = Composer(engine: try RimeFixture.session(), actionKey: .enter)
            composer.removedCandidates = pages[1] + (lastRemoved ? [pages[0][4]] : [])
            let last = lastRemoved ? pages[0][3] : pages[0][4]
            typing("shenghuo", composer)
            _ = composer.handleKeyDown(pageDownKey)
            #expect(composer.engineState.pageNumber == 2 && rows(composer) == pages[2], "\(composer.engineState.pageNumber)")
            #expect(highlightedRow(composer) == pages[2][0])
            _ = composer.handleKeyDown(arrowUp)
            #expect(composer.engineState.pageNumber == 0 && highlightedRow(composer) == last,
                    "\(lastRemoved): page \(composer.engineState.pageNumber), \(String(describing: highlightedRow(composer)))")
            if lastRemoved {
                // Last, as what is put in is learned: the order of these pages may change.
                #expect(putIn(composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.space, characters: " "))) == [last])
            } else {
                _ = composer.handleKeyDown(pageDownKey)
                _ = composer.handleKeyDown(pageUpKey)
                let row = highlightedRow(composer)
                #expect(composer.engineState.pageNumber == 0 && row.map { pages[0].contains($0) } == true,
                        "Page Up: \(composer.engineState.pageNumber), \(String(describing: row))")
            }
            for _ in 0..<3 where composer.engineState.isComposing { escaping(composer) }
        }
    }

    /// One of the user's English words ("Pengyou", `EnglishWordsEngine.words`, the settings' `Config.englishWords`)
    /// removed: gone from the rows, the engine's words as they were (removing only leaves it out); out under a new engine
    /// too (librime deployed again: the session's new `EnglishWordsEngine`); restored (the list without it), it comes
    /// back on the row it had.
    @Test func anEnglishWordOfTheUsersRemovedAndRestored() throws {
        let session = try RimeFixture.session()
        let dictionary = try #require(RimeService.shared.englishDictionary)
        let mixed = EnglishWordsEngine(base: session, dictionary: dictionary, words: ["Pengyou"])
        let composer = Composer(engine: mixed, actionKey: .enter)
        typing("pengyou", composer)
        let before = rows(composer)
        let row = try #require(before.firstIndex(of: "Pengyou"), "\(before)")
        let effects = composer.deleteCandidate(index: row)
        #expect(removals(effects) == ["Pengyou"] && putIn(effects).isEmpty, "\(effects)")
        #expect(rows(composer) == before.filter { $0 != "Pengyou" } && numberedAsShown(composer), "\(rows(composer))")
        #expect(mixed.words == ["Pengyou"] && composer.removedCandidates == ["Pengyou"])
        escaping(composer)

        let fresh = EnglishWordsEngine(base: try RimeFixture.session(), dictionary: dictionary, words: ["Pengyou"])
        composer.engine = fresh
        typing("pengyou", composer)
        #expect(!rows(composer).contains("Pengyou") && composer.removedCandidates == ["Pengyou"], "a new engine: \(rows(composer))")
        escaping(composer)

        composer.removedCandidates = []
        typing("pengyou", composer)
        #expect(rows(composer) == before, "restored: \(rows(composer)) for \(before)")
        escaping(composer)
    }
}

/// The last page with nothing shown, with the real librime: the page before it is where the user lands (claim 1 of the
/// fix after 0.6.8.4's first: `EnglishWordsEngine.skipEmptyPages` back from the last). Spellings no other test types.
extension RimeEngineTests {

    /// "fangfa"'s last page shows 牥 alone: removed (a right-click), the user is on the page before, the highlight on its
    /// last row, nothing put in, the letters as they were; librime was given page and arrow keys only besides the
    /// delete, nothing picked or cleared. Page Down and ↓ past its last row there: the same page, the highlight on its
    /// last row. Its pages from the first then: 牥 on none, the page before the last one the user gets to.
    @Test func removingTheOnlyShownOfTheLastPageGoesBackAPage() throws {
        let pages = pagesOf("fangfa", Composer(engine: try RimeFixture.session(), actionKey: .enter), count: 12)
        try #require(pages.count >= 3 && pages.last == ["牥"] && pages[pages.count - 2].count == 5, "\(pages.suffix(2))")
        let last = pages.count - 1, before = pages[last - 1]
        let told = KeysTold(try RimeFixture.session())
        let composer = Composer(engine: told, actionKey: .enter)
        typing("fangfa", composer)
        for _ in 0..<last { _ = composer.handleKeyDown(pageDownKey) }
        try #require(composer.engineState.pageNumber == last && rows(composer) == ["牥"] && composer.engineState.isLastPage,
                     "\(composer.engineState.pageNumber): \(rows(composer))")
        let keys = told.keys.count
        let effects = composer.deleteCandidate(index: 0)
        #expect(removals(effects) == ["牥"] && putIn(effects).isEmpty, "\(effects)")
        #expect(composer.engineState.pageNumber == last - 1 && rows(composer) == before,
                "page \(composer.engineState.pageNumber): \(rows(composer))")
        #expect(highlightedRow(composer) == before.last, "on its last row: \(String(describing: highlightedRow(composer)))")
        #expect(numberedAsShown(composer) && composer.engineState.isComposing && composer.engine?.rawInput == "fangfa")
        #expect(composer.removedCandidates == ["牥"] && told.deleted == [0] && told.picked.isEmpty && told.cleared == 0)
        let moves = [RimeKey.pageDown, RimeKey.pageUp, RimeKey.down, RimeKey.up]
        let others = told.keys[keys...].filter { !moves.contains($0) }
        #expect(others.isEmpty, "only page and arrow keys: \(others)")

        _ = composer.handleKeyDown(pageDownKey)
        #expect(composer.engineState.pageNumber == last - 1 && rows(composer) == before,
                "Page Down: \(composer.engineState.pageNumber): \(rows(composer))")
        #expect(highlightedRow(composer).map(before.contains) == true)
        for _ in 0..<5 where highlightedRow(composer) != before.last { _ = composer.handleKeyDown(arrowDown) }
        _ = composer.handleKeyDown(arrowDown)
        #expect(composer.engineState.pageNumber == last - 1 && highlightedRow(composer) == before.last,
                "↓: \(composer.engineState.pageNumber), \(String(describing: highlightedRow(composer)))")
        escaping(composer)

        typing("fangfa", composer)
        var seen = [rows(composer)]
        for _ in 0..<12 {
            let page = composer.engineState.pageNumber
            _ = composer.handleKeyDown(pageDownKey)
            guard composer.engineState.pageNumber > page else { break }
            seen.append(rows(composer))
        }
        #expect(seen.count == last && seen.last == before && !seen.joined().contains("牥"), "\(seen.suffix(2))")
        escaping(composer)
    }

    /// "shengri"'s last page (陞 alone) with nothing shown, on the list: Page Down, = and ↓ past the last row shown of the
    /// page before land back on it, never on an empty panel; after ↓ the highlight on its last row shown, also when
    /// librime's last there is removed, which Space puts in.
    @Test func pageDownOrDownOntoAnEmptiedLastPageStaysOnThePageBefore() throws {
        let pages = pagesOf("shengri", Composer(engine: try RimeFixture.session(), actionKey: .enter), count: 12)
        try #require(pages.count >= 3 && pages.last?.count == 1 && pages[pages.count - 2].count == 5, "\(pages.suffix(2))")
        let last = pages.count - 1, before = pages[last - 1]
        for lastRowRemoved in [false, true] {
            let composer = Composer(engine: try RimeFixture.session(), actionKey: .enter)
            composer.removedCandidates = pages[last] + (lastRowRemoved ? [before[4]] : [])
            let shown = lastRowRemoved ? Array(before.prefix(4)) : before
            typing("shengri", composer)
            for _ in 0..<(last - 1) { _ = composer.handleKeyDown(pageDownKey) }
            try #require(composer.engineState.pageNumber == last - 1 && rows(composer) == shown,
                         "\(composer.engineState.pageNumber): \(rows(composer))")
            for (name, key) in [("Page Down", pageDownKey), ("=", key("="))] {
                _ = composer.handleKeyDown(key)
                #expect(composer.engineState.pageNumber == last - 1 && rows(composer) == shown && composer.engineState.isComposing,
                        "\(lastRowRemoved) \(name): \(composer.engineState.pageNumber): \(rows(composer))")
                #expect(highlightedRow(composer).map(shown.contains) == true, "\(lastRowRemoved) \(name): a row shown")
            }
            for _ in 0..<5 where highlightedRow(composer) != shown.last { _ = composer.handleKeyDown(arrowDown) }
            #expect(highlightedRow(composer) == shown.last)
            _ = composer.handleKeyDown(arrowDown)
            #expect(composer.engineState.pageNumber == last - 1 && rows(composer) == shown && highlightedRow(composer) == shown.last,
                    "\(lastRowRemoved) ↓: \(composer.engineState.pageNumber), \(String(describing: highlightedRow(composer)))")
            #expect(numberedAsShown(composer) && composer.engine?.rawInput == "shengri")
            if lastRowRemoved {
                // Last, as what is put in is learned: the order of these pages may change.
                let picked = putIn(composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.space, characters: " "))).first
                    ?? composer.engineState.preedit
                #expect(picked.hasPrefix(shown.last!), "\(picked) for \(shown.last!)")
            }
            for _ in 0..<3 where composer.engineState.isComposing { escaping(composer) }
        }
    }

    /// "zhuanye"'s two last pages with nothing shown: Page Down from the page before them goes on over them to the last
    /// and back to it; ↓ past its last row the same, the highlight on its last row.
    @Test func twoEmptiedPagesAtTheEndAreGoneOverBack() throws {
        let pages = pagesOf("zhuanye", Composer(engine: try RimeFixture.session(), actionKey: .enter), count: 24)
        try #require(pages.count >= 4 && pages.count < 24 && pages[pages.count - 3].count == 5, "\(pages.count): \(pages.suffix(3))")
        let last = pages.count - 1, before = pages[last - 2]
        let told = KeysTold(try RimeFixture.session())
        let composer = Composer(engine: told, actionKey: .enter)
        composer.removedCandidates = pages[last - 1] + pages[last]
        typing("zhuanye", composer)
        for _ in 0..<(last - 2) { _ = composer.handleKeyDown(pageDownKey) }
        try #require(composer.engineState.pageNumber == last - 2 && rows(composer) == before, "\(composer.engineState.pageNumber)")
        let keys = told.keys.count
        _ = composer.handleKeyDown(pageDownKey)
        #expect(composer.engineState.pageNumber == last - 2 && rows(composer) == before, "\(composer.engineState.pageNumber): \(rows(composer))")
        #expect(told.keys[keys...].filter { $0 == RimeKey.pageDown }.count == 2, "on to the last: \(told.keys[keys...])")
        for _ in 0..<5 where highlightedRow(composer) != before.last { _ = composer.handleKeyDown(arrowDown) }
        _ = composer.handleKeyDown(arrowDown)
        #expect(composer.engineState.pageNumber == last - 2 && highlightedRow(composer) == before.last,
                "\(composer.engineState.pageNumber), \(String(describing: highlightedRow(composer)))")
        let others = told.keys[keys...].filter { ![RimeKey.pageDown, RimeKey.pageUp, RimeKey.down, RimeKey.up].contains($0) }
        #expect(others.isEmpty && told.picked.isEmpty && told.cleared == 0, "\(others)")
        escaping(composer)
    }

    /// "zengjia": every page but the first with nothing shown, Page Down goes over them to the last and back to the
    /// first; every page with nothing shown, the panel has no candidates (no page has any) and Space puts the letters in.
    @Test func thePanelIsEmptyOnlyWhenNoPageShowsAnything() throws {
        let pages = pagesOf("zengjia", Composer(engine: try RimeFixture.session(), actionKey: .enter), count: 6)
        try #require(pages.count >= 3 && pages.count < 6, "\(pages.count)")
        let composer = Composer(engine: try RimeFixture.session(), actionKey: .enter)
        composer.removedCandidates = Array(pages.dropFirst().joined())
        typing("zengjia", composer)
        #expect(composer.engineState.pageNumber == 0 && rows(composer) == pages[0])
        _ = composer.handleKeyDown(pageDownKey)
        #expect(composer.engineState.pageNumber == 0 && rows(composer) == pages[0], "\(composer.engineState.pageNumber): \(rows(composer))")
        escaping(composer)
        composer.removedCandidates = Array(pages.joined())
        typing("zengjia", composer)
        #expect(rows(composer).isEmpty && composer.engineState.isComposing, "\(rows(composer))")
        #expect(putIn(composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.space, characters: " "))) == ["zengjia"])
        #expect(!composer.engineState.isComposing)
    }
}

/// librime as level one has it (wrapped, as any engine but an `EnglishWordsEngine` is), what it is given recorded: every
/// key, the candidates picked and deleted by their place on its page, how often its composition was cleared or
/// committed.
private final class KeysTold: PinyinEngine {
    let base: PinyinEngine
    private(set) var keys: [Int32] = []
    private(set) var picked: [Int] = []
    private(set) var deleted: [Int] = []
    private(set) var cleared = 0

    init(_ base: PinyinEngine) { self.base = base }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        keys.append(keycode)
        return base.processKey(keycode, mask: mask)
    }
    func takeCommit() -> String? { base.takeCommit() }
    func snapshot() -> EngineSnapshot { base.snapshot() }
    func selectCandidate(onPage index: Int) -> Bool {
        picked.append(index)
        return base.selectCandidate(onPage: index)
    }
    func deleteCandidate(onPage index: Int) -> Bool {
        deleted.append(index)
        return base.deleteCandidate(onPage: index)
    }
    func commitComposition() -> String? {
        cleared += 1
        return base.commitComposition()
    }
    var rawInput: String { base.rawInput }
    func clearComposition() {
        cleared += 1
        base.clearComposition()
    }
    func setAsciiMode(_ on: Bool) { base.setAsciiMode(on) }
    var language: Language { base.language }
}

private let arrowDown = KeyEvent(keyCode: VirtualKey.down, characters: "\u{F701}")
private let arrowUp = KeyEvent(keyCode: VirtualKey.up, characters: "\u{F700}")
private let controlForwardDelete = KeyEvent(keyCode: VirtualKey.forwardDelete, characters: "\u{F728}", modifiers: .control)

/// The row shown highlighted.
private func highlightedRow(_ composer: Composer) -> String? {
    let state = composer.engineState
    return state.candidates.indices.contains(state.highlighted) ? state.candidates[state.highlighted].text : nil
}

private let pageDownKey = KeyEvent(keyCode: VirtualKey.pageDown, characters: "\u{F72D}")
private let pageUpKey = KeyEvent(keyCode: VirtualKey.pageUp, characters: "\u{F72C}")

private func typing(_ letters: String, _ composer: Composer) {
    for ch in letters { _ = composer.handleKeyDown(key(ch)) }
}

private func escaping(_ composer: Composer) {
    _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}"))
}

private func rows(_ composer: Composer) -> [String] { composer.engineState.candidates.map(\.text) }

/// The rows labelled 1, 2 … as they are shown.
private func numberedAsShown(_ composer: Composer) -> Bool {
    composer.engineState.candidates.enumerated().allSatisfy { $0.element.label == String(($0.offset + 1) % 10) }
}

private func putIn(_ effects: [Composer.Effect]) -> [String] {
    effects.compactMap { if case let .commit(text) = $0 { return text } else { return nil } }
}

private func putIn(_ response: Composer.Response) -> [String] { putIn(response.effects) }

/// The candidates removed (`Composer.Effect.candidateRemoved`), as the session is told them.
private func removals(_ effects: [Composer.Effect]) -> [String] {
    effects.compactMap { if case let .candidateRemoved(text) = $0 { return text } else { return nil } }
}

/// The rows for `letters`, page after page (`count` at most), the composition then cleared.
private func pagesOf(_ letters: String, _ composer: Composer, count: Int) -> [[String]] {
    typing(letters, composer)
    var pages: [[String]] = []
    for _ in 0..<count {
        pages.append(rows(composer))
        if composer.engineState.isLastPage { break }
        _ = composer.handleKeyDown(pageDownKey)
    }
    escaping(composer)
    return pages
}

private func everyPage(_ letters: String, _ composer: Composer) -> [String] { pagesOf(letters, composer, count: 8).flatMap { $0 } }

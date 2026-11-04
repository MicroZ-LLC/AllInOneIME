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

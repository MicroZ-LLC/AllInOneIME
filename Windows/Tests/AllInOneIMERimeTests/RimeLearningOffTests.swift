import AllInOneIMECore
import Foundation
import Testing
@testable import AllInOneIMERime

/// A session that learns nothing (`RimeSession.learns` off: a private field's): what is picked goes in as librime puts
/// it in, and its place among the candidates is the same the next time, however it went in: picked to the end (a number,
/// a click), a part picked and Return or a tap of Shift after it, the composition committed as it is. With learning on
/// the same pick is up front the next time. Each with pinyin of its own: the learned words are the process's. In
/// `RimeEngineTests`: one test at a time in librime.
extension RimeEngineTests {
    /// `word`'s place among `pinyin`'s candidates in a new session, in the first three pages; nil past them.
    func place(of word: String, for pinyin: String) throws -> Int? {
        let s = try RimeFixture.session()
        defer { s.clearComposition() }
        type(pinyin, into: s)
        var seen: [String] = []
        for _ in 0..<3 {
            seen += s.snapshot().candidates.map(\.text)
            if let index = seen.firstIndex(of: word) { return index }
            _ = s.processKey(RimeKey.pageDown, mask: 0)
        }
        return nil
    }

    /// `pinyin` typed into `s`, its second page shown: a word of two characters there that isn't on the first, and its
    /// index on the page.
    func secondPageWord(_ pinyin: String, in s: RimeSession) throws -> (word: String, index: Int) {
        type(pinyin, into: s)
        let first = s.snapshot().candidates.map(\.text)
        _ = s.processKey(RimeKey.pageDown, mask: 0)
        let page = s.snapshot().candidates.map(\.text)
        let index = try #require(page.firstIndex { $0.count == 2 && !first.contains($0) }, "\(pinyin): \(first) | \(page)")
        return (page[index], index)
    }

    @Test func pickedToTheEndWithANumber() throws {
        let s = try RimeFixture.session()
        s.learns = false
        defer { s.learns = true }
        let (word, index) = try secondPageWord("shiyan", in: s)
        let before = try place(of: word, for: "shiyan")
        #expect(s.processKey(0x31 + Int32(index), mask: 0))  // its number
        #expect(s.takeCommit() == word && !s.snapshot().isComposing)
        #expect(try place(of: word, for: "shiyan") == before, "\(word)")
    }

    @Test func aPartPickedAndReturn() throws {
        let s = try RimeFixture.session()
        s.learns = false
        defer { s.learns = true }
        let (word, _) = try secondPageWord("jiyi", in: s)
        let before = try place(of: word, for: "jiyi")
        s.clearComposition()
        // The word for the first two syllables of four, picked by a click; the rest goes in as typed.
        type("jiyihenhao", into: s)
        var page = s.snapshot().candidates.map(\.text)
        for _ in 0..<5 where !page.contains(word) {
            _ = s.processKey(RimeKey.pageDown, mask: 0)
            page = s.snapshot().candidates.map(\.text)
        }
        let place = try #require(page.firstIndex(of: word), "\(page)")
        #expect(s.selectCandidate(onPage: place))
        #expect(s.takeCommit() == nil && s.snapshot().isComposing, "only a part picked")
        #expect(s.processKey(RimeKey.returnKey, mask: 0))
        #expect(s.takeCommit() == word + "henhao" && !s.snapshot().isComposing)
        #expect(try self.place(of: word, for: "jiyi") == before, "\(word)")
    }

    @Test func aPartPickedAndATapOfShift() throws {
        let s = try RimeFixture.session()
        s.learns = false
        defer {
            s.setAsciiMode(false)
            s.learns = true
        }
        let (word, _) = try secondPageWord("zhiyuan", in: s)
        let before = try place(of: word, for: "zhiyuan")
        s.clearComposition()
        type("zhiyuanhenduo", into: s)
        var page = s.snapshot().candidates.map(\.text)
        for _ in 0..<5 where !page.contains(word) {
            _ = s.processKey(RimeKey.pageDown, mask: 0)
            page = s.snapshot().candidates.map(\.text)
        }
        let place = try #require(page.firstIndex(of: word), "\(page)")
        #expect(s.selectCandidate(onPage: place))
        // rime-ice's Shift_L: the part picked and the letters after it, then Latin.
        _ = s.processKey(RimeKey.shiftL, mask: 0)
        _ = s.processKey(RimeKey.shiftL, mask: RimeKey.releaseMask)
        #expect(s.takeCommit() == word + "henduo" && !s.snapshot().isComposing)
        #expect(s.snapshot().isAsciiMode)
        #expect(try self.place(of: word, for: "zhiyuan") == before, "\(word)")
    }

    /// `commitComposition` (the action key on pinyin not picked yet, a command after it) on a part picked: the part, and
    /// the candidate highlighted for the rest. (librime's own commit learns nothing there either, none of it confirmed;
    /// with learning off librime doesn't commit it at all.)
    @Test func theCompositionCommittedAsItIs() throws {
        let s = try RimeFixture.session()
        s.learns = false
        defer { s.learns = true }
        let (word, _) = try secondPageWord("yishi", in: s)
        let before = try place(of: word, for: "yishi")
        s.clearComposition()
        type("yishihenzhong", into: s)
        var page = s.snapshot().candidates.map(\.text)
        for _ in 0..<5 where !page.contains(word) {
            _ = s.processKey(RimeKey.pageDown, mask: 0)
            page = s.snapshot().candidates.map(\.text)
        }
        #expect(s.selectCandidate(onPage: try #require(page.firstIndex(of: word), "\(page)")))
        let rest = try #require(s.snapshot().candidates.first?.text)
        #expect(s.commitComposition() == word + rest && !s.snapshot().isComposing)
        #expect(try place(of: word, for: "yishi") == before, "\(word)")
    }

    /// Punctuation after the pinyin: the word highlighted and the mark, as librime puts them in.
    @Test func punctuationAfterThePinyin() throws {
        let s = try RimeFixture.session()
        s.learns = false
        defer { s.learns = true }
        type("nihao", into: s)
        let first = try #require(s.snapshot().candidates.first?.text)
        #expect(s.processKey(0x2C, mask: 0))  // ","
        #expect(s.takeCommit() == first + "，" && !s.snapshot().isComposing)
        // Space and the number keys on a page, and Return with nothing picked, as with learning on.
        type("nihao", into: s)
        #expect(s.processKey(RimeKey.space, mask: 0) && s.takeCommit() == first)
        type("nihao", into: s)
        #expect(s.processKey(RimeKey.returnKey, mask: 0) && s.takeCommit() == "nihao")
    }

    /// The same pick as `pickedToTheEndWithANumber`'s with learning on: up front the next time.
    @Test func withLearningOnThePickIsUpFront() throws {
        let s = try RimeFixture.session()
        let (word, index) = try secondPageWord("gongshi", in: s)
        let before = try #require(try place(of: word, for: "gongshi"))
        #expect(before >= s.snapshot().candidates.count)
        #expect(s.processKey(0x31 + Int32(index), mask: 0))
        #expect(s.takeCommit() == word)
        let after = try #require(try place(of: word, for: "gongshi"))
        #expect(after < 3 && after < before, "\(word): \(before) → \(after)")
    }
}

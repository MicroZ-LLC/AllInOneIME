import Foundation
import Testing
@testable import AllInOneIMECore

/// `SortedWordList` finds a word in a sorted file of them by halving it.
struct SortedWordListTests {
    static func list(_ words: [String]) -> SortedWordList {
        SortedWordList(lines: Data(words.map { $0 + "\n" }.joined().utf8))
    }

    @Test func everyWordIsFoundAndNothingElse() {
        let words = ["a-b", "aal", "aalii", "ab", "abc", "b", "ba", "zyzzogeton"]
        let list = Self.list(words)
        for word in words { #expect(list.contains(word), "\(word)") }
        // Before the first, after the last, between two, a prefix of one, one with a letter added, other bytes.
        for word in ["", "-", "a", "aa", "aali", "aaliii", "abcd", "bb", "c", "zz", "zzz", "Aal", "aal\n", "aal ", "é"] {
            #expect(!list.contains(word), "\(word.debugDescription)")
        }
        #expect(list.count == words.count && list.words == words && !list.isEmpty)
    }

    /// Every size from none to a few, and every word in each: the halving ends well wherever the middle falls.
    @Test func everySizeOfList() {
        let all = (0..<40).map { String(format: "w%03d", $0 * 3) }
        for size in 0...all.count {
            let words = Array(all.prefix(size))
            let list = Self.list(words)
            #expect(words.allSatisfy(list.contains), "\(size) words")
            #expect(!(0..<(size * 3 + 3)).contains { $0 % 3 != 0 && list.contains(String(format: "w%03d", $0)) },
                    "\(size) words: one not in the list found")
        }
    }

    /// A file that isn't there (a shell that didn't ship the core's resources) is an empty list, not a crash.
    @Test func aMissingFileIsAnEmptyList() {
        let list = SortedWordList(contentsOf: URL(fileURLWithPath: "/nonexistent/RedactionWords.txt"))
        #expect(list.isEmpty && list.count == 0 && !list.contains("aal"))
        #expect(SortedWordList(contentsOf: nil).isEmpty)
    }

    /// The last line without its LF is still a word.
    @Test func theLastLineWithoutItsNewline() {
        let list = SortedWordList(lines: Data("abc\nabd\nxyz".utf8))
        #expect(list.contains("abc") && list.contains("abd") && list.contains("xyz") && !list.contains("xy"))
    }
}

import Foundation

// MARK: - What is sent of the text before the caret

extension Autocomplete {
    /// The most of the text before the caret's line that goes with a request (`sent`): the most recent sentences in the
    /// line's language, this many characters at most.
    public static let poolLimit = 200

    /// The languages the text before the caret is sorted into, sentence by sentence (`pool(of:)`), by the scripts of their
    /// letters (Unicode code points): a sentence is in the first of them it has a letter of. Japanese (kana) before
    /// Chinese, though its sentences have kanji; Korean (Hangul) before it too; Chinese (Han) before the rest, so a Chinese
    /// sentence with English words in it is Chinese ("我原本计划明天去hiking，"); Latin letters last, one pool for English,
    /// French and the other languages written in them. Letters of a script that isn't here are one pool (`otherPool`).
    /// Another language: a line here.
    static let pools: [(name: String, scripts: [ClosedRange<UInt32>])] = [
        ("Japanese", [0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F]),
        ("Korean", [0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7FF, 0xFFA0...0xFFDC]),
        ("Chinese", [0x3005...0x3007, 0x3021...0x3029, 0x3038...0x303B, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                     0x20000...0x3FFFF]),
        ("Hindi", [0x0900...0x097F, 0xA8E0...0xA8FF]),
        ("Bengali", [0x0980...0x09FF]),
        ("Gurmukhi", [0x0A00...0x0A7F]),
        ("Gujarati", [0x0A80...0x0AFF]),
        ("Tamil", [0x0B80...0x0BFF]),
        ("Telugu", [0x0C00...0x0C7F]),
        ("Kannada", [0x0C80...0x0CFF]),
        ("Malayalam", [0x0D00...0x0D7F]),
        ("Thai", [0x0E00...0x0E7F]),
        ("Arabic", [0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF]),
        ("Hebrew", [0x0590...0x05FF, 0xFB1D...0xFB4F]),
        ("Greek", [0x0370...0x03FF, 0x1F00...0x1FFF]),
        ("Cyrillic", [0x0400...0x052F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F]),
        ("Armenian", [0x0530...0x058F]),
        ("Georgian", [0x10A0...0x10FF, 0x1C90...0x1CBF, 0x2D00...0x2D2F]),
        ("Latin", [0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F, 0x1E00...0x1EFF, 0xFF21...0xFF3A, 0xFF41...0xFF5A]),
    ]

    /// The pool of letters of a script none of `pools` has.
    static let otherPool = "Other"

    /// What a request sends of `before`, the text before the caret (`Context.before`): the caret's line, whole, and before
    /// it the most recent sentences (`sentences(in:)`) in that line's language (`pool(of:)` of `languageText`, which the
    /// examples and the space at the answer's start go by too), `poolLimit` characters at most with what is between them,
    /// in their order. Sentences in other languages are left out: with a Chinese paragraph above an English line, the
    /// model went on with the English in Chinese. Where some were, a line break, so that the model doesn't read the two
    /// around them as one; between two that were next to each other, what was there. The most recent sentence alone
    /// longer than that: its end. Text with no letters (a date, a number) is in no language, and goes with any.
    static func sent(_ before: String) -> String {
        let lineStart = before.lastIndex(where: \.isNewline).map(before.index(after:)) ?? before.startIndex
        let language = pool(of: languageText(before))
        var earlier = ""
        // From the most recent sentence back: where what is taken starts, and whether one was left out since.
        var next = lineStart, skipped = false
        for sentence in sentences(in: before[..<lineStart]).reversed() {
            let text = before[sentence]
            if let language, let own = pool(of: text), own != language {
                skipped = true
                continue
            }
            let between = skipped ? "\n" : String(before[sentence.upperBound..<next])
            let room = poolLimit - earlier.count - between.count
            guard text.count <= room else {
                if earlier.isEmpty, room > 0 { earlier = String(text.suffix(room)) + between }
                break
            }
            earlier = String(text) + between + earlier
            (next, skipped) = (sentence.lowerBound, false)
        }
        return earlier + before[lineStart...]
    }

    /// The pool of `text` (`pools`): the first whose script it has a letter of, `otherPool` where it has letters of none
    /// of them. Nil: no letters (a date, a number, marks).
    static func pool(of text: some StringProtocol) -> String? {
        var found: Int?, letters = false
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters = true
            if let index = pools.prefix(found ?? pools.count).firstIndex(where: { $0.scripts.contains { $0.contains(scalar.value) } }) {
                found = index
                if index == 0 { break }
            }
        }
        return found.map { pools[$0].name } ?? (letters ? otherPool : nil)
    }

    /// The sentences of `text`, without the spaces around them: each ends at a line break, or once it has a letter, after
    /// a mark that ends one (`endOfSentence`). "1. 准备材料" is one.
    static func sentences(in text: Substring) -> [Range<String.Index>] {
        var sentences: [Range<String.Index>] = []
        var start: String.Index?, end = text.startIndex, letter = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isNewline {
                if let start { sentences.append(start..<end) }
                (start, letter) = (nil, false)
            } else if !character.isWhitespace {
                let first = start ?? index
                letter = letter || character.isLetter
                if letter, let close = endOfSentence(in: text, at: index) {
                    sentences.append(first..<close)
                    (start, letter, index) = (nil, false, close)
                    continue
                }
                (start, end) = (first, text.index(after: index))
            }
            index = text.index(after: index)
        }
        if let start { sentences.append(start..<end) }
        return sentences
    }

    /// Marks that end a sentence wherever they are (Chinese and Japanese, full width, Devanagari), and those that end
    /// one only before a space, a Chinese or Japanese character or the end ("3.5", "example.com" go on).
    static let endsAnywhere: Set<Character> = ["。", "！", "？", "．", "｡", "।", "॥"]
    static let endsBeforeASpace: Set<Character> = [".", "!", "?"]
    static let closers: Set<Character> = ["\"", "'", "”", "’", "」", "』", "）", ")", "]", "】", "》"]

    /// Where the sentence ends if the character at `index` in `text` is a mark that ends it: after the mark, the marks
    /// right after it ("?!", "。。。") and the closing quotes and brackets. Nil where it doesn't end one.
    static func endOfSentence(in text: Substring, at index: String.Index) -> String.Index? {
        let mark = text[index]
        guard endsAnywhere.contains(mark) || endsBeforeASpace.contains(mark) else { return nil }
        var end = text.index(after: index)
        while end < text.endIndex, endsAnywhere.contains(text[end]) || endsBeforeASpace.contains(text[end]) || closers.contains(text[end]) {
            end = text.index(after: end)
        }
        guard endsAnywhere.contains(mark) || end == text.endIndex || text[end].isWhitespace || text[end].isWide else { return nil }
        return end
    }
}

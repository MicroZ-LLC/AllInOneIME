import Foundation

/// A list of words searched where it lies: the bytes of a file of them, sorted by their bytes, a word a line (LF, the
/// last one too, as Scripts/make-redaction-words.swift writes RedactionWords.txt; a last line without it still counts).
/// A lookup halves the file until it meets the word (about 20 steps for the 234,000 English words), so nothing is
/// parsed or copied: the file is mapped, and only the pages a lookup touches are read (a `Set` of the words took tens
/// of milliseconds to build and megabytes to keep).
struct SortedWordList: Sendable {
    private let lines: Data

    /// `lines`: words sorted by their bytes, each followed by "\n".
    init(lines: Data) {
        self.lines = lines
    }

    /// The list in the file at `url`, mapped; empty when it can't be read.
    init(contentsOf url: URL?) {
        self.init(lines: url.flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) } ?? Data())
    }

    /// Whether `word` is one of the lines, byte for byte.
    func contains(_ word: String) -> Bool {
        var key = word
        return !key.isEmpty && key.withUTF8 { key in lines.withUnsafeBytes { Self.search(key, in: $0) } }
    }

    /// Whether there are none (the file was missing).
    var isEmpty: Bool { lines.isEmpty }

    /// How many words there are: a line each, the last one counted too when it has no LF.
    var count: Int {
        lines.withUnsafeBytes { bytes in
            let ended = bytes.reduce(0) { $1 == Self.newline ? $0 + 1 : $0 }
            return bytes.last == nil || bytes.last == Self.newline ? ended : ended + 1
        }
    }

    /// Every word, in order.
    var words: [String] {
        lines.split(separator: Self.newline).map { String(decoding: $0, as: UTF8.self) }
    }

    private static let newline = UInt8(ascii: "\n")

    /// Binary search over byte offsets: `low` is always where a line starts, and `high` where one starts or the end.
    /// The line around the middle is compared with `key`; the half that can't hold it is dropped, that line with it.
    private static func search(_ key: UnsafeBufferPointer<UInt8>, in bytes: UnsafeRawBufferPointer) -> Bool {
        var low = 0
        var high = bytes.count
        while low < high {
            var start = (low + high) / 2
            while start > low && bytes[start - 1] != newline { start -= 1 }
            var end = start
            while end < high && bytes[end] != newline { end += 1 }
            switch compare(key, UnsafeRawBufferPointer(rebasing: bytes[start..<end])) {
            case 0: return true
            case ..<0: high = start
            default: low = end + 1
            }
        }
        return false
    }

    /// Negative when `key` sorts before `line` by bytes, positive after, 0 when they're the same.
    private static func compare(_ key: UnsafeBufferPointer<UInt8>, _ line: UnsafeRawBufferPointer) -> Int {
        for (left, right) in zip(key, line) where left != right {
            return Int(left) - Int(right)
        }
        return key.count - line.count
    }
}

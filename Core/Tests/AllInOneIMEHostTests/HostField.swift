import Foundation
import AllInOneIMECore
import AllInOneIMETestSupport

/// The field as its host's text-input API tells it (NSTextInputClient's calls on the Mac) under a profile: the text with
/// the marked part where the caret is, in UTF-16 offsets. What `FakeHost` holds is the truth; this is what a shell can
/// learn of it, each call counted.
final class HostField {
    let host: FakeHost
    let profile: HostProfile
    /// The calls made since the count was last taken (`takeCalls`).
    private(set) var calls = HostCallCount()
    /// The ranges as they were when the turn began, told during it where the profile tells them stale.
    private var turn: (selected: Range<Int>, marked: Range<Int>?)?

    init(host: FakeHost, profile: HostProfile) {
        (self.host, self.profile) = (host, profile)
    }

    // MARK: The truth

    /// The text shown: the document with the marked text at the caret.
    var shown: NSString {
        let document = host.document as NSString
        guard !host.marked.isEmpty else { return document }
        return document.replacingCharacters(in: NSRange(location: host.caret, length: 0), with: host.marked) as NSString
    }

    var markedNow: Range<Int>? {
        host.marked.isEmpty ? nil : host.caret..<host.caret + (host.marked as NSString).length
    }

    /// The selection, or the caret (at the marked text's end while there is some).
    var selectedNow: Range<Int> {
        if let marked = markedNow { return marked.upperBound..<marked.upperBound }
        return host.selection ?? host.caret..<host.caret
    }

    // MARK: Turns

    /// An event begins: the ranges as they are now are what a stale profile tells until it ends.
    func beginTurn() {
        turn = profile.staleRanges ? (selectedNow, markedNow) : nil
    }

    func endTurn() { turn = nil }

    // MARK: What the shell can ask

    /// The text's length (0 where the host tells none).
    func length() -> Int {
        calls.add(.length)
        return profile.tellsLength ? shown.length : 0
    }

    /// The selection or the caret; nil: the host tells none (NSNotFound).
    func selectedRange() -> Range<Int>? {
        calls.add(.selectedRange)
        guard profile.tellsRanges else { return nil }
        return turn?.selected ?? selectedNow
    }

    /// The marked text's range; nil: none (NSNotFound).
    func markedRange() -> Range<Int>? {
        calls.add(.markedRange)
        guard profile.tellsRanges else { return nil }
        return turn.map(\.marked) ?? markedNow
    }

    /// The shown text in `range`; nil where the host tells none: past the end, beyond its reach of the caret.
    func substring(_ range: Range<Int>) -> String? {
        calls.add(.substring)
        return text(in: range)
    }

    /// `substring`'s answer, not counted (the reads a replacement makes are its own).
    func text(in range: Range<Int>) -> String? {
        let text = shown
        guard range.lowerBound >= 0, range.upperBound <= text.length else { return nil }
        if let reach = profile.substringReach {
            let caret = (turn?.selected ?? selectedNow).lowerBound
            guard range.lowerBound >= caret - reach, range.upperBound <= caret + reach, reach > 0 else { return nil }
        }
        return text.substring(with: NSRange(location: range.lowerBound, length: range.count))
    }

    /// The calls since the last time, and the count started again.
    func takeCalls() -> HostCallCount {
        defer { calls = HostCallCount() }
        return calls
    }
}

/// How many of each call a shell made of the host (`HostField`).
struct HostCallCount: Equatable, Sendable, CustomStringConvertible {
    private var counts: [HostCall: Int] = [:]

    mutating func add(_ call: HostCall) { counts[call, default: 0] += 1 }

    subscript(call: HostCall) -> Int {
        call == .total ? counts.values.reduce(0, +) : counts[call] ?? 0
    }

    var description: String {
        HostCall.allCases.filter { $0 != .total && self[$0] > 0 }.map { "\($0.rawValue) \(self[$0])" }.joined(separator: ", ")
    }
}

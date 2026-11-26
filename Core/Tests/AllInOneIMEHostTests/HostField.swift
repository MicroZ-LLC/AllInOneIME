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
    /// How the host answers beyond what its profile tells: slowly, or with garbage (`HostAnswers`).
    var answers = HostAnswers()
    /// How long the calls since the count was last taken took (`answers.latency`, the run's own time: nothing sleeps).
    private(set) var spent: TimeInterval = 0

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
        count(.length)
        let told = profile.tellsLength ? shown.length : 0
        return answers.garbled(told) { [shown.length + 50, Int(Int32.max), -1, 0] }
    }

    /// The selection or the caret; nil: the host tells none (NSNotFound).
    func selectedRange() -> Range<Int>? {
        count(.selectedRange)
        let told = profile.tellsRanges ? turn?.selected ?? selectedNow : nil
        let end = shown.length
        return answers.garbled(told) { [nil, end + 10..<end + 12, 0..<end + 100, Int(Int32.max)..<Int(Int32.max)] }
    }

    /// The marked text's range; nil: none (NSNotFound).
    func markedRange() -> Range<Int>? {
        count(.markedRange)
        let told = profile.tellsRanges ? turn.map(\.marked) ?? markedNow : nil
        return answers.garbled(told) { [0..<5, shown.length..<shown.length + 3, nil] }
    }

    /// The shown text in `range`; nil where the host tells none: past the end, beyond its reach of the caret.
    func substring(_ range: Range<Int>) -> String? {
        count(.substring)
        return answers.garbled(text(in: range)) { [nil, "", "garbage 😀", String(repeating: "x", count: range.count + 7)] }
    }

    /// `substring`'s answer, not counted (the reads a replacement makes are its own).
    func text(in range: Range<Int>) -> String? {
        let text = shown
        if profile.substringClips {
            let caret = (turn?.selected ?? selectedNow).lowerBound, reach = profile.substringReach ?? text.length
            let part = range.clamped(to: max(caret - reach, 0)..<max(min(caret + reach, text.length), 0))
            return part.isEmpty ? nil : text.substring(with: NSRange(location: part.lowerBound, length: part.count))
        }
        guard range.lowerBound >= 0, range.upperBound <= text.length else { return nil }
        if let reach = profile.substringReach {
            let caret = (turn?.selected ?? selectedNow).lowerBound
            guard range.lowerBound >= caret - reach, range.upperBound <= caret + reach, reach > 0 else { return nil }
        }
        return text.substring(with: NSRange(location: range.lowerBound, length: range.count))
    }

    /// The calls since the last time, and the count started again (the time they took too).
    func takeCalls() -> HostCallCount {
        defer { (calls, spent) = (HostCallCount(), 0) }
        return calls
    }

    private func count(_ call: HostCall) {
        calls.add(call)
        spent += answers.latency[call] ?? 0
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

/// How a host answers beyond what its profile tells (`HostField.answers`): each call taking this long (a host that
/// answers late: 50–500 ms, a busy web process, a hung app), or now and then garbage (a range past the text, a length of
/// 2147483647, a substring of another length than asked, nil), from a seed. What the input method must survive without
/// freezing the typing or crashing: no app is listed for it.
struct HostAnswers {
    var latency: [HostCall: TimeInterval] = [:]
    /// Garbage one call in `garbageEvery` (0: never), picked from the call's own list by this generator.
    var garbageEvery = 0
    var random = HostStress.SplitMix(seed: 1)

    /// `told`, or one of `garbage()`'s answers where this call is one to garble.
    mutating func garbled<T>(_ told: T, _ garbage: () -> [T]) -> T {
        guard garbageEvery > 0, random.next(below: garbageEvery) == 0 else { return told }
        return random.pick(garbage())
    }
}

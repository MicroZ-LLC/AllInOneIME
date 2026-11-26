import Foundation
import AllInOneIMECore

/// An event the host hands the input method: a key down (at `time`, its own) or a modifier change (its time in it).
enum HostEvent {
    case key(KeyEvent, time: TimeInterval)
    case modifiers(ModifierChange, code: UInt16)
}

/// What comes later on a run's clock (`HostRun.now`), in order: copies of events on their way (`HostProfile.copyDelay`),
/// the session's timers, Caps Lock's lock going off as the input method asked.
struct HostAgenda {
    enum Item {
        case copy(HostEvent)
        case timer(TimerID)
        case lockOff
    }

    private var items: [(due: TimeInterval, order: Int, item: Item)] = []
    private var added = 0

    mutating func add(_ item: Item, at due: TimeInterval) {
        added += 1
        items.append((due, added, item))
    }

    /// The first item due by `time` (the earliest; of two at once, the one added first), taken off.
    mutating func next(until time: TimeInterval) -> (due: TimeInterval, item: Item)? {
        guard let index = items.indices.filter({ items[$0].due <= time })
            .min(by: { (items[$0].due, items[$0].order) < (items[$1].due, items[$1].order) }) else { return nil }
        let next = items.remove(at: index)
        return (next.due, next.item)
    }

    /// When the last copy still on its way comes; nil: none is.
    var lastCopy: TimeInterval? {
        items.filter { if case .copy = $0.item { true } else { false } }.map(\.due).max()
    }
}

/// The characters the field should hold, for `EXPECT nolost`: its text when it was last set (`TEXT`, `APP clears`), and
/// what was committed since (by the session, by the app typing a key it had, by the host itself: a page committing the
/// marked text it shows), less what was taken out (⌫, a replacement, the app's undo). What the session committed and the
/// field dropped counts too: it is lost.
struct CommitLedger {
    /// How many of each character the field should hold.
    private(set) var expected: [Character: Int] = [:]
    /// The characters committed since the field was last set: the ones `nolost` checks.
    private(set) var committed: Set<Character> = []
    /// What the session put in and the field dropped (it had lost the focus): never in it.
    private(set) var dropped = ""

    /// The field set to `text`: what it holds from now on.
    mutating func reset(to text: String) {
        expected = [:]
        committed = []
        dropped = ""
        for character in text { expected[character, default: 0] += 1 }
    }

    mutating func put(_ text: String) {
        for character in text {
            expected[character, default: 0] += 1
            committed.insert(character)
        }
    }

    /// What the session put in that the field dropped: it should hold it all the same.
    mutating func drop(_ text: String) {
        dropped += text
        put(text)
    }

    mutating func take(_ text: String) {
        for character in text where expected[character, default: 0] > 0 { expected[character, default: 0] -= 1 }
    }

    /// What `document` holds of the characters put in that it shouldn't: each with how many it has and should have.
    func mismatches(in document: String) -> [(character: Character, has: Int, should: Int)] {
        var has: [Character: Int] = [:]
        for character in document { has[character, default: 0] += 1 }
        return committed.sorted().compactMap { character in
            let (found, wanted) = (has[character] ?? 0, expected[character] ?? 0)
            return found == wanted ? nil : (character, found, wanted)
        }
    }
}

/// A check that failed in a run: the scenario's line and what was wrong.
struct HostFailure: Equatable, CustomStringConvertible {
    var line: Int
    var message: String

    var description: String { "line \(line): \(message)" }
}

/// The settings the session reads, changed by nothing during a run; a class so the services' closures share it.
final class HostSettings: @unchecked Sendable {
    var config: Config

    init(_ config: Config) { self.config = config }
}

/// The run's clock and what the pointer did, read by the services' closures.
final class HostClock: @unchecked Sendable {
    /// Seconds of uptime on the run's clock.
    var now: TimeInterval = 100
    /// A click came since the last event the session had: the caret may have moved (`SessionServices.pointerUsedWithin`).
    var clicked = false
}

/// The host calls one key, modifier change or timer made (`HostRun.everyTurn`), and how long they took.
struct HostTurnCalls: Sendable {
    var line: Int
    var what: String
    var calls: HostCallCount
    var spent: TimeInterval
}

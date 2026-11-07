import Foundation

/// The keys a shell posts to the app itself, and the order they reach it in: one the input method gave back after the
/// selection read (`PlatformAction.passKey`), and the keys behind it (`PlatformAction.replayKey`, and every key typed
/// while one posted is on its way). From the moment a key is posted until it comes back to the input method (the app
/// hands each key over, in its order: then the app has it), a key typed goes behind it, posted too, never ahead. A key
/// posted carries its mark (`Mark`) in the event: one given to the app goes through untouched, one replayed is answered
/// as typed, at its place; neither is posted again. One that never comes back (the focus went to another app, a menu
/// took it) is given up after `timeout`. A shell keeps one for all its fields, on the keys' thread.
public struct KeysOnTheWay: Sendable {
    /// What a posted key carries, so that it is known when it comes back: what it is, and its number.
    public enum Mark: Equatable, Sendable {
        /// Given to the app: it goes through untouched.
        case passed(UInt32)
        /// Behind the keys posted before it: the input method answers it as typed.
        case replayed(UInt32)

        /// "AIOP" and "AIOR": what the event's own field (the Mac's `eventSourceUserData`) holds above the number.
        static let passedTag: Int64 = 0x4149_4F50
        static let replayedTag: Int64 = 0x4149_4F52

        /// As the event carries it.
        public var userData: Int64 {
            switch self {
            case let .passed(number): Self.passedTag << 32 | Int64(number)
            case let .replayed(number): Self.replayedTag << 32 | Int64(number)
            }
        }

        /// The mark an event carries (nil: none of these, a key typed).
        public init?(userData: Int64) {
            let number = UInt32(truncatingIfNeeded: userData)
            switch userData >> 32 {
            case Self.passedTag: self = .passed(number)
            case Self.replayedTag: self = .replayed(number)
            default: return nil
            }
        }

        var number: UInt32 {
            switch self {
            case let .passed(number), let .replayed(number): number
            }
        }
    }

    /// What the shell does with a key down that came in (`arrived`).
    public enum Answer: Equatable, Sendable {
        /// A key given to the app, back: through to the app, untouched.
        case toApp
        /// The input method's to answer, as typed: a key at its place.
        case handle
        /// Typed while a key posted is on its way: taken from the app and posted behind it (`post(passed: false)`).
        case behind
    }

    /// How long a key posted is waited for (seconds).
    public static let timeout: TimeInterval = 1

    /// The keys posted and not back yet, in the order posted: their numbers, and when.
    private var onTheWay: [(number: UInt32, posted: TimeInterval)] = []
    private var next: UInt32 = 0

    public init() {}

    /// Whether a key posted is on its way at `now` (not back, not given up).
    public func isWaiting(now: TimeInterval) -> Bool {
        onTheWay.contains { now - $0.posted <= Self.timeout }
    }

    /// A key posted at `now` (given to the app: `passed`; else replayed): the mark it carries.
    public mutating func post(passed: Bool, now: TimeInterval) -> Mark {
        next &+= 1
        onTheWay.append((next, now))
        return passed ? .passed(next) : .replayed(next)
    }

    /// A key down came in at `now` carrying `mark` (nil: typed): what is done with it. One posted is back, and so are all
    /// posted before it (they came first, or never will): none of them is waited for any longer.
    public mutating func arrived(_ mark: Mark?, now: TimeInterval) -> Answer {
        guard let mark else {
            onTheWay.removeAll { now - $0.posted > Self.timeout }
            return onTheWay.isEmpty ? .handle : .behind
        }
        if let at = onTheWay.firstIndex(where: { $0.number == mark.number }) { onTheWay.removeSubrange(...at) }
        if case .passed = mark { return .toApp }
        return .handle
    }
}

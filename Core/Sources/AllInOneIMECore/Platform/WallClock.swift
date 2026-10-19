import Foundation

/// The time of day, for what the core dates or compares with now: a reminder's 「明天」, how long ago a question was
/// asked, a command's last use, when a background task was started. A shell or a test can give one that it moves
/// itself. (Not Swift's `Clock`, which measures intervals and sleeps: `ManualClock` in the tests' support is one.)
public protocol WallClock: Sendable {
    /// Now.
    var now: Date { get }
}

/// The system's clock, `Date()`: the same on every platform.
public struct SystemWallClock: WallClock {
    public init() {}
    public var now: Date { Date() }
}

/// A clock that says what it was told (`now`), until it is told otherwise: for tests.
public final class FixedWallClock: WallClock {
    private let time: Locked<Date>

    public init(_ now: Date) { time = Locked(initialState: now) }

    public var now: Date {
        get { time.withLock { $0 } }
        set { time.withLock { $0 = newValue } }
    }

    /// Moves it on (back, when `seconds` is negative).
    public func advance(by seconds: TimeInterval) { time.withLock { $0 += seconds } }
}

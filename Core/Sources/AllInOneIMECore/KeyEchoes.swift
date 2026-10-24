import Foundation

/// Tells a key down handed over a second time from a new one, and what the first was answered. The owner typed "#1" in
/// 0.6.7, then "7": the field had "#17" and the session's token "#" and three characters, a key the field got once
/// reaching the input method twice. Chromium and Electron hand every modifier change over twice (`ModifierEchoes`); a key
/// down handed over again would be that, or anything else that delivers one event twice. The shell asks first, before
/// anything else sees the key (macOS: `AllInOneIMEInputController.handleKeyDown`), the same for every text field: a copy
/// may reach another one.
///
/// A copy is the same event again: the same key, characters, modifiers and repeat, at the very same time, no more than
/// `window` after the first came. That is never a new key: a held key's repeats come at later times (and say they are
/// repeats), and two presses are never at one time (the clock ticks every few tens of nanoseconds). However many keys
/// came between, within `window` a copy is one (a busy page hands it over after the keys typed meanwhile). The copy is
/// answered as the first was (taken or the app's) and nothing else sees it. A key at no time (0) or at one still to come
/// (a tool's, in another unit or from another clock) is never taken for a copy, nor kept.
public struct KeyEchoes: Equatable, Sendable {
    /// How many key downs it keeps: far more than come within `window` (a fast typist's ten a second, a held key's
    /// repeats thirty); past that, the one that came first is forgotten.
    public static let kept = 64

    /// How long after the first a copy may come, in seconds: Chromium's copies of a modifier change come within tens of
    /// milliseconds, a busy page's after hundreds, about a second at most (`ModifierEchoes`). A key down that comes again
    /// later is one of its own.
    public static let window: TimeInterval = 2

    /// A key down as the shell has it: `keyCode` the key, `characters` what it types, `modifiers` the event's modifier
    /// flags with every bit it has (the Mac's `NSEvent.modifierFlags.rawValue`), `isRepeat` sent again because the key is
    /// held, `timestamp` its time (the Mac's `NSEvent.timestamp`).
    public struct Key: Equatable, Sendable {
        public var keyCode: UInt16
        public var characters: String
        public var modifiers: UInt
        public var isRepeat: Bool
        public var timestamp: TimeInterval

        public init(keyCode: UInt16, characters: String, modifiers: UInt, isRepeat: Bool = false, timestamp: TimeInterval) {
            self.keyCode = keyCode
            self.characters = characters
            self.modifiers = modifiers
            self.isRepeat = isRepeat
            self.timestamp = timestamp
        }
    }

    private struct Answered: Equatable, Sendable {
        var key: Key
        /// When it came, on the clock `now` is on.
        var came: TimeInterval
        var handled: Bool
    }

    /// The key downs answered within `window`, the one that came first first.
    private var answered: [Answered] = []

    public init() {}

    /// `key` came, at `now` on the clock its time is on (the Mac's `ProcessInfo.systemUptime`): what the first was
    /// answered when it is a copy (true: the input method took it), to answer the same and do nothing else; nil when it
    /// is new, to be handled, then told (`answered`).
    public func copy(of key: Key, now: TimeInterval) -> Bool? {
        guard Self.keepable(key, now: now) else { return nil }
        return answered.last { $0.key == key && $0.came <= now && now - $0.came <= Self.window }?.handled
    }

    /// A new key down came at `now` and was answered `handled`: kept for its copies.
    public mutating func answered(_ key: Key, now: TimeInterval, handled: Bool) {
        answered.removeAll { $0.came > now || now - $0.came > Self.window }
        guard Self.keepable(key, now: now) else { return }
        answered.append(Answered(key: key, came: now, handled: handled))
        if answered.count > Self.kept { answered.removeFirst(answered.count - Self.kept) }
    }

    /// A key at a time of its own, not yet to come.
    private static func keepable(_ key: Key, now: TimeInterval) -> Bool { key.timestamp > 0 && key.timestamp <= now }
}

import AppKit

/// The keys the input method posts itself (the input method's `TerminalPaste`: a kept image pasted with the app's own
/// paste key, ⌃V again, text with line breaks pasted into a terminal) told from the user's, so that each one reaches the
/// app and none is answered as the user's. A posted key carries a mark (`marker`, its event's source user data), but only
/// the key tap sees it: an app hands a key to the input method in the input method's own process, and an event's data sent
/// between processes keeps its key, modifiers and time, not the mark. Since 0.6.8.2 a ⌃V of its own handed over was
/// answered as the user's: in a terminal clipboard history opened again instead of the image going in, and ⌃V again only
/// showed the panel again.
///
/// So each key posted is remembered (its key and modifiers, when it was posted), and is the first like it within
/// `window`: at the key tap the marked one, its time kept; handed over by the app, the one with that time (an event's
/// copies keep it: `KeyEchoes`), or where the tap didn't see it or no time is told, the first posted like it, never a key
/// from before it was posted. Each once: a key like it the user presses after is the user's (⌃V opens clipboard
/// history), at the tap (no mark) and handed over (a time of its own). The input method keeps one, on the main thread
/// (`TerminalPaste`), where its keys and posts all are.
public struct PostedKeys: Sendable {
    /// The mark a posted key carries ("AIOI", its event's source user data): the key tap reads it.
    public static let marker: Int64 = 0x4149_4F49

    /// How long after it was posted a key may come: the tap has it at once, an app busy with output hands it over late
    /// (as `KeyEchoes.window`). Past that, a key like it is the user's.
    public static let window: TimeInterval = 2

    /// How much earlier than when it was posted a key's time may be and still be it (the two clocks read apart).
    static let earlier: TimeInterval = 0.01

    /// A key down: `keyCode` the key, `modifiers` ⌘ ⌥ ⌃ ⇧ as `CGEventFlags` and `NSEvent.ModifierFlags` both have them
    /// (any other bit dropped: Caps Lock, a side, a posted key's own), `timestamp` its time (the Mac's
    /// `NSEvent.timestamp`, on `ProcessInfo.systemUptime`'s clock; 0: none told).
    public struct Key: Equatable, Sendable {
        public var keyCode: UInt16
        public var modifiers: UInt64
        public var timestamp: TimeInterval

        public init(keyCode: UInt16, modifiers: UInt64, timestamp: TimeInterval = 0) {
            self.keyCode = keyCode
            self.modifiers = modifiers & Self.held
            self.timestamp = timestamp
        }

        /// `event`'s key, as the app hands it over, or as the key tap has it (`NSEvent(cgEvent:)`, the same time).
        public init(_ event: NSEvent) {
            self.init(keyCode: event.keyCode, modifiers: UInt64(event.modifierFlags.rawValue), timestamp: event.timestamp)
        }

        /// ⇧ ⌃ ⌥ ⌘: the same bits in `CGEventFlags` and `NSEvent.ModifierFlags`.
        public static let held = CGEventFlags([.maskShift, .maskControl, .maskAlternate, .maskCommand]).rawValue
    }

    /// Whether `event` (at the key tap) carries the mark of a key posted here.
    public static func isMarked(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    /// A key posted: when (`at`); whether the tap has seen it, and its time there (0: none), then; whether the app has
    /// handed it over.
    private struct Posted: Sendable {
        var keyCode: UInt16
        var modifiers: UInt64
        var at: TimeInterval
        var seenAtTap = false
        var time: TimeInterval = 0
        var handedOver = false

        func isLike(_ key: Key) -> Bool { keyCode == key.keyCode && modifiers == key.modifiers }
    }

    /// The keys posted within `window`, the first posted first.
    private var posted: [Posted] = []

    public init() {}

    /// V (or any key) with `modifiers` is about to be posted, at `now` (`ProcessInfo.systemUptime`).
    public mutating func posting(keyCode: UInt16, modifiers: UInt64, now: TimeInterval) {
        forget(now)
        posted.append(Posted(keyCode: keyCode, modifiers: modifiers & Key.held, at: now))
    }

    /// A key down at the key tap, `marked` (`isMarked`) or not: whether it is one posted here (it goes on untouched, never
    /// answered). The marked one is, and the first posted like it the tap hasn't seen keeps its time, for when the app hands
    /// it over (one posted longer ago, by its mark alone, as from now). A key not marked never is: the user's, whatever was
    /// posted.
    public mutating func atTap(_ key: Key, marked: Bool, now: TimeInterval) -> Bool {
        guard marked else { return false }
        forget(now)
        if let index = posted.firstIndex(where: { !$0.seenAtTap && $0.isLike(key) }) {
            posted[index].seenAtTap = true
            posted[index].time = key.timestamp
        } else {
            posted.append(Posted(keyCode: key.keyCode, modifiers: key.modifiers, at: now, seenAtTap: true, time: key.timestamp))
        }
        return true
    }

    /// A key down the app handed over (the Mac's IMK), `marked` (never, from another process): whether it is one posted
    /// here (it goes on to the app, never answered). The one the tap saw, by its time, its copies too (a page hands a key
    /// over twice: `KeyEchoes`); else the first posted like it not handed over yet (an app may tell its own time), and
    /// never a key from before it was posted.
    public mutating func handedOver(_ key: Key, marked: Bool, now: TimeInterval) -> Bool {
        forget(now)
        if let index = posted.firstIndex(where: { $0.isLike(key) && $0.time != 0 && $0.time == key.timestamp }) {
            posted[index].handedOver = true
            return true
        }
        // Else the first posted like it not handed over yet, whatever time the tap saw (an app may hand a key over with a
        // time of its own), never a key from before it was posted; its copies are then known by this time.
        if let index = posted.firstIndex(where: { posted in
            posted.isLike(key) && !posted.handedOver && (key.timestamp == 0 || key.timestamp >= posted.at - Self.earlier)
        }) {
            posted[index].handedOver = true
            if key.timestamp != 0 { posted[index].time = key.timestamp }
            return true
        }
        return marked
    }

    /// The keys posted more than `window` ago (or at a time still to come: another clock) forgotten.
    private mutating func forget(_ now: TimeInterval) {
        posted.removeAll { $0.at > now || now - $0.at > Self.window }
    }
}

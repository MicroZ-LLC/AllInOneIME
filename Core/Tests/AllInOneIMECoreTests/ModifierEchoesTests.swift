import Foundation
import Testing
@testable import AllInOneIMECore

// MARK: - A modifier change handed over again

/// `ModifierEchoes` through a class (its mutating call inside `#expect`).
final class EchoProbe {
    var echoes = ModifierEchoes()
    /// The clock's time as the change is handed over (the shell's `systemUptime`).
    var now: TimeInterval = 10
    func echo(_ keyCode: UInt16, _ flags: UInt, at timestamp: TimeInterval) -> Bool {
        echoes.isEcho(keyCode: keyCode, flags: flags, timestamp: timestamp, now: now)
    }
}

struct ModifierEchoesTests {
    // Left Shift (56) down and up, left Option (58) down, as an Electron app hands them over (NSEvent's flags).
    static let shiftDown: UInt = 0x20102, shiftUp: UInt = 0x100, optionDown: UInt = 0x80120

    /// Chromium's copy: the same key, flags and time, right after the change or after the next ones (a busy page); and
    /// again.
    @Test func theSameChangeAgainIsAnEcho() {
        let e = EchoProbe()
        #expect(!e.echo(56, Self.shiftDown, at: 1.0))
        #expect(e.echo(56, Self.shiftDown, at: 1.0))
        #expect(!e.echo(56, Self.shiftUp, at: 1.1))
        #expect(e.echo(56, Self.shiftDown, at: 1.0))  // after the release
        #expect(e.echo(56, Self.shiftUp, at: 1.1))
        #expect(e.echo(56, Self.shiftUp, at: 1.1))
    }

    /// Unlike every change kept in its key, its flags or its time: new. The same key pressed again; the other Shift, or
    /// other flags, at the same time.
    @Test func anythingElseIsNew() {
        let e = EchoProbe()
        #expect(!e.echo(56, Self.shiftDown, at: 1.0))
        #expect(!e.echo(56, Self.shiftDown, at: 1.5))
        #expect(!e.echo(60, Self.shiftDown, at: 1.5))
        #expect(!e.echo(56, Self.shiftDown | 0x4, at: 1.5))
    }

    /// No time (0): never taken for a copy.
    @Test func aChangeWithNoTimeIsNeverAnEcho() {
        let e = EchoProbe()
        #expect(!e.echo(56, Self.shiftDown, at: 0))
        #expect(!e.echo(56, Self.shiftDown, at: 0))
    }

    /// Synthesized changes needn't have times of their own, or in order (a tool posting one CGEvent again, giving its
    /// events one time or an earlier one): a change like one handed over, at its time or before, is taken for a copy.
    /// Two taps at one time: the second's down and up dropped.
    @Test func synthesizedChangesAtOneTimeAreTakenForCopies() {
        let e = EchoProbe()
        #expect(!e.echo(56, Self.shiftDown, at: 1))
        #expect(!e.echo(56, Self.shiftUp, at: 1))
        #expect(e.echo(56, Self.shiftDown, at: 1))
        #expect(e.echo(56, Self.shiftUp, at: 1))
        #expect(e.echo(56, Self.shiftDown, at: 0.5))
    }

    /// However many changes came between (a busy page's copies after nine capitals: eighteen changes), a change no
    /// later than the latest of its key and flags is a copy; the key pressed again is new.
    @Test func aCopyAfterManyChangesIsStillAnEcho() {
        let e = EchoProbe()
        let times = (0..<9).map { 1 + Double($0) / 10 }
        for time in times {
            #expect(!e.echo(56, Self.shiftDown, at: time))
            #expect(!e.echo(56, Self.shiftUp, at: time + 0.05))
        }
        for time in times {
            #expect(e.echo(56, Self.shiftDown, at: time))
            #expect(e.echo(56, Self.shiftUp, at: time + 0.05))
        }
        #expect(!e.echo(56, Self.shiftDown, at: 2))
    }

    /// It keeps the latest time of `kept` keys with their flags: one more, and the one seen longest ago is forgotten.
    @Test func itForgetsTheKeyAndFlagsSeenLongestAgo() {
        let e = EchoProbe()
        #expect(!e.echo(56, Self.shiftDown, at: 1))
        for i in 1..<ModifierEchoes.kept {
            #expect(!e.echo(UInt16(100 + i), Self.optionDown, at: 1 + Double(i) / 1000))
        }
        #expect(e.echo(56, Self.shiftDown, at: 1))
        #expect(!e.echo(58, Self.optionDown, at: 2))
        #expect(!e.echo(56, Self.shiftDown, at: 1))
    }

    /// A synthesized change at a time still to come (another unit, another clock), its key and flags the keyboard's:
    /// neither a copy nor kept, so it never takes the keyboard's changes after it for its copies. A hundred taps of
    /// Shift after it, every change new.
    @Test func aChangeFromTheFutureDoesntSwallowTheKeyboards() {
        let e = EchoProbe()
        e.now = 100
        #expect(!e.echo(56, Self.shiftDown, at: 1e9))
        #expect(!e.echo(56, Self.shiftUp, at: 1e9))
        #expect(!e.echo(56, Self.shiftDown, at: 1e9))
        for tap in 1...100 {
            e.now = 100 + Double(tap)
            #expect(!e.echo(56, Self.shiftDown, at: e.now - 0.1), "tap \(tap)")
            #expect(!e.echo(56, Self.shiftUp, at: e.now), "tap \(tap)")
            #expect(e.echo(56, Self.shiftUp, at: e.now), "tap \(tap)")  // its copy, still dropped
        }
    }

    /// Only a change within `window` seconds of the latest of its key and flags is taken for a copy: one from longer
    /// before (a tool's event at an old time of its own) is new, and the latest stays the latest.
    @Test func aChangeLongBeforeTheLatestIsNoCopy() {
        let e = EchoProbe()
        e.now = 100
        #expect(!e.echo(56, Self.shiftDown, at: 99))
        #expect(e.echo(56, Self.shiftDown, at: 99.5 - ModifierEchoes.window))
        #expect(!e.echo(56, Self.shiftDown, at: 98.5 - ModifierEchoes.window))
        #expect(!e.echo(56, Self.shiftDown, at: 10))
        #expect(e.echo(56, Self.shiftDown, at: 99))
    }
}

/// The composer and the long press of Shift as the Mac's shell hands them a modifier change
/// (`AllInOneIMEInputController.handleFlagsChanged`): a change handed over again dropped first (`ModifierEchoes`), any
/// other to the composer, then to the long press. The events' times on the long press's clock, moved by hand.
final class ModifierFeed {
    let composer: Composer
    let hold = HoldProbe()
    private var echoes = ModifierEchoes()
    /// What the composer did with every change so far.
    private(set) var effects: [Composer.Effect] = []

    init(_ composer: Composer = Composer(engine: FakeEngine(), actionKey: .enter)) { self.composer = composer }

    var now: TimeInterval { hold.clock.now }
    func wait(_ seconds: TimeInterval) { hold.wait(seconds) }

    /// A modifier change of `keyCode`, `modifiers` down after it, at `time` (the event's: a copy has the first one's).
    /// What the composer did (nil: dropped, a copy).
    @discardableResult
    func change(_ keyCode: UInt16, _ modifiers: KeyModifiers, at time: TimeInterval) -> [Composer.Effect]? {
        guard !echoes.isEcho(keyCode: keyCode, flags: UInt(modifiers.rawValue), timestamp: time, now: now) else { return nil }
        let done = composer.handleFlagsChanged(keyCode: keyCode, modifiers: modifiers, timestamp: time)
        effects += done
        _ = hold.flags(keyCode, modifiers)
        return done
    }

    func shiftDown(at time: TimeInterval) { change(VirtualKey.leftShift, [.shift, .leftShift], at: time) }
    func shiftUp(at time: TimeInterval) { change(VirtualKey.leftShift, [], at: time) }

    /// How many times the input language switched.
    var switches: Int { effects.filter { if case .inputLanguageChanged = $0 { true } else { false } }.count }
}

extension ModifierEchoesTests {
    /// A tap of Shift with the page busy: down, up, then down and up again with their times. The input language
    /// switched once, not back again; no long press.
    @Test func aTapOnABusyPage() {
        let f = ModifierFeed()
        let (pressed, released) = (f.now, f.now + 0.1)
        f.shiftDown(at: pressed)
        f.wait(0.1)
        f.shiftUp(at: released)
        f.wait(0.15)
        f.shiftDown(at: pressed)
        f.wait(0.003)
        f.shiftUp(at: released)
        f.wait(1.2)
        #expect(f.switches == 1 && f.composer.inputLanguage == .english)
        #expect(f.hold.poll() == nil && f.hold.hold.held == nil)
    }

    /// Two taps (back to the language before), each handed over again after both: two switches, not four.
    @Test func twoTapsOnABusyPage() {
        let f = ModifierFeed()
        let times = [f.now, f.now + 0.08, f.now + 0.16, f.now + 0.24]
        for (index, time) in times.enumerated() {
            f.hold.clock.now = time
            if index.isMultiple(of: 2) { f.shiftDown(at: time) } else { f.shiftUp(at: time) }
        }
        f.wait(0.2)
        for (index, time) in times.enumerated() {
            if index.isMultiple(of: 2) { f.shiftDown(at: time) } else { f.shiftUp(at: time) }
        }
        #expect(f.switches == 2 && f.composer.inputLanguage == .chinese)
    }

    /// A tap, then Shift held for the long press, the tap's copies coming while it's held: one switch (the tap's), and
    /// the long press toggles 1 s after its own down.
    @Test func aTapThenALongPressOnABusyPage() {
        let f = ModifierFeed()
        let (tapped, released) = (f.now, f.now + 0.1)
        f.shiftDown(at: tapped)
        f.wait(0.1)
        f.shiftUp(at: released)
        f.wait(0.2)
        f.shiftDown(at: f.now)
        #expect(f.hold.hold.held != nil)
        f.wait(0.05)
        f.shiftDown(at: tapped)
        f.shiftUp(at: released)
        f.wait(0.45)  // 0.5 s
        #expect(f.hold.poll() == .hint)
        f.wait(0.5)  // 1.0 s
        #expect(f.hold.poll() == .toggle)
        #expect(f.switches == 1)
    }

    /// Shift held for a capital, Shift's down handed over again after the letter (the page busy): released, no switch.
    @Test func aCapitalOnABusyPage() {
        let f = ModifierFeed()
        let pressed = f.now
        f.shiftDown(at: pressed)
        f.wait(0.1)
        _ = f.composer.handleKeyDown(KeyEvent(keyCode: 0x00, characters: "A", modifiers: .shift))
        f.hold.key()
        f.wait(0.1)
        f.shiftDown(at: pressed)
        f.wait(0.1)
        f.shiftUp(at: f.now)
        f.shiftUp(at: f.now)
        #expect(f.switches == 0)
    }

    /// Nine capitals typed with the page busy, all eighteen changes handed over again after them: every copy dropped,
    /// no switch (each down and up again would be a tap), no long press.
    @Test func nineCapitalsOnABusyPage() {
        let f = ModifierFeed()
        var times: [(pressed: TimeInterval, released: TimeInterval)] = []
        for _ in 0..<9 {
            let pressed = f.now
            f.shiftDown(at: pressed)
            f.wait(0.05)
            _ = f.composer.handleKeyDown(KeyEvent(keyCode: 0x00, characters: "A", modifiers: .shift))
            f.hold.key()
            f.wait(0.05)
            f.shiftUp(at: f.now)
            times.append((pressed, f.now))
            f.wait(0.05)
        }
        for (pressed, released) in times {
            #expect(f.change(VirtualKey.leftShift, [.shift, .leftShift], at: pressed) == nil)
            #expect(f.change(VirtualKey.leftShift, [], at: released) == nil)
        }
        f.wait(1.2)
        #expect(f.switches == 0 && f.composer.inputLanguage == .chinese)
        #expect(f.hold.poll() == nil && f.hold.hold.held == nil)
    }
}

// MARK: - The action key tapped (⌥), each change handed over twice

extension ComposerTests {
    /// Left Option tapped with a draft pending, each change handed over again right after it (Chromium, Electron): the
    /// tap sends the draft, once.
    @Test func anOptionTapInAnElectronApp() {
        let (c, _) = improveDraft(key: .optionTap)
        type("nihao", c)
        let f = ModifierFeed(c)
        let (pressed, released) = (f.now, f.now + 0.1)
        #expect(f.change(VirtualKey.leftOption, [.option, .leftOption], at: pressed) == [])
        #expect(f.change(VirtualKey.leftOption, [.option, .leftOption], at: pressed) == nil)
        f.wait(0.1)
        #expect(f.change(VirtualKey.leftOption, [], at: released)?.first == .startConversion(input: "你好", id: 1))
        #expect(f.change(VirtualKey.leftOption, [], at: released) == nil)
    }

    /// The same with the page busy: down, up, then down and up again with their times. Sent once; the copies do
    /// nothing (no second tap: in level two it would insert the result).
    @Test func anOptionTapOnABusyPage() {
        let (c, _) = improveDraft(key: .optionTap)
        type("nihao", c)
        let f = ModifierFeed(c)
        let (pressed, released) = (f.now, f.now + 0.1)
        f.change(VirtualKey.leftOption, [.option, .leftOption], at: pressed)
        f.wait(0.1)
        #expect(f.change(VirtualKey.leftOption, [], at: released)?.first == .startConversion(input: "你好", id: 1))
        f.wait(0.2)
        #expect(f.change(VirtualKey.leftOption, [.option, .leftOption], at: pressed) == nil)
        #expect(f.change(VirtualKey.leftOption, [], at: released) == nil)
        #expect(f.effects.filter { if case .startConversion = $0 { true } else { false } }.count == 1)
    }
}

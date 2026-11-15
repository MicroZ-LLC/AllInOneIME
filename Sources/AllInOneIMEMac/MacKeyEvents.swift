import AllInOneIMECore
import AppKit
import Carbon.HIToolbox

/// The keys and modifier changes AppKit hands the input method (`NSEvent`), as the session and the copies' filters take
/// them: a key down (`KeyEvent`, `KeyEchoes.Key`), a modifier change (`ModifierChange`), and whether a modifier change is
/// a copy of one handed over before (Chromium's and Electron's).
public enum MacKeyEvents {
    /// A key down as the session takes it.
    public static func key(_ event: NSEvent) -> KeyEvent {
        KeyEvent(keyCode: event.keyCode, usage: MacKeyboard.usage(event.keyCode), characters: event.characters ?? "",
                 charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                 modifiers: modifiers(event.modifierFlags), isRepeat: event.isARepeat)
    }

    /// A key down as `KeyEchoes` tells a copy of it from a new one.
    public static func echoKey(_ event: NSEvent) -> KeyEchoes.Key {
        KeyEchoes.Key(keyCode: event.keyCode, characters: event.characters ?? "", modifiers: event.modifierFlags.rawValue,
                      isRepeat: event.isARepeat, timestamp: event.timestamp)
    }

    /// A modifier change as the session takes it, handed over at `now` (the uptime clock its time is on): which side's keys
    /// are down, and fn; how late it came (the key was held up to the event; the pointer is asked later, so the session
    /// looks back that much further).
    public static func modifierChange(_ event: NSEvent, now: TimeInterval) -> ModifierChange {
        var modifiers = flagsChangedModifiers(event.modifierFlags)
        if event.modifierFlags.contains(.function) { modifiers.insert(.function) }
        return ModifierChange(key: MacKeyCodes.key(event.keyCode), modifiers: modifiers, timestamp: event.timestamp,
                              late: max(now - event.timestamp, 0))
    }

    public static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.capsLock) { result.insert(.capsLock) }
        return result
    }

    /// Device-dependent bits of NSEvent.modifierFlags (NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK).
    public static let leftOptionBit: UInt = 0x20, rightOptionBit: UInt = 0x40
    /// All eight (IOKit's NX_DEVICE…KEYMASK): which side's key of each kind is down.
    public static let sideBits: [(bit: UInt, side: KeyModifiers)] = [
        (0x01, .leftControl), (0x02, .leftShift), (0x04, .rightShift), (0x08, .leftCommand), (0x10, .rightCommand),
        (leftOptionBit, .leftOption), (rightOptionBit, .rightOption), (0x2000, .rightControl),
    ]

    /// Modifiers of a modifier-change event, including which side's keys are down.
    public static func flagsChangedModifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var result = modifiers(flags)
        for (bit, side) in sideBits where flags.rawValue & bit != 0 { result.insert(side) }
        return result
    }

    /// What a modifier change handed over again is a copy of: the same event again (`ModifierEchoes`), or Caps Lock's
    /// change again with a time of its own, told by the lock (`CapsLockCopies`).
    public enum Copy: Sendable {
        case echo
        case capsLock
    }

    /// Whether `event`, a modifier change handed over at `now`, is one handed over before, and which kind: Chromium and
    /// Electron apps (Slack, VS Code, Chrome, Brave) hand every modifier change over twice, the same event, after the next
    /// change too when the page is busy; a page's Caps Lock change comes again with a time of its own (`lockOn`: whether
    /// the lock is on now, asked only for Caps Lock's change). `echoes` and `capsLock` are every field's: a copy may
    /// reach another one.
    public static func copy(_ event: NSEvent, now: TimeInterval, echoes: inout ModifierEchoes, capsLock: inout CapsLockCopies,
                            lockOn: () -> Bool) -> Copy? {
        if echoes.isEcho(keyCode: event.keyCode, flags: event.modifierFlags.rawValue, timestamp: event.timestamp, now: now) {
            return .echo
        }
        guard event.keyCode == UInt16(kVK_CapsLock),
              capsLock.isCopy(saysOn: event.modifierFlags.contains(.capsLock), lockOn: lockOn(), timestamp: event.timestamp,
                              now: now) else { return nil }
        return .capsLock
    }
}

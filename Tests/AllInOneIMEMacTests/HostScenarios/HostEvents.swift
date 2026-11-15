import AppKit
import Carbon.HIToolbox

/// The events a host hands the input method (`NSEvent`: key downs and modifier changes, all it asks for), on a clock of
/// the test's own, with the copies `HostProfile` says the host sends: Chromium hands every modifier change, and every key
/// down the input method leaves it, over a second time 5–20 ms later with the same timestamp; Electron does too, 100 ms
/// or more later, after the next change. The delays come from a generator seeded by the scenario: a replay is the same
/// every time.
struct HostEvents {
    let profile: HostProfile
    /// The time now, in seconds on the uptime clock the events' times are on (never 0: a time of 0 is none).
    private(set) var now: TimeInterval = 1_000
    /// The copies to come: when, and the event (the very event handed over first).
    private var pending: [(at: TimeInterval, event: NSEvent)] = []
    private var random: SeededRandom

    init(profile: HostProfile, seed: String) {
        self.profile = profile
        random = SeededRandom(seed: seed + "/" + profile.rawValue)
    }

    /// A key down now: `characters` as it types them, `ignoringModifiers` without them.
    func keyDown(keyCode: UInt16, characters: String, ignoringModifiers: String, flags: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: now, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: ignoringModifiers, isARepeat: false, keyCode: keyCode)
    }

    /// A modifier change now: `flags` the modifiers down after it, with their sides' bits.
    func flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: now, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode)
    }

    /// The host hands `event` over again later, as its profile does (nothing for NSTextView, a terminal or WeChat).
    mutating func sendsCopy(of event: NSEvent) {
        let delay: TimeInterval
        switch profile {
        case .chromium: delay = random.next(in: 0.005...0.020)
        case .electron: delay = random.next(in: 0.100...0.250)
        case .nstextview, .tellsnothing: return
        }
        pending.append((now + delay, event))
        pending.sort { $0.at < $1.at }
    }

    /// When the next copy comes, if one is to.
    var nextCopy: TimeInterval? { pending.first?.at }

    /// The next copy, the clock moved to its time.
    mutating func takeCopy() -> NSEvent? {
        guard !pending.isEmpty else { return nil }
        let copy = pending.removeFirst()
        now = max(now, copy.at)
        return copy.event
    }

    /// The clock moved to `time` (never back).
    mutating func move(to time: TimeInterval) { now = max(now, time) }
}

/// A key as the host's keyboard (ANSI, U.S.) has it: its key code, and whether Shift types it.
enum HostKeys {
    static let letters: [Character: UInt16] = [
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E, "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
        "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F, "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
        "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10, "z": 0x06,
    ]
    static let others: [Character: UInt16] = [
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
        "-": 0x1B, "=": 0x18, "[": 0x21, "]": 0x1E, "\\": 0x2A, ";": 0x29, "'": 0x27, "`": 0x32, ",": 0x2B, ".": 0x2F,
        "/": 0x2C, " ": 0x31,
    ]
    /// What Shift types on each key that isn't a letter.
    static let shifted: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0", "_": "-",
        "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "~": "`", "<": ",", ">": ".", "?": "/",
    ]

    /// `character`'s key: its code, and whether it is typed with Shift. A character the keyboard has no key for goes as
    /// the key code 0 with its text, as a tool's key does.
    static func key(for character: Character) -> (code: UInt16, shift: Bool, base: Character) {
        if let code = letters[character] { return (code, false, character) }
        if let lower = character.lowercased().first, character.isUppercase, let code = letters[lower] { return (code, true, lower) }
        if let code = others[character] { return (code, false, character) }
        if let base = shifted[character], let code = others[base] { return (code, true, base) }
        return (0, false, character)
    }

    /// The named keys: their code and what they type.
    static let named: [String: (code: UInt16, characters: String)] = [
        "space": (UInt16(kVK_Space), " "), "enter": (UInt16(kVK_Return), "\r"), "return": (UInt16(kVK_Return), "\r"),
        "esc": (UInt16(kVK_Escape), "\u{1B}"), "escape": (UInt16(kVK_Escape), "\u{1B}"), "tab": (UInt16(kVK_Tab), "\t"),
        "backspace": (UInt16(kVK_Delete), "\u{7F}"), "delete": (UInt16(kVK_Delete), "\u{7F}"),
        "left": (UInt16(kVK_LeftArrow), "\u{F702}"), "right": (UInt16(kVK_RightArrow), "\u{F703}"),
        "up": (UInt16(kVK_UpArrow), "\u{F700}"), "down": (UInt16(kVK_DownArrow), "\u{F701}"),
    ]

    /// The modifier keys (the left one of each): code, flag and side bit (`MacKeyEvents.sideBits`).
    static let modifiers: [String: (code: UInt16, flag: NSEvent.ModifierFlags, side: UInt)] = [
        "shift": (UInt16(kVK_Shift), .shift, 0x02), "cmd": (UInt16(kVK_Command), .command, 0x08),
        "command": (UInt16(kVK_Command), .command, 0x08), "opt": (UInt16(kVK_Option), .option, 0x20),
        "option": (UInt16(kVK_Option), .option, 0x20), "alt": (UInt16(kVK_Option), .option, 0x20),
        "ctrl": (UInt16(kVK_Control), .control, 0x01), "control": (UInt16(kVK_Control), .control, 0x01),
    ]

    /// What ⌥ types on a U.S. keyboard for the keys a scenario is likely to press with it.
    static let option: [Character: String] = [
        "1": "¡", "2": "™", "3": "£", "4": "¢", "5": "∞", "6": "§", "7": "¶", "8": "•", "9": "ª", "0": "º",
        "a": "å", "c": "ç", "e": "´", "n": "˜", "o": "ø", "s": "ß", "u": "¨",
    ]
}

/// Numbers from a seed, the same every run (SplitMix64).
struct SeededRandom {
    private var state: UInt64

    init(seed: String) {
        // FNV-1a of the seed.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        state = hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
}

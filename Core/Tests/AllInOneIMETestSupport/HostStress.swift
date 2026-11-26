import Foundation

/// Random host scenarios from a seed, for the host tests' stress runs (the core's AllInOneIMEHostTests and the Mac's
/// replayer): a field, then keys (pinyin, English, Space, Return, ⌫, Esc, Tab, the arrows, digits, a tap of Shift, Caps
/// Lock, ⌘Z), clicks inside the field and outside it, the focus going and coming back, the field emptied by its app, the
/// input source switched to ABC and back, pauses, and (`drafts`) command drafts after "@". Written in the host scenario
/// format (`.hostcase`), so that a failure is a scenario file as it is, the same seed the same text everywhere.
public struct HostStress: Sendable {
    /// How the scenarios are made.
    public struct Options: Sendable {
        /// Steps in each.
        public var steps = 40
        /// "@" and a command's name and text now and then (run with Return only where nothing leaves the process: the
        /// core's runner has the on-device model, silent).
        public var drafts = true

        public init(steps: Int = 40, drafts: Bool = true) {
            (self.steps, self.drafts) = (steps, drafts)
        }
    }

    /// The seeds a run goes through: `ALLINONEIME_HOST_STRESS` runs (else `fixed`) from `ALLINONEIME_HOST_STRESS_SEED`
    /// (else 1). CI's are the fixed ones; a long run sets the first (`ALLINONEIME_HOST_STRESS=100000`).
    public static func seeds(fixed: Int, environment: [String: String] = ProcessInfo.processInfo.environment) -> [UInt64] {
        let runs = environment["ALLINONEIME_HOST_STRESS"].flatMap(Int.init) ?? fixed
        let first = environment["ALLINONEIME_HOST_STRESS_SEED"].flatMap(UInt64.init) ?? 1
        return (0..<UInt64(max(runs, 0))).map { first + $0 }
    }

    /// The scenario of `seed`: its header (`NAME`, `PROFILES all`, `LANG`, `TEXT`) and its steps, one a line.
    public static func scenario(seed: UInt64, _ options: Options = Options()) -> (header: [String], steps: [String]) {
        var random = SplitMix(seed: seed)
        var maker = Maker(options: options)
        let header = ["NAME stress seed \(seed)", "PROFILES all", "LANG \(random.chance(0.6) ? "chinese" : "english")",
                      "TEXT \"\(random.pick(fields))\""]
        let steps = (0..<options.steps).map { _ in maker.step(&random) }
        return (header, steps)
    }

    /// `header` and `steps` as a scenario file's text.
    public static func text(_ header: [String], _ steps: [String]) -> String {
        (header + steps).joined(separator: "\n") + "\n"
    }

    /// The fields a scenario starts with (scenario markup: `|` the caret, `[..]` a selection).
    static let fields = ["|", "Hi |", "Hello world|", "ab|cd", "你好|", "x 😀|y", "Hi [Bob] ok", "line one\\nline two|",
                         String(repeating: "long ", count: 60) + "|end"]
    static let syllables = ["ni", "hao", "wo", "shi", "zhong", "guo", "a", "e", "ma", "de", "xie", "nihao", "zhongguo"]
    static let words = ["ok", "the", "hello", "a", "is", "x"]
    static let keys = ["space", "space", "enter", "backspace", "backspace", "escape", "tab", "left", "right", "up", "down",
                       "shift", "shift", "capslock", "cmd+z", "1", "2", "3"]

    /// Makes the steps, keeping track of what makes the next one likely: a field left gets the focus back, ABC switched
    /// back.
    struct Maker {
        var options: Options
        var focused = true
        var abc = false

        mutating func step(_ random: inout SplitMix) -> String {
            if !focused, random.chance(0.7) {
                focused = true
                return "FOCUS back"
            }
            if abc, random.chance(0.5) {
                abc = false
                return "SWITCH back"
            }
            let roll = random.next(below: 100)
            switch roll {
            case 0..<30: return "TYPE " + random.pick(HostStress.syllables + (random.chance(0.3) ? HostStress.words : []))
            case 30..<55: return "KEY " + random.pick(HostStress.keys)
            case 55..<62: return "CLICK inside \(random.next(below: 40))"
            case 62..<65:
                focused = false
                return "CLICK outside"
            case 65..<70:
                focused = false
                return "FOCUS " + random.pick(["away", "otherapp", "closewindow"])
            case 70..<73: return "APP clears"
            case 73..<76:
                abc = true
                return "SWITCH abc"
            case 76..<86: return "WAIT \(random.pick([20, 60, 150, 400, 1200]))ms"
            case 86..<92 where options.drafts:
                return "TYPE \"@" + random.pick(["improve ok", "question hi", "tr", "q", "x"]) + "\""
            default: return "TYPE " + random.pick(HostStress.syllables)
            }
        }
    }

    /// SplitMix64: the same numbers from the same seed on every platform.
    public struct SplitMix: RandomNumberGenerator, Sendable {
        private var state: UInt64

        public init(seed: UInt64) { state = seed }

        public mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        public mutating func next(below bound: Int) -> Int { Int(next() % UInt64(max(bound, 1))) }
        public mutating func chance(_ probability: Double) -> Bool { Double(next() % 10_000) < probability * 10_000 }
        public mutating func pick<T>(_ list: [T]) -> T { list[next(below: list.count)] }
    }

    // MARK: Shrinking

    /// The fewest of `steps` with which `fails` still holds: chunks taken out, then single steps, as long as it fails
    /// the same way (`fails` is given the steps kept). A failure found at random becomes a scenario a person can read.
    public static func shrink(_ steps: [String], fails: ([String]) -> Bool) -> [String] {
        var kept = steps
        var chunk = max(kept.count / 2, 1)
        while chunk >= 1 {
            var start = 0
            var changed = false
            while start < kept.count {
                var trial = kept
                trial.removeSubrange(start..<min(start + chunk, kept.count))
                if fails(trial) {
                    kept = trial
                    changed = true
                } else {
                    start += chunk
                }
            }
            if !changed { chunk /= 2 }
        }
        return kept
    }
}

import Foundation

/// Typing a result out character by character, like a person typing (`Config.typeOut`): how long to
/// wait before each character. The pace varies a little, and stops after punctuation and spaces last longer.
public enum TypeOut {
    /// Characters a second, on average.
    public enum Speed: String, Codable, CaseIterable, Sendable {
        /// `random`: no one pace: short bursts, each at its own between slow and fast, like a person
        /// speeding up and slowing down.
        case slow, normal, fast, random

        /// The average; for `random`, the middle of its range.
        public var charactersPerSecond: Double {
            switch self {
            case .slow: return 8
            case .normal, .random: return 16
            case .fast: return 32
            }
        }
    }

    /// The pause before each character of `text` (the first one too, so it reads as typed), in seconds.
    /// `random` gives numbers in 0..<1 (the tests pass their own).
    public static func delays(for text: String, speed: Speed, random: () -> Double = { Double.random(in: 0..<1) }) -> [Double] {
        var base = 1 / speed.charactersPerSecond
        var burstLeft = 0
        var previous: Character?
        return text.map { character in
            defer { previous = character }
            if speed == .random {
                // A new burst of 3–8 characters at a pace of its own, from slow to fast.
                if burstLeft == 0 {
                    burstLeft = 3 + Int(random() * 6)
                    let slowest = Speed.slow.charactersPerSecond, fastest = Speed.fast.charactersPerSecond
                    base = 1 / (slowest + (fastest - slowest) * random())
                }
                burstLeft -= 1
            }
            var delay = base * (0.6 + 0.8 * random())  // 60–140 % of the average
            if let previous {
                if ".,;:!?。，、；：！？…".contains(previous) { delay *= 3 }  // a breath after punctuation
                else if previous == " " || previous == "\n" { delay *= 1.5 }
            }
            return delay
        }
    }
}

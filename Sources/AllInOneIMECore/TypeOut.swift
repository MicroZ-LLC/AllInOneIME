import Foundation

/// Typing a result out character by character, like a person typing (`Config.typeOut`): how long to
/// wait before each character. The pace varies a little, and stops after punctuation and spaces last longer.
public enum TypeOut {
    /// Characters a second, on average.
    public enum Speed: String, Codable, CaseIterable, Sendable {
        case slow, normal, fast

        public var charactersPerSecond: Double {
            switch self {
            case .slow: return 8
            case .normal: return 16
            case .fast: return 32
            }
        }
    }

    /// The pause before each character of `text` (the first one too, so it reads as typed), in seconds.
    /// `random` gives numbers in 0..<1 (the tests pass their own).
    public static func delays(for text: String, speed: Speed, random: () -> Double = { Double.random(in: 0..<1) }) -> [Double] {
        let base = 1 / speed.charactersPerSecond
        var previous: Character?
        return text.map { character in
            defer { previous = character }
            var delay = base * (0.6 + 0.8 * random())  // 60–140 % of the average
            if let previous {
                if ".,;:!?。，、；：！？…".contains(previous) { delay *= 3 }  // a breath after punctuation
                else if previous == " " || previous == "\n" { delay *= 1.5 }
            }
            return delay
        }
    }
}

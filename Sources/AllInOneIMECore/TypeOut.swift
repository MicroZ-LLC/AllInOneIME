import Foundation

/// Typing a result out character by character, like a person typing (`Config.typeOut`): how long to
/// wait before each character. The pace varies a little, and stops after punctuation and spaces last longer.
public enum TypeOut {
    /// Characters a second, from very slow (6 s a character) to fast; the default.
    public static let slowestRate = 1.0 / 6
    public static let fastestRate = 40.0
    public static let defaultRate = 16.0

    /// The pause before each character of `text` (the first one too, so it reads as typed), in seconds,
    /// at `rate` characters a second on average. `varies`: short bursts of 3–8 characters, each at its
    /// own pace from half to twice `rate`, like a person speeding up and slowing down. `random` gives
    /// numbers in 0..<1 (the tests pass their own).
    public static func delays(for text: String, rate: Double, varies: Bool = false,
                              random: () -> Double = { Double.random(in: 0..<1) }) -> [Double] {
        let rate = min(max(rate, slowestRate), fastestRate)
        var base = 1 / rate
        var burstLeft = 0
        var previous: Character?
        return text.map { character in
            defer { previous = character }
            if varies {
                if burstLeft == 0 {
                    burstLeft = 3 + Int(random() * 6)
                    base = 1 / (rate * pow(2, 2 * random() - 1))  // ½× to 2× the rate, the middle as likely as the ends
                }
                burstLeft -= 1
            }
            var delay = base * (0.6 + 0.8 * random())  // 60–140 % of the pace
            if let previous {
                if ".,;:!?。，、；：！？…".contains(previous) { delay *= 3 }  // a breath after punctuation
                else if previous == " " || previous == "\n" { delay *= 1.5 }
            }
            return delay
        }
    }

    /// The slider's position (0…1, a log scale so the slow end isn't squeezed) for `rate`, and back.
    public static func position(of rate: Double) -> Double {
        log(min(max(rate, slowestRate), fastestRate) / slowestRate) / log(fastestRate / slowestRate)
    }

    public static func rate(at position: Double) -> Double {
        slowestRate * pow(fastestRate / slowestRate, min(max(position, 0), 1))
    }
}

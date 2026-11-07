import Foundation

/// Finds the dates and times written in a text, for `ReminderParser` (its `detect`): NSDataDetector on Apple
/// platforms (`DataDetectorDates`); elsewhere none, and the parser's own rules read them alone.
public protocol DateDetector: Sendable {
    /// Each date or time in `text`: where it's written and the moment it means, from the real clock.
    func dates(in text: String) -> [ReminderParser.Match]
    /// Whether all of `text` is one date or one phone number, as the system reads them ("2026-11-06", "11/5",
    /// "010-12345678"): no sum for one @ (`Arithmetic`), whatever its signs say.
    func isWholeDateOrPhoneNumber(_ text: String) -> Bool
}

extension DateDetector {
    /// None, without the system's detection.
    public func isWholeDateOrPhoneNumber(_ text: String) -> Bool { false }
}

/// No system date detection: the reminder parser's rules (clock times, 明天, "next Monday", 15号, durations …) alone.
public struct RulesOnlyDateDetector: DateDetector {
    public init() {}
    public func dates(in text: String) -> [ReminderParser.Match] { [] }
}

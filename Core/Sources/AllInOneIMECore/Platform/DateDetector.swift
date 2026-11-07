import Foundation

/// Finds the dates and times written in a text, for `ReminderParser` (its `detect`): NSDataDetector on Apple
/// platforms (`DataDetectorDates`); elsewhere none, and the parser's own rules read them alone.
public protocol DateDetector: Sendable {
    /// Each date or time in `text`: where it's written and the moment it means, from the real clock.
    func dates(in text: String) -> [ReminderParser.Match]
}

/// No system date detection: the reminder parser's rules (clock times, 明天, "next Monday", 15号, durations …) alone.
public struct RulesOnlyDateDetector: DateDetector {
    public init() {}
    public func dates(in text: String) -> [ReminderParser.Match] { [] }
}

#if canImport(Darwin)
import Foundation

/// The system's date detection (NSDataDetector, which only Apple's Foundation has).
public struct DataDetectorDates: DateDetector {
    public init() {}

    public func dates(in text: String) -> [ReminderParser.Match] {
        guard let detector = Self.shared else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { result in
            guard let date = result.date, let range = Range(result.range, in: text) else { return nil }
            return ReminderParser.Match(range: range, date: date)
        }
    }

    /// Made once (that takes a few milliseconds) and shared: like any NSRegularExpression it is immutable.
    private static let shared = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
}
#endif

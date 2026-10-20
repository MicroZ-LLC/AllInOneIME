import Foundation

/// How long ago a date was, in an interface language, in the three ways the interface says it (`Style`). Under a minute,
/// or ahead of `now` (another device's clock), it is 「刚刚」 / "just now".
public enum RelativeTime {
    public enum Style: Sendable {
        /// In words, ICU's in each language, in the largest calendar unit between the two, whole ones: 「3小时前」,
        /// "3 hours ago", "1 week ago": the candidate panel's recent questions and saved answers.
        case words
        /// Short, in minutes, hours or days: 「5 分钟前」, "5 min ago", "2 hr ago", "3 days ago": the menu bar panel's and
        /// the settings'.
        case short
        /// Short within a day ("2 min ago", "3 h ago"), then the date and time: iCloud's last sync.
        case shortThenDate
    }

    public static func ago(_ date: Date, now: Date, language: String, style: Style) -> String {
        let t = InterfaceWords(language: language)
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 60 else { return t.tr("刚刚", "just now") }
        if style == .words { return words(date, now: now, language: language) }
        let (minutes, hours, days) = (Int(seconds / 60), Int(seconds / 3600), Int(seconds / 86400))
        if hours < 1 { return t.tr("\(minutes) 分钟前", "\(minutes) min ago") }
        if days < 1 {
            return style == .short ? t.tr("\(hours) 小时前", "\(hours) hr ago") : t.tr("\(hours) 小时前", "\(hours) h ago")
        }
        guard style == .short else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: language == "en" ? "en_US" : language)
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return days == 1 ? t.tr("1 天前", "1 day ago") : t.tr("\(days) 天前", "\(days) days ago")
    }

    /// `ago` in words: Apple's RelativeDateTimeFormatter on Apple platforms, elsewhere `countedWords`, which says the same.
    static func words(_ date: Date, now: Date, language: String) -> String {
        #if canImport(Darwin)
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language)
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
        #else
        return countedWords(date, now: now, language: language)
        #endif
    }

    /// The calendar units RelativeDateTimeFormatter counts in, largest first, and the format style's field for each.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private static let units: [(Calendar.Component, Date.RelativeFormatStyle.Field)] = [
        (.year, .year), (.month, .month), (.weekOfMonth, .week), (.day, .day), (.hour, .hour), (.minute, .minute), (.second, .second),
    ]

    /// `ago` in words where there is no RelativeDateTimeFormatter with a units style (swift-corelibs-foundation: Linux,
    /// Windows, Android): swift-foundation's format style, the same ICU words, made to count as Apple's formatter does,
    /// in the largest calendar unit between the two and whole ones (90 seconds is "1 minute ago", not 2; 4 weeks is
    /// "4 weeks ago", not "1 month ago"). The style counts from the present, so it is given the date as far before it as
    /// those units are before `now`. On Apple platforms too (macOS 15), where the tests hold it to the formatter.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    static func countedWords(_ date: Date, now: Date, language: String) -> String {
        let calendar = Calendar.current
        let parts = calendar.dateComponents(Set(units.map(\.0)), from: date, to: now)
        var (back, field) = (now, Date.RelativeFormatStyle.Field.second)
        if let (unit, unitField) = units.first(where: { (parts.value(for: $0.0) ?? 0) != 0 }), let count = parts.value(for: unit) {
            back = calendar.date(byAdding: unit, value: -count, to: now) ?? now
            field = unitField
        }
        let style = Date.RelativeFormatStyle(allowedFields: [field], presentation: .numeric, unitsStyle: .wide,
                                             locale: Locale(identifier: language), calendar: calendar)
        return Date().addingTimeInterval(-now.timeIntervalSince(back)).formatted(style)
    }
}

import AllInOneIMECore
import Foundation

/// The menu bar panel's row for this week's stats, at its top: "本周 132 次指令 ↑18% ›"; a click opens Settings → This
/// Week. Not there before the first command is counted.
public enum WeekStatsMenuBar {
    public struct Row: Equatable, Sendable {
        /// "本周 132 次指令".
        public var title: String
        /// "18%" with which way it went; nil without a comparison.
        public var percent: String?
        public var trend: WeekStatsText.Trend?
        /// Where a click goes.
        public var destination: SettingsPlace
        /// The row read out (VoiceOver).
        public var spoken: String
    }

    /// The row for `stats` in `language`; nil while no command is counted.
    public static func row(stats: WeekStats, language: String) -> Row? {
        guard stats.hasCommands else { return nil }
        let text = WeekStatsText(stats.snapshot(for: .current), language: language)
        return Row(title: text.menuBarTitle, percent: text.comparisonPercent, trend: text.trend, destination: .weekStats,
                   spoken: [text.menuBarTitle, text.atStatsComparison].compactMap { $0 }.joined(separator: ", "))
    }
}

/// What Settings → This Week remembers of itself: whether the user's own command names are hidden in the picture
/// ("复制时隐藏我的命令名"). A preference of the page, in the input method's own defaults, not one of the settings.
public final class WeekStatsPagePreferences: @unchecked Sendable {
    private let defaults: UserDefaults
    static let hideOwnCommandNamesKey = "weekStats.hideOwnCommandNames"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Off until turned on.
    public var hideOwnCommandNames: Bool {
        get { defaults.bool(forKey: Self.hideOwnCommandNamesKey) }
        set { defaults.set(newValue, forKey: Self.hideOwnCommandNamesKey) }
    }
}

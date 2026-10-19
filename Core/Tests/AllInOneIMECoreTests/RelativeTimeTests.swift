import Foundation
import Testing
@testable import AllInOneIMECore

/// How long ago, the three ways the interface says it (`RelativeTime`), in Simplified Chinese and English.
struct RelativeTimeTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func ago(_ seconds: TimeInterval, _ language: String, _ style: RelativeTime.Style) -> String {
        RelativeTime.ago(t0, now: t0 + seconds, language: language, style: style)
    }

    /// The menu bar panel's and the settings': minutes, hours, days.
    @Test func short() {
        let cases: [(TimeInterval, String, String)] = [
            (-30, "刚刚", "just now"), (59, "刚刚", "just now"), (60, "1 分钟前", "1 min ago"),
            (25 * 60, "25 分钟前", "25 min ago"), (3599, "59 分钟前", "59 min ago"), (3600, "1 小时前", "1 hr ago"),
            (2 * 3600 + 59 * 60, "2 小时前", "2 hr ago"), (86_399, "23 小时前", "23 hr ago"),
            (86_400, "1 天前", "1 day ago"), (3 * 86_400 + 5, "3 天前", "3 days ago"),
        ]
        for (seconds, chinese, english) in cases {
            #expect(ago(seconds, "zh-Hans", .short) == chinese && ago(seconds, "en", .short) == english, "\(seconds) s")
        }
    }

    /// iCloud's last sync: within a day the same, "h" for hours; after it the date.
    @Test func shortThenTheDate() {
        #expect([ago(-5, "en", .shortThenDate), ago(59, "en", .shortThenDate), ago(60, "en", .shortThenDate),
                 ago(3599, "en", .shortThenDate), ago(3600, "en", .shortThenDate), ago(86_399, "en", .shortThenDate)]
                == ["just now", "just now", "1 min ago", "59 min ago", "1 h ago", "23 h ago"])
        #expect(ago(3600, "zh-Hans", .shortThenDate) == "1 小时前")
        let day = ago(86_400, "en", .shortThenDate)
        #expect(day.contains("2027") && !day.contains("ago"), "\(day)")  // t0 is in January 2027
    }

    /// The candidate panel's, in words: whole units of the largest one there is, as Apple's formatter counts.
    @Test func inWords() {
        let english: [(TimeInterval, String)] = [
            (-30, "just now"), (59, "just now"), (60, "1 minute ago"), (90, "1 minute ago"), (150, "2 minutes ago"),
            (3599, "59 minutes ago"), (5400, "1 hour ago"), (7 * 86_400, "1 week ago"), (28 * 86_400, "4 weeks ago"),
        ]
        for (seconds, text) in english { #expect(ago(seconds, "en", .words) == text, "\(seconds) s") }
        #expect(ago(90, "zh-Hans", .words) == "1分钟前" && ago(59, "zh-Hans", .words) == "刚刚")
        #expect(InterfaceWords(language: "en").ago(t0, now: t0 + 90) == "1 minute ago")
    }

    /// Off Apple platforms the words come from swift-foundation's format style (`countedWords`), which on its own rounds
    /// (90 seconds "2 minutes ago", 4 weeks "1 month ago"): counted as Apple's formatter counts, they say the same, in
    /// every language, for minutes to years. Checked here where both are (macOS 15), and on Linux against the words above.
    @Test func theWordsElsewhereAreApplesWords() throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        #if canImport(Darwin)
        var intervals: [TimeInterval] = Array(stride(from: 60, to: 7200, by: 37))
        intervals += Array(stride(from: 7200, to: 3 * 86_400, by: 1613))
        intervals += Array(stride(from: 3 * 86_400, to: 800 * 86_400, by: 0.73 * 86_400))
        let now = Date()
        for language in ["en", "zh-Hans", "zh-Hant", "de", "fr", "ja"] {
            let differing = intervals.filter {
                let date = now - $0
                return RelativeTime.countedWords(date, now: now, language: language) != RelativeTime.words(date, now: now, language: language)
            }
            #expect(differing.isEmpty, "\(language): \(differing.prefix(5)) s")
        }
        #endif
        #expect(RelativeTime.countedWords(t0, now: t0 + 90, language: "en") == "1 minute ago")
        #expect(RelativeTime.countedWords(t0, now: t0 + 28 * 86_400, language: "en") == "4 weeks ago")
    }
}

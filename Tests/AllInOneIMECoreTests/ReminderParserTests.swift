import Foundation
import Testing
@testable import AllInOneIMECore

/// `ReminderParser` with a stand-in for NSDataDetector (what it would find, without its clock) for the
/// rules, then the real one for what it is used for, relative to now. The stand-ins return what the real
/// detector returned on this Mac for the same text (as the parser hands it over: 明晚 → 明天晚上 …).
struct ReminderParserTests {
    /// Pacific time; "now" is Friday 2026-10-09 16:00.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
    let now = ReminderParserTests.date(10, 9, 16)
    static let at1am = date(10, 9, 1), at9am = date(10, 9, 9), at9pm = date(10, 9, 21)

    static func date(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func due(_ month: Int, _ day: Int, _ hour: Int? = nil, _ minute: Int? = nil, year: Int = 2026) -> DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    }

    /// Due then, with its moment.
    static func timed(_ title: String, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> ReminderDraft {
        ReminderDraft(title: title, due: due(month, day, hour, minute), hasTime: true, date: date(month, day, hour, minute))
    }

    /// Due that day, no time.
    static func allDay(_ title: String, _ month: Int, _ day: Int, year: Int = 2026) -> ReminderDraft {
        ReminderDraft(title: title, due: due(month, day, year: year), hasTime: false)
    }

    /// The same, written to repeat (每周一, "every Monday"): set once.
    static func once(_ draft: ReminderDraft) -> ReminderDraft {
        var draft = draft
        draft.writtenAsRepeating = true
        return draft
    }

    static let saturday = date(10, 10, 12), sunday = date(10, 11, 12)

    /// A parser whose detector finds each phrase in the text, meaning that date.
    func parser(_ found: [String: Date] = [:]) -> ReminderParser {
        ReminderParser(calendar: Self.calendar) { text in
            found.compactMap { phrase, date in text.range(of: phrase).map { ReminderParser.Match(range: $0, date: date) } }
                .sorted { $0.range.lowerBound < $1.range.lowerBound }
        }
    }

    func parse(_ text: String, _ found: [String: Date] = [:], at time: Date? = nil) -> ReminderDraft {
        parser(found).parse(text, now: time ?? now)
    }

    // MARK: - Titles

    @Test func theTitleIsTheTextWithoutTheDate() {
        let tomorrow3pm = Self.date(10, 10, 15)
        #expect(parse("明天下午3点给张三打电话", ["明天下午3点": tomorrow3pm]) == Self.timed("给张三打电话", 10, 10, 15))
        // Wherever the date is, and without 「提醒我」 / "remind me to" or a word that led into the date.
        let cases: [(String, String, String)] = [
            ("提醒我明天下午3点给张三打电话", "明天下午3点", "给张三打电话"),
            ("明天下午3点提醒我给张三打电话", "明天下午3点", "给张三打电话"),
            ("给张三打电话，明天下午3点", "明天下午3点", "给张三打电话"),
            ("给张三明天下午3点打电话", "明天下午3点", "给张三打电话"),
            ("在明天下午3点开会", "明天下午3点", "开会"),
            ("开会（明天下午3点）", "明天下午3点", "开会"),
            ("明天下午3点之前交报告", "明天下午3点", "交报告"),
            ("明天下午3点的飞机", "明天下午3点", "飞机"),
            ("提醒我 明天 下午3点 开会", "明天 下午3点", "开会"),
            ("给Bob明天下午3点打电话", "明天下午3点", "给Bob打电话"),
            ("remind me to call Bob tomorrow at 3pm", "tomorrow at 3pm", "call Bob"),
            ("Remind me to call Bob tomorrow at 3pm.", "tomorrow at 3pm", "call Bob"),
            ("tomorrow at 3pm call Bob", "tomorrow at 3pm", "call Bob"),
            ("call Bob tomorrow at 3pm about the report", "tomorrow at 3pm", "call Bob about the report"),
            ("call Bob at 3pm tomorrow", "at 3pm tomorrow", "call Bob"),
        ]
        for (text, phrase, title) in cases {
            #expect(parse(text, [phrase: tomorrow3pm]).title == title, "\(text)")
        }
        // NSDataDetector leaves "at" / "on" out of some phrases ("at [5 pm]", "on [Friday]").
        #expect(parse("Call Bob at 5 pm", ["5 pm": Self.date(10, 9, 17)]) == Self.timed("Call Bob", 10, 9, 17))
        #expect(parse("pay rent on Friday", ["Friday": Self.date(10, 16)]) == Self.allDay("pay rent", 10, 16))
    }

    @Test func wordsThatOnlyWentWithTheDate() {
        // 「在」 / 「于」 of their own go, not the end of a word (关于, 现在, 对于, 由于).
        #expect(parse("关于明天下午3点的会议", ["明天下午3点": Self.date(10, 10, 15)]) == Self.timed("关于会议", 10, 10, 15))
        #expect(parse("现在下午3点开会", ["下午3点": Self.date(10, 9, 15)], at: Self.at9am) == Self.timed("现在开会", 10, 9, 15))
        #expect(parse("对于明天的安排", ["明天": Self.date(10, 10)]).title == "对于安排")
        #expect(parse("由于明天下雨带伞", ["明天": Self.date(10, 10)]).title == "由于下雨带伞")
        #expect(parse("我在明天下午3点开会", ["明天下午3点": Self.date(10, 10, 15)]).title == "我开会")
        #expect(parse("开会，于明天下午3点", ["明天下午3点": Self.date(10, 10, 15)]).title == "开会")
        // By when: 「前」 / 「之前」 / 「以前」 right after the date (not 前台, 前面 …).
        for text in ["周五前交报告", "周五之前交报告", "周五以前交报告"] {
            #expect(parse(text, ["周五": Self.date(10, 16)]) == Self.allDay("交报告", 10, 16), "\(text)")
        }
        #expect(parse("明天前台见", ["明天": Self.date(10, 10)]).title == "前台见")
        // A verb that starts like such a word comes after a "by then" 「前」: 提交, 提供, 提出, 提醒, 列出, 进行.
        #expect(parse("周五前提交报告", ["周五": Self.date(10, 16)]) == Self.allDay("提交报告", 10, 16))
        #expect(parse("下午3点前提供数据", ["下午3点": Self.date(10, 9, 15)]) == Self.timed("提供数据", 10, 10, 15))
        for (text, title) in [("周五前提出意见", "提出意见"), ("周五前提醒他", "提醒他"), ("周五前列出清单", "列出清单"),
                              ("周五前进行评审", "进行评审"), ("周五前往北京", "前往北京")] {
            #expect(parse(text, ["周五": Self.date(10, 16)]).title == title, "\(text)")
        }
        // A 是 / "is" that only said what the date is, the date starting the text or a clause.
        #expect(parse("明天是小王生日", ["明天": Self.date(10, 10)]) == Self.allDay("小王生日", 10, 10))
        #expect(parse("提醒我明天是小王生日", ["明天": Self.date(10, 10)]).title == "小王生日")
        #expect(parse("别忘了，明天是小王生日", ["明天": Self.date(10, 10)]).title == "别忘了，小王生日")
        #expect(parse("tomorrow is Bob's birthday", ["tomorrow": Self.date(10, 10)]) == Self.allDay("Bob's birthday", 10, 10))
        for (text, title) in [("明天是否开会", "是否开会"), ("明天是不是开会", "是不是开会"), ("他说明天是晴天", "他说是晴天")] {
            #expect(parse(text, ["明天": Self.date(10, 10)]).title == title, "\(text)")
        }
        #expect(parse("tomorrow isn't a holiday", ["tomorrow": Self.date(10, 10)]).title == "isn't a holiday")
        // 左右: about then.
        #expect(parse("明天开会，3点左右", ["明天": Self.date(10, 10)]) == Self.timed("开会", 10, 10, 15))
        // What only asked for the reminder.
        #expect(parse("提醒我一下明天交报告", ["明天": Self.date(10, 10)]) == Self.allDay("交报告", 10, 10))
        #expect(parse("提醒一下明天交报告", ["明天": Self.date(10, 10)]).title == "交报告")
        #expect(parse("记得明天带伞", ["明天": Self.date(10, 10)]).title == "带伞")
        #expect(parse("提醒我记得带伞").title == "带伞" && parse("提醒我一下").title.isEmpty)
    }

    @Test func onlyBracketsTheDateLeftEmptyGo() {
        let tomorrow = Self.date(10, 10)
        // Empty already: part of the title.
        #expect(parse("明天修复 parse() 崩溃", ["明天": tomorrow]) == Self.allDay("修复 parse() 崩溃", 10, 10))
        #expect(parse("明天 call foo() again", ["明天": tomorrow]).title == "call foo() again")
        #expect(parse("明天给数组[]加测试", ["明天": tomorrow]).title == "给数组[]加测试")
        #expect(parse("开会（明天）讨论「」的用法", ["明天": tomorrow]).title == "开会讨论「」的用法")
        // Holding only the date, and the words that went with it: they go, spaced as the date was.
        #expect(parse("开会（明天下午3点前）", ["明天下午3点": Self.date(10, 10, 15)]) == Self.timed("开会", 10, 10, 15))
        #expect(parse("开会【在明天】", ["明天": tomorrow]).title == "开会")
        #expect(parse("开会 （明天） 讨论", ["明天": tomorrow]).title == "开会 讨论")
        #expect(parse("call Bob (tomorrow) about it", ["tomorrow": tomorrow]).title == "call Bob about it")
        #expect(parse("（明天）是小王生日", ["明天": tomorrow]).title == "小王生日")
        #expect(parse("开会（「明天」）", ["明天": tomorrow]).title == "开会")
        // With more in them: they stay.
        #expect(parse("开会（明天，302室）", ["明天": tomorrow]).title.hasSuffix("302室）"))
    }

    @Test func mealsTheDetectorReadsAsATimeStayInTheTitle() {
        // It reads "tomorrow lunch" (at 12:00): the reminder is the lunch, tomorrow.
        #expect(parse("tomorrow lunch with Ann", ["tomorrow lunch": Self.date(10, 10, 12)]) == Self.allDay("lunch with Ann", 10, 10))
        #expect(parse("lunch tomorrow with Ann", ["lunch tomorrow": Self.date(10, 10, 12)]) == Self.allDay("lunch with Ann", 10, 10))
        #expect(parse("tomorrow dinner with Bob", ["tomorrow dinner": Self.date(10, 10, 19)]).title == "dinner with Bob")
        // A time written with it stays.
        #expect(parse("at noon tomorrow lunch", ["at noon tomorrow lunch": Self.date(10, 10, 12)]) == Self.timed("lunch", 10, 10, 12))
        #expect(parse("明天午饭和张三", ["明天午饭": Self.date(10, 10, 12)]) == Self.allDay("午饭和张三", 10, 10))
        #expect(parse("明天早餐", ["明天早餐": Self.date(10, 10, 9)]) == Self.allDay("早餐", 10, 10))
        // Only a meal: no date.
        #expect(parse("lunch with Ann", ["lunch": Self.date(10, 9, 12)]) == ReminderDraft(title: "lunch with Ann"))
    }

    @Test func aDayWithoutATimeHasNoTime() {
        // NSDataDetector puts a day at noon: it stays a day, without a time (and so without an alarm).
        #expect(parse("10月15日交房租", ["10月15日": Self.date(10, 15)]) == Self.allDay("交房租", 10, 15))
        #expect(parse("明天给张三打电话", ["明天": Self.date(10, 10)]).hasTime == false)
        #expect(parse("Oct 15 pay rent", ["Oct 15": Self.date(10, 15)]).due == Self.due(10, 15))
        // A part of the day is a time: 今晚, "tonight", 下午.
        #expect(parse("今晚给妈妈打电话", ["今晚": Self.date(10, 9, 18)]) == Self.timed("给妈妈打电话", 10, 9, 18))
        #expect(parse("tonight call mom", ["tonight": Self.date(10, 9, 19)]).hasTime)
    }

    @Test func withoutADateThereIsNoDueDate() {
        #expect(parse("买牛奶") == ReminderDraft(title: "买牛奶"))
        #expect(parse("提醒我买牛奶") == ReminderDraft(title: "买牛奶"))
        #expect(parse("  remind me to buy milk. ") == ReminderDraft(title: "buy milk"))
        // Only a date: nothing to be reminded of (the composer asks for it).
        #expect(parse("明天下午3点", ["明天下午3点": Self.date(10, 10, 15)]).title.isEmpty)
        // Numbers that aren't dates or times (the detector finds none in them either).
        for text in ["买3斤苹果", "订2张票", "转500块", "10.15元", "3号线换乘", "5号楼开会", "第3点意见", "500日元", "3点赞",
                     "买一点水果", "快一点", "有一点累", "一点也不急", "给我一点时间", "早一点到"] {
            #expect(parse(text).due == nil, "\(text)")
        }
        // 「晚一点」 is "a bit later", which the detector reads as 13:00.
        #expect(parse("晚一点出发", ["晚一点": Self.date(10, 9, 13)]) == ReminderDraft(title: "晚一点出发"))
        #expect(parse("明天晚一点开会", ["明天晚一点": Self.date(10, 10, 13)]) == Self.allDay("晚一点开会", 10, 10))
    }

    // MARK: - A time of day that has passed

    @Test func aTimeOfDayAlreadyPastMeansTomorrow() {
        // At 16:00, "下午3点" / "9am" / "15:00" alone are tomorrow's.
        #expect(parse("下午3点开会", ["下午3点": Self.date(10, 9, 15)]).due == Self.due(10, 10, 15, 0))
        #expect(parse("9am standup", ["9am": Self.date(10, 9, 9)]).due == Self.due(10, 10, 9, 0))
        #expect(parse("15:00开会", ["15:00": Self.date(10, 9, 15)]).due == Self.due(10, 10, 15, 0))
        // Still to come today: today's.
        #expect(parse("下午5点开会", ["下午5点": Self.date(10, 9, 17)]).due == Self.due(10, 9, 17, 0))
        // A day was named: that day, even if it is over (the row then says so).
        let today = parse("今天下午3点开会", ["今天下午3点": Self.date(10, 9, 15)])
        #expect(today.due == Self.due(10, 9, 15, 0) && today.isPast(now: now, calendar: Self.calendar))
        #expect(parse("today at 3pm call Bob", ["today at 3pm": Self.date(10, 9, 15)]).due == Self.due(10, 9, 15, 0))
        #expect(parse("周五下午3点开会", ["周五下午3点": Self.date(10, 9, 15)]).due == Self.due(10, 9, 15, 0))
        #expect(parse("10/9 3pm", ["10/9 3pm": Self.date(10, 9, 15)]).due == Self.due(10, 9, 15, 0))
        // A day without a time is never moved.
        #expect(parse("今天交报告", ["今天": Self.date(10, 9)]).due == Self.due(10, 9))
    }

    // MARK: - A part of the day and a clock time

    @Test func aPartOfTheDayAndAClockTimeAreOneTime() {
        // Written out for the detector, 明晚7点 is 明天晚上7点, which it reads whole.
        #expect(parse("明晚7点吃饭", ["明天晚上7点": Self.date(10, 10, 19)]) == Self.timed("吃饭", 10, 10, 19))
        #expect(parse("明晚八点看电影", ["明天晚上八点": Self.date(10, 10, 20)]) == Self.timed("看电影", 10, 10, 20))
        // Where it reads only the part of the day (18:00), the clock time after it counts, in that half.
        #expect(parse("明晚7点吃饭", ["明天晚上": Self.date(10, 10, 18)]) == Self.timed("吃饭", 10, 10, 19))
        #expect(parse("明晚八点看电影", ["明天晚上": Self.date(10, 10, 18)]) == Self.timed("看电影", 10, 10, 20))
        #expect(parse("明晚7点半吃饭", ["明天晚上": Self.date(10, 10, 18), "7点半": Self.date(10, 9, 19, 30)])
                == Self.timed("吃饭", 10, 10, 19, 30))
        #expect(parse("今天晚上 7点半 吃饭", ["今天晚上": Self.date(10, 9, 18)]) == Self.timed("吃饭", 10, 9, 19, 30))
        #expect(parse("明天早上8点开会", ["明天早上": Self.date(10, 10, 9)]) == Self.timed("开会", 10, 10, 8))
        // It reads 中午 alone (12:00): 十二点 is noon, 1点 just after.
        #expect(parse("中午十二点吃饭", ["中午": Self.date(10, 9, 12)]) == Self.timed("吃饭", 10, 10, 12))  // over at 16:00
        #expect(parse("中午十二点吃饭", ["中午": Self.date(10, 9, 12)], at: Self.at9am) == Self.timed("吃饭", 10, 9, 12))
        #expect(parse("明天中午十二点吃饭", ["明天中午": Self.date(10, 10, 12)]) == Self.timed("吃饭", 10, 10, 12))
        #expect(parse("明天中午1点吃饭", ["明天中午": Self.date(10, 10, 12)]) == Self.timed("吃饭", 10, 10, 13))
        // It finds nothing in these.
        #expect(parse("中午1点开会") == Self.timed("开会", 10, 10, 13))
        #expect(parse("中午12点开会", at: Self.at9am) == Self.timed("开会", 10, 9, 12))
        #expect(parse("傍晚6点散步") == Self.timed("散步", 10, 9, 18))
        #expect(parse("周五傍晚6点散步", ["周五": Self.date(10, 16)]) == Self.timed("散步", 10, 16, 18))
        // Morning and 凌晨 as written; 晚上12点 is midnight, the end of the day.
        #expect(parse("凌晨3点起床") == Self.timed("起床", 10, 10, 3))
        #expect(parse("晚上12点睡觉") == Self.timed("睡觉", 10, 10, 0))
        let hours: [(Int, String, Int)] = [(7, "晚上", 19), (8, "晚", 20), (3, "下午", 15), (6, "傍晚", 18), (12, "晚上", 24),
                                          (12, "中午", 12), (1, "中午", 13), (2, "中午", 14), (11, "中午", 11), (8, "早上", 8),
                                          (10, "上午", 10), (3, "凌晨", 3), (12, "凌晨", 0), (2, "半夜", 2), (12, "半夜", 24),
                                          (20, "晚上", 20)]
        for (hour, part, meant) in hours { #expect(ReminderParser.hour(hour, in: part) == meant, "\(part)\(hour)点") }
    }

    // MARK: - A clock time without its half of the day

    @Test func aBareClockTimeIsTheNextOfMorningAndAfternoon() {
        // h:mm or (h+12):mm, whichever comes first from now, never 0:00–5:59; else tomorrow's first.
        #expect(parse("3点接孩子", at: Self.at1am) == Self.timed("接孩子", 10, 9, 15))
        #expect(parse("8点", at: Self.at9am).due == Self.due(10, 9, 20, 0))
        #expect(parse("8点", at: Self.at9pm).due == Self.due(10, 10, 8, 0))
        #expect(parse("8点开会", at: Self.at1am).due == Self.due(10, 9, 8, 0))
        for (text, hour) in [("十点", 22), ("9点", 21), ("11点", 23), ("8点", 20), ("十一点半", 23)] {
            #expect(parse(text).due?.hour == hour && parse(text).due?.day == 9, "\(text)")
        }
        #expect(parse("4点").due == Self.due(10, 10, 16, 0))  // 16:00 is now: tomorrow's
        // The detector's own guess for the hour doesn't count (it says 03:30 for 3点半 in the morning, 01:30 for 1点半).
        #expect(parse("3点半接孩子", ["3点半": Self.date(10, 9, 3, 30)]) == Self.timed("接孩子", 10, 10, 15, 30))  // 15:30 is over
        #expect(parse("3点半接孩子", ["3点半": Self.date(10, 9, 3, 30)], at: Self.at9am) == Self.timed("接孩子", 10, 9, 15, 30))
        #expect(parse("1点半开会", ["1点半": Self.date(10, 9, 1, 30)], at: Self.at9am).due == Self.due(10, 9, 13, 30))
        #expect(parse("8点半跑步", ["8点半": Self.date(10, 9, 8, 30)]).due == Self.due(10, 9, 20, 30))
        #expect(parse("1:30 call Bob", ["1:30": Self.date(10, 9, 13, 30)], at: Self.at9am) == Self.timed("call Bob", 10, 9, 13, 30))
        #expect(parse("1:30 call Bob", ["1:30": Self.date(10, 9, 13, 30)]) == Self.timed("call Bob", 10, 10, 13, 30))
        // English "at N" (the detector finds nothing there).
        #expect(parse("at 5 leave") == Self.timed("leave", 10, 9, 17))
        #expect(parse("call Bob at 3") == Self.timed("call Bob", 10, 10, 15))
        #expect(parse("call Bob at 3", at: Self.at9am) == Self.timed("call Bob", 10, 9, 15))
        // 12点 is noon.
        #expect(parse("12点吃饭", at: Self.at9am) == Self.timed("吃饭", 10, 9, 12))
        #expect(parse("12点吃饭") == Self.timed("吃饭", 10, 10, 12))
        // 凌晨 / 半夜 written: 3:00 can be meant.
        #expect(parse("3点，凌晨的航班", at: Self.at1am).due == Self.due(10, 9, 3, 0))
        // With a day: that day, the earlier of the two from 6:00 (today: the one still to come).
        #expect(parse("明天3点开会", ["明天3点": Self.date(10, 10, 15)]) == Self.timed("开会", 10, 10, 15))
        #expect(parse("明天8点开会", ["明天8点": Self.date(10, 10, 8)]).due == Self.due(10, 10, 8, 0))
        #expect(parse("今天8点开会", ["今天8点": Self.date(10, 9, 8)], at: Self.at9am).due == Self.due(10, 9, 20, 0))
        #expect(parse("today at 5 call Bob", ["today at 5": Self.date(10, 9, 17)]) == Self.timed("call Bob", 10, 9, 17))
        #expect(parse("Friday at 3", ["Friday at 3": Self.date(10, 16, 15)]).due == Self.due(10, 16, 15, 0))
        #expect(parse("明天一点开会", ["明天": Self.date(10, 10)]) == Self.timed("开会", 10, 10, 13))
    }

    @Test func aNumberOfPointsIsNoTime() {
        // 「N点」 before what it counts is points made: no time, also not for a day written elsewhere (it was 15:00,
        // 14:00, 17:00 and cut from the title). The detector reads only the day in these.
        #expect(parse("明天交报告，写3点建议", ["明天": Self.date(10, 10)]) == Self.allDay("交报告，写3点建议", 10, 10))
        #expect(parse("周五开会，提两点建议", ["周五": Self.date(10, 16)]) == Self.allDay("开会，提两点建议", 10, 16))
        #expect(parse("明天开会讨论两点问题", ["明天": Self.date(10, 10)]) == Self.allDay("开会讨论两点问题", 10, 10))
        #expect(parse("周五前列出5点意见", ["周五": Self.date(10, 16)]) == Self.allDay("列出5点意见", 10, 16))
        for text in ["写3点建议", "两点小建议", "总结三点经验", "说两点个人看法", "有3点注意事项", "提5点要求"] {
            #expect(parse(text).due == nil, "\(text)")
        }
        // After a part of the day or a day it is the time.
        #expect(parse("下午3点问题讨论", at: Self.at9am) == Self.timed("问题讨论", 10, 9, 15))
        #expect(parse("明天3点内容评审", ["明天": Self.date(10, 10)]) == Self.timed("内容评审", 10, 10, 15))
        // Another bare 「N点」 is a day's time from elsewhere only when it ends its clause: more after it may count
        // things too (「写3点东西」).
        #expect(parse("明天交报告，写3点东西", ["明天": Self.date(10, 10)]) == Self.allDay("交报告，写3点东西", 10, 10))
        #expect(parse("明天开会，3点开始", ["明天": Self.date(10, 10)]) == Self.allDay("开会，3点开始", 10, 10))
        #expect(parse("明天开会，3点半开始", ["明天": Self.date(10, 10), "3点半": Self.date(10, 9, 3, 30)])
                == Self.allDay("开会，3点半开始", 10, 10))
        #expect(parse("周五晚上聚餐，写3点东西", ["周五晚上": Self.date(10, 16, 18)]) == Self.timed("聚餐，写3点东西", 10, 16, 18))
        for text in ["明天开会，3点", "明天开会，3点。", "明天开会，3点前", "明天开会 3点 带电脑"] {
            #expect(parse(text, ["明天": Self.date(10, 10)]).due == Self.due(10, 10, 15, 0), "\(text)")
        }
        #expect(parse("明天开会 3点 带电脑", ["明天": Self.date(10, 10)]).title == "开会 带电脑")
        // Next to the day, or alone, as before.
        #expect(parse("明天3点开会", ["明天3点": Self.date(10, 10, 15)]) == Self.timed("开会", 10, 10, 15))
        #expect(parse("明天 3点开会", ["明天": Self.date(10, 10)]) == Self.timed("开会", 10, 10, 15))
        #expect(parse("3点半接孩子", ["3点半": Self.date(10, 9, 3, 30)], at: Self.at9am) == Self.timed("接孩子", 10, 9, 15, 30))
        #expect(parse("3点开始，明天", ["明天": Self.date(10, 10)]) == Self.timed("开始", 10, 10, 15))  // the reminder's own time
        #expect(ReminderParser.countsThings("建议") && ReminderParser.countsThings("小建议") && !ReminderParser.countsThings("开会"))
    }

    // MARK: - A day and a time written apart

    @Test func aDayAndATimeWrittenApartAreOneDate() {
        let tomorrow = Self.date(10, 10), at3pm = Self.date(10, 9, 15)
        // A day alone takes its time from anywhere in the text, and both leave the title.
        #expect(parse("明天开会，3点", ["明天": tomorrow]) == Self.timed("开会", 10, 10, 15))
        #expect(parse("下周一开会 上午10点", ["下周一": Self.date(10, 12), "上午10点": Self.date(10, 9, 10)]) == Self.timed("开会", 10, 12, 10))
        #expect(parse("tomorrow call Bob at 5", ["tomorrow": tomorrow]) == Self.timed("call Bob", 10, 10, 17))
        #expect(parse("tomorrow - call Bob at 3pm", ["tomorrow": tomorrow, "3pm": at3pm]) == Self.timed("call Bob", 10, 10, 15))
        // With dinner, 7 is in the evening.
        #expect(parse("Friday: dinner at 7", ["Friday": Self.date(10, 16)]) == Self.timed("dinner", 10, 16, 19))
        // A time alone takes its day.
        #expect(parse("at 5 dentist tomorrow", ["tomorrow": tomorrow]) == Self.timed("dentist", 10, 10, 17))
        #expect(parse("5pm meeting with Ann on Monday", ["5pm": Self.date(10, 9, 17), "Monday": Self.date(10, 12)])
                == Self.timed("meeting with Ann", 10, 12, 17))
        #expect(parse("8pm movie on Friday", ["8pm": Self.date(10, 9, 20), "Friday": Self.date(10, 16)]) == Self.timed("movie", 10, 16, 20))
        // A part of the day takes the clock time, in that half of the day.
        #expect(parse("周五晚上 聚餐 7点", ["周五晚上": Self.date(10, 16, 18)]) == Self.timed("聚餐", 10, 16, 19))
        #expect(parse("明天晚上开会，8点", ["明天晚上": Self.date(10, 10, 18)]) == Self.timed("开会", 10, 10, 20))
        // A number of days takes the time, a time the number of days.
        #expect(parse("3天后开会，下午3点", ["下午3点": at3pm]) == Self.timed("开会", 10, 12, 15))
        #expect(parse("下午3点体检，两天后", ["下午3点": at3pm]) == Self.timed("体检", 10, 11, 15))
        // Side by side with a colon, a comma, a dash or brackets between: one phrase.
        #expect(parse("明天：下午3点开会", ["明天": tomorrow, "下午3点": at3pm]) == Self.timed("开会", 10, 10, 15))
        #expect(parse("明天、下午3点", ["明天": tomorrow, "下午3点": at3pm]) == Self.timed("", 10, 10, 15))
        #expect(parse("给张三明天、下午3点打电话", ["明天": tomorrow, "下午3点": at3pm]) == Self.timed("给张三打电话", 10, 10, 15))
        #expect(parse("明天（下午3点）开会", ["明天": tomorrow, "下午3点": at3pm]) == Self.timed("开会", 10, 10, 15))
        #expect(parse("（明天）下午3点开会", ["明天": tomorrow, "下午3点": at3pm]) == Self.timed("开会", 10, 10, 15))
        #expect(parse("明天(3pm) call Bob", ["明天": tomorrow, "3pm": at3pm]) == Self.timed("call Bob", 10, 10, 15))
        // Two days, or a day with a time: the first stands, the other is the title's.
        #expect(parse("明天开会，后天3点出发", ["明天": tomorrow, "后天3点": Self.date(10, 11, 15)]) == Self.allDay("开会，后天3点出发", 10, 10))
        // A meal inside what the detector read stays in the title; it reads "tomorrow dinner at 7" at 19:00.
        #expect(parse("tomorrow dinner at 7", ["tomorrow dinner at 7": Self.date(10, 10, 19)]) == Self.timed("dinner", 10, 10, 19))
        #expect(parse("dinner at 7 tomorrow", ["dinner at 7 tomorrow": Self.date(10, 10, 19)]) == Self.timed("dinner", 10, 10, 19))
        #expect(parse("明天晚饭7点", ["明天晚饭7点": Self.date(10, 10, 19)]) == Self.timed("晚饭", 10, 10, 19))
    }

    @Test func nextMonthIsNoMonday() {
        // "next mon…" in "next month" is no weekday: the detector's 15th of next month stands, and "on the" goes.
        #expect(parse("pay rent on the 15th of next month", ["15th of next month": Self.date(11, 15)], at: Self.saturday)
                == Self.allDay("pay rent", 11, 15))
        #expect(parse("pay rent by the 15th of next month", ["15th of next month": Self.date(11, 15)]).title == "pay rent")
        #expect(parse("pay rent next month", at: Self.saturday) == Self.allDay("pay rent", 11, 1))  // its 1st
        // Weekdays, whole or short, still are (the detector: 9 days ahead for some, said on a Saturday).
        #expect(parse("next Mon call Bob", ["next Mon": Self.date(10, 19)], at: Self.saturday).due == Self.due(10, 12))
        #expect(parse("next Tues call Bob", ["next Tues": Self.date(10, 20)], at: Self.saturday).due == Self.due(10, 13))
        #expect(parse("next Thurs call Bob", ["next Thurs": Self.date(10, 15)], at: Self.saturday).due == Self.due(10, 15))
    }

    // MARK: - Forms the detector misses

    @Test func formsTheDetectorMisses() {
        // 明早 / 今早 / 早8点 written out (明天早上, 今天早上, 早上8点), which it reads.
        #expect(parse("明早8点开会", ["明天早上8点": Self.date(10, 10, 8)]) == Self.timed("开会", 10, 10, 8))
        #expect(parse("今早9点开会", ["今天早上9点": Self.date(10, 9, 9)]) == Self.timed("开会", 10, 9, 9))  // over: shown so
        #expect(parse("明天早8点开会", ["明天早上8点": Self.date(10, 10, 8)]) == Self.timed("开会", 10, 10, 8))
        #expect(parse("明早8点开会").due == Self.due(10, 10, 8, 0))  // the clock time after 早上 is read here too
        // Days of the month: this month's while still to come (today too), else the next month's.
        #expect(parse("15号交房租") == Self.allDay("交房租", 10, 15))
        #expect(parse("15日交房租").due == Self.due(10, 15) && parse("十五号交房租").due == Self.due(10, 15))
        #expect(parse("9号交房租").due == Self.due(10, 9) && parse("5号交房租").due == Self.due(11, 5))
        #expect(parse("31号交房租", at: Self.date(11, 5)).due == Self.due(12, 31))  // November has no 31st
        #expect(parse("15号下午3点交房租", ["下午3点": Self.date(10, 9, 15)]) == Self.timed("交房租", 10, 15, 15))
        #expect(parse("10月15号交房租", ["10月15号": Self.date(10, 15)]) == Self.allDay("交房租", 10, 15))
        // noon (it reads "at noon" as "noon", and nothing in "noon" alone).
        #expect(parse("lunch at noon", ["noon": Self.date(10, 9, 12)]) == Self.timed("lunch", 10, 10, 12))
        #expect(parse("noon call Bob", at: Self.at9am) == Self.timed("call Bob", 10, 9, 12))
        // Durations in other words.
        let cases: [(String, Int, String)] = [
            ("30 minutes from now check the oven", 30, "check the oven"), ("call mom 2 hours later", 120, "call mom"),
            ("after 30 minutes stretch", 30, "stretch"), ("half an hour later leave", 30, "leave"),
            ("an hour from now call Ann", 60, "call Ann"), ("3日后交报告", 3 * 24 * 60, "交报告"),
        ]
        for (text, minutes, title) in cases {
            let draft = parse(text)
            let when = now.addingTimeInterval(Double(minutes) * 60)
            #expect(draft.title == title && draft.due?.day == Self.calendar.component(.day, from: when), "\(text): \(draft)")
            if minutes < 24 * 60 { #expect(draft.date == when && draft.hasTime, "\(text)") }
        }
    }

    @Test func moreFormsTheDetectorMisses() {
        // "on the 15th": the next 15th (not "the 3rd floor").
        #expect(parse("pay rent on the 15th") == Self.allDay("pay rent", 10, 15))
        #expect(parse("pay rent on the 1st") == Self.allDay("pay rent", 11, 1) && parse("pay rent by 1st").due == Self.due(11, 1))
        #expect(parse("meet on the 3rd floor").due == nil && parse("my 5th try").due == nil)
        // 10.1 / 11.11 / 5.20 with words around them: a month and day, the next one.
        #expect(parse("10.1出发") == Self.allDay("出发", 10, 1, year: 2027))  // over this year
        #expect(parse("11.11买东西") == Self.allDay("买东西", 11, 11) && parse("出发 5.20") == Self.allDay("出发", 5, 20, year: 2027))
        // After a part of the day or a day it is a time: 9.30 is 9:30.
        #expect(parse("明天9.30开会", ["明天": Self.date(10, 10)]) == Self.timed("开会", 10, 10, 9, 30))
        #expect(parse("下午3.30开会", at: Self.at9am) == Self.timed("开会", 10, 9, 15, 30))
        // Money, quantities, versions, addresses, numbers alone.
        for text in ["10.15元", "¥5.20", "v1.2发布", "3.5斤苹果", "2.5倍", "192.168.1.1", "版本1.2.3", "Swift 5.10发布", "10.1", "3.14159",
                     "涨了5.2%", "1.5小时", "售价9.9"] {
            #expect(parse(text).due == nil, "\(text)")
        }
        // 1个月后, "in 1 month" (not 3月后, which is March, nor half a month).
        #expect(parse("1个月后复查") == Self.allDay("复查", 11, 9) && parse("两个月后复查").due == Self.due(12, 9))
        #expect(parse("in 1 month renew") == Self.allDay("renew", 11, 9) && parse("2 months later").due == Self.due(12, 9))
        #expect(parse("一个月后下午3点复查", ["下午3点": Self.date(10, 9, 15)]) == Self.timed("复查", 11, 9, 15))
        #expect(parse("3月后").due == nil && parse("半个月后").due == nil)
        // 周末 / "this weekend": today on a Saturday or Sunday, else the coming Saturday; 下周末: next week's.
        #expect(parse("周末大扫除") == Self.allDay("大扫除", 10, 10) && parse("这周末大扫除").due == Self.due(10, 10))
        #expect(parse("this weekend hike") == Self.allDay("hike", 10, 10) && parse("hike on the weekend").title == "hike")
        #expect(parse("周末大扫除", at: Self.saturday).due == Self.due(10, 10) && parse("周末大扫除", at: Self.sunday).due == Self.due(10, 11))
        #expect(parse("下周末爬山") == Self.allDay("爬山", 10, 17) && parse("next weekend hike", at: Self.sunday).due == Self.due(10, 17))
        #expect(parse("上周末的照片").due == nil)
        // 月底: the month's last day.
        #expect(parse("月底交房租") == Self.allDay("交房租", 10, 31) && parse("下个月底交房租").due == Self.due(11, 30))
        #expect(parse("pay rent by the end of the month") == Self.allDay("pay rent", 10, 31))
        #expect(parse("上个月底的账单").due == nil)
    }

    @Test func aDecimalIsADateOnlyWhenNothingElseSaysWhen() {
        let tomorrow = Self.date(10, 10)
        // Another day in the text: the number before it is no month and day (Sep 8, Dec 8 came first and won).
        #expect(parse("评分9.8的电影明天看", ["明天": tomorrow]) == Self.allDay("评分9.8的电影看", 10, 10))
        #expect(parse("血压12.8 明天复查", ["明天": tomorrow]) == Self.allDay("血压12.8复查", 10, 10))
        #expect(parse("电影9.8 明天看", ["明天": tomorrow]) == Self.allDay("电影9.8看", 10, 10))
        #expect(parse("刻度6.1 下周一复查").due == Self.due(10, 12) && parse("刻度6.1 15号复查").due == Self.due(10, 15))
        #expect(parse("刻度6.1，3天后复测").due == Self.due(10, 12))
        #expect(parse("刻度6.1 30分钟后复测").date == now.addingTimeInterval(30 * 60))
        // After a score, a reading, a rate, a price or a version: a number, with no other day too.
        for text in ["评分9.8的电影", "得分 8.5", "打分：9.5", "评分是9.8", "血压12.8", "血糖6.1", "视力5.1", "汇率7.1", "绩点3.8",
                     "价格9.9", "版本1.2", "指数3.1"] {
            #expect(parse(text).due == nil, "\(text)")
        }
        // Still a month and day: alone with words, with a time, after the 分 of a number (minutes, a score).
        #expect(parse("10.1 下午3点出发").due == Self.due(10, 1, 15, 0, year: 2027))
        #expect(parse("考了95分 10.1出成绩").due == Self.due(10, 1, year: 2027))
        #expect(parse("3点20分 10.1出发").due == Self.due(10, 1, 15, 20, year: 2027))
    }

    @Test func fixedDaysTheDetectorMisses() {
        // 下个月 / "next month": its 1st, or the day of the month written with it (they were 「未设时间」, in the title).
        #expect(parse("下个月交报告") == Self.allDay("交报告", 11, 1))
        #expect(parse("下月交报告").due == Self.due(11, 1) && parse("下下个月交报告").due == Self.due(12, 1))
        #expect(parse("下个月的会议") == Self.allDay("会议", 11, 1))
        #expect(parse("下个月 15号交报告") == Self.allDay("交报告", 11, 15) && parse("下月15号交报告").due == Self.due(11, 15))
        #expect(parse("pay rent next month") == Self.allDay("pay rent", 11, 1))
        #expect(parse("pay rent next month on the 15th") == Self.allDay("pay rent", 11, 15))
        #expect(parse("pay rent on the 15th next month") == Self.allDay("pay rent", 11, 15))
        #expect(parse("下个月底交房租").due == Self.due(11, 30))  // 月底, as before
        // 月初: the next 1st (today on the 1st); 下月初 next month's; 这个月初 this month's (over: shown so).
        #expect(parse("月初交房租") == Self.allDay("交房租", 11, 1) && parse("月初一起吃饭").title == "一起吃饭")
        #expect(parse("月初交房租", at: Self.date(10, 1, 9)).due == Self.due(10, 1))
        #expect(parse("下月初交房租") == Self.allDay("交房租", 11, 1) && parse("下个月初交房租", at: Self.date(10, 1, 9)).due == Self.due(11, 1))
        #expect(parse("这个月初交房租").due == Self.due(10, 1))
        // 年底 / 年末 / "end of the year": Dec 31, of the year written with it.
        #expect(parse("年底交报告") == Self.allDay("交报告", 12, 31) && parse("年末盘点").due == Self.due(12, 31))
        #expect(parse("今年年底交报告").due == Self.due(12, 31) && parse("年底前交报告").title == "交报告")
        #expect(parse("明年年底交报告") == Self.allDay("交报告", 12, 31, year: 2027) && parse("明年底").due == Self.due(12, 31, year: 2027))
        #expect(parse("然后年底交报告") == Self.allDay("然后交报告", 12, 31))  // 然后 says no year
        #expect(parse("finish the report by the end of the year") == Self.allDay("finish the report", 12, 31))
        #expect(parse("file taxes by the end of next year") == Self.allDay("file taxes", 12, 31, year: 2027))
        // 元旦, 圣诞节: the next one, or that of the year written with it.
        #expect(parse("元旦去爬山") == Self.allDay("去爬山", 1, 1, year: 2027) && parse("元旦节去爬山").title == "去爬山")
        #expect(parse("圣诞节买礼物") == Self.allDay("买礼物", 12, 25) && parse("圣诞节前买礼物").title == "买礼物")
        #expect(parse("明年圣诞节去日本") == Self.allDay("去日本", 12, 25, year: 2027))
        #expect(parse("元旦去爬山", at: Self.date(1, 1, 9, year: 2027)).due == Self.due(1, 1, year: 2027))  // today counts
        // Not these: another month or year, the middle of a month, lunar dates (which move).
        for text in ["上个月的账单", "去年年底的账单", "2026年底", "10月初", "正月初一拜年", "下个月中旬", "中秋回家", "春节回家"] {
            #expect(parse(text) == ReminderDraft(title: text), "\(text)")
        }
        // Written to repeat: each month, each year.
        #expect(parse("每个月初交房租") == Self.once(Self.allDay("每个月初交房租", 11, 1)))
        #expect(parse("每年年底总结") == Self.once(Self.allDay("每年年底总结", 12, 31)))
        #expect(ReminderParser.repeatStep(marker: "每个", phrase: "月初") == DateComponents(month: 1))
        #expect(ReminderParser.repeatStep(marker: "每", phrase: "年底") == DateComponents(year: 1))
    }

    // MARK: - A part of the day, or a month and day, that is over

    @Test func aPartOfTheDayStillGoingIsTodayAllDay() {
        let at2130 = Self.date(10, 9, 21, 30), at1603 = Self.date(10, 9, 16, 3), at1830 = Self.date(10, 9, 18, 30)
        // Its usual time is over, the part of the day isn't: today, all day (no alarm in the past, not tomorrow).
        #expect(parse("今晚看电影", ["今晚": Self.date(10, 9, 18)], at: at2130) == Self.allDay("看电影", 10, 9))
        #expect(parse("tonight call mom", ["tonight": Self.date(10, 9, 19)], at: at2130) == Self.allDay("call mom", 10, 9))
        #expect(parse("下午开会", ["下午": Self.date(10, 9, 15)], at: at1603) == Self.allDay("开会", 10, 9))
        #expect(parse("今天下午开会", ["今天下午": Self.date(10, 9, 15)], at: at1603) == Self.allDay("开会", 10, 9))
        #expect(!parse("今晚看电影", ["今晚": Self.date(10, 9, 18)], at: at2130).isPast(now: at2130, calendar: Self.calendar))
        // Still to come: then. The part of the day over: tomorrow's, or that of the day named (shown as over).
        #expect(parse("今晚看电影", ["今晚": Self.date(10, 9, 18)]) == Self.timed("看电影", 10, 9, 18))
        #expect(parse("下午开会", ["下午": Self.date(10, 9, 15)], at: at1830) == Self.timed("开会", 10, 10, 15))
        let over = parse("今天下午开会", ["今天下午": Self.date(10, 9, 15)], at: at1830)
        #expect(over == Self.timed("开会", 10, 9, 15) && over.isPast(now: at1830, calendar: Self.calendar))
        // Another day's, and a clock time, as they say.
        #expect(parse("明晚看电影", ["明天晚上": Self.date(10, 10, 18)], at: at2130) == Self.timed("看电影", 10, 10, 18))
        #expect(parse("下午3点开会", ["下午3点": Self.date(10, 9, 15)], at: at1603).due == Self.due(10, 10, 15, 0))
    }

    @Test func aMonthAndDayAlreadyPastIsNextYears() {
        #expect(parse("10月5日交报告", ["10月5日": Self.date(10, 5)]) == Self.allDay("交报告", 10, 5, year: 2027))
        #expect(parse("Oct 5 pay rent", ["Oct 5": Self.date(10, 5)]).due == Self.due(10, 5, year: 2027))
        #expect(parse("10/5 pay rent", ["10/5": Self.date(10, 5)]).due == Self.due(10, 5, year: 2027))
        #expect(parse("10月5日下午3点开会", ["10月5日下午3点": Self.date(10, 5, 15)]).due == Self.due(10, 5, 15, 0, year: 2027))
        // Today's and later ones are this year's; with a year written, that one.
        #expect(parse("10月9日交报告", ["10月9日": Self.date(10, 9)]).due == Self.due(10, 9))
        #expect(parse("2026年10月5日交报告", ["2026年10月5日": Self.date(10, 5)]).due == Self.due(10, 5))
        #expect(parse("今年10月5日交报告", ["10月5日": Self.date(10, 5)]).due == Self.due(10, 5))
        // Not a month and day: as read.
        #expect(parse("昨天的会议纪要", ["昨天": Self.date(10, 8)]).due == Self.due(10, 8))
    }

    @Test func nextWeekdaySaidAtTheWeekendIsTheComingOne() {
        let saturday = Self.date(10, 10, 12), sunday = Self.date(10, 11, 12), monday = Self.date(10, 12, 12)
        // On a Saturday the detector says 9 days ahead for "next Monday": the coming Monday, like 下周一.
        #expect(parse("next Monday 9:30 standup", ["next Monday 9:30": Self.date(10, 19, 9, 30)], at: saturday)
                == Self.timed("standup", 10, 12, 9, 30))
        #expect(parse("next Tuesday", ["next Tuesday": Self.date(10, 20)], at: saturday).due == Self.due(10, 13))
        #expect(parse("next Sunday", ["next Sunday": Self.date(10, 18)], at: saturday).due == Self.due(10, 18))
        #expect(parse("next Monday call Bob", ["next Monday": Self.date(10, 19)]).due == Self.due(10, 12))  // Friday
        #expect(parse("next Monday call Bob", ["next Monday": Self.date(10, 19)], at: sunday).due == Self.due(10, 12))
        // Monday to Thursday: as it says.
        #expect(parse("next Friday", ["next Friday": Self.date(10, 23)], at: monday).due == Self.due(10, 23))
    }

    @Test func weeksCountFromMondayAsInChinese() {
        let (saturday, sunday) = (Self.saturday, Self.sunday)
        // The detector counts from Sunday here: on Saturday 10/10 it says 10/4 for 这周日, 10/11 for 下周日.
        #expect(parse("这周日开会", ["这周日": Self.date(10, 4)], at: saturday) == Self.allDay("开会", 10, 11))
        #expect(parse("本周日开会", ["本周日": Self.date(10, 4)], at: saturday) == Self.allDay("开会", 10, 11))
        #expect(parse("下周日开会", ["下周日": Self.date(10, 11)], at: saturday) == Self.allDay("开会", 10, 18))
        #expect(parse("下周一开会", ["下周一": Self.date(10, 12)], at: saturday) == Self.allDay("开会", 10, 12))
        #expect(parse("下个星期一开会", ["下个星期一": Self.date(10, 12)], at: saturday).due == Self.due(10, 12))
        #expect(parse("这个星期五开会", ["这个星期五": Self.date(10, 9)], at: saturday).due == Self.due(10, 9))  // over: shown so
        // The extra 下 (it reads 下周一 in 下下周一) goes with it; its time stays.
        #expect(parse("下下周一开会", ["下周一": Self.date(10, 19)], at: saturday) == Self.allDay("开会", 10, 19))
        #expect(parse("下周日下午3点开会", ["下周日下午3点": Self.date(10, 11, 15)], at: saturday) == Self.timed("开会", 10, 18, 15))
        // On a Sunday, 下周一 is the next day (it says 8 days ahead), 这周日 today.
        #expect(parse("下周一开会", ["下周一": Self.date(10, 19)], at: sunday) == Self.allDay("开会", 10, 12))
        #expect(parse("这周日开会", ["这周日": Self.date(10, 11)], at: sunday).due == Self.due(10, 11))
        #expect(parse("下周日开会", ["下周日": Self.date(10, 18)], at: sunday).due == Self.due(10, 18))
        // Next week without a day (the detector reads nothing): its Monday, all day.
        #expect(parse("下周开会", at: saturday) == Self.allDay("开会", 10, 12))
        #expect(parse("下周开会", at: sunday).due == Self.due(10, 12) && parse("下下周开会", at: sunday).due == Self.due(10, 19))
        #expect(parse("next week call Bob", at: saturday) == Self.allDay("call Bob", 10, 12))
        #expect(parse("下周开会").due == Self.due(10, 12))  // Friday
    }

    // MARK: - Titles

    @Test func titlesKeepWhatTheDateDoesNotSay() {
        // 之内 / 以内 after a date: by then.
        #expect(parse("周五之内交报告", ["周五": Self.date(10, 16)]) == Self.allDay("交报告", 10, 16))
        #expect(parse("周五以内交报告", ["周五": Self.date(10, 16)]).title == "交报告")
        // 下午茶, 早茶, 夜宵 are meals (it reads 「明天下午」 in 「明天下午茶」, at 15:00): in the title, all day.
        #expect(parse("明天下午茶", ["明天下午": Self.date(10, 10, 15)]) == Self.allDay("下午茶", 10, 10))
        #expect(parse("明天早茶", ["明天": Self.date(10, 10)]) == Self.allDay("早茶", 10, 10))
        #expect(parse("下午茶", ["下午": Self.date(10, 9, 15)]) == ReminderDraft(title: "下午茶"))
        // 明年 / 今年 / "next year" with a month and day (it reads only the month and day).
        #expect(parse("明年1月5日交报告", ["1月5日": Self.date(1, 5, year: 2027)]) == Self.allDay("交报告", 1, 5, year: 2027))
        #expect(parse("明年12月1日", ["12月1日": Self.date(12, 1)]) == Self.allDay("", 12, 1, year: 2027))
        #expect(parse("今年12月1日交报告", ["12月1日": Self.date(12, 1)]) == Self.allDay("交报告", 12, 1))
        #expect(parse("今年1月5日交报告", ["1月5日": Self.date(1, 5, year: 2027)]).due == Self.due(1, 5))  // as written: over
        #expect(parse("next year Jan 5 renew passport", ["Jan 5": Self.date(1, 5, year: 2027)])
                == Self.allDay("renew passport", 1, 5, year: 2027))
        #expect(parse("renew passport Oct 20, next year", ["Oct 20": Self.date(10, 20)]) == Self.allDay("renew passport", 10, 20, year: 2027))
        // "on the" / "the" that led into what it reads.
        #expect(parse("pay rent on the 15th of October", ["15th of October": Self.date(10, 15)]) == Self.allDay("pay rent", 10, 15))
        #expect(parse("pay rent the 15th of October", ["15th of October": Self.date(10, 15)]).title == "pay rent")
    }

    @Test func writtenToRepeatItIsSetOnceForTheNextTime() {
        // The words stay in the title, it is due the next time, and the row says it is once only.
        #expect(parse("每周一9点开会", ["周一9点": Self.date(10, 12, 9)]) == Self.once(Self.timed("每周一9点开会", 10, 12, 9)))
        #expect(parse("standup every Monday at 9", ["Monday at 9": Self.date(10, 12, 9)])
                == Self.once(Self.timed("standup every Monday at 9", 10, 12, 9)))
        #expect(parse("提醒我每周一9点开会", ["周一9点": Self.date(10, 12, 9)]).title == "每周一9点开会")
        // It reads only 下午 in 每周五下午: Friday is read here; said on a Friday, today's while still to come.
        #expect(parse("每周五下午开周会", ["下午": Self.date(10, 9, 15)], at: Self.at9am)
                == Self.once(Self.timed("每周五下午开周会", 10, 9, 15)))
        #expect(parse("每周五下午开周会", ["下午": Self.date(10, 9, 15)], at: Self.at9pm)
                == Self.once(Self.timed("每周五下午开周会", 10, 16, 15)))
        #expect(parse("每周五下午开周会", ["下午": Self.date(10, 9, 15)], at: Self.saturday)
                == Self.once(Self.timed("每周五下午开周会", 10, 16, 15)))
        #expect(parse("每天9点吃药") == Self.once(Self.timed("每天9点吃药", 10, 9, 21)))
        #expect(parse("每月15号交房租") == Self.once(Self.allDay("每月15号交房租", 10, 15)))
        #expect(parse("每月9号下午3点交房租", ["下午3点": Self.date(10, 9, 15)]) == Self.once(Self.timed("每月9号下午3点交房租", 11, 9, 15)))
        #expect(parse("每个周末大扫除").writtenAsRepeating && parse("every day at 9 stretch").writtenAsRepeating)
        // 每人 is no repeat.
        #expect(parse("每人明天交100元", ["明天": Self.date(10, 10)]) == Self.allDay("每人交100元", 10, 10))
        // The row; and Reminders gets that one date, without a repeat rule.
        let standup = Self.once(Self.timed("每周一9点开会", 10, 12, 9))
        #expect(standup.when(now: now, calendar: Self.calendar, chinese: true, clock24: true) == "10月12日 周一 9:00 · 只提醒这一次")
        #expect(standup.when(now: now, calendar: Self.calendar, chinese: false, clock24: true) == "Mon, Oct 12 9:00 · once only")
        #expect(standup.schedule(timeZone: Self.calendar.timeZone) == Self.timed("x", 10, 12, 9).schedule(timeZone: Self.calendar.timeZone))
    }

    @Test func whatAPhraseSays() {
        for phrase in ["下午3点", "9:30", "9：30", "3pm", "5 pm", "at 3", "tonight", "早上7点", "8点半", "十点", "noon"] {
            #expect(ReminderParser.mentionsTime(phrase), "\(phrase)")
        }
        for phrase in ["明天", "10月15日", "下周一", "Friday", "Oct 15", "12/25", "2026-10-15", "next week"] {
            #expect(!ReminderParser.mentionsTime(phrase), "\(phrase)")
        }
        for phrase in ["今晚8点", "明天下午", "后天", "周五", "星期三", "下周一 9:30", "15号", "10月15日", "tomorrow at 3pm",
                       "tonight", "today 5pm", "next Monday 9:30", "Friday 5pm", "Oct 15", "10/15 9:00", "the 15th"] {
            #expect(ReminderParser.mentionsDay(phrase), "\(phrase)")
        }
        for phrase in ["下午3点", "9am", "15:00", "8点半", "晚上9点", "5 pm", "10:30-11:00"] {
            #expect(!ReminderParser.mentionsDay(phrase), "\(phrase)")
        }
        // Clock times written without their half of the day.
        for phrase in ["3点半", "1:30", "明天3点", "Friday at 3", "today at 5", "十点", "12点", "5 o'clock"] {
            #expect(ReminderParser.bareClock(in: phrase) != nil, "\(phrase)")
        }
        for phrase in ["下午3点", "晚8点", "3pm", "9:30 am", "15:00", "明天", "tonight at 8", "凌晨3点"] {
            #expect(ReminderParser.bareClock(in: phrase) == nil, "\(phrase)")
        }
    }

    // MARK: - Durations (NSDataDetector misses them)

    @Test func minutesAndHoursFromNow() {
        let cases: [(String, Date, String)] = [
            ("30分钟后关火", Self.date(10, 9, 16, 30), "关火"),
            ("半小时后喝水", Self.date(10, 9, 16, 30), "喝水"),
            ("半个小时后喝水", Self.date(10, 9, 16, 30), "喝水"),
            ("两小时后开会", Self.date(10, 9, 18), "开会"),
            ("两个钟头以后开会", Self.date(10, 9, 18), "开会"),
            ("一个半小时后出发", Self.date(10, 9, 17, 30), "出发"),
            ("十分钟后", Self.date(10, 9, 16, 10), ""),
            ("提醒我二十五分钟之后拿快递", Self.date(10, 9, 16, 25), "拿快递"),
            ("1小时后", Self.date(10, 9, 17), ""),
            ("in 30 minutes check the oven", Self.date(10, 9, 16, 30), "check the oven"),
            ("in 30min check the oven", Self.date(10, 9, 16, 30), "check the oven"),
            ("call mom in 2 hours", Self.date(10, 9, 18), "call mom"),
            ("In an hour and a half: leave", Self.date(10, 9, 17, 30), "leave"),
            ("in half an hour stretch", Self.date(10, 9, 16, 30), "stretch"),
            ("Remind me in 2h to stretch", Self.date(10, 9, 18), "stretch"),
        ]
        for (text, when, title) in cases {
            let draft = parse(text)
            #expect(draft == ReminderDraft(title: title, due: Self.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: when),
                                           hasTime: true, date: when), "\(text): \(draft)")
        }
        // To the minute.
        let soon = parser().parse("5分钟后", now: Self.date(10, 9, 16).addingTimeInterval(40))
        #expect(soon.due == Self.due(10, 9, 16, 6) && soon.date == Self.date(10, 9, 16, 6))
    }

    @Test func aDurationKeepsItsMomentWhenTheClocksChange() {
        // 2026-11-01 01:50 PDT. 30 minutes on is 01:20 PST: the second 01:20 that night.
        let now = ISO8601DateFormatter().date(from: "2026-11-01T08:50:00Z")!
        let draft = parser().parse("30分钟后关火", now: now)
        #expect(draft.date == now.addingTimeInterval(30 * 60) && draft.due == Self.due(11, 1, 1, 20) && draft.hasTime)
        // The components alone name the first 01:20 (PDT), before now: neither the alarm nor 「已过」 go by them.
        #expect(Self.calendar.date(from: draft.due!)! < now && !draft.isPast(now: now, calendar: Self.calendar))
        #expect(draft.schedule(timeZone: Self.calendar.timeZone).alarm == now.addingTimeInterval(30 * 60))
        #expect(draft.when(now: now, calendar: Self.calendar, chinese: true, clock24: true) == "今天 1:20")
    }

    @Test func daysFromNowAreADay() {
        #expect(parse("3天后交报告") == Self.allDay("交报告", 10, 12))
        #expect(parse("两天后体检").due == Self.due(10, 11))
        #expect(parse("1周后复查").due == Self.due(10, 16))
        #expect(parse("in 3 days pay rent") == Self.allDay("pay rent", 10, 12))
        // NSDataDetector reads "in 3 days" itself (at noon): inside the duration, the duration decides, a day.
        #expect(parse("in 3 days pay rent", ["in 3 days": Self.date(10, 12)]) == Self.allDay("pay rent", 10, 12))
        // With a time of day right after (the detector reads only 下午3点): that day at that time.
        #expect(parse("两天后下午3点体检", ["下午3点": Self.date(10, 9, 15)]) == Self.timed("体检", 10, 11, 15))
        #expect(parse("3天后的上午10点开会", ["上午10点": Self.date(10, 9, 10)]) == Self.timed("开会", 10, 12, 10))
        #expect(parse("3天后3点开会") == Self.timed("开会", 10, 12, 15))
        // In English it reads the duration and the time as one phrase: the time counts, on the duration's day
        // (as of now, not of the detector's clock).
        #expect(parse("pay rent in 3 days at 3pm", ["in 3 days at 3pm": Self.date(10, 12, 15)]) == Self.timed("pay rent", 10, 12, 15))
        #expect(parse("in 2 days at 9am call mom", ["in 2 days at 9am": Self.date(10, 11, 9)]) == Self.timed("call mom", 10, 11, 9))
        #expect(parse("remind me to call Bob in 2 days at 3pm", ["in 2 days at 3pm": Self.date(10, 11, 15)])
                == Self.timed("call Bob", 10, 11, 15))
        #expect(parse("pay rent in 3 days at 3pm", ["in 3 days at 3pm": Self.date(10, 20, 15)]).due == Self.due(10, 12, 15, 0))
        // Not a duration: half a day, no amount, and other words.
        #expect(parse("1.5天后").due == nil && parse("半天后").due == nil && parse("0分钟后").due == nil)
        #expect(parse("within 2 hours").due == nil)
    }

    @Test func smallChineseNumbers() {
        let numbers: [String: Int?] = ["一": 1, "两": 2, "十": 10, "十五": 15, "二十": 20, "三十五": 35, "九十九": 99, "零五": 5,
                                       "一百": nil, "一二": nil, "十十": nil]
        for (text, value) in numbers { #expect(ReminderParser.chineseNumber(text) == value, "\(text)") }
        #expect(parse("3点零五开会").due == Self.due(10, 10, 15, 5) && parse("三点一刻", at: Self.at9am).due == Self.due(10, 9, 15, 15))
        #expect(parse("3点15开会", at: Self.at9am).due == Self.due(10, 9, 15, 15))
    }

    // MARK: - How it is shown, and what goes to Reminders

    @Test func whenItIsDue() {
        func when(_ due: DateComponents?, time: Bool, chinese: Bool, clock24: Bool = true) -> String {
            ReminderDraft(title: "x", due: due, hasTime: time).when(now: now, calendar: Self.calendar, chinese: chinese, clock24: clock24)
        }
        #expect(when(Self.due(10, 10, 15, 0), time: true, chinese: true) == "明天 15:00")
        #expect(when(Self.due(10, 10, 15, 0), time: true, chinese: false) == "tomorrow 15:00")
        #expect(when(Self.due(10, 15), time: false, chinese: true) == "10月15日 周四")
        #expect(when(Self.due(10, 15), time: false, chinese: false) == "Thu, Oct 15")
        #expect(when(Self.due(10, 12, 9, 30), time: true, chinese: true) == "10月12日 周一 9:30")
        #expect(when(Self.due(10, 11), time: false, chinese: true) == "后天")
        #expect(when(Self.due(10, 9, 17, 0), time: true, chinese: true) == "今天 17:00")
        #expect(when(nil, time: false, chinese: true) == "未设时间" && when(nil, time: false, chinese: false) == "no date")
        #expect(when(Self.due(1, 5, year: 2027), time: false, chinese: true) == "2027年1月5日 周二")
        #expect(when(Self.due(1, 5, year: 2027), time: false, chinese: false) == "Tue, Jan 5, 2027")
        // Over: 「已过」 / "overdue". Today's day without a time isn't over yet.
        #expect(when(Self.due(10, 9, 9, 0), time: true, chinese: true) == "今天 9:00 · 已过")
        #expect(when(Self.due(10, 9, 9, 0), time: true, chinese: false) == "today 9:00 · overdue")
        #expect(when(Self.due(10, 8), time: false, chinese: true) == "昨天 · 已过")
        #expect(when(Self.due(10, 9), time: false, chinese: true) == "今天")
        // With the 12-hour clock, when the Mac uses it.
        #expect(when(Self.due(10, 10, 15, 0), time: true, chinese: true, clock24: false) == "明天 下午3:00")
        #expect(when(Self.due(10, 10, 15, 0), time: true, chinese: false, clock24: false) == "tomorrow 3:00 PM")
        #expect(when(Self.due(10, 12, 9, 30), time: true, chinese: true, clock24: false) == "10月12日 周一 上午9:30")
        #expect(when(Self.due(10, 9, 9, 0), time: true, chinese: false, clock24: false) == "today 9:00 AM · overdue")
        #expect(ReminderDraft.clock(hour: 0, minute: 5, chinese: false, clock24: false) == "12:05 AM"
                && ReminderDraft.clock(hour: 12, minute: 0, chinese: true, clock24: false) == "下午12:00"
                && ReminderDraft.clock(hour: 9, minute: 5, chinese: true, clock24: true) == "9:05")
    }

    @Test func whatGoesToReminders() {
        let zone = Self.calendar.timeZone
        // A time: in the zone it was written in, the alarm at its moment.
        let timed = Self.timed("开会", 10, 10, 15).schedule(timeZone: zone)
        #expect(timed.alarm == Self.date(10, 10, 15))
        #expect(timed.due?.calendar?.identifier == .gregorian && timed.due?.timeZone == zone)
        #expect(timed.due?.year == 2026 && timed.due?.month == 10 && timed.due?.day == 10 && timed.due?.hour == 15 && timed.due?.minute == 0)
        // A day: all day and floating, no alarm.
        let day = Self.allDay("交房租", 10, 15).schedule(timeZone: zone)
        #expect(day.alarm == nil && day.due?.timeZone == nil && day.due?.hour == nil && day.due?.minute == nil)
        #expect(day.due?.calendar?.identifier == .gregorian && day.due?.day == 15)
        #expect(ReminderDraft(title: "买牛奶").schedule() == ReminderSchedule(due: nil, alarm: nil))
        // Without its moment (made elsewhere): the components' moment.
        #expect(ReminderDraft(title: "x", due: Self.due(10, 10, 15, 0), hasTime: true).schedule(timeZone: zone).alarm == Self.date(10, 10, 15))
    }

    @Test func remindersReadBackFromReminders() {
        // A day: that day.
        #expect(ReminderDraft(stored: "交房租", due: Self.due(10, 15), calendar: Self.calendar) == Self.allDay("交房租", 10, 15))
        // A time written in Tokyo: the same moment, here (09:00 there is 17:00 the day before in Pacific time).
        var tokyo = DateComponents(year: 2026, month: 10, day: 10, hour: 9, minute: 0)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")
        tokyo.calendar = Calendar(identifier: .gregorian)
        let call = ReminderDraft(stored: "打电话", due: tokyo, calendar: Self.calendar)
        #expect(call == Self.timed("打电话", 10, 9, 17))
        #expect(!call.isPast(now: now, calendar: Self.calendar) && call.isPast(now: Self.date(10, 9, 18), calendar: Self.calendar))
        // Without a zone: this one's.
        let morning = ReminderDraft(stored: "x", due: Self.due(10, 9, 9, 0), calendar: Self.calendar)
        #expect(morning == Self.timed("x", 10, 9, 9) && morning.isPast(now: now, calendar: Self.calendar))
        #expect(ReminderDraft(stored: "x", due: nil) == ReminderDraft(title: "x"))
        #expect(ReminderDraft(stored: "x", due: DateComponents(hour: 9)) == ReminderDraft(title: "x"))
    }

    // MARK: - The real NSDataDetector, relative to now

    /// Now, not in the last seconds of a day: the detector reads its own clock, and the expectations below
    /// are worked out from this `now`; across midnight the two would be different days.
    static func realNow() -> Date {
        let calendar = ReminderParser.localCalendar
        let now = Date()
        let left = calendar.dateInterval(of: .day, for: now)!.end.timeIntervalSince(now)
        guard left < 5 else { return now }
        Thread.sleep(forTimeInterval: left + 1)
        return Date()
    }

    /// `days` after `now`'s day at that time, as the draft's components.
    static func on(_ days: Int, at hour: Int, _ minute: Int = 0, from now: Date) -> DateComponents {
        let calendar = ReminderParser.localCalendar
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                       from: calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!)
    }

    /// Today's `hour:minute` if still to come at `now`, else tomorrow's.
    static func next(_ hour: Int, _ minute: Int = 0, from now: Date) -> DateComponents {
        let today = on(0, at: hour, minute, from: now)
        return ReminderParser.localCalendar.date(from: today)! > now ? today : on(1, at: hour, minute, from: now)
    }

    /// Minutes from now, as the parser rounds them.
    func fromNow(_ seconds: TimeInterval, _ draft: ReminderDraft, at now: Date) -> Bool {
        guard let date = draft.date else { return false }
        return abs(date.timeIntervalSince(now.addingTimeInterval(seconds))) <= 30 && draft.hasTime
    }

    /// Long runs of spaces after numbers (a pasted table row) are read in a moment, not seconds.
    @Test func manySpacesAreQuick() {
        let parser = ReminderParser()
        let texts = ["1" + String(repeating: " ", count: 300) + "x",
                     "12345678901234567890" + String(repeating: " ", count: 200) + "x",
                     String(repeating: "3 ", count: 150) + "天后开会",
                     "两" + String(repeating: " ", count: 300) + "个"]
        for text in texts {
            let start = Date()
            _ = parser.parse(text, now: Self.realNow())
            #expect(Date().timeIntervalSince(start) < 0.2, "\(text.prefix(20))…")
        }
        // Spaces inside a duration still read.
        #expect(fromNow(1800, parse("30 分钟 后关火"), at: now))
        #expect(fromNow(7200, parse("两 个 小时后开会"), at: now))
    }

    @Test func theSystemsDetectorInChinese() {
        let now = Self.realNow()
        let parser = ReminderParser()
        func parse(_ text: String) -> ReminderDraft { parser.parse(text, now: now) }
        let call = parse("明天下午3点给张三打电话")
        #expect(call.title == "给张三打电话" && call.due == Self.on(1, at: 15, from: now) && call.hasTime, "\(call)")
        let off = parse("30分钟后关火")
        #expect(off.title == "关火" && fromNow(30 * 60, off, at: now), "\(off)")
        let water = parse("半小时后提醒我喝水")
        #expect(water.title == "喝水" && fromNow(30 * 60, water, at: now), "\(water)")
        // Only a day: no time.
        let day = parse("明天给张三打电话")
        #expect(day.title == "给张三打电话" && !day.hasTime && day.due?.hour == nil && day.due?.day == Self.on(1, at: 0, from: now).day)
        // What it misses or reads wrong.
        let dinner = parse("明晚7点吃饭")
        #expect(dinner.title == "吃饭" && dinner.due == Self.on(1, at: 19, from: now), "\(dinner)")
        let meeting = parse("明早8点开会")
        #expect(meeting.title == "开会" && meeting.due == Self.on(1, at: 8, from: now), "\(meeting)")
        let lunch = parse("中午十二点吃饭")
        #expect(lunch.title == "吃饭" && lunch.due == Self.next(12, from: now), "\(lunch)")
        let pickUp = parse("3点半接孩子")
        #expect(pickUp.title == "接孩子" && pickUp.due == Self.next(15, 30, from: now), "\(pickUp)")
        #expect(parse("关于明天下午3点的会议").title == "关于会议")
        let report = parse("周五前交报告")
        #expect(report.title == "交报告" && !report.hasTime && report.due.flatMap { ReminderParser.localCalendar.date(from: $0) }
                .map { ReminderParser.localCalendar.component(.weekday, from: $0) } == 6, "\(report)")
        #expect(parse("提醒我一下明天交报告").title == "交报告")
        #expect(parse("买3斤苹果") == ReminderDraft(title: "买3斤苹果") && parse("晚一点出发").due == nil)
    }

    @Test func theSystemsDetectorInEnglish() {
        let now = Self.realNow()
        let parser = ReminderParser()
        func parse(_ text: String) -> ReminderDraft { parser.parse(text, now: now) }
        let call = parse("remind me to call Bob tomorrow at 3pm")
        #expect(call.title == "call Bob" && call.due == Self.on(1, at: 15, from: now), "\(call)")
        let oven = parse("in 2 hours check the oven")
        #expect(oven.title == "check the oven" && fromNow(2 * 3600, oven, at: now), "\(oven)")
        #expect(parse("buy milk") == ReminderDraft(title: "buy milk"))
        let rent = parse("pay rent in 3 days at 3pm")
        #expect(rent.title == "pay rent" && rent.due == Self.on(3, at: 15, from: now), "\(rent)")
        let lunch = parse("tomorrow lunch with Ann")
        #expect(lunch.title == "lunch with Ann" && !lunch.hasTime && lunch.due?.day == Self.on(1, at: 0, from: now).day, "\(lunch)")
        let leave = parse("at 5 leave")
        #expect(leave.title == "leave" && leave.due == Self.next(17, from: now), "\(leave)")
        let standup = parse("next Monday 9:30 standup")
        let weekday = ReminderParser.localCalendar.component(.weekday, from: now)
        #expect(standup.title == "standup" && standup.due?.hour == 9 && standup.due?.minute == 30, "\(standup)")
        if [6, 7, 1].contains(weekday) {  // Friday to Sunday: the coming Monday
            #expect(standup.due == Self.on((9 - weekday) % 7, at: 9, 30, from: now), "\(standup)")
        }
    }

    /// What the stand-ins above assume of it for the forms read together, weeks from Monday, and the rest.
    @Test func theSystemsDetectorWithWhatIsReadHere() {
        let now = Self.realNow()
        let parser = ReminderParser()
        let calendar = ReminderParser.localCalendar
        func parse(_ text: String) -> ReminderDraft { parser.parse(text, now: now) }
        /// `days` after today, as the components of a day.
        func day(_ days: Int) -> DateComponents {
            calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))!)
        }
        let meeting = parse("明天开会，3点")
        #expect(meeting.title == "开会" && meeting.due == Self.on(1, at: 15, from: now), "\(meeting)")
        let dentist = parse("at 5 dentist tomorrow")
        #expect(dentist.title == "dentist" && dentist.due == Self.on(1, at: 17, from: now), "\(dentist)")
        let party = parse("周五晚上 聚餐 7点")
        #expect(party.title == "聚餐" && party.due?.hour == 19 && party.hasTime, "\(party)")
        let movie = parse("8pm movie on Friday")
        #expect(movie.title == "movie" && movie.due?.hour == 20 && movie.due.flatMap { calendar.date(from: $0) }
                .map { calendar.component(.weekday, from: $0) } == 6, "\(movie)")
        // "next month" is no Monday.
        let rent = parse("pay rent on the 15th of next month")
        let nextMonth = calendar.dateComponents([.year, .month], from: calendar.date(byAdding: .month, value: 1, to: now)!)
        #expect(rent.title == "pay rent" && rent.due == DateComponents(year: nextMonth.year, month: nextMonth.month, day: 15), "\(rent)")
        // Weeks from Monday.
        let index = ReminderParser.mondayFirst(calendar.component(.weekday, from: now))
        for (text, days) in [("这周日开会", 6 - index), ("下周日开会", 13 - index), ("下下周一开会", 14 - index), ("下周开会", 7 - index)] {
            let draft = parse(text)
            #expect(draft == Self.allDayDraft("开会", day(days)), "\(text): \(draft)")
        }
        let tea = parse("明天下午茶")
        #expect(tea == Self.allDayDraft("下午茶", day(1)), "\(tea)")
        let weekly = parse("每周一9点开会")
        #expect(weekly.title == "每周一9点开会" && weekly.writtenAsRepeating && weekly.due?.hour == 9, "\(weekly)")
        let soon = parse("1个月后复查")
        let inAMonth = calendar.date(byAdding: .month, value: 1, to: calendar.startOfDay(for: now))!
        #expect(soon == Self.allDayDraft("复查", calendar.dateComponents([.year, .month, .day], from: inAMonth)), "\(soon)")
    }

    static func allDayDraft(_ title: String, _ day: DateComponents) -> ReminderDraft { ReminderDraft(title: title, due: day) }

    /// The sentences of the behaviour review, with the real detector: points aren't times, the titles, fixed days.
    @Test func theSystemsDetectorWithPointsTitlesAndFixedDays() {
        let now = Self.realNow()
        let parser = ReminderParser()
        let calendar = ReminderParser.localCalendar
        func parse(_ text: String) -> ReminderDraft { parser.parse(text, now: now) }
        let today = calendar.startOfDay(for: now)
        func components(_ date: Date) -> DateComponents { calendar.dateComponents([.year, .month, .day], from: date) }
        func weekday(_ draft: ReminderDraft) -> Int? { draft.due.flatMap { calendar.date(from: $0) }.map { calendar.component(.weekday, from: $0) } }
        /// The next `month`/`dayOfMonth`, today counting.
        func coming(_ month: Int, _ dayOfMonth: Int) -> DateComponents {
            let year = calendar.component(.year, from: today)
            let thisYear = calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
            return components(thisYear >= today ? thisYear : calendar.date(byAdding: .year, value: 1, to: thisYear)!)
        }
        let tomorrow = components(calendar.date(byAdding: .day, value: 1, to: today)!)
        let nextMonth = components(calendar.dateInterval(of: .month, for: calendar.date(byAdding: .month, value: 1, to: today)!)!.start)
        // 「N点」 counting points: the day alone, all day, and the words stay.
        #expect(parse("明天交报告，写3点建议") == Self.allDayDraft("交报告，写3点建议", tomorrow))
        #expect(parse("明天开会讨论两点问题") == Self.allDayDraft("开会讨论两点问题", tomorrow))
        let points = parse("周五开会，提两点建议"), opinions = parse("周五前列出5点意见")
        #expect(points.title == "开会，提两点建议" && !points.hasTime && weekday(points) == 6, "\(points)")
        #expect(opinions.title == "列出5点意见" && !opinions.hasTime && weekday(opinions) == 6, "\(opinions)")
        // Still times.
        #expect(parse("明天3点开会") == ReminderDraft(title: "开会", due: Self.on(1, at: 15, from: now), hasTime: true,
                                                    date: calendar.date(from: Self.on(1, at: 15, from: now))))
        #expect(parse("3点半接孩子").due == Self.next(15, 30, from: now))
        // Titles.
        let report = parse("周五前提交报告")
        #expect(report.title == "提交报告" && !report.hasTime && weekday(report) == 6, "\(report)")
        let data = parse("下午3点前提供数据")
        #expect(data.title == "提供数据" && data.due?.hour == 15, "\(data)")
        #expect(parse("明天是小王生日") == Self.allDayDraft("小王生日", tomorrow))
        // Fixed days.
        #expect(parse("下个月交报告") == Self.allDayDraft("交报告", nextMonth))
        #expect(parse("月初交房租") == Self.allDayDraft("交房租", calendar.component(.day, from: today) == 1 ? components(today) : nextMonth))
        #expect(parse("下月初交房租") == Self.allDayDraft("交房租", nextMonth))
        #expect(parse("年底交报告") == Self.allDayDraft("交报告", coming(12, 31)))
        #expect(parse("元旦去爬山") == Self.allDayDraft("去爬山", coming(1, 1)))
        #expect(parse("圣诞节买礼物") == Self.allDayDraft("买礼物", coming(12, 25)))
        #expect(parse("pay rent next month") == Self.allDayDraft("pay rent", nextMonth))
        #expect(parse("finish the report by the end of the year") == Self.allDayDraft("finish the report", coming(12, 31)))
        // Lunar holidays move: not read.
        #expect(parse("中秋回家") == ReminderDraft(title: "中秋回家") && parse("春节回家") == ReminderDraft(title: "春节回家"))
        // Brackets that were empty stay in the title; a decimal before the day is a number.
        #expect(parse("明天修复 parse() 崩溃") == Self.allDayDraft("修复 parse() 崩溃", tomorrow))
        #expect(parse("明天 call foo() again") == Self.allDayDraft("call foo() again", tomorrow))
        #expect(parse("明天给数组[]加测试") == Self.allDayDraft("给数组[]加测试", tomorrow))
        #expect(parse("评分9.8的电影明天看") == Self.allDayDraft("评分9.8的电影看", tomorrow))
        #expect(parse("血压12.8 明天复查") == Self.allDayDraft("血压12.8复查", tomorrow))
    }

    @Test func aLongTextFullOfDatesIsReadQuickly() {
        // Read on the main thread as @reminder ⏎ is pressed (a long text from the clipboard): one with a date every
        // few characters took most of a second, each date looking for meals in all of the text.
        let unit = "明天下午3点开会，周五前交报告，10月15日交房租，3点半接孩子，晚饭7点，下周一 9:30，15号，"
            + "tomorrow lunch at noon, dinner at 7 on Friday, "
        let text = String(String(repeating: unit, count: 40).prefix(2000))
        let parser = ReminderParser()
        _ = parser.parse("明天", now: Date())  // the detector is made on first use
        let start = Date()
        let draft = parser.parse(text, now: Date())
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.05, "\(Int(elapsed * 1000)) ms")
        #expect(draft.hasTime && draft.title.hasPrefix("开会，周五前交报告") && draft.title.count > 1900, "\(draft.title.prefix(40))")
        // Dates are read in the first 500 characters; the title is all of the text.
        let late = String(repeating: "备注", count: 300) + "明天交报告"
        #expect(parse(late, ["明天": Self.date(10, 10)]) == ReminderDraft(title: late))
        let early = "明天交报告，" + String(repeating: "备注", count: 300)
        #expect(parse(early, ["明天": Self.date(10, 10)]) == Self.allDay("交报告，" + String(repeating: "备注", count: 300), 10, 10))
    }
}

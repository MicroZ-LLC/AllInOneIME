import Foundation

/// A reminder read from an `@reminder` text, shown to confirm before it goes into Apple Reminders:
/// "明天下午3点给张三打电话" → 「给张三打电话」, due tomorrow at 15:00 with an alarm then.
public struct ReminderDraft: Equatable, Sendable {
    /// What to be reminded of: the text without its date and time (with them when written to repeat).
    public var title: String
    /// When it is due, in the Gregorian calendar: year, month and day, plus hour and minute with
    /// `hasTime`. Nil: no date.
    public var due: DateComponents?
    /// A time of day was written: due then, with an alarm. Without one it is due that day, no alarm.
    public var hasTime: Bool
    /// The moment it is due, with a time: what the alarm and `isPast` go by. The components can't always
    /// say it: the night summer time ends, 1:20 comes twice, and "30分钟后" said at 1:50 means the second.
    public var date: Date?
    /// Written to repeat (「每周一9点开会」, "standup every Monday at 9"): due the next time only, as Reminders gets
    /// no repeat rule. The title keeps those words, and `when` says it is once only.
    public var writtenAsRepeating: Bool

    public init(title: String, due: DateComponents? = nil, hasTime: Bool = false, date: Date? = nil,
                writtenAsRepeating: Bool = false) {
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.date = date
        self.writtenAsRepeating = writtenAsRepeating
    }

    /// Whether the time it is due (without a time: the day) is over at `now`.
    public func isPast(now: Date, calendar: Calendar = ReminderParser.localCalendar) -> Bool {
        if hasTime, let date { return date < now }
        guard let due, let day = calendar.date(from: due) else { return false }
        return hasTime ? day < now : calendar.startOfDay(for: day) < calendar.startOfDay(for: now)
    }

    /// When it is due, as the panel and the notice say it: 「明天 15:00」 (「明天 下午3:00」 with the 12-hour
    /// clock), 「10月15日 周四」, 「未设时间」 ("tomorrow 3:00 PM", "Thu, Oct 15", "no date"), with 「只提醒这一次」 /
    /// "once only" when written to repeat, and 「已过」 / "overdue" once that time is over.
    public func when(now: Date, calendar: Calendar = ReminderParser.localCalendar, chinese: Bool,
                     clock24: Bool = ReminderDraft.systemUses24HourClock) -> String {
        guard let due, let date = calendar.date(from: due) else { return chinese ? "未设时间" : "no date" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        var text: String
        switch days {
        case 0: text = chinese ? "今天" : "today"
        case 1: text = chinese ? "明天" : "tomorrow"
        case 2 where chinese: text = "后天"
        case -1: text = chinese ? "昨天" : "yesterday"
        default:
            // Fixed wording rather than the locale's formats: it sits next to the Chinese or English panel text.
            let weekday = calendar.component(.weekday, from: date) - 1
            let (year, month, day) = (calendar.component(.year, from: date), calendar.component(.month, from: date),
                                      calendar.component(.day, from: date))
            let otherYear = year != calendar.component(.year, from: now)
            if chinese {
                text = (otherYear ? "\(year)年" : "") + "\(month)月\(day)日 " + ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][weekday]
            } else {
                let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
                text = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday] + ", \(months[month - 1]) \(day)"
                    + (otherYear ? ", \(year)" : "")
            }
        }
        if hasTime, let hour = due.hour, let minute = due.minute {
            text += " " + Self.clock(hour: hour, minute: minute, chinese: chinese, clock24: clock24)
        }
        // 「每周一」 asked for more than this one: say that only this one is set.
        if writtenAsRepeating { text += chinese ? " · 只提醒这一次" : " · once only" }
        if isPast(now: now, calendar: calendar) { text += chinese ? " · 已过" : " · overdue" }
        return text
    }

    /// A time of day the way this Mac shows times: "15:00" with the 24-hour clock, else 「下午3:00」 / "3:00 PM".
    public static func clock(hour: Int, minute: Int, chinese: Bool, clock24: Bool) -> String {
        if clock24 { return String(format: "%d:%02d", hour, minute) }
        let time = String(format: "%d:%02d", hour % 12 == 0 ? 12 : hour % 12, minute)
        if chinese { return (hour < 12 ? "上午" : "下午") + time }
        return time + (hour < 12 ? " AM" : " PM")
    }

    /// Whether this Mac shows times with the 24-hour clock (System Settings → General → Date & Time).
    /// Read each time: the setting can change while the input method runs.
    public static var systemUses24HourClock: Bool {
        switch Locale.autoupdatingCurrent.hourCycle {
        case .zeroToTwentyThree, .oneToTwentyFour: return true
        default: return false
        }
    }
}

/// What goes to Apple Reminders for a draft (`ReminderDraft.schedule`).
public struct ReminderSchedule: Equatable, Sendable {
    /// The due date as EventKit takes it (with the Gregorian calendar, without which it raises an
    /// exception): a day without a time is all day and floats; a time keeps the zone it was written in.
    public var due: DateComponents?
    /// When the alarm goes off: the moment it is due, for a draft with a time.
    public var alarm: Date?
}

extension ReminderDraft {
    /// The due date and alarm for Reminders. The alarm is the exact moment (`date`), not the components
    /// read again: those can name the hour that comes twice when summer time ends.
    public func schedule(timeZone: TimeZone = .current) -> ReminderSchedule {
        guard var due else { return ReminderSchedule(due: nil, alarm: nil) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        due.calendar = calendar
        guard hasTime else {
            (due.hour, due.minute, due.second, due.nanosecond, due.timeZone) = (nil, nil, nil, nil, nil)
            return ReminderSchedule(due: due, alarm: nil)
        }
        due.timeZone = timeZone
        return ReminderSchedule(due: due, alarm: date ?? calendar.date(from: due))
    }

    /// A reminder as Reminders keeps it, read in `calendar` (this Mac's zone): a time written in another
    /// zone keeps its moment (and is shown in this one); a day without a time stays that day.
    public init(stored title: String, due components: DateComponents?, calendar: Calendar = ReminderParser.localCalendar) {
        self.init(title: title)
        guard let components, let year = components.year, let month = components.month, let day = components.day else { return }
        guard components.hour != nil else {
            due = DateComponents(year: year, month: month, day: day)
            return
        }
        var written = components.calendar ?? Calendar(identifier: .gregorian)
        written.timeZone = components.timeZone ?? calendar.timeZone
        guard let moment = written.date(from: components) else { return }
        due = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moment)
        hasTime = true
        date = moment
    }
}

/// Reads the date and time in a reminder's text, on this Mac: nothing is sent anywhere.
///
/// NSDataDetector finds most dates and times ("明天下午3点", "下周一 9:30", "tomorrow at 3pm"). What it misses
/// or gets wrong is read here:
/// - 明早 / 今早 / 明晚 and 早8点, which it reads written out (明天早上, 早上8点);
/// - a part of the day and a clock time after it, in that half of the day ("中午十二点", "傍晚6点"; it reads
///   中午 alone, or nothing);
/// - a clock time without its half of the day ("3点半", "8点", "1:30", "at 5"): the next of h:mm and
///   (h+12):mm, never 0:00–5:59 unless 凌晨 / 半夜 is written; with dinner, in the evening ("dinner at 7"); not a
///   「N点」 that counts what follows it (「写3点建议」, 「两点问题」);
/// - days: "15号" and "on the 15th" (the next 15th), 10.1 / 11.11 as a month and day (not 10.15元, v1.2 or 评分9.8,
///   nor with another day in the text: 「血压12.8 明天复查」), 周末 / "this weekend", 月底 / "end of the month", 下周 /
///   "next week" (next Monday), 下个月 / "next month" (its 1st), 月初 (the 1st), 年底 / "end of the year" (Dec 31), 元旦
///   and 圣诞节 (not the lunar holidays, which move), and 明年 / 今年 / "next year" with a month and day;
/// - "noon", and durations ("30分钟后", "半小时后", "3天后", "1个月后", "in 2 hours", "30 minutes from now",
///   "2 hours later"), with a time of day after a number of days ("3天后下午3点", "in 3 days at 3pm");
/// - weeks from Monday, as Chinese counts them (下周日, 这周日, 下下周一; it counts from Sunday where the region
///   does), and "next Monday" said Friday to Sunday: the coming one, like 下周一;
/// - a meal ("tomorrow lunch", 「明天下午茶」) stays in the title.
/// The first date or time in the text is the reminder's, completed from another one anywhere in the text: the
/// time of a day alone ("明天开会，3点"; a bare 「N点」 only when it ends its clause), the day of a time alone ("at 5
/// dentist tomorrow"), the clock time of a part of the day (「周五晚上 聚餐 7点」). A time of day without a day that
/// has already passed today means tomorrow, but a part of the day still going (下午 at 16:00, 今晚 at 21:30) is
/// today, all day; a month and day already past this year is next year's. The rest of the text is the title,
/// without a leading 「提醒我」 / "remind me to". Written to repeat (每周一9点, "every Monday at 9"), it is due the
/// next time, once, and the text stays whole. Dates are read in the first `readLength` characters only.
public struct ReminderParser: Sendable {
    /// A date or time found in a text: where it is written and the moment it means.
    public struct Match: Equatable, Sendable {
        public var range: Range<String.Index>
        public var date: Date

        public init(range: Range<String.Index>, date: Date) {
            self.range = range
            self.date = date
        }
    }

    /// Finds the dates and times in a text. The system's (`dataDetector`) works from the real clock;
    /// tests pass their own, so what they expect doesn't depend on today's date. It is given the text
    /// as the rules read it (`Written`: 明晚 → 明天晚上 …).
    public var detect: @Sendable (String) -> [Match]
    /// What the due date's components are in (Gregorian, in the Mac's time zone).
    public var calendar: Calendar

    public init(calendar: Calendar = ReminderParser.localCalendar,
                detect: @escaping @Sendable (String) -> [Match] = ReminderParser.dataDetector) {
        self.calendar = calendar
        self.detect = detect
    }

    /// The Gregorian calendar in the Mac's time zone as of now (it may change when travelling). Not
    /// `Calendar.current`, which can be another calendar: Reminders takes Gregorian components.
    public static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// The system's date detection (NSDataDetector).
    public static let dataDetector: @Sendable (String) -> [Match] = { text in
        guard let detector = sharedDetector else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { result in
            guard let date = result.date, let range = Range(result.range, in: text) else { return nil }
            return Match(range: range, date: date)
        }
    }

    /// Made once (that takes a few milliseconds) and shared: like any NSRegularExpression it is immutable.
    private static let sharedDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// Dates are read in the first this many characters of a text (its title is all of it): `parse` runs on the main
    /// thread, as `@reminder` ⏎ is pressed, and a long clipboard text full of dates would hold it up.
    public static let readLength = 500

    /// The reminder in `text`, as of `now`.
    public func parse(_ text: String, now: Date) -> ReminderDraft {
        let written = Written(text, reading: Self.readLength)
        let source = written.text
        let night = source.contains("凌晨") || source.contains("半夜")
        let weekdays = self.weekdays(in: source, now: now)
        var durations = Self.durations(in: source)
        var found = detected(in: source, now: now, weekdays: weekdays) + own(in: source, now: now) + weekdays
        // 10.1 is a month and day only when nothing else in the text says when: in 「评分9.8的电影明天看」 or 「血压12.8
        // 明天复查」 the day is 明天, and the number only a number (the first reading would be the reminder's).
        if !durations.isEmpty || found.contains(where: { $0.day != nil && !$0.dotted }) { found.removeAll(where: \.dotted) }
        var phrases = Self.merged(found, in: source)
        // A date read inside a duration is the duration's ("in 3 days", which the detector reads too). One that
        // covers it and goes on with a time ("in 3 days at 3pm"), or a time right after it ("3天后下午3点"),
        // is that day's time.
        for index in durations.indices {
            let duration = durations[index]
            phrases.removeAll { phrase in
                guard phrase.range.overlaps(duration.range) else { return false }
                if duration.isDays, durations[index].time == nil, phrase.range.upperBound > duration.range.upperBound,
                   let time = phrase.time {
                    durations[index].time = time
                    durations[index].extent = duration.range.lowerBound..<phrase.range.upperBound
                }
                return true
            }
            if duration.isDays, durations[index].time == nil,
               let next = phrases.firstIndex(where: { $0.range.lowerBound >= duration.range.upperBound }),
               phrases[next].day == nil, let time = phrases[next].time,
               Self.onlyJoins(source[duration.range.upperBound..<phrases[next].range.lowerBound]) {
                durations[index].time = time
                durations[index].extent = duration.range.lowerBound..<phrases[next].range.upperBound
                phrases.remove(at: next)
            }
        }
        // Every reading in the text's order (a duration first where a phrase starts too): the first is the reminder's.
        let readings = (durations.map { reading(of: $0, now: now) } + phrases).enumerated()
            .sorted { ($0.element.range.lowerBound, $0.offset) < ($1.element.range.lowerBound, $1.offset) }
            .map(\.element)
        guard var chosen = readings.first else { return ReminderDraft(title: Self.title(text, without: [])) }
        // What it lacks, from another one anywhere in the text: the time of a day alone (「明天开会，3点」), the day
        // of a time alone ("at 5 dentist tomorrow"), the clock time of a part of the day (「周五晚上 聚餐 7点」).
        var ranges = [chosen.range]
        for other in readings.dropFirst() {
            // A 「N点」 with more of its clause after it may count things (「明天交报告，写3点东西」): not this day's time.
            guard !Self.isLooseClock(other, in: source), let both = Self.combined(chosen, other) else { continue }
            chosen = both
            ranges.append(other.range)
        }
        guard let found = moment(of: chosen, now: now, night: night) else {
            return ReminderDraft(title: Self.title(text, without: []))
        }
        var date = found.date
        let hasTime = found.hasTime
        // Written to repeat (每周一9点, "every Monday at 9"): the next time, set once (Reminders gets no repeat
        // rule); the words stay in the title, which then still says what was meant.
        if let marker = ranges.lazy.compactMap({ Self.repeatMarker(before: $0.lowerBound, in: source) }).first {
            let step = Self.repeatStep(marker: marker, phrase: String(source[ranges[0]]))
            let today = calendar.startOfDay(for: now)
            var steps = 0
            while steps < 12, hasTime ? date < now : date < today, let next = calendar.date(byAdding: step, to: date) {
                date = next
                steps += 1
            }
            return draft(Self.title(text, without: []), date: date, hasTime: hasTime, repeating: true)
        }
        return draft(Self.title(written.original, without: ranges.map(written.originalRange)), date: date, hasTime: hasTime)
    }

    private func draft(_ title: String, date: Date, hasTime: Bool, repeating: Bool = false) -> ReminderDraft {
        let fields: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        return ReminderDraft(title: title, due: calendar.dateComponents(fields, from: date), hasTime: hasTime,
                             date: hasTime ? date : nil, writtenAsRepeating: repeating)
    }

    /// A duration as a reading: minutes and hours from now are a moment (to the minute, the moment itself: the
    /// alarm goes off then, also across a change of the clocks); days, weeks and months are a day, or that day at
    /// the time written with them.
    private func reading(of duration: Duration, now: Date) -> Phrase {
        let today = calendar.startOfDay(for: now), amount = Int(duration.amount)
        let day: Date?
        switch duration.unit {
        case .minute, .hour:
            let seconds = duration.amount * (duration.unit == .minute ? 60 : 3600)
            let date = Date(timeIntervalSinceReferenceDate: ((now.timeIntervalSinceReferenceDate + seconds) / 60).rounded() * 60)
            return Phrase(range: duration.range, exact: date)
        case .day: day = calendar.date(byAdding: .day, value: amount, to: today)
        case .week: day = calendar.date(byAdding: .day, value: 7 * amount, to: today)
        case .month: day = calendar.date(byAdding: .month, value: amount, to: today)
        }
        return Phrase(range: duration.time == nil ? duration.range : duration.extent,
                      day: calendar.dateComponents([.year, .month, .day], from: day ?? today), time: duration.time)
    }

    // MARK: - When a phrase is

    /// A date or time read from the text (as the rules read it): where, the day it names (year, month,
    /// day), and the time of day it gives.
    struct Phrase {
        var range: Range<String.Index>
        var day: DateComponents?
        var time: Time?
        /// The part of the day its time stands for, with no clock time written (下午, 今晚, tonight): roughly then.
        /// A clock time elsewhere says when (「周五晚上 聚餐 7点」); while it is still going it is today, all day.
        var part: String?
        /// A moment from now ("30分钟后", "in 2 hours"): nothing to add to it.
        var exact: Date?
        /// Found by the detector (for the same words, its reading stands).
        var detected = false
        /// A month and day written with a dot (10.1, 11.11): read only when nothing else in the text says when.
        var dotted = false
    }

    /// A time of day as written. `ambiguous`: without its half of the day ("3点", "1:30", "at 5"), so h or
    /// h+12. An hour of 24 is midnight at the end of the day (晚上12点).
    struct Time: Equatable {
        var hour: Int
        var minute: Int
        var ambiguous = false

        /// The time in `part` of the day when written without its half (晚上 and 7点: 19:00); else as written.
        func within(_ part: String) -> Time {
            guard ambiguous, let hour = ReminderParser.hour(hour, in: part) else { return self }
            return Time(hour: hour, minute: minute)
        }
    }

    /// When `phrase` is: its moment, its day (all day), its time of day on that day, or a time of day alone, the
    /// next one. A part of the day still going when its usual time is over (今晚 at 21:30, 下午 at 16:03) is
    /// today, all day, rather than a time already past or tomorrow's.
    private func moment(of phrase: Phrase, now: Date, night: Bool) -> (date: Date, hasTime: Bool)? {
        if let exact = phrase.exact { return (exact, true) }
        let day = phrase.day.flatMap { calendar.date(from: $0) }
        guard let time = phrase.time else { return day.map { ($0, false) } }
        if let part = phrase.part, day.map({ calendar.isDate($0, inSameDayAs: now) }) ?? true,
           let today = stillGoing(part, usually: time, now: now) {
            return (today, false)
        }
        return moment(time, on: day, now: now, night: night).map { ($0, true) }
    }

    /// Today, when `part` of the day is still going at `now` but its usual time (`usually`, the detector's) is over.
    private func stillGoing(_ part: String, usually time: Time, now: Date) -> Date? {
        let today = calendar.startOfDay(for: now)
        guard let end = Self.end(of: part), time.hour < 24,
              let usual = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: today), usual <= now,
              let over = end < 24 ? calendar.date(bySettingHour: end, minute: 0, second: 0, of: today)
                                  : calendar.date(byAdding: .day, value: 1, to: today),
              now < over else { return nil }
        return today
    }

    /// The moment `time` means: on `day` (still that day if it is over, and today the one still to come), or
    /// without a day the next such time from now. A clock time without its half of the day is h:mm or
    /// (h+12):mm, never 0:00–5:59 unless `night` (凌晨 / 半夜 is written); 12点 is noon.
    private func moment(_ time: Time, on day: Date?, now: Date, night: Bool) -> Date? {
        var hours = [time.hour]
        if time.ambiguous, time.hour < 12 { hours = [time.hour, time.hour + 12].filter { night || $0 >= 6 } }
        func candidates(on day: Date) -> [Date] {
            hours.compactMap { hour in
                calendar.date(byAdding: .day, value: hour / 24, to: day).flatMap {
                    calendar.date(bySettingHour: hour % 24, minute: time.minute, second: 0, of: $0)
                }
            }.sorted()
        }
        if let day {
            let all = candidates(on: day)
            return calendar.isDate(day, inSameDayAs: now) ? all.first { $0 > now } ?? all.last : all.first
        }
        let today = calendar.startOfDay(for: now)
        if let next = candidates(on: today).first(where: { $0 > now }) { return next }
        return calendar.date(byAdding: .day, value: 1, to: today).flatMap { candidates(on: $0).first }
    }

    /// What the detector found, each read again here: the day if it names one, the time of day (a clock time
    /// written without its half of the day is read here: the detector guesses), "next Monday", the year of a month
    /// and day, and the weekdays read here (`weekdays`).
    private func detected(in source: String, now: Date, weekdays: [Phrase]) -> [Phrase] {
        let years = Self.yearWords(in: source)
        return detect(source).compactMap { match -> Phrase? in
            // A meal it takes for a time ("tomorrow lunch", 「明天下午茶」) is what the reminder is for; 「晚一点」
            // ("a bit later"), which it reads as 13:00, is no time.
            var range = Self.withoutALittle(Self.withoutMeal(match.range, in: source), in: source)
            guard !range.isEmpty else { return nil }
            let phrase = String(source[range])
            var time: Time?, part: String?
            if let clock = Self.bareClock(in: phrase) {
                // Its guess at the half of the day doesn't count, the dinner it read with it does ("dinner at 7").
                time = Self.hasEveningMeal(source[match.range]) ? clock.within("晚上") : clock
            } else if Self.mentionsTime(phrase) {
                let parts = calendar.dateComponents([.hour, .minute], from: match.date)
                time = Time(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
                if Self.clocks(in: phrase).isEmpty { part = Self.part(in: phrase) }
            }
            var day: DateComponents?
            if Self.mentionsDay(phrase) || time == nil { day = calendar.dateComponents([.year, .month, .day], from: match.date) }
            if let coming = comingWeekday(in: phrase, now: now) { day = coming }
            // A month and day: in the year written with it (明年1月5日, "Jan 5 next year"), else the next one.
            if let found = day, Self.namesMonthAndDay(phrase), !Self.namesYear(phrase) {
                if let word = years.first(where: { Self.nextTo($0.range, range, in: source) }) {
                    day?.year = calendar.component(.year, from: now) + word.years
                    range = min(range.lowerBound, word.range.lowerBound)..<max(range.upperBound, word.range.upperBound)
                } else {
                    day = notPast(found, now: now)
                }
            }
            // 下周日, 这周日, 下下周一, 每周五: that day as read here (the time stays the detector's).
            if let weekday = weekdays.first(where: { $0.range.overlaps(range) }) {
                day = weekday.day
                range = min(range.lowerBound, weekday.range.lowerBound)..<max(range.upperBound, weekday.range.upperBound)
            }
            return Phrase(range: range, day: day, time: time, part: part, detected: true)
        }
    }

    /// A month and day written without a year that is over this year: next year's.
    private func notPast(_ day: DateComponents, now: Date) -> DateComponents {
        guard let date = calendar.date(from: day), date < calendar.startOfDay(for: now),
              let next = calendar.date(byAdding: .year, value: 1, to: date) else { return day }
        return calendar.dateComponents([.year, .month, .day], from: next)
    }

    /// What the detector misses, read here: clock times (with the part of the day before them, if any), "noon",
    /// days of the month ("15号", "on the 15th"), a month and day as 10.1, 元旦 and 圣诞节, and 周末, 月底, 下周, 下个月,
    /// 月初, 年底 (`spans`).
    private func own(in source: String, now: Date) -> [Phrase] {
        var found: [Phrase] = []
        for clock in Self.clocks(in: source) {
            if clock.meridiem == nil, let part = Self.partOfDay(before: clock.range.lowerBound, in: source) {
                // 中午十二点, 傍晚6点, 晚上 7点半: that half of the day.
                guard let hour = Self.hour(clock.hour, in: part.word) else { continue }
                found.append(Phrase(range: part.start..<clock.range.upperBound, time: Time(hour: hour, minute: clock.minute)))
            } else if Self.hasEveningMeal(source[..<clock.range.lowerBound], atEnd: true) {
                // "dinner at 7", 「晚饭 7点」: in the evening (the meal stays in the title).
                found.append(Phrase(range: clock.range, time: clock.time.within("晚上")))
            } else {
                found.append(Phrase(range: clock.range, time: clock.time))
            }
        }
        for match in Self.noon.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            if let range = Range(match.range, in: source) { found.append(Phrase(range: range, time: Time(hour: 12, minute: 0))) }
        }
        for (range, number) in Self.daysOfMonth(in: source) + Self.ordinalDays(in: source) {
            if let day = dayOfMonth(number, now: now) { found.append(Phrase(range: range, day: day)) }
        }
        let years = Self.yearWords(in: source)
        // A month and day without a year: in the year written with it (明年5.20, 明年圣诞节), else the next one.
        func add(month: Int, day: Int, at written: Range<String.Index>, dotted: Bool = false) {
            let word = years.first { Self.nextTo($0.range, written, in: source) }
            let year = calendar.component(.year, from: now) + (word?.years ?? 0)
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.day, from: date) == day else { return }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            let range = word.map { min($0.range.lowerBound, written.lowerBound)..<max($0.range.upperBound, written.upperBound) }
            found.append(Phrase(range: range ?? written, day: word == nil ? notPast(components, now: now) : components,
                                dotted: dotted))
        }
        for written in Self.dottedDates(in: source) { add(month: written.month, day: written.day, at: written.range, dotted: true) }
        for match in Self.holidays.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let range = Range(match.range, in: source) else { continue }
            if source[range].hasPrefix("元旦") { add(month: 1, day: 1, at: range) } else { add(month: 12, day: 25, at: range) }
        }
        return found + spans(in: source, now: now)
    }

    /// Holidays on a fixed day: 元旦 (Jan 1), 圣诞节 (Dec 25). The lunar ones (春节, 中秋) move, and aren't read.
    private static let holidays = try! NSRegularExpression(pattern: "元旦节?|圣诞节")

    /// Phrases that overlap are one (the detector's 「明天中午」 and 「中午十二点」 read here); a day and a time
    /// of day right next to each other too ("15号下午3点", "周五 傍晚6点"). In order.
    static func merged(_ phrases: [Phrase], in source: String) -> [Phrase] {
        let sorted = phrases.sorted {
            if $0.range.lowerBound != $1.range.lowerBound { return $0.range.lowerBound < $1.range.lowerBound }
            if $0.range.upperBound != $1.range.upperBound { return $0.range.upperBound > $1.range.upperBound }
            return $0.detected && !$1.detected
        }
        var out: [Phrase] = []
        for phrase in sorted {
            guard var last = out.last else {
                out.append(phrase)
                continue
            }
            if phrase.range.lowerBound < last.range.upperBound {
                // Inside the one before: that reading stands (the detector's, for the same words).
                guard phrase.range.upperBound > last.range.upperBound else { continue }
                // Going on past it: the later one reads the clock time (「中午」 + 「中午十二点」).
                last.range = last.range.lowerBound..<phrase.range.upperBound
                last.day = last.day ?? phrase.day
                if let time = phrase.time { (last.time, last.part) = (time, phrase.part) }
            } else if onlyJoins(source[last.range.upperBound..<phrase.range.lowerBound]),
                      last.day != nil && last.time == nil && phrase.day == nil && phrase.time != nil
                        || last.time != nil && last.day == nil && phrase.day != nil && phrase.time == nil {
                last.range = last.range.lowerBound..<phrase.range.upperBound
                last.day = last.day ?? phrase.day
                if last.time == nil { (last.time, last.part) = (phrase.time, phrase.part) }
            } else {
                out.append(phrase)
                continue
            }
            out[out.count - 1] = last
        }
        return out
    }

    /// Only spaces, a 「的」 ("3天后的下午3点"), commas, colons, dashes or brackets between two phrases (「明天：下午3点」,
    /// 「明天、下午3点」, "tomorrow - 3pm", 「明天（下午3点）」): they go together.
    static func onlyJoins(_ text: Substring) -> Bool { text.allSatisfy { $0.isWhitespace || joiners.contains($0) } }
    private static let joiners: Set<Character> = Set("的，,、：:-–—（）()【】[]「」")

    /// `phrase` with what `other` adds to it: the time of day of a day alone, the day of a time alone, the clock
    /// time of a part of the day (周五晚上 and 7点: 19:00). Nil when it adds nothing (two days, two times, a moment).
    static func combined(_ phrase: Phrase, _ other: Phrase) -> Phrase? {
        guard phrase.exact == nil, other.exact == nil else { return nil }
        var both = phrase
        if phrase.time == nil, other.day == nil, let time = other.time {
            (both.time, both.part) = (time, other.part)
        } else if phrase.day == nil, phrase.time != nil, other.time == nil, let day = other.day {
            both.day = day
        } else if let part = phrase.part, other.day == nil, other.part == nil, let clock = other.time {
            (both.time, both.part) = (clock.within(part), nil)
        } else if let part = other.part, phrase.day == nil, phrase.part == nil, let clock = phrase.time {
            (both.day, both.time, both.part) = (other.day, clock.within(part), nil)
        } else {
            return nil
        }
        return both
    }

    /// A clock time 「N点」 written without its half of the day, with more of its clause after it (「写3点东西」,
    /// 「3点开始」): it may count things rather than say when. It is the time of a day written elsewhere only when
    /// it ends its clause (「明天开会，3点」, 「周五晚上 聚餐 7点」); right next to the day it always is (「明天3点开会」,
    /// read together), and alone it is the next such time.
    static func isLooseClock(_ phrase: Phrase, in source: String) -> Bool {
        guard phrase.day == nil, phrase.part == nil, phrase.exact == nil, phrase.time?.ambiguous == true,
              source[phrase.range].contains(where: { $0 == "点" || $0 == "點" }) else { return false }
        return !endsClause(at: phrase.range.upperBound, in: source)
    }

    /// Whether a clause ends at `index`: the end of the text, a space or punctuation, maybe after a word that only
    /// says around, before or after then (「3点左右」, 「3点前。」).
    static func endsClause(at index: String.Index, in text: String) -> Bool {
        var rest = text[index...]
        if let word = aroundTheTime.first(where: rest.hasPrefix) { rest = rest.dropFirst(word.count) }
        guard let next = rest.first else { return true }
        return next.isWhitespace || next.isPunctuation
    }

    private static let aroundTheTime = ["左右", "之前", "以前", "之后", "以后", "前", "后"]

    /// "next Monday" said on a Friday, Saturday or Sunday: the coming Monday, like 下周一 (the detector skips
    /// a week for some days, e.g. 9 days ahead on a Saturday).
    private func comingWeekday(in phrase: String, now: Date) -> DateComponents? {
        guard let match = Self.nextWeekday.firstMatch(in: phrase, range: NSRange(phrase.startIndex..., in: phrase)),
              let range = Range(match.range(withName: "day"), in: phrase),
              let offset = Self.weekdayIndex(phrase[range]) else { return nil }
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)  // 1 Sunday … 6 Friday, 7 Saturday
        guard [6, 7, 1].contains(weekday), let date = calendar.date(byAdding: .day, value: (9 - weekday) % 7 + offset, to: today) else {
            return nil
        }
        return calendar.dateComponents([.year, .month, .day], from: date)
    }

    /// The next 15th for "15号": this month's if it is still to come (today counts), else the next month that has one.
    private func dayOfMonth(_ number: Int, now: Date) -> DateComponents? {
        let today = calendar.startOfDay(for: now)
        var month = calendar.dateComponents([.year, .month], from: today)
        for _ in 0..<12 {
            if let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: number)),
               calendar.component(.day, from: date) == number, date >= today {
                return calendar.dateComponents([.year, .month, .day], from: date)
            }
            guard let next = calendar.date(from: DateComponents(year: month.year, month: (month.month ?? 1) + 1, day: 1)) else { return nil }
            month = calendar.dateComponents([.year, .month], from: next)
        }
        return nil
    }

    /// Weekdays read here, where the detector counts weeks from Sunday (the region's first weekday on this Mac):
    /// 这周五 / 本周日 this week's, 下周日 next week's, 下下周一 the week after's, with weeks from Monday as
    /// Chinese counts them (said on a Saturday, 下周日 isn't the next day, nor 这周日 the one before); and a weekday
    /// to repeat (每周五, "every Monday"): the next one, today too. Their day stands where the detector reads them.
    private func weekdays(in source: String, now: Date) -> [Phrase] {
        let today = calendar.startOfDay(for: now)
        let todayIndex = Self.mondayFirst(calendar.component(.weekday, from: today))
        func day(_ offset: Int) -> DateComponents? {
            calendar.date(byAdding: .day, value: offset, to: today).map { calendar.dateComponents([.year, .month, .day], from: $0) }
        }
        let whole = NSRange(source.startIndex..., in: source)
        var found: [Phrase] = []
        for match in Self.chineseWeekday.matches(in: source, range: whole) {
            guard let range = Range(match.range, in: source), let which = Range(match.range(withName: "which"), in: source),
                  let weekday = Self.weekdayIndex(source[range]) else { continue }
            let weeks = source[which] == "下下" ? 2 : source[which] == "下" ? 1 : 0
            if let day = day(7 * weeks + weekday - todayIndex) { found.append(Phrase(range: range, day: day)) }
        }
        for match in Self.repeatedWeekday.matches(in: source, range: whole) {
            guard let range = ["zh", "en"].lazy.compactMap({ Range(match.range(withName: $0), in: source) }).first,
                  let weekday = Self.weekdayIndex(source[range]) else { continue }
            if let day = day((weekday - todayIndex + 7) % 7) { found.append(Phrase(range: range, day: day)) }
        }
        return found
    }

    /// Days read here for a span of days, all day, with weeks from Monday: 周末 / "this weekend" (today on a
    /// Saturday or Sunday, else the coming Saturday) and 下周末 / "next weekend" (next week's Saturday); 月底 /
    /// 月末 / "end of the month" (its last day; 下个月底: next month's); 下周 / 下个星期 / "next week" without a
    /// weekday: next Monday (下下周: the one after); 下个月 / "next month": its 1st (or the day written with it);
    /// 月初: the next 1st (下月初: next month's); 年底 / "end of the year": Dec 31.
    private func spans(in source: String, now: Date) -> [Phrase] {
        let today = calendar.startOfDay(for: now)
        let todayIndex = Self.mondayFirst(calendar.component(.weekday, from: today))
        let whole = NSRange(source.startIndex..., in: source)
        // The word that says which (这, 下, 下下, next …), from the groups the pattern has (asking for another raises an exception).
        func which(_ match: NSTextCheckingResult, _ names: [String]) -> String {
            names.lazy.compactMap { Range(match.range(withName: $0), in: source) }.first.map { source[$0].lowercased() } ?? ""
        }
        func phrase(_ match: NSTextCheckingResult, _ date: Date?) -> Phrase? {
            guard let range = Range(match.range, in: source), let date else { return nil }
            return Phrase(range: range, day: calendar.dateComponents([.year, .month, .day], from: date))
        }
        var found: [Phrase] = []
        for match in Self.weekend.matches(in: source, range: whole) {
            let word = which(match, ["which", "en"])
            let weeks = word.hasPrefix("下下") ? 2 : word.hasPrefix("下") || word == "next" ? 1 : 0
            let offset = weeks == 0 && todayIndex >= 5 ? 0 : 7 * weeks + 5 - todayIndex
            found += [phrase(match, calendar.date(byAdding: .day, value: offset, to: today))].compactMap { $0 }
        }
        for match in Self.monthEnd.matches(in: source, range: whole) {
            let word = which(match, ["which", "en"])
            let month = calendar.date(byAdding: .month, value: word.hasPrefix("下") || word == "next" ? 1 : 0, to: today)
            let end = month.flatMap { calendar.dateInterval(of: .month, for: $0) }
            found += [phrase(match, end.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) })].compactMap { $0 }
        }
        for match in Self.nextWeek.matches(in: source, range: whole) {
            let weeks = which(match, ["which"]) == "下下" ? 2 : 1
            found += [phrase(match, calendar.date(byAdding: .day, value: 7 * weeks - todayIndex, to: today))].compactMap { $0 }
        }
        for match in Self.nextMonth.matches(in: source, range: whole) {
            let months = which(match, ["which"]) == "下下" ? 2 : 1
            let written = ["d", "ed", "ed2"].lazy.compactMap { Range(match.range(withName: $0), in: source) }.first
                .flatMap { Self.number(String(source[$0])) }
            guard let month = calendar.date(byAdding: .month, value: months, to: today) else { continue }
            var day = calendar.dateComponents([.year, .month], from: month)
            day.day = written ?? 1
            // A day the month doesn't have (下个月31号 in November) is no date.
            guard let date = calendar.date(from: day), calendar.component(.day, from: date) == day.day else { continue }
            found += [phrase(match, date)].compactMap { $0 }
        }
        for match in Self.monthStart.matches(in: source, range: whole) {
            let word = which(match, ["which"])
            let date: Date?
            if word.isEmpty {
                date = dayOfMonth(1, now: now).flatMap { calendar.date(from: $0) }
            } else {
                let month = calendar.date(byAdding: .month, value: word.hasPrefix("下下") ? 2 : word.hasPrefix("下") ? 1 : 0, to: today)
                date = month.flatMap { calendar.dateInterval(of: .month, for: $0)?.start }
            }
            found += [phrase(match, date)].compactMap { $0 }
        }
        for match in Self.yearEnd.matches(in: source, range: whole) {
            let word = which(match, ["which", "en"])
            let years = word == "后" ? 2 : word == "明" || word == "next" ? 1 : 0
            let year = calendar.component(.year, from: today) + years
            found += [phrase(match, calendar.date(from: DateComponents(year: year, month: 12, day: 31)))].compactMap { $0 }
        }
        return found
    }

    /// 周末, 这周末, 下周末, 下下周末 (not 上周末); "this weekend", "next weekend", "the weekend".
    private static let weekend = try! NSRegularExpression(pattern:
        "(?<![上下这本])(?<which>这个?|本|下下个?|下个?)?周末|\\b(?:(?<en>this|next)\\s+)?weekend\\b", options: .caseInsensitive)
    /// 月底, 月末, 这个月底, 本月底, 下个月底 (not 上个月底, nor 10月底); "end of the month", "end of next month".
    private static let monthEnd = try! NSRegularExpression(pattern:
        "(?<![0-9零〇一二两三四五六七八九十上])(?<!上个)(?<which>这个?|本|下个?)?月[底末]"
        + "|\\b(?:the\\s+)?end\\s+of\\s+(?:(?<en>this|next|the)\\s+)?month\\b", options: .caseInsensitive)
    /// 下个月, 下月, 下下个月, "next month": its 1st, or the day of the month written with it (下个月 15号, 下月15号,
    /// "next month on the 15th", "the 15th next month"; the detector reads 下个月15号 and "the 15th of next month"
    /// too). Not 上个月, 下个月底 / 下月初 (`monthEnd`, `monthStart`), nor 下个月中旬.
    private static let nextMonth = try! NSRegularExpression(pattern:
        "(?<![上这本每下])(?<which>下下|下)个?月(?:\\s*(?<d>[0-9]{1,2}|[一二三四五六七八九十]{1,3})\\s*[号號日](?![\(notADay)])"
        + "|(?!\\s*[底末初中上下旬份0-9０-９零〇一二两三四五六七八九十号號日]))"
        + "|\\bnext\\s+month(?:\\s+on\\s+the\\s+(?<ed>[0-9]{1,2})(?:st|nd|rd|th))?\\b"
        + "|\\b(?:on\\s+)?the\\s+(?<ed2>[0-9]{1,2})(?:st|nd|rd|th)\\s+next\\s+month\\b", options: .caseInsensitive)
    /// 月初, 这个月初, 本月初, 下个月初, 下月初: the 1st (月初 alone: the next one, today on the 1st). Not 10月初, 上个月初,
    /// nor the lunar 正月初一, 腊月初八.
    private static let monthStart = try! NSRegularExpression(pattern:
        "(?<![0-9零〇一二两三四五六七八九十上正腊冬闰])(?<!上个)(?<which>这个?|本|下下个?|下个?)?月初")
    /// 年底, 年末, 今年年底, 明年底, 后年年底, 每年年底: that year's Dec 31; "end of the year", "end of next year". Not 去年年底,
    /// 2026年底; the 后 of 然后 / 之后 and the 明 of 说明 / 表明 say no year (「然后年底交」 is this year's).
    private static let yearEnd = try! NSRegularExpression(pattern:
        "(?<![0-9０-９零〇一二两三四五六七八九十去前上年])"
        + "(?:(?<which>今|(?<![说声表证发光文分透聪标注阐查简])明|(?<![然之以最随而前先背落延往])后)年?|年)?年[底末]"
        + "|\\b(?:the\\s+)?end\\s+of\\s+(?:(?<en>this|next|the)\\s+)?year\\b", options: .caseInsensitive)
    /// 下周, 下个星期, 下礼拜, 下下周 with no weekday after it; "next week".
    private static let nextWeek = try! NSRegularExpression(pattern:
        "(?<![上这本每下])(?<which>下下|下)个?(?:周|星期|礼拜)(?![一二三四五六日天末])|\\bnext\\s+week\\b", options: .caseInsensitive)

    /// 这周五, 本周日, 下周日, 下个星期一, 下下礼拜三 (not 上周五, nor the 下周一 inside 下下周一).
    private static let chineseWeekday = try! NSRegularExpression(pattern:
        "(?<![上这本下每])(?<which>这|本|下下|下)个?(?:周|星期|礼拜)[一二三四五六日天]")
    /// A weekday after 「每」 / "every" / "each" (每周五, 每个星期一, "every Monday"): the weekday's words.
    private static let repeatedWeekday = try! NSRegularExpression(pattern:
        "每\\s*个?\\s*(?<zh>(?:周|星期|礼拜)[一二三四五六日天])|\\b(?:every|each)\\s+(?:other\\s+)?(?<en>" + englishWeekday + ")\\b",
        options: .caseInsensitive)

    /// English weekdays, whole words: the names and their short forms ("Mon", "Tues", "Thurs"); "month" is none.
    static let englishWeekday =
        "(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)"
    private static let nextWeekday = try! NSRegularExpression(pattern: "\\bnext\\s+(?<day>" + englishWeekday + ")\\b",
                                                              options: .caseInsensitive)
    private static let chineseWeekdays: [Character: Int] = ["一": 0, "二": 1, "三": 2, "四": 3, "五": 4, "六": 5, "日": 6, "天": 6]

    /// Monday 0 … Sunday 6, for a weekday as written: 周五, 星期天, Monday, Tues.
    static func weekdayIndex(_ name: Substring) -> Int? {
        if let last = name.last, let index = chineseWeekdays[last] { return index }
        return ["mon", "tue", "wed", "thu", "fri", "sat", "sun"].firstIndex(of: name.prefix(3).lowercased())
    }

    /// Monday 0 … Sunday 6, for the calendar's weekday (1 Sunday … 7 Saturday): weeks start on Monday in Chinese.
    static func mondayFirst(_ weekday: Int) -> Int { (weekday + 5) % 7 }

    // MARK: - Clock times

    /// A clock time read here: where, the hour and minute as written, and "am" / "pm" when written ("a" / "p").
    struct Clock {
        var range: Range<String.Index>
        var hour: Int
        var minute: Int
        var meridiem: Character?

        /// With am / pm, or 0 and 13–24: exact. 1–12 without: either half of the day.
        var time: Time {
            if let meridiem { return Time(hour: hour % 12 + (meridiem == "p" ? 12 : 0), minute: minute) }
            return Time(hour: hour, minute: minute, ambiguous: (1...12).contains(hour))
        }
    }

    /// 3点, 3点半, 3点15(分), 三点一刻, 十点, 3点钟; not 第3点, 0.5点.
    private static let chineseClock = try! NSRegularExpression(pattern:
        "(?<![0-9.．:：第周期拜零〇一二两三四五六七八九十百千万])(?<h>[0-9]{1,2}|[零〇一二两三四五六七八九十]{1,3})\\s*[点點]"
        + "(?:\\s*(?:(?<half>半)|(?<quarter>[一三])\\s*刻|(?<m>[0-9]{1,2}(?![0-9])|[零〇一二三四五六七八九十]{1,3})\\s*分?|钟|整))?")
    /// The other forms, each with the groups it has: 9:30 (am / pm), 15时30分, at 5 (:30, pm), 5 o'clock, 5pm.
    private static let latinClocks: [(NSRegularExpression, [String])] = [
        ("(?<![0-9:：.])(?<h>[0-9]{1,2})\\s*[:：]\\s*(?<m>[0-9]{2})(?![0-9])(?:\\s*(?<ampm>[ap])\\.?\\s*m\\b\\.?)?", ["h", "m", "ampm"]),
        ("(?<![0-9.])(?<h>[0-9]{1,2})\\s*[时時](?:\\s*(?<m>[0-9]{1,2})\\s*分)?(?![间候期代长差段])", ["h", "m"]),
        ("\\bat\\s+(?<h>[0-9]{1,2})(?:[:.](?<m>[0-9]{2}))?(?![0-9%])(?:\\s*(?<ampm>[ap])\\.?\\s*m\\b\\.?)?(?!\\s*o['’]?clock)",
         ["h", "m", "ampm"]),
        ("\\b(?:at\\s+)?(?<h>[0-9]{1,2})\\s*o['’]?clock\\b", ["h"]),
        ("\\b(?<h>[0-9]{1,2})\\s*(?<ampm>[ap])\\.?\\s*m\\b\\.?", ["h", "ampm"]),
    ].map { (try! NSRegularExpression(pattern: $0.0, options: .caseInsensitive), $0.1) }
    private static let noon = try! NSRegularExpression(pattern: "\\b(?:at\\s+)?(?:noon|midday)\\b", options: .caseInsensitive)

    /// 「点」 starting a word of its own after a number: 3点赞, 点评 — not a time.
    private static let wordsWithDian: Set<Character> = ["击", "赞", "评", "名", "菜", "单", "数", "子", "心", "滴", "缀", "播", "燃", "亮", "破", "头"]
    /// What 「N点」 counts when one of these follows it: points made (「写3点建议」, 「提两点意见」, 「讨论两点问题」), not a time.
    private static let countedAfterDian = ["建议", "意见", "问题", "要求", "经验", "想法", "看法", "原因", "内容", "理由", "体会",
                                           "收获", "注意事项", "要点", "事项", "措施", "原则", "好处", "优势", "优点", "缺点", "不足",
                                           "区别", "疑问", "启示", "心得", "感想", "感受", "结论", "观点", "共识", "教训", "特点",
                                           "意义", "作用", "变化", "差异", "需求", "规则", "顾虑", "思路", "目标", "反思"]
    /// Words that may come between the number and what it counts: 「两点小建议」, 「三点主要原因」, 「两点个人看法」.
    private static let countedModifiers = ["小", "个人", "主要", "具体", "重要"]

    /// Whether `rest`, right after a 「N点」, says what it counts (`countedAfterDian`).
    static func countsThings(_ rest: Substring) -> Bool {
        var rest = rest
        if let modifier = countedModifiers.first(where: rest.hasPrefix) { rest = rest.dropFirst(modifier.count) }
        return countedAfterDian.contains(where: rest.hasPrefix)
    }
    /// 「一点」 is mostly "a little": 买一点水果, 快一点, 晚一点, 有一点, 一点也不, 一点儿, 给我一点时间.
    private static let aLittleBefore: Set<Character> = Set("有早晚快慢多少好大小高低长短近远轻重稍差这那买吃喝带拿要留省加放写看学点些再又更还就找做用弄存赚花剩挤让来去走跑睡起")
    private static let aLittleAfter: Set<Character> = Set("儿点也都些时钱事东水吧啊呀")

    /// The clock times in `text`, in order; where two readings overlap ("at 5:30" and "5:30"), the longer. A time
    /// with a dot (3.30) only after a part of the day or a day (下午3.30, 明天9.30): alone it is a month and day.
    static func clocks(in text: String) -> [Clock] {
        let whole = NSRange(text.startIndex..., in: text)
        var found: [Clock] = chineseClock.matches(in: text, range: whole).compactMap { readChineseClock($0, in: text) }
        for (regex, names) in latinClocks {
            for match in regex.matches(in: text, range: whole) {
                func group(_ name: String) -> Substring? {
                    names.contains(name) ? Range(match.range(withName: name), in: text).map { text[$0] } : nil
                }
                guard let range = Range(match.range, in: text), let hour = group("h").flatMap({ Int($0) }), hour <= 24,
                      case let minute = group("m").flatMap({ Int($0) }) ?? 0, minute < 60 else { continue }
                let meridiem = group("ampm")?.lowercased().first
                if meridiem != nil, !(1...12).contains(hour) { continue }
                found.append(Clock(range: range, hour: hour, minute: minute, meridiem: meridiem))
            }
        }
        found += dottedClocks(in: text)
        found.sort { ($0.range.lowerBound, $1.range.upperBound) < ($1.range.lowerBound, $0.range.upperBound) }
        var out: [Clock] = []
        for clock in found where !(out.last.map { clock.range.lowerBound < $0.range.upperBound } ?? false) { out.append(clock) }
        return out
    }

    private static func readChineseClock(_ match: NSTextCheckingResult, in text: String) -> Clock? {
        func group(_ name: String) -> String? { Range(match.range(withName: name), in: text).map { String(text[$0]) } }
        guard let range = Range(match.range, in: text), let written = group("h"), let hour = number(written), hour <= 24 else { return nil }
        var minute = 0
        if group("half") != nil {
            minute = 30
        } else if let quarter = group("quarter") {
            minute = quarter == "一" ? 15 : 45
        } else if let m = group("m") {
            guard let value = number(m), value < 60 else { return nil }
            minute = value
        }
        // Ends at 「点」: it may start another word (点赞), be "a little" (一点), or count what follows (「3点建议」;
        // after a part of the day or a day it is still a time: 「下午3点问题讨论」).
        if let last = text[range].last, last == "点" || last == "點" {
            if let next = text[range.upperBound...].first, wordsWithDian.contains(next) { return nil }
            if countsThings(text[range.upperBound...]), partOfDay(before: range.lowerBound, in: text) == nil,
               !dayBefore(range.lowerBound, in: text) { return nil }
            if written == "一" {
                if let before = text[..<range.lowerBound].last, aLittleBefore.contains(before) { return nil }
                if let after = text[range.upperBound...].first, aLittleAfter.contains(after) { return nil }
            }
        }
        return Clock(range: range, hour: hour, minute: minute, meridiem: nil)
    }

    /// A clock time written without its half of the day ("3点半", "1:30", "明天3点", "Friday at 3"): it may be
    /// in the morning or the afternoon. Nil when the phrase says which (下午, 晚, am, tonight, …) or has none.
    static func bareClock(in phrase: String) -> Time? {
        guard !saysHalfOfDay(phrase), let time = clocks(in: phrase).first?.time, time.ambiguous else { return nil }
        return time
    }

    /// Whether a phrase says which half of the day: 早, 晚, 午, 夜, 晨 (上午, 傍晚, 凌晨 …), am, pm, tonight, noon …
    static func saysHalfOfDay(_ phrase: String) -> Bool {
        if phrase.contains(where: { "早晚午夜晨".contains($0) }) { return true }
        return phrase.range(of: "\\b(a\\.?m|p\\.?m|morning|afternoon|evening|night|tonight|noon|midday|midnight)\\b|[0-9]\\s*[ap]\\.?m\\b",
                            options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Parts of the day a clock time can follow, longest first.
    private static let partsOfDay = ["早上", "早晨", "清晨", "上午", "中午", "正午", "下午", "傍晚", "晚上", "夜里", "夜间", "凌晨",
                                     "半夜", "午夜", "今晚", "明晚", "今早", "明早", "早", "晚"]

    /// The part of the day written right before `index` (spaces between are fine), and where it starts.
    static func partOfDay(before index: String.Index, in text: String) -> (word: String, start: String.Index)? {
        var end = index
        while end > text.startIndex, text[text.index(before: end)].isWhitespace { end = text.index(before: end) }
        let before = text[..<end]
        guard let word = partsOfDay.first(where: { before.hasSuffix($0) }) else { return nil }
        return (word, text.index(end, offsetBy: -word.count))
    }

    /// The hour `hour` means after `part`: 晚上 / 下午 / 傍晚 1–11 are after noon (晚上12点 is midnight, the
    /// day's end); 中午 12 is noon and 1–2 just after; 早上 / 上午 / 凌晨 as written (凌晨12点: the start of the
    /// day); 半夜 / 夜里 as written (12: midnight). Nil for an hour no clock has.
    static func hour(_ hour: Int, in part: String) -> Int? {
        guard hour <= 24 else { return nil }
        switch part {
        case "下午", "傍晚", "afternoon":
            return (1...11).contains(hour) ? hour + 12 : hour
        case "晚上", "晚", "今晚", "明晚", "夜", "evening", "tonight", "night":
            return (1...11).contains(hour) ? hour + 12 : hour == 12 ? 24 : hour
        case "中午", "正午":
            return (1...2).contains(hour) ? hour + 12 : hour
        case "半夜", "午夜", "夜里", "夜间":
            return hour == 12 ? 24 : hour
        case "凌晨":
            return hour == 12 ? 0 : hour
        default:
            return hour
        }
    }

    // MARK: - Parts of the day without a clock time

    /// The parts of the day a date phrase can name without a clock time, longest first.
    private static let roughParts = ["早上", "早晨", "清晨", "上午", "中午", "下午", "傍晚", "晚上", "夜里", "夜间", "凌晨",
                                     "今晚", "明晚", "今早", "明早", "afternoon", "morning", "evening", "tonight", "night",
                                     "早", "晚", "夜"]

    /// The part of the day a date phrase names (「明天下午」: 下午, "tonight"); nil for a moment (半夜, 午夜, 正午,
    /// noon, midnight).
    static func part(in phrase: String) -> String? {
        let lower = phrase.lowercased()
        if ["半夜", "午夜", "正午"].contains(where: phrase.contains)
            || lower.range(of: "\\b(noon|midday|midnight)\\b", options: .regularExpression) != nil { return nil }
        return roughParts.first(where: lower.contains)
    }

    /// The hour a part of the day is over (24: at midnight).
    static func end(of part: String) -> Int? {
        switch part {
        case "凌晨": return 6
        case "早上", "早晨", "清晨", "上午", "早", "今早", "明早", "morning": return 12
        case "中午": return 14
        case "下午", "afternoon": return 18
        case "傍晚": return 19
        case "晚上", "晚", "今晚", "明晚", "夜里", "夜间", "夜", "evening", "tonight", "night": return 24
        default: return nil
        }
    }

    // MARK: - Days of the month

    /// What a number before 号 / 日 counts when one of these follows: 3号线, 5号楼, 500日元 — not a day.
    private static let notADay = "楼樓线線门門床位房馆館厅廳机機车車桌口码碼窗台柜櫃店院厂廠箱球字座舱艙站道元币幣游遊队隊员員件包罐框键鍵文内"

    /// 15号, 15日, 十五号, 每月15号; not 3号线, 5号楼, 500日元, 10月15日 (the detector reads that).
    private static let dayOfMonthPattern: NSRegularExpression = {
        let notAMonth = "(?<![0-9０-９零〇一二两三四五六七八九十]月)"
        return try! NSRegularExpression(pattern:
            "(?<![0-9０-９第./-])\(notAMonth)(?<d>[0-9]{1,2})\\s*[号號日](?![\(notADay)])"
            + "|(?<![零〇一二两三四五六七八九十第])\(notAMonth)(?<c>[一二三四五六七八九十]{1,3})\\s*[号號](?![\(notADay)])")
    }()

    static func daysOfMonth(in text: String) -> [(Range<String.Index>, Int)] {
        dayOfMonthPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let digits = Range(match.range(withName: "d"), in: text).flatMap { Int(text[$0]) }
            let chinese = Range(match.range(withName: "c"), in: text).flatMap { chineseNumber(String(text[$0])) }
            guard let day = digits ?? chinese, (1...31).contains(day) else { return nil }
            return (range, day)
        }
    }

    /// "the 15th", "on the 1st", "by 3rd": a day of the month (not "the 3rd floor", nor "the 15th of October",
    /// which the detector reads).
    private static let ordinalDay = try! NSRegularExpression(pattern:
        "\\b(?<the>the\\s+)?(?<d>[0-9]{1,2})(?:st|nd|rd|th)\\b(?!\\s+(?:of|floor|time|times|attempt|try|place|row|line|page|"
        + "level|round|grade|step|item|one|century|anniversary|birthday|edition|chapter|season|episode|day|week|month|"
        + "year|street|avenue|ave|generation|version|quarter|period|lesson|question|issue|game|option|point|hole|"
        + "inning|seat|gate|door|house|stop|exit|lap|person|car|draft)\\b)", options: .caseInsensitive)

    static func ordinalDays(in text: String) -> [(Range<String.Index>, Int)] {
        ordinalDay.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text), let digits = Range(match.range(withName: "d"), in: text),
                  let day = Int(text[digits]), (1...31).contains(day) else { return nil }
            // Without "the", only right after "on" or "by" ("on 15th"): looked for in the few characters before it.
            if match.range(withName: "the").location == NSNotFound,
               text[..<range.lowerBound].suffix(24).range(of: "\\b(on|by)\\s+$", options: [.regularExpression, .caseInsensitive]) == nil {
                return nil
            }
            return (range, day)
        }
    }

    /// 10.1, 11.11, 5.20: month.day, not inside a longer number (192.168.1.1, 1.2.3, 3.14159).
    private static let dottedDate = try! NSRegularExpression(pattern:
        "(?<![0-9０-９.．,])(?<m>1[0-2]|0?[1-9])[.．](?<d>3[01]|[12][0-9]|0?[1-9])(?![0-9０-９%％]|[.．][0-9])")
    /// Written after a number with a decimal point: what it counts (money, weight, length, times, a score …).
    private static let unitsAfterNumber: Set<Character> = Set("元块角毛分钱斤两克吨米寸尺升度倍折岁万亿千百个只件张本次秒天周年月级版星点镑磅刀%％¥￥$€£")
    private static let wordUnitsAfterNumber = ["日元", "小时", "公里", "公斤", "厘米", "毫米", "毫升", "英寸", "英里", "美元",
                                               "美金", "港币", "欧元", "英镑"]
    /// Written before a number that is money, a version or a sum: ¥5.20, $5.20, +1.2.
    private static let beforeNumber: Set<Character> = Set("¥￥$€£₩₹+-±=×/")
    /// Words after which a number is what they measure, not a date (a colon, 是 or 为 may come between): a score (评分9.8,
    /// 得分 8.5; not the 分 of 20分), a count or a rate (指数, 汇率7.1), a reading (体温, 血压12.8, 血糖, 视力5.1), a
    /// price (价格, 售价9.9), a version (版本1.2), an ordinal (第).
    private static let measuredBefore = try! NSRegularExpression(pattern:
        "(?:(?<![0-9０-９零〇一二两三四五六七八九十百])分|数|率|价|价格|价钱|体温|气温|水温|室温|温度|血压|气压|胎压|血糖|体重|视力"
        + "|成绩|绩点|版|版本|第)\\s*(?:[:：]|是|为)?$")

    /// Whether a number right after `lead` is what a word there measures (`measuredBefore`).
    private static func measures(_ lead: Substring) -> Bool {
        let tail = String(lead.suffix(12))  // the words are short: only the end of the text is looked at
        return measuredBefore.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)) != nil
    }

    /// 10.1, 11.11, 5.20 as a month and day, with words before or after it (10.1出发, 出发10.1) that don't make it
    /// money, a quantity, a score or a reading, or a version (10.15元, ¥5.20, 3.5斤, 2.5倍, 评分9.8, 血压12.8, v1.2,
    /// 版本1.2, Swift 5.10); not a number alone. (`parse` reads one only when nothing else in the text says when.)
    static func dottedDates(in text: String) -> [(range: Range<String.Index>, month: Int, day: Int)] {
        dottedDate.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text),
                  let month = Range(match.range(withName: "m"), in: text).flatMap({ Int(text[$0]) }),
                  let day = Range(match.range(withName: "d"), in: text).flatMap({ Int(text[$0]) }) else { return nil }
            var lead = text[..<range.lowerBound], rest = text[range.upperBound...]
            while let last = lead.last, last.isWhitespace { lead = lead.dropLast() }
            while let first = rest.first, first.isWhitespace { rest = rest.dropFirst() }
            guard !lead.isEmpty || !rest.isEmpty else { return nil }
            if let before = lead.last, isLatin(before) || beforeNumber.contains(before) || measures(lead) { return nil }
            if let after = rest.first, after.isASCII && after.isLetter || unitsAfterNumber.contains(after)
                || wordUnitsAfterNumber.contains(where: rest.hasPrefix) { return nil }
            // After a part of the day or a day (下午3.30, 明天9.30) it is a clock time (`dottedClocks`).
            if partOfDay(before: range.lowerBound, in: text) != nil || dayBefore(range.lowerBound, in: text) { return nil }
            return (range, month, day)
        }
    }

    /// 3.30, 9.45: a clock time with a dot, read only after a part of the day or a day (下午3.30, 明天9.30).
    private static let dottedClock = try! NSRegularExpression(pattern:
        "(?<![0-9０-９.．,])(?<h>[0-9]{1,2})[.．](?<m>[0-5][0-9])(?![0-9０-９%％]|[.．][0-9])")
    /// A day written right before a clock time: 今天, 明天, 后天, 周五, 星期五, 15号, 10月1日.
    private static let dayAtEnd = try! NSRegularExpression(pattern:
        "(?:今天|明天|后天|今日|明日|[周期拜][一二三四五六日天]|[0-9零〇一二两三四五六七八九十][号號日])\\s*$")

    static func dayBefore(_ index: String.Index, in text: String) -> Bool {
        let lead = String(text[..<index].suffix(12))
        return dayAtEnd.firstMatch(in: lead, range: NSRange(lead.startIndex..., in: lead)) != nil
    }

    /// The clock times written with a dot after a part of the day or a day (`dottedClock`).
    static func dottedClocks(in text: String) -> [Clock] {
        dottedClock.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text),
                  let hour = Range(match.range(withName: "h"), in: text).flatMap({ Int(text[$0]) }), hour <= 24,
                  let minute = Range(match.range(withName: "m"), in: text).flatMap({ Int(text[$0]) }),
                  partOfDay(before: range.lowerBound, in: text) != nil || dayBefore(range.lowerBound, in: text) else { return nil }
            return Clock(range: range, hour: hour, minute: minute, meridiem: nil)
        }
    }

    // MARK: - Years

    /// 明年 / 今年 / 后年, "next year" / "this year".
    private static let yearWord = try! NSRegularExpression(pattern: "明年|今年|后年|\\b(?:next|this)\\s+year\\b", options: .caseInsensitive)

    /// The year words in `text` (`yearWord`), each with the years from now it means.
    static func yearWords(in text: String) -> [(range: Range<String.Index>, years: Int)] {
        yearWord.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let word = text[range].lowercased()
            return (range, word == "明年" || word.hasPrefix("next") ? 1 : word == "后年" ? 2 : 0)
        }
    }

    /// Whether two phrases are side by side, with only spaces or a comma between (明年1月5日, "Jan 5, next year").
    static func nextTo(_ a: Range<String.Index>, _ b: Range<String.Index>, in text: String) -> Bool {
        let gap: Substring? = a.upperBound <= b.lowerBound ? text[a.upperBound..<b.lowerBound]
            : b.upperBound <= a.lowerBound ? text[b.upperBound..<a.lowerBound] : nil
        return gap?.allSatisfy { $0.isWhitespace || $0 == "," || $0 == "，" } ?? false
    }

    /// 10月5日, 十月五号, Oct 5, 5 October, the 5th of October, 10/5.
    private static let monthAndDay = try! NSRegularExpression(pattern:
        "[0-9零〇一二两三四五六七八九十]\\s*月\\s*[0-9零〇一二两三四五六七八九十]"
        + "|\\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?\\s*[0-9]{1,2}(?![0-9:])"
        + "|(?<![0-9:])[0-9]{1,2}(?:st|nd|rd|th)?\\s+(?:of\\s+)?(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\b"
        + "|(?<![0-9/:.])[0-9]{1,2}\\s*/\\s*[0-9]{1,2}(?![0-9/])", options: .caseInsensitive)

    /// Whether a date phrase names a month and a day (`monthAndDay`).
    static func namesMonthAndDay(_ phrase: String) -> Bool {
        monthAndDay.firstMatch(in: phrase, range: NSRange(phrase.startIndex..., in: phrase)) != nil
    }

    /// Whether a date phrase gives its year: 2027年, 2027-01-05, 1/5/27, "next year".
    static func namesYear(_ phrase: String) -> Bool {
        phrase.range(of: "年|[0-9]{4}|\\byear\\b|[0-9]{1,2}\\s*[/.-]\\s*[0-9]{1,2}\\s*[/.-]\\s*[0-9]{2}",
                     options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Meals

    private static let meals = ["breakfast", "brunch", "lunch", "dinner", "supper", "下午茶", "早茶", "夜宵", "宵夜",
                                "早饭", "早餐", "午饭", "午餐", "中饭", "晚饭", "晚餐"]
    /// Meals in the evening: a clock time written with one is in the evening too ("dinner at 7", 「晚饭7点」).
    private static let eveningMeals = ["dinner", "supper", "晚饭", "晚餐", "夜宵", "宵夜"]
    private static let longestMeal = meals.map(\.count).max() ?? 0

    /// The detector's phrase without the meals in it ("tomorrow lunch", "lunch tomorrow", 「明天午饭」, 「明天下午茶」,
    /// "tomorrow dinner at 7"): the meal is what the reminder is for, and stays in the title. One at the start goes
    /// with what is before it, any other with what follows (a clock time after it is read on its own).
    static func withoutMeal(_ range: Range<String.Index>, in source: String) -> Range<String.Index> {
        var lower = range.lowerBound, upper = range.upperBound
        // Only meals that overlap the phrase count, so only around it is looked in (a meal's length on each side):
        // not the whole text again for each of its dates.
        let window = (source.index(lower, offsetBy: -longestMeal, limitedBy: source.startIndex) ?? source.startIndex)
            ..< (source.index(upper, offsetBy: longestMeal, limitedBy: source.endIndex) ?? source.endIndex)
        for meal in meals {
            var from = window.lowerBound
            while lower < upper, let found = source.range(of: meal, options: .caseInsensitive, range: from..<window.upperBound) {
                from = found.upperBound
                guard found.lowerBound < upper else { break }
                guard found.upperBound > lower, isWord(found, in: source) else { continue }
                if found.lowerBound <= lower { lower = found.upperBound } else { upper = found.lowerBound }
            }
        }
        var phrase = source[lower..<max(lower, upper)]
        while let first = phrase.first, first.isWhitespace { phrase = phrase.dropFirst() }
        while let last = phrase.last, last.isWhitespace { phrase = phrase.dropLast() }
        return phrase.startIndex..<phrase.endIndex
    }

    /// Whether `text` has an evening meal in it, or (`atEnd`) ends with one, spaces aside.
    static func hasEveningMeal(_ text: Substring, atEnd: Bool = false) -> Bool {
        var text = text
        while let last = text.last, last.isWhitespace { text = text.dropLast() }
        // At the end, only the last few characters are looked at (a meal and the one before it, where its word
        // starts): a clock time late in a long text has all of it before it.
        if atEnd { text = text.suffix(longestMeal + 1) }
        let options: String.CompareOptions = atEnd ? [.caseInsensitive, .backwards, .anchored] : .caseInsensitive
        return eveningMeals.contains { meal in text.range(of: meal, options: options).map { isWord($0, in: text) } ?? false }
    }

    /// A Latin word found in `text` is all of a word there ("lunch", not the start of "lunches").
    private static func isWord<S: StringProtocol>(_ range: Range<String.Index>, in text: S) -> Bool where S.Index == String.Index {
        guard text[range].first.map(isLatin) == true else { return true }
        return (range.lowerBound == text.startIndex || !isLatin(text[text.index(before: range.lowerBound)]))
            && (range.upperBound == text.endIndex || !isLatin(text[range.upperBound]))
    }

    /// The detector's phrase without a 「晚一点」 / 「早一点」 at its end ("a bit later / earlier": 「明天晚一点」 is
    /// tomorrow, no time).
    static func withoutALittle(_ range: Range<String.Index>, in source: String) -> Range<String.Index> {
        var phrase = source[range]
        if phrase.hasSuffix("儿") { phrase = phrase.dropLast() }
        guard phrase.hasSuffix("晚一点") || phrase.hasSuffix("早一点") else { return range }
        phrase = phrase.dropLast(3)
        while let last = phrase.last, last.isWhitespace { phrase = phrase.dropLast() }
        return phrase.startIndex..<phrase.endIndex
    }

    // MARK: - The text as the rules read it

    /// The text with what the detector misses written out (明早 → 明天早上, 今早 → 今天早上, 明晚 → 明天晚上,
    /// 早8点 → 早上8点), and the way back to the text as typed for the title. Of a longer text, only the first `limit`
    /// characters are read; the ranges found there are ranges of the whole text as typed.
    struct Written {
        let original: String
        let text: String
        /// For each Character of `text`: the Characters (offsets) of `original` it stands for.
        private let origins: [Range<Int>]

        private static let words = ["明早": "明天早上", "今早": "今天早上", "明晚": "明天晚上"]

        init(_ original: String, reading limit: Int = .max) {
            self.original = original
            let chars = Array(original.prefix(limit))
            var text = "", origins: [Range<Int>] = []
            var i = 0
            while i < chars.count {
                var replacement: (word: String, length: Int)?
                if i + 1 < chars.count, let word = Self.words[String(chars[i...(i + 1)])] {
                    replacement = (word, 2)
                } else if chars[i] == "早", Self.clockFollows(chars, from: i + 1) {
                    replacement = ("早上", 1)
                }
                if let (word, length) = replacement {
                    text += word
                    origins += Array(repeating: i..<(i + length), count: word.count)
                    i += length
                } else {
                    text.append(chars[i])
                    origins.append(i..<(i + 1))
                    i += 1
                }
            }
            self.text = text
            self.origins = origins
        }

        /// 早 + 8点 / 八点 / 8:30 (not 早一点: "a bit earlier").
        private static func clockFollows(_ chars: [Character], from start: Int) -> Bool {
            var i = start
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            let digits = i
            while i < chars.count, chars[i].isASCII && chars[i].isNumber || "零〇一二两三四五六七八九十".contains(chars[i]) { i += 1 }
            guard i > digits, i < chars.count, !(i == digits + 1 && chars[digits] == "一") else { return false }
            return "点點:：".contains(chars[i])
        }

        /// The range of the text as typed that `range` (in `text`) came from.
        func originalRange(_ range: Range<String.Index>) -> Range<String.Index> {
            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.distance(from: text.startIndex, to: range.upperBound)
            let from = lower < origins.count ? origins[lower].lowerBound : origins.last?.upperBound ?? 0
            let to = upper > lower ? origins[min(upper, origins.count) - 1].upperBound : from
            return original.index(original.startIndex, offsetBy: from)..<original.index(original.startIndex, offsetBy: to)
        }
    }

    // MARK: - Durations

    /// "30分钟后", "in 2 hours": an amount of time from now.
    struct Duration: Equatable {
        enum Unit: Equatable { case minute, hour, day, week, month }
        var range: Range<String.Index>
        var amount: Double
        var unit: Unit
        /// A time of day written with a number of days ("3天后下午3点", "in 3 days at 3pm"), and the whole of it.
        var time: Time?
        var extent: Range<String.Index>

        init(range: Range<String.Index>, amount: Double, unit: Unit) {
            self.range = range
            self.amount = amount
            self.unit = unit
            extent = range
        }

        var isDays: Bool { unit == .day || unit == .week || unit == .month }
    }

    /// 30分钟后, 两个钟头以后, 3天后, 1周后, 1个月后 (not 3月后: March). A number starts at its first digit and
    /// spaces are taken whole (possessive), so a long run of them can't be tried every way (a pasted table row).
    private static let chineseDuration = try! NSRegularExpression(pattern:
        "(?:(?<n>(?<![0-9.])[0-9]++(?:\\.[0-9]++)?|(?<![零〇一二两三四五六七八九十])[零〇一二两三四五六七八九十]++)\\s*+(?:个\\s*+)?"
        + "(?:(?<plushalf>半)\\s*+)?|(?<half>半)\\s*+(?:个\\s*+)?)"
        + "(?<unit>分钟|小时|钟头|天|日|周|星期|礼拜|(?<=个)月)\\s*+(?:以后|之后|后)")
    /// An amount of time in English: "30 minutes", "30min", "2h", "an hour and a half", "half an hour", "3 days",
    /// "a month".
    private static let englishAmount =
        "(?:(?<n>[0-9]+(?:\\.[0-9]+)?)\\s*|(?<w>an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|"
        + "twelve|fifteen|twenty|thirty|forty-five|forty|fifty|sixty|ninety)\\s+|(?<half>half\\s+an?)\\s+)"
        + "(?<unit>months?|minutes?|mins?|m|hours?|hrs?|h|days?|weeks?)(?<plushalf>\\s+and\\s+a\\s+half)?"
    /// "in 30 minutes", "after 2 hours"; "30 minutes from now", "2 hours later".
    private static let englishDurations = [
        "\\b(?:in|after)\\s+" + englishAmount + "\\b",
        "\\b" + englishAmount + "\\s+(?:from\\s+now|later)\\b",
    ].map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    private static let englishNumbers: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30,
        "forty": 40, "forty-five": 45, "fifty": 50, "sixty": 60, "ninety": 90,
    ]

    /// The durations in `text`, in order. Half a unit only for minutes and hours ("半小时后", "in half an hour").
    static func durations(in text: String) -> [Duration] {
        let whole = NSRange(text.startIndex..., in: text)
        return ([(chineseDuration, false)] + englishDurations.map { ($0, true) }).flatMap { regex, english in
            regex.matches(in: text, range: whole).compactMap { match -> Duration? in
                func group(_ name: String) -> String? {
                    // The Chinese pattern has no "w" group (asking for one it lacks raises an exception).
                    guard english || name != "w" else { return nil }
                    return Range(match.range(withName: name), in: text).map { String(text[$0]).lowercased() }
                }
                guard let range = Range(match.range, in: text), let unitWord = group("unit") else { return nil }
                let unit: Duration.Unit
                switch unitWord {
                case "分钟", "minute", "minutes", "min", "mins", "m": unit = .minute
                case "小时", "钟头", "hour", "hours", "hr", "hrs", "h": unit = .hour
                case "天", "日", "day", "days": unit = .day
                case "月", "month", "months": unit = .month
                default: unit = .week
                }
                var amount: Double
                if group("half") != nil {
                    amount = 0.5
                } else if let n = group("n") ?? group("w"),
                          let value = Double(n) ?? englishNumbers[n] ?? chineseNumber(n).map(Double.init) {
                    amount = value + (group("plushalf") != nil ? 0.5 : 0)
                } else {
                    return nil
                }
                // A count of days is whole ("1.5天后" is no day); half a day, week or month isn't read either.
                if unit == .day || unit == .week || unit == .month { guard amount == amount.rounded() else { return nil } }
                guard amount > 0, amount <= 10_000 else { return nil }
                return Duration(range: range, amount: amount, unit: unit)
            }
        }.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// 一 … 九十九 ("两" for 2, 零五 for 5): what people write for small numbers.
    static func chineseNumber(_ text: String) -> Int? {
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5,
                                        "六": 6, "七": 7, "八": 8, "九": 9]
        let chars = Array(text)
        guard let ten = chars.firstIndex(of: "十") else {
            if chars.count == 2, chars[0] == "零" || chars[0] == "〇" { return digits[chars[1]] }  // 3点零五
            return chars.count == 1 ? digits[chars[0]] : nil
        }
        let before = chars[..<ten], after = chars[(ten + 1)...]
        guard before.count <= 1, after.count <= 1 else { return nil }
        let tens = before.first.map { digits[$0] } ?? 1, ones = after.first.map { digits[$0] } ?? 0
        guard let tens, let ones else { return nil }
        return tens * 10 + ones
    }

    /// A number as written: 12 or 十二.
    private static func number(_ text: String) -> Int? { Int(text) ?? chineseNumber(text) }

    // MARK: - What a date phrase says

    /// Whether a date phrase gives a time of day ("下午3点", "9:30", "3pm", "tonight"), not just a day.
    static func mentionsTime(_ phrase: String) -> Bool {
        let lower = phrase.lowercased()
        let words = ["凌晨", "早上", "早晨", "上午", "中午", "正午", "下午", "傍晚", "晚", "夜", "早",
                     "noon", "midnight", "morning", "afternoon", "evening", "tonight", "night"]
        if words.contains(where: lower.contains) { return true }
        let clock = "[0-9][\\s]*[:：][\\s]*[0-9]|[0-9零〇一二两三四五六七八九十][\\s]*[点點时時]|[0-9][\\s]*(am|pm|a\\.m\\.|p\\.m\\.)"
            + "|\\bat\\s+[0-9]|o'?clock"
        return lower.range(of: clock, options: .regularExpression) != nil
    }

    /// Whether a date phrase names a day: 今 / 明 / 后天 / 周X / 星期X / 下周 / 号 / 日 / 月, today /
    /// tonight / tomorrow, a weekday, a month or a date in digits. Without one, a time that has passed
    /// today means tomorrow.
    static func mentionsDay(_ phrase: String) -> Bool {
        let chinese = ["今", "明", "昨", "后天", "前天", "周", "星期", "礼拜", "号", "日", "月", "年"]
        if chinese.contains(where: phrase.contains) { return true }
        let lower = phrase.lowercased()
        let english = ["today", "tonight", "tomorrow", "yesterday", "this", "next", "last", "week", "month", "year",
                       "mon", "tue", "wed", "thu", "fri", "sat", "sun",
                       "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let words = lower.split(whereSeparator: { !$0.isLetter })
        if words.contains(where: { word in english.contains(where: { word.hasPrefix($0) }) }) { return true }
        // 10/15, 2026-10-15, 15th (not a time range like 10:30-11:00).
        return lower.range(of: "(?<![:0-9])[0-9]{1,4}\\s*[/-]\\s*[0-9]{1,2}(?![:0-9])|[0-9](st|nd|rd|th)\\b",
                           options: .regularExpression) != nil
    }

    // MARK: - Written to repeat

    /// 「每」 (每天, 每个月, 每周 …), "every" / "each" ("every day at", "every month on the"), "daily" … right before a
    /// date: the text asks for it again and again.
    private static let repeatBefore = try! NSRegularExpression(pattern:
        "每\\s*个?\\s*(?:天|日|晚上|晚|早上|早晨|早|夜里|夜|周末|周|星期|礼拜|月|年)?\\s*的?\\s*$"
        + "|\\b(?:every|each)\\s+(?:other\\s+)?(?:(?:day|morning|afternoon|evening|night|week|weekday|month|year)\\s+)?"
        + "(?:(?:at|on|in)\\s+)?(?:the\\s+)?$"
        + "|\\b(?:daily|nightly|weekly|monthly|yearly|annually)\\s+(?:(?:at|on)\\s+)?(?:the\\s+)?$", options: .caseInsensitive)

    /// The words asking to repeat right before `index` (`repeatBefore`), if any.
    static func repeatMarker(before index: String.Index, in text: String) -> String? {
        let lead = String(text[..<index].suffix(40))
        guard let match = repeatBefore.firstMatch(in: lead, range: NSRange(lead.startIndex..., in: lead)),
              let range = Range(match.range, in: lead) else { return nil }
        return String(lead[range])
    }

    /// How far apart the times a repeating text asks for are: a day (每天, "every day"), a week (每周, a weekday), a
    /// month (每月, a day of the month) or a year (每年, a month and day); what the marker says, else the date.
    static func repeatStep(marker: String, phrase: String) -> DateComponents {
        func has(_ pattern: String, _ text: String) -> Bool {
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        if has("[天日晚早夜]|day|morning|afternoon|evening|night|daily|nightly", marker) { return DateComponents(day: 1) }
        if has("[周星礼]|week", marker) { return DateComponents(day: 7) }
        if has("月|month", marker) { return DateComponents(month: 1) }
        if has("年|year|annual", marker) { return DateComponents(year: 1) }
        if has("周|星期|礼拜|weekend|\\b" + englishWeekday + "\\b", phrase) { return DateComponents(day: 7) }
        if namesMonthAndDay(phrase) || has("年[底末]|end of (?:the |this |next )?year|元旦|圣诞", phrase) { return DateComponents(year: 1) }
        if has("[0-9零〇一二两三四五六七八九十]\\s*[号號日]|[0-9](st|nd|rd|th)\\b|月[底末初]|end of", phrase) { return DateComponents(month: 1) }
        return DateComponents(day: 1)
    }

    // MARK: - Title

    /// The text without the date phrases at `ranges` (and a word that only led into one: "at", "on (the)", "by",
    /// "before", "the", a 「在」 / 「于」 of its own, or what only went with it: 「之前」 / 「以前」 / 「之内」 / 「以内」 /
    /// 「前」, 「左右」, a 「的」, a 「是」 / "is" after a date that starts the text or a clause, brackets that held only
    /// the date), trimmed of spaces and punctuation, without a leading 「提醒我（一下）」 / 「提醒一下」 / 「记得」 /
    /// "remind me to".
    static func title(_ text: String, without ranges: [Range<String.Index>]) -> String {
        var result = text
        // The last first: what goes is at or after the ones before it, which keep their place.
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.distance(from: text.startIndex, to: range.upperBound)
            result = cut(result, result.index(result.startIndex, offsetBy: lower)..<result.index(result.startIndex, offsetBy: upper))
        }
        result = trimmed(result)
        // What only asked for the reminder.
        while true {
            if let lead = leads.first(where: result.hasPrefix) {
                result = trimmed(String(result.dropFirst(lead.count)))
            } else if let lead = result.range(of: "^remind me(\\s+to)?\\b", options: [.regularExpression, .caseInsensitive]) {
                result.removeSubrange(lead)
                result = trimmed(result)
            } else {
                return result
            }
        }
    }

    /// `text` without the phrase at `range` and the words that only went with it (see `title`).
    private static func cut(_ text: String, _ range: Range<String.Index>) -> String {
        let range = withBrackets(range, in: text)
        var before = String(text[..<range.lowerBound]), after = String(text[range.upperBound...])
        // Spaces only where the two parts meet: what is before keeps its place.
        func trim() {
            while let last = before.last, last.isWhitespace { before.removeLast() }
            while let first = after.first, first.isWhitespace { after.removeFirst() }
        }
        trim()
        if let dangling = before.range(of: "(^|\\s)(?:(?:at|on|by|around|before|over)\\s+the|at|on|by|around|before|the)$",
                                       options: [.regularExpression, .caseInsensitive]) {
            before.removeSubrange(dangling)
        } else if let last = before.last, last == "在" || last == "于", standsAlone(before.dropLast()) {
            // Not the end of a word (现在, 正在, 关于, 对于, 由于).
            before.removeLast()
        }
        // By when ("周五前交报告", "明天下午3点之前", 「周五之内」), about when (「3点左右」), or a 「的」 that tied the date
        // to the rest (「…的会议」).
        if let lead = ["之前", "以前", "之内", "以内", "左右", "的"].first(where: after.hasPrefix) {
            after.removeFirst(lead.count)
        } else if after.hasPrefix("前"), verbsAfterQian.contains(where: after.dropFirst().hasPrefix)
                    || !(after.dropFirst().first.map(wordsWithQian.contains) ?? false) {
            after.removeFirst()
        }
        trim()
        // Whether spaces set the phrase off (for the joint, below).
        var spaced = text[..<range.lowerBound].last?.isWhitespace == true && text[range.upperBound...].first?.isWhitespace == true
        // Brackets that held only the date (and its words), now empty: 「开会（明天下午3点）」. Only those: a pair
        // that was empty already is part of the title (「修复 parse() 崩溃」, "call foo() again"). Spaces around
        // them then set the phrase off ("call Bob (tomorrow) about it").
        while let open = before.last, let close = after.first, brackets.contains(where: { $0.open == open && $0.close == close }) {
            before.removeLast()
            after.removeFirst()
            spaced = before.last?.isWhitespace == true && after.first?.isWhitespace == true
            trim()
        }
        // What only said what the date is, the date starting the text or a clause: 「明天是小王生日」, "tomorrow is
        // Bob's birthday" (not 是否, 是不是).
        if before.isEmpty || before.last?.isPunctuation == true || leads.contains(before) {
            if after.hasPrefix("是"), !["是否", "是不是", "是非"].contains(where: after.hasPrefix) {
                after.removeFirst()
            } else if let word = after.range(of: "^is(?=\\s)", options: [.regularExpression, .caseInsensitive]) {
                after.removeSubrange(word)
            }
            trim()
        }
        // One space where the text set the phrase off with spaces ("call Bob tomorrow at 3pm about it"),
        // or where two Latin words would run together; none between Chinese words written together.
        var joint = ""
        if let last = before.last, let first = after.first, !first.isPunctuation, !"([（【「“".contains(last),
           spaced || isLatin(last) && isLatin(first) {
            joint = " "
        }
        return before + joint + after
    }

    private static let brackets: [(open: Character, close: Character)] = [("（", "）"), ("(", ")"), ("【", "】"), ("[", "]"), ("「", "」")]

    /// `range` with the other half of a bracket it opens or closes, when that is right next to it: of
    /// 「明天（下午3点）开会」 the phrase is 「明天（下午3点」, and 「）」 goes with it.
    static func withBrackets(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        var lower = range.lowerBound, upper = range.upperBound
        for (open, close) in brackets {
            let inside = text[lower..<upper]
            let opens = inside.filter { $0 == open }.count, closes = inside.filter { $0 == close }.count
            if opens > closes, upper < text.endIndex, text[upper] == close {
                upper = text.index(after: upper)
            } else if closes > opens, lower > text.startIndex, text[text.index(before: lower)] == open {
                lower = text.index(before: lower)
            }
        }
        return lower..<upper
    }

    /// Whether a 「在」 / 「于」 after `prefix` is a word of its own: at the start, after a space or punctuation,
    /// or after 我 ("提醒我在明天…").
    private static func standsAlone(_ prefix: Substring) -> Bool {
        guard let last = prefix.last else { return true }
        return last.isWhitespace || last.isPunctuation || last == "我"
    }

    /// 「前」 starting a word of its own after the date: 前台, 前面, 前往 … (not "by then").
    private static let wordsWithQian: Set<Character> = Set("台面往门排任端提方辈进线后夕景途锋妻夫天年者身额沿卫列")
    /// Verbs after a "by then" 「前」 that start like one of those words: 「周五前提交报告」 (not 前提), 「下午3点前提供数据」,
    /// 「周五前列出意见」.
    private static let verbsAfterQian = ["提交", "提供", "提出", "提醒", "列出", "进行"]
    /// What only asks for the reminder, at the start of its text.
    private static let leads = ["提醒我一下", "提醒一下", "提醒我", "记得"]

    private static let trimmedCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，。、；：！？,.;:!?…·~～-—–"))

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: trimmedCharacters) }

    private static func isLatin(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }
}

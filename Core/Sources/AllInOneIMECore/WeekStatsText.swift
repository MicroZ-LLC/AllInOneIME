import Foundation

/// A week's stats as words, in an interface language (`InterfaceLanguage`): what Settings → This Week's card, the shared
/// picture, the menu bar panel's row and `@stats`'s row say, laid out as the owner's design has them ("这周你用了 / 132 /
/// 次指令", "↑18% 比上周同期", "5 天都用了 · 在 8 个 App 里" …). The shells draw it; the numbers are the snapshot's.
public struct WeekStatsText: Equatable, Sendable {
    public let week: WeekStats.Snapshot
    public let language: String
    private let words: WeekStatsWords

    public init(_ week: WeekStats.Snapshot, language: String) {
        self.week = week
        self.language = language
        words = WeekStatsWords(language: language)
    }

    public static func == (lhs: WeekStatsText, rhs: WeekStatsText) -> Bool {
        lhs.week == rhs.week && lhs.language == rhs.language
    }

    // MARK: The page

    /// The page's name in the sidebar ("本周") and its title ("本周统计"), whatever the week.
    public static func sidebarTitle(language: String) -> String { WeekStatsWords(language: language).thisWeek }
    public static func pageTitle(language: String) -> String { WeekStatsWords(language: language).pageTitle }
    /// What Settings → Privacy → Learned… lists for the stats, which its Forget All forgets too.
    public static func learnedRow(language: String) -> String {
        WeekStatsWords(language: language).kept(weeks: WeekStats.weeksKept)
    }

    /// The sidebar's name for the page ("本周").
    public var sidebarTitle: String { words.thisWeek }
    /// "本周统计".
    public var pageTitle: String { words.pageTitle }
    /// The page's two tabs: this week, last week.
    public var tabTitles: [String] { [words.thisWeek, words.lastWeek] }
    public var hideNamesLabel: String { words.hideNames }
    /// Under the switch: how one of the user's own commands shows in the picture ("@sig 会显示成「我的命令 1」"), the most
    /// run of them, or the user's own in general when none ran.
    public var hideNamesNote: String {
        guard let own = week.topCommands.first(where: { $0.source == .own }) else { return words.hideNamesNoteGeneric }
        return words.hideNamesNote("@" + own.id, words.ownCommand(1))
    }
    public var saveImageLabel: String { words.saveImage }
    public var copyImageLabel: String { words.copyImage }
    /// "统计只存在这台 Mac 上，不同步，也不上传。"
    public var privacyNote: String { words.privacyNote }
    /// The notice once the picture is on the clipboard.
    public var imageCopied: String { words.imageCopied }

    // MARK: The card

    /// "这周你用了" on the page, "这周我用了" in the shared picture (last week's: "上周…").
    public var headline: String { week.week == .current ? words.headlineYou : words.lastHeadlineYou }
    public var shareHeadline: String { week.week == .current ? words.headlineI : words.lastHeadlineI }
    /// The big number, and what it counts ("次指令", "commands").
    public var count: String { "\(week.commandCount)" }
    public var countUnit: String { words.unit(week.commandCount) }

    /// How the week compares with the one before, in a sentence: "比上周同期多 18%", "比上周同期少 25%"; in the first week
    /// counted, "下周起会和上周比较"; nil when the week before had none on those days (or this is last week's first).
    public var comparison: String? {
        guard let comparison = week.comparison else {
            return week.week == .current && week.isFirstWeek ? words.firstWeek : nil
        }
        let percent = "\(abs(comparison.percent))"
        let previous = week.week == .previous
        switch comparison.percent {
        case 1...: return previous ? words.moreThanWeekBefore(percent) : words.moreThanLastWeek(percent)
        case ..<0: return previous ? words.fewerThanWeekBefore(percent) : words.fewerThanLastWeek(percent)
        default: return previous ? words.sameAsWeekBefore : words.sameAsLastWeek
        }
    }

    /// Which way the week went, for the badge's arrow; nil without a comparison.
    public enum Trend: Sendable {
        case up, down, same
    }

    public var trend: Trend? {
        week.comparison.map { $0.percent > 0 ? .up : $0.percent < 0 ? .down : .same }
    }

    /// The badge's number ("18%"; "0%" the same), and the words beside it ("比上周同期"); nil without a comparison.
    public var comparisonPercent: String? { week.comparison.map { words.percent("\(abs($0.percent))") } }
    public var comparisonLabel: String? {
        week.comparison.map { _ in week.week == .previous ? words.againstWeekBefore : words.againstLastWeek }
    }
    /// The badge as one text: "↑18%", "↓25%", "18%"…
    public var comparisonBadge: String? {
        guard let percent = comparisonPercent, let trend else { return nil }
        switch trend {
        case .up: return "↑" + percent
        case .down: return "↓" + percent
        case .same: return percent
        }
    }

    /// "5 天都用了 · 在 8 个 App 里".
    public var activity: String { words.daysUsed(week.daysUsed) + " · " + words.apps(week.distinctAppCount) }
    /// Under it: "打了 12,340 个字", the characters typed through the input method in the week (the number grouped as
    /// the language groups it); nil when there are none. Not on the menu bar panel's row or `@stats`'s.
    public var charactersTyped: String? {
        week.charactersTyped > 0 ? words.charactersTyped(week.charactersTyped) : nil
    }

    /// The week's days ("11 月 9 日 – 15 日").
    public var dateRange: String {
        guard let first = week.days.first?.date, let last = week.days.last?.date else { return "" }
        return words.range(first, last, calendar: week.calendar)
    }

    /// The line above the card: the days, then how far it goes ("截至周五") or, in the first week counted, the day it
    /// started ("从周四开始统计").
    public var dateSubtitle: String {
        if week.isFirstWeek, let first = week.firstRecordedDay,
           let index = week.days.firstIndex(where: { $0.date == first }) {
            return dateRange + " · " + words.countingSince(words.weekday(index))
        }
        if let today = week.todayIndex { return dateRange + " · " + words.through(words.weekday(today)) }
        return dateRange
    }

    /// "AllInOneIME 0.7.4", across from the days.
    public var versionLabel: String { "AllInOneIME " + AppVersion.string }

    /// Over each bar: its count, or "–" for a day without any (and the days after today).
    public var barLabels: [String] { week.days.map { $0.commandCount > 0 && !$0.isFuture ? "\($0.commandCount)" : "–" } }

    /// Under each bar: the weekday ("一" … "日"), today as "今天" on the page; the picture names every day.
    public func weekdayLabels(forShare: Bool) -> [String] {
        (0..<7).map { index in !forShare && week.days[index].isToday ? words.today : words.shortWeekday(index) }
    }

    /// "常用指令", over the commands.
    public var topCommandsTitle: String { words.mostUsed }
    /// Under them: the rest ("另外 4 个指令共 32 次"); nil when they are all listed.
    public var otherCommands: String? {
        let others = week.otherCommands
        return others.count > 0 ? words.others(others.count, others.total) : nil
    }
    /// Under them when they are all listed (none ran, or few): where to find every command.
    public var commandHint: String? { otherCommands == nil ? words.hint : nil }

    /// "来自", over the split bar.
    public var sourcesTitle: String { words.from }
    /// "其中 54 次用到 AI".
    public var aiSummary: String { words.usedAI(week.aiCommandCount) }
    /// The split bar's legend: the user's own, built in, plugins.
    public func sourceName(_ source: WeekStats.CommandSource) -> String {
        switch source {
        case .own: return words.own
        case .builtIn: return words.builtIn
        case .plugin: return words.plugins
        }
    }
    /// The split on one line: "我的命令 61 · 内置 52 · 插件 19".
    public var sourceSummary: String {
        let counts = week.sourceCounts
        return words.sourceSummary("\(counts.own)", "\(counts.builtIn)", "\(counts.plugin)")
    }

    /// "另外，从剪贴板历史粘贴了 47 次", and what is (not) kept of them.
    public var clipboardPastes: String { words.pastes(week.clipboardPasteCount) }
    public var clipboardNote: String { words.countsOnly }
    public var clipboardFooter: String { clipboardPastes + " · " + clipboardNote }

    /// The card read out (VoiceOver): the headline and number, the comparison, the days and apps, the commands.
    public func spoken(forShare: Bool = false, hideOwnCommandNames: Bool = false) -> String {
        var parts = [(forShare ? shareHeadline : headline) + " " + count + " " + countUnit]
        if let comparison { parts.append(comparison) }
        parts.append(activity)
        if let charactersTyped { parts.append(charactersTyped) }
        parts.append(week.shareCommands(hideOwnCommandNames: forShare && hideOwnCommandNames, language: language)
            .map { "\($0.displayName) \($0.count)" }.joined(separator: ", "))
        parts.append(sourceSummary)
        parts.append(aiSummary)
        parts.append(clipboardPastes)
        return parts.joined(separator: ". ")
    }

    // MARK: The menu bar panel and @stats

    /// "本周 132 次指令": the menu bar panel's row and `@stats`'s.
    public var menuBarTitle: String { words.thisWeekCount(week.commandCount) }
    /// The row with its badge: "本周 132 次指令 ↑18%".
    public var menuBarRow: String { comparisonBadge.map { menuBarTitle + " " + $0 } ?? menuBarTitle }
    public var atStatsTitle: String { menuBarTitle }
    /// Beside it: "比上周同期多 18%"; nil without a comparison.
    public var atStatsComparison: String? { week.comparison == nil ? nil : comparison }
    /// ⏎'s word on `@stats`'s row (its keys are said in the panel's footer: `PanelPresenter`).
    public var openAction: String { words.open }
}

/// The stats' words in each interface language that ships: Simplified Chinese (the design's), English, Traditional
/// Chinese, Japanese, Korean, German, French, Spanish and Brazilian Portuguese; English for any other. Kept here, with
/// the code that uses them, rather than in the String Catalog: the shared picture and `@stats` read the same in every
/// shell, the core's own tests included, which have no catalog's translations (a shell installs those). The formats take
/// what `InterfaceText.fill` takes (%@, %n$@, %%).
struct WeekStatsWords: Sendable {
    static let languages = ["zh-Hans", "en", "zh-Hant", "ja", "ko", "de", "fr", "es", "pt-BR"]

    let language: String
    private let index: Int

    init(language: String) {
        self.language = language
        if let exact = Self.languages.firstIndex(of: language) {
            index = exact
        } else if InterfaceLanguage.isChinese(language) {
            index = InterfaceLanguage.isSimplifiedChinese(language) ? 0 : 2
        } else {
            index = Self.languages.firstIndex(of: String(language.prefix { $0 != "-" })) ?? 1
        }
    }

    private var code: String { Self.languages[index] }

    private func pick(_ values: [String]) -> String { values[index] }

    private func fill(_ values: [String], _ arguments: String...) -> String {
        InterfaceText.fill(values[index], arguments) ?? InterfaceText.fill(values[1], arguments) ?? values[1]
    }

    /// One of two forms by `count`: French and Portuguese take 0 and 1 as one, the others only 1. `number`: the count
    /// as shown (`grouped`), else its digits.
    private func plural(_ count: Int, _ one: [String], _ other: [String], number: String? = nil) -> String {
        let single = ["fr", "pt-BR"].contains(code) ? count == 0 || count == 1 : count == 1
        return fill(single ? one : other, number ?? "\(count)")
    }

    /// `count` with its thousands grouped as the language writes them: "12,340" (Chinese, Japanese, Korean, English),
    /// "12.340" (German, Spanish, Portuguese; Spanish leaves four digits alone: "1234"), "12 340" (French, a narrow
    /// no-break space). The same on every platform (no locale data needed).
    func grouped(_ count: Int) -> String {
        let digits = String(abs(count))
        let separator: String
        switch code {
        case "de", "pt-BR": separator = "."
        case "es": separator = digits.count > 4 ? "." : ""
        case "fr": separator = "\u{202F}"
        default: separator = ","
        }
        var groups: [Substring] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(digits[start..<end], at: 0)
            end = start
        }
        return (count < 0 ? "-" : "") + groups.joined(separator: separator)
    }

    // The order of each list: zh-Hans, en, zh-Hant, ja, ko, de, fr, es, pt-BR.

    var thisWeek: String { pick(["本周", "This Week", "本週", "今週", "이번 주", "Diese Woche", "Cette semaine", "Esta semana", "Esta semana"]) }
    var lastWeek: String { pick(["上周", "Last Week", "上週", "先週", "지난주", "Letzte Woche", "Semaine dernière", "Semana pasada", "Semana passada"]) }
    var pageTitle: String {
        pick(["本周统计", "This Week's Stats", "本週統計", "今週の統計", "이번 주 통계", "Diese Woche in Zahlen",
              "Statistiques de la semaine", "Estadísticas de la semana", "Estatísticas da semana"])
    }

    var headlineYou: String {
        pick(["这周你用了", "This week you used", "這週你用了", "今週あなたが使ったコマンド", "이번 주에 사용한 명령",
              "Diese Woche hast du genutzt", "Cette semaine, vous avez utilisé", "Esta semana usaste", "Esta semana você usou"])
    }
    var headlineI: String {
        pick(["这周我用了", "This week I used", "這週我用了", "今週わたしが使ったコマンド", "이번 주에 내가 사용한 명령",
              "Diese Woche habe ich genutzt", "Cette semaine, j’ai utilisé", "Esta semana usé", "Esta semana eu usei"])
    }
    var lastHeadlineYou: String {
        pick(["上周你用了", "Last week you used", "上週你用了", "先週あなたが使ったコマンド", "지난주에 사용한 명령",
              "Letzte Woche hast du genutzt", "La semaine dernière, vous avez utilisé", "La semana pasada usaste",
              "Na semana passada você usou"])
    }
    var lastHeadlineI: String {
        pick(["上周我用了", "Last week I used", "上週我用了", "先週わたしが使ったコマンド", "지난주에 내가 사용한 명령",
              "Letzte Woche habe ich genutzt", "La semaine dernière, j’ai utilisé", "La semana pasada usé",
              "Na semana passada eu usei"])
    }
    func unit(_ count: Int) -> String {
        let single = ["fr", "pt-BR"].contains(code) ? count == 0 || count == 1 : count == 1
        return pick(single ? ["次指令", "command", "次指令", "回", "회", "Befehl", "commande", "comando", "comando"]
                    : ["次指令", "commands", "次指令", "回", "회", "Befehle", "commandes", "comandos", "comandos"])
    }

    func percent(_ number: String) -> String {
        fill(["%@%%", "%@%%", "%@%%", "%@%%", "%@%%", "%@\u{00A0}%%", "%@\u{00A0}%%", "%@\u{00A0}%%", "%@%%"], number)
    }
    var againstLastWeek: String {
        pick(["比上周同期", "vs. the same days last week", "比上週同期", "先週の同じ時点と比べて", "지난주 같은 기간 대비",
              "ggü. denselben Tagen der Vorwoche", "par rapport aux mêmes jours la semaine dernière",
              "frente a los mismos días de la semana pasada", "em relação aos mesmos dias da semana passada"])
    }
    var againstWeekBefore: String {
        pick(["比前一周", "vs. the week before", "比前一週", "前の週と比べて", "그 전 주 대비", "ggü. der Woche davor",
              "par rapport à la semaine précédente", "frente a la semana anterior", "em relação à semana anterior"])
    }
    func moreThanLastWeek(_ number: String) -> String {
        fill(["比上周同期多 %@%%", "%@%% more than the same days last week", "比上週同期多 %@%%", "先週の同じ時点より %@%% 多い",
              "지난주 같은 기간보다 %@%% 많음", "%@\u{00A0}%% mehr als an denselben Tagen der Vorwoche",
              "%@\u{00A0}%% de plus que les mêmes jours la semaine dernière",
              "un %@\u{00A0}%% más que los mismos días de la semana pasada", "%@%% a mais que nos mesmos dias da semana passada"],
             number)
    }
    func fewerThanLastWeek(_ number: String) -> String {
        fill(["比上周同期少 %@%%", "%@%% fewer than the same days last week", "比上週同期少 %@%%", "先週の同じ時点より %@%% 少ない",
              "지난주 같은 기간보다 %@%% 적음", "%@\u{00A0}%% weniger als an denselben Tagen der Vorwoche",
              "%@\u{00A0}%% de moins que les mêmes jours la semaine dernière",
              "un %@\u{00A0}%% menos que los mismos días de la semana pasada", "%@%% a menos que nos mesmos dias da semana passada"],
             number)
    }
    var sameAsLastWeek: String {
        pick(["和上周同期一样多", "The same as the same days last week", "和上週同期一樣多", "先週の同じ時点と同じ",
              "지난주 같은 기간과 같음", "Genauso viele wie an denselben Tagen der Vorwoche",
              "Autant que les mêmes jours la semaine dernière", "Igual que los mismos días de la semana pasada",
              "O mesmo que nos mesmos dias da semana passada"])
    }
    func moreThanWeekBefore(_ number: String) -> String {
        fill(["比前一周多 %@%%", "%@%% more than the week before", "比前一週多 %@%%", "前の週より %@%% 多い", "그 전 주보다 %@%% 많음",
              "%@\u{00A0}%% mehr als in der Woche davor", "%@\u{00A0}%% de plus que la semaine précédente",
              "un %@\u{00A0}%% más que la semana anterior", "%@%% a mais que na semana anterior"], number)
    }
    func fewerThanWeekBefore(_ number: String) -> String {
        fill(["比前一周少 %@%%", "%@%% fewer than the week before", "比前一週少 %@%%", "前の週より %@%% 少ない", "그 전 주보다 %@%% 적음",
              "%@\u{00A0}%% weniger als in der Woche davor", "%@\u{00A0}%% de moins que la semaine précédente",
              "un %@\u{00A0}%% menos que la semana anterior", "%@%% a menos que na semana anterior"], number)
    }
    var sameAsWeekBefore: String {
        pick(["和前一周一样多", "The same as the week before", "和前一週一樣多", "前の週と同じ", "그 전 주와 같음",
              "Genauso viele wie in der Woche davor", "Autant que la semaine précédente", "Igual que la semana anterior",
              "O mesmo que na semana anterior"])
    }
    var firstWeek: String {
        pick(["下周起会和上周比较", "Compared with last week from next week", "下週起會和上週比較", "来週から前の週と比べます",
              "다음 주부터 지난주와 비교해요", "Vergleich mit der Vorwoche ab nächster Woche",
              "Comparaison dès la semaine prochaine", "Comparación desde la próxima semana",
              "Comparação a partir da próxima semana"])
    }

    func through(_ weekday: String) -> String {
        fill(["截至%@", "through %@", "截至%@", "%@まで", "%@까지", "bis %@", "jusqu’à %@", "hasta el %@", "até %@"], weekday)
    }
    func countingSince(_ weekday: String) -> String {
        fill(["从%@开始统计", "counting since %@", "從%@開始統計", "%@から集計", "%@부터 집계", "gezählt ab %@", "compté depuis %@",
              "contando desde el %@", "contando desde %@"], weekday)
    }

    /// Monday (0) to Sunday (6), as "截至周五" names it.
    func weekday(_ index: Int) -> String {
        let names: [[String]] = [
            ["周一", "周二", "周三", "周四", "周五", "周六", "周日"],
            ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
            ["週一", "週二", "週三", "週四", "週五", "週六", "週日"],
            ["月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日", "日曜日"],
            ["월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일"],
            ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"],
            ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"],
            ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"],
            ["segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado", "domingo"],
        ]
        return names[self.index][min(max(index, 0), 6)]
    }

    /// Monday (0) to Sunday (6), under the bars.
    func shortWeekday(_ index: Int) -> String {
        let names: [[String]] = [
            ["一", "二", "三", "四", "五", "六", "日"],
            ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
            ["一", "二", "三", "四", "五", "六", "日"],
            ["月", "火", "水", "木", "金", "土", "日"],
            ["월", "화", "수", "목", "금", "토", "일"],
            ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"],
            ["lun", "mar", "mer", "jeu", "ven", "sam", "dim"],
            ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"],
            ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"],
        ]
        return names[self.index][min(max(index, 0), 6)]
    }

    var today: String { pick(["今天", "Today", "今天", "今日", "오늘", "Heute", "Auj.", "Hoy", "Hoje"]) }

    /// The days from `first` to `last` ("11 月 9 日 – 15 日", "Nov 9 – 15", "Oct 26 – Nov 1"), read in `calendar` (the
    /// snapshot's: its days are in its time zone).
    func range(_ first: Date, _ last: Date, calendar: Calendar) -> String {
        let a = calendar.dateComponents([.month, .day], from: first), b = calendar.dateComponents([.month, .day], from: last)
        let (m1, d1, m2, d2) = (a.month ?? 1, a.day ?? 1, b.month ?? 1, b.day ?? 1)
        let same = m1 == m2
        let months: [String]
        switch code {
        case "zh-Hans", "zh-Hant":
            return same ? "\(m1) 月 \(d1) 日 – \(d2) 日" : "\(m1) 月 \(d1) 日 – \(m2) 月 \(d2) 日"
        case "ja":
            return same ? "\(m1)月\(d1)日 – \(d2)日" : "\(m1)月\(d1)日 – \(m2)月\(d2)日"
        case "ko":
            return same ? "\(m1)월 \(d1)일 – \(d2)일" : "\(m1)월 \(d1)일 – \(m2)월 \(d2)일"
        case "de":
            months = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]
            return same ? "\(d1). – \(d2). \(months[m2 - 1])" : "\(d1). \(months[m1 - 1]) – \(d2). \(months[m2 - 1])"
        case "fr":
            months = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]
            return same ? "\(d1) – \(d2) \(months[m2 - 1])" : "\(d1) \(months[m1 - 1]) – \(d2) \(months[m2 - 1])"
        case "es":
            months = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"]
            return same ? "\(d1) – \(d2) \(months[m2 - 1])" : "\(d1) \(months[m1 - 1]) – \(d2) \(months[m2 - 1])"
        case "pt-BR":
            months = ["jan.", "fev.", "mar.", "abr.", "mai.", "jun.", "jul.", "ago.", "set.", "out.", "nov.", "dez."]
            return same ? "\(d1) – \(d2) de \(months[m2 - 1])" : "\(d1) de \(months[m1 - 1]) – \(d2) de \(months[m2 - 1])"
        default:
            months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            return same ? "\(months[m1 - 1]) \(d1) – \(d2)" : "\(months[m1 - 1]) \(d1) – \(months[m2 - 1]) \(d2)"
        }
    }

    func daysUsed(_ count: Int) -> String {
        plural(count, ["%@ 天都用了", "Used on %@ day", "%@ 天都用了", "%@ 日間使用", "%@일 사용", "An %@ Tag genutzt",
                       "Utilisé %@ jour", "Usado %@ día", "Usado em %@ dia"],
               ["%@ 天都用了", "Used on %@ days", "%@ 天都用了", "%@ 日間使用", "%@일 사용", "An %@ Tagen genutzt",
                "Utilisé %@ jours", "Usado %@ días", "Usado em %@ dias"])
    }
    func apps(_ count: Int) -> String {
        plural(count, ["在 %@ 个 App 里", "in %@ app", "在 %@ 個 App 裡", "%@ 個のアプリで", "앱 %@개에서", "in %@ App",
                       "dans %@ app", "en %@ app", "em %@ app"],
               ["在 %@ 个 App 里", "in %@ apps", "在 %@ 個 App 裡", "%@ 個のアプリで", "앱 %@개에서", "in %@ Apps",
                "dans %@ apps", "en %@ apps", "em %@ apps"])
    }

    func charactersTyped(_ count: Int) -> String {
        plural(count, ["打了 %@ 个字", "%@ character typed", "打了 %@ 個字", "%@ 文字を入力", "%@자 입력", "%@ Zeichen getippt",
                       "%@ caractère saisi", "%@ carácter escrito", "%@ caractere digitado"],
               ["打了 %@ 个字", "%@ characters typed", "打了 %@ 個字", "%@ 文字を入力", "%@자 입력", "%@ Zeichen getippt",
                "%@ caractères saisis", "%@ caracteres escritos", "%@ caracteres digitados"], number: grouped(count))
    }

    var mostUsed: String {
        pick(["常用指令", "Most Used", "常用指令", "よく使うコマンド", "자주 쓰는 명령", "Meistgenutzt", "Les plus utilisées",
              "Los más usados", "Mais usados"])
    }
    func others(_ commands: Int, _ runs: Int) -> String {
        let first = plural(commands, ["另外 %@ 个指令", "%@ more command", "另外 %@ 個指令", "ほか %@ 個のコマンドで",
                                      "명령 %@개 더", "%@ weiterer Befehl", "%@ autre commande", "%@ comando más", "mais %@ comando"],
                           ["另外 %@ 个指令", "%@ more commands", "另外 %@ 個指令", "ほか %@ 個のコマンドで", "명령 %@개 더",
                            "%@ weitere Befehle", "%@ autres commandes", "%@ comandos más", "mais %@ comandos"])
        let second = plural(runs, ["共 %@ 次", ", %@ run in all", "共 %@ 次", "計 %@ 回", ", 모두 %@회", ", zusammen %@-mal",
                                   ", %@ fois au total", ", %@ vez en total", ", %@ vez no total"],
                            ["共 %@ 次", ", %@ runs in all", "共 %@ 次", "計 %@ 回", ", 모두 %@회", ", zusammen %@-mal",
                             ", %@ fois au total", ", %@ veces en total", ", %@ vezes no total"])
        return first + second
    }
    var hint: String {
        pick(["在输入框开头打 @，可以看到全部指令", "Type @ at the start of a text field to see every command",
              "在輸入框開頭打 @，可以看到全部指令", "入力欄の先頭で @ を打つと、すべてのコマンドが表示されます",
              "입력란 맨 앞에 @를 입력하면 모든 명령을 볼 수 있어요", "Tippe @ am Anfang eines Textfelds, um alle Befehle zu sehen",
              "Tapez @ au début d’un champ de texte pour voir toutes les commandes",
              "Escribe @ al principio de un campo de texto para ver todos los comandos",
              "Digite @ no início de um campo de texto para ver todos os comandos"])
    }

    var from: String { pick(["来自", "From", "來自", "内訳", "출처", "Herkunft", "Provenance", "Origen", "Origem"]) }
    func usedAI(_ count: Int) -> String {
        plural(count, ["其中 %@ 次用到 AI", "%@ of them used AI", "其中 %@ 次用到 AI", "うち %@ 回は AI を使用", "그중 %@회는 AI 사용",
                       "davon %@ mit KI", "dont %@ avec l’IA", "%@ de ellos con IA", "%@ deles com IA"],
               ["其中 %@ 次用到 AI", "%@ of them used AI", "其中 %@ 次用到 AI", "うち %@ 回は AI を使用", "그중 %@회는 AI 사용",
                "davon %@ mit KI", "dont %@ avec l’IA", "%@ de ellos con IA", "%@ deles com IA"])
    }
    var own: String {
        pick(["我的命令", "My commands", "我的命令", "自分のコマンド", "내 명령", "Eigene", "Mes commandes", "Mis comandos", "Meus comandos"])
    }
    var builtIn: String {
        pick(["内置", "Built-in", "內建", "組み込み", "기본 제공", "Integriert", "Intégrées", "Integrados", "Integrados"])
    }
    var plugins: String { pick(["插件", "Plugins", "外掛", "プラグイン", "플러그인", "Plug-ins", "Plug-ins", "Plugins", "Plug-ins"]) }
    func sourceSummary(_ own: String, _ builtIn: String, _ plugins: String) -> String {
        fill(["我的命令 %1$@ · 内置 %2$@ · 插件 %3$@", "%1$@ yours · %2$@ built-in · %3$@ from plugins",
              "我的命令 %1$@ · 內建 %2$@ · 外掛 %3$@", "自分のコマンド %1$@ · 組み込み %2$@ · プラグイン %3$@",
              "내 명령 %1$@ · 기본 제공 %2$@ · 플러그인 %3$@", "Eigene %1$@ · Integriert %2$@ · Plug-ins %3$@",
              "Mes commandes %1$@ · Intégrées %2$@ · Plug-ins %3$@", "Mis comandos %1$@ · Integrados %2$@ · Plugins %3$@",
              "Meus comandos %1$@ · Integrados %2$@ · Plug-ins %3$@"], own, builtIn, plugins)
    }

    func pastes(_ count: Int) -> String {
        plural(count, ["另外，从剪贴板历史粘贴了 %@ 次", "Also, %@ paste from clipboard history", "另外，從剪貼簿歷史貼上了 %@ 次",
                       "また、クリップボード履歴から %@ 回ペースト", "또한 클립보드 기록에서 %@회 붙여넣음",
                       "Außerdem %@-mal aus dem Verlauf der Zwischenablage eingesetzt",
                       "Et %@ collage depuis l’historique du presse-papiers", "Además, %@ pegado desde el historial del portapapeles",
                       "Além disso, %@ colagem do histórico da área de transferência"],
               ["另外，从剪贴板历史粘贴了 %@ 次", "Also, %@ pastes from clipboard history", "另外，從剪貼簿歷史貼上了 %@ 次",
                "また、クリップボード履歴から %@ 回ペースト", "또한 클립보드 기록에서 %@회 붙여넣음",
                "Außerdem %@-mal aus dem Verlauf der Zwischenablage eingesetzt",
                "Et %@ collages depuis l’historique du presse-papiers", "Además, %@ pegados desde el historial del portapapeles",
                "Além disso, %@ colagens do histórico da área de transferência"])
    }
    var countsOnly: String {
        pick(["只记次数，不记内容", "Counts only, never the contents", "只記次數，不記內容", "回数だけを記録し、内容は記録しません",
              "횟수만 기록하고 내용은 기록하지 않아요", "Nur die Anzahl, nie der Inhalt", "Le nombre seulement, jamais le contenu",
              "Solo la cantidad, nunca el contenido", "Só a contagem, nunca o conteúdo"])
    }

    var hideNames: String {
        pick(["复制时隐藏我的命令名", "Hide my command names in the image", "複製時隱藏我的命令名稱", "画像では自分のコマンド名を隠す",
              "이미지에서 내 명령 이름 숨기기", "Eigene Befehlsnamen im Bild ausblenden", "Masquer le nom de mes commandes dans l’image",
              "Ocultar los nombres de mis comandos en la imagen", "Ocultar os nomes dos meus comandos na imagem"])
    }
    func hideNamesNote(_ name: String, _ shown: String) -> String {
        InterfaceText.fill(pick(["%1$@ 会显示成「%2$@」", "%1$@ shows as “%2$@”", "%1$@ 會顯示成「%2$@」", "%1$@ は「%2$@」と表示されます",
                                 "%1$@은(는) ‘%2$@’(으)로 표시돼요", "%1$@ erscheint als „%2$@“", "%1$@ apparaît comme «\u{00A0}%2$@\u{00A0}»",
                                 "%1$@ aparece como «%2$@»", "%1$@ aparece como “%2$@”"]), [name, shown]) ?? name
    }
    var hideNamesNoteGeneric: String {
        pick(["你的命令会显示成「我的命令 1」「我的命令 2」…", "Yours show as “My command 1”, “My command 2” …",
              "你的命令會顯示成「我的命令 1」「我的命令 2」…", "自分のコマンドは「自分のコマンド 1」「自分のコマンド 2」…と表示されます",
              "내 명령은 ‘내 명령 1’, ‘내 명령 2’ …로 표시돼요", "Eigene erscheinen als „Eigener Befehl 1“, „Eigener Befehl 2“ …",
              "Les vôtres apparaissent comme «\u{00A0}Ma commande 1\u{00A0}», «\u{00A0}Ma commande 2\u{00A0}» …",
              "Los tuyos aparecen como «Mi comando 1», «Mi comando 2» …", "Os seus aparecem como “Meu comando 1”, “Meu comando 2” …"])
    }
    func ownCommand(_ number: Int) -> String {
        fill(["我的命令 %@", "My command %@", "我的命令 %@", "自分のコマンド %@", "내 명령 %@", "Eigener Befehl %@", "Ma commande %@",
              "Mi comando %@", "Meu comando %@"], "\(number)")
    }
    var saveImage: String {
        pick(["存为图片…", "Save as Image…", "存成圖片…", "画像として保存…", "이미지로 저장…", "Als Bild sichern …",
              "Enregistrer l’image…", "Guardar como imagen…", "Salvar como imagem…"])
    }
    var copyImage: String {
        pick(["复制图片", "Copy Image", "拷貝圖片", "画像をコピー", "이미지 복사", "Bild kopieren", "Copier l’image", "Copiar imagen",
              "Copiar imagem"])
    }
    var imageCopied: String {
        pick(["已复制图片", "Image copied", "已拷貝圖片", "画像をコピーしました", "이미지를 복사했어요", "Bild kopiert", "Image copiée",
              "Imagen copiada", "Imagem copiada"])
    }
    var privacyNote: String {
        pick(["统计只存在这台 Mac 上，不同步，也不上传。", "These stats stay on this Mac: never synced, never uploaded.",
              "統計只存在這台 Mac 上，不同步，也不上傳。", "統計はこの Mac にだけ保存され、同期もアップロードもされません。",
              "통계는 이 Mac에만 저장되며, 동기화하거나 업로드하지 않아요.",
              "Die Statistik bleibt auf diesem Mac: nie synchronisiert, nie hochgeladen.",
              "Ces statistiques restent sur ce Mac\u{00A0}: jamais synchronisées, jamais envoyées.",
              "Estas estadísticas se quedan en este Mac: nunca se sincronizan ni se suben.",
              "Estas estatísticas ficam neste Mac: nunca são sincronizadas nem enviadas."])
    }

    func thisWeekCount(_ count: Int) -> String {
        plural(count, ["本周 %@ 次指令", "%@ command this week", "本週 %@ 次指令", "今週 %@ 回のコマンド", "이번 주 명령 %@회",
                       "%@ Befehl diese Woche", "%@ commande cette semaine", "%@ comando esta semana", "%@ comando esta semana"],
               ["本周 %@ 次指令", "%@ commands this week", "本週 %@ 次指令", "今週 %@ 回のコマンド", "이번 주 명령 %@회",
                "%@ Befehle diese Woche", "%@ commandes cette semaine", "%@ comandos esta semana", "%@ comandos esta semana"])
    }
    var openStats: String {
        pick(["打开本周统计", "open this week's stats", "打開本週統計", "今週の統計を開く", "이번 주 통계 열기", "Wochenstatistik öffnen",
              "ouvrir les statistiques", "abrir las estadísticas", "abrir as estatísticas"])
    }
    var copyImageHint: String {
        pick(["复制图片", "copy image", "拷貝圖片", "画像をコピー", "이미지 복사", "Bild kopieren", "copier l’image", "copiar imagen",
              "copiar imagem"])
    }
    var cancel: String { pick(["取消", "cancel", "取消", "キャンセル", "취소", "abbrechen", "annuler", "cancelar", "cancelar"]) }
    var open: String { pick(["打开", "open", "打開", "開く", "열기", "öffnen", "ouvrir", "abrir", "abrir"]) }

    /// `@stats` in the command list.
    var commandSummary: String {
        pick(["本周用了多少次指令，可以复制成图片", "How much you used AllInOneIME this week, as a picture to share",
              "本週用了多少次指令，可以拷貝成圖片", "今週のコマンドの利用回数（画像で共有できます）",
              "이번 주 명령 사용 횟수 (이미지로 공유할 수 있어요)", "Wie oft du AllInOneIME diese Woche genutzt hast, als Bild zum Teilen",
              "Votre usage d’AllInOneIME cette semaine, en image à partager",
              "Cuánto usaste AllInOneIME esta semana, como imagen para compartir",
              "Quanto você usou o AllInOneIME esta semana, como imagem para compartilhar"])
    }

    /// Settings → Privacy → Learned…'s row for them.
    func kept(weeks: Int) -> String {
        fill(["本周统计：最近 %@ 周用了多少次指令、打了多少字（只有数字）",
              "This week's stats: how much you used it and how many characters you typed over the last %@ weeks (numbers only)",
              "本週統計：最近 %@ 週用了多少次指令、打了多少字（只有數字）", "今週の統計：過去 %@ 週間の利用回数と入力文字数（数のみ）",
              "이번 주 통계: 최근 %@주 동안의 사용 횟수와 입력한 글자 수(숫자만)",
              "Wochenstatistik: Nutzung und getippte Zeichen der letzten %@ Wochen (nur Zahlen)",
              "Statistiques de la semaine\u{00A0}: usage et caractères saisis des %@ dernières semaines (nombres seulement)",
              "Estadísticas de la semana: uso y caracteres escritos de las últimas %@ semanas (solo cantidades)",
              "Estatísticas da semana: uso e caracteres digitados das últimas %@ semanas (só contagens)"], "\(weeks)")
    }
}

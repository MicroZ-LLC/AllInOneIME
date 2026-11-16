import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// #122: a three-step start instead of "type @improve". Step 3's "Three example buttons each fill in a text after the
/// magic key: a sum (`200*15%`), a time (「明天下午三点开会」), and an app every Mac has (`safari`)", and "The panel is the
/// real one @ list, with nothing special here". The acceptance: "Each example's text gives the same first one-@ row as
/// the same text typed anywhere: a value, a reminder, an app."
///
/// Seen here, through a field's session (`FakeHost`) as any app's field has it, the examples typed after the magic key
/// as a user types them (the sentence as pinyin and Space with the input on Chinese, as the pinyin's first candidate
/// while it is composed, and as its characters; the sum and the app with the input on Chinese and on English), with
/// "@" and with "~" the magic key:
///   - `200*15%`: the first row is the sum's value (30), highlighted; ⏎ puts it in place of the text.
///   - 明天下午三点开会: the first row is the reminder (its command's name, its title 开会), highlighted; ⏎ adds it, due
///     tomorrow at 15:00.
///   - `safari`: the first row is Safari, highlighted; ⏎ opens it.
///   - "Step 3 sends nothing until the user presses Return on a row that uses the AI": none of the three sends anything,
///     before ⏎ or after it.
/// The examples are the issue's own (the Mac's `StartModel.examples`, which StartWindowMacTests holds to the same three).
/// The stand-ins: an app index with Safari among other apps (`SessionServices.instantResults`), the reminder's reading
/// of a time (the system's detector: 明天下午三点 is tomorrow at 15:00, by the clock now), a pinyin engine that knows the
/// sentence, and the on-device model, which keeps what it is sent. No network, no AI call.
@Suite(.serialized)
struct StartExamplesAcceptanceTests {
    typealias Suite = StartExamplesAcceptanceTests

    /// The issue's examples, in the order of step 3's buttons.
    static let sum = "200*15%"
    static let time = "明天下午三点开会"
    static let app = "safari"
    /// The sentence as its pinyin is typed.
    static let timePinyin = "mingtianxiawusandiankaihui"

    static let triggers = ["@", "~"]

    static let safari = SearchResult(name: "Safari", path: "/Applications/Safari.app")
    /// The apps the index knows: Safari is found by its name, not for being the only one.
    static let apps = [SearchResult(name: "Slack", path: "/Applications/Slack.app"),
                       SearchResult(name: "System Settings", path: "/System/Applications/System Settings.app", chineseName: "系统设置"),
                       safari,
                       SearchResult(name: "Calendar", path: "/System/Applications/Calendar.app", chineseName: "日历")]

    // MARK: - Stand-ins

    /// The on-device model (`Provider.apple`): keeps each request, answers it with one line.
    final class Model: AppleModelBackend, @unchecked Sendable {
        let availability = AppleModelAvailability.available
        let contextSize = 4096
        let supportedLanguages: Set<String> = ["en", "zh"]
        private let asked = Locked<[AppleModelRequest]>(initialState: [])

        var requests: [AppleModelRequest] { asked.withLock { $0 } }

        func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            asked.withLock { $0.append(request) }
            return AsyncThrowingStream { continuation in
                continuation.yield(AppleModelSnapshot(text: "OK"))
                continuation.finish()
            }
        }
    }

    /// The app index (`SessionServices.instantResults`): the apps each word typed starts a word of whose name (its own
    /// or its Chinese one), as the Mac's index finds them.
    static func found(_ query: String) -> [SearchResult] {
        let keywords = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !keywords.isEmpty else { return [] }
        return apps.filter { app in
            let words = ([app.name] + (app.chineseName.map { [$0] } ?? [])).flatMap { $0.lowercased().split(separator: " ").map(String.init) }
            return keywords.allSatisfy { keyword in words.contains { $0.hasPrefix(keyword) } }
        }
    }

    /// Tomorrow at 15:00 by the clock now.
    static func tomorrowAtThree(_ calendar: Calendar, _ now: Date) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: now).flatMap { calendar.date(bySettingHour: 15, minute: 0, second: 0, of: $0) }
    }

    /// `@reminder`'s reading of a text (`SessionServices.parseReminder`): the parser's own, with the system's detector
    /// stood in for: 明天下午三点 (or as the parser's rules may write it, 明天下午3点) is tomorrow at 15:00.
    static func reminder(in text: String) -> ReminderDraft {
        let (calendar, now) = (ReminderParser.localCalendar, Date())
        let parser = ReminderParser(calendar: calendar) { written in
            guard let range = written.range(of: "明天下午三点") ?? written.range(of: "明天下午3点"),
                  let date = tomorrowAtThree(calendar, now) else { return [] }
            return [ReminderParser.Match(range: range, date: date)]
        }
        return parser.parse(text, now: now)
    }

    /// A field of an app like any other that has the focus: Chinese the main input language, then English; the AI on the
    /// device (a stand-in); `trigger` the magic key.
    final class Field {
        let host: FakeHost
        let model = Model()
        let trigger: String
        let reminders = Locked<[ReminderDraft]>(initialState: [])

        init(trigger: String, english: Bool) {
            var config = Config.default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
            config.provider = .apple
            config.claudeInBackground = false
            config.commandTrigger = trigger
            let (fixed, engine, added) = (config, FakeEngine(), reminders)
            engine.dictionary[Suite.timePinyin] = [Suite.time]
            var services = SessionServices(converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: model),
                                           loadSettings: { fixed })
            services.levelOne = { .engine(engine) }
            services.instantResults = { query, _ in Suite.found(query) }
            services.searchFiles = { _, _ in [] }
            services.loadCommandUsage = { CommandUsage() }
            services.saveCommandUsage = { _ in }
            services.parseReminder = { Suite.reminder(in: $0) }
            services.addReminder = { draft in added.withLock { $0.append(draft) } }
            self.trigger = trigger
            host = FakeHost(services: services)
            host.focus()
            if english { host.composer.setInputMode(.english) }
        }

        /// The one-@ rows for the text: the panel's, without the pinyin candidates shown with them while composing.
        var rows: [PanelModel.Row] {
            let candidates = Set(host.composer.engineState.isComposing ? host.composer.engineState.candidates.map(\.text) : [])
            return (host.panel?.rows ?? []).filter { !candidates.contains($0.text) }
        }
        /// The first row, all it says.
        var first: String { rows.first.map { $0.text + " " + $0.comment } ?? "" }
        var texts: [String] { rows.map { $0.comment.isEmpty ? $0.text : "\($0.text) | \($0.comment)" } }
        /// The first row is the one highlighted: what ⏎ does.
        var firstIsHighlighted: Bool {
            guard let panel = host.panel, let index = panel.highlighted, panel.rows.indices.contains(index) else { return false }
            return panel.rows[index] == rows.first
        }

        /// The magic key, then `text`, a key a character.
        func typeAfterTheKey(_ text: String) { host.type(trigger + text) }
    }

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// How a field is asked for: the magic key, and the input on English or on Chinese.
    static let fields: [(trigger: String, english: Bool)] = triggers.flatMap { trigger in [false, true].map { (trigger, $0) } }

    // MARK: - A sum: its value

    /// `200*15%` after the magic key: the first row is its value, 30 ("`%` after a number is percent"), highlighted; ⏎
    /// puts 30 in place of the text. Nothing reaches the AI.
    @Test func theSumGivesItsValueFirst() async {
        await inEnglish {
            for (trigger, english) in Suite.fields {
                let field = Field(trigger: trigger, english: english)
                field.typeAfterTheKey(Suite.sum)
                let row = field.rows.first?.text.trimmingCharacters(in: .whitespaces) ?? ""
                #expect(row.hasPrefix("=") && row.contains("30"), "\(trigger), English \(english): \(field.texts)")
                #expect(field.firstIsHighlighted, "\(trigger), English \(english): \(field.texts)")
                #expect(field.model.requests.isEmpty, "sent before ⏎")
                field.host.press(FakeHost.enter)
                #expect(field.host.document == "30" && field.host.marked.isEmpty,
                        "\(trigger), English \(english): \(field.host.document)|\(field.host.marked)")
                #expect(!field.host.settle(timeout: 0.3) { !field.model.requests.isEmpty }, "a value was sent to the AI")
                #expect(field.host.opened.isEmpty && field.reminders.withLock { $0 }.isEmpty)
            }
        }
    }

    // MARK: - A time: the reminder

    /// What the reminder's row is told by: its command's name after the magic key, and its title.
    func expectReminderFirst(_ field: Field, _ how: String) {
        let expected = Suite.reminder(in: Suite.time)
        #expect(expected.title == "开会" && expected.hasTime, "the stand-in reads \(expected)")
        #expect(field.first.contains(field.trigger + Command.reminder.name) && field.first.contains("开会"),
                "\(field.trigger), \(how): \(field.texts)")
        // When, as `@reminder` says it: the system's clock, in the locale the test runs in.
        #expect(field.first.contains(UIText.when(expected)), "\(field.trigger), \(how): \(UIText.when(expected)): \(field.texts)")
        #expect(field.firstIsHighlighted, "\(field.trigger), \(how): \(field.texts)")
        #expect(field.model.requests.isEmpty && field.reminders.withLock { $0 }.isEmpty, "\(how): sent or added before ⏎")
    }

    /// 明天下午三点开会 after the magic key, typed as its pinyin and Space (the input on Chinese): the first row is the
    /// reminder, highlighted; ⏎ adds it: 开会, tomorrow at 15:00. Nothing reaches the AI.
    @Test func theTimeGivesAReminderFirst() async {
        await inEnglish {
            for trigger in Suite.triggers {
                let field = Field(trigger: trigger, english: false)
                field.typeAfterTheKey(Suite.timePinyin)
                field.host.press(FakeHost.space)
                expectReminderFirst(field, "pinyin and Space")
                field.host.press(FakeHost.enter)
                let expected = Suite.reminder(in: Suite.time)
                #expect(field.host.settle(timeout: 5) { !field.reminders.withLock { $0 }.isEmpty }, "\(trigger): no reminder added")
                let added = field.reminders.withLock { $0 }
                #expect(added == [expected], "\(trigger): \(added)")
                let calendar = ReminderParser.localCalendar
                let due = Suite.tomorrowAtThree(calendar, Date()).map { calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
                #expect(added.first?.due?.day == due?.day && added.first?.due?.hour == 15 && added.first?.due?.minute == 0,
                        "\(trigger): due \(String(describing: added.first?.due))")
                #expect(!field.host.settle(timeout: 0.3) { !field.model.requests.isEmpty }, "a reminder was sent to the AI")
                #expect(field.host.opened.isEmpty)
            }
        }
    }

    /// The same while the pinyin is still composed (its first candidate is the sentence): the reminder is the first row
    /// already, as anywhere ("as it would be with the pinyin's first candidate").
    @Test func theTimeGivesAReminderFirstWhileItsPinyinIsComposed() async {
        await inEnglish {
            for trigger in Suite.triggers {
                let field = Field(trigger: trigger, english: false)
                field.typeAfterTheKey(Suite.timePinyin)
                expectReminderFirst(field, "pinyin composed")
            }
        }
    }

    /// The same with the sentence's characters as they are (what the example's button fills in), the input on Chinese or
    /// on English.
    @Test func theTimeGivesAReminderFirstAsItsCharacters() async {
        await inEnglish {
            for (trigger, english) in Suite.fields {
                let field = Field(trigger: trigger, english: english)
                field.typeAfterTheKey(Suite.time)
                expectReminderFirst(field, "characters, English \(english)")
                field.host.press(FakeHost.enter)
                #expect(field.host.settle(timeout: 5) { !field.reminders.withLock { $0 }.isEmpty }, "\(trigger): no reminder added")
                #expect(field.reminders.withLock { $0 } == [Suite.reminder(in: Suite.time)])
                #expect(field.model.requests.isEmpty)
            }
        }
    }

    // MARK: - An app: opened

    /// `safari` after the magic key: the first row is Safari, highlighted; ⏎ opens it. Nothing reaches the AI.
    @Test func theAppGivesSafariFirst() async {
        await inEnglish {
            for (trigger, english) in Suite.fields {
                let field = Field(trigger: trigger, english: english)
                field.typeAfterTheKey(Suite.app)
                #expect(field.rows.first?.text.contains("Safari") == true, "\(trigger), English \(english): \(field.texts)")
                #expect(field.firstIsHighlighted, "\(trigger), English \(english): \(field.texts)")
                #expect(field.model.requests.isEmpty && field.host.opened.isEmpty, "sent or opened before ⏎")
                field.host.press(FakeHost.enter)
                field.host.settle(timeout: 5) { !field.host.opened.isEmpty }
                #expect(field.host.opened == [Suite.safari.path], "\(trigger), English \(english): \(field.host.opened)")
                #expect(!field.host.settle(timeout: 0.3) { !field.model.requests.isEmpty }, "an app was sent to the AI")
                #expect(field.reminders.withLock { $0 }.isEmpty)
            }
        }
    }
}

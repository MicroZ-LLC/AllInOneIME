import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// One @ (0.7.0): the magic key, then whatever the user wants; the panel lists what can be done with it, the likeliest
/// first, each row saying what ⏎ does, its command's name dimmed. The order ("The order, exactly"): 1 the commands whose
/// name the letters start, 2 an arithmetic text's value, 3 a web address, 4 an app named so (a word's start, the pinyin or
/// initials of its Chinese name), 5 a reminder for a time in the text, 6 Ask AI for a question, 7 Translate for another
/// language than the main input language, 8 otherwise Improve; Ask AI last unless a question put it first. No AI rows in
/// an app with No AI, no Reply outside chat apps. With a selection and the magic key alone: Reply first in a chat app, else
/// Translate or Improve by the text, Ask AI about it last; text typed then is an instruction for it. What is picked rises,
/// in its app first. Pinyin right after the magic key is composed while names are searched. Nothing is sent, run or read
/// before ⏎; `@name text`, `user@host` and another magic key work as before.
///
/// Through a field's session (`FakeHost`), typed as the user types it: Chinese as pinyin (the stand-in engine knows the
/// sentences), English with the input on English. What ⏎ did is what the user sees happen: a path opened, text inserted,
/// a reminder added, a note saved, a program run, or what reached the AI (a stand-in for the on-device model keeps each
/// request), set against what the command typed by name sends (`@translate text`, `@question text` …): a row does "what
/// `@question` does". A row is told by the command name it shows (`@translate`, dimmed; a command list's row is the name
/// itself), a value by its "=" (`= 23`); its wording is otherwise free. While pinyin is composed, its candidates are left
/// out of the rows looked at. What is in memory (`SessionServices.instantResults`), the reminder's reading of a time, and
/// everything that reaches outside the field are stand-ins that keep what they were asked.
@Suite(.serialized)
struct OneAtAcceptanceTests {
    typealias Suite = OneAtAcceptanceTests

    // MARK: - Apps and texts

    static let editor = "com.example.editor"
    /// Chat apps (`AppClass.chat`): Slack, WeChat.
    static let slackApp = "com.tinyspeck.slackmacgap"
    static let wechatApp = "com.tencent.xinwechat"
    /// An app with No AI (`AppProfile.noAI`).
    static let bankApp = "com.example.bank"

    static let safari = SearchResult(name: "Safari", path: "/Applications/Safari.app")
    static let slack = SearchResult(name: "Slack", path: "/Applications/Slack.app")
    static let wechat = SearchResult(name: "WeChat", path: "/Applications/WeChat.app", chineseName: "微信")
    static let systemSettings = SearchResult(name: "System Settings", path: "/System/Applications/System Settings.app",
                                             chineseName: "系统设置")
    static let documents = SearchResult(name: "Documents", path: "/Users/me/Documents", isFolder: true, chineseName: "文稿")

    /// A custom `run` command.
    static let shout = CustomCommand(name: "shout", type: .run, summary: "Upper case", argv: ["/usr/bin/tr", "a-z", "A-Z"])

    /// The pinyin the stand-in engine composes, and its candidates (the first is what Space picks).
    static let pinyin: [String: [String]] = [
        "zhejiadiandecaihenhaochi": ["这家店的菜很好吃"],  // a statement in the user's language: Improve
        "hongshaorouzenmezuo": ["红烧肉怎么做"],  // a question (怎么)
        "nichifanlema": ["你吃饭了吗", "你吃饭了"],  // a question (吗)
        "mingtianxiawusandiankaihui": ["明天下午3点开会"],  // a time: a reminder
        "gaizhengshiyidian": ["改正式一点"],  // an instruction for a selection
        "nihao": ["你好", "拟好"],
        "wx": ["我想", "无线"],  // initials: Rime's first candidates aren't the app's name
        "xtsz": ["系统设置"],
    ]

    // MARK: - Stand-ins

    /// The on-device model (`Provider.apple`): keeps each request, answers it with one line.
    final class Model: AppleModelBackend, @unchecked Sendable {
        let availability = AppleModelAvailability.available
        let contextSize = 4096
        let supportedLanguages: Set<String> = ["de", "en", "es", "fr", "ja", "ko", "zh"]
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

    /// What is in memory (`SessionServices.instantResults`): an app index's apps and folders, found when each word typed
    /// starts a word of a name (its own or its Chinese one), or the letters start the pinyin or the initials of its
    /// Chinese name, as the Mac's index finds them. What it was asked is kept.
    final class Memory: @unchecked Sendable {
        static let index: [(result: SearchResult, spelled: [String])] = [
            (Suite.safari, []), (Suite.slack, []), (Suite.wechat, ["weixin", "wx"]),
            (Suite.systemSettings, ["xitongshezhi", "xtsz"]), (Suite.documents, ["wengao", "wg"]),
        ]
        private let asked = Locked<[String]>(initialState: [])

        var queries: [String] { asked.withLock { $0 } }

        func results(_ query: String, _ history: OpenHistory) -> [SearchResult] {
            asked.withLock { $0.append(query) }
            let keywords = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            guard !keywords.isEmpty else { return [] }
            return Self.index.filter { app in
                let words = ([app.result.name] + (app.result.chineseName.map { [$0] } ?? []))
                    .flatMap { $0.lowercased().split(separator: " ").map(String.init) }
                return keywords.allSatisfy { keyword in words.contains { $0.hasPrefix(keyword) } }
                    || keywords.count == 1 && app.spelled.contains { $0.hasPrefix(keywords[0]) }
            }.map(\.result)
        }
    }

    /// `@reminder`'s reading of a text (`SessionServices.parseReminder`): "明天下午3点" is tomorrow at 15:00 by the clock
    /// now (what the system's detector finds), the rest is the parser's own.
    static func reminder(in text: String) -> ReminderDraft {
        let (calendar, now) = (ReminderParser.localCalendar, Date())
        let parser = ReminderParser(calendar: calendar) { written in
            guard let range = written.range(of: "明天下午3点"),
                  let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  let date = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: tomorrow) else { return [] }
            return [ReminderParser.Match(range: range, date: date)]
        }
        return parser.parse(text, now: now)
    }

    /// Where `@note` saves: the texts saved, kept by the world.
    struct Notes: NoteDestination {
        let world: World
        var name: String { "Notes" }
        var leavesDevice: Bool { false }

        func save(_ draft: NoteDraft) async throws -> SavedNoteRef {
            world.notes.withLock { $0.append(draft.text) }
            return SavedNoteRef(id: nil, title: draft.text)
        }

        func check() async throws -> String { "" }
    }

    /// A program's output: `text`, at once.
    static func printing(_ text: String) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(ConversionUpdate(result: ConversionResult(versions: [CandidateLine(text)]), rawText: text,
                                                isFinal: true, elapsed: 0.1, firstTokenLatency: nil, fromCache: false))
            continuation.finish()
        }
    }

    /// The settings, what is kept between fields, and what reached outside them, for the fields made from it (`field`):
    /// Chinese the main input language, then English; English, then Chinese, the output languages; the AI on the device;
    /// an app with No AI; a custom command.
    final class World: @unchecked Sendable {
        var config: Config
        let memory = Memory()
        /// The command usage as kept (`SessionServices.loadCommandUsage`, `saveCommandUsage`).
        let usage = Locked(initialState: CommandUsage())
        /// What reached outside the fields but the AI: a page read, a script, an agent, a terminal, a search key, the
        /// contacts.
        let outside = Locked<[String]>(initialState: [])
        let reminders = Locked<[ReminderDraft]>(initialState: [])
        let notes = Locked<[String]>(initialState: [])
        /// The texts custom commands' programs were given.
        let programs = Locked<[String]>(initialState: [])
        private let models = Locked<[Model]>(initialState: [])

        init(trigger: String = "@") {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
            config.setOrder([OutputLanguage.english, .chinese])
            config.provider = .apple
            config.claudeInBackground = false
            config.commandTrigger = trigger
            config.appProfiles = [Suite.bankApp: AppProfile(noAI: true)]
            config.customCommands = [Suite.shout]
        }

        var trigger: String { config.commandTrigger }
        /// What every field's model was sent.
        var requests: [AppleModelRequest] { models.withLock { $0.flatMap(\.requests) } }

        /// A new field of `app` that has the focus, the input on English or Chinese, `selected` its text, all selected.
        func field(app: String = Suite.editor, english: Bool = false, selected: String? = nil) -> Field {
            let field = Field(self, app: app, english: english, selected: selected)
            models.withLock { $0.append(field.model) }
            return field
        }

        /// What reached the AI when `keys` were typed in a new field, then ⏎ (nil: nothing).
        func sent(app: String = Suite.editor, english: Bool = false, selected: String? = nil,
                  _ keys: (Field) -> Void) -> AppleModelRequest? {
            let field = self.field(app: app, english: english, selected: selected)
            keys(field)
            return field.returnSends()
        }
    }

    final class Field {
        let host: FakeHost
        let model: Model
        let world: World
        let selected: String?

        init(_ world: World, app: String, english: Bool, selected: String?) {
            let (model, engine, fixed) = (Model(), FakeEngine(), world.config)
            engine.dictionary.merge(Suite.pinyin) { $1 }
            var services = SessionServices(converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: model),
                                           loadSettings: { fixed })
            services.levelOne = { .engine(engine) }
            services.programInstalled = { _ in true }
            services.instantResults = { world.memory.results($0, $1) }
            // Spotlight, as the Mac's search lists a web address typed after @open: nothing else.
            services.searchFiles = { query, _ in SearchResult.web(query).map { [$0] } ?? [] }
            services.loadCommandUsage = { world.usage.withLock { $0 } }
            services.saveCommandUsage = { usage in world.usage.withLock { $0 = usage } }
            services.parseReminder = { Suite.reminder(in: $0) }
            services.addReminder = { draft in world.reminders.withLock { $0.append(draft) } }
            services.noteDestination = { _ in Notes(world: world) }
            services.runProgram = { _, input in
                world.programs.withLock { $0.append(input) }
                return Suite.printing(input.uppercased())
            }
            services.page = { _ in
                PageSource(wake: {}, release: {}, reader: {
                    { @Sendable () -> PageContext? in
                        world.outside.withLock { $0.append("page") }
                        return nil
                    }
                })
            }
            services.startScript = { _, _, _, _ in
                world.outside.withLock { $0.append("script") }
                return nil
            }
            services.startAgent = { _ in
                world.outside.withLock { $0.append("agent") }
                return "agent"
            }
            services.runInTerminal = { _, _ in world.outside.withLock { $0.append("terminal") } }
            services.loadSearchKey = {
                world.outside.withLock { $0.append("search key") }
                return nil
            }
            services.loadContacts = {
                world.outside.withLock { $0.append("contacts") }
                return nil
            }
            host = FakeHost(services: services)
            (self.model, self.world, self.selected) = (model, world, selected)
            host.app = app
            if let selected {
                host.document = selected
                host.selection = 0..<(selected as NSString).length
            }
            host.focus()
            if english { host.composer.setInputMode(.english) }
        }

        /// The rows for the text: the panel's, without the pinyin candidates shown with them while composing.
        var rows: [PanelModel.Row] {
            let candidates = Set(host.composer.engineState.isComposing ? host.composer.engineState.candidates.map(\.text) : [])
            return (host.panel?.rows ?? []).filter { !candidates.contains($0.text) }
        }
        /// What each row is (`Suite.kind`).
        var kinds: [String] { rows.map(Suite.kind) }
        var texts: [String] { rows.map { $0.comment.isEmpty ? $0.text : "\($0.text) | \($0.comment)" } }
        /// The first row is the one highlighted.
        var firstIsHighlighted: Bool {
            guard let panel = host.panel, let index = panel.highlighted, panel.rows.indices.contains(index) else { return false }
            return panel.rows[index] == rows.first
        }
        /// All the panel says.
        var panelText: String {
            guard let panel = host.panel else { return "" }
            return (panel.rows.flatMap { [$0.text, $0.comment] } + panel.header + [panel.input?.text ?? "", panel.footer]).joined(separator: " ")
        }

        func type(_ text: String) { host.type(text) }
        func press(_ key: KeyEvent) { host.press(key) }

        /// Pinyin, then Space: its first candidate.
        func write(pinyin letters: String) {
            host.type(letters)
            host.press(FakeHost.space)
        }

        /// The magic key, a command's full name and Tab: "@name ", as the command list picks it.
        func pick(_ name: String) {
            host.type(world.trigger + name)
            host.press(FakeHost.tab)
        }

        /// ⏎, then ⏎ again if what was found is listed to pick from (`@open` today): what was opened.
        func returnOpens() -> [String] {
            host.press(FakeHost.enter)
            host.settle(timeout: 5) { host.composer.phase == .choosing || !host.opened.isEmpty }
            if host.opened.isEmpty { host.press(FakeHost.enter) }
            return host.opened
        }

        /// ⏎, and what reached the AI for it (nil: nothing within five seconds).
        func returnSends() -> AppleModelRequest? {
            host.press(FakeHost.enter)
            host.settle(timeout: 5) { !model.requests.isEmpty }
            return model.requests.first
        }
    }

    /// The names a row can show: the built-in commands', `@edit`'s and the custom one's.
    static let names = Command.builtins.map(\.name) + [Command.edit.name, Suite.shout.name]

    /// What a row is: "=" for a value ("= 23"); else the command whose name it shows: the name itself (a command list's
    /// row), or the name after a magic key, in its text or else its comment ("@translate"); else its text.
    static func kind(of row: PanelModel.Row) -> String {
        if row.text.trimmingCharacters(in: .whitespaces).hasPrefix("=") { return "=" }
        for part in [row.text, row.comment] {
            let bare = part.trimmingCharacters(in: .whitespaces)
            if names.contains(bare) { return bare }
            let characters = Array(part)
            for (index, character) in characters.enumerated() where character == "@" || character == "~" {
                let name = String(characters[(index + 1)...].prefix { $0.isASCII && ($0.isLetter || $0.isNumber) })
                if names.contains(name) { return name }
            }
        }
        return row.text
    }

    static let aiKinds: Set<String> = ["improve", "translate", "question", "reply", "edit"]

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    // MARK: - 1. Command names first

    /// `@no` → note, `@tr` → translate (a power user's shortcut); ⏎ picks the command, as the list does today.
    @Test func lettersThatStartACommandsNameListThoseCommandsFirst() async {
        await inEnglish {
            let world = World()
            let note = world.field()
            note.type("@no")
            #expect(note.kinds.first == "note", "\(note.texts)")
            note.press(FakeHost.enter)
            #expect(note.host.composer.draftCommand == .note, "\(note.host.composer.draft)")
            #expect(world.notes.withLock { $0 }.isEmpty)
            let translate = world.field()
            translate.type("@tr")
            #expect(translate.kinds.first == "translate", "\(translate.texts)")
        }
    }

    // MARK: - 2. Arithmetic

    @Test func arithmeticShowsItsValueFirstAndReturnInsertsIt() async {
        await inEnglish {
            let field = World().field()
            field.type("@3*7+2")
            #expect(field.kinds.first == "=" && field.rows.first?.text.contains("23") == true, "\(field.texts)")
            #expect(field.firstIsHighlighted, "\(String(describing: field.host.panel?.highlighted))")
            field.press(FakeHost.enter)
            #expect(field.host.document == "23" && field.host.marked.isEmpty, "\(field.host.document)|\(field.host.marked)")
            #expect(field.model.requests.isEmpty)
        }
    }

    /// Numbers and `+ - * / × ÷ ( ) ^ .`: ⏎ inserts the value.
    @Test func theEvaluatorTakesNumbersAndItsOperators() async {
        await inEnglish {
            let world = World()
            let sums = [("(1+2)^3", "27"), ("6×7", "42"), ("84÷2", "42"), ("7/2", "3.5"), ("10-4*2", "2"), ("2^10", "1024"),
                        ("0.5+0.25", "0.75")]
            for (text, value) in sums {
                let field = world.field(english: true)
                field.type("@" + text)
                #expect(field.kinds.first == "=", "\(text): \(field.texts)")
                field.press(FakeHost.enter)
                #expect(field.host.document == value, "\(text): \(field.host.document)")
            }
        }
    }

    /// Never a script engine on the text: anything but numbers and the operators, or not all of it a sum, has no value
    /// row (the list is there: Ask AI last).
    @Test func theEvaluatorRefusesAnythingButNumbersAndTheOperators() async {
        await inEnglish {
            let world = World()
            for text in ["3*x", "sqrt(9)", "Math.max(2,3)", "1+1;2", "2+2)", "3*7+", "0x10+1"] {
                let field = world.field(english: true)
                field.type("@" + text)
                #expect(!field.kinds.contains("=") && field.kinds.last == "question", "\(text): \(field.texts)")
            }
            #expect(world.programs.withLock { $0 }.isEmpty && world.outside.withLock { $0 }.isEmpty)
        }
    }

    // MARK: - 3. A web address

    @Test func aWebAddressIsOpenedInTheBrowser() async {
        await inEnglish {
            let field = World().field(english: true)
            field.type("@github.com/apple/swift")
            #expect(field.rows.first.map { ($0.text + $0.comment).contains("github.com") } == true, "\(field.texts)")
            #expect(field.firstIsHighlighted)
            field.press(FakeHost.enter)
            let address = SearchResult.web("github.com/apple/swift")?.path
            #expect(address != nil && field.host.opened == [address ?? ""], "\(field.host.opened)")
        }
    }

    // MARK: - 4. An app

    @Test func anAppIsFoundByTheStartOfAWordOfItsName() async {
        await inEnglish {
            let field = World().field(english: true)
            field.type("@saf")
            #expect(field.rows.first?.text.contains("Safari") == true && field.firstIsHighlighted, "\(field.texts)")
            field.press(FakeHost.enter)
            #expect(field.host.opened == [Suite.safari.path], "\(field.host.opened)")
        }
    }

    /// With the input on Chinese, as the user types: the letters are composed as pinyin ("wx" → 我想 …) while they find
    /// the app whose Chinese name they spell; ⏎ opens it.
    @Test func anAppIsFoundByThePinyinInitialsOfItsChineseName() async {
        await inEnglish {
            let world = World()
            for (letters, app) in [("wx", Suite.wechat), ("xtsz", Suite.systemSettings)] {
                let field = world.field()
                field.type("@" + letters)
                let first = field.rows.first.map { $0.text + " " + $0.comment } ?? ""
                #expect(first.contains(app.name) || first.contains(app.chineseName ?? "-"), "@\(letters): \(field.texts)")
                field.press(FakeHost.enter)
                #expect(field.host.opened == [app.path], "@\(letters): \(field.host.opened)")
            }
        }
    }

    // MARK: - 5. A time

    /// "明天下午3点开会": "Reminder: tomorrow 3:00 PM 开会" ("tomorrow 15:00" with the 24-hour clock: the time as the system
    /// shows times, as `@reminder` shows it); ⏎ adds it, the rest of the text its title.
    @Test func aTimeInTheTextMakesAReminderFirst() async {
        await inEnglish {
            let world = World()
            let field = world.field()
            field.type("@")
            field.write(pinyin: "mingtianxiawusandiankaihui")
            let expected = Suite.reminder(in: "明天下午3点开会")
            // When, as `@reminder`'s confirmation says it (`UIText.when`): the system's clock, in the locale the test runs in.
            let when = UIText.when(expected)
            let row = field.rows.first.map { $0.text + " " + $0.comment } ?? ""
            #expect(field.kinds.first == "reminder" && row.contains(when) && row.contains("开会"), "\(when): \(field.texts)")
            #expect(field.firstIsHighlighted)
            field.press(FakeHost.enter)
            #expect(expected.title == "开会" && expected.hasTime)
            #expect(field.host.settle(timeout: 5) { !world.reminders.withLock { $0 }.isEmpty })
            #expect(world.reminders.withLock { $0 } == [expected], "\(world.reminders.withLock { $0 })")
            #expect(field.model.requests.isEmpty)
        }
    }

    // MARK: - 6. A question

    /// 怎么, 吗: Ask AI first (and only there); ⏎ asks what `@question` asks.
    @Test func aQuestionInChinesePutsAskAIFirst() async {
        await inEnglish {
            let world = World()
            for letters in ["hongshaorouzenmezuo", "nichifanlema"] {
                let field = world.field()
                field.type("@")
                field.write(pinyin: letters)
                #expect(field.kinds.first == "question" && field.kinds.filter { $0 == "question" }.count == 1, "\(letters): \(field.texts)")
                #expect(field.firstIsHighlighted)
                let sent = field.returnSends()
                let asked = world.sent { $0.pick("question"); $0.write(pinyin: letters) }
                #expect(asked != nil && sent == asked, "\(letters): \(String(describing: sent?.prompt)) / \(String(describing: asked?.prompt))")
            }
        }
    }

    /// "how …", a question mark: Ask AI first, though the text is in another language.
    @Test func aQuestionInEnglishPutsAskAIFirst() async {
        await inEnglish {
            let world = World()
            for text in ["how do I undo a commit", "pizza or pasta?"] {
                let field = world.field(english: true)
                field.type("@" + text)
                #expect(field.kinds.first == "question" && field.kinds.filter { $0 == "question" }.count == 1, "\(text): \(field.texts)")
                let sent = field.returnSends()
                let asked = world.sent(english: true) { $0.pick("question"); $0.type(text) }
                #expect(asked != nil && sent == asked, "\(text): \(String(describing: sent?.prompt)) / \(String(describing: asked?.prompt))")
            }
        }
    }

    // MARK: - 7. Another language

    /// English, the main input language Chinese: Translate first, named by the language `@translate` would translate it
    /// into (Chinese); ⏎ sends what `@translate` sends.
    @Test func anotherLanguagePutsTranslateFirst() async {
        await inEnglish {
            let world = World()
            let field = world.field(english: true)
            field.type("@thank you for the gift")
            #expect(field.kinds.first == "translate" && field.firstIsHighlighted, "\(field.texts)")
            #expect(field.rows.first.map { $0.text.contains("Chinese") || $0.text.contains("中文") } == true, "\(field.texts)")
            let sent = field.returnSends()
            let translated = world.sent(english: true) { $0.pick("translate"); $0.type("thank you for the gift") }
            #expect(translated != nil && sent == translated, "\(String(describing: sent?.prompt)) / \(String(describing: translated?.prompt))")
        }
    }

    // MARK: - 8. Otherwise Improve

    @Test func otherwiseImproveIsFirst() async {
        await inEnglish {
            let world = World()
            let field = world.field()
            field.type("@")
            field.write(pinyin: "zhejiadiandecaihenhaochi")
            #expect(field.kinds.first == "improve" && field.firstIsHighlighted, "\(field.texts)")
            let sent = field.returnSends()
            let improved = world.sent { $0.pick("improve"); $0.write(pinyin: "zhejiadiandecaihenhaochi") }
            #expect(improved != nil && sent == improved, "\(String(describing: sent?.prompt)) / \(String(describing: improved?.prompt))")
        }
    }

    // MARK: - Ask AI last

    /// Whatever the first row, Ask AI is the last, once: nothing is a dead end. ⏎ on it asks what `@question` asks.
    @Test func askAIIsTheLastRowWhenNoQuestionPutItFirst() async {
        await inEnglish {
            let world = World()
            let typed: [(String, Bool, (Field) -> Void)] = [
                ("a statement", false, { $0.type("@"); $0.write(pinyin: "zhejiadiandecaihenhaochi") }),
                ("English", true, { $0.type("@thank you for the gift") }),
                ("a reminder", false, { $0.type("@"); $0.write(pinyin: "mingtianxiawusandiankaihui") }),
                ("a sum", false, { $0.type("@3*7+2") }),
                ("an app", true, { $0.type("@saf") }),
            ]
            for (what, english, keys) in typed {
                let field = world.field(english: english)
                keys(field)
                #expect(field.kinds.last == "question" && field.kinds.filter { $0 == "question" }.count == 1, "\(what): \(field.texts)")
            }
            let field = world.field()
            field.type("@")
            field.write(pinyin: "zhejiadiandecaihenhaochi")
            for _ in 1..<max(field.rows.count, 1) { field.press(FakeHost.down) }
            #expect(field.host.panel?.highlighted == (field.host.panel?.rows.count ?? 0) - 1, "↓ to the last row")
            let sent = field.returnSends()
            let asked = world.sent { $0.pick("question"); $0.write(pinyin: "zhejiadiandecaihenhaochi") }
            #expect(asked != nil && sent == asked, "\(String(describing: sent?.prompt)) / \(String(describing: asked?.prompt))")
        }
    }

    // MARK: - Rows never offered

    /// No AI in the app: no AI row, for a text or a selection; the local answers stay.
    @Test func anAppWithNoAIOffersNoAIRows() async {
        await inEnglish {
            let world = World()
            let chinese = world.field(app: Suite.bankApp)
            chinese.type("@")
            chinese.write(pinyin: "hongshaorouzenmezuo")
            #expect(Suite.aiKinds.isDisjoint(with: chinese.kinds), "\(chinese.texts)")
            let english = world.field(app: Suite.bankApp, english: true)
            english.type("@thank you for the gift")
            #expect(Suite.aiKinds.isDisjoint(with: english.kinds), "\(english.texts)")
            let selected = world.field(app: Suite.bankApp, selected: "这个方案我觉得还可以")
            selected.type("@")
            #expect(Suite.aiKinds.isDisjoint(with: selected.kinds), "\(selected.texts)")
            let sum = world.field(app: Suite.bankApp)
            sum.type("@3*7+2")
            #expect(sum.kinds.first == "=", "\(sum.texts)")
            let app = world.field(app: Suite.bankApp, english: true)
            app.type("@saf")
            #expect(app.rows.first?.text.contains("Safari") == true, "\(app.texts)")
            #expect(world.requests.isEmpty)
        }
    }

    @Test func replyIsNeverOfferedOutsideChatApps() async {
        await inEnglish {
            let world = World()
            let selected = world.field(selected: "会议室在哪里？")
            selected.type("@")
            #expect(!selected.rows.isEmpty && !selected.kinds.contains("reply"), "\(selected.texts)")
            let typed = world.field()
            typed.type("@")
            typed.write(pinyin: "zhejiadiandecaihenhaochi")
            #expect(!typed.rows.isEmpty && !typed.kinds.contains("reply"), "\(typed.texts)")
        }
    }

    // MARK: - A selection, then the magic key alone

    @Test func aSelectionInAChatAppPutsReplyFirstAndAskAILast() async {
        await inEnglish {
            let world = World()
            let message = "会议室在哪里？"
            let field = world.field(app: Suite.slackApp, selected: message)
            field.type("@")
            #expect(field.kinds.first == "reply" && field.kinds.last == "question" && field.firstIsHighlighted, "\(field.texts)")
            let sent = field.returnSends()
            let replied = world.sent(app: Suite.slackApp, selected: message) { $0.pick("reply") }
            #expect(replied != nil && sent == replied, "\(String(describing: sent?.prompt)) / \(String(describing: replied?.prompt))")
            #expect(field.host.document == message, "nothing replaced yet")
        }
    }

    @Test func aSelectionInAnotherLanguageIsTranslatedFirst() async {
        await inEnglish {
            let world = World()
            let text = "The report looks good to me"
            let field = world.field(selected: text)
            field.type("@")
            #expect(field.kinds.first == "translate" && field.kinds.last == "question", "\(field.texts)")
            let sent = field.returnSends()
            let translated = world.sent(selected: text) { $0.pick("translate") }
            #expect(translated != nil && sent == translated, "\(String(describing: sent?.prompt)) / \(String(describing: translated?.prompt))")
        }
    }

    @Test func aSelectionInTheUsersLanguageIsImprovedFirst() async {
        await inEnglish {
            let world = World()
            let text = "这个方案我觉得还可以"
            let field = world.field(selected: text)
            field.type("@")
            #expect(field.kinds.first == "improve" && field.kinds.last == "question", "\(field.texts)")
            let sent = field.returnSends()
            let improved = world.sent(selected: text) { $0.pick("improve") }
            #expect(improved != nil && sent == improved, "\(String(describing: sent?.prompt)) / \(String(describing: improved?.prompt))")
        }
    }

    /// The last row, picked with ↓: what `@question` asks about the selection.
    @Test func askAIAboutTheSelectionIsTheLastRow() async {
        await inEnglish {
            let world = World()
            let text = "这个方案我觉得还可以"
            let field = world.field(selected: text)
            field.type("@")
            #expect(field.kinds.last == "question", "\(field.texts)")
            for _ in 1..<max(field.rows.count, 1) { field.press(FakeHost.down) }
            let sent = field.returnSends()
            let asked = world.sent(selected: text) { $0.pick("question") }
            #expect(asked != nil && sent == asked, "\(String(describing: sent?.prompt)) / \(String(describing: asked?.prompt))")
        }
    }

    /// "改正式一点" typed with a selection: first, the selection rewritten as it says (`Command.edit`: what a writing command
    /// with an instruction sends, with this instruction and the selected text).
    @Test func textTypedWithASelectionIsAnInstructionForIt() async {
        await inEnglish {
            let world = World()
            let text = "this sentance have a error"
            let field = world.field(selected: text)
            field.type("@")
            field.write(pinyin: "gaizhengshiyidian")
            #expect(field.firstIsHighlighted, "\(field.texts)")
            let sent = field.returnSends()
            let edited = world.sent(selected: text) { $0.pick("improve"); $0.write(pinyin: "gaizhengshiyidian") }
            #expect(edited != nil && sent?.instructions == edited?.instructions, "the edit request: \(String(describing: sent?.instructions.prefix(200)))")
            #expect(sent.map { $0.prompt.contains("改正式一点") && $0.prompt.contains(text) } == true, "\(String(describing: sent?.prompt))")
            #expect(field.host.document == text, "nothing replaced yet")
        }
    }

    // MARK: - It learns

    /// Improve picked in Slack rises there; Translate picked in the editor rises there; elsewhere, use overall (the
    /// writing actions after a question's Ask AI).
    @Test func thePickedWritingActionRisesInItsAppFirst() async {
        await inEnglish {
            let world = World()
            for _ in 0..<2 {
                let improved = world.field(app: Suite.slackApp)
                improved.type("@")
                improved.write(pinyin: "zhejiadiandecaihenhaochi")
                #expect(improved.kinds.first == "improve", "\(improved.texts)")
                let sent = improved.returnSends()
                #expect(sent != nil)
            }
            let translated = world.field(english: true)
            translated.type("@thank you for the gift")
            #expect(translated.kinds.first == "translate", "\(translated.texts)")
            let sent = translated.returnSends()
            #expect(sent != nil)
            func order(in app: String) -> [String] {
                let field = world.field(app: app)
                field.type("@")
                field.write(pinyin: "hongshaorouzenmezuo")
                #expect(field.kinds.first == "question", "\(app): \(field.texts)")
                return field.kinds.filter { $0 == "improve" || $0 == "translate" }
            }
            #expect(order(in: Suite.slackApp) == ["improve", "translate"], "Slack: Improve picked there")
            #expect(order(in: Suite.editor) == ["translate", "improve"], "the editor: Translate picked there")
            #expect(order(in: "com.example.notes") == ["improve", "translate"], "another app: by use overall")
        }
    }

    /// `@re`: @reminder used twice in the editor, @reply once in Slack. In Slack @reply comes first, in the editor
    /// @reminder.
    @Test func theCommandsTheLettersStartAreOrderedByUseInThisAppFirst() async {
        await inEnglish {
            let world = World()
            for added in 1...2 {
                let field = world.field()
                field.pick("reminder")
                field.write(pinyin: "mingtianxiawusandiankaihui")
                field.press(FakeHost.enter)
                field.host.settle(timeout: 1) { field.host.composer.pendingReminder != nil }
                field.press(FakeHost.enter)
                #expect(field.host.settle(timeout: 5) { world.reminders.withLock { $0 }.count == added })
            }
            let replied = world.field(app: Suite.slackApp, selected: "会议室在哪里？")
            replied.pick("reply")
            let sent = replied.returnSends()
            #expect(sent != nil)
            func order(in app: String) -> [String] {
                let field = world.field(app: app)
                field.type("@re")
                return field.kinds.filter { $0 == "reply" || $0 == "reminder" }
            }
            #expect(order(in: Suite.slackApp) == ["reply", "reminder"], "Slack")
            #expect(order(in: Suite.editor) == ["reminder", "reply"], "the editor")
        }
    }

    // MARK: - Pinyin right after the magic key

    /// While "nichifanlema" is composed: its candidates in the panel, and the rows for the first one (你吃饭了吗, a
    /// question: Ask AI), not for the letters; Space picks it, and the rows are the sentence's.
    @Test func pinyinIsComposedRightAfterTheMagicKeyAndTheRowsFollowTheFirstCandidate() async {
        await inEnglish {
            let field = World().field()
            field.type("@nichifanlema")
            #expect(field.host.composer.engineState.isComposing, "\(field.host.composer.draft)")
            #expect(field.panelText.contains("你吃饭了吗"), "the candidates are shown: \(field.panelText)")
            #expect(field.kinds.first == "question", "\(field.texts)")
            field.press(FakeHost.space)
            #expect(!field.host.composer.engineState.isComposing && field.host.composer.draft.contains("你吃饭了吗"),
                    "\(field.host.composer.draft)")
            #expect(field.kinds.first == "question" && field.firstIsHighlighted, "\(field.texts)")
        }
    }

    /// A digit picks a candidate while composing: "@nihao" 2 → 拟好.
    @Test func aDigitPicksACandidateWhileComposing() async {
        await inEnglish {
            let field = World().field()
            field.type("@nihao")
            field.type("2")
            #expect(!field.host.composer.engineState.isComposing && field.host.composer.draft.contains("拟好"),
                    "\(field.host.composer.draft)")
            #expect(field.kinds.first == "improve", "\(field.texts)")
        }
    }

    // MARK: - Never automatic

    /// Typed, the rows up, nothing pressed: nothing reached the AI, no page, program, script, agent, terminal or contact
    /// was asked, the clipboard wasn't read, nothing was opened, added, saved or inserted. ⏎ then sends one request.
    @Test func nothingIsSentRunOrReadBeforeReturn() async {
        await inEnglish {
            let world = World()
            var fields: [Field] = []
            func typed(english: Bool = false, app: String = Suite.editor, selected: String? = nil, _ keys: (Field) -> Void) {
                let field = world.field(app: app, english: english, selected: selected)
                keys(field)
                fields.append(field)
            }
            typed { $0.type("@"); $0.write(pinyin: "zhejiadiandecaihenhaochi") }
            typed { $0.type("@"); $0.write(pinyin: "hongshaorouzenmezuo") }
            typed { $0.type("@"); $0.write(pinyin: "mingtianxiawusandiankaihui") }
            typed { $0.type("@nichifanlema") }
            typed { $0.type("@3*7+2") }
            typed(english: true) { $0.type("@thank you for the gift") }
            typed(english: true) { $0.type("@github.com/apple/swift") }
            typed(english: true) { $0.type("@saf") }
            typed(app: Suite.slackApp, selected: "会议室在哪里？") { $0.type("@") }
            typed(selected: "this sentance have a error") { $0.type("@"); $0.write(pinyin: "gaizhengshiyidian") }
            let shout = world.field(english: true)  // a command by name, its text written: run only by ⏎
            shout.type("@shout hello")
            #expect(world.requests.isEmpty, "\(world.requests.map(\.prompt))")
            #expect(world.outside.withLock { $0 }.isEmpty, "\(world.outside.withLock { $0 })")
            #expect(world.programs.withLock { $0 }.isEmpty && world.reminders.withLock { $0 }.isEmpty
                    && world.notes.withLock { $0 }.isEmpty)
            for field in fields {
                #expect(!field.rows.isEmpty, "the rows are up: \(field.host.composer.draft)")
                #expect(field.host.opened.isEmpty && field.host.copied.isEmpty, "\(field.host.opened)")
                #expect(!field.host.outputs.contains { if case .readClipboard = $0 { true } else { false } })
                #expect(field.host.document == (field.selected ?? ""), "nothing inserted: \(field.host.document)")
            }
            #expect(shout.host.document.isEmpty, "\(shout.host.document)")
            let sent = fields[0].returnSends()
            #expect(sent != nil && world.requests.count == 1, "\(world.requests.count)")
        }
    }

    // MARK: - What doesn't change

    /// A command's name, a space, its text, ⏎, as today: @translate, @note, a custom command, @open with an address,
    /// @question with pinyin.
    @Test func aCommandsNameThenItsTextWorksAsToday() async {
        await inEnglish {
            let world = World()
            let translate = world.field(english: true)
            translate.type("@translate thank you")
            let sent = translate.returnSends()
            #expect(translate.host.composer.activeCommand == .translate && sent?.prompt.contains("thank you") == true,
                    "\(String(describing: translate.host.composer.activeCommand)): \(String(describing: sent?.prompt))")
            let note = world.field(english: true)
            note.type("@note buy milk")
            note.press(FakeHost.enter)
            #expect(note.host.settle(timeout: 5) { world.notes.withLock { $0 } == ["buy milk"] }, "\(world.notes.withLock { $0 })")
            let shout = world.field(english: true)
            shout.type("@shout hello")
            shout.press(FakeHost.enter)
            #expect(shout.host.settle(timeout: 5) { world.programs.withLock { $0 } == ["hello"] }, "\(world.programs.withLock { $0 })")
            let open = world.field(english: true)
            open.type("@open github.com")
            let opened = open.returnOpens()
            let address = SearchResult.web("github.com")?.path
            #expect(address != nil && opened == [address ?? ""], "\(opened)")
            let question = world.field()
            question.type("@question ")
            question.write(pinyin: "zhejiadiandecaihenhaochi")
            let asked = question.returnSends()
            #expect(question.host.composer.activeCommand == .question && asked?.prompt.contains("这家店的菜很好吃") == true,
                    "\(String(describing: question.host.composer.activeCommand)): \(String(describing: asked?.prompt))")
        }
    }

    @Test func anAtInsideAWordIsText() async {
        await inEnglish {
            let field = World().field(english: true)
            field.host.appTypesKeys = true
            field.type("user@host")
            #expect(field.host.document == "user@host" && !field.host.composer.isComposing && field.rows.isEmpty,
                    "\(field.host.document) \(field.texts)")
        }
    }

    /// `~` the magic key: the same list (a value, Translate, a command), and "@" is text.
    @Test func anotherMagicKeyWorksTheSameWay() async {
        await inEnglish {
            let world = World(trigger: "~")
            let sum = world.field()
            sum.type("~3*7+2")
            #expect(sum.kinds.first == "=", "\(sum.texts)")
            sum.press(FakeHost.enter)
            #expect(sum.host.document == "23", "\(sum.host.document)")
            let english = world.field(english: true)
            english.type("~thank you for the gift")
            #expect(english.kinds.first == "translate" && english.kinds.last == "question", "\(english.texts)")
            let note = world.field()
            note.type("~no")
            #expect(note.kinds.first == "note", "\(note.texts)")
            let at = world.field(english: true)
            at.type("@thank you")
            #expect(at.rows.isEmpty, "\(at.texts)")
        }
    }

    /// Esc: the rows go, the text stays as typed, nothing sent.
    @Test func escLeavesTheTextAsTyped() async {
        await inEnglish {
            let field = World().field(english: true)
            field.type("@hello world")
            #expect(!field.rows.isEmpty, "\(field.host.composer.draft)")
            field.press(FakeHost.escape)
            #expect(field.host.document + field.host.marked == "@hello world", "\(field.host.document)|\(field.host.marked)")
            #expect(field.rows.isEmpty && field.model.requests.isEmpty, "\(field.texts)")
        }
    }
}

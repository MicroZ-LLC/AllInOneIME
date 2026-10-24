import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Settings v2 (0.6.7, the owner's decisions of 2026-10-24): §3, what is learned, and the Core half of §6's tests for it.
// The acceptance tests, written from the spec before the implementation by an author other than the implementation's
// (whose changes don't edit them). They drive text fields' sessions as a shell does (`FakeHost`, through the Suggestions
// rig: `SuggestionsWorld`, `SuggestionsField`): a field of an app takes the focus, Shift is tapped, keys are typed. What
// they look at is what the user sees: the input a new field starts in (`Composer.input`), what the sessions said, the
// Learned list, the store's file and the settings (`Config`), never the implementation's insides.
//
// §6, Core, bullet by bullet, here: the learning rule (before-typing switches only, twice in a row, the streak, another
// input restarts it, Code counts, the global default never learned, the notice once, Forget), the effective starting
// input's order, the store is local (not in the config, not in the synced document), the Learned list (its items, Forget,
// Forget All, the learned state that exists already reached through it). Insert's choices, `appProfiles` left as they are
// and "Previous per-app settings": SettingsV2PerAppAcceptanceTests.swift.
//
// Where the spec is silent, these tests take it so:
// - A field is a new text field taking the focus: a session of its own (a `FakeHost`), as the Mac has one per text field;
//   the field before it is left (`.blur`) first.
// - A field's correction is the input Shift left it in before its first key that types: two taps there (中 → EN → FR)
//   correct it to the last (FR). After the switch something is always typed, so no test depends on a field left untyped.
// - A switch after typing neither teaches nor breaks a streak ("switching in the middle of typing never teaches
//   anything"; such a field is one "used without such a switch").
// - Forget, of an item or of all, forgets the streaks with it: two corrections in a row are needed again. The streaks are
//   kept with the learned inputs, in the store's file: a new launch goes on with them.
// - A learned input that is no longer among the inputs is passed over, as an app's own starting input is today.
// - The notice of what was learned comes up once, in the field where it was learned or as the next field of the app takes
//   the focus, as any notice does (on its own, elsewhere, or on the candidate panel's footer).
// - The Learned list's rows are checked for what they name (the app, the input, the count, the model), not their wording.

/* The API these tests use that doesn't exist yet (Core module, AllInOneIMECore; also in SettingsV2-API.md):

/// What is learned on this device (Settings v2 §3.2), in one local store: the starting input each app learned and the
/// streaks toward one, the apps where typos couldn't be fixed and the suggestion rows picked (both kept here now), and
/// what `AutocompleteStore` and `TemperatureSupport` learned, reached through it. App identifiers, inputs, counts and
/// times only, never text; never in the config file, never synced. Safe from any thread. (New file: Learned.swift.)
public final class LearnedStore: @unchecked Sendable {
    /// Where a shell keeps it: a file in the app's data folder (`CorePaths.dataDir`, Application Support).
    public static var defaultURL: URL { get }
    /// The store kept in `file` (nil: in memory only), reaching what `autocomplete` and `temperature` learned.
    public init(file: URL?, autocomplete: AutocompleteStore, temperature: TemperatureSupport)
    /// Writes to its file now what waits to be written.
    public func flush()

    /// Remembers `app` as one where typos couldn't be fixed (the Mac's `TypoMemory` until now): true if it wasn't yet.
    @discardableResult public func turnTyposOff(in app: String) -> Bool
    /// Whether `app` is one where typos couldn't be fixed (it gets none).
    public func typosOff(in app: String) -> Bool
    /// The suggestion rows picked, oldest first (what `SuggestionsServices.loadPicks` gives), and keeping one.
    public var picks: [SuggestionPick] { get }
    public func recordPick(_ pick: SuggestionPick)

    /// Privacy → Learned…: a row for each thing learned, its text in the interface language, apps named by `appName`.
    public func items(appName: (String) -> String?) -> [LearnedItem]
    /// Forget: `item` forgotten where it is kept (a learned starting input with its app's streak).
    public func forget(_ item: LearnedItem)
    /// Forget All: every item, and every streak.
    public func forgetAll()
}

/// One row of Privacy → Learned… (Core module, Learned.swift).
public struct LearnedItem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// "Slack: starts in English": `app` as the field told it.
        case startingInput(app: String, input: Input)
        /// "Autocomplete stopped in Mail" (`Autocomplete.Learning`): `app` as it keeps it.
        case autocompleteStopped(app: String)
        /// "Typos off in Terminal".
        case typosOff(app: String)
        /// "Suggestion rows you picked: 42".
        case pickedRows(count: Int)
        /// "Model x doesn't take temperature" (`TemperatureSupport.models`).
        case noTemperature(provider: Provider, model: String)
    }
    public var kind: Kind
    /// The row as the list shows it, in the interface language.
    public var text: String
}

extension SessionServices {
    /// What is learned on this device: a field starts in what its app learned, and its switches teach it (Settings v2
    /// §3.1). The shell gives one for every field; the default is these services' own, in memory. (A stored property.)
    public var learned: LearnedStore
}

Also used here: `Config.removePreviousAppSettings(for:)`, declared in SettingsV2PerAppAcceptanceTests.swift.
*/

// MARK: - The rig

/// The apps the tests type in, and their names as the shell tells them (`SessionServices.appName`).
enum SettingsV2Apps {
    static let slack = "com.tinyspeck.slackmacgap"
    static let mail = "com.apple.mail"
    static let notes = "com.apple.Notes"
    static let terminal = "com.apple.Terminal"
    static let xcode = "com.apple.dt.Xcode"

    static let names = [slack: "Slack", mail: "Mail", notes: "Notes", terminal: "Terminal", xcode: "Xcode"]

    /// An app's name, its id in any case.
    static func name(_ app: String) -> String? {
        names.first { $0.key.caseInsensitiveCompare(app) == .orderedSame }?.value
    }
}

/// The fields of one launch: the settings (`config`, the config file as the sessions read it), the one local store of what
/// is learned (in a file of its own, read again by `relaunch`), and what it reaches (autocomplete's store, the models
/// that refuse a temperature). Each field is a new text field taking the focus, the one before it left first.
final class SettingsV2World {
    let world: SuggestionsWorld
    let folder: URL
    let autocomplete = AutocompleteStore()
    let temperature = TemperatureSupport(file: nil)
    private(set) var learned: LearnedStore
    /// The fields made, in order, and the one that has the focus.
    private(set) var fields: [SuggestionsField] = []
    private var focused: SuggestionsField?

    /// `inputs`: the input languages in order, the first the default (the first chip).
    init(_ inputs: [Language] = [.chinese, .english]) {
        world = SuggestionsWorld(input: inputs[0])
        world.config.setOrder(inputs)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("settings-v2-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        learned = LearnedStore(file: folder.appendingPathComponent("learned.json"), autocomplete: autocomplete, temperature: temperature)
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    var config: Config {
        get { world.config }
        set { world.config = newValue }
    }

    /// The store's file.
    var file: URL { folder.appendingPathComponent("learned.json") }

    /// Code (decision 22) among the inputs, after the languages, in Python.
    func addCode() throws {
        world.addCode("python", packs: [try SuggestionsCodingPacksTests.shipped("python")])
    }

    /// A new text field of `app` taking the focus; the field before it left first.
    @discardableResult
    func field(_ app: String) -> SuggestionsField {
        focused?.host.send(.blur)
        let learned = self.learned, autocomplete = self.autocomplete
        let field = world.field(app: app) { services in
            services.learned = learned
            services.autocomplete = autocomplete
            services.appName = SettingsV2Apps.name
        }
        fields.append(field)
        focused = field
        return field
    }

    /// A new field of `app`, corrected: switched with `taps` taps of Shift as it takes the focus, then typed in.
    @discardableResult
    func corrected(_ app: String, taps: Int = 1) -> SuggestionsField {
        let field = field(app)
        field.correct(taps: taps)
        return field
    }

    /// A new field of `app`, typed in without a switch.
    @discardableResult
    func used(_ app: String) -> SuggestionsField {
        let field = field(app)
        field.type("ok ")
        return field
    }

    /// The input a new field of `app` starts in. (The field is one used without a switch: it breaks no streak.)
    func startingInput(_ app: String) -> Input { field(app).host.composer.input }

    /// A new launch: what waits is written, and the store is read again from its file.
    func relaunch() {
        focused?.host.send(.blur)
        focused?.host.send(.close)
        focused = nil
        learned.flush()
        learned = LearnedStore(file: file, autocomplete: autocomplete, temperature: temperature)
    }

    /// What every field said, in order, each time a notice came up (`SettingsV2World.said`).
    var said: [String] { fields.flatMap(Self.said) }

    /// What `field` said, each time a notice came up: on its own, elsewhere, or on the candidate panel's footer (a notice
    /// staying up through the panel's updates counts once).
    static func said(_ field: SuggestionsField) -> [String] {
        var said: [String] = [], up: String?
        for output in field.host.outputs {
            switch output {
            case let .notice(text), let .noticeElsewhere(text, _, _):
                if text != up { said.append(text) }
                up = text
            case let .panel(model):
                if let detail = model?.detail, detail != up { said.append(detail) }
                up = model?.detail
            default:
                break
            }
        }
        return said
    }

    /// What is learned, as the Learned list has it.
    func items() -> [LearnedItem] { learned.items(appName: SettingsV2Apps.name) }

    /// The starting input learned for `app`, as the Learned list has it.
    func learnedInput(_ app: String) -> Input? {
        for item in items() {
            if case let .startingInput(learnedApp, input) = item.kind, learnedApp.caseInsensitiveCompare(app) == .orderedSame { return input }
        }
        return nil
    }
}

extension SuggestionsField {
    /// Switched with `taps` taps of Shift before anything is typed, then something typed ("ok" and a space, which every
    /// input takes: letters in English, pinyin put in as typed, Code's word put in).
    func correct(taps: Int = 1) {
        for _ in 0..<taps { tapShift() }
        type("ok ")
    }
}

private let chinese = Input.language(.chinese)
private let english = Input.language(.english)
private let french = Input.language(.french)

// MARK: - The tests

@Suite(.serialized, SuggestionsOneAtATime())
struct SettingsV2LearningAcceptanceTests {
    typealias Apps = SettingsV2Apps

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    // MARK: §3.1 Twice in a row

    /// "In an app, when you switch the input with Shift before typing anything in a field, to the same input twice in a
    /// row, the app's fields start in that input from then on."
    @Test func twoFieldsInARowSwitchedBeforeTypingTeachTheApp() async throws {
        await inEnglish {
            let world = SettingsV2World()
            #expect(world.startingInput(Apps.slack) == chinese, "the default input (the first chip) before anything is learned")
            world.corrected(Apps.slack)
            world.corrected(Apps.slack)
            #expect(world.startingInput(Apps.slack) == english)
            #expect(world.startingInput(Apps.slack) == english, "from then on")
            #expect(world.startingInput(Apps.mail) == chinese, "another app as before")
        }
    }

    /// "Twice in a row": one field switched is not enough; nothing is learned and nothing said of it.
    @Test func oneFieldSwitchedIsNotEnough() async throws {
        await inEnglish {
            let world = SettingsV2World()
            world.corrected(Apps.slack)
            #expect(world.startingInput(Apps.slack) == chinese)
            #expect(world.learnedInput(Apps.slack) == nil, "\(world.items())")
            #expect(world.said.filter { $0.contains("Slack") }.isEmpty, "\(world.said)")
        }
    }

    /// "Before typing anything": "Only such switches count; switching in the middle of typing never teaches anything."
    /// Two fields switched after typing (in the middle of a word, and after one put in) teach nothing.
    @Test func switchesAfterTypingTeachNothing() async throws {
        await inEnglish {
            let world = SettingsV2World()
            let first = world.field(Apps.slack)
            first.type("ni")  // composing
            first.tapShift()
            first.type("ok ")
            let second = world.field(Apps.slack)
            second.type("nihao ")  // put in
            second.tapShift()
            second.type("ok ")
            #expect(world.startingInput(Apps.slack) == chinese)
            #expect(world.learnedInput(Apps.slack) == nil, "\(world.items())")
        }
    }

    /// "A field of the app used without such a switch in between doesn't break the streak": a field switched only after
    /// typing is one of them (its switch counts for nothing).
    @Test func aSwitchAfterTypingDoesntBreakTheStreak() async throws {
        await inEnglish {
            let world = SettingsV2World()
            world.corrected(Apps.slack)
            let between = world.field(Apps.slack)
            between.type("wo ")
            between.tapShift()
            between.type("ok ")
            world.corrected(Apps.slack)
            #expect(world.startingInput(Apps.slack) == english)
        }
    }

    /// "Before typing anything": "in a field since it took the focus, before any key that types or composes". A field
    /// with text in it already, and a key that types nothing (an arrow) before the switch, still count.
    @Test func beforeTypingCountsFromTheFocusNotFromAnEmptyField() async throws {
        await inEnglish {
            let world = SettingsV2World()
            for _ in 0..<2 {
                let field = world.field(Apps.slack)
                field.host.document = "Dear team, "
                field.press(SuggestionKeys.left)
                field.correct()
            }
            #expect(world.startingInput(Apps.slack) == english)
        }
    }

    /// "A field of the app used without such a switch in between doesn't break the streak."
    @Test func aFieldUsedWithoutASwitchDoesntBreakTheStreak() async throws {
        await inEnglish {
            let world = SettingsV2World()
            world.corrected(Apps.slack)
            world.used(Apps.slack)
            world.used(Apps.slack)
            world.corrected(Apps.slack)
            #expect(world.startingInput(Apps.slack) == english)
        }
    }

    /// "A switch to another input Y restarts it with Y": EN, FR, EN is no streak of two; one more EN makes it one.
    @Test func aSwitchToAnotherInputRestartsTheStreak() async throws {
        await inEnglish {
            let world = SettingsV2World([.chinese, .english, .french])
            world.corrected(Apps.slack, taps: 1)  // 中 → EN
            world.corrected(Apps.slack, taps: 2)  // 中 → EN → FR
            world.corrected(Apps.slack, taps: 1)
            let fourth = world.field(Apps.slack)
            #expect(fourth.host.composer.input == chinese, "EN, FR, EN: nothing learned")
            fourth.correct(taps: 1)  // EN twice in a row now
            #expect(world.startingInput(Apps.slack) == english)
        }
    }

    /// "Two fields (focus sessions) of that app in a row, each corrected to the same input X": a field is corrected to
    /// the input Shift left it in before typing, through as many taps as it took (中 → EN → FR is FR).
    @Test func aFieldIsCorrectedToTheInputItWasLeftIn() async throws {
        await inEnglish {
            let world = SettingsV2World([.chinese, .english, .french])
            world.corrected(Apps.mail, taps: 2)
            world.corrected(Apps.mail, taps: 2)
            #expect(world.startingInput(Apps.mail) == french)
        }
    }

    /// The streak is the app's ("two fields of that app in a row"): fields of another app in between neither count for it
    /// nor break it, and teach that app on their own.
    @Test func eachAppHasItsOwnStreak() async throws {
        await inEnglish {
            let world = SettingsV2World()
            world.corrected(Apps.slack)
            world.corrected(Apps.mail)
            world.corrected(Apps.mail)
            #expect(world.startingInput(Apps.mail) == english, "Mail: twice in a row")
            #expect(world.startingInput(Apps.slack) == chinese, "Slack: once, Mail's fields don't count for it")
            world.corrected(Apps.slack)
            #expect(world.startingInput(Apps.slack) == english, "Slack: twice, Mail's fields didn't break it")
        }
    }

    /// "Code counts as an input like the languages."
    @Test func codeIsLearnedLikeALanguage() async throws {
        try await inEnglish {
            let world = SettingsV2World([.english])
            try world.addCode()
            #expect(world.config.inputs == [english, .code])
            world.corrected(Apps.notes)
            world.corrected(Apps.notes)
            let field = world.field(Apps.notes)
            #expect(field.host.composer.input == .code && field.host.composer.coding)
            #expect(world.startingInput(Apps.slack) == english)
            #expect(world.learnedInput(Apps.notes) == .code, "\(world.items())")
        }
    }

    /// "The global default (the first chip) is never learned": however many apps learn English, the first input stays
    /// Chinese, the settings aren't changed, and an app that learned nothing starts in Chinese.
    @Test func theGlobalDefaultIsNeverLearned() async throws {
        await inEnglish {
            let world = SettingsV2World()
            let before = world.config
            for app in [Apps.slack, Apps.mail, Apps.notes, Apps.xcode] {
                world.corrected(app)
                world.corrected(app)
            }
            #expect(world.config == before)
            #expect(world.config.inputLanguages == [.chinese, .english] && world.config.defaultInput == .chinese)
            #expect(world.startingInput(Apps.terminal) == chinese)
            #expect(world.startingInput(Apps.slack) == english)
        }
    }

    /// "Said once, as a notice when it is learned ("Slack starts in English from now on")", in the interface language:
    /// once, naming the app and the input, as it is learned (by the time the next field of the app has the focus), and
    /// never again in the fields after.
    @Test(arguments: ["en", "zh"])
    func whatIsLearnedIsSaidOnce(_ language: String) async throws {
        await withInterfaceLanguage(language) {
            let world = SettingsV2World()
            world.config.uiLanguage = language
            world.corrected(Apps.slack)
            let saidEarly = SettingsV2World.said(world.fields[0]).filter { $0.contains("Slack") }
            #expect(saidEarly.isEmpty, "nothing learned yet")
            world.corrected(Apps.slack)
            let next = world.field(Apps.slack)
            let saidByThen = world.said.filter { $0.contains("Slack") }
            #expect(saidByThen.count == 1, "\(world.said)")
            if language == "en" {
                #expect(saidByThen.first?.contains("English") == true, "\(saidByThen)")
            } else {
                #expect(saidByThen.first?.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } == true,
                        "in Chinese: \(saidByThen)")
            }
            next.type("ok ")
            world.used(Apps.slack)
            world.used(Apps.slack)
            #expect(world.said.filter { $0.contains("Slack") }.count == 1, "\(world.said)")
        }
    }

    // MARK: §3.1 The effective starting input

    /// "The effective starting input of an app: the learned one if any, else its `startingInput` (§2), else the default
    /// input (the first chip)." The learned one over the app's own (which stays in the settings as it is); forgotten, the
    /// app's own again; that removed ("Previous per-app settings"), the default.
    @Test func theLearnedInputThenTheAppsOwnThenTheDefault() async throws {
        try await inEnglish {
            let world = SettingsV2World([.chinese, .english, .french])
            world.config.changeProfile(for: Apps.slack) { $0.inputLanguage = .english }
            let profiles = world.config.appProfiles
            #expect(world.startingInput(Apps.slack) == english, "the app's own")
            #expect(world.startingInput(Apps.mail) == chinese, "the default")
            world.corrected(Apps.slack)  // EN → FR
            world.corrected(Apps.slack)
            #expect(world.startingInput(Apps.slack) == french, "learned, over the app's own")
            #expect(world.config.appProfiles == profiles, "the app's own stays in the settings as it was")
            let item = try #require(world.items().first { $0.kind == .startingInput(app: Apps.slack, input: french) }, "\(world.items())")
            world.learned.forget(item)
            #expect(world.startingInput(Apps.slack) == english, "forgotten: the app's own again")
            world.config.removePreviousAppSettings(for: Apps.slack)
            #expect(world.startingInput(Apps.slack) == chinese, "that removed: the default")
        }
    }

    /// "`startingInput`: still honored as the app's starting input until the user removes it or the app learns another":
    /// learning the default input is learning another too.
    @Test func learningTheDefaultInputOverridesTheAppsOwn() async throws {
        await inEnglish {
            let world = SettingsV2World()
            world.config.changeProfile(for: Apps.mail) { $0.inputLanguage = .english }
            world.corrected(Apps.mail)  // EN → 中
            world.corrected(Apps.mail)
            #expect(world.startingInput(Apps.mail) == chinese)
            #expect(world.config.profile(for: Apps.mail)?.inputLanguage == .english, "the settings as they were")
        }
    }

    /// A learned input that can't be typed now (no longer among the inputs) is passed over, as an app's own starting input
    /// is: the app's own, else the default.
    @Test func aLearnedInputNoLongerAmongTheInputsIsPassedOver() async throws {
        await inEnglish {
            let world = SettingsV2World([.chinese, .english, .french])
            world.corrected(Apps.slack, taps: 2)
            world.corrected(Apps.slack, taps: 2)
            #expect(world.startingInput(Apps.slack) == french)
            world.config.setOrder([Language.chinese, .english])
            #expect(world.startingInput(Apps.slack) == chinese)
            world.config.changeProfile(for: Apps.slack) { $0.inputLanguage = .english }
            #expect(world.startingInput(Apps.slack) == english)
        }
    }

    // MARK: §3.1 Forget

    /// Forget (the Learned list's, as the input menu's "This App ▸ … · Forget" does): the app's fields start in the default
    /// again, and it learns again as it did the first time, twice in a row.
    @Test func aForgottenAppLearnsAgainTwiceInARow() async throws {
        try await inEnglish {
            let world = SettingsV2World()
            world.corrected(Apps.slack)
            world.corrected(Apps.slack)
            let item = try #require(world.items().first { $0.kind == .startingInput(app: Apps.slack, input: english) }, "\(world.items())")
            #expect(item.text.contains("Slack") && item.text.contains("English"), "\(item.text)")
            world.learned.forget(item)
            #expect(world.learnedInput(Apps.slack) == nil)
            #expect(world.startingInput(Apps.slack) == chinese)
            world.corrected(Apps.slack)
            #expect(world.startingInput(Apps.slack) == chinese, "once after Forget is not enough")
            world.corrected(Apps.slack)
            #expect(world.startingInput(Apps.slack) == english)
        }
    }

    /// Forget All forgets the streaks too: a correction before it and one after are not two in a row.
    @Test func forgetAllForgetsTheStreaks() async throws {
        await inEnglish {
            let world = SettingsV2World()
            world.corrected(Apps.slack)
            world.learned.forgetAll()
            world.corrected(Apps.slack)
            #expect(world.startingInput(Apps.slack) == chinese)
            world.corrected(Apps.slack)
            #expect(world.startingInput(Apps.slack) == english)
        }
    }

    // MARK: §3.2 Local only

    /// "All learned state lives in one local store (Application Support, not the config file, never synced)": learning
    /// changes neither the settings nor what syncs, and the store is kept in the app's data folder, apart from the config
    /// file and from iCloud Drive.
    @Test func whatIsLearnedIsInTheLocalStoreNotTheConfigNorTheSyncedDocument() async throws {
        await inEnglish {
            let world = SettingsV2World()
            world.config.changeProfile(for: Apps.mail) { $0.noAI = true }
            let config = world.config
            let synced = ICloudSync.values(of: config, in: Set(ICloudSync.Category.allCases))
            world.corrected(Apps.slack)
            world.corrected(Apps.slack)
            world.corrected(Apps.mail)
            world.corrected(Apps.mail)
            #expect(world.startingInput(Apps.slack) == english && world.startingInput(Apps.mail) == english)
            #expect(world.config == config)
            #expect(ICloudSync.values(of: world.config, in: Set(ICloudSync.Category.allCases)) == synced)
            let store = LearnedStore.defaultURL.standardizedFileURL.path
            #expect(store.hasPrefix(CorePaths.dataDir.standardizedFileURL.path + "/"), "\(store)")
            #expect(store != Config.defaultURL.standardizedFileURL.path)
            #expect(!store.hasPrefix(CorePaths.configDir.standardizedFileURL.path + "/"))
            #expect(!store.hasPrefix(ICloudSyncFolder.iCloudDriveRoot().standardizedFileURL.path + "/"))
        }
    }

    /// "No text is stored, only app identifiers, inputs, counts and times": what was typed in the fields is nowhere in the
    /// store's file, which holds what was learned (a new launch reads it back).
    @Test func theStoreKeepsNoTextTyped() async throws {
        try await inEnglish {
            let world = SettingsV2World()
            for _ in 0..<2 {
                let field = world.field(Apps.slack)
                field.tapShift()
                field.type("zebrafinch quokka ")
            }
            let other = world.used(Apps.mail)
            other.type("nihao ")
            world.relaunch()
            let data = try Data(contentsOf: world.file)
            let text = String(decoding: data, as: UTF8.self)
            #expect(!data.isEmpty)
            for typed in ["zebrafinch", "quokka", "nihao", "你好"] {
                #expect(!text.contains(typed), "\(typed) in \(text)")
            }
            #expect(world.startingInput(Apps.slack) == english, "the file has what was learned")
        }
    }

    /// The learned inputs "and their streaks" are the store's: a new launch (the store read again from its file) starts
    /// fields in what was learned, and goes on with a streak begun before it.
    @Test func whatIsLearnedAndTheStreaksOutlastALaunch() async throws {
        await inEnglish {
            let world = SettingsV2World()
            world.corrected(Apps.slack)
            world.corrected(Apps.slack)
            world.corrected(Apps.mail)
            world.relaunch()
            #expect(world.startingInput(Apps.slack) == english)
            #expect(world.startingInput(Apps.mail) == chinese)
            world.corrected(Apps.mail)
            #expect(world.startingInput(Apps.mail) == english, "the streak begun before the launch")
        }
    }

    // MARK: §3.2 Privacy → Learned…

    /// The learned state, put in the stores the way each is learned.
    func learnEverything(_ world: SettingsV2World) {
        world.corrected(Apps.slack)
        world.corrected(Apps.slack)
        world.autocomplete.learn { learning in
            for _ in 0..<Autocomplete.Learning.window { _ = learning.record(false, in: Apps.mail) }
        }
        world.learned.turnTyposOff(in: Apps.terminal)
        for n in 1...42 { world.learned.recordPick(SuggestionPick(plugin: "github", source: "issues", match: "#\(1000 + n)")) }
        world.temperature.remember(.anthropic, model: "claude-reasoning-test")
    }

    /// "Privacy → Learned… lists it: one row per item ("Slack: starts in English", "Autocomplete stopped in Xcode", "Typos
    /// off in Terminal", "Suggestion rows you picked: 42", "Model x doesn't take temperature")": the starting input learned
    /// and the learned state that exists already, each a row that names it.
    @Test func theLearnedListHasARowForEachThingLearned() async throws {
        await inEnglish {
            let world = SettingsV2World()
            #expect(world.items().isEmpty)
            learnEverything(world)
            #expect(world.autocomplete.stopped(in: Apps.mail) && world.learned.typosOff(in: Apps.terminal))
            let items = world.items()
            #expect(items.count == 5, "\(items)")
            func row(_ kind: (LearnedItem.Kind) -> Bool) -> String? { items.first { kind($0.kind) }?.text }
            let slack = row { $0 == .startingInput(app: Apps.slack, input: english) }
            #expect(slack?.contains("Slack") == true && slack?.contains("English") == true, "\(items)")
            let mail = row { if case let .autocompleteStopped(app) = $0 { app.caseInsensitiveCompare(Apps.mail) == .orderedSame } else { false } }
            #expect(mail?.contains("Mail") == true && mail?.contains("Autocomplete") == true, "\(items)")
            let terminal = row { if case let .typosOff(app) = $0 { app.caseInsensitiveCompare(Apps.terminal) == .orderedSame } else { false } }
            #expect(terminal?.contains("Terminal") == true, "\(items)")
            #expect(row { $0 == .pickedRows(count: 42) }?.contains("42") == true, "\(items)")
            #expect(row { $0 == .noTemperature(provider: .anthropic, model: "claude-reasoning-test") }?.contains("claude-reasoning-test") == true,
                    "\(items)")
        }
    }

    /// "Each with "Forget"": each row forgets its own where it is kept, and only it: the app starts in the default
    /// again, autocomplete runs in Mail again, Terminal gets typos again, the picks are gone, the model gets a
    /// temperature again.
    @Test func forgetForgetsEachWhereItIsKept() async throws {
        await inEnglish {
            let world = SettingsV2World()
            learnEverything(world)
            #expect(world.items().count == 5, "\(world.items())")
            var on = world.config
            on.autocomplete = true
            for item in world.items() {
                let others = world.items().filter { $0 != item }
                world.learned.forget(item)
                let left = world.items()
                #expect(left.count == others.count && others.allSatisfy(left.contains), "\(item) forgotten alone: \(left)")
                switch item.kind {
                case .startingInput:
                    #expect(world.startingInput(Apps.slack) == chinese)
                case .autocompleteStopped:
                    #expect(!world.autocomplete.stopped(in: Apps.mail))
                    #expect(Autocomplete.isOn(in: Apps.mail, config: on, stopped: world.autocomplete.stopped(in: Apps.mail)))
                case .typosOff:
                    #expect(!world.learned.typosOff(in: Apps.terminal))
                case .pickedRows:
                    #expect(world.learned.picks.isEmpty)
                case .noTemperature:
                    #expect(world.temperature.models.isEmpty)
                }
            }
            #expect(world.items().isEmpty)
        }
    }

    /// "And "Forget All"": every row and what it stands for, at once.
    @Test func forgetAllForgetsEverything() async throws {
        await inEnglish {
            let world = SettingsV2World()
            learnEverything(world)
            #expect(world.items().count == 5, "\(world.items())")
            world.learned.forgetAll()
            #expect(world.items().isEmpty)
            #expect(world.startingInput(Apps.slack) == chinese)
            #expect(!world.autocomplete.stopped(in: Apps.mail) && !world.learned.typosOff(in: Apps.terminal))
            #expect(world.learned.picks.isEmpty && world.temperature.models.isEmpty)
        }
    }

    /// What is forgotten stays forgotten: a new launch reads the store as Forget left it.
    @Test func whatIsForgottenStaysForgottenAfterALaunch() async throws {
        await inEnglish {
            let world = SettingsV2World()
            learnEverything(world)
            world.relaunch()
            #expect(world.items().count == 5, "kept across the launch: \(world.items())")
            world.learned.forgetAll()
            world.relaunch()
            #expect(world.items().isEmpty, "\(world.items())")
            #expect(world.startingInput(Apps.slack) == chinese)
        }
    }
}

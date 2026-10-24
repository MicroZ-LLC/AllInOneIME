import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Settings v2 (0.6.7, the owner's decisions of 2026-10-24): §2, what happens to the old per-app settings, and §4, the two
// that stay, with the Core half of §6's tests for them. The acceptance tests, written from the spec before the
// implementation by an author other than the implementation's (whose changes don't edit them).
//
// §6, Core, bullet by bullet, here: Insert's offered choices and the old values honored (the choice itself, the settings
// document every shell can draw, what a row puts in), `appProfiles` untouched by an upgrade and by Settings v2's code
// paths except the explicit Remove (the config file, and what syncs through iCloud), "Previous per-app settings" (its
// contents and Remove). The learning rule and the Learned list: SettingsV2LearningAcceptanceTests.swift, whose rig
// (`SettingsV2Apps`) and API these use too.
//
// Where the spec is silent, these tests take it so:
// - Core's settings document (`SettingsService`, the Windows shell's) offers Insert's choices as Settings does: "ID only"
//   and "source" (the source's own, set explicitly) aren't offered anew, here as on the Mac, everywhere and per app; one
//   a config has is shown as its value (`Choice.disabled`, under its name) and kept until changed; Restore Default sets
//   it to null (unset, the source's own).
// - A row of "Previous per-app settings" names the app and what is set ("Slack: starts in English, Translate as You Type
//   always on"); its order among the rows isn't checked. `translateAlways` counts as set when true, as `AppProfile`
//   counts it.
// - Remove leaves an app with nothing set without a profile (as a profile that sets nothing isn't saved).
// - "An upgrade" is the new version reading the old file: opening it in Settings (the document built, nothing changed,
//   saved) writes nothing, and a change of something else saved leaves the file's `appProfiles` as they were.

/* The API these tests use that doesn't exist yet (Core module, AllInOneIMECore; also in SettingsV2-API.md):

extension SuggestionsInsert {
    /// What Settings offers to choose, everywhere and per app, in this order (Settings v2 §4): With title, With title and
    /// link. Unset is the source's own; ID only and "source" set explicitly can't be chosen anew, one a config has is
    /// still honored.
    public static var offered: [SuggestionsInsert] { get }
}

extension AppProfile {
    /// The fields no Settings UI sets any more (Settings v2 §2), still honored while set, in the order a row lists them.
    public enum PreviousField: String, CaseIterable, Sendable {
        case startingInput, translateAlways, autocomplete, typeOut, rewriteStyles
    }
}

/// One row of General → "Previous per-app settings" (Core module, AppProfile.swift).
public struct PreviousAppSettings: Equatable, Sendable {
    /// The app's key in `Config.appProfiles` (what Remove takes).
    public var app: String
    /// What its profile sets of them, in `PreviousField`'s order.
    public var fields: [AppProfile.PreviousField]
    /// The row, in the interface language: "Slack: starts in English, Translate as You Type always on".
    public var text: String
}

extension Config {
    /// General → "Previous per-app settings": a row for each app whose profile sets any `PreviousField` (none: the
    /// section isn't shown), apps named by `appName` (else by their id).
    public func previousAppSettings(appName: (String) -> String?) -> [PreviousAppSettings]
    /// Remove: `app`'s `PreviousField`s cleared, its id in any case; its `noAI`, `suggestions` and `suggestionsInsert` as
    /// they are. A profile left setting nothing goes.
    public mutating func removePreviousAppSettings(for app: String)
}

Also used here: `LearnedStore` (its `init(file:autocomplete:temperature:)`, `items(appName:)`, `forgetAll()`), declared in
SettingsV2LearningAcceptanceTests.swift.
*/

@Suite(.serialized, MemorySecrets(), SuggestionsOneAtATime())
struct SettingsV2PerAppAcceptanceTests {
    typealias Apps = SettingsV2Apps
    typealias JSON = AIConfig.JSONValue

    static let bank = "com.example.bank"

    // MARK: Helpers

    /// A config file of its own with `text`, its store, and a settings service on it for `platform` (its plugins in the
    /// test's own folder: the user's are never read).
    func service(_ text: String, platform: SettingsPlatform = .mac) throws -> (service: SettingsService, store: SettingsStore, url: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("settings-v2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(text.utf8).write(to: url)
        let store = SettingsStore(configURL: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
        return (SettingsService(store: store, platform: platform, library: library), store, url)
    }

    /// The `appProfiles` of the config file at `url` as written there, app by app.
    func appProfiles(in url: URL) throws -> [String: JSON] {
        let file = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        guard let apps = file["appProfiles"] else { return [:] }
        guard case let .object(profiles)? = JSON(apps) else { Issue.record("appProfiles isn't an object"); return [:] }
        return profiles
    }

    /// What syncs through iCloud of `config`, every category.
    func synced(_ config: Config) -> [String: JSON] { ICloudSync.values(of: config, in: Set(ICloudSync.Category.allCases)) }

    /// The choices of `field` that can be picked (not one shown only as the value it has now), null (unset) aside.
    func offered(_ field: SettingsDocument.Field?) -> [JSON] {
        (field?.choices ?? []).filter { $0.disabled != true && $0.value != .null }.map(\.value)
    }

    /// Whether `result` was refused as a value the field doesn't take.
    func refused(_ result: Result<Void, SettingsProblem>) -> Bool {
        if case let .failure(problem) = result { return problem.code == .badValue }
        return false
    }

    static let theTwo: [JSON] = [.string("title"), .string("titleAndLink")]

    /// A 0.6.6 config file with every per-app setting there was, the old Insert choices among them.
    static let oldFile = """
        {
          "uiLanguage": "en",
          "inputLanguages": ["zh", "en"],
          "codingLanguage": "python",
          "suggestionsInsert": "id",
          "appProfiles": {
            "com.tinyspeck.slackmacgap": {"inputLanguage": "en", "translateAlways": true, "noAI": true, "suggestionsInsert": "titleAndLink"},
            "com.apple.mail": {"rewriteStyles": ["委婉", "正式"], "typeOut": false},
            "com.apple.dt.Xcode": {"inputLanguage": "code", "autocomplete": true, "suggestions": false},
            "com.example.bank": {"noAI": true},
            "com.apple.Terminal": {"suggestionsInsert": "source", "typeOut": true},
            "com.apple.Notes": {"suggestionsInsert": "id", "autocomplete": false, "rewriteStyles": []}
          }
        }
        """

    // MARK: §4 Insert: what is offered

    /// "Insert offers only **With title** and **With title and link**; "ID only" is no longer offered."
    @Test func onlyWithTitleAndWithTitleAndLinkAreOffered() {
        #expect(SuggestionsInsert.offered == [.title, .titleAndLink])
        UIText.$scopedLanguage.withValue("en") {
            #expect(SuggestionsInsert.offered.map(\.label) == ["With title", "With title and link"])
        }
    }

    /// "Insert: everywhere (With title / With title and link; unset = the source's own templates)", in the settings every
    /// shell draws (Core's settings document, the Windows shell's): the two can be picked, ID only and the source's own
    /// can't be chosen anew.
    @Test(arguments: SettingsPlatform.allCases)
    func everywhereTheTwoAreOffered(_ platform: SettingsPlatform) throws {
        let (service, _, url) = try service(#"{"uiLanguage": "en"}"#, platform: platform)
        let field = try #require(service.document().field("suggestionsInsert"))
        #expect(field.value == nil, "unset: the source's own")
        #expect(offered(field) == Self.theTwo, "\(field.choices ?? [])")
        #expect(refused(service.set("suggestionsInsert", to: .string("id"))))
        #expect(refused(service.set("suggestionsInsert", to: .string("source"))))
        #expect((try? service.set("suggestionsInsert", to: .string("titleAndLink")).get()) != nil)
        #expect(try Config.load(from: url).suggestionsInsert == .titleAndLink)
    }

    /// "A value "id" (ID only) already in a config is still honored and shown as "ID only" with "Restore Default"; it
    /// can't be chosen anew. "source" likewise is the unset state, shown as "Source's default" only where it is set
    /// explicitly, with "Restore Default"": either, set everywhere, is shown as the value, under its name, not to be
    /// picked; Restore Default unsets it, and then it can't be had back.
    @Test(arguments: SettingsPlatform.allCases, ["id", "source"])
    func anOldChoiceEverywhereIsShownUntilRestored(_ platform: SettingsPlatform, _ old: String) throws {
        let (service, _, url) = try service(#"{"uiLanguage": "en", "suggestionsInsert": "\#(old)"}"#, platform: platform)
        let field = try #require(service.document().field("suggestionsInsert"))
        #expect(field.value == .string(old))
        let shown = field.choices?.first { $0.value == .string(old) }
        #expect(shown?.label == (old == "id" ? "ID only" : "Source's default") && shown?.disabled == true, "\(field.choices ?? [])")
        #expect(offered(field) == Self.theTwo)
        #expect(try Config.load(from: url).suggestionsInsert == SuggestionsInsert(rawValue: old), "honored as it is")
        // Restore Default.
        #expect((try? service.set("suggestionsInsert", to: .null).get()) != nil)
        #expect(try Config.load(from: url).suggestionsInsert == nil)
        #expect(service.document().field("suggestionsInsert")?.value == nil)
        #expect(refused(service.set("suggestionsInsert", to: .string(old))))
    }

    /// "Then "In these apps:" a list of apps with their own choice (app, With title / With title and link, Remove)": an
    /// app's own offers the two too; an app's ID only, and its "source" set explicitly ("shown as "Source's default" only
    /// where it is set explicitly, with "Restore Default""), are shown as they are; Restore Default unsets the app's own
    /// alone; neither can be chosen anew.
    @Test(arguments: SettingsPlatform.allCases)
    func anAppsOwnOffersTheTwoAndShowsAnOldOne(_ platform: SettingsPlatform) throws {
        let text = """
            {"uiLanguage": "en", "appProfiles": {
              "com.tinyspeck.slackmacgap": {"suggestionsInsert": "id", "noAI": true},
              "com.apple.Terminal": {"suggestionsInsert": "source"},
              "com.apple.mail": {"suggestionsInsert": "title"}}}
            """
        let (service, _, url) = try service(text, platform: platform)
        let document = service.document()
        func field(_ app: String) -> SettingsDocument.Field? { document.field("apps.\(app).suggestionsInsert") }
        for app in [Apps.slack, Apps.terminal, Apps.mail] {
            #expect(offered(field(app)) == Self.theTwo, "\(app): \(field(app)?.choices ?? [])")
        }
        let slack = field(Apps.slack)?.choices?.first { $0.value == .string("id") }
        #expect(field(Apps.slack)?.value == .string("id") && slack?.label == "ID only" && slack?.disabled == true)
        let terminal = field(Apps.terminal)?.choices?.first { $0.value == .string("source") }
        #expect(field(Apps.terminal)?.value == .string("source") && terminal?.label == "Source's default" && terminal?.disabled == true)
        // Restore Default: the app's own unset, its No AI as it was.
        #expect((try? service.set("apps.\(Apps.slack).suggestionsInsert", to: .null).get()) != nil)
        #expect(try Config.load(from: url).profile(for: Apps.slack) == AppProfile(noAI: true))
        // One of the two, chosen; the old ones, not.
        #expect((try? service.set("apps.\(Apps.terminal).suggestionsInsert", to: .string("titleAndLink")).get()) != nil)
        #expect(try Config.load(from: url).profile(for: Apps.terminal)?.suggestionsInsert == .titleAndLink)
        #expect(refused(service.set("apps.\(Apps.mail).suggestionsInsert", to: .string("id"))))
        #expect(refused(service.set("apps.\(Apps.mail).suggestionsInsert", to: .string("source"))))
        #expect(try Config.load(from: url).profile(for: Apps.mail)?.suggestionsInsert == .title)
    }

    // MARK: §4 Insert: the old values honored

    /// "A value "id" (ID only) already in a config is still honored"; ""source" likewise is the unset state": read from
    /// a config file, ID only everywhere puts the ID alone in, an app's "source" its source's own templates (the GitHub
    /// plugin's for chat apps: title and link), an app's With title and link that.
    @Test func theOldValuesStillPutInWhatTheySay() async throws {
        try await withInterfaceLanguage("en") {
            let text = """
                {"suggestionsInsert": "id", "appProfiles": {
                  "com.tinyspeck.slackmacgap": {"suggestionsInsert": "source"},
                  "com.apple.mail": {"suggestionsInsert": "titleAndLink"}}}
                """
            let settings = try JSONDecoder().decode(Config.self, from: Data(text.utf8)).suggestionsSettings()
            #expect(settings.insert == .id && settings.insert(for: Apps.slack) == .source && settings.insert(for: Apps.mail) == .titleAndLink)
            let expected = [
                (SuggestionsApps.editor, SuggestionsInsertChoiceTests.github(.id, .ordinary)),
                (Apps.slack, SuggestionsInsertChoiceTests.github(.source, .chat)),
                (Apps.mail, SuggestionsInsertChoiceTests.github(.titleAndLink, .ordinary)),
            ]
            for (app, inserted) in expected {
                let world = try SuggestionsInsertChoiceTests.githubWorld()
                world.switches.insert = settings.insert
                world.switches.appInserts = settings.appInserts
                let field = world.field(app: app)
                field.type("#12")
                #expect(field.settle { field.issuesShown == ["#1234", "#1299"] }, "\(app): \(field.rows.map(\.text))")
                field.host.send(.pick(0))
                #expect(field.document == inserted, "\(app)")
            }
        }
    }

    // MARK: §2 `appProfiles` untouched

    /// "`Config.appProfiles` is kept as it is, in the config file, synced as today: nothing is deleted or rewritten by the
    /// upgrade (iCloud's newest-wins merge would carry a deletion to Macs still on an older version and erase their
    /// settings)." The old file opened in Settings (on either platform) is written not at all; every field of every app
    /// reads as written; what syncs of each app is what the file has (each Mac's own fields aside), the old Insert values
    /// among it; a change of something else saved leaves the file's `appProfiles` as they were.
    @Test(arguments: SettingsPlatform.allCases)
    func anUpgradeLeavesAppProfilesAsTheyAre(_ platform: SettingsPlatform) throws {
        let (service, store, url) = try service(Self.oldFile, platform: platform)
        let original = try Data(contentsOf: url)
        let written = try appProfiles(in: url)
        _ = service.document()
        store.save()
        store.refresh()
        #expect(try Data(contentsOf: url) == original, "nothing written")

        let config = try Config.load(from: url)
        let slack = config.profile(for: Apps.slack), xcode = config.profile(for: Apps.xcode), notes = config.profile(for: Apps.notes)
        #expect(slack?.inputLanguage == .english && slack?.translateAlways == true && slack?.noAI == true && slack?.suggestionsInsert == .titleAndLink)
        #expect(config.profile(for: Apps.mail)?.rewriteStyles == ["委婉", "正式"] && config.profile(for: Apps.mail)?.typeOut == false)
        #expect(xcode?.startingInput == .code && xcode?.autocomplete == true && xcode?.suggestions == false)
        #expect(config.profile(for: Self.bank)?.noAI == true)
        #expect(config.profile(for: Apps.terminal)?.suggestionsInsert == .source && config.profile(for: Apps.terminal)?.typeOut == true)
        #expect(notes?.suggestionsInsert == .id && notes?.autocomplete == false && notes?.rewriteStyles == [])
        #expect(config.suggestionsInsert == .id)

        let values = synced(config)
        #expect(values["suggestionsInsert"] == .string("id"))
        for (app, profile) in written {
            guard case var .object(fields) = profile else { Issue.record("\(app)"); continue }
            for own in ICloudSync.thisMacsOwnAppFields { fields[own] = nil }
            #expect(values[ICloudSync.appPrefix + app] == (fields.isEmpty ? nil : .object(fields)), "\(app)")
        }

        #expect((try? service.set("suggestions", to: .bool(false)).get()) != nil)
        #expect(try Config.load(from: url).suggestions == false)
        #expect(try appProfiles(in: url) == written)
    }

    /// "`appProfiles` untouched … by Settings v2 code paths except the explicit Remove": Insert chosen everywhere and
    /// restored, the "Previous per-app settings" read, the Learned list read and forgotten, all saved: the file's
    /// `appProfiles` and what syncs of them as they were.
    @Test func settingsV2LeavesAppProfilesAloneButForRemove() throws {
        let (service, store, url) = try service(Self.oldFile)
        let written = try appProfiles(in: url)
        let profiles = store.config.appProfiles
        let values = synced(store.config).filter { $0.key.hasPrefix(ICloudSync.appPrefix) }
        #expect((try? service.set("suggestionsInsert", to: .string("title")).get()) != nil)
        #expect((try? service.set("suggestionsInsert", to: .null).get()) != nil)
        _ = service.document()
        #expect(!store.config.previousAppSettings(appName: Apps.name).isEmpty)
        let learned = LearnedStore(file: nil, autocomplete: AutocompleteStore(), temperature: TemperatureSupport(file: nil))
        _ = learned.items(appName: Apps.name)
        learned.forgetAll()
        store.save()
        #expect(try appProfiles(in: url) == written)
        #expect(store.config.appProfiles == profiles)
        #expect(synced(store.config).filter { $0.key.hasPrefix(ICloudSync.appPrefix) } == values)
    }

    /// The explicit Remove, saved: only that app changes, in the file and in what syncs; its No AI and Insert stay. An
    /// app left with nothing is gone from both (the one deletion the user asked for).
    @Test func theExplicitRemoveChangesThatAppAlone() throws {
        let (_, store, url) = try service(Self.oldFile)
        let written = try appProfiles(in: url)
        let before = synced(store.config)
        store.config.removePreviousAppSettings(for: Apps.slack)
        store.save()
        var file = try appProfiles(in: url)
        #expect(file[Apps.slack] == .object(["noAI": .bool(true), "suggestionsInsert": .string("titleAndLink")]))
        for (app, profile) in written where app != Apps.slack { #expect(file[app] == profile, "\(app)") }
        var after = synced(store.config)
        for key in Set(before.keys).union(after.keys) where key != ICloudSync.appPrefix + Apps.slack {
            #expect(after[key] == before[key], "\(key)")
        }
        #expect(after[ICloudSync.appPrefix + Apps.slack] == .object(["noAI": .bool(true), "suggestionsInsert": .string("titleAndLink")]))

        store.config.removePreviousAppSettings(for: Apps.mail)
        store.save()
        file = try appProfiles(in: url)
        #expect(file[Apps.mail] == nil && store.config.profile(for: Apps.mail) == nil)
        for (app, profile) in written where app != Apps.slack && app != Apps.mail { #expect(file[app] == profile, "\(app)") }
        after = synced(store.config)
        #expect(after[ICloudSync.appPrefix + Apps.mail] == nil)
    }

    // MARK: §2 "Previous per-app settings"

    /// ""Previous per-app settings" (General, at the end; only when any app has one of the fields above set)": the two
    /// kept settings (No AI, Insert) alone make no row.
    @Test func thePreviousSettingsShowOnlyWhenAnAppHasOne() {
        var config = Config.default
        config.appProfiles = [Self.bank: AppProfile(noAI: true), Apps.mail: AppProfile(suggestionsInsert: .title)]
        #expect(config.previousAppSettings(appName: Apps.name).isEmpty)
        config.changeProfile(for: Apps.mail) { $0.typeOut = true }
        let rows = config.previousAppSettings(appName: Apps.name)
        #expect(rows.map(\.app) == [Apps.mail] && rows.first?.fields == [.typeOut], "\(rows)")
    }

    /// The fields "above": `startingInput`, `translateAlways`, `autocomplete`, `typeOut`, `rewriteStyles`, each with any
    /// value it can have; a row lists each that is set, and only those. `suggestions` is no longer one of them (the
    /// owner's decision of 2026-10-24: Off in "In these apps" sets it): an app that only turns them off makes no row.
    @Test func eachPreviousFieldMakesARow() {
        var code = AppProfile()
        code.startingInput = .code
        var all = AppProfile(inputLanguage: .english, rewriteStyles: ["口语"], typeOut: true, noAI: true, translateAlways: true,
                             autocomplete: false, suggestions: false, suggestionsInsert: .title)
        all.startingInput = .language(.french)
        let cases: [(String, AppProfile, [AppProfile.PreviousField])] = [
            ("com.example.language", AppProfile(inputLanguage: .english), [.startingInput]),
            ("com.example.code", code, [.startingInput]),
            ("com.example.translate", AppProfile(translateAlways: true), [.translateAlways]),
            ("com.example.always", AppProfile(autocomplete: true), [.autocomplete]),
            ("com.example.never", AppProfile(autocomplete: false), [.autocomplete]),
            ("com.example.typed", AppProfile(typeOut: true), [.typeOut]),
            ("com.example.nottyped", AppProfile(typeOut: false), [.typeOut]),
            ("com.example.nostyles", AppProfile(rewriteStyles: []), [.rewriteStyles]),
            ("com.example.styles", AppProfile(rewriteStyles: ["口语"]), [.rewriteStyles]),
            ("com.example.all", all, AppProfile.PreviousField.allCases),
        ]
        var config = Config.default
        for (app, profile, _) in cases { config.appProfiles[app] = profile }
        config.appProfiles[Self.bank] = AppProfile(noAI: true, suggestionsInsert: .titleAndLink)
        config.appProfiles["com.example.nosuggestions"] = AppProfile(suggestions: false)
        let rows = config.previousAppSettings(appName: { _ in nil })
        #expect(Set(rows.map(\.app)) == Set(cases.map(\.0)), "\(rows.map(\.app))")
        for (app, _, fields) in cases {
            #expect(rows.first { $0.app == app }?.fields == fields, "\(app)")
        }
    }

    /// "A row per app listing what is set ("Slack: starts in English, Translate as You Type always on")", in the
    /// interface language (English and Simplified Chinese).
    @Test func aRowSaysWhatIsSet() {
        var config = Config.default
        config.appProfiles = [Apps.slack: AppProfile(inputLanguage: .english, noAI: true, translateAlways: true)]
        UIText.$scopedLanguage.withValue("en") {
            let row = config.previousAppSettings(appName: Apps.name).first
            #expect(row?.fields == [.startingInput, .translateAlways])
            let text = row?.text ?? ""
            #expect(text.hasPrefix("Slack") && text.contains("English") && text.contains("Translate as You Type"), "\(text)")
        }
        UIText.$scopedLanguage.withValue("zh-Hans") {
            let text = config.previousAppSettings(appName: Apps.name).first?.text ?? ""
            #expect(text.contains("Slack") && text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, "\(text)")
        }
    }

    /// ""Remove", which clears those fields of that app (the two kept settings untouched)": its No AI and Insert stay
    /// (its suggestions off too, Off in "In these apps"), the other apps are as they were, its id in any case; an app left
    /// with nothing set has no profile any more, and the last Remove leaves no row.
    @Test func removeClearsThoseFieldsOfThatAppAlone() {
        var config = Config.default
        config.appProfiles = [
            Apps.slack: AppProfile(inputLanguage: .english, rewriteStyles: ["口语"], typeOut: true, noAI: true, translateAlways: true,
                                   autocomplete: true, suggestions: false, suggestionsInsert: .title),
            "com.apple.Mail": AppProfile(typeOut: false),
            Self.bank: AppProfile(noAI: true),
        ]
        config.removePreviousAppSettings(for: Apps.slack)
        #expect(config.profile(for: Apps.slack) == AppProfile(noAI: true, suggestions: false, suggestionsInsert: .title))
        #expect(config.profile(for: Apps.mail) == AppProfile(typeOut: false) && config.profile(for: Self.bank) == AppProfile(noAI: true))
        #expect(config.previousAppSettings(appName: Apps.name).map(\.app) == ["com.apple.Mail"])
        config.removePreviousAppSettings(for: Apps.mail)  // "com.apple.Mail" as written by hand
        #expect(config.profile(for: Apps.mail) == nil && config.appProfiles.count == 2)
        #expect(config.previousAppSettings(appName: Apps.name).isEmpty)
    }

    /// "An old "always autocomplete" is listed here, visible and removable, never turned into a hidden learned value (it
    /// sends text even with autocomplete off)": honored while it is set (autocomplete runs in the app with the switch
    /// off), its row says so, the Learned list has nothing of it; removed, autocomplete is off there as everywhere, with
    /// nothing learned in its place.
    @Test func anOldAlwaysAutocompleteIsListedNeverLearned() {
        var config = Config.default
        config.autocomplete = false
        config.appProfiles = [Apps.notes: AppProfile(autocomplete: true)]
        let autocomplete = AutocompleteStore()
        let learned = LearnedStore(file: nil, autocomplete: autocomplete, temperature: TemperatureSupport(file: nil))
        #expect(Autocomplete.isOn(in: Apps.notes, config: config, stopped: autocomplete.stopped(in: Apps.notes)))
        UIText.$scopedLanguage.withValue("en") {
            let row = config.previousAppSettings(appName: Apps.name).first
            #expect(row?.app == Apps.notes && row?.fields == [.autocomplete])
            #expect(row?.text.contains("Notes") == true && row?.text.contains("Autocomplete") == true, "\(row?.text ?? "")")
        }
        #expect(learned.items(appName: Apps.name).isEmpty)
        config.removePreviousAppSettings(for: Apps.notes)
        #expect(!Autocomplete.isOn(in: Apps.notes, config: config, stopped: autocomplete.stopped(in: Apps.notes)))
        #expect(learned.items(appName: Apps.name).isEmpty)
        #expect(config.previousAppSettings(appName: Apps.name).isEmpty)
    }

    /// "`startingInput`: still honored as the app's starting input until the user removes it or the app learns another
    /// (§3). `translateAlways`, `autocomplete`, `typeOut`, `rewriteStyles`: still honored while they are set; no UI sets
    /// them any more." And once removed, the app follows the settings for every app. Its suggestions off (Off in "In these
    /// apps", no longer one of them) stay.
    @Test func thePreviousFieldsAreHonoredUntilRemoved() {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.setOrder([OutputLanguage.english, .chinese])
        config.typeOut = false
        config.autocomplete = false
        config.rewriteStyles = ["润色"]
        var xcode = AppProfile(autocomplete: true, suggestions: false)
        xcode.startingInput = .code
        config.appProfiles = [Apps.slack: AppProfile(inputLanguage: .english, translateAlways: true),
                              Apps.mail: AppProfile(rewriteStyles: ["委婉"], typeOut: true), Apps.xcode: xcode]
        func translatesAlways(_ app: String) -> Bool {
            var mode = TranslateMode.State()
            if case .entered = mode.activated(app: app, last: nil, config: config) { return true }
            return false
        }
        #expect(config.startingInput(in: Apps.slack, among: [.chinese, .english], code: true) == .language(.english))
        #expect(config.startingInput(in: Apps.xcode, among: [.chinese, .english], code: true) == .code)
        #expect(translatesAlways(Apps.slack) && !translatesAlways(Apps.mail))
        #expect(config.applying(app: Apps.mail).typeOut && config.applying(app: Apps.mail).rewriteStyles == ["委婉"])
        #expect(Autocomplete.isOn(in: Apps.xcode, config: config, stopped: false), "always, even in a code editor with the switch off")
        #expect(config.suggestionsSettings().apps.first { $0.key.caseInsensitiveCompare(Apps.xcode) == .orderedSame }?.value == false)
        for app in [Apps.slack, Apps.mail, Apps.xcode] { config.removePreviousAppSettings(for: app) }
        #expect(config.startingInput(in: Apps.slack, among: [.chinese, .english], code: true) == .language(.chinese))
        #expect(config.startingInput(in: Apps.xcode, among: [.chinese, .english], code: true) == .language(.chinese))
        #expect(!translatesAlways(Apps.slack))
        #expect(!config.applying(app: Apps.mail).typeOut && config.applying(app: Apps.mail).rewriteStyles == ["润色"])
        #expect(!Autocomplete.isOn(in: Apps.xcode, config: config, stopped: false))
        #expect(config.suggestionsSettings().apps.first { $0.key.caseInsensitiveCompare(Apps.xcode) == .orderedSame }?.value == false)
    }
}

import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// 0.7.5 settings: lighter, one place for AI commands (owner-approved 2026-11-12/13). The acceptance tests, written from
// the spec before the implementation by an author other than the implementation's (whose changes don't edit them). They
// look at what Core can see: the core's settings document (`SettingsService(...).document()`, the one Windows' window
// draws, and the Mac's flavor of it, platform .mac, in "en" and "zh-Hans"), the config file (`Config` load and save), the
// commands users can type (`Command`), and what is learned per app (`LearnedStore`) as a text field's session uses it.
//
// The pages the spec rearranges (Settings → AI with its AI commands section, the recent questions in one place, a removed
// control's Restore Default row) are the Mac window's (SwiftUI): the core's document never had its pages (its sections
// are Windows' window's; 0.7.4's Restore Default rows are the Mac window's alone too). They are tested through the Mac
// window's search in Tests/AllInOneIMEMacTests/Acceptance/Settings075MacTests.swift. The iCloud section's Remove from
// iCloud…, the help texts' length and the docs aren't tested.
//
// Where the spec is silent, these tests take it so:
// - "The toggle leaves the window" (`useSelection`): the Mac's document has no field of it, whatever its value; the
//   document can't set it any more. (Windows' window keeps its switch: not looked at here.)
// - `useSelection` learned per app is kept as `turnTyposOff` is: in the local store of what is learned (`LearnedStore`),
//   by the API that mirrors typos': `turnSelectionOff(in:)` (true the first time), `selectionOff(in:)`; Privacy →
//   Learned… lists each app so with a row of its own that names it (`selectionOffApps`, `selectionOffText`), forgotten
//   with Forget (`forgetSelectionOff(in:)`) or Forget All. What makes the input method learn it (an app that doesn't take
//   the replacement of its selection) is the shell's to tell, as the Mac's `InputController` tells `turnTyposOff`: these
//   tests call the store as that shell does, as the turnTyposOff tests do (SettingsV2LearningAcceptanceTests).
// - The session decides whether "@" works on the selection where it does today (`InputSession.selectionMayBeRead`, Core):
//   an app that learned it off doesn't, whatever the config says; `useSelection: false` in the config still turns it off
//   in every app.
// - @read and @search are gone from what users can type: neither name is among the built-ins (`Command.builtins`) nor in
//   the catalog the input method offers (`Command.catalog`), and "@read …" / "@search …" parse as no command. A web
//   address still opens through @open (`SearchResult.web`, which read it with `WebReader.url` until now).
// - The Brave key 0.7.4 saved was kept under the keychain account "brave-search": it stays there untouched (no setting
//   reaches it any more, none removes it). No config key of @search's ever existed in `Config.CodingKeys`; a file with one
//   (written by hand: "webSearch", "braveSearch") is read as if it weren't there, and a change Settings saves leaves it in
//   the file as it was (no migration).

@Suite(.serialized, MemorySecrets())
struct Settings075Tests {
    typealias Field = SettingsDocument.Field

    // MARK: - The rig

    /// The interface languages the core writes its text in.
    static let languages = ["en", "zh-Hans"]

    /// A config in `language` (the interface's) on the AI `ai` says (Claude API by default), with `rest` (JSON members)
    /// added.
    static func config(_ language: String, _ rest: String = "", ai: String = #""provider": "anthropic""#) -> String {
        #"{"uiLanguage": "\#(language)", \#(ai), "inputLanguages": ["zh", "en"]"# + (rest.isEmpty ? "" : ", " + rest) + "}"
    }

    /// A settings service on a config file of its own (`text`), its plugins in its own folder; keys in memory
    /// (`MemorySecrets`).
    func service(_ text: String, platform: SettingsPlatform = .mac) throws -> (SettingsService, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("settings-075-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(text.utf8).write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
        return (SettingsService(store: SettingsStore(configURL: url), platform: platform, library: library), url)
    }

    /// The document `text`'s config makes on `platform`, in `language`.
    func document(_ text: String, language: String, platform: SettingsPlatform = .mac) async throws -> SettingsDocument {
        let (service, url) = try service(text, platform: platform)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return await withInterfaceLanguage(language) { service.document() }
    }

    /// Every field of the document, an item's own fields too.
    static func allFields(_ document: SettingsDocument) -> [Field] {
        func all(_ fields: [Field]) -> [Field] {
            fields.flatMap { field in [field] + (field.items ?? []).flatMap { all($0.fields ?? []) } }
        }
        return document.sections.flatMap { all($0.fields) }
    }

    /// The config file's keys, as written.
    static func fileKeys(_ url: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    // MARK: - 4. "Use the selection": the toggle leaves the window

    /// With the value the default (on, or no key at all), nothing of `useSelection` is in the Mac's document.
    @Test(arguments: languages)
    func theUseSelectionToggleLeavesTheDocument(language: String) async throws {
        for rest in ["", #""useSelection": true"#] {
            let document = try await document(Self.config(language, rest), language: language)
            let left = Self.allFields(document).filter { $0.id.localizedCaseInsensitiveContains("useSelection") }.map(\.id)
            #expect(left.isEmpty, "\(rest): \(left)")
        }
    }

    /// Off in the config (set by hand, by an earlier version): no toggle in the Mac's document either, and the document
    /// can't set it any more; the file keeps it off. (Its Restore Default row is the Mac window's: Settings075MacTests.)
    @Test(arguments: languages)
    func useSelectionOffIsNoToggleEither(language: String) async throws {
        let (service, url) = try service(Self.config(language, #""useSelection": false"#))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = await withInterfaceLanguage(language) { service.document() }
        #expect(!Self.allFields(document).contains { $0.id == "useSelection" && $0.kind == .toggle }, "no toggle")
        let set = await withInterfaceLanguage(language) { service.set("useSelection", to: .bool(true)) }
        #expect((try? set.get()) == nil, "no control sets it any more")
        #expect(try Config.load(from: url).useSelection == false)
    }

    // MARK: - Config keys keep being read and written as now

    /// Every moved or removed control's key, not the default, in a file: read as written, written back by `write`
    /// (the whole config) and kept by a change Settings saves (`Config.change`) as it was.
    @Test func theMovedAndRemovedKeysRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("settings-075-keys-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.json")
        try Data(#"""
            {"outputLanguages": ["ja", "en"], "rewriteStyles": ["口语", "黑话"], "improveTranslates": true,
             "jargonFile": "~/team-jargon.txt", "rememberQuestions": false, "questionContinueIn": ["chatgpt", "copy"],
             "useSelection": false}
            """#.utf8).write(to: url)
        func check(_ config: Config, _ when: String) {
            #expect(config.outputLanguages.map(\.code) == ["ja", "en"], "\(when)")
            #expect(config.rewriteStyles == ["口语", "黑话"], "\(when)")
            #expect(config.improveTranslates, "\(when)")
            #expect(config.jargonFile == "~/team-jargon.txt", "\(when)")
            #expect(!config.rememberQuestions, "\(when)")
            #expect(config.questionContinueIn == [.chatgpt, .copy], "\(when)")
            #expect(!config.useSelection, "\(when)")
        }
        let loaded = try Config.load(from: url)
        check(loaded, "read")
        let written = folder.appendingPathComponent("written.json")
        try loaded.write(to: written)
        check(try Config.load(from: written), "written whole")
        try Config.change(at: url) { $0.maxTokens = 2500 }
        check(try Config.load(from: url), "after another change")
        let keys = try Self.fileKeys(url)
        for key in ["outputLanguages", "rewriteStyles", "improveTranslates", "jargonFile", "rememberQuestions", "questionContinueIn",
                    "useSelection"] {
            #expect(keys[key] != nil, "\(key) is still the file's")
        }
        #expect(Config.allKeys.contains("useSelection") && Config.allKeys.contains("rememberQuestions"))
    }

    /// The moved fields, set in the document, write the keys they always wrote.
    @Test func theMovedFieldsWriteTheSameKeys() async throws {
        let (service, url) = try service(Self.config("en"))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let changes: [(String, AIConfig.JSONValue)] = [
            ("outputLanguages", .array([.string("ja"), .string("en")])),
            ("rewriteStyles", .array([.string("口语"), .string("黑话")])),
            ("improveTranslates", .bool(true)),
            ("jargonFile", .string("~/team-jargon.txt")),
            ("rememberQuestions", .bool(false)),
        ]
        for (id, value) in changes {
            let set = await withInterfaceLanguage("en") { service.set(id, to: value) }
            #expect((try? set.get()) != nil, "\(id): \(set)")
        }
        let config = try Config.load(from: url)
        #expect(config.outputLanguages.map(\.code) == ["ja", "en"])
        #expect(config.rewriteStyles == ["口语", "黑话"])
        #expect(config.improveTranslates && config.jargonFile == "~/team-jargon.txt" && !config.rememberQuestions)
        let keys = try Self.fileKeys(url)
        #expect(keys["outputLanguages"] as? [String] == ["ja", "en"])
        #expect(keys["rewriteStyles"] as? [String] == ["口语", "黑话"])
        #expect(keys["improveTranslates"] as? Bool == true)
        #expect(keys["jargonFile"] as? String == "~/team-jargon.txt")
        #expect(keys["rememberQuestions"] as? Bool == false)
    }

    // MARK: - 6, 7. @read and @search are deleted

    /// Neither is a command users can type: not among the built-ins, not in the catalog the input method offers, and
    /// "@read …", "@search …" are no command; the list for "rea" and "sea" offers neither.
    @Test func readAndSearchAreNoLongerCommands() {
        let builtins = Command.builtins.map(\.name)
        let offered = Command.catalog([]).map(\.name)
        for name in ["read", "search"] {
            #expect(!builtins.contains(name), "\(name) among the built-ins: \(builtins)")
            #expect(!offered.contains(name), "\(name) offered: \(offered)")
        }
        #expect(Command.parse("@read https://example.com/page", in: Command.catalog([])) == nil)
        #expect(Command.parse("@search swift testing", in: Command.catalog([])) == nil)
        #expect(Command.parse("@read https://example.com/page") == nil)
        #expect(Command.parse("@search swift testing") == nil)
        #expect(!Command.matching("rea").map(\.name).contains("read"))
        #expect(!Command.matching("sea").map(\.name).contains("search"))
        // The others are as they were.
        for name in ["improve", "translate", "question", "agent", "open", "reply", "note", "reminder"] {
            #expect(offered.contains(name), "\(name): \(offered)")
        }
    }

    /// "A typed web address still opens through @open": @open is offered, and a web address typed after it is one to open.
    @Test func aWebAddressStillOpensThroughOpen() {
        #expect(Command.catalog([]).contains { $0.name == "open" })
        #expect(SearchResult.web("https://example.com/a/b")?.webURL?.host == "example.com")
        #expect(SearchResult.web("github.com/apple/swift")?.path == "https://github.com/apple/swift")
        #expect(SearchResult.web("www.apple.com")?.path == "https://www.apple.com")
        #expect(SearchResult.web("HTTPS://Example.com")?.webURL != nil)
        #expect(SearchResult.web("http://localhost:8080/a")?.webURL?.port == 8080)
        for notAnAddress in ["report.pdf", "Safari.app", "hello world", "/Users/me", "~/notes"] {
            #expect(SearchResult.web(notAnAddress) == nil, "\(notAnAddress)")
        }
    }

    /// The Brave key's settings are gone from every document (Mac's, Windows'; both languages), even with a key saved for
    /// @search: no section, no field, and a change or an action on its old field is refused. The key stays in the keychain
    /// as it was (no migration).
    @Test func theSearchSettingsAreGoneAndItsKeyStays() async throws {
        let account = "brave-search"  // where 0.7.4 saved @search's key
        try APIKeys.save("BSAsettings075test0000", account: account, label: "AllInOneIME: Brave Search")
        #expect(APIKeys.hasKeychainKey(account: account))
        for platform in [SettingsPlatform.mac, .windows] {
            for language in Self.languages {
                let (service, url) = try service(Self.config(language), platform: platform)
                defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                let document = await withInterfaceLanguage(language) { service.document() }
                #expect(!document.sections.contains { $0.id == "search" }, "\(platform) \(language): \(document.sections.map(\.id))")
                let left = Self.allFields(document).map(\.id).filter { $0.hasPrefix("search.") || $0 == "search" }
                #expect(left.isEmpty, "\(platform) \(language): \(left)")
                for section in document.sections {
                    #expect(!section.title.contains("@search") && !section.title.contains("Web Search") && !section.title.contains("网页搜索"),
                            "\(section.title)")
                }
                let tested = await service.perform(SettingsAction(field: "search.key", name: SettingsAction.test))
                #expect((try? tested.get()) == nil)
                let removed = await service.perform(SettingsAction(field: "search.key", name: SettingsAction.removeKey))
                #expect((try? removed.get()) == nil)
            }
        }
        #expect(APIKeys.hasKeychainKey(account: account), "the key saved for @search is left in the keychain")
    }

    /// A config key for @search in the file (written by hand, or by a build that had one) is ignored when read: the file
    /// reads as without it, nothing offers @search or its settings, and a change Settings saves leaves the key in the file
    /// as it was.
    @Test func aSavedWebSearchConfigKeyIsIgnored() async throws {
        let rest = #""maxTokens": 2500, "webSearch": {"backend": "brave", "enabled": true, "country": "us"}, "braveSearch": true"#
        let (service, url) = try service(Self.config("en", rest))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let config = try Config.load(from: url)
        #expect(config.maxTokens == 2500, "the rest of the file is read")
        #expect(!Config.allKeys.contains("webSearch") && !Config.allKeys.contains("braveSearch"))
        #expect(!Command.catalog(config.customCommands).contains { $0.name == "search" })
        let document = await withInterfaceLanguage("en") { service.document() }
        #expect(document.loadError == nil, "\(document.loadError ?? "")")
        #expect(!Self.allFields(document).contains { $0.id.hasPrefix("search.") })
        let set = await withInterfaceLanguage("en") { service.set("timeoutSeconds", to: .number(30)) }
        #expect((try? set.get()) != nil, "\(set)")
        #expect(try Config.load(from: url).timeoutSeconds == 30)
        let keys = try Self.fileKeys(url)
        #expect((keys["webSearch"] as? [String: Any])?["backend"] as? String == "brave", "left in the file untouched")
        #expect(keys["braveSearch"] as? Bool == true)
    }

    // MARK: - 4. "Use the selection" learned per app, as turnTyposOff is

    /// The apps the tests type in, and their names as a shell tells them.
    enum Apps {
        static let mail = "com.apple.mail"
        static let slack = "com.tinyspeck.slackmacgap"
        static let names = [mail: "Mail", slack: "Slack"]
        static func name(_ app: String) -> String? { names.first { $0.key.caseInsensitiveCompare(app) == .orderedSame }?.value }
    }

    /// A store of what is learned, in a file of its own in `folder`.
    static func learnedStore(in folder: URL) -> LearnedStore {
        LearnedStore(file: folder.appendingPathComponent("learned.json"), autocomplete: AutocompleteStore(),
                     temperature: TemperatureSupport(file: nil))
    }

    static func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("settings-075-learned-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The selection learned off is the app's own (its id in any case), once: true the first time, as `turnTyposOff`.
    @Test func theSelectionIsLearnedOffPerApp() throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let learned = Self.learnedStore(in: folder)
        #expect(!learned.selectionOff(in: Apps.mail) && !learned.selectionOff(in: Apps.slack))
        #expect(learned.turnSelectionOff(in: Apps.mail))
        #expect(!learned.turnSelectionOff(in: Apps.mail), "already learned")
        #expect(!learned.turnSelectionOff(in: ""), "never an app without an id")
        #expect(learned.selectionOff(in: Apps.mail) && learned.selectionOff(in: Apps.mail.uppercased()))
        #expect(!learned.selectionOff(in: Apps.slack), "another app as before")
        #expect(!learned.typosOff(in: Apps.mail), "nothing else learned with it")
    }

    /// Privacy → Learned… has a row for it naming the app, beside typos' (`selectionOffApps`, `selectionOffText`, in both
    /// languages); Forget forgets it alone (its id in any case), Forget All too.
    @Test func theLearnedListHasARowForTheSelectionOff() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let learned = Self.learnedStore(in: folder)
        func row(_ app: String) -> String { LearnedStore.selectionOffText(app) { Apps.name($0) ?? $0 } }
        await withInterfaceLanguage("en") {
            learned.turnSelectionOff(in: Apps.mail)
            learned.turnTyposOff(in: Apps.slack)
            #expect(learned.selectionOffApps == [Apps.mail], "\(learned.selectionOffApps)")
            // Its row names the app, and isn't typos' (which names Slack, and is listed as before).
            let typos = learned.items(appName: Apps.name)
            #expect(typos.map(\.kind) == [.typosOff(app: Apps.slack)], "\(typos)")
            #expect(row(Apps.mail).contains("Mail") && !typos.map(\.text).contains(row(Apps.mail)), "\(row(Apps.mail))")
            learned.forgetSelectionOff(in: Apps.mail.uppercased())
            #expect(!learned.selectionOff(in: Apps.mail) && learned.selectionOffApps.isEmpty)
            #expect(learned.typosOff(in: Apps.slack), "forgotten alone")
            learned.turnSelectionOff(in: Apps.mail)
            learned.forgetAll()
            #expect(!learned.selectionOff(in: Apps.mail) && learned.selectionOffApps.isEmpty && learned.items(appName: Apps.name).isEmpty)
        }
        await withInterfaceLanguage("zh-Hans") {
            #expect(row(Apps.mail).contains("Mail") && row(Apps.mail) != row(Apps.slack), "\(row(Apps.mail))")
        }
    }

    /// It is kept in the store's file, never in the config: a new launch reads it again.
    @Test func theSelectionOffOutlastsALaunch() throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let learned = Self.learnedStore(in: folder)
        learned.turnSelectionOff(in: Apps.mail)
        #expect(learned.flush())
        let text = try String(contentsOf: folder.appendingPathComponent("learned.json"), encoding: .utf8)
        #expect(text.lowercased().contains(Apps.mail), "\(text)")
        let again = Self.learnedStore(in: folder)
        #expect(again.selectionOff(in: Apps.mail) && !again.selectionOff(in: Apps.slack))
    }

    /// The settings a field's session reads: pinyin first, Shift to English; English then Chinese to translate into;
    /// English interface; `useSelection` as given.
    static func sessionConfig(useSelection: Bool = true) -> Config {
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.chinese, .english])
        config.setOrder([OutputLanguage.english, .chinese])
        config.useSelection = useSelection
        return config
    }

    /// A new text field of `app` with the focus, "world" selected in "hello world", its session reading `config` and
    /// what is learned in `learned`.
    func selectedField(in app: String, config: Config, learned: LearnedStore) -> FakeHost {
        let engine = FakeEngine()
        var services = SessionServices(loadSettings: { config })
        services.levelOne = { .engine(engine) }
        services.programInstalled = { _ in true }
        services.learned = learned
        let host = FakeHost(services: services)
        host.app = app
        host.focus()
        host.document = "hello world"
        host.selection = 6..<11
        return host
    }

    /// "@" and `@improve` picked from the list (its first letter, Tab): whether it works on the selection (written in the
    /// panel, the field keeping its selection) rather than marked in the field as without one.
    func pickingImproveUsesTheSelection(_ host: FakeHost) -> Bool {
        host.press(FakeHost.at)
        host.type("i")
        host.press(FakeHost.tab)
        return host.composer.draftInPanel
    }

    /// An app that learned the selection off: "@" there no longer works on the selected text (the draft is marked as
    /// without a selection, the text left as it is); another app as before; forgotten, the app uses it again.
    @Test func anAppThatLearnedTheSelectionOffDoesNotUseIt() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let learned = Self.learnedStore(in: folder)
        let config = Self.sessionConfig()
        await withInterfaceLanguage("en") {
            #expect(pickingImproveUsesTheSelection(selectedField(in: Apps.mail, config: config, learned: learned)),
                    "before anything is learned, the selection is used")
            learned.turnSelectionOff(in: Apps.mail)
            let mail = selectedField(in: Apps.mail, config: config, learned: learned)
            #expect(!pickingImproveUsesTheSelection(mail), "learned off in Mail")
            #expect(mail.document == "hello world" && !mail.marked.isEmpty, "marked as without a selection: \(mail.document) | \(mail.marked)")
            #expect(pickingImproveUsesTheSelection(selectedField(in: Apps.slack, config: config, learned: learned)), "Slack as before")
            // Forget on its row in Privacy → Learned….
            for app in learned.selectionOffApps { learned.forgetSelectionOff(in: app) }
            #expect(pickingImproveUsesTheSelection(selectedField(in: Apps.mail, config: config, learned: learned)), "forgotten")
        }
    }

    /// "The config key still works for those who set it": `useSelection: false` turns it off in every app, whatever is
    /// learned; nothing is learned from it.
    @Test func theUseSelectionKeyStillTurnsItOffEverywhere() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let learned = Self.learnedStore(in: folder)
        let off = Self.sessionConfig(useSelection: false)
        await withInterfaceLanguage("en") {
            for app in [Apps.mail, Apps.slack] {
                let field = selectedField(in: app, config: off, learned: learned)
                #expect(!pickingImproveUsesTheSelection(field), "\(app)")
                #expect(field.document == "hello world")
            }
            #expect(learned.selectionOffApps.isEmpty && learned.items(appName: Apps.name).isEmpty,
                    "the setting isn't learned per app: \(learned.selectionOffApps)")
        }
    }
}

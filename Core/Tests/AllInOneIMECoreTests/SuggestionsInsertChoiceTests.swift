import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// What a suggestion row inserts is the user's choice (spec Suggestions v1, decision 28): the source's own templates (a
/// plugin's `insert`, a custom command's Insert), ID only, with title, with title and link; everywhere (Settings →
/// General, `Config.suggestionsInsert`) and per app (Settings → Apps, `AppProfile.suggestionsInsert`), an app's own over
/// the one everywhere. Every suggestion source follows it, plugins' and custom commands', never Code's packs; only what
/// wasn't typed goes in. Rows are put in by a click here, which inserts the row in every class of app whatever its keys
/// do. The rig is the acceptance tests' (Acceptance/SuggestionsAcceptanceTests.swift).
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsInsertChoiceTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// Where a row goes in: an ordinary app (a text editor), a chat app (Slack), a terminal.
    enum Place: String, CaseIterable, Sendable {
        case ordinary, chat, terminal

        var app: String {
            switch self {
            case .ordinary: return SuggestionsApps.editor
            case .chat: return SuggestionsApps.slack
            case .terminal: return "com.apple.Terminal"
            }
        }
    }

    /// Every choice, and none made (nil: the source's own, the default).
    static let choices: [SuggestionsInsert?] = [nil] + SuggestionsInsert.allCases.map(Optional.some)

    // MARK: - A GitHub-like plugin

    /// The GitHub plugin's `insert` as it ships: its title in documents, its title and link in chat apps, the number alone
    /// in terminals.
    static let githubInsert = #"{ "default": ["{arg} {title}", "{arg}"], "chat": ["{arg} {title} {url}", "{arg} {url}", "{arg}"], "terminal": "{match}" }"#

    /// An issue as the GitHub plugin returns it: the row shows "#1234 Fix login"; `{title}` is the title alone.
    static func issue(_ number: Int, _ title: String) -> CompletionItem {
        CompletionItem(match: "#\(number)", title: "#\(number) \(title)", arg: "#\(number)",
                       variables: ["url": "https://github.com/octo-org/octo-repo/issues/\(number)", "title": title])
    }

    static let link = "https://github.com/octo-org/octo-repo/issues/1234"

    /// A world with the GitHub-like plugin's issues #1234 and #1299 (a list, no lookups).
    static func githubWorld() throws -> SuggestionsWorld {
        let world = SuggestionsWorld()
        try world.github(items: [issue(1234, "Fix login"), issue(1299, "Dark mode")],
                         manifest: SuggestionsPlugins.githubManifest(query: false, insert: githubInsert))
        return world
    }

    /// What the row #1234 puts in for `choice` at `place`.
    static func github(_ choice: SuggestionsInsert?, _ place: Place) -> String {
        switch (choice ?? .source, place) {
        case (.source, .ordinary): return "#1234 Fix login"
        case (.source, .chat): return "#1234 Fix login " + link
        case (.source, .terminal): return "#1234"
        case (.id, _): return "#1234"
        case (.title, _): return "#1234 Fix login"
        case (.titleAndLink, _): return "#1234 Fix login " + link
        }
    }

    /// Each choice made everywhere, in an ordinary app, a chat app and a terminal: the source's own is the plugin's
    /// template for the app's class; the others are the same in every class. Only what wasn't typed goes in.
    @Test(arguments: choices, Place.allCases)
    func eachChoiceForAPluginsSource(_ choice: SuggestionsInsert?, _ place: Place) async throws {
        try await inEnglish {
            let world = try Self.githubWorld()
            world.switches.insert = choice
            let field = world.field(app: place.app, terminal: place == .terminal)
            field.type("#12")
            #expect(field.settle { field.issuesShown == ["#1234", "#1299"] }, "\(field.rows.map(\.text))")
            let before = field.host.outputs.count
            field.host.send(.pick(0))
            #expect(field.document == Self.github(choice, place), "\(choice?.rawValue ?? "none") in \(place)")
            let inserted = field.host.outputs.dropFirst(before).compactMap { output -> String? in
                if case let .commit(text) = output { return text } else { return nil }
            }
            #expect(inserted == [String(Self.github(choice, place).dropFirst(3))], "only what wasn't typed: \(inserted)")
        }
    }

    // MARK: - A custom command

    /// A custom suggestions command's program, as the tests run it: Jira tickets as lines "match⇥title⇥url".
    final class Tickets: CommandCompletionRuntime, @unchecked Sendable {
        func list(_ command: CustomCommand) async throws -> Data {
            Data("JIRA-12\tFix login\thttps://jira.example.com/browse/JIRA-12\nJIRA-17\tDark mode\n".utf8)
        }

        func query(_ text: String, _ command: CustomCommand) async throws -> Data { Data() }
    }

    /// A Jira command whose own Insert is the editor's default ("Just the match": `{arg}`).
    static let jira = CustomCommand(name: "jira", type: .suggestions, summary: "Jira issues", argv: ["/Users/me/bin/jira-list"],
                                    prefix: "JIRA-")

    /// What the row JIRA-12 puts in for `choice`: the command's own is the match in every class.
    static func jira(_ choice: SuggestionsInsert?) -> String {
        switch choice ?? .source {
        case .source, .id: return "JIRA-12"
        case .title: return "JIRA-12 Fix login"
        case .titleAndLink: return "JIRA-12 Fix login https://jira.example.com/browse/JIRA-12"
        }
    }

    /// Each choice made everywhere, for a custom command's rows, in an ordinary app, a chat app and a terminal: the
    /// command's own Insert (the match), else the choice, its title and link from the program's lines.
    @Test(arguments: choices, Place.allCases)
    func eachChoiceForACustomCommand(_ choice: SuggestionsInsert?, _ place: Place) async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            world.switches.commands = [Self.jira]
            world.switches.insert = choice
            let field = world.field(app: place.app, terminal: place == .terminal) { $0.suggestions.commandRuntime = Tickets() }
            field.type("JIRA-1")
            #expect(field.settle { field.rows.map(\.text) == ["JIRA-12", "JIRA-17"] }, "\(field.rows.map(\.text))")
            field.host.send(.pick(0))
            #expect(field.document == Self.jira(choice), "\(choice?.rawValue ?? "none") in \(place)")
        }
    }

    // MARK: - An app's own

    /// An app's own choice (Settings → Apps) wins over the one everywhere, its id in any case; an app without one follows
    /// the one everywhere; an app whose own is the source's has the plugin's templates whatever is chosen everywhere.
    @Test func anAppsOwnChoiceWinsOverTheOneEverywhere() async throws {
        try await inEnglish {
            var config = Config.default
            config.suggestionsInsert = .titleAndLink
            config.appProfiles = ["com.apple.Mail": AppProfile(suggestionsInsert: .title),
                                  "com.apple.Terminal": AppProfile(suggestionsInsert: .source),
                                  SuggestionsApps.slack: AppProfile(suggestionsInsert: .id)]
            let settings = config.suggestionsSettings()
            #expect(settings.insert == .titleAndLink)
            #expect(settings.insert(for: "com.apple.mail") == .title && settings.insert(for: "COM.APPLE.TERMINAL") == .source)
            #expect(settings.insert(for: SuggestionsApps.editor) == .titleAndLink && settings.insert(for: nil) == .titleAndLink)
            #expect(SuggestionsSettings().insert(for: "com.apple.mail") == .source, "nothing chosen: the source's own")

            let world = try Self.githubWorld()
            (world.switches.insert, world.switches.appInserts) = (settings.insert, settings.appInserts)
            for (app, terminal, expected) in [("com.apple.mail", false, "#1234 Fix login"), ("com.apple.Terminal", true, "#1234"),
                                              (SuggestionsApps.slack, false, "#1234"), (SuggestionsApps.editor, false, "#1234 Fix login " + Self.link),
                                              (SuggestionsApps.chrome, false, "#1234 Fix login " + Self.link)] {
                let field = world.field(app: app, terminal: terminal)
                field.type("#1234")
                #expect(field.settle { field.issuesShown == ["#1234"] }, "\(app): \(field.rows.map(\.text))")
                field.host.send(.pick(0))
                #expect(field.document == expected, "\(app)")
            }
        }
    }

    // MARK: - Fewer variables

    /// An item without a title or a link falls back to what it has: "With title and link" puts in the title alone where
    /// there's no link, the number alone where there's no title; "With title" the number alone without a title.
    @Test func anItemWithoutTitleOrLinkFallsBack() throws {
        let items = [CompletionItem(match: "#1201", arg: "#1201"),
                     CompletionItem(match: "#1202", title: "#1202 Only a title", variables: ["title": "Only a title"]),
                     CompletionItem(match: "#1203", variables: ["url": "https://example.com/1203"]),
                     Self.issue(1204, "Both")]
        let source = try #require(try Self.githubSource())
        func inserted(_ choice: SuggestionsInsert, _ appClass: SuggestionsAppClass = .ordinary) -> [String] {
            PluginRows.rows("#120", key: CompletionSourceKey(plugin: "github", source: "issues"), source: source,
                            lists: [CompletionItems(items)], madeAt: nil, appClass: appClass, insert: choice,
                            in: InterfaceWords(language: "en")).map(\.insertion)
        }
        let both = "#1204 Both https://github.com/octo-org/octo-repo/issues/1204"
        for appClass in [SuggestionsAppClass.ordinary, .chat, .codeEditor] {
            #expect(inserted(.titleAndLink, appClass) == ["#1201", "#1202 Only a title", "#1203", both], "\(appClass)")
            #expect(inserted(.title, appClass) == ["#1201", "#1202 Only a title", "#1203", "#1204 Both"], "\(appClass)")
            #expect(inserted(.id, appClass) == ["#1201", "#1202", "#1203", "#1204"], "\(appClass)")
        }
    }

    /// The GitHub-like plugin's source as declared.
    static func githubSource() throws -> CompletionSource? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("insert-choice-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try SuggestionsPlugins.install(SuggestionsPlugins.githubManifest(query: false, insert: githubInsert), in: folder)?
            .manifest.completions.first
    }

    /// One place decides a row's templates (`PluginRows.templates`): the source's for the app's class when its own is
    /// chosen, else the choice's in every class. A class the source has no rows in (`null`) still has none: the choice
    /// is what a row puts in, not where rows show.
    @Test func theTemplatesAreTheSourcesOrTheChoicesButNeverRowsWhereTheSourceHasNone() throws {
        let source = try #require(try Self.githubSource())
        #expect(PluginRows.templates(source, .ordinary) == ["{arg} {title}", "{arg}"])
        #expect(PluginRows.templates(source, .chat, insert: .source) == ["{arg} {title} {url}", "{arg} {url}", "{arg}"])
        #expect(PluginRows.templates(source, .codeEditor, insert: .source) == ["{match}"])
        for appClass in [SuggestionsAppClass.ordinary, .chat, .codeEditor] {
            #expect(PluginRows.templates(source, appClass, insert: .id) == ["{arg}"])
            #expect(PluginRows.templates(source, appClass, insert: .title) == ["{arg} {title}", "{arg}"])
            #expect(PluginRows.templates(source, appClass, insert: .titleAndLink) == ["{arg} {title} {url}", "{arg} {title}", "{arg}"])
        }
        var quiet = source
        quiet.insert = CompletionInsert(default: .templates(["{arg}"]), chat: .off, terminal: .off)
        for choice in SuggestionsInsert.allCases {
            #expect(PluginRows.templates(quiet, .chat, insert: choice) == nil, "\(choice)")
            #expect(PluginRows.templates(quiet, .codeEditor, insert: choice) == nil, "\(choice)")
            #expect(PluginRows.templates(quiet, .ordinary, insert: choice) != nil, "\(choice)")
        }
    }

    // MARK: - Code

    /// Code's rows (its pack's keywords and snippets, the field's words) are never the choice's: a keyword goes in as
    /// itself whatever is chosen everywhere or for the app.
    @Test func codesRowsAreNeverAffected() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            world.addCode("python", packs: [CodingLanguagePack(language: "python", title: "Python", version: "1.0.0",
                                                               keywords: ["define"], snippets: [])])
            world.switches.insert = .titleAndLink
            world.switches.appInserts = [SuggestionsApps.editor: .id]
            let code = world.codeField()
            code.type("def")
            #expect(code.settle { code.rows.map(\.text) == ["define"] }, "\(code.rows.map(\.text))")
            code.host.send(.pick(0))
            #expect(code.document == "define", "\(code.document)")
        }
    }

    // MARK: - The config

    /// Both keys round-trip: everywhere's (`suggestionsInsert`) and an app's (in its profile), each of the four values; a
    /// file without them doesn't gain them; a value this version doesn't know, or of the wrong type, reads as none and
    /// the rest of the file loads; an app that only chooses this has settings of its own (it's kept).
    @Test func theConfigRoundTrips() throws {
        for choice in SuggestionsInsert.allCases {
            var config = Config.default
            config.suggestionsInsert = choice
            config.appProfiles = ["com.apple.Terminal": AppProfile(suggestionsInsert: choice)]
            let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
            #expect(decoded.suggestionsInsert == choice && decoded.profile(for: "com.apple.terminal")?.suggestionsInsert == choice)
            #expect(decoded.suggestionsSettings().insert == choice && decoded.suggestionsSettings().appInserts == ["com.apple.Terminal": choice])
        }
        let none = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Config.default)) as? [String: Any])
        #expect(none["suggestionsInsert"] == nil, "a file from before doesn't gain the key")
        #expect(Config.allKeys.contains("suggestionsInsert"))

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("insert-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.json")
        try Data((#"{"suggestionsInsert": "titleAndLink", "appProfiles": {"com.apple.Terminal": {"suggestionsInsert": "id"}, "#
            + #""com.apple.mail": {"suggestionsInsert": "source", "noAI": true}}}"#).utf8).write(to: url)
        let read = try Config.load(from: url)
        #expect(read.suggestionsInsert == .titleAndLink)
        #expect(read.profile(for: "com.apple.Terminal") == AppProfile(suggestionsInsert: .id))
        #expect(read.profile(for: "com.apple.mail") == AppProfile(noAI: true, suggestionsInsert: .source))
        #expect(AppProfile(suggestionsInsert: .source).isEmpty == false, "its own choice: kept")
        try read.write(to: url)
        let again = try Config.load(from: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(again.suggestionsInsert == .titleAndLink && again.appProfiles == read.appProfiles, "\(text)")

        try Data(#"{"suggestionsInsert": "everything", "typeOut": true, "appProfiles": {"com.apple.Terminal": {"suggestionsInsert": 3, "noAI": true}}}"#
            .utf8).write(to: url)
        let lenient = try Config.load(from: url)
        #expect(lenient.suggestionsInsert == nil && lenient.typeOut == true)
        #expect(lenient.profile(for: "com.apple.Terminal") == AppProfile(noAI: true))
    }

    // MARK: - iCloud

    let t0 = SyncRig.t0
    func t(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    /// The choice everywhere syncs as the other settings do: set on one Mac, it comes to the other; back to the source's
    /// own (no value), it goes there too.
    @Test func theChoiceEverywhereSyncs() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A"), b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        try a.edit(at: t(2)) { $0.suggestionsInsert = .title }
        #expect(a.sync(at: t(3)).uploaded == ["suggestionsInsert"])
        let entry = try #require(try rig.settingsJSON()["suggestionsInsert"] as? [String: Any])
        #expect(entry["value"] as? String == "title", "\(entry)")
        #expect(b.sync(at: t(4)).applied == ["suggestionsInsert"])
        #expect(try b.config().suggestionsInsert == .title)
        try b.edit(at: t(5)) { $0.suggestionsInsert = nil }
        #expect(b.sync(at: t(6)).uploaded == ["suggestionsInsert"])
        #expect(a.sync(at: t(7)).applied == ["suggestionsInsert"])
        #expect(try a.config().suggestionsInsert == nil)
        #expect(a.sync(at: t(8)).applied.isEmpty && b.sync(at: t(9)).uploaded.isEmpty)
    }

    /// An app's own choice is a field of its settings iCloud knows, and syncs as the app's other fields do (what goes in
    /// there is the same on every Mac), unlike its Suggestions switch, each Mac's own: set on A it comes to B, B's own
    /// switch for the app staying B's; changed on B it comes back.
    @Test func anAppsChoiceSyncsAsItsOtherFieldsDo() throws {
        let terminal = "com.apple.Terminal"
        #expect(ICloudSync.knownFields(of: ICloudSync.appPrefix + terminal)?.contains("suggestionsInsert") == true)
        #expect(!ICloudSync.thisMacsOwnAppFields.contains("suggestionsInsert"))
        let rig = try SyncRig()
        let a = try rig.mac("A"), b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        try b.edit(at: t(2)) { $0.changeProfile(for: terminal) { $0.suggestions = false } }
        try a.edit(at: t(3)) { $0.changeProfile(for: terminal) { $0.suggestionsInsert = .id } }
        #expect(a.sync(at: t(4)).uploaded == ["appProfiles.\(terminal)"])
        let entry = try #require(try rig.settingsJSON()["appProfiles.\(terminal)"] as? [String: Any])
        #expect(entry["value"] as? [String: String] == ["suggestionsInsert": "id"], "\(entry)")
        #expect(b.sync(at: t(5)).applied == ["appProfiles.\(terminal)"])
        #expect(try b.config().profile(for: terminal) == AppProfile(suggestions: false, suggestionsInsert: .id))
        try b.edit(at: t(6)) { $0.changeProfile(for: terminal) { $0.suggestionsInsert = .titleAndLink } }
        #expect(b.sync(at: t(7)).uploaded == ["appProfiles.\(terminal)"])
        #expect(a.sync(at: t(8)).applied == ["appProfiles.\(terminal)"])
        #expect(try a.config().profile(for: terminal) == AppProfile(suggestionsInsert: .titleAndLink))
        #expect(a.sync(at: t(9)).applied.isEmpty && b.sync(at: t(10)).uploaded.isEmpty)
    }

    /// Every field of an app's settings, this one too, is one this version knows; the choice everywhere is a synced
    /// setting; a value iCloud brings that this version can't read is refused (the Mac's own kept), none (back to the
    /// source's own) taken.
    @Test func iCloudKnowsBothKeysAndRefusesWhatItCantRead() throws {
        let every = AppProfile(inputLanguage: .english, rewriteStyles: [], typeOut: true, noAI: true, translateAlways: true,
                               autocomplete: true, suggestions: false, suggestionsInsert: .title)
        let fields = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(every)) as? [String: Any])
        #expect(Set(fields.keys) == ICloudSync.knownFields(of: ICloudSync.appPrefix + "com.apple.mail"))
        #expect(ICloudSync.category(of: "suggestionsInsert") == .settings && !ICloudSync.neverSynced.contains("suggestionsInsert"))

        let env = ICloudSync.Environment()
        for choice in SuggestionsInsert.allCases {
            #expect(ICloudSync.problem("suggestionsInsert", .string(choice.rawValue), environment: env) == nil, "\(choice)")
            #expect(ICloudSync.problem("appProfiles.com.apple.mail", .object(["suggestionsInsert": .string(choice.rawValue)]),
                                       environment: env) == nil, "\(choice)")
        }
        #expect(ICloudSync.problem("suggestionsInsert", nil, environment: env) == nil)
        #expect(ICloudSync.problem("suggestionsInsert", .string("everything"), environment: env) == .unknownValue)
        #expect(ICloudSync.problem("suggestionsInsert", .bool(true), environment: env) == .wrongType)
        #expect(ICloudSync.problem("appProfiles.com.apple.mail", .object(["suggestionsInsert": .string("everything")]),
                                   environment: env) == .unknownValue)
        #expect(ICloudSync.problem("appProfiles.com.apple.mail", .object(["suggestionsInsert": .number(1)]), environment: env) == .wrongType)

        var config = Config.default
        config.suggestionsInsert = .id
        let refused = ICloudSync.applying(["suggestionsInsert": .string("everything")], to: config, environment: env)
        #expect(refused.config.suggestionsInsert == .id && refused.applied.isEmpty)
        let none: [String: AIConfig.JSONValue?] = ["suggestionsInsert": nil]
        let taken = ICloudSync.applying(none, to: config, environment: env)
        #expect(taken.config.suggestionsInsert == nil && taken.applied == ["suggestionsInsert"])
    }

    // MARK: - The settings document

    /// Windows' Settings (and the Mac's document): the choice everywhere in General under the Suggestions switch (not in
    /// Plugins), unset and the two Settings offers (Settings v2 §4: With title, With title and link), its help with
    /// GitHub's example, set into the config; an app's own in its item in Apps, "Same as everywhere" naming the choice
    /// everywhere, the two among its values, and in its summary. An app's ID only from an older version stays honored:
    /// its value, shown under its name, never picked anew.
    @Test(arguments: [SettingsPlatform.windows, .mac])
    func theSettingsDocumentHasBothFields(_ platform: SettingsPlatform) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("insert-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.json")
        try Data(#"{"appProfiles": {"com.apple.Terminal": {"noAI": true}, "com.apple.mail": {"suggestionsInsert": "id"}}}"#.utf8).write(to: url)
        let service = SettingsService(store: SettingsStore(configURL: url), platform: platform,
                                      library: PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true)),
                                      secrets: .inMemory())
        try await withInterfaceLanguage("en") {
            func section(_ id: String) -> [String] { service.document().sections.first { $0.id == id }?.fields.map(\.id) ?? [] }
            let general = section("general")
            #expect(general.firstIndex(of: "suggestions").flatMap { general.dropFirst($0 + 1).first } == "suggestionsInsert",
                    "\(general)")
            #expect(!section("plugins").contains("suggestionsInsert"), "\(section("plugins"))")
            let everywhere = try #require(service.document().field("suggestionsInsert"))
            #expect(everywhere.kind == .choice && everywhere.label == "Insert" && everywhere.value == nil, "\(everywhere)")
            #expect(everywhere.choices?.map(\.value) == [.null, .string("title"), .string("titleAndLink")])
            #expect(everywhere.choices?.map(\.label) == ["Default (each source's own)", "With title", "With title and link"])
            let help = try #require(everywhere.help)
            // One sentence (Settings v2): the example with title, and that the link comes after it.
            #expect(help.contains("#1234 Fix login") && help.contains("link") && !help.contains("Settings →"), "\(help)")

            #expect((try? service.set("suggestionsInsert", to: .string("title")).get()) != nil)
            #expect(try Config.load(from: url).suggestionsInsert == .title)
            #expect(service.document().field("suggestionsInsert")?.value == .string("title"))

            let own = try #require(service.document().field("apps.com.apple.Terminal.suggestionsInsert"))
            #expect(own.kind == .choice && own.label == "Insert" && own.value == nil, "\(own)")
            #expect(own.choices?.map(\.value) == [.null, .string("title"), .string("titleAndLink")])
            #expect(own.choices?.map(\.label) == ["Same as everywhere (With title)", "With title", "With title and link"])
            #expect((try? service.set("apps.com.apple.Terminal.suggestionsInsert", to: .string("titleAndLink")).get()) != nil)
            #expect(try Config.load(from: url).profile(for: "com.apple.Terminal") == AppProfile(noAI: true, suggestionsInsert: .titleAndLink))
            let item = service.document().field("apps.profiles")?.items?.first { $0.id == "com.apple.Terminal" }
            #expect(item?.detail?.contains("Insert: With title and link") == true, "\(item?.detail ?? "-")")
            #expect((try? service.set("apps.com.apple.Terminal.suggestionsInsert", to: .string("id")).get()) == nil, "ID only isn't offered")
            #expect((try? service.set("apps.com.apple.Terminal.suggestionsInsert", to: .null).get()) != nil)
            #expect(try Config.load(from: url).profile(for: "com.apple.Terminal") == AppProfile(noAI: true))

            // An app's ID only from an older version: honored and shown as it is.
            let old = try #require(service.document().field("apps.com.apple.mail.suggestionsInsert"))
            #expect(old.value == .string("id") && old.choices?.last == SettingsDocument.Choice(value: .string("id"), label: "ID only", disabled: true),
                    "\(old.choices ?? [])")
            let mail = service.document().field("apps.profiles")?.items?.first { $0.id == "com.apple.mail" }
            #expect(mail?.detail?.contains("Insert: ID only") == true, "\(mail?.detail ?? "-")")
            #expect(try Config.load(from: url).profile(for: "com.apple.mail")?.suggestionsInsert == .id)

            #expect((try? service.set("suggestionsInsert", to: .null).get()) != nil)
            #expect(try Config.load(from: url).suggestionsInsert == nil)
        }
    }
}

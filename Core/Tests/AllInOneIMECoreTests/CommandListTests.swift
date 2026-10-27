import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// What the @ command list offers (0.6.8, the owner's subtraction): a Suggestions command (a custom command of type
/// `suggestions`) is no @ command, used by its prefix alone; a plugin or script extension command with suggestions can be
/// taken out of the list too (Show in the @ list off, `Config.hiddenFromCommandList`, this Mac's own), its suggestions as
/// they were. Out of the list, its name after the magic key is a word like any name no command has; names are taken as
/// before. Its rows through a session: CommandSuggestionsSessionTests (a Suggestions command's), and here (a plugin's and an
/// extension's taken out of the list).
@Suite(.serialized, SuggestionsOneAtATime())
struct CommandListTests {
    static func jira() -> CustomCommand {
        CustomCommand(name: "Jira", type: .suggestions, summary: "Jira issues", argv: ["/usr/local/bin/jira-list"], prefix: "JIRA-")
    }

    /// A temporary folder the test removes.
    final class Folder: @unchecked Sendable {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("command-list-\(UUID().uuidString)", isDirectory: true)

        init() throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }

        deinit { try? FileManager.default.removeItem(at: url) }
    }

    /// A plugin with no completions: an @ command only.
    static let linkManifest = #"""
        { "name": "post", "version": "1.0.0", "type": "link", "url": "https://example.com/post?text={input}" }
        """#

    /// What the magic key, then `name`'s letters, then the action key twice do in a composer offering `commands` (English or
    /// Chinese): each key's answer, the field's text as the app has it then (what goes in, and the keys it gets), and
    /// whether the command list ever offered a command named `listed`.
    static func typed(_ name: String, with commands: [Command], english: Bool = true,
                      listed: String) -> (responses: [Composer.Response], text: String, offered: Bool) {
        let composer = Composer(engine: FakeEngine(), actionKey: .enter)
        composer.commands = commands
        composer.horizontalCandidates = true
        if english { composer.setInputMode(.english) }
        let field = AtSignTests.Field(composer)
        var responses: [Composer.Response] = []
        var offered = false
        func press(_ key: KeyEvent) {
            responses.append(field.press(key))
            offered = offered || composer.paletteMatches.contains { $0.name == listed }
        }
        press(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        for letter in name { press(k(String(letter))) }
        press(enterKey)
        press(enterKey)
        return (responses, field.text, offered)
    }

    // MARK: - A Suggestions command

    /// Never in the list: not with the magic key alone, not for a query it would match, not for its exact name; its name
    /// is no command's (`Command.parse`). The other custom commands are offered as before.
    @Test func aSuggestionsCommandIsNeverInTheList() {
        let catalog = Command.catalog([Self.jira(), CustomCommand(name: "python", type: .run, argv: ["python3", "-c", "{input}"])])
        #expect(!catalog.contains { $0.name == "jira" } && catalog.contains { $0.name == "python" })
        #expect(Command.palette("", in: catalog, usage: CommandUsage(), limit: .max).allSatisfy { $0.name != "jira" })
        for query in ["j", "ji", "jir", "jira", "JIRA"] {
            #expect(!Command.matching(query, in: catalog).contains { $0.name == "jira" }, "\(query)")
            #expect(!Command.palette(query, in: catalog, usage: CommandUsage(), limit: .max).contains { $0.name == "jira" }, "\(query)")
        }
        #expect(Command.parse("@jira JIRA-12", in: catalog) == nil && Command.parse("@python 1", in: catalog) != nil)
        for english in [true, false] {
            for name in ["", "j", "jira"] {
                #expect(!Self.typed(name, with: catalog, english: english, listed: "jira").offered, "@\(name), English: \(english)")
            }
        }
    }

    /// "@jira" then the action key does what it does where no command has that name (no Suggestions command at all): each
    /// key answers the same, the same text goes in, nothing is said; in English and in Chinese.
    @Test func atItsNameTheActionKeyDoesWhatAnUnknownNameDoes() {
        let with = Command.catalog([Self.jira()])
        let without = Command.catalog([])
        for english in [true, false] {
            let typed = Self.typed("jira", with: with, english: english, listed: "jira")
            let unknown = Self.typed("jira", with: without, english: english, listed: "jira")
            #expect(typed.responses == unknown.responses && typed.text == unknown.text, "English: \(english): \(typed.text) / \(unknown.text)")
            #expect(english ? typed.text.hasPrefix("@jira") : typed.text.hasPrefix("@"), "\(typed.text)")
            #expect(!typed.responses.contains { $0.effects.contains { if case .notice = $0 { return true } else { return false } } },
                    "nothing said: \(typed.responses)")
        }
    }

    /// Names as before (owner): it is a custom command, its name unique among them, the built-ins and the plugins, and
    /// still taken: a script extension of its name stays left out (Settings says by which), so no command changes name.
    @Test func itsNameIsTakenAsBefore() throws {
        let jira = Self.jira()
        #expect(jira.problem(among: []) == nil)
        #expect(CustomCommand(name: "jira", type: .run, argv: ["jira"]).problem(among: [jira]) == .nameTaken)
        #expect(CustomCommand(name: "github", type: .suggestions, argv: ["gh-issues"], prefix: "#").problem(among: [], plugins: ["github"])
                == .nameTaken)
        #expect(CustomCommand(name: "question", type: .suggestions, argv: ["q"], prefix: "Q-").problem(among: []) == .nameTaken)
        let extensions = try ExtensionCompletionsTests.Extensions()
        try extensions.script("jira.sh", metadata: ["schemaVersion 1", "title Jira"], body: "echo hi")
        let script = try #require(extensions.command("jira"))
        #expect(Command.hiddenScripts([script], custom: [jira]).map(\.owner) == [.custom])
        #expect(!Command.catalog([jira], scripts: [script]).contains { $0.name == "jira" })
        #expect(Command.catalog([], scripts: [script]).contains { $0.name == "jira" && $0.script == script }, "without it: the script's")
    }

    // MARK: - Show in the @ list

    /// A plugin with suggestions whose name is in `hiddenFromCommandList` is out of the list, its name still taken (a
    /// custom command of its name isn't offered in its place); one with no suggestion source is in it whatever the list
    /// says, as are the built-ins and the custom commands.
    @Test func aPluginWithSuggestionsCanBeTakenOutOfTheList() throws {
        let folder = try Folder()
        let tracker = try #require(try SuggestionsPlugins.install(SuggestionsPlugins.trackerManifest, in: folder.url))
        let post = try #require(try SuggestionsPlugins.install(Self.linkManifest, in: folder.url))
        #expect(tracker.hasSuggestions && !post.hasSuggestions)
        let plugins = [tracker, post]
        let mine = CustomCommand(name: "python", type: .run, argv: ["python3"])
        #expect(Set(Command.catalog([mine], plugins: plugins).map(\.name)).isSuperset(of: ["tracker", "post", "python", "question"]))
        let hidden = ["tracker", "post", "python", "question"]
        let names = Command.catalog([mine], plugins: plugins, hidden: hidden).map(\.name)
        #expect(!names.contains("tracker"), "\(names)")
        #expect(names.contains("post") && names.contains("python") && names.contains("question"), "no suggestion source: listed (\(names))")
        // Its name stays the plugin's: a custom command of that name (from a config edited by hand) doesn't take its place.
        let clash = CustomCommand(name: "tracker", type: .run, argv: ["tracker"])
        #expect(!Command.catalog([clash], plugins: plugins, hidden: hidden).contains { $0.name == "tracker" })
        // A Suggestions command is out whatever the list says.
        #expect(!Command.catalog([Self.jira()], hidden: []).contains { $0.name == "jira" })
    }

    /// "@tracker" then the action key, the plugin out of the list, does what it does with no such plugin; in the list, it
    /// is offered.
    @Test func atTheNameOfOneTakenOutTheActionKeyDoesWhatAnUnknownNameDoes() throws {
        let folder = try Folder()
        let tracker = try #require(try SuggestionsPlugins.install(SuggestionsPlugins.trackerManifest, in: folder.url))
        let hidden = Command.catalog([], plugins: [tracker], hidden: ["tracker"])
        for english in [true, false] {
            let typed = Self.typed("tracker", with: hidden, english: english, listed: "tracker")
            let unknown = Self.typed("tracker", with: Command.catalog([]), english: english, listed: "tracker")
            #expect(!typed.offered && typed.responses == unknown.responses && typed.text == unknown.text, "English: \(english): \(typed.text)")
        }
        #expect(Self.typed("tr", with: Command.catalog([], plugins: [tracker]), listed: "tracker").offered, "shown: offered")
    }

    /// A script extension command with suggestions whose id is in the list is out of it, its name still taken; one with
    /// none, or whose declaration was refused, is in it whatever the list says.
    @Test func aScriptExtensionWithSuggestionsCanBeTakenOutOfTheList() throws {
        let extensions = try ExtensionCompletionsTests.Extensions()
        let tickets = try ExtensionCompletionsTests.tickets(in: extensions)
        try extensions.script("hello.sh", metadata: ["schemaVersion 1", "title Hello"], body: "echo hi")
        try extensions.script("bad.sh", metadata: ["schemaVersion 1", #"completion {"query": true}"#], body: "echo")
        let hello = try #require(extensions.command("hello")), bad = try #require(extensions.command("bad"))
        #expect(tickets.hasSuggestions && !hello.hasSuggestions && !bad.hasSuggestions)
        let scripts = extensions.index.commands
        let hidden = [tickets.id, hello.id, bad.id]
        #expect(Set(Command.catalog([], scripts: scripts).map(\.name)).isSuperset(of: ["tickets", "hello", "bad"]))
        let names = Command.catalog([], scripts: scripts, hidden: hidden).map(\.name)
        #expect(!names.contains("tickets") && names.contains("hello") && names.contains("bad"), "\(names)")
        // Its name stays its own: a later extension of that name isn't offered in its place, as when it is listed.
        var other = hello
        (other.id, other.name) = ("~/elsewhere/tickets.sh", "tickets")
        #expect(Command.catalog([], scripts: [tickets, other]).filter { $0.name == "tickets" }.map(\.script) == [tickets])
        #expect(!Command.catalog([], scripts: [tickets, other], hidden: [tickets.id]).contains { $0.name == "tickets" })
        #expect(Command.hiddenScripts([tickets, other], custom: []).map(\.script) == [other], "Settings: left out, as before")
    }

    /// Out of the list, a plugin's suggestions are as they were: its rows show as its prefix is typed, as when it is listed,
    /// and the field's command list hasn't it.
    @Test func aPluginsSuggestionsStayWhenItIsOutOfTheList() async throws {
        try await withInterfaceLanguage("en") {
            func rows(hidden: [String]) throws -> (issues: [String], offered: Bool) {
                let world = SuggestionsWorld()
                try world.github()
                world.config.hiddenFromCommandList = hidden
                let field = world.field()
                let offered = field.host.session.composer.commands.contains { $0.name == "github" }
                field.type("#70")
                field.settle(timeout: 3) { field.issuesShown.count > 1 }
                return (field.issuesShown, offered)
            }
            let listed = try rows(hidden: []), hidden = try rows(hidden: ["github"])
            #expect(listed.offered && !hidden.offered)
            #expect(!hidden.issues.isEmpty && hidden.issues == listed.issues, "\(hidden.issues) / \(listed.issues)")
        }
    }

    /// Out of the list, a script extension's suggestions are as they were: its rows show as its prefix is typed, its list
    /// run by its script.
    @Test func anExtensionsSuggestionsStayWhenItIsOutOfTheList() async throws {
        try await withInterfaceLanguage("en") {
            let extensions = try ExtensionCompletionsTests.Extensions()
            let tickets = try ExtensionCompletionsTests.tickets(in: extensions)
            let (world, adjust) = ExtensionCompletionsTests.world(extensions, on: [tickets])
            world.config.hiddenFromCommandList = [tickets.id]
            let field = world.field(adjust)
            #expect(!field.host.session.composer.commands.contains { $0.name == "tickets" })
            field.type("TCK-1")
            #expect(field.settle(timeout: 15) { field.rows.map(\.text) == ["TCK-12", "TCK-17"] }, "\(field.rows.map(\.text))")
        }
    }

    // MARK: - Settings

    /// The item `id` of the settings list `list` ("plugins.installed", "extensions.installed").
    static func item(_ document: SettingsDocument, _ list: String, _ id: String) -> SettingsDocument.Item? {
        document.field(list)?.items?.first { $0.id == id }
    }

    /// Settings → Commands: under a plugin with suggestions, right after its suggestions' switch, Show in the @ list (on by
    /// default, the magic key in its name); off, its name is kept in `hiddenFromCommandList` (and nothing else changes),
    /// on again it's taken off. None under a plugin without suggestions.
    @Test func underAPluginItIsNextToItsSuggestionsSwitch() async throws {
        let folder = try Folder()
        _ = try SuggestionsPlugins.install(SuggestionsPlugins.trackerManifest, in: folder.url)
        _ = try SuggestionsPlugins.install(Self.linkManifest, in: folder.url)
        let url = folder.url.appendingPathComponent("config.json")
        try Data(#"{"commandTrigger": "~"}"#.utf8).write(to: url)
        let service = SettingsService(store: SettingsStore(configURL: url), platform: .mac,
                                      library: PluginLibrary(directory: folder.url.appendingPathComponent("plugins", isDirectory: true)),
                                      secrets: .inMemory())
        try await withInterfaceLanguage("en") {
            let tracker = try #require(Self.item(service.document(), "plugins.installed", "tracker"))
            let ids = (tracker.fields ?? []).map(\.id)
            #expect(ids.prefix(2) == ["plugins.completion.tracker.tickets", "plugins.commandList.tracker"], "\(ids)")
            let field = try #require(tracker.fields?[1])
            #expect(field.kind == .toggle && field.value == .bool(true) && field.label == "Show in the ~ list", "\(field)")
            #expect(field.help?.contains("~ command list") == true, "\(field.help ?? "")")
            let post = Self.item(service.document(), "plugins.installed", "post")
            #expect(post?.fields?.contains { $0.id.contains("commandList") } != true, "no suggestions: no switch")
            let before = try Config.load(from: url)
            #expect((try? service.set(field.id, to: .bool(false)).get()) != nil)
            var off = try Config.load(from: url)
            #expect(off.hiddenFromCommandList == ["tracker"])
            off.hiddenFromCommandList = []
            #expect(off == before, "nothing else changed")
            #expect(service.document().field(field.id)?.value == .bool(false))
            #expect((try? service.set(field.id, to: .bool(true)).get()) != nil)
            #expect(try Config.load(from: url).hiddenFromCommandList.isEmpty && service.document().field(field.id)?.value == .bool(true))
        }
    }

    /// Under a script extension command with suggestions, right after its suggestions' switch; none under one without, or
    /// one whose declaration was refused; never among the custom commands (a Suggestions command is always out) or for a
    /// built-in.
    @Test func underAnExtensionCommandItIsNextToItsSuggestionsSwitch() async throws {
        let extensions = try ExtensionCompletionsTests.Extensions()
        let tickets = try ExtensionCompletionsTests.tickets(in: extensions)
        try extensions.script("hello.sh", metadata: ["schemaVersion 1", "title Hello"], body: "echo hi")
        try extensions.script("bad.sh", metadata: ["schemaVersion 1", #"completion {"query": true}"#], body: "echo")
        let hello = try #require(extensions.command("hello")), bad = try #require(extensions.command("bad"))
        let folder = try Folder()
        let url = folder.url.appendingPathComponent("config.json")
        var config = Config.default
        config.extensionFolders = [extensions.folder.path]
        config.findRaycastScripts = false
        config.customCommands = [Self.jira()]
        config.uiLanguage = "zh"  // the document's language
        try config.write(to: url)
        let service = SettingsService(store: SettingsStore(configURL: url), platform: .mac,
                                      library: PluginLibrary(directory: folder.url.appendingPathComponent("plugins", isDirectory: true)),
                                      secrets: .inMemory())
        try await withInterfaceLanguage("zh") {
            let document = service.document()
            let item = try #require(Self.item(document, "extensions.installed", tickets.id))
            let ids = (item.fields ?? []).map(\.id)
            let suggestions = try #require(ids.firstIndex(of: "extensions.completion." + tickets.id))
            #expect(ids.indices.contains(suggestions + 1) && ids[suggestions + 1] == "extensions.commandList." + tickets.id, "\(ids)")
            #expect(document.field("extensions.commandList." + tickets.id)?.label == "在 @ 列表里显示")
            #expect(document.field("extensions.commandList." + hello.id) == nil && document.field("extensions.commandList." + bad.id) == nil)
            func switches(_ fields: [SettingsDocument.Field]) -> [String] {
                fields.flatMap { field in
                    (field.id.contains("commandList") ? [field.id] : []) + (field.items ?? []).flatMap { switches($0.fields ?? []) }
                }
            }
            #expect(document.sections.flatMap { switches($0.fields) } == ["extensions.commandList." + tickets.id])
            #expect((try? service.set("extensions.commandList." + tickets.id, to: .bool(false)).get()) != nil)
            #expect(try Config.load(from: url).hiddenFromCommandList == [tickets.id])
        }
    }

    // MARK: - The config

    /// `hiddenFromCommandList` stays on this Mac, as `disabledExtensions` does: never synced through iCloud. It is a config
    /// key, read back as written, not written while empty, a value of the wrong type read as none; turned on again, a
    /// name is taken off it once.
    @Test func theListIsKeptOnThisMacOnly() throws {
        #expect(ICloudSync.category(of: "disabledExtensions") == nil && ICloudSync.neverSynced.contains("disabledExtensions"))
        #expect(ICloudSync.category(of: "hiddenFromCommandList") == nil && ICloudSync.neverSynced.contains("hiddenFromCommandList"))
        #expect(Config.allKeys.contains("hiddenFromCommandList"))
        var config = Config.default
        #expect(config.hiddenFromCommandList.isEmpty && config.showsInCommandList("github"))
        config.setShownInCommandList("github", false)
        config.setShownInCommandList("github", false)
        config.setShownInCommandList("~/Scripts/tickets.sh", false)
        #expect(config.hiddenFromCommandList == ["github", "~/Scripts/tickets.sh"] && !config.showsInCommandList("github"))
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(decoded.hiddenFromCommandList == config.hiddenFromCommandList)
        config.setShownInCommandList("github", true)
        #expect(config.hiddenFromCommandList == ["~/Scripts/tickets.sh"] && config.showsInCommandList("github"))
        let empty = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Config.default)) as? [String: Any]
        #expect(empty?["hiddenFromCommandList"] == nil, "not written while empty")
        let wrong = try JSONDecoder().decode(Config.self, from: Data(#"{"hiddenFromCommandList": "github"}"#.utf8))
        #expect(wrong.hiddenFromCommandList.isEmpty)
    }
}

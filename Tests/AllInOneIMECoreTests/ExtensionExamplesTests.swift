import Foundation
import Testing
@testable import AllInOneIMECore

/// The public examples in Examples/extensions, loaded and run through the composer as a user would.
struct ExtensionExamplesTests {
    let helpers = ExtensionComposerTests()

    func typeKeys(_ text: String, _ composer: Composer) { helpers.typeKeys(text, composer) }
    func composer(_ index: ExtensionIndex) -> Composer { helpers.composer(index) }
    func runList(_ c: Composer) async throws -> [Composer.Effect] { try await helpers.runList(c) }
    func environment(_ command: ScriptCommand, query: String, preferences: [String: String] = [:]) -> [String: String] {
        helpers.environment(command, query: query, preferences: preferences)
    }
    @discardableResult
    func finish(_ effects: [Composer.Effect], in c: Composer, preferences: [String: String] = [:]) async -> [Composer.Effect] {
        await helpers.finish(effects, in: c, preferences: preferences)
    }
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    /// Examples/extensions, as the repository has them.
    static let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Examples/extensions")

    @Test func theExamplesLoad() throws {
        let index = ExtensionStore.load([.init(path: Self.examples.path, found: false)])
        #expect(index.skipped.isEmpty, "\(index.skipped)")
        #expect(index.commands.map(\.name)
            == ["bm", "convert", "unitlist", "battery", "clock", "countdown", "say", "timer", "uuid", "wordcount"])
        #expect(index.bundles.map(\.name) == ["bookmarks", "units"])
        #expect(index.bundles.map { $0.preferences.map(\.kind) } == [[.textfield, .password], [.dropdown]])
        let byName = Dictionary(uniqueKeysWithValues: index.commands.map { ($0.name, $0) })
        // Every feature of the protocol has an example.
        #expect(byName["clock"]?.output == .list && byName["countdown"]?.output == .show && byName["uuid"]?.input == ScriptCommand.Input.none)
        #expect(byName["timer"]?.background == true && byName["battery"]?.status?.isSelf == true && byName["convert"]?.output == .list)
        #expect(byName["say"]?.confirm == true && byName["say"]?.output == .silent)
        #expect(byName["wordcount"]?.source == .raycast && byName["wordcount"]?.output == .silent && byName["wordcount"]?.group == "Text")
        #expect(byName["bm"]?.output == .list && byName["bm"]?.source == .bundle("bookmarks"))
    }

    @Test func theExamplesRun() async throws {
        let index = ExtensionStore.load([.init(path: Self.examples.path, found: false)])
        let bundle = try #require(index.bundles.first { $0.name == "units" })
        let prefs = bundle.values([:])
        // A list that reruns: the cities matching, with their time.
        let clock = composer(index)
        typeKeys("@clock tok", clock)
        _ = try await runList(clock)
        #expect(clock.currentList?.items.first?.title.hasPrefix("Tokyo") == true && clock.currentList?.rerun == 30)
        let picked = clock.handleKeyDown(enterKey).effects
        #expect(commits(picked).first?.hasSuffix("(Tokyo)") == true)
        // The bundle's list, with its preference (precision 2 by default).
        let convert = composer(index)
        typeKeys("@convert 10 km", convert)
        let query = try #require(convert.listQuery), script = try #require(convert.draftCommand?.script)
        var output = ScriptOutput.text("")
        for try await update in CommandRunner.run(script, arguments: [query], environment: environment(script, query: query, preferences: prefs))
        where update.isFinal { output = update.output }
        _ = convert.receiveList(output, for: query)
        #expect(convert.currentList?.items.contains { $0.title == "6.21 mi" } == true)
        // A show, from the bundle's shared table.
        let units = composer(index)
        typeKeys("@unitlist", units)
        _ = units.handleKeyDown(tab)
        await finish(units.handleKeyDown(enterKey).effects, in: units, preferences: prefs)
        #expect(units.choices.contains { $0.text.hasPrefix("km") } && units.choices.allSatisfy { $0.kind == .shown })
        // No input: a new UUID to insert.
        let uuid = composer(index)
        typeKeys("@uuid", uuid)
        _ = uuid.handleKeyDown(tab)
        await finish(uuid.handleKeyDown(enterKey).effects, in: uuid)
        #expect(uuid.choices.first?.text.count == 36)
        // A show with progress.
        let countdown = composer(index)
        typeKeys("@countdown 1", countdown)
        await finish(countdown.handleKeyDown(enterKey).effects, in: countdown)
        #expect(countdown.choices.map(\.text) == ["1…", "Time's up!"])
        // In the background: started here, its summary when done (run directly: the controller would).
        let timer = try #require(index.commands.first { $0.name == "timer" })
        var summary: ScriptOutput?
        for try await update in CommandRunner.run(timer, arguments: ["0"], environment: environment(timer, query: "0")) where update.isFinal {
            summary = update.output
        }
        #expect(summary == .summary("Time is up", detail: "Your 0-minute timer finished"))
        // A status line.
        let battery = try #require(index.commands.first { $0.name == "battery" })
        var status: String?
        let env = ScriptContext(language: "en", inputLanguage: "en", app: nil, query: "").environment(for: battery, base: ["PATH": "/usr/bin:/bin"], status: true)
        for try await update in CommandRunner.run(battery, arguments: [], environment: env, status: true) where update.isFinal {
            status = update.output.lines.first
        }
        #expect(status.map { $0 == "AC" || $0.hasSuffix("%") } == true, "\(status ?? "nil")")
    }

    /// The bookmarks bundle: each row action (open, copy, a second step with `run`), and a password preference.
    @Test func theBookmarksRowActions() async throws {
        let index = ExtensionStore.load([.init(path: Self.examples.path, found: false)])
        let bookmarks = try #require(index.bundles.first { $0.name == "bookmarks" })
        let prefs = bookmarks.values(["token": "t0ken"])
        func listed(_ text: String) async throws -> Composer {
            let c = composer(index)
            typeKeys("@bm " + text, c)
            let query = try #require(c.listQuery), script = try #require(c.draftCommand?.script)
            var output = ScriptOutput.text("")
            for try await update in CommandRunner.run(script, arguments: [query], environment: environment(script, query: query, preferences: prefs))
            where update.isFinal { output = update.output }
            _ = c.receiveList(output, for: query)
            return c
        }
        let open = try await listed("swi")
        #expect(open.currentList?.items.map(\.action) == [.open, .copy, .run, .insert] && open.currentList?.items.last?.valid == false)
        #expect(open.handleKeyDown(enterKey).effects.contains(.openLink(URL(string: "https://www.swift.org")!)))
        let copy = try await listed("swi")
        _ = copy.handleKeyDown(downKey)
        #expect(copy.handleKeyDown(enterKey).effects.contains(.copy("https://www.swift.org")))
        let details = try await listed("swi")
        _ = details.handleKeyDown(downKey)
        _ = details.handleKeyDown(downKey)
        await finish(details.handleKeyDown(enterKey).effects, in: details, preferences: prefs)
        #expect(details.choices.first?.text == "https://www.swift.org" && details.choices.first?.detail == "Swift · a checker token is set")
        // The home folder row opens a folder (allowed); the word count is a Raycast silent script.
        let home = try await listed("home")
        #expect(home.handleKeyDown(enterKey).effects.contains(.openLink(URL(fileURLWithPath: NSHomeDirectory()))))
        let words = composer(index)
        typeKeys("@wordcount hello big world", words)
        let said = await finish(words.handleKeyDown(enterKey).effects, in: words)
        #expect(said.contains(.notice("3 words, 15 characters")))
    }
}

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
        #expect(index.commands.map(\.name) == ["convert", "unitlist", "battery", "clock", "countdown", "timer", "uuid"])
        #expect(index.bundles.map(\.name) == ["units"] && index.bundles.first?.preferences.map(\.name) == ["precision"])
        let byName = Dictionary(uniqueKeysWithValues: index.commands.map { ($0.name, $0) })
        #expect(byName["clock"]?.output == .list && byName["countdown"]?.output == .show && byName["uuid"]?.input == ScriptCommand.Input.none)
        #expect(byName["timer"]?.background == true && byName["battery"]?.status?.isSelf == true && byName["convert"]?.output == .list)
    }

    @Test func theExamplesRun() async throws {
        let index = ExtensionStore.load([.init(path: Self.examples.path, found: false)])
        let bundle = try #require(index.bundles.first)
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
}

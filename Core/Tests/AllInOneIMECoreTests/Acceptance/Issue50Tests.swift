import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// #50: a script command with `input required` whose argument1 is marked optional and argument2 isn't. The code makes
/// the first argument required only when every argument is optional: at least one must be written, and one the author
/// marked optional stays optional when a later one is required, so `@weather , tokyo` runs with an empty $1. That stays
/// (the fix is to the docs, which said the first is required "whatever it says"). Through the composer as the user
/// types the command (the scripts made in a temporary folder and really run, as ExtensionComposerTests runs them).
struct Issue50Tests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)

    func typeKeys(_ text: String, _ composer: Composer) {
        for ch in text { _ = composer.handleKeyDown(ch == "@" ? at : ch == " " ? spaceKey : k(String(ch))) }
    }

    /// A composer in English mode, ⏎ the action key, offering `folder`'s commands.
    func composer(_ folder: ScriptFolder) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.commands = Command.catalog([], scripts: folder.load().commands)
        return c
    }

    /// The run `effects` start: its command, arguments, text and request.
    func started(_ effects: [Composer.Effect]) -> (command: Command, arguments: [String], query: String, id: Int, action: Bool)? {
        for effect in effects {
            if case let .startScript(command, arguments, query, id, action) = effect { return (command, arguments, query, id, action) }
        }
        return nil
    }

    /// Runs what `effects` start, as the controller does, and gives the composer each update (as ExtensionComposerTests).
    func finish(_ effects: [Composer.Effect], in c: Composer) async {
        guard let start = started(effects), var script = start.command.script else { return }
        script.timeout = Double(Timing.longSleep)
        let environment = ScriptContext(language: "en", inputLanguage: "en", app: "com.example.editor", query: start.query)
            .environment(for: script, base: ["PATH": "/usr/bin:/bin"], action: start.action)
        do {
            for try await update in CommandRunner.run(script, arguments: start.arguments, environment: environment) {
                _ = c.receiveScript(update.output, isFinal: update.isFinal, id: start.id)
            }
        } catch {
            _ = c.fail(error.localizedDescription, id: start.id)
        }
    }

    /// `input required`, argument1 optional, argument2 required.
    func weather(_ folder: ScriptFolder) {
        folder.add("weather.sh", script(["title Weather", "input required",
                                         #"argument1 {"type": "text", "placeholder": "day", "optional": true}"#,
                                         #"argument2 {"type": "text", "placeholder": "city"}"#],
                                        #"echo "<$1|$2>""#))
    }

    /// The issue's trigger, kept as it is: `@weather , tokyo` runs with an empty $1 and "tokyo" as $2.
    @Test func aLaterRequiredArgumentLeavesTheFirstOptional() async throws {
        let folder = ScriptFolder()
        weather(folder)
        let command = try #require(folder.load().commands.first { $0.name == "weather" })
        #expect(command.input == .required)
        #expect(command.arguments.map(\.optional) == [true, false], "argument1 stays optional: argument2 is required")

        let c = composer(folder)
        typeKeys("@weather , tokyo", c)
        let effects = c.handleKeyDown(enterKey).effects
        let start = try #require(started(effects), "runs with only the required argument written: \(effects)")
        #expect(start.arguments == ["", "tokyo"])
        await finish(effects, in: c)
        #expect(c.choices.map(\.text) == ["<|tokyo>"])
    }

    /// Something must still be written: the required one. With nothing written, or only the first, nothing runs and
    /// the notice names argument2 (the one still needed), not argument1.
    @Test func nothingWrittenNamesTheLaterRequiredArgument() {
        let folder = ScriptFolder()
        weather(folder)

        let c = composer(folder)
        typeKeys("@weather ", c)
        let nothing = c.handleKeyDown(enterKey).effects
        #expect(started(nothing) == nil && nothing == [.notice("还要写：city")], "\(nothing)")

        let d = composer(folder)
        typeKeys("@weather monday", d)
        let first = d.handleKeyDown(enterKey).effects
        #expect(started(first) == nil && first == [.notice("还要写：city")], "\(first)")
    }
}

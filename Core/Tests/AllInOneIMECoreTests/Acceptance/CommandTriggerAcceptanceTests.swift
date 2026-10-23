import Foundation
import Testing
@testable import AllInOneIMECore

/// User-visible behavior of the command prefix. These cases deliberately drive keys through Composer,
/// independently of the implementation's own unit tests.
struct CommandTriggerAcceptanceTests {
    private func composer(trigger: String = "@", before: Character? = nil) -> Composer {
        let composer = Composer(engine: FakeEngine(), actionKey: .enter)
        composer.setInputMode(.english)
        composer.commands = Command.builtins
        composer.commandTrigger = trigger
        composer.characterBeforeCaret = { before }
        return composer
    }

    private func press(_ character: String, on composer: Composer) -> Composer.Response {
        composer.handleKeyDown(k(character))
    }

    @Test func existingInstallKeepsAtSignAsTheDefault() throws {
        let oldFile = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(Config.default.commandTrigger == "@")
        #expect(oldFile.commandTrigger == "@")

        let composer = composer(trigger: oldFile.commandTrigger)
        let response = press("@", on: composer)
        #expect(response.handled)
        #expect(composer.draft == "@")
        #expect(!composer.paletteMatches.isEmpty)
    }

    @Test func tildeOpensTheSameCommandPaletteAndOldAtSignIsOrdinaryText() {
        let composer = composer(trigger: "~")
        let at = press("@", on: composer)
        #expect(!at.handled && composer.draft.isEmpty && composer.paletteMatches.isEmpty)

        let tilde = press("~", on: composer)
        #expect(tilde.handled && composer.draft == "~" && !composer.paletteMatches.isEmpty)
        _ = press("i", on: composer)
        _ = press("m", on: composer)
        #expect(composer.paletteQuery == "im")
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        #expect(composer.draft == "~improve ")
        #expect(composer.draftCommand == .improve)
    }

    @Test func customTriggerInsideAWordDoesNotStealOrdinaryTyping() {
        let composer = composer(trigger: "~", before: "x")
        let response = press("~", on: composer)
        #expect(!response.handled && composer.draft.isEmpty && composer.markedText.isEmpty)
    }

    @Test func anotherSymbolAlsoWorksAndEscapingThePaletteKeepsWhatWasTyped() {
        let composer = composer(trigger: "#")
        #expect(press("#", on: composer).handled && composer.draft == "#")
        let response = press(".", on: composer)
        #expect(commits(response) == ["#"] && !response.handled)
        #expect(composer.draft.isEmpty && !composer.isComposing)
    }

    @Test func nestedCommandPaletteUsesTheNewTrigger() {
        let composer = composer(trigger: "~")
        for character in "~reply" { _ = press(String(character), on: composer) }
        _ = composer.handleKeyDown(spaceKey)
        #expect(composer.draftCommand == .reply)
        for character in "hello ~py" { _ = press(String(character), on: composer) }
        #expect(composer.paletteQuery == "py")
        #expect(composer.paletteMatches.contains(.py))
    }

    @Test func commandTriggerSurvivesSavingAndReloadingConfig() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("command-trigger-\(UUID())")
        let file = folder.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: folder) }

        var config = Config.default
        config.commandTrigger = "~"
        try config.write(to: file)
        let restored = try Config.load(from: file)
        #expect(restored.commandTrigger == "~")

        let composer = composer(trigger: restored.commandTrigger)
        #expect(press("~", on: composer).handled && composer.draft == "~")
    }

    @Test func unusableTriggerValuesFallBackToAtSign() throws {
        for invalid in ["", " ", "a", "7", "~~", "\n"] {
            let data = try JSONEncoder().encode(["commandTrigger": invalid])
            let config = try JSONDecoder().decode(Config.self, from: data)
            #expect(config.commandTrigger == "@", "Invalid prefix \(String(reflecting: invalid))")
        }
    }

    @Test func writingModePairsCommandsUsingOnlyTheConfiguredTrigger() {
        let pair = WritingMode.parse(.improve, "~translate 你好", trigger: "~")
        #expect(pair.mode == .both && pair.text == "你好")
        let literal = WritingMode.parse(.improve, "@translate 你好", trigger: "~")
        #expect(literal.mode == .improve && literal.text == "@translate 你好")
    }

    @Test func nestedCommandPlanUsesOnlyTheConfiguredTrigger() {
        let catalog = Command.catalog([CustomCommand(name: "stock", type: .run, argv: ["stock", "{input}"])])
        let plan = CommandPlan.make("比较 ~stock AAPL 和 @stock 700", commands: catalog, trigger: "~")
        #expect(plan.inner.map(\.command.name) == ["stock"])
        #expect(plan.inner.map(\.argument) == ["AAPL"])
        #expect(plan.input(outputs: ["QUOTE"]) == "比较 QUOTE 和 @stock 700")
    }
}

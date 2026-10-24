import AllInOneIMECore
import Testing
@testable import AllInOneIMERime

extension RimeEngineTests {
    @Test func customTriggerStartsAndRunsCommandsWithRealRime() throws {
        let composer = Composer(engine: try RimeFixture.session())
        composer.commandTrigger = "~"
        composer.commands = Command.catalog([CustomCommand(name: "stock", type: .run, argv: ["stock", "{input}"])])
        defer { composer.engine?.clearComposition() }

        let tilde = KeyEvent(keyCode: 0x32, characters: "~", charactersIgnoringModifiers: "`", modifiers: .shift)
        #expect(composer.handleKeyDown(tilde).handled && composer.draft == "~")
        _ = composer.handleKeyDown(key("q"))
        _ = composer.handleKeyDown(enter)
        #expect(composer.draft == "~question ")

        for character in "nihao" { _ = composer.handleKeyDown(key(character)) }
        _ = composer.handleKeyDown(space)
        #expect(composer.draft == "~question 你好")

        #expect(composer.handleKeyDown(tilde).handled)
        #expect(composer.paletteMatches.map(\.name) == ["py", "js", "stock"])
        for character in "st" { _ = composer.handleKeyDown(key(character)) }
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        #expect(composer.draft == "~question 你好~stock ")
        for character in "AAPL" {
            _ = composer.handleKeyDown(KeyEvent(keyCode: 0, characters: String(character), modifiers: .shift))
        }
        _ = composer.handleKeyDown(space)
        for character in "zenmeyang" { _ = composer.handleKeyDown(key(character)) }

        let effects = composer.handleKeyDown(enter).effects
        guard case let .startPlan(command, plan, _)? = effects.first else {
            Issue.record("Expected nested command plan: \(effects)")
            return
        }
        #expect(command == .question)
        #expect(plan.inner.map(\.command.name) == ["stock"] && plan.inner.map(\.argument) == ["AAPL"])
        #expect(plan.input(outputs: ["QUOTE"]) == "你好QUOTE 怎么样")
    }

    @Test func oldAtSignIsOrdinaryTextAfterChangingTriggerWithRealRime() throws {
        let composer = Composer(engine: try RimeFixture.session())
        composer.commandTrigger = "~"
        composer.setInputMode(.english)
        defer { composer.engine?.clearComposition() }

        let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "2", modifiers: .shift)
        let response = composer.handleKeyDown(at)
        #expect(!response.handled)
        #expect(composer.draft.isEmpty && composer.paletteMatches.isEmpty)
    }
}

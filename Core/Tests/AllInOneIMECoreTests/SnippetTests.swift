import Foundation
import Testing
@testable import AllInOneIMECore

// Snippets beyond the acceptance scenarios: `}}` only closing a `{{` (JSON and code kept), the text planned once with the
// snippets in it (an "@" in a snippet's text runs and stops nothing), `{selection}` with a selection too long, the
// narrow keeping of custom commands a later version wrote, and a bundle's snippets that can't be read.

private let atKey = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)

private func snippet(_ name: String, _ text: String) -> CustomCommand {
    CustomCommand(name: name, type: .snippet, text: text)
}

/// A text field typing English, with the built-ins and `custom`.
private func field(_ custom: [CustomCommand], selection: Composer.Selection? = nil) -> Composer {
    let c = Composer(engine: FakeEngine(), voiceEnabled: false, actionKey: .enter)
    c.commands = Command.catalog(custom)
    c.inputLanguages = [.chinese, .english]
    c.setInputMode(.english)
    if let selection { c.readSelection = { selection } }
    return c
}

/// Each character as a key ("@" as Shift-2, Space as the Space key).
private func typeIn(_ text: String, _ c: Composer) {
    for ch in text {
        let event = ch == "@" ? atKey : ch == " " ? spaceKey : KeyEvent(keyCode: 0, characters: String(ch), modifiers: ch.isUppercase ? .shift : [])
        _ = c.handleKeyDown(event)
    }
}

private func notices(_ effects: [Composer.Effect]) -> [String] {
    effects.compactMap { if case let .notice(s) = $0 { return s } else { return nil } }
}

private func rendered(_ template: String, input: String = "") -> String {
    SnippetTemplate.parse(template).render(SnippetValues(input: input)).text
}

@Suite struct SnippetEscapeTests {
    @Test func jsonAndCodeKeepTheirBraces() {
        // No `{{` before them: every `}}` stays as written.
        #expect(rendered(#"{"a":{"b":1}}"#) == #"{"a":{"b":1}}"#)
        #expect(rendered(#"{"a":{"b":{"c":[1,{"d":2}]}}}"#) == #"{"a":{"b":{"c":[1,{"d":2}]}}}"#)
        #expect(rendered("function f(){return {a:1}}") == "function f(){return {a:1}}")
        #expect(rendered("if (x) { if (y) { z() }}") == "if (x) { if (y) { z() }}")
        #expect(rendered("fn main() { println!(\"{}\", 1); }}") == "fn main() { println!(\"{}\", 1); }}")
        #expect(rendered("}}") == "}}" && rendered("a }} b") == "a }} b")
        // JSON with a placeholder in it: filled, the braces kept.
        #expect(rendered(#"{"user":"{input}","n":{"m":1}}"#, input: "wei") == #"{"user":"wei","n":{"m":1}}"#)
        let code = SnippetTemplate.parse("func f() {\n    {cursor}\n}}")
        let render = code.render(SnippetValues())
        #expect(render.text == "func f() {\n    \n}}" && render.caretBack == 3)
    }

    @Test func doubledBracesStillEscape() {
        // S11: the `}}` closing a `{{`.
        #expect(rendered("{{input}} {x}", input: "typed") == "{input} {x}")
        #expect(rendered(#"{{"a":1}}"#) == #"{"a":1}"#)
        // Only one `}}` per `{{`; the next stays.
        #expect(rendered("{{ }} }}") == "{ } }}")
        #expect(rendered("{{a}} and {{b}}") == "{a} and {b}")
        // Two open, two closed.
        #expect(rendered("{{{{x}}}}") == "{{x}}")
        // An escape for a placeholder's braces: written, not filled.
        #expect(rendered("{{date}}") == "{date}" && SnippetTemplate.parse("{{cursor}}").cursorCount == 0)
    }

    @Test func lineBreaksAcrossPlaceholders() {
        // `\r` in the text and `\n` from the input are one line break.
        #expect(rendered("a\r{input}", input: "\nb") == "a\nb")
        let render = SnippetTemplate.parse("a\r{cursor}\nb").render(SnippetValues())
        #expect(render.text == "a\nb" && render.caretBack == 2)
        let crlf = SnippetTemplate.parse("x\r\n{cursor}y\r\nz").render(SnippetValues())
        #expect(crlf.text == "x\ny\nz" && crlf.caretBack == 3)
    }
}

@Suite struct SnippetInsideATextTests {
    /// A signature with an address in it.
    let sig = snippet("sig", "Wei <wei@example.com>")

    @Test func anAtInASnippetDoesntStopTheUsersCommands() throws {
        let catalog = Command.catalog([sig])
        let filled = CommandPlan.make("1+1 @py print(2) @sig 。", commands: catalog).fillingSnippets(SnippetValues())
        #expect(filled.plan.inner.map(\.command) == [.py] && filled.plan.inner.map(\.argument) == ["print(2)"])
        #expect(filled.used.map(\.name) == ["sig"])
        #expect(filled.plan.input(outputs: ["2"]) == "1+1 2 Wei <wei@example.com> 。")

        // In the composer: @py runs, the signature is text in the question, nothing said about code not run.
        let c = field([sig])
        typeIn("@question 1+1 @py print(2) @sig 。", c)
        #expect(c.draft == "@question 1+1 @py print(2) @sig 。", "\(c.draft)")
        let effects = c.handleKeyDown(enterKey).effects
        guard case let .startPlan(outer, plan, _)? = effects.first else {
            Issue.record("expected a plan, got \(effects)")
            return
        }
        #expect(outer == .question && plan.inner.map(\.command) == [.py], "\(plan)")
        #expect(plan.input(outputs: ["2"]) == "1+1 2 Wei <wei@example.com> 。")
        #expect(notices(effects).isEmpty, "\(effects)")
        #expect(effects.contains(.commandUsed("sig")) && effects.contains(.commandUsed("py")))
    }

    @Test func aCommandWrittenInASnippetIsText() {
        // What a snippet inserts is never read for commands again: neither code nor a program in it runs.
        let memo = snippet("memo", "run @py 1+1 and @stock AAPL")
        let catalog = Command.catalog([memo, CustomCommand(name: "stock", type: .run, argv: ["stock", "{input}"])])
        let filled = CommandPlan.make("see @memo.", commands: catalog).fillingSnippets(SnippetValues())
        #expect(filled.plan.isEmpty && filled.used.map(\.name) == ["memo"])
        #expect(filled.plan.input(outputs: []) == "see run @py 1+1 and @stock AAPL.")
        #expect(SnippetTemplate.expandInner("see @memo.", commands: catalog, values: SnippetValues()) == "see run @py 1+1 and @stock AAPL.")

        let c = field([memo])
        typeIn("@improve see @memo.", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(effects.first == .startConversion(input: "see run @py 1+1 and @stock AAPL.", id: 1), "\(effects)")
        #expect(notices(effects).isEmpty && c.refineRequest != nil)
    }
}

@Suite struct SnippetSelectionTests {
    let bold = snippet("bold", "**{selection}**")
    let long = String(repeating: "a", count: Composer.maxSelectionLength + 1000)

    @Test func aSelectionTooLongIsNeverReplacedWithNothing() {
        let selection = Composer.Selection(text: long, range: 0..<long.count)
        let c = field([bold], selection: selection)
        typeIn("@bold", c)
        #expect(c.selectionTooLong)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(notices(effects) == [c.messages.snippetSelectionTooLong], "\(effects)")
        #expect(!effects.contains { if case .replaceSelection = $0 { return true } else { return false } }, "\(effects)")
        #expect(commits(effects).isEmpty && c.draft.hasPrefix("@bold"), "\(c.draft)")
        #expect(!effects.contains(.commandUsed("bold")))
        #expect(Composer.Messages.make(language: "en").snippetSelectionTooLong
                == "The selected text is too long: \(Composer.maxSelectionLength) characters at most")
    }

    @Test func aSnippetWithoutSelectionStillGoesIn() {
        let selection = Composer.Selection(text: long, range: 0..<long.count)
        let c = field([snippet("hi", "Hello")], selection: selection)
        typeIn("@hi", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(notices(effects).isEmpty && effects.contains(.commandUsed("hi")), "\(effects)")
    }
}

@Suite struct UnreadCustomCommandTests {
    private func decode(_ entries: String) throws -> Config {
        try JSONDecoder().decode(Config.self, from: Data((#"{"customCommands": ["# + entries + "]}").utf8))
    }

    @Test func onlyALaterTypeWithANameIsKept() throws {
        let kept = try decode(#"{"name": "sig", "type": "snippet", "text": "Best"}, {"name": "Future", "type": "hologram", "beam": 1}"#)
        #expect(kept.customCommands.map(\.name) == ["sig"] && kept.unreadCustomCommandNames == ["Future"])

        // A known type written wrong is the error it always was, not kept out of sight.
        #expect(throws: (any Error).self) { try decode(#"{"name": "ls", "type": "run", "argv": "ls"}"#) }
        #expect(throws: (any Error).self) { try decode(#"{"name": "x", "type": "prompt", "prompt": 5}"#) }
        // A later type without a name that's a string, or a type that isn't a string: errors too.
        #expect(throws: (any Error).self) { try decode(#"{"name": 5, "type": "hologram"}"#) }
        #expect(throws: (any Error).self) { try decode(#"{"type": "hologram"}"#) }
        #expect(throws: (any Error).self) { try decode(#"{"name": "x", "type": 7}"#) }
        #expect(throws: (any Error).self) { try decode(#"{"name": "x"}"#) }
        #expect(throws: (any Error).self) { try decode(#""just text""#) }
    }

    @Test func theirNamesAreTaken() throws {
        let config = try decode(#"{"name": "future", "type": "hologram"}"#)
        let mine = CustomCommand(name: "Future", type: .prompt, prompt: "Hi")
        #expect(mine.problem(among: config.customCommands, unread: config.unreadCustomCommandNames) == .nameTaken)
        #expect(mine.problem(among: config.customCommands) == nil)
        #expect(CustomCommand(name: "other", type: .prompt, prompt: "Hi").problem(among: [], unread: ["future"]) == nil)
    }

    @Test func iCloudChecksThemAsTheFileDoes() {
        typealias J = AIConfig.JSONValue
        let env = ICloudSync.Environment()
        func problem(_ entries: [J]) -> ICloudSync.Problem? {
            ICloudSync.problem(ICloudSync.commandsKey, .array(entries), environment: env)
        }
        let future = J.object(["name": .string("x"), "type": .string("hologram"), "beam": .number(1)])
        let prompt = J.object(["name": .string("X"), "type": .string("prompt"), "prompt": .string("y")])
        #expect(problem([future]) == nil)
        // A later type's name and a command of this version's: one name twice.
        #expect(problem([future, prompt]) == .invalidCommand)
        #expect(problem([future, future]) == .invalidCommand)
        // Not a later type's entry: as wrong as it always was.
        #expect(problem([.object(["name": .number(5), "type": .string("hologram")])]) == .wrongType)
        #expect(problem([.object(["type": .string("hologram")])]) == .wrongType)
        #expect(problem([.object(["name": .string("ls"), "type": .string("run"), "argv": .string("ls")])]) == .wrongType)
        #expect(problem([.string("x")]) == .wrongType)
    }
}

@Suite struct BundleSnippetProblemTests {
    private func load(_ manifest: String, script: Bool = false) -> ExtensionIndex {
        let folder = ScriptFolder()
        folder.add("t/extension.json", manifest)
        if script { folder.add("t/x.sh", "#!/bin/bash\necho x\n") }
        return folder.load()
    }

    @Test func aTextThatIsntAStringIsRefused() {
        let index = load(#"{"schemaVersion": 1, "name": "t", "snippets": [{"name": "a", "text": ["x", "y"]}, {"name": "n", "text": 42}, {"name": "b", "text": "ok"}]}"#)
        #expect(index.snippets.map(\.name) == ["b"])
        #expect(index.skipped.map(\.problem) == [.badValue(key: "text", value: #"["x","y"]"#), .badValue(key: "text", value: "42")])
        // Nothing usable at all: the bundle says so.
        let none = load(#"{"schemaVersion": 1, "name": "t", "snippets": [{"name": "a"}]}"#)
        #expect(none.snippets.isEmpty && none.skipped.map(\.problem) == [.missing("text")])
    }

    @Test func aBrokenListNextToSnippetsIsReported() {
        let index = load(#"{"schemaVersion": 1, "name": "t", "commands": "oops", "snippets": [{"name": "b", "text": "ok"}]}"#)
        #expect(index.bundles.map(\.name) == ["t"] && index.snippets.map(\.name) == ["b"])
        #expect(index.skipped.map(\.problem) == [.badValue(key: "commands", value: "oops")])
        let other = load(#"{"schemaVersion": 1, "name": "t", "commands": [{"script": "x.sh", "name": "x"}], "snippets": {"name": "b"}}"#, script: true)
        #expect(other.commands.map(\.name) == ["x"] && other.skipped.map(\.problem) == [.badValue(key: "snippets", value: #"{"name":"b"}"#)])
    }

    @Test func aClashNamesTheOtherOne() {
        let index = load(#"""
            {"schemaVersion": 1, "name": "t", "commands": [{"script": "x.sh", "name": "x"}],
             "snippets": [{"name": "x", "text": "a"}, {"name": "y", "text": "1"}, {"name": "y", "text": "2"}]}
            """#, script: true)
        #expect(index.snippets.map(\.text) == ["1"])
        #expect(index.skipped.map(\.problem) == [.nameTaken("x", by: .command("t/x")), .nameTaken("y", by: .snippet("t/y"))])
    }
}

import Foundation
import Testing
@testable import AllInOneIMECore

// Acceptance tests for "`@claude` becomes `@agent`" (0.6.5/agent), written from the spec only, independently of the
// implementation's own tests. Each test names the spec point it checks ("s2" = point 2; "edge" = a case the spec
// implies). What the input controller does (it lives in the app target, which these tests can't load) is played as the
// spec says it does: `composer.claudeInBackground = config.claudeInBackground && config.agent == .claude`, and
// `aiRefusal` / `secureInputActive` as the per-app and secure-input rules set them. Points 3, 4's Terminal side, 7 and
// 10 are app-target behaviour (the prompt file, the installed-program check, palette text, Settings) and are only
// checked here as far as `AllInOneIMECore` carries them.

struct AgentAcceptanceTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)

    static let refusal = "AI is off in this app"

    // MARK: Helpers

    /// A text field as the controller sets it up for `config`: English typed, `commands` offered, background only for
    /// Claude Code.
    func field(_ config: Config = .default, commands: [Command] = Command.builtins, secureInput: Bool = false,
               aiOff: Bool = false) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.commands = commands
        c.inputLanguages = [.chinese, .english]
        c.setInputMode(.english)
        c.claudeInBackground = config.claudeInBackground && config.agent == .claude
        c.secureInputActive = { secureInput }
        c.aiRefusal = { aiOff ? Self.refusal : nil }
        return c
    }

    func typeKeys(_ text: String, _ c: Composer) {
        for ch in text { _ = c.handleKeyDown(ch == "@" ? at : ch == " " ? spaceKey : k(String(ch))) }
    }

    /// Types `text` and presses ⏎: the effects of the ⏎.
    func run(_ text: String, _ c: Composer) -> [Composer.Effect] {
        typeKeys(text, c)
        return c.handleKeyDown(enterKey).effects
    }

    func terminal(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .runInTerminal(prompt) = $0 { return prompt } else { return nil } }
    }

    func background(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .startBackgroundAgent(prompt) = $0 { return prompt } else { return nil } }
    }

    func launched(_ effects: [Composer.Effect]) -> [[String]] {
        effects.compactMap { if case let .launchInTerminal(argv) = $0 { return argv } else { return nil } }
    }

    func notices(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .notice(s) = $0 { return s } else { return nil } }
    }

    /// Whether `effects` start anything: a model request, a Terminal window, a background session, a program.
    func startsAnything(_ effects: [Composer.Effect]) -> Bool {
        effects.contains { effect in
            switch effect {
            case .startConversion, .startCommand, .startPlan, .runInTerminal, .startBackgroundAgent, .launchInTerminal:
                return true
            default: return false
            }
        }
    }

    /// Text put into the field (an empty commit is nothing inserted).
    func inserted(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { effect in
            switch effect {
            case let .commit(s), let .typeOut(s): return s.isEmpty ? Optional<String>.none : s
            case let .replaceSelection(s, _): return s
            default: return Optional<String>.none
            }
        }
    }

    func decode(_ json: String) throws -> Config {
        try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    }

    func encodeObject(_ config: Config) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try #require(JSONSerialization.jsonObject(with: encoder.encode(config)) as? [String: Any])
    }

    func config(_ agent: AgentKind, _ command: [String] = [], background: Bool = true) -> Config {
        var config = Config.default
        config.agent = agent
        config.agentCommand = command
        config.claudeInBackground = background
        return config
    }

    // MARK: 1. The built-in is @agent; @claude is not a built-in

    @Test func s1_agentIsABuiltInTerminalCommandAndClaudeIsNot() {
        #expect(Command.agent.name == "agent")
        #expect(Command.agent.kind == .terminal)
        #expect(Command.agent.custom == nil && Command.agent.plugin == nil && Command.agent.script == nil)
        #expect(Command.builtins.filter { $0.name == "agent" } == [.agent])
        #expect(!Command.builtins.contains { $0.name == "claude" })
        // Offered in the catalog, no command named "claude" there without the user's own.
        let catalog = Command.catalog([])
        #expect(catalog.contains(.agent))
        #expect(!catalog.contains { $0.name == "claude" })
        // Still sends text to an agent: an AI command.
        #expect(Command.agent.usesAI)
    }

    @Test func s1_parseAndMatching() throws {
        let parsed = try #require(Command.parse("@agent fix the bug"))
        #expect(parsed.command == .agent && parsed.content == "fix the bug")
        let upper = try #require(Command.parse("@Agent fix the bug"))
        #expect(upper.command == .agent)
        #expect(Command.parse("@claude fix the bug") == nil)
        #expect(Command.parse("@claude fix the bug", in: Command.catalog([])) == nil)
        #expect(Command.matching("ag").contains(.agent))
        #expect(Command.matching("cl").isEmpty || !Command.matching("cl").contains { $0.name == "claude" })
        #expect(!Command.matching("claude").contains { $0.name == "claude" })
    }

    @Test func s1_paletteListsAgentAndNoClaude() {
        let catalog = Command.catalog([])
        #expect(Command.palette("agent", in: catalog, usage: CommandUsage()).first == .agent)
        #expect(Command.palette("ag", in: catalog, usage: CommandUsage()).first == .agent)
        #expect(!Command.palette("claude", in: catalog, usage: CommandUsage()).contains { $0.name == "claude" })
        #expect(!Command.palette("cla", in: catalog, usage: CommandUsage()).contains { $0.name == "claude" })
        // Nothing typed: @agent is among the commands, in the catalog's order (no use yet).
        let all = Command.palette("", in: catalog, usage: CommandUsage(), limit: catalog.count)
        #expect(all == catalog)
    }

    /// Types `text` into a field and presses ⏎, as the app sees it: what ends up in the field (text committed, and
    /// keys the composer passes on to the app), the draft left, and every effect.
    func typeIntoField(_ text: String, _ c: Composer) -> (field: String, effects: [Composer.Effect]) {
        var field = "", effects: [Composer.Effect] = []
        for ch in text {
            let response = c.handleKeyDown(ch == "@" ? at : ch == " " ? spaceKey : k(String(ch)))
            effects += response.effects
            field += inserted(response.effects).joined()
            if !response.handled { field.append(ch) }
        }
        let enter = c.handleKeyDown(enterKey)
        effects += enter.effects
        field += inserted(enter.effects).joined()
        return (field + c.draft, effects)
    }

    @Test func s1_typedClaudeIsPlainText() {
        // Like any word after "@" that isn't a command: nothing starts, the text is the user's, as typed.
        let typed = typeIntoField("@claude fix the bug", field())
        #expect(!startsAnything(typed.effects), "\(typed.effects)")
        #expect(typed.field == "@claude fix the bug", "\(typed.effects)")
        let unknown = typeIntoField("@zzqx fix the bug", field())
        #expect(!startsAnything(unknown.effects))
        #expect(unknown.field == "@zzqx fix the bug")
        #expect(notices(typed.effects).allSatisfy { !$0.contains("Claude Code") }, "\(typed.effects)")
    }

    @Test func s1_typedClaudeIsPlainTextEvenWithAIOffOrSecureInput() {
        // Not an AI command any more: the per-app "no AI" rule doesn't refuse it, nor does secure input hold it.
        let off = typeIntoField("@claude fix the bug", field(aiOff: true))
        #expect(!notices(off.effects).contains(Self.refusal), "\(off.effects)")
        #expect(!startsAnything(off.effects) && off.field == "@claude fix the bug")
        let secure = typeIntoField("@claude fix the bug", field(secureInput: true))
        #expect(!startsAnything(secure.effects) && secure.field == "@claude fix the bug", "\(secure.effects)")
    }

    @Test func s1_aCustomCommandNamedClaudeIsAllowedAndRuns() throws {
        let mine = CustomCommand(name: "claude", type: .prompt, prompt: "Answer like a pirate.")
        #expect(mine.problem(among: []) == nil)
        let catalog = Command.catalog([mine])
        let command = try #require(catalog.first { $0.name == "claude" })
        #expect(command.custom == mine && command.kind == .generate)
        let parsed = try #require(Command.parse("@claude hello", in: catalog))
        #expect(parsed.command == command && parsed.content == "hello")
        // Typed, it is that command, not the agent.
        let c = field(commands: catalog)
        let effects = run("@claude hello", c)
        #expect(terminal(effects).isEmpty && background(effects).isEmpty, "\(effects)")
        #expect(effects.contains { if case .startCommand = $0 { return true } else { return false } }, "\(effects)")

        // A custom terminal command named "claude" runs its own argv.
        let term = CustomCommand(name: "claude", type: .terminal, argv: ["claude", "-p", CustomCommand.placeholder])
        #expect(term.problem(among: []) == nil)
        let termCatalog = Command.catalog([term])
        let tc = field(commands: termCatalog)
        let termEffects = run("@claude fix", tc)
        #expect(launched(termEffects) == [term.arguments(for: "fix")], "\(termEffects)")
        #expect(terminal(termEffects).isEmpty && background(termEffects).isEmpty)
    }

    @Test func s1_aCustomCommandNamedAgentIsTakenAndHidden() {
        let mine = CustomCommand(name: "agent", type: .prompt, prompt: "Something else.")
        #expect(mine.problem(among: []) == .nameTaken)
        #expect(CustomCommand(name: "Agent", type: .prompt, prompt: "x").problem(among: []) == .nameTaken)
        let catalog = Command.catalog([mine])
        #expect(catalog.filter { $0.name == "agent" } == [.agent])
    }

    // MARK: 2. The agents

    @Test func s2_theFourKinds() {
        #expect(AgentKind.allCases == [.claude, .gemini, .kiro, .custom])
        #expect(AgentKind.allCases.map(\.rawValue) == ["claude", "gemini", "kiro", "custom"])
    }

    @Test func s2_namesShown() {
        #expect(AgentKind.claude.displayName() == "Claude Code")
        #expect(AgentKind.gemini.displayName() == "Gemini CLI")
        #expect(AgentKind.kiro.displayName() == "Kiro CLI")
        #expect(AgentKind.custom.displayName(custom: ["muse", "--"]) == "muse")
        #expect(AgentKind.custom.displayName(custom: ["/opt/homebrew/bin/muse", "--"]) == "muse")
        #expect(AgentKind.custom.displayName(custom: ["~/bin/my-agent"]) == "my-agent")
        // The built-in agents' names don't depend on a custom command.
        #expect(AgentKind.gemini.displayName(custom: ["muse", "--"]) == "Gemini CLI")
        #expect(AgentKind.claude.displayName(custom: ["muse"]) == "Claude Code")
        // No custom command: still a name to show (Settings lists the kind).
        #expect(!AgentKind.custom.displayName().isEmpty)
        #expect(!AgentKind.custom.displayName(custom: []).isEmpty)
    }

    @Test func s2_programs() {
        #expect(AgentKind.claude.program() == "claude")
        #expect(AgentKind.gemini.program() == "gemini")
        #expect(AgentKind.kiro.program() == "kiro-cli")
        #expect(AgentKind.custom.program(custom: ["muse", "--"]) == "muse")
        #expect(AgentKind.custom.program(custom: ["/opt/homebrew/bin/muse", "--"]) == "/opt/homebrew/bin/muse")
        #expect(AgentKind.kiro.program(custom: ["muse"]) == "kiro-cli")
        // Empty, or a blank first word: no custom agent.
        #expect(AgentKind.custom.program() == nil)
        #expect(AgentKind.custom.program(custom: []) == nil)
        #expect(AgentKind.custom.program(custom: [""]) == nil)
        #expect(AgentKind.custom.program(custom: ["   ", "--"]) == nil)
    }

    @Test func s2_terminalArgumentsWithoutThePrompt() {
        #expect(AgentKind.claude.terminalArguments() == ["claude", "--"])
        #expect(AgentKind.gemini.terminalArguments() == ["gemini", "--"])
        #expect(AgentKind.kiro.terminalArguments() == ["kiro-cli", "chat", "--"])
        #expect(AgentKind.custom.terminalArguments(custom: ["muse", "--"]) == ["muse", "--"])
        // As is: nothing added, nothing taken away.
        #expect(AgentKind.custom.terminalArguments(custom: ["muse"]) == ["muse"])
        #expect(AgentKind.custom.terminalArguments(custom: ["/usr/local/bin/aider", "--yes", "--message"])
                == ["/usr/local/bin/aider", "--yes", "--message"])
        #expect(AgentKind.gemini.terminalArguments(custom: ["muse", "--"]) == ["gemini", "--"])
        // Nothing to run.
        #expect(AgentKind.custom.terminalArguments() == nil)
        #expect(AgentKind.custom.terminalArguments(custom: []) == nil)
        #expect(AgentKind.custom.terminalArguments(custom: ["", "--"]) == nil)
        #expect(AgentKind.custom.terminalArguments(custom: [" \t", "--"]) == nil)
    }

    @Test func s2_onlyClaudeCodeRunsInTheBackground() {
        #expect(AgentKind.claude.supportsBackground)
        #expect(!AgentKind.gemini.supportsBackground)
        #expect(!AgentKind.kiro.supportsBackground)
        #expect(!AgentKind.custom.supportsBackground)
    }

    @Test func s2_defaults() throws {
        #expect(Config.default.agent == .claude)
        #expect(Config.default.agentCommand == [])
        let empty = try decode("{}")
        #expect(empty.agent == .claude && empty.agentCommand == [])
    }

    @Test func s2_decodesEveryKind() throws {
        #expect(try decode(#"{"agent":"claude"}"#).agent == .claude)
        #expect(try decode(#"{"agent":"gemini"}"#).agent == .gemini)
        #expect(try decode(#"{"agent":"kiro"}"#).agent == .kiro)
        let custom = try decode(#"{"agent":"custom","agentCommand":["muse","--"]}"#)
        #expect(custom.agent == .custom && custom.agentCommand == ["muse", "--"])
        // The command alone doesn't pick the custom agent.
        let commandOnly = try decode(#"{"agentCommand":["muse","--"]}"#)
        #expect(commandOnly.agent == .claude && commandOnly.agentCommand == ["muse", "--"])
    }

    @Test func s2_unknownKindIsClaudeCodeAndTheRestStillReads() throws {
        for value in [#""martian""#, #""Claude""#, #""""#, "null"] {
            let config = try decode(#"{"agent":\#(value),"maxTokens":900,"claudeInBackground":false}"#)
            #expect(config.agent == .claude, "\(value)")
            #expect(config.maxTokens == 900 && !config.claudeInBackground, "\(value)")
            #expect(try encodeObject(config)["agent"] as? String == "claude", "\(value)")
        }
    }

    @Test func s2_bothKeysAreWrittenBack() throws {
        let defaults = try encodeObject(.default)
        #expect(defaults["agent"] as? String == "claude")
        #expect(defaults["agentCommand"] as? [String] == [])
        let old = try encodeObject(decode(#"{"maxTokens":900}"#))
        #expect(old["agent"] as? String == "claude" && old["agentCommand"] as? [String] == [])
        for kind in AgentKind.allCases {
            let object = try encodeObject(config(kind, ["muse", "--"]))
            #expect(object["agent"] as? String == kind.rawValue)
            #expect(object["agentCommand"] as? [String] == ["muse", "--"])
        }
        // Exact bytes of the two keys.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let text = String(decoding: try encoder.encode(config(.custom, ["/opt/bin/muse", "--"])), as: UTF8.self)
        #expect(text.contains(#""agent":"custom","agentCommand":["/opt/bin/muse","--"]"#), "\(text)")
    }

    @Test func s2_roundTrips() throws {
        for kind in AgentKind.allCases {
            for command in [[], ["muse", "--"], ["/Applications/My Agent.app/Contents/MacOS/agent", "--prompt"]] {
                let original = config(kind, command, background: false)
                let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(original))
                #expect(back.agent == kind && back.agentCommand == command && !back.claudeInBackground)
                #expect(back == original)
            }
        }
    }

    // MARK: 3. The prompt: the last argument, any length

    @Test func s3_thePromptGoesWholeAndAsTyped() {
        let long = String(repeating: "refactor the parser and keep the tests green ", count: 60)
            .trimmingCharacters(in: .whitespaces)
        for prompt in [long, "-rf everything", "fix \"quotes\" and $HOME and `ticks`; rm -rf /"] {
            let c = field(config(.gemini))
            let effects = run("@agent " + prompt, c)
            #expect(terminal(effects) == [prompt], "\(prompt.prefix(20)): \(effects)")
        }
    }

    @Test func s3_theBuiltInAgentsEndWithDoubleDash() {
        // The prompt comes last, after "--": a prompt starting with "-" stays the prompt.
        for kind in [AgentKind.claude, .gemini, .kiro] {
            #expect(kind.terminalArguments()?.last == "--", "\(kind)")
        }
    }

    // MARK: 4. Offered only when the agent's program is installed

    @Test func s4_theProgramAgentNeedsIsTheChosenAgents() {
        for kind in [AgentKind.claude, .gemini, .kiro] {
            #expect(Command.agent.program(agent: kind) == kind.program(), "\(kind)")
        }
        #expect(Command.agent.program(agent: .gemini) == "gemini")
        #expect(Command.agent.program(agent: .kiro) == "kiro-cli")
        #expect(Command.agent.program(agent: .custom, custom: ["muse", "--"]) == "muse")
        // The default (no agent given) is Claude Code's.
        #expect(Command.agent.program == "claude")
        // A custom agent without a command needs a program it can't have.
        #expect(AgentKind.custom.program(custom: []) == nil && AgentKind.custom.terminalArguments(custom: []) == nil)
        // Other commands' programs don't depend on the agent.
        #expect(Command.py.program(agent: .gemini) == Command.py.program)
        #expect(Command.question.program(agent: .kiro) == nil)
    }

    // MARK: 5. Background only with Claude Code

    @Test func s5_claudeCodeInTheBackground() {
        let c = field(config(.claude, background: true))
        let effects = run("@agent fix the bug", c)
        #expect(background(effects) == ["fix the bug"], "\(effects)")
        #expect(terminal(effects).isEmpty)
        #expect(inserted(effects).isEmpty)
    }

    @Test func s5_claudeCodeInTerminalWithBackgroundOff() {
        let c = field(config(.claude, background: false))
        let effects = run("@agent fix the bug", c)
        #expect(terminal(effects) == ["fix the bug"], "\(effects)")
        #expect(background(effects).isEmpty)
        #expect(inserted(effects).isEmpty)
    }

    @Test(arguments: [AgentKind.gemini, .kiro, .custom])
    func s5_otherAgentsAlwaysOpenTerminal(_ kind: AgentKind) {
        for on in [true, false] {
            let c = field(config(kind, ["muse", "--"], background: on))
            #expect(!c.claudeInBackground)
            let effects = run("@agent fix the bug", c)
            #expect(terminal(effects) == ["fix the bug"], "\(kind) \(on): \(effects)")
            #expect(background(effects).isEmpty && launched(effects).isEmpty)
            #expect(inserted(effects).isEmpty)
        }
    }

    @Test func s5_theBackgroundSettingStaysWithItsKey() throws {
        #expect(Config.default.claudeInBackground)
        let picked = try decode(#"{"agent":"gemini","claudeInBackground":true}"#)
        #expect(picked.agent == .gemini && picked.claudeInBackground)
        let object = try encodeObject(picked)
        #expect(object["claudeInBackground"] as? Bool == true)
        #expect(try decode(#"{"agent":"kiro","claudeInBackground":false}"#).claudeInBackground == false)
    }

    // MARK: 6. @tasks unchanged; text says "@agent"

    @Test func s6_tasksIsUnchanged() {
        #expect(Command.tasks.name == "tasks" && Command.tasks.kind == .agents)
        #expect(Command.builtins.contains(.tasks))
        let c = field()
        let effects = run("@tasks ", c)
        #expect(effects.contains { if case .listAgents = $0 { return true } else { return false } }, "\(effects)")
    }

    @Test func s6_theComposersTextSaysAgentNotClaude() {
        for messages in [Composer.Messages.chinese, Composer.Messages.english] {
            let text = String(describing: messages)
            #expect(!text.contains("@claude"), "\(text)")
        }
    }

    // MARK: 8. Unchanged rules

    @Test(arguments: [AgentKind.claude, .gemini, .kiro, .custom])
    func s8_refusedDuringSecureInput(_ kind: AgentKind) {
        for on in [true, false] {
            let c = field(config(kind, ["muse", "--"], background: on), secureInput: true)
            let effects = run("@agent fix the bug", c)
            #expect(!startsAnything(effects), "\(kind) \(on): \(effects)")
            #expect(!notices(effects).isEmpty, "\(kind): no notice")
            #expect(inserted(effects).isEmpty, "\(kind): \(effects)")
        }
    }

    @Test(arguments: [AgentKind.claude, .gemini, .kiro, .custom])
    func s8_refusedInAnAppWithAIOff(_ kind: AgentKind) {
        for on in [true, false] {
            let c = field(config(kind, ["muse", "--"], background: on), aiOff: true)
            let effects = run("@agent fix the bug", c)
            #expect(!startsAnything(effects), "\(kind) \(on): \(effects)")
            #expect(notices(effects).contains(Self.refusal), "\(kind): \(effects)")
            #expect(inserted(effects).isEmpty)
            #expect(c.draft == "@agent fix the bug")
        }
    }

    @Test func s8_nothingTypedAfterAgentStartsNothing() {
        let c = field()
        let effects = run("@agent ", c)
        #expect(!startsAnything(effects), "\(effects)")
    }

    // MARK: 9. Command usage moves from "claude" to "agent", once

    @Test func s9_theScoreMoves() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var usage = CommandUsage()
        for _ in 0..<3 { usage.record("claude", now: now) }
        usage.record("note", now: now)
        let before = usage.score("claude", now: now)
        #expect(before > 2.9)
        usage.migrateRenamed(from: "claude", to: "agent")
        #expect(abs(usage.score("agent", now: now) - before) < 1e-9)
        #expect(usage.score("claude", now: now) == 0)
        #expect(abs(usage.score("note", now: now) - 1) < 1e-9)
    }

    @Test func s9_onlyOnce() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var usage = CommandUsage()
        for _ in 0..<3 { usage.record("claude", now: now) }
        usage.migrateRenamed(from: "claude", to: "agent")
        let moved = usage.score("agent", now: now)
        usage.migrateRenamed(from: "claude", to: "agent")
        usage.migrateRenamed(from: "claude", to: "agent")
        #expect(abs(usage.score("agent", now: now) - moved) < 1e-9, "the score was moved more than once")
        // Nothing to move: nothing changes.
        var none = CommandUsage()
        none.record("note", now: now)
        let copy = none
        none.migrateRenamed(from: "claude", to: "agent")
        #expect(none == copy)
    }

    @Test func s9_thePaletteOrderStaysAsItWas() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // As 0.6.4 kept it: @claude used most, then @note, then @translate.
        var usage = CommandUsage()
        for _ in 0..<5 { usage.record("claude", now: now) }
        for _ in 0..<3 { usage.record("note", now: now) }
        usage.record("translate", now: now)
        // Kept across the update (the stored form), then migrated.
        var stored = (try? JSONDecoder().decode(CommandUsage.self, from: JSONEncoder().encode(usage))) ?? CommandUsage()
        #expect(stored == usage)
        stored.migrateRenamed(from: "claude", to: "agent")
        let catalog = Command.catalog([])
        let top = Command.palette("", in: catalog, usage: stored, now: now)
        #expect(Array(top.prefix(3)) == [.agent, .note, .translate], "\(top.map(\.name))")
        // Without the move, @agent would have lost its place.
        let unmoved = Command.palette("", in: catalog, usage: usage, now: now)
        #expect(unmoved.first == .note)
    }
}

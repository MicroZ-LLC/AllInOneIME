import Foundation
import Testing
@testable import AllInOneIMECore

// Acceptance tests for "@config and @doctor move into Settings" (0.6.5/settings-assistant), written from the spec only,
// independently of the implementation's own tests. They cover the core side of it ("Removing the commands"):
//
//   r1  `config` and `doctor` are no longer built-in commands: not in `Command.builtins` or the catalog, not found by
//       name (`parse`, `matching`, `palette`), not offered when "@" is typed.
//   r2  Nothing else is removed: the other built-ins are still there, in the same order, and still run.
//   r3  Typing `@config …` or `@doctor` (with no command of that name of the user's own) behaves like any other unknown
//       name: compared with `@zzqx` through the same composer, and through `CommandPlan` inside a text.
//   r4  The names are free: a custom command named `config` or `doctor` is valid (`CustomCommand.problem(among:)` is
//       nil) and is offered and runs like any custom command; so does a plugin or a script extension of that name.
//   r5  Core text that told the user to type `@config` or `@doctor` no longer does (it points to Settings → Assistant).
//
// The tests never name `Command.config`, `Command.doctor` or their kinds: those are gone after the change, so the
// commands are only ever looked up by name. The Settings page itself (app target) is checked by the self-tests.

struct SettingsAssistantAcceptanceTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)

    static let removed = ["config", "doctor"]
    /// A name nothing has: what an unknown command does.
    static let unknown = "zzqx"
    /// The built-ins before the change, in order (0.6.5/calculator's `Command.builtins`).
    static let before = ["improve", "translate", "question", "agent", "open", "read", "note", "reminder", "py", "js", "search",
                         "tasks", "settings", "config", "doctor", "imessage", "reportissue"]
    static let refusal = "AI is off in this app"

    // MARK: Helpers

    /// A text field as the controller sets it up: English typed, `commands` offered, ⏎ runs.
    func field(commands: [Command] = Command.catalog([]), aiOff: Bool = false) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.commands = commands
        c.inputLanguages = [.chinese, .english]
        c.setInputMode(.english)
        c.aiRefusal = { aiOff ? Self.refusal : nil }
        return c
    }

    func key(_ ch: Character) -> KeyEvent { ch == "@" ? at : ch == " " ? spaceKey : k(String(ch)) }

    /// Types `text` into a field and presses ⏎, as the app sees it: what ends up in the field (text committed, and keys
    /// the composer passes on to the app, then the draft left), every effect, and the ⏎'s own response.
    func typeIntoField(_ text: String, _ c: Composer) -> (field: String, effects: [Composer.Effect], enter: Composer.Response) {
        var field = "", effects: [Composer.Effect] = []
        for ch in text {
            let response = c.handleKeyDown(key(ch))
            effects += response.effects
            field += inserted(response.effects).joined()
            if !response.handled { field.append(ch) }
        }
        let enter = c.handleKeyDown(enterKey)
        effects += enter.effects
        field += inserted(enter.effects).joined()
        return (field + c.draft, effects, enter)
    }

    /// Types `text` and presses ⏎: the effects of the ⏎.
    func run(_ text: String, _ c: Composer) -> [Composer.Effect] {
        for ch in text { _ = c.handleKeyDown(key(ch)) }
        return c.handleKeyDown(enterKey).effects
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

    func notices(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .notice(s) = $0 { return s } else { return nil } }
    }

    /// Whether `effects` start anything: a model request, a command, a program, a Terminal window, a plan.
    func startsAnything(_ effects: [Composer.Effect]) -> Bool {
        effects.contains { effect in
            switch effect {
            case .startConversion, .startCommand, .startPlan, .startRun, .startScript, .startBackgroundScript, .runInTerminal,
                 .startBackgroundAgent, .launchInTerminal:
                return true
            default:
                // Whatever @config / @doctor had of their own (applying or undoing settings, a preview of fixes), by name:
                // those effects may not exist any more.
                let name = String(describing: effect)
                return name.contains("Config") || name.contains("Fixes")
            }
        }
    }

    /// `effects` with the command's name written as a placeholder, to compare one name's effects with another's.
    func normalized(_ effects: [Composer.Effect], _ name: String) -> [String] {
        effects.map { String(describing: $0).replacingOccurrences(of: name, with: "NAME") }
    }

    /// What typing `@<name><rest>` and ⏎ does in a fresh field, with the name as a placeholder.
    func behaviour(_ name: String, _ rest: String, commands: [Command] = Command.catalog([]), aiOff: Bool = false)
        -> (field: String, enter: [String], handled: Bool, draft: String, phase: String, panel: Bool) {
        let c = field(commands: commands, aiOff: aiOff)
        let typed = typeIntoField("@" + name + rest, c)
        return (typed.field.replacingOccurrences(of: name, with: "NAME"), normalized(typed.enter.effects, name),
                typed.enter.handled, c.draft.replacingOccurrences(of: name, with: "NAME"), "\(c.phase)", c.wantsPanel)
    }

    // MARK: r1. Not built-in any more

    @Test func r1_configAndDoctorAreNotBuiltIns() {
        for name in Self.removed {
            #expect(!Command.builtins.contains { $0.name == name }, "@\(name) is still a built-in")
            #expect(!Command.catalog([]).contains { $0.name == name }, "@\(name) is still offered")
            #expect(!Command.off.contains { $0.name == name })
            // No built-in kind of theirs is left either (looked at by name: the cases are gone).
            #expect(!Command.builtins.contains { "\($0.kind)" == name }, "a built-in still has the kind .\(name)")
        }
    }

    @Test func r1_lookupsByNameFindNothing() {
        let catalog = Command.catalog([])
        for name in Self.removed {
            #expect(Command.parse("@\(name) output languages English and French") == nil, "@\(name)")
            #expect(Command.parse("@\(name) x", in: catalog) == nil, "@\(name)")
            #expect(Command.parse("@\(name.uppercased()) x", in: catalog) == nil, "@\(name)")
            #expect(!Command.matching(name).contains { $0.name == name }, "@\(name)")
            #expect(!Command.matching(String(name.prefix(3)), in: catalog).contains { $0.name == name }, "@\(name)")
            #expect(Command.palette(name, in: catalog, usage: CommandUsage()).isEmpty, "@\(name)")
            #expect(!Command.palette(String(name.prefix(2)), in: catalog, usage: CommandUsage(), limit: 100)
                .contains { $0.name == name }, "@\(name)")
            // As an unknown name is: `@zzqx` finds nothing the same way.
            #expect(Command.palette(Self.unknown, in: catalog, usage: CommandUsage()).isEmpty)
        }
        // Nothing typed: the whole list has neither.
        let all = Command.palette("", in: catalog, usage: CommandUsage(), limit: 100)
        #expect(!all.contains { Self.removed.contains($0.name) })
    }

    @Test func r1_typingAtDoesNotOfferThem() {
        let c = field()
        _ = c.handleKeyDown(at)
        #expect(!c.paletteMatches.contains { Self.removed.contains($0.name) })
        for name in Self.removed {
            for length in 1...name.count {
                let d = field()
                for ch in "@" + name.prefix(length) { _ = d.handleKeyDown(key(ch)) }
                #expect(!d.paletteMatches.contains { $0.name == name }, "\"@\(name.prefix(length))\" offers @\(name)")
            }
        }
    }

    @Test func r1_usageKeptFromBeforeBringsNeitherBack() {
        // Someone who ran @config and @doctor a lot before updating: the kept usage names them, the list doesn't.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var usage = CommandUsage()
        for _ in 0..<9 {
            usage.record("config", now: now)
            usage.record("doctor", now: now)
        }
        let catalog = Command.catalog([])
        let first = Command.palette("", in: catalog, usage: usage, now: now)
        #expect(!first.contains { Self.removed.contains($0.name) })
        #expect(first.map(\.name) == ["improve", "translate", "question", "agent", "open"])
    }

    // MARK: r2. Nothing else removed

    @Test func r2_theOtherBuiltInsStayInOrder() {
        let names = Command.builtins.map(\.name)
        let kept = Self.before.filter { !Self.removed.contains($0) }
        // Every other built-in is still there, in the order it had.
        #expect(names.filter { kept.contains($0) } == kept, "\(names)")
        for name in kept {
            #expect(Command.builtins.filter { $0.name == name }.count == 1, "@\(name)")
        }
        #expect(Command.builtins.contains(.improve) && Command.builtins.contains(.translate) && Command.builtins.contains(.question))
        #expect(Command.builtins.contains(.agent) && Command.builtins.contains(.open) && Command.builtins.contains(.settings))
        #expect(Command.builtins.contains(.py) && Command.builtins.contains(.js) && Command.builtins.contains(.note))
        #expect(Command.builtins.contains(.reminder) && Command.builtins.contains(.tasks) && Command.builtins.contains(.imessage))
        #expect(Command.builtins.contains(.reportIssue))
        // The catalog offers what it did, less the two.
        let catalog = Command.catalog([]).map(\.name)
        let offeredBefore = Self.before.filter { $0 != "read" && $0 != "search" }
        #expect(catalog.filter { offeredBefore.contains($0) } == offeredBefore.filter { !Self.removed.contains($0) }, "\(catalog)")
        // Their names are still taken.
        for name in ["improve", "translate", "question", "py", "settings", "note"] {
            #expect(CustomCommand(name: name, type: .prompt, prompt: "x").problem(among: []) == .nameTaken, "@\(name)")
        }
    }

    @Test func r2_theOtherBuiltInsStillParseAndRun() throws {
        let catalog = Command.catalog([])
        for (typed, command, content) in [("@translate 你好", Command.translate, "你好"), ("@improve hi there", .improve, "hi there"),
                                          ("@question what is it", .question, "what is it"), ("@py 2**10", .py, "2**10"),
                                          ("@settings x", .settings, "x"), ("@agent fix it", .agent, "fix it")] {
            let parsed = try #require(Command.parse(typed, in: catalog), "\(typed)")
            #expect(parsed.command == command && parsed.content == content, "\(typed)")
        }
        // Typed into a field, they still start what they did.
        let question = run("@question what is it", field())
        #expect(question.contains { if case let .startCommand(c, input, _) = $0 { return c == .question && input == "what is it" }
                                    else { return false } }, "\(question)")
        let py = run("@py 23*17", field())
        #expect(py.first == .startRun(.py, input: "23*17", id: 1), "\(py)")
        // @settings is still the command that opens Settings (where the Assistant page now is).
        #expect(Command.settings.name == "settings" && Command.settings.kind == .settings)
    }

    // MARK: r3. Typed, they are unknown names

    @Test func r3_typedWithTextTheyAreLikeAnUnknownName() {
        let control = behaviour(Self.unknown, " output languages English and French")
        // The control itself: an unknown name starts nothing and leaves the text as typed.
        #expect(control.field == "@NAME output languages English and French")
        for name in Self.removed {
            let c = field()
            let typed = typeIntoField("@\(name) output languages English and French", c)
            #expect(!startsAnything(typed.effects), "@\(name): \(typed.effects)")
            #expect(typed.field == "@\(name) output languages English and French", "@\(name): \(typed.effects)")
            let seen = behaviour(name, " output languages English and French")
            #expect(seen.field == control.field, "@\(name)")
            #expect(seen.enter == control.enter, "@\(name)")
            #expect(seen.handled == control.handled && seen.draft == control.draft, "@\(name)")
            #expect(seen.phase == control.phase && seen.panel == control.panel, "@\(name)")
        }
    }

    @Test func r3_typedAloneTheyAreLikeAnUnknownName() {
        // "@doctor" and ⏎ used to run the checks; "@config" and ⏎ did nothing (it waited for a request).
        let control = behaviour(Self.unknown, "")
        for name in Self.removed {
            let c = field()
            let typed = typeIntoField("@\(name)", c)
            #expect(!startsAnything(typed.effects), "@\(name): \(typed.effects)")
            let seen = behaviour(name, "")
            #expect(seen.field == control.field && seen.enter == control.enter && seen.handled == control.handled, "@\(name)")
            #expect(seen.draft == control.draft && seen.phase == control.phase && seen.panel == control.panel, "@\(name)")
            // With a space after it, too.
            let spaced = behaviour(name, " ")
            let spacedControl = behaviour(Self.unknown, " ")
            #expect(spaced.field == spacedControl.field && spaced.enter == spacedControl.enter, "@\(name) ")
        }
    }

    @Test func r3_configUndoIsJustText() {
        // "@config undo" put back the last changes; now it is text like any other.
        let c = field()
        let typed = typeIntoField("@config undo", c)
        #expect(!startsAnything(typed.effects), "\(typed.effects)")
        #expect(typed.field == "@config undo")
        let seen = behaviour("config", " undo"), control = behaviour(Self.unknown, " undo")
        #expect(seen.field == control.field && seen.enter == control.enter && seen.draft == control.draft)
    }

    @Test func r3_noAIRefusalForThem() {
        // In an app with AI off @config was refused with a notice; an unknown name is not an AI command, so it isn't.
        for name in Self.removed {
            let c = field(aiOff: true)
            let typed = typeIntoField("@\(name) use Apple Intelligence", c)
            #expect(!notices(typed.effects).contains(Self.refusal), "@\(name): \(typed.effects)")
            #expect(!startsAnything(typed.effects) && typed.field == "@\(name) use Apple Intelligence", "@\(name)")
            let seen = behaviour(name, " use Apple Intelligence", aiOff: true)
            let control = behaviour(Self.unknown, " use Apple Intelligence", aiOff: true)
            #expect(seen.field == control.field && seen.enter == control.enter, "@\(name)")
        }
    }

    @Test func r3_insideATextTheyStayText() {
        // In a text with commands inside it, `@config …` is text, as `@zzqx …` is.
        let catalog = Command.catalog([])
        for name in Self.removed {
            for text in ["总结一下 @\(name) abc", "@\(name) 「a b」 then @py 1+1", "x @\(name)"] {
                let plan = CommandPlan.make(text, commands: catalog)
                let control = CommandPlan.make(text.replacingOccurrences(of: name, with: Self.unknown), commands: catalog)
                #expect(!plan.inner.contains { $0.command.name == name }, "\(text)")
                #expect(plan.inner == control.inner, "\(text)")
                #expect(plan.input(outputs: plan.inner.map { _ in "OUT" })
                        == control.input(outputs: control.inner.map { _ in "OUT" }).replacingOccurrences(of: Self.unknown, with: name))
            }
        }
        // And after another command in the field: "@improve hello @doctor" improves the text as typed.
        let c = field()
        let effects = run("@improve hello @doctor", c)
        let control = run("@improve hello @\(Self.unknown)", field())
        #expect(normalized(effects, "doctor") == normalized(control, Self.unknown), "\(effects)")
    }

    // MARK: r4. The names are free

    @Test func r4_customCommandsMayBeNamedConfigOrDoctor() {
        for name in Self.removed {
            for definition in [CustomCommand(name: name, type: .prompt, prompt: "Answer briefly."),
                               CustomCommand(name: name, type: .run, argv: ["echo", CustomCommand.placeholder]),
                               CustomCommand(name: name, type: .terminal, argv: ["zsh", "-c", CustomCommand.placeholder]),
                               CustomCommand(name: name, type: .link, url: "https://example.com/search?q={input}"),
                               CustomCommand(name: name.capitalized, type: .prompt, prompt: "x")] {
                #expect(definition.isValid, "\(definition)")
                #expect(definition.problem(among: []) == nil, "\(definition)")
            }
            // As with any name: taken by another custom command or a plugin of that name.
            let mine = CustomCommand(name: name, type: .prompt, prompt: "x")
            #expect(mine.problem(among: [CustomCommand(name: name.uppercased(), type: .prompt, prompt: "y")]) == .nameTaken)
            #expect(mine.problem(among: [], plugins: [name]) == .nameTaken)
        }
        // The same as for a name that never was a built-in.
        #expect(CustomCommand(name: Self.unknown, type: .prompt, prompt: "x").problem(among: []) == nil)
    }

    @Test func r4_aCustomCommandNamedConfigIsOfferedAndRuns() throws {
        let mine = CustomCommand(name: "config", type: .prompt, prompt: "Answer in one line.")
        let catalog = Command.catalog([mine])
        // In the catalog, after the built-ins, as the user's own.
        let command = try #require(catalog.first { $0.name == "config" })
        #expect(catalog.filter { $0.name == "config" }.count == 1)
        #expect(command.custom == mine && command.kind == .generate && command.plugin == nil)
        #expect(catalog.last == command)
        // Found by name and offered in the list.
        let parsed = try #require(Command.parse("@config nginx for a static site", in: catalog))
        #expect(parsed.command == command && parsed.content == "nginx for a static site")
        #expect(Command.palette("config", in: catalog, usage: CommandUsage()).first == command)
        #expect(Command.palette("con", in: catalog, usage: CommandUsage()).contains(command))
        #expect(Command.matching("conf", in: catalog) == [command])
        // Its instruction goes to the model.
        #expect(Prompt.commandSystem(command).hasSuffix("Answer in one line."))
        // Typed, it is that command.
        let c = field(commands: catalog)
        _ = c.handleKeyDown(at)
        for ch in "con" { _ = c.handleKeyDown(key(ch)) }
        #expect(c.paletteMatches.contains(command))
        let effects = run("@config nginx", field(commands: catalog))
        #expect(effects.contains { if case let .startCommand(c, input, _) = $0 { return c == command && input == "nginx" }
                                   else { return false } }, "\(effects)")
        // As any custom prompt command does.
        let other = CustomCommand(name: "yaml", type: .prompt, prompt: "Answer in one line.")
        let otherCatalog = Command.catalog([other])
        let otherEffects = run("@yaml nginx", field(commands: otherCatalog))
        #expect(normalized(effects, "config") == normalized(otherEffects, "yaml"), "\(effects) vs \(otherEffects)")
    }

    @Test func r4_aCustomRunCommandNamedDoctorRuns() throws {
        let mine = CustomCommand(name: "doctor", type: .run, argv: ["brew", "doctor", CustomCommand.placeholder])
        let catalog = Command.catalog([mine])
        let command = try #require(catalog.first { $0.name == "doctor" })
        #expect(command.custom == mine && command.kind == .run)
        #expect(command.program == "brew")
        #expect(Command.palette("doctor", in: catalog, usage: CommandUsage()).first == command)
        let effects = run("@doctor verbose", field(commands: catalog))
        #expect(effects.first == .startRun(command, input: "verbose", id: 1), "\(effects)")
        // Inside a text it runs first, like any custom run command typed there.
        let plan = CommandPlan.make("看看 @doctor verbose 的结果", commands: catalog)
        #expect(plan.inner.map(\.command) == [command] && plan.inner.first?.argument == "verbose")
        // Without the custom command, the same text has nothing to run.
        #expect(CommandPlan.make("看看 @doctor verbose 的结果", commands: Command.catalog([])).isEmpty)
    }

    @Test func r4_pluginsNamedConfigOrDoctorAreAllowed() throws {
        let config = InstalledPlugin(manifest: PluginManifest(name: "config", version: "1.0.0", type: .prompt,
                                                              prompt: "Rewrite as a config file."),
                                     directory: URL(fileURLWithPath: "/tmp/config"), isLocal: true)
        let doctor = InstalledPlugin(manifest: PluginManifest(name: "doctor", version: "1.0.0", type: .script, script: "main.js"),
                                     directory: URL(fileURLWithPath: "/tmp/doctor"), isLocal: false)
        // The manifest's own check takes the names.
        #expect(config.manifest.problem(appVersion: AppVersion.string) == nil)
        #expect(doctor.manifest.problem(appVersion: AppVersion.string) == nil)
        // In the catalog as the plugins' commands (a built-in no longer hides them).
        let catalog = Command.catalog([], plugins: [config, doctor])
        let configCommand = try #require(catalog.first { $0.name == "config" })
        let doctorCommand = try #require(catalog.first { $0.name == "doctor" })
        #expect(configCommand.plugin == config && configCommand.kind == .generate, "\(configCommand)")
        #expect(doctorCommand.plugin == doctor && doctorCommand.kind == .run, "\(doctorCommand)")
        #expect(catalog.filter { Self.removed.contains($0.name) }.count == 2)
        // A plugin wins over a custom command of the same name, as for any name.
        let custom = CustomCommand(name: "config", type: .prompt, prompt: "x")
        #expect(Command.catalog([custom], plugins: [config]).filter { $0.name == "config" }.map(\.plugin) == [config])
        // Typed, the prompt plugin runs.
        let effects = run("@config a b c", field(commands: catalog))
        #expect(effects.contains { if case let .startCommand(c, input, _) = $0 { return c == configCommand && input == "a b c" }
                                   else { return false } }, "\(effects)")
        // The script plugin runs inside a text, as plugins do.
        let plan = CommandPlan.make("结果是 @doctor 「x y」", commands: catalog)
        #expect(plan.inner.map(\.command) == [doctorCommand] && plan.inner.first?.argument == "x y")
    }

    @Test func r4_scriptExtensionsNamedConfigOrDoctorAreNotHidden() throws {
        let scripts = Self.removed.map { ScriptCommand(file: URL(fileURLWithPath: "/x/\($0).sh"), name: $0, arguments: [.init(placeholder: "what")]) }
        // No built-in owns the names, so Settings doesn't list them as hidden.
        #expect(Command.hiddenScripts(scripts, custom: []).isEmpty)
        let catalog = Command.catalog([], scripts: scripts)
        for (name, script) in zip(Self.removed, scripts) {
            let command = try #require(catalog.first { $0.name == name }, "@\(name)")
            #expect(command.script == script && command.kind == .run, "@\(name)")
        }
        // A custom command of the name still comes before an extension's, as for any name.
        let custom = CustomCommand(name: "doctor", type: .prompt, prompt: "x")
        let hidden = Command.hiddenScripts(scripts, custom: [custom])
        #expect(hidden.map { $0.script.name } == ["doctor"])
    }

    // MARK: r5. Core text no longer says to type them

    @Test func r5_hostedAdviceNoLongerSaysToType() {
        for error in [ProviderError.signedOut, .quotaExhausted] {
            for onDevice in [true, false] {
                let advice = ProviderError.hostedAdvice(error, onDevice: onDevice) ?? ""
                #expect(!advice.isEmpty, "\(error)")
                #expect(!advice.contains("@config") && !advice.contains("@doctor"), "\(error), onDevice \(onDevice): \(advice)")
            }
            // With Apple Intelligence on this Mac it pointed to "@config use Apple Intelligence": now to Settings → Assistant.
            let onDevice = ProviderError.hostedAdvice(error, onDevice: true) ?? ""
            #expect(onDevice.contains("Assistant"), "\(error): \(onDevice)")
        }
    }

    @Test func r5_doctorFindingsDoNotNameTheCommands() {
        var facts = Doctor.Facts()
        var config = Config.default
        config.provider = .anthropic
        facts.config = config
        facts.configData = try? JSONEncoder().encode(config)
        facts.keySaved = [.anthropic: true]
        facts.connection = .ok("answered in 0.8 s")
        for apple in [AppleModelAvailability.available, .appleIntelligenceNotEnabled, .deviceNotEligible] {
            facts.apple = apple
            for chinese in [false, true] {
                let findings = Doctor.findings(facts, chinese: chinese)
                #expect(findings.contains { $0.area == .appleIntelligence }, "\(apple)")
                for finding in findings {
                    let text = finding.text(chinese: chinese)
                    #expect(!text.contains("@config") && !text.contains("@doctor"), "\(apple), chinese \(chinese): \(text)")
                }
            }
        }
    }
}

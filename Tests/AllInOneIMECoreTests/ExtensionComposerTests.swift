import Foundation
import Testing
@testable import AllInOneIMECore

/// Script extensions typed as @ commands: the action key runs them with their arguments, and what they print is
/// used as their `output` says. The scripts are made in temporary folders and really run, as the controller does.
struct ExtensionComposerTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    let copyKey = KeyEvent(keyCode: 0x08, characters: "c", charactersIgnoringModifiers: "c", modifiers: .command)

    func typeKeys(_ text: String, _ composer: Composer) {
        for ch in text { _ = composer.handleKeyDown(ch == "@" ? at : ch == " " ? spaceKey : k(String(ch))) }
    }

    /// A composer in English mode, ⏎ the action key, offering `index`'s commands.
    func composer(_ index: ExtensionIndex) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.commands = Command.catalog([], scripts: index.commands)
        return c
    }

    func composer(_ folder: ScriptFolder) -> Composer { composer(folder.load()) }

    /// The run `effects` start: its command, arguments, text and request.
    func started(_ effects: [Composer.Effect]) -> (command: Command, arguments: [String], query: String, id: Int, action: Bool)? {
        for effect in effects {
            if case let .startScript(command, arguments, query, id, action) = effect { return (command, arguments, query, id, action) }
        }
        return nil
    }

    func environment(_ command: ScriptCommand, query: String, action: Bool = false, preferences: [String: String] = [:]) -> [String: String] {
        ScriptContext(language: "en", inputLanguage: "en", app: "com.example.editor", query: query)
            .environment(for: command, base: ["PATH": "/usr/bin:/bin"], preferences: preferences, action: action)
    }

    /// Runs what `effects` start, as the controller does, and gives the composer each update; the effects of that.
    @discardableResult
    func finish(_ effects: [Composer.Effect], in c: Composer, preferences: [String: String] = [:]) async -> [Composer.Effect] {
        guard let start = started(effects), let script = start.command.script else { return [] }
        var out: [Composer.Effect] = []
        do {
            for try await update in CommandRunner.run(script, arguments: start.arguments,
                                                      environment: environment(script, query: start.query, action: start.action,
                                                                               preferences: preferences)) {
                out += c.receiveScript(update.output, isFinal: update.isFinal, id: start.id)
            }
        } catch {
            out += c.fail(error.localizedDescription, id: start.id)
        }
        return out
    }

    /// Runs the list being typed in `c` once, as the controller does after its `queryDelay`.
    func runList(_ c: Composer) async throws -> [Composer.Effect] {
        let query = try #require(c.listQuery), script = try #require(c.draftCommand?.script)
        guard case let .success(arguments) = script.arguments(from: query) else { return [] }
        var output = ScriptOutput.text("")
        for try await update in CommandRunner.run(script, arguments: arguments, environment: environment(script, query: query)) where update.isFinal {
            output = update.output
        }
        return c.receiveList(output, for: query)
    }

    // MARK: - input

    @Test func noInputRunsOnTheActionKeyOnly() async throws {
        let folder = ScriptFolder()
        folder.add("uuid.sh", script(["input none", "title New UUID"], "echo 1234-abcd"))
        let c = composer(folder)
        typeKeys("@uu", c)
        // Tab (or Space) only completes the name…
        #expect(started(c.handleKeyDown(tab).effects) == nil && c.draft == "@uuid " && !c.isLevelTwo)
        // …the action key runs it; what's typed after it is ignored.
        typeKeys("ignored", c)
        let effects = c.handleKeyDown(enterKey).effects
        let start = try #require(started(effects))
        #expect(start.arguments == [] && start.query == "ignored" && effects.contains(.commandUsed("uuid")))
        await finish(effects, in: c)
        #expect(c.choices.map(\.text) == ["1234-abcd"] && commits(c.handleKeyDown(enterKey)) == ["1234-abcd"])
        // ⏎ on its name in the list (⏎ the action key) picks and runs it at once.
        let d = composer(folder)
        typeKeys("@uu", d)
        #expect(started(d.handleKeyDown(enterKey).effects) != nil && d.draft == "@uuid ")
        // With another action key, ⏎ in the list only picks.
        let e = composer(folder)
        e.actionKey = .optionTap
        typeKeys("@uu", e)
        #expect(started(e.handleKeyDown(enterKey).effects) == nil && e.draft == "@uuid ")
    }

    @Test func argumentsComeFromTheText() async throws {
        let folder = ScriptFolder()
        folder.add("flights.sh", script(["title Flights", #"argument1 {"type": "text", "placeholder": "from city"}"#,
                                         #"argument2 {"type": "text", "placeholder": "to city"}"#],
                                        #"echo "searching $ALLINONEIME_QUERY"; echo "$1 → $2""#))
        folder.add("free.sh", script(["title Free"], #"echo "<$1>""#))
        folder.add("temp.sh", script([#"argument1 {"type": "dropdown", "placeholder": "unit", "data": [{"title": "Celsius", "value": "c"}]}"#]))
        let c = composer(folder)
        typeKeys("@fl", c)
        _ = c.handleKeyDown(tab)
        #expect(c.handleKeyDown(enterKey).effects == [.notice("还要写：from city, to city")])  // nothing runs
        typeKeys("beijing, new york", c)
        #expect(c.markedText == "flights › beijing, new york")
        let effects = c.handleKeyDown(enterKey).effects
        let start = try #require(started(effects))
        #expect(start.arguments == ["beijing", "new york"] && start.query == "beijing, new york" && !start.action)
        await finish(effects, in: c)
        // All of it, then each line.
        #expect(c.choices.map(\.text) == ["searching beijing, new york\nbeijing → new york", "searching beijing, new york", "beijing → new york"])
        #expect(c.choices.map(\.label) == ["1", "2", "3"] && c.highlighted == 0)
        #expect(commits(c.handleKeyDown(k("3"))) == ["beijing → new york"] && !c.isComposing)
        // The one free-text argument: written or not, as with any command.
        let d = composer(folder)
        typeKeys("@free ", d)
        #expect(d.handleKeyDown(enterKey).effects == [.notice(Composer.Messages.chinese.typeAfterCommand)])
        let e = composer(folder)
        typeKeys("@temp kelvin", e)
        #expect(e.handleKeyDown(enterKey).effects == [.notice("只能是这几个之一：Celsius")])
        // An "@" in a script's text is just text (no list of commands inside it).
        let f = composer(folder)
        typeKeys("@flights me@", f)
        #expect(f.paletteQuery == nil)
    }

    // MARK: - output

    @Test func summaryAndDetail() async throws {
        let folder = ScriptFolder()
        folder.add("check.sh", script(["input none"], #"echo '{"summary": "3 tests failed", "detail": "parser, cache, ui"}'"#))
        let c = composer(folder)
        typeKeys("@check", c)
        _ = c.handleKeyDown(tab)
        await finish(c.handleKeyDown(enterKey).effects, in: c)
        #expect(c.choices.map(\.text) == ["3 tests failed"] && c.choices.first?.detail == "parser, cache, ui")
        #expect(commits(c.handleKeyDown(enterKey)) == ["3 tests failed"])
    }

    @Test func showIsShownAsItComesAndNeverInserted() async throws {
        let folder = ScriptFolder()
        folder.add("deploy.sh", script(["input none", "output show"], "echo 'step 1'; sleep 0.3; echo 'step 2'; sleep 0.3; echo done"))
        let c = composer(folder)
        typeKeys("@deploy", c)
        _ = c.handleKeyDown(tab)
        let effects = c.handleKeyDown(enterKey).effects
        let start = try #require(started(effects))
        var sawProgress = false
        for try await update in CommandRunner.run(start.command.script!, arguments: [], environment: ["PATH": "/usr/bin:/bin"]) {
            _ = c.receiveScript(update.output, isFinal: update.isFinal, id: start.id)
            if !update.isFinal, case .translating = c.phase, c.choices.first?.text == "step 1" { sawProgress = true }
        }
        #expect(sawProgress)
        #expect(c.phase == .choosing && c.choices.map(\.text) == ["step 1", "step 2", "done"] && c.choices.allSatisfy { $0.kind == .shown })
        // ⌘C copies all of it; ⏎ closes, inserting nothing.
        #expect(c.handleKeyDown(copyKey).effects.first == .copy("step 1\nstep 2\ndone"))
        let closed = c.handleKeyDown(enterKey).effects
        #expect(commits(closed).isEmpty && !c.isComposing)
    }

    @Test func showGoesOnWhenTheFieldIsLeft() throws {
        let folder = ScriptFolder()
        folder.add("deploy.sh", script(["input none", "output show"], "sleep 5"))
        folder.add("insert.sh", script(["input none"], "sleep 5"))
        let c = composer(folder)
        typeKeys("@deploy", c)
        _ = c.handleKeyDown(tab)
        let start = try #require(started(c.handleKeyDown(enterKey).effects))
        // Leaving the field: it goes to the background (the controller detaches it); Esc would stop it.
        let left = c.commitAll()
        #expect(left.contains(.detachScript(id: start.id)) && !left.contains(.cancelConversion))
        let d = composer(folder)
        typeKeys("@insert", d)
        _ = d.handleKeyDown(tab)
        _ = d.handleKeyDown(enterKey)
        #expect(d.commitAll().contains(.cancelConversion))
        let e = composer(folder)
        typeKeys("@deploy", e)
        _ = e.handleKeyDown(tab)
        _ = e.handleKeyDown(enterKey)
        #expect(e.handleKeyDown(escKey).effects.first == .cancelConversion && e.draft == "@deploy ")
    }

    @Test func silentSaysItNearTheCaret() async throws {
        let folder = ScriptFolder()
        folder.add("toggle.sh", raycast(title: "Toggle", mode: "compact", [], "echo working; echo 'Dark mode on'"))
        folder.add("quiet.sh", script(["input none"], "true"))
        let c = composer(folder)
        typeKeys("@toggle", c)
        _ = c.handleKeyDown(tab)
        let done = await finish(c.handleKeyDown(enterKey).effects, in: c)
        #expect(done.contains(.notice("Dark mode on")) && commits(done).isEmpty && !c.isComposing)
        let q = composer(folder)
        typeKeys("@quiet", q)
        _ = q.handleKeyDown(tab)
        let ran = await finish(q.handleKeyDown(enterKey).effects, in: q)
        #expect(ran.contains(.notice("已运行：quiet")))
    }

    @Test func failuresAndRetrying() async throws {
        let folder = ScriptFolder()
        folder.add("broken.sh", script(["input none"], "echo 'Not signed in'; exit 1"))
        let c = composer(folder)
        typeKeys("@broken", c)
        _ = c.handleKeyDown(tab)
        await finish(c.handleKeyDown(enterKey).effects, in: c)
        #expect(c.phase == .failed("Not signed in"))
        #expect(started(c.handleKeyDown(enterKey).effects) != nil)  // ⏎ tries again
    }

    @Test func backgroundStartsAndTheDraftIsDone() {
        let folder = ScriptFolder()
        folder.add("timer.sh", script(["background true", #"argument1 {"type": "text", "placeholder": "minutes"}"#], "sleep 1"))
        let c = composer(folder)
        typeKeys("@timer 10", c)
        let effects = c.handleKeyDown(enterKey).effects
        let command = c.commands.first { $0.name == "timer" }!
        #expect(effects.contains(.startBackgroundScript(command, arguments: ["10"], query: "10")))
        #expect(effects.contains(.notice("在后台运行，完成后通知你：timer")) && !c.isComposing && started(effects) == nil)
    }

    @Test func confirmFirst() {
        let folder = ScriptFolder()
        folder.add("empty-trash.sh", raycast(title: "Empty Trash", mode: "silent", ["needsConfirmation true"], "echo emptied"))
        let c = composer(folder)
        c.messages = .english
        typeKeys("@emptytrash", c)
        _ = c.handleKeyDown(tab)
        #expect(c.handleKeyDown(enterKey).effects == [.notice("Run Empty Trash? ⏎ again")])
        #expect(started(c.handleKeyDown(enterKey).effects) != nil)
        // Changing the text asks again.
        let d = composer(folder)
        d.messages.actionKeyName = "⌥Space"
        d.messages.confirmScript = Composer.Messages.english.confirmScript
        typeKeys("@emptytrash", d)
        _ = d.handleKeyDown(tab)
        #expect(d.handleKeyDown(enterKey).effects == [.notice("Run Empty Trash? ⌥Space again")])
        typeKeys("x", d)
        #expect(started(d.handleKeyDown(enterKey).effects) == nil)
        #expect(started(d.handleKeyDown(enterKey).effects) != nil)
    }

    // MARK: - list

    let people = #"""
        case "$ALLINONEIME_ACTION" in
          run) echo "{\"summary\": \"Details of $1\", \"detail\": \"second step\"}"; exit ;;
        esac
        printf '{"items": [{"title": "Jane %s", "subtitle": "Engineer", "arg": "jane@example.com", "text": {"copy": "jdoe"}, "autocomplete": "jane "},
          {"title": "Open her page", "arg": "https://example.com/jane"},
          {"title": "Copy her id", "arg": "jdoe-42", "action": "copy"},
          {"title": "More about her", "arg": "jane", "action": "run"},
          {"title": "Information only", "valid": false}]}' "$1"
        """#

    @Test func aListAsYouType() async throws {
        let folder = ScriptFolder()
        folder.add("people.sh", script(["output list", #"argument1 {"type": "text", "optional": true}"#], people))
        let c = composer(folder)
        typeKeys("@people j", c)
        #expect(c.listQuery == "j" && c.currentList == nil)
        let shown = try await runList(c)
        #expect(shown == [.showPanel])
        let list = try #require(c.currentList)
        #expect(list.items.map(\.title) == ["Jane j", "Open her page", "Copy her id", "More about her", "Information only"])
        #expect(c.listItem?.title == "Jane j" && c.handleKeyDown(copyKey).effects.first == .copy("jdoe"))
        // Another key: the list belongs to the text before (the controller runs it again after `queryDelay`).
        typeKeys("a", c)
        #expect(c.currentList == nil && c.listQuery == "ja")
        _ = try await runList(c)
        // ↑↓ skip rows of information; Tab completes the text.
        _ = c.handleKeyDown(upKey)
        #expect(c.listItem?.title == "More about her")
        _ = c.handleKeyDown(downKey)
        #expect(c.listItem?.title == "Jane ja")
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@people jane ")
        _ = try await runList(c)
        // The action key: the row's action, here insert its arg.
        let inserted = c.handleKeyDown(enterKey).effects
        #expect(commits(inserted) == ["jane@example.com"] && inserted.contains(.commandUsed("people")) && !c.isComposing)
    }

    @Test func listActions() async throws {
        let folder = ScriptFolder()
        folder.add("people.sh", script(["output list", "input optional"], people))
        func at(_ row: Int) async throws -> Composer {
            let c = composer(folder)
            typeKeys("@people x", c)
            _ = try await runList(c)
            for _ in 0..<row { _ = c.handleKeyDown(downKey) }
            return c
        }
        let open = try await at(1)
        #expect(open.handleKeyDown(enterKey).effects.contains(.openLink(URL(string: "https://example.com/jane")!)))
        let copy = try await at(2)
        let copied = copy.handleKeyDown(enterKey).effects
        #expect(copied.contains(.copy("jdoe-42")) && commits(copied).isEmpty && !copy.isComposing)
        // run: the script again with the row's arg as $1 (ALLINONEIME_ACTION=run); what it prints, to insert.
        let run = try await at(3)
        let effects = run.handleKeyDown(enterKey).effects
        let start = try #require(started(effects))
        #expect(start.arguments == ["jane"] && start.action && run.isLevelTwo)
        await finish(effects, in: run)
        #expect(run.choices.map(\.text) == ["Details of jane"] && run.choices.first?.detail == "second step")
        // Without a list yet, the action key asks for one now.
        let c = composer(folder)
        typeKeys("@people y", c)
        #expect(c.handleKeyDown(enterKey).effects == [.refreshList])
        // What isn't a list is a row of information.
        _ = c.receiveList(.text("oops: no JSON"), for: "y")
        #expect(c.currentList?.items == [ScriptItem(title: "oops: no JSON", valid: false)] && c.listItem == nil)
    }

    @Test func aSecondStepCanBeAList() async throws {
        let folder = ScriptFolder()
        folder.add("steps.sh", script(["output list", "input optional"], #"""
            if [ "$ALLINONEIME_ACTION" = run ]; then
              echo '{"items": [{"title": "Sub one", "arg": "1"}, {"title": "Sub two", "arg": "2"}]}'
            else
              echo '{"items": [{"title": "Go deeper", "arg": "deeper", "action": "run"}]}'
            fi
            """#))
        let c = composer(folder)
        typeKeys("@steps ", c)
        _ = try await runList(c)
        await finish(c.handleKeyDown(enterKey).effects, in: c)
        #expect(c.choices.map(\.text) == ["Sub one", "Sub two"] && c.choices.map(\.label) == ["1", "2"])
        #expect(commits(c.handleKeyDown(k("2"))) == ["2"])
    }

    // MARK: - the command list

    @Test func namesWithDigitsAndTitlesInTheList() {
        let folder = ScriptFolder()
        folder.add("base64.sh", script(["title Encode Base64"]))
        folder.add("bases.sh", script(["title Database Lookup", "keywords sql, tables"]))
        let c = composer(folder)
        typeKeys("@base", c)
        #expect(c.paletteMatches.map(\.name) == ["base64", "bases"])
        typeKeys("6", c)  // a digit that goes on a name is part of it
        #expect(c.paletteMatches.map(\.name) == ["base64"] && c.draft == "@base6")
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@base64 " && c.markedText == "base64 › ")
        // Found by a word of its title or a keyword, after the names.
        let d = composer(folder)
        typeKeys("@sq", d)
        #expect(d.paletteMatches.map(\.name) == ["bases"])
        let e = composer(folder)
        typeKeys("@enc", e)
        #expect(e.paletteMatches.map(\.name) == ["base64"])
        // Another digit picks a row.
        let f = composer(folder)
        typeKeys("@base", f)
        _ = f.handleKeyDown(k("2"))
        #expect(f.draft == "@bases ")
    }
}

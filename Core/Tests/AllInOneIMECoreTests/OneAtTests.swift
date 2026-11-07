import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// One @'s parts (OneAt.swift, Composer+OneAt.swift), the lists that fill as you type (LiveRows.swift,
/// `SessionTasks.asTyped`), and what the session reads after the "@" key. The behaviour the spec describes is the
/// acceptance tests' (Acceptance/OneAtAcceptanceTests.swift); these check the pieces and what the spec leaves to them.
struct OneAtTests {
    // MARK: - Arithmetic

    @Test func theEvaluatorReadsSumsOnly() {
        let sums: [(String, String)] = [("3*7+2", "23"), ("(1+2)^3", "27"), ("2^3^2", "512"), ("200*15%", "30"), ("-3+5", "2"),
                                        ("7/2", "3.5"), ("0.1+0.2", "0.3"), ("１２＋３", "15"), ("6×7", "42"), ("84÷2", "42"),
                                        (" 1 + 1 ", "2"), ("10%", "0.1")]
        for (text, value) in sums {
            #expect(Arithmetic.value(of: text).map(Arithmetic.format) == value, "\(text)")
        }
        for text in ["3", "3*x", "1/0", "2+2)", "(2+2", "3*7+", "1..2+1", "0x10+1", "9^9999", "", "+", "%", "1,000+1", "e^2"] {
            #expect(Arithmetic.value(of: text) == nil, "\(text)")
        }
    }

    // MARK: - What the text is

    @Test func questionsAndLanguages() {
        for text in ["红烧肉怎么做", "你吃饭了吗", "how do I undo a commit", "pizza or pasta?", "Is it done", "多少钱"] {
            #expect(OneAt.isQuestion(text), "\(text)")
        }
        for text in ["这家店的菜很好吃", "thank you for the gift", "show me how", "明天下午3点开会"] {
            #expect(!OneAt.isQuestion(text), "\(text)")
        }
        #expect(OneAt.mostly("这个PR我觉得还可以") == .chinese)
        #expect(OneAt.mostly("please update the 文档 today") == .english)
        #expect(!OneAt.isOtherLanguage("3*7+2", main: .chinese), "no letters: no language")
    }

    // MARK: - The order

    func input(_ text: String, letters: String? = nil, selection: String? = nil, app: String? = nil, chat: Bool = false,
               noAI: Bool = false, usage: CommandUsage = CommandUsage(), commands: [Command] = Command.builtins,
               instant: @escaping (String) -> [SearchResult] = { _ in [] }) -> OneAt.Input {
        let named = letters.map { Command.palette($0, in: commands, usage: usage, app: app, limit: .max) } ?? []
        return OneAt.Input(text: text, letters: letters, selection: selection, commands: commands, named: named, usage: usage, app: app,
                           chat: chat, noAI: noAI, mainLanguage: .chinese, instant: instant)
    }

    func names(_ actions: [OneAt.Action]) -> [String] { actions.map(\.id) }

    @Test func aNameTypedListsItsCommandsAndNotTheirActionAgain() {
        let rows = OneAt.actions(input("tr", letters: "tr"))
        #expect(rows.first == .command(.translate), "\(names(rows))")
        #expect(!rows.contains(.write(.translate)), "Translate is there by name already: \(names(rows))")
        #expect(rows.last == .write(.question))
    }

    @Test func theUsersOwnWritingActionsOnceUsed() {
        let prompts = ["pa", "pb", "pc", "pd", "pe"].map { CustomCommand(name: $0, type: .prompt, summary: "Mine \($0)", prompt: "Do \($0).") }
        let run = CustomCommand(name: "shout", type: .run, summary: "Upper case", argv: ["/usr/bin/tr", "a-z", "A-Z"])
        let commands = Command.catalog(prompts + [run])
        var usage = CommandUsage()
        for name in ["pa", "pb", "pc", "pd", "shout"] { usage.record(name) }
        usage.record("pd", in: "com.example.notes")
        usage.record("pd", in: "com.example.notes")
        let rows = OneAt.actions(input("这家店的菜很好吃", app: "com.example.notes", usage: usage, commands: commands))
        let own = rows.compactMap { action -> String? in
            if case let .write(command) = action, command.custom != nil { return command.name }
            return nil
        }
        #expect(own.count == OneAt.ownLimit && own.first == "pd" && !own.contains("pe"), "used ones, at most three: \(names(rows)) \(commands.map(\.name))")
        #expect(!rows.contains { $0.command?.name == "shout" }, "a run command is never guessed: \(names(rows))")
        #expect(rows.first == .write(.improve) && rows.last == .write(.question))
        // Found by its summary's words, in any language.
        let found = OneAt.actions(OneAt.Input(text: "upper", commands: commands, words: { Composer.words(of: $0).flatMap(OneAt.words) }))
        #expect(found.first == .command(commands.first { $0.name == "shout" }!), "\(names(found))")
    }

    @Test func aSelectionAloneInAChatAppAndWithoutAI() {
        let chat = OneAt.actions(input("", selection: "会议室在哪里？", chat: true))
        #expect(names(chat) == ["write:reply", "write:improve", "write:translate", "write:question"])
        let english = OneAt.actions(input("", selection: "The report looks good"))
        #expect(names(english) == ["write:translate", "write:improve", "write:question"])
        #expect(OneAt.actions(input("", selection: "x", chat: true, noAI: true)).isEmpty)
        let instruction = OneAt.actions(input("改正式一点", selection: "this sentance have a error"))
        #expect(names(instruction) == ["edit", "write:question"])
    }

    @Test func nothingTypedIsTheCommandListWithoutAIWhereThereIsNone() {
        let all = OneAt.actions(input(""))
        #expect(all.count == Command.builtins.count && all.allSatisfy { if case .command = $0 { true } else { false } })
        let noAI = OneAt.actions(input("", noAI: true))
        #expect(!noAI.contains { $0.command?.usesAI == true } && noAI.contains(.command(.open)))
    }

    /// What one @ costs a key with many script extensions: the composer's work and the panel, over names, sentences and
    /// ⌫, in the CPU time of the thread typing (`Timing`). 3 ms at 1000 extensions in a debug build on a Mac mini, where
    /// the rows were checked against each other one by one before (109 ms); the bound leaves room for a slower machine.
    @Test func typingStaysFast() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.commands = ExtensionPerformanceTests.commands(1000)
        let presenter = PanelPresenter(config: .default, language: "en")
        let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
        var spent: Duration = .zero
        var pressed = 0
        for word in ["beta", "cmdx", "does", "list", "zqvw", "alph", "thin", "comm", "abcd", "mnop", "thank you", "3*7+2"] {
            for key in [at] + word.map({ $0 == " " ? spaceKey : k(String($0)) }) + Array(repeating: backspaceKey, count: word.count + 1) {
                spent += Timing.cpuTime {
                    _ = c.handleKeyDown(key)
                    _ = presenter.model(for: c)
                    _ = c.markedText
                }
                pressed += 1
            }
        }
        let perKey = (Double(spent.components.seconds) * 1000 + Double(spent.components.attoseconds) / 1e15) / Double(pressed)
        print(String(format: "one @ per key at 1000 extensions: %.3f ms", perKey))
        #if os(Linux)
        #expect(perKey < 30, "\(perKey) ms")
        #else
        #expect(perKey < 15, "\(perKey) ms")
        #endif
    }

    // MARK: - Use, per app

    @Test func usageIsKeptPerAppAndReadsAnOldFile() throws {
        var usage = CommandUsage()
        let now = Date()
        usage.record("reply", in: "com.tinyspeck.slackmacgap", now: now)
        usage.record("reminder", now: now)
        #expect(usage.score("reply", in: "COM.TINYSPECK.SLACKMACGAP", now: now) == 1 && usage.score("reply", now: now) == 1)
        #expect(usage.score("reminder", in: "com.tinyspeck.slackmacgap", now: now) == 0)
        let commands = Command.catalog([])
        #expect(Command.palette("re", in: commands, usage: usage, app: "com.tinyspeck.slackmacgap").first == .reply)
        #expect(Command.palette("re", in: commands, usage: usage, app: "com.example.editor").first == .reply, "by use overall")
        let coded = try JSONDecoder().decode(CommandUsage.self, from: JSONEncoder().encode(usage))
        #expect(coded == usage)
        let old = try JSONDecoder().decode(CommandUsage.self, from: Data(#"{"entries": {"note": {"score": 2, "last": 0}}}"#.utf8))
        #expect(old.score("note", now: Date(timeIntervalSinceReferenceDate: 0)) == 2)
    }

    // MARK: - Lists that fill as you type

    @Test func liveRowsKeepTheirRowsAndTheirHighlight() {
        var rows = LiveRows<String>(limit: 2, id: { $0 })
        rows.show("a", instant: ["apple"], fits: { _ in true })
        rows.receive(["apple", "avocado", "apricot"], for: "a", current: "a", fits: { _ in true })
        rows.move(by: 1)
        #expect(rows.rows[rows.highlight] == "avocado")
        // The same text's answer again: the highlight stays on its row.
        rows.receive(["apricot", "avocado"], for: "a", current: "a", fits: { _ in true })
        #expect(rows.rows[rows.highlight] == "avocado")
        // A new text: what still fits stays until its answer, the highlight on the first.
        rows.show("av", fits: { $0.hasPrefix("av") })
        #expect(rows.rows == ["avocado"] && rows.highlight == 0)
        // An answer for an older text only adds what fits the text now.
        rows.receive(["avalanche", "apple"], for: "a", current: "av", fits: { $0.hasPrefix("av") })
        #expect(rows.rows == ["avocado", "avalanche"])
        // Back to a text answered before: its rows at once.
        rows.show("a", fits: { _ in false })
        #expect(rows.rows == ["avalanche", "apple"])
    }

    /// A field whose services list `scripts`' commands, the input on English.
    func field(_ folder: ScriptFolder, contacts: [Contact]? = nil) -> FakeHost {
        var services = SessionServices(loadSettings: { .default })
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        let index = folder.load()
        services.loadExtensions = { _, _ in index }
        services.cachedContacts = { contacts }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    static let people = """
        #!/bin/sh
        # @allinoneime.schemaVersion 1
        # @allinoneime.title People
        # @allinoneime.output list
        # @allinoneime.argument1 {"type": "text", "optional": true}
        # @allinoneime.queryDelay 5000
        sleep 0.2
        printf '{"items": [{"title": "Person %s", "arg": "%s"}, {"title": "Other %s", "arg": "o%s"}]}' "$1" "$1" "$1" "$1"
        """

    /// The first run once the command is picked goes at once (its query delay is 5 s); a key keeps the rows until its run
    /// answers; ⏎ before it answers starts it at once and acts on its first row; a text typed again lists what it printed
    /// before at once. In the interface language's turn, as the other sessions that wait for their work.
    @Test func aListKeepsItsRowsAndReturnWaitsForItsRun() async throws {
        try await withInterfaceLanguage("en") {
            let folder = ScriptFolder()
            folder.add("people.sh", Self.people)
            let host = field(folder)
            host.type("@people")
            host.press(FakeHost.tab)
            let picked = Date()
            #expect(host.settle(timeout: 15) { host.composer.currentList?.items.first?.title == "Person " })
            #expect(Date().timeIntervalSince(picked) < 4.5, "no query delay before the first run")
            host.type("j")
            #expect(host.composer.currentList?.items.first?.title == "Person ", "the rows stay until the run for \"j\" answers")
            let pressed = Date()
            host.press(FakeHost.enter)
            #expect(host.settle(timeout: 15) { host.document == "j" }, "⏎ waited for the run for \"j\": \(host.document)")
            #expect(Date().timeIntervalSince(pressed) < 4.5, "⏎ started the run in its pause")
            // Another draft of the same field: what the one before printed went with it.
            host.type("@people")
            host.press(FakeHost.tab)
            #expect(host.settle(timeout: 15) { host.composer.currentList != nil })
            host.type("j")
            #expect(host.settle(timeout: 15) { host.composer.currentList?.items.first?.title == "Person j" })
            host.press(backspaceKey)
            #expect(host.composer.currentList?.items.first?.title == "Person ", "the text before, listed at once")
        }
    }

    @Test func recipientsAreFoundInTheBookKeptOnTheKey() async {
        await withInterfaceLanguage("en") {
            let book = [Contact(name: "Ann Lee", handles: ["+1 555 0100"]), Contact(name: "Bob Ray", handles: ["bob@example.com"])]
            let host = field(ScriptFolder(), contacts: book)
            host.type("@imessage")
            host.press(FakeHost.tab)
            host.type("an")
            #expect(host.composer.currentRecipients.first?.name == "Ann Lee", "on the key: \(host.composer.currentRecipients)")
            #expect(host.panel?.rows.first?.text == "Ann Lee")
        }
    }

    // MARK: - The selection, read after the key

    /// The field told no selection with "@" and reads it after (the Mac's Accessibility): the list shows on the key, the
    /// draft stays out of the field, the selection's rows once it's in.
    @Test func theSelectionReadAfterTheKeyJoinsTheList() async {
        await withInterfaceLanguage("en") {
            let host = field(ScriptFolder())
            host.document = "The report looks good"
            host.selection = 0..<(host.document as NSString).length
            var told = host.context
            told.selection = nil
            told.selectionFollows = true
            host.press(FakeHost.at, with: told)
            #expect(host.marked.isEmpty && host.panel != nil, "nothing marked over the selection: \(host.marked)")
            #expect(host.composer.selection?.text == "The report looks good", "read after the key")
            #expect(host.panel?.rows.first?.comment == "@improve", "the selection's: \(host.panel?.rows.map(\.text) ?? [])")
            #expect(host.selectionWaits.isEmpty, "no key waited: it was in before the next")
        }
    }

    /// A field (English) with "hello there", all of it selected or nothing, that tells no selection with "@" and reads it
    /// after the key (the Mac's Accessibility: `selectionFollows`): "@" typed, then `text`, the read still in flight. A
    /// key that acts on the draft waits for it, and it lands `takes` seconds into the wait (nil: never).
    func reading(selected: Bool, takes: TimeInterval? = 0.05, typing text: String = "") -> FakeHost {
        let host = field(ScriptFolder())
        host.document = "hello there"
        host.selection = selected ? 0..<11 : nil
        host.selectionReadsWait = true
        host.selectionReadTakes = takes
        var told = host.context
        told.selection = nil
        told.selectionFollows = true
        host.press(FakeHost.at, with: told)
        #expect(host.composer.selectionPending)
        host.type(text)
        #expect(host.selectionWaits.isEmpty && host.document == "hello there", "letters only edit the draft: they don't wait")
        return host
    }

    /// ⏎ while the selection read after "@" is in flight waits for it on the key's thread, at most
    /// `InputSession.selectionWait`, then does what it does where the field tells the selection with the key: landed with
    /// the selection, before or right at the end of the wait, the selection's first row runs; landed with none, the "@"
    /// is typed. Not landed by then: the selection counts as none ("@" typed, as over any selection), and what the read
    /// answers later is dropped, also once another "@" waits for a read of its own. No key is posted, ever.
    @Test func returnWaitsForTheSelectionReadAtMostAMoment() async {
        await withInterfaceLanguage("en") {
            for takes in [0.05, InputSession.selectionWait] {
                let host = reading(selected: true, takes: takes)
                #expect(host.press(FakeHost.enter))
                #expect(host.composer.isLevelTwo && host.composer.activeCommand == .improve,
                        "\(takes) s: \(String(describing: host.composer.activeCommand)) \(host.composer.draft)")
                #expect(host.document == "hello there" && host.selectionWaits.map(\.waited) == [takes], "\(host.selectionWaits)")
                #expect(host.selectionWaits.map(\.timeout) == [InputSession.selectionWait] && host.platformActions.isEmpty)
            }
            let none = reading(selected: false)
            #expect(none.press(FakeHost.enter))
            #expect(none.document == "hello there@" && !none.composer.isComposing, "\(none.document) \(none.composer.draft)")
            #expect(none.platformActions.isEmpty)

            let late = reading(selected: true, takes: InputSession.selectionWait + 0.2)
            #expect(late.press(FakeHost.enter))
            #expect(late.selectionWaits.map(\.waited) == [InputSession.selectionWait], "given up at the deadline")
            #expect(late.document == "@" && !late.composer.isComposing && !late.composer.isLevelTwo, "\(late.document)")
            let panel = late.panel
            late.answerFieldReads()
            #expect(late.document == "@" && !late.composer.isComposing && late.composer.selection == nil, "the late answer is dropped")
            #expect(late.panel == panel && late.platformActions.isEmpty)

            let again = reading(selected: false, takes: nil)
            let first = again.outputs.compactMap { if case let .readSelection(id) = $0 { id } else { nil } }.first
            again.press(FakeHost.escape)
            #expect(again.selectionWaits.count == 1 && !again.composer.isComposing)
            var told = again.context
            told.selectionFollows = true
            again.press(FakeHost.at, with: told)
            #expect(again.composer.selectionPending)
            again.send(.selection(Composer.Selection(text: "hello there"), id: first ?? -1))
            #expect(again.composer.selectionPending && again.composer.selection == nil, "not the read this draft waits for")
        }
    }

    /// The keys that act wait for the read, then do what they do where the field tells the selection with the key: Esc
    /// leaves a selection alone, and a text as typed where none is; → gives the keys back, the text going in only where
    /// nothing is selected, and the → isn't taken (the app has it, as the key it is, after the keys before it and before
    /// those after it). Letters, ⌫ and ↑↓ only edit the draft and don't wait.
    @Test func keysWaitForTheSelectionReadAfterTheKey() async {
        await withInterfaceLanguage("en") {
            let escape = reading(selected: true, typing: "hello")
            #expect(escape.press(FakeHost.escape))
            #expect(escape.document == "hello there" && escape.selection == 0..<11 && !escape.composer.isComposing, "\(escape.document)")
            let escapeNone = reading(selected: false, typing: "hello")
            escapeNone.press(FakeHost.escape)
            #expect(escapeNone.document == "hello there@hello" && !escapeNone.composer.isComposing, "\(escapeNone.document)")
            let escapeAlone = reading(selected: false)
            #expect(escapeAlone.press(FakeHost.escape))
            #expect(escapeAlone.document == "hello there" && !escapeAlone.composer.isComposing, "\(escapeAlone.document)")
            for host in [escape, escapeNone, escapeAlone] {
                #expect(host.selectionWaits.count == 1 && host.platformActions.isEmpty)
            }

            let rightOnSelection = reading(selected: true, typing: "hello")
            #expect(!rightOnSelection.press(FakeHost.right), "→ is the app's")
            #expect(rightOnSelection.document == "hello there" && !rightOnSelection.composer.isComposing)
            let rightAlone = reading(selected: true)
            #expect(!rightAlone.press(FakeHost.right))
            #expect(rightAlone.document == "hello there" && rightAlone.selection == 0..<11 && !rightAlone.composer.isComposing)
            let right = reading(selected: false, typing: "hello")
            right.appTypesKeys = true
            #expect(!right.press(FakeHost.right))
            right.type("x")
            #expect(right.document == "hello there@hellox", "the text, then the app's → and x in order: \(right.document)")
            for host in [rightOnSelection, rightAlone, right] {
                #expect(host.selectionWaits.count == 1 && host.platformActions.isEmpty, "\(host.platformActions)")
            }

            let edits = reading(selected: true, typing: "help")
            for key in [backspaceKey, FakeHost.down, FakeHost.up] { edits.press(key) }
            edits.type("p")
            #expect(edits.selectionWaits.isEmpty && edits.composer.selectionPending && edits.composer.draft == "@help")
            edits.press(FakeHost.tab)
            edits.press(FakeHost.enter)
            #expect(edits.selectionWaits.count == 1, "once the read is in, nothing waits: \(edits.selectionWaits)")
        }
    }

    /// A row clicked while the read is in flight waits for it the same way, and the row shown is done with what it found:
    /// "@improve"'s Improve picked for the selection (the draft stays in the panel, the selection as it is), which ⏎ then
    /// runs it on. Where nothing is read after the key, nothing ever waits.
    @Test func aRowClickedWaitsForTheSelectionRead() async {
        await withInterfaceLanguage("en") {
            let host = reading(selected: true, typing: "improve")
            #expect(host.composer.oneAtRows.first == .command(.improve), "\(names(host.composer.oneAtRows))")
            host.send(.pick(0))
            #expect(host.selectionWaits.count == 1)
            #expect(host.composer.draftCommand == .improve && host.composer.selection?.text == "hello there", "\(host.composer.draft)")
            #expect(host.marked.isEmpty && host.document == "hello there" && host.selection == 0..<11, "\(host.marked)")
            host.press(FakeHost.enter)
            #expect(host.composer.isLevelTwo && host.composer.activeCommand == .improve && host.selectionWaits.count == 1)
            #expect(host.platformActions.isEmpty)

            let told = field(ScriptFolder())
            told.document = "hello there"
            told.press(FakeHost.at)
            told.press(FakeHost.enter)
            #expect(told.selectionWaits.isEmpty && told.document == "hello there@", "\(told.document)")
        }
    }

    // MARK: - Commands that come while the list is open

    @Test func commandsThatArriveShowInTheOpenList() async {
        await withInterfaceLanguage("en") {
            var services = SessionServices(loadSettings: { .default })
            services.levelOne = { .engine(FakeEngine()) }
            let extra = ScriptFolder()
            extra.add("hello.sh", "#!/bin/sh\n# @allinoneime.schemaVersion 1\n# @allinoneime.title Hello there\necho hi\n")
            let index = Locked(initialState: ExtensionIndex.empty)
            services.loadExtensions = { _, _ in index.withLock { $0 } }
            let host = FakeHost(services: services)
            host.focus()
            host.composer.setInputMode(.english)
            host.type("@he")
            let before = host.panel?.rows.map(\.text) ?? []
            #expect(!before.contains("hello"), "\(before)")
            index.withLock {
                $0 = extra.load()
                $0.generation = 1
            }
            // The rebuild landed (the shell tells it): the list open now shows the command, its letters' first.
            let outputs = host.session.commandsChanged()
            #expect(outputs.contains { if case .panel = $0 { true } else { false } })
            #expect(host.composer.commands.contains { $0.name == "hello" })
            #expect(host.composer.oneAtRows.first == .command(host.composer.commands.first { $0.name == "hello" }!))
        }
    }

    /// Spotlight's files never take the first row nor move the highlight (rule 4 is what is known at once): they join
    /// below the rows already shown, Ask AI still last, and are never listed alone.
    @Test func spotlightsFilesJoinBelowTheRowsShown() {
        let file = SearchResult(name: "Quarterly Report.pdf", path: "/Users/me/Documents/Quarterly Report.pdf")
        func rows(_ noAI: Bool = false, files: [SearchResult]) -> [OneAt.Action] {
            OneAt.actions(OneAt.Input(text: "quarterly report", commands: Command.builtins, noAI: noAI, mainLanguage: .chinese,
                                      files: files))
        }
        let before = rows(files: [])
        let after = rows(files: [file])
        #expect(after.first == before.first && after.first != .open(file), "\(names(after))")
        #expect(after.last == .write(.question) && after.dropLast().last == .open(file), "\(names(after))")
        #expect(rows(true, files: [file]).isEmpty, "no row but a file: none")
        // In the composer: the highlight stays on the first row as the files come.
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.commands = Command.builtins
        for key in [FakeHost.at] + "quarterly report".map({ $0 == " " ? spaceKey : k(String($0)) }) { _ = c.handleKeyDown(key) }
        let first = c.oneAtRows.first
        _ = c.receiveOneAtFiles([file], for: "quarterly report")
        #expect(c.oneAtRows.contains(.open(file)) && c.oneAtRows.first == first && c.oneAtHighlighted == 0, "\(names(c.oneAtRows))")
    }

    /// A path's rows are made where a path is opened, `@open ~/…`, and nothing of its folder is read on the key: the
    /// folder is listed by `@open`'s search (`SessionServices.searchFiles`, off the key's thread), however long the path,
    /// and its entries come as that answers; on the key only a listing kept from a moment ago (`instantResults`, which
    /// reads no disk) shows, at once.
    @Test func aPathsFolderIsListedOffTheKey() async {
        await withInterfaceLanguage("en") {
            let path = "~/Library/Application Support/AllInOneIME/LanguagePacks/"
            let entry = SearchResult(name: "zh-pinyin", path: "/Users/me/Library/Application Support/AllInOneIME/LanguagePacks/zh-pinyin",
                                     isFolder: true)
            let kept = Locked(initialState: false)
            let searched = Locked<[String]>(initialState: [])
            var services = SessionServices(loadSettings: { .default })
            services.levelOne = { .engine(FakeEngine()) }
            services.instantResults = { query, _ in kept.withLock { $0 } && query.hasPrefix(path) ? [entry] : [] }
            services.searchFiles = { query, _ in
                searched.withLock { $0.append(query) }
                return query.hasPrefix(path) ? [entry] : []
            }
            let host = FakeHost(services: services)
            host.focus()
            host.composer.setInputMode(.english)
            host.press(FakeHost.at)
            host.type("ope")
            host.press(FakeHost.tab)
            host.type(path)
            #expect(host.composer.draftCommand == .open && host.composer.draft == "@open " + path, "\(host.composer.draft)")
            #expect(host.composer.currentLiveResults.isEmpty, "nothing of the folder on the key")
            #expect(host.settle { host.composer.currentLiveResults == [entry] }, "listed off the key: \(searched.withLock { $0 })")
            #expect(searched.withLock { $0 }.last == path, "a long path is listed too")
            // The next key: the listing kept from a moment ago, at once.
            kept.withLock { $0 = true }
            host.type("z")
            #expect(host.composer.currentLiveResults.first == entry, "\(host.composer.currentLiveResults)")
        }
    }

    /// A mark right after the magic key gives it back as typed, a path's "~" and "/" too: with "~" the magic key, "~/" is
    /// "~/" (a terminal's home folder); "@~/Downloads/" is the at sign and the path, as text. No rows, and nothing of a
    /// folder is asked for. (A path is opened with `@open ~/Downloads/`.)
    @Test func aMarkRightAfterTheMagicKeyGivesItBack() async {
        await withInterfaceLanguage("en") {
            for trigger in ["~", "@"] {
                for (text, terminal) in [("~/", false), ("~/", true), ("@~/Downloads/", false), ("@~/Downloads/", true)] {
                    var config = Config.default
                    config.commandTrigger = trigger
                    let fixed = config
                    let asked = Locked<[String]>(initialState: [])
                    var services = SessionServices(loadSettings: { fixed })
                    services.levelOne = { .engine(FakeEngine()) }
                    services.instantResults = { query, _ in
                        if query.contains("/") { asked.withLock { $0.append(query) } }
                        return []
                    }
                    services.searchFileNames = { query, _ in
                        asked.withLock { $0.append(query) }
                        return []
                    }
                    let host = FakeHost(services: services)
                    host.terminal = terminal
                    host.appTypesKeys = true
                    host.focus()
                    host.composer.setInputMode(.english)
                    host.type(text)
                    let place = "\(trigger) \(text)\(terminal ? " in a terminal" : "")"
                    #expect(host.document == text && host.marked.isEmpty && !host.composer.isComposing, "\(place): \(host.document)|\(host.marked)")
                    #expect(host.composer.oneAt == nil && host.panel?.rows.isEmpty != false, "\(place)")
                    #expect(!host.settle(timeout: 0.1) { !asked.withLock { $0 }.isEmpty }, "\(place): \(asked.withLock { $0 })")
                }
            }
        }
    }

    /// Only a prompt plugin is a writing action once used; a script plugin (like a `run` command) is found by its name or
    /// summary only, never guessed for a sentence or a selection, also where there is no AI.
    @Test func aScriptPluginIsNeverGuessed() {
        let script = InstalledPlugin(manifest: PluginManifest(name: "shouty", version: "1.0.0", type: .script, script: "main.js"),
                                     directory: URL(fileURLWithPath: "/tmp/shouty"), isLocal: true)
        let prompt = InstalledPlugin(manifest: PluginManifest(name: "kindly", version: "1.0.0", type: .prompt, prompt: "Be kind."),
                                     directory: URL(fileURLWithPath: "/tmp/kindly"), isLocal: true)
        let commands = Command.catalog([], plugins: [script, prompt])
        var usage = CommandUsage()
        for _ in 0..<2 { usage.record("shouty"); usage.record("kindly") }
        let sentence = OneAt.actions(input("这家店的菜很好吃", usage: usage, commands: commands))
        #expect(!sentence.contains { $0.command?.name == "shouty" } && sentence.contains { $0.command?.name == "kindly" }, "\(names(sentence))")
        let selection = OneAt.actions(input("", selection: "这家店的菜很好吃", usage: usage, commands: commands))
        #expect(!selection.contains { $0.command?.name == "shouty" }, "\(names(selection))")
        #expect(OneAt.actions(input("hello", noAI: true, usage: usage, commands: commands)).isEmpty)
    }

    /// No AI here: the rows one @ guesses (the writing actions, Ask AI, the AI commands in the list for "@" alone or a
    /// selection) aren't offered; an AI command found by its name is listed as before, and when run gets the notice that
    /// AI is off in this app.
    @Test func withoutAIAnAICommandFoundByNameIsListedAndRefused() async {
        await withInterfaceLanguage("en") {
            var config = Config.default
            config.uiLanguage = "en"
            config.appProfiles["com.example.editor"] = AppProfile(noAI: true)
            var services = SessionServices(loadSettings: { config })
            services.levelOne = { .engine(FakeEngine()) }
            let host = FakeHost(services: services)
            host.focus()
            host.composer.setInputMode(.english)
            host.type("@")
            #expect(!host.composer.oneAtRows.contains { $0.command?.usesAI == true }, "\(names(host.composer.oneAtRows))")
            host.type("hello")
            #expect(!host.composer.oneAtRows.contains { $0.command?.usesAI == true }, "\(names(host.composer.oneAtRows))")
            host.press(FakeHost.escape)
            host.document = "the selected words"
            host.selection = 0..<18
            host.type("@")
            #expect(!host.composer.oneAtRows.contains { $0.command?.usesAI == true }, "\(names(host.composer.oneAtRows))")
            host.press(FakeHost.escape)
            host.selection = nil
            host.document = ""
            host.type("@tr")
            #expect(host.composer.oneAtRows.first == .command(.translate), "\(names(host.composer.oneAtRows))")
            host.press(FakeHost.tab)
            host.type("hello")
            host.press(FakeHost.enter)
            #expect(!host.composer.isLevelTwo && (host.noticeAlone ?? host.panel?.detail) == InputSession.aiRefusal,
                    "\(host.noticeAlone ?? host.panel?.detail ?? "none")")
        }
    }

    /// "At most 3 of the user's own": the three most used in this app, then overall for ties: one used only here counts
    /// here even where others are used more elsewhere.
    @Test func theUsersOwnAreTheMostUsedInThisApp() {
        let prompts = ["pa", "pb", "pc", "pd"].map { CustomCommand(name: $0, type: .prompt, summary: "Mine \($0)", prompt: "Do \($0).") }
        let commands = Command.catalog(prompts)
        var usage = CommandUsage()
        for (name, times) in [("pa", 10), ("pb", 9), ("pc", 8)] {
            for _ in 0..<times { usage.record(name, in: "com.apple.mail") }
        }
        for _ in 0..<3 { usage.record("pd", in: "com.tinyspeck.slackmacgap") }
        let own = { (app: String) -> [String] in
            OneAt.actions(self.input("这家店的菜很好吃", app: app, usage: usage, commands: commands)).compactMap { action in
                if case let .write(command) = action, command.custom != nil { return command.name }
                return nil
            }
        }
        #expect(own("com.tinyspeck.slackmacgap") == ["pd", "pa", "pb"], "\(own("com.tinyspeck.slackmacgap"))")
        #expect(own("com.apple.mail") == ["pa", "pb", "pc"])
    }

    /// Esc while pinyin is composed after "@": the rows go and the text stays as typed, the letters as letters.
    @Test func escWhilePinyinComposesLeavesTheLetters() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.commands = Command.builtins
        for key in [FakeHost.at] + "nihao".map({ k(String($0)) }) { _ = c.handleKeyDown(key) }
        #expect(c.engineState.isComposing)
        let response = c.handleKeyDown(escKey)
        #expect(commits(response) == ["@nihao"] && !c.isComposing && c.draft.isEmpty, "\(commits(response)) \(c.draft)")
    }

    /// In Chinese, a digit that goes on a command's name being composed (`@base64`) is part of the name, as in 0.6.9;
    /// any other digit picks a candidate.
    @Test func aDigitGoesOnANameWhilePinyinComposes() {
        let folder = ScriptFolder()
        folder.add("base64.sh", "#!/bin/sh\n# @allinoneime.schemaVersion 1\n# @allinoneime.title Encode Base64\necho hi\n")
        let commands = Command.catalog([], scripts: folder.load().commands)
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.commands = commands
        for key in [FakeHost.at] + "base64 ".map({ $0 == " " ? spaceKey : k(String($0)) }) { _ = c.handleKeyDown(key) }
        #expect(c.draftCommand?.name == "base64" && c.draft == "@base64 ", "\(c.draft)")
        let other = Composer(engine: FakeEngine(), actionKey: .enter)
        other.commands = commands
        for key in [FakeHost.at] + "nihao2".map({ k(String($0)) }) { _ = other.handleKeyDown(key) }
        #expect(other.oneAt?.text == "拟好", "\(String(describing: other.oneAt))")
    }

    /// "@" alone, then ← (a key that isn't the list's): the "@" goes in and the key goes to the app, as in 0.6.9. With
    /// text after "@", ← moves the caret in the text, never before the "@".
    @Test func leftAfterTheMagicKey() {
        let leftKey = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        _ = c.handleKeyDown(FakeHost.at)
        let left = c.handleKeyDown(leftKey)
        #expect(commits(left) == ["@"] && !left.handled && c.draft.isEmpty, "\(commits(left)) \(c.draft)")
        for key in [FakeHost.at, k("h"), k("i"), leftKey, leftKey, leftKey, leftKey, k("x")] { _ = c.handleKeyDown(key) }
        #expect(c.draft == "@xhi" && c.oneAt?.text == "xhi", "\(c.draft)")
    }

    /// No row at all ("@hello" in an app with No AI): ⏎ types the text as typed, the "@" with it, and the footer says
    /// so, never "⏎ do it".
    @Test func noRowsAndReturnTypesTheTextAsTyped() async {
        await withInterfaceLanguage("en") {
            var config = Config.default
            config.uiLanguage = "en"
            config.appProfiles["com.example.editor"] = AppProfile(noAI: true)
            var services = SessionServices(loadSettings: { config })
            services.levelOne = { .engine(FakeEngine()) }
            let host = FakeHost(services: services)
            host.focus()
            host.composer.setInputMode(.english)
            host.type("@hello")
            #expect(host.composer.oneAtRows.isEmpty, "\(names(host.composer.oneAtRows))")
            let footer = host.panel?.footer ?? ""
            #expect(footer.contains("types it as typed") && !footer.contains("do it"), "\(footer)")
            host.press(FakeHost.enter)
            #expect(host.document == "@hello" && !host.composer.isComposing, "\(host.document)")
        }
    }

    /// A text that is, as a whole, a date or a phone number is no sum ("2026-11-06" isn't 2009): the other rules take it.
    /// One rule, the same on every platform (no system detector: this runs on Linux and Windows alike). In Chinese mode
    /// "……" after a number is "^", as "。" is ".".
    @Test func aWholeDateOrPhoneNumberIsNoSum() {
        let notSums = ["2026-11-06", "2026/11/06", "11/06/2026", "2026.11.06", "010-12345678", "555-1234", "138-0013-8000",
                       "+86 138 0013 8000", " 2026-11-06 ", "２０２６－１１－０６", "0755-8888 6666", "6/11/2026"]
        for text in notSums {
            #expect(Arithmetic.value(of: text) == nil, "\(text)")
            #expect(OneAt.actions(input(text)).first.map { if case .value = $0 { true } else { false } } == false, "\(text)")
        }
        for text in ["2026-11-06", "2026/11/06", "11/06/2026", "2026.11.06", "010-12345678", "555-1234", "138-0013-8000",
                     "+86 138 0013 8000"] {
            #expect(Arithmetic.isDateOrPhoneNumber(text), "\(text)")
        }
        let sums = [("7/2", "3.5"), ("3/4", "0.75"), ("11/5", "2.2"), ("100-20", "80"), ("12-3", "9"), ("2^10", "1024"),
                    ("3*7+2", "23"), ("200*15%", "30"), ("10-4*2", "2"), ("1-2-3", "-4"), ("2000-1000", "1000"), ("1000-200", "800"),
                    ("12/31", "0.387096774194")]
        for (text, value) in sums {
            #expect(!Arithmetic.isDateOrPhoneNumber(text), "\(text)")
            #expect(Arithmetic.value(of: text).map(Arithmetic.format) == value, "\(text)")
        }
        #expect(Arithmetic.value(of: "2……10").map(Arithmetic.format) == "1024" && Arithmetic.value(of: "1。5*2") == 3)
    }

    /// "@" alone: Esc gives the magic key up (nothing goes in), and the footer says so ("Esc cancel"), not "as typed".
    @Test func theFooterOfTheMagicKeyAloneSaysEscCancels() async {
        await withInterfaceLanguage("en") {
            let host = field(ScriptFolder())
            host.type("@")
            let footer = host.panel?.footer ?? ""
            #expect(footer.hasSuffix("Esc cancel") && !footer.contains("as typed"), "\(footer)")
            host.press(FakeHost.escape)
            #expect(host.document.isEmpty && !host.composer.isComposing)
        }
    }

    /// Whether the app has AI is read once a turn of the session (a key, an answer), not on each read of one @'s rows (each
    /// read of the settings looks at the config file); a change of the settings shows from the next key on.
    @Test func whetherTheAppHasAIIsReadOnceAKey() async {
        await withInterfaceLanguage("en") {
            let config = Locked(initialState: Config.default)
            let reads = Locked(initialState: 0)
            var services = SessionServices(loadSettings: {
                reads.withLock { $0 += 1 }
                return config.withLock { $0 }
            })
            services.levelOne = { .engine(FakeEngine()) }
            let host = FakeHost(services: services)
            host.focus()
            host.composer.setInputMode(.english)
            host.type("@hello")
            #expect(host.composer.oneAtRows.contains(.write(.question)))
            reads.withLock { $0 = 0 }
            for _ in 0..<5 { _ = host.composer.oneAtRows }
            #expect(reads.withLock { $0 } == 0, "\(reads.withLock { $0 }) reads of the settings")
            config.withLock { $0.appProfiles["com.example.editor"] = AppProfile(noAI: true) }
            host.type("!")
            #expect(!host.composer.oneAtRows.contains(.write(.question)), "\(names(host.composer.oneAtRows))")
        }
    }

    /// The reminder row's time as the system shows times (12- or 24-hour: "3:00 PM" or "15:00"), with the same words
    /// `@reminder`'s row has for it.
    @Test func theReminderRowsTimeIsAsTheSystemShowsIt() async throws {
        try await withInterfaceLanguage("en") {
            let calendar = ReminderParser.localCalendar
            let day = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())))
            var due = calendar.dateComponents([.year, .month, .day], from: day)
            (due.hour, due.minute) = (15, 0)
            let draft = ReminderDraft(title: "meeting", due: due, hasTime: true, date: calendar.date(from: due))
            var services = SessionServices(loadSettings: { .default })
            services.levelOne = { .engine(FakeEngine()) }
            services.parseReminder = { $0.hasPrefix("meeting") ? draft : ReminderDraft(title: $0) }
            let host = FakeHost(services: services)
            host.focus()
            host.composer.setInputMode(.english)
            host.type("@meeting tomorrow 3pm")
            let row = try #require(host.panel?.rows.first { $0.text.hasPrefix("Reminder: ") }, "\(host.panel?.rows.map(\.text) ?? [])")
            #expect(row.text == "Reminder: " + InterfaceWords(language: "en").when(draft) + " meeting", "\(row.text)")
            let clock = ReminderDraft.clock(hour: 15, minute: 0, language: "en", clock24: UIText.clock24 ?? ReminderDraft.systemUses24HourClock)
            #expect(row.text.contains(clock), "\(row.text) \(clock)")
        }
    }

    // MARK: - Secure input

    /// Whether `row` is one the AI does (a writing action, an instruction for the selection, an AI command).
    func asksAI(_ row: OneAt.Action) -> Bool {
        switch row {
        case .write, .edit: return true
        case let .command(command): return command.usesAI
        case .value, .open, .reminder: return false
        }
    }

    /// A field whose session has secure input on elsewhere (`SessionServices.secureInputActive`: another app's Secure
    /// Keyboard Entry, a password field, the lock screen) or off, Chinese first and English to translate into, the input on
    /// English.
    func field(secureInput: Bool, noAI: Bool = false) -> FakeHost {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.setOrder([OutputLanguage.english, .chinese])
        if noAI { config.appProfiles = ["com.example.editor": AppProfile(noAI: true)] }
        var services = SessionServices(loadSettings: { config })
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        services.secureInputActive = { secureInput }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    /// Secure input on: as in an app with No AI, one @ guesses no AI row (Translate, Improve, Ask AI), and ⏎ on a text no
    /// row is left for types it as typed: it doesn't run Translate (nothing goes to the AI, no notice). Off, the same text
    /// has them.
    @Test func secureInputGuessesNoAIRows() async {
        await withInterfaceLanguage("en") {
            let open = field(secureInput: false)
            open.type("@hello")
            #expect(open.composer.oneAtRows.first == .write(.translate) && open.composer.oneAtRows.contains(.write(.question)),
                    "\(names(open.composer.oneAtRows))")
            let secure = field(secureInput: true)
            secure.type("@hello")
            #expect(!secure.composer.oneAtRows.contains(where: asksAI), "\(names(secure.composer.oneAtRows))")
            let noAI = field(secureInput: false, noAI: true)
            noAI.type("@hello")
            #expect(secure.composer.oneAtRows == noAI.composer.oneAtRows, "as with No AI: \(names(noAI.composer.oneAtRows))")
            secure.press(FakeHost.enter)
            #expect(secure.document == "@hello" && !secure.composer.isComposing && secure.composer.phase == .idle,
                    "\(secure.document) \(secure.composer.phase)")
            // The footer says what ⏎ does then.
            let again = field(secureInput: true)
            again.type("@hello")
            #expect(again.panel?.footer.contains("as typed") == true, "\(again.panel?.footer ?? "")")
        }
    }

    /// Secure input on: "@" alone lists the commands that don't use the AI, as in an app with No AI; the local rows stay
    /// (a sum's value).
    @Test func secureInputLeavesTheAICommandsOutOfTheList() async {
        await withInterfaceLanguage("en") {
            let secure = field(secureInput: true)
            secure.type("@")
            let rows = secure.composer.oneAtRows
            #expect(!rows.isEmpty && !rows.contains(where: asksAI), "\(names(rows))")
            #expect(rows.contains(.command(.note)) && !rows.contains(.command(.improve)) && !rows.contains(.command(.translate)))
            let noAI = field(secureInput: false, noAI: true)
            noAI.type("@")
            #expect(rows == noAI.composer.oneAtRows, "as with No AI: \(names(noAI.composer.oneAtRows))")
            let open = field(secureInput: false)
            open.type("@")
            #expect(open.composer.oneAtRows.contains(.command(.improve)), "\(names(open.composer.oneAtRows))")
            let sum = field(secureInput: true)
            sum.type("@3*7")
            #expect(sum.composer.oneAtRows.first == .value("21"), "\(names(sum.composer.oneAtRows))")
            sum.press(FakeHost.enter)
            #expect(sum.document == "21")
        }
    }

    /// Secure input on: an AI command typed by its name is still listed, first, and run it gets the notice it gets under
    /// secure input; nothing is sent.
    @Test func secureInputListsAnAICommandByNameAndRefusesIt() async {
        await withInterfaceLanguage("en") {
            let host = field(secureInput: true)
            host.type("@tr")
            #expect(host.composer.oneAtRows.first == .command(.translate), "\(names(host.composer.oneAtRows))")
            #expect(!host.composer.oneAtRows.dropFirst().contains(where: asksAI), "\(names(host.composer.oneAtRows))")
            host.press(FakeHost.tab)
            host.type("hello")
            #expect(host.composer.draft == "@translate hello")
            host.press(FakeHost.enter)
            #expect(host.composer.phase == .failed("Secure input is on (a password field or the lock screen): nothing was sent to the AI"),
                    "\(host.composer.phase)")
            #expect(host.document.isEmpty)
        }
    }
}

import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The magic key alone, nothing selected (owner, 2026-11-06, after trying 0.7.0): the list is the command list, and ⏎ and
/// the action key do the highlighted row there too, exactly as after a typed name: a command row picks the command (then
/// its text), one that takes no input runs. An empty list types the key as typed. Space, a mark and → after the key give
/// it back as typed and Esc gives it up, as before; with a selection, its rows as before. The same while the selection is
/// still read after the key: a parked ⏎ settled as nothing selected does the row it was pressed on, if still listed.
@Suite(.serialized)
struct OneAtKeyAloneTests {
    // MARK: - Stand-ins

    /// The owner's own commands: a program that runs the text, a terminal command, an AI instruction, and a snippet that
    /// needs nothing typed.
    static let python = CustomCommand(name: "python", type: .run, summary: "Run Python", argv: ["/usr/bin/python3", "-c", "{input}"])
    static let sh = CustomCommand(name: "sh", type: .terminal, summary: "Shell", argv: ["zsh", "-c", "{input}"])
    static let myreply = CustomCommand(name: "myreply", type: .prompt, summary: "My reply", prompt: "Write a short, friendly reply.")
    static let sig = CustomCommand(name: "sig", type: .snippet, summary: "Signature", text: "Best,\nWei")

    /// The on-device model (`Provider.apple`): keeps each request, answers it with one line. Nothing leaves the test.
    final class Model: AppleModelBackend, @unchecked Sendable {
        let availability = AppleModelAvailability.available
        let contextSize = 4096
        let supportedLanguages: Set<String> = ["en", "zh"]
        private let asked = Locked<[AppleModelRequest]>(initialState: [])

        var requests: [AppleModelRequest] { asked.withLock { $0 } }

        func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            asked.withLock { $0.append(request) }
            return AsyncThrowingStream { continuation in
                continuation.yield(AppleModelSnapshot(text: "OK"))
                continuation.finish()
            }
        }
    }

    /// A field with `trigger` the magic key and the owner's commands, the input on English or Chinese, `selected` its text
    /// (all of it selected), the AI on the device (`model`); what the programs and the terminal were given is kept in
    /// `ran` ("python hello", "terminal zsh -c ls"). `secure`: secure input on elsewhere, as the test says.
    struct Field {
        let host: FakeHost
        let model: Model
        let ran: Locked<[String]>

        var composer: Composer { host.composer }
        var rows: [OneAt.Action] { host.composer.oneAtRows }
    }

    func field(_ trigger: String, english: Bool = true, selected: String? = nil, secure: Locked<Bool> = Locked(initialState: false))
        -> Field {
        var config = Config.default
        config.uiLanguage = "en"
        config.commandTrigger = trigger
        config.provider = .apple
        config.claudeInBackground = false
        config.customCommands = [Self.python, Self.sh, Self.myreply, Self.sig]
        let fixed = config, model = Model(), ran = Locked<[String]>(initialState: [])
        var services = SessionServices(converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: model),
                                       loadSettings: { fixed })
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        services.secureInputActive = { secure.withLock { $0 } }
        services.runProgram = { command, input in
            ran.withLock { $0.append("\(command.name) \(input)") }
            return Self.printing(input.uppercased())
        }
        services.launchInTerminal = { argv in ran.withLock { $0.append((["terminal"] + argv).joined(separator: " ")) } }
        let host = FakeHost(services: services)
        if let selected {
            host.document = selected
            host.selection = 0..<(selected as NSString).length
        }
        host.focus()
        host.composer.setInputMode(english ? .english : .chinese)
        return Field(host: host, model: model, ran: ran)
    }

    /// A program's output: `text`, at once.
    static func printing(_ text: String) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(ConversionUpdate(result: ConversionResult(versions: [CandidateLine(text)]), rawText: text,
                                                isFinal: true, elapsed: 0.1, firstTokenLatency: nil, fromCache: false))
            continuation.finish()
        }
    }

    /// The magic key as typed: "@" with Shift, "~" a character.
    static func key(_ trigger: String) -> KeyEvent {
        trigger == "@" ? FakeHost.at : KeyEvent(keyCode: 0, characters: trigger)
    }

    /// The command of a row (nil: another kind of row).
    static func command(_ row: OneAt.Action?) -> Command? {
        if case let .command(command)? = row { return command }
        return nil
    }

    /// ↓ from the first row to the command named `name`: whether it is highlighted then.
    @discardableResult
    func highlight(_ name: String, in field: Field) -> Bool {
        guard let index = field.rows.firstIndex(where: { Self.command($0)?.name == name }) else { return false }
        for _ in 0..<index { field.host.press(FakeHost.down) }
        return field.composer.oneAtHighlighted == index
    }

    static let places: [(trigger: String, english: Bool)] = [("~", true), ("~", false), ("@", true), ("@", false)]

    // MARK: - ⏎ on the key alone

    /// "~" ⏎: the first row's command is picked ("~improve ", its text to follow), nothing typed into the field; "~" ↓ ⏎:
    /// the second's. In English and Chinese mode, with "~" and "@" the magic key.
    @Test func returnOnTheKeyAlonePicksTheHighlightedCommand() async {
        await withInterfaceLanguage("en") {
            for (trigger, english) in Self.places {
                let place = "\(trigger) \(english ? "English" : "Chinese")"
                let first = field(trigger, english: english)
                first.host.type(trigger)
                let rows = first.rows
                guard rows.count > 2, let top = Self.command(rows.first), let second = Self.command(rows[1]) else {
                    Issue.record("\(place): \(rows.map(\.id))")
                    continue
                }
                #expect(first.host.press(FakeHost.enter), "\(place): taken")
                #expect(first.composer.draftCommand == top && first.composer.draft == trigger + top.name + " ",
                        "\(place): \(first.composer.draft)")
                #expect(first.host.document.isEmpty && !first.composer.isLevelTwo && first.composer.phase == .drafting,
                        "\(place): only picked: \(first.host.document) \(first.composer.phase)")

                let down = field(trigger, english: english)
                down.host.type(trigger)
                down.host.press(FakeHost.down)
                down.host.press(FakeHost.enter)
                #expect(down.composer.draftCommand == second && down.composer.draft == trigger + second.name + " ",
                        "\(place): \(down.composer.draft)")
                #expect(down.host.document.isEmpty && down.model.requests.isEmpty && down.ran.withLock { $0 }.isEmpty, "\(place)")
            }
        }
    }

    /// The owner's own commands from the list of the key alone: python (a program) picked with ⏎, then its text, then ⏎
    /// runs it with that text; sh (a terminal command) the same; myreply (an AI instruction) sends its text with it.
    @Test func theUsersOwnCommandPickedFromTheListThenItsTextRuns() async {
        await withInterfaceLanguage("en") {
            for trigger in ["~", "@"] {
                let python = field(trigger)
                python.host.type(trigger)
                #expect(highlight("python", in: python), "\(trigger): \(python.rows.map(\.id))")
                python.host.press(FakeHost.enter)
                #expect(python.composer.draft == trigger + "python " && python.ran.withLock { $0 }.isEmpty, "\(python.composer.draft)")
                python.host.type("hello")
                python.host.press(FakeHost.enter)
                #expect(python.host.settle(timeout: 5) { python.ran.withLock { $0 } == ["python hello"] }, "\(python.ran.withLock { $0 })")

                let sh = field(trigger)
                sh.host.type(trigger)
                #expect(highlight("sh", in: sh), "\(trigger): \(sh.rows.map(\.id))")
                sh.host.press(FakeHost.enter)
                #expect(sh.composer.draft == trigger + "sh ", "\(sh.composer.draft)")
                sh.host.type("ls")
                sh.host.press(FakeHost.enter)
                #expect(sh.host.settle(timeout: 5) { sh.ran.withLock { $0 } == ["terminal zsh -c ls"] }, "\(sh.ran.withLock { $0 })")

                let reply = field(trigger)
                reply.host.type(trigger)
                #expect(highlight("myreply", in: reply), "\(trigger): \(reply.rows.map(\.id))")
                reply.host.press(FakeHost.enter)
                #expect(reply.composer.draft == trigger + "myreply " && reply.model.requests.isEmpty, "\(reply.composer.draft)")
                reply.host.type("see you soon")
                reply.host.press(FakeHost.enter)
                #expect(reply.host.settle(timeout: 5) { !reply.model.requests.isEmpty }, "nothing sent")
                let request = reply.model.requests.first
                #expect((request.map { $0.instructions + $0.prompt } ?? "").contains(Self.myreply.prompt ?? "-")
                        && request?.prompt.contains("see you soon") == true, "\(String(describing: request))")
            }
        }
    }

    /// A command that takes no input runs on ⏎ from the list of the key alone: the snippet goes in at once.
    @Test func aCommandThatTakesNoInputRuns() async {
        await withInterfaceLanguage("en") {
            for (trigger, english) in Self.places {
                let field = field(trigger, english: english)
                field.host.type(trigger)
                #expect(highlight("sig", in: field), "\(trigger): \(field.rows.map(\.id))")
                field.host.press(FakeHost.enter)
                #expect(field.host.document == "Best,\nWei" && !field.composer.isComposing, "\(trigger): \(field.host.document)")
            }
        }
    }

    /// The action key does what ⏎ does there: ⌥Space and the Option tap pick the highlighted command, and Tab picks the
    /// same row. ⏎, when the action key is another, still does the row.
    @Test func theActionKeyAndTabDoTheSameRow() async {
        await withInterfaceLanguage("en") {
            for (trigger, english) in Self.places {
                let place = "\(trigger) \(english ? "English" : "Chinese")"
                let ways: [(String, (Field) -> Void)] = [
                    ("⌥Space", { field in
                        field.composer.actionKey = .optionSpace
                        #expect(field.host.press(optionSpace), "\(place): taken")
                    }),
                    ("the Option tap", { field in
                        field.composer.actionKey = .optionTap
                        field.host.modifiers(ModifierChange(key: .modifier(.option, .left), modifiers: [.option, .leftOption], timestamp: 100))
                        field.host.modifiers(ModifierChange(key: .modifier(.option, .left), modifiers: [], timestamp: 100.1))
                    }),
                    ("Tab", { field in #expect(field.host.press(FakeHost.tab), "\(place): taken") }),
                    ("⏎ with ⌥Space the action key", { field in
                        field.composer.actionKey = .optionSpace
                        #expect(field.host.press(FakeHost.enter), "\(place): taken")
                    }),
                ]
                for (way, press) in ways {
                    let field = field(trigger, english: english)
                    field.host.type(trigger)
                    field.host.press(FakeHost.down)
                    let second = Self.command(field.rows[1])
                    press(field)
                    #expect(second != nil && field.composer.draftCommand == second && field.composer.draft == trigger + (second?.name ?? "-") + " ",
                            "\(place), \(way): \(field.composer.draft)")
                    #expect(field.host.document.isEmpty && field.composer.phase == .drafting, "\(place), \(way): \(field.host.document)")
                }
            }
        }
    }

    /// Nothing at all listed for the key alone: ⏎ and the action key put the key in as typed, never a dead end, and the
    /// footer says so.
    @Test func anEmptyListTypesTheKey() async {
        await withInterfaceLanguage("en") {
            for trigger in ["~", "@"] {
                for actionKey in [ActionKey.enter, .optionSpace] {
                    let c = Composer(engine: FakeEngine(), actionKey: actionKey)
                    c.setInputMode(.english)
                    c.commandTrigger = trigger
                    c.commands = []
                    _ = c.handleKeyDown(Self.key(trigger))
                    #expect(c.oneAt != nil && c.oneAtRows.isEmpty, "\(trigger)")
                    let footer = PanelPresenter(config: .default, language: "en").model(for: c).footer
                    #expect(footer.contains("types it as typed") && footer.hasSuffix("Esc cancel"), "\(footer)")
                    let response = c.handleKeyDown(actionKey == .enter ? enterKey : optionSpace)
                    #expect(commits(response) == [trigger] && response.handled && c.draft.isEmpty, "\(trigger) \(actionKey): \(commits(response))")
                }
            }
        }
    }

    /// Space, a mark and → right after the key give it back as typed, and Esc gives it up, as before.
    @Test func spaceAMarkRightAndEscAreAsBefore() async {
        await withInterfaceLanguage("en") {
            for (trigger, english) in Self.places {
                let place = "\(trigger) \(english ? "English" : "Chinese")"
                for typed in [" ", "/"] {
                    let field = field(trigger, english: english)
                    field.host.appTypesKeys = true
                    field.host.press(Self.key(trigger))
                    field.host.press(typed == " " ? FakeHost.space : KeyEvent(keyCode: 0, characters: typed))
                    #expect(field.host.document.hasPrefix(trigger) && field.host.document.count == 2 && !field.composer.isComposing,
                            "\(place) \(typed): \(field.host.document)")
                    #expect(field.composer.draftCommand == nil && field.ran.withLock { $0 }.isEmpty, "\(place) \(typed)")
                }
                let right = field(trigger, english: english)
                right.host.type(trigger)
                #expect(!right.host.press(FakeHost.right), "\(place): → is the app's")
                #expect(right.host.document == trigger && !right.composer.isComposing, "\(place): \(right.host.document)")
                let escape = field(trigger, english: english)
                escape.host.type(trigger)
                #expect(escape.host.press(FakeHost.escape))
                #expect(escape.host.document.isEmpty && escape.host.marked.isEmpty && !escape.composer.isComposing, "\(place)")
            }
        }
    }

    /// With a selection, the key alone lists the selection's rows, and ⏎ does the first of them on it, as before.
    @Test func withASelectionItIsTheSelectionsRows() async {
        await withInterfaceLanguage("en") {
            for (trigger, english) in Self.places {
                let field = field(trigger, english: english, selected: "The report looks good")
                field.host.type(trigger)
                guard case let .write(first)? = field.rows.first else {
                    Issue.record("\(trigger): \(field.rows.map(\.id))")
                    continue
                }
                field.host.press(FakeHost.enter)
                #expect(field.composer.isLevelTwo && field.composer.activeCommand == first, "\(trigger): \(String(describing: field.composer.activeCommand))")
                #expect(field.host.settle(timeout: 5) { !field.model.requests.isEmpty }, "\(trigger)")
                #expect(field.model.requests.first?.prompt.contains("The report looks good") == true)
            }
        }
    }

    // MARK: - While the selection is read after the key

    /// A field that reads the selection after the key (`selectionFollows`), nothing selected, the read in flight until the
    /// test lands it: the key typed.
    func reading(_ trigger: String, english: Bool = true, secure: Locked<Bool> = Locked(initialState: false)) -> Field {
        let field = field(trigger, english: english, secure: secure)
        field.host.selectionReadsWait = true
        var told = field.host.context
        told.selectionFollows = true
        field.host.press(Self.key(trigger), with: told)
        #expect(field.composer.selectionPending)
        return field
    }

    /// ⏎ on the key alone while the selection is read is parked; settled as nothing selected (the read lands with none,
    /// gives up, or a key comes), it does the row it was pressed on: "~" ↓ ⏎ picks the second command. The action key's
    /// tap and ⌥Space the same. A row no longer listed then (secure input turned on: no AI command) types the key.
    @Test func aParkedReturnOnTheKeyAloneDoesItsRow() async {
        await withInterfaceLanguage("en") {
            for (trigger, english) in Self.places {
                let place = "\(trigger) \(english ? "English" : "Chinese")"
                let settles: [(String, (Field) -> Void)] = [
                    ("the read with none", { $0.host.answerFieldReads() }),
                    ("the read giving up", { $0.host.selectionReadsGiveUp() }),
                    ("a key", { #expect($0.host.press(FakeHost.space), "\(place): Space goes on in the text") }),
                ]
                for (way, settle) in settles {
                    let field = reading(trigger, english: english)
                    field.host.press(FakeHost.down)
                    let second = Self.command(field.rows[1])
                    #expect(field.host.press(FakeHost.enter))
                    #expect(field.composer.parkedForSelection == .key(FakeHost.enter) && field.composer.draftCommand == nil, "\(place), \(way)")
                    settle(field)
                    #expect(second != nil && field.composer.draftCommand == second, "\(place), \(way): \(field.composer.draft)")
                    #expect(field.composer.draft.hasPrefix(trigger + (second?.name ?? "-") + " ") && field.host.document.isEmpty,
                            "\(place), \(way): \(field.composer.draft) | \(field.host.document)")
                    #expect(!field.composer.selectionPending && field.composer.parkedForSelection == nil && field.host.platformActions.isEmpty)
                }

                let space = reading(trigger, english: english)
                #expect(space.rows.first == .command(.improve), "\(place): \(space.rows.map(\.id))")
                space.composer.actionKey = .optionSpace
                #expect(space.composer.whileSelectionIsRead(optionSpace) == .parks, "\(place)")
                #expect(space.host.press(optionSpace))
                space.host.selectionReadsGiveUp()
                #expect(space.composer.draftCommand == .improve && space.composer.draft == trigger + "improve ", "\(place): \(space.composer.draft)")

                let tap = reading(trigger, english: english)
                tap.composer.actionKey = .optionTap
                tap.host.press(FakeHost.down)
                let second = Self.command(tap.rows[1])
                tap.host.modifiers(ModifierChange(key: .modifier(.option, .left), modifiers: [.option, .leftOption], timestamp: 100))
                tap.host.modifiers(ModifierChange(key: .modifier(.option, .left), modifiers: [], timestamp: 100.1))
                #expect(tap.composer.parkedForSelection == .actionKeyTap, "\(place)")
                tap.host.answerFieldReads()
                #expect(second != nil && tap.composer.draftCommand == second, "\(place): the tap: \(tap.composer.draft)")

                // Improve highlighted (the first row), then secure input on before the read gives up: no AI command is
                // listed then, so the key goes in as typed, nothing picked, nothing sent.
                let secure = Locked(initialState: false)
                let gone = reading(trigger, english: english, secure: secure)
                #expect(gone.rows.first == .command(.improve), "\(place): \(gone.rows.map(\.id))")
                gone.host.press(FakeHost.enter)
                secure.withLock { $0 = true }
                gone.host.selectionReadsGiveUp()
                #expect(gone.host.document == trigger && gone.composer.draftCommand == nil && !gone.composer.isComposing,
                        "\(place): \(gone.host.document) \(gone.composer.draft)")
                #expect(gone.model.requests.isEmpty && gone.composer.phase == .idle)
            }
        }
    }
}

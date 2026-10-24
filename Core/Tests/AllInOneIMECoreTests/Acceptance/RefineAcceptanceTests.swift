import CryptoKit
import Foundation
import os
import Testing
@testable import AllInOneIMECore

// Acceptance tests for "Refine the results", written from the user-facing spec (points 1–12), independently of the
// implementation's own tests. Each test names the spec point it checks ("s3" = point 3; "edge" = a case the spec
// implies). The provider is stubbed at the HTTP level (a Claude API endpoint served by `RAStubProtocol`), so what
// was sent can be read back; the input controller is stood in for by `RARig`, which does with the composer's
// effects what `AllInOneIMEInputController` does (`startConversion`, `startCommand`, `startRefine`, secure input).

// MARK: - A provider that records every request

/// Serves queued replies per host and keeps every request body, in order.
final class RAStubProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        /// A streamed Claude API answer with this text.
        case answer(String)
        /// An HTTP error.
        case status(Int)
    }

    private struct State {
        var replies: [String: [Reply]] = [:]
        var bodies: [String: [Data]] = [:]
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func enqueue(_ host: String, _ replies: Reply...) {
        state.withLock { $0.replies[host, default: []] += replies }
    }

    static func bodies(_ host: String) -> [Data] { state.withLock { $0.bodies[host] ?? [] } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RAStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func body(of request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    static func sse(_ text: String) -> Data {
        let delta = try! JSONSerialization.data(withJSONObject: [
            "type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": text],
        ] as [String: Any])
        return Data([
            "event: message_start", #"data: {"type":"message_start","message":{"id":"msg_1"}}"#, "",
            "event: content_block_delta", "data: " + String(decoding: delta, as: UTF8.self), "",
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#, "",
            #"data: {"type":"message_stop"}"#, "", "",
        ].joined(separator: "\n").utf8)
    }

    override func startLoading() {
        let request = self.request
        let host = request.url?.host ?? ""
        let body = Self.body(of: request)
        let reply = Self.state.withLock { state -> Reply in
            state.bodies[host, default: []].append(body)
            guard var queue = state.replies[host], !queue.isEmpty else { return .status(599) }
            let next = queue.removeFirst()
            state.replies[host] = queue
            return next
        }
        guard let url = request.url else { return }
        switch reply {
        case let .answer(text):
            let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.sse(text))
        case let .status(code):
            let http = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"type":"error","error":{"type":"api_error","message":"boom"}}"#.utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A request as the Claude API got it.
struct RASent {
    var system: String
    /// (role, text), oldest first.
    var messages: [(role: String, text: String)]

    init(_ data: Data) throws {
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        system = json["system"] as? String ?? ""
        let raw = try #require(json["messages"] as? [[String: Any]])
        messages = raw.map { ($0["role"] as? String ?? "", $0["content"] as? String ?? "") }
    }

    var lastUser: String { messages.last { $0.role == "user" }?.text ?? "" }
    var assistantTexts: [String] { messages.filter { $0.role == "assistant" }.map(\.text) }
}

// MARK: - Keys

private let raAt = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
private let raTab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
private let raOptionSpace = KeyEvent(keyCode: VirtualKey.space, characters: "\u{A0}", charactersIgnoringModifiers: " ", modifiers: .option)

// MARK: - The input controller, stood in for

/// A composer with a fake pinyin engine, wired to a `Converter` whose provider is `RAStubProtocol` at `host`.
final class RARig {
    let engine = FakeEngine()
    let composer: Composer
    let host: String
    let converter: Converter
    /// Every effect the composer returned for keys, in order.
    var effects: [Composer.Effect] = []
    /// Secure input on: requests are refused as the input controller refuses them.
    var secureInput = false
    static let secureMessage = "Secure input is on (a password field or the lock screen): nothing was sent to the AI"

    init(host: String = "refine-\(UUID().uuidString.lowercased()).test", actionKey: ActionKey = .enter,
         outputLanguages: [OutputLanguage] = [.english], styles: [String] = [],
         selection: Composer.Selection? = nil, commands: [Command] = Command.builtins) {
        self.host = host
        composer = Composer(engine: engine, actionKey: actionKey)
        composer.commands = commands
        if let selection { composer.readSelection = { selection } }
        var config = Config.default
        config.provider = .anthropic
        config.anthropic.baseURL = "https://\(host)"
        config.rewriteStyles = styles
        config.outputLanguages = outputLanguages
        let fixed = config
        converter = Converter(client: BedrockClient(session: RAStubProtocol.session()), loadConfig: { fixed },
                              loadKey: { provider, _ in provider == .anthropic ? "sk-test" : nil },
                              loadJargon: { _ in [] })
    }

    var c: Composer { composer }

    @discardableResult
    func key(_ event: KeyEvent) -> [Composer.Effect] {
        let out = composer.handleKeyDown(event).effects
        effects += out
        return out
    }

    /// Each character as a key (English letters as typed, pinyin through the fake engine in Chinese).
    @discardableResult
    func type(_ s: String) -> [Composer.Effect] {
        s.flatMap { ch -> [Composer.Effect] in
            let text = String(ch)
            let shifted = ch.isUppercase
            return key(KeyEvent(keyCode: 0, characters: text, modifiers: shifted ? .shift : []))
        }
    }

    /// "@", the palette letters, Tab: "@name ".
    func pick(_ letters: String) {
        key(raAt)
        type(letters)
        key(raTab)
    }

    func shiftTap(at t: Double) -> [Composer.Effect] {
        _ = composer.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: t)
        return composer.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: t + 0.1)
    }

    /// The requests the provider got, decoded.
    func sent() throws -> [RASent] { try RAStubProtocol.bodies(host).map(RASent.init) }

    /// Does what the input controller does with the start effects among `effects`, to the end of each stream.
    func perform(_ effects: [Composer.Effect]) async {
        for effect in effects {
            let stream: AsyncThrowingStream<ConversionUpdate, Error>
            let id: Int
            switch effect {
            case let .startConversion(input, rid):
                id = rid
                if secureInput { _ = composer.fail(Self.secureMessage, id: id); continue }
                let command = composer.activeCommand?.kind == .convert ? composer.activeCommand : nil
                let (mode, text) = WritingMode.parse(command, input)
                stream = converter.convert(text, mode: mode)
            case let .startCommand(command, input, rid):
                id = rid
                if secureInput { _ = composer.fail(Self.secureMessage, id: id); continue }
                stream = converter.generate(command, input: input)
            case let .startRefine(refinement, rid):
                id = rid
                if secureInput { _ = composer.fail(Self.secureMessage, id: id); continue }
                switch refinement.request {
                case let .writing(command, input):
                    let (mode, text) = WritingMode.parse(command?.kind == .convert ? command : nil, input)
                    stream = converter.convert(text, mode: mode, turns: refinement.turns)
                case let .command(command, input):
                    stream = converter.generate(command, input: input, turns: refinement.turns)
                }
            default:
                continue
            }
            do {
                for try await update in stream {
                    lastFromCache = update.fromCache
                    _ = composer.receive(update.result, isFinal: update.isFinal, id: id)
                }
            } catch {
                _ = composer.fail("failed: \(error)", id: id)
            }
        }
    }

    var lastFromCache = false

    /// A key, and what the input controller would do with its effects.
    @discardableResult
    func press(_ event: KeyEvent) async -> [Composer.Effect] {
        let out = key(event)
        await perform(out)
        return out
    }

    /// The rows shown (not the original, row 0).
    var rows: [String] { composer.choices.filter { $0.kind != .original }.map(\.text) }
}

/// Nothing goes into the field nor is marked there (a command on a selection works in the panel only).
func raLeavesTheField(_ effects: [Composer.Effect]) -> Bool {
    !effects.contains { effect in
        switch effect {
        case .updateMarkedText, .commit, .replaceSelection, .typeOut: return true
        default: return false
        }
    }
}

func raReplaced(_ effects: [Composer.Effect]) -> [String] {
    effects.compactMap { if case let .replaceSelection(s, _) = $0 { return s } else { return nil } }
}

func raRefines(_ effects: [Composer.Effect]) -> [Refinement] {
    effects.compactMap { if case let .startRefine(r, _) = $0 { return r } else { return nil } }
}

func raStartsSomething(_ effects: [Composer.Effect]) -> Bool {
    effects.contains {
        switch $0 {
        case .startRefine, .startConversion, .startCommand: return true
        default: return false
        }
    }
}

// MARK: - The tests

struct RefineAcceptanceTests {
    let sentence = "i has a apple"
    let first = ConversionResult(versions: [
        CandidateLine("I have an apple."), CandidateLine("I've got an apple."), CandidateLine("I own an apple."),
    ])
    let shorter = ConversionResult(versions: [
        CandidateLine("An apple."), CandidateLine("Got an apple."), CandidateLine("Apple here."),
    ])
    let formal = ConversionResult(versions: [
        CandidateLine("I am in possession of an apple."), CandidateLine("I possess an apple."), CandidateLine("An apple is mine."),
    ])

    /// The answer the model writes for `result` (versions in English, no styles).
    func lines(_ result: ConversionResult) -> String {
        result.versions.map { "EN: \($0.text)" }.joined(separator: "\n")
    }

    /// "@improve i has a apple" in English, ⏎, and `result` in as request 1 (no network).
    func improveShown(_ rig: RARig = RARig(), result: ConversionResult? = nil) -> RARig {
        rig.c.setInputMode(.english)
        rig.pick("i")
        #expect(rig.c.draft == "@improve ")
        rig.type(sentence)
        let run = rig.key(enterKey)
        #expect(run.contains(.startConversion(input: sentence, id: 1)))
        _ = rig.c.receive(result ?? first, isFinal: true, id: 1)
        #expect(rig.c.phase == .choosing && rig.rows == (result ?? first).versions.map(\.text))
        return rig
    }

    /// The same through the stubbed provider: the first answer is `first`.
    func improveShownOnline(_ rig: RARig = RARig()) async -> RARig {
        RAStubProtocol.enqueue(rig.host, .answer(lines(first)))
        rig.c.setInputMode(.english)
        rig.pick("i")
        rig.type(sentence)
        await rig.press(enterKey)
        #expect(rig.c.phase == .choosing && rig.rows == first.versions.map(\.text))
        return rig
    }

    /// Types `instruction` into the refine line (Space as the Space key), then ⇧⏎ when `run`. With `run`, what ⇧⏎ did;
    /// without, what the typing did. (0.6.4: ⇧⏎ sends a refine, ⏎ inserts.)
    @discardableResult
    func refine(_ rig: RARig, _ instruction: String, run: Bool = true) -> [Composer.Effect] {
        var typed: [Composer.Effect] = []
        for ch in instruction {
            typed += ch == " " ? rig.key(spaceKey) : rig.type(String(ch))
        }
        return run ? rig.key(acceptanceShiftReturn) : typed
    }

    func refineOnline(_ rig: RARig, _ instruction: String, answer: RAStubProtocol.Reply) async -> [Composer.Effect] {
        RAStubProtocol.enqueue(rig.host, answer)
        let effects = refine(rig, instruction)
        await rig.perform(effects)
        return effects
    }

    // MARK: 1. Which results

    @Test func s1_improveTranslateQuestionPromptAndEditResultsAcceptARefine() {
        // @improve
        let improve = improveShown()
        improve.type("s")
        #expect(improve.c.canRefine && improve.c.refineLine == "s", "@improve")

        // @translate
        let translate = RARig()
        translate.c.setInputMode(.english)
        translate.pick("t")
        #expect(translate.c.draft == "@translate ")
        translate.type("hello")
        #expect(translate.key(enterKey).contains(.startConversion(input: "hello", id: 1)))
        _ = translate.c.receive(ConversionResult(versions: [CandidateLine("你好")]), isFinal: true, id: 1)
        // 0.6.4: @translate has no refine: a letter goes back to its text, which ⏎ translates again.
        #expect(!translate.c.canRefine, "@translate")
        translate.type("s")
        #expect(translate.c.refineLine == nil && !translate.c.isLevelTwo && translate.c.draft == "@translate hellos", "@translate")

        // @question
        let question = RARig()
        question.c.setInputMode(.english)
        question.pick("q")
        #expect(question.c.draft == "@question ")
        question.type("what is a monad")
        #expect(question.key(enterKey).contains(.startCommand(.question, input: "what is a monad", id: 1)))
        _ = question.c.receive(ConversionResult(versions: [CandidateLine("A monad is a monoid in the category of endofunctors.")]),
                               isFinal: true, id: 1)
        question.type("s")
        #expect(question.c.refineLine == "s", "@question")

        // A prompt custom command
        let reply = CustomCommand(name: "respond", type: .prompt, prompt: "Write a polite reply.")
        let catalog = Command.catalog([reply])
        let custom = RARig(commands: catalog)
        custom.c.setInputMode(.english)
        custom.pick("resp")
        #expect(custom.c.draft == "@respond ")
        custom.type("thanks for the invite")
        let start = custom.key(enterKey)
        #expect(start.contains { if case let .startCommand(c, _, _) = $0 { return c.name == "respond" } else { return false } })
        _ = custom.c.receive(ConversionResult(versions: [CandidateLine("Thank you, I'd be glad to come.")]), isFinal: true, id: 1)
        custom.type("s")
        #expect(custom.c.refineLine == "s", "prompt command")

        // The edit mode on a selection ("@improve more formal" with a text selected)
        let edit = RARig(selection: Composer.Selection(text: "this sentance have a error", range: 11..<37))
        edit.c.setInputMode(.english)
        edit.pick("i")
        refine(edit, "more formal", run: false)
        let editStart = edit.key(enterKey)
        #expect(editStart.contains { if case .startCommand(.edit, _, 1) = $0 { return true } else { return false } })
        _ = edit.c.receive(ConversionResult(versions: [CandidateLine("This sentence contains an error.")]), isFinal: true, id: 1)
        edit.type("s")
        #expect(edit.c.refineLine == "s", "edit mode on a selection")
    }

    @Test func s1_openKeepsItsOldKeys() {
        let rig = RARig()
        rig.c.setInputMode(.english)
        rig.pick("ope")
        #expect(rig.c.draft == "@open ")
        rig.type("notes")
        #expect(rig.key(enterKey).contains(.search(query: "notes", id: 1)))
        _ = rig.c.receiveSearch([SearchResult(name: "Notes", path: "/System/Applications/Notes.app")], id: 1)
        #expect(!rig.c.canRefine)
        // As before: a letter goes back to the draft and continues it.
        rig.type("x")
        #expect(rig.c.refineLine == nil && !rig.c.isLevelTwo && rig.c.draft == "@open notesx")
    }

    @Test func s1_programsKeepTheirOldKeys() {
        let python = CustomCommand(name: "python", type: .run, argv: ["python3", "-c", "{input}"])
        let rig = RARig(commands: Command.catalog([python]))
        rig.pick("pyt")
        #expect(rig.c.draft == "@python ")
        rig.type("print(1)")
        let run = rig.key(enterKey)
        #expect(run.contains { if case .startRun = $0 { return true } else { return false } })
        _ = rig.c.receive(ConversionResult(versions: [CandidateLine("1")]), isFinal: true, id: 1)
        #expect(!rig.c.canRefine)
        rig.type("x")
        #expect(rig.c.refineLine == nil && !rig.c.isLevelTwo && rig.c.draft == "@python print(1)x")
    }

    @Test func s1_remindersKeepTheirOldKeys() {
        let rig = RARig()
        rig.pick("rem")
        #expect(rig.c.draft == "@reminder ")
        rig.type("nihao")
        let run = rig.key(enterKey)
        #expect(run.contains { if case .previewReminder = $0 { return true } else { return false } })
        _ = rig.c.receiveReminder(ReminderDraft(title: "你好"), id: 1)
        #expect(!rig.c.canRefine)
        // A letter (pinyin) goes back to the reminder's text, as before.
        rig.type("w")
        #expect(rig.c.refineLine == nil && !rig.c.isLevelTwo && rig.c.draft.hasPrefix("@reminder 你好"))
    }

    // MARK: 2. Starting a refine

    @Test func s2_aLetterStartsTheLineAndPinyinIsPickedFromItsCandidates() {
        let rig = RARig()
        rig.engine.dictionary["gengkouyu"] = ["更口语", "更口雨"]
        rig.engine.dictionary["yidian"] = ["一点", "亿点"]
        // Chinese: "@improve 你好" ⏎
        rig.pick("i")
        rig.type("nihao")
        #expect(rig.key(enterKey).contains(.startConversion(input: "你好", id: 1)))
        let zh = ConversionResult(versions: [CandidateLine("您好"), CandidateLine("你好呀"), CandidateLine("嗨")])
        _ = rig.c.receive(zh, isFinal: true, id: 1)
        #expect(rig.c.refineLine == nil)
        rig.type("gengkouyu")
        // The line has started with the pinyin; its candidates are offered.
        #expect(rig.c.refineLine == "gengkouyu" && rig.c.refineIsComposing)
        #expect(rig.c.engineState.candidates.map(\.text) == ["更口语", "更口雨"])
        // The results are still the ones shown.
        #expect(rig.c.isLevelTwo && rig.rows == zh.versions.map(\.text))
        // Space picks the first candidate, into the line (nothing is inserted in the document).
        let picked = rig.key(spaceKey)
        #expect(commits(picked).isEmpty && rig.c.refineText == "更口语" && !rig.c.refineIsComposing)
        // A digit picks another candidate while pinyin is typed.
        rig.type("yidian")
        let two = rig.key(k("2"))
        #expect(commits(two).isEmpty && rig.c.refineText == "更口语亿点")
        // A click on a candidate picks it too.
        rig.type("yidian")
        let click = rig.c.choose(index: 0)
        #expect(commits(click).isEmpty && rig.c.refineText == "更口语亿点一点")
        #expect(rig.c.isLevelTwo && rig.rows == zh.versions.map(\.text))
    }

    // MARK: 3. Running it

    @Test func s3_returnSendsTheOriginalTheResultsAndTheInstruction() {
        let rig = improveShown()
        let run = refine(rig, "shorter")
        let refinement = try? #require(raRefines(run).first)
        #expect(refinement?.request == .writing(.improve, input: sentence))
        #expect(refinement?.turns == [Refinement.Turn(answer: first, instruction: "shorter")])
        #expect(run.contains(.startRefine(refinement!, id: 2)))
        // Nothing went into the document.
        #expect(commits(run).isEmpty && rig.c.isRefining && rig.c.refineText.isEmpty)
        // The new results replace the old ones in the same panel; row 0 is still the sentence as typed.
        _ = rig.c.receive(shorter, isFinal: true, id: 2)
        #expect(rig.c.phase == .choosing && rig.rows == shorter.versions.map(\.text))
        #expect(rig.c.choices.first?.kind == .original && rig.c.choices.first?.text == sentence)
        // Picking inserts the refined row.
        #expect(commits(rig.key(enterKey)) == [shorter.versions[0].text])
    }

    @Test func s3_itCanBeRepeated() {
        let rig = improveShown()
        refine(rig, "shorter")
        _ = rig.c.receive(shorter, isFinal: true, id: 2)
        let again = refine(rig, "more formal")
        let refinement = raRefines(again).first
        #expect(refinement?.turns == [
            Refinement.Turn(answer: first, instruction: "shorter"),
            Refinement.Turn(answer: shorter, instruction: "more formal"),
        ])
        _ = rig.c.receive(formal, isFinal: true, id: 3)
        #expect(rig.rows == formal.versions.map(\.text))
    }

    @Test func s3_theActionKeyRunsItToo() {
        // ⌥Space
        let option = improveShown(RARig(actionKey: .optionSpace))
        refine(option, "shorter", run: false)
        let viaOptionSpace = option.key(raOptionSpace)
        #expect(raRefines(viaOptionSpace).first?.turns.last?.instruction == "shorter")
        // A recorded shortcut (⌃⏎).
        let shortcut = KeyShortcut(keyCode: VirtualKey.returnKey, modifiers: .control, name: "⌃⏎")
        let ctrl = improveShown(RARig(actionKey: .shortcut(shortcut)))
        refine(ctrl, "shorter", run: false)
        let viaShortcut = ctrl.key(KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .control))
        #expect(raRefines(viaShortcut).first?.turns.last?.instruction == "shorter")
        // ⇧⏎ runs it when ⏎ isn't the action key too (0.6.4: ⏎ inserts).
        let enter = improveShown(RARig(actionKey: .optionSpace))
        let viaEnter = refine(enter, "shorter")
        #expect(raRefines(viaEnter).first?.turns.last?.instruction == "shorter")
    }

    @Test func s3_theWritingRequestCarriesTheSentenceTheResultsAndTheInstruction() async throws {
        let rig = await improveShownOnline()
        _ = await refineOnline(rig, "shorter", answer: .answer(lines(shorter)))
        #expect(rig.rows == shorter.versions.map(\.text))
        let sent = try rig.sent()
        try #require(sent.count == 2)
        let (normal, followUp) = (sent[0], sent[1])
        // The first request, untouched, starts the follow-up: the sentence is intact.
        #expect(normal.lastUser == sentence)
        #expect(followUp.messages.count == normal.messages.count + 2)
        #expect(zip(normal.messages, followUp.messages).allSatisfy { $0.role == $1.role && $0.text == $1.text })
        // Then the results shown, as the model's answer, and the instruction.
        let answer = followUp.messages[normal.messages.count]
        #expect(answer.role == "assistant")
        for row in first.versions { #expect(answer.text.contains(row.text)) }
        let ask = followUp.messages[normal.messages.count + 1]
        #expect(ask.role == "user" && ask.text.contains("shorter") && !ask.text.contains(sentence))
        // The follow-up's system prompt keeps the rules of the first one.
        #expect(followUp.system.hasPrefix(normal.system))

        // A second refine sends the whole conversation: both answers and both instructions, in order.
        _ = await refineOnline(rig, "more formal", answer: .answer(lines(formal)))
        let third = try rig.sent()[2]
        #expect(third.messages.count == normal.messages.count + 4)
        #expect(third.messages[normal.messages.count + 2].role == "assistant")
        for row in shorter.versions { #expect(third.messages[normal.messages.count + 2].text.contains(row.text)) }
        #expect(third.lastUser.contains("more formal") && third.messages[normal.messages.count + 1].text.contains("shorter"))
        #expect(rig.rows == formal.versions.map(\.text))
    }

    @Test func s3_theCommandRequestCarriesTheQuestionTheAnswerAndTheInstruction() async throws {
        let rig = RARig()
        let answer = "A monad is a way to chain computations that carry context, such as optional values or effects."
        RAStubProtocol.enqueue(rig.host, .answer(answer), .answer("A monad chains computations with context."))
        rig.c.setInputMode(.english)
        rig.pick("q")
        rig.type("what is a monad")
        await rig.press(enterKey)
        #expect(rig.rows == [answer])
        await rig.perform(refine(rig, "shorter"))
        let sent = try rig.sent()
        try #require(sent.count == 2)
        #expect(sent[0].messages.map(\.text) == ["what is a monad"])
        #expect(sent[1].messages.map(\.role) == ["user", "assistant", "user"])
        #expect(sent[1].messages[0].text == "what is a monad" && sent[1].messages[1].text == answer)
        #expect(sent[1].messages[2].text.contains("shorter"))
        // 0.6.4: @question is a conversation: every round's answer is a row (no row 0), the latest selected.
        #expect(rig.rows == [answer, "A monad chains computations with context."])
        #expect(rig.c.choices[rig.c.highlighted].text == "A monad chains computations with context.")
    }

    // MARK: 4. Keys with an empty line

    @Test func s4_withAnEmptyLineDigitsSpaceReturnAndArrowsAreAsBefore() {
        // A digit picks its row.
        let digit = improveShown()
        #expect(commits(digit.key(k("2"))) == [first.versions[1].text])
        // Space inserts the highlighted row (the first version).
        let space = improveShown()
        #expect(space.c.highlighted == 1)
        #expect(commits(space.key(spaceKey)) == [first.versions[0].text])
        // ⏎ inserts it too.
        let enter = improveShown()
        #expect(commits(enter.key(enterKey)) == [first.versions[0].text])
        // ↓ ↓ ↑ move, then ⏎ inserts the row moved to.
        let arrows = improveShown()
        arrows.key(downKey)
        arrows.key(downKey)
        #expect(arrows.c.highlighted == 3)
        arrows.key(upKey)
        #expect(arrows.c.highlighted == 2)
        #expect(commits(arrows.key(enterKey)) == [first.versions[1].text])
        // 0 is the sentence as typed.
        let zero = improveShown()
        #expect(commits(zero.key(k("0"))) == [sentence])
    }

    @Test func s4_afterARefineAndAnEmptiedLineTheKeysAreStillAsBefore() {
        let rig = improveShown()
        refine(rig, "shorter")
        _ = rig.c.receive(shorter, isFinal: true, id: 2)
        // A line typed and deleted again: empty.
        rig.type("ab")
        rig.key(backspaceKey)
        rig.key(backspaceKey)
        #expect(rig.c.refineLine == nil && rig.c.refineText.isEmpty)
        rig.key(downKey)
        #expect(rig.c.highlighted == 2)
        #expect(commits(rig.key(k("3"))) == [shorter.versions[2].text])
    }

    // MARK: 5. Keys with text in the line

    @Test func s5_spaceDigitsAndPunctuationAreTextAndBackspaceDeletes() {
        let rig = improveShown()
        let typed = refine(rig, "make it 2 lines, please!", run: false)
        #expect(commits(typed).isEmpty && rig.c.refineText == "make it 2 lines, please!")
        #expect(rig.c.isLevelTwo && rig.rows == first.versions.map(\.text) && !rig.c.isRefining)
        rig.key(backspaceKey)
        rig.key(backspaceKey)
        #expect(rig.c.refineText == "make it 2 lines, pleas" && rig.c.isLevelTwo, "line: \(rig.c.refineText.debugDescription)")
        // ⇧⏎ sends exactly what is in the line.
        #expect(raRefines(rig.key(acceptanceShiftReturn)).first?.turns.last?.instruction == "make it 2 lines, pleas")
    }

    @Test func edge_aDigitInANonEmptyLineDoesNotPickARow() {
        let rig = improveShown()
        rig.type("v")
        let digit = rig.key(k("2"))
        #expect(commits(digit).isEmpty && rig.c.refineText == "v2" && rig.c.isLevelTwo)
        let zero = rig.key(k("0"))
        #expect(commits(zero).isEmpty && rig.c.refineText == "v20")
        // Space too.
        let space = rig.key(spaceKey)
        #expect(commits(space).isEmpty && rig.c.refineText == "v20 ")
    }

    @Test func s5_backspaceDeletesAWholeCJKCharacter() {
        let rig = RARig()
        rig.engine.dictionary["gengkouyu"] = ["更口语"]
        rig.pick("i")
        rig.type("nihao")
        rig.key(enterKey)
        _ = rig.c.receive(ConversionResult(versions: [CandidateLine("您好")]), isFinal: true, id: 1)
        rig.type("gengkouyu")
        rig.key(spaceKey)
        #expect(rig.c.refineText == "更口语")
        rig.key(backspaceKey)
        #expect(rig.c.refineText == "更口")
    }

    // MARK: 6. Esc

    @Test func s6_escClearsTheLineThenStepsBackThenGoesToTheDraft() {
        let rig = improveShown()
        refine(rig, "shorter")
        _ = rig.c.receive(shorter, isFinal: true, id: 2)
        refine(rig, "more formal")
        _ = rig.c.receive(formal, isFinal: true, id: 3)
        #expect(rig.rows == formal.versions.map(\.text))
        // A non-empty line: Esc clears it, the results stay.
        rig.type("in french")
        rig.key(escKey)
        #expect(rig.c.refineText.isEmpty && rig.c.refineLine == nil && rig.rows == formal.versions.map(\.text))
        // Empty: back one step at a time.
        rig.key(escKey)
        #expect(rig.c.isLevelTwo && rig.rows == shorter.versions.map(\.text))
        rig.key(escKey)
        #expect(rig.c.isLevelTwo && rig.rows == first.versions.map(\.text))
        // No refines left: back to the draft, as before.
        let back = rig.key(escKey)
        #expect(!rig.c.isLevelTwo && rig.c.draft == "@improve " + sentence && commits(back).isEmpty)
    }

    @Test func s6_escWithNoRefineGoesBackToTheDraftAsBefore() {
        let rig = improveShown()
        rig.key(escKey)
        #expect(!rig.c.isLevelTwo && rig.c.draft == "@improve " + sentence)
    }

    @Test func s6_escWhileARefineRunsStopsItAndShowsTheResultsBefore() {
        let rig = improveShown()
        refine(rig, "shorter")
        _ = rig.c.receive(ConversionResult(versions: [CandidateLine("An", isComplete: false)]), isFinal: false, id: 2)
        let esc = rig.key(escKey)
        #expect(esc.contains(.cancelConversion))
        #expect(rig.c.phase == .choosing && rig.rows == first.versions.map(\.text) && rig.c.refineHistory.isEmpty)
        // What still arrives for the stopped refine is ignored.
        _ = rig.c.receive(shorter, isFinal: true, id: 2)
        #expect(rig.rows == first.versions.map(\.text))
    }

    // MARK: 7. History

    @Test func s7_theHistoryListsTheInstructionsInOrder() {
        let rig = improveShown()
        #expect(rig.c.refineHistory.isEmpty)
        refine(rig, "shorter")
        _ = rig.c.receive(shorter, isFinal: true, id: 2)
        refine(rig, "more formal")
        _ = rig.c.receive(formal, isFinal: true, id: 3)
        #expect(rig.c.refineHistory == ["shorter", "more formal"])
        #expect(rig.c.refineHistory.joined(separator: " · ") == "shorter · more formal")
    }

    @Test func edge_theHistoryAfterGoingBackAStep() {
        let rig = improveShown()
        refine(rig, "shorter")
        _ = rig.c.receive(shorter, isFinal: true, id: 2)
        refine(rig, "more formal")
        _ = rig.c.receive(formal, isFinal: true, id: 3)
        rig.key(escKey)
        #expect(rig.c.refineHistory == ["shorter"] && rig.rows == shorter.versions.map(\.text))
        // A new step after going back continues from there.
        refine(rig, "warmer")
        let warmer = ConversionResult(versions: [CandidateLine("Got a lovely apple!")])
        _ = rig.c.receive(warmer, isFinal: true, id: 4)
        #expect(rig.c.refineHistory == ["shorter", "warmer"])
        rig.key(escKey)
        rig.key(escKey)
        #expect(rig.c.refineHistory.isEmpty && rig.rows == first.versions.map(\.text))
        // A new request starts without history.
        rig.key(escKey)
        rig.key(enterKey)
        _ = rig.c.receive(first, isFinal: true, id: 5)
        #expect(rig.c.refineHistory.isEmpty)
    }

    // MARK: 8. Failures

    @Test func s8_aNetworkErrorKeepsTheResultsAndTheInstructionAndRetryWorks() async throws {
        let rig = await improveShownOnline()
        _ = await refineOnline(rig, "shorter", answer: .status(500))
        #expect(rig.c.phase == .choosing && rig.rows == first.versions.map(\.text))
        #expect(rig.c.refineText == "shorter" && rig.c.refineError != nil && rig.c.refineHistory.isEmpty)
        // ⇧⏎ again tries again.
        RAStubProtocol.enqueue(rig.host, .answer(lines(shorter)))
        await rig.press(acceptanceShiftReturn)
        #expect(rig.rows == shorter.versions.map(\.text) && rig.c.refineHistory == ["shorter"] && rig.c.refineText.isEmpty)
        #expect(try rig.sent().count == 3)
    }

    @Test func s8_anEmptyAnswerKeepsTheResultsAndTheInstruction() async throws {
        let rig = await improveShownOnline()
        _ = await refineOnline(rig, "shorter", answer: .answer(""))
        #expect(rig.c.phase == .choosing && rig.rows == first.versions.map(\.text))
        #expect(rig.c.refineText == "shorter" && rig.c.refineError != nil)
        RAStubProtocol.enqueue(rig.host, .answer(lines(shorter)))
        await rig.press(acceptanceShiftReturn)
        #expect(rig.rows == shorter.versions.map(\.text))
    }

    @Test func s8_secureInputKeepsTheResultsAndTheInstruction() async throws {
        let rig = await improveShownOnline()
        rig.secureInput = true
        _ = await refineOnline(rig, "shorter", answer: .answer(lines(shorter)))
        #expect(try rig.sent().count == 1)  // nothing was sent
        #expect(rig.rows == first.versions.map(\.text))
        #expect(rig.c.refineText == "shorter" && rig.c.refineError == RARig.secureMessage)
        rig.secureInput = false
        await rig.press(acceptanceShiftReturn)
        #expect(rig.rows == shorter.versions.map(\.text) && rig.c.refineError == nil)
    }

    @Test func s8_aFailureAfterPartOfTheAnswerKeepsTheResultsBefore() {
        let rig = improveShown()
        refine(rig, "shorter")
        _ = rig.c.receive(ConversionResult(versions: [CandidateLine("An app", isComplete: false)]), isFinal: false, id: 2)
        _ = rig.c.fail("The network connection was lost.", id: 2)
        #expect(rig.c.phase == .choosing && rig.rows == first.versions.map(\.text))
        #expect(rig.c.refineText == "shorter" && rig.c.refineError == "The network connection was lost.")
        // The next key clears the error; ⇧⏎ runs the same instruction again.
        let retry = rig.key(acceptanceShiftReturn)
        #expect(raRefines(retry).first?.turns == [Refinement.Turn(answer: first, instruction: "shorter")])
    }

    // MARK: 9. Selection mode

    let selected = "this sentance have a error"
    var selection: Composer.Selection { Composer.Selection(text: selected, range: 11..<37) }

    @Test func s9_onASelectionRefiningNeverTouchesTheDocumentAndThePickReplacesExactlyIt() async throws {
        let rig = RARig(selection: selection)
        RAStubProtocol.enqueue(rig.host, .answer(lines(first)))
        rig.c.setInputMode(.english)
        rig.pick("i")
        #expect(rig.c.selectionInUse == selected)
        let run = await rig.press(enterKey)
        #expect(run.contains(.startConversion(input: selected, id: 1)))
        #expect(rig.rows == first.versions.map(\.text))
        var effects = run
        effects += await refineOnline(rig, "shorter", answer: .answer(lines(shorter)))
        effects += refine(rig, "more formal", run: false)
        rig.key(escKey)  // clears the line
        // Every key so far stayed in the panel.
        #expect(raLeavesTheField(rig.effects), "\(rig.effects)")
        #expect(raLeavesTheField(effects))
        // The refine was sent with the selection as the sentence.
        let sent = try rig.sent()
        #expect(sent.count == 2 && sent[0].lastUser == selected)
        #expect(sent[1].messages.dropLast(2).last?.text == selected)
        // Picking replaces exactly the selection, with the refined row.
        let pick = rig.key(k("2"))
        #expect(pick.contains(.replaceSelection(shorter.versions[1].text, selection)) && commits(pick).isEmpty)
        #expect(raReplaced(pick).count == 1)
    }

    @Test func s9_theEditModeOnASelectionCanBeRefined() async throws {
        let rig = RARig(selection: selection)
        RAStubProtocol.enqueue(rig.host, .answer("This sentence contains an error."), .answer("It has an error."))
        rig.c.setInputMode(.english)
        rig.pick("i")
        refine(rig, "more formal", run: false)
        let run = await rig.press(enterKey)
        let editInput = Prompt.editRequest(instruction: "improve: more formal", text: selected)
        #expect(run.contains(.startCommand(.edit, input: editInput, id: 1)))
        #expect(rig.rows == ["This sentence contains an error."])
        _ = await refineOnline(rig, "shorter", answer: .answer("It has an error."))
        #expect(rig.rows == ["It has an error."] && raLeavesTheField(rig.effects))
        let sent = try rig.sent()
        try #require(sent.count == 2)
        #expect(sent[1].messages.map(\.role) == ["user", "assistant", "user"])
        #expect(sent[1].messages[0].text == editInput && sent[1].messages[1].text == "This sentence contains an error.")
        #expect(sent[1].system.hasPrefix(sent[0].system))
        let pick = rig.key(enterKey)
        #expect(raReplaced(pick) == ["It has an error."] && pick.contains(.replaceSelection("It has an error.", selection)))
    }

    @Test func edge_aRefineAfterASelectionWithEscAllTheWayBack() {
        let rig = RARig(selection: selection)
        rig.c.setInputMode(.english)
        rig.pick("i")
        rig.key(enterKey)
        _ = rig.c.receive(first, isFinal: true, id: 1)
        refine(rig, "shorter")
        _ = rig.c.receive(shorter, isFinal: true, id: 2)
        refine(rig, "more formal")
        _ = rig.c.receive(formal, isFinal: true, id: 3)
        rig.key(escKey)
        #expect(rig.rows == shorter.versions.map(\.text))
        rig.key(escKey)
        #expect(rig.rows == first.versions.map(\.text) && rig.c.isLevelTwo)
        rig.key(escKey)
        // Back to the command written on the selection, in the panel; the selection still the same.
        #expect(!rig.c.isLevelTwo && rig.c.draft == "@improve " && rig.c.selection == selection && rig.c.draftInPanel)
        #expect(raLeavesTheField(rig.effects), "\(rig.effects)")
        let cancel = rig.key(escKey)
        #expect(raReplaced(cancel).isEmpty && commits(cancel).isEmpty)
        #expect(raReplaced(rig.effects).isEmpty && commits(rig.effects).isEmpty)
    }

    // MARK: 10. Cache

    @Test func s10_theSameRefineOfTheSameResultsComesFromTheCache() async throws {
        let rig = await improveShownOnline()
        _ = await refineOnline(rig, "shorter", answer: .answer(lines(shorter)))
        #expect(try rig.sent().count == 2 && !rig.lastFromCache)
        // Back to the first results, the same instruction again: no request, the same results.
        rig.key(escKey)
        #expect(rig.rows == first.versions.map(\.text))
        await rig.perform(refine(rig, "shorter"))
        #expect(try rig.sent().count == 2 && rig.lastFromCache)
        #expect(rig.rows == shorter.versions.map(\.text))
        // Another instruction is asked for.
        rig.key(escKey)
        _ = await refineOnline(rig, "more formal", answer: .answer(lines(formal)))
        #expect(try rig.sent().count == 3 && !rig.lastFromCache && rig.rows == formal.versions.map(\.text))
    }

    @Test func s10_theSameInstructionOnOtherResultsIsNotTakenFromTheCache() async throws {
        let converterRig = RARig()
        RAStubProtocol.enqueue(converterRig.host, .answer(lines(shorter)), .answer(lines(formal)))
        let a = [Refinement.Turn(answer: first, instruction: "shorter")]
        let b = [Refinement.Turn(answer: formal, instruction: "shorter")]
        var finals: [ConversionUpdate] = []
        for turns in [a, b, a] {
            for try await update in converterRig.converter.convert(sentence, mode: .improve, turns: turns) where update.isFinal {
                finals.append(update)
            }
        }
        #expect(finals.map(\.fromCache) == [false, false, true])
        let requests = try converterRig.sent().count
        #expect(finals[2].result == finals[0].result && requests == 2)
    }

    // MARK: 11. Normal requests unchanged

    @Test func s11_normalPromptsAreByteIdenticalToRelease063() {
        let cases = refineAcceptanceGoldenCases()
        #expect(cases.count == refineAcceptanceGolden.count)
        for (name, request) in cases {
            // @question's without 0.6.4's live-data rule; the others as they are.
            let data = AcceptanceLiveRule.strip(refineAcceptanceEncode(request), question: name.hasPrefix("question/"))
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(refineAcceptanceGolden[name] == hash, "\(name) differs from 55d496e")
        }
    }

    @Test func s11_aNewRequestAfterRefiningIsANormalOne() async throws {
        let rig = await improveShownOnline()
        _ = await refineOnline(rig, "shorter", answer: .answer(lines(shorter)))
        rig.key(escKey)
        rig.key(escKey)
        #expect(!rig.c.isLevelTwo)
        rig.type(" today")
        RAStubProtocol.enqueue(rig.host, .answer(lines(first)))
        await rig.press(enterKey)
        let sent = try rig.sent()
        try #require(sent.count == 3)
        var config = Config.default
        config.rewriteStyles = []
        config.outputLanguages = [.english]
        let expected = Prompt.request(for: sentence + " today", mode: .improve, config: config)
        #expect(sent[2].system == expected.system.map(\.text).joined())
        #expect(sent[2].messages.map(\.text) == expected.messages.map { $0.content.map(\.text).joined() })
        #expect(sent[2].messages.map(\.role) == expected.messages.map(\.role))
    }

    // MARK: 12. Payload size

    @Test func s12_theInstructionIsCappedAt200Characters() {
        let rig = improveShown()
        refine(rig, String(repeating: "a", count: 250), run: false)
        #expect(rig.c.refineText.count == 200)
        let run = rig.key(acceptanceShiftReturn)
        #expect(raRefines(run).first?.turns.last?.instruction.count == 200)
    }

    @Test func s12_theCapCountsCJKAndEmojiAsCharacters() {
        let rig = RARig()
        rig.engine.dictionary["kouyu"] = ["口语"]
        rig.pick("i")
        rig.type("nihao")
        rig.key(enterKey)
        _ = rig.c.receive(ConversionResult(versions: [CandidateLine("您好")]), isFinal: true, id: 1)
        for _ in 0..<110 {
            rig.type("kouyu")
            rig.key(spaceKey)
        }
        #expect(rig.c.refineText.count == 200 && rig.c.refineText == String(repeating: "口语", count: 100))
        // Emoji with modifiers are kept whole.
        let emoji = improveShown()
        emoji.type("a")
        for _ in 0..<300 { emoji.key(KeyEvent(keyCode: 0, characters: "👍🏽")) }
        #expect(emoji.c.refineText.count == 200 && emoji.c.refineText.last == "👍🏽")
    }

    @Test func s12_theRequestCarriesAtMost200CharactersOfInstruction() async throws {
        let rig = await improveShownOnline()
        _ = await refineOnline(rig, String(repeating: "b", count: 260), answer: .answer(lines(shorter)))
        let ask = try #require(try rig.sent().last?.lastUser)
        #expect(ask.contains(String(repeating: "b", count: 200)) && !ask.contains(String(repeating: "b", count: 201)))
    }

    // MARK: Edge cases

    /// Point 2 as clarified: a refine starts only once the results are complete. Letters typed while the first
    /// results stream do what they did before the feature: back to the draft, continuing the sentence.
    @Test func edge_lettersWhileTheFirstResultsStreamContinueTheSentenceAsBefore() {
        let rig = RARig()
        rig.c.setInputMode(.english)
        rig.pick("i")
        rig.type(sentence)
        rig.key(enterKey)
        _ = rig.c.receive(ConversionResult(versions: [CandidateLine("I have", isComplete: false)]), isFinal: false, id: 1)
        #expect(rig.c.isLevelTwo && !rig.c.canRefine)
        let typed = rig.type("s")
        // The request is stopped, and the letter continues the sentence in the draft; no refine line.
        #expect(typed.contains(.cancelConversion))
        #expect(!rig.c.isLevelTwo && rig.c.draft == "@improve " + sentence + "s")
        #expect(rig.c.refineLine == nil && rig.c.refineText.isEmpty && rig.c.refineHistory.isEmpty)
        rig.type("o")
        #expect(rig.c.draft == "@improve " + sentence + "so")
        // What still arrives for the stopped request is ignored.
        _ = rig.c.receive(first, isFinal: true, id: 1)
        #expect(!rig.c.isLevelTwo && rig.c.draft == "@improve " + sentence + "so")
        // ⏎ sends the longer sentence as a new, normal request.
        #expect(rig.key(enterKey).contains(.startConversion(input: sentence + "so", id: 2)))
    }

    /// New requirement: keys typed while a refine streams are not lost. They start (or extend) the refine line for
    /// the next refine, and the running refine goes on.
    @Test func edge_keysTypedWhileARefineStreamsAreKeptForTheNextRefine() {
        let rig = improveShown()
        refine(rig, "shorter")
        #expect(rig.c.isRefining)
        // Typed before any of the answer is in: starts the line.
        let early = refine(rig, "more", run: false)
        _ = rig.c.receive(ConversionResult(versions: [CandidateLine("An", isComplete: false)]), isFinal: false, id: 2)
        // Typed while it streams: extends it (a Space and letters).
        let later = refine(rig, " formal", run: false)
        let typed = early + later
        #expect(!typed.contains(.cancelConversion) && commits(typed).isEmpty && !raStartsSomething(typed))
        #expect(rig.c.isRefining && rig.c.isLevelTwo, "the running refine was stopped: phase \(rig.c.phase)")
        #expect(rig.c.refineText == "more formal", "line while streaming: \(rig.c.refineText.debugDescription)")
        // The refine's results arrive in full, and the line is still there.
        _ = rig.c.receive(shorter, isFinal: true, id: 2)
        #expect(rig.c.phase == .choosing && rig.rows == shorter.versions.map(\.text))
        #expect(rig.c.refineHistory == ["shorter"])
        #expect(rig.c.refineText == "more formal" && rig.c.refineLine == "more formal",
                "line after the results: \(rig.c.refineText.debugDescription)")
        // ⇧⏎ runs it as the next refine, on the refined results.
        let next = raRefines(rig.key(acceptanceShiftReturn)).first
        #expect(next?.turns == [
            Refinement.Turn(answer: first, instruction: "shorter"),
            Refinement.Turn(answer: shorter, instruction: "more formal"),
        ])
    }

    /// Accepted: ⌫ on an empty refine line steps back like Esc (with no refines left: back to the draft, as before).
    @Test func edge_backspaceOnAnEmptyLineStepsBackLikeEsc() {
        let rig = improveShown()
        refine(rig, "shorter")
        _ = rig.c.receive(shorter, isFinal: true, id: 2)
        refine(rig, "more formal")
        _ = rig.c.receive(formal, isFinal: true, id: 3)
        // ⌫ in a non-empty line deletes; once it's empty, the next ⌫ steps back.
        rig.type("ab")
        rig.key(backspaceKey)
        rig.key(backspaceKey)
        #expect(rig.c.refineText.isEmpty && rig.c.isLevelTwo && rig.rows == formal.versions.map(\.text))
        let back = rig.key(backspaceKey)
        #expect(commits(back).isEmpty && rig.c.isLevelTwo && rig.rows == shorter.versions.map(\.text))
        #expect(rig.c.refineHistory == ["shorter"])
        rig.key(backspaceKey)
        #expect(rig.c.isLevelTwo && rig.rows == first.versions.map(\.text) && rig.c.refineHistory.isEmpty)
        rig.key(backspaceKey)
        #expect(!rig.c.isLevelTwo && rig.c.draft == "@improve " + sentence)
        // While a refine runs, ⌫ on the empty line stops it and shows the results before, as Esc does.
        let running = improveShown()
        refine(running, "shorter")
        let stop = running.key(backspaceKey)
        #expect(stop.contains(.cancelConversion) && running.c.phase == .choosing)
        #expect(running.rows == first.versions.map(\.text) && running.c.refineHistory.isEmpty)
    }

    /// Accepted: Esc with pinyin being typed in the line clears the pinyin first, then the line on the next Esc.
    @Test func edge_escClearsThePinyinFirstThenTheLine() {
        let rig = RARig()
        rig.engine.dictionary["kouyu"] = ["口语"]
        rig.pick("i")
        rig.type("nihao")
        rig.key(enterKey)
        let zh = ConversionResult(versions: [CandidateLine("您好"), CandidateLine("你好呀")])
        _ = rig.c.receive(zh, isFinal: true, id: 1)
        rig.type("kouyu")
        rig.key(spaceKey)
        rig.type("geng")
        #expect(rig.c.refineText == "口语" && rig.c.refineIsComposing && rig.c.refineLine == "口语geng")
        // First Esc: the pinyin goes, the words picked stay.
        rig.key(escKey)
        #expect(!rig.c.refineIsComposing && rig.c.refineText == "口语" && rig.c.refineLine == "口语")
        #expect(rig.c.isLevelTwo && rig.rows == zh.versions.map(\.text))
        // Second Esc: the line is cleared; the results stay.
        rig.key(escKey)
        #expect(rig.c.refineText.isEmpty && rig.c.refineLine == nil && rig.c.isLevelTwo && rig.rows == zh.versions.map(\.text))
        // Pinyin alone in the line: one Esc clears it, the results stay.
        rig.type("geng")
        #expect(rig.c.refineLine == "geng")
        rig.key(escKey)
        #expect(rig.c.refineLine == nil && rig.c.isLevelTwo && rig.rows == zh.versions.map(\.text))
        // Then Esc on the empty line (no refines): back to the draft.
        rig.key(escKey)
        #expect(!rig.c.isLevelTwo && rig.c.draft == "@improve 你好")
    }

    @Test func edge_unicodeAndCJKInstructionsReachTheModelIntact() async throws {
        let rig = await improveShownOnline()
        rig.engine.dictionary["gengkouyu"] = ["更口语"]
        // Shift to pinyin, and back to English after the words are picked.
        _ = rig.shiftTap(at: 10)
        #expect(rig.c.inputLanguage == .chinese)
        rig.type("gengkouyu")
        rig.key(spaceKey)
        _ = rig.shiftTap(at: 20)
        #expect(rig.c.inputLanguage == .english)
        for ch in " très poli, 日本語で 🙂" {
            if ch == " " { rig.key(spaceKey) } else { rig.key(KeyEvent(keyCode: 0, characters: String(ch))) }
        }
        let instruction = "更口语 très poli, 日本語で 🙂"
        #expect(rig.c.refineText == instruction, "line: \(rig.c.refineText.debugDescription)")
        RAStubProtocol.enqueue(rig.host, .answer(lines(shorter)))
        let run = await rig.press(acceptanceShiftReturn)
        #expect(raRefines(run).first?.turns.last?.instruction == instruction)
        let ask = try #require(try rig.sent().last?.lastUser)
        #expect(ask.contains(instruction))
        #expect(rig.c.refineHistory == [instruction])
    }

    /// 0.6.4: @translate has no refine. Typing after its results (here into several languages) goes back to its text,
    /// the results dropped, and ⏎ translates the edited text again as a normal request.
    @Test func edge_translateIntoSeveralLanguagesHasNoRefine() async throws {
        let languages = [OutputLanguage.english, OutputLanguage("ja"), OutputLanguage("fr")]
        let rig = RARig(outputLanguages: languages)
        RAStubProtocol.enqueue(rig.host, .answer("EN: Hello.\nJA: こんにちは。\nFR: Bonjour."))
        rig.pick("t")
        #expect(rig.c.draft == "@translate ")
        rig.type("nihao")
        await rig.press(enterKey)
        #expect(rig.rows == ["Hello.", "こんにちは。", "Bonjour."] && !rig.c.canRefine)
        rig.type("x")  // pinyin, continuing the text
        #expect(!rig.c.isLevelTwo && rig.c.refineLine == nil && rig.c.draft == "@translate 你好")
        RAStubProtocol.enqueue(rig.host, .answer("EN: Hello x.\nJA: こんにちはx。\nFR: Bonjour x."))
        let again = await rig.press(enterKey)
        #expect(again.contains(.startConversion(input: "你好x", id: 2)) && raRefines(again).isEmpty)
        let sent = try rig.sent()
        try #require(sent.count == 2)
        #expect(sent[1].lastUser == "你好x" && sent[1].assistantTexts.count == sent[0].assistantTexts.count)
    }

    @Test func edge_shiftSwitchesTheLanguageInsideTheLine() {
        let rig = RARig()
        rig.engine.dictionary["kouyu"] = ["口语"]
        rig.pick("i")
        rig.type("nihao")
        rig.key(enterKey)
        _ = rig.c.receive(ConversionResult(versions: [CandidateLine("您好")]), isFinal: true, id: 1)
        #expect(rig.c.inputLanguage == .chinese)
        rig.type("kouyu")
        rig.key(spaceKey)
        #expect(rig.c.refineText == "口语")
        // Shift: English letters in the same line.
        _ = rig.shiftTap(at: 10)
        #expect(rig.c.inputLanguage == .english && rig.c.isLevelTwo)
        rig.key(spaceKey)
        rig.type("please")
        #expect(rig.c.refineText == "口语 please")
        // Shift back: pinyin again.
        _ = rig.shiftTap(at: 20)
        #expect(rig.c.inputLanguage == .chinese)
        rig.type("kouyu")
        rig.key(spaceKey)
        #expect(rig.c.refineText == "口语 please口语")
        // Shift while pinyin is typed keeps its letters in the line, as in a draft.
        rig.type("ni")
        _ = rig.shiftTap(at: 30)
        #expect(rig.c.refineText == "口语 please口语ni" && !rig.c.refineIsComposing && rig.c.inputLanguage == .english)
        #expect(rig.rows == ["您好"])
    }
}

// MARK: - Point 11: the normal requests at release-0.6.3 (55d496e)

// The cases below were compiled into a small program in a `git worktree` of 55d496e, which printed the SHA-256 of
// each request encoded with sorted keys (`refineAcceptanceEncode`); `refineAcceptanceGolden` is that output. The
// same function, unchanged, is run here on this branch's code.

// Shared between the golden dumper (run at 55d496e) and RefineAcceptanceTests: the normal requests compared.
func refineAcceptanceGoldenCases() -> [(name: String, request: ConverseRequest)] {
    var out: [(name: String, request: ConverseRequest)] = []
    let inputs: [(String, String)] = [
        ("zh", "今天天气不错，我们去公园散步吧"),
        ("zhShort", "你好"),
        ("en", "i has a apple and it are red"),
        ("mixed", "明天的meeting我不去了"),
        ("ko", "안녕하세요 반갑습니다"),
        ("zhLong", String(repeating: "这个项目的进度有点慢，我们需要加快速度，争取下周之前完成第一版。", count: 12)),
        ("enLong", String(repeating: "We should probably move the release to next week because the tests are not done. ", count: 10)),
    ]
    var zhOut = Config.default
    zhOut.outputLanguages = [.chinese]
    var multi = Config.default
    multi.outputLanguages = [.english, OutputLanguage("ja"), OutputLanguage("fr")]
    var styles = Config.default
    styles.rewriteStyles = ["润色"]
    styles.maxTokens = 500
    styles.temperature = nil
    let configs: [(String, Config)] = [("default", Config.default), ("zhOut", zhOut), ("multi", multi), ("styles", styles)]
    let modes: [(String, WritingMode)] = [("improve", .improve), ("translate", .translate), ("both", .both)]
    for (cname, config) in configs {
        for (iname, input) in inputs {
            for (mname, mode) in modes {
                out.append(("writing/\(cname)/\(iname)/\(mname)", Prompt.request(for: input, mode: mode, config: config)))
            }
        }
    }
    let reply = Command.catalog([CustomCommand(name: "respond", type: .prompt, prompt: "Write a polite reply in the same language.")])
        .first { $0.name == "respond" }!
    let commandInputs: [(String, String)] = [
        ("zh", "量子计算是什么"), ("en", "what is a monad"),
        ("about", Prompt.question("总结一下", about: "Dear team, this sentance have a error.")),
        ("edit", Prompt.editRequest(instruction: "translate: ja", text: "Dear team,\nthis sentance have a error.")),
    ]
    for (cname, config) in [("default", Config.default), ("styles", styles)] {
        for (iname, input) in commandInputs {
            out.append(("question/\(cname)/\(iname)", Prompt.commandRequest(.question, input: input, config: config)))
            out.append(("reply/\(cname)/\(iname)", Prompt.commandRequest(reply, input: input, config: config)))
            out.append(("edit/\(cname)/\(iname)", Prompt.commandRequest(.edit, input: input, config: config)))
        }
    }
    return out
}

func refineAcceptanceEncode(_ request: ConverseRequest) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try! encoder.encode(request)
}

/// SHA-256 of `refineAcceptanceEncode` of each case, as built by 55d496e.
let refineAcceptanceGolden: [String: String] = [
    "writing/default/zh/improve": "9651b661f012202aa9faf4726b7647860626819d885f3d6bf8391e7244216ae8",
    "writing/default/zh/translate": "792361ccb3396d70a9255a59b2b04958c7f518032654d7ff1d1cc015332abf08",
    "writing/default/zh/both": "7542d09f424ec4dc8fc39e0d2957cb52d81fc20e91dc8d453d5037f65e7298f1",
    "writing/default/zhShort/improve": "3814ed3ac25ade356c087b183c9e531f542b1aca8e4c077c42e255108c39c092",
    "writing/default/zhShort/translate": "e83ef43c46d6d47b17c04f9e0c24f2574e61503f12ea4f775450c0e46407d67c",
    "writing/default/zhShort/both": "58efbe9a2fbe0c0824a122faa31ba3a265962a0e874c108a9edd69e8160a160b",
    "writing/default/en/improve": "0a214769e00f17c06d310c94dae2978212d9689a09fd212ce253a4ce8753b6f6",
    "writing/default/en/translate": "34bf26f41074ccf266f7caf44af64875beb81365514a2ac6d6115b2e298133e1",
    "writing/default/en/both": "3e78b35ee05a08e181fa8f80e2df0ba06a1b628aed4910987e34e6bc74db1fd8",
    "writing/default/mixed/improve": "a9cbb356e342d46bbdf52bb38ff4a29c4e5610432792d54137f4b9f4034fd152",
    "writing/default/mixed/translate": "daa69daf435f843a4162f03a75c94110fa84097b3dec919a0a1af87ad8e758b0",
    "writing/default/mixed/both": "5b96662343a1c460c58c87ea7d43a944d02629b8a34871d68c8b0f08032f0be4",
    "writing/default/ko/improve": "3c581aa9512c20fad0997ac84afc00f62ce1676571c38c17b015a8b9a40b4e18",
    "writing/default/ko/translate": "0c53faf9c38d48076cbb0822313a9d53419690215ac99acdaecc17d2dadb1ba7",
    "writing/default/ko/both": "1f2a8af0e9333fdf0635c884f92c0267cf32c460a7ce9640dcacc1ff9f0ad49e",
    "writing/default/zhLong/improve": "7467e24f317604456e2f69a18d233cc472f5de4a27ab323f210a928171c52ff6",
    "writing/default/zhLong/translate": "ee03a802a22fe3ac3f9da2f6ce009c9c8627017b8e4439c6569ed4702060548b",
    "writing/default/zhLong/both": "40b5d4eb6cfa063e3476fee7ac18db1f805bc8c7d09840ac3419c29829e593d1",
    "writing/default/enLong/improve": "6b7b32259a18ab5d2358dd45d2577974119ca743c121635f4f8047ef5c23c9d1",
    "writing/default/enLong/translate": "3e7219cbf3424af08870e6b2cdc450ff550dfb3e82d588e3586efd264b5c2c20",
    "writing/default/enLong/both": "b0830fd57de57e32a8e6efaa41b1429fc9e07435d108b188d061983ad90eec6e",
    "writing/zhOut/zh/improve": "9651b661f012202aa9faf4726b7647860626819d885f3d6bf8391e7244216ae8",
    "writing/zhOut/zh/translate": "b6ce21ab3947fda254c9633f337cd97b364d5523e1909bcd62fb6b202c3539f0",
    "writing/zhOut/zh/both": "1771730500603ff57c6e4c914ed1e275166b67d71b357880cc8589415d800488",
    "writing/zhOut/zhShort/improve": "3814ed3ac25ade356c087b183c9e531f542b1aca8e4c077c42e255108c39c092",
    "writing/zhOut/zhShort/translate": "01a27ff74f151e95192da17fdf89edbfe94e4c5ad8c2a61feccd08492a10b2b7",
    "writing/zhOut/zhShort/both": "c11efb5cb6ef21bdd0e5bb8caf76473cb70efce2bdae52c92d7429e9a2287ec4",
    "writing/zhOut/en/improve": "0a214769e00f17c06d310c94dae2978212d9689a09fd212ce253a4ce8753b6f6",
    "writing/zhOut/en/translate": "53a9b3dd5f64bc64b8ec4472afc0492bce0cddac54c71f1565ca666fedc34c5a",
    "writing/zhOut/en/both": "457ecbed0eac05b1018d9c0f7d49a3c5086877320574d1d595a400f85c01263d",
    "writing/zhOut/mixed/improve": "a9cbb356e342d46bbdf52bb38ff4a29c4e5610432792d54137f4b9f4034fd152",
    "writing/zhOut/mixed/translate": "dff26142c718957452f60d71842cd3011b48816ba39289fa54633aac8965c9ea",
    "writing/zhOut/mixed/both": "dfcd4e743b180ef5c8835a162dc38b52c910aa0a2dea08695ddac45a476668f2",
    "writing/zhOut/ko/improve": "3c581aa9512c20fad0997ac84afc00f62ce1676571c38c17b015a8b9a40b4e18",
    "writing/zhOut/ko/translate": "2e2470c13d2d9265fc0be5c0efc77d3c051c1ea275d35cd2c148eac8b443fa0e",
    "writing/zhOut/ko/both": "900d97114cf71e2ef685405c422160793c6680bc55f903863ca18bfc14677947",
    "writing/zhOut/zhLong/improve": "7467e24f317604456e2f69a18d233cc472f5de4a27ab323f210a928171c52ff6",
    "writing/zhOut/zhLong/translate": "9e05cf662ec2924d135099e755bd90a1fb14e3a519e4daf9c776b71ae099bcc5",
    "writing/zhOut/zhLong/both": "897875363b33a71af6564b06017e9a49dea0b2369ab0f24328a983cfdb005f89",
    "writing/zhOut/enLong/improve": "6b7b32259a18ab5d2358dd45d2577974119ca743c121635f4f8047ef5c23c9d1",
    "writing/zhOut/enLong/translate": "4a9a152aa5a3ee1f9bc470067a63d049e646a406964b122e2dc038de7cedddf0",
    "writing/zhOut/enLong/both": "2087052061dd5eea5f9f6167372db54aa13a818f77922a8af91326fd9a56a824",
    "writing/multi/zh/improve": "9651b661f012202aa9faf4726b7647860626819d885f3d6bf8391e7244216ae8",
    "writing/multi/zh/translate": "4d06dece2de28c6e6519382d7fff0ad7cd258cd1fd35a6c42a999f1de6c397c6",
    "writing/multi/zh/both": "a36e56d2a374858148869af571b91cb92c8818471730616695430d42d4c17af7",
    "writing/multi/zhShort/improve": "3814ed3ac25ade356c087b183c9e531f542b1aca8e4c077c42e255108c39c092",
    "writing/multi/zhShort/translate": "9073f9355b0ad86309d4f9472663e7f1ed35f92acecb274758dea99eea0a47f4",
    "writing/multi/zhShort/both": "c0a5e81943d1c39cd83938627617cd77ef4bd2eb93dc15e4f1743af77f276dd0",
    "writing/multi/en/improve": "0a214769e00f17c06d310c94dae2978212d9689a09fd212ce253a4ce8753b6f6",
    "writing/multi/en/translate": "8b26351d70e085189732c0ff952b7d8049543a6f54918a8a9aaf43183cb242c4",
    "writing/multi/en/both": "6bf71acddaa381bb7f65fd39ebfe0af58d9e2f6f148e7a9cca48e6343a4e1a36",
    "writing/multi/mixed/improve": "a9cbb356e342d46bbdf52bb38ff4a29c4e5610432792d54137f4b9f4034fd152",
    "writing/multi/mixed/translate": "b2273ed412094d485301af9464871efdda0346815ae2cbf3ddf028e604ddf6d4",
    "writing/multi/mixed/both": "aead36eee5ee27bc09a4fa2bd4af34b593af42c5d17f01cb8b0dca9fce9d9d4d",
    "writing/multi/ko/improve": "3c581aa9512c20fad0997ac84afc00f62ce1676571c38c17b015a8b9a40b4e18",
    "writing/multi/ko/translate": "7da2ba6f7156d68561f942ffe023ac809e3f0c3cd450c327b747e86069179009",
    "writing/multi/ko/both": "2d413c60e250e51d509401adf81904201e90de90c0f76da44acdc958288d7928",
    "writing/multi/zhLong/improve": "7467e24f317604456e2f69a18d233cc472f5de4a27ab323f210a928171c52ff6",
    "writing/multi/zhLong/translate": "c8e04cf306df81e21c194ee30bd658fa4696f8d8d53eb9a9b38c866e50e77848",
    "writing/multi/zhLong/both": "5d6ee0945f51f12d8c79bb749e41f213781c7e39a37abf92df6e86e9d6cb23b7",
    "writing/multi/enLong/improve": "6b7b32259a18ab5d2358dd45d2577974119ca743c121635f4f8047ef5c23c9d1",
    "writing/multi/enLong/translate": "137aef1f6026278b9c96b1bfa8219129cf0844bfc393b10711be1ce798bd57be",
    "writing/multi/enLong/both": "3b97b460788e97b8dc156c0109dee18531f19c8fc9a38af5c4bb925e29849295",
    "writing/styles/zh/improve": "6b29f2cf214cfc6e57c42919c2567f6e48d8741521efa579f4576de77b02a7a5",
    "writing/styles/zh/translate": "937cac8b578f8eabb06cc0bd7f5c5bd413e2715c32ba60d35c8a4183f6176e33",
    "writing/styles/zh/both": "36b6d3aae5fc4a525e8740bc3698d81928a96a2b5aac4b60f6c5a5b32f367ee9",
    "writing/styles/zhShort/improve": "f9d93fbf1c11592323870de8070049ca5898d70f055f16e39af730ec3d0810a3",
    "writing/styles/zhShort/translate": "e22c26d973fd89159aae2ec11bb687d1672e19752104a70eed712fb7a6d4be6e",
    "writing/styles/zhShort/both": "02bc900e4c82bb3af92b777285e714ec87a88b828bd7e608c2f6c921d4445c1f",
    "writing/styles/en/improve": "d2b5c3fecc70e94ac07939c5e10c368ba16b7d4c1452cde6b3a18fd68da4a41e",
    "writing/styles/en/translate": "ad48e5b216239d17d0b527908aeb3cef11c83904c7e3953be81f9092ee305acb",
    "writing/styles/en/both": "3155783a65c5c793cde2f0f188279483024020baf60ba0ed696821f39fe3ef97",
    "writing/styles/mixed/improve": "4d47ed4e7c74852ebfd66a2b64e2d7ef13c0fbcbbcf36485989bb038713611f5",
    "writing/styles/mixed/translate": "746c0f657aab6e76ab9ee4cab57bb4021a7a4ad0e97fcf104b0b312796f04ab8",
    "writing/styles/mixed/both": "ca00962bc67164d122208c6bac7440ffbd7c4453c4b2c96d2dc81bd2d845ca2e",
    "writing/styles/ko/improve": "1fcde3b4c994c243949ace0fc046eed8e2f70e21812e60b100b12a2ba984c49c",
    "writing/styles/ko/translate": "69ffc63b47451a80c1f009b10318d25cba050ce8c5e512b8109694973add79dd",
    "writing/styles/ko/both": "5b7f7f76a9228b4e2273dbc415e63bb613c08fc4906388e40312cca25ee10415",
    "writing/styles/zhLong/improve": "cdca32cfe51e6970f90b350ccfe62e1773d19f3b3fd886563e826a510dcc7bc4",
    "writing/styles/zhLong/translate": "dabb5a128427d3f46b6b464b90251fb97c7c47206f4c04bc854010b38fc3b4fe",
    "writing/styles/zhLong/both": "401729e61ef3db7b449d68c899875bee5dab1a3fc484b0dfe0b0b02d07bdfb80",
    "writing/styles/enLong/improve": "5a8885bbd2c2a0f9fdc6e452ae6742f7f9b26dc149ad63f29bfdc8ccc068c1e4",
    "writing/styles/enLong/translate": "a070ed237c88f39baa5073b3a6b93e8917c823c491293f89bd682fc77ef50841",
    "writing/styles/enLong/both": "09e6e1f3c0079cd1ebcdac71904823069e8ed382399a1a1a1b33a546210270ee",
    "question/default/zh": "b625602f4d0139a5d9903ff55c02034c05ccded529f33bbffd2d481b454e0c16",
    "reply/default/zh": "36b529a530e56991b5b385fe1cc5bf24a5f9a4c04565a272d964bc963b8b1db1",
    "edit/default/zh": "8e0ac6b9268964f0e0a1060995df68c87c7f0909b1f71855576c61d81d6c3827",
    "question/default/en": "5a9726af44eed9d0c97d850b17096a2362d21cafcf48eb1963fa401ec968723f",
    "reply/default/en": "113440e89e660caf324ff237896ad15c434d6e9532d90ffdf33ca19d47a247d4",
    "edit/default/en": "2a672079aacdc91c40a76d4f7787b29433dad639e3de223d6db4e65440b41295",
    "question/default/about": "597eb644b8d005b03ffe6423d119a98ed36d436beca2fafc59adbf11dc2b6c25",
    "reply/default/about": "af902cb0bbbed0982f5f3c0022ee8344c38a222c051cc2c76149c72c3f06450b",
    "edit/default/about": "62d28cdf8ea4022a4da65b343eff8d88178f3ceb445699c12cbac2b7ec6206c7",
    "question/default/edit": "df25984bb99bc6dbe9f4e3a29ad15be359f4f4005a8a0adcc47aa6ff977b0efc",
    "reply/default/edit": "805d72c3fa4d0a1aeed04b8c9cdd9edb9638a04228b134ca0cc8a456f752f583",
    "edit/default/edit": "cfe4f0f168781088e20dfcdc242139b586ed01f582c93172d6890731172d20cf",
    "question/styles/zh": "4670114ff379af173578eaa5bcfcd1593681501765b5f10aada23aef9ecdf8f1",
    "reply/styles/zh": "ea6a810dc19c133acf1ffaf50d49d66ef51890c9b18ae2576a49ea03537e39db",
    "edit/styles/zh": "4591abe9c7056da0261d907be52338d923b61e1bcd31998eb89a5787792f0de8",
    "question/styles/en": "7060f5e216a98f1b5520befdcfc418a37b3160bcb62b73e541bd787935c6d785",
    "reply/styles/en": "8fe495f04508769a95fdc66fec79596170369b3953000f0156bc142a4c486a28",
    "edit/styles/en": "4b8d11e2e3af54b990ea974337ec942f6cd2d3bffc692eba277d547bce5bd157",
    "question/styles/about": "f5acac6bf0be609c0b9c7fc92fa5990d2dc3d30468f83a6e4c3963083c1a1478",
    "reply/styles/about": "bd1bdd37ab7d845953fe232863eac7d061fb3e1bb747743cbb99102eb93dd7e4",
    "edit/styles/about": "c569ca37cc8c306ba7231fe3ffa435bb67efdc869b72ac3b72e2e0ca805800fd",
    "question/styles/edit": "b7f67655577466888e9c4bb22332492a6ab52118a1fb341bcb1a5172f2f16e40",
    "reply/styles/edit": "b760ceec2b002a2acd25f46ad931128c83fb711142c4e10ce91cfa6fff04e318",
    "edit/styles/edit": "9e41de2564b0482091701130c8a5fe2fb7e7b59146a13665bdd8d394bc7d3d67",
]

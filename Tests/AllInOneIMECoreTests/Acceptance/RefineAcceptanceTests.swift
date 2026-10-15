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

    /// Types `instruction` into the refine line (Space as the Space key), then ⏎ when `run`. With `run`, what ⏎ did;
    /// without, what the typing did.
    @discardableResult
    func refine(_ rig: RARig, _ instruction: String, run: Bool = true) -> [Composer.Effect] {
        var typed: [Composer.Effect] = []
        for ch in instruction {
            typed += ch == " " ? rig.key(spaceKey) : rig.type(String(ch))
        }
        return run ? rig.key(enterKey) : typed
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
        translate.type("s")
        #expect(translate.c.refineLine == "s", "@translate")

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
        let reply = CustomCommand(name: "reply", type: .prompt, prompt: "Write a polite reply.")
        let catalog = Command.catalog([reply])
        let custom = RARig(commands: catalog)
        custom.c.setInputMode(.english)
        custom.pick("repl")
        #expect(custom.c.draft == "@reply ")
        custom.type("thanks for the invite")
        let start = custom.key(enterKey)
        #expect(start.contains { if case let .startCommand(c, _, _) = $0 { return c.name == "reply" } else { return false } })
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
        // ⏎ still runs it when it isn't the action key.
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
        #expect(rig.rows == ["A monad chains computations with context."])
        #expect(rig.c.choices.first?.text == "what is a monad")
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
        // ⏎ sends exactly what is in the line.
        #expect(raRefines(rig.key(enterKey)).first?.turns.last?.instruction == "make it 2 lines, pleas")
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
        // ⏎ again tries again.
        RAStubProtocol.enqueue(rig.host, .answer(lines(shorter)))
        await rig.press(enterKey)
        #expect(rig.rows == shorter.versions.map(\.text) && rig.c.refineHistory == ["shorter"] && rig.c.refineText.isEmpty)
        #expect(try rig.sent().count == 3)
    }

    @Test func s8_anEmptyAnswerKeepsTheResultsAndTheInstruction() async throws {
        let rig = await improveShownOnline()
        _ = await refineOnline(rig, "shorter", answer: .answer(""))
        #expect(rig.c.phase == .choosing && rig.rows == first.versions.map(\.text))
        #expect(rig.c.refineText == "shorter" && rig.c.refineError != nil)
        RAStubProtocol.enqueue(rig.host, .answer(lines(shorter)))
        await rig.press(enterKey)
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
        await rig.press(enterKey)
        #expect(rig.rows == shorter.versions.map(\.text) && rig.c.refineError == nil)
    }

    @Test func s8_aFailureAfterPartOfTheAnswerKeepsTheResultsBefore() {
        let rig = improveShown()
        refine(rig, "shorter")
        _ = rig.c.receive(ConversionResult(versions: [CandidateLine("An app", isComplete: false)]), isFinal: false, id: 2)
        _ = rig.c.fail("The network connection was lost.", id: 2)
        #expect(rig.c.phase == .choosing && rig.rows == first.versions.map(\.text))
        #expect(rig.c.refineText == "shorter" && rig.c.refineError == "The network connection was lost.")
        // The next key clears the error; ⏎ runs the same instruction again.
        let retry = rig.key(enterKey)
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
            let data = refineAcceptanceEncode(request)
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
        let run = rig.key(enterKey)
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

    @Test func edge_aRefineTypedWhileTheFirstResultsStream() {
        let rig = RARig()
        rig.c.setInputMode(.english)
        rig.pick("i")
        rig.type(sentence)
        rig.key(enterKey)
        _ = rig.c.receive(ConversionResult(versions: [CandidateLine("I have", isComplete: false)]), isFinal: false, id: 1)
        #expect(rig.c.isLevelTwo)
        // The user starts typing an instruction before the answer is complete.
        let typed = refine(rig, "shorter", run: false)
        // The request isn't thrown away, nor is the sentence edited.
        #expect(!typed.contains(.cancelConversion), "typing during streaming cancelled the request: \(typed)")
        #expect(rig.c.isLevelTwo && rig.c.draft == "@improve " + sentence,
                "level two: \(rig.c.isLevelTwo), phase: \(rig.c.phase), draft: \(rig.c.draft.debugDescription), effects: \(typed)")
        _ = rig.c.receive(first, isFinal: true, id: 1)
        #expect(rig.rows == first.versions.map(\.text))
        // The instruction is in the line, and ⏎ sends it.
        #expect(rig.c.refineText == "shorter")
        #expect(raRefines(rig.key(enterKey)).first?.turns.last?.instruction == "shorter")
    }

    @Test func edge_keysWhileARefineStreamsDoNotStopIt() {
        let rig = improveShown()
        refine(rig, "shorter")
        _ = rig.c.receive(ConversionResult(versions: [CandidateLine("An", isComplete: false)]), isFinal: false, id: 2)
        let typed = rig.type("x")
        #expect(!typed.contains(.cancelConversion) && rig.c.isRefining && commits(typed).isEmpty)
        _ = rig.c.receive(shorter, isFinal: true, id: 2)
        #expect(rig.rows == shorter.versions.map(\.text))
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
        let run = await rig.press(enterKey)
        #expect(raRefines(run).first?.turns.last?.instruction == instruction)
        let ask = try #require(try rig.sent().last?.lastUser)
        #expect(ask.contains(instruction))
        #expect(rig.c.refineHistory == [instruction])
    }

    @Test func edge_aRefineOnTranslateIntoSeveralLanguagesKeepsThemAll() async throws {
        let languages = [OutputLanguage.english, OutputLanguage("ja"), OutputLanguage("fr")]
        let rig = RARig(outputLanguages: languages)
        RAStubProtocol.enqueue(rig.host, .answer("EN: Hello.\nJA: こんにちは。\nFR: Bonjour."))
        rig.pick("t")
        #expect(rig.c.draft == "@translate ")
        rig.type("nihao")
        await rig.press(enterKey)
        #expect(rig.rows == ["Hello.", "こんにちは。", "Bonjour."])
        _ = rig.shiftTap(at: 10)  // English for the instruction
        _ = await refineOnline(rig, "more formal",
                               answer: .answer("EN: Good day to you.\nJA: こんにちは（丁寧）。\nFR: Bonjour, madame."))
        // All three come back, each in its language.
        #expect(rig.rows == ["Good day to you.", "こんにちは（丁寧）。", "Bonjour, madame."])
        #expect(rig.c.choices.compactMap { if case let .translation(code) = $0.kind { return code } else { return nil } }
            == ["en", "ja", "fr"])
        // The model was shown all three lines, with their languages.
        let sent = try rig.sent()
        try #require(sent.count == 2)
        let shown = try #require(sent[1].assistantTexts.last)
        #expect(shown.contains("EN: Hello.") && shown.contains("JA: こんにちは。") && shown.contains("FR: Bonjour."))
        #expect(sent[1].lastUser.contains("more formal"), "sent: \(sent[1].lastUser.debugDescription)")
        // The first request is untouched inside it (the sentence "你好").
        #expect(sent[0].lastUser == "你好")
        #expect(zip(sent[0].messages, sent[1].messages).allSatisfy { $0.text == $1.text })
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
    let reply = Command.catalog([CustomCommand(name: "reply", type: .prompt, prompt: "Write a polite reply in the same language.")])
        .first { $0.name == "reply" }!
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
    "writing/default/zh/improve": "94361ecb1b2d71fcddc405998996cd88c0a16a7062184e63c30b9ba1c53089f7",
    "writing/default/zh/translate": "96c830d627d019451a6117bad94f8cb2a031c647da9742137d49c1d6dbc69d9c",
    "writing/default/zh/both": "3135350ee0a53ebf400eda387ee7115bf6b9dd065d7964fe8092c72edba95b92",
    "writing/default/zhShort/improve": "fdb2b8c86d0c76e3157055d5a4c762f09a962556c4c2d8491d29135a1462d84e",
    "writing/default/zhShort/translate": "a0ca3415c9da46dbd7e0d035195fe2bcfbe65b3ec104c594b57e18e7f36c955f",
    "writing/default/zhShort/both": "a858c76a5b1791fffda1d4f94cf7c79105a01f41a225d00fce43f9ae898b734d",
    "writing/default/en/improve": "4b89de4aeb3fdec854f8cf7228009816657516ea6c0aa1185baa006a713ce78d",
    "writing/default/en/translate": "2c0e7a623a025613c9e1e5386f7553796afc13bb5d96e7f67d6aeed807864682",
    "writing/default/en/both": "574e315dd731f9970222df2b597f4d5c555337d6bf96116c7f7b479483079c10",
    "writing/default/mixed/improve": "a0b84da524e5fd93e90bf6be50cdbae154b31cae89de8b399a04ec8049466713",
    "writing/default/mixed/translate": "95bf227fa793ae408f68a8f448da6bbc45d6a9e3f73b1307bbe9622c11cdbfc9",
    "writing/default/mixed/both": "511df95cfa0aad9e90f1d21b3324f0db18f1f671b0221c66272853cb97648922",
    "writing/default/ko/improve": "d516d0652d9b2f16984b101a8fb58412cd35c0d78a0247f2cb5b96a55bc497d6",
    "writing/default/ko/translate": "caeaaf7b9a39da55438c3ec45afb0d94d63c3c6d1155ec868e4eebf6628f38ee",
    "writing/default/ko/both": "9bbdc4bf3cdae4f53dd2514d277d7c752cad33903c95a2e55bdd33bf8d3248b1",
    "writing/default/zhLong/improve": "7467e24f317604456e2f69a18d233cc472f5de4a27ab323f210a928171c52ff6",
    "writing/default/zhLong/translate": "ee03a802a22fe3ac3f9da2f6ce009c9c8627017b8e4439c6569ed4702060548b",
    "writing/default/zhLong/both": "40b5d4eb6cfa063e3476fee7ac18db1f805bc8c7d09840ac3419c29829e593d1",
    "writing/default/enLong/improve": "6b7b32259a18ab5d2358dd45d2577974119ca743c121635f4f8047ef5c23c9d1",
    "writing/default/enLong/translate": "3e7219cbf3424af08870e6b2cdc450ff550dfb3e82d588e3586efd264b5c2c20",
    "writing/default/enLong/both": "b0830fd57de57e32a8e6efaa41b1429fc9e07435d108b188d061983ad90eec6e",
    "writing/zhOut/zh/improve": "94361ecb1b2d71fcddc405998996cd88c0a16a7062184e63c30b9ba1c53089f7",
    "writing/zhOut/zh/translate": "cc29f8aa8e0e7d9e7727de4a128e14788fc089f4ff42bf81ec797351c08ca378",
    "writing/zhOut/zh/both": "7e25402cc814317f87d511efa07a6d91dd0fac183fbb3a6a554c4dfc7b2ca3a4",
    "writing/zhOut/zhShort/improve": "fdb2b8c86d0c76e3157055d5a4c762f09a962556c4c2d8491d29135a1462d84e",
    "writing/zhOut/zhShort/translate": "445b39c48e269845a8d6b127846b4b852bc213445e540c5b3a30ded5d8b470bd",
    "writing/zhOut/zhShort/both": "135f664c608871869dcdc46817586839a81ffa555a54ab768804caec1bb4c0f0",
    "writing/zhOut/en/improve": "4b89de4aeb3fdec854f8cf7228009816657516ea6c0aa1185baa006a713ce78d",
    "writing/zhOut/en/translate": "1a158f8df0de1f6ce4b75ae0ecce5524d15647b893e05003e82b5aea9e6dfd81",
    "writing/zhOut/en/both": "eb026988b5aed9113c22a29fe685b60238041be64df791dc517a4b99fd843db8",
    "writing/zhOut/mixed/improve": "a0b84da524e5fd93e90bf6be50cdbae154b31cae89de8b399a04ec8049466713",
    "writing/zhOut/mixed/translate": "85cd5cc66744c204aa9cf876a5157cb06903e213df192fb1056f142ac44b9e23",
    "writing/zhOut/mixed/both": "3dfafe9c200f55311c92deeb9e2a895658039f3f34489c19b71d8c3677f4de06",
    "writing/zhOut/ko/improve": "d516d0652d9b2f16984b101a8fb58412cd35c0d78a0247f2cb5b96a55bc497d6",
    "writing/zhOut/ko/translate": "e8b52b280c9ff57b2ac3463effb52d73304f137865837a43e37b2d7c34f7778f",
    "writing/zhOut/ko/both": "eb49cdd51476dc66448d2c9a375cb0c3eb17d8145679e81619d7d1b88253bd8e",
    "writing/zhOut/zhLong/improve": "7467e24f317604456e2f69a18d233cc472f5de4a27ab323f210a928171c52ff6",
    "writing/zhOut/zhLong/translate": "9e05cf662ec2924d135099e755bd90a1fb14e3a519e4daf9c776b71ae099bcc5",
    "writing/zhOut/zhLong/both": "897875363b33a71af6564b06017e9a49dea0b2369ab0f24328a983cfdb005f89",
    "writing/zhOut/enLong/improve": "6b7b32259a18ab5d2358dd45d2577974119ca743c121635f4f8047ef5c23c9d1",
    "writing/zhOut/enLong/translate": "4a9a152aa5a3ee1f9bc470067a63d049e646a406964b122e2dc038de7cedddf0",
    "writing/zhOut/enLong/both": "2087052061dd5eea5f9f6167372db54aa13a818f77922a8af91326fd9a56a824",
    "writing/multi/zh/improve": "94361ecb1b2d71fcddc405998996cd88c0a16a7062184e63c30b9ba1c53089f7",
    "writing/multi/zh/translate": "02575dbf03b9a6fa3b5bd813033c8becb87d8f9bcb67fba984560c38b648f6dd",
    "writing/multi/zh/both": "c2557e34afac3182da6e8e1baf96d7e6c8806a7e3805bb584922eac3eb1e9541",
    "writing/multi/zhShort/improve": "fdb2b8c86d0c76e3157055d5a4c762f09a962556c4c2d8491d29135a1462d84e",
    "writing/multi/zhShort/translate": "60f21b0f23088aa69b6ef776edc0c08df2c2752c91b6a9200b32a2892aeec63c",
    "writing/multi/zhShort/both": "30493a6ae48a406d95903face3c48081dbee9bb7591fb14ae94cc690bc7d99b0",
    "writing/multi/en/improve": "4b89de4aeb3fdec854f8cf7228009816657516ea6c0aa1185baa006a713ce78d",
    "writing/multi/en/translate": "d2e84e446c9350c655f20440eca958c4194843bb7c6c4e2a05686608b93a36bd",
    "writing/multi/en/both": "3a517f6616410814b81c74f6f7fd6ab3f97fb7bc8b5fc23393ff6b18e8d295ee",
    "writing/multi/mixed/improve": "a0b84da524e5fd93e90bf6be50cdbae154b31cae89de8b399a04ec8049466713",
    "writing/multi/mixed/translate": "73d034b6687f162ad989b32ced729742a9eb140d4930dc2fc4df59ed1f923654",
    "writing/multi/mixed/both": "907b1fb9a134571e6aef6bbe3bf8986784d1d9e56f6883194f4fc7e48d032f10",
    "writing/multi/ko/improve": "d516d0652d9b2f16984b101a8fb58412cd35c0d78a0247f2cb5b96a55bc497d6",
    "writing/multi/ko/translate": "6e7771a79373e965c370a15bb07e78eae60abf2aa4c3219df0da4e543db9cfa7",
    "writing/multi/ko/both": "19e201884a2fe9594f24e220b2935db73485da017eca953682f00efa6f40b207",
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
    "question/default/zh": "331e9436d8c40191a866de8a741e8edaae8018956f369d19984e408742a0e368",
    "reply/default/zh": "1b027c4a5376c73bc289550003a60ac0d2a93b39b1ec0c93b4dcdff8452ecf89",
    "edit/default/zh": "1882ef6428455b7e81c5cdf9164cfb9d6a67213416f5c5fb056c95915a27e1f5",
    "question/default/en": "55143a23ab63fb85ecd7a3c2af0eb813b68d600346c4c47e8fd84bf9f265b319",
    "reply/default/en": "3b94c6972f015e26528124ef785cefd9024e7e50aac03d1e5b244de0604d79ac",
    "edit/default/en": "7efd49a5482507a24cd0c327be98f191a4ed0f87e44a31e8c4381a8cddaf26cf",
    "question/default/about": "cc3abe0e61268893d83b109fe67f84c73f4f6b32ed651225965eead8e093f026",
    "reply/default/about": "74623dead6bedc1c438922fc1e3b3208a2ac3024225634d3968240941ee52db1",
    "edit/default/about": "77e379a274f286b51c9e2f200da8f94c7c164621b381929e2dd3498ac4b19247",
    "question/default/edit": "b34ddc7d5a1f9988af54abd964d29da5b6282b53eb20f78f743238a547e64987",
    "reply/default/edit": "f764aadf57b1968d4e2891ee7c5a1010aa4f5ec91b42208f3326516133cca854",
    "edit/default/edit": "0771eb0205b1460bd98f6ffd93cd78a8108702c5403e7ede6b1281f6c90a6eaa",
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

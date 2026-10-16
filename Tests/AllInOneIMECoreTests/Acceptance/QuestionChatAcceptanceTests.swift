import Foundation
import os
import Testing
@testable import AllInOneIMECore

// Acceptance tests for the @question conversation and the one ⇧⏎ rule (0.6.4), written from the spec
// (spec-question-chat.md with its CHANGE 1 and CHANGE 2, and the coordinator's decisions after it), independently of
// the implementation's own tests. Each test names the clause it checks ("conv" the conversation, "keys" CHANGE 1's keys,
// "req" the requests, "ctx" the context limit, "limit" the round limit, "handoff" continuing elsewhere, "hist" the
// history, "c2" CHANGE 2, "live" the live-data rule). The provider is a Claude API endpoint stubbed at the HTTP level
// (`QCStubProtocol`), so what was sent can be read back; `QCRig` does with the composer's effects what the input
// controller does.

// MARK: - A provider that records every request

/// Answers each request with "Answer: <the last user message as sent>" (or a reply queued for its host) as a streamed
/// Claude API answer, and keeps every body. Other wires get an error (their bodies are still kept).
final class QCStubProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case answer(String)
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
        configuration.protocolClasses = [QCStubProtocol.self]
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
        let anthropic = request.url?.path.hasSuffix("/v1/messages") == true
        let reply = Self.state.withLock { state -> Reply in
            state.bodies[host, default: []].append(body)
            guard anthropic else { return .status(599) }
            guard var queue = state.replies[host], !queue.isEmpty else {
                return .answer("Answer: " + ((try? QCSent(body))?.lastUser ?? "?"))
            }
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

/// A Claude API request as it was sent.
struct QCSent {
    var raw: Data
    var system: String
    /// (role, text), oldest first.
    var messages: [(role: String, text: String)]

    init(_ data: Data) throws {
        raw = data
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["messages"] as? [[String: Any]] else { throw CocoaError(.coderReadCorrupt) }
        system = json["system"] as? String ?? ""
        messages = list.map { message in
            let text: String
            if let s = message["content"] as? String { text = s }
            else if let parts = message["content"] as? [[String: Any]] { text = parts.compactMap { $0["text"] as? String }.joined() }
            else { text = "" }
            return (message["role"] as? String ?? "", text)
        }
    }

    var lastUser: String { messages.last { $0.role == "user" }?.text ?? "" }
    var body: String { String(decoding: raw, as: UTF8.self) }
}

// MARK: - Keys

private let qcAt = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
private let qcTab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
private let qcShiftReturn = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift)
private let qcCommandReturn = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .command)
private let qcCommandC = KeyEvent(keyCode: 0x08, characters: "c", charactersIgnoringModifiers: "c", modifiers: .command)
private let qcOptionSpace = KeyEvent(keyCode: VirtualKey.space, characters: "\u{A0}", charactersIgnoringModifiers: " ", modifiers: .option)
private func qcCommandDigit(_ n: Int) -> KeyEvent {
    KeyEvent(keyCode: 0x12, characters: String(n), charactersIgnoringModifiers: String(n), modifiers: .command)
}

// MARK: - The input controller, stood in for

/// A composer with a fake pinyin engine, wired to a `Converter` whose provider is `QCStubProtocol` at `host`, and a
/// recent-questions file in a temp folder (never the user's).
final class QCRig {
    let host: String
    let converter: Converter
    let config: Config
    let directory: URL
    let historyURL: URL
    private(set) var engine = FakeEngine()
    private(set) var composer: Composer
    private let actionKey: ActionKey
    private let commands: [Command]
    private let selection: Composer.Selection?
    private let english: Bool
    let claudeInstalled: Bool

    /// Secure input on: the composer is told, and requests are refused as the controller refuses them.
    var secure = false { didSet { let on = secure; composer.secureInputActive = { on } } }
    /// The app has no AI (`AppProfile.noAI`): the composer's refusal.
    var noAI: String? { didSet { let refusal = noAI; composer.aiRefusal = { refusal } } }
    /// `Config.rememberQuestions`.
    var rememberQuestions = true

    private(set) var log: [Composer.Effect] = []
    private(set) var committed: [String] = []
    private(set) var replaced: [String] = []
    private(set) var copied: [String] = []
    private(set) var opened: [URL] = []
    private(set) var claudeCode: [String] = []
    private(set) var notices: [String] = []
    private(set) var updates: [ConversionUpdate] = []

    static let secureMessage = "Secure input is on: nothing was sent"

    init(actionKey: ActionKey = .enter, english: Bool = true, selection: Composer.Selection? = nil,
         commands: [Command] = Command.builtins, claudeInstalled: Bool = true, history: QuestionHistory? = nil,
         historyJSON: String? = nil, configure: (inout Config) -> Void = { _ in }) {
        host = "qchat-\(UUID().uuidString.lowercased()).test"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("qchat-acceptance-\(UUID().uuidString)")
        historyURL = directory.appendingPathComponent("recent-questions.json")
        precondition(historyURL.path != QuestionHistory.defaultURL.path)
        var config = Config.default
        config.provider = .anthropic
        config.anthropic = ProviderSettings(baseURL: "https://\(host)")
        config.openai = ProviderSettings(model: "test-model", baseURL: "https://\(host)/v1")
        configure(&config)
        self.config = config
        let fixed = config
        converter = Converter(client: BedrockClient(session: QCStubProtocol.session()), loadConfig: { fixed },
                              loadCredentials: { _ in throw CocoaError(.userCancelled) },
                              loadKey: { _, _ in "sk-test" }, loadJargon: { _ in [] })
        self.actionKey = actionKey
        self.commands = commands
        self.selection = selection
        self.english = english
        self.claudeInstalled = claudeInstalled
        composer = Composer(engine: engine, actionKey: actionKey)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let history { try? history.write(to: historyURL) }
        if let historyJSON { try? Data(historyJSON.utf8).write(to: historyURL) }
        setUp()
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    private func setUp() {
        composer.commands = commands
        if let selection { composer.readSelection = { selection } }
        if english { composer.setInputMode(.english) }
        composer.questionRounds = config.questionRounds
        composer.handoffChoices = ChatHandoff.choices(config.questionContinueIn, claudeCode: claudeInstalled)
        composer.chatMessages = .english
        let on = secure
        composer.secureInputActive = { on }
        let refusal = noAI
        composer.aiRefusal = { refusal }
    }

    /// Another text field: a new composer, the same converter (its cache) and history file.
    func newField() {
        engine = FakeEngine()
        composer = Composer(engine: engine, actionKey: actionKey)
        setUp()
    }

    var c: Composer { composer }

    /// As the controller does before each key: the history, when nothing is being composed.
    private func reload() {
        guard !composer.isComposing else { return }
        composer.remembersQuestions = rememberQuestions
        composer.questionHistory = QuestionHistory.load(from: historyURL)
    }

    @discardableResult
    func key(_ event: KeyEvent) async -> [Composer.Effect] {
        reload()
        let out = composer.handleKeyDown(event).effects
        await perform(out)
        return out
    }

    /// Each character as a key (Space as the Space key).
    func type(_ text: String) async {
        for ch in text {
            if ch == " " { await key(spaceKey); continue }
            await key(KeyEvent(keyCode: 0, characters: String(ch), modifiers: ch.isUppercase ? .shift : []))
        }
    }

    @discardableResult
    func click(_ index: Int) async -> [Composer.Effect] {
        reload()
        let out = composer.choose(index: index)
        await perform(out)
        return out
    }

    func shiftTap(at t: Double) {
        _ = composer.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: t)
        _ = composer.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: t + 0.1)
    }

    /// "@", the palette letters, Tab: "@name ".
    func pick(_ letters: String) async {
        await key(qcAt)
        await type(letters)
        await key(qcTab)
    }

    /// "@question <question>" ⏎, answered.
    func ask(_ question: String) async {
        await pick("q")
        #expect(composer.draft == "@question ")
        await type(question)
        await key(enterKey)
    }

    /// Types `question` after the answer shown and asks it with ⇧⏎.
    @discardableResult
    func followUp(_ question: String) async -> [Composer.Effect] {
        await type(question)
        return await key(qcShiftReturn)
    }

    /// A conversation of `rounds` rounds: "q1", then "q2" … as follow-ups.
    func converse(_ rounds: Int) async {
        await ask("q1")
        for n in stride(from: 2, through: rounds, by: 1) { await followUp("q\(n)") }
    }

    var requests: [QCSent] { QCStubProtocol.bodies(host).compactMap { try? QCSent($0) } }
    var requestCount: Int { QCStubProtocol.bodies(host).count }
    var rawBodies: [Data] { QCStubProtocol.bodies(host) }
    var saved: QuestionHistory { QuestionHistory.load(from: historyURL) }
    var rows: [String] { composer.choices.filter { $0.kind != .original }.map(\.text) }
    var selected: String? { composer.choices.indices.contains(composer.highlighted) ? composer.choices[composer.highlighted].text : nil }

    func perform(_ effects: [Composer.Effect]) async {
        for effect in effects {
            log.append(effect)
            switch effect {
            case let .startCommand(command, input, id):
                if secure { await perform(composer.fail(Self.secureMessage, id: id)); continue }
                await run(converter.generate(command, input: input), id: id)
            case let .reask(command, input, id):
                if secure { await perform(composer.fail(Self.secureMessage, id: id)); continue }
                await run(converter.generate(command, input: input, fresh: true), id: id)
            case let .startConversion(input, id):
                if secure { await perform(composer.fail(Self.secureMessage, id: id)); continue }
                let command = composer.activeCommand?.kind == .convert ? composer.activeCommand : nil
                let (mode, text) = WritingMode.parse(command, input)
                await run(converter.convert(text, mode: mode), id: id)
            case let .startRefine(refinement, id):
                if secure { await perform(composer.fail(Self.secureMessage, id: id)); continue }
                switch refinement.request {
                case let .writing(command, input):
                    let (mode, text) = WritingMode.parse(command?.kind == .convert ? command : nil, input)
                    await run(converter.convert(text, mode: mode, turns: refinement.turns), id: id)
                case let .command(command, input):
                    await run(converter.generate(command, input: input, fresh: refinement.fresh, turns: refinement.turns), id: id)
                }
            case let .rememberQuestion(entry):
                guard rememberQuestions, !secure else { continue }
                var history = QuestionHistory.load(from: historyURL)
                history.record(entry)
                try? history.write(to: historyURL)
            case let .commit(text): committed.append(text)
            case let .typeOut(text): committed.append(text)
            case let .replaceSelection(text, _): replaced.append(text)
            case let .copy(text): copied.append(text)
            case let .openLink(url): opened.append(url)
            case let .continueInClaudeCode(prompt): claudeCode.append(prompt)
            case let .notice(text): notices.append(text)
            default: break
            }
        }
    }

    private func run(_ stream: AsyncThrowingStream<ConversionUpdate, Error>, id: Int) async {
        do {
            for try await update in stream {
                updates.append(update)
                await perform(composer.receive(update.result, isFinal: update.isFinal, id: id))
            }
        } catch {
            await perform(composer.fail("failed: \(error)", id: id))
        }
    }

    /// Whether anything was asked of the model by `effects`.
    static func asks(_ effects: [Composer.Effect]) -> Bool {
        effects.contains {
            switch $0 {
            case .startRefine, .startCommand, .startConversion, .reask: return true
            default: return false
            }
        }
    }
}

/// The answer the stub gives to `question` (sent as is).
func qcAnswer(_ question: String) -> String { "Answer: " + question }

/// @question's system prompt as release 0.6.3 sent it (55d496e).
let qcSystem063 = "The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the "
    + "language of their message unless they ask for another. Write plain text: line breaks only where they help (code, "
    + "steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No "
    + "Markdown (no headings, bold, tables or code fences), no preamble such as \"Sure\" or \"Here is\", and no closing "
    + "remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for "
    + "more. If you are not sure, say so briefly."

/// "What is Rust?" as release 0.6.3 sent it, byte for byte: the Claude API, then OpenAI-compatible (55d496e).
let qcGolden063Anthropic = #"{"max_tokens":5096,"messages":[{"content":"What is Rust?","role":"user"}],"model":"claude-haiku-5-5","output_config":{"effort":"low"},"stream":true,"system":"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \"Sure\" or \"Here is\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly."}"#
let qcGolden063OpenAI = #"{"max_tokens":1000,"messages":[{"content":"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \"Sure\" or \"Here is\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.","role":"system"},{"content":"What is Rust?","role":"user"}],"model":"test-model","stream":true}"#

/// What 0.6.4 adds after 0.6.3's @question system prompt (the live-data rule), read from a system prompt sent: nil when
/// that prompt isn't 0.6.3's followed by " " and more.
func qcLiveRule(in system: String) -> String? {
    guard system.hasPrefix(qcSystem063 + " "), system.count > qcSystem063.count + 1 else { return nil }
    return String(system.dropFirst(qcSystem063.count + 1))
}

/// The rule's own words, as a live-data rule should have them: a few of its subjects, and that it can't check.
func qcLooksLikeTheLiveRule(_ rule: String) -> Bool {
    let lower = rule.lowercased()
    return ["weather", "news", "price", "score"].allSatisfy(lower.contains) && lower.contains("live information")
}

// MARK: - The tests

@Suite("QuestionChatAcceptance")
struct QuestionChatAcceptanceTests {

    // MARK: The conversation

    /// conv: the answer in, typing goes on as the next question (not a refine), ⇧⏎ asks it, and the transcript grows a
    /// round at a time, oldest first, the latest answer selected.
    @Test func conv_typingAfterAnAnswerIsAFollowUpThatShiftReturnAsksAndTheTranscriptGrows() async throws {
        let rig = QCRig()
        await rig.ask("what is rust")
        #expect(rig.requestCount == 1 && rig.c.isQuestionChat && rig.c.chatRound == 1)
        #expect(rig.c.chatRounds == [QuestionChat.Round(question: "what is rust", answer: qcAnswer("what is rust"))])
        // Typing: a line for the next question; nothing is sent yet.
        await rig.type("who made it")
        #expect(rig.c.refineLine == "who made it" && rig.requestCount == 1 && rig.c.isLevelTwo)
        let ask = await rig.key(qcShiftReturn)
        #expect(QCRig.asks(ask) && rig.requestCount == 2)
        #expect(rig.c.chatRound == 2 && rig.c.chatRounds.map(\.question) == ["what is rust", "who made it"])
        #expect(rig.c.chatRounds.map(\.answer) == [qcAnswer("what is rust"), qcAnswer("who made it")])
        #expect(rig.c.refineLine == nil || rig.c.refineLine == "")
        // A third round.
        await rig.followUp("when")
        #expect(rig.requestCount == 3 && rig.c.chatRound == 3)
        #expect(rig.c.chatRounds.map(\.question) == ["what is rust", "who made it", "when"])
        // Every round's answer is a row, numbered 1… in round order; the questions aren't rows; the latest is selected.
        #expect(rig.c.choices.map(\.text) == [qcAnswer("what is rust"), qcAnswer("who made it"), qcAnswer("when")])
        #expect(rig.c.choices.map(\.label) == ["1", "2", "3"])
        #expect(rig.selected == qcAnswer("when"))
        #expect(rig.committed.isEmpty)
    }

    /// conv: pinyin in the next question goes through the engine as usual; ⇧⏎ asks what it makes.
    @Test func conv_aFollowUpCanBeTypedInPinyin() async throws {
        let rig = QCRig()
        await rig.ask("greet me")
        rig.shiftTap(at: 10)  // to Chinese
        await rig.type("nihao")
        #expect(rig.requestCount == 1)
        await rig.key(qcShiftReturn)
        #expect(rig.requestCount == 2)
        #expect(rig.requests.last?.lastUser == "你好", "sent \(rig.requests.last?.lastUser.debugDescription ?? "nil")")
        #expect(rig.c.chatRounds.last?.question == "你好")
    }

    /// CHANGE 1: Space while typing is a space in the question; Space with nothing typed inserts the selected answer.
    @Test func keys_spaceIsASpaceWhileTypingAndInsertsWithNothingTyped() async throws {
        let rig = QCRig()
        await rig.ask("what is rust")
        await rig.type("who made it")
        #expect(rig.c.refineLine == "who made it" && rig.committed.isEmpty)
        await rig.key(escKey)  // clears it
        #expect(rig.c.isLevelTwo && rig.committed.isEmpty)
        await rig.key(spaceKey)
        #expect(rig.committed == [qcAnswer("what is rust")] && !rig.c.isComposing)
    }

    /// CHANGE 1/2: ⏎ inserts the selected answer even with a follow-up half typed, which is dropped (nothing asked).
    @Test func keys_returnInsertsTheSelectedAnswerAndDropsAHalfTypedFollowUp() async throws {
        let rig = QCRig()
        await rig.converse(2)
        await rig.type("and th")
        let insert = await rig.key(enterKey)
        #expect(!QCRig.asks(insert) && rig.requestCount == 2)
        #expect(rig.committed == [qcAnswer("q2")], "inserted \(rig.committed)")
        #expect(!rig.committed.joined().contains("and th") && !rig.c.isComposing)
    }

    /// CHANGE 1: any round's answer: a digit picks it and inserts it at once.
    @Test func keys_aDigitInsertsThatRoundsAnswer() async throws {
        for n in 1...3 {
            let rig = QCRig()
            await rig.converse(3)
            let pick = await rig.key(k(String(n)))
            #expect(!QCRig.asks(pick) && rig.committed == [qcAnswer("q\(n)")], "digit \(n): \(rig.committed)")
            #expect(!rig.c.isComposing)
        }
    }

    /// CHANGE 1: ↑/↓ move between the answers (the selection starts on the latest) and ⏎ inserts the one selected.
    @Test func keys_upAndDownMoveBetweenAnswersAndReturnInsertsIt() async throws {
        let rig = QCRig()
        await rig.converse(3)
        #expect(rig.selected == qcAnswer("q3"))
        await rig.key(upKey)
        #expect(rig.selected == qcAnswer("q2"))
        await rig.key(upKey)
        #expect(rig.selected == qcAnswer("q1"))
        await rig.key(downKey)
        #expect(rig.selected == qcAnswer("q2"))
        await rig.key(enterKey)
        #expect(rig.committed == [qcAnswer("q2")] && rig.requestCount == 3)
    }

    /// CHANGE 1: clicking an answer inserts it.
    @Test func keys_clickingAnAnswerInsertsIt() async throws {
        let rig = QCRig()
        await rig.converse(3)
        await rig.click(0)
        #expect(rig.committed == [qcAnswer("q1")])
        let other = QCRig()
        await other.converse(3)
        await other.click(1)
        #expect(other.committed == [qcAnswer("q2")])
    }

    /// CHANGE 1: ⌘C copies the selected answer (the latest, or the one moved to), and the conversation stays up.
    @Test func keys_commandCCopiesTheSelectedAnswer() async throws {
        let rig = QCRig()
        await rig.converse(2)
        await rig.key(qcCommandC)
        #expect(rig.copied == [qcAnswer("q2")] && rig.c.isQuestionChat && rig.committed.isEmpty)
        await rig.key(upKey)
        await rig.key(qcCommandC)
        #expect(rig.copied == [qcAnswer("q2"), qcAnswer("q1")])
        #expect(rig.c.chatRound == 2 && rig.committed.isEmpty)
    }

    /// CHANGE 1: a long answer (several lines) is one selectable item, inserted whole.
    @Test func keys_aLongAnswerIsOneItem() async throws {
        let rig = QCRig()
        let long = "Line one of the answer.\nLine two of the answer.\nLine three of the answer."
        QCStubProtocol.enqueue(rig.host, .answer(long))
        await rig.ask("explain")
        #expect(rig.c.choices.count == 1)
        await rig.key(enterKey)
        #expect(rig.committed.count == 1)
        #expect(rig.committed.first?.contains("Line one") == true && rig.committed.first?.contains("Line three") == true)
    }

    /// CHANGE 2 (over CHANGE 1): ⇧⏎ with nothing typed keeps its global meaning, inserting what was typed as typed;
    /// nothing is asked.
    @Test func keys_shiftReturnWithNothingTypedInsertsAsTyped() async throws {
        let rig = QCRig()
        await rig.ask("what is rust")
        let typed = rig.c.draft
        #expect(typed == "@question what is rust")
        let out = await rig.key(qcShiftReturn)
        #expect(!QCRig.asks(out) && rig.requestCount == 1)
        #expect(rig.committed == [typed], "inserted \(rig.committed)")
        #expect(!rig.c.isComposing)
        // At a later round too.
        let later = QCRig()
        await later.converse(2)
        let draft = later.c.draft
        await later.key(qcShiftReturn)
        #expect(later.requestCount == 2 && later.committed == [draft])
    }

    /// Coordinator: the action key (⌥Space here) still sends a typed follow-up; ⏎ inserts.
    @Test func keys_theActionKeySendsATypedFollowUp() async throws {
        let rig = QCRig(actionKey: .optionSpace)
        await rig.pick("q")
        await rig.type("what is rust")
        await rig.key(qcOptionSpace)
        #expect(rig.requestCount == 1 && rig.c.isQuestionChat)
        await rig.type("who made it")
        await rig.key(qcOptionSpace)
        #expect(rig.requestCount == 2 && rig.c.chatRounds.last?.question == "who made it")
        await rig.type("and")
        await rig.key(enterKey)
        #expect(rig.requestCount == 2 && rig.committed == [qcAnswer("who made it")])
    }

    // MARK: Esc

    /// Esc: the text typed is cleared first, then the choices (⌘⏎) are hidden, then a round goes (the last Q and A are
    /// dropped, and not sent again), and at round 1 the conversation is left as before (back to the question's text).
    @Test func esc_clearsTheTextThenHidesTheChoicesThenGoesBackARoundThenLeaves() async throws {
        let rig = QCRig()
        await rig.converse(3)
        await rig.key(qcCommandReturn)
        #expect(rig.c.showsHandoff)
        await rig.type("more")
        #expect(rig.c.refineLine == "more")
        // 1. The text.
        await rig.key(escKey)
        #expect(rig.c.refineText.isEmpty && rig.c.chatRound == 3)
        #expect(rig.c.showsHandoff, "Esc with text typed only clears it")
        // 2. The choices.
        await rig.key(escKey)
        #expect(!rig.c.showsHandoff && rig.c.chatRound == 3 && rig.c.isQuestionChat)
        // 3. A round back: the latest answer is round 2's, selected.
        await rig.key(escKey)
        #expect(rig.c.chatRound == 2 && rig.c.chatRounds.map(\.question) == ["q1", "q2"])
        #expect(rig.c.choices.map(\.text) == [qcAnswer("q1"), qcAnswer("q2")] && rig.selected == qcAnswer("q2"))
        await rig.key(escKey)
        #expect(rig.c.chatRound == 1 && rig.c.chatRounds.map(\.question) == ["q1"] && rig.c.isLevelTwo)
        // The round dropped isn't sent with the next question.
        await rig.followUp("q2b")
        let last = try #require(rig.requests.last)
        #expect(last.messages.map(\.text) == ["q1", qcAnswer("q1"), "q2b"])
        // The saved thread is the conversation as it now is (the saved-answer-replaces rule).
        #expect(rig.saved.entries.map { $0.thread.map(\.question) } == [["q1", "q2b"]])
        await rig.key(escKey)
        // 4. At round 1: left, back to the question as typed; nothing inserted, nothing asked.
        await rig.key(escKey)
        #expect(!rig.c.isLevelTwo && rig.c.draft == "@question q1")
        #expect(rig.committed.isEmpty && rig.requestCount == 4)
    }

    // MARK: The requests

    /// req: a follow-up is a multi-turn request: the same system prompt, the earlier questions and answers as user and
    /// assistant turns, then the new question, as plain messages (not the `<refine>` wording).
    @Test func req_followUpsAreMultiTurnWithPlainUserMessages() async throws {
        let rig = QCRig()
        await rig.converse(3)
        let sent = rig.requests
        try #require(sent.count == 3)
        #expect(sent[0].messages.map(\.role) == ["user"] && sent[0].messages.map(\.text) == ["q1"])
        #expect(sent[1].messages.map(\.role) == ["user", "assistant", "user"])
        #expect(sent[1].messages.map(\.text) == ["q1", qcAnswer("q1"), "q2"])
        #expect(sent[2].messages.map(\.role) == ["user", "assistant", "user", "assistant", "user"])
        #expect(sent[2].messages.map(\.text) == ["q1", qcAnswer("q1"), "q2", qcAnswer("q2"), "q3"])
        // The same system prompt every round, nothing about refining in it or in the turns.
        #expect(sent[1].system == sent[0].system && sent[2].system == sent[0].system)
        for request in sent {
            #expect(!request.body.contains("<refine>") && !request.body.contains("refine"), "\(request.body)")
        }
        // The rest of the request (model, limits, stream) as round 1's.
        func others(_ s: QCSent) throws -> NSDictionary {
            var json = try #require(try JSONSerialization.jsonObject(with: s.raw) as? [String: Any])
            json["messages"] = nil
            return json as NSDictionary
        }
        #expect(try others(sent[2]) == others(sent[0]))
    }

    /// req: round 1 is byte for byte 0.6.3's @question request, apart from the live-data rule at the end of its system
    /// prompt (Claude API, through the panel; OpenAI-compatible, through the converter).
    @Test func req_roundOneIsByteIdenticalTo063ApartFromTheLiveDataRule() async throws {
        let rig = QCRig()
        await rig.ask("What is Rust?")
        let first = try #require(rig.requests.first)
        let rule = try #require(qcLiveRule(in: first.system), "system: \(first.system)")
        #expect(qcLooksLikeTheLiveRule(rule), "rule: \(rule)")
        #expect(!rule.contains("\"") && !rule.contains("\\") && !rule.contains("/"))
        let want = qcGolden063Anthropic.replacingOccurrences(of: "say so briefly.\"}", with: "say so briefly. \(rule)\"}")
        #expect(first.body == want, "sent \(first.body)")

        // OpenAI-compatible.
        let openai = QCRig { $0.provider = .openai }
        do { for try await _ in openai.converter.generate(.question, input: "What is Rust?") {} } catch {}
        let body = String(decoding: try #require(openai.rawBodies.first), as: UTF8.self)
        let wantOpenAI = qcGolden063OpenAI.replacingOccurrences(of: "say so briefly.\",\"role\"", with: "say so briefly. \(rule)\",\"role\"")
        #expect(body == wantOpenAI, "sent \(body)")
    }

    /// req: values hidden from the AI are hidden in every round's turns (the questions and the answers sent back), each
    /// with the same placeholder throughout; the answers shown have the real values back.
    @Test func req_redactionAppliesToEveryRound() async throws {
        let rig = QCRig { $0.redaction = RedactionSettings(enabled: true, customWords: ["Phoenix"]) }
        let phone = "+86 138 0013 8000"
        await rig.ask("is Phoenix on track")
        await rig.followUp("call \(phone) about Phoenix")
        await rig.followUp("and Phoenix again")
        let sent = rig.requests
        try #require(sent.count == 3)
        let secrets = ["Phoenix", "phoenix", "138 0013 8000", "13800138000"]
        for (n, data) in rig.rawBodies.enumerated() {
            let body = String(decoding: data, as: UTF8.self)
            for secret in secrets { #expect(!body.contains(secret), "request \(n + 1) has \(secret): \(body)") }
        }
        for (n, request) in sent.enumerated() {
            for message in request.messages {
                for secret in secrets { #expect(!message.text.contains(secret), "request \(n + 1) \(message.role): \(message.text)") }
            }
        }
        // The word has one placeholder, the same in every turn of the last request.
        let third = sent[2].messages.map(\.text)
        let placeholder = try #require(third[0].components(separatedBy: " ").first { $0.hasPrefix("[") && $0.contains("_") })
        #expect(third[0] == "is \(placeholder) on track")
        #expect(third[2].hasSuffix("about \(placeholder)") && third[4] == "and \(placeholder) again")
        #expect(third[1].contains(placeholder) && third[3].contains(placeholder))
        // What is shown has the real values.
        #expect(rig.c.chatRounds.map(\.answer) == [qcAnswer("is Phoenix on track"), qcAnswer("call \(phone) about Phoenix"),
                                                   qcAnswer("and Phoenix again")])
    }

    /// req: a follow-up is cached like other conversions: the same conversation in another field isn't sent again;
    /// another question is.
    @Test func req_followUpsAreCached() async throws {
        let rig = QCRig()
        await rig.converse(2)
        #expect(rig.requestCount == 2)
        rig.newField()
        await rig.converse(2)
        #expect(rig.requestCount == 2, "the same conversation was sent again")
        #expect(rig.c.chatRounds.map(\.answer) == [qcAnswer("q1"), qcAnswer("q2")])
        await rig.followUp("q3")
        #expect(rig.requestCount == 3)
    }

    // MARK: The context limit

    func appleModelSize(_ request: AppleModelRequest) -> Int {
        AppleModel.estimatedTokens(request.instructions) + AppleModel.estimatedTokens(request.prompt)
            + request.examples.reduce(0) { $0 + AppleModel.estimatedTokens($1.prompt) + AppleModel.estimatedTokens($1.response) }
    }

    /// Four long rounds and a last question, as the composer keeps them.
    func longConversation() -> (first: String, turns: [Refinement.Turn], questions: [String], answers: [String]) {
        let questions = (1...5).map { "question number \($0)?" }
        let answers = (1...4).map { "Start of answer \($0). " + String(repeating: "Some words of the answer. ", count: 160) + "End of answer \($0)." }
        let turns = (0..<4).map {
            Refinement.Turn(answer: ConversionResult(versions: [CandidateLine(answers[$0])]), instruction: questions[$0 + 1])
        }
        return (questions[0], turns, questions, answers)
    }

    /// ctx: on the on-device model a conversation too long for the context is fitted: the oldest answers' middles or
    /// the oldest rounds go first, the last question goes whole, and the update says "shortened". It is then answered
    /// (the framework would refuse a request that doesn't fit). With 8K (macOS 27) at least as much is kept as with 4K;
    /// where the whole conversation fits, it goes whole and nothing is said.
    @Test func ctx_theOnDeviceModelGetsAShortenedConversationAndSaysSo() async throws {
        let (first, turns, questions, answers) = longConversation()
        var wholeAnswers: [Int: Int] = [:]
        for contextSize in [4096, 8192] {
            let model = ScriptedAppleModel(.frameworkLike("Fine."), contextSize: contextSize)
            let converter = AppleAcceptance.converter(AppleAcceptance.apple(), model)
            var updates: [ConversionUpdate] = []
            for try await update in converter.generate(.question, input: first, turns: turns) { updates.append(update) }
            let final = try #require(updates.last)
            #expect(final.isFinal && final.result.versions.first?.text == "Fine.", "\(contextSize)")
            let request = try #require(model.log.requests.last)
            let room = min(Config.default.maxTokens, AppleModel.answerRoom, contextSize / 3)
            let wholeSize = AppleModel.estimatedTokens(request.instructions)
                + questions.reduce(0) { $0 + AppleModel.estimatedTokens($1) } + answers.reduce(0) { $0 + AppleModel.estimatedTokens($1) }
            let fitsWhole = wholeSize + room <= contextSize
            #expect(final.shortened == !fitsWhole, "\(contextSize): shortened \(final.shortened), fits whole \(fitsWhole)")
            #expect(contextSize != 4096 || final.shortened, "4K: this conversation can't fit whole")
            #expect(request.prompt == questions[4], "\(contextSize): the last question whole")
            #expect(appleModelSize(request) + room <= contextSize)
            // What's left of the earlier rounds is in order, the newest kept; shortening goes from the oldest.
            let kept = request.examples
            #expect(!kept.isEmpty && kept.count <= 4)
            let offset = 4 - kept.count
            for (i, example) in kept.enumerated() { #expect(example.prompt == questions[offset + i], "\(contextSize)") }
            let whole = kept.enumerated().map { $0.element.response == answers[offset + $0.offset] }
            // Once an answer is whole, every newer one is too.
            if let firstWhole = whole.firstIndex(of: true) { #expect(whole[firstWhole...].allSatisfy { $0 }, "\(contextSize): \(whole)") }
            #expect(whole.last == true, "\(contextSize): the newest answer should be kept whole here")
            for (i, example) in kept.enumerated() where !whole[i] {
                let answer = answers[offset + i]
                // A shortened answer keeps its start (or its end) and is shorter.
                #expect(example.response.count < answer.count)
                #expect(example.response.hasPrefix("Start of answer \(offset + i + 1)") || example.response.hasSuffix("End of answer \(offset + i + 1)."))
            }
            if fitsWhole { #expect(kept.count == 4 && whole.allSatisfy { $0 }, "\(contextSize)") }
            wholeAnswers[contextSize] = whole.filter { $0 }.count
        }
        #expect((wholeAnswers[8192] ?? 0) >= (wholeAnswers[4096] ?? 0))
    }

    /// ctx: a conversation that fits is sent whole to the on-device model, and nothing is said.
    @Test func ctx_aShortConversationIsSentWholeOnDevice() async throws {
        let model = ScriptedAppleModel(.frameworkLike("Fine."), contextSize: 4096)
        let converter = AppleAcceptance.converter(AppleAcceptance.apple(), model)
        let turns = [Refinement.Turn(answer: ConversionResult(versions: [CandidateLine("A language.")]), instruction: "who made it?")]
        var updates: [ConversionUpdate] = []
        for try await update in converter.generate(.question, input: "what is rust?", turns: turns) { updates.append(update) }
        #expect(!updates.isEmpty && updates.allSatisfy { !$0.shortened })
        let request = try #require(model.log.requests.last)
        #expect(request.examples.map(\.prompt) == ["what is rust?"] && request.examples.map(\.response) == ["A language."])
        #expect(request.prompt == "who made it?")
    }

    /// Coordinator: only conversations on the on-device model are trimmed: another provider gets the whole of a long
    /// one, not said to be shortened.
    @Test func ctx_otherProvidersGetTheWholeConversation() async throws {
        let rig = QCRig()
        let (first, turns, questions, answers) = longConversation()
        var updates: [ConversionUpdate] = []
        for try await update in rig.converter.generate(.question, input: first, turns: turns) { updates.append(update) }
        #expect(!updates.isEmpty && updates.allSatisfy { !$0.shortened })
        let sent = try #require(rig.requests.last)
        var want: [String] = []
        for i in 0..<4 { want += [questions[i], answers[i]] }
        #expect(sent.messages.map(\.text) == want + [questions[4]])
    }

    @Test func ctx_shortenedIsOffByDefault() {
        let update = ConversionUpdate(result: .empty, rawText: "", isFinal: true, elapsed: 0, firstTokenLatency: nil, fromCache: false)
        #expect(!update.shortened)
    }

    // MARK: The round limit

    /// limit: after the 5th answer (the default) the next-question line is the hand-off row; before it, not. Typing then
    /// doesn't ask a 6th question in the panel: it is the first message of the hand-off.
    @Test func limit_afterTheFifthAnswerTheHandoffRowAndNoSixthQuestion() async throws {
        #expect(Config.default.questionRounds == 5)
        let rig = QCRig()
        await rig.converse(4)
        #expect(rig.c.chatRound == 4 && !rig.c.showsHandoff && !rig.c.chatAtLimit)
        await rig.followUp("q5")
        #expect(rig.requestCount == 5 && rig.c.chatRound == 5)
        #expect(rig.c.showsHandoff && rig.c.chatAtLimit)
        // A 6th question isn't asked here.
        await rig.type("tell me more")
        let out = await rig.key(qcShiftReturn)
        #expect(rig.requestCount == 5 && !QCRig.asks(out))
        #expect(!rig.committed.contains { $0.contains("tell me more") })
    }

    /// limit: at the limit, the typed text goes with the hand-off as its first message (here, to Claude Code).
    @Test func limit_typingAfterTheLastRoundIsTheHandoffsFirstMessage() async throws {
        let rig = QCRig { $0.questionContinueIn = [.claudeCode, .copy] }
        await rig.converse(5)
        await rig.type("tell me more")
        await rig.key(qcCommandDigit(1))
        let prompt = try #require(rig.claudeCode.first)
        #expect(prompt.hasSuffix("tell me more"), "\(prompt)")
        #expect(prompt.contains("q5") && prompt.contains(qcAnswer("q5")))
        #expect(rig.requestCount == 5)
    }

    /// limit: ⏎ still inserts the selected answer at the limit, and digits still pick answers there.
    @Test func limit_returnAndDigitsStillInsertAnswersAtTheLimit() async throws {
        let rig = QCRig()
        await rig.converse(5)
        await rig.key(enterKey)
        #expect(rig.committed == [qcAnswer("q5")])
        let digits = QCRig()
        await digits.converse(5)
        await digits.key(k("2"))
        #expect(digits.committed == [qcAnswer("q2")] && digits.opened.isEmpty && digits.copied.isEmpty)
    }

    /// limit: Esc at the limit goes back a round, where questions can be asked again.
    @Test func limit_escAtTheLimitGoesBackARound() async throws {
        let rig = QCRig()
        await rig.converse(5)
        await rig.key(escKey)
        #expect(rig.c.chatRound == 4 && !rig.c.showsHandoff)
        await rig.followUp("q5b")
        #expect(rig.requestCount == 6 && rig.c.chatRound == 5 && rig.c.showsHandoff)
    }

    /// limit: `questionRounds` sets it (2–10): 2 here.
    @Test func limit_theRoundLimitIsConfigurable() async throws {
        let two = QCRig { $0.questionRounds = 2 }
        await two.ask("q1")
        #expect(!two.c.showsHandoff)
        await two.followUp("q2")
        #expect(two.c.showsHandoff && two.c.chatAtLimit)
        await two.type("q3")
        await two.key(qcShiftReturn)
        #expect(two.requestCount == 2)

        let ten = QCRig { $0.questionRounds = 10 }
        await ten.converse(9)
        #expect(ten.c.chatRound == 9 && !ten.c.showsHandoff)
        await ten.followUp("q10")
        #expect(ten.c.chatRound == 10 && ten.c.showsHandoff && ten.requestCount == 10)
    }

    /// limit: in the config file, `questionRounds` is 5 when absent and kept within 2–10.
    @Test func limit_theConfigKeepsTheRoundsWithinTwoToTen() throws {
        func decoded(_ json: String) throws -> Config { try JSONDecoder().decode(Config.self, from: Data(json.utf8)) }
        #expect(try decoded("{}").questionRounds == 5)
        #expect(try decoded(#"{"questionRounds": 7}"#).questionRounds == 7)
        #expect(try decoded(#"{"questionRounds": 1}"#).questionRounds == 2)
        #expect(try decoded(#"{"questionRounds": 2}"#).questionRounds == 2)
        #expect(try decoded(#"{"questionRounds": 10}"#).questionRounds == 10)
        #expect(try decoded(#"{"questionRounds": 50}"#).questionRounds == 10)
        // Through a save and a load.
        var config = Config.default
        config.questionRounds = 3
        config.questionContinueIn = [.gemini, .copy]
        let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(back.questionRounds == 3 && back.questionContinueIn == [.gemini, .copy])
        // The names in the spec.
        let names = try decoded(#"{"questionContinueIn": ["claudeCode","claudeWeb","chatgpt","gemini","copy"]}"#)
        #expect(names.questionContinueIn == [.claudeCode, .claudeWeb, .chatgpt, .gemini, .copy])
    }

    // MARK: Continuing elsewhere

    /// Coordinator: ⌘⏎ opens the choices at any round (round 1 here); ⌘1–⌘5 pick one while they're shown; digits still
    /// pick answers; Esc hides them.
    @Test func handoff_commandReturnOpensTheChoicesAtAnyRound() async throws {
        let rig = QCRig()
        await rig.ask("what is rust")
        #expect(!rig.c.showsHandoff)
        // ⌘1 before they are shown does nothing of the hand-off.
        await rig.key(qcCommandDigit(4))
        #expect(rig.copied.isEmpty && rig.opened.isEmpty && rig.claudeCode.isEmpty)
        await rig.key(qcCommandReturn)
        #expect(rig.c.showsHandoff && rig.requestCount == 1 && rig.committed.isEmpty)
        #expect(rig.c.handoffChoices == [.claudeCode, .claudeWeb, .chatgpt, .copy])
        await rig.key(escKey)
        #expect(!rig.c.showsHandoff && rig.c.isQuestionChat)
        await rig.key(qcCommandReturn)
        // ⌘4: Copy, the 4th choice.
        await rig.key(qcCommandDigit(4))
        #expect(rig.copied.count == 1 && rig.committed.isEmpty && !rig.c.isComposing)

        // A digit with the choices shown still picks an answer.
        let digits = QCRig()
        await digits.converse(2)
        await digits.key(qcCommandReturn)
        await digits.key(k("1"))
        #expect(digits.committed == [qcAnswer("q1")] && digits.copied.isEmpty && digits.opened.isEmpty)
    }

    /// handoff: Claude Code gets the transcript, "Let's continue this discussion" (English), then the follow-up typed;
    /// the panel closes and nothing is inserted.
    @Test func handoff_claudeCodeGetsTheTranscriptAndTheContinuation() async throws {
        let rig = QCRig()
        rig.c.chatMessages = .chinese  // the hand-off text is English whatever the interface's language
        await rig.converse(2)
        await rig.key(qcCommandReturn)
        await rig.type("and in 2020")
        await rig.key(qcCommandDigit(1))
        let prompt = try #require(rig.claudeCode.first)
        #expect(rig.claudeCode.count == 1 && rig.committed.isEmpty && rig.replaced.isEmpty && !rig.c.isComposing)
        let q1 = try #require(prompt.range(of: "q1")), a1 = try #require(prompt.range(of: qcAnswer("q1")))
        let q2 = try #require(prompt.range(of: "q2")), a2 = try #require(prompt.range(of: qcAnswer("q2")))
        let more = try #require(prompt.range(of: "Let's continue this discussion"))
        let typed = try #require(prompt.range(of: "and in 2020"))
        #expect(q1.lowerBound < a1.lowerBound && a1.lowerBound < q2.lowerBound && q2.lowerBound < a2.lowerBound)
        #expect(a2.upperBound <= more.lowerBound && more.upperBound <= typed.lowerBound)
        #expect(rig.requestCount == 2)
    }

    /// handoff: Copy puts the conversation on the clipboard as Markdown, "**Q:**" and "**A:**" lines in order.
    @Test func handoff_copyIsMarkdownWithQAndALines() async throws {
        let rig = QCRig { $0.questionContinueIn = [.copy] }
        await rig.converse(2)
        await rig.key(qcCommandReturn)
        await rig.key(qcCommandDigit(1))
        let text = try #require(rig.copied.first)
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        #expect(lines == ["**Q:** q1", "**A:** " + qcAnswer("q1"), "**Q:** q2", "**A:** " + qcAnswer("q2")], "\(text)")
        #expect(rig.committed.isEmpty && !rig.c.isComposing)
    }

    /// handoff: Claude and ChatGPT on the web: the text in `?q=` when it fits a safe length.
    @Test func handoff_theWebGetsTheTextInTheAddressWhenItFits() async throws {
        let rig = QCRig { $0.questionContinueIn = [.claudeWeb, .chatgpt] }
        await rig.ask("what is a & b + c # d = e?")
        await rig.key(qcCommandReturn)
        await rig.key(qcCommandDigit(1))
        let url = try #require(rig.opened.first)
        #expect(url.absoluteString.hasPrefix("https://claude.ai/new?q="), "\(url)")
        let q = try #require(url.absoluteString.components(separatedBy: "?q=").last?.removingPercentEncoding)
        #expect(q.contains("what is a & b + c # d = e?") && q.contains("Let's continue this discussion"), "\(q)")
        #expect(rig.copied.isEmpty, "nothing need go on the clipboard")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.count == 1)

        let gpt = QCRig { $0.questionContinueIn = [.claudeWeb, .chatgpt] }
        await gpt.ask("what is rust")
        await gpt.key(qcCommandReturn)
        await gpt.key(qcCommandDigit(2))
        let chat = try #require(gpt.opened.first)
        #expect(chat.host == "chatgpt.com" && chat.absoluteString.contains("?q="), "\(chat)")
        #expect(chat.absoluteString.components(separatedBy: "?q=").last?.removingPercentEncoding?.contains("what is rust") == true)
    }

    /// handoff: too long for an address: the conversation on the clipboard, the site opened without it, and the notice
    /// says to paste it.
    @Test func handoff_aLongConversationGoesOnTheClipboard() async throws {
        let rig = QCRig { $0.questionContinueIn = [.claudeWeb, .chatgpt] }
        QCStubProtocol.enqueue(rig.host, .answer(String(repeating: "长回答。", count: 1500)))
        await rig.ask("tell me everything")
        await rig.key(qcCommandReturn)
        await rig.key(qcCommandDigit(1))
        let url = try #require(rig.opened.first)
        #expect(url.absoluteString == "https://claude.ai/new" || url.absoluteString == "https://claude.ai/new/", "\(url)")
        let clip = try #require(rig.copied.first)
        #expect(clip.contains("tell me everything") && clip.contains("长回答。") && clip.contains("Let's continue this discussion"))
        #expect(rig.notices.contains { $0.lowercased().contains("clipboard") && $0.lowercased().contains("paste") }, "\(rig.notices)")
    }

    /// handoff: the length rule itself (about 6000 characters): short text in the address, long text on the clipboard,
    /// and no address longer than the limit.
    @Test func handoff_theLengthRule() throws {
        #expect((5000...7000).contains(ChatHandoff.maxURLLength))
        for destination in [ChatHandoff.Destination.claudeWeb, .chatgpt] {
            let short = String(repeating: "a", count: 4000)
            switch ChatHandoff.action(destination, prompt: short, copied: "copied") {
            case let .open(url, clipboard):
                #expect(clipboard == nil && url.absoluteString.contains("?q=") && url.absoluteString.count <= ChatHandoff.maxURLLength)
            default: Issue.record("\(destination): not opened")
            }
            for long in [String(repeating: "a", count: 7000), String(repeating: "中", count: 1000)] {
                switch ChatHandoff.action(destination, prompt: long, copied: "copied") {
                case let .open(url, clipboard):
                    #expect(clipboard == long && !url.absoluteString.contains("?q="), "\(destination)")
                default: Issue.record("\(destination): not opened")
                }
            }
        }
        // Gemini: copied, its app opened (no prefill).
        switch ChatHandoff.action(.gemini, prompt: "hi", copied: "copied") {
        case let .open(url, clipboard): #expect(url.absoluteString == "https://gemini.google.com/app" && clipboard == "hi")
        default: Issue.record("gemini: not opened")
        }
    }

    /// Coordinator: by default the choices are Claude Code (if installed), Claude on the web, ChatGPT and Copy; Gemini is
    /// opt-in; Claude Code is never offered when it isn't installed.
    @Test func handoff_theChoicesClaudeCodeOnlyWhenInstalledAndGeminiOptIn() async throws {
        #expect(ChatHandoff.defaultChoices(claudeCode: true) == [.claudeCode, .claudeWeb, .chatgpt, .copy])
        #expect(ChatHandoff.defaultChoices(claudeCode: false) == [.claudeWeb, .chatgpt, .copy])
        #expect(ChatHandoff.choices(nil, claudeCode: true) == [.claudeCode, .claudeWeb, .chatgpt, .copy])
        #expect(ChatHandoff.choices(nil, claudeCode: false) == [.claudeWeb, .chatgpt, .copy])
        #expect(ChatHandoff.choices([.gemini, .claudeCode, .copy], claudeCode: false) == [.gemini, .copy])
        #expect(ChatHandoff.choices([.chatgpt, .claudeCode], claudeCode: true) == [.chatgpt, .claudeCode])
        #expect(Config.default.questionContinueIn == nil)

        // In the panel: without Claude Code, ⌘1 is Claude on the web, and no Terminal is started.
        let rig = QCRig(claudeInstalled: false)
        await rig.ask("what is rust")
        await rig.key(qcCommandReturn)
        #expect(!rig.c.handoffChoices.contains(.claudeCode) && !rig.c.handoffChoices.contains(.gemini))
        await rig.key(qcCommandDigit(1))
        #expect(rig.claudeCode.isEmpty && rig.opened.first?.host == "claude.ai")
    }

    /// Coordinator: during secure input, and in an app with no AI, the hand-off is refused (nothing opened or started,
    /// the conversation still up), except Copy.
    @Test func handoff_refusedInSecureInputAndNoAIAppsExceptCopy() async throws {
        for refusal in ["secure", "noAI"] {
            let rig = QCRig()
            await rig.converse(2)
            if refusal == "secure" { rig.secure = true } else { rig.noAI = "No AI in this app" }
            await rig.key(qcCommandReturn)
            for n in 1...3 {
                await rig.key(qcCommandDigit(n))
                #expect(rig.opened.isEmpty && rig.claudeCode.isEmpty && rig.copied.isEmpty, "\(refusal) ⌘\(n)")
                #expect(rig.c.isQuestionChat && rig.committed.isEmpty, "\(refusal) ⌘\(n): the conversation should stay up")
            }
            #expect(!rig.notices.isEmpty, "\(refusal): nothing said")
            if !rig.c.showsHandoff { await rig.key(qcCommandReturn) }
            await rig.key(qcCommandDigit(4))  // Copy
            #expect(rig.copied.count == 1 && rig.copied.first?.contains(qcAnswer("q2")) == true, "\(refusal): copy")
            #expect(rig.requestCount == 2)
        }
    }

    /// Privacy: the hand-off carries the real text, not the placeholders of values hidden from our own requests.
    @Test func handoff_carriesTheRealValuesNotPlaceholders() async throws {
        let rig = QCRig {
            $0.redaction = RedactionSettings(enabled: true, customWords: ["Phoenix"])
            $0.questionContinueIn = [.copy, .claudeCode]
        }
        await rig.ask("is Phoenix on track")
        await rig.followUp("call +86 138 0013 8000 about Phoenix")
        await rig.key(qcCommandReturn)
        await rig.key(qcCommandDigit(1))
        let text = try #require(rig.copied.first)
        #expect(text.contains("is Phoenix on track") && text.contains("+86 138 0013 8000") && text.contains(qcAnswer("is Phoenix on track")))
        #expect(!text.contains("[ITEM_") && !text.contains("[PHONE_") && !text.contains("_1]"), "\(text)")
    }

    // MARK: History

    /// hist: the whole thread is saved, by its first question, once; each round updates it.
    @Test func hist_theWholeThreadIsSavedByItsFirstQuestion() async throws {
        let rig = QCRig()
        await rig.ask("what is rust")
        #expect(rig.saved.entries.map(\.question) == ["what is rust"])
        await rig.followUp("who made it")
        await rig.followUp("when")
        let entries = rig.saved.entries
        try #require(entries.count == 1)
        #expect(entries[0].question == "what is rust" && entries[0].answer == qcAnswer("when"))
        #expect(entries[0].thread == [
            QuestionChat.Round(question: "what is rust", answer: qcAnswer("what is rust")),
            QuestionChat.Round(question: "who made it", answer: qcAnswer("who made it")),
            QuestionChat.Round(question: "when", answer: qcAnswer("when")),
        ])
    }

    /// hist: a file from 0.6.3 (single answers) loads, each entry one round, and can be continued.
    @Test func hist_oldSingleAnswerFilesLoadAsOneRoundAndCanBeContinued() async throws {
        let json = """
            {
              "entries" : [
                {
                  "answer" : "A systems language.",
                  "date" : "2026-10-10T08:00:00Z",
                  "question" : "what is rust"
                },
                {
                  "answer" : "量子比特。",
                  "date" : "2026-10-09T08:00:00Z",
                  "question" : "量子计算是什么"
                }
              ]
            }
            """
        let rig = QCRig(historyJSON: json)
        let loaded = rig.saved.entries
        try #require(loaded.count == 2)
        #expect(loaded[0].thread == [QuestionChat.Round(question: "what is rust", answer: "A systems language.")])
        #expect(loaded[1].thread == [QuestionChat.Round(question: "量子计算是什么", answer: "量子比特。")])
        #expect(loaded[0].rounds == nil || loaded[0].rounds?.count == 1)
        // Picked, then continued.
        await rig.pick("q")
        await rig.key(k("1"))
        #expect(rig.c.showsSavedAnswer && rig.c.chatRounds == loaded[0].thread && rig.requestCount == 0)
        await rig.followUp("who made it")
        let sent = try #require(rig.requests.last)
        #expect(sent.messages.map(\.text) == ["what is rust", "A systems language.", "who made it"])
        let entries = rig.saved.entries
        #expect(entries.count == 2 && entries[0].question == "what is rust" && entries[0].thread.count == 2)
    }

    /// hist: a saved conversation picked shows its transcript and goes on under the round limit; the saved thread is
    /// updated, not doubled.
    @Test func hist_aSavedThreadShowsItsTranscriptAndGoesOn() async throws {
        let rounds = [QuestionChat.Round(question: "what is rust", answer: "A language."),
                      QuestionChat.Round(question: "who made it", answer: "Graydon Hoare.")]
        let history = QuestionHistory(entries: [QuestionHistory.Entry(rounds: rounds, date: Date(timeIntervalSince1970: 1_790_000_000))])
        let rig = QCRig(history: history)
        await rig.pick("q")
        await rig.key(k("1"))
        #expect(rig.c.showsSavedAnswer && rig.requestCount == 0)
        #expect(rig.c.chatRounds == rounds && rig.c.chatRound == 2 && !rig.c.showsHandoff)
        #expect(rig.c.choices.map(\.text) == ["A language.", "Graydon Hoare."])
        await rig.followUp("when")
        let sent = try #require(rig.requests.last)
        #expect(sent.messages.map(\.text) == ["what is rust", "A language.", "who made it", "Graydon Hoare.", "when"])
        #expect(rig.c.chatRound == 3)
        let entries = rig.saved.entries
        try #require(entries.count == 1)
        #expect(entries[0].thread == rounds + [QuestionChat.Round(question: "when", answer: qcAnswer("when"))])
    }

    /// hist: a saved conversation at the round limit shows the hand-off row when picked.
    @Test func hist_aSavedThreadAtTheLimitShowsTheHandoffRow() async throws {
        let rounds = (1...5).map { QuestionChat.Round(question: "q\($0)", answer: "a\($0)") }
        let rig = QCRig(history: QuestionHistory(entries: [QuestionHistory.Entry(rounds: rounds, date: Date(timeIntervalSince1970: 1_790_000_000))]))
        await rig.pick("q")
        await rig.key(k("1"))
        #expect(rig.c.chatRounds == rounds && rig.c.showsHandoff && rig.c.chatAtLimit)
        await rig.type("more")
        await rig.key(qcShiftReturn)
        #expect(rig.requestCount == 0)
    }

    /// Coordinator: ⌘R (and ⌘⇧R) re-asks a saved answer, past the cache; the fresh answer replaces the saved one.
    @Test func hist_commandRReasksASavedAnswer() async throws {
        let rig = QCRig()
        await rig.ask("what is rust")
        await rig.key(enterKey)
        #expect(rig.requestCount == 1)
        for key in [k("r", mods: .command), k("R", mods: [.command, .shift])] {
            rig.newField()
            await rig.pick("q")
            await rig.key(k("1"))
            #expect(rig.c.showsSavedAnswer)
            let before = rig.requestCount
            QCStubProtocol.enqueue(rig.host, .answer("A fresh answer \(before)."))
            await rig.key(key)
            #expect(rig.requestCount == before + 1, "\(key): not asked again past the cache")
            #expect(rig.requests.last?.messages.map(\.text) == ["what is rust"])
            #expect(rig.c.chatRounds.last?.answer == "A fresh answer \(before).")
            #expect(rig.saved.entries.first?.answer == "A fresh answer \(before).")
            await rig.key(escKey)
            await rig.key(escKey)
            await rig.key(escKey)
        }
    }

    /// Coordinator: ⌘R on a saved conversation asks its latest question again with the rounds before it; the thread
    /// keeps its length, the latest answer replaced.
    @Test func hist_commandRReasksASavedThreadsLatestQuestion() async throws {
        let rounds = [QuestionChat.Round(question: "what is rust", answer: "A language."),
                      QuestionChat.Round(question: "who made it", answer: "Graydon Hoare.")]
        let rig = QCRig(history: QuestionHistory(entries: [QuestionHistory.Entry(rounds: rounds, date: Date(timeIntervalSince1970: 1_790_000_000))]))
        await rig.pick("q")
        await rig.key(k("1"))
        QCStubProtocol.enqueue(rig.host, .answer("Graydon Hoare, at Mozilla."))
        await rig.key(k("r", mods: .command))
        let sent = try #require(rig.requests.last)
        #expect(rig.requestCount == 1)
        #expect(sent.messages.map(\.text) == ["what is rust", "A language.", "who made it"])
        #expect(rig.c.chatRounds.map(\.answer) == ["A language.", "Graydon Hoare, at Mozilla."])
        let entries = rig.saved.entries
        #expect(entries.count == 1 && entries.first?.thread.map(\.answer) == ["A language.", "Graydon Hoare, at Mozilla."])
    }

    /// Coordinator: ⌘R on a saved conversation goes past the cache: the conversation asked here before (cached) is
    /// asked again.
    @Test func hist_commandRReasksASavedThreadPastTheCache() async throws {
        let rig = QCRig()
        await rig.converse(2)
        await rig.key(enterKey)
        #expect(rig.requestCount == 2)
        rig.newField()
        await rig.pick("q")
        await rig.key(k("1"))
        #expect(rig.c.showsSavedAnswer && rig.c.chatRound == 2)
        await rig.key(k("r", mods: .command))
        #expect(rig.requestCount == 3, "the cached answer was used")
        #expect(rig.requests.last?.messages.map(\.text) == ["q1", qcAnswer("q1"), "q2"])
    }

    /// Coordinator: R is an ordinary letter on a saved answer: it starts a follow-up; nothing is asked.
    @Test func hist_plainRStartsAFollowUp() async throws {
        let rig = QCRig(history: QuestionHistory(entries: [QuestionHistory.Entry(question: "what is rust", answer: "A language.",
                                                                                  date: Date(timeIntervalSince1970: 1_790_000_000))]))
        await rig.pick("q")
        await rig.key(k("1"))
        await rig.key(k("r"))
        #expect(rig.requestCount == 0 && rig.c.refineLine == "r")
        await rig.type("ust history")
        await rig.key(qcShiftReturn)
        #expect(rig.requests.last?.messages.map(\.text) == ["what is rust", "A language.", "rust history"])
    }

    // MARK: CHANGE 2: one rule for the result panel

    let improveLines = "EN: I have an apple.\nEN: I've got an apple.\nEN: I own an apple."

    func improveShown(_ rig: QCRig) async {
        QCStubProtocol.enqueue(rig.host, .answer(improveLines))
        await rig.pick("i")
        #expect(rig.c.draft == "@improve ")
        await rig.type("i has a apple")
        await rig.key(enterKey)
        #expect(rig.rows == ["I have an apple.", "I've got an apple.", "I own an apple."])
    }

    /// CHANGE 2 @improve: ⇧⏎ sends the refine (0.6.3's `<refine>` request), ⏎ inserts the selected version dropping a
    /// half-typed instruction, ⇧⏎ with nothing typed inserts as typed, Esc steps back.
    @Test func c2_improveRefinesWithShiftReturnAndReturnInserts() async throws {
        let configure: (inout Config) -> Void = { $0.outputLanguages = [.english]; $0.rewriteStyles = [] }
        // ⏎ with an instruction typed: the selected version goes in, nothing is sent.
        let insert = QCRig(configure: configure)
        await improveShown(insert)
        await insert.type("shorter")
        #expect(insert.c.refineLine == "shorter")
        let out = await insert.key(enterKey)
        #expect(!QCRig.asks(out) && insert.requestCount == 1 && insert.committed == ["I have an apple."])

        // ⇧⏎: the refine, as 0.6.3 sent it.
        let refine = QCRig(configure: configure)
        await improveShown(refine)
        await refine.type("shorter")
        QCStubProtocol.enqueue(refine.host, .answer("EN: An apple.\nEN: Got an apple.\nEN: Apple here."))
        let run = await refine.key(qcShiftReturn)
        #expect(run.contains { if case .startRefine = $0 { return true } else { return false } })
        let sent = try #require(refine.requests.last)
        #expect(refine.requestCount == 2 && sent.lastUser.contains("<refine>") && sent.lastUser.contains("shorter"), "\(sent.lastUser)")
        #expect(refine.rows == ["An apple.", "Got an apple.", "Apple here."])
        #expect(refine.c.refineHistory == ["shorter"])
        // Esc steps back to the versions before it.
        await refine.key(escKey)
        #expect(refine.rows == ["I have an apple.", "I've got an apple.", "I own an apple."])

        // ⇧⏎ with nothing typed: as typed.
        let typed = QCRig(configure: configure)
        await improveShown(typed)
        let draft = typed.c.draft
        let asTyped = await typed.key(qcShiftReturn)
        #expect(!QCRig.asks(asTyped) && typed.committed == [draft] && typed.requestCount == 1)
    }

    /// CHANGE 2 prompt commands: the same keys.
    @Test func c2_promptCommandsRefineWithShiftReturnAndReturnInserts() async throws {
        let catalog = Command.catalog([CustomCommand(name: "reply", type: .prompt, prompt: "Write a polite reply.")])
        for shift in [false, true] {
            let rig = QCRig(commands: catalog)
            QCStubProtocol.enqueue(rig.host, .answer("Thank you, I'd be glad to come."), .answer("Thanks, I'll come."))
            await rig.pick("repl")
            #expect(rig.c.draft == "@reply ")
            await rig.type("thanks for the invite")
            await rig.key(enterKey)
            #expect(rig.requestCount == 1 && rig.c.canRefine)
            await rig.type("shorter")
            await rig.key(shift ? qcShiftReturn : enterKey)
            if shift {
                #expect(rig.requestCount == 2 && rig.requests.last?.lastUser.contains("<refine>") == true)
                #expect(rig.rows.last == "Thanks, I'll come." && rig.committed.isEmpty)
                #expect(!rig.c.isQuestionChat)
            } else {
                #expect(rig.requestCount == 1 && rig.committed == ["Thank you, I'd be glad to come."])
            }
        }
    }

    /// CHANGE 2 selection commands: on a selection, ⏎ replaces it with the selected version (an instruction typed is
    /// dropped); ⇧⏎ refines.
    @Test func c2_selectionCommandsFollowTheSameKeys() async throws {
        let selection = Composer.Selection(text: "i has a apple", range: 4..<17)
        let configure: (inout Config) -> Void = { $0.outputLanguages = [.english]; $0.rewriteStyles = [] }
        for shift in [false, true] {
            let rig = QCRig(selection: selection, configure: configure)
            QCStubProtocol.enqueue(rig.host, .answer(improveLines), .answer("EN: An apple.\nEN: Got an apple.\nEN: Apple here."))
            await rig.pick("i")
            #expect(rig.c.selectionInUse == "i has a apple")
            await rig.key(enterKey)
            #expect(rig.rows == ["I have an apple.", "I've got an apple.", "I own an apple."])
            await rig.type("shorter")
            await rig.key(shift ? qcShiftReturn : enterKey)
            if shift {
                #expect(rig.requestCount == 2 && rig.requests.last?.lastUser.contains("<refine>") == true)
                #expect(rig.rows == ["An apple.", "Got an apple.", "Apple here."] && rig.replaced.isEmpty && rig.committed.isEmpty)
            } else {
                #expect(rig.requestCount == 1 && rig.replaced == ["I have an apple."] && rig.committed.isEmpty)
            }
        }
    }

    /// CHANGE 2 @translate: no refine. Typing after its results goes back to its text (the results dropped, the letters
    /// continuing it), and ⏎ translates the edited text again as a normal request.
    @Test func c2_translateHasNoRefineTypingGoesBackToItsText() async throws {
        let rig = QCRig { $0.outputLanguages = [.english] }
        QCStubProtocol.enqueue(rig.host, .answer("EN: Hello."), .answer("EN: Hello there."))
        await rig.pick("t")
        #expect(rig.c.draft == "@translate ")
        await rig.type("hello")
        await rig.key(enterKey)
        #expect(rig.requestCount == 1 && rig.c.isLevelTwo && !rig.c.canRefine)
        await rig.type("s")
        #expect(!rig.c.isLevelTwo && rig.c.refineLine == nil && rig.c.draft == "@translate hellos", "\(rig.c.draft)")
        let again = await rig.key(enterKey)
        #expect(again.contains(.startConversion(input: "hellos", id: 2)), "\(again)")
        #expect(rig.requestCount == 2 && rig.c.isLevelTwo && !rig.c.canRefine)
        let sent = try #require(rig.requests.last)
        #expect(!sent.lastUser.contains("<refine>") && sent.lastUser == "hellos")
        #expect(sent.messages.count == rig.requests[0].messages.count)
        // ⇧⏎ on its results with nothing typed: as typed.
        let draft = rig.c.draft
        await rig.key(qcShiftReturn)
        #expect(rig.committed == [draft] && rig.requestCount == 2)
    }

    // MARK: The live-data rule

    /// live: the rule is in @question's system prompt only (every round, and a question about a selection); @improve,
    /// @translate, a prompt command and a command on a selection don't have it.
    @Test func live_theRuleIsInQuestionOnly() async throws {
        let question = QCRig()
        await question.converse(2)
        let rule = try #require(qcLiveRule(in: question.requests[0].system))
        #expect(qcLooksLikeTheLiveRule(rule))
        #expect(question.requests.allSatisfy { $0.system == qcSystem063 + " " + rule })

        let about = QCRig(selection: Composer.Selection(text: "Error 404 at the users page", range: 0..<27))
        await about.pick("q")
        await about.type("what does this mean")
        await about.key(enterKey)
        #expect(about.requests.first.map { $0.system.hasSuffix(rule) } == true)

        var others: [(String, QCSent)] = []
        let configure: (inout Config) -> Void = { $0.outputLanguages = [.english] }
        let improve = QCRig(configure: configure)
        await improve.pick("i")
        await improve.type("i has a apple")
        await improve.key(enterKey)
        others += improve.requests.map { ("@improve", $0) }
        let translate = QCRig(configure: configure)
        await translate.pick("t")
        await translate.type("hello")
        await translate.key(enterKey)
        others += translate.requests.map { ("@translate", $0) }
        let reply = QCRig(commands: Command.catalog([CustomCommand(name: "reply", type: .prompt, prompt: "Write a polite reply.")]))
        await reply.pick("repl")
        await reply.type("thanks")
        await reply.key(enterKey)
        others += reply.requests.map { ("prompt command", $0) }
        let edit = QCRig(selection: Composer.Selection(text: "this sentance have a error", range: 0..<26), configure: configure)
        await edit.pick("i")
        await edit.type("more formal")
        await edit.key(enterKey)
        others += edit.requests.map { ("edit on a selection", $0) }
        #expect(others.count == 4)
        for (name, sent) in others {
            #expect(!sent.body.contains(rule) && !sent.system.lowercased().contains("live information"), "\(name): \(sent.system)")
        }
    }
}

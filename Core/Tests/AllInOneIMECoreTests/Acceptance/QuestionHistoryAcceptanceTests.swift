import Foundation
import os
import Testing
@testable import AllInOneIMECore

// Acceptance tests for "@question lists the recent questions", written from the spec (not from the implementer's tests).
//
// What is driven: the real `Composer` (keys, clicks, the effects it asks for), the real `Converter` talking to a stubbed
// OpenAI-compatible API through `URLProtocol` (every request recorded), and the real `QuestionHistory` file in a temporary
// folder. The input controller (an executable target the tests can't import) is stood in for by `QHHarness`, which does
// what InputController does with the effects: reloads the history and the setting before a key when nothing is being
// composed, runs `.startCommand` / `.reask` (fresh) on the converter and feeds the updates back, keeps
// `.rememberQuestion` in the file unless the setting is off or secure input is on.
//
// Never the user's ~/Library/Application Support/AllInOneIME/recent-questions.json: each harness has its own temp file.

// MARK: - A stubbed provider that records every request

/// Answers like an OpenAI-compatible chat API (SSE), per host, recording every request. Each test has its own host, so
/// the tests can run in parallel.
final class QHAcceptanceURLProtocol: URLProtocol, @unchecked Sendable {
    enum Mode: Sendable {
        /// "A<n>: <the question>" for the n-th request to the host.
        case answer
        /// The network is down.
        case networkError
    }

    private struct State {
        var requests: [String: [URLRequest]] = [:]
        var modes: [String: Mode] = [:]
        /// Answers to give instead of the made-up one, in order.
        var scripted: [String: [String]] = [:]
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func requests(_ host: String) -> [URLRequest] { state.withLock { $0.requests[host] ?? [] } }
    static func setMode(_ mode: Mode, for host: String) { state.withLock { $0.modes[host] = mode } }
    static func script(_ answers: [String], for host: String) { state.withLock { $0.scripted[host, default: []] += answers } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QHAcceptanceURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// The request with its body as `httpBody` (URLSession hands it to a protocol as a stream).
    static func withBody(_ request: URLRequest) -> URLRequest {
        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            request.httpBody = data
        }
        return request
    }

    /// The last user message of an OpenAI-style body.
    static func question(in request: URLRequest) -> String {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]],
              let last = messages.last(where: { $0["role"] as? String == "user" }) else { return "" }
        return last["content"] as? String ?? ""
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = Self.withBody(self.request)
        let host = request.url?.host ?? ""
        let (mode, number, scripted) = Self.state.withLock { state -> (Mode, Int, String?) in
            state.requests[host, default: []].append(request)
            let scripted = state.scripted[host]?.isEmpty == false ? state.scripted[host]!.removeFirst() : nil
            return (state.modes[host] ?? .answer, state.requests[host]!.count, scripted)
        }
        guard case .answer = mode, let url = request.url,
              let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                         headerFields: ["Content-Type": "text/event-stream"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let answer = scripted ?? "A\(number): \(Self.question(in: request))"
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        // The Claude API's events or the OpenAI-compatible ones, in pieces, as a stream comes.
        let claude = url.path.hasSuffix("/v1/messages")
        var rest = Substring(answer)
        while !rest.isEmpty {
            let piece = String(rest.prefix(700))
            rest = rest.dropFirst(piece.count)
            client?.urlProtocol(self, didLoad: Self.event(claude
                ? ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": piece]]
                : ["choices": [["index": 0, "delta": ["content": piece], "finish_reason": NSNull()]]]))
        }
        client?.urlProtocol(self, didLoad: Self.event(claude
            ? ["type": "message_delta", "delta": ["stop_reason": "end_turn"]]
            : ["choices": [["index": 0, "delta": [String: String](), "finish_reason": "stop"]]]))
        if !claude { client?.urlProtocol(self, didLoad: Data("data: [DONE]\n\n".utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func event(_ object: [String: Any]) -> Data {
        let json = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return Data("data: ".utf8) + json + Data("\n\n".utf8)
    }

    override func stopLoading() {}
}

// MARK: - The harness: a text field, the input controller's part, the provider, the file

final class QHClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// A Composer in a text field with the controller's part around it (see the top of the file).
final class QHHarness {
    let host: String
    let directory: URL
    /// Where the recent questions are kept (a temp folder, never the user's).
    let fileURL: URL
    let converter: Converter
    let clock = QHClock(Date(timeIntervalSince1970: 1_791_000_000))  // 2026-10-03
    private(set) var composer: Composer
    /// `Config.rememberQuestions`.
    var setting = true
    /// Secure input on (the controller refuses to ask; the composer is told too).
    var secure = false {
        didSet { let on = secure; composer.secureInputActive = { on } }
    }
    var selection: Composer.Selection?
    /// Every effect the composer asked for, nested ones too.
    private(set) var log: [Composer.Effect] = []
    private(set) var committed: [String] = []
    private(set) var copied: [String] = []
    /// What was run on the converter: the input, and whether past the cache.
    private(set) var runs: [(input: String, fresh: Bool)] = []
    /// The last final update's `fromCache`.
    private(set) var lastFromCache: Bool?

    static let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    static let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    static let commandC = KeyEvent(keyCode: 0x08, characters: "c", charactersIgnoringModifiers: "c", modifiers: .command)

    init(provider: Provider = .openai, history: QuestionHistory? = nil, engine: FakeEngine = FakeEngine()) throws {
        host = "qh-\(UUID().uuidString.lowercased()).test"
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qh-acceptance-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Application Support/AllInOneIME", isDirectory: true)
        fileURL = directory.appendingPathComponent("recent-questions.json")
        precondition(fileURL.path != QuestionHistory.defaultURL.path)
        var config = Config.default
        config.provider = provider
        config.openai = ProviderSettings(model: "test-model", baseURL: "https://\(host)/v1")
        config.anthropic = ProviderSettings(baseURL: "https://\(host)")
        let fixed = config
        converter = Converter(
            client: BedrockClient(session: QHAcceptanceURLProtocol.session()), loadConfig: { fixed },
            loadCredentials: { _ in
                AWSSharedConfig.Resolved(credentials: AWSCredentials(accessKeyId: "AKIDTEST", secretAccessKey: "secret"), region: nil)
            },
            loadKey: { _, _ in "sk-test" })
        composer = Composer(engine: engine, actionKey: .enter)
        if let history { try history.write(to: fileURL) }
        setUpComposer()
    }

    deinit { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent().deletingLastPathComponent()) }

    private func setUpComposer() {
        composer.setInputMode(.english)
        let clock = self.clock
        composer.now = { clock.now }
        let on = secure
        composer.secureInputActive = { on }
        composer.readSelection = { [unowned self] in self.selection }
    }

    /// Another text field (the history is shared through the file).
    func newField(engine: FakeEngine = FakeEngine()) {
        composer = Composer(engine: engine, actionKey: .enter)
        setUpComposer()
    }

    var requests: [URLRequest] { QHAcceptanceURLProtocol.requests(host) }
    /// What the file holds now.
    var saved: QuestionHistory { QuestionHistory.load(from: fileURL) }
    var savedQuestions: [String] { saved.entries.map(\.question) }

    /// As the controller does before each key: the setting and the history, when nothing is being composed.
    private func reload() {
        guard !composer.isComposing else { return }
        composer.remembersQuestions = setting
        composer.questionHistory = QuestionHistory.load(from: fileURL)
    }

    @discardableResult
    func press(_ event: KeyEvent) async -> [Composer.Effect] {
        reload()
        let effects = composer.handleKeyDown(event).effects
        await perform(effects)
        return effects
    }

    /// A row of the panel clicked.
    @discardableResult
    func click(_ index: Int) async -> [Composer.Effect] {
        reload()
        let effects = composer.choose(index: index)
        await perform(effects)
        return effects
    }

    func type(_ text: String) async {
        for ch in text { await press(ch == " " ? spaceKey : k(String(ch))) }
    }

    /// "@", "q", Tab: "@question ".
    func startQuestion() async {
        await press(Self.at)
        await press(k("q"))
        await press(Self.tab)
    }

    /// "@question <text>" ⏎, then (`insert`) ⏎ again inserts the answer. A minute passes after.
    func ask(_ text: String, insert: Bool = true) async {
        await startQuestion()
        await type(text)
        await press(enterKey)
        if insert, composer.phase == .choosing { await press(enterKey) }
        clock.now += 60
    }

    private func perform(_ effects: [Composer.Effect]) async {
        for effect in effects {
            log.append(effect)
            switch effect {
            case let .startCommand(command, input, id):
                if secure { continue }  // refused, as the controller does
                await run(command, input: input, id: id, fresh: false)
            case let .reask(command, input, id):
                if secure { continue }
                await run(command, input: input, id: id, fresh: true)
            case let .rememberQuestion(entry):
                // QuestionHistoryStore.record, in the temp file.
                guard setting, !secure else { continue }
                var history = QuestionHistory.load(from: fileURL)
                history.record(entry)
                try? history.write(to: fileURL)
            case let .commit(text):
                committed.append(text)
            case let .copy(text):
                copied.append(text)
            default:
                break
            }
        }
    }

    private func run(_ command: Command, input: String, id: Int, fresh: Bool) async {
        runs.append((input, fresh))
        do {
            for try await update in converter.generate(command, input: input, fresh: fresh) {
                if update.isFinal { lastFromCache = update.fromCache }
                await perform(composer.receive(update.result, isFinal: update.isFinal, id: id))
            }
        } catch {
            await perform(composer.fail(String(describing: error), id: id))
        }
    }

    /// Whether the composer asked for anything to be sent since `index` of the log.
    func askedSomething(since index: Int) -> Bool {
        log[index...].contains {
            switch $0 {
            case .startCommand, .reask, .startConversion, .startPlan, .startRun: return true
            default: return false
            }
        }
    }

    /// The answer shown in level two.
    var answerShown: String? { composer.choices.first { $0.kind == .answer }?.text }

    /// History entries, newest first, made-up but in the file's format.
    static func history(_ questions: [String], from date: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> QuestionHistory {
        // `questions` newest first: the first gets the latest date.
        var history = QuestionHistory()
        for (i, q) in questions.enumerated().reversed() {
            history.record(.init(question: q, answer: "saved answer to \(q)", date: date.addingTimeInterval(Double(questions.count - i) * 3600)))
        }
        return history
    }
}

// MARK: - The tests

@Suite("QuestionHistoryAcceptance")
struct QuestionHistoryAcceptanceTests {

    // MARK: 1. The list

    /// Spec 1: "@question" and nothing after it lists the last 5 questions asked, newest first; nothing is sent.
    @Test func emptyQueryListsTheLastFiveNewestFirst() async throws {
        let h = try QHHarness()
        for q in ["alpha one", "bravo two", "charlie three", "delta four", "echo five", "foxtrot six"] { await h.ask(q) }
        #expect(h.requests.count == 6)
        await h.startQuestion()
        #expect(h.composer.draft == "@question ")
        #expect(h.composer.questionMatches.map(\.question) == ["foxtrot six", "echo five", "delta four", "charlie three", "bravo two"])
        #expect(h.composer.questionDigitsPick)
        #expect(h.requests.count == 6)  // listing sends nothing
        // The answers listed are the ones given.
        #expect(h.composer.questionMatches.first?.answer == "A6: foxtrot six")
    }

    /// Spec 1: nothing asked yet, no list; ⏎ with text asks as before.
    @Test func noHistoryNoList() async throws {
        let h = try QHHarness()
        await h.startQuestion()
        #expect(h.composer.questionMatches.isEmpty && !h.composer.questionDigitsPick)
        await h.type("hello there")
        await h.press(enterKey)
        #expect(h.requests.count == 1 && h.answerShown == "A1: hello there")
    }

    // MARK: 2. Filtering

    /// Spec 2: matching anywhere in the question, in any case; newest first.
    @Test func filterMatchesAnywhereCaseInsensitive() async throws {
        let h = try QHHarness(history: QHHarness.history(["Rust vs Go performance", "How do I bake bread", "What is Rust?"]))
        await h.startQuestion()
        await h.type("RUST")
        #expect(h.composer.questionMatches.map(\.question) == ["Rust vs Go performance", "What is Rust?"])
        // Mid-word, end of the question.
        for _ in 0..<4 { await h.press(backspaceKey) }
        await h.type("read")
        #expect(h.composer.questionMatches.map(\.question) == ["How do I bake bread"])
        for _ in 0..<4 { await h.press(backspaceKey) }
        await h.type("ance")
        #expect(h.composer.questionMatches.map(\.question) == ["Rust vs Go performance"])
        #expect(h.requests.isEmpty)
    }

    /// Spec 2: CJK-aware: "芯片" finds "AI 芯片的未来"; so do a single character, the end, "ai芯片" without the space.
    @Test func cjkFiltering() async throws {
        let h = try QHHarness(history: QHHarness.history(["量子计算是什么", "AI 芯片的未来", "What is Rust?"]))
        for (query, expected) in [("芯片", ["AI 芯片的未来"]), ("未来", ["AI 芯片的未来"]), ("芯", ["AI 芯片的未来"]),
                                  ("ai芯片", ["AI 芯片的未来"]), ("计算", ["量子计算是什么"]), ("的", ["AI 芯片的未来"])] {
            await h.press(escKey)
            await h.startQuestion()
            await h.type(query)
            #expect(h.composer.questionMatches.map(\.question) == expected, "\(query)")
        }
        #expect(h.requests.isEmpty)
    }

    /// Spec 2: CJK typed with pinyin (the way it is typed for real): the list filters once the words are in.
    @Test func cjkFilteringTypedInPinyin() async throws {
        let engine = FakeEngine()
        engine.dictionary["xinpian"] = ["芯片", "新片"]
        let h = try QHHarness(history: QHHarness.history(["量子计算是什么", "AI 芯片的未来", "What is Rust?"]), engine: engine)
        h.composer.setInputMode(.chinese)
        await h.startQuestion()
        await h.type("xinpian")
        await h.press(spaceKey)  // picks 芯片
        #expect(h.composer.draft == "@question 芯片")
        #expect(h.composer.questionMatches.map(\.question) == ["AI 芯片的未来"])
    }

    /// Spec 2: a filter that matches nothing, then ⏎: the typed text is asked as a new question.
    @Test func filterMatchingNothingThenEnterAsksTheTypedText() async throws {
        let h = try QHHarness(history: QHHarness.history(["What is Rust?", "AI 芯片的未来"]))
        await h.startQuestion()
        await h.type("quantum gravity")
        #expect(h.composer.questionMatches.isEmpty)
        await h.press(enterKey)
        #expect(h.requests.count == 1)
        #expect(QHAcceptanceURLProtocol.question(in: h.requests[0]) == "quantum gravity")
        #expect(h.runs.map(\.input) == ["quantum gravity"] && h.runs.map(\.fresh) == [false])
        #expect(h.answerShown == "A1: quantum gravity" && !h.composer.showsSavedAnswer)
    }

    /// Spec 2: a filter that matches, nothing picked, ⏎: the typed text is asked (not the saved question).
    @Test func filterMatchingButNothingPickedEnterAsksTheTypedText() async throws {
        let h = try QHHarness(history: QHHarness.history(["What is Rust?"]))
        await h.startQuestion()
        await h.type("rust")
        #expect(h.composer.questionMatches.map(\.question) == ["What is Rust?"])
        await h.press(enterKey)
        #expect(h.requests.count == 1 && QHAcceptanceURLProtocol.question(in: h.requests[0]) == "rust")
        #expect(h.answerShown == "A1: rust" && !h.composer.showsSavedAnswer)
    }

    /// Spec 2/3: digits typed when text is present are part of the question, not a pick.
    @Test func digitsAfterTextArePartOfTheQuestion() async throws {
        let h = try QHHarness(history: QHHarness.history(["What is Rust?", "rust 2024 edition", "AI 芯片的未来"]))
        await h.startQuestion()
        await h.type("what is 2")
        #expect(!h.composer.isLevelTwo && h.composer.draft == "@question what is 2" && !h.composer.questionDigitsPick)
        await h.type("+2")
        #expect(h.composer.draft == "@question what is 2+2")
        // Text that matches saved questions: the digit is still text.
        await h.press(escKey)
        await h.startQuestion()
        await h.type("rust ")
        #expect(h.composer.questionMatches.count == 2)
        await h.press(k("1"))
        #expect(!h.composer.isLevelTwo && h.composer.draft == "@question rust 1" && !h.composer.showsSavedAnswer)
        #expect(h.requests.isEmpty)
        await h.press(enterKey)
        #expect(h.requests.count == 1 && QHAcceptanceURLProtocol.question(in: h.requests[0]) == "rust 1")
    }

    /// Spec 2: "nothing picked, ⏎ asks the typed text": a row picked in an earlier draft isn't still picked in a new
    /// one that happens to have the same text (after the saved answer was inserted, or the draft was dropped with Esc).
    @Test func aRowPickedInAnEarlierDraftIsNotPickedInANewOne() async throws {
        let h = try QHHarness(history: QHHarness.history(["What is Rust?", "rust 2024 edition"]))
        await h.startQuestion()
        await h.type("rust")
        await h.press(downKey)
        await h.press(enterKey)
        #expect(h.answerShown == "saved answer to What is Rust?")
        await h.press(enterKey)  // inserted: the draft is done
        #expect(h.committed == ["saved answer to What is Rust?"] && !h.composer.isComposing)
        // Later, the same words as a new question: nothing is picked, ⏎ asks them.
        await h.startQuestion()
        await h.type("rust")
        #expect(h.composer.questionHighlight == nil)
        await h.press(enterKey)
        #expect(!h.composer.showsSavedAnswer)
        #expect(h.requests.count == 1 && h.runs.map(\.input) == ["rust"])
        // The same after Esc, Esc.
        let e = try QHHarness(history: QHHarness.history(["What is Rust?", "rust 2024 edition"]))
        await e.startQuestion()
        await e.press(downKey)
        await e.press(downKey)
        await e.press(enterKey)
        await e.press(escKey)
        await e.press(escKey)
        #expect(!e.composer.isComposing)
        await e.startQuestion()
        #expect(e.composer.questionHighlight == nil)
    }

    // MARK: 3. Picking a saved question

    /// Spec 3: a digit with nothing typed shows the saved answer at once; no request; ⏎ inserts it.
    @Test func digitPickShowsTheSavedAnswerWithoutARequest() async throws {
        let h = try QHHarness()
        for q in ["first question", "second question", "third question"] { await h.ask(q) }
        #expect(h.requests.count == 3)
        await h.startQuestion()
        let mark = h.log.count
        await h.press(k("2"))
        #expect(h.composer.showsSavedAnswer && h.composer.phase == .choosing)
        #expect(h.answerShown == "A2: second question")
        #expect(h.composer.savedAnswerDate != nil)
        #expect(h.requests.count == 3 && !h.askedSomething(since: mark))
        await h.press(enterKey)
        #expect(h.committed.last == "A2: second question" && !h.composer.isComposing)
        #expect(h.requests.count == 3 && !h.askedSomething(since: mark))
    }

    /// Spec 3: each digit 1–5 picks its row when nothing is typed; a digit past the list picks nothing.
    @Test func everyDigitPicksItsRow() async throws {
        let h = try QHHarness(history: QHHarness.history(["q one", "q two", "q three", "q four", "q five"]))
        for (digit, question) in zip(["1", "2", "3", "4", "5"], ["q one", "q two", "q three", "q four", "q five"]) {
            await h.startQuestion()
            await h.press(k(digit))
            #expect(h.answerShown == "saved answer to \(question)", "\(digit)")
            await h.press(escKey)
            await h.press(escKey)
            #expect(!h.composer.isComposing)
        }
        let few = try QHHarness(history: QHHarness.history(["q one", "q two"]))
        await few.startQuestion()
        await few.press(k("4"))
        #expect(!few.composer.showsSavedAnswer && !few.composer.isLevelTwo)
        #expect(h.requests.isEmpty && few.requests.isEmpty)
    }

    /// Spec 3: ↑/↓ then ⏎ shows the saved answer; no request.
    @Test func arrowsThenEnterShowTheSavedAnswer() async throws {
        let h = try QHHarness(history: QHHarness.history(["newest q", "middle q", "oldest q"]))
        await h.startQuestion()
        await h.press(downKey)
        await h.press(downKey)
        #expect(h.composer.questionHighlight == 1)
        await h.press(enterKey)
        #expect(h.composer.showsSavedAnswer && h.answerShown == "saved answer to middle q")
        // ↑ from nothing highlighted: the last row.
        await h.press(escKey)
        await h.press(escKey)
        await h.startQuestion()
        await h.press(upKey)
        await h.press(enterKey)
        #expect(h.answerShown == "saved answer to oldest q")
        // In a filtered list.
        await h.press(escKey)
        await h.press(escKey)
        await h.startQuestion()
        await h.type("mid")
        await h.press(downKey)
        await h.press(enterKey)
        #expect(h.answerShown == "saved answer to middle q")
        #expect(h.requests.isEmpty && !h.askedSomething(since: 0))
    }

    /// Spec 3: a click on a row shows its saved answer; no request. Also in a filtered list.
    @Test func clickShowsTheSavedAnswer() async throws {
        let h = try QHHarness(history: QHHarness.history(["What is Rust?", "AI 芯片的未来", "How do I bake bread"]))
        await h.startQuestion()
        await h.click(2)
        #expect(h.composer.showsSavedAnswer && h.answerShown == "saved answer to How do I bake bread")
        await h.press(escKey)
        await h.press(escKey)
        await h.startQuestion()
        await h.type("芯片")
        await h.click(0)
        #expect(h.answerShown == "saved answer to AI 芯片的未来")
        #expect(h.requests.isEmpty && !h.askedSomething(since: 0))
    }

    /// Spec 3: insert and copy work as on any answer: ⌘C copies it (and it stays), the digit of its row inserts it.
    @Test func insertAndCopyOnTheSavedAnswer() async throws {
        let h = try QHHarness(history: QHHarness.history(["What is Rust?"]))
        await h.startQuestion()
        await h.press(k("1"))
        await h.press(QHHarness.commandC)
        #expect(h.copied == ["saved answer to What is Rust?"] && h.composer.showsSavedAnswer)
        let answerRow = try #require(h.composer.choices.first { $0.kind == .answer })
        await h.press(k(answerRow.label))
        #expect(h.committed == ["saved answer to What is Rust?"] && !h.composer.isComposing)
        // Space inserts as on any answer too.
        await h.startQuestion()
        await h.press(k("1"))
        await h.press(spaceKey)
        #expect(h.committed.count == 2 && h.committed.last == "saved answer to What is Rust?")
        #expect(h.requests.isEmpty)
        // A fresh answer is copied and inserted the same way.
        await h.ask("compare", insert: false)
        await h.press(QHHarness.commandC)
        #expect(h.copied.last == "A1: compare")
    }

    /// Esc sequence: saved answer → Esc → the list (as it was typed, the row picked highlighted) → Esc → the draft goes.
    @Test func escFromTheSavedAnswerBackToTheListThenTheDraft() async throws {
        let h = try QHHarness(history: QHHarness.history(["What is Rust?", "AI 芯片的未来", "AI 芯片的历史"]))
        await h.startQuestion()
        await h.type("芯片")
        await h.press(downKey)
        await h.press(downKey)
        await h.press(enterKey)
        #expect(h.answerShown == "saved answer to AI 芯片的历史")
        await h.press(escKey)
        #expect(!h.composer.isLevelTwo && h.composer.draft == "@question 芯片")
        #expect(h.composer.questionMatches.map(\.question) == ["AI 芯片的未来", "AI 芯片的历史"])
        #expect(h.composer.questionHighlight == 1)
        // ⏎ there shows it again, still without asking.
        await h.press(enterKey)
        #expect(h.answerShown == "saved answer to AI 芯片的历史")
        await h.press(escKey)
        await h.press(escKey)
        #expect(h.composer.draft.isEmpty && !h.composer.isComposing && h.committed.isEmpty)
        #expect(h.requests.isEmpty && !h.askedSomething(since: 0))
    }

    // MARK: 4. Re-asking

    /// Spec 4: R on a saved answer sends exactly one request, past the cache, and the fresh answer replaces the entry.
    @Test func reaskSendsOneFreshRequestAndReplacesTheEntry() async throws {
        let h = try QHHarness()
        await h.ask("What is Rust?")
        await h.ask("AI 芯片的未来")
        #expect(h.requests.count == 2)
        // The same question typed again is answered from the cache: no request (so a re-ask must get past it).
        await h.ask("What is Rust?")
        #expect(h.requests.count == 2 && h.lastFromCache == true)
        #expect(h.savedQuestions == ["What is Rust?", "AI 芯片的未来"])
        let before = try #require(h.saved.entries.first { $0.question == "AI 芯片的未来" })
        #expect(before.answer == "A2: AI 芯片的未来")

        await h.startQuestion()
        await h.press(k("2"))
        #expect(h.answerShown == "A2: AI 芯片的未来" && h.requests.count == 2)
        h.clock.now += 3600
        let mark = h.log.count
        await h.press(k("r", mods: .command))
        #expect(h.requests.count == 3)
        #expect(QHAcceptanceURLProtocol.question(in: h.requests[2]) == "AI 芯片的未来")
        #expect(h.requests[2].httpBody == h.requests[1].httpBody)  // the same request as when it was first asked
        #expect(h.runs.last?.fresh == true && h.lastFromCache == false)
        let reasks = h.log[mark...].filter { if case .reask = $0 { return true } else { return false } }
        #expect(reasks.count == 1)
        #expect(h.answerShown == "A3: AI 芯片的未来" && !h.composer.showsSavedAnswer)
        // The fresh answer in place of the saved one: no duplicate, nothing else lost.
        #expect(h.saved.entries.count == 2)
        let after = try #require(h.saved.entries.first { $0.question == "AI 芯片的未来" })
        #expect(after.answer == "A3: AI 芯片的未来" && after.date == h.clock.now)
        #expect(h.saved.entries.filter { $0.question == "AI 芯片的未来" }.count == 1)
        #expect(h.saved.entries.contains { $0.question == "What is Rust?" && $0.answer == "A1: What is Rust?" })
        // Picked again: the fresh answer, no request.
        await h.press(escKey)
        await h.press(escKey)
        await h.startQuestion()
        await h.type("芯片")
        await h.press(downKey)
        await h.press(enterKey)
        #expect(h.answerShown == "A3: AI 芯片的未来" && h.requests.count == 3)
    }

    /// Spec 4: ⌘⇧R (Shift held, or caps) re-asks too. (0.6.4: ⌘R and ⌘⇧R re-ask; R alone starts a follow-up.)
    @Test func capitalRReasks() async throws {
        let h = try QHHarness(history: QHHarness.history(["What is Rust?"]))
        await h.startQuestion()
        await h.press(k("1"))
        await h.press(k("R", mods: [.command, .shift]))
        #expect(h.requests.count == 1 && h.answerShown == "A1: What is Rust?")
        #expect(h.saved.entries.first?.answer == "A1: What is Rust?")
    }

    /// Spec 4: a re-ask that fails (network down) leaves the saved entry as it was, in the list and in the file.
    @Test func reaskFailingWithANetworkErrorKeepsTheSavedEntry() async throws {
        let h = try QHHarness()
        await h.ask("What is Rust?")
        let before = h.saved
        let bytes = try Data(contentsOf: h.fileURL)
        QHAcceptanceURLProtocol.setMode(.networkError, for: h.host)
        await h.startQuestion()
        await h.press(k("1"))
        h.clock.now += 3600
        await h.press(k("r", mods: .command))
        #expect(h.requests.count == 2)  // it was tried
        if case .failed = h.composer.phase {} else { Issue.record("expected a failure, got \(h.composer.phase)") }
        #expect(h.saved == before)
        #expect(try Data(contentsOf: h.fileURL) == bytes)
        #expect(!h.log.contains { if case let .rememberQuestion(e) = $0 { return e.date == h.clock.now } else { return false } })
        // Back to the list: the saved answer is still there to pick.
        await h.press(escKey)
        await h.press(escKey)
        #expect(!h.composer.isComposing)
        await h.startQuestion()
        #expect(h.composer.questionMatches.map(\.answer) == ["A1: What is Rust?"])
        await h.press(k("1"))
        #expect(h.answerShown == "A1: What is Rust?" && h.requests.count == 2)
    }

    // MARK: 5. Storage

    /// Spec 5: the file is under ~/Library/Application Support/AllInOneIME/ (the default; tests use a temp one).
    @Test func theFileIsUnderApplicationSupport() {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let url = QuestionHistory.defaultURL.standardizedFileURL
        #expect(url.deletingLastPathComponent().path == home + "/Library/Application Support/AllInOneIME")
        #expect(url.isFileURL)
    }

    /// Spec 5: question, answer and time are what is kept; nothing is sent to keep them.
    @Test func theFileKeepsQuestionAnswerAndTime() async throws {
        let h = try QHHarness()
        h.clock.now = Date(timeIntervalSince1970: 1_791_000_123)
        await h.ask("What is Rust?")
        #expect(h.requests.count == 1)  // the question; keeping it sends nothing more
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: h.fileURL)) as? [String: Any])
        let entries = try #require(json["entries"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries.first?["question"] as? String == "What is Rust?")
        #expect(entries.first?["answer"] as? String == "A1: What is Rust?")
        #expect(h.saved.entries.first?.date == Date(timeIntervalSince1970: 1_791_000_123))
    }

    /// Spec 5: exactly 5 are kept; a 6th drops the oldest (the file and the list).
    @Test func exactlyFiveThenASixth() async throws {
        let h = try QHHarness()
        for q in ["one", "two", "three", "four", "five"] { await h.ask("question \(q)") }
        #expect(h.savedQuestions == ["question five", "question four", "question three", "question two", "question one"])
        await h.ask("question six")
        #expect(h.savedQuestions == ["question six", "question five", "question four", "question three", "question two"])
        await h.startQuestion()
        #expect(h.composer.questionMatches.map(\.question) == h.savedQuestions)
        await h.type("one")
        #expect(h.composer.questionMatches.isEmpty)
        // A file edited by hand to hold 8: only 5 listed.
        let text = """
            {"entries":[\((1...8).map { #"{"question":"hand \#($0)","answer":"x","date":"2026-10-0\#(min($0, 9))T10:00:00Z"}"# }.joined(separator: ","))]}
            """
        try Data(text.utf8).write(to: h.fileURL)
        await h.press(escKey)
        await h.press(escKey)
        await h.startQuestion()
        #expect(h.composer.questionMatches.count == 5)
    }

    /// Spec 5: the same question again replaces its entry (newest first), no duplicate.
    @Test func theSameQuestionAgainReplacesItsEntry() async throws {
        let h = try QHHarness()
        await h.ask("What is Rust?")
        await h.ask("AI 芯片的未来")
        await h.ask("What is Rust?")  // from the cache: answered all the same
        #expect(h.savedQuestions == ["What is Rust?", "AI 芯片的未来"])
        // Spaces around it are not part of it.
        await h.ask("  AI 芯片的未来  ")
        #expect(h.savedQuestions == ["AI 芯片的未来", "What is Rust?"])
    }

    /// Spec 5 (edge): the same question differing only in case is the same question: one entry.
    @Test func duplicatesDifferingOnlyInCase() async throws {
        let h = try QHHarness()
        await h.ask("What is Rust?")
        await h.ask("what is rust?")
        #expect(h.savedQuestions == ["what is rust?"], "a question differing only in case was kept twice")
    }

    /// Spec 5 (edge): the same question differing only in whitespace inside it is the same question: one entry.
    @Test func duplicatesDifferingOnlyInInnerWhitespace() async throws {
        let h = try QHHarness()
        await h.ask("What is Rust?")
        await h.ask("What  is   Rust?")
        #expect(h.savedQuestions.count == 1, "kept: \(h.savedQuestions)")
    }

    /// Spec 5: readable only by the user (0600), also after rewriting a file that was readable by others.
    @Test func theFileIsReadableOnlyByTheUser() async throws {
        let h = try QHHarness()
        await h.ask("What is Rust?")
        func mode() throws -> Int {
            (try FileManager.default.attributesOfItem(atPath: h.fileURL.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
        }
        #expect(try mode() == 0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: h.fileURL.path)
        await h.ask("AI 芯片的未来")
        #expect(try mode() == 0o600)
        #expect(h.savedQuestions == ["AI 芯片的未来", "What is Rust?"])
    }

    /// Spec 5: a corrupt file never breaks @question: no list, ⏎ asks, and the answer is kept in a good file.
    @Test(arguments: ["not json at all", "{\"entries\": 5}", "{\"entries\":[{\"question\":1}]}", "", "{\"entries\":[{\"question\":\"q\",\"answer\":\"a\",\"date\":\"yesterday\"}]}", "\u{0}\u{1}\u{2}garbage"])
    func aCorruptFileNeverBreaksQuestion(_ content: String) async throws {
        let h = try QHHarness()
        try FileManager.default.createDirectory(at: h.directory, withIntermediateDirectories: true)
        try Data(content.utf8).write(to: h.fileURL)
        await h.startQuestion()
        #expect(h.composer.questionMatches.isEmpty)
        await h.type("What is Rust?")
        await h.press(enterKey)
        #expect(h.requests.count == 1 && h.answerShown == "A1: What is Rust?")
        await h.press(enterKey)
        #expect(h.committed == ["A1: What is Rust?"])
        #expect(h.savedQuestions == ["What is Rust?"])
    }

    /// Spec 5: a missing file (and folder) never breaks @question either; the folder is made when one is kept.
    @Test func aMissingFileNeverBreaksQuestion() async throws {
        let h = try QHHarness()
        #expect(!FileManager.default.fileExists(atPath: h.directory.path))
        await h.startQuestion()
        #expect(h.composer.questionMatches.isEmpty)
        await h.type("What is Rust?")
        await h.press(enterKey)
        #expect(h.answerShown == "A1: What is Rust?")
        #expect(h.savedQuestions == ["What is Rust?"])
        // A folder where the file should be: nothing listed, asking still works.
        let d = try QHHarness()
        try FileManager.default.createDirectory(at: d.fileURL, withIntermediateDirectories: true)
        await d.startQuestion()
        #expect(d.composer.questionMatches.isEmpty)
        await d.type("still works")
        await d.press(enterKey)
        #expect(d.answerShown == "A1: still works")
    }

    /// Spec 5 (edge): two questions in the same second: the one asked last is first, in the list and after a reload.
    @Test func twoQuestionsInTheSameSecond() async throws {
        let h = try QHHarness()
        let second = Date(timeIntervalSince1970: 1_791_000_000)
        h.clock.now = second.addingTimeInterval(0.9)
        await h.startQuestion(); await h.type("earlier one"); await h.press(enterKey); await h.press(enterKey)
        h.clock.now = second.addingTimeInterval(0.1)  // same second (a clock that stepped back a little, even)
        await h.startQuestion(); await h.type("later one"); await h.press(enterKey); await h.press(enterKey)
        h.clock.now = second.addingTimeInterval(0.5)
        await h.startQuestion(); await h.type("latest one"); await h.press(enterKey); await h.press(enterKey)
        #expect(h.savedQuestions == ["latest one", "later one", "earlier one"])
        h.newField()
        await h.startQuestion()
        #expect(h.composer.questionMatches.map(\.question) == ["latest one", "later one", "earlier one"])
        await h.press(k("2"))
        #expect(h.answerShown == "A2: later one")
        // The time is kept (to the second at least).
        #expect(h.saved.entries.allSatisfy { abs($0.date.timeIntervalSince(second)) < 1 })
    }

    /// Spec 3/5 (edge): a very long answer is kept whole, shown whole and inserted whole.
    @Test func aVeryLongAnswer() async throws {
        let h = try QHHarness()
        let long = (1...300).map { "Line \($0): " + String(repeating: "lorem ipsum ", count: 4) + "芯片" }.joined(separator: "\n")
        #expect(long.utf8.count > 18_000)
        QHAcceptanceURLProtocol.script([long], for: h.host)
        await h.ask("Explain everything at length")
        #expect(h.committed == [long])
        #expect(h.saved.entries.first?.answer == long)
        h.newField()
        await h.startQuestion()
        await h.press(k("1"))
        #expect(h.answerShown == long)
        await h.press(enterKey)
        #expect(h.committed.last == long && h.requests.count == 1)
    }

    /// Spec 1–5 (edge): an emoji question is kept, found, picked and asked as typed.
    @Test func anEmojiQuestion() async throws {
        let h = try QHHarness()
        await h.ask("🚀 how far is Mars?")
        await h.ask("👨‍👩‍👧 family plans")
        #expect(h.savedQuestions == ["👨‍👩‍👧 family plans", "🚀 how far is Mars?"])
        #expect(QHAcceptanceURLProtocol.question(in: h.requests[0]) == "🚀 how far is Mars?")
        await h.startQuestion()
        await h.type("🚀")
        #expect(h.composer.questionMatches.map(\.question) == ["🚀 how far is Mars?"])
        await h.press(downKey)
        await h.press(enterKey)
        #expect(h.answerShown == "A1: 🚀 how far is Mars?" && h.requests.count == 2)
        await h.press(escKey); await h.press(escKey)
        await h.startQuestion()
        await h.type("👨‍👩‍👧")
        #expect(h.composer.questionMatches.map(\.question) == ["👨‍👩‍👧 family plans"])
    }

    // MARK: 6. Not stored

    /// Spec 6: a question asked during secure input is not kept (secure input on when the answer comes).
    @Test func notStoredDuringSecureInput() async throws {
        let h = try QHHarness()
        await h.startQuestion()
        await h.type("secret question")
        // On by the time the answer arrives (the field turned secure, a password prompt came up).
        let effects = h.composer.handleKeyDown(enterKey).effects
        guard case let .startCommand(command, input, id)? = effects.first(where: { if case .startCommand = $0 { return true } else { return false } }) else {
            Issue.record("no request: \(effects)"); return
        }
        #expect(command == .question && input == "secret question")
        h.secure = true
        let answered = h.composer.receive(ConversionResult(versions: [CandidateLine("an answer")]), isFinal: true, id: id)
        #expect(h.composer.phase == .choosing)
        #expect(!answered.contains { if case .rememberQuestion = $0 { return true } else { return false } })
        #expect(h.composer.questionHistory.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: h.fileURL.path))
        // Secure input on from the start: nothing is sent, nothing kept.
        let s = try QHHarness()
        s.secure = true
        await s.ask("another secret")
        #expect(s.requests.isEmpty && !FileManager.default.fileExists(atPath: s.fileURL.path))
    }

    /// Spec 6: a question asked on selected text is not kept (and the selection never lands in the file).
    @Test func notStoredForAQuestionOnSelectedText() async throws {
        let h = try QHHarness(history: QHHarness.history(["What is Rust?"]))
        let before = try Data(contentsOf: h.fileURL)
        h.selection = Composer.Selection(text: "Confidential: the merger closes Friday", range: 0..<38)
        await h.startQuestion()
        #expect(h.composer.selectionInUse != nil)
        await h.type("summarize this")
        await h.press(enterKey)
        #expect(h.requests.count == 1 && h.answerShown != nil)
        #expect(!h.log.contains { if case .rememberQuestion = $0 { return true } else { return false } })
        #expect(try Data(contentsOf: h.fileURL) == before)
        let text = String(decoding: try Data(contentsOf: h.fileURL), as: UTF8.self)
        #expect(!text.contains("Confidential") && !text.contains("summarize this"))
    }

    /// Spec 6/7: with the setting off nothing is listed (digits are text) and nothing is kept.
    @Test func nothingWhenTheSettingIsOff() async throws {
        let h = try QHHarness(history: QHHarness.history(["What is Rust?"]))
        let before = try Data(contentsOf: h.fileURL)
        h.setting = false
        await h.startQuestion()
        #expect(h.composer.questionMatches.isEmpty && !h.composer.questionDigitsPick)
        await h.press(k("1"))
        #expect(!h.composer.showsSavedAnswer && h.composer.draft == "@question 1")
        await h.press(escKey)
        await h.ask("a question while off")
        #expect(h.requests.count == 1)
        #expect(!h.log.contains { if case .rememberQuestion = $0 { return true } else { return false } })
        #expect(try Data(contentsOf: h.fileURL) == before)
    }

    // MARK: 7. The setting

    /// Spec 7: "Remember recent questions" is on by default, also for a config file written before it existed.
    @Test func theSettingIsOnByDefault() throws {
        #expect(Config.default.rememberQuestions)
        #expect(Composer().remembersQuestions)
        let old = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(old.rememberQuestions)
        var off = Config.default
        off.rememberQuestions = false
        let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(off))
        #expect(!back.rememberQuestions)
    }

    /// Spec 7: clearing (the Clear button, turning the setting off: both save an empty history) removes the file, and
    /// the list is empty after.
    @Test func clearingRemovesTheSavedQuestions() async throws {
        let h = try QHHarness()
        await h.ask("What is Rust?")
        #expect(FileManager.default.fileExists(atPath: h.fileURL.path))
        try QuestionHistory().write(to: h.fileURL)
        #expect(!FileManager.default.fileExists(atPath: h.fileURL.path))
        await h.startQuestion()
        #expect(h.composer.questionMatches.isEmpty)
        // Clearing with nothing saved is fine.
        try QuestionHistory().write(to: h.fileURL)
    }

    // MARK: 8. Prompts unchanged (golden requests from release-0.6.3 at 55d496e)

    struct Golden: Decodable {
        let provider: String
        let question: String
        let input: String
        let method: String
        let url: String
        let headers: [String: String]
        let body: String
    }

    static let goldens: [Golden] = (try? JSONDecoder().decode([Golden].self, from: Data(goldenJSON.utf8))) ?? []

    static func sameJSON(_ a: String, _ b: String) -> Bool {
        guard let x = try? JSONSerialization.jsonObject(with: Data(a.utf8)) as? NSObject,
              let y = try? JSONSerialization.jsonObject(with: Data(b.utf8)) as? NSObject else { return false }
        return x.isEqual(y)
    }

    /// The golden's base URL in place of the harness's host (the goldens were made with fixed hosts).
    func matches(_ request: URLRequest, _ golden: Golden, host: String) -> Bool {
        let url = request.url?.absoluteString
            .replacingOccurrences(of: host, with: golden.provider == "anthropic" ? "golden-anthropic.test" : "golden-openai.test")
        var headers = request.allHTTPHeaderFields ?? [:]
        headers["Content-Length"] = nil
        return request.httpMethod == golden.method && url == golden.url && headers == golden.headers
            && AcceptanceLiveRule.strip(String(decoding: request.httpBody ?? Data(), as: UTF8.self), question: true) == golden.body
    }

    /// Spec 8: asking sends exactly the request 55d496e sends (Claude API and OpenAI-compatible), with or without
    /// saved questions listed, and a re-ask sends that same request again.
    @Test(arguments: ["anthropic", "openai"])
    func askingSendsTheSameRequestAsBefore(_ provider: String) async throws {
        let goldens = Self.goldens.filter { $0.provider == provider }
        #expect(goldens.count == 5)
        for golden in goldens {
            // No saved questions, then a list of them (some matching what's typed).
            for history in [QuestionHistory(), QHHarness.history(["What is Rust?", "AI 芯片的未来", "rust 2024", "🚀 launch"])] {
                let h = try QHHarness(provider: Provider(rawValue: provider)!, history: history.entries.isEmpty ? nil : history)
                await h.startQuestion()
                await h.type(golden.question)
                await h.press(enterKey)
                #expect(h.runs.map(\.input) == [golden.input], "\(golden.question)")
                #expect(h.requests.count == 1, "\(golden.question)")
                if let request = h.requests.first {
                    #expect(matches(request, golden, host: h.host), "\(provider) \(golden.question): \(String(decoding: request.httpBody ?? Data(), as: UTF8.self))")
                }
                // Re-asked from the list: the same request.
                await h.press(escKey); await h.press(escKey)
                await h.startQuestion()
                await h.type(golden.question)
                let found = h.composer.questionMatches.firstIndex { $0.question == golden.input }
                #expect(found != nil, "\(golden.question) not listed")
                if let found {
                    for _ in 0...found { await h.press(downKey) }
                    await h.press(enterKey)
                    #expect(h.composer.showsSavedAnswer && h.requests.count == 1)
                    await h.press(k("r", mods: .command))
                    #expect(h.requests.count == 2)
                    if h.requests.count == 2 {
                        #expect(matches(h.requests[1], golden, host: h.host), "re-ask \(provider) \(golden.question)")
                    }
                }
            }
        }
    }

    /// Spec 8: the request body itself, as the Converter builds it for each provider (Bedrock signs with the time, so
    /// its body and address only).
    @Test func converterRequestsMatchTheGoldens() async throws {
        #expect(Self.goldens.count == 15)
        for (index, golden) in Self.goldens.enumerated() where golden.provider == "bedrock" {
            var config = Config.default
            config.provider = .bedrock
            config.region = "qh-\(UUID().uuidString.prefix(8).lowercased())-\(index)"
            config.awsProfile = "test"
            let fixed = config
            let converter = Converter(
                client: BedrockClient(session: QHAcceptanceURLProtocol.session()), loadConfig: { fixed },
                loadCredentials: { _ in
                    AWSSharedConfig.Resolved(credentials: AWSCredentials(accessKeyId: "AKIDTEST", secretAccessKey: "secret"), region: nil)
                })
            let bedrockHost = "bedrock-runtime.\(fixed.region!).amazonaws.com"
            QHAcceptanceURLProtocol.setMode(.networkError, for: bedrockHost)
            for fresh in [false, true] {
                do { for try await _ in converter.generate(.question, input: golden.input, fresh: fresh) {} } catch {}
            }
            let requests = QHAcceptanceURLProtocol.requests(bedrockHost)
            #expect(requests.count == 2)
            for request in requests {
                // The same JSON (Bedrock's body is encoded without sorted keys: the order of its keys varies by run).
                let sent = AcceptanceLiveRule.strip(String(decoding: request.httpBody ?? Data(), as: UTF8.self), question: true)
                #expect(Self.sameJSON(sent, golden.body), "\(golden.question): sent \(sent)")
                #expect(request.url?.absoluteString.replacingOccurrences(of: fixed.region!, with: "golden-1") == golden.url)
                #expect(request.httpMethod == golden.method)
            }
        }
    }
}

// MARK: - Golden requests

/// Generated from a temporary worktree of 55d496e (release-0.6.3 before the feature): "@question <text>" ⏎ typed in a
/// Composer, the `.startCommand` input run with `Converter.generate` against a recording URLProtocol. Content-Length
/// left out (it follows the body).
let goldenJSON = #"""
[
 {
  "body": "{\"max_tokens\":6096,\"messages\":[{\"content\":\"What is Rust?\",\"role\":\"user\"}],\"model\":\"claude-haiku-5-5\",\"output_config\":{\"effort\":\"low\"},\"stream\":true,\"system\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\"}",
  "headers": {
   "Accept": "text/event-stream",
   "Content-Type": "application/json",
   "anthropic-version": "2023-06-01",
   "x-api-key": "sk-test"
  },
  "input": "What is Rust?",
  "method": "POST",
  "provider": "anthropic",
  "question": "What is Rust?",
  "url": "https://golden-anthropic.test/v1/messages"
 },
 {
  "body": "{\"max_tokens\":6096,\"messages\":[{\"content\":\"AI 芯片的未来\",\"role\":\"user\"}],\"model\":\"claude-haiku-5-5\",\"output_config\":{\"effort\":\"low\"},\"stream\":true,\"system\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\"}",
  "headers": {
   "Accept": "text/event-stream",
   "Content-Type": "application/json",
   "anthropic-version": "2023-06-01",
   "x-api-key": "sk-test"
  },
  "input": "AI 芯片的未来",
  "method": "POST",
  "provider": "anthropic",
  "question": "AI 芯片的未来",
  "url": "https://golden-anthropic.test/v1/messages"
 },
 {
  "body": "{\"max_tokens\":6096,\"messages\":[{\"content\":\"🚀 how far is Mars?\",\"role\":\"user\"}],\"model\":\"claude-haiku-5-5\",\"output_config\":{\"effort\":\"low\"},\"stream\":true,\"system\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\"}",
  "headers": {
   "Accept": "text/event-stream",
   "Content-Type": "application/json",
   "anthropic-version": "2023-06-01",
   "x-api-key": "sk-test"
  },
  "input": "🚀 how far is Mars?",
  "method": "POST",
  "provider": "anthropic",
  "question": "🚀 how far is Mars?",
  "url": "https://golden-anthropic.test/v1/messages"
 },
 {
  "body": "{\"max_tokens\":6096,\"messages\":[{\"content\":\"what is 2+2\",\"role\":\"user\"}],\"model\":\"claude-haiku-5-5\",\"output_config\":{\"effort\":\"low\"},\"stream\":true,\"system\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\"}",
  "headers": {
   "Accept": "text/event-stream",
   "Content-Type": "application/json",
   "anthropic-version": "2023-06-01",
   "x-api-key": "sk-test"
  },
  "input": "what is 2+2",
  "method": "POST",
  "provider": "anthropic",
  "question": "what is 2+2",
  "url": "https://golden-anthropic.test/v1/messages"
 },
 {
  "body": "{\"max_tokens\":6096,\"messages\":[{\"content\":\"rust\",\"role\":\"user\"}],\"model\":\"claude-haiku-5-5\",\"output_config\":{\"effort\":\"low\"},\"stream\":true,\"system\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\"}",
  "headers": {
   "Accept": "text/event-stream",
   "Content-Type": "application/json",
   "anthropic-version": "2023-06-01",
   "x-api-key": "sk-test"
  },
  "input": "rust",
  "method": "POST",
  "provider": "anthropic",
  "question": "rust",
  "url": "https://golden-anthropic.test/v1/messages"
 },
 {
  "body": "{\"max_tokens\":2000,\"messages\":[{\"content\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\",\"role\":\"system\"},{\"content\":\"What is Rust?\",\"role\":\"user\"}],\"model\":\"test-model\",\"stream\":true}",
  "headers": {
   "Accept": "text/event-stream",
   "Authorization": "Bearer sk-test",
   "Content-Type": "application/json"
  },
  "input": "What is Rust?",
  "method": "POST",
  "provider": "openai",
  "question": "What is Rust?",
  "url": "https://golden-openai.test/v1/chat/completions"
 },
 {
  "body": "{\"max_tokens\":2000,\"messages\":[{\"content\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\",\"role\":\"system\"},{\"content\":\"AI 芯片的未来\",\"role\":\"user\"}],\"model\":\"test-model\",\"stream\":true}",
  "headers": {
   "Accept": "text/event-stream",
   "Authorization": "Bearer sk-test",
   "Content-Type": "application/json"
  },
  "input": "AI 芯片的未来",
  "method": "POST",
  "provider": "openai",
  "question": "AI 芯片的未来",
  "url": "https://golden-openai.test/v1/chat/completions"
 },
 {
  "body": "{\"max_tokens\":2000,\"messages\":[{\"content\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\",\"role\":\"system\"},{\"content\":\"🚀 how far is Mars?\",\"role\":\"user\"}],\"model\":\"test-model\",\"stream\":true}",
  "headers": {
   "Accept": "text/event-stream",
   "Authorization": "Bearer sk-test",
   "Content-Type": "application/json"
  },
  "input": "🚀 how far is Mars?",
  "method": "POST",
  "provider": "openai",
  "question": "🚀 how far is Mars?",
  "url": "https://golden-openai.test/v1/chat/completions"
 },
 {
  "body": "{\"max_tokens\":2000,\"messages\":[{\"content\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\",\"role\":\"system\"},{\"content\":\"what is 2+2\",\"role\":\"user\"}],\"model\":\"test-model\",\"stream\":true}",
  "headers": {
   "Accept": "text/event-stream",
   "Authorization": "Bearer sk-test",
   "Content-Type": "application/json"
  },
  "input": "what is 2+2",
  "method": "POST",
  "provider": "openai",
  "question": "what is 2+2",
  "url": "https://golden-openai.test/v1/chat/completions"
 },
 {
  "body": "{\"max_tokens\":2000,\"messages\":[{\"content\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\",\"role\":\"system\"},{\"content\":\"rust\",\"role\":\"user\"}],\"model\":\"test-model\",\"stream\":true}",
  "headers": {
   "Accept": "text/event-stream",
   "Authorization": "Bearer sk-test",
   "Content-Type": "application/json"
  },
  "input": "rust",
  "method": "POST",
  "provider": "openai",
  "question": "rust",
  "url": "https://golden-openai.test/v1/chat/completions"
 },
 {
  "body": "{\"inferenceConfig\":{\"maxTokens\":2000,\"temperature\":0.3},\"system\":[{\"text\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\"}],\"messages\":[{\"content\":[{\"text\":\"What is Rust?\"}],\"role\":\"user\"}]}",
  "headers": {},
  "input": "What is Rust?",
  "method": "POST",
  "provider": "bedrock",
  "question": "What is Rust?",
  "url": "https://bedrock-runtime.golden-1.amazonaws.com/model/us.anthropic.claude-haiku-4-5-20251001-v1%3A0/converse-stream"
 },
 {
  "body": "{\"inferenceConfig\":{\"maxTokens\":2000,\"temperature\":0.3},\"system\":[{\"text\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\"}],\"messages\":[{\"content\":[{\"text\":\"AI 芯片的未来\"}],\"role\":\"user\"}]}",
  "headers": {},
  "input": "AI 芯片的未来",
  "method": "POST",
  "provider": "bedrock",
  "question": "AI 芯片的未来",
  "url": "https://bedrock-runtime.golden-1.amazonaws.com/model/us.anthropic.claude-haiku-4-5-20251001-v1%3A0/converse-stream"
 },
 {
  "body": "{\"inferenceConfig\":{\"maxTokens\":2000,\"temperature\":0.3},\"system\":[{\"text\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\"}],\"messages\":[{\"content\":[{\"text\":\"🚀 how far is Mars?\"}],\"role\":\"user\"}]}",
  "headers": {},
  "input": "🚀 how far is Mars?",
  "method": "POST",
  "provider": "bedrock",
  "question": "🚀 how far is Mars?",
  "url": "https://bedrock-runtime.golden-1.amazonaws.com/model/us.anthropic.claude-haiku-4-5-20251001-v1%3A0/converse-stream"
 },
 {
  "body": "{\"inferenceConfig\":{\"maxTokens\":2000,\"temperature\":0.3},\"system\":[{\"text\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\"}],\"messages\":[{\"content\":[{\"text\":\"what is 2+2\"}],\"role\":\"user\"}]}",
  "headers": {},
  "input": "what is 2+2",
  "method": "POST",
  "provider": "bedrock",
  "question": "what is 2+2",
  "url": "https://bedrock-runtime.golden-1.amazonaws.com/model/us.anthropic.claude-haiku-4-5-20251001-v1%3A0/converse-stream"
 },
 {
  "body": "{\"inferenceConfig\":{\"maxTokens\":2000,\"temperature\":0.3},\"system\":[{\"text\":\"The user is typing in a text field on a Mac, and your reply is inserted at their cursor as is. Reply in the language of their message unless they ask for another. Write plain text: line breaks only where they help (code, steps, a short list), and code as plain lines with its indentation, exactly as it would be pasted into a file. No Markdown (no headings, bold, tables or code fences), no preamble such as \\\"Sure\\\" or \\\"Here is\\\", and no closing remarks. Answer the user's question accurately and concisely: two or three sentences, unless the question asks for more. If you are not sure, say so briefly.\"}],\"messages\":[{\"content\":[{\"text\":\"rust\"}],\"role\":\"user\"}]}",
  "headers": {},
  "input": "rust",
  "method": "POST",
  "provider": "bedrock",
  "question": "rust",
  "url": "https://bedrock-runtime.golden-1.amazonaws.com/model/us.anthropic.claude-haiku-4-5-20251001-v1%3A0/converse-stream"
 }
]
"""#

/// Watches a folder from another thread: every regular file seen in it whose mode lets the group or others read it.
final class QHModeWatcher: @unchecked Sendable {
    let folder: String
    private let lock = OSAllocatedUnfairLock(initialState: (running: false, exposed: [String](), looks: 0))
    private let done = DispatchSemaphore(value: 0)

    init(folder: URL) { self.folder = folder.path }

    func start() {
        lock.withLock { $0.running = true }
        Thread.detachNewThread { [self] in
            while lock.withLock({ $0.running }) {
                if let dir = opendir(folder) {
                    while let entry = readdir(dir) {
                        let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
                        if name == "." || name == ".." { continue }
                        var info = stat()
                        guard lstat(folder + "/" + name, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { continue }
                        if info.st_mode & 0o077 != 0 {
                            let mode = String(info.st_mode & 0o777, radix: 8)
                            lock.withLock { $0.exposed.append("\(name) \(mode)") }
                        }
                    }
                    closedir(dir)
                }
                lock.withLock { $0.looks += 1 }
            }
            done.signal()
        }
    }

    /// Stops; what was seen readable by others, and how many times the folder was looked at.
    func stop() -> (exposed: [String], looks: Int) {
        lock.withLock { $0.running = false }
        done.wait()
        return lock.withLock { ($0.exposed, $0.looks) }
    }
}

extension QuestionHistoryAcceptanceTests {
    /// Spec 5: readable only by the user from the start: while it is written, no file in its folder (the file, or one it
    /// is written to first) can be read by others, not even for a moment. Watched from another thread over many writes;
    /// the same watcher does see the write-then-chmod way (the control), so seeing nothing means something.
    @Test func theFileIsNeverReadableByOthersWhileWritten() throws {
        func watch(_ write: (URL, Int) throws -> Void) throws -> (exposed: [String], looks: Int) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("qh-acceptance-mode-\(UUID().uuidString)")
            let folder = root.appendingPathComponent("AllInOneIME")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let url = folder.appendingPathComponent("recent-questions.json")
            let watcher = QHModeWatcher(folder: folder)
            watcher.start()
            for i in 0..<300 { try write(url, i) }
            return watcher.stop()
        }
        // The control: written, then made 0600.
        let control = try watch { url, i in
            try Data("{\"i\":\(i)}".utf8).write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            if i % 2 == 0 { try FileManager.default.removeItem(at: url) }
        }
        #expect(!control.exposed.isEmpty, "the watcher saw nothing even for write-then-chmod (\(control.looks) looks)")
        // QuestionHistory's own writes: a new file every other time (cleared in between), replaced the others.
        let real = try watch { url, i in
            let history = QHHarness.history(["question \(i)", "AI 芯片的未来", "What is Rust?"])
            try history.write(to: url)
            if i % 2 == 0 { try QuestionHistory().write(to: url) }
        }
        #expect(real.looks > 100)
        #expect(real.exposed.isEmpty, "readable by others while written: \(Set(real.exposed).sorted())")
    }
}

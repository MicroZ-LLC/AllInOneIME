import Foundation
import os
import Testing
@testable import AllInOneIMECore

// Acceptance tests for Translate as You Type (「边打边译」, 0.6.4), written from the spec (the user's decisions of
// 2026-10-16/17), independently of the implementation's own tests. Each test names the clause it checks: "hold" the
// long press of Shift, "draft" typing in the mode, "keys" ⏎ ⇧⏎ Esc and typing while it translates, "fail" failures,
// "same" text already in the target language, "where" No-AI apps and secure input, "target" the target language,
// "chip" the chip, "tone" the tone by app, "apps" switching apps and `translateAlways`, "privacy" redaction and the
// prompts, "cmd" no @mode / @exit, "ui" the app-side wording (read from the app target's source: it isn't in Core).
//
// The composer is driven as the input controller drives it: keys (`k`, `enterKey` …), modifier changes, the chip's
// clicks, and the translation delivered to `receive` (by hand, or end to end through a `Converter` whose provider is a
// Claude API endpoint stubbed at the HTTP level, `TMAccStub`). What the controller keeps for every field (on or off,
// the language picked last) is `TranslateMode.State`; the long press is `TranslateMode.ShiftHold` on a test clock.

// MARK: - A provider that records every request

/// Answers each request to its host with the next queued reply, else with "EN: <the user's message as sent>" (the
/// format of a translation line), streamed as the Claude API streams; keeps every body.
final class TMAccStub: URLProtocol, @unchecked Sendable {
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
        configuration.protocolClasses = [TMAccStub.self]
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
            guard var queue = state.replies[host], !queue.isEmpty else {
                return .answer("EN: " + ((try? TMAccSent(body))?.lastUser ?? "?"))
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
struct TMAccSent {
    var raw: Data
    var system: String
    /// (role, text), oldest first.
    var messages: [(role: String, text: String)]

    init(_ data: Data) throws {
        raw = data
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["messages"] as? [[String: Any]] else { throw CocoaError(.coderReadCorrupt) }
        if let s = json["system"] as? String { system = s }
        else if let parts = json["system"] as? [[String: Any]] { system = parts.compactMap { $0["text"] as? String }.joined() }
        else { system = "" }
        messages = list.map { message in
            let text: String
            if let s = message["content"] as? String { text = s }
            else if let parts = message["content"] as? [[String: Any]] { text = parts.compactMap { $0["text"] as? String }.joined() }
            else { text = "" }
            return (message["role"] as? String ?? "", "\(text)")
        }
    }

    var lastUser: String { messages.last { $0.role == "user" }?.text ?? "" }
    var body: String { String(decoding: raw, as: UTF8.self) }
}

/// A `Converter` whose provider is `TMAccStub` at a host of its own (a fresh one has an empty cache).
struct TMAccWire {
    let host: String
    let config: Config
    let converter: Converter

    init(configure: (inout Config) -> Void = { _ in }) {
        host = "tmode-\(UUID().uuidString.lowercased()).test"
        var config = Config.default
        config.provider = .anthropic
        config.anthropic = ProviderSettings(baseURL: "https://\(host)")
        configure(&config)
        self.config = config
        let fixed = config
        converter = Converter(client: BedrockClient(session: TMAccStub.session()), loadConfig: { fixed },
                              loadCredentials: { _ in throw CocoaError(.userCancelled) },
                              loadKey: { _, _ in "sk-test" }, loadJargon: { _ in [] })
    }

    var requests: [TMAccSent] { TMAccStub.bodies(host).compactMap { try? TMAccSent($0) } }
    var requestCount: Int { TMAccStub.bodies(host).count }

    /// Everything a stream gave: its updates and how it ended.
    static func drain(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) async -> (updates: [ConversionUpdate], error: Error?) {
        var updates: [ConversionUpdate] = []
        do {
            for try await update in stream { updates.append(update) }
            return (updates, nil)
        } catch {
            return (updates, error)
        }
    }

    /// Translate as You Type on `input` into `target` in `app`, to the end.
    func mode(_ input: String, into target: OutputLanguage = .english, app: String? = nil)
        async -> (updates: [ConversionUpdate], error: Error?) {
        await Self.drain(converter.translateMode(input, target: target, app: app))
    }
}

// MARK: - Keys and clock

private let tmCommandKey: UInt16 = 0x37
private let tmControlKey: UInt16 = 0x3B
private let tmCapsLockKey: UInt16 = 0x39
private let tmShiftReturn = acceptanceShiftReturn
private let tmAt = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
private let tmShiftA = KeyEvent(keyCode: 0x00, characters: "A", charactersIgnoringModifiers: "A", modifiers: .shift)

/// The clock a long press is timed by (seconds), set by hand.
final class TMAccClock {
    var t: TimeInterval = 0
}

// MARK: - The input controller, stood in for

/// A composer with the fake pinyin engine ("nihao" → 你好, "wo" → 我), the mode on (into `target`) as the controller
/// turns it on, and what reached the field: commits, text typed out, keys passed to the app as they were.
/// Requests (`Effect.startTranslateMode`) are kept: a test delivers their translation by hand (`deliver`, `failRequest`),
/// or, with a `wire`, `runRequests` sends them through the converter as the controller does.
final class TMAccRig {
    let engine = FakeEngine()
    let composer: Composer
    var wire: TMAccWire?
    /// The app of the field (for the converter: its tone and its settings).
    var app: String?

    private(set) var log: [Composer.Effect] = []
    /// What went into the field, in order: commits, text typed out, a selection replaced, and printable keys the app
    /// got as they were (the composer let them through).
    private(set) var inserted: [String] = []
    /// Keys the composer let through to the app (⏎ among them would send in a chat app).
    private(set) var passedThrough: [KeyEvent] = []
    private(set) var notices: [String] = []
    private(set) var starts: [(input: String, target: OutputLanguage, id: Int)] = []
    private(set) var cancels = 0
    private(set) var languageChanges: [Language] = []
    private var pending: [(input: String, target: OutputLanguage, id: Int)] = []

    /// Secure input on: the composer is told (as the controller tells it).
    var secure = false { didSet { let on = secure; composer.secureInputActive = { on } } }
    /// The app has no AI (`AppProfile.noAI`): the composer's refusal, as the controller sets it.
    var noAI: String? { didSet { let refusal = noAI; composer.aiRefusal = { refusal } } }

    init(actionKey: ActionKey = .enter, english: Bool = false, target: OutputLanguage? = .english,
         messages: TranslateMode.Messages = .chinese) {
        composer = Composer(engine: engine, actionKey: actionKey)
        composer.commands = Command.builtins
        composer.translateModeMessages = messages
        composer.secureInputActive = { false }
        composer.aiRefusal = { nil }
        if english { composer.setInputMode(.english) }
        if let target { record(composer.setTranslateMode(TranslateMode.Session(target: target))) }
    }

    var c: Composer { composer }

    @discardableResult
    func key(_ event: KeyEvent) -> Composer.Response {
        let response = composer.handleKeyDown(event)
        if !response.handled {
            passedThrough.append(event)
            if let text = event.printableText { inserted.append(text) }
        }
        record(response.effects)
        return response
    }

    /// Each character as a key (Space as the Space key, capitals with Shift).
    func type(_ text: String) {
        for ch in text {
            if ch == " " { key(spaceKey); continue }
            key(KeyEvent(keyCode: 0, characters: String(ch), modifiers: ch.isUppercase ? .shift : []))
        }
    }

    /// Pinyin, then Space: its first candidate picked.
    func pick(_ pinyin: String) {
        type(pinyin)
        key(spaceKey)
    }

    /// Turns the mode on (`target`) or off (nil) here, as the controller does.
    @discardableResult
    func setMode(_ target: OutputLanguage?) -> [Composer.Effect] {
        let out = composer.setTranslateMode(target.map(TranslateMode.Session.init(target:)))
        record(out)
        return out
    }

    func record(_ effects: [Composer.Effect]) {
        for effect in effects {
            log.append(effect)
            switch effect {
            case let .startTranslateMode(input, session, id):
                starts.append((input, session.target, id))
                pending.append((input, session.target, id))
            case let .commit(text): inserted.append(text)
            case let .typeOut(text): inserted.append(text)
            case let .replaceSelection(text, _): inserted.append(text)
            case let .notice(text): notices.append(text)
            case .cancelConversion: cancels += 1
            case let .inputLanguageChanged(language): languageChanges.append(language)
            default: break
            }
        }
    }

    /// The translation of request `id` (`text` in its target), as the converter delivers it.
    @discardableResult
    func deliver(_ text: String, id: Int, isFinal: Bool = true, complete: Bool = true) -> [Composer.Effect] {
        let target = starts.first { $0.id == id }?.target ?? .english
        let result = ConversionResult(translations: [Translation(language: target, line: CandidateLine(text, isComplete: complete))])
        let out = composer.receive(result, isFinal: isFinal, id: id)
        record(out)
        return out
    }

    @discardableResult
    func failRequest(_ message: String, id: Int) -> [Composer.Effect] {
        let out = composer.fail(message, id: id)
        record(out)
        return out
    }

    /// The requests started and not yet sent, through the wire's converter, their updates to `receive` (a failure to
    /// `fail`), as the controller does.
    func runRequests() async {
        guard let wire else { return }
        while !pending.isEmpty {
            let request = pending.removeFirst()
            do {
                for try await update in wire.converter.translateMode(request.input, target: request.target, app: app) {
                    record(composer.receive(update.result, isFinal: update.isFinal, id: request.id))
                }
            } catch {
                record(composer.fail("\(error)", id: request.id))
            }
        }
    }

    var lastStart: (input: String, target: OutputLanguage, id: Int)? { starts.last }
    /// The id of the last request started (-1, which no request has, before any).
    var lastID: Int { starts.last?.id ?? -1 }

    /// What the effects of one key asked the model for.
    static func starts(_ effects: [Composer.Effect]) -> [(input: String, target: OutputLanguage)] {
        effects.compactMap {
            if case let .startTranslateMode(input, session, _) = $0 { return (input, session.target) }
            return nil
        }
    }

    static func notices(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .notice(text) = $0 { return text } else { return nil } }
    }
}

/// A config whose output languages are `outputs`, in that order (the first in use).
private func tmConfig(_ outputs: [OutputLanguage], configure: (inout Config) -> Void = { _ in }) -> Config {
    var config = Config.default
    config.setOrder(outputs)
    configure(&config)
    return config
}

private let tmJapanese = OutputLanguage("ja")
private let tmFrench = OutputLanguage("fr")
private let tmKorean = OutputLanguage("ko")

private let tmSlack = "com.tinyspeck.slackmacgap"
private let tmMail = "com.apple.mail"
private let tmTextEdit = "com.apple.TextEdit"

// MARK: - The long press of Shift

/// A press of Shift timed as the controller times it (`TranslateMode.ShiftHold`), on a clock set by hand.
final class TMAccPress {
    private let clock: TMAccClock
    var hold: TranslateMode.ShiftHold

    init() {
        let clock = TMAccClock()
        self.clock = clock
        hold = TranslateMode.ShiftHold(now: { clock.t })
    }

    /// A modifier changed at `t`: whether a long press is now being timed.
    @discardableResult
    func flags(_ keyCode: UInt16, _ modifiers: KeyModifiers, at t: TimeInterval) -> Bool {
        clock.t = t
        return hold.flagsChanged(keyCode: keyCode, modifiers: modifiers)
    }

    @discardableResult
    func down(at t: TimeInterval) -> Bool { flags(VirtualKey.leftShift, .shift, at: t) }

    func up(at t: TimeInterval) { flags(VirtualKey.leftShift, [], at: t) }

    /// A key went down at `t` (a letter with Shift: a capital).
    func key(at t: TimeInterval) {
        clock.t = t
        hold.keyDown()
    }

    /// What was due at each of `times`, in order (the timers going off then).
    func polls(_ times: [TimeInterval]) -> [TranslateMode.ShiftHold.Due?] {
        times.map { time in
            clock.t = time
            return hold.poll()
        }
    }
}

@Suite("TranslateModeAcceptance: the long press of Shift")
struct TranslateModeAcceptanceHoldTests {
    @Test func hold_hintAtHalfASecondToggleAtOneSecond() {
        #expect(TranslateMode.ShiftHold.hintAfter == 0.5)
        #expect(TranslateMode.ShiftHold.toggleAfter == 1.0)
        let press = TMAccPress()
        #expect(press.down(at: 10), "Shift down alone arms a long press")
        let due = press.polls([10.2, 10.45, 10.5, 10.7, 10.95, 11.0, 11.3, 12.5])
        #expect(due == [nil, nil, .hint, nil, nil, .toggle, nil, nil], "\(due)")
    }

    @Test func hold_theRightShiftWorksToo() {
        let press = TMAccPress()
        #expect(press.flags(VirtualKey.rightShift, .shift, at: 0))
        #expect(press.polls([0.5, 1.0]) == [.hint, .toggle])
    }

    @Test func hold_releasedBeforeOneSecondTogglesNothing() {
        // Released after the hint.
        let press = TMAccPress()
        #expect(press.down(at: 0))
        #expect(press.polls([0.5]) == [.hint])
        press.up(at: 0.9)
        #expect(press.polls([1.0, 1.5, 3.0]) == [nil, nil, nil])
        // Released before the hint: no hint either.
        let early = TMAccPress()
        #expect(early.down(at: 5))
        early.up(at: 5.3)
        #expect(early.polls([5.5, 6.0, 7.0]) == [nil, nil, nil])
    }

    @Test func hold_shiftWithALetterNeverToggles() {
        // A capital before the hint.
        let press = TMAccPress()
        #expect(press.down(at: 0))
        press.key(at: 0.2)
        #expect(press.polls([0.5, 1.0, 2.0]) == [nil, nil, nil])
        // A capital after the hint.
        let late = TMAccPress()
        #expect(late.down(at: 4))
        #expect(late.polls([4.5]) == [.hint])
        late.key(at: 4.7)
        #expect(late.polls([5.0, 6.0]) == [nil, nil])
    }

    @Test func hold_shiftWithALetterTypesACapitalAndNeverToggles() {
        // The composer and the press on one timeline, as the controller runs them: Shift down, A, still held.
        let rig = TMAccRig(english: true, target: nil)
        let press = TMAccPress()
        rig.record(rig.c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 0))
        #expect(press.down(at: 0))
        press.key(at: 0.15)
        rig.key(tmShiftA)
        #expect(rig.inserted == ["A"], "Shift + a letter is a capital: \(rig.inserted)")
        #expect(press.polls([0.5, 1.0, 1.6]) == [nil, nil, nil])
        rig.record(rig.c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.7))
        press.up(at: 1.7)
        #expect(rig.languageChanges.isEmpty)
    }

    @Test func hold_anotherModifierInBetweenNeverToggles() {
        for (keyCode, modifier) in [(tmCommandKey, KeyModifiers.command), (tmControlKey, .control),
                                    (VirtualKey.leftOption, .option), (tmCapsLockKey, .capsLock)] {
            let press = TMAccPress()
            #expect(press.down(at: 0))
            press.flags(keyCode, [.shift, modifier], at: 0.2)
            press.flags(keyCode, .shift, at: 0.3)  // let go again, Shift still down
            #expect(press.polls([0.5, 1.0, 1.5]) == [nil, nil, nil], "\(modifier)")
        }
    }

    @Test func hold_shiftDownWithAnotherModifierAlreadyHeldIsAShortcut() {
        for modifier in [KeyModifiers.command, .control, .option] {
            let press = TMAccPress()
            press.flags(VirtualKey.leftShift, [.shift, modifier], at: 0)
            #expect(press.polls([0.5, 1.0]) == [nil, nil], "\(modifier)")
        }
    }

    @Test func hold_theOtherShiftInBetweenIsAnotherKey() {
        let press = TMAccPress()
        #expect(press.down(at: 0))
        press.flags(VirtualKey.rightShift, .shift, at: 0.2)
        #expect(press.polls([0.5, 1.0, 1.5]) == [nil, nil, nil])
    }

    /// Reading: Caps Lock already on is a state, not another modifier pressed in between.
    @Test func hold_capsLockAlreadyOnStillCounts() {
        let press = TMAccPress()
        #expect(press.flags(VirtualKey.leftShift, [.shift, .capsLock], at: 0))
        #expect(press.polls([0.5, 1.0]) == [.hint, .toggle])
    }

    @Test func hold_eachPressTogglesOnceAndTheNextOneAgain() {
        let press = TMAccPress()
        #expect(press.down(at: 0))
        #expect(press.polls([0.5, 1.0, 2.0, 4.0]) == [.hint, .toggle, nil, nil], "held on: still once")
        press.up(at: 4.1)
        #expect(press.down(at: 6))
        #expect(press.polls([6.5, 7.0]) == [.hint, .toggle], "the next press (to turn it off)")
    }

    @Test func hold_aShortTapStillSwitchesTheInputLanguage() {
        let rig = TMAccRig(target: .english)
        let press = TMAccPress()
        #expect(rig.c.inputLanguage == .chinese)
        rig.record(rig.c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 0))
        press.down(at: 0)
        rig.record(rig.c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 0.12))
        press.up(at: 0.12)
        #expect(rig.languageChanges == [.english])
        #expect(rig.c.inputLanguage == .english)
        #expect(press.polls([0.5, 1.0]) == [nil, nil], "a tap toggles nothing")
        // Off as well.
        let off = TMAccRig(target: nil)
        off.record(off.c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 0))
        off.record(off.c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 0.12))
        #expect(off.languageChanges == [.english])
    }

    @Test func hold_aLongPressDoesNotAlsoSwitchTheInputLanguage() {
        let rig = TMAccRig(target: nil)
        let press = TMAccPress()
        rig.record(rig.c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 0))
        press.down(at: 0)
        #expect(press.polls([0.5, 1.0]) == [.hint, .toggle])
        rig.record(rig.c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1))
        press.up(at: 1.1)
        #expect(rig.languageChanges.isEmpty)
        #expect(rig.c.inputLanguage == .chinese)
    }

    /// Released after the hint, before the toggle: nothing at all (no mode, and no switch of language either: that's a
    /// short tap's, as before).
    @Test func hold_releasedAfterTheHintSwitchesNothing() {
        let rig = TMAccRig(target: nil)
        let press = TMAccPress()
        rig.record(rig.c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 0))
        press.down(at: 0)
        #expect(press.polls([0.5]) == [.hint])
        rig.record(rig.c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 0.8))
        press.up(at: 0.8)
        #expect(press.polls([1.0]) == [nil])
        #expect(rig.languageChanges.isEmpty)
    }
}

// MARK: - Typing in the mode

@Suite("TranslateModeAcceptance: typing, ⏎ and the other keys")
struct TranslateModeAcceptanceTypingTests {
    /// The mode on into English, "你好" picked: the draft.
    func drafted(actionKey: ActionKey = .enter, messages: TranslateMode.Messages = .chinese) -> TMAccRig {
        let rig = TMAccRig(actionKey: actionKey, target: .english, messages: messages)
        rig.pick("nihao")
        return rig
    }

    // draft

    @Test func draft_wordsPickedCollectIntoADraftShownAsTyped() {
        let rig = TMAccRig(target: .english)
        rig.type("nihao")
        #expect(rig.c.markedText == "nihao", "pinyin composes as usual")
        rig.key(spaceKey)
        #expect(rig.inserted.isEmpty, "a word picked goes into the draft, not the field: \(rig.inserted)")
        #expect(rig.c.draft == "你好")
        #expect(rig.c.markedText == "你好")
        rig.type("wo")
        #expect(rig.c.markedText == "你好wo")
        rig.key(spaceKey)
        #expect(rig.c.draft == "你好我")
        #expect(rig.c.markedText == "你好我")
        #expect(rig.inserted.isEmpty && rig.starts.isEmpty)
    }

    @Test func draft_noLanguagePrefixInTheField() {
        for target in [OutputLanguage.english, tmJapanese, tmKorean] {
            let rig = TMAccRig(target: target)
            #expect(!rig.c.markedText.contains("→"), "before typing: \(rig.c.markedText)")
            rig.type("ni")
            #expect(rig.c.markedText == "ni", "\(target.code): \(rig.c.markedText)")
            rig.type("hao")
            rig.key(spaceKey)
            #expect(rig.c.markedText == "你好", "\(target.code): \(rig.c.markedText)")
            rig.key(enterKey)
            #expect(!rig.c.markedText.contains("→"), "\(target.code) while translating: \(rig.c.markedText)")
            #expect(rig.c.markedText.hasPrefix("你好"))
        }
        // Typed in English letters, into Japanese.
        let english = TMAccRig(english: true, target: tmJapanese)
        english.type("see you")
        #expect(english.c.markedText == "see you", "\(english.c.markedText)")
    }

    // keys: ⏎

    @Test func keys_enterTranslatesAndInsertsTheResultDirectly() throws {
        let rig = drafted()
        let enter = rig.key(enterKey)
        #expect(enter.handled, "⏎ is the mode's, the app doesn't get it (it would send)")
        #expect(TMAccRig.starts(enter.effects).map(\.input) == ["你好"])
        #expect(TMAccRig.starts(enter.effects).map(\.target) == [.english])
        #expect(rig.inserted.isEmpty, "nothing in the field until the translation is in")
        // No list to choose from, while it comes or once it's in: the panel isn't shown.
        #expect(!rig.c.wantsPanel)
        #expect(!enter.effects.contains(.showPanel), "\(enter.effects)")
        let id = try #require(rig.lastStart?.id)
        let partial = rig.deliver("Hel", id: id, isFinal: false, complete: false)
        #expect(rig.inserted.isEmpty, "a partial translation isn't inserted")
        #expect(!rig.c.wantsPanel)
        #expect(!partial.contains(.showPanel), "\(partial)")
        let done = rig.deliver("Hello", id: id)
        #expect(rig.inserted == ["Hello"], "\(rig.inserted)")
        #expect(!done.contains(.showPanel))
        #expect(rig.c.draft.isEmpty && rig.c.markedText.isEmpty && !rig.c.isComposing)
        #expect(rig.c.choices.isEmpty)
        // It doesn't send: no line break inserted, no key passed on.
        #expect(rig.passedThrough.isEmpty)
        #expect(!rig.inserted.joined().contains("\n") && !rig.inserted.joined().contains("\r"))
        // The next ⏎ (nothing typed) is the app's as usual.
        #expect(!rig.key(enterKey).handled)
    }

    /// "It doesn't send": ⏎ pressed again while it translates doesn't reach the app either, and the translation goes in once.
    @Test func keys_enterAgainWhileItTranslatesDoesNotSend() throws {
        let rig = drafted()
        rig.key(enterKey)
        let id = try #require(rig.lastStart?.id)
        let again = rig.key(enterKey)
        #expect(again.handled, "\(again.effects)")
        #expect(rig.passedThrough.isEmpty)
        #expect(rig.inserted.isEmpty)
        rig.deliver("Hello", id: rig.lastID)
        if rig.lastID != id { rig.deliver("Hello", id: id) }
        #expect(rig.inserted == ["Hello"], "\(rig.inserted)")
    }

    @Test func keys_enterTranslatesWhateverTheActionKey() {
        for actionKey in [ActionKey.enter, .optionSpace, .optionTap, .space] {
            let rig = drafted(actionKey: actionKey)
            #expect(rig.c.draft == "你好", "\(actionKey)")
            let enter = rig.key(enterKey)
            #expect(enter.handled, "\(actionKey)")
            #expect(TMAccRig.starts(enter.effects).map(\.input) == ["你好"], "\(actionKey)")
            if let id = rig.lastStart?.id { rig.deliver("Hello", id: id) }
            #expect(rig.inserted == ["Hello"], "\(actionKey): \(rig.inserted)")
            #expect(rig.passedThrough.isEmpty, "\(actionKey)")
        }
    }

    @Test func keys_enterWhereResultsAreTypedOutTypesTheTranslation() throws {
        let rig = drafted()
        rig.c.typesResults = true
        rig.key(enterKey)
        let id = try #require(rig.lastStart?.id)
        rig.deliver("Hello", id: id)
        #expect(rig.inserted == ["Hello"], "\(rig.inserted)")
        #expect(rig.c.choices.isEmpty)
    }

    @Test func keys_translatingMarkerFollowsTheDraft() {
        let rig = drafted()
        #expect(!rig.c.markedText.contains("翻译中"))
        rig.key(enterKey)
        #expect(rig.c.markedText.hasPrefix("你好"), "\(rig.c.markedText)")
        #expect(rig.c.markedText.hasSuffix("· 翻译中…"), "\(rig.c.markedText)")
        rig.deliver("Hello", id: rig.lastID)
        #expect(!rig.c.markedText.contains("翻译中"))
        // English UI.
        let english = drafted(messages: .english)
        english.key(enterKey)
        #expect(english.c.markedText.hasPrefix("你好"), "\(english.c.markedText)")
        #expect(english.c.markedText.hasSuffix("· Translating…"), "\(english.c.markedText)")
    }

    @Test func keys_shiftEnterInsertsTheDraftAsTyped() {
        let rig = drafted()
        let response = rig.key(tmShiftReturn)
        #expect(response.handled)
        #expect(rig.starts.isEmpty, "not translated")
        #expect(rig.inserted == ["你好"], "\(rig.inserted)")
        #expect(rig.c.draft.isEmpty && rig.c.markedText.isEmpty)
        #expect(!rig.inserted.joined().contains("\n"))
    }

    @Test func keys_escWhileTranslatingCancelsAndKeepsTheDraft() throws {
        let rig = drafted()
        rig.key(enterKey)
        let first = try #require(rig.lastStart?.id)
        let esc = rig.key(escKey)
        #expect(esc.handled)
        #expect(esc.effects.contains(.cancelConversion), "\(esc.effects)")
        #expect(rig.c.draft == "你好")
        #expect(rig.c.markedText == "你好", "\(rig.c.markedText)")
        #expect(rig.inserted.isEmpty)
        // The cancelled request's answer, arriving late, changes nothing.
        rig.deliver("Hello", id: first)
        #expect(rig.inserted.isEmpty && rig.c.draft == "你好")
        // ⏎ translates the draft again.
        rig.key(enterKey)
        #expect(rig.starts.map(\.input) == ["你好", "你好"])
        #expect(rig.lastID != first)
        rig.deliver("Hi", id: rig.lastID)
        #expect(rig.inserted == ["Hi"])
    }

    @Test func keys_escOnADraftClearsIt() {
        let rig = drafted()
        let esc = rig.key(escKey)
        #expect(esc.handled)
        #expect(rig.c.draft.isEmpty && rig.c.markedText.isEmpty)
        #expect(rig.inserted.isEmpty && rig.starts.isEmpty)
        // Pinyin being typed on a draft: Esc as usual.
        let typing = drafted()
        typing.type("wo")
        typing.key(escKey)
        #expect(typing.inserted.isEmpty && typing.starts.isEmpty)
        #expect(!typing.c.markedText.contains("wo"))
    }

    @Test func keys_typingWhileItTranslatesCancelsAndGoesOnWithTheDraft() throws {
        let rig = drafted()
        rig.key(enterKey)
        let first = try #require(rig.lastStart?.id)
        let w = rig.key(k("w"))
        #expect(w.handled)
        #expect(w.effects.contains(.cancelConversion), "\(w.effects)")
        #expect(rig.c.markedText == "你好w", "\(rig.c.markedText)")
        rig.key(k("o"))
        rig.key(spaceKey)
        #expect(rig.c.draft == "你好我")
        #expect(rig.inserted.isEmpty)
        rig.deliver("Hello", id: first)
        #expect(rig.inserted.isEmpty, "the cancelled translation never goes in")
        rig.key(enterKey)
        #expect(rig.starts.map(\.input) == ["你好", "你好我"])
        rig.deliver("Hello me", id: rig.lastID)
        #expect(rig.inserted == ["Hello me"])
    }

    // fail

    @Test func fail_aNetworkFailureKeepsTheDraftWithAOneLineNoticeAndEnterRetries() {
        let rig = drafted()
        rig.key(enterKey)
        let failed = rig.failRequest("The network connection was lost.\nNSURLErrorDomain Code=-1005 (and more)", id: rig.lastID)
        #expect(rig.c.draft == "你好")
        #expect(rig.c.markedText == "你好", "\(rig.c.markedText)")
        #expect(rig.inserted.isEmpty)
        let notices = TMAccRig.notices(failed)
        #expect(notices.count == 1, "\(failed)")
        #expect(notices.allSatisfy { !$0.isEmpty && !$0.contains("\n") }, "one line: \(notices)")
        #expect(notices.first?.contains("The network connection was lost.") == true, "\(notices)")
        // ⏎ again retries.
        let retry = rig.key(enterKey)
        #expect(TMAccRig.starts(retry.effects).map(\.input) == ["你好"])
        rig.deliver("Hello", id: rig.lastID)
        #expect(rig.inserted == ["Hello"])
    }

    @Test func fail_aRefusalOrNoTranslationKeepsTheDraftAndEnterRetries() {
        let rig = drafted()
        rig.key(enterKey)
        let empty = rig.c.receive(.empty, isFinal: true, id: rig.lastID)
        rig.record(empty)
        #expect(rig.c.draft == "你好")
        #expect(rig.inserted.isEmpty)
        #expect(TMAccRig.notices(empty).count == 1, "\(empty)")
        rig.key(enterKey)
        #expect(rig.starts.count == 2)
        rig.deliver("Hello", id: rig.lastID)
        #expect(rig.inserted == ["Hello"])
    }

    @Test func fail_secureInputAtEnterKeepsTheDraftWithANoticeAndEnterRetries() {
        let rig = drafted()
        rig.secure = true
        let enter = rig.key(enterKey)
        #expect(enter.handled)
        #expect(TMAccRig.starts(enter.effects).isEmpty, "nothing sent during secure input")
        #expect(rig.c.draft == "你好")
        #expect(rig.inserted.isEmpty)
        #expect(TMAccRig.notices(enter.effects).count == 1, "\(enter.effects)")
        rig.secure = false
        rig.key(enterKey)
        #expect(rig.starts.map(\.input) == ["你好"])
    }

    /// The controller refuses a request itself during secure input (`fail`): as any failure.
    @Test func fail_secureInputRefusedByTheControllerKeepsTheDraft() {
        let rig = drafted()
        rig.key(enterKey)
        rig.failRequest("Secure input is on: nothing was sent", id: rig.lastID)
        #expect(rig.c.draft == "你好" && rig.inserted.isEmpty)
        #expect(rig.notices.count == 1)
        rig.key(enterKey)
        #expect(rig.starts.count == 2)
    }

    // same

    @Test func same_englishTypedWhileTheTargetIsEnglishGoesInAsTyped() {
        let rig = TMAccRig(english: true, target: .english)
        rig.type("see you")
        #expect(rig.inserted.joined() == "see you", "\(rig.inserted)")
        #expect(rig.c.draft.isEmpty)
        #expect(!rig.key(enterKey).handled, "⏎ is the app's as usual")
        #expect(rig.starts.isEmpty)
    }

    @Test func same_chineseTypedWhileTheTargetIsChineseGoesInAsTyped() {
        let rig = TMAccRig(target: .chinese)
        rig.pick("nihao")
        #expect(rig.inserted == ["你好"], "\(rig.inserted)")
        #expect(rig.c.draft.isEmpty)
        rig.key(enterKey)
        #expect(rig.starts.isEmpty)
    }

    /// A draft that is in the target language all the same (letters picked as they are): ⏎ inserts it as typed.
    @Test func same_aDraftAlreadyInTheTargetGoesInAsTypedAtEnter() {
        let rig = TMAccRig(target: .english)
        rig.type("hello")
        rig.key(spaceKey)  // no such pinyin: the letters as typed
        #expect(rig.inserted.isEmpty || rig.inserted == ["hello"], "\(rig.inserted)")
        rig.key(enterKey)
        #expect(rig.starts.isEmpty, "\(rig.starts.map(\.input))")
        #expect(rig.inserted.joined() == "hello", "\(rig.inserted)")
    }

    // where

    @Test func where_inANoAIAppTextGoesInAsTypedWithANotice() {
        let rig = drafted()
        rig.noAI = "AI is off in this app"
        let enter = rig.key(enterKey)
        #expect(TMAccRig.starts(enter.effects).isEmpty, "nothing sent")
        #expect(rig.inserted == ["你好"], "\(rig.inserted)")
        #expect(!TMAccRig.notices(enter.effects).isEmpty, "with a notice: \(enter.effects)")
        #expect(rig.passedThrough.isEmpty)
    }

    @Test func where_inANoAIAppNothingIsSentToTheModel() async {
        let wire = TMAccWire { $0.appProfiles = ["com.example.bank": AppProfile(noAI: true)] }
        let out = await wire.mode("我的账号是 12345", app: "com.example.bank")
        #expect(out.error != nil, "refused")
        #expect(out.updates.allSatisfy { $0.result.isEmpty })
        #expect(wire.requestCount == 0)
        // Another app of the same settings does send.
        let elsewhere = await wire.mode("你好", app: tmTextEdit)
        #expect(elsewhere.error == nil)
        #expect(wire.requestCount == 1)
    }

    @Test func where_underSecureInputTextGoesInAsTyped() {
        let rig = TMAccRig(target: .english)
        rig.secure = true
        rig.pick("nihao")
        #expect(rig.inserted == ["你好"], "\(rig.inserted)")
        #expect(rig.c.draft.isEmpty)
        rig.key(enterKey)
        #expect(rig.starts.isEmpty)
        // Secure input off again: it collects again.
        rig.secure = false
        rig.pick("wo")
        #expect(rig.c.draft == "我")
    }

    // end to end

    @Test func keys_endToEndEnterSendsTheDraftAndInsertsTheTranslation() async {
        let rig = drafted()
        let wire = TMAccWire()
        rig.wire = wire
        TMAccStub.enqueue(wire.host, .answer("EN: Hello there."))
        rig.key(enterKey)
        await rig.runRequests()
        #expect(wire.requests.count == 1)
        #expect(wire.requests.first?.lastUser == "你好")
        #expect(rig.inserted == ["Hello there."], "\(rig.inserted)")
        #expect(rig.c.draft.isEmpty && rig.c.choices.isEmpty)
        #expect(rig.passedThrough.isEmpty)
    }

    @Test func fail_endToEndAFailedRequestKeepsTheDraftAndARetryInserts() async {
        let rig = drafted()
        let wire = TMAccWire()
        rig.wire = wire
        TMAccStub.enqueue(wire.host, .status(500), .answer("EN: Hello."))
        rig.key(enterKey)
        await rig.runRequests()
        #expect(rig.c.draft == "你好")
        #expect(rig.inserted.isEmpty)
        #expect(rig.notices.count == 1 && rig.notices.allSatisfy { !$0.contains("\n") }, "\(rig.notices)")
        rig.key(enterKey)
        await rig.runRequests()
        #expect(wire.requestCount == 2)
        #expect(rig.inserted == ["Hello."], "\(rig.inserted)")
    }
}

// MARK: - The target language

@Suite("TranslateModeAcceptance: the target language")
struct TranslateModeAcceptanceTargetTests {
    @Test func target_beforeAnyPickItIsTheFirstOutputLanguageTheTypedLanguageCanBeTranslatedInto() throws {
        #expect(TranslateMode.target(last: nil, outputs: [tmJapanese, .english]) == tmJapanese)
        var state = TranslateMode.State()
        let entered = state.enter(last: nil, config: tmConfig([tmJapanese, .english]))
        let session = try #require(entered)
        #expect(session.target == tmJapanese)
        #expect(state.isOn)
        // English alone typed, English first among the outputs: the first output it can translate into (spec, 0.6.5.1).
        var other = TranslateMode.State()
        #expect(other.enter(last: nil, config: tmConfig([.english, .chinese]))?.target == .chinese)
        // Chinese and English typed: the first output, as before.
        var bilingual = TranslateMode.State()
        #expect(bilingual.enter(last: nil, config: tmConfig([.english, .chinese]) { $0.inputLanguages = [.chinese, .english] })?.target == .english)
    }

    @Test func target_theLastPickIsRemembered() throws {
        let config = tmConfig([tmJapanese, .english, tmFrench])
        // Turned on again later (or after a restart: a new state), with the language picked last.
        var state = TranslateMode.State()
        #expect(state.enter(last: tmFrench, config: config)?.target == tmFrench)
        state.leave()
        #expect(!state.isOn)
        #expect(state.enter(last: tmFrench, config: config)?.target == tmFrench)
        var afterRestart = TranslateMode.State()
        #expect(afterRestart.enter(last: tmFrench, config: config)?.target == tmFrench)
        // In another app that translates always, too.
        var configAlways = config
        configAlways.appProfiles = [tmSlack: AppProfile(translateAlways: true)]
        var elsewhere = TranslateMode.State()
        _ = elsewhere.activated(app: tmTextEdit, last: tmFrench, config: configAlways)
        #expect(elsewhere.activated(app: tmSlack, last: tmFrench, config: configAlways) == .entered(TranslateMode.Session(target: tmFrench)))
    }

    @Test func target_aPickNoLongerAnOutputLanguageFallsBackToTheFirst() {
        #expect(TranslateMode.target(last: tmKorean, outputs: [tmJapanese, .english]) == tmJapanese)
        var state = TranslateMode.State()
        #expect(state.enter(last: tmKorean, config: tmConfig([tmJapanese, .english]))?.target == tmJapanese)
    }

    @Test func target_theInputLanguageNeverChangesIt() {
        // Typing Chinese with Chinese first among the outputs: still Chinese (what is typed in it goes in as typed).
        let config = tmConfig([.chinese, .english])
        for typing in [Language.chinese, .english] {
            let rig = TMAccRig(english: typing == .english, target: nil)
            #expect(rig.c.inputLanguage == typing)
            var state = TranslateMode.State()
            let session = state.enter(last: nil, config: config)
            #expect(session?.target == .chinese, "typing \(typing)")
            rig.setMode(session?.target)
            #expect(rig.c.translateMode?.target == .chinese)
            #expect(rig.c.translateModeChip()?.target == .chinese)
            var picked = TranslateMode.State()
            #expect(picked.enter(last: .english, config: config)?.target == .english, "typing \(typing)")
        }
    }

    /// The language picked last is kept in the input method's defaults under `translateModeTarget` (the app target: read
    /// from its source, Core can't reach it).
    @Test func ui_theLastPickIsKeptUnderItsDefaultsKey() throws {
        let source = try TMAccSource.app()
        #expect(source.contains("\"translateModeTarget\""))
    }
}

// MARK: - The chip

@Suite("TranslateModeAcceptance: the chip")
struct TranslateModeAcceptanceChipTests {
    @Test func chip_namesTheSourceAndTheTarget() throws {
        let rig = TMAccRig(target: .english)
        let chip = try #require(rig.c.translateModeChip())
        #expect(chip.text == "中 → 英")
        #expect(chip.sourceText == "中" && chip.targetText == "英")
        #expect(chip.source == .chinese && chip.target == .english)
        let japaneseRig = TMAccRig(english: true, target: tmJapanese)
        #expect(japaneseRig.c.translateModeChip()?.text == "英 → 日")
    }

    @Test func chip_onlyWhileTheModeIsOn() {
        let rig = TMAccRig(target: nil)
        #expect(rig.c.translateModeChip() == nil)
        rig.setMode(.english)
        #expect(rig.c.translateModeChip() != nil)
        rig.setMode(nil)
        #expect(rig.c.translateModeChip() == nil)
    }

    @Test func chip_itsSourcePartSwitchesTheInputLanguageAsATapOfShiftDoes() throws {
        let rig = TMAccRig(target: tmJapanese)
        let clicked = rig.c.shiftTapped()
        rig.record(clicked)
        #expect(rig.languageChanges == [.english])
        #expect(rig.c.inputLanguage == .english)
        #expect(try #require(rig.c.translateModeChip()).text == "英 → 日")
        // The same as a tap of Shift in a twin field.
        let twin = TMAccRig(target: tmJapanese)
        _ = twin.c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 0)
        let tapped = twin.c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 0.1)
        #expect(clicked == tapped)
        // Again: back to Chinese.
        rig.record(rig.c.shiftTapped())
        #expect(rig.c.inputLanguage == .chinese)
        #expect(rig.c.translateModeChip()?.text == "中 → 日")
    }

    @Test func chip_itsTargetPartListsTheOutputLanguagesTheCurrentOneChecked() throws {
        let outputs = [OutputLanguage.english, tmJapanese, tmFrench]
        let rig = TMAccRig(target: tmJapanese)
        let chip = try #require(rig.c.translateModeChip(choices: outputs))
        #expect(chip.choices == outputs)
        #expect(outputs.filter(chip.checks) == [tmJapanese])
        #expect(chip.choice(at: 2) == tmFrench)
        #expect(rig.c.translateModeChip()?.choices == nil, "no list unless its target part was clicked")
    }

    @Test func chip_aLanguageClickedIsTheTargetAtOnceAndRemembered() throws {
        // Chinese and English typed (pinyin below): the first output, English, until Japanese is clicked.
        let config = tmConfig([.english, tmJapanese, tmFrench]) { $0.inputLanguages = [.chinese, .english] }
        var state = TranslateMode.State()
        let rig = TMAccRig(target: nil)
        let entered = state.enter(last: nil, config: config)
        #expect(entered?.target == .english)
        rig.setMode(try #require(entered).target)
        rig.pick("nihao")
        // The target part clicked, then Japanese in its list (as the controller does with the row clicked).
        let chip = try #require(rig.c.translateModeChip(choices: config.outputLanguages))
        let picked = try #require(chip.choice(at: 1))
        #expect(picked == tmJapanese)
        let retargeted = state.retarget(picked)
        let session = try #require(retargeted)
        let changed = rig.c.setTranslateMode(session)
        rig.record(changed)
        #expect(rig.c.draft == "你好" && rig.inserted.isEmpty, "the draft stays")
        #expect(rig.c.translateModeChip()?.text == "中 → 日", "the chip at once")
        #expect(rig.c.translateModeChip(choices: config.outputLanguages).map { config.outputLanguages.filter($0.checks) } == [tmJapanese])
        rig.key(enterKey)
        #expect(rig.lastStart?.target == tmJapanese, "the next translation")
        // Remembered: turned on again (anywhere, later), it's the one picked.
        state.leave()
        #expect(state.enter(last: picked, config: config)?.target == tmJapanese)
    }
}

// MARK: - Tone

@Suite("TranslateModeAcceptance: the tone")
struct TranslateModeAcceptanceToneTests {
    static let chat = ["com.tencent.xinWeChat", "com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "ru.keepcoder.Telegram",
                       "com.hnc.Discord", "com.microsoft.teams2"]
    static let mailApps = ["com.apple.mail", "com.microsoft.Outlook", "com.readdle.SparkDesktop"]
    static let others: [String?] = ["com.apple.TextEdit", "com.apple.Notes", "com.google.Chrome", "com.microsoft.VSCode", nil]

    @Test func tone_byTheKindOfApp() {
        let config = Config.default
        for app in Self.chat { #expect(TranslateMode.tone(app: app, config: config) == .casual, "\(app)") }
        for app in Self.mailApps { #expect(TranslateMode.tone(app: app, config: config) == .formal, "\(app)") }
        for app in Self.others { #expect(TranslateMode.tone(app: app, config: config) == .natural, "\(app ?? "nil")") }
    }

    @Test func tone_theAppsOwnRewriteStyleComesFirst() {
        var config = Config.default
        config.appProfiles = [
            tmSlack: AppProfile(rewriteStyles: ["正式"]),
            tmMail: AppProfile(rewriteStyles: ["口语"]),
            tmTextEdit: AppProfile(rewriteStyles: ["简洁"]),
            "com.apple.Notes": AppProfile(rewriteStyles: []),
            "com.tencent.xinWeChat": AppProfile(typeOut: true),
        ]
        #expect(TranslateMode.tone(app: tmSlack, config: config) == .formal)
        #expect(TranslateMode.tone(app: tmMail, config: config) == .casual)
        #expect(TranslateMode.tone(app: tmTextEdit, config: config) == .concise)
        // A profile without a style of its own: by the kind of app.
        #expect(TranslateMode.tone(app: "com.apple.Notes", config: config) == .natural)
        #expect(TranslateMode.tone(app: "com.tencent.xinWeChat", config: config) == .casual)
        // The style written by its tag, and the bundle id in another case.
        config.appProfiles = ["COM.TINYSPECK.SLACKMACGAP": AppProfile(rewriteStyles: ["FORMAL"])]
        #expect(TranslateMode.tone(app: tmSlack, config: config) == .formal)
    }

    /// The tone reaches what is sent: the same instructions for apps of one tone, others for another.
    @Test func tone_reachesTheRequest() async throws {
        func system(_ app: String?, configure: @escaping (inout Config) -> Void = { _ in }) async throws -> String {
            let wire = TMAccWire(configure: configure)
            _ = await wire.mode("明天下午三点开会", app: app)
            return try #require(wire.requests.first, "\(app ?? "nil")").system
        }
        let casual = try await system(tmSlack), formal = try await system(tmMail), natural = try await system(tmTextEdit)
        #expect(casual != formal && formal != natural && casual != natural)
        #expect(try await system("com.hnc.Discord") == casual)
        #expect(try await system("com.microsoft.Outlook") == formal)
        #expect(try await system(nil) == natural)
        #expect(casual.lowercased().contains("casual"), "\(casual)")
        #expect(formal.lowercased().contains("formal"), "\(formal)")
        // Slack with a formal style of its own is written as for mail.
        let styled = try await system(tmSlack) { $0.appProfiles = [tmSlack: AppProfile(rewriteStyles: ["正式"])] }
        #expect(styled == formal)
    }
}

// MARK: - Switching apps

@Suite("TranslateModeAcceptance: apps")
struct TranslateModeAcceptanceAppTests {
    @Test func apps_switchingToAnotherAppTurnsTheModeOffWithoutANotice() throws {
        let config = tmConfig([.english, tmJapanese])
        var state = TranslateMode.State()
        #expect(state.activated(app: tmTextEdit, last: nil, config: config) == .unchanged)
        let entered = state.enter(last: nil, config: config)
        let session = try #require(entered)
        let rig = TMAccRig(target: nil)
        rig.setMode(session.target)
        // Another field of the same app: still on.
        #expect(state.activated(app: tmTextEdit, last: nil, config: config) == .unchanged)
        #expect(state.isOn)
        // Another app: off.
        #expect(state.activated(app: tmSlack, last: nil, config: config) == .left(session))
        #expect(!state.isOn && state.session == nil)
        let off = rig.setMode(nil)
        #expect(TMAccRig.notices(off).isEmpty, "no notice: \(off)")
        #expect(rig.c.translateMode == nil && rig.c.translateModeChip() == nil)
        // Back in the first app: still off.
        #expect(state.activated(app: tmTextEdit, last: nil, config: config) == .unchanged)
        #expect(!state.isOn)
    }

    @Test func apps_anAppThatTranslatesAlwaysTurnsItOnThere() throws {
        let json = #"{"appProfiles":{"com.tinyspeck.slackmacgap":{"translateAlways":true}},"outputLanguages":["ja","en"],"outputLanguage":"ja"}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.profile(for: tmSlack)?.translateAlways == true)
        #expect(config.outputLanguages.first == tmJapanese)
        var state = TranslateMode.State()
        _ = state.activated(app: tmTextEdit, last: nil, config: config)
        #expect(!state.isOn)
        #expect(state.activated(app: tmSlack, last: nil, config: config) == .entered(TranslateMode.Session(target: tmJapanese)))
        #expect(state.isOn)
        // Leaving it for an app that doesn't: off.
        #expect(state.activated(app: tmTextEdit, last: nil, config: config) == .left(TranslateMode.Session(target: tmJapanese)))
        // Already on when switching to it: stays on, into what it was.
        var on = TranslateMode.State()
        _ = on.activated(app: tmTextEdit, last: nil, config: config)
        _ = on.enter(last: .english, config: config)
        _ = on.activated(app: "COM.TinySpeck.SlackMacGap", last: .english, config: config)
        #expect(on.isOn && on.session?.target == .english)
        // The first field of the input method's life in it, too.
        var fresh = TranslateMode.State()
        #expect(fresh.activated(app: tmSlack, last: .english, config: config) == .entered(TranslateMode.Session(target: .english)))
    }

    @Test func apps_translateAlwaysIsKeptInTheConfigFile() throws {
        var config = Config.default
        config.appProfiles = [tmSlack: AppProfile(translateAlways: true)]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(config), as: UTF8.self)
        #expect(text.contains(#""com.tinyspeck.slackmacgap":{"translateAlways":true}"#), "\(text)")
        let back = try JSONDecoder().decode(Config.self, from: Data(text.utf8))
        #expect(back.profile(for: tmSlack)?.translateAlways == true)
        #expect(!AppProfile(translateAlways: true).isEmpty)
    }

    /// Settings → Apps names it (the app target: read from its source).
    @Test func ui_settingsNameTheSwitch() throws {
        let source = try TMAccSource.app()
        #expect(source.contains("总是边打边译"))
        #expect(source.contains("Always Translate as You Type"))
    }
}

// MARK: - Privacy and prompts

@Suite("TranslateModeAcceptance: privacy and prompts")
struct TranslateModeAcceptancePrivacyTests {
    static let secret = "alice.wong@example.com"
    static let input = "请把合同发到 alice.wong@example.com 谢谢"

    @Test func privacy_redactionAppliesAsForTranslate() async throws {
        let wire = TMAccWire { $0.redaction = RedactionSettings(enabled: true) }
        TMAccStub.enqueue(wire.host, .answer("EN: Please send the contract to [EMAIL_1], thanks."))
        let out = await wire.mode(Self.input)
        #expect(out.error == nil)
        let sent = try #require(wire.requests.first)
        #expect(!sent.body.contains(Self.secret), "the value hidden from the model")
        #expect(sent.lastUser.contains("[EMAIL_1]"), "\(sent.lastUser)")
        #expect(sent.system.hasSuffix(Redaction.note), "the placeholder note, as for @translate")
        // Put back in what goes in.
        let final = try #require(out.updates.last { $0.isFinal })
        #expect(final.hidden == 1)
        let line = final.result.translations.first?.line.text ?? final.result.versions.first?.text ?? ""
        #expect(line == "Please send the contract to \(Self.secret), thanks.", "\(line)")
        // @translate on the same text hides it the same way.
        let translate = TMAccWire { $0.redaction = RedactionSettings(enabled: true) }
        _ = await TMAccWire.drain(translate.converter.convert(Self.input, mode: .translate))
        let sentByTranslate = try #require(translate.requests.first)
        #expect(!sentByTranslate.body.contains(Self.secret))
        #expect(sentByTranslate.lastUser == sent.lastUser)
        #expect(sentByTranslate.system.hasSuffix(Redaction.note))
    }

    @Test func privacy_withHidingOffTheTextIsSentAsTyped() async throws {
        let wire = TMAccWire()
        _ = await wire.mode(Self.input)
        let sent = try #require(wire.requests.first)
        #expect(sent.lastUser == Self.input)
        #expect(!sent.system.contains(Redaction.note))
    }

    @Test func privacy_customWordsAreHiddenToo() async throws {
        let wire = TMAccWire { $0.redaction = RedactionSettings(enabled: true, customWords: ["Project Falcon"]) }
        _ = await wire.mode("Project Falcon 下周上线")
        let sent = try #require(wire.requests.first)
        #expect(!sent.body.contains("Project Falcon"), "\(sent.body)")
    }

    /// Its request is its own: the mode's instructions aren't any existing request's.
    @Test func privacy_theModeHasAPromptOfItsOwn() {
        let config = Config.default
        let mode = Prompt.translateModeRequest(for: "你好", target: .english, tone: .natural, config: config)
        for writing in [WritingMode.improve, .translate, .both] {
            let existing = Prompt.request(for: "你好", mode: writing, config: config)
            #expect(mode.system != existing.system, "\(writing)")
        }
        #expect(mode.messages.last?.content.map(\.text).joined() == "你好")
    }

    /// Every existing prompt is byte-identical to release 0.6.3's (the goldens the other acceptance tests use).
    @Test func privacy_existingPromptsAreByteIdenticalTo063() throws {
        let groups = AcceptanceGolden.groups()
        #expect(groups.count == AcceptanceGolden.golden063.count)
        for (name, text) in groups {
            let golden = try #require(AcceptanceGolden.golden063[name], "no golden for \(name)")
            // 0.6.4's live-data rule is in @question's requests only, once each (`AcceptanceLiveRule`).
            var compared = text
            if name.hasSuffix("/commands") {
                let questions = AcceptanceGolden.commands().map { $0.1 == .question }
                let requests = text.components(separatedBy: "\n----\n")
                #expect(requests.count == questions.count, "\(name)")
                compared = zip(requests, questions).map { AcceptanceLiveRule.strip($0, question: $1) }.joined(separator: "\n----\n")
            }
            for added in AcceptanceGolden.addedSince063[name] ?? [] {
                #expect(text.components(separatedBy: added).count == 2, "\(name) lacks \(added)")
                compared = compared.replacingOccurrences(of: added, with: "")
            }
            #expect(AcceptanceGolden.sha256(compared) == golden, "\(name) differs from 0.6.3")
        }
    }

    /// An app that translates always sends the same existing requests as one without a profile.
    @Test func privacy_translateAlwaysLeavesTheAppsExistingRequestsAlone() async throws {
        var config = Config.default
        config.appProfiles = [tmSlack: AppProfile(translateAlways: true)]
        for mode in [WritingMode.improve, .translate, .both] {
            #expect(Prompt.request(for: "我今天有点不舒服", mode: mode, config: config.applying(app: tmSlack))
                == Prompt.request(for: "我今天有点不舒服", mode: mode, config: Config.default), "\(mode)")
        }
        for (_, command, input) in AcceptanceGolden.commands() {
            #expect(Prompt.commandRequest(command, input: input, config: config.applying(app: tmSlack))
                == Prompt.commandRequest(command, input: input, config: Config.default), "\(command.name)")
        }
        // Over the wire as well: @translate in it.
        let always = TMAccWire { $0.appProfiles = [tmSlack: AppProfile(translateAlways: true)] }
        let plain = TMAccWire()
        _ = await TMAccWire.drain(always.converter.convert("我今天有点不舒服", mode: .translate, app: tmSlack))
        _ = await TMAccWire.drain(plain.converter.convert("我今天有点不舒服", mode: .translate, app: tmSlack))
        let a = try #require(always.requests.first), b = try #require(plain.requests.first)
        #expect(a.raw == b.raw)
    }
}

// MARK: - No commands

@Suite("TranslateModeAcceptance: no commands")
struct TranslateModeAcceptanceCommandTests {
    @Test func cmd_noModeOrExitCommand() {
        for list in [Command.builtins, Command.catalog([])] {
            let names = Set(list.map(\.name))
            #expect(!names.contains("mode") && !names.contains("exit"), "\(names.sorted())")
        }
        // Typed in the mode: nothing to pick, and the mode stays on.
        for name in ["mode", "exit"] {
            let rig = TMAccRig(english: true, target: tmJapanese)
            rig.key(tmAt)
            rig.type(name)
            #expect(!rig.c.paletteMatches.contains { $0.name == name }, "\(rig.c.paletteMatches.map(\.name))")
            rig.key(enterKey)
            #expect(rig.c.translateMode?.target == tmJapanese, "@\(name) doesn't turn it off")
        }
    }
}

// MARK: - The app's wording (not in Core: read from the app target's source)

enum TMAccSource {
    /// Every Swift file of the input method's app target, joined.
    static func app() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("Sources/AllInOneIME")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!files.isEmpty, "no sources at \(folder.path)")
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }
}

@Suite("TranslateModeAcceptance: the app's wording")
struct TranslateModeAcceptanceWordingTests {
    @Test func ui_theHintAndTheNotices() throws {
        let source = try TMAccSource.app()
        for text in [
            "继续按住 → 边打边译", "继续按住 → 关闭边打边译", "Keep holding → Translate as You Type",
            "边打边译 已开启：", " · 再长按 Shift 关闭", "边打边译 已关闭",
            "Translate as You Type on: ", " · hold Shift again to turn off", "Translate as You Type off",
        ] {
            #expect(source.contains(text), "\(text)")
        }
    }
}

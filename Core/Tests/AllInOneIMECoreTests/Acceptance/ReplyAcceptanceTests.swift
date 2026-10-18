import CoreGraphics
import Foundation
import os
import Testing
@testable import AllInOneIMECore

// Acceptance tests for "Screenshot context and @reply" (0.6.5/reply), written from the spec only, independently of the
// implementation's own tests. Each test is one of the spec's core scenarios ("s4" = S4). What the input controller
// does (it lives in the app target, which these tests can't load) is played as the spec says it does: ⌃V's clipboard
// is handed to `pasted(_:id:)` as a `ClipboardContent`, `.recognizeText` is answered by running `ScreenText.recognize`
// with a fake `TextRecognizer` and handing the result to `recognized(_:id:)`, and requests go through the real
// `Converter` to a recording URL protocol (a Claude API endpoint), so what was sent is read back, not assumed. The
// macOS self-tests (Vision, the pasteboard, IMK, Chrome, the rename notice) are app-target behaviour and aren't here.
//
// ASSUMPTIONS (API details the spec leaves open; the narrowest reading, for the implementation to match):
//  1. `Command.reply` is a static built-in command (name "reply", kind `.generate`) in `Command.builtins`; the start
//     effect is `.startCommand(.reply, input: Prompt.replyMessage(context), id:)`.
//  2. `Config.freeBuiltinNames()` is `mutating`, renames in `customCommands` in place (order and every other field
//     kept) and returns `[(old: String, new: String)]`, one pair per rename, in config order; nothing to do: `[]`.
//  3. `RecognizedLine` (top level, Sendable) has a public `init(text:box:confidence:)`; `box` is 0…1 with a top-left
//     origin. `UnsupportedTextRecognizer` has a public `init()`.
//  4. `ScreenText.recognize(_ image: Data, with: any TextRecognizer, languages: [String]) async throws -> ScreenText`
//     is static; it throws `ScreenText.Problem` (Error, Equatable) with the cases `.unsupported` (the recognizer can't
//     read images) and `.noText` (it found no line). `ScreenText.languages(_ config: Config) -> [String]` gives
//     recognizer language codes ("zh-Hans", "en-US", the output languages' codes, e.g. "ja…").
//  5. `ClipboardContent` has `.text(String)`, `.image(Data)`, `.none`, and the composer's new
//     `pasted(_ content: ClipboardContent, id: Int) -> [Effect]` takes it (written with a leading dot here, so it may
//     be nested in `Composer` or not). Text pasted into `@reply` longer than 4,000 characters is cut to at most 4,000
//     (a cap, as for the other layers), not refused.
//  6. `Composer.Effect.recognizeText(image: Data, id: Int)`.
//  7. `Composer.attachment` is optional (nil: none), an enum with `.screenshot(_)` and `.copiedText(String)`; the
//     screenshot's state has `.recognizing` and `.ready(_)` (its payload isn't looked at here).
//  8. `Composer.recognized(_ text: ScreenText?, id: Int) -> [Effect]` and
//     `Composer.recognitionFailed(_ message: String, id: Int) -> [Effect]`; for an id that isn't the latest
//     recognition's, both do nothing (no effects that start anything, the attachment as it was).
//  9. `Composer.readFieldText: () -> FieldText?` (default: nil) with `FieldText(before: String, after: String)`
//     (written `.init(before:after:)` here, so `FieldText` may be nested or not), and
//     `Composer.pageContextApplies: () -> Bool` (default: false).
// 10. `Composer.Messages` gains `replyHint` and `screenshotUnused`, shown as `.notice(messages.replyHint)` /
//     `.notice(messages.screenshotUnused)`.
// 11. The composer learns the provider in use (for the 1,500-character screenshot cap of `Provider.apple`) from a new
//     `Composer.provider: Provider`, set by the controller from the config; its default is not `.apple`.
// 12. `ReplyParser.parse(_ text: String, isFinal: Bool) -> [CandidateLine]`: the replies between lines holding only
//     "---", each trimmed of the blank space at its ends (its own line breaks kept), empty ones dropped, at most 3;
//     every one complete except, while the text is still streaming (`isFinal` false), the last one. The converter's
//     `.reply` result has them as its `versions`.
// 13. `Prompt.replySystem(tone:appClass:) -> String` takes the tone `TranslateMode.tone(app:config:)` returns and the
//     app class `AppClass(app:)` makes (cases `.chat`, `.mail`), and the system prompt `Converter.generate(.reply, …)`
//     sends contains it. `Prompt.withScreenshot(_ typed: String, _ text: String) -> String`.
// 14. In the request a speaker's line of the transcript starts with "them:" or "me:" (after any leading whitespace or
//     opening tag); an unlabelled transcript has no line starting so. Field text is inside an XML-style tag of any name.
// 15. The screenshot's text reaches other commands once `recognized` has been given it: AI commands use it at the action
//     key, `@note` gets it pasted into its draft (lines kept). The `screenshotUnused` notice comes with `recognized`'s
//     or the action key's effects.
// 16. ⌘R is `KeyEvent(characters: "r", modifiers: .command)`; its refine's request is `.command(.reply, input:)` with
//     the input first sent, its last turn's instruction "Write three different replies.".

// MARK: - Keys and test data

fileprivate let accAt = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
fileprivate let accTab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
fileprivate let accControlV = KeyEvent(keyCode: 0x09, characters: "\u{16}", charactersIgnoringModifiers: "v",
                                       modifiers: .control)
fileprivate let accCommandR = k("r", mods: .command)
/// An image's bytes as the clipboard gives them (the composer never decodes them).
fileprivate let accPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48])

// MARK: - Fakes

/// A recognizer that "reads" the lines it was made with, whatever the image.
fileprivate final class ReplyAccRecognizer: TextRecognizer, @unchecked Sendable {
    let lines: [RecognizedLine]
    init(_ lines: [RecognizedLine]) { self.lines = lines }
    func prepare() async {}
    func recognize(image: Data, languages: [String]) async throws -> [RecognizedLine] { lines }
}

/// Japanese for a text with kana in it, else Simplified Chinese, always as sure as `confidence`.
fileprivate struct ReplyAccLanguages: LanguageIdentifier {
    var confidence: Double
    func dominantLanguage(of text: String, among candidates: [String]) -> (code: String, confidence: Double)? {
        let kana = text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
        return (kana ? "ja" : "zh-Hans", confidence)
    }
}

/// A Claude API endpoint: answers each host with the text queued for it (streamed), and keeps every request body.
fileprivate final class ReplyAccRecorder: URLProtocol, @unchecked Sendable {
    private struct State {
        var answers: [String: [String]] = [:]
        var bodies: [String: [Data]] = [:]
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func answer(_ host: String, _ text: String) { state.withLock { $0.answers[host, default: []].append(text) } }
    static func bodies(_ host: String) -> [Data] { state.withLock { $0.bodies[host] ?? [] } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReplyAccRecorder.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        let host = request.url?.host ?? ""
        let sent = body
        let answer = Self.state.withLock { state -> String? in
            state.bodies[host, default: []].append(sent)
            guard var queue = state.answers[host], !queue.isEmpty else { return nil }
            let next = queue.removeFirst()
            state.answers[host] = queue
            return next
        }
        guard let url = request.url else { return }
        guard let answer else {
            let http = HTTPURLResponse(url: url, statusCode: 500, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"type":"error","error":{"type":"api_error","message":"no answer"}}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let delta = try! JSONSerialization.data(withJSONObject: [
            "type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": answer],
        ] as [String: Any])
        let sse = [
            "event: message_start", #"data: {"type":"message_start","message":{"id":"msg_1"}}"#, "",
            "event: content_block_delta", "data: " + String(decoding: delta, as: UTF8.self), "",
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#, "",
            #"data: {"type":"message_stop"}"#, "", "",
        ].joined(separator: "\n")
        let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(sse.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

fileprivate enum ReplyAcc {
    static let wechat = "com.tencent.xinwechat"
    static let mail = "com.apple.mail"
    static let bank = "com.example.bank"

    /// A line of the screenshot; `x`, `y`, `width`, `height` in 0…1, top-left origin.
    static func line(_ text: String, x: Double, y: Double, width: Double, height: Double = 0.03) -> RecognizedLine {
        RecognizedLine(text: text, box: CGRect(x: x, y: y, width: width, height: height), confidence: 0.95)
    }

    /// The other party's bubble: on the left (minX < 0.30, midX < 0.5).
    static func them(_ text: String, y: Double, height: Double = 0.03) -> RecognizedLine {
        line(text, x: 0.05, y: y, width: 0.35, height: height)
    }

    /// The user's own bubble: on the right (maxX > 0.70, midX > 0.5).
    static func me(_ text: String, y: Double) -> RecognizedLine { line(text, x: 0.60, y: y, width: 0.35) }

    /// A short line in the middle (a time between the messages).
    static func centred(_ text: String, y: Double) -> RecognizedLine { line(text, x: 0.46, y: y, width: 0.08, height: 0.02) }

    static func clipboardID(_ effects: [Composer.Effect]) -> Int? {
        for effect in effects { if case let .readClipboard(id) = effect { return id } }
        return nil
    }

    static func recognition(_ effects: [Composer.Effect]) -> (image: Data, id: Int)? {
        for effect in effects { if case let .recognizeText(image, id) = effect { return (image, id) } }
        return nil
    }

    static func replyStart(_ effects: [Composer.Effect]) -> (input: String, id: Int)? {
        for effect in effects {
            if case let .startCommand(command, input, id) = effect, command == .reply { return (input, id) }
        }
        return nil
    }

    static func refine(_ effects: [Composer.Effect]) -> (refinement: Refinement, id: Int)? {
        for effect in effects { if case let .startRefine(refinement, id) = effect { return (refinement, id) } }
        return nil
    }

    /// The inputs of every model request `effects` start.
    static func requestInputs(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { effect in
            switch effect {
            case let .startConversion(input, _), let .startCommand(_, input, _): return input
            default: return nil
            }
        }
    }

    /// Whether `effects` start anything at all.
    static func startsAnything(_ effects: [Composer.Effect]) -> Bool {
        effects.contains { effect in
            switch effect {
            case .startConversion, .startCommand, .startRefine, .startPlan, .startRun, .startScript, .runInTerminal,
                 .startBackgroundAgent, .saveNote: return true
            default: return false
            }
        }
    }

    static func notices(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .notice(s) = $0 { return s } else { return nil } }
    }

    static func notes(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .saveNote(text) = $0 { return text } else { return nil } }
    }

    static func replies(_ texts: String...) -> ConversionResult {
        ConversionResult(versions: texts.map { CandidateLine($0) })
    }

    /// Each line of `text`, without leading whitespace and opening tags ("<screenshot>them: …" → "them: …").
    static func contentLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { line in
            var rest = Substring(line).drop { $0.isWhitespace }
            while rest.hasPrefix("<"), !rest.hasPrefix("</"), let end = rest.firstIndex(of: ">") {
                rest = rest[rest.index(after: end)...].drop { $0.isWhitespace }
            }
            return String(rest)
        }
    }

    static func labelled(_ input: String, _ label: String, _ text: String) -> Bool {
        contentLines(input).contains { $0.hasPrefix(label + ":") && $0.contains(text) }
    }

    static func hasSpeakerLabels(_ input: String) -> Bool {
        contentLines(input).contains { $0.hasPrefix("them:") || $0.hasPrefix("me:") }
    }

    /// Whether `text` sits inside an XML-style tag in `input`: `<name …>` before it, its `</name>` after it, and no
    /// `</name>` between the two.
    static func inTag(_ text: String, _ input: String) -> Bool {
        guard let found = input.range(of: text) else { return false }
        let before = input[..<found.lowerBound]
        let after = input[found.upperBound...]
        let regex = try! NSRegularExpression(pattern: "<([A-Za-z_][A-Za-z0-9_]*)[^<>/]*>")
        let ns = String(before) as NSString
        for match in regex.matches(in: String(before), range: NSRange(location: 0, length: ns.length)).reversed() {
            let name = ns.substring(with: match.range(at: 1))
            let opened = ns.substring(from: match.range.location + match.range.length)
            if !opened.contains("</\(name)>"), after.contains("</\(name)>") { return true }
        }
        return false
    }

    static func count(_ character: Character, in text: String) -> Int { text.reduce(0) { $1 == character ? $0 + 1 : $0 } }

    // MARK: Sending through the converter

    static func newHost() -> String { "h\(UUID().uuidString.lowercased().prefix(12)).reply-acc.test" }

    static func converter(_ config: Config, host: String) -> Converter {
        var config = config
        config.provider = .anthropic
        config.anthropic.baseURL = "https://\(host)"
        config.anthropic.model = "claude-test"
        let fixed = config
        return Converter(client: BedrockClient(session: ReplyAccRecorder.session()), loadConfig: { fixed },
                         loadCredentials: { _ in throw ProviderError.missingKey(.anthropic) },
                         loadKey: { _, _ in "sk-test" }, loadJargon: { _ in [] })
    }

    /// `@reply`'s request for `input` in `app`, answered with `answer`: the bodies sent, the final result, the error.
    static func generate(_ config: Config, input: String, app: String?, answer: String) async
        -> (bodies: [Data], final: ConversionResult?, error: Error?) {
        let host = newHost()
        ReplyAccRecorder.answer(host, answer)
        var final: ConversionResult?
        var failure: Error?
        do {
            for try await update in converter(config, host: host).generate(.reply, input: input, app: app)
            where update.isFinal { final = update.result }
        } catch {
            failure = error
        }
        return (ReplyAccRecorder.bodies(host), final, failure)
    }

    /// The system prompt of a Claude API body (a string, or blocks of text).
    static func system(of body: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return "" }
        if let text = json["system"] as? String { return text }
        let blocks = json["system"] as? [[String: Any]] ?? []
        return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    static func text(of body: Data) -> String { String(decoding: body, as: UTF8.self) }
}

/// A text field with a composer as the controller sets it up (a fake pinyin engine, ⏎ the action key).
fileprivate final class ReplyAccRig {
    let engine = FakeEngine()
    let c: Composer
    /// Every effect the composer returned, in order.
    var effects: [Composer.Effect] = []

    init(english: Bool = false, selection: Composer.Selection? = nil) {
        engine.dictionary["weiwanjujue"] = ["委婉拒绝"]
        c = Composer(engine: engine, actionKey: .enter)
        c.inputLanguages = [.chinese, .english]
        if let selection { c.readSelection = { selection } }
        if english { c.setInputMode(.english) }
    }

    @discardableResult
    func key(_ event: KeyEvent) -> [Composer.Effect] {
        let out = c.handleKeyDown(event).effects
        effects += out
        return out
    }

    /// Each character as a key ("@" and Space as their keys).
    func type(_ text: String) {
        for ch in text { key(ch == "@" ? accAt : ch == " " ? spaceKey : k(String(ch))) }
    }

    /// "@", the command's name, Tab: "@name ".
    func pick(_ name: String) {
        key(accAt)
        type(name)
        key(accTab)
    }

    /// Pinyin, then Space for its first candidate.
    func pinyin(_ letters: String) {
        type(letters)
        key(spaceKey)
    }

    /// The action key.
    @discardableResult
    func act() -> [Composer.Effect] { key(enterKey) }

    /// ⌃V: the clipboard request's id.
    func controlV() throws -> Int { try #require(ReplyAcc.clipboardID(key(accControlV)), "⌃V asked for no clipboard") }

    /// ⌃V with `text` on the clipboard: what the delivery returned.
    @discardableResult
    func pasteText(_ text: String) throws -> [Composer.Effect] {
        let id = try controlV()
        let out = c.pasted(.text(text), id: id)
        effects += out
        return out
    }

    /// ⌃V with an image on the clipboard: the recognition's id.
    func pasteImage() throws -> Int {
        let id = try controlV()
        let out = c.pasted(.image(accPNG), id: id)
        effects += out
        let asked = try #require(ReplyAcc.recognition(out), "an image asked for no recognition: \(out)")
        #expect(asked.image == accPNG)
        return asked.id
    }

    /// ⌃V with a screenshot whose text is `lines`, read by the recognizer: what `recognized` returned.
    @discardableResult
    func screenshot(_ lines: [RecognizedLine]) async throws -> [Composer.Effect] {
        let id = try pasteImage()
        let text = try await ScreenText.recognize(accPNG, with: ReplyAccRecognizer(lines), languages: ["zh-Hans", "en-US"])
        let out = c.recognized(text, id: id)
        effects += out
        return out
    }

    /// `@reply`, a screenshot of `lines`, the intent (pinyin, or English letters), the action key: the request's input.
    func replyInput(_ lines: [RecognizedLine], pinyin: String? = nil, typed: String? = nil) async throws -> String {
        pick("reply")
        if let pinyin { self.pinyin(pinyin) }
        if let typed { type(typed) }
        try await screenshot(lines)
        let out = act()
        return try #require(ReplyAcc.replyStart(out), "no @reply request: \(out)").input
    }

    /// The reply rows shown (kind `.answer`).
    var answers: [String] { c.choices.filter { $0.kind == .answer }.map(\.text) }

    var screenshotRecognizing: Bool {
        if case .screenshot(.recognizing)? = c.attachment { return true }
        return false
    }

    var screenshotReady: Bool {
        if case .screenshot(.ready)? = c.attachment { return true }
        return false
    }

    var copiedText: String? {
        if case let .copiedText(text)? = c.attachment { return text }
        return nil
    }
}

// MARK: - The tests

struct ReplyAcceptanceTests {
    // MARK: S1. A built-in command, and the user's own @reply renamed

    @Test func s1_replyIsBuiltInAndTheUsersOwnIsRenamed() throws {
        #expect(Command.builtins.contains(.reply))
        #expect(Command.reply.name == "reply" && Command.reply.kind == .generate)
        #expect(Command.reply.usesAI)
        #expect(Command.reply.custom == nil)

        // A custom "reply" is hidden by it: the catalog offers the built-in once.
        let own = CustomCommand(name: "reply", type: .prompt, prompt: "Write a polite reply.")
        let offered = Command.catalog([own]).filter { $0.name == "reply" }
        #expect(offered.count == 1 && offered.first == .reply && offered.first?.custom == nil, "\(offered)")
        #expect(own.problem(among: []) == .nameTaken)

        // freeBuiltinNames: renamed to the first free name, everything else kept.
        let other = CustomCommand(name: "tweetit", type: .prompt, prompt: "Rewrite this as a tweet.")
        var config = Config.default
        config.customCommands = [own, other]
        let renamed = config.freeBuiltinNames()
        #expect(renamed.map { $0.old } == ["reply"] && renamed.map { $0.new } == ["myreply"], "\(renamed)")
        #expect(config.customCommands.map(\.name) == ["myreply", "tweetit"])
        #expect(config.customCommands.first?.prompt == "Write a polite reply.")
        #expect(config.customCommands.first?.type == .prompt)
        #expect(config.customCommands.last == other)
        // Now offered under its new name, beside the built-in.
        let catalog = Command.catalog(config.customCommands)
        #expect(catalog.contains { $0.name == "myreply" && $0.custom?.prompt == "Write a polite reply." })
        #expect(catalog.filter { $0.name == "reply" } == [.reply])

        // Twice: nothing more changes.
        let before = config.customCommands
        let again = config.freeBuiltinNames()
        #expect(again.isEmpty, "\(again)")
        #expect(config.customCommands == before)

        // "myreply" taken already: "myreply2".
        let mine = CustomCommand(name: "myreply", type: .prompt, prompt: "Something else.")
        var taken = Config.default
        taken.customCommands = [own, mine]
        let second = taken.freeBuiltinNames()
        #expect(second.map { $0.old } == ["reply"] && second.map { $0.new } == ["myreply2"], "\(second)")
        #expect(taken.customCommands.map(\.name) == ["myreply2", "myreply"])
        #expect(taken.customCommands.last == mine)
        #expect(taken.freeBuiltinNames().isEmpty)

        // Nothing to rename.
        var plain = Config.default
        plain.customCommands = [other]
        #expect(plain.freeBuiltinNames().isEmpty)
        #expect(plain.customCommands == [other])
    }

    // MARK: S2. Nothing to reply to

    @Test func s2_replyAloneGivesTheHintAndStartsNothing() throws {
        let rig = ReplyAccRig()
        rig.pick("reply")
        #expect(rig.c.draft == "@reply ")
        let out = rig.act()
        #expect(ReplyAcc.notices(out).contains(rig.c.messages.replyHint), "\(out)")
        #expect(!ReplyAcc.startsAnything(out), "\(out)")
        #expect(rig.c.draft == "@reply ")
        #expect(!rig.c.messages.replyHint.isEmpty)

        // In Chrome with the page to take along, it goes: the page is the context.
        let chrome = ReplyAccRig()
        chrome.c.pageContextApplies = { true }
        chrome.pick("reply")
        let started = chrome.act()
        #expect(ReplyAcc.replyStart(started) != nil, "\(started)")
        #expect(!ReplyAcc.notices(started).contains(chrome.c.messages.replyHint))
    }

    // MARK: S3. On a selection, with an intent

    @Test func s3_selectionAndIntentAndTheReplyGoesInAfterTheSelection() throws {
        let selected = "明天能来加班吗？"
        let selection = Composer.Selection(text: selected, range: 0..<8)
        let rig = ReplyAccRig(selection: selection)
        rig.pick("reply")
        rig.pinyin("weiwanjujue")
        #expect(rig.c.draft == "@reply 委婉拒绝")
        let out = rig.act()
        let start = try #require(ReplyAcc.replyStart(out), "\(out)")
        #expect(start.input.contains("<intent>委婉拒绝</intent>"), "\(start.input)")
        #expect(start.input.contains(selected), "\(start.input)")
        // Nothing went into the field meanwhile.
        #expect(!rig.effects.contains { if case .commit = $0 { return true } else { return false } })

        let first = "不好意思，明天家里有事，来不了了"
        _ = rig.c.receive(ReplyAcc.replies(first, "明天恐怕不行，下次一定", "这次实在抽不开身，抱歉"), isFinal: true,
                          id: start.id)
        let picked = rig.key(enterKey)
        #expect(picked.contains(.replaceSelection(selected + "\n" + first, selection)), "\(picked)")
        #expect(commits(picked).isEmpty)
    }

    // MARK: S4. A screenshot pasted: recognized, the chip ready, a stale answer ignored

    @Test func s4_aScreenshotIsRecognizedAndAStaleIDIsIgnored() async throws {
        let rig = ReplyAccRig()
        rig.pick("reply")
        let id = try rig.pasteImage()
        #expect(rig.screenshotRecognizing)
        #expect(rig.c.draft == "@reply ")

        let text = try await ScreenText.recognize(accPNG, with: ReplyAccRecognizer([ReplyAcc.them("明天能来加班吗？", y: 0.2)]),
                                                  languages: ["zh-Hans", "en-US"])
        // Another recognition's answer: nothing changes.
        let stale = rig.c.recognized(text, id: id + 1)
        #expect(!ReplyAcc.startsAnything(stale), "\(stale)")
        #expect(rig.screenshotRecognizing)
        let staleFailure = rig.c.recognitionFailed("boom", id: id + 1)
        #expect(!ReplyAcc.startsAnything(staleFailure) && ReplyAcc.notices(staleFailure).isEmpty, "\(staleFailure)")
        #expect(rig.screenshotRecognizing)

        // Its own: the chip is ready.
        let ready = rig.c.recognized(text, id: id)
        #expect(!ReplyAcc.startsAnything(ready), "nothing was asked for yet: \(ready)")
        #expect(rig.screenshotReady)
        #expect(rig.c.draft == "@reply ")

        // ⌫ with nothing typed after the name takes the attachment away, and only it.
        rig.key(backspaceKey)
        #expect(rig.c.attachment == nil)
        #expect(rig.c.draft == "@reply ")
    }

    // MARK: S5. The action key while the screenshot is being read

    @Test func s5_theRequestWaitsForTheRecognition() async throws {
        let rig = ReplyAccRig()
        rig.pick("reply")
        let id = try rig.pasteImage()
        let waiting = rig.act()
        #expect(ReplyAcc.replyStart(waiting) == nil, "\(waiting)")
        #expect(!ReplyAcc.startsAnything(waiting), "\(waiting)")
        #expect(!ReplyAcc.notices(waiting).contains(rig.c.messages.replyHint), "it has a context coming: \(waiting)")
        let text = try await ScreenText.recognize(accPNG, with: ReplyAccRecognizer([ReplyAcc.them("明天能来加班吗？", y: 0.2)]),
                                                  languages: ["zh-Hans", "en-US"])
        let started = rig.c.recognized(text, id: id)
        let start = try #require(ReplyAcc.replyStart(started), "\(started)")
        #expect(start.input.contains("明天能来加班吗？"), "\(start.input)")

        // The recognition fails instead: a notice, and nothing is sent.
        let failing = ReplyAccRig()
        failing.pick("reply")
        let failingID = try failing.pasteImage()
        #expect(!ReplyAcc.startsAnything(failing.act()))
        let failed = failing.c.recognitionFailed("The screenshot couldn't be read", id: failingID)
        #expect(!ReplyAcc.notices(failed).isEmpty, "\(failed)")
        #expect(!ReplyAcc.startsAnything(failed), "\(failed)")
    }

    // MARK: S6. The transcript: who said what

    @Test func s6_leftIsThemRightIsMeTimesDroppedOneSidedUnlabelled() async throws {
        // Given out of order: sorted top to bottom.
        let lines = [
            ReplyAcc.them("那周日呢？", y: 0.45),
            ReplyAcc.centred("14:32", y: 0.10),
            ReplyAcc.me("我看看", y: 0.30),
            ReplyAcc.them("明天能来加班吗？", y: 0.20),
        ]
        let input = try await ReplyAccRig().replyInput(lines)
        #expect(ReplyAcc.labelled(input, "them", "明天能来加班吗？"), "\(input)")
        #expect(ReplyAcc.labelled(input, "me", "我看看"), "\(input)")
        #expect(ReplyAcc.labelled(input, "them", "那周日呢？"), "\(input)")
        let first = try #require(input.range(of: "明天能来加班吗？"))
        let second = try #require(input.range(of: "我看看"))
        let third = try #require(input.range(of: "那周日呢？"))
        #expect(first.lowerBound < second.lowerBound && second.lowerBound < third.lowerBound, "\(input)")
        #expect(!input.contains("14:32"), "\(input)")

        // Lines on one side only: no speakers.
        let oneSided = try await ReplyAccRig().replyInput([
            ReplyAcc.them("今天下午开会吗？", y: 0.20),
            ReplyAcc.them("几点开始？", y: 0.30),
        ])
        #expect(oneSided.contains("今天下午开会吗？") && oneSided.contains("几点开始？"), "\(oneSided)")
        #expect(!ReplyAcc.hasSpeakerLabels(oneSided), "\(oneSided)")
    }

    // MARK: S7. The reply's language: the other party's

    @Test func s7_theOtherPartysLanguageEvenWithAChineseIntent() async throws {
        let lines = [
            ReplyAcc.them("明日、来られますか？", y: 0.20),
            ReplyAcc.me("我看看", y: 0.30),
            ReplyAcc.them("土曜日でも大丈夫ですよ", y: 0.40),
        ]
        var sure = Platform()
        sure.languages = ReplyAccLanguages(confidence: 0.9)
        let input = try await Platform.$override.withValue(sure) {
            try await ReplyAccRig().replyInput(lines, pinyin: "weiwanjujue")
        }
        #expect(input.contains("<intent>委婉拒绝</intent>"), "\(input)")
        #expect(input.contains("<reply_language>Japanese</reply_language>"), "\(input)")
        #expect(input.components(separatedBy: "<reply_language>").count == 2, "\(input)")

        // Not sure enough (0.4 < 0.6): no language named.
        var unsure = Platform()
        unsure.languages = ReplyAccLanguages(confidence: 0.4)
        let vague = try await Platform.$override.withValue(unsure) {
            try await ReplyAccRig().replyInput(lines, pinyin: "weiwanjujue")
        }
        #expect(!vague.contains("<reply_language>"), "\(vague)")
    }

    // MARK: S8. The app's tone

    @Test func s8_casualInWeChatFormalWithItsProfileAndInMail() async throws {
        let config = Config.default
        #expect(TranslateMode.tone(app: ReplyAcc.wechat, config: config) == .casual)
        var formal = config
        formal.appProfiles = [ReplyAcc.wechat: AppProfile(rewriteStyles: ["正式"])]
        #expect(TranslateMode.tone(app: ReplyAcc.wechat, config: formal) == .formal)
        #expect(TranslateMode.tone(app: ReplyAcc.mail, config: config) == .formal)

        let chatCasual = Prompt.replySystem(tone: .casual, appClass: .chat)
        let chatFormal = Prompt.replySystem(tone: .formal, appClass: .chat)
        let mailFormal = Prompt.replySystem(tone: .formal, appClass: .mail)
        #expect(chatCasual != chatFormal && chatFormal != mailFormal)
        // The email rule is the mail class's.
        #expect(mailFormal.lowercased().contains("email"), "\(mailFormal)")
        // The format: replies separated by a line of "---".
        #expect(chatCasual.contains("---"), "\(chatCasual)")

        let input = "<intent>ok</intent>"
        let answer = "A\n---\nB\n---\nC"
        let inWeChat = await ReplyAcc.generate(config, input: input, app: ReplyAcc.wechat, answer: answer)
        let sentWeChat = try #require(inWeChat.bodies.first)
        #expect(ReplyAcc.system(of: sentWeChat).contains(chatCasual), "\(ReplyAcc.system(of: sentWeChat))")

        let withProfile = await ReplyAcc.generate(formal, input: input, app: ReplyAcc.wechat, answer: answer)
        let sentProfile = try #require(withProfile.bodies.first)
        #expect(ReplyAcc.system(of: sentProfile).contains(chatFormal), "\(ReplyAcc.system(of: sentProfile))")

        let inMail = await ReplyAcc.generate(config, input: input, app: ReplyAcc.mail, answer: answer)
        let sentMail = try #require(inMail.bodies.first)
        #expect(ReplyAcc.system(of: sentMail).contains(mailFormal), "\(ReplyAcc.system(of: sentMail))")
    }

    // MARK: S9. The replies split

    @Test func s9_replyParser() async throws {
        let three = ReplyParser.parse("A\n---\nB\n---\nC", isFinal: true)
        #expect(three == [CandidateLine("A"), CandidateLine("B"), CandidateLine("C")], "\(three)")

        // While it streams: the last one isn't complete yet.
        let streaming = ReplyParser.parse("A\n---\nB", isFinal: false)
        #expect(streaming.map(\.text) == ["A", "B"], "\(streaming)")
        #expect(streaming.map(\.isComplete) == [true, false], "\(streaming)")
        let one = ReplyParser.parse("A", isFinal: false)
        #expect(one.map(\.text) == ["A"] && one.first?.isComplete == false, "\(one)")
        let afterSeparator = ReplyParser.parse("A\n---\n", isFinal: false)
        #expect(afterSeparator.filter { !$0.text.isEmpty }.map(\.text) == ["A"], "\(afterSeparator)")
        #expect(afterSeparator.first?.isComplete == true, "\(afterSeparator)")

        // Fewer than three.
        let two = ReplyParser.parse("A\n---\nB", isFinal: true)
        #expect(two == [CandidateLine("A"), CandidateLine("B")], "\(two)")
        #expect(ReplyParser.parse("Only one", isFinal: true) == [CandidateLine("Only one")])

        // A reply of several lines (an email body) keeps them.
        let email = "Dear Li,\n\nThanks for the invitation.\n\nBest,\nWei"
        let multi = ReplyParser.parse(email + "\n---\nB\n---\nC\n", isFinal: true)
        #expect(multi.map(\.text) == [email, "B", "C"], "\(multi)")

        // A fourth is dropped.
        let four = ReplyParser.parse("A\n---\nB\n---\nC\n---\nD", isFinal: true)
        #expect(four.map(\.text) == ["A", "B", "C"], "\(four)")

        // The converter's answer for @reply: its replies as the versions.
        let sent = await ReplyAcc.generate(.default, input: "<intent>ok</intent>", app: ReplyAcc.wechat,
                                           answer: "A\n---\nB\n---\nC\n---\nD")
        #expect(sent.error == nil, "\(String(describing: sent.error))")
        let final = try #require(sent.final)
        #expect(final.versions.map(\.text) == ["A", "B", "C"], "\(final)")
        #expect(final.versions.allSatisfy { $0.isComplete })
    }

    // MARK: S10. The rows

    @Test func s10_threeAnswerRowsRowZeroOnlyWithAnIntentAndADigitPicks() throws {
        // Nothing typed: the copied message is the context, and there is no row 0.
        let rig = ReplyAccRig()
        rig.pick("reply")
        try rig.pasteText("明天能来加班吗？")
        let start = try #require(ReplyAcc.replyStart(rig.act()))
        _ = rig.c.receive(ReplyAcc.replies("A reply", "B reply", "C reply"), isFinal: true, id: start.id)
        let rows = rig.c.choices
        #expect(rows.map(\.kind) == [.answer, .answer, .answer], "\(rows)")
        #expect(rows.map(\.label) == ["1", "2", "3"], "\(rows)")
        #expect(rows.map(\.text) == ["A reply", "B reply", "C reply"])
        #expect(rows.indices.contains(rig.c.highlighted) && rows[rig.c.highlighted].label == "1")
        let picked = rig.key(k("2"))
        #expect(commits(picked) == ["B reply"], "\(picked)")

        // With an intent: row 0 is what was typed.
        let typed = ReplyAccRig(english: true)
        typed.pick("reply")
        typed.type("no thanks")
        let typedStart = try #require(ReplyAcc.replyStart(typed.act()))
        _ = typed.c.receive(ReplyAcc.replies("A", "B", "C"), isFinal: true, id: typedStart.id)
        let shown = typed.c.choices
        #expect(shown.map(\.label) == ["0", "1", "2", "3"], "\(shown)")
        #expect(shown.first?.kind == .original && shown.first?.text == "no thanks", "\(shown)")
        #expect(shown.dropFirst().map(\.kind) == [.answer, .answer, .answer])
        #expect(shown.indices.contains(typed.c.highlighted) && shown[typed.c.highlighted].label == "1")
        #expect(commits(typed.key(enterKey)) == ["A"])
    }

    // MARK: S11. ⌘R: three more

    @Test func s11_commandRAsksForThreeMoreAndEscBringsTheOthersBack() throws {
        let rig = ReplyAccRig()
        rig.pick("reply")
        try rig.pasteText("明天能来加班吗？")
        let start = try #require(ReplyAcc.replyStart(rig.act()))
        _ = rig.c.receive(ReplyAcc.replies("A", "B", "C"), isFinal: true, id: start.id)

        let again = rig.key(accCommandR)
        let refine = try #require(ReplyAcc.refine(again), "\(again)")
        #expect(refine.refinement.turns.last?.instruction == "Write three different replies.", "\(refine.refinement)")
        #expect(refine.refinement.turns.last?.answer.versions.map(\.text) == ["A", "B", "C"])
        #expect(refine.refinement.request == .command(.reply, input: start.input), "\(refine.refinement.request)")
        _ = rig.c.receive(ReplyAcc.replies("D", "E", "F"), isFinal: true, id: refine.id)
        #expect(rig.answers == ["D", "E", "F"])

        rig.key(escKey)
        #expect(rig.answers == ["A", "B", "C"])
        #expect(rig.c.isLevelTwo)
    }

    // MARK: S12. Hidden values in the screenshot's text

    @Test func s12_anEmailInTheScreenshotIsHiddenAndRestored() async throws {
        let email = "zhang.wei@example.com"
        let input = try await ReplyAccRig().replyInput([
            ReplyAcc.them("合同请发到 \(email) 谢谢", y: 0.20),
            ReplyAcc.me("好的", y: 0.30),
        ])
        #expect(input.contains(email), "the composer has it; the converter hides it: \(input)")

        var config = Config.default
        config.redaction = RedactionSettings(enabled: true)
        let sent = await ReplyAcc.generate(config, input: input, app: ReplyAcc.wechat,
                                           answer: "好的，马上发到 [EMAIL_1]\n---\n收到，这就发\n---\n好，稍等")
        #expect(sent.error == nil, "\(String(describing: sent.error))")
        let body = try #require(sent.bodies.first)
        #expect(!ReplyAcc.text(of: body).contains(email), "\(ReplyAcc.text(of: body))")
        #expect(ReplyAcc.text(of: body).contains("[EMAIL_1]"))
        let final = try #require(sent.final)
        #expect(final.versions.count == 3, "\(final)")
        #expect(final.versions.first?.text == "好的，马上发到 \(email)", "\(final)")
    }

    // MARK: S13. No AI here; a terminal

    @Test func s13_noAIRefusesAndATerminalGetsOneLine() async throws {
        let refusal = "AI is off in this app"
        let rig = ReplyAccRig(english: true)
        rig.c.aiRefusal = { refusal }
        rig.pick("reply")
        rig.type("no thanks")
        let out = rig.act()
        #expect(ReplyAcc.notices(out).contains(refusal), "\(out)")
        #expect(!ReplyAcc.startsAnything(out), "\(out)")
        #expect(rig.c.draft == "@reply no thanks")

        // The converter sends nothing for an app with no AI either.
        var config = Config.default
        config.appProfiles = [ReplyAcc.bank: AppProfile(noAI: true)]
        let sent = await ReplyAcc.generate(config, input: "<intent>no thanks</intent>", app: ReplyAcc.bank, answer: "A")
        #expect(sent.error != nil)
        #expect(sent.bodies.isEmpty)

        // A terminal runs every line it is given: each reply on one line.
        let replies = ReplyParser.parse("Dear Li,\nThanks.\n---\nB\n---\nC", isFinal: true)
        let flat = CommandRunner.oneLine(ConversionResult(versions: replies))
        #expect(flat.versions.count == 3)
        #expect(flat.versions.allSatisfy { !$0.text.contains(where: \.isNewline) }, "\(flat)")
        #expect(flat.versions.first?.text == "Dear Li, Thanks.", "\(flat)")
    }

    // MARK: S14. A screenshot in other commands

    @Test func s14_otherCommandsWithAScreenshot() async throws {
        let lines = [ReplyAcc.them("Meeting moved to Friday", y: 0.20), ReplyAcc.them("Room 4B at 3pm", y: 0.30)]

        // @question: what is typed, with the screenshot's text.
        let question = ReplyAccRig(english: true)
        question.pick("question")
        question.type("what does it say")
        try await question.screenshot(lines)
        let asked = question.act()
        let input = try #require(asked.compactMap { effect -> String? in
            if case let .startCommand(command, input, _) = effect, command == .question { return input }
            return nil
        }.first, "\(asked)")
        #expect(input.contains("what does it say"), "\(input)")
        #expect(input.contains("Meeting moved to Friday") && input.contains("Room 4B at 3pm"), "\(input)")
        let wrapped = Prompt.withScreenshot("what does it say", "Meeting moved to Friday\nRoom 4B at 3pm")
        #expect(wrapped.contains("what does it say") && wrapped.contains("Room 4B at 3pm"), "\(wrapped)")

        // @translate on a screenshot of several lines: one rewrite of it, inserted at the caret.
        let translate = ReplyAccRig(english: true)
        translate.pick("translate")
        try await translate.screenshot(lines)
        let translating = translate.act()
        let edit = try #require(translating.compactMap { effect -> (String, Int)? in
            if case let .startCommand(command, input, id) = effect, command == .edit { return (input, id) }
            return nil
        }.first, "\(translating)")
        #expect(edit.0.contains("Meeting moved to Friday") && edit.0.contains("Room 4B at 3pm"), "\(edit.0)")
        _ = translate.c.receive(ReplyAcc.replies("会议改到周五\n下午3点在4B会议室"), isFinal: true, id: edit.1)
        let inserted = translate.key(enterKey)
        #expect(commits(inserted) == ["会议改到周五\n下午3点在4B会议室"], "\(inserted)")
        #expect(!inserted.contains { if case .replaceSelection = $0 { return true } else { return false } })

        // @note saves the screenshot's text, its lines kept.
        let note = ReplyAccRig(english: true)
        note.pick("note")
        try await note.screenshot(lines)
        let saved = ReplyAcc.notes(note.act())
        let text = try #require(saved.first, "\(note.effects)")
        #expect(text.contains("Meeting moved to Friday") && text.contains("Room 4B at 3pm"), "\(text)")
        #expect(text.contains("\n"), "\(text)")

        // @translate with a selection too: the selection wins, and a notice says the screenshot wasn't used.
        let selection = Composer.Selection(text: "Good morning", range: 0..<12)
        let selected = ReplyAccRig(english: true, selection: selection)
        selected.pick("translate")
        let recognized = try await selected.screenshot(lines)
        let started = selected.act()
        #expect(ReplyAcc.notices(recognized + started).contains(selected.c.messages.screenshotUnused),
                "\(recognized + started)")
        let inputs = ReplyAcc.requestInputs(started)
        #expect(inputs.count == 1 && inputs.first?.contains("Good morning") == true, "\(started)")
        #expect(!inputs.contains { $0.contains("Meeting moved to Friday") }, "\(inputs)")
    }

    // MARK: S15. Text pasted into @reply

    @Test func s15_pastedTextIsTheMessageAndTheDraftStays() throws {
        let message = "明天能来加班吗？\n周六上午十点到公司"
        let rig = ReplyAccRig()
        rig.pick("reply")
        try rig.pasteText(message)
        #expect(rig.c.draft == "@reply ")
        #expect(rig.copiedText == message, "\(String(describing: rig.c.attachment))")
        let start = try #require(ReplyAcc.replyStart(rig.act()))
        #expect(start.input.contains(message) || start.input.contains("明天能来加班吗？") && start.input.contains("周六上午十点到公司"),
                "\(start.input)")

        // At most 4,000 characters of it.
        let long = ReplyAccRig()
        long.pick("reply")
        try long.pasteText(String(repeating: "很长的消息。", count: 1000))
        #expect(long.c.draft == "@reply ")
        let kept = try #require(long.copiedText)
        #expect(kept.count <= 4000 && kept.count > 2000, "\(kept.count)")

        // Every other command takes pasted text into its draft, as before.
        let question = ReplyAccRig(english: true)
        question.pick("question")
        try question.pasteText("What is a monad?")
        #expect(question.c.draft == "@question What is a monad?")
        #expect(question.c.attachment == nil)
    }

    // MARK: S16. A long screenshot

    @Test func s16_aLongScreenshotKeepsItsLastLines() async throws {
        // 40 lines of 124 characters (about 5,000), far enough apart not to be one message.
        let body = String(repeating: "●", count: 120)
        let lines = (1...40).map { i in
            ReplyAcc.them(String(format: "L%02d ", i) + body, y: Double(i - 1) * 0.024, height: 0.01)
        }
        let input = try await ReplyAccRig().replyInput(lines, typed: nil)
        #expect(input.contains("L40 "), "the last line is kept")
        #expect(!input.contains("L01 "), "the first line is dropped")
        let kept = ReplyAcc.count("●", in: input)
        #expect(kept <= 4000 && kept > 2500, "\(kept)")

        // The on-device model: 1,500.
        let apple = ReplyAccRig()
        apple.c.provider = .apple
        let small = try await apple.replyInput(lines)
        #expect(small.contains("L40 "))
        #expect(!small.contains("L01 "))
        let keptSmall = ReplyAcc.count("●", in: small)
        #expect(keptSmall <= 1500 && keptSmall > 800, "\(keptSmall)")
    }

    // MARK: S17. Nothing read

    @Test func s17_unsupportedAndNoText() async throws {
        await #expect(throws: ScreenText.Problem.unsupported) {
            try await ScreenText.recognize(accPNG, with: UnsupportedTextRecognizer(), languages: ["en-US"])
        }
        await #expect(throws: ScreenText.Problem.noText) {
            try await ScreenText.recognize(accPNG, with: ReplyAccRecognizer([]), languages: ["en-US"])
        }
        // Lines read: no error.
        _ = try await ScreenText.recognize(accPNG, with: ReplyAccRecognizer([ReplyAcc.them("hi", y: 0.2)]),
                                           languages: ["en-US"])
    }

    // MARK: S18. The text around the caret

    @Test func s18_fieldTextGoesInTaggedAndCapped() throws {
        let before = "BEFORE-START " + String(repeating: "Ⓑ", count: 3000) + " BEFORE-END"
        let after = "AFTER-START " + String(repeating: "Ⓐ", count: 3000) + " AFTER-END"
        let rig = ReplyAccRig(english: true)
        rig.c.readFieldText = { .init(before: before, after: after) }
        rig.pick("reply")
        rig.type("no thanks")
        let start = try #require(ReplyAcc.replyStart(rig.act()))
        let input = start.input
        // Before the caret: the end of it, nearest the caret; after: its start.
        #expect(input.contains("BEFORE-END") && !input.contains("BEFORE-START"), "\(input.prefix(300))")
        #expect(input.contains("AFTER-START") && !input.contains("AFTER-END"), "\(input.suffix(300))")
        let b = ReplyAcc.count("Ⓑ", in: input)
        let a = ReplyAcc.count("Ⓐ", in: input)
        #expect(b <= 1500 && b > 1000, "\(b)")
        #expect(a <= 1500 && a > 1000, "\(a)")
        #expect(ReplyAcc.inTag("BEFORE-END", input), "\(input.prefix(300))")
        #expect(ReplyAcc.inTag("AFTER-START", input), "\(input.suffix(300))")

        // Short field text goes in whole.
        let short = ReplyAccRig(english: true)
        short.c.readFieldText = { .init(before: "Hi Li, about the offsite:", after: "See you then.") }
        short.pick("reply")
        short.type("sounds good")
        let shortInput = try #require(ReplyAcc.replyStart(short.act())).input
        #expect(shortInput.contains("Hi Li, about the offsite:") && shortInput.contains("See you then."), "\(shortInput)")
        #expect(ReplyAcc.inTag("Hi Li, about the offsite:", shortInput) && ReplyAcc.inTag("See you then.", shortInput))
    }

    // MARK: S19. The recognizer's languages

    @Test func s19_recognitionLanguages() {
        var chinese = Config.default
        chinese.inputLanguages = [.chinese, .english]
        chinese.outputLanguages = [.english, .chinese]
        let zh = ScreenText.languages(chinese)
        #expect(zh.first == "zh-Hans", "\(zh)")
        #expect(zh.contains("en-US"), "\(zh)")

        var other = Config.default
        other.inputLanguages = [.english, .french]
        other.defaultInput = .english
        other.outputLanguages = [.english, OutputLanguage("ja")]
        let en = ScreenText.languages(other)
        #expect(en.contains("en-US"), "\(en)")
        #expect(en.first != "zh-Hans", "\(en)")
        #expect(en.contains { $0.hasPrefix("ja") }, "the output languages: \(en)")
    }
}

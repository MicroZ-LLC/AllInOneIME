import CoreGraphics
import Foundation
import os
import Testing
@testable import AllInOneIMECore

// Acceptance tests for "a screenshot's image goes to an AI that can see it" (owner decision 2026-11-16), written from
// the spec only, independently of the implementation's own tests. When asking AI (an `@question` draft, the one-@ draft
// that becomes Ask AI, the follow-ups of the question chat), ⌃V with an image on the clipboard attaches the screenshot:
// the image itself goes to the AI when the chosen AI can see images; its text, read on the device, always goes along
// (`Prompt.withScreenshot`, as before), so an AI that can't see images still gets the text.
//
// What the input controller does (the app target, which these tests can't load) is played as the spec says it does:
// ⌃V's clipboard is handed to `pasted(_:id:)`, `.recognizeText` is answered with the text a fake `TextRecognizer` read
// and the image it would have made smaller (`recognized(_:image:id:)`), and requests go through the real `Converter` to
// a recording URL protocol that speaks each provider's wire, so what was sent is read back, not assumed. No network, no
// CLI, no paid call.
//
// API PROMISES the tests rely on (from the spec, used exactly):
//  1. `public struct PromptImage: Hashable, Sendable { init(data: Data, mediaType: String); var data: Data;
//     var mediaType: String; static let longSide = 1568 }`; `mediaType` is "image/jpeg" or "image/png".
//  2. `TextRecognizer` gains `func downscaled(_ image: Data, longSide: Int) -> PromptImage?`, a requirement with a
//     default implementation returning nil (a fake recognizer may implement it).
//  3. `Composer.aiSeesImages: () -> Bool` (default: false), set by the session from the AI chosen.
//  4. `Composer.recognized(_ text: ScreenText?, image: PromptImage?, id: Int) -> [Effect]`; the existing
//     `recognized(_:id:)` stays and means image nil.
//  5. `QuestionConversation.attachments: [Int: QuestionConversation.Attachment]`, keyed by round (0 the first question,
//     1 the first follow-up, …); `QuestionConversation.Attachment(text: String, image: PromptImage?)` with those two
//     properties. `Composer.questionConversation` holds it.
//  6. `Composer.followUpAttachment: Composer.Attachment?`: a screenshot pasted while typing a follow-up in the question
//     chat (`.screenshot(.recognizing)`, then `.screenshot(.ready(_))`).
//  7. `ConverseRequest.Message.images: [PromptImage]` (empty by default); Bedrock Converse JSON encodes each as a
//     content block `{"image":{"format":"jpeg"|"png","source":{"bytes":"<base64>"}}}` before the text block.
//  8. `Provider.seesImages(model: String, baseURL: String?) -> Bool`: `.anthropic` and `.gemini` true; `.openai` true
//     only when the base URL's host is api.openai.com; `.bedrock` true for model ids containing "anthropic." or
//     "amazon.nova-" except "nova-micro"; `.hosted` and `.apple` false.
//  9. `ClaudeSession.userMessage(_ text: String, images: [PromptImage]) -> Data`: one stream-json line
//     `{"type":"user","message":{"role":"user","content":[{"type":"image","source":{"type":"base64","media_type":…,
//     "data":…}}…,{"type":"text","text":…}]}}`; with no images the content may stay a plain string.
// 10. `SessionDriver.message(_ text: String, images: [PromptImage]) -> [Data]`. ACP (`ACPDriver`): the `session/prompt`
//     content gets `{"type":"image","mimeType":…,"data":<base64>}` before the text block only when the agent's
//     `initialize` result said `agentCapabilities.promptCapabilities.image == true`; otherwise text only. Codex
//     (`CodexDriver`): `turn/start`'s input gets `{"type":"image","url":"data:<mediaType>;base64,<base64>"}` before the
//     text item.
// 11. HTTP bodies (`HTTPProviders.makeRequest`). Claude API: the user message's `content` is
//     `[{"type":"image","source":{"type":"base64","media_type":…,"data":…}}, {"type":"text","text":…}]`. Gemini:
//     `parts` has `{"inline_data":{"mime_type":…,"data":…}}` before the text part. OpenAI-compatible: `content` is
//     `[{"type":"image_url","image_url":{"url":"data:…;base64,…"}}, {"type":"text","text":…}]`. AllInOneIME Cloud
//     (`.hosted`): never an image (its service takes text blocks only).
// 12. (Withdrawn.) The existing rule stays: a question asked with a screenshot, on the first question or on any
//     follow-up, isn't kept in the recent questions at all (no `.rememberQuestion`, `questionHistory.entries` as they
//     were): the screenshot's text may be someone else's and must not end up on disk or synced.
//
// ASSUMPTIONS (what the spec leaves open; the narrowest reading, for the implementation to match):
//  A. The question's request starts as it does today, `.startCommand(.question, input:id:)`; the spec's text says
//     `.startConversion`, so either is taken as the start (`QShot.questionStart`).
//  B. "The recognizer found no text" reaches the composer as a nil `ScreenText` or as one with no lines: both are played.
//     The attachment kept for it has an empty `text`.
//  C. The converter learns the images from the `conversation:` it is given (`QuestionConversation.attachments`), with
//     the input and turns the composer's effects carry; whether a follow-up's screenshot text is put into the turn's
//     instruction by the composer or added by the converter isn't looked at, only that it is in the second user message.
//  D. With words to hide configured and none of them in the screenshot's text, the image is sent as usual (the rule is
//     about words "that appear in the screenshot's text").
//  E. A question asked without a screenshot is kept as before; the entry's `question` stays what was typed.
//  F. Esc with a follow-up's screenshot attached leaves the conversation (`isQuestionChat` false, not level two).

// MARK: - Keys and test data

fileprivate let qsAt = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
fileprivate let qsTab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
fileprivate let qsControlV = KeyEvent(keyCode: 0x09, characters: "\u{16}", charactersIgnoringModifiers: "v",
                                      modifiers: .control)
/// An image's bytes as the clipboard gives them (the composer never decodes them).
fileprivate let qsClipboardPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48])
/// What the recognizer made of them for the AI (never decoded here either: obviously not real images).
fileprivate let qsImage = PromptImage(data: Data("AllInOneIME acceptance test: the first screenshot, not a real JPEG".utf8),
                                      mediaType: "image/jpeg")
fileprivate let qsSecondImage = PromptImage(data: Data("AllInOneIME acceptance test: the follow-up's screenshot, not a real PNG".utf8),
                                            mediaType: "image/png")

/// The provider a request goes to, as the spec's cases name them.
enum QShotWire: String, CaseIterable, Sendable, CustomTestStringConvertible {
    /// The Claude API.
    case claude
    case gemini
    /// OpenAI-compatible, at OpenAI's own base URL (https://api.openai.com/v1).
    case openAI
    /// OpenAI-compatible, at another service's base URL (https://api.deepseek.com).
    case deepSeek
    /// AllInOneIME Cloud.
    case hosted

    var testDescription: String { rawValue }

    /// Whether its request carries the image.
    var takesImages: Bool { self == .claude || self == .gemini || self == .openAI }
}

/// A row of `Provider.seesImages`' table.
struct QShotSeesCase: Sendable, CustomTestStringConvertible {
    var provider: Provider
    var model: String
    var baseURL: String?
    var sees: Bool

    var testDescription: String { "\(provider.rawValue) \(model) \(baseURL ?? "-") → \(sees)" }

    static let table: [QShotSeesCase] = [
        .init(provider: .anthropic, model: "claude-haiku-5-5", baseURL: "https://api.anthropic.com", sees: true),
        .init(provider: .anthropic, model: "claude-haiku-5-5", baseURL: nil, sees: true),
        .init(provider: .gemini, model: "gemini-3.8-flash", baseURL: "https://generativelanguage.googleapis.com", sees: true),
        .init(provider: .gemini, model: "gemini-3.8-flash", baseURL: nil, sees: true),
        .init(provider: .openai, model: "gpt-6-luna", baseURL: "https://api.openai.com/v1", sees: true),
        .init(provider: .openai, model: "deepseek-chat", baseURL: "https://api.deepseek.com", sees: false),
        .init(provider: .openai, model: "qwen-plus", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", sees: false),
        .init(provider: .openai, model: "llava", baseURL: "http://localhost:11434/v1", sees: false),
        .init(provider: .bedrock, model: "us.anthropic.claude-haiku-4-5-20251001-v1:0", baseURL: nil, sees: true),
        .init(provider: .bedrock, model: "anthropic.claude-3-haiku-20240307-v1:0", baseURL: nil, sees: true),
        .init(provider: .bedrock, model: "us.amazon.nova-lite-v1:0", baseURL: nil, sees: true),
        .init(provider: .bedrock, model: "amazon.nova-pro-v1:0", baseURL: nil, sees: true),
        .init(provider: .bedrock, model: "us.amazon.nova-micro-v1:0", baseURL: nil, sees: false),
        .init(provider: .bedrock, model: "amazon.nova-micro-v1:0", baseURL: nil, sees: false),
        .init(provider: .bedrock, model: "meta.llama3-70b-instruct-v1:0", baseURL: nil, sees: false),
        .init(provider: .bedrock, model: "deepseek.r1-v1:0", baseURL: nil, sees: false),
        .init(provider: .hosted, model: "hosted", baseURL: HostedService.baseURL, sees: false),
        .init(provider: .hosted, model: "", baseURL: nil, sees: false),
        .init(provider: .apple, model: AppleModel.modelName, baseURL: nil, sees: false),
    ]
}

// MARK: - Fakes

/// A recognizer that "reads" the lines it was made with, whatever the image, and makes the image `small`.
fileprivate struct QShotRecognizer: TextRecognizer {
    var lines: [RecognizedLine] = []
    var small: PromptImage?

    func recognize(image: Data, languages: [String]) async throws -> [RecognizedLine] { lines }
    func downscaled(_ image: Data, longSide: Int) -> PromptImage? { small }
}

/// A recognizer from before the feature: it only reads text.
fileprivate struct QShotTextOnlyRecognizer: TextRecognizer {
    func recognize(image: Data, languages: [String]) async throws -> [RecognizedLine] { [] }
}

/// Every provider's endpoint: answers each request with "OK", streamed in the wire its path is of (the Claude API's,
/// Gemini's, an OpenAI-compatible service's, AllInOneIME Cloud's), and keeps every request body by host.
fileprivate final class QShotRecorder: URLProtocol, @unchecked Sendable {
    private static let bodies = OSAllocatedUnfairLock(initialState: [String: [Data]]())

    static func bodies(_ host: String) -> [Data] { bodies.withLock { $0[host] ?? [] } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QShotRecorder.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// The streamed answer "OK" for a request to `url`; nil: not a provider's path.
    private static func answer(for url: URL) -> String? {
        let path = url.path
        let lines: [String]
        if path.hasSuffix("/v1/messages") {
            lines = ["event: message_start", #"data: {"type":"message_start","message":{"id":"msg_1"}}"#, "",
                     "event: content_block_delta",
                     #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"OK"}}"#, "",
                     #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#, "",
                     #"data: {"type":"message_stop"}"#, "", ""]
        } else if path.contains(":streamGenerateContent") {
            lines = [#"data: {"candidates":[{"content":{"parts":[{"text":"OK"}]},"finishReason":"STOP"}]}"#, "", ""]
        } else if path.hasSuffix("/chat/completions") {
            lines = [#"data: {"choices":[{"delta":{"content":"OK"}}]}"#, "",
                     #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#, "", "data: [DONE]", "", ""]
        } else if path.hasSuffix("/chat") {
            lines = [#"data: {"text":"OK"}"#, "", #"data: {"stop":"end_turn"}"#, "", ""]
        } else {
            return nil
        }
        return lines.joined(separator: "\n")
    }

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
        let sent = body
        Self.bodies.withLock { $0[request.url?.host ?? "", default: []].append(sent) }
        guard let url = request.url else { return }
        guard let answer = Self.answer(for: url) else {
            let http = HTTPURLResponse(url: url, statusCode: 500, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"error":{"type":"api_error","message":"no such path"}}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

fileprivate enum QShot {
    static let question = "这是什么"
    static let followUp = "那这个呢"

    /// A word no other request has: the screenshot's text holds it, so a request is found by it on a host other tests
    /// send to as well (api.openai.com, the hosted service's). Letters only: nothing a redaction pattern takes for a key.
    static func marker() -> String {
        "qs" + String(UUID().uuidString.lowercased().compactMap { character -> Character? in
            guard let value = character.hexDigitValue else { return nil }
            return Character(Unicode.Scalar(UInt8(0x61 + value)))
        }.prefix(16))
    }

    /// A line of the screenshot on the left (all on one side: no speakers), top-left origin, 0…1.
    static func line(_ text: String, y: Double) -> RecognizedLine {
        RecognizedLine(text: text, box: CGRect(x: 0.05, y: y, width: 0.35, height: 0.03), confidence: 0.95)
    }

    /// A screenshot of a report, its first line with `marker`.
    static func report(_ marker: String, second: String = "Total due Friday") -> [RecognizedLine] {
        [line("Quarterly report \(marker)", y: 0.20), line(second, y: 0.30)]
    }

    /// The text the recognizer reads in a screenshot of `lines`, as the session has it read.
    static func read(_ lines: [RecognizedLine]) async throws -> ScreenText {
        try await ScreenText.recognize(qsClipboardPNG, with: QShotRecognizer(lines: lines), languages: ["zh-Hans", "en-US"])
    }

    static func answer(_ text: String) -> ConversionResult { ConversionResult(versions: [CandidateLine(text, isComplete: true)]) }

    static func clipboardID(_ effects: [Composer.Effect]) -> Int? {
        for effect in effects { if case let .readClipboard(id) = effect { return id } }
        return nil
    }

    static func recognition(_ effects: [Composer.Effect]) -> (image: Data, id: Int)? {
        for effect in effects { if case let .recognizeText(image, id) = effect { return (image, id) } }
        return nil
    }

    /// The question's request among `effects` (assumption A).
    static func questionStart(_ effects: [Composer.Effect]) -> (input: String, id: Int)? {
        for effect in effects {
            switch effect {
            case let .startCommand(command, input, id) where command == .question: return (input, id)
            case let .startConversion(input, id): return (input, id)
            default: continue
            }
        }
        return nil
    }

    static func refine(_ effects: [Composer.Effect]) -> (refinement: Refinement, id: Int)? {
        for effect in effects { if case let .startRefine(refinement, id) = effect { return (refinement, id) } }
        return nil
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

    static func remembered(_ effects: [Composer.Effect]) -> QuestionHistory.Entry? {
        for effect in effects { if case let .rememberQuestion(entry) = effect { return entry } }
        return nil
    }

    static func isRecognizing(_ attachment: Composer.Attachment?) -> Bool {
        if case .screenshot(.recognizing)? = attachment { return true }
        return false
    }

    static func isReady(_ attachment: Composer.Attachment?) -> Bool {
        if case .screenshot(.ready)? = attachment { return true }
        return false
    }

    /// Whether `data` (a request body, a stored file) has `image`'s bytes in it as base64 (JSON may write "/" as "\/").
    static func holds(_ data: Data, _ image: PromptImage) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        let base64 = image.data.base64EncodedString()
        return text.contains(base64) || text.contains(base64.replacingOccurrences(of: "/", with: "\\/"))
    }

    /// The panel's header lines for `composer`, as one text.
    static func header(_ composer: Composer, language: String) -> String {
        PanelPresenter(config: .default, language: language).model(for: composer).header.joined(separator: "\n")
    }

    // MARK: Sending through the converter

    static func newHost() -> String { "h\(UUID().uuidString.lowercased().prefix(12)).qshot-acc.test" }

    /// `base` with `wire` as its provider, and the host its requests go to.
    static func config(_ wire: QShotWire, base: Config = .default) -> (config: Config, host: String) {
        var config = base
        var host = newHost()
        switch wire {
        case .claude:
            config.provider = .anthropic
            config.anthropic.baseURL = "https://\(host)"
            config.anthropic.model = "claude-test"
        case .gemini:
            config.provider = .gemini
            config.gemini.baseURL = "https://\(host)"
            config.gemini.model = "gemini-test"
        case .openAI:
            config.provider = .openai
            config.openai.baseURL = "https://api.openai.com/v1"
            config.openai.model = "gpt-test"
            host = "api.openai.com"
        case .deepSeek:
            config.provider = .openai
            config.openai.baseURL = "https://api.deepseek.com"
            config.openai.model = "deepseek-chat"
            host = "api.deepseek.com"
        case .hosted:
            config.provider = .hosted
            host = HostedService.host ?? ""
        }
        return (config, host)
    }

    /// The question (`input`, with its `turns` for a follow-up) sent to `wire` as the session sends it, with the panel's
    /// `conversation`: the bodies that hold `marker` (this request's), and the error, if it failed.
    static func send(_ wire: QShotWire, base: Config = .default, input: String, turns: [Refinement.Turn] = [],
                     conversation: QuestionConversation?, marker: String) async -> (bodies: [Data], error: Error?) {
        let (config, host) = Self.config(wire, base: base)
        let converter = Converter(client: BedrockClient(session: QShotRecorder.session()), loadConfig: { config },
                                  loadCredentials: { _ in throw ProviderError.missingKey(config.provider) },
                                  loadKey: { _, _ in "sk-test" }, loadJargon: { _ in [] })
        var failure: Error?
        do {
            for try await _ in converter.generate(.question, input: input, turns: turns, conversation: conversation) {}
        } catch {
            failure = error
        }
        let mine = QShotRecorder.bodies(host).filter { String(decoding: $0, as: UTF8.self).contains(marker) }
        return (mine, failure)
    }

    // MARK: Reading a request body

    /// Each user message's content blocks in `body`, oldest first (a plain string as one text block).
    static func userMessages(_ body: Data, _ wire: QShotWire) throws -> [[[String: Any]]] {
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let list = try #require(json[wire == .gemini ? "contents" : "messages"] as? [[String: Any]])
        return list.filter { $0["role"] as? String == "user" }.map { message in
            let content = message[wire == .gemini ? "parts" : "content"]
            if let text = content as? String { return [["type": "text", "text": text]] }
            return content as? [[String: Any]] ?? []
        }
    }

    /// The image `block` is, in `wire`'s shape (promise 11); nil: not an image block of that shape.
    static func image(_ block: [String: Any], _ wire: QShotWire) -> PromptImage? {
        switch wire {
        case .claude:
            guard block["type"] as? String == "image", let source = block["source"] as? [String: Any],
                  source["type"] as? String == "base64", let media = source["media_type"] as? String,
                  let data = (source["data"] as? String).flatMap({ Data(base64Encoded: $0) }) else { return nil }
            return PromptImage(data: data, mediaType: media)
        case .gemini:
            guard let inline = block["inline_data"] as? [String: Any], let media = inline["mime_type"] as? String,
                  let data = (inline["data"] as? String).flatMap({ Data(base64Encoded: $0) }) else { return nil }
            return PromptImage(data: data, mediaType: media)
        case .openAI, .deepSeek:
            guard block["type"] as? String == "image_url", let url = (block["image_url"] as? [String: Any])?["url"] as? String,
                  url.hasPrefix("data:"), let marker = url.range(of: ";base64,"),
                  let data = Data(base64Encoded: String(url[marker.upperBound...])) else { return nil }
            return PromptImage(data: data, mediaType: String(url[url.index(url.startIndex, offsetBy: 5)..<marker.lowerBound]))
        case .hosted:
            return nil
        }
    }

    /// `blocks` (one user message's) hold exactly `image`, before the text, which has every one of `texts`.
    static func expect(_ blocks: [[String: Any]], _ wire: QShotWire, image: PromptImage, texts: [String],
                       sourceLocation: SourceLocation = #_sourceLocation) {
        let images = blocks.compactMap { QShot.image($0, wire) }
        #expect(images == [image], "\(wire): \(blocks)", sourceLocation: sourceLocation)
        let imageAt = blocks.firstIndex { QShot.image($0, wire) != nil }
        let textAt = blocks.firstIndex { $0["text"] is String }
        if let imageAt, let textAt {
            #expect(imageAt < textAt, "the image comes before the text: \(blocks)", sourceLocation: sourceLocation)
        } else {
            Issue.record("\(wire): an image block and a text block are expected: \(blocks)", sourceLocation: sourceLocation)
        }
        let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        for wanted in texts { #expect(text.contains(wanted), "\(wanted) in \(text)", sourceLocation: sourceLocation) }
    }

    /// `body` has no image at all: none of `images`' bytes, no image block in any user message; its text is there.
    static func expectNoImage(_ body: Data, _ wire: QShotWire, images: [PromptImage] = [qsImage, qsSecondImage], texts: [String],
                              sourceLocation: SourceLocation = #_sourceLocation) throws {
        for image in images { #expect(!holds(body, image), "\(wire) was sent the image", sourceLocation: sourceLocation) }
        let users = try userMessages(body, wire)
        for blocks in users {
            for block in blocks {
                // The other wires' image shapes aren't there either.
                for shape in QShotWire.allCases { #expect(image(block, shape) == nil, "\(block)", sourceLocation: sourceLocation) }
                #expect(block["image"] == nil && block["image_url"] == nil && block["inline_data"] == nil
                        && block["type"] as? String != "image", "\(block)", sourceLocation: sourceLocation)
                if wire == .hosted { #expect(Array(block.keys) == ["text"], "text blocks only: \(block)", sourceLocation: sourceLocation) }
            }
        }
        let text = users.flatMap { $0 }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        for wanted in texts { #expect(text.contains(wanted), "\(wanted) in \(text)", sourceLocation: sourceLocation) }
    }

    // MARK: Session drivers

    static func json(_ line: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
    }

    /// The request of `method` among the lines a driver wrote.
    static func request(_ lines: [Data], _ method: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        let objects = try lines.map(json)
        return try #require(objects.first { $0["method"] as? String == method }, "no \(method) in \(objects)",
                            sourceLocation: sourceLocation)
    }

    /// The agent's answer to `request`: its result, as a line.
    static func result(of request: [String: Any], _ result: [String: Any]) throws -> Data {
        let id = try #require(request["id"])
        var data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result] as [String: Any])
        data.append(0x0A)
        return data
    }

    static var folder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("qshot-acc-\(UUID().uuidString)") }
}

/// A text field with a composer as the controller sets it up (a fake pinyin engine, ⏎ the action key).
fileprivate final class QShotRig {
    let engine = FakeEngine()
    let c: Composer
    /// Every effect the composer returned, in order.
    var effects: [Composer.Effect] = []

    init(seesImages: Bool) {
        engine.dictionary["zheshishenme"] = [QShot.question]
        engine.dictionary["nazhegene"] = [QShot.followUp]
        c = Composer(engine: engine, actionKey: .enter)
        c.inputLanguages = [.chinese, .english]
        c.aiSeesImages = { seesImages }
    }

    @discardableResult
    func key(_ event: KeyEvent) -> [Composer.Effect] {
        let out = c.handleKeyDown(event).effects
        effects += out
        return out
    }

    /// Each character as a key ("@" and Space as their keys).
    func type(_ text: String) {
        for ch in text { key(ch == "@" ? qsAt : ch == " " ? spaceKey : k(String(ch))) }
    }

    /// Pinyin, then Space for its first candidate.
    func pinyin(_ letters: String) {
        type(letters)
        key(spaceKey)
    }

    /// "@question 这是什么": "@", the command's name, Tab, the question in pinyin.
    func draftQuestion() {
        key(qsAt)
        type("question")
        key(qsTab)
        pinyin("zheshishenme")
    }

    /// The action key (⏎).
    @discardableResult
    func act() -> [Composer.Effect] { key(enterKey) }

    /// ⌃V with an image on the clipboard: the recognition's id.
    func pasteImage() throws -> Int {
        let id = try #require(QShot.clipboardID(key(qsControlV)), "⌃V asked for no clipboard")
        let out = c.pasted(.image(qsClipboardPNG), id: id)
        effects += out
        let asked = try #require(QShot.recognition(out), "an image asked for no recognition: \(out)")
        #expect(asked.image == qsClipboardPNG)
        return asked.id
    }

    /// ⌃V with a screenshot on the clipboard, read as `text` and made `image` for the AI: what `recognized` returned.
    @discardableResult
    func screenshot(_ text: ScreenText?, image: PromptImage?) throws -> [Composer.Effect] {
        let id = try pasteImage()
        let out = c.recognized(text, image: image, id: id)
        effects += out
        return out
    }

    /// "@question 这是什么" with a screenshot (`text`, `image`), asked: the request.
    func ask(_ text: ScreenText?, image: PromptImage?) throws -> (input: String, id: Int) {
        draftQuestion()
        try screenshot(text, image: image)
        let out = act()
        return try #require(QShot.questionStart(out), "no question asked: \(out)")
    }

    /// The first question's attachment in the conversation.
    var first: QuestionConversation.Attachment? { c.questionConversation?.attachments[0] }
}

// MARK: - The tests

struct QuestionScreenshotAcceptanceTests {
    // MARK: Promises 1 and 2: the image, and the recognizer that makes it

    @Test func promptImageAndTheRecognizersDownscale() {
        #expect(PromptImage.longSide == 1568)
        let image = PromptImage(data: Data([1, 2, 3]), mediaType: "image/png")
        #expect(image.data == Data([1, 2, 3]) && image.mediaType == "image/png")
        #expect(image == PromptImage(data: Data([1, 2, 3]), mediaType: "image/png"))
        #expect(Set([image, image, qsImage]).count == 2)

        // A recognizer that only reads text makes none; one that implements it is asked (a requirement, not a helper).
        let plain: any TextRecognizer = QShotTextOnlyRecognizer()
        #expect(plain.downscaled(qsClipboardPNG, longSide: PromptImage.longSide) == nil)
        #expect(UnsupportedTextRecognizer().downscaled(qsClipboardPNG, longSide: PromptImage.longSide) == nil)
        let own: any TextRecognizer = QShotRecognizer(small: qsImage)
        #expect(own.downscaled(qsClipboardPNG, longSide: PromptImage.longSide) == qsImage)
    }

    // MARK: a. @question with a screenshot, the AI sees images

    @Test func a_aScreenshotInAQuestionIsAttachedWithItsImageAndItsText() async throws {
        let marker = QShot.marker()
        let text = try await QShot.read(QShot.report(marker))
        let rig = QShotRig(seesImages: true)
        rig.draftQuestion()
        #expect(rig.c.draft == "@question \(QShot.question)")

        let id = try rig.pasteImage()
        #expect(QShot.isRecognizing(rig.c.attachment), "\(String(describing: rig.c.attachment))")
        let ready = rig.c.recognized(text, image: qsImage, id: id)
        #expect(!QShot.startsAnything(ready), "nothing was asked for yet: \(ready)")
        #expect(QShot.isReady(rig.c.attachment), "\(String(describing: rig.c.attachment))")
        #expect(rig.c.draft == "@question \(QShot.question)")

        let out = rig.act()
        let start = try #require(QShot.questionStart(out), "\(out)")
        #expect(start.input.contains(QShot.question), "\(start.input)")
        #expect(start.input.contains("Quarterly report \(marker)") && start.input.contains("Total due Friday"), "\(start.input)")
        #expect(rig.first?.image == qsImage, "\(String(describing: rig.c.questionConversation))")
        #expect(rig.first?.text == text.text, "\(String(describing: rig.first?.text))")
        #expect(rig.c.questionConversation?.attachments.count == 1)
    }

    /// The existing `recognized(_:id:)` means no image: the text goes as before.
    @Test func a_recognizedWithoutAnImageAttachesTheTextOnly() async throws {
        let marker = QShot.marker()
        let text = try await QShot.read(QShot.report(marker))
        let rig = QShotRig(seesImages: true)
        rig.draftQuestion()
        let id = try rig.pasteImage()
        _ = rig.c.recognized(text, id: id)
        #expect(QShot.isReady(rig.c.attachment))
        let start = try #require(QShot.questionStart(rig.act()))
        #expect(start.input.contains(QShot.question) && start.input.contains(marker), "\(start.input)")
        #expect(rig.first?.image == nil)
    }

    // MARK: b. No text in the screenshot

    /// `emptyText`: the recognizer's nothing comes as a text with no lines, not as nil (assumption B).
    @Test(arguments: [false, true])
    func b_anImageWithNoTextIsKeptForAnAIThatSeesImages(emptyText: Bool) throws {
        let none: ScreenText? = emptyText ? ScreenText(lines: []) : nil
        let rig = QShotRig(seesImages: true)
        rig.draftQuestion()
        let read = try rig.screenshot(none, image: qsImage)
        #expect(!QShot.notices(read).contains(rig.c.messages.reply.noText), "\(read)")
        #expect(QShot.isReady(rig.c.attachment), "\(String(describing: rig.c.attachment))")
        #expect(rig.c.draft == "@question \(QShot.question)")

        let out = rig.act()
        let start = try #require(QShot.questionStart(out), "\(out)")
        #expect(start.input.contains(QShot.question), "\(start.input)")
        #expect(rig.first?.image == qsImage, "\(String(describing: rig.c.questionConversation))")
        #expect(rig.first?.text.isEmpty == true, "\(String(describing: rig.first?.text))")
    }

    @Test(arguments: [false, true])
    func b_anImageWithNoTextIsRefusedForAnAIThatCannotSeeImages(emptyText: Bool) throws {
        let none: ScreenText? = emptyText ? ScreenText(lines: []) : nil
        let rig = QShotRig(seesImages: false)
        rig.draftQuestion()
        let read = try rig.screenshot(none, image: qsImage)
        #expect(QShot.notices(read).contains(rig.c.messages.reply.noText), "\(read)")
        #expect(rig.c.attachment == nil, "\(String(describing: rig.c.attachment))")
        #expect(!QShot.startsAnything(read), "\(read)")
        #expect(rig.c.draft == "@question \(QShot.question)")

        // Asked all the same: the question alone, with nothing attached.
        let start = try #require(QShot.questionStart(rig.act()))
        #expect(start.input.contains(QShot.question))
        #expect(rig.first?.image == nil)
    }

    /// With no image either (a recognizer that makes none), nothing is attached, whatever the AI sees.
    @Test(arguments: [false, true])
    func b_nothingReadAndNoImageIsTheNoTextNotice(seesImages: Bool) throws {
        let rig = QShotRig(seesImages: seesImages)
        rig.draftQuestion()
        let read = try rig.screenshot(nil, image: nil)
        #expect(QShot.notices(read).contains(rig.c.messages.reply.noText), "\(read)")
        #expect(rig.c.attachment == nil)
    }

    // MARK: c. The AI can't see images: the text, as before

    @Test func c_anAIThatCannotSeeImagesIsAskedWithTheText() async throws {
        let marker = QShot.marker()
        let text = try await QShot.read(QShot.report(marker))
        let rig = QShotRig(seesImages: false)
        rig.draftQuestion()
        let read = try rig.screenshot(text, image: qsImage)
        #expect(!QShot.notices(read).contains(rig.c.messages.reply.noText))
        #expect(QShot.isReady(rig.c.attachment))
        let out = rig.act()
        let start = try #require(QShot.questionStart(out), "\(out)")
        #expect(start.input.contains(QShot.question), "\(start.input)")
        #expect(start.input.contains("Quarterly report \(marker)") && start.input.contains("Total due Friday"), "\(start.input)")
        #expect(rig.first?.text == text.text)

        // Whatever the conversation keeps, a provider that can't see images is sent none.
        let sent = await QShot.send(.deepSeek, input: start.input, conversation: rig.c.questionConversation, marker: marker)
        #expect(sent.error == nil, "\(String(describing: sent.error))")
        let body = try #require(sent.bodies.first)
        #expect(sent.bodies.count == 1)
        try QShot.expectNoImage(body, .deepSeek, texts: [QShot.question, "Quarterly report \(marker)"])
    }

    // MARK: d. One @

    @Test func d_oneAtTakesTheScreenshotAndOffersAskAIFirst() async throws {
        let marker = QShot.marker()
        let text = try await QShot.read(QShot.report(marker))
        let rig = QShotRig(seesImages: true)
        rig.key(qsAt)
        rig.pinyin("zheshishenme")
        #expect(rig.c.draft == "@\(QShot.question)")

        let id = try rig.pasteImage()
        #expect(QShot.isRecognizing(rig.c.attachment), "\(String(describing: rig.c.attachment))")
        #expect(rig.c.draft == "@\(QShot.question)")
        let ready = rig.c.recognized(text, image: qsImage, id: id)
        #expect(!QShot.startsAnything(ready), "\(ready)")
        // Attached, not pasted: the draft is as it was typed.
        #expect(QShot.isReady(rig.c.attachment), "\(String(describing: rig.c.attachment))")
        #expect(rig.c.draft == "@\(QShot.question)")
        #expect(!rig.c.draft.contains(marker) && !rig.c.draft.contains("Total due Friday"))
        #expect(rig.c.oneAtRows.first == .write(.question), "\(rig.c.oneAtRows.map(\.id))")
        #expect(rig.c.oneAtHighlighted == 0)

        let out = rig.act()
        let start = try #require(QShot.questionStart(out), "\(out)")
        #expect(start.input.contains(QShot.question), "\(start.input)")
        #expect(start.input.contains("Quarterly report \(marker)") && start.input.contains("Total due Friday"), "\(start.input)")
        #expect(rig.first?.image == qsImage, "\(String(describing: rig.c.questionConversation))")
        #expect(rig.first?.text == text.text)
        #expect(commits(rig.effects).isEmpty, "nothing went into the field: \(rig.effects)")
    }

    // MARK: e. A follow-up in the question chat

    /// A question answered (no screenshot with it), "那这个呢" typed after it.
    private func chatWithAFollowUpTyped() throws -> QShotRig {
        let rig = QShotRig(seesImages: true)
        rig.draftQuestion()
        let start = try #require(QShot.questionStart(rig.act()))
        _ = rig.c.receive(QShot.answer("这是一张季度报表。"), isFinal: true, id: start.id)
        #expect(rig.c.isQuestionChat && rig.c.phase == .choosing)
        #expect(rig.first == nil)
        rig.pinyin("nazhegene")
        #expect(rig.c.refineLine == QShot.followUp)
        return rig
    }

    @Test func e_aFollowUpTakesAScreenshotOfItsOwn() async throws {
        let marker = QShot.marker()
        let text = try await QShot.read(QShot.report(marker, second: "Paid in full"))
        let rig = try chatWithAFollowUpTyped()

        let id = try rig.pasteImage()
        #expect(QShot.isRecognizing(rig.c.followUpAttachment), "\(String(describing: rig.c.followUpAttachment))")
        let ready = rig.c.recognized(text, image: qsSecondImage, id: id)
        #expect(!QShot.startsAnything(ready), "\(ready)")
        #expect(QShot.isReady(rig.c.followUpAttachment), "\(String(describing: rig.c.followUpAttachment))")
        // Still the conversation, the follow-up as typed (the screenshot's text isn't put on its line).
        #expect(rig.c.isQuestionChat && rig.c.phase == .choosing)
        #expect(rig.c.refineLine == QShot.followUp)
        #expect(QShot.header(rig.c, language: "en").lowercased().contains("screenshot"), "\(QShot.header(rig.c, language: "en"))")
        #expect(QShot.header(rig.c, language: "zh-Hans").contains("截图"), "\(QShot.header(rig.c, language: "zh-Hans"))")

        let out = rig.act()
        let refine = try #require(QShot.refine(out), "\(out)")
        #expect(refine.refinement.turns.count == 1)
        #expect(refine.refinement.turns.last?.instruction.contains(QShot.followUp) == true, "\(refine.refinement.turns)")
        let attached = try #require(rig.c.questionConversation?.attachments[1], "\(String(describing: rig.c.questionConversation))")
        #expect(attached.image == qsSecondImage)
        #expect(attached.text == text.text)
        #expect(rig.c.questionConversation?.attachments[0] == nil, "the first question had none")
        #expect(rig.c.followUpAttachment == nil)
        #expect(commits(rig.effects).isEmpty)
    }

    @Test func e_escWithAFollowUpsScreenshotClosesAndInsertsNothing() async throws {
        let text = try await QShot.read(QShot.report(QShot.marker()))
        let rig = try chatWithAFollowUpTyped()
        try rig.screenshot(text, image: qsSecondImage)
        #expect(QShot.isReady(rig.c.followUpAttachment))

        let out = rig.key(escKey)
        #expect(commits(out).isEmpty, "\(out)")
        #expect(!out.contains { if case .replaceSelection = $0 { return true } else { return false } }, "\(out)")
        #expect(!QShot.startsAnything(out), "\(out)")
        #expect(!rig.c.isQuestionChat && !rig.c.isLevelTwo, "\(rig.c.phase)")
        #expect(rig.c.followUpAttachment == nil)
        #expect(commits(rig.effects).isEmpty)
    }

    // MARK: f. What each provider is sent

    @Test(arguments: QShotWire.allCases)
    func f_theImageGoesOnlyToAProviderThatSeesImages(wire: QShotWire) async throws {
        let marker = QShot.marker()
        let text = try await QShot.read(QShot.report(marker))
        let rig = QShotRig(seesImages: true)
        let start = try rig.ask(text, image: qsImage)
        let conversation = try #require(rig.c.questionConversation)
        #expect(conversation.attachments[0]?.image == qsImage)

        let sent = await QShot.send(wire, input: start.input, conversation: conversation, marker: marker)
        #expect(sent.error == nil, "\(wire): \(String(describing: sent.error))")
        #expect(sent.bodies.count == 1, "\(wire): \(sent.bodies.count) requests")
        let body = try #require(sent.bodies.first, "\(wire): nothing was sent")
        let texts = [QShot.question, "Quarterly report \(marker)", "Total due Friday"]
        if wire.takesImages {
            let users = try QShot.userMessages(body, wire)
            #expect(users.count == 1, "\(users)")
            QShot.expect(try #require(users.first), wire, image: qsImage, texts: texts)
            #expect(QShot.holds(body, qsImage))
        } else {
            try QShot.expectNoImage(body, wire, texts: texts)
        }
    }

    /// The same question with no image in the conversation: every provider's body is text only, as before.
    @Test(arguments: QShotWire.allCases)
    func f_noImageInTheConversationNoImageInTheRequest(wire: QShotWire) async throws {
        let marker = QShot.marker()
        let text = try await QShot.read(QShot.report(marker))
        let rig = QShotRig(seesImages: true)
        let start = try rig.ask(text, image: nil)
        #expect(rig.first?.image == nil)

        let sent = await QShot.send(wire, input: start.input, conversation: rig.c.questionConversation, marker: marker)
        #expect(sent.error == nil, "\(wire): \(String(describing: sent.error))")
        let body = try #require(sent.bodies.first, "\(wire): nothing was sent")
        try QShot.expectNoImage(body, wire, texts: [QShot.question, "Quarterly report \(marker)"])
    }

    @Test func f_aFollowUpsImageIsInItsOwnMessageAndTheFirstRoundsInTheFirst() async throws {
        let marker = QShot.marker(), second = QShot.marker()
        let firstText = try await QShot.read(QShot.report(marker))
        let secondText = try await QShot.read(QShot.report(second, second: "Paid in full"))
        let rig = QShotRig(seesImages: true)
        let start = try rig.ask(firstText, image: qsImage)
        _ = rig.c.receive(QShot.answer("这是一张季度报表。"), isFinal: true, id: start.id)
        #expect(rig.c.isQuestionChat && rig.c.phase == .choosing)
        rig.pinyin("nazhegene")
        try rig.screenshot(secondText, image: qsSecondImage)
        let out = rig.act()
        let refinement = try #require(QShot.refine(out), "\(out)").refinement
        guard case let .command(command, input) = refinement.request else {
            Issue.record("a question's follow-up: \(refinement.request)")
            return
        }
        #expect(command == .question)
        let conversation = try #require(rig.c.questionConversation)
        #expect(conversation.attachments[0]?.image == qsImage && conversation.attachments[1]?.image == qsSecondImage)

        let sent = await QShot.send(.claude, input: input, turns: refinement.turns, conversation: conversation, marker: marker)
        #expect(sent.error == nil, "\(String(describing: sent.error))")
        let body = try #require(sent.bodies.first)
        let users = try QShot.userMessages(body, .claude)
        #expect(users.count == 2, "\(users)")
        guard users.count == 2 else { return }
        QShot.expect(users[0], .claude, image: qsImage, texts: [QShot.question, "Quarterly report \(marker)"])
        QShot.expect(users[1], .claude, image: qsSecondImage, texts: [QShot.followUp, "Quarterly report \(second)", "Paid in full"])
    }

    // MARK: g. Words to hide in the screenshot's text

    @Test func g_aScreenshotWithAWordToHideGoesAsRedactedTextWithoutItsImage() async throws {
        var config = Config.default
        config.redaction = RedactionSettings(enabled: true, emails: false, phones: false, cards: false, keys: false,
                                             customWords: ["Phoenix"])

        let marker = QShot.marker()
        let text = try await QShot.read(QShot.report(marker, second: "Project Phoenix ships in May"))
        let rig = QShotRig(seesImages: true)
        let start = try rig.ask(text, image: qsImage)
        #expect(start.input.contains("Phoenix"), "the composer has it; the converter hides it: \(start.input)")
        let sent = await QShot.send(.claude, base: config, input: start.input, conversation: rig.c.questionConversation,
                                    marker: marker)
        #expect(sent.error == nil, "\(String(describing: sent.error))")
        let body = try #require(sent.bodies.first)
        let raw = String(decoding: body, as: UTF8.self)
        #expect(!raw.contains("Phoenix"), "\(raw)")
        try QShot.expectNoImage(body, .claude, texts: [QShot.question, "Quarterly report \(marker)", "ships in May"])

        // None of the words in the screenshot's text: the image goes (assumption D).
        let plainMarker = QShot.marker()
        let plainText = try await QShot.read(QShot.report(plainMarker))
        let plain = QShotRig(seesImages: true)
        let plainStart = try plain.ask(plainText, image: qsImage)
        let plainSent = await QShot.send(.claude, base: config, input: plainStart.input,
                                         conversation: plain.c.questionConversation, marker: plainMarker)
        #expect(plainSent.error == nil, "\(String(describing: plainSent.error))")
        let plainBody = try #require(plainSent.bodies.first)
        QShot.expect(try #require(try QShot.userMessages(plainBody, .claude).first), .claude, image: qsImage,
                     texts: [QShot.question, "Quarterly report \(plainMarker)"])
    }

    // MARK: h. The session drivers

    @Test func h_claudeSessionsUserMessageHasTheImageBeforeTheText() throws {
        let line = ClaudeSession.userMessage(QShot.question, images: [qsImage, qsSecondImage])
        #expect(line.last == 0x0A && line.filter { $0 == 0x0A }.count == 1, "one stream-json line")
        let object = try QShot.json(line)
        #expect(object["type"] as? String == "user")
        let message = try #require(object["message"] as? [String: Any])
        #expect(message["role"] as? String == "user")
        let content = try #require(message["content"] as? [[String: Any]], "\(message)")
        #expect(content.count == 3, "\(content)")
        guard content.count == 3 else { return }
        #expect(content.prefix(2).map { QShot.image($0, .claude) } == [qsImage, qsSecondImage], "\(content)")
        #expect(content[2]["type"] as? String == "text" && content[2]["text"] as? String == QShot.question, "\(content)")

        // With no images: the text, as a plain string or as one text block.
        let plain = try #require(try QShot.json(ClaudeSession.userMessage(QShot.question, images: []))["message"] as? [String: Any])
        if let text = plain["content"] as? String {
            #expect(text == QShot.question)
        } else {
            let blocks = try #require(plain["content"] as? [[String: Any]], "\(plain)")
            #expect(blocks.count == 1 && blocks.first?["type"] as? String == "text" && blocks.first?["text"] as? String == QShot.question,
                    "\(blocks)")
        }

        // Claude Code's driver writes that line.
        let driver: any SessionDriver = ClaudeStreamDriver()
        #expect(driver.message(QShot.question, images: [qsImage]) == [ClaudeSession.userMessage(QShot.question, images: [qsImage])])
    }

    /// `image`: what the agent's `initialize` result says of `promptCapabilities.image` (nil: nothing).
    @Test(arguments: [true, false, nil] as [Bool?])
    func h_anACPAgentGetsTheImageOnlyWhenItSaidItTakesImages(image: Bool?) throws {
        let driver = ACPDriver(directory: QShot.folder, agentSessionID: nil, mode: nil)
        let initialize = try QShot.request(driver.opening(), "initialize")
        var capabilities: [String: Any] = ["loadSession": false]
        if let image { capabilities["promptCapabilities"] = ["image": image] }
        let opened = driver.received(try QShot.result(of: initialize, ["protocolVersion": 1, "agentCapabilities": capabilities]))
        let new = try QShot.request(opened.replies, "session/new")
        _ = driver.received(try QShot.result(of: new, ["sessionId": "s1"]))

        let session: any SessionDriver = driver
        let prompt = try QShot.request(session.message(QShot.question, images: [qsImage]), "session/prompt")
        let params = try #require(prompt["params"] as? [String: Any])
        #expect(params["sessionId"] as? String == "s1")
        let content = try #require(params["prompt"] as? [[String: Any]], "\(params)")
        let text = try #require(content.last)
        #expect(text["type"] as? String == "text" && text["text"] as? String == QShot.question, "\(content)")
        if image == true {
            #expect(content.count == 2, "\(content)")
            let block = try #require(content.first)
            #expect(block["type"] as? String == "image", "\(block)")
            #expect(block["mimeType"] as? String == qsImage.mediaType, "\(block)")
            #expect(block["data"] as? String == qsImage.data.base64EncodedString(), "\(block)")
        } else {
            #expect(content.count == 1, "text only: \(content)")
            #expect(!QShot.holds(try JSONSerialization.data(withJSONObject: prompt), qsImage))
        }
    }

    @Test func h_codexGetsTheImageAsADataURLBeforeTheText() throws {
        let driver = CodexDriver(directory: QShot.folder, threadID: nil)
        let initialize = try QShot.request(driver.opening(), "initialize")
        let initialized = driver.received(try QShot.result(of: initialize, [:]))
        let config = try QShot.request(initialized.replies, "config/read")
        let read = driver.received(try QShot.result(of: config, ["config": [:] as [String: Any]]))
        let thread = try QShot.request(read.replies, "thread/start")
        _ = driver.received(try QShot.result(of: thread, ["thread": ["id": "t1"]]))

        let session: any SessionDriver = driver
        let turn = try QShot.request(session.message(QShot.question, images: [qsImage]), "turn/start")
        let params = try #require(turn["params"] as? [String: Any])
        #expect(params["threadId"] as? String == "t1")
        let input = try #require(params["input"] as? [[String: Any]], "\(params)")
        #expect(input.count == 2, "\(input)")
        guard input.count == 2 else { return }
        #expect(input[0]["type"] as? String == "image", "\(input)")
        #expect(input[0]["url"] as? String == "data:image/jpeg;base64," + qsImage.data.base64EncodedString(), "\(input)")
        #expect(input[1]["type"] as? String == "text" && input[1]["text"] as? String == QShot.question, "\(input)")

        // With no images: the text item alone, as before.
        _ = driver.received(try QShot.result(of: turn, ["turn": ["id": "turn1"]]))
        let plain = try QShot.request(session.message(QShot.followUp, images: []), "turn/start")
        let plainInput = try #require((plain["params"] as? [String: Any])?["input"] as? [[String: Any]])
        #expect(plainInput.count == 1 && plainInput.first?["type"] as? String == "text"
                && plainInput.first?["text"] as? String == QShot.followUp, "\(plainInput)")
    }

    // MARK: Promise 7: Bedrock Converse

    @Test func bedrockConverseEncodesImagesBeforeTheText() throws {
        var message = ConverseRequest.Message(role: "user", text: QShot.question)
        #expect(message.images.isEmpty)
        let plain = try QShot.json(JSONEncoder().encode(message))
        let plainContent = try #require(plain["content"] as? [[String: Any]])
        #expect(plainContent.count == 1 && plainContent.first?["text"] as? String == QShot.question, "\(plainContent)")
        #expect(plainContent.first?["image"] == nil)

        message.images = [qsImage, qsSecondImage]
        let object = try QShot.json(JSONEncoder().encode(message))
        #expect(object["role"] as? String == "user")
        let content = try #require(object["content"] as? [[String: Any]])
        #expect(content.count == 3, "\(content)")
        guard content.count == 3 else { return }
        for (block, expected) in zip(content, [(qsImage, "jpeg"), (qsSecondImage, "png")]) {
            let image = try #require(block["image"] as? [String: Any], "\(block)")
            #expect(image["format"] as? String == expected.1, "\(image)")
            #expect((image["source"] as? [String: Any])?["bytes"] as? String == expected.0.data.base64EncodedString(), "\(image)")
            #expect(block["text"] == nil)
        }
        #expect(content[2]["text"] as? String == QShot.question && content[2]["image"] == nil, "\(content)")
    }

    // MARK: i. The recent questions

    @Test func i_aQuestionAskedWithAScreenshotIsNotKept() async throws {
        let marker = QShot.marker()
        let text = try await QShot.read(QShot.report(marker))
        let rig = QShotRig(seesImages: true)
        rig.c.remembersQuestions = true
        let before = rig.c.questionHistory
        let start = try rig.ask(text, image: qsImage)
        let answered = rig.c.receive(QShot.answer("这是一张季度报表。"), isFinal: true, id: start.id)
        #expect(rig.c.isQuestionChat && rig.c.phase == .choosing, "the answer is shown: \(rig.c.phase)")
        #expect(QShot.remembered(answered) == nil, "\(answered)")
        #expect(QShot.remembered(rig.effects) == nil)
        #expect(rig.c.questionHistory.entries.isEmpty, "\(rig.c.questionHistory.entries)")
        #expect(rig.c.questionHistory == before)
        // Neither the image nor the text read in it is in what would be stored.
        let stored = try JSONEncoder().encode(rig.c.questionHistory)
        #expect(!QShot.holds(stored, qsImage))
        #expect(!String(decoding: stored, as: UTF8.self).contains(marker), "\(String(decoding: stored, as: UTF8.self))")
    }

    @Test func i_aFollowUpsScreenshotKeepsItsRoundOutOfTheRecentQuestions() async throws {
        let marker = QShot.marker()
        let text = try await QShot.read(QShot.report(marker, second: "Paid in full"))
        // The first question, with no screenshot, is answered (and kept, as before) before the follow-up is typed.
        let rig = try chatWithAFollowUpTyped()
        #expect(rig.c.remembersQuestions)
        let before = rig.c.questionHistory
        try rig.screenshot(text, image: qsSecondImage)
        let refine = try #require(QShot.refine(rig.act()), "no follow-up asked")
        let answered = rig.c.receive(QShot.answer("这张已经付清了。"), isFinal: true, id: refine.id)
        #expect(rig.c.isQuestionChat && rig.c.phase == .choosing, "the answer is shown: \(rig.c.phase)")
        #expect(QShot.remembered(answered) == nil, "\(answered)")
        #expect(rig.c.questionHistory.entries == before.entries, "\(rig.c.questionHistory.entries)")
        let stored = try JSONEncoder().encode(rig.c.questionHistory)
        #expect(!QShot.holds(stored, qsSecondImage))
        let kept = String(decoding: stored, as: UTF8.self)
        #expect(!kept.contains(marker) && !kept.contains("Paid in full") && !kept.contains("这张已经付清了。"), "\(kept)")
    }

    @Test func i_aQuestionWithNoScreenshotIsKeptAsBefore() throws {
        let rig = QShotRig(seesImages: true)
        rig.c.remembersQuestions = true
        rig.draftQuestion()
        let start = try #require(QShot.questionStart(rig.act()))
        let answered = rig.c.receive(QShot.answer("一个问题。"), isFinal: true, id: start.id)
        let entry = try #require(QShot.remembered(answered), "\(answered)")
        #expect(entry.question == QShot.question)
        #expect(entry.answer == "一个问题。")
        #expect(rig.c.questionHistory.entries == [entry], "\(rig.c.questionHistory.entries)")
    }

    // MARK: j. Which AI sees images

    @Test(arguments: QShotSeesCase.table)
    func j_providerSeesImages(row: QShotSeesCase) {
        #expect(row.provider.seesImages(model: row.model, baseURL: row.baseURL) == row.sees)
    }

    // MARK: k. What the panel says of a screenshot that is ready

    @Test(arguments: [true, false])
    func k_theHeaderSaysTheImageStaysOnlyWhenItDoes(seesImages: Bool) async throws {
        let text = try await QShot.read(QShot.report(QShot.marker()))
        let rig = QShotRig(seesImages: seesImages)
        rig.draftQuestion()
        try rig.screenshot(text, image: qsImage)
        #expect(QShot.isReady(rig.c.attachment))

        let english = QShot.header(rig.c, language: "en"), chinese = QShot.header(rig.c, language: "zh-Hans")
        #expect(english.lowercased().contains("screenshot"), "\(english)")
        #expect(chinese.contains("截图"), "\(chinese)")
        #expect(english.contains("only its text is sent") == !seesImages, "\(english)")
        #expect(chinese.contains("只发送认出的文字") == !seesImages, "\(chinese)")
    }
}

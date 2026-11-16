import AllInOneIMETestSupport
import CoreGraphics
import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
import Testing
@testable import AllInOneIMECore

/// A screenshot asked about (`PromptImage`, Composer+QuestionScreenshot.swift, Converter+Images.swift): who can see the
/// image, how each provider and CLI is sent it, the composer's attachments by round.
struct QuestionScreenshotTests {
    let image = PromptImage(data: Data([0xFF, 0xD8, 0xFF, 0x01, 0x02]), mediaType: "image/jpeg")
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    let controlV = KeyEvent(keyCode: 0x09, characters: "\u{16}", charactersIgnoringModifiers: "v", modifiers: .control)
    let commandV = KeyEvent(keyCode: 0x09, characters: "v", charactersIgnoringModifiers: "v", modifiers: .command)

    // MARK: - Who sees it

    @Test(arguments: [
        (Provider.anthropic, "claude-haiku-5-5", "https://api.anthropic.com", true),
        (.gemini, "gemini-3.8-flash", "https://generativelanguage.googleapis.com", true),
        (.openai, "gpt-6-luna", "https://api.openai.com/v1", true),
        (.openai, "gpt-6-luna", "https://API.OpenAI.com/v1/", true),
        (.openai, "deepseek-chat", "https://api.deepseek.com", false),
        (.bedrock, "us.anthropic.claude-haiku-4-5-20251001-v1:0", nil, true),
        (.bedrock, "amazon.nova-lite-v1:0", nil, true),
        (.bedrock, "amazon.nova-micro-v1:0", nil, false),
        (.bedrock, "meta.llama3-8b-instruct-v1:0", nil, false),
        (.hosted, "hosted", "https://svc.test", false),
        (.apple, "apple", nil, false),
    ] as [(Provider, String, String?, Bool)])
    func whoSeesAnImage(_ provider: Provider, _ model: String, _ base: String?, _ sees: Bool) {
        #expect(provider.seesImages(model: model, baseURL: base) == sees)
    }

    #if canImport(Vision) && canImport(ImageIO)
    @Test func visionMakesTheImageSmallerAsJPEG() throws {
        let png = try #require(VisionTextRecognizer.blankPNG as Data?)
        let small = try #require(VisionTextRecognizer().downscaled(png, longSide: 32))
        #expect(small.mediaType == "image/jpeg" && small.data.starts(with: [0xFF, 0xD8]))
        let source = try #require(CGImageSourceCreateWithData(small.data as CFData, nil))
        let size = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(size[kCGImagePropertyPixelWidth] as? Int == 32 && size[kCGImagePropertyPixelHeight] as? Int == 16)
        #expect(VisionTextRecognizer().downscaled(Data([1, 2, 3]), longSide: 32) == nil)
    }
    #endif

    // MARK: - How it's sent

    func body(_ provider: Provider, base: String, images: [PromptImage]) throws -> [String: Any] {
        var message = ConverseRequest.Message(role: "user", text: "what is this")
        message.images = images
        let request = ConverseRequest(system: [.init("s")], messages: [message], inferenceConfig: .init(maxTokens: 10),
                                      additionalModelRequestFields: nil)
        let settings = ProviderSettings(model: "m", baseURL: base)
        let http = try HTTPProviders.makeRequest(request, provider: provider, settings: settings, key: "fake-key", maxTokens: 10, timeout: 5)
        let data = try #require(http.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func theClaudeAPIGetsAnImageBlockBeforeTheText() throws {
        let sent = try body(.anthropic, base: "https://api.anthropic.com", images: [image])
        let messages = try #require(sent["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(content.count == 2 && content[0]["type"] as? String == "image" && content[1]["text"] as? String == "what is this")
        let source = try #require(content[0]["source"] as? [String: Any])
        #expect(source["media_type"] as? String == "image/jpeg" && source["data"] as? String == image.base64)
        // None: the text as before.
        let none = try body(.anthropic, base: "https://api.anthropic.com", images: [])
        let plain = try #require(none["messages"] as? [[String: Any]])
        #expect(plain.first?["content"] as? String == "what is this")
    }

    @Test func geminiGetsInlineData() throws {
        let sent = try body(.gemini, base: "https://g.test", images: [image])
        let contents = try #require(sent["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let inline = try #require(parts.first?["inline_data"] as? [String: Any])
        #expect(inline["mime_type"] as? String == "image/jpeg" && inline["data"] as? String == image.base64)
        #expect(parts.last?["text"] as? String == "what is this")
    }

    @Test func openAIsOwnAPIGetsADataURLAnotherServiceTheTextAlone() throws {
        let ownBody = try body(.openai, base: "https://api.openai.com/v1", images: [image])
        let own = try #require(ownBody["messages"] as? [[String: Any]])
        let content = try #require(own.last?["content"] as? [[String: Any]])
        #expect((content.first?["image_url"] as? [String: Any])?["url"] as? String == image.dataURL)
        let otherBody = try body(.openai, base: "https://api.deepseek.com", images: [image])
        let other = try #require(otherBody["messages"] as? [[String: Any]])
        #expect(other.last?["content"] as? String == "what is this")
    }

    @Test func theCloudServiceNeverGetsAnImage() throws {
        let data = try JSONSerialization.data(withJSONObject: try body(.hosted, base: "https://svc.test", images: [image]))
        #expect(!String(decoding: data, as: UTF8.self).contains(image.base64))
    }

    @Test func bedrockConverseEncodesAnImageBlock() throws {
        var message = ConverseRequest.Message(role: "user", text: "hi")
        message.images = [image]
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        let content = try #require(json["content"] as? [[String: Any]])
        let block = try #require(content.first?["image"] as? [String: Any])
        #expect(block["format"] as? String == "jpeg" && (block["source"] as? [String: Any])?["bytes"] as? String == image.base64)
        #expect(content.last?["text"] as? String == "hi")
    }

    @Test func roundsGetTheirOwnImageAndHiddenWordsStopThem() throws {
        var conversation = QuestionConversation(web: .open)
        conversation.attachments = [0: .init(text: "a", image: image), 1: .init(text: "b", image: nil)]
        var config = Config.default
        config.provider = .anthropic
        let request = ConverseRequest(system: [], messages: [.init(role: "user", text: "q1"), .init(role: "assistant", text: "a1"),
                                                             .init(role: "user", text: "q2")],
                                      inferenceConfig: .init(maxTokens: 10), additionalModelRequestFields: nil)
        let sent = Converter.attaching(Converter.images(conversation, hidden: 0), to: request, config: config)
        #expect(sent.messages.map { $0.images.count } == [1, 0, 0])
        #expect(Converter.images(conversation, hidden: 1).isEmpty)
        config.provider = .hosted
        #expect(Converter.attaching(Converter.images(conversation, hidden: 0), to: request, config: config) == request)
        // A follow-up's screenshot text goes with it; the first question's is in it already.
        let turns = [Refinement.Turn(answer: .empty, instruction: "and this?")]
        #expect(Converter.withScreenshots(turns, conversation).first?.instruction == Prompt.withScreenshot("and this?", "b"))
    }

    @Test func eachCLIIsSentTheImage() throws {
        let claude = try #require(JSONSerialization.jsonObject(with: ClaudeSession.userMessage("q", images: [image])) as? [String: Any])
        let content = try #require((claude["message"] as? [String: Any])?["content"] as? [[String: Any]])
        #expect(content.first?["type"] as? String == "image" && content.last?["text"] as? String == "q")
        #expect(ClaudeSession.userMessage("q", images: []) == ClaudeSession.userMessage("q"))
        for takes in [true, false] {
            let prompt = try acpPrompt(takesImages: takes)
            #expect((prompt.first?["type"] as? String == "image") == takes)
            #expect(prompt.last?["text"] as? String == "q")
        }
        let input = try codexInput()
        #expect(input.first?["type"] as? String == "image" && input.first?["url"] as? String == image.dataURL)
    }

    func line(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    /// An ACP agent that says whether it takes images, asked once its session is open: the prompt's blocks.
    func acpPrompt(takesImages: Bool) throws -> [[String: Any]] {
        let driver = ACPDriver(directory: FileManager.default.temporaryDirectory, agentSessionID: nil, mode: nil)
        _ = driver.opening()
        #expect(driver.message("q", images: [image]).isEmpty)  // queued until the session is open
        let capabilities: [String: Any] = ["loadSession": true, "promptCapabilities": ["image": takesImages]]
        _ = driver.received(try line(["jsonrpc": "2.0", "id": 1, "result": ["agentCapabilities": capabilities]]))
        let replies = driver.received(try line(["jsonrpc": "2.0", "id": 2, "result": ["sessionId": "s1"]])).replies
        let last = try #require(replies.last)
        let sent = try #require(try JSONSerialization.jsonObject(with: last) as? [String: Any])
        return try #require((sent["params"] as? [String: Any])?["prompt"] as? [[String: Any]])
    }

    /// Codex's `turn/start` input once its thread is open.
    func codexInput() throws -> [[String: Any]] {
        let driver = CodexDriver(directory: FileManager.default.temporaryDirectory, threadID: nil)
        _ = driver.opening()
        _ = driver.message("q", images: [image])
        _ = driver.received(try line(["id": 1, "result": [:]]))
        _ = driver.received(try line(["id": 2, "result": ["config": [:]]]))
        let replies = driver.received(try line(["id": 3, "result": ["thread": ["id": "t1"]]])).replies
        let turn = try #require(replies.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .first { $0["method"] as? String == "turn/start" })
        return try #require((turn["params"] as? [String: Any])?["input"] as? [[String: Any]])
    }

    // MARK: - The composer

    func type(_ text: String, _ c: Composer) {
        for ch in text { _ = c.handleKeyDown(ch == " " ? spaceKey : k(String(ch))) }
    }

    func composer(sees: Bool) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.remembersQuestions = true
        c.setInputMode(.english)
        c.aiSeesImages = { sees }
        return c
    }

    func lines(_ texts: [String]) -> ScreenText {
        ScreenText(lines: texts.enumerated().map {
            RecognizedLine(text: $1, box: CGRect(x: 0.05, y: 0.1 + Double($0) * 0.1, width: 0.4, height: 0.03), confidence: 0.9)
        })
    }

    /// ⌃V (or `key`) with an image, read as `text` (nil: no text in it) with `image`.
    @discardableResult
    func pasteScreenshot(_ c: Composer, text: ScreenText?, key: KeyEvent? = nil) -> [Composer.Effect] {
        guard case let .readClipboard(id)? = c.handleKeyDown(key ?? controlV).effects.last else { return [] }
        guard case let .recognizeText(_, recognition)? = c.pasted(.image(Data([1, 2, 3])), id: id).last else { return [] }
        return c.recognized(text, image: image, id: recognition)
    }

    func questionDraft(_ c: Composer, _ question: String) {
        _ = c.handleKeyDown(at)
        type("question", c)
        _ = c.handleKeyDown(tab)
        type(question, c)
    }

    @Test func aQuestionGoesWithItsScreenshotsTextAndImage() {
        let c = composer(sees: true)
        questionDraft(c, "what is this")
        pasteScreenshot(c, text: lines(["Error 42"]))
        let out = c.handleKeyDown(enterKey).effects
        guard case let .startCommand(.question, input, _)? = out.first else {
            Issue.record("not asked: \(out)")
            return
        }
        #expect(input == Prompt.withScreenshot("what is this", "Error 42"))
        #expect(c.questionConversation?.attachments[0] == .init(text: "Error 42", image: image))
        #expect(SessionText.attachmentHeader(c, language: "en").joined().contains("goes to the AI")
            || SessionText.attachmentHeader(c, language: "en").joined().contains("go to the AI"))
    }

    @Test func aScreenshotWithoutTextIsKeptOnlyForAnAIThatSeesIt() {
        let sees = composer(sees: true)
        questionDraft(sees, "what is this")
        pasteScreenshot(sees, text: nil)
        guard case .screenshot(.ready)? = sees.attachment else {
            Issue.record("not kept: \(String(describing: sees.attachment))")
            return
        }
        _ = sees.handleKeyDown(enterKey)
        #expect(sees.questionConversation?.attachments[0]?.image == image)
        let blind = composer(sees: false)
        questionDraft(blind, "what is this")
        let out = pasteScreenshot(blind, text: nil)
        #expect(blind.attachment == nil && out.contains(.notice(blind.messages.reply.noText)))
    }

    @Test func oneAtTakesTheScreenshotAndOffersAskAIFirst() {
        let c = composer(sees: true)
        c.commands = Command.catalog([])
        _ = c.handleKeyDown(at)
        type("what is this", c)
        pasteScreenshot(c, text: lines(["Error 42"]))
        #expect(c.draft == "@what is this")
        #expect(c.oneAtRows.first == .write(.question))
        _ = c.handleKeyDown(enterKey)
        #expect(c.questionConversation?.attachments[0]?.image == image)
    }

    @Test func aFollowUpTakesAScreenshotOfItsOwn() {
        let c = composer(sees: true)
        questionDraft(c, "what is rust")
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("A language.")]), isFinal: true, id: 1)
        type("and this", c)
        pasteScreenshot(c, text: lines(["fn main"]))
        guard case .screenshot(.ready)? = c.followUpAttachment else {
            Issue.record("not attached: \(String(describing: c.followUpAttachment))")
            return
        }
        #expect(SessionText.followUpHeader(c, language: "en").count == 1)
        let out = c.handleKeyDown(enterKey).effects
        #expect(out.contains { if case .startRefine = $0 { true } else { false } })
        #expect(c.questionConversation?.attachments[1] == .init(text: "fn main", image: image))
        #expect(c.followUpAttachment == nil)
        // Answered, it isn't kept in the recent questions (the screenshot's text may be someone else's).
        #expect(c.receive(ConversionResult(versions: [CandidateLine("It's Rust.")]), isFinal: true, id: 2)
            .allSatisfy { if case .rememberQuestion = $0 { false } else { true } })
    }

    @Test func backspaceOnAnEmptyLineTakesTheFollowUpsScreenshotAway() {
        let c = composer(sees: true)
        questionDraft(c, "what is rust")
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("A language.")]), isFinal: true, id: 1)
        pasteScreenshot(c, text: lines(["fn main"]))
        #expect(c.followUpAttachment != nil)
        _ = c.handleKeyDown(backspaceKey)
        #expect(c.followUpAttachment == nil && c.isQuestionChat)
    }

    /// "@question what is rust" asked and answered, then a follow-up with a screenshot asked (request 2).
    func askedWithFollowUpScreenshot() -> Composer {
        let c = composer(sees: true)
        questionDraft(c, "what is rust")
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("A language.")]), isFinal: true, id: 1)
        type("and this", c)
        pasteScreenshot(c, text: lines(["fn main"]))
        _ = c.handleKeyDown(enterKey)
        return c
    }

    @Test func aRoundTakenBackTakesItsScreenshotWithIt() {
        let c = askedWithFollowUpScreenshot()
        _ = c.receive(ConversionResult(versions: [CandidateLine("It's Rust.")]), isFinal: true, id: 2)
        #expect(c.questionConversation?.attachments[1] != nil)
        _ = c.handleKeyDown(backspaceKey)  // a round back
        #expect(c.questionConversation?.attachments[1] == nil && c.followUpAttachment == nil)
        type("what else", c)
        _ = c.handleKeyDown(enterKey)
        #expect(c.questionConversation?.attachments.isEmpty == true)
    }

    @Test func aFailedFollowUpGetsItsScreenshotBackOnTheLine() {
        let c = askedWithFollowUpScreenshot()
        _ = c.fail("offline", id: 2)
        #expect(c.questionConversation?.attachments[1] == nil)
        guard case .screenshot(.ready)? = c.followUpAttachment else {
            Issue.record("not back: \(String(describing: c.followUpAttachment))")
            return
        }
        _ = c.handleKeyDown(enterKey)
        #expect(c.questionConversation?.attachments[1]?.image == image)
    }

    @Test func commandVInTheConversationStaysTheAppsOnTheMac() {
        let c = composer(sees: true)
        questionDraft(c, "what is rust")
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("A language.")]), isFinal: true, id: 1)
        #expect(!c.handleKeyDown(commandV).effects.contains { if case .readClipboard = $0 { true } else { false } })
    }

    @Test func noAIOneAtPastesTheScreenshotsTextAsBefore() {
        let c = composer(sees: true)
        c.commands = Command.catalog([])
        c.aiAllowed = { false }
        _ = c.handleKeyDown(at)
        type("see", c)
        pasteScreenshot(c, text: lines(["Error 42"]))
        #expect(c.attachment == nil && c.draft.contains("Error 42"))
    }
}


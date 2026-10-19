import AllInOneIMECore
import AppKit
import InputMethodKit
import os

/// A Claude API endpoint for the @reply checks: answers every request with three replies (streamed) and keeps each body,
/// so what left the Mac is read back. Nothing goes to the network.
final class ReplySelfTestEndpoint: URLProtocol, @unchecked Sendable {
    private static let bodies = OSAllocatedUnfairLock(initialState: [String]())
    static var sent: [String] { bodies.withLock { $0 } }
    static func reset() { bodies.withLock { $0 = [] } }
    static let answer = "Sure, Friday works.\n---\nFriday is fine with me.\n---\nLet's do Friday then."

    @MainActor
    static func converter() -> Converter {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReplySelfTestEndpoint.self]
        var config = SelfTest.settings
        config.provider = .anthropic
        config.anthropic.baseURL = "https://reply-selftest.invalid"
        config.anthropic.model = "claude-selftest"
        let fixed = config
        return Converter(client: BedrockClient(session: URLSession(configuration: configuration)), loadConfig: { fixed },
                         loadCredentials: { _ in throw ProviderError.missingKey(.anthropic) }, loadKey: { _, _ in "sk-test" },
                         loadJargon: { _ in [] })
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
        let sent = String(decoding: body, as: UTF8.self)
        Self.bodies.withLock { $0.append(sent) }
        guard let url = request.url else { return }
        let delta = (try? JSONSerialization.data(withJSONObject: [
            "type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": Self.answer],
        ] as [String: Any])) ?? Data()
        let sse = [
            "event: message_start", #"data: {"type":"message_start","message":{"id":"msg_1"}}"#, "",
            "event: content_block_delta", "data: " + String(decoding: delta, as: UTF8.self), "",
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#, "",
            #"data: {"type":"message_stop"}"#, "", "",
        ].joined(separator: "\n")
        let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(sse.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A text field that keeps its marked text in its text, as NSTextView does (`FakeTextClient` keeps it apart): the text
/// around the caret is read past it.
final class MarkedInTextClient: FakeTextClient {
    private var whole: String {
        let text = document as NSString
        let at = min(insertionPoint ?? text.length, text.length)
        return text.replacingCharacters(in: NSRange(location: at, length: 0), with: marked)
    }

    override func markedRange() -> NSRange {
        marked.isEmpty ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: min(insertionPoint ?? (document as NSString).length, (document as NSString).length),
                      length: (marked as NSString).length)
    }

    override func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        let text = whole as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= text.length else { return nil }
        return NSAttributedString(string: text.substring(with: range))
    }

    override func length() -> Int { (whole as NSString).length }
}

extension SelfTest {
    /// A PNG of `lines` drawn black on white, as a screenshot of a conversation: the first on the left, the next on the
    /// right, and so on.
    static func screenshotPNG(_ lines: [String], size: NSSize = NSSize(width: 900, height: 320)) -> Data? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.black]
        for (index, line) in lines.enumerated() {
            let text = line as NSString
            let width = text.size(withAttributes: attributes).width
            let y = size.height - CGFloat(index + 1) * 70
            text.draw(at: NSPoint(x: index % 2 == 0 ? 30 : size.width - width - 30, y: y), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Screenshots and @reply on this Mac: Vision reads a rendered screenshot quickly once warmed up; the clipboard gives
    /// a PNG or a TIFF, never a concealed one, its text before an image; nothing is read during secure input; the text
    /// around the caret comes through IMK, past the draft; a screenshot pasted into @reply is read here and only its text
    /// is sent; @reply in Chrome takes the page along; a custom @reply renamed is said once.
    static func testReply(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        section("screenshots: read on this Mac (Vision)")
        let conversation = ["明天能来加班吗？", "Meeting moved to Friday"]
        let png = screenshotPNG(conversation)
        check(png != nil, "a screenshot of a conversation rendered (\(png?.count ?? 0) bytes)")
        let vision = VisionTextRecognizer()
        let warm = Date()
        _ = runAsync(40) { await vision.prepare(languages: ["zh-Hans", "en-US"]) }
        print(String(format: "  Vision warmed up in %.2fs", Date().timeIntervalSince(warm)))
        if let png {
            // The first real read may still load what the warm-up didn't need.
            let first = Date()
            _ = runAsync(30) { try await ScreenText.recognize(png, with: vision, languages: ["zh-Hans", "en-US"]) }
            print(String(format: "  the first read after it: %.2fs", Date().timeIntervalSince(first)))
            let started = Date()
            let outcome = runAsync(10) { () async -> Result<ScreenText, Error> in
                do { return .success(try await ScreenText.recognize(png, with: vision, languages: ["zh-Hans", "en-US"])) } catch {
                    return .failure(error)
                }
            }
            if case let .failure(error)? = outcome { print("  Vision: \(error)") }
            let read = try? outcome?.get()
            let seconds = Date().timeIntervalSince(started)
            let text = read?.text ?? ""
            check(text.contains("加班") && text.contains("Friday") && seconds < 2,
                  String(format: "Vision reads its Chinese and English in %.2fs, once warm (%@)", seconds, text.replacingOccurrences(of: "\n", with: " | ")))
            check(read?.transcript.labelled == true && read?.transcript.text.hasPrefix("them: ") == true,
                  "the left line is the other party's, the right one the user's (\(read?.transcript.text.replacingOccurrences(of: "\n", with: " | ") ?? "-"))")
        }

        section("screenshots: the clipboard")
        func reads(_ fill: (NSPasteboard) -> Void) -> ClipboardContent {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            board.clearContents()
            fill(board)
            return AllInOneIMEInputController.clipboardContent(board)
        }
        let image = png ?? Data([0x89, 0x50, 0x4E, 0x47])
        check(reads { $0.setData(image, forType: .png) } == .image(image), "a PNG is taken as an image")
        let tiff = NSImage(data: image)?.tiffRepresentation ?? Data([0x4D, 0x4D, 0, 0x2A])
        check(reads { $0.setData(tiff, forType: .tiff) } == .image(tiff), "a TIFF is taken as an image")
        let concealed = NSPasteboardItem()
        concealed.setData(image, forType: .png)
        concealed.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        check(reads { $0.writeObjects([concealed]) } == .none, "an image marked concealed is not taken")
        let both = NSPasteboardItem()
        both.setString("their message", forType: .string)
        both.setData(image, forType: .png)
        check(reads { $0.writeObjects([both]) } == .text("their message"), "text and an image on the clipboard: the text is taken")

        section("@reply: a screenshot pasted, read here, its text sent", needs: .composing)
        let (converterBefore, secureBefore, clipboardBefore) = (controller.services.converter, controller.services.secureInputActive, controller.readClipboard)
        let (recognizerBefore, pageProcessBefore, pageBefore) = (controller.services.recognizeText, controller.pageProcess, controller.readPageContext)
        defer {
            (controller.services.converter, controller.services.secureInputActive, controller.readClipboard) = (converterBefore, secureBefore, clipboardBefore)
            (controller.services.recognizeText, controller.pageProcess, controller.readPageContext) = (recognizerBefore, pageProcessBefore, pageBefore)
            controller.commitComposition(client)
            client.inserted.removeAll()
        }
        controller.services.converter = ReplySelfTestEndpoint.converter()
        controller.services.recognizeText = vision
        controller.commitComposition(client)
        func startReply() {
            press(controller, client, "@", code: 0x13, flags: .shift)
            type("reply", controller, client)
            press(controller, client, "\t", code: VirtualKey.tab)
        }
        func controlV() { press(controller, client, "v", code: 0x09, flags: .control) }
        var clipboardReads = 0
        controller.readClipboard = { clipboardReads += 1; return .image(image) }
        startReply()
        check(client.marked == "reply › " && controller.panelModel().status == .hint("回复对方：⌃V 粘贴消息或截图"),
              "@reply says what it takes (\(client.marked) | \(controller.panelModel().status))")
        ReplySelfTestEndpoint.reset()
        controlV()
        let ready = pump(timeout: 15) { if case .screenshot(.ready)? = controller.composer.attachment { return true } else { return false } }
        let header = controller.panelModel().header ?? ""
        check(ready && clipboardReads == 1 && header.hasPrefix("截图 · 2 行（本机识别）") && header.contains("图片不会离开这台 Mac"),
              "⌃V: the screenshot is read on this Mac, the panel says so (\(header.replacingOccurrences(of: "\n", with: " | ")))")
        _ = enter(controller, client)
        _ = pump(timeout: 10) { controller.composer.phase == .choosing }
        let sent = ReplySelfTestEndpoint.sent.last ?? ""
        check(controller.composer.choices.filter { $0.kind == .answer }.map(\.text)
              == ["Sure, Friday works.", "Friday is fine with me.", "Let's do Friday then."],
              "three replies to pick from (\(controller.composer.choices.map(\.text)))")
        check(sent.contains("<screenshot>") && sent.contains("加班") && sent.contains("them: ") && !sent.contains("iVBOR")
              && sent.count < 20_000, "what was sent is the screenshot's text, never the image (\(sent.count) bytes)")
        check(controller.panelModel().footer.hasPrefix("⌘R 再写三条"), "the footer offers three more (\(controller.panelModel().footer))")
        _ = press(controller, client, "2", code: 0x13)
        check(client.inserted.last == "Friday is fine with me.", "2 inserts the second reply (\(client.inserted.last ?? "-"))")

        section("@reply after a selection: the selection kept, the reply after it")
        let quoted = FakeTextClient()
        quoted.document = "Lunch tomorrow? Bye"
        let message = Composer.Selection(text: "Lunch tomorrow?", range: 0..<("Lunch tomorrow?" as NSString).length)
        quoted.selection = NSRange(location: 0, length: message.range!.count)
        controller.replaceSelection("Lunch tomorrow?\nSure!", message, in: quoted)
        check(quoted.document == "Lunch tomorrow?\nSure! Bye" && quoted.inserted == ["\nSure!"],
              "only the reply goes in, at the selection's end (\(quoted.document.debugDescription) | \(quoted.inserted))")
        let unknown = Composer.Selection(text: "Lunch tomorrow?")
        check(AllInOneIMEInputController.afterSelection("Lunch tomorrow?\nSure!", unknown) == nil
              && AllInOneIMEInputController.afterSelection("Sure!", message) == nil,
              "without its range, or a result that doesn't start with it: the selection is replaced, as before")

        section("@reply: nothing read during secure input", needs: .composing)
        clipboardReads = 0
        controller.services.secureInputActive = { true }
        startReply()
        controlV()
        _ = pump(timeout: 0.5) { false }
        check(clipboardReads == 0 && controller.composer.attachment == nil, "⌃V during secure input reads no clipboard (\(clipboardReads))")
        check(controller.readFieldText(from: client) == nil, "nor the field's text")
        controller.commitComposition(client)
        controller.services.secureInputActive = secureBefore

        section("@reply: the text around the caret, through IMK", needs: .composing)
        let field = MarkedInTextClient()
        field.document = "Hi Li, about the offsite: See you then."
        field.insertionPoint = ("Hi Li, about the offsite: " as NSString).length
        field.marked = "reply › 好"
        let around = controller.readFieldText(from: field)
        check(around == FieldText(before: "Hi Li, about the offsite: ", after: "See you then."),
              "before and after the caret, without the draft (\(String(describing: around)))")
        let selected = FakeTextClient()
        selected.document = "Can you come in tomorrow? Thanks"
        selected.selection = NSRange(location: 0, length: ("Can you come in tomorrow?" as NSString).length)
        let past = controller.readFieldText(from: selected)
        check(past == FieldText(before: "", after: " Thanks"), "with a selection: the text past it (\(String(describing: past)))")
        let terminal = FakeTextClient()
        terminal.document = "ls -la"
        terminal.bundleIDOverride = "com.apple.Terminal"
        check(controller.readFieldText(from: terminal) == nil, "none in a terminal")

        section("@reply in Chrome takes the page", needs: .composing)
        // A process that doesn't exist: the page tree is asked of no one (the page is the stand-in's).
        var pid: pid_t = 99_999
        while kill(pid, 0) == 0 || errno != ESRCH { pid -= 1 }
        controller.pageProcess = { _ in pid }
        controller.readPageContext = { _, _ in
            PageContext(url: "https://mail.example.com/thread/1", title: "Lunch on Friday?",
                        visible: "Ana: Are you free for lunch on Friday?")
        }
        controller.readClipboard = { .none }
        ReplySelfTestEndpoint.reset()
        startReply()
        _ = enter(controller, client)
        _ = pump(timeout: 10) { controller.composer.phase == .choosing }
        let withPage = ReplySelfTestEndpoint.sent.last ?? ""
        check(withPage.contains("<page") && withPage.contains("free for lunch on Friday") && withPage.contains("mail.example.com"),
              "@reply alone in Chrome sends the page as its context (\(withPage.count) bytes)")
        controller.commitComposition(client)

        section("a custom @reply renamed, said once")
        let suite = "AllInOneIME-selftest-renames-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        var own = Config.default
        own.customCommands = [CustomCommand(name: "reply", type: .prompt, prompt: "Reply politely.")]
        try? own.write(to: url)
        let renamed = BuiltinRenames.apply(configURL: url, defaults: defaults, taken: [])
        let written = (try? Config.load(from: url))?.customCommands.map(\.name) ?? []
        check(renamed.map(\.new) == ["myreply"] && written == ["myreply"] && BuiltinRenames.apply(configURL: url, defaults: defaults, taken: []).isEmpty,
              "the custom @reply is @myreply in the config, once (\(written))")
        let takeBefore = controller.services.takeRenameNotice
        defer { controller.services.takeRenameNotice = takeBefore }
        controller.services.takeRenameNotice = { BuiltinRenames.takeNotice($0, defaults: defaults) }
        controller.notice = nil
        controller.activateServer(client)
        let first = controller.notice
        controller.notice = nil
        controller.activateServer(client)
        check(first == "你自己的 @reply 改名为 @myreply：@reply 现在是内置命令" && controller.notice == nil,
              "the next text field says so, once (\(first ?? "-"))")
    }
}

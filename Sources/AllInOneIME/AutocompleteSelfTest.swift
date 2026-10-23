import AllInOneIMECore
import AppKit
import Carbon
import InputMethodKit
import os

/// The self-test's harness window for autocomplete: a window of its own with an NSTextView in it, as an input method's
/// client (`IMKTextInput`), so the suggestion is placed at a real caret. Invisible and click-through (someone may be using
/// this Mac); keys reach it only through the controller (`handle`), never posted, and what the controller lets through is
/// typed into it as the app would (`AutocompleteHarness.key`).
final class HarnessTextClient: NSObject, IMKTextInput {
    let window: NSWindow
    let textView: NSTextView
    var bundleID = "com.aipinyin.selftest.harness"
    /// How far up the rect for an empty range is told, off the caret's line (as Notes's has been); the line's rect
    /// (`attributes(forCharacterIndex:lineHeightRectangle:)`) stays right.
    var emptyRangeOffset: CGFloat = 0

    override init() {
        window = NSWindow(contentRect: NSRect(x: 240, y: 360, width: 520, height: 44), styleMask: [.titled], backing: .buffered,
                          defer: false)
        window.title = "AllInOneIME self-test: autocomplete"
        window.isReleasedWhenClosed = false
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 44))
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 10, height: 12)
        window.contentView = textView
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        super.init()
        window.orderFrontRegardless()
    }

    var text: String {
        get { textView.string }
        set {
            textView.string = newValue
            textView.setSelectedRange(NSRange(location: (newValue as NSString).length, length: 0))
        }
    }

    func close() { window.orderOut(nil) }

    func insertText(_ string: Any!, replacementRange: NSRange) {
        textView.insertText(string as Any, replacementRange: replacementRange)
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        textView.setMarkedText(string as Any, selectedRange: selectionRange, replacementRange: replacementRange)
    }

    func selectedRange() -> NSRange { textView.selectedRange() }
    func markedRange() -> NSRange { textView.markedRange() }

    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        textView.attributedSubstring(forProposedRange: range, actualRange: nil)
    }

    func length() -> Int { (textView.string as NSString).length }

    func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { NSNotFound }

    /// The caret's line and the font there, as an app tells them.
    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
        lineRect?.pointee = lineRectangle
        return [NSAttributedString.Key.font: textView.font ?? NSFont.systemFont(ofSize: 15)]
    }

    var lineRectangle: NSRect {
        textView.firstRect(forCharacterRange: NSRange(location: textView.selectedRange().location, length: 0), actualRange: nil)
    }

    /// Where the text's baseline is on the screen, at the character before the caret, as the text view laid it out.
    var baseline: CGFloat? {
        let index = textView.selectedRange().location - 1
        guard index >= 0 else { return nil }
        var point: NSPoint?
        if let manager = textView.textLayoutManager, let content = manager.textContentManager,
           let location = content.location(content.documentRange.location, offsetBy: index),
           let fragment = manager.textLayoutFragment(for: location) {
            let offset = content.offset(from: fragment.rangeInElement.location, to: location)
            if let line = fragment.textLineFragments.first(where: { $0.characterRange.contains(offset) }) ?? fragment.textLineFragments.last {
                let origin = fragment.layoutFragmentFrame.origin
                point = NSPoint(x: origin.x, y: origin.y + line.typographicBounds.minY + line.glyphOrigin.y)
            }
        } else if let manager = textView.layoutManager {
            let glyph = manager.glyphIndexForCharacter(at: index)
            let fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            point = NSPoint(x: fragment.minX, y: fragment.minY + manager.location(forGlyphAt: glyph).y)
        }
        guard let point else { return nil }
        let inView = NSPoint(x: point.x + textView.textContainerOrigin.x, y: point.y + textView.textContainerOrigin.y)
        return window.convertPoint(toScreen: textView.convert(inView, to: nil)).y
    }

    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { bundleID }
    func windowLevel() -> CGWindowLevel { CGWindowLevelForKey(.normalWindow) }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "allinoneime-selftest-harness" }

    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! {
        (textView.string as NSString).substring(with: range)
    }

    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect {
        let rect = textView.firstRect(forCharacterRange: aRange, actualRange: actualRange)
        return aRange.length == 0 ? rect.offsetBy(dx: 0, dy: emptyRangeOffset) : rect
    }
}

/// Stands in for the on-device model in the self-test: answers each request by how its text ends (`answers`), and
/// counts them. Nothing is sent anywhere.
final class AutocompleteStubModel: AppleModelBackend, @unchecked Sendable {
    let availability: AppleModelAvailability
    let contextSize = 4096
    let supportedLanguages: Set<String> = ["en", "zh", "ja", "fr", "de", "es"]
    private let lock = NSLock()
    private var _prompts: [String] = []
    var prompts: [String] { lock.withLock { _prompts } }

    init(_ availability: AppleModelAvailability = .available) { self.availability = availability }

    /// What it says after text ending this way (the request's `<before>…</before>`).
    static let answers: [(ending: String, answer: String)] = [
        ("Hello wor", "ld, how are you? I hope"), ("you? Se", "e you soon. Bye"), ("you? See yo", "u soon. Bye"), ("你好", "，今天怎么样？还好吗"),
        ("Let me know", " when you are free."), ("Write to", " [EMAIL_1] by Friday."),
    ]

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        lock.withLock { _prompts.append(request.prompt) }
        let before = request.prompt.components(separatedBy: "</before>").first ?? ""
        let answer = Self.answers.first { before.hasSuffix($0.ending) }?.answer ?? " and more."
        return AsyncThrowingStream { continuation in
            continuation.yield(AppleModelSnapshot(text: answer))
            continuation.finish()
        }
    }
}

/// A Claude API endpoint for autocomplete's cloud check: answers each request with a continuation, keeps its body.
/// Nothing goes to the network.
final class AutocompleteSelfTestEndpoint: URLProtocol, @unchecked Sendable {
    private static let bodies = OSAllocatedUnfairLock(initialState: [String]())
    static var sent: [String] { bodies.withLock { $0 } }

    /// The user's message in a request's body (the Claude API's JSON).
    static func message(of body: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let messages = object["messages"] as? [[String: Any]], let last = messages.last else { return "" }
        if let text = last["content"] as? String { return text }
        return (last["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
    }

    /// A converter whose Claude API is this endpoint, with `config`'s answer about sending it text.
    static func converter(_ config: Config) -> Converter {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AutocompleteSelfTestEndpoint.self]
        var config = config
        config.provider = .anthropic
        config.anthropic.baseURL = "https://autocomplete-selftest.invalid"
        config.anthropic.model = "claude-selftest"
        let fixed = config
        return Converter(client: BedrockClient(session: URLSession(configuration: configuration)), loadConfig: { fixed },
                         loadCredentials: { _ in throw ProviderError.missingKey(.anthropic) }, loadKey: { _, _ in "sk-test" },
                         loadJargon: { _ in [] }, appleModel: AutocompleteStubModel(.appleIntelligenceNotEnabled))
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
            "type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": " when you are free. Thanks"],
        ] as [String: Any])) ?? Data()
        let sse = [
            "event: message_start", #"data: {"type":"message_start","message":{"id":"msg_1","usage":{"input_tokens":120}}}"#, "",
            "event: content_block_delta", "data: " + String(decoding: delta, as: UTF8.self), "",
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":7}}"#, "",
            #"data: {"type":"message_stop"}"#, "", "",
        ].joined(separator: "\n")
        let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(sse.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension SelfTest {
    /// A key into the harness window through the controller; what the controller lets through is typed into the window
    /// as the app types it (a character, a Tab). True: the controller took it.
    @discardableResult
    static func harnessKey(_ c: AllInOneIMEInputController, _ h: HarnessTextClient, _ characters: String, code: UInt16,
                           flags: NSEvent.ModifierFlags = []) -> Bool {
        let handled = c.handle(event(characters, code: code, flags: flags), client: h)
        guard !handled, flags.isDisjoint(with: [.command, .control]) else { return handled }
        if code == VirtualKey.tab {
            if flags.isDisjoint(with: [.shift, .option]) { h.insertText("\t", replacementRange: h.selectedRange()) }
        } else if let scalar = characters.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F,
                  !(0xF700...0xF8FF).contains(scalar.value) {
            h.insertText(characters, replacementRange: h.selectedRange())
        }
        return handled
    }

    static func harnessType(_ text: String, _ c: AllInOneIMEInputController, _ h: HarnessTextClient) {
        for character in text {
            let lower = Character(character.lowercased())
            let shifted = character.isUppercase || "?!@".contains(character)
            let code = keyCodes[lower] ?? (character == "?" ? 0x2C : character == "." ? 0x2F : 0)
            harnessKey(c, h, String(character), code: code, flags: shifted ? .shift : [])
        }
    }

    /// Autocomplete (`Autocomplete`, the core's; the overlay, the switch and the field read, the Mac's): the switch in
    /// the input menu and the menu bar panel (nothing asks first: they say where the text goes), then a harness window of
    /// its own with a stand-in model: the suggestion after the caret, Tab, typing along, Esc, ⇧Tab, a Tab right as it
    /// appears, pinyin, where it never runs, the candidate panel's line where there's no caret rect, an app's own choice,
    /// an app where it stops for want of use, turning it on with a cloud provider picked and the provider asked through a
    /// local endpoint; last, Apple's on-device model where it's available. Writes `autocomplete.png` and
    /// `autocomplete-zh.png` (the READMEs' images).
    static func testAutocomplete(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("autocomplete: the switch (input menu, menu bar panel)")
        let configFile = try? Data(contentsOf: Config.defaultURL)
        let store = AutocompleteSwitch.store
        defer { if let configFile { try? configFile.write(to: Config.defaultURL) } }
        let toggle = #selector(AllInOneIMEInputController.toggleAutocomplete(_:))
        func menuItem(_ action: Selector) -> NSMenuItem? { controller.menu()?.items.first { $0.action == action } }
        func line() -> NSMenuItem? {
            let items = controller.menu()?.items ?? []
            guard let index = items.firstIndex(where: { $0.action == toggle }), items.indices.contains(index + 1) else { return nil }
            return items[index + 1].tag == AllInOneIMEInputController.autocompleteDestinationTag ? items[index + 1] : nil
        }
        // The self-test's config is Bedrock's: the switch names it and its model, and what each pause would send there,
        // before it's turned on.
        let bedrock = "Amazon Bedrock · " + ((try? Config.load())?.modelId ?? "")
        check(menuItem(toggle)?.title == tr("续写（\(bedrock)）", "Autocomplete (\(bedrock))") && menuItem(toggle)?.state == .off,
              "the input menu has 续写, off, with the provider and its model (\(menuItem(toggle)?.title ?? "none"))")
        check(line()?.title.hasPrefix(tr("每次停顿会把光标所在行和它前面同一语言的最多 200 字", "Each pause sends the caret's line and up to 200 characters before it in the same language")) == true
              && line()?.title.contains(bedrock) == true && line()?.isEnabled == false,
              "under it, what each pause sends there (\(line()?.title ?? "none"))")
        // Turned on: on at once, and nothing asks.
        let visible = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        controller.toggleAutocomplete(nil)
        let asked = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) && !visible.contains(ObjectIdentifier($0)) }
        check((try? Config.load())?.autocomplete == true && NSApp.modalWindow == nil && asked.isEmpty && menuItem(toggle)?.state == .on,
              "turned on with Bedrock picked: on at once, no question (\(asked.map(\.title)))")
        controller.toggleAutocomplete(nil)
        check((try? Config.load())?.autocomplete == false && store.metrics.turnedOn == 1 && store.metrics.turnedOffWithinADay == 1,
              "off again; counted as turned off within a day (\(store.metrics.turnedOn), \(store.metrics.turnedOffWithinADay))")
        // The menu bar panel's switch, with stand-ins (it writes nothing here).
        let stand = PanelStandIns()
        let panel = FloatingPanel(sources: stand.sources)
        panel.prepareWindow = { window in
            window.alphaValue = 0
            window.ignoresMouseEvents = true
        }
        panel.checksOcclusion = false
        let screen = NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 875)
        panel.show(below: CGRect(x: screen.maxX - 200, y: screen.maxY, width: 22, height: 24))
        panel.setAutocomplete(true)
        check(panel.autocomplete && stand.autocomplete && panel.autocompleteModel == tr("本机 Apple Intelligence", "Apple Intelligence on this Mac"),
              "the menu bar panel's switch turns it on, and says the model (\(panel.autocompleteModel ?? "none"))")
        panel.closeDropDown()

        section("autocomplete: a harness window, a stand-in model", needs: .composing)
        let harness = HarnessTextClient()
        let model = AutocompleteStubModel()
        var now: TimeInterval = 1000
        let (settingsBefore, converterBefore, uptimeBefore, overrideBefore, secureBefore) = (settings, controller.services.converter,
            controller.services.uptime, controller.clientOverride, controller.services.secureInputActive)
        defer {
            harness.close()
            GhostOverlay.shared.hide()
            (settings, controller.services.converter, controller.services.uptime) = (settingsBefore, converterBefore, uptimeBefore)
            (controller.clientOverride, controller.services.secureInputActive) = (overrideBefore, secureBefore)
            (controller.passwordField, controller.fieldFrame) = (nil, nil)
            controller.activateServer(client)
            controller.applySettings()
            controller.composer.setInputMode(settings.defaultInput)
        }
        settings.autocomplete = true
        settings.typeOut = false
        // Apple Intelligence picked: the on-device model, the stand-in.
        settings.provider = .apple
        let modelSettings = settings
        controller.services.converter = Converter(loadConfig: { modelSettings }, appleModel: model)
        controller.services.uptime = { now }
        controller.services.secureInputActive = { false }
        // The harness field is never the one focused: Accessibility's answers would be about another app's.
        controller.passwordField = { false }
        controller.fieldFrame = { nil }
        controller.clientOverride = harness
        controller.activateServer(harness)
        controller.applySettings()
        controller.composer.setInputMode(.english)
        func ghost(_ text: String?, within seconds: TimeInterval = 3) -> Bool {
            pump(timeout: seconds) { GhostOverlay.shared.text == text }
        }
        func settled() { _ = pump(timeout: 0.4) { false } }

        harnessType("Hello wor", controller, harness)
        check(ghost("ld, how are you?"), "a pause after typing: the rest of the sentence after the caret (\(GhostOverlay.shared.text ?? "none"))")
        let caret = AllInOneIMEInputController.caretRect(harness) ?? .zero
        let frame = GhostOverlay.shared.frame
        let (baseline, ghostBaseline) = (harness.baseline ?? .nan, frame.minY + GhostOverlay.shared.ghost.baseline)
        check(caret != .zero && abs(frame.minX - caret.maxX - 1) < 1 && abs(ghostBaseline - baseline) < 1
              && GhostOverlay.shared.ghost.font == harness.textView.font,
              "drawn right after the caret, on its text's baseline, in its font (caret \(caret), baseline \(baseline), text \(frame), its baseline \(ghostBaseline))")
        check(model.prompts.last == "<before>Hello wor</before>", "what was sent: the text before the caret (\(model.prompts.last ?? "none"))")
        snapshotGhost(harness, to: snapshotDirectory.appendingPathComponent("autocomplete.png"))
        now += 0.5
        check(harnessKey(controller, harness, "\t", code: VirtualKey.tab) && harness.text == "Hello world, how are you?" && ghost(nil),
              "Tab puts it in (\(harness.text))")

        harnessType(" Se", controller, harness)
        check(ghost("e you soon."), "the next sentence (\(GhostOverlay.shared.text ?? "none"))")
        harnessType("e y", controller, harness)
        check(ghost("ou soon.") && model.prompts.count == 2, "typed along: the rest moves on, no request (\(GhostOverlay.shared.text ?? "none"))")
        check(harnessKey(controller, harness, "\u{1B}", code: VirtualKey.escape) && ghost(nil) && harness.text.hasSuffix("See y"),
              "Esc takes it down, the text as it was")
        // Not this one: typed on, it isn't shown again, though the model says it again; another one is.
        harnessType("o", controller, harness)
        settled()
        check(GhostOverlay.shared.text == nil && model.prompts.count == 3,
              "Esc: not this one, not shown again typed on (\(GhostOverlay.shared.text ?? "none"), \(model.prompts.count) requests)")
        harnessType("u", controller, harness)
        check(ghost(" and more."), "another suggestion is (\(GhostOverlay.shared.text ?? "none"))")
        now += 0.5
        check(!harnessKey(controller, harness, "\t", code: VirtualKey.tab, flags: .shift) && ghost(nil),
              "⇧Tab goes to the app, the suggestion goes")
        // A pause on "Let me know": the suggestion comes; a Tab right as it appears (the clock not moved) is the user's own.
        harness.text = "Let me kno"
        harnessType("w", controller, harness)
        check(ghost(" when you are free."), "a suggestion for “Let me know” (\(GhostOverlay.shared.text ?? "none"))")
        check(!harnessKey(controller, harness, "\t", code: VirtualKey.tab) && ghost(nil) && harness.text == "Let me know\t",
              "a Tab right as it appears goes to the app (\(harness.text.debugDescription))")

        // A field whose rect for the empty range at the caret is off its line (Notes's has been above it): on the line
        // the candidate panel goes by, after the character before the caret; more than a line off, the panel's line.
        let arrow = { _ = harnessKey(controller, harness, "\u{F703}", code: 0x7C) }
        harness.text = "Hello wo"
        harness.emptyRangeOffset = 12
        harnessType("r", controller, harness)
        let caretLine = harness.lineRectangle
        check(ghost("ld, how are you?") && abs(GhostOverlay.shared.frame.minY - caretLine.minY) < 1
              && abs(GhostOverlay.shared.frame.minX - caretLine.maxX - 1) < 1,
              "the empty range's rect 12 pt above the line: drawn on the line (line \(caretLine), text \(GhostOverlay.shared.frame))")
        arrow()
        harness.text = "Hello wo"
        harness.emptyRangeOffset = 60
        harnessType("r", controller, harness)
        let panelLine = pump(timeout: 3) { CandidatePanel.shared.view.model.rows.first?.label == "Tab" }
        check(panelLine && CandidatePanel.shared.view.model.rows.first?.text == "ld, how are you?" && GhostOverlay.shared.text == nil,
              "60 pt above, more than a line: a line of the candidate panel instead (\(CandidatePanel.shared.view.model.rows.map(\.text)))")
        arrow()
        harness.emptyRangeOffset = 0

        // Not before the end of a line; not with text selected.
        let asked1 = model.prompts.count
        harness.text = "Hello wor and more"
        harness.textView.setSelectedRange(NSRange(location: 9, length: 0))
        harnessType("l", controller, harness)
        settled()
        check(model.prompts.count == asked1 && GhostOverlay.shared.text == nil, "nothing in the middle of a line")

        // Pinyin: nothing while it's composed; what goes in is the suggestion's start, its rest comes back.
        controller.composer.setInputMode(.chinese)
        harness.text = ""
        harnessType("nihao", controller, harness)
        settled()
        check(GhostOverlay.shared.text == nil, "nothing while pinyin is composed")
        harnessKey(controller, harness, " ", code: VirtualKey.space)
        check(harness.text == "你好" && ghost("，今天怎么样？"), "after 你好 goes in: ，今天怎么样？ (\(GhostOverlay.shared.text ?? "none"))")
        snapshotGhost(harness, to: snapshotDirectory.appendingPathComponent("autocomplete-zh.png"))
        harnessKey(controller, harness, ",", code: 0x2B)
        check(harness.text == "你好，" && ghost("今天怎么样？"), "typed along: ， (\(harness.text))")
        harnessType("jintian", controller, harness)
        check(ghost(nil), "held while 今天 is composed")
        harnessKey(controller, harness, " ", code: VirtualKey.space)
        check(harness.text == "你好，今天" && ghost("怎么样？"), "今天 in: its rest comes back (\(GhostOverlay.shared.text ?? "none"))")
        now += 0.5
        check(harnessKey(controller, harness, "\t", code: VirtualKey.tab) && harness.text == "你好，今天怎么样？", "Tab puts it in (\(harness.text))")
        controller.composer.setInputMode(.english)

        // Where it never runs.
        func nothing(_ what: String, refocus: Bool = true, prepare: () -> Void, restore: () -> Void) {
            prepare()
            if refocus { controller.activateServer(harness) }
            harness.text = "Hello wor"
            let before = model.prompts.count
            harnessType("l", controller, harness)
            settled()
            check(model.prompts.count == before && GhostOverlay.shared.text == nil, "never \(what)")
            restore()
            controller.activateServer(harness)
        }
        nothing("while secure input is on", prepare: { controller.services.secureInputActive = { true } },
                restore: { controller.services.secureInputActive = { false } })
        nothing("in a password field Accessibility tells, secure input off", prepare: { controller.passwordField = { true } },
                restore: { controller.passwordField = { false } })
        nothing("in a terminal", prepare: { harness.bundleID = "com.apple.Terminal" }, restore: { harness.bundleID = "com.aipinyin.selftest.harness" })
        nothing("in a password manager", prepare: { harness.bundleID = "com.1password.1password" },
                restore: { harness.bundleID = "com.aipinyin.selftest.harness" })
        nothing("in a remote desktop", prepare: { harness.bundleID = "com.microsoft.rdc.macos" },
                restore: { harness.bundleID = "com.aipinyin.selftest.harness" })
        nothing("in a code editor not set to always", prepare: { harness.bundleID = "com.microsoft.VSCode" },
                restore: { harness.bundleID = "com.aipinyin.selftest.harness" })
        nothing("in an app with no AI", prepare: { settings.appProfiles = [harness.bundleID: AppProfile(noAI: true)] },
                restore: { settings.appProfiles = [:] })
        nothing("in an app set to never", prepare: { settings.appProfiles = [harness.bundleID: AppProfile(autocomplete: false)] },
                restore: { settings.appProfiles = [:] })
        nothing("with the switch off", prepare: { settings.autocomplete = false }, restore: { settings.autocomplete = true })
        nothing("while Translate as You Type is on", refocus: false, prepare: {
            settings.setOrder([OutputLanguage.english, .chinese])
            controller.perform(controller.composer.setTranslateMode(TranslateMode.Session(target: .chinese)), client: harness)
        }, restore: { controller.perform(controller.composer.setTranslateMode(nil), client: harness) })
        // An app set to always: on there with the switch off.
        settings.autocomplete = false
        settings.appProfiles = [harness.bundleID: AppProfile(autocomplete: true)]
        controller.activateServer(harness)
        harness.text = "Hello wo"
        harnessType("r", controller, harness)
        check(ghost("ld, how are you?"), "an app set to always: on there with the switch off")
        arrow()  // not Esc: that would wave the suggestion away for this text
        (settings.autocomplete, settings.appProfiles) = (true, [:])

        // It stops in an app where none of the last 30 was taken, and says so once (the input menu reads the config file:
        // the switch on there too, for its "This App"). The field takes the focus first: the switch seen on again since the
        // section before turned it off starts every app over (`AutocompleteStore.saw`), what was learned before too.
        if var file = try? Config.load() {
            file.autocomplete = true
            try? file.write()
        }
        controller.activateServer(harness)
        store.learn { learning in
            learning.restart()
            for _ in 0..<29 { _ = learning.record(false, in: "com.aipinyin.selftest.harness") }
        }
        harness.text = "Hello wo"
        harnessType("r", controller, harness)
        check(ghost("ld, how are you?", within: 5), "a suggestion, the 30th in the app")
        harnessKey(controller, harness, "\u{1B}", code: VirtualKey.escape)
        check(store.stopped(in: "com.aipinyin.selftest.harness")
              && controller.notice?.hasPrefix(tr("续写在「", "Autocomplete wasn't used in")) == true,
              "none taken: it stops there and says so (\(controller.notice ?? "none"))")
        let stoppedMenu = controller.menu()?.items.first { $0.title.hasPrefix(tr("这个 App：", "This App: ")) }?.submenu?.items.map(\.title) ?? []
        check(stoppedMenu.contains(tr("跟全局一样（在这里没用上，已停）", "Same as everywhere (stopped here: not used)"))
              && stoppedMenu.contains(tr("总是续写", "Always", key: "autocomplete.always")),
              "the input menu's This App says so, and offers Always (\(stoppedMenu))")
        // Turned off and on again elsewhere than the switch (Settings → Assistant writes the file): seen as a field takes
        // the focus, every app starts over, as with the switch.
        let turnedOn = store.metrics.turnedOn
        settings.autocomplete = false
        controller.activateServer(harness)
        settings.autocomplete = true
        controller.activateServer(harness)
        check(!store.stopped(in: "com.aipinyin.selftest.harness") && store.metrics.turnedOn == turnedOn + 1,
              "turned on again by Settings → Assistant: counted, and the app starts over")
        store.learn { $0.restart() }

        // A field that tells no caret rect: a line of the candidate panel. (The fake field's caret rect made empty, and its
        // text, what earlier sections put in, put aside.)
        let caretBefore = client.caretRect
        let fieldBefore = (client.document, client.selection, client.insertionPoint, client.inserted)
        (client.document, client.selection, client.insertionPoint) = ("", nil, nil)
        client.caretRect = .zero
        client.bundleIDOverride = "com.example.no-caret"
        controller.clientOverride = client
        controller.activateServer(client)
        client.inserted.removeAll()
        type("Hello wor", controller, client)  // let through: the fake field has none of it, so what was typed stands in
        let line = pump(timeout: 3) { CandidatePanel.shared.view.model.rows.first?.label == "Tab" }
        check(line && CandidatePanel.shared.view.model.rows.first?.text == "ld, how are you?",
              "no caret rect: a line of the candidate panel (\(CandidatePanel.shared.view.model.rows.map(\.text)))")
        now += 0.5
        check(press(controller, client, "\t", code: VirtualKey.tab) && client.inserted.last == "ld, how are you?", "Tab puts it in there too")
        (client.caretRect, client.bundleIDOverride, controller.clientOverride) = (caretBefore, nil, harness)
        (client.document, client.selection, client.insertionPoint, client.inserted) = fieldBefore
        controller.activateServer(harness)

        // A narrow field (its frame as Accessibility tells it): the suggestion is cut at its edge, not drawn over what is
        // beside it. In an app of its own: "Hello wor"'s suggestion, waved away with Esc above, never comes back in the
        // harness's app for that text.
        let window = harness.window.frame
        let narrow = NSRect(x: window.minX, y: window.minY, width: 160, height: window.height)
        controller.fieldFrame = { narrow }
        harness.bundleID = "com.aipinyin.selftest.narrow"
        controller.activateServer(harness)
        harness.text = "Hello wo"
        harnessType("r", controller, harness)
        let narrowShown = ghost("ld, how are you?")
        check(narrowShown && GhostOverlay.shared.frame.maxX <= narrow.maxX + 0.5
              && GhostOverlay.shared.frame.minX > AllInOneIMEInputController.caretRect(harness)?.minX ?? .infinity,
              "a narrow field: cut at its edge (field to \(narrow.maxX), text \(narrowShown ? "\(GhostOverlay.shared.frame)" : "not shown"))")
        harnessKey(controller, harness, "\u{1B}", code: VirtualKey.escape)
        controller.fieldFrame = { nil }
        harness.bundleID = "com.aipinyin.selftest.harness"
        controller.activateServer(harness)

        testAutocompleteCloudSwitch(controller, harness, ghost: { ghost($0) })

        // The cloud provider picked, through a local endpoint: the caret's line, whole (at most 1,500 characters), the
        // values hidden, the tokens counted. The session's settings and the endpoint's converter name the same address, as
        // one config file does.
        settings.provider = .anthropic
        settings.anthropic.baseURL = "https://autocomplete-selftest.invalid"
        settings.anthropic.model = "claude-selftest"
        settings.redaction = RedactionSettings(enabled: true)
        controller.services.converter = AutocompleteSelfTestEndpoint.converter(settings)
        controller.activateServer(harness)
        let tokens = store.metrics.cloudInputTokens
        let long = String(repeating: "We went over the plan again today. ", count: 50)  // 1,750 characters
        harness.text = long + "Write to ann@example.com and let me kno"
        harnessType("w", controller, harness)
        check(ghost(" when you are free.", within: 5), "the provider's suggestion (\(GhostOverlay.shared.text ?? "none"))")
        let body = AutocompleteSelfTestEndpoint.sent.last ?? ""
        let before = AutocompleteSelfTestEndpoint.message(of: body).components(separatedBy: "<before>").dropFirst().first?
            .components(separatedBy: "</before>").first ?? ""
        print("  sent: …\(before.suffix(60)) (\(before.count) characters)")
        check(before.count == 1500 - "ann@example.com".count + "[EMAIL_1]".count && !body.contains("ann@example.com") && body.contains("[EMAIL_1]"),
              "what went there: the caret's line, its last 1,500 characters, the email hidden (\(before.count) characters)")
        // The answer is read only as far as the suggestion goes: the tokens read are told at its start, those written at its end.
        check(store.metrics.cloudInputTokens == tokens + 120, "the tokens it read counted (\(store.metrics.cloudInputTokens - tokens))")
        harnessKey(controller, harness, "\u{1B}", code: VirtualKey.escape)
        (settings.provider, settings.anthropic, settings.redaction) = (settingsBefore.provider, settingsBefore.anthropic, settingsBefore.redaction)

        let metrics = store.metrics
        check(metrics.shown >= 8 && metrics.accepted >= 3 && metrics.p90 != nil
              && menuItem(toggle)?.toolTip == metrics.summary(language: UIText.language),
              "counted on this Mac: \(metrics.summary(language: "en") ?? "nothing"); the menu's tooltip says so")

        testAutocompleteOnDevice(controller, harness, now: { now }, advance: { now += $0 })
    }

    /// Turning it on with a cloud provider picked, as the user does: nothing asks (no panel, no modal loop), the input
    /// menu says the provider, its model and what each pause sends there, and the next pause asks that provider (here the
    /// Claude API at a local endpoint, `AutocompleteSelfTestEndpoint`: never a paid call), not the on-device model.
    /// `ghost(text)`: whether that suggestion is up, waiting a moment for it.
    static func testAutocompleteCloudSwitch(_ controller: AllInOneIMEInputController, _ harness: HarnessTextClient,
                                            ghost: (String?) -> Bool) {
        section("autocomplete: turned on with a cloud provider, no question, the provider asked", needs: .composing)
        func file() -> Config? { try? Config.load() }
        guard var config = file() else {
            check(false, "the config file reads")
            return
        }
        (config.provider, config.anthropic.baseURL, config.anthropic.model, config.autocomplete) =
            (.anthropic, "https://autocomplete-selftest.invalid", "claude-selftest", false)
        try? config.write()
        let (settingsBefore, converterBefore) = (settings, controller.services.converter)
        defer { (settings, controller.services.converter) = (settingsBefore, converterBefore) }
        controller.activateServer(harness)
        let visible = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        controller.toggleAutocomplete(nil)
        let asked = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) && !visible.contains(ObjectIdentifier($0)) }
        check(file()?.autocomplete == true && NSApp.modalWindow == nil && asked.isEmpty,
              "turned on with the Claude API picked: on at once, no question (\(asked.map(\.title)))")
        let toggle = #selector(AllInOneIMEInputController.toggleAutocomplete(_:))
        let items = controller.menu()?.items ?? []
        let index = items.firstIndex { $0.action == toggle }
        let line = index.flatMap { items.indices.contains($0 + 1) ? items[$0 + 1] : nil }
        check(index.map { items[$0].title } == tr("续写（Claude API · claude-selftest）", "Autocomplete (Claude API · claude-selftest)")
              && line?.tag == AllInOneIMEInputController.autocompleteDestinationTag && line?.title.contains("Claude API · claude-selftest") == true,
              "the input menu: the provider and its model, and what each pause sends there (\(line?.title ?? "none"))")
        // The next pause asks it, as the session's settings have it.
        (settings.provider, settings.anthropic.baseURL, settings.anthropic.model) = (.anthropic, "https://autocomplete-selftest.invalid", "claude-selftest")
        controller.services.converter = AutocompleteSelfTestEndpoint.converter(settings)
        controller.activateServer(harness)
        let sent = AutocompleteSelfTestEndpoint.sent.count
        harness.text = "Let me kno"
        harnessType("w", controller, harness)
        check(ghost(" when you are free.") && AutocompleteSelfTestEndpoint.sent.count == sent + 1,
              "the next pause asks the Claude API (the local endpoint): its suggestion (\(GhostOverlay.shared.text ?? "none"))")
        harnessKey(controller, harness, "\u{1B}", code: VirtualKey.escape)
        controller.toggleAutocomplete(nil)
    }

    /// Apple's on-device model, where it's available (skipped elsewhere): a suggestion, or nothing to suggest, without an
    /// error, and how long it took.
    static func testAutocompleteOnDevice(_ controller: AllInOneIMEInputController, _ harness: HarnessTextClient, now: () -> TimeInterval,
                                         advance: (TimeInterval) -> Void) {
        let availability = AppleModel.system.availability
        section("autocomplete: Apple's on-device model (\(availability.rawValue))", needs: .composing)
        guard availability == .available else {
            print("  skipped: the on-device model isn't available here")
            return
        }
        let store = AutocompleteSwitch.store
        let (failed, shown) = (store.metrics.failed, store.metrics.shown)
        let modelSettings = settings
        controller.services.converter = Converter(loadConfig: { modelSettings })
        controller.activateServer(harness)
        controller.composer.setInputMode(.english)
        harness.text = "Thanks for the update. I will send you the report by the end of the"
        // Loaded ahead, as a field taking the focus has it loaded (`Converter.prewarmOnDevice`).
        controller.services.converter.prewarmOnDevice()
        _ = pump(timeout: 2) { false }
        func ask(_ text: String, then typed: String) {
            harness.text = text
            let started = Date()
            harnessType(typed, controller, harness)
            // The real model's time: the pause (350 ms at least), the field read, the answer, the overlay (30 ms).
            _ = pump(timeout: 10) { GhostOverlay.shared.text != nil || store.metrics.failed > failed }
            let seconds = Date().timeIntervalSince(started)
            print(String(format: "  on-device: %@ after %.2f s, from the last key", GhostOverlay.shared.text.map { "“\($0)”" } ?? "nothing shown", seconds))
            check(store.metrics.failed == failed && (GhostOverlay.shared.text == nil || store.metrics.shown > shown),
                  "the on-device model answered without an error (\(GhostOverlay.shared.text ?? "nothing to suggest"))")
            advance(0.5)
            harnessKey(controller, harness, "\u{1B}", code: VirtualKey.escape)
        }
        ask("Thanks for the update. I will send you the report by the end of the", then: " ")
        ask("Could you please send me the slides from yesterday's", then: " ")
        _ = now
    }

    /// The harness window with the suggestion over it, as the screen would show it (the window's own drawing, then the
    /// overlay's, where it is on the screen), in the light appearance.
    static func snapshotGhost(_ harness: HarnessTextClient, to url: URL) {
        let view = harness.textView
        let ghost = GhostOverlay.shared.ghost
        let frame = GhostOverlay.shared.frame
        let light = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        let (before, ghostBefore) = (harness.window.appearance, ghost.appearance)
        (harness.window.appearance, ghost.appearance) = (light, light)
        defer { (harness.window.appearance, ghost.appearance) = (before, ghostBefore) }
        view.needsDisplay = true
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        // Where the overlay's bottom left is, in the text view's coordinates (flipped: its y runs down).
        let inWindow = harness.window.convertPoint(fromScreen: NSPoint(x: frame.minX, y: frame.minY))
        let top = view.convert(inWindow, from: nil)
        let composed = NSImage(size: view.bounds.size, flipped: false) { rect in
            rep.draw(in: rect)
            light.performAsCurrentDrawingAppearance {
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: top.x, yBy: rect.height - top.y)
                transform.concat()
                ghost.draw(NSRect(origin: .zero, size: frame.size))
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        guard let tiff = composed.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}

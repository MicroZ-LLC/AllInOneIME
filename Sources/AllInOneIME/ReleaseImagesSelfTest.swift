import AllInOneIMECore
import AppKit
import os
import SwiftUI

/// A stand-in AI endpoint for the release images' `@reply`: it answers every request with `answer` (three replies),
/// and nothing leaves this Mac.
final class ReleaseImageEndpoint: URLProtocol, @unchecked Sendable {
    private static let current = OSAllocatedUnfairLock(initialState: "")
    static var answer: String {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    @MainActor
    static func converter() -> Converter {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseImageEndpoint.self]
        var config = SelfTest.settings
        config.provider = .anthropic
        config.anthropic.baseURL = "https://release-images.invalid"
        config.anthropic.model = "claude-selftest"
        let fixed = config
        return Converter(client: BedrockClient(session: URLSession(configuration: configuration)), loadConfig: { fixed },
                         loadCredentials: { _ in throw ProviderError.missingKey(.anthropic) }, loadKey: { _, _ in "sk-test" },
                         loadJargon: { _ in [] })
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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

extension SelfTest {
    /// The panels 0.6.5's release notes show, in the Chinese interface and in English (`-en`, English typed, no
    /// Chinese): Translate as You Type's chip over a draft, `@reply` with a screenshot pasted and its replies, the
    /// notice of `@agent` that took the Chrome page along, and the custom command editor's "Insert text". Made-up
    /// content, canned answers and a stand-in endpoint: nothing is sent, nothing of the user's is read.
    static func testReleaseImages(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("0.6.5's release images (canned answers)", needs: .composing)
        let saved = (converter: controller.services.converter, settings: settings, load: controller.services.loadSettings,
                     clipboard: controller.readClipboard, recognizer: controller.services.recognizeText, secure: controller.services.secureInputActive,
                     defaults: TranslateModeShared.defaults, lastTarget: TranslateModeShared.lastTarget, shiftHeld: TranslateModeShared.shiftHeld)
        let caretBefore = client.caretRect
        let suite = "com.aipinyin.selftest.releaseimages"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        TranslateModeShared.defaults = UserDefaults(suiteName: suite) ?? .standard
        defer {
            if TranslateModeShared.state.isOn { controller.toggleTranslateMode() }
            TranslateModeShared.state = TranslateMode.State()
            controller.perform(controller.composer.setTranslateMode(nil), client: client)
            controller.hideTranslateChip()
            MenuBarIcon.shared.setTranslating(false)
            if let notice = controller.notice { controller.endNotice(notice) }
            controller.commitComposition(client)
            (controller.services.converter, settings, controller.services.loadSettings) = (saved.converter, saved.settings, saved.load)
            (controller.readClipboard, controller.services.recognizeText, controller.services.secureInputActive) = (saved.clipboard, saved.recognizer, saved.secure)
            TranslateModeShared.defaults = saved.defaults
            if TranslateModeShared.lastTarget != saved.lastTarget { TranslateModeShared.lastTarget = saved.lastTarget }
            TranslateModeShared.shiftHeld = saved.shiftHeld
            UserDefaults.standard.removePersistentDomain(forName: suite)
            client.bundleIDOverride = nil
            client.caretRect = caretBefore
            controller.applySettings()
            controller.activateServer(client)
            controller.composer.setInputMode(settings.defaultInput)
            client.inserted.removeAll()
        }
        controller.services.loadSettings = { SelfTest.settings }
        controller.services.secureInputActive = { false }
        // The panels away from the pointer, so no row shows as hovered in the images.
        let screen = NSScreen.screens[0].frame, mouse = NSEvent.mouseLocation
        client.caretRect = NSRect(x: mouse.x < screen.midX ? screen.maxX - 1100 : screen.minX + 80,
                                  y: mouse.y < screen.midY ? screen.maxY - 120 : screen.minY + 520, width: 1, height: 18)
        let vision = VisionTextRecognizer()
        _ = runAsync(40) { await vision.prepare(languages: ["zh-Hans", "en-US"]) }

        for english in [false, true] {
            let suffix = english ? "-en" : ""
            /// Settings for this language's images: its interface, what's typed, what's translated into.
            func use(input: [Language], outputs: [OutputLanguage]) {
                settings = (try? Config.load()) ?? .default
                (settings.typeOut, settings.typeOutMistakes) = (false, false)
                settings.uiLanguage = english ? "en" : "zh"
                settings.actionKey = .enter
                settings.setOrder(input)
                settings.setOrder(outputs)
                controller.applySettings()
            }
            func idle() {
                if TranslateModeShared.state.isOn { controller.toggleTranslateMode() }
                if let notice = controller.notice { controller.endNotice(notice) }
                for _ in 0..<4 where controller.composer.isComposing { _ = escape(controller, client) }
                controller.commitComposition(client)
                CandidatePanel.shared.hide()
                client.inserted.removeAll()
            }

            // Translate as You Type: on (its notice), a draft typed, the chip near the caret.
            idle()
            use(input: english ? [.english] : [.chinese, .english], outputs: english ? ["es", "fr"].map(OutputLanguage.init) : [.english, OutputLanguage("ja")])
            let model = CannedTranslationModel(answers: [:])
            let fixed = settings
            controller.services.converter = Converter(loadConfig: { fixed }, appleModel: model)
            client.bundleIDOverride = "com.example.chat"
            controller.activateServer(client)
            controller.composer.setInputMode(english ? .english : .chinese)
            TranslateModeShared.lastTarget = nil
            controller.toggleTranslateMode()
            check(TranslateModeShared.state.isOn, "Translate as You Type on for the image (\(english ? "English" : "Chinese"))")
            type(english ? "see you at the station at noon" : "mingtianjian", controller, client)
            controller.refreshTranslateChip()
            _ = pump(timeout: 0.3) { false }
            snapshot("release-translate-mode\(suffix)", in: snapshotDirectory)
            try? Data(client.marked.utf8).write(to: snapshotDirectory.appendingPathComponent("release-translate-mode\(suffix).marked.txt"))
            check(CandidatePanel.shared.view.model.chip != nil, "the chip is in the image (\(client.marked))")
            idle()
            client.bundleIDOverride = nil
            controller.activateServer(client)

            // @reply with a screenshot pasted (⌃V): read here, then three replies.
            use(input: english ? [.english] : [.chinese, .english], outputs: english ? [OutputLanguage("es")] : [.english])
            controller.services.converter = ReleaseImageEndpoint.converter()
            controller.services.recognizeText = vision
            controller.composer.setInputMode(.english)
            let conversation = english ? ["Can you join the launch review on Friday at 3?", "Let me check my calendar"]
                : ["周五下午三点能来参加上线评审吗？", "我看一下日程"]
            guard let png = screenshotPNG(conversation) else { check(false, "a sample screenshot"); continue }
            controller.readClipboard = { .image(png) }
            ReleaseImageEndpoint.answer = english
                ? "Yes, I can join! Could we make it 4 pm instead of 3?\n---\nCount me in. Would 4 pm work for everyone?\n---\nSure, though 4 pm would suit me better. Can we move it?"
                : "可以的，不过能改到四点吗？三点我还有个会。\n---\n没问题，就是三点有点赶，四点可以吗？\n---\n能来！要是能挪到四点就更好了。"
            press(controller, client, "@", code: 0x13, flags: .shift)
            type("reply", controller, client)
            press(controller, client, "\t", code: VirtualKey.tab)
            press(controller, client, "v", code: 0x09, flags: .control)
            let ready = pump(timeout: 15) { if case .screenshot(.ready)? = controller.composer.attachment { return true } else { return false } }
            if english { type("yes, but ask for 4 pm", controller, client) }
            _ = pump(timeout: 0.3) { false }
            check(ready, "the screenshot is read (\(controller.panelModel().headerText ?? "-"))")
            snapshot("release-reply-screenshot\(suffix)", in: snapshotDirectory)
            try? Data(client.marked.utf8).write(to: snapshotDirectory.appendingPathComponent("release-reply-screenshot\(suffix).marked.txt"))
            _ = enter(controller, client)
            let replied = pump(timeout: 10) { controller.composer.phase == .choosing }
            _ = pump(timeout: 0.3) { false }
            check(replied && controller.composer.choices.filter { $0.kind == .answer }.count == 3,
                  "three replies (\(controller.composer.choices.map(\.text)))")
            snapshot("release-reply\(suffix)", in: snapshotDirectory)
            try? Data(client.marked.utf8).write(to: snapshotDirectory.appendingPathComponent("release-reply\(suffix).marked.txt"))
            idle()

            // @agent's notice when it took the Chrome page along.
            controller.showNotice(controller.composer.messages.openedTerminal + UIText.withPage("Pipeline #4821 · deploy-web"), client: client)
            _ = pump(timeout: 0.3) { false }
            snapshot("release-agent-page\(suffix)", in: snapshotDirectory)
            idle()

            // The custom command editor's "Insert text": a signature with a blank and the caret's place.
            UIText.choice = english ? "en" : "zh"
            let snippet = CustomCommand(name: "sig", type: .snippet, summary: english ? "Signature" : "签名",
                                        text: english ? "Best regards,\n{name?}\nAcme Design · {date}\n{cursor}" : "祝好，\n{name?}\n示例设计工作室 · {date}\n{cursor}")
            let editor = snapshotDirectory.appendingPathComponent("release-snippet-editor\(suffix).png")
            renderLight(CommandEditor(edit: CommandEdit(index: nil, command: snippet), others: []) { _ in true },
                        size: NSSize(width: 660, height: 540), to: editor)
            check(FileManager.default.fileExists(atPath: editor.path), "the snippet editor renders (\(editor.lastPathComponent))")
        }
    }

    /// `view` drawn offscreen in the light appearance, whatever this Mac's is, into a PNG of `size`.
    static func renderLight<V: View>(_ view: V, size: NSSize, to url: URL) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.alphaValue = 0
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        _ = pump(timeout: 0.8) { false }
        defer { window.close() }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

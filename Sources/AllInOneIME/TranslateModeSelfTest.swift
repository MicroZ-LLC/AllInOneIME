import AllInOneIMECore
import AppKit

/// Canned translations for translation mode's self-test, behind the on-device model's interface: nothing is sent
/// anywhere. It answers in the format the request asks for (the tag of its one line, "EN" or "JA"), by that tag and the
/// text; it can wait before answering, and fail the next request.
final class CannedTranslationModel: AppleModelBackend, @unchecked Sendable {
    let answers: [String: String]
    private let lock = NSLock()
    private var _requests: [AppleModelRequest] = []
    private var _failNext = false
    private var _delay: TimeInterval = 0
    var requests: [AppleModelRequest] { lock.withLock { _requests } }
    var failNext: Bool {
        get { lock.withLock { _failNext } }
        set { lock.withLock { _failNext = newValue } }
    }
    var delay: TimeInterval {
        get { lock.withLock { _delay } }
        set { lock.withLock { _delay = newValue } }
    }

    /// `answers` by "TAG|text": "EN|你好" → "Hello".
    init(answers: [String: String]) { self.answers = answers }

    var availability: AppleModelAvailability { .available }
    var contextSize: Int { 4096 }
    var supportedLanguages: Set<String> { ["en", "zh", "ja"] }

    /// The tag of the line the instructions ask for ("EN: <the sentence in English…").
    static func tag(in instructions: String) -> String {
        let line = instructions.split(separator: "\n").first { $0.contains(": <the sentence in ") } ?? ""
        return line.split(separator: ":").first.map(String.init) ?? "EN"
    }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        let (fails, delay) = lock.withLock { () -> (Bool, TimeInterval) in
            _requests.append(request)
            defer { _failNext = false }
            return (_failNext, _delay)
        }
        let tag = Self.tag(in: request.instructions)
        let text = "\(tag): " + (answers["\(tag)|\(request.prompt)"] ?? "(\(request.prompt))")
        return AsyncThrowingStream { continuation in
            let task = Task {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled else { return continuation.finish() }
                if fails { return continuation.finish(throwing: AppleModelError.failed("canned failure")) }
                continuation.yield(AppleModelSnapshot(text: text))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension SelfTest {
    /// Translation mode through the fake field, with canned translations (`CannedTranslationModel`, no live AI): a long
    /// press of Shift (the real modifier changes and timers) shows the hint, then turns it on, the input language
    /// unchanged; a tap still switches it, Shift with a letter toggles nothing. Pinyin collects into the draft after
    /// 「中→英 ›」, ⏎ translates (「翻译中…」 meanwhile) and the translation goes in at once, nothing sent after it;
    /// ⇧⏎ inserts as typed; Esc while translating keeps the draft; a failure keeps it with a notice and ⏎ tries again;
    /// typing in English (the target) goes in as typed; in an app with no AI, ⏎ inserts as typed with the notice.
    /// `@mode ja formal` and `@exit`; switching apps leaves it, an app that translates always turns it on, in its tone.
    static func testTranslateMode(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        section("translation mode (canned translations)", needs: .composing)
        let (notes, chat, mail) = ("com.example.notes", "com.example.chat", "com.example.mail")
        let saved = (converter: controller.converter, settings: settings, shiftHeld: TranslateModeShared.shiftHeld)
        defer {
            TranslateModeShared.state.leave()
            controller.perform(controller.composer.setTranslateMode(nil), client: client)
            controller.refreshTranslateModeCommands()
            controller.commitComposition(client)
            (controller.converter, settings, TranslateModeShared.shiftHeld) = (saved.converter, saved.settings, saved.shiftHeld)
            client.bundleIDOverride = nil
            controller.activateServer(client)
            controller.composer.setInputMode(settings.defaultInput)
        }
        settings.provider = .apple  // the canned model's place
        settings.setOrder([OutputLanguage.english, .chinese])
        settings.setOrder([Language.chinese, .english])
        settings.appProfiles = [mail: AppProfile(rewriteStyles: ["正式"], translateAlways: true)]
        let model = CannedTranslationModel(answers: ["EN|你好": "Hello", "JA|你好": "こんにちは", "EN|我们": "We"])
        let fixed = settings
        controller.converter = Converter(loadConfig: { fixed }, appleModel: model)
        controller.commitComposition(client)
        client.bundleIDOverride = notes
        controller.activateServer(client)
        controller.composer.setInputMode(.chinese)
        client.inserted.removeAll()
        let translating = tr("翻译中…", "Translating…")
        func shift(_ down: Bool) {
            _ = controller.handle(event("", code: VirtualKey.leftShift, flags: down ? .shift : [], type: .flagsChanged), client: client)
        }
        func draft(_ pinyin: String) {
            type(pinyin, controller, client)
            _ = space(controller, client)
        }

        // Off: @mode offered, @exit not; Shift with a letter (a capital) held long toggles nothing.
        check(controller.composer.commands.contains(.translationMode) && !controller.composer.commands.contains(.exitMode),
              "@mode is offered, @exit only once it's on")
        TranslateModeShared.shiftHeld = { true }  // the fake field's Shift "held" while the timers run
        shift(true)
        press(controller, client, "A", code: 0x00, flags: .shift)
        _ = pump(timeout: 1.0) { false }
        shift(false)
        check(!TranslateModeShared.state.isOn, "Shift held with a letter (a capital) doesn't turn it on")
        controller.commitComposition(client)
        controller.composer.setInputMode(.chinese)
        client.inserted.removeAll()

        // A long press of Shift: the hint, then on.
        shift(true)
        let hinted = pump(timeout: 0.75) { controller.notice?.hasPrefix(tr("继续按住", "Keep holding")) == true }
        check(hinted && !TranslateModeShared.state.isOn, "a long press of Shift: \(controller.notice ?? "no hint") at about 0.4 s")
        let on = pump(timeout: 1.5) { TranslateModeShared.state.isOn }
        shift(false)
        check(on && controller.composer.translateMode?.target == .english && controller.notice == tr("中→英 已开启", "中→英 on")
              && controller.composer.inputLanguage == .chinese,
              "…at 0.8 s it's on (\(controller.notice ?? "-")), the input language not switched")
        check(controller.composer.commands.contains(.exitMode), "@exit is offered while it's on")
        // A tap of Shift still switches the input language.
        tapShift(controller, client)
        check(controller.composer.inputLanguage == .english && TranslateModeShared.state.isOn, "a tap of Shift still switches the input language")
        // English is what it translates into: typed as usual.
        check(!press(controller, client, "o", code: 0x1F) && client.marked.isEmpty, "typing in English (the target) goes in as typed")
        tapShift(controller, client)

        // Pinyin collects into the draft; ⏎ translates and inserts at once.
        type("nihao", controller, client)
        check(client.marked.hasPrefix("中→英 › "), "pinyin in the mode: '\(client.marked)'")
        _ = space(controller, client)
        check(client.marked == "中→英 › 你好" && client.inserted.isEmpty, "the words picked collect into the draft: '\(client.marked)'")
        model.delay = 0.3
        _ = enter(controller, client)
        check(client.marked == "中→英 › 你好 · \(translating)" && controller.panelModel().rows.isEmpty,
              "⏎: '\(client.marked)', no candidates")
        let inserted = pump(timeout: 5) { client.inserted.last == "Hello" }
        check(inserted && client.marked.isEmpty && !controller.composer.isComposing, "…and the translation goes in at once (\(client.inserted))")
        check(!enter(controller, client), "…not sent: the next ⏎ is the app's")
        let instructions = model.requests.last?.instructions ?? ""
        check(instructions.contains("Tone of the translation") && instructions.contains(TranslateMode.Tone.natural.rule)
              && model.requests.last?.examples.isEmpty == true,
              "translation mode's own request: one line, a tone line (natural here)")

        // ⇧⏎: as typed.
        draft("nihao")
        _ = shiftEnter(controller, client)
        check(client.inserted.last == "你好" && client.marked.isEmpty, "⇧⏎ inserts the draft as typed")

        // Esc while translating: stopped, the draft kept.
        model.delay = 2
        draft("women")
        let typed = controller.composer.draft
        _ = enter(controller, client)
        _ = escape(controller, client)
        check(client.marked == "中→英 › \(typed)" && controller.composer.phase == .drafting, "Esc while translating stops it, the draft kept: '\(client.marked)'")
        let count = client.inserted.count
        _ = pump(timeout: 2.3) { false }
        check(client.inserted.count == count, "…and nothing goes in later")
        _ = escape(controller, client)
        model.delay = 0

        // A failure: the draft kept, a notice; ⏎ tries again. (Text not asked for before: an answer kept would come
        // from the cache.)
        model.failNext = true
        draft("women")
        let failing = controller.composer.draft
        _ = enter(controller, client)
        let failed = pump(timeout: 5) { controller.notice?.contains("canned failure") == true }
        check(failed && client.marked == "中→英 › \(failing)" && controller.composer.phase == .drafting,
              "a failure keeps the draft, with a notice: \(controller.notice ?? "-")")
        let before = client.inserted.count
        _ = enter(controller, client)
        let retried = pump(timeout: 5) { client.inserted.count > before && !controller.composer.isComposing }
        check(retried && client.inserted.last == (failing == "我们" ? "We" : "(\(failing))"), "⏎ tries again: \(client.inserted.last ?? "")")

        // No AI in this app: as typed, with the notice.
        settings.appProfiles[notes] = AppProfile(noAI: true)
        draft("nihao")
        _ = enter(controller, client)
        check(client.inserted.last == "你好" && controller.notice == AppProfileText.refusal, "no AI in the app: ⏎ inserts as typed, with the notice")
        settings.appProfiles[notes] = nil

        // @mode ja formal, then @exit.
        press(controller, client, "@", code: 0x13, flags: .shift)
        type("mo", controller, client)
        press(controller, client, "\t", code: VirtualKey.tab)
        type("ja formal", controller, client)
        _ = enter(controller, client)
        check(controller.composer.translateMode == TranslateMode.Session(target: OutputLanguage("ja"), tone: .formal)
              && controller.notice == tr("中→日 已开启 · 正式", "中→日 on · formal"),
              "@mode ja formal: \(controller.notice ?? "-")")
        draft("nihao")
        _ = enter(controller, client)
        check(pump(timeout: 5) { client.inserted.last == "こんにちは" } && model.requests.last?.instructions.contains(TranslateMode.Tone.formal.rule) == true,
              "…into Japanese, formally (\(client.inserted.last ?? ""))")
        press(controller, client, "@", code: 0x13, flags: .shift)
        type("ex", controller, client)
        _ = enter(controller, client)
        check(!TranslateModeShared.state.isOn && controller.composer.translateMode == nil && controller.notice == tr("中→日 已关闭", "中→日 off"),
              "@exit: \(controller.notice ?? "-")")
        draft("nihao")
        check(client.inserted.last == "你好" && client.marked.isEmpty, "off: words go straight in again")

        // Another app leaves it; an app that translates always turns it on, in its own tone.
        controller.changeTranslateMode(.enter(target: nil, tone: nil))
        controller.commitComposition(client)
        client.bundleIDOverride = chat
        controller.activateServer(client)
        check(!TranslateModeShared.state.isOn && controller.composer.translateMode == nil, "switching to another app leaves it")
        client.bundleIDOverride = mail
        controller.activateServer(client)
        check(TranslateModeShared.state.isOn && controller.composer.translateMode?.target == .english, "an app that translates always turns it on")
        draft("nihao")
        _ = enter(controller, client)
        check(pump(timeout: 5) { client.inserted.last == "Hello" } && model.requests.last?.instructions.contains(TranslateMode.Tone.formal.rule) == true,
              "…in the app's tone (its first rewrite style, 正式)")
        controller.commitComposition(client)
        client.bundleIDOverride = notes
        controller.activateServer(client)
        check(!TranslateModeShared.state.isOn, "…and leaving that app leaves it")
        check(AppProfileText.summary(AppProfile(translateAlways: true)) == tr("总是 中→英", "Always translate"),
              "Settings → Apps says so: \(AppProfileText.summary(AppProfile(translateAlways: true)))")
    }
}

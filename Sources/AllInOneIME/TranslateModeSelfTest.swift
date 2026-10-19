import AllInOneIMECore
import AppKit

/// Canned translations for Translate as You Type's self-test, behind the on-device model's interface: nothing is sent
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
    /// Translate as You Type through the fake field, with canned translations (`CannedTranslationModel`, no live AI): a
    /// long press of Shift (the real modifier changes and timers) shows the hint at 0.5 s, then turns it on at 1.0 s with
    /// its notice and the menu bar badge, the input language unchanged; a tap still switches it, Shift with a letter
    /// toggles nothing, a press given up takes its hint down at once, and no @ command is offered for it. Pinyin
    /// collects into the draft (the chip names the languages), ⏎ translates (「翻译中…」 meanwhile) and the translation
    /// goes in at once, nothing sent after it; ⇧⏎ inserts as typed; Esc while translating keeps the draft; a failure
    /// keeps it with a notice and ⏎ tries again; typing in English (the target) goes in as typed; in an app with no AI,
    /// ⏎ inserts as typed with the notice. The chip near the caret (「中 → 英」,
    /// in the candidate panel, rendered: translate-mode-chip*.png): its source part switches the input language as a tap
    /// of Shift, its target part lists the output languages and Japanese clicked there is the target at once and after
    /// turning it on again (kept in the input method's defaults: the self-test's own here); the target removed while it's
    /// on gives way to the first at once, the chip following; a pick no longer offered goes back to the first, and the
    /// language typed when it comes on doesn't matter. A long press again turns it off, the chip gone; another app active
    /// (Finder, no text field) leaves it at once, the draft in as typed, and ends a press of Shift (not the input
    /// method's own process, its settings app, or a notice of an app no longer frontmost); switching apps leaves it with
    /// no notice, an app that translates always turns it on, in its tone. It leaves everything as it found it: off, no
    /// notice, no chip, no timer, the language picked last.
    static func testTranslateMode(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("Translate as You Type (canned translations)", needs: .composing)
        let (notes, chat, mail) = ("com.example.notes", "com.example.chat", "com.example.mail")
        let saved = (converter: controller.converter, settings: settings, shiftHeld: TranslateModeShared.shiftHeld,
                     shiftDown: TranslateModeShared.shiftDown, defaults: TranslateModeShared.defaults,
                     lastTarget: TranslateModeShared.lastTarget, pointer: TranslateModeShared.pointer,
                     stickyKeys: TranslateModeShared.stickyKeys)
        // The mouse left alone and Sticky Keys off, whatever this Mac's are, while Shift is "held"; Shift down as the
        // fake field's last modifier change left it.
        var shiftIsDown = false
        (TranslateModeShared.pointer, TranslateModeShared.stickyKeys) = ({ .zero }, { false })
        TranslateModeShared.shiftDown = { shiftIsDown }
        // The language picked last: in the self-test's own defaults (the user's stay as they are).
        let suite = "com.aipinyin.selftest.translatemode"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        TranslateModeShared.defaults = UserDefaults(suiteName: suite) ?? .standard
        // Everything left as it was found, for the sections after it: off, no press timed and no timer of one or of the
        // chip to go off, no chip, no notice up (its timer cancelled), the language picked last as it was.
        defer {
            TranslateModeShared.state = TranslateMode.State()
            TranslateModeShared.hold.resync(shiftDown: false)
            TranslateModeShared.holdToken += 1
            TranslateModeShared.chipToken += 1
            (TranslateModeShared.hint, TranslateModeShared.hintField) = (nil, nil)
            (TranslateModeShared.listOpen, TranslateModeShared.toldSecureInput) = (false, false)
            controller.perform(controller.composer.setTranslateMode(nil), client: client)
            controller.commitComposition(client)
            MenuBarIcon.shared.setTranslating(false)
            (controller.converter, settings, TranslateModeShared.shiftHeld) = (saved.converter, saved.settings, saved.shiftHeld)
            TranslateModeShared.defaults = saved.defaults
            if TranslateModeShared.lastTarget != saved.lastTarget { TranslateModeShared.lastTarget = saved.lastTarget }
            (TranslateModeShared.pointer, TranslateModeShared.stickyKeys) = (saved.pointer, saved.stickyKeys)
            TranslateModeShared.shiftDown = saved.shiftDown
            UserDefaults.standard.removePersistentDomain(forName: suite)
            client.bundleIDOverride = nil
            controller.activateServer(client)
            controller.composer.setInputMode(settings.defaultInput)
            controller.hideTranslateChip()
            if let notice = controller.notice { controller.endNotice(notice) }
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
        let translating = tr("翻译中…", "Translating…", key: "translateMode.translating")
        func shift(_ down: Bool) {
            shiftIsDown = down
            _ = controller.handle(event("", code: VirtualKey.leftShift, flags: down ? .shift : [], type: .flagsChanged), client: client)
        }
        /// The notice up taken down now, its timer cancelled.
        func endNotice() {
            if let notice = controller.notice { controller.endNotice(notice) }
        }
        func draft(_ pinyin: String) {
            type(pinyin, controller, client)
            _ = space(controller, client)
        }
        /// Shift held on its own until the mode turns on or off: whether the hint was `hint` first.
        func longPress(hint: String) -> (hinted: Bool, toggled: Bool) {
            let was = TranslateModeShared.state.isOn
            shift(true)
            let hinted = pump(timeout: 0.9) { controller.notice == hint }
            let toggled = pump(timeout: 1.5) { TranslateModeShared.state.isOn != was }
            shift(false)
            return (hinted, toggled)
        }
        let (onHint, offHint) = (tr("继续按住 → 边打边译", "Keep holding → Translate as You Type"),
                                 tr("继续按住 → 关闭边打边译", "Keep holding → Translate as You Type off"))

        // Off: no @ command for it; Shift with a letter (a capital) held long toggles nothing.
        check(!controller.composer.commands.contains { $0.name == "mode" || $0.name == "exit" }, "no @mode or @exit")
        TranslateModeShared.shiftHeld = { true }  // the fake field's Shift "held" while the timers run
        shift(true)
        press(controller, client, "A", code: 0x00, flags: .shift)
        _ = pump(timeout: 1.3) { false }
        shift(false)
        check(!TranslateModeShared.state.isOn, "Shift held with a letter (a capital) doesn't turn it on")
        controller.commitComposition(client)
        controller.composer.setInputMode(.chinese)
        client.inserted.removeAll()
        // A press given up after its hint: the hint goes at once, Shift let go or a letter typed.
        shift(true)
        let letGo = pump(timeout: 0.9) { controller.notice == onHint }
        shift(false)
        check(letGo && controller.notice == nil, "Shift let go after the hint: the hint goes at once (\(controller.notice ?? "none"))")
        shift(true)
        let capital = pump(timeout: 0.9) { controller.notice == onHint }
        press(controller, client, "A", code: 0x00, flags: .shift)
        check(capital && controller.notice != onHint, "…a letter typed then: the hint goes at once (\(controller.notice ?? "none"))")
        _ = pump(timeout: 0.7) { TranslateModeShared.state.isOn }
        shift(false)
        check(!TranslateModeShared.state.isOn, "…and nothing turns on")
        controller.commitComposition(client)
        controller.composer.setInputMode(.chinese)
        client.inserted.removeAll()

        // A long press of Shift: the hint, then on.
        shift(true)
        let hinted = pump(timeout: 0.9) { controller.notice == onHint }
        check(hinted && !TranslateModeShared.state.isOn, "a long press of Shift: \(controller.notice ?? "no hint") at about 0.5 s")
        let on = pump(timeout: 1.5) { TranslateModeShared.state.isOn }
        shift(false)
        check(on && controller.composer.translateMode?.target == .english
              && controller.notice == tr("边打边译 已开启：中文 → 英文 · 再长按 Shift 关闭", "Translate as You Type on: Chinese → English · hold Shift again to turn off")
              && controller.composer.inputLanguage == .chinese && MenuBarIcon.shared.translating,
              "…at 1.0 s it's on (\(controller.notice ?? "-")), the menu bar badge shown, the input language not switched")
        check(pump(timeout: 2.2) { controller.notice == nil }, "…its notice up about 1.5 s")
        // A tap of Shift still switches the input language.
        tapShift(controller, client)
        check(controller.composer.inputLanguage == .english && TranslateModeShared.state.isOn, "a tap of Shift still switches the input language")
        // English is what it translates into: typed as usual.
        check(!press(controller, client, "o", code: 0x1F) && client.marked.isEmpty, "typing in English (the target) goes in as typed")
        tapShift(controller, client)

        // Pinyin collects into the draft; ⏎ translates and inserts at once.
        type("nihao", controller, client)
        check(!client.marked.contains("→"), "pinyin in the mode: '\(client.marked)'")
        _ = space(controller, client)
        check(client.marked == "你好" && client.inserted.isEmpty, "the words picked collect into the draft: '\(client.marked)'")
        model.delay = 0.3
        _ = enter(controller, client)
        check(client.marked == "你好 · \(translating)" && controller.panelModel().rows.isEmpty,
              "⏎: '\(client.marked)', no candidates")
        let inserted = pump(timeout: 5) { client.inserted.last == "Hello" }
        check(inserted && client.marked.isEmpty && !controller.composer.isComposing, "…and the translation goes in at once (\(client.inserted))")
        check(!enter(controller, client), "…not sent: the next ⏎ is the app's")
        let instructions = model.requests.last?.instructions ?? ""
        check(instructions.contains("Tone of the translation") && instructions.contains(AppTone.natural.rule)
              && model.requests.last?.examples.isEmpty == true,
              "Translate as You Type's own request: one line, a tone line (natural here)")

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
        check(client.marked == "\(typed)" && controller.composer.phase == .drafting, "Esc while translating stops it, the draft kept: '\(client.marked)'")
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
        check(failed && client.marked == "\(failing)" && controller.composer.phase == .drafting,
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

        // The chip near the caret, in the candidate panel (non-activating, never key: the field keeps the focus).
        let japanese = OutputLanguage("ja")
        settings.setOrder([OutputLanguage.english, japanese, .chinese])
        let panel = CandidatePanel.shared
        func chip() -> String { panel.isVisible ? panel.view.model.chip.map { "\($0.source) → \($0.target)" } ?? "none" : "hidden" }
        let (zhEn, enEn, zhJa) = (tr("中 → 英", "ZH → EN"), tr("英 → 英", "EN → EN"), tr("中 → 日", "ZH → JA"))
        /// A click on a part of the chip, through the panel's own mouse handling.
        func click(_ part: CandidateView.ChipPart) {
            guard let frames = panel.view.chipFrames else { return check(false, "the chip is in the panel to click") }
            let rect = part == .source ? frames.source : frames.target
            let point = panel.view.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
            guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                                                context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
            check(panel.view.chipPart(at: panel.view.convert(point, from: nil)) == part, "a click there is on the chip's \(part) part")
            panel.view.mouseDown(with: down)
        }
        endNotice()
        controller.refreshTranslateChip()
        check(chip() == zhEn && panel.view.model.rows.isEmpty && !panel.canBecomeKey && !panel.isKeyWindow
              && panel.styleMask.contains(.nonactivatingPanel), "the chip near the caret while it's on: \(chip())")
        snapshot("translate-mode-chip", in: snapshotDirectory)
        type("nihao", controller, client)
        check(chip() == zhEn && panel.view.model.rows.first?.text == "你好", "…on top of the mode's candidates")
        snapshot("translate-mode-chip-pinyin", in: snapshotDirectory)
        _ = space(controller, client)
        check(chip() == zhEn && client.marked == "你好", "…and over the draft (\(chip()))")
        // Its source part: as a tap of Shift.
        click(.source)
        check(controller.composer.inputLanguage == .english && chip() == enEn && client.marked == "你好",
              "a click on 「中」 switches the input language, as a tap of Shift: \(chip())")
        click(.source)
        check(controller.composer.inputLanguage == .chinese && chip() == zhEn, "…and back (\(chip()))")
        // Its target part: the output languages, the target checked; Japanese clicked is the target at once.
        click(.target)
        let listed = panel.view.model.rows
        check(listed.map(\.text) == [OutputLanguage.english, japanese, .chinese].map(UIText.name) && listed.map(\.label) == ["✓", "", ""]
              && chip() == zhEn, "a click on 「英」 lists the output languages, English checked: \(listed.map { $0.label + $0.text })")
        snapshot("translate-mode-chip-list", in: snapshotDirectory)
        panel.onSelect?(1)
        check(controller.composer.translateMode?.target == japanese && chip() == zhJa && panel.view.model.rows.isEmpty
              && client.marked == "你好" && TranslateModeShared.defaults.string(forKey: "translateModeTarget") == "ja",
              "Japanese clicked: the target at once, the chip \(chip()), the draft '\(client.marked)', kept as the last pick")
        _ = enter(controller, client)
        check(pump(timeout: 5) { client.inserted.last == "こんにちは" }, "…and the next translation into it (\(client.inserted.last ?? ""))")
        // A key closes the list, and does what it does.
        click(.target)
        type("ni", controller, client)
        check(!TranslateModeShared.listOpen && chip() == zhJa && panel.view.model.rows.first?.label == "1",
              "a key closes the list: the candidates again, under the chip")
        _ = escape(controller, client)
        check(pump(timeout: 1) { chip() == zhJa && panel.view.model.rows.isEmpty }, "…the chip alone again (\(chip()))")

        // A long press again: off, the chip gone.
        let off = longPress(hint: offHint)
        check(off.hinted && off.toggled && controller.composer.translateMode == nil && !MenuBarIcon.shared.translating
              && controller.notice == tr("边打边译 已关闭", "Translate as You Type off") && panel.view.model.chip == nil,
              "a long press again turns it off, the chip gone: \(controller.notice ?? "-")")
        draft("nihao")
        check(client.inserted.last == "你好" && client.marked.isEmpty, "off: words go straight in again")

        // On again: into the language picked last, the notice naming it.
        let again = longPress(hint: onHint)
        check(again.toggled && controller.composer.translateMode?.target == japanese
              && controller.notice == tr("边打边译 已开启：中文 → 日语 · 再长按 Shift 关闭", "Translate as You Type on: Chinese → Japanese · hold Shift again to turn off"),
              "on again: into the last pick, \(controller.notice ?? "-")")
        draft("nihao")
        check(client.marked == "你好", "…the draft as typed, the chip naming 中 → 日: '\(client.marked)'")
        controller.commitComposition(client)
        // Japanese removed in the settings while it's on (read again on the next key): into the first output language
        // at once, the chip following.
        settings.setOrder([OutputLanguage.english, .chinese])
        type("ni", controller, client)
        check(TranslateModeShared.state.session?.target == .english && controller.composer.translateMode?.target == .english
              && chip() == zhEn && MenuBarIcon.shared.translating,
              "the target removed while it's on: into English at once, the chip following (\(chip()))")
        _ = escape(controller, client)
        _ = longPress(hint: offHint)
        // Japanese no longer offered: the first again. Turned on while English is typed: still into English.
        tapShift(controller, client)
        let english = longPress(hint: onHint)
        check(english.toggled && controller.composer.translateMode?.target == .english && controller.composer.inputLanguage == .english
              && controller.notice == tr("边打边译 已开启：中文 → 英文 · 再长按 Shift 关闭", "Translate as You Type on: Chinese → English · hold Shift again to turn off"),
              "a pick no longer offered: the first output language; English typed doesn't change it (\(controller.notice ?? "-"))")
        check(!press(controller, client, "o", code: 0x1F) && client.marked.isEmpty, "…and English goes in as typed")
        tapShift(controller, client)
        _ = longPress(hint: offHint)

        // Another app active with no text field in it (Finder, `watchApps`): off at once, the draft in as typed, the chip
        // and the menu bar badge gone, no notice; a press of Shift held then ends, its hint gone, and turns nothing on.
        controller.toggleTranslateMode()
        endNotice()
        draft("nihao")
        shift(true)
        let holding = pump(timeout: 0.9) { controller.notice == offHint }
        AllInOneIMEInputController.otherAppActivated("com.apple.finder")
        check(holding && !TranslateModeShared.state.isOn && controller.composer.translateMode == nil && client.inserted.last == "你好"
              && client.marked.isEmpty && ["hidden", "none"].contains(chip()) && !MenuBarIcon.shared.translating
              && controller.notice == nil && TranslateModeShared.hold.held == nil,
              "Finder active: off, the draft in as typed (\(client.inserted.last ?? "-")), no chip (\(chip())), no badge, no notice (\(controller.notice ?? "none"))")
        let later = pump(timeout: 0.7) { TranslateModeShared.state.isOn }  // past the toggle's time, Shift still held
        shift(false)
        check(!later && !TranslateModeShared.state.isOn, "…the press of Shift held then turns nothing on later")
        let (own, other) = (ProcessInfo.processInfo.processIdentifier, pid_t(1))
        check(TranslateModeShared.isOtherApp(pid: other, id: "com.apple.finder", frontmost: other)
              && !TranslateModeShared.isOtherApp(pid: own, id: Bundle.main.bundleIdentifier, frontmost: own)
              && !TranslateModeShared.isOtherApp(pid: other, id: Updater.settingsBundleID, frontmost: other)
              && !TranslateModeShared.isOtherApp(pid: other, id: "com.apple.finder", frontmost: own),
              "…not the input method itself, its settings app, or an app no longer frontmost (a stale notice)")

        // Another app leaves it, with no notice; an app that translates always turns it on, in its own tone.
        controller.toggleTranslateMode()
        controller.commitComposition(client)
        endNotice()
        controller.deactivateServer(client)
        check(chip() != zhEn, "the field left: the chip goes (\(chip()))")
        client.bundleIDOverride = chat
        controller.activateServer(client)
        check(!TranslateModeShared.state.isOn && controller.composer.translateMode == nil && controller.notice == nil
              && !MenuBarIcon.shared.translating && chip() != zhEn, "switching to another app leaves it, with no notice and no chip")
        client.bundleIDOverride = mail
        controller.activateServer(client)
        check(TranslateModeShared.state.isOn && controller.composer.translateMode?.target == .english, "an app that translates always turns it on")
        draft("nihao")
        _ = enter(controller, client)
        check(pump(timeout: 5) { client.inserted.last == "Hello" } && model.requests.last?.instructions.contains(AppTone.formal.rule) == true,
              "…in the app's tone (its first rewrite style, 正式)")
        controller.commitComposition(client)
        client.bundleIDOverride = notes
        controller.activateServer(client)
        check(!TranslateModeShared.state.isOn, "…and leaving that app leaves it")
        check(AppProfileText.summary(AppProfile(translateAlways: true)) == tr("总是边打边译", "Always Translate as You Type"),
              "Settings → Apps says so: \(AppProfileText.summary(AppProfile(translateAlways: true)))")
    }
}

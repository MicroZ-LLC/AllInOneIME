import AllInOneIMECore
import AppKit

/// Translate as You Type (「边打边译」, `TranslateMode`) for the whole input method: on or off for every text field (IMK
/// makes a controller per field), and the long press of Shift that turns it on and off.
@MainActor
enum TranslateModeShared {
    /// How long the notice of a long press turning it on or off stays up.
    static let noticeLasting: TimeInterval = 1.5
    static var state = TranslateMode.State()
    /// The press of Shift being timed (keys reach the field being typed in, one at a time).
    static var hold = TranslateMode.ShiftHold()
    /// Counts the presses: the timers of an older one do nothing.
    static var holdToken = 0
    /// Whether Shift is still down, with no mouse button, when a timer goes off (the self-test supplies its own).
    static var shiftHeld: () -> Bool = { NSEvent.modifierFlags.contains(.shift) && NSEvent.pressedMouseButtons == 0 }
    /// The mode said it lets text in as typed while secure input is on (once each time it comes on).
    static var toldSecureInput = false
}

extension AllInOneIMEInputController {
    /// The app of the field being typed in.
    private var modeApp: String? { (clientOverride ?? client())?.bundleIdentifier() }

    // MARK: The long press of Shift

    /// A modifier change, after the composer's own (a tap of Shift still switches the input language): Shift down on
    /// its own starts timing a long press, which the timers check (`shiftHoldElapsed`).
    @MainActor
    func translateModeFlagsChanged(keyCode: UInt16, modifiers: KeyModifiers) {
        guard TranslateModeShared.hold.flagsChanged(keyCode: keyCode, modifiers: modifiers) else { return }
        TranslateModeShared.holdToken += 1
        let token = TranslateModeShared.holdToken
        for delay in [TranslateMode.ShiftHold.hintAfter, TranslateMode.ShiftHold.toggleAfter] {
            // A little after: a timer never finds the press shorter than it waits for.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.02) { [weak self] in
                guard let self, token == TranslateModeShared.holdToken else { return }
                self.shiftHoldElapsed()
            }
        }
    }

    /// A key went down: Shift held with it is for a capital or a shortcut. With the mode on here while secure input is
    /// on elsewhere, nothing collects (text goes in as typed): said once each time. (In the app holding it the input
    /// method is paused, and says so itself.)
    @MainActor
    func translateModeKeyDown() {
        TranslateModeShared.hold.keyDown()
        guard composer.translateMode != nil else { return }
        guard secureInputActive() else {
            TranslateModeShared.toldSecureInput = false
            return
        }
        guard !TranslateModeShared.toldSecureInput, !SecureInput.blocksComposing(clientOverride ?? client()) else { return }
        TranslateModeShared.toldSecureInput = true
        showNotice(tr("边打边译：系统安全输入开着，照原样上屏", "Translate as You Type: secure input is on, text goes in as typed"), client: nil)
    }

    /// A timer of the press went off: the hint near the caret ("keep holding"), then the toggle. Not if Shift's release
    /// went unseen, the pointer was used meanwhile (a Shift-click), or dictation runs.
    @MainActor
    func shiftHoldElapsed() {
        guard let held = TranslateModeShared.hold.held else { return }
        guard TranslateModeShared.shiftHeld(), composer.voice == .off else {
            TranslateModeShared.hold.cancel()
            return
        }
        switch TranslateModeShared.hold.poll(pointerUsed: pointerUsedWithin(held)) {
        case .hint?:
            // Up until about when the toggle would come; released before it, nothing happens.
            showNotice(holdHint(), client: nil,
                       lasting: TranslateMode.ShiftHold.toggleAfter - TranslateMode.ShiftHold.hintAfter + 0.3)
        case .toggle?:
            toggleTranslateMode()
        case nil:
            break
        }
    }

    /// 「继续按住 → 边打边译」, or 「继续按住 → 关闭边打边译」 while it's on.
    @MainActor
    private func holdHint() -> String {
        if TranslateModeShared.state.isOn {
            return tr("继续按住 → 关闭边打边译", "Keep holding → Translate as You Type off")
        }
        guard TranslateMode.target(source: composer.inputLanguage, outputs: loadSettings().outputLanguages) != nil else {
            return noTargetText
        }
        return tr("继续按住 → 边打边译", "Keep holding → Translate as You Type")
    }

    // MARK: On and off

    /// A long press of Shift: on (`enterTranslateMode`) or off, with a notice either way.
    @MainActor
    func toggleTranslateMode() {
        if TranslateModeShared.state.isOn { leaveTranslateMode() } else { enterTranslateMode() }
    }

    /// On, for every field: into the first output language that isn't the one typed, in the app's tone. In an app with
    /// no AI it's on but does nothing there, and says so.
    @MainActor
    private func enterTranslateMode() {
        let config = loadSettings()
        guard let session = TranslateModeShared.state.enter(source: composer.inputLanguage, config: config) else {
            showNotice(noTargetText, client: nil)
            return
        }
        log.notice("Translate as You Type on (into \(session.target.code, privacy: .public))")
        let app = modeApp
        let allowed = config.allowsAI(in: app)
        perform(composer.setTranslateMode(allowed ? session : nil), client: nil)
        MenuBarIcon.shared.setTranslating(true)
        showOnNotice(session, allowed: allowed)
    }

    @MainActor
    private func leaveTranslateMode() {
        log.notice("Translate as You Type off")
        TranslateModeShared.state.leave()
        perform(composer.setTranslateMode(nil), client: nil)
        MenuBarIcon.shared.setTranslating(false)
        showNotice(tr("边打边译 已关闭", "Translate as You Type off"), client: nil, lasting: TranslateModeShared.noticeLasting)
    }

    /// A text field became active (`activateServer`, after the app's settings): another app leaves the mode, with no
    /// notice, unless it translates always (`AppProfile.translateAlways`), where it comes on. The composer of this field
    /// follows.
    @MainActor
    func translateModeActivated(app: String?) {
        TranslateModeShared.hold.cancel()
        let config = loadSettings()
        let transition = TranslateModeShared.state.activated(app: app, source: composer.inputLanguage, config: config)
        let allowed = config.allowsAI(in: app)
        perform(composer.setTranslateMode(TranslateModeShared.state.session.flatMap { allowed ? $0 : nil }), client: nil)
        MenuBarIcon.shared.setTranslating(TranslateModeShared.state.isOn)
        switch transition {
        case let .entered(session):
            log.notice("Translate as You Type on (the app translates always)")
            showOnNotice(session, allowed: allowed)
        case .left:
            log.notice("Translate as You Type off (another app)")
        case .unchanged:
            break
        }
    }

    /// 「边打边译 已开启：中文 → 英文 · 再长按 Shift 关闭」, from the language typed (when that's the target: the first
    /// other input language); and why it does nothing here if it doesn't.
    @MainActor
    private func showOnNotice(_ session: TranslateMode.Session, allowed: Bool) {
        let typed = composer.inputLanguage
        let from = typed.matches(session.target) ? composer.inputLanguages.first { !$0.matches(session.target) } : typed
        let languages = (from.map { UIText.name(OutputLanguage($0)) + " → " } ?? "") + UIText.name(session.target)
        let why = !allowed ? tr(" · 这个 App 里关了 AI，照原样上屏", " · AI is off in this app, text goes in as typed")
            : secureInputActive() ? tr(" · 系统安全输入开着，暂时照原样上屏", " · secure input is on, text goes in as typed for now") : ""
        let text = tr("边打边译 已开启：\(languages) · 再长按 Shift 关闭", "Translate as You Type on: \(languages) · hold Shift again to turn off")
        showNotice(text + why, client: nil, lasting: why.isEmpty ? TranslateModeShared.noticeLasting : nil)
    }

    private var noTargetText: String {
        tr("没有要翻译成的语言：在设置的「翻译与改写」里加一种", "No language to translate into: add one under Translate & Rewrite in the settings")
    }

    // MARK: The request

    /// Translate as You Type's request for `input` (`Composer.Effect.startTranslateMode`), in `app`'s settings; in a terminal
    /// on one line.
    @MainActor
    func translateModeStream(_ input: String, session: TranslateMode.Session, app: String?, id: Int)
        -> AsyncThrowingStream<ConversionUpdate, Error> {
        conversionTask?.cancel()
        (lastElapsed, lastFromCache, lastHidden, lastShortened) = (nil, false, 0, false)
        log.notice("conversion \(id) started (Translate as You Type, \(input.count) chars, into \(session.target.code, privacy: .public))")
        let stream = converter.translateMode(input, target: session.target, app: app)
        return Self.isTerminal(clientOverride ?? client()) ? Self.oneLine(stream) : stream
    }

    // MARK: The footer

    /// The candidate panel's footer while pinyin is typed in the mode: what ⏎ and ⇧⏎ do.
    @MainActor
    func translateModeFooter() -> String? {
        guard composer.inModeComposition, let target = composer.translateMode?.target else { return nil }
        let name = UIText.name(target)
        return tr("空格 选词 · ⏎ 翻译成\(name)上屏 · ⇧⏎ 原文上屏", "Space picks · ⏎ translate to \(name) and insert · ⇧⏎ as typed")
    }
}

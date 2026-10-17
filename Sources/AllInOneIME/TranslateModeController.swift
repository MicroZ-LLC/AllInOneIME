import AllInOneIMECore
import AppKit

/// Translation mode (`TranslateMode`) for the whole input method: on or off for every text field (IMK makes a controller
/// per field), and the long press of Shift that turns it on and off.
@MainActor
enum TranslateModeShared {
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
        guard let session = composer.translateMode else { return }
        guard secureInputActive() else {
            TranslateModeShared.toldSecureInput = false
            return
        }
        guard !TranslateModeShared.toldSecureInput, !SecureInput.blocksComposing(clientOverride ?? client()) else { return }
        TranslateModeShared.toldSecureInput = true
        showNotice(indicator(session) + tr("：系统安全输入开着，照原样上屏", ": secure input is on, text goes in as typed"), client: nil)
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

    /// 「继续按住 → 中→英」, or what holding on would turn off.
    @MainActor
    private func holdHint() -> String {
        if let session = TranslateModeShared.state.session {
            return tr("继续按住 → 关闭 \(indicator(session))", "Keep holding → \(indicator(session)) off")
        }
        guard let target = TranslateMode.target(source: composer.inputLanguage, outputs: loadSettings().outputLanguages) else {
            return noTargetText
        }
        return tr("继续按住 → ", "Keep holding → ") + TranslateMode.indicator(from: composer.inputLanguage, to: target)
    }

    // MARK: On and off

    @MainActor
    func toggleTranslateMode() {
        if TranslateModeShared.state.isOn { leaveTranslateMode() } else { enterTranslateMode(target: nil, tone: nil) }
    }

    /// `@mode …`, `@mode off`, `@exit` (`Composer.Effect.translateMode`).
    @MainActor
    func changeTranslateMode(_ change: TranslateMode.Change) {
        switch change {
        case let .enter(target, tone): enterTranslateMode(target: target, tone: tone)
        case .leave: leaveTranslateMode()
        }
    }

    /// On, for every field: into `target` (nil: the first output language that isn't the one typed), in `tone` (nil: the
    /// app's). In an app with no AI it's on but does nothing there, and says so.
    @MainActor
    private func enterTranslateMode(target: OutputLanguage?, tone: TranslateMode.Tone?) {
        let config = loadSettings()
        guard let session = TranslateModeShared.state.enter(target: target, tone: tone, source: composer.inputLanguage, config: config) else {
            showNotice(noTargetText, client: nil)
            return
        }
        log.notice("translation mode on (into \(session.target.code, privacy: .public))")
        let app = modeApp
        let allowed = config.allowsAI(in: app)
        perform(composer.setTranslateMode(allowed ? session : nil), client: nil)
        refreshTranslateModeCommands()
        showNotice(onText(session, allowed: allowed), client: nil)
    }

    @MainActor
    private func leaveTranslateMode() {
        guard let session = TranslateModeShared.state.session else {
            showNotice(tr("翻译模式没有开", "Translation mode isn't on"), client: nil)
            return
        }
        log.notice("translation mode off")
        TranslateModeShared.state.leave()
        perform(composer.setTranslateMode(nil), client: nil)
        refreshTranslateModeCommands()
        showNotice(offText(session), client: nil)
    }

    /// A text field became active (`activateServer`, after the app's settings): another app leaves the mode, unless it
    /// translates always (`AppProfile.translateAlways`), where it comes on. The composer of this field follows.
    @MainActor
    func translateModeActivated(app: String?) {
        TranslateModeShared.hold.cancel()
        let config = loadSettings()
        let transition = TranslateModeShared.state.activated(app: app, source: composer.inputLanguage, config: config)
        let allowed = config.allowsAI(in: app)
        perform(composer.setTranslateMode(TranslateModeShared.state.session.flatMap { allowed ? $0 : nil }), client: nil)
        refreshTranslateModeCommands()
        switch transition {
        case let .entered(session):
            log.notice("translation mode on (the app translates always)")
            showNotice(onText(session, allowed: allowed), client: nil)
        case let .left(session):
            log.notice("translation mode off (another app)")
            showNotice(offText(session), client: nil)
        case .unchanged:
            break
        }
    }

    /// 「中→英」 for `session`, from the language typed (when that's the target: the first other input language).
    @MainActor
    private func indicator(_ session: TranslateMode.Session) -> String {
        let typed = composer.inputLanguage
        let from = typed.matches(session.target) ? composer.inputLanguages.first { !$0.matches(session.target) } : typed
        return TranslateMode.indicator(from: from, to: session.target)
    }

    /// 「中→英 已开启」 / "中→英 on", with the tone `@mode` named, and why it does nothing here if it doesn't.
    @MainActor
    private func onText(_ session: TranslateMode.Session, allowed: Bool) -> String {
        let tone = session.tone.map { " · " + $0.name(chinese: UIText.chinese) } ?? ""
        let why = !allowed ? tr("：这个 App 里关了 AI，照原样上屏", ": AI is off in this app, text goes in as typed")
            : secureInputActive() ? tr("：系统安全输入开着，暂时照原样上屏", ": secure input is on, text goes in as typed for now") : ""
        return indicator(session) + tr(" 已开启", " on") + tone + why
    }

    @MainActor
    private func offText(_ session: TranslateMode.Session) -> String { indicator(session) + tr(" 已关闭", " off") }

    private var noTargetText: String {
        tr("没有要翻译成的语言：在设置的「翻译与改写」里加一种", "No language to translate into: add one under Translate & Rewrite in the settings")
    }

    // MARK: The request

    /// Translation mode's request for `input` (`Composer.Effect.startTranslateMode`), in `app`'s settings; in a terminal
    /// on one line.
    @MainActor
    func translateModeStream(_ input: String, session: TranslateMode.Session, app: String?, id: Int)
        -> AsyncThrowingStream<ConversionUpdate, Error> {
        conversionTask?.cancel()
        (lastElapsed, lastFromCache, lastHidden, lastShortened) = (nil, false, 0, false)
        log.notice("conversion \(id) started (translation mode, \(input.count) chars, into \(session.target.code, privacy: .public))")
        let stream = converter.translateMode(input, target: session.target, tone: session.tone, app: app)
        return Self.isTerminal(clientOverride ?? client()) ? Self.oneLine(stream) : stream
    }

    // MARK: Commands and hints

    /// `commands` with translation mode's: `@mode` always, `@exit` while it's on; never over a command of the user's
    /// (or a plugin's, an extension's) with the same name.
    @MainActor
    static func withTranslateModeCommands(_ commands: [Command]) -> [Command] {
        let others = commands.filter { $0 != .translationMode && $0 != .exitMode }
        let taken = Set(others.map(\.name))
        let mode: [Command] = [.translationMode] + (TranslateModeShared.state.isOn ? [.exitMode] : [])
        return others + mode.filter { !taken.contains($0.name) }
    }

    @MainActor
    func refreshTranslateModeCommands() {
        let updated = Self.withTranslateModeCommands(composer.commands)
        if updated != composer.commands { composer.commands = updated }
    }

    /// The candidate panel's footer while pinyin is typed in the mode: what ⏎ and ⇧⏎ do.
    @MainActor
    func translateModeFooter() -> String? {
        guard composer.inModeComposition, let target = composer.translateMode?.target else { return nil }
        let name = UIText.name(target)
        return tr("空格 选词 · ⏎ 翻译成\(name)上屏 · ⇧⏎ 原文上屏", "Space picks · ⏎ translate to \(name) and insert · ⇧⏎ as typed")
    }

    /// The hint under `@mode …` and `@exit` (`draftHint`): what the action key does.
    @MainActor
    func translateModeHint(_ command: Command, how: String) -> String? {
        guard command == .translationMode || command == .exitMode else { return nil }
        if command == .exitMode || TranslateMode.parse(composer.sentText) == .change(.leave) {
            return "\(how) → " + tr("关闭翻译模式", "translation mode off")
        }
        return "\(how) → " + tr("打开翻译模式（如 @mode en formal、@mode 日语 口语；@mode off 关闭）",
                                "translation mode on (e.g. @mode en formal, @mode ja casual; @mode off)")
    }
}

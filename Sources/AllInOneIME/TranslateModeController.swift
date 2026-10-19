import AllInOneIMECore
import AppKit
import InputMethodKit

/// Translate as You Type (「边打边译」, `TranslateMode`) for the whole input method: on or off for every text field (IMK
/// makes a controller per field), the long press of Shift that turns it on and off, and the language picked last on
/// its chip.
@MainActor
enum TranslateModeShared {
    /// How long the notice of a long press turning it on or off stays up.
    static let noticeLasting: TimeInterval = 1.5
    static var state = TranslateMode.State()
    /// The press of Shift being timed (keys reach the field being typed in, one at a time).
    static var hold = TranslateMode.ShiftHold(pointer: { pointer() }, stickyKeys: { stickyKeys() })
    /// Counts the presses: the timers of an older one do nothing.
    static var holdToken = 0
    /// Whether Shift is still down, with no mouse button, when a timer goes off (the self-test supplies its own).
    static var shiftHeld: () -> Bool = { NSEvent.modifierFlags.contains(.shift) && NSEvent.pressedMouseButtons == 0 }
    /// Whether Shift is down now, as the system has it: the press is synced with it where its modifier changes may have
    /// gone unseen, another field or another app becoming active (the self-test supplies its own).
    static var shiftDown: () -> Bool = { NSEvent.modifierFlags.contains(.shift) }
    /// Where the mouse is, while Shift is held (the self-test supplies its own).
    static var pointer: () -> CGPoint = { NSEvent.mouseLocation }
    /// Whether Sticky Keys is on (Accessibility → Keyboard), as the system keeps it (the self-test supplies its own).
    static var stickyKeys: () -> Bool = { universalAccess?.bool(forKey: "stickyKey") ?? false }
    private static let universalAccess = UserDefaults(suiteName: "com.apple.universalaccess")
    /// The press's hint ("keep holding") while it may still be up, and the field showing it: taken down once the press
    /// ends short of the toggle.
    static var hint: String?
    static weak var hintField: AllInOneIMEInputController?
    /// The mode said it lets text in as typed while secure input is on (once each time it comes on).
    static var toldSecureInput = false
    /// Where the language picked last on the chip is kept: this input method's own defaults (the self-test leaves the
    /// user's alone).
    static var defaults = UserDefaults.standard
    static let lastTargetKey = "translateModeTarget"
    /// The language picked last on the chip, for every app and across launches (nil: none yet): what it translates
    /// into while that's an output language (`TranslateMode.target(last:outputs:)`).
    static var lastTarget: OutputLanguage? {
        get { defaults.string(forKey: lastTargetKey).map(OutputLanguage.init) }
        set { defaults.set(newValue?.code, forKey: lastTargetKey) }
    }
    /// The chip's list of output languages is open (its target part clicked); a key closes it.
    static var listOpen = false
    /// Counts the chip's refreshes after a key or text put in: only the last one runs.
    static var chipToken = 0

    /// Another app becoming active turns it off (`AllInOneIMEInputController.otherAppActivated`), whether it has a text
    /// field or not (`isOtherApp`).
    static func watchApps() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  isOtherApp(pid: app.processIdentifier, id: app.bundleIdentifier,
                             frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier) else { return }
            let id = app.bundleIdentifier
            MainActor.assumeIsolated { AllInOneIMEInputController.otherAppActivated(id) }
        }
    }

    /// Whether an app becoming active (its process `pid`, bundle id `id`) is another app's: not the input method itself
    /// (its settings window) nor its settings app, and still the frontmost one (`frontmost`'s process): a notice that
    /// comes after the next app's activation, and maybe after its text field's, is stale.
    nonisolated static func isOtherApp(pid: pid_t, id: String?, frontmost: pid_t?) -> Bool {
        pid != ProcessInfo.processInfo.processIdentifier && id != Updater.settingsBundleID && frontmost == pid
    }
}

extension AllInOneIMEInputController {
    /// The app of the field being typed in.
    private var modeApp: String? { (clientOverride ?? client())?.bundleIdentifier() }

    // MARK: The long press of Shift

    /// A modifier change, after the composer's own (a tap of Shift still switches the input language): Shift down on
    /// its own starts timing a long press, which the timers check (`shiftHoldElapsed`).
    @MainActor
    func translateModeFlagsChanged(keyCode: UInt16, modifiers: KeyModifiers) {
        guard TranslateModeShared.hold.flagsChanged(keyCode: keyCode, modifiers: modifiers) else {
            Self.endHoldHint()
            return
        }
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

    /// A modifier change secure input keeps from the composer (`shiftDown`: Shift down after it): no long press, and
    /// Shift as it is for the next one.
    @MainActor
    func translateModeFlagsMissed(shiftDown: Bool) {
        TranslateModeShared.hold.resync(shiftDown: shiftDown)
        Self.endHoldHint()
    }

    /// A key went down: Shift held with it is for a capital or a shortcut. With the mode on here while secure input is
    /// on elsewhere, nothing collects (text goes in as typed): said once each time. (In the app holding it the input
    /// method is paused, and says so itself.)
    @MainActor
    func translateModeKeyDown() {
        TranslateModeShared.hold.keyDown()
        Self.endHoldHint()
        guard composer.translateMode != nil else { return }
        TranslateModeShared.listOpen = false  // a key closes the chip's list, and does what it does
        scheduleChipRefresh()
        guard services.secureInputActive() else {
            TranslateModeShared.toldSecureInput = false
            return
        }
        guard !TranslateModeShared.toldSecureInput, !SecureInput.blocksComposing(clientOverride ?? client()) else { return }
        TranslateModeShared.toldSecureInput = true
        showNotice(tr("边打边译：系统安全输入开着，照原样上屏", "Translate as You Type: secure input is on, text goes in as typed"), client: nil)
    }

    /// A timer of the press went off: the hint near the caret ("keep holding"), then the toggle. Not if Shift's release
    /// went unseen, the pointer was used or moved meanwhile (a Shift-click), or dictation runs.
    @MainActor
    func shiftHoldElapsed() {
        guard let held = TranslateModeShared.hold.held else { return }
        guard TranslateModeShared.shiftHeld(), composer.voice == .off else {
            TranslateModeShared.hold.cancel()
            Self.endHoldHint()
            return
        }
        switch TranslateModeShared.hold.poll(pointerUsed: services.pointerUsedWithin(held)) {
        case .hint?:
            // Up until about when the toggle would come; the press ended before it, nothing happens and it goes then.
            let hint = holdHint()
            showNotice(hint, client: nil,
                       lasting: TranslateMode.ShiftHold.toggleAfter - TranslateMode.ShiftHold.hintAfter + 0.3)
            if hint != noTargetText { (TranslateModeShared.hint, TranslateModeShared.hintField) = (hint, self) }
        case .toggle?:
            TranslateModeShared.hint = nil  // the toggle's own notice takes its place
            toggleTranslateMode()
        case nil:
            Self.endHoldHint()  // the pointer used or moved: a Shift-click
        }
    }

    /// The press is no longer timed (released, a key, another modifier, the pointer, another field or app): its hint
    /// goes at once if it's still the notice up.
    @MainActor
    private static func endHoldHint() {
        guard TranslateModeShared.hold.held == nil, let hint = TranslateModeShared.hint else { return }
        TranslateModeShared.hint = nil
        TranslateModeShared.hintField?.endNotice(hint)
    }

    /// 「继续按住 → 边打边译」, or 「继续按住 → 关闭边打边译」 while it's on.
    @MainActor
    private func holdHint() -> String {
        if TranslateModeShared.state.isOn {
            return tr("继续按住 → 关闭边打边译", "Keep holding → Translate as You Type off")
        }
        guard TranslateMode.target(last: TranslateModeShared.lastTarget, outputs: services.loadSettings().outputLanguages) != nil else {
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

    /// On, for every field: into the language picked last on the chip (at first, the first output language), whatever
    /// is being typed, in the app's tone. In an app with no AI it's on but does nothing there, and says so.
    @MainActor
    private func enterTranslateMode() {
        let config = services.loadSettings()
        guard let session = TranslateModeShared.state.enter(last: TranslateModeShared.lastTarget, config: config) else {
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
        TranslateModeShared.listOpen = false
        perform(composer.setTranslateMode(nil), client: nil)
        MenuBarIcon.shared.setTranslating(false)
        showNotice(tr("边打边译 已关闭", "Translate as You Type off"), client: nil, lasting: TranslateModeShared.noticeLasting)
    }

    /// A text field became active (`activateServer`, after the app's settings): another app leaves the mode, with no
    /// notice, unless it translates always (`AppProfile.translateAlways`), where it comes on. The composer of this field
    /// follows, and the chip shows here (or no longer). A press of Shift ends, synced with Shift as it is (its release
    /// may have gone unseen).
    @MainActor
    func translateModeActivated(app: String?) {
        TranslateModeShared.hold.resync(shiftDown: TranslateModeShared.shiftDown())
        Self.endHoldHint()
        TranslateModeShared.listOpen = false
        let config = services.loadSettings()
        let transition = TranslateModeShared.state.activated(app: app, last: TranslateModeShared.lastTarget, config: config)
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
        refreshTranslateChip()
    }

    /// Another app became active (`TranslateModeShared.watchApps`), a text field in it or not: it leaves, with no
    /// notice, unless that app translates always (`State.appActivated`). The field still being typed in, if any,
    /// follows (its draft goes in as typed) and the chip goes. A press of Shift ends there, its hint gone.
    @MainActor
    static func otherAppActivated(_ app: String?) {
        TranslateModeShared.hold.resync(shiftDown: TranslateModeShared.shiftDown())
        endHoldHint()
        let field = activeController
        let config = field?.services.loadSettings() ?? LiveConfig.current
        guard case .left = TranslateModeShared.state.appActivated(app, config: config) else { return }
        log.notice("Translate as You Type off (another app)")
        TranslateModeShared.listOpen = false
        MenuBarIcon.shared.setTranslating(false)
        guard let field else { return }
        field.perform(field.composer.setTranslateMode(nil), client: nil)
        field.refreshTranslateChip()
    }

    /// The settings read again (`applySettings`, a key): a target no longer among the output languages (removed in the
    /// settings) gives way at once to the first of them (`State.follow`), in this field and on its chip.
    @MainActor
    func translateModeFollow(_ config: Config) {
        guard TranslateModeShared.state.follow(outputs: config.outputLanguages) else { return }
        let session = TranslateModeShared.state.session
        log.notice("Translate as You Type: into \(session?.target.code ?? "-", privacy: .public) (the target was removed)")
        perform(composer.setTranslateMode(session.flatMap { config.allowsAI(in: modeApp) ? $0 : nil }), client: nil)
        MenuBarIcon.shared.setTranslating(TranslateModeShared.state.isOn)
        refreshTranslateChip()
    }

    /// 「边打边译 已开启：中文 → 日语 · 再长按 Shift 关闭」, into the target, from the language typed (when that's the
    /// target: the first other input language); and why it does nothing here if it doesn't.
    @MainActor
    private func showOnNotice(_ session: TranslateMode.Session, allowed: Bool) {
        let typed = composer.inputLanguage
        let from = typed.matches(session.target) ? composer.inputLanguages.first { !$0.matches(session.target) } : typed
        let languages = (from.map { UIText.name(OutputLanguage($0)) + " → " } ?? "") + UIText.name(session.target)
        let why = !allowed ? tr(" · 这个 App 里关了 AI，照原样上屏", " · AI is off in this app, text goes in as typed")
            : services.secureInputActive() ? tr(" · 系统安全输入开着，暂时照原样上屏", " · secure input is on, text goes in as typed for now") : ""
        let text = tr("边打边译 已开启：\(languages) · 再长按 Shift 关闭", "Translate as You Type on: \(languages) · hold Shift again to turn off")
        showNotice(text + why, client: nil, lasting: why.isEmpty ? TranslateModeShared.noticeLasting : nil)
    }

    private var noTargetText: String {
        tr("没有要翻译成的语言：在设置的「翻译与改写」里加一种", "No language to translate into: add one under Translate & Rewrite in the settings")
    }

    // MARK: The chip

    /// The chip here (「中 → 英」, "ZH → EN", `TranslateMode.Chip`): while the mode is on in this field, the field active and not one
    /// secure input pauses; with its list of output languages while that's open. Nil otherwise.
    @MainActor
    func translateChip() -> TranslateMode.Chip? {
        guard composer.translateMode != nil, Self.activeController === self,
              !SecureInput.blocksComposing(clientOverride ?? client()) else { return nil }
        return composer.translateModeChip(choices: TranslateModeShared.listOpen ? services.loadSettings().outputLanguages : nil)
    }

    /// The chip's list is what the panel shows here (it's open and the chip is here), over anything else.
    @MainActor
    var translateChipListShown: Bool { TranslateModeShared.listOpen && translateChip() != nil }

    /// The panel when the composer has nothing to show in it: the chip, under it its list of output languages (the
    /// target checked) and the notice. False, and nothing shown: no chip here.
    @MainActor
    func showTranslateChip(_ client: IMKTextInput?) -> Bool {
        guard let client, let chip = translateChip() else { return false }
        let model = CandidateView.Model(PanelPresenter.chipModel(chip, notice: notice))
        let panel = CandidatePanel.shared
        panel.owner = self
        panel.onSelect = { [weak self] index in self?.pickTranslateTarget(row: index) }
        panel.onChip = { [weak self] part in self?.translateChipClicked(part) }
        let anchor = anchor(client)
        if !panel.shows(model, anchor: anchor) { panel.show(model, anchor: anchor) }  // nothing changed, nothing moved: as it is
        return true
    }

    /// A click on the chip: its source part switches the input language as a tap of Shift does; its target part opens
    /// (or closes) the list of output languages.
    @MainActor
    func translateChipClicked(_ part: CandidateView.ChipPart) {
        guard translateChip() != nil else { return }
        switch part {
        case .source:
            TranslateModeShared.listOpen = false
            perform(composer.shiftTapped(), client: nil)
        case .target:
            TranslateModeShared.listOpen.toggle()
        }
        refreshTranslateChip()
    }

    /// A language clicked in the chip's list (its row `index`): the target at once (the chip, the next translation), and
    /// from then on, everywhere (`TranslateModeShared.lastTarget`).
    @MainActor
    func pickTranslateTarget(row index: Int) {
        guard let language = translateChip()?.choice(at: index) else { return }
        TranslateModeShared.listOpen = false
        TranslateModeShared.lastTarget = language
        log.notice("Translate as You Type: into \(language.code, privacy: .public) (picked)")
        if let session = TranslateModeShared.state.retarget(language) {
            perform(composer.setTranslateMode(session), client: nil)
        }
        refreshTranslateChip()
    }

    /// The panel again as it should be, if the chip is (or was) in it here: after a click on it, a key, a field
    /// activated, the mode turned off.
    @MainActor
    func refreshTranslateChip() {
        let panel = CandidatePanel.shared
        let shown = panel.isVisible && panel.owner === self && panel.view.model.chip != nil
        guard shown || translateChip() != nil else { return }
        showPanel(clientOverride ?? client())
    }

    /// After a key or text put in, once the app has had it: the chip goes where the caret is now (a key the app types,
    /// a translation inserted, moves it). Not while the candidates are up: they place the panel themselves.
    @MainActor
    func scheduleChipRefresh() {
        TranslateModeShared.chipToken += 1
        let token = TranslateModeShared.chipToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, token == TranslateModeShared.chipToken, !self.composer.wantsPanel else { return }
            self.refreshTranslateChip()
        }
    }

    /// The field was left: the chip goes with it.
    @MainActor
    func hideTranslateChip() {
        TranslateModeShared.listOpen = false
        let panel = CandidatePanel.shared
        if panel.isVisible, panel.owner === self, panel.view.model.chip != nil { panel.hide() }
    }

    // MARK: The request

    /// Translate as You Type's request for `input` (`Composer.Effect.startTranslateMode`, `SessionTasks.translate`), in the
    /// app's settings; in a terminal on one line.
    @MainActor
    func startTranslateMode(_ input: String, session: TranslateMode.Session, id: Int) {
        tasks.cancel(.request)
        (lastElapsed, lastFromCache, lastHidden, lastShortened) = (nil, false, 0, false)
        log.notice("conversion \(id) started (Translate as You Type, \(input.count) chars, into \(session.target.code, privacy: .public))")
        let terminal = Self.isTerminal(clientOverride ?? client())
        tasks.translate(input, session: session, id: id,
                        in: SessionTasks.Place(app: appID, terminal: terminal, pastesInTerminal: false, improveTranslates: false,
                                               pluginLanguage: UIText.pluginLanguage),
                        converter: services.converter)
    }
}

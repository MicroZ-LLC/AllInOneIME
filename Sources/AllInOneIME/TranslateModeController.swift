import AllInOneIMECore
import AppKit
import InputMethodKit

/// Translate as You Type (「边打边译」, `TranslateMode`) for the whole input method: on or off for every text field (IMK
/// makes a controller per field; the session's long press of Shift turns it on and off: `setTranslateMode`), and the
/// language picked last on its chip.
@MainActor
enum TranslateModeShared {
    /// How long the notice of turning it on or off stays up.
    static let noticeLasting: TimeInterval = 1.5
    static var state = TranslateMode.State()
    /// Where the mouse is, while Shift is held, and whether Sticky Keys is on (Accessibility → Keyboard), as the system
    /// keeps it: what the session's long press of Shift goes by (`SuggestionsServices.pointer`, `stickyKeys`; the
    /// self-test supplies its own).
    static var pointer: () -> CGPoint = { NSEvent.mouseLocation }
    /// Whether Shift is still down, with no mouse button, when the long press's time comes (`SuggestionsServices.shiftHeld`:
    /// a release that went unseen turns nothing on or off; the self-test supplies its own).
    static var shiftHeld: () -> Bool = { NSEvent.modifierFlags.contains(.shift) && NSEvent.pressedMouseButtons == 0 }
    /// Whether Shift is down now, as a text field takes the focus (`SuggestionsServices.shiftDown`: its release, or its
    /// press, may have gone to the field before).
    static var shiftDown: () -> Bool = { NSEvent.modifierFlags.contains(.shift) }
    static var stickyKeys: () -> Bool = { universalAccess?.bool(forKey: "stickyKey") ?? false }
    private static let universalAccess = UserDefaults(suiteName: "com.apple.universalaccess")
    /// The mode said it lets text in as typed while secure input is on (once each time it comes on).
    static var toldSecureInput = false
    /// Where the language picked last on the chip is kept: this input method's own defaults (the self-test leaves the
    /// user's alone).
    static var defaults = UserDefaults.standard
    static let lastTargetKey = "translateModeTarget"
    /// The language picked last on the chip, for every app and across launches (nil: none yet): what it translates
    /// into while that's an output language (`TranslateMode.target(last:outputs:inputs:)`).
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

    /// A key went down. With the mode on here while secure input is on elsewhere, nothing collects (text goes in as
    /// typed): said once each time. (In the app holding it the input method is paused, and says so itself.)
    @MainActor
    func translateModeKeyDown() {
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

    // MARK: On and off

    /// On (`enterTranslateMode`) or off, with a notice either way.
    @MainActor
    func toggleTranslateMode() {
        if TranslateModeShared.state.isOn { leaveTranslateMode() } else { enterTranslateMode() }
    }

    /// A long press of Shift turned it on or off, the session's (`SuggestionsServices.setTranslateAsYouType`).
    @MainActor
    func setTranslateMode(_ on: Bool) {
        guard on != TranslateModeShared.state.isOn else { return }
        toggleTranslateMode()
    }

    /// On, for every field: into the language picked last on the chip (at first, the first output language other than
    /// the only one typed), whatever is being typed, in the app's tone. In an app with no AI it's on but does nothing
    /// there, and says so.
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
    /// notice, unless it translates always (`AppProfile.translateAlways`), where it comes on (a field in Code has none of
    /// it: `Composer.coding`). The composer of this field follows, and the chip shows here (or no longer).
    @MainActor
    func translateModeActivated(app: String?) {
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
    /// follows (its draft goes in as typed) and the chip goes. A long press of Shift there ends, its hint gone.
    @MainActor
    static func otherAppActivated(_ app: String?) {
        let field = activeController
        if let field { field.apply(field.session.otherAppActivated(), client: nil) }
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
    /// settings) gives way at once to the one it would come on into with none picked (`State.follow`), in this field
    /// and on its chip. With none (English alone typed, English left), it goes off and says where to add one, as a long
    /// press says when it can't come on.
    @MainActor
    func translateModeFollow(_ config: Config) {
        guard TranslateModeShared.state.follow(outputs: config.outputLanguages, inputs: config.inputLanguages) else { return }
        let session = TranslateModeShared.state.session
        let now = session.map { "into " + $0.target.code } ?? "off"
        log.notice("Translate as You Type: \(now, privacy: .public) (the target was removed)")
        if session == nil { TranslateModeShared.listOpen = false }
        perform(composer.setTranslateMode(session.flatMap { config.allowsAI(in: modeApp) ? $0 : nil }), client: nil)
        MenuBarIcon.shared.setTranslating(TranslateModeShared.state.isOn)
        refreshTranslateChip()
        if session == nil { showNotice(noTargetText, client: nil) }
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

    /// Nothing to translate into but the languages typed (`Config.hasLanguageToTranslateInto`): where one is added, the
    /// page named as the settings' sidebar names it.
    /// Half way through a long press of Shift, near the caret (`SuggestionsServices.holdHint`, as in 0.6.6): 「继续按住 →
    /// 边打边译」, 「继续按住 → 关闭边打边译」 while it's on, or that there's nothing to translate into.
    @MainActor
    func translateModeHoldHint() -> String {
        if TranslateModeShared.state.isOn {
            return tr("继续按住 → 关闭边打边译", "Keep holding → Translate as You Type off")
        }
        let config = services.loadSettings()
        guard config.hasLanguageToTranslateInto,
              TranslateMode.target(last: TranslateModeShared.lastTarget, outputs: config.outputLanguages) != nil else {
            return noTargetText
        }
        return tr("继续按住 → 边打边译", "Keep holding → Translate as You Type")
    }

    private var noTargetText: String {
        let page = SettingsPage.writing.title
        return tr("没有要翻译成的语言：在设置 →「\(page)」里加一种", "No language to translate into: add one in Settings → \(page)")
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
        let model = PanelPresenter.chipModel(chip, notice: notice, language: UIText.language)
        let panel = CandidatePanel.shared
        panel.owner = self
        // A click picks the clicked row's choice (`PanelModel.Row.choice`): its language's place in the chip's list.
        panel.onSelect = { [weak self] index in
            guard model.rows.indices.contains(index), let choice = model.rows[index].choice else { return }
            self?.pickTranslateTarget(choice)
        }
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

    /// A language clicked in the chip's list (`index` in it): the target at once (the chip, the next translation), and
    /// from then on, everywhere (`TranslateModeShared.lastTarget`).
    @MainActor
    func pickTranslateTarget(_ index: Int) {
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
        let shown = panel.isShowing && panel.owner === self && panel.view.model.chip != nil
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
        if panel.isShowing, panel.owner === self, panel.view.model.chip != nil { panel.hide() }
    }
}

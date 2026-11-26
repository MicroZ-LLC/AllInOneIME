import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import InputMethodKit

/// Autocomplete's suggestion (`SessionOutput.ghost`, the core's `Autocomplete`) after the caret: gray text in a window
/// of its own, on the caret's line, in the field's font where it tells it, on its text's baseline, a small Tab key
/// after it, cut at the field's edge where Accessibility tells its frame (`FocusedField.frame`). It takes no clicks; a
/// click or the wheel anywhere takes it down (the session sees the pointer used, `SessionServices.pointerUsedWithin`,
/// and ends the suggestion at the next key). Where the field tells no caret rect, or rects that don't agree, the
/// suggestion is a line of the candidate panel instead (`PanelModel.autocomplete`).
@MainActor
final class GhostOverlay: NSPanel {
    static let shared = GhostOverlay()

    /// The controller whose suggestion it shows.
    weak var owner: AnyObject?
    let ghost = GhostView()
    /// What it shows (nil: nothing).
    var text: String? { isVisible ? ghost.text : nil }
    /// Invisible and click-through in the self-test, as the candidate panel there (someone may be using the Mac); there
    /// the user's own clicks don't take it down either.
    static var invisible = false
    static var watchesPointer = true
    private var monitor: Any?
    /// Put back on screen as the candidate panel is (GitHub #61), while it shows.
    private var screenEvents: ScreenEvents?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
        // The candidate panel's level: above full-screen apps and popup menus.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)) - 100)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = ghost
        screenEvents = ScreenEvents { [weak self] in self?.resurface() }
    }

    /// Something that can take it off the screen with AppKit none the wiser (`ScreenEvents`): ordered in again while it
    /// shows a suggestion, the app shown again first if it was hidden (never activated).
    private func resurface() {
        guard !ghost.text.isEmpty else { return }
        CandidatePanel.unhideAppIfHidden()
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Where a suggestion goes on the screen: the caret's line (a rect as tall as the line), where the caret is on it
    /// (`x`), and the field's font there, if it tells one.
    struct Place: Equatable {
        var line: NSRect
        var x: CGFloat
        var font: NSFont?
    }

    /// `text` right after the caret at `place`, its baseline on the line's text's, cut at the screen's edge and at the
    /// field's (`field`, its frame where it is known: `GhostPlacement`). False, and nothing up: too little room there for
    /// its text (less than its first few characters).
    @discardableResult
    func show(_ text: String, at place: Place, field: NSRect? = nil) -> Bool {
        ghost.text = text
        ghost.font = Self.font(place.font, lineHeight: place.line.height)
        let line = place.line
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: place.x, y: line.midY)) } ?? NSScreen.main
        // Across: from the caret on, as far as the screen and the field go.
        let caret = NSRect(x: place.x, y: line.minY, width: 0, height: line.height)
        guard var frame = GhostPlacement.frame(size: ghost.fittingSize, caret: caret, visible: screen?.visibleFrame, field: field,
                                               chrome: ghost.chrome, minimumText: ghost.minimumTextWidth) else {
            hide()
            return false
        }
        // The text's baseline is the line's bottom and the font's descent: AppKit puts what makes a line taller than
        // its font (a line height multiple, a minimum) above the text, and a line's spacing below its rect.
        let baseline = line.minY + ghost.descent
        frame.origin.y = line.minY
        frame.size.height = max(line.height, baseline - line.minY + ghost.ascent)
        setFrame(frame, display: true)
        ghost.baseline = baseline - line.minY
        ghost.needsDisplay = true
        alphaValue = Self.invisible ? 0 : 1
        // Coming up: the app shown again first if it was hidden, never activated (GitHub #61).
        if !isVisible { CandidatePanel.unhideAppIfHidden() }
        orderFrontRegardless()
        watchPointer()
        return true
    }

    func hide() {
        // Its text too: one AppKit took off the screen (the app hidden) isn't put back once hidden (`resurface`).
        guard isVisible || monitor != nil || !ghost.text.isEmpty else { return }
        orderOut(nil)
        ghost.text = ""
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
    }

    /// The suggestion's font: the field's (`font`), unless it is taller than the line (a bogus one, or a zoomed-out
    /// view); else the system font about as big as text on a line `lineHeight` high.
    static func font(_ font: NSFont?, lineHeight: CGFloat) -> NSFont {
        if let font, (4...200).contains(font.pointSize), GhostView.lineHeight(font) <= lineHeight * 1.3 { return font }
        return NSFont.systemFont(ofSize: min(max((lineHeight / 1.25).rounded(), 10), 40))
    }

    /// A click or the wheel anywhere takes it down: the caret may move, the text scroll.
    private func watchPointer() {
        guard monitor == nil, Self.watchesPointer else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { _ in
            MainActor.assumeIsolated { GhostOverlay.shared.hide() }
        }
    }
}

/// The suggestion drawn: gray text on its baseline, then a small key cap with "Tab" in it.
final class GhostView: NSView {
    var text = ""
    var font = NSFont.systemFont(ofSize: 13)
    /// Where the text's baseline is, from the view's bottom.
    var baseline: CGFloat = 3

    override var isFlipped: Bool { false }

    /// A line of `font`, as AppKit lays it out: how tall, and how far its baseline is from its top. One layout manager
    /// answers every time (it keeps nothing of a font), not a new one each: a suggestion placed and drawn asked up to
    /// seven.
    static func lineHeight(_ font: NSFont) -> CGFloat { layoutManager.defaultLineHeight(for: font) }
    static func baselineOffset(_ font: NSFont) -> CGFloat { layoutManager.defaultBaselineOffset(for: font) }
    private static let layoutManager = NSLayoutManager()

    /// The font's line below its baseline, and above it.
    var descent: CGFloat { Self.lineHeight(font) - Self.baselineOffset(font) }
    var ascent: CGFloat { Self.baselineOffset(font) }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.placeholderTextColor]
    }

    private var keyAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: max(font.pointSize * 0.6, 8), weight: .medium), .foregroundColor: NSColor.tertiaryLabelColor]
    }

    private var keySize: NSSize {
        let label = ("Tab" as NSString).size(withAttributes: keyAttributes)
        return NSSize(width: label.width + 8, height: label.height + 2)
    }

    /// What of its width isn't the text's: the key cap and the gaps beside it.
    var chrome: CGFloat { keySize.width + 8 }

    /// The least room its text is shown in: its first few characters (all of a shorter one); with less, nothing shows
    /// (`GhostPlacement`).
    var minimumTextWidth: CGFloat { ceil((String(text.prefix(4)) as NSString).size(withAttributes: attributes).width) }

    override var fittingSize: NSSize {
        let size = (text as NSString).size(withAttributes: attributes)
        return NSSize(width: ceil(size.width) + chrome, height: ceil(max(size.height, keySize.height)))
    }

    override func draw(_ dirtyRect: NSRect) {
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let key = keySize
        let room = bounds.width - chrome
        // Cut where it doesn't fit (the screen's edge), with an ellipsis; one line of the font, on `baseline`.
        string.draw(with: NSRect(x: 0, y: baseline - descent, width: max(room, 0), height: Self.lineHeight(font)),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        // The key cap centered on the capitals.
        let keyRect = NSRect(x: min(size.width, max(room, 0)) + 6, y: baseline + font.capHeight / 2 - key.height / 2, width: key.width,
                             height: key.height)
        let cap = NSBezierPath(roundedRect: keyRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        NSColor.tertiaryLabelColor.setStroke()
        cap.lineWidth = 1
        cap.stroke()
        let label = NSAttributedString(string: "Tab", attributes: keyAttributes)
        let labelSize = label.size()
        label.draw(at: NSPoint(x: keyRect.midX - labelSize.width / 2, y: keyRect.midY - labelSize.height / 2))
    }
}

// MARK: - The switch

/// Autocomplete's switch (`Config.autocomplete`), for the input menu, the menu bar panel and the self-test: written to the
/// config file and counted (`Autocomplete.Metrics.switched`). Nothing asks first: it asks the AI provider picked in
/// Settings, or the on-device model (`Autocomplete.route`), and the switch says which and where the text goes
/// (`modelName`, `destination`); with a CLI chosen as the AI, its fast fallback's, or with none, that it can't run, as
/// Settings → Common says it (`shown`).
@MainActor
enum AutocompleteSwitch {
    /// What autocomplete learns and counts, for every field: this input method's own defaults (the self-test has its own,
    /// in memory).
    static var store = AutocompleteStore(defaults: UserDefaultsStore())

    /// Whether it's on for every app now.
    static var isOn: Bool { LiveConfig.current.autocomplete }

    /// Turns it on or off for every app, and says so in `field` (the one being typed in). False: nothing changed (the
    /// config file can't be written).
    @discardableResult
    static func set(_ on: Bool, notify field: AllInOneIMEInputController?) -> Bool {
        do {
            let saved = try Config.change { $0.autocomplete = on }
            // Counted here, before a session sees the file (`AutocompleteStore.saw`), which then counts nothing more.
            store.switched(on: on)
            NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
            let config = fastConfig(saved) ?? saved  // what it asks: with a CLI chosen, its fast fallback
            log.notice("autocomplete \(on ? "on" : "off", privacy: .public) (\(String(describing: Autocomplete.route(config)), privacy: .public))")
            field?.applySettings()
            field?.showNotice(on ? onNotice(config) : tr("续写 已关闭", "Autocomplete off"), client: nil, long: on && !modelReady(config))
            return true
        } catch {
            log.error("could not turn autocomplete \(on ? "on" : "off", privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    // MARK: Whether it can run

    /// The switch as the input menu and the menu bar panel show it, as Settings → Common does (`Config.fastConfig`): on or
    /// off, and the model it asks and where the text goes; with a CLI chosen as the AI and no faster AI, off, not to be
    /// turned on (the setting kept, for when there is one), and why.
    struct Shown: Equatable {
        var on: Bool
        /// The model it asks (`modelName`); nil: it can't run.
        var model: String?
        /// Where the text goes (`destination`; nil with Apple Intelligence), or why it can't run (`noFasterAI`).
        var line: String?
        /// The settings it asks with: with a CLI chosen, its fast fallback's (`fastConfig`); nil: it can't run.
        var fast: Config?
        var available: Bool { fast != nil }
    }

    static func shown(_ config: Config) -> Shown {
        guard let fast = fastConfig(config) else { return Shown(on: false, model: nil, line: noFasterAI, fast: nil) }
        return Shown(on: config.autocomplete, model: modelName(fast), line: destination(fast), fast: fast)
    }

    /// Why it can't run, in the words Settings → Common has under the switch.
    static var noFasterAI: String {
        tr("选了 CLI、又没有更快的 AI 时，续写不会运行（设置 →「AI」）", "With a CLI chosen and no faster AI, autocomplete doesn't run (Settings → AI)")
    }

    /// The settings it asks with (`Config.fastConfig`): `config` with a provider chosen; with a CLI, its fast fallback's as
    /// a request finds it (`Converter.fastConfig`: the keychain, the shell's variables, the AWS profile's files), looked
    /// up off the main thread each time the switch is shown (`lookUp`) and at launch: what the last look found until the
    /// next comes back (none before the first); with another fast fallback chosen since that look, that one at once
    /// (where the requests go from now on; the look on its way says so if it can't answer). Nil: it can't run.
    static func fastConfig(_ config: Config) -> Config? {
        guard case .cli = config.ai else { return config }
        lookUp(config)
        guard let found, let provider = found.config.provider == config.provider ? found.provider : config.provider else { return nil }
        var fast = config
        fast.provider = provider
        return fast
    }

    /// What the last look found: the settings it was for, the fast fallback's provider with them (nil: none), and when it
    /// came back (system uptime). Nil: not looked up yet.
    private static var found: (config: Config, provider: Provider?, at: TimeInterval)?
    /// The settings the look started last is for, until it comes back: Notes asks for the input menu after every key, and
    /// a look for the same settings isn't made again while one runs, nor within a few seconds of the last.
    private static var looking: Config?
    /// Told when a look found another answer than the last, and when one for settings changed since came back (its
    /// answer not kept): the menu bar panel shows the switch again, as the settings are now.
    static var foundAnother: @MainActor () -> Void = { FloatingPanel.shared.setAutocomplete(nil) }

    /// `fastConfig`'s look with `config` (a CLI chosen), off the main thread; nothing while one runs for it, or within a
    /// few seconds of the last for it. With autocomplete off no key is read (`Converter.fastConfig(_:readingKeys:)`):
    /// the switch shows whether it could run from the keychain items' attributes, and nothing asks for the login
    /// password at launch or as the input menu opens. Only the answer for the settings asked about last is kept: an
    /// earlier look that comes back later (its keychain item slow to answer) never replaces it.
    static func lookUp(_ config: Config) {
        let now = ProcessInfo.processInfo.systemUptime
        guard case .cli = config.ai, looking != config else { return }
        if let found, found.config == config, now - found.at < 5 { return }
        looking = config
        Task.detached(priority: .userInitiated) {
            let provider = sharedConverter.fastConfig(config, readingKeys: config.autocomplete)?.provider
            await MainActor.run {
                guard looking == config else { return foundAnother() }
                looking = nil
                let another = found.map { $0.provider != provider || $0.config.provider != config.provider } ?? true
                found = (config, provider, ProcessInfo.processInfo.systemUptime)
                if another { foundAnother() }
            }
        }
    }

    /// The model it uses with `config` (`Autocomplete.Words.model`), for the input menu and the menu bar panel: the
    /// provider and its model, or Apple Intelligence on this Mac (and that it isn't available, where it isn't: asked only
    /// then, and at most every few seconds, `recentAvailability`). Notes asks for the input menu after every key.
    static func modelName(_ config: Config) -> String {
        Autocomplete.Words(language: UIText.language).model(config, onDeviceAvailable: recentAvailability.availability(
            now: ProcessInfo.processInfo.systemUptime, ask: { AppleModel.system.availability }) == .available)
    }

    /// The on-device model's availability as the input menu last asked it.
    static var recentAvailability = RecentAvailability()

    /// Where the text goes with `config` (`Autocomplete.Words.destination`): to the provider, what each pause sends; with
    /// AllInOneIME Cloud picked, that it uses Apple Intelligence. Nil with Apple Intelligence picked.
    static func destination(_ config: Config) -> String? {
        Autocomplete.Words(language: UIText.language).destination(config)
    }

    /// `shown`'s line as a menu's, under the switch: where the text goes, or why it can't run; not choosable, indented;
    /// with AllInOneIME Cloud picked, its tooltip says why it isn't asked. Nil where there is no line.
    static func lineItem(_ shown: Shown) -> NSMenuItem? {
        guard let text = shown.line else { return nil }
        let line = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        line.isEnabled = false
        line.indentationLevel = 1
        if shown.fast?.provider == .hosted {
            line.toolTip = UIText.triggered(tr("AllInOneIME 云每天的免费次数，停顿几分钟就会用完，当天的 @ 命令就用不了了",
                                               "A few minutes of pauses would use up AllInOneIME Cloud's free requests for the day, and your @ commands would fail"))
        }
        return line
    }

    /// Whether the model it would ask can answer: a cloud provider (whether it does is seen at the first pause), or the
    /// on-device model available.
    static func modelReady(_ config: Config) -> Bool {
        Autocomplete.route(config) != .onDevice || AppleModel.system.availability == .available
    }

    /// 「续写 已开启：停一下，灰字出现后按 Tab」, with the model (and, with AllInOneIME Cloud picked, what is faster); or why
    /// nothing will show.
    static func onNotice(_ config: Config) -> String {
        if Autocomplete.route(config) == .onDevice {
            let availability = AppleModel.system.availability
            guard availability == .available else {
                return tr("续写 已开启，但本机的 Apple Intelligence 不可用，不会出灰字：", "Autocomplete on, but Apple Intelligence on this Mac isn't available, so nothing shows: ")
                    + UIText.describe(AppleModelError.unavailable(availability))
            }
            if config.provider == .hosted, let destination = destination(config) {
                return tr("续写 已开启：", "Autocomplete on: ") + destination
            }
        }
        let model = modelName(config)
        return tr("续写 已开启（\(model)）：停一下，灰字出现后按 Tab 接受", "Autocomplete on (\(model)): pause, and Tab takes the gray text")
    }
}

// MARK: - In the field

extension AllInOneIMEInputController {
    /// The suggestion up (`SessionOutput.ghost`), or none. Placed a moment later: the key that brought it (typed along)
    /// reaches the app after this, and moves the caret.
    @MainActor
    func showGhost(_ text: String?, in client: IMKTextInput?) {
        ghostToken += 1
        guard let text, let client else {
            hideGhost()
            return
        }
        let token = ghostToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self, token == self.ghostToken else { return }
            self.placeGhost(text, in: client)
        }
    }

    /// At the caret, where the field tells it (`ghostPlace`; cut at the field's edge, its frame asked once a suggestion:
    /// as it's typed along, the field stays where it is); else as a line of the candidate panel.
    @MainActor
    func placeGhost(_ text: String, in client: IMKTextInput) {
        let rects = Self.caretRects(client)
        let place = Self.ghostPlace(rects)
        // What the field told, to check a real app by (`log stream --level debug --predicate 'subsystem ==
        // "com.allinoneime.inputmethod.AllInOneIME" AND eventMessage BEGINSWITH "autocomplete placed"'`): numbers only.
        log.debug("""
            autocomplete placed \(place == nil ? "in the panel" : "after the caret", privacy: .public) in \(client.bundleIdentifier() ?? "", privacy: .private): \
            caret \(Self.describe(rects.caret), privacy: .public), previous character \(Self.describe(rects.previous), privacy: .public), \
            line \(Self.describe(rects.line), privacy: .public), font \(Double(rects.font?.pointSize ?? 0), format: .fixed(precision: 1), privacy: .public) pt
            """)
        if let place {
            if ghostInPanel { hidePanelLine() }
            if ghostField == nil { askGhostField(client) }
            GhostOverlay.shared.owner = self
            if !GhostOverlay.shared.show(text, at: place, field: ghostField ?? nil) {
                // Too close to the field's edge for its text: not shown at all, and Tab isn't its.
                received(.ghostNotShown(text))
            }
            return
        }
        GhostOverlay.shared.hide()
        // The wheel over the line is this field's: no pointer use in it, so Tab and Esc stay the line's (GitHub #66).
        let panel = CandidatePanel.shared
        panel.take(by: self, .session({ [weak self] in self?.received($0) }))
        if show(.autocomplete(text, language: UIText.language), anchoredIn: client) { ghostInPanel = true }  // superseded: as the newer one left it
    }

    /// The field's frame the suggestion is cut at (`ghostField`), asked once a suggestion: the self-test's at once
    /// (`fieldFrame`: its harness field isn't the one focused); Accessibility's off the main thread (an app slow to answer
    /// would hold typing up), not known meanwhile, the suggestion still shown placed again by it once it is in. Only the
    /// last one asked is gone by (`ghostFieldAsked`): an answer for a suggestion taken down since, or another field's, isn't.
    @MainActor
    func askGhostField(_ client: IMKTextInput) {
        ghostFieldAsked += 1
        if let fieldFrame { return ghostField = .some(fieldFrame()) }
        ghostField = .some(nil)
        let asked = ghostFieldAsked
        let (box, held, top, read) = (WeakBox(self), MainThreadBox(client), FocusedField.screenTop, Self.focusedFieldReaders.frame)
        DispatchQueue.global(qos: .userInitiated).async {
            let frame = read(top)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // Asked again since, hidden since (`hideGhost` forgets it), or another's now: nothing to place.
                    guard let self = box.value, self.ghostFieldAsked == asked, self.ghostField == .some(nil),
                          GhostOverlay.shared.owner === self, let text = GhostOverlay.shared.text else { return }
                    self.ghostField = .some(frame)
                    if frame != nil { self.placeGhost(text, in: held.value) }
                }
            }
        }
    }

    @MainActor
    func hideGhost() {
        ghostField = nil
        if GhostOverlay.shared.owner === self || GhostOverlay.shared.owner == nil { GhostOverlay.shared.hide() }
        if ghostInPanel { hidePanelLine() }
    }

    @MainActor
    private func hidePanelLine() {
        ghostInPanel = false
        let panel = CandidatePanel.shared
        if panel.owner === self, !composer.wantsPanel { panel.hide() }
    }

    /// What autocomplete and the password-field check ask Accessibility of the focused element (`FocusedField`): this
    /// Mac's, or a test's.
    @MainActor static var focusedFieldReaders = FocusedFieldReaders()

    /// Whether Accessibility tells the focused element is a password field (`FocusedField.isSecure`, the self-test's
    /// `passwordField` for its harness field; nil: it can't tell, which the session counts as unknown, never as none),
    /// asked off the main thread, once the key that asks it is answered
    /// (`SessionOutput.readPasswordField`: Accessibility may wait a quarter of a second for each of its two calls, more
    /// than a key may), and handed back for the focus it was asked in (`SessionEvent.passwordField`).
    @MainActor
    func readPasswordField(focus: Int) {
        let box = WeakBox(self)
        let told: @Sendable (Bool?) -> Void = { answer in
            DispatchQueue.main.async { MainActor.assumeIsolated { box.value?.received(.passwordField(answer, focus: focus)) } }
        }
        if let harness = passwordField { return told(harness()) }
        let read = Self.focusedFieldReaders.isSecure
        DispatchQueue.global(qos: .userInitiated).async { told(read()) }
    }

    /// Where the caret is on the screen (as tall as its line), as the field tells it for an empty range there: nil
    /// where it tells none (no caret, an empty rect, off every screen).
    static func caretRect(_ client: IMKTextInput) -> NSRect? {
        caretRect(client, selected: client.selectedRange())
    }

    /// `caretRect` for `selected`, the selection `client` told.
    private static func caretRect(_ client: IMKTextInput, selected: NSRange) -> NSRect? {
        guard selected.location != NSNotFound else { return nil }
        return onScreen(client.firstRect(forCharacterRange: NSRange(location: selected.location, length: 0), actualRange: nil))
    }

    /// What a field tells of its caret's place on the screen, three ways: the empty range at the caret (`caret`), the
    /// character before it (`previous`), and the line as the candidate panel has it (`line`,
    /// `attributes(forCharacterIndex:lineHeightRectangle:)`), with the font there. Nil for a rect it doesn't tell.
    struct CaretRects {
        var caret: NSRect?
        var previous: NSRect?
        var line: NSRect?
        var font: NSFont?
    }

    static func caretRects(_ client: IMKTextInput) -> CaretRects {
        // The selection asked once, for the caret and the character before it.
        let selected = client.selectedRange()
        var rects = CaretRects(caret: caretRect(client, selected: selected))
        if selected.location != NSNotFound, selected.location > 0 {
            rects.previous = onScreen(client.firstRect(forCharacterRange: NSRange(location: selected.location - 1, length: 1), actualRange: nil))
        }
        var line = NSRect.zero
        let attributes = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &line) ?? [:]
        rects.line = onScreen(line)
        rects.font = (attributes[NSAttributedString.Key.font] ?? attributes[NSAttributedString.Key.font.rawValue]) as? NSFont
        return rects
    }

    /// Where the suggestion goes: on the line the candidate panel goes by, at the caret (`GhostPlacement.line`); nil, the
    /// candidate panel's line instead.
    static func ghostPlace(_ rects: CaretRects) -> GhostOverlay.Place? {
        GhostPlacement.line(rects.line, caret: rects.caret, previous: rects.previous).map {
            GhostOverlay.Place(line: $0.line, x: $0.x, font: rects.font)
        }
    }

    /// `rect` if it is one: not empty, not at the origin, on a screen.
    static func onScreen(_ rect: NSRect) -> NSRect? {
        guard rect.height > 1, rect.origin != .zero,
              NSScreen.screens.contains(where: { $0.frame.intersects(rect.insetBy(dx: -2, dy: -2)) }) else { return nil }
        return rect
    }

    /// A rect for the log: "x 120.0 y 540.5 w 0.0 h 18.0", or "none".
    static func describe(_ rect: NSRect?) -> String {
        rect.map { String(format: "x %.1f y %.1f w %.1f h %.1f", $0.minX, $0.minY, $0.width, $0.height) } ?? "none"
    }

    /// What the field says once a pause in typing is over (`SessionOutput.readField`): autocomplete's, or Code's
    /// for the field's words (`id` below 0, more after the caret): secure input, a password field as Accessibility tells
    /// it where secure input isn't on (`FocusedField.isSecure`: the field marked secure), the selection, the text around
    /// the caret (nothing of it during secure input or in a password field). Whether it is a password field is asked of
    /// Accessibility first, off the main thread (each of its two calls may wait a quarter of a second on an app slow to
    /// answer; the self-test's harness field, which isn't the one focused, is told by the self-test: `passwordField`);
    /// the rest is read on the main thread once that is answered, never before this event is done, and handed back.
    @MainActor
    func readFieldAfterPause(id: Int, in client: IMKTextInput?) {
        let (box, held) = (WeakBox(self), MainThreadBox(client))
        let read: @Sendable (Bool?) -> Void = { told in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self = box.value else { return }
                    let target = held.value ?? self.clientOverride ?? self.client()
                    // Secure input, the password field as told (for suggestions too: both go by the same answer), the
                    // selection and the text around the caret (`FieldReading.contextAfterPause`).
                    var reading = self.fieldReading
                    reading.passwordField = { told }
                    self.received(.field(reading.contextAfterPause(in: target, id: id), id: id))
                }
            }
        }
        if let harness = passwordField { return read(harness()) }
        // Secure input on: nothing of the field is read, nor asked of Accessibility.
        if services.secureInputActive() { return read(nil) }
        let isSecure = Self.focusedFieldReaders.isSecure
        DispatchQueue.global(qos: .userInitiated).async { read(isSecure()) }
    }
}

/// What the input method asks Accessibility of the focused element (`FocusedField`), off the main thread where it may
/// wait on an app: this Mac's, or a test's.
struct FocusedFieldReaders {
    /// Whether it is a password field (`FocusedField.isSecure`; nil: it can't tell).
    var isSecure: @Sendable () -> Bool? = { FocusedField.isSecure() }
    /// Its frame, given the main screen's top (`FocusedField.frame`).
    var frame: @Sendable (CGFloat) -> NSRect? = { FocusedField.frame(top: $0) }
}

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
        orderFrontRegardless()
        watchPointer()
        return true
    }

    func hide() {
        guard isVisible || monitor != nil else { return }
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

    /// A line of `font`, as AppKit lays it out: how tall, and how far its baseline is from its top.
    static func lineHeight(_ font: NSFont) -> CGFloat { NSLayoutManager().defaultLineHeight(for: font) }
    static func baselineOffset(_ font: NSFont) -> CGFloat { NSLayoutManager().defaultBaselineOffset(for: font) }

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
/// (`modelName`, `destination`).
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
            var config = try Config.load()
            config.autocomplete = on
            try config.write()
            // Counted here, before a session sees the file (`AutocompleteStore.saw`), which then counts nothing more.
            store.switched(on: on)
            NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
            log.notice("autocomplete \(on ? "on" : "off", privacy: .public) (\(String(describing: Autocomplete.route(config)), privacy: .public))")
            field?.applySettings()
            field?.showNotice(on ? onNotice(config) : tr("续写 已关闭", "Autocomplete off"), client: nil, long: on && !modelReady(config))
            return true
        } catch {
            log.error("could not turn autocomplete \(on ? "on" : "off", privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// The model it uses with `config` (`Autocomplete.Words.model`), for the input menu and the menu bar panel: the
    /// provider and its model, or Apple Intelligence on this Mac (and that it isn't available, where it isn't).
    static func modelName(_ config: Config) -> String {
        Autocomplete.Words(language: UIText.language).model(config, onDeviceAvailable: AppleModel.system.availability == .available)
    }

    /// Where the text goes with `config` (`Autocomplete.Words.destination`): to the provider, what each pause sends; with
    /// AllInOneIME Cloud picked, that it uses Apple Intelligence. Nil with Apple Intelligence picked.
    static func destination(_ config: Config) -> String? {
        Autocomplete.Words(language: UIText.language).destination(config)
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
        // "com.aipinyin.inputmethod.AIPinyin" AND eventMessage BEGINSWITH "autocomplete placed"'`): numbers only.
        log.debug("""
            autocomplete placed \(place == nil ? "in the panel" : "after the caret", privacy: .public) in \(client.bundleIdentifier() ?? "", privacy: .private): \
            caret \(Self.describe(rects.caret), privacy: .public), previous character \(Self.describe(rects.previous), privacy: .public), \
            line \(Self.describe(rects.line), privacy: .public), font \(Double(rects.font?.pointSize ?? 0), format: .fixed(precision: 1), privacy: .public) pt
            """)
        if let place {
            if ghostInPanel { hidePanelLine() }
            if ghostField == nil { ghostField = .some(fieldFrame?() ?? FocusedField.frame()) }
            GhostOverlay.shared.owner = self
            if !GhostOverlay.shared.show(text, at: place, field: ghostField ?? nil) {
                // Too close to the field's edge for its text: not shown at all, and Tab isn't its.
                received(.ghostNotShown(text))
            }
            return
        }
        GhostOverlay.shared.hide()
        let panel = CandidatePanel.shared
        panel.owner = self
        panel.onSelect = nil
        panel.show(.autocomplete(text, language: UIText.language), anchor: anchor(client))
        ghostInPanel = true
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

    /// Whether Accessibility tells the focused element is a password field (`FocusedField.isSecure`; the self-test's
    /// harness field, which isn't the one focused, is told by the self-test).
    @MainActor
    func passwordFieldByAccessibility() -> Bool {
        passwordField?() ?? (FocusedField.isSecure() == true)
    }

    /// Where the caret is on the screen (as tall as its line), as the field tells it for an empty range there: nil
    /// where it tells none (no caret, an empty rect, off every screen).
    static func caretRect(_ client: IMKTextInput) -> NSRect? {
        let selected = client.selectedRange()
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
        var rects = CaretRects(caret: caretRect(client))
        let selected = client.selectedRange()
        if selected.location != NSNotFound, selected.location > 0 {
            rects.previous = onScreen(client.firstRect(forCharacterRange: NSRange(location: selected.location - 1, length: 1), actualRange: nil))
        }
        var line = NSRect.zero
        let attributes = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &line) ?? [:]
        rects.line = onScreen(line)
        rects.font = (attributes[NSAttributedString.Key.font] ?? attributes[NSAttributedString.Key.font.rawValue]) as? NSFont
        return rects
    }

    /// Where the suggestion goes: on the line the candidate panel goes by (the empty range's rect where the field tells
    /// no line), at the caret's x, from the empty range's rect where that is on the line, else from the end of the
    /// character before the caret. Nil, the candidate panel's line instead: no line told; the empty range's rect more
    /// than a line from it (one of them is wrong: Notes's has been above the line); no x on the line.
    static func ghostPlace(_ rects: CaretRects) -> GhostOverlay.Place? {
        guard let line = rects.line ?? rects.caret else { return nil }
        func apart(_ rect: NSRect) -> CGFloat { abs(rect.midY - line.midY) }
        if let caret = rects.caret, apart(caret) > line.height { return nil }
        let x: CGFloat
        if let caret = rects.caret, apart(caret) <= line.height / 2 {
            x = caret.maxX
        } else if let previous = rects.previous, apart(previous) <= line.height / 2 {
            x = previous.maxX
        } else if rects.caret == nil {
            x = line.minX
        } else {
            return nil
        }
        return GhostOverlay.Place(line: line, x: x, font: rects.font)
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
    /// the caret (nothing of it during secure input or in a password field). Read once this event is done, and handed
    /// back.
    @MainActor
    func readFieldAfterPause(id: Int, in client: IMKTextInput?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let target = client ?? self.clientOverride ?? self.client()
            var context = FieldContext(read: [.secure], field: Self.fieldInfo(target))
            context.secure = SecureInput.blocksComposing(target) || self.services.secureInputActive()
            if !context.secure {
                // Told for suggestions too (`FieldContext.Parts.passwordField`): both go by the same answer.
                context.field?.secure = self.passwordFieldByAccessibility()
                context.read.insert(.passwordField)
            }
            if !context.secure, context.field?.secure != true {
                context.selectedRange = target.flatMap { Self.range($0.selectedRange()) }
                context.text = id < 0
                    ? self.readFieldText(from: target, before: ReplyContext.Limits.fieldBefore, after: ReplyContext.Limits.fieldAfter,
                                         purpose: "Code's words")
                    : self.readFieldText(from: target, before: Autocomplete.beforeLimit, after: Autocomplete.afterLimit,
                                         purpose: "autocomplete")
                context.read.formUnion([.selectedRange, .text])
            }
            self.received(.field(context, id: id))
        }
    }
}

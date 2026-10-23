import AllInOneIMECore
import AppKit
import InputMethodKit

/// Autocomplete's suggestion (`SessionOutput.ghost`, the core's `Autocomplete`) after the caret: gray text in a window of
/// its own, on the caret's line, in the field's font where it tells it, on its text's baseline, a small Tab key after it.
/// It takes no clicks; a click or the wheel anywhere takes it down (the session sees the pointer used,
/// `SessionServices.pointerUsedWithin`, and ends the suggestion at the next key). Where the field tells no caret rect, or
/// rects that don't agree, the suggestion is a line of the candidate panel instead (`PanelModel.autocomplete`).
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

    /// `text` right after the caret at `place`, its baseline on the line's text's, cut at the screen's edge.
    func show(_ text: String, at place: Place) {
        ghost.text = text
        ghost.font = Self.font(place.font, lineHeight: place.line.height)
        let size = ghost.fittingSize
        let line = place.line
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: place.x, y: line.midY)) } ?? NSScreen.main
        let right = screen?.visibleFrame.maxX ?? place.x + size.width
        let x = place.x + 1
        let width = max(min(size.width, right - x), 24)
        // The text's baseline is the line's bottom and the font's descent: AppKit puts what makes a line taller than its
        // font (a line height multiple, a minimum) above the text, and a line's spacing below its rect.
        let baseline = line.minY + ghost.descent
        let height = max(line.height, baseline - line.minY + ghost.ascent)
        setFrame(NSRect(x: x, y: line.minY, width: width, height: height), display: true)
        ghost.baseline = baseline - line.minY
        ghost.needsDisplay = true
        alphaValue = Self.invisible ? 0 : 1
        orderFrontRegardless()
        watchPointer()
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

    override var fittingSize: NSSize {
        let size = (text as NSString).size(withAttributes: attributes)
        return NSSize(width: ceil(size.width) + 6 + keySize.width + 2, height: ceil(max(size.height, keySize.height)))
    }

    override func draw(_ dirtyRect: NSRect) {
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let key = keySize
        let room = bounds.width - key.width - 8
        // Cut where it doesn't fit (the screen's edge), with an ellipsis; one line of the font, its baseline on `baseline`.
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
/// config file, counted (`Autocomplete.Metrics.switched`), and, turned on with a cloud provider picked for the first
/// time, after asking whether it may send text there (`Config.autocompleteCloud`).
@MainActor
enum AutocompleteSwitch {
    /// What autocomplete learns and counts, for every field: this input method's own defaults (the self-test has its own,
    /// in memory).
    static var store = AutocompleteStore(defaults: UserDefaultsStore())
    /// Asks whether autocomplete may send the text before the caret to `provider`: true yes, false only the on-device
    /// model, nil cancelled (the self-test answers itself, no dialog).
    static var askCloud: (_ provider: Provider, _ onDevice: Bool) -> Bool? = { cloudAlert($0, onDevice: $1) }

    /// Whether it's on for every app now.
    static var isOn: Bool { LiveConfig.current.autocomplete }

    /// Turns it on or off for every app; on, with a cloud provider the user wasn't asked about, asks first. Says so in
    /// `field` (the one being typed in). False: nothing changed (cancelled, or the config file can't be written).
    @discardableResult
    static func set(_ on: Bool, notify field: AllInOneIMEInputController?) -> Bool {
        do {
            var config = try Config.load()
            if on, Autocomplete.asksForCloud(config) {
                guard let yes = askCloud(config.provider, AppleModel.system.availability == .available) else { return false }
                config.autocompleteCloud = yes
            }
            config.autocomplete = on
            try config.write()
            NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
            store.switched(on: on)
            log.notice("autocomplete \(on ? "on" : "off", privacy: .public) (\(String(describing: Autocomplete.route(config)), privacy: .public))")
            field?.applySettings()
            field?.showNotice(on ? onNotice(config) : tr("续写 已关闭", "Autocomplete off"), client: nil, long: on && !modelReady(config))
            return true
        } catch {
            log.error("could not turn autocomplete \(on ? "on" : "off", privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// The yes to the cloud provider given or taken back (the input menu's "Autocomplete with …"); given, it asks first.
    static func setCloud(_ yes: Bool) {
        do {
            var config = try Config.load()
            if yes {
                guard askCloud(config.provider, AppleModel.system.availability == .available) == true else { return }
            }
            config.autocompleteCloud = yes
            try config.write()
            NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
            log.notice("autocomplete with the cloud provider: \(yes ? "yes" : "no", privacy: .public)")
        } catch {
            log.error("could not change autocomplete's model: \(String(describing: error), privacy: .public)")
        }
    }

    /// Whether the model it would ask can answer: a cloud provider agreed to, or the on-device model available.
    static func modelReady(_ config: Config) -> Bool {
        Autocomplete.route(config) != .onDevice || AppleModel.system.availability == .available
    }

    /// 「续写 已开启：停一下，灰字出现后按 Tab」, with the model; or why nothing will show.
    static func onNotice(_ config: Config) -> String {
        let model: String
        switch Autocomplete.route(config) {
        case let .cloud(provider): model = provider.displayName
        case .onDevice:
            let availability = AppleModel.system.availability
            guard availability == .available else {
                return tr("续写 已开启，但本机的 Apple Intelligence 不可用，不会出灰字：", "Autocomplete on, but Apple Intelligence on this Mac isn't available, so nothing shows: ")
                    + UIText.describe(AppleModelError.unavailable(availability))
            }
            model = tr("本机 Apple Intelligence", "Apple Intelligence on this Mac")
        }
        return tr("续写 已开启（\(model)）：停一下，灰字出现后按 Tab 接受", "Autocomplete on (\(model)): pause, and Tab takes the gray text")
    }

    /// The question, as a dialog of the input method's own.
    static func cloudAlert(_ provider: Provider, onDevice: Bool) -> Bool? {
        let name = provider.displayName
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = tr("续写用 \(name) 吗？", "Use \(name) for Autocomplete?")
        let otherwise = onDevice ? tr("不用的话，只用这台 Mac 上的 Apple Intelligence。", "Otherwise it uses only Apple Intelligence on this Mac.")
            : tr("不用的话只用这台 Mac 上的 Apple Intelligence，但它现在不可用，不会出灰字。",
                 "Otherwise it uses only Apple Intelligence on this Mac, which isn't available now: no suggestions.")
        alert.informativeText = tr("每次停顿会把光标前最多 1,500 字（和光标后最多 200 字）发给 \(name)，照常隐藏敏感信息。",
                                   "Each pause sends up to 1,500 characters before the caret (and up to 200 after it) to \(name), with sensitive information hidden as usual. ")
            + otherwise
        alert.addButton(withTitle: tr("用 \(name)", "Use \(name)"))
        alert.addButton(withTitle: tr("只用本机", "On This Mac Only"))
        alert.addButton(withTitle: tr("取消", "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: return false
        default: return nil
        }
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

    /// At the caret, where the field tells it (`ghostPlace`); else as a line of the candidate panel.
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
            GhostOverlay.shared.owner = self
            GhostOverlay.shared.show(text, at: place)
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
        if GhostOverlay.shared.owner === self || GhostOverlay.shared.owner == nil { GhostOverlay.shared.hide() }
        if ghostInPanel { hidePanelLine() }
    }

    @MainActor
    private func hidePanelLine() {
        ghostInPanel = false
        let panel = CandidatePanel.shared
        if panel.owner === self, !composer.wantsPanel { panel.hide() }
    }

    /// Where the caret is on the screen (as tall as its line), as the field tells it for an empty range there: nil where
    /// it tells none (no caret, an empty rect, off every screen).
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

    /// What the field says once autocomplete's pause is over (`SessionOutput.readField`): secure input, the selection,
    /// the text around the caret (nothing of it during secure input). Read once this event is done, and handed back.
    @MainActor
    func readFieldForAutocomplete(id: Int, in client: IMKTextInput?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let target = client ?? self.clientOverride ?? self.client()
            var context = FieldContext(read: [.secure], field: Self.fieldInfo(target))
            context.secure = SecureInput.blocksComposing(target) || self.services.secureInputActive()
            if !context.secure {
                context.selectedRange = target.flatMap { Self.range($0.selectedRange()) }
                context.text = self.readFieldText(from: target, before: Autocomplete.beforeLimit, after: Autocomplete.afterLimit,
                                                  purpose: "autocomplete")
                context.read.formUnion([.selectedRange, .text])
            }
            self.received(.field(context, id: id))
        }
    }
}

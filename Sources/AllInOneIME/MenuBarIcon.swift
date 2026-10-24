import AllInOneIMECore
import AppKit

/// The menu bar icon (config `menuBarIcon`, on by default): a click drops the panel down under it
/// (`FloatingPanel.toggleDropDown`), with the notes, reminders and Claude tasks; a click elsewhere
/// closes it. While Translate as You Type is on (`setTranslating`) it carries a small dot; while the field being typed in
/// is in Code (`setCode`), Code's own mark, "{}".
@MainActor
final class MenuBarIcon {
    static let shared = MenuBarIcon()

    private var item: NSStatusItem?
    /// Translate as You Type is on: the icon carries its badge (kept while the icon is off, for when it's shown).
    private(set) var translating = false
    /// The field being typed in is in Code, named so ("Code (Python)"): the icon shows it (`{}` in its corner), the tooltip
    /// says so. Nil: another input.
    private(set) var code: String?

    /// Shows or removes the icon at once (launch, the settings window).
    func apply(_ on: Bool) {
        if on, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                button.target = self
                button.action = #selector(clicked(_:))
            }
            self.item = item
            update()
            log.notice("menu bar icon shown")
        } else if !on, let item {
            FloatingPanel.shared.closeDropDown()
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
            log.notice("menu bar icon removed")
        }
    }

    /// Translate as You Type turned on or off: the badge comes or goes. Nothing to show with the icon off.
    func setTranslating(_ on: Bool) {
        guard on != translating else { return }
        translating = on
        update()
    }

    /// The input of the field being typed in became Code (`name`, "Code (Python)") or left it (nil): the icon shows it.
    /// Nothing to show with the icon off.
    func setCode(_ name: String?) {
        guard name != code else { return }
        code = name
        update()
    }

    private func update() {
        guard let button = item?.button else { return }
        // The app's ∞-and-cursor mark, not boxed (the input source's icon is), as a template image.
        let mark = Bundle.main.image(forResource: "panel-icon")
            ?? NSImage(systemSymbolName: "infinity", accessibilityDescription: nil)
        let image = code != nil ? mark.map(Self.coded) : translating ? mark.map(Self.badged) : mark
        image?.isTemplate = true
        image?.accessibilityDescription = code.map { "AllInOneIME: " + $0 }
            ?? (translating ? tr("AllInOneIME：边打边译 已开启", "AllInOneIME: Translate as You Type on") : "AllInOneIME")
        button.image = image
        button.toolTip = tr("AllInOneIME：笔记、提醒、Claude 任务", "AllInOneIME: notes, reminders, Claude tasks")
            + (translating ? tr(" · 边打边译 已开启", " · Translate as You Type on") : "")
            + (code.map { " · " + $0 } ?? "")
    }

    /// `mark` with "{}" in its lower right corner, the mark cut away around it: Code's mark.
    private static func coded(_ mark: NSImage) -> NSImage {
        NSImage(size: mark.size, flipped: false) { rect in
            mark.draw(in: rect)
            let side = rect.width * 0.55
            let corner = NSRect(x: rect.maxX - side, y: rect.minY, width: side, height: side * 0.8)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(roundedRect: corner.insetBy(dx: -1, dy: -1), xRadius: 2, yRadius: 2).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let font = NSFont.monospacedSystemFont(ofSize: corner.height * 0.95, weight: .heavy)
            let text = NSAttributedString(string: "{}", attributes: [.font: font, .foregroundColor: NSColor.black])
            let size = text.size()
            text.draw(at: NSPoint(x: corner.midX - size.width / 2, y: corner.midY - size.height / 2))
            return true
        }
    }

    /// `mark` with a dot in its lower right corner, the mark cut away around it.
    private static func badged(_ mark: NSImage) -> NSImage {
        NSImage(size: mark.size, flipped: false) { rect in
            mark.draw(in: rect)
            let side = rect.width * 0.36
            let dot = NSRect(x: rect.maxX - side, y: rect.minY, width: side, height: side)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
    }

    /// Whether `event` is a click on the icon (the panel's outside-click check leaves it to `clicked`).
    func owns(_ event: NSEvent) -> Bool {
        guard let window = item?.button?.window else { return false }
        return event.window === window
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let window = sender.window else { return }
        FloatingPanel.shared.toggleDropDown(below: window.convertToScreen(sender.convert(sender.bounds, to: nil)))
    }
}

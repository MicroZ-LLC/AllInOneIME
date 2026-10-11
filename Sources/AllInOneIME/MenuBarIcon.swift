import AllInOneIMECore
import AppKit

/// The menu bar icon (config `menuBarIcon`, on by default): a click drops the panel down under it
/// (`FloatingPanel.toggleDropDown`), with the notes, reminders and Claude tasks; a click elsewhere
/// closes it.
@MainActor
final class MenuBarIcon {
    static let shared = MenuBarIcon()

    private var item: NSStatusItem?

    /// Shows or removes the icon at once (launch, the settings window).
    func apply(_ on: Bool) {
        if on, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                // The app's ∞-and-cursor mark, not boxed (the input source's icon is), as a template image.
                let image = Bundle.main.image(forResource: "panel-icon")
                    ?? NSImage(systemSymbolName: "infinity", accessibilityDescription: nil)
                image?.isTemplate = true
                image?.accessibilityDescription = "AllInOneIME"
                button.image = image
                button.toolTip = tr("AllInOneIME：笔记、提醒、Claude 任务", "AllInOneIME: notes, reminders, Claude tasks")
                button.target = self
                button.action = #selector(clicked(_:))
            }
            self.item = item
            log.notice("menu bar icon shown")
        } else if !on, let item {
            FloatingPanel.shared.closeDropDown()
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
            log.notice("menu bar icon removed")
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

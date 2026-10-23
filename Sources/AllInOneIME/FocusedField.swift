import AppKit

/// The focused element as Accessibility tells it, where this app may use Accessibility already (never asked for here): a
/// quarter of a second at most per call. Nil where it can't be told: not allowed, nothing focused, no answer in time.
enum FocusedField {
    static func element() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement  // checked just above
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }

    /// Whether it is a password field (`AXSecureTextField`): one whose app doesn't turn secure event input on for it, or
    /// not yet (a web page's, a field of the app's own drawing).
    static func isSecure() -> Bool? {
        guard let element = element() else { return nil }
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success else { return false }
        return subrole as? String == kAXSecureTextFieldSubrole as String
    }

    /// Its frame on the screen, in AppKit's coordinates (Accessibility's start at the main screen's top left, y down).
    static func frame() -> NSRect? {
        guard let element = element() else { return nil }
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent),  // checked
              extent.width > 0, extent.height > 0 else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: origin.x, y: top - origin.y - extent.height, width: extent.width, height: extent.height)
    }
}

import AllInOneIMEMac
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

    // MARK: The caret, for a panel

    /// The frame of `app`'s frontmost window as the window server lists it (no Accessibility: Chrome's can take longer
    /// than a key may wait), in AppKit's coordinates: its first ordinary window (layer 0) from the front. Nil: `app` not
    /// the one in front, no window listed.
    static func listedWindowFrame(in app: String) -> CGRect? {
        guard let pid = PageContextReader.runningPID(app),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for window in windows where (window[kCGWindowOwnerPID as String] as? pid_t) == pid
            && (window[kCGWindowLayer as String] as? Int) == 0 {
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 100, rect.height > 100 else { continue }
            return PanelAnchor.appKit(rect, top: NSScreen.screens.first?.frame.maxY ?? 0)
        }
        return nil
    }

    /// The frame of `app`'s focused window, in AppKit's coordinates (`PanelAnchor.Memory.learnWindow`): two calls, each
    /// waiting `timeout` at most. Nil: Accessibility not allowed (never asked for here), `app` not running, no window told.
    static func windowFrame(in app: String, timeout: Float = 0.05) -> (frame: CGRect?, timedOut: Bool)? {
        guard AXIsProcessTrusted(), let pid = PageContextReader.runningPID(app) else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        var found: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &found)
        guard error == .success, let found, CFGetTypeID(found) == AXUIElementGetTypeID() else {
            return (nil, error == .cannotComplete)
        }
        let window = found as! AXUIElement  // checked just above
        AXUIElementSetMessagingTimeout(window, timeout)
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return (nil, false) }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent),  // checked
              extent.width > 0, extent.height > 0 else { return (nil, false) }
        return (PanelAnchor.appKit(CGRect(origin: origin, size: extent), top: NSScreen.screens.first?.frame.maxY ?? 0), false)
    }

    /// What Accessibility tells of the caret in `app`'s focused element, where its field told the panel no rect to trust
    /// (`PanelAnchor`): its bounds (`AXSelectedTextRange` and `AXBoundsForRange`: the caret, the selection's last
    /// character where there is one), the focused window's frame and, with `page`, the frame of the outermost web area
    /// above it (the page: a walk up to the window). In AppKit's coordinates. Each call waits `timeout` at most and
    /// all of them `budget`: one that gets no answer in time ends the read (`timedOut`). Nil: Accessibility not allowed
    /// (never asked for here), `app` not the one in front, nothing focused, a password field. Never during secure input
    /// (the caller's to check).
    static func caret(in app: String, page: Bool, timeout: Float = 0.05, budget: TimeInterval = 0.1) -> PanelAnchor.Accessibility? {
        guard AXIsProcessTrusted(), let pid = PageContextReader.runningPID(app) else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        var read = PanelAnchor.Accessibility()
        // Every element asked waits `timeout` at most (set on each: the system-wide element's would be every call's).
        func value(_ element: AXUIElement, _ name: String, _ parameter: CFTypeRef? = nil) -> CFTypeRef? {
            guard !read.timedOut else { return nil }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                read.timedOut = true
                return nil
            }
            AXUIElementSetMessagingTimeout(element, timeout)
            var value: CFTypeRef?
            let error = parameter.map { AXUIElementCopyParameterizedAttributeValue(element, name as CFString, $0, &value) }
                ?? AXUIElementCopyAttributeValue(element, name as CFString, &value)
            if error == .cannotComplete { read.timedOut = true }
            return error == .success ? value : nil
        }
        func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
            guard let found = value(element, name), CFGetTypeID(found) == AXUIElementGetTypeID() else { return nil }
            return (found as! AXUIElement)  // checked just above
        }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        func rect(_ found: CFTypeRef?) -> CGRect? {
            guard let found, CFGetTypeID(found) == AXValueGetTypeID() else { return nil }
            var told = CGRect.zero
            return AXValueGetValue(found as! AXValue, .cgRect, &told) ? PanelAnchor.appKit(told, top: top) : nil  // checked
        }
        func frame(_ element: AXUIElement) -> CGRect? {
            guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute),
                  CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
            var origin = CGPoint.zero, extent = CGSize.zero
            guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent),  // checked
                  extent.width > 0, extent.height > 0 else { return nil }
            return PanelAnchor.appKit(CGRect(origin: origin, size: extent), top: top)
        }
        func bounds(_ element: AXUIElement, _ location: Int, _ length: Int) -> CGRect? {
            var range = CFRange(location: location, length: length)
            guard location >= 0, let parameter = AXValueCreate(.cfRange, &range) else { return nil }
            return rect(value(element, kAXBoundsForRangeParameterizedAttribute, parameter))
        }

        let application = AXUIElementCreateApplication(pid)
        guard let focused = element(application, kAXFocusedUIElementAttribute) else { return read.timedOut ? read : nil }
        if value(focused, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole as String { return nil }
        if let window = element(focused, kAXWindowAttribute) ?? element(application, kAXFocusedWindowAttribute) {
            read.window = frame(window)
        }
        if let selected = value(focused, kAXSelectedTextRangeAttribute), CFGetTypeID(selected) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(selected as! AXValue, .cfRange, &range) {  // checked just above
                if range.length > 0 {
                    read.caret = bounds(focused, range.location + range.length - 1, 1)
                } else if let caret = bounds(focused, range.location, 0), caret.height > 1 {
                    read.caret = caret
                } else if let previous = bounds(focused, range.location - 1, 1) {
                    // No rect for an empty range: right after the character before.
                    read.caret = CGRect(x: previous.maxX, y: previous.minY, width: 0, height: previous.height)
                }
            }
        }
        if page {
            // The outermost one: an iframe (Google Docs types into one) is a web area of its own, inside the page.
            var current: AXUIElement? = focused
            for _ in 0..<40 {
                guard let node = current else { break }
                let role = value(node, kAXRoleAttribute) as? String
                if role == kAXWindowRole as String { break }
                if role == "AXWebArea", let area = frame(node) { read.page = area }
                current = element(node, kAXParentAttribute)
            }
        }
        return read
    }
}

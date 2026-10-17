import AllInOneIMECore
import AppKit
import ApplicationServices

/// `@agent` typed in Chrome: the page's layers (`PageContext`) read with the Accessibility API — the focused field and
/// the way to it, what's visible in the window, the element under the pointer, the selection. Never a password field's
/// text, never asked for Accessibility from here (`AXIsProcessTrusted`). Off the main thread; at most `budget` seconds.
enum PageContextReader {
    /// The browsers whose pages are read.
    static let browsers: Set = ["com.google.Chrome"]

    /// Whether a page may be read for `app` now: the setting, a browser, Accessibility already allowed.
    static func applies(app: String?, enabled: Bool) -> Bool {
        enabled && app.map(browsers.contains) == true && AXIsProcessTrusted()
    }

    /// Chrome builds its pages' accessibility trees only for an assistive app: with `AXEnhancedUserInterface` on (as
    /// VoiceOver sets it), within a few seconds. Turned on when `@agent` starts being written there, so the tree is ready
    /// by ⏎, and back off once the page is read (`release`) or the field is left; left alone when it was on already.
    static func wake(pid: pid_t) {
        DispatchQueue.global(qos: .userInitiated).async {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.25)
            var value: CFTypeRef?
            let on = AXUIElementCopyAttributeValue(app, enhanced, &value) == .success && (value as? Bool) == true
            guard !on else { return }
            lock.lock()
            let added = raised.insert(pid).inserted
            lock.unlock()
            guard added else { return }
            AXUIElementSetAttributeValue(app, enhanced, kCFBooleanTrue)
            log.notice("page context: Chrome's accessibility tree asked for")
        }
    }

    /// `AXEnhancedUserInterface` back as it was, if `wake` turned it on.
    static func release(pid: pid_t) {
        lock.lock()
        let removed = raised.remove(pid) != nil
        lock.unlock()
        guard removed else { return }
        DispatchQueue.global(qos: .utility).async {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.25)
            AXUIElementSetAttributeValue(app, enhanced, kCFBooleanFalse)
        }
    }

    private static let enhanced = "AXEnhancedUserInterface" as CFString
    /// The browsers `wake` turned it on for. Any thread, under `lock`.
    nonisolated(unsafe) private static var raised: Set<pid_t> = []
    private static let lock = NSLock()

    /// The process of `app` when it's the one in front (the app being typed in).
    static func runningPID(_ app: String) -> pid_t? {
        guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == app else { return nil }
        return front.processIdentifier
    }

    /// The page in front in `pid`'s focused window; nil when there is none (or it isn't built in time) or the focus is in
    /// a password field. Out of time while reading it: what was read by then. `pointer`: the mouse location, top-left origin (main thread only to read it, hence passed in).
    static func read(pid: pid_t, pointer: CGPoint, budget: TimeInterval = 3) -> PageContext? {
        let deadline = Date().addingTimeInterval(budget)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var focused: AXUIElement?
        var web: AXUIElement?
        // A page tree not built yet has no children: asked again a few times.
        while true {
            focused = element(app, kAXFocusedUIElementAttribute)
            if let focused, string(focused, kAXSubroleAttribute) == kAXSecureTextFieldSubrole as String { return nil }
            web = focused.flatMap(webArea(above:)) ?? element(app, kAXFocusedWindowAttribute).flatMap { find("AXWebArea", in: $0) }
            if let web, !children(web).isEmpty { break }
            guard Date().addingTimeInterval(0.3) < deadline else { return nil }
            Thread.sleep(forTimeInterval: 0.3)
        }
        guard let web else { return nil }
        let viewport = element(app, kAXFocusedWindowAttribute).flatMap(frame)
        // The focused element counts only inside this page (not the address bar); else the one under the pointer.
        var focusPath: [AXUIElement] = []
        if let focused, webArea(above: focused).map({ CFEqual($0, web) }) == true {
            var current: AXUIElement? = focused
            while let element = current, !CFEqual(element, web) {
                focusPath.append(element)
                current = parent(element)
            }
        }
        var hit: AXUIElement?
        if focusPath.isEmpty {
            AXUIElementCopyElementAtPosition(app, Float(pointer.x), Float(pointer.y), &hit)
        }
        var snapshot = Snapshot(focusPath: focusPath, focused: focusPath.first, pointer: hit, viewport: viewport, deadline: deadline)
        let page = snapshot.node(web)  // out of time: what was read by then
        let selection = focusPath.first.flatMap { string($0, kAXSelectedTextAttribute) } ?? string(web, kAXSelectedTextAttribute)
        log.notice("page context: \(snapshot.count) elements read in \(String(format: "%.0f", (budget - deadline.timeIntervalSinceNow) * 1000), privacy: .public) ms")
        return PageContext.make(page: page, url: string(web, "AXURL") ?? "", title: string(web, kAXTitleAttribute) ?? "",
                                selection: selection, viewport: viewport)
    }

    /// The page's elements as `PageNode`s: only those inside the viewport, plus the way to the focused field.
    private struct Snapshot {
        let focusPath: [AXUIElement]
        let focused: AXUIElement?
        let pointer: AXUIElement?
        let viewport: CGRect?
        let deadline: Date
        var count = 0
        static let limit = 6000
        static let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
                            kAXValueAttribute, "AXPlaceholderValue", "AXDOMIdentifier", "AXInvalid", "AXRequired",
                            kAXPositionAttribute, kAXSizeAttribute] as [CFString]

        mutating func node(_ element: AXUIElement) -> PageNode {
            count += 1
            var values: CFArray?
            AXUIElementCopyMultipleAttributeValues(element, Self.names as CFArray, [], &values)
            let all = (values as? [Any]) ?? []
            func text(_ index: Int) -> String? {
                guard index < all.count else { return nil }
                if let text = all[index] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                return nil
            }
            func flag(_ index: Int) -> Bool {
                guard index < all.count else { return false }
                if let bool = all[index] as? Bool { return bool }
                return (all[index] as? String) == "true"
            }
            var frame: CGRect?
            if all.count > 10, CFGetTypeID(all[9] as CFTypeRef) == AXValueGetTypeID(), CFGetTypeID(all[10] as CFTypeRef) == AXValueGetTypeID() {
                var origin = CGPoint.zero, size = CGSize.zero
                AXValueGetValue(all[9] as! AXValue, .cgPoint, &origin)  // checked just above
                AXValueGetValue(all[10] as! AXValue, .cgSize, &size)
                frame = CGRect(origin: origin, size: size)
            }
            var node = PageNode(role: text(0) ?? "", subrole: text(1), label: nil, value: nil, placeholder: text(5),
                                domID: text(6), invalid: flag(7), required: flag(8),
                                focused: focused.map { CFEqual($0, element) } ?? false,
                                pointer: pointer.map { CFEqual($0, element) } ?? false, frame: frame)
            if !node.isPassword { node.value = text(4) }
            if node.isField {
                node.label = text(2) ?? PageContextReader.element(element, "AXTitleUIElement").flatMap { string($0, kAXValueAttribute) }
                    ?? text(3) ?? node.placeholder
                return node  // a field's children are its own text
            }
            node.label = text(2) ?? text(3)
            if ["AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton"].contains(node.role) { return node }
            for child in PageContextReader.children(element) {
                guard count < Self.limit, Date() < deadline else { break }
                let onFocusPath = focusPath.contains { CFEqual($0, child) }
                // Off screen: Chrome pins those to the window's edge with a height of 1 or less.
                if !onFocusPath, let viewport, let frame = PageContextReader.frame(child), frame.height <= 1 || !frame.intersects(viewport) {
                    continue
                }
                node.children.append(self.node(child))
            }
            return node
        }
    }

    // MARK: Accessibility helpers

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)  // checked just above
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        if let url = value as? URL { return url.absoluteString }
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    static func parent(_ element: AXUIElement) -> AXUIElement? { self.element(element, kAXParentAttribute) }

    static func frame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)  // checked just above
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    /// The web area `element` is in, if any.
    static func webArea(above element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        var hops = 0
        while let candidate = current, hops < 60 {
            if string(candidate, kAXRoleAttribute) == "AXWebArea" { return candidate }
            current = parent(candidate)
            hops += 1
        }
        return nil
    }

    /// The first element with `role` below `element` (depth first, not too deep).
    static func find(_ role: String, in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if string(element, kAXRoleAttribute) == role { return element }
        guard depth < 25 else { return nil }
        for child in children(element) {
            if let found = find(role, in: child, depth: depth + 1) { return found }
        }
        return nil
    }
}

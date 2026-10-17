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

    // MARK: Chrome's page tree on and off

    /// Chrome builds its pages' accessibility trees only for an assistive app: with `AXEnhancedUserInterface` on (as
    /// VoiceOver sets it), within a few seconds. Turned on when `@agent` starts being written there, so the tree is ready
    /// by ⏎, and back off once nobody wants it (`release`: the page read, the draft given up, the field left). Taken
    /// over only when it was surely off: on already, or not readable, it's left alone. All on one serial queue, in the
    /// order asked; who wants it is counted at once, under `lock`.
    static func wake(pid: pid_t) {
        lock.lock()
        wanted[pid, default: 0] += 1
        lock.unlock()
        queue.async {
            guard wantedNow(pid), !owned.contains(pid), !leftAlone.contains(pid) else { return }
            let app = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, enhanced, &value) == .success, let on = value as? Bool else {
                leftAlone.insert(pid)  // can't tell: not ours to change
                return
            }
            guard !on else {
                leftAlone.insert(pid)  // VoiceOver or another assistive app has it on
                return
            }
            owned.insert(pid)
            remember()
            AXUIElementSetAttributeValue(app, enhanced, kCFBooleanTrue)
            log.notice("page context: Chrome's accessibility tree asked for")
        }
    }

    /// One `wake` less; with nobody wanting it any more, `AXEnhancedUserInterface` is off again if `wake` turned it on.
    static func release(pid: pid_t) {
        lock.lock()
        wanted[pid] = max((wanted[pid] ?? 0) - 1, 0)
        lock.unlock()
        queue.async {
            guard !wantedNow(pid) else { return }
            leftAlone.remove(pid)
            guard owned.remove(pid) != nil else { return }
            remember()
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), enhanced, kCFBooleanFalse)
        }
    }

    /// Turned on by an earlier run that ended before turning it off (a crash, a reinstall): off again, for the
    /// processes that are still Chrome. At launch.
    static func releaseLeftOver() {
        let pids = (UserDefaults.standard.array(forKey: ownedKey) as? [Int]) ?? []
        guard !pids.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: ownedKey)
        queue.async {
            for pid in pids.map(pid_t.init) where NSRunningApplication(processIdentifier: pid).map({ browsers.contains($0.bundleIdentifier ?? "") }) == true {
                AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), enhanced, kCFBooleanFalse)
                log.notice("page context: Chrome's accessibility tree turned off again (left on by an earlier run)")
            }
        }
    }

    private static let enhanced = "AXEnhancedUserInterface" as CFString
    private static let ownedKey = "pageContextChromeTreeOn"
    private static let queue = DispatchQueue(label: "AllInOneIME.pageTree")
    private static let lock = NSLock()
    /// How many want each browser's tree (under `lock`); which ones `wake` turned it on for, and which it leaves alone
    /// (on `queue` only).
    nonisolated(unsafe) private static var wanted: [pid_t: Int] = [:]
    nonisolated(unsafe) private static var owned: Set<pid_t> = []
    nonisolated(unsafe) private static var leftAlone: Set<pid_t> = []

    private static func wantedNow(_ pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return (wanted[pid] ?? 0) > 0
    }

    /// The processes it's on for, kept for `releaseLeftOver`. On `queue`.
    private static func remember() {
        if owned.isEmpty { UserDefaults.standard.removeObject(forKey: ownedKey) } else { UserDefaults.standard.set(owned.map(Int.init), forKey: ownedKey) }
    }

    /// The process of `app` when it's the one in front (the app being typed in).
    static func runningPID(_ app: String) -> pid_t? {
        guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == app else { return nil }
        return front.processIdentifier
    }

    // MARK: Reading

    /// The page in front in `pid`'s focused window; nil when there is none (or it isn't built in time) or the focus is in
    /// a password field. Out of time while reading it: what was read by then. `pointer`: the mouse location, top-left
    /// origin (only the main thread may read it, hence passed in). Blocks for at most about `budget` seconds: run it off
    /// the main thread.
    static func read(pid: pid_t, pointer: CGPoint, budget: TimeInterval = 3) -> PageContext? {
        let deadline = Date().addingTimeInterval(budget)
        // Every element's calls wait 0.25 s at most (the system-wide element sets it for this process).
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
        let app = AXUIElementCreateApplication(pid)
        var focused: AXUIElement?
        var web: AXUIElement?
        // A page tree not built yet has no children: asked again a few times.
        while true {
            focused = element(app, kAXFocusedUIElementAttribute)
            if let focused, string(focused, kAXSubroleAttribute) == kAXSecureTextFieldSubrole as String { return nil }
            web = focused.flatMap { outermostWebArea(above: $0, deadline: deadline) }
                ?? element(app, kAXFocusedWindowAttribute).flatMap { find("AXWebArea", in: $0, deadline: deadline) }
            if let web, !children(web).isEmpty { break }
            guard Date().addingTimeInterval(0.3) < deadline else { return nil }
            Thread.sleep(forTimeInterval: 0.3)
        }
        guard let web else { return nil }
        // Just built, the tree may not say where the focus is yet: asked once more (a password field is still none).
        if focused.flatMap({ outermostWebArea(above: $0, deadline: deadline) }) == nil {
            for _ in 0..<5 where Date().addingTimeInterval(0.1) < deadline {
                if let now = element(app, kAXFocusedUIElementAttribute), outermostWebArea(above: now, deadline: deadline) != nil {
                    focused = now
                    break
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            if let focused, string(focused, kAXSubroleAttribute) == kAXSecureTextFieldSubrole as String { return nil }
        }
        let viewport = element(app, kAXFocusedWindowAttribute).flatMap(frame)
        // The focused element counts only inside this page (not the address bar), an iframe's too; else the one under
        // the pointer.
        var focusPath: [AXUIElement] = []
        if let focused, outermostWebArea(above: focused, deadline: deadline).map({ CFEqual($0, web) }) == true {
            var current: AXUIElement? = focused
            while let element = current, !CFEqual(element, web), focusPath.count < 200 {
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
            // A failed attribute comes back as an AXValue of the error type: only a point and a size make a frame.
            if all.count > 10, CFGetTypeID(all[9] as CFTypeRef) == AXValueGetTypeID(), CFGetTypeID(all[10] as CFTypeRef) == AXValueGetTypeID() {
                let position = all[9] as! AXValue, extent = all[10] as! AXValue  // checked just above
                var origin = CGPoint.zero, size = CGSize.zero
                if AXValueGetType(position) == .cgPoint, AXValueGetType(extent) == .cgSize,
                   AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(extent, .cgSize, &size) {
                    frame = CGRect(origin: origin, size: size)
                }
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

    /// The page `element` is in: the outermost web area above it (an iframe is a web area of its own, inside the page).
    static func outermostWebArea(above element: AXUIElement, deadline: Date) -> AXUIElement? {
        var current: AXUIElement? = element
        var found: AXUIElement?
        var hops = 0
        while let candidate = current, hops < 200, Date() < deadline {
            if string(candidate, kAXRoleAttribute) == "AXWebArea" { found = candidate }
            current = parent(candidate)
            hops += 1
        }
        return found
    }

    /// The first element with `role` below `element` (depth first, not too deep, not past `deadline`).
    static func find(_ role: String, in element: AXUIElement, depth: Int = 0, deadline: Date) -> AXUIElement? {
        if string(element, kAXRoleAttribute) == role { return element }
        guard depth < 25, Date() < deadline else { return nil }
        for child in children(element) {
            if let found = find(role, in: child, depth: depth + 1, deadline: deadline) { return found }
        }
        return nil
    }
}

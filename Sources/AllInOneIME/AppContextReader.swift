import AllInOneIMECore
import AppKit
import ApplicationServices

/// What the user is looking at in the app in front, for an `@question` the input method's session answers
/// (`AppSnapshot`, the core's AppContext.swift): read with Accessibility as the question starts, at most
/// `AppSnapshot.budget`, off the main thread. Only attributes are read: no screenshot, no text recognition, nothing typed
/// or posted to the app. The app, its window's title, the selection; Slack's channel and messages (`SlackAdapter`, its
/// web content tree turned on: `AXManualAccessibility`); Chrome's page (`PageContextReader`, its tree woken while the
/// question was written). Never asks for Accessibility (`AXIsProcessTrusted`).
enum AppContextReader {
    /// Chrome, whose page is read as `@agent` reads it.
    static let chrome = "com.google.Chrome"

    /// The reader for the app in front, made on the main thread: the app as it is now (its name, bundle id, process) and
    /// the pointer (only the main thread may read it); nil without Accessibility, or when the app in front isn't `app`.
    @MainActor
    static func reader(app: String?, request: AppSnapshot.Request) -> (@Sendable () -> AppSnapshot?)? {
        guard AXIsProcessTrusted(), let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier, app == nil || app == bundleID else { return nil }
        let (pid, name) = (front.processIdentifier, front.localizedName ?? bundleID)
        // Chrome's page: asked for (counted) now, so that the input method's own wake, given back as the draft goes,
        // doesn't turn the tree off while it is read; given back once read, or once the reader is dropped unread.
        let page = request.adapters && PageContextReader.applies(app: bundleID, enabled: true) ? PageHold(pid: pid) : nil
        let pointer = pointerLocation()
        return {
            let snapshot = read(pid: pid, name: name, bundleID: bundleID, request: request, page: page != nil, pointer: pointer)
            page?.release()
            return snapshot
        }
    }

    /// Chrome's page tree asked for (`PageContextReader.wake`), given back once: by `release`, else when it goes.
    private final class PageHold: @unchecked Sendable {
        let pid: pid_t
        private let held = Locked(initialState: true)

        init(pid: pid_t) {
            self.pid = pid
            PageContextReader.wake(pid: pid)
        }

        func release() {
            guard held.withLock({ held in defer { held = false }; return held }) else { return }
            PageContextReader.release(pid: pid)
        }

        deinit { release() }
    }

    /// An `@question` about to be asked in `app`: Slack's web content tree turned on now (`AXManualAccessibility`), so that
    /// it is built by ⏎. Left on (as an assistive app leaves it).
    @MainActor
    static func wake(app: String?) {
        guard app == SlackAdapter.bundleID, AXIsProcessTrusted(), let pid = PageContextReader.runningPID(SlackAdapter.bundleID) else { return }
        queue.async { manualAccessibility(pid) }
    }

    private static let queue = DispatchQueue(label: "AllInOneIME.appContext")

    /// Electron builds its web content's accessibility tree for an assistive app that sets this on the app's element.
    static func manualAccessibility(_ pid: pid_t) {
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// The mouse pointer, top-left origin (as Accessibility has it).
    @MainActor
    static func pointerLocation() -> CGPoint {
        let mouse = NSEvent.mouseLocation, height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: mouse.x, y: height - mouse.y)
    }

    /// The snapshot of the app `pid` (in front): the always-part, then its adapter's, until `budget` seconds are up.
    /// Blocks: off the main thread.
    static func read(pid: pid_t, name: String, bundleID: String, request: AppSnapshot.Request, page: Bool, pointer: CGPoint,
                     budget: TimeInterval = AppSnapshot.budget) -> AppSnapshot {
        let started = Date()
        let deadline = AppDeadline(seconds: budget)
        PageContextReader.boundCalls()
        let access = AXAppAccess(pid: pid)
        if request.adapters, bundleID == SlackAdapter.bundleID { manualAccessibility(pid) }
        var snapshot = AppSnapshot(appName: name, bundleID: bundleID, typed: request.typed)
        snapshot.windowTitle = access.window.flatMap { PageContextReader.string($0.element, kAXTitleAttribute) }
        let focused = access.focused
        if let selection = request.selection, !selection.isEmpty {
            snapshot.selection = selection
        } else if let focused, PageContextReader.string(focused.element, kAXSubroleAttribute) != kAXSecureTextFieldSubrole as String {
            snapshot.selection = PageContextReader.string(focused.element, kAXSelectedTextAttribute)
        }
        if request.adapters {
            if page {
                let left = max(budget - Date().timeIntervalSince(started), 0.02)
                snapshot.detail = PageContextReader.read(pid: pid, pointer: pointer, budget: left).map(AppDetail.init(page:))
            } else if let adapter = AppContextAdapters.adapter(for: bundleID) {
                snapshot.detail = adapter.read(access, marked: request.marked, deadline: deadline)
            }
        }
        snapshot.elapsed = Date().timeIntervalSince(started) * 1000
        log.notice("app context: \(bundleID, privacy: .public), \(snapshot.detail?.messages.count ?? 0, privacy: .public) messages, \(String(format: "%.0f", snapshot.elapsed), privacy: .public) ms")
        return snapshot
    }

    // MARK: The debug command

    /// `--app-context [seconds] [tree]`: the snapshot of the app in front after `seconds` (3 by default: time to bring it
    /// to the front), printed with the block a session would get; `tree` prints the elements Slack's adapter walks too.
    /// Only reads (nothing typed, nothing sent). Needs Accessibility for the process that runs it.
    @MainActor
    static func debug(_ arguments: [String]) -> Int32 {
        guard AXIsProcessTrusted() else {
            print("Accessibility isn't allowed for this process (System Settings → Privacy & Security → Accessibility)")
            return 1
        }
        let wait = arguments.compactMap(Double.init).first ?? 3
        if wait > 0 {
            print("reading the app in front in \(Int(wait)) s…")
            RunLoop.main.run(until: Date().addingTimeInterval(wait))
        }
        guard let front = NSWorkspace.shared.frontmostApplication, let bundleID = front.bundleIdentifier else {
            print("no app in front"); return 1
        }
        let pid = front.processIdentifier
        let page = PageContextReader.applies(app: bundleID, enabled: true)
        if page {
            PageContextReader.wake(pid: pid)
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))  // as while the question was written
        }
        if bundleID == SlackAdapter.bundleID {
            manualAccessibility(pid)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        }
        let request = AppSnapshot.Request(typed: "(the question)")
        let snapshot = read(pid: pid, name: front.localizedName ?? bundleID, bundleID: bundleID, request: request, page: page,
                            pointer: pointerLocation())
        if page { PageContextReader.release(pid: pid) }
        print("app: \(snapshot.appName) (\(snapshot.bundleID))")
        print("window: \(snapshot.windowTitle ?? "-")")
        print("selection: \(snapshot.selection.map { String($0.prefix(80)) } ?? "-")")
        if let detail = snapshot.detail {
            for field in detail.fields { print("\(field.name): \(field.value)") }
            print("messages: \(detail.messages.count)")
            for message in detail.messages {
                print("  [\(message.time ?? "-")] \(message.sender ?? "?"): \(message.text.prefix(60))  \(message.link ?? "")")
            }
            print("draft: \(detail.draft.map { String($0.prefix(80)) } ?? "-")")
            for section in detail.sections { print("\(section.name): \(section.value.count) chars") }
        } else {
            print("(no adapter for this app, or nothing read)")
        }
        let block = snapshot.block()
        print("\n— the block (\(block.count) chars), read in \(String(format: "%.0f", snapshot.elapsed)) ms —\n\(block)")
        if arguments.contains("tree") { dumpTree(pid: pid) }
        Thread.sleep(forTimeInterval: 0.3)  // a page given back is turned off in the background
        return 0
    }

    /// The focused element's way up to the web area, and the first list's last items below it, as Accessibility gives
    /// them (for checking `SlackAdapter` against an app).
    private static func dumpTree(pid: pid_t) {
        let access = AXAppAccess(pid: pid)
        print("\n— the way up from the focus —")
        var current = access.focusedElement()
        var hops = 0
        while let element = current, hops < 40 {
            print("  " + describe(element.read()))
            if element.read().role == "AXWebArea" { break }
            current = element.parent()
            hops += 1
        }
        func walk(_ element: any AppElement, depth: Int, budget: inout Int) {
            guard budget > 0, depth < 14 else { return }
            budget -= 1
            print(String(repeating: "  ", count: depth) + describe(element.read()))
            for child in element.children() { walk(child, depth: depth + 1, budget: &budget) }
        }
        guard let window = access.window else { return }
        var budget = 300
        var lists: [any AppElement] = []
        func findLists(_ element: any AppElement, depth: Int) {
            guard budget > 0, depth < 40 else { return }
            budget -= 1
            if element.read().role == "AXList" { lists.append(element); return }
            for child in element.children() { findLists(child, depth: depth + 1) }
        }
        findLists(window, depth: 0)
        for list in lists.prefix(4) {
            print("\n— list: \(describe(list.read())) —")
            var items = 120
            for item in list.children().suffix(3) { walk(item, depth: 1, budget: &items) }
        }
    }

    private static func describe(_ node: AppNode) -> String {
        [node.role, node.subrole.map { "(\($0))" }, node.title.map { "title=\"\($0.prefix(100))\"" },
         node.description.map { "desc=\"\($0.prefix(60))\"" }, node.value.map { "value=\"\($0.prefix(60))\"" },
         node.url.map { "url=\($0)" }, node.frame.map { "frame=\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))×\(Int($0.height))" }]
            .compactMap { $0 }.joined(separator: " ")
    }
}

/// An `AXUIElement` as the core's adapters walk it (`AppElement`): one Accessibility call per read (the attributes at
/// once), per children, per parent.
final class AXAppElement: AppElement {
    let element: AXUIElement

    init(_ element: AXUIElement) { self.element = element }

    private static let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
                                kAXValueAttribute, kAXURLAttribute, kAXPositionAttribute, kAXSizeAttribute] as [CFString]

    func read() -> AppNode {
        var values: CFArray?
        AXUIElementCopyMultipleAttributeValues(element, Self.names as CFArray, [], &values)
        let all = (values as? [Any]) ?? []
        func text(_ index: Int) -> String? {
            guard index < all.count else { return nil }
            if let url = all[index] as? URL { return url.absoluteString }
            guard let text = all[index] as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        var frame: CGRect?
        // A failed attribute comes back as an AXValue of the error type: only a point and a size make a frame.
        if all.count > 7, CFGetTypeID(all[6] as CFTypeRef) == AXValueGetTypeID(), CFGetTypeID(all[7] as CFTypeRef) == AXValueGetTypeID() {
            let position = all[6] as! AXValue, extent = all[7] as! AXValue  // checked just above
            var origin = CGPoint.zero, size = CGSize.zero
            if AXValueGetType(position) == .cgPoint, AXValueGetType(extent) == .cgSize,
               AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(extent, .cgSize, &size) {
                frame = CGRect(origin: origin, size: size)
            }
        }
        var node = AppNode(role: text(0) ?? "", subrole: text(1), title: text(2), description: text(3), url: text(5), frame: frame)
        if !node.isPassword { node.value = text(4) }
        return node
    }

    func children() -> [any AppElement] { PageContextReader.children(element).map(AXAppElement.init) }

    func parent() -> (any AppElement)? { PageContextReader.parent(element).map(AXAppElement.init) }

    func isSame(_ other: any AppElement) -> Bool {
        guard let other = other as? AXAppElement else { return false }
        return CFEqual(element, other.element)
    }
}

/// The app `pid` as the core's adapters start from it.
struct AXAppAccess: AppAccess {
    let app: AXUIElement

    init(pid: pid_t) { app = AXUIElementCreateApplication(pid) }

    var focused: AXAppElement? { PageContextReader.element(app, kAXFocusedUIElementAttribute).map(AXAppElement.init) }
    var window: AXAppElement? { PageContextReader.element(app, kAXFocusedWindowAttribute).map(AXAppElement.init) }

    func focusedElement() -> (any AppElement)? { focused }
    func focusedWindow() -> (any AppElement)? { window }
}

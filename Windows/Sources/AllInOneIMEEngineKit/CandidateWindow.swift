#if os(Windows)
import AllInOneIMECore
import CAllInOneIMEPanel
import Foundation
import WinSDK

/// Who owns the foreground, and where a client's caret may be (§8): the candidate window's own checks, for the engine.
public enum Foreground {
    /// Whether process `pid` is the app in front: the foreground window is its own (a classic console's, its
    /// conhost's), or the focus is in a window of its own, or a window inside the foreground window is: a UWP app's in
    /// the frame around it, or, for a `trusted` client (§8), any (a browser's, a plugin's).
    public static func isOwned(by pid: UInt32, trusted: Bool) -> Bool { aio_owns_foreground(pid, trusted ? 1 : 0) != 0 }

    /// `isOwned(by:trusted:)` with `foreground` as the foreground window and `focus` its thread's focus window.
    static func isInFront(_ pid: UInt32, foreground: HWND?, focus: HWND? = nil, trusted: Bool = true) -> Bool {
        aio_in_front(UnsafeMutableRawPointer(foreground), UnsafeMutableRawPointer(focus), pid, trusted ? 1 : 0) != 0
    }

    /// The rectangle a caret that process `pid` reports in window `hwnd` must be in: that window's, if it is the
    /// process's; with no window, the foreground window's, if the process owns it (`trusted` as `isOwned`). Nil if
    /// neither.
    public static func caretBounds(hwnd: UInt64?, pid: UInt32?, trusted: Bool) -> CaretRect? {
        guard let pid else { return nil }
        var bounds = AioCaret()
        guard aio_caret_bounds(hwnd ?? 0, pid, trusted ? 1 : 0, &bounds) != 0 else { return nil }
        return CaretRect(x: Int(bounds.x), y: Int(bounds.y), width: Int(bounds.width), height: Int(bounds.height))
    }
}

/// The engine's candidate window (M6), the `PanelWindow` on Windows: the C++ window of `CAllInOneIMEPanel` (a layered,
/// no-activate, topmost tool window drawn with Direct2D and DirectWrite, on a thread of its own), given each of the
/// core's `PanelModel`s as a flat copy. A click on a row comes back on the window's thread and goes to the owner's
/// session (`PanelOwner.choose`: its connection's queue).
public final class CandidateWindow: PanelWindow, @unchecked Sendable {
    private var panel: OpaquePointer?
    private let lock = NSLock()
    /// The owners by the token the window knows them by.
    private var owners: [UInt64: PanelOwner] = [:]
    private var tokens: [ObjectIdentifier: UInt64] = [:]
    private var nextToken: UInt64 = 1
    /// How long a notice stays up.
    public var noticeDuration: Int32 = 1500

    /// The window, created hidden; nil without a desktop to put it on, or without Direct2D. The window calls back with
    /// this object unretained: it lives as long as the window (`deinit` closes the window first).
    public init?() {
        var callbacks = AioPanelCallbacks(
            context: nil,
            click: { context, owner, row in
                guard let context else { return }
                Unmanaged<CandidateWindow>.fromOpaque(context).takeUnretainedValue().clicked(owner: owner, row: Int(row))
            },
            scroll: { context, owner, steps in
                guard let context else { return }
                Unmanaged<CandidateWindow>.fromOpaque(context).takeUnretainedValue().scrolled(owner: owner, steps: Int(steps))
            })
        callbacks.context = Unmanaged.passUnretained(self).toOpaque()
        guard let created = aio_panel_create(callbacks) else { return nil }
        panel = created
    }

    deinit {
        aio_panel_destroy(panel)
    }

    private func token(_ owner: PanelOwner) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        if let token = tokens[ObjectIdentifier(owner)] { return token }
        let token = nextToken
        nextToken += 1
        tokens[ObjectIdentifier(owner)] = token
        owners[token] = owner
        return token
    }

    private func owner(_ token: UInt64) -> PanelOwner? {
        lock.lock()
        defer { lock.unlock() }
        return owners[token]
    }

    public func forget(owner: PanelOwner) {
        lock.lock()
        if let token = tokens.removeValue(forKey: ObjectIdentifier(owner)) { owners[token] = nil }
        lock.unlock()
    }

    private func clicked(owner token: UInt64, row: Int) { owner(token)?.choose(row) }
    private func scrolled(owner token: UInt64, steps: Int) { owner(token)?.scroll(steps) }

    public func show(_ model: PanelModel, owner: PanelOwner, caret: CaretRect?) {
        let token = token(owner)
        Self.withModel(model) { flat in
            if let caret {
                var c = Self.flat(caret)
                aio_panel_show(panel, flat, &c, token, owner.pid ?? 0, owner.trusted ? 1 : 0)
            } else {
                aio_panel_show(panel, flat, nil, token, owner.pid ?? 0, owner.trusted ? 1 : 0)
            }
        }
    }

    public func hide(owner: PanelOwner) {
        aio_panel_hide(panel, token(owner))
    }

    public func move(owner: PanelOwner, caret: CaretRect) {
        var c = Self.flat(caret)
        aio_panel_move(panel, token(owner), &c)
    }

    public func notice(_ text: String, owner: PanelOwner, caret: CaretRect?) {
        let token = token(owner)
        Self.withUTF16(text) { text in
            if let caret {
                var c = Self.flat(caret)
                aio_panel_notice(panel, text, token, owner.pid ?? 0, owner.trusted ? 1 : 0, &c, noticeDuration)
            } else {
                aio_panel_notice(panel, text, token, owner.pid ?? 0, owner.trusted ? 1 : 0, nil, noticeDuration)
            }
        }
    }

    /// What the window does now, once it has done what it was asked before.
    public var state: AioPanelState {
        var state = AioPanelState()
        aio_panel_state(panel, &state)
        return state
    }

    /// Where row `row` was drawn last, in the window's own pixels.
    public func rowRect(_ row: Int) -> (x: Int, y: Int, width: Int, height: Int)? {
        var x: Int32 = 0, y: Int32 = 0, width: Int32 = 0, height: Int32 = 0
        guard aio_panel_row_rect(panel, Int32(row), &x, &y, &width, &height) != 0 else { return nil }
        return (Int(x), Int(y), Int(width), Int(height))
    }

    /// The window's handle, for tests.
    public var window: UnsafeMutableRawPointer? { aio_panel_window(panel) }

    /// Writes what was drawn last to a PNG.
    public func savePNG(to url: URL) -> Bool {
        Self.withUTF16(url.withUnsafeFileSystemRepresentation { String(cString: $0!) }.replacingOccurrences(of: "/", with: "\\")) {
            aio_panel_save_png(panel, $0) != 0
        }
    }

    // MARK: - Flat copies for C

    static func flat(_ caret: CaretRect) -> AioCaret {
        AioCaret(x: Int32(clamping: caret.x), y: Int32(clamping: caret.y), width: Int32(clamping: caret.width),
                 height: Int32(clamping: caret.height), exact: caret.exact ? 1 : 0)
    }

    static func withUTF16<T>(_ text: String, _ body: (UnsafePointer<UInt16>) -> T) -> T {
        let units = Array(text.utf16) + [0]
        return units.withUnsafeBufferPointer { body($0.baseAddress!) }
    }

    /// `model` as `AioPanelModel`, its strings alive for `body`: a line each for the input, the header and the status
    /// (`PanelModel.inputLine`, `headerLine`, `statusLine`), and no icons. A conversation's rows (`transcript`) are drawn
    /// as any others; a row's `choice` stays with the engine (`PanelOwner.choose`).
    static func withModel(_ model: PanelModel, _ body: (UnsafePointer<AioPanelModel>) -> Void) {
        var storage: [[UInt16]] = []
        func keep(_ text: String?) -> Int? {
            guard let text, !text.isEmpty else { return nil }
            storage.append(Array(text.utf16) + [0])
            return storage.count - 1
        }
        struct RowIndices { var label, text, comment: Int? }
        let rowIndices = model.rows.map { RowIndices(label: keep($0.label), text: keep($0.text), comment: keep($0.comment)) }
        let kind: Int32
        switch model.status {
        case .none: kind = Int32(AIO_STATUS_NONE)
        case .hint, .list: kind = Int32(AIO_STATUS_HINT)
        case .loading: kind = Int32(AIO_STATUS_LOADING)
        case .error: kind = Int32(AIO_STATUS_ERROR)
        }
        let statusIndex = keep(model.statusLine), inputIndex = keep(model.inputLine), headerIndex = keep(model.headerLine)
        let footerIndex = keep(model.footer), detailIndex = keep(model.detail)
        // The strings' addresses stay put while `pointers` is in scope (arrays of arrays, none of them changed).
        let pointers: [UnsafeMutablePointer<UInt16>] = storage.map { units in
            let pointer = UnsafeMutablePointer<UInt16>.allocate(capacity: units.count)
            pointer.initialize(from: units, count: units.count)
            return pointer
        }
        defer { pointers.forEach { $0.deallocate() } }
        func pointer(_ index: Int?) -> UnsafePointer<UInt16>? { index.map { UnsafePointer(pointers[$0]) } }
        var rows = zip(model.rows, rowIndices).map { row, indices in
            AioPanelRow(label: pointer(indices.label), text: pointer(indices.text), comment: pointer(indices.comment),
                        style: row.kind == .candidate ? 0 : row.kind == .original ? 1 : 2,
                        pickable: row.pickable ? 1 : 0, complete: row.isComplete ? 1 : 0)
        }
        rows.withUnsafeMutableBufferPointer { buffer in
            var flat = AioPanelModel(rows: UnsafePointer(buffer.baseAddress), rowCount: Int32(buffer.count),
                                     highlighted: Int32(model.highlighted ?? -1), horizontal: model.horizontal ? 1 : 0,
                                     statusKind: kind, status: pointer(statusIndex), input: pointer(inputIndex),
                                     header: pointer(headerIndex), footer: pointer(footerIndex), detail: pointer(detailIndex))
            withUnsafePointer(to: &flat) { body($0) }
        }
    }
}
#endif

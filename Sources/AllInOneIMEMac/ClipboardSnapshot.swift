import AppKit

/// What was on a pasteboard before a paste of the input method's (`TerminalPaste`), to put back after it: its items as
/// they were, each with its types in its own order (the first is what a reader takes first: clipboard history records an
/// image only when it comes first). Taken only where the clipboard can be read without macOS asking
/// (`ClipboardAccess.allowed`): with Ask, or never asked yet, each read would be macOS's prompt; with Deny each comes back
/// empty, and putting that back would empty the clipboard. Nor where it was copied on an iPhone or another Mac
/// (Universal Clipboard, `SystemClipboard.remoteType`): its data is fetched from there when read, over the network.
public struct ClipboardSnapshot: Sendable {
    public let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]

    public init(items: [[(type: NSPasteboard.PasteboardType, data: Data)]]) { self.items = items }

    /// Whether `pasteboard` can be taken: `access` is `.allowed`, and none of its items came from Universal Clipboard
    /// (its types only are looked at, which never asks for data).
    public static func canTake(_ pasteboard: NSPasteboard, access: ClipboardAccess) -> Bool {
        let remote = NSPasteboard.PasteboardType(SystemClipboard.remoteType)
        return access == .allowed && !(pasteboard.pasteboardItems ?? []).contains { $0.types.contains(remote) }
    }

    /// `pasteboard`'s items as they are; nil, nothing of it read, where it can't be taken (`canTake`).
    public static func take(_ pasteboard: NSPasteboard, access: ClipboardAccess) -> ClipboardSnapshot? {
        guard canTake(pasteboard, access: access) else { return nil }
        return ClipboardSnapshot(items: (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        })
    }

    /// `take`, read off the main thread, which never waits on it: nil also where it isn't all read within `limit` (an
    /// app's data handed over only when read, and slow to come: a busy app; it is left to come on its own), or where
    /// something else was copied meanwhile.
    @MainActor
    public static func take(_ pasteboard: NSPasteboard, access: ClipboardAccess, within limit: TimeInterval) async -> ClipboardSnapshot? {
        guard canTake(pasteboard, access: access) else { return nil }
        let was = pasteboard.changeCount
        let snapshot = await withCheckedContinuation { continuation in
            let read = Read(pasteboard, continuation)
            DispatchQueue.global(qos: .userInitiated).async { read.answer(take(read.pasteboard, access: access)) }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + limit) { read.answer(nil) }
        }
        return pasteboard.changeCount == was ? snapshot : nil
    }

    /// A read of a pasteboard on another thread, answered once: with what it read, or nil at its time limit, whichever
    /// comes first.
    private final class Read: @unchecked Sendable {
        let pasteboard: NSPasteboard
        private let lock = NSLock()
        private var continuation: CheckedContinuation<ClipboardSnapshot?, Never>?

        init(_ pasteboard: NSPasteboard, _ continuation: CheckedContinuation<ClipboardSnapshot?, Never>) {
            self.pasteboard = pasteboard
            self.continuation = continuation
        }

        func answer(_ snapshot: ClipboardSnapshot?) {
            let waiting = lock.withLock {
                defer { continuation = nil }
                return continuation
            }
            waiting?.resume(returning: snapshot)
        }
    }

    /// Put back on `pasteboard`, in its order.
    public func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        })
    }
}

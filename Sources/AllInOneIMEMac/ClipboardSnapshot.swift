import AppKit

/// What was on a pasteboard before a paste of the input method's (`TerminalPaste`), to put back after it: its items as
/// they were, each with its types in its own order (the first is what a reader takes first: clipboard history records an
/// image only when it comes first). Taken only where the clipboard can be read without macOS asking
/// (`ClipboardAccess.allowed`): with Ask, or never asked yet, each read would be macOS's prompt; with Deny each comes back
/// empty, and putting that back would empty the clipboard.
public struct ClipboardSnapshot {
    public let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]

    public init(items: [[(type: NSPasteboard.PasteboardType, data: Data)]]) { self.items = items }

    /// `pasteboard`'s items as they are; nil, nothing of it read, where `access` isn't `.allowed`.
    public static func take(_ pasteboard: NSPasteboard, access: ClipboardAccess) -> ClipboardSnapshot? {
        guard access == .allowed else { return nil }
        return ClipboardSnapshot(items: (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        })
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

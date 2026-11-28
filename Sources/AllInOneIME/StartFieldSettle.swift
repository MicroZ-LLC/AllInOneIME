import AllInOneIMECore
import AppKit

/// Step 3's wait between the two Escapes an example's click posts first (`StartModel.strokes`) and the keys that type
/// the example. Esc in the @ list may put the draft's text in as typed (`Composer.handleOneAtKey`), and that comes back
/// from the input method (this process's own, through the field's input context) some time after the key is posted,
/// never during the click. So the field is emptied after it is in and before the example's first key goes out: emptied
/// sooner, the old "@…" lands in front of the example; later, the magic key arrives after the old text (and right after
/// a letter it is only text, no list: `Composer.continuesWord`). A fixed delay is too short on a busy Mac and slow on an
/// idle one, so it is looked at, on the main queue every `interval` (nothing waits on the main thread).
///
/// Nothing of a draft is ever in the field (the input method marks none: it shows in the panel), so what the field
/// shows says nothing of it. What tells is the input method itself, in this process (`draftOpen`): while it has a
/// draft, a panel or a result being typed out, the Escapes aren't through with it. Once it has none, they are through
/// when one of these has come (`settled`), and the field has then stayed as it is for `quiet` (time for the text an
/// Escape put in to come back):
///
/// - an Escape's key up in this app (a local monitor, which keeps nothing from the field): its key down went past the
///   input method, which had nothing open for it;
/// - the draft or panel seen open has ended (the key tap takes an Escape's key down and up while a panel shows,
///   `KeyGuard`, so the app may see neither);
/// - the field's text changed (put in as typed).
///
/// At most `limit`: a draft the Escapes don't end is left as before this wait, and waiting changes nothing for it.
@MainActor
final class StartFieldSettle {
    static let interval: TimeInterval = 0.02
    static let quiet: TimeInterval = 0.15
    static let limit: TimeInterval = 1.5

    /// The wait going on: an example clicked before it is over replaces it (its keys never go out), so that two clicks'
    /// keys never mix.
    private static var current: StartFieldSettle?

    private let editor: NSTextView
    private let draftOpen: @MainActor () -> Bool
    private let then: @MainActor () -> Void
    private let start: String
    private var last: String
    private let began = ProcessInfo.processInfo.systemUptime
    private var changed: TimeInterval
    private var escapeAt: TimeInterval?
    private var draftSeen = false
    private var draftEndedAt: TimeInterval?
    private var monitor: Any?

    private init(_ editor: NSTextView, draftOpen: @escaping @MainActor () -> Bool, then: @escaping @MainActor () -> Void) {
        self.editor = editor
        self.draftOpen = draftOpen
        self.then = then
        start = editor.string
        last = start
        changed = began
        // Looked at before the Escapes go out: a draft they end before the first look is seen to end there.
        draftSeen = draftOpen()
    }

    /// `editor` looked at for the Escapes about to be posted, `then` run once they are handled (above); `draftOpen`
    /// tells whether the input method has a draft, a panel or a result being typed out now. Called before they are
    /// posted: they come to this app no sooner than the main thread's next turn, so none goes by unseen.
    static func watch(_ editor: NSTextView, draftOpen: @escaping @MainActor () -> Bool, then: @escaping @MainActor () -> Void) {
        cancel()
        let settle = StartFieldSettle(editor, draftOpen: draftOpen, then: then)
        current = settle
        settle.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak settle] event in
            if event.keyCode == VirtualKey.escape { MainActor.assumeIsolated { settle?.escapeWentThrough() } }
            return event
        }
        settle.lookLater()
    }

    /// The wait going on stopped, its `then` never run: a newer ask for step 3's keys, or the window closed.
    static func cancel() { current?.stop() }

    /// Whether the Escapes are handled (above). `draftOpen`: the input method has something open now. Each `since…` is
    /// the time since it came: `sinceChange` the field's text last changed (or the watch began), `sinceEscape` an
    /// Escape's key up came to the app (nil: none yet), `sinceDraftEnded` a draft or panel seen open ended (nil: none).
    static func settled(start: String, now: String, draftOpen: Bool, sinceChange: TimeInterval, sinceEscape: TimeInterval?,
                        sinceDraftEnded: TimeInterval?, elapsed: TimeInterval) -> Bool {
        if elapsed >= limit { return true }
        guard !draftOpen else { return false }
        // The first sign the Escapes went through; the text changing is one, and its last change the quiet's start.
        guard let through = [sinceEscape, sinceDraftEnded, now != start ? sinceChange : nil].compactMap({ $0 }).max() else {
            return false
        }
        return min(through, sinceChange) >= quiet
    }

    /// An Escape's key up dequeued: its key down went through the field (and the input method's context) before it.
    private func escapeWentThrough() {
        if escapeAt == nil { escapeAt = ProcessInfo.processInfo.systemUptime }
    }

    private func lookLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.interval) { [self] in look() }
    }

    private func look() {
        guard Self.current === self else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let text = editor.string
        if text != last { (last, changed) = (text, now) }
        let open = draftOpen()
        // Ended as last seen: one opened again (a key posted before the Escapes, still on its way) ends anew.
        if open {
            (draftSeen, draftEndedAt) = (true, nil)
        } else if draftSeen, draftEndedAt == nil {
            draftEndedAt = now
        }
        guard Self.settled(start: start, now: text, draftOpen: open, sinceChange: now - changed,
                           sinceEscape: escapeAt.map { now - $0 }, sinceDraftEnded: draftEndedAt.map { now - $0 },
                           elapsed: now - began) else {
            lookLater()
            return
        }
        stop()
        then()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if Self.current === self { Self.current = nil }
    }
}

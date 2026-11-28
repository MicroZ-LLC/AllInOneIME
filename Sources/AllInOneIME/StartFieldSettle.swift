import AllInOneIMECore
import AppKit

/// Step 3's wait between the two Escapes an example's click posts first (`StartModel.strokes`) and the keys that type
/// the example. Esc in the @ list may put the draft's text in as typed (`Composer.handleOneAtKey`), and that comes back
/// from the input method (this process's own, through the field's input context) some time after the key is posted,
/// never during the click. So the field is emptied after it is in and before the example's first key goes out: emptied
/// sooner, the old "@…" lands in front of the example; later, the magic key arrives after the old text (and right after
/// a letter it is only text, no list: `Composer.continuesWord`). A fixed delay is too short on a busy Mac and slow on an
/// idle one, so the field itself is looked at, on the main queue every `interval` (nothing waits on the main thread):
///
/// - The draft the field showed has ended (no marked text left, and the field changed: its text put in as typed, or
///   given up): on at once. Nothing more comes of the Escapes: with no draft open the input method leaves the other one
///   to the window, where it does nothing (`StartWindow`), and it reaches the input method before the example's keys do.
/// - No draft shown in the field (none open, or a selection's, in the panel): once both Escapes have gone through this
///   app (their key ups seen by a local monitor, which keeps nothing from the field) and the field has then stayed as
///   it is for `quiet`, time for what the input method does after a key.
/// - A draft still shown (a command's result list taken back to its draft by the first Escape, the second one's answer
///   not back yet): only its end, as above, or `limit`. Going on sooner would empty the field before the draft's text
///   comes in; a draft the Escapes don't end is left as before this wait, and waiting changes nothing for it.
/// - At most `limit`: Escapes the key tap takes (`KeyGuard`, a panel shown with nothing marked) never reach the app.
@MainActor
final class StartFieldSettle {
    /// What is looked at: the field's text, marked text and all, and whether some of it is marked (a draft's).
    struct Field: Equatable {
        var text: String
        var marked: Bool
    }

    static let interval: TimeInterval = 0.02
    static let quiet: TimeInterval = 0.15
    static let limit: TimeInterval = 1.5

    /// The wait going on: an example clicked before it is over replaces it (its keys never go out), so that two clicks'
    /// keys never mix.
    private static var current: StartFieldSettle?

    private let editor: NSTextView
    private let escapes: Int
    private let then: @MainActor () -> Void
    private let start: Field
    private var last: Field
    private let began = ProcessInfo.processInfo.systemUptime
    private var changed: TimeInterval
    private var escapesSeen = 0
    private var escapesThrough: TimeInterval?
    private var monitor: Any?

    private init(_ editor: NSTextView, escapes: Int, then: @escaping @MainActor () -> Void) {
        self.editor = editor
        self.escapes = escapes
        self.then = then
        start = Self.field(editor)
        last = start
        changed = began
    }

    /// `editor` looked at for the `escapes` Escapes about to be posted, `then` run once they are handled (above). Called
    /// before they are posted: they come to this app no sooner than the main thread's next turn, so none goes by unseen.
    static func watch(_ editor: NSTextView, escapes: Int, then: @escaping @MainActor () -> Void) {
        current?.stop()
        let settle = StartFieldSettle(editor, escapes: escapes, then: then)
        current = settle
        settle.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak settle] event in
            if event.keyCode == VirtualKey.escape { MainActor.assumeIsolated { settle?.escapeWentThrough() } }
            return event
        }
        settle.lookLater()
    }

    /// Whether the Escapes are handled (above): `sinceEscapes` nil until both have gone through the app.
    static func settled(start: Field, now: Field, sinceChange: TimeInterval, sinceEscapes: TimeInterval?,
                        elapsed: TimeInterval) -> Bool {
        if !now.marked, now != start { return true }
        if elapsed >= limit { return true }
        guard let sinceEscapes, !now.marked else { return false }
        return min(sinceChange, sinceEscapes) >= quiet
    }

    private static func field(_ editor: NSTextView) -> Field { Field(text: editor.string, marked: editor.hasMarkedText()) }

    /// An Escape's key up dequeued: its key down went through the field (and the input method's context) before it.
    private func escapeWentThrough() {
        escapesSeen += 1
        if escapesSeen >= escapes, escapesThrough == nil { escapesThrough = ProcessInfo.processInfo.systemUptime }
    }

    private func lookLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.interval) { [self] in look() }
    }

    private func look() {
        guard Self.current === self else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let field = Self.field(editor)
        if field != last { (last, changed) = (field, now) }
        guard Self.settled(start: start, now: field, sinceChange: now - changed, sinceEscapes: escapesThrough.map { now - $0 },
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

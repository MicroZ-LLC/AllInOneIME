import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import InputMethodKit

extension AllInOneIMEInputController {
    /// The field is left, or the app ends the composition (`.commit`, `.blur`): a row marked during the key goes in, a
    /// result being typed out stops (its rest in with `insertingRest`), and what is composed and not yet confirmed goes,
    /// nothing of it in (#116).
    @MainActor
    func leaveField(_ event: SessionEvent, client target: IMKTextInput?, insertingRest: Bool) {
        commitRow()
        stopTyping(insertingRest: insertingRest)
        apply(session.handle(event).outputs, client: target)
    }

    /// The app cancelled the composition: nothing of it goes in, the draft and the panel go.
    override func cancelComposition() {
        MainActor.assumeIsolated {
            commitRow()
            stopTyping(insertingRest: false)
            apply(session.handle(.cancel).outputs, client: client())
        }
        super.cancelComposition()
    }

    /// A mouse down at the tap (`MouseDownTap`), before any app has it: what is marked is dropped, unless the click is on
    /// a window of ours (a candidate row picks it).
    @MainActor
    func mouseDownAtTap(_ event: CGEvent) {
        guard hasMarkedText else { return }
        let point = CompositionLeave.appKitPoint(event.location, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        let ours = NSApp.windows.filter { $0.isVisible && !$0.ignoresMouseEvents }.map(\.frame)
        guard CompositionLeave.mouseDownEnds(at: point, marked: hasMarkedText, ownWindows: ours) else { return }
        leaveOnMouseDown(client: nil, from: "the tap")
    }

    /// A click while something is marked (#116): the user is leaving it (another field, another app, a place in the same
    /// field). What is composed is dropped now, through the app's own field, before the app ends the marked text itself
    /// (Chromium commits it on the mouse down; NSTextField keeps it as text when another field takes the focus): as the
    /// app's commit (`leaveField`). Then the app is asked something back, so it has taken the change before it goes on to
    /// the click.
    @MainActor
    func leaveOnMouseDown(client sender: IMKTextInput?, from source: String) {
        guard hasMarkedText, let target = sender ?? client() else { return }
        log.notice("a mouse down (\(source, privacy: .public)) while composing: what is marked is dropped before the app has the click")
        leaveField(.commit, client: target, insertingRest: true)
        _ = target.markedRange()
    }
}

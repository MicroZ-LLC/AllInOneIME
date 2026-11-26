import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import InputMethodKit

extension AllInOneIMEInputController {
    /// The field is left, or the app ends the composition (`.commit`, `.blur`, `.pointerDown`): a row marked during the
    /// key goes in, a result being typed out stops (its rest in with `insertingRest`), and what is composed and not yet
    /// confirmed goes, nothing of it in (#116). A stop that settles later (`settleStop`) does so in the field typed into,
    /// its rest not typed once the field is left (`.blur`); one with keys typed meanwhile (`keysWhileStopping`) settles at
    /// once, so they go in before the field is left.
    @MainActor
    func leaveField(_ event: SessionEvent, client target: IMKTextInput?, insertingRest: Bool) {
        commitRow()
        // A stop still settling when the field is left drops its rest, whatever the stop asked (a click outside asks for
        // the rest in), and goes on settling by itself (`settleStop`, which takes its typo out a moment later): nothing
        // is put into the field at the moment it is left.
        if case .blur = event, stopsInsertingRest != nil, keysWhileStopping.isEmpty {
            stopsInsertingRest = false
        } else {
            stopTyping(insertingRest: insertingRest, waiting: keysWhileStopping.isEmpty)
        }
        apply(session.handle(event).outputs, client: target)
    }

    /// The app cancelled the composition: nothing of it goes in, the draft and the panel go (keys typed while a stop
    /// settles before it: `leaveField`).
    override func cancelComposition() {
        IMKRecorder.shared.event("cancelComposition")
        MainActor.assumeIsolated {
            commitRow()
            stopTyping(insertingRest: false, waiting: keysWhileStopping.isEmpty)
            apply(session.handle(.cancel).outputs, client: client())
        }
        super.cancelComposition()
    }

    /// Mouse downs in other apps' windows, told to the field being typed in (`pointerOwner`, the key tap's) as
    /// `SessionEvent.pointerDown` (contract v1.4): nothing is marked in the field (`InputSession+Preedit.swift`), so no app
    /// tells the input method of a click, and a click (in this field, another one, another app) leaves what is being
    /// typed. A global monitor: it needs no Accessibility, and it never sees clicks on this process's own windows (a
    /// candidate row picks what it shows). Made once, with the key tap (`attachKeyGuard`: a field's activation, or its
    /// first key after the input method started again); not while the key tap is off (the self-test: the user's real
    /// clicks meanwhile are never its fake fields').
    @MainActor
    func watchPointerDowns() {
        guard !KeyGuard.shared.disabled else { return }
        Self.pointerOwner = self
        guard Self.pointerMonitor == nil else { return }
        Self.pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            MainActor.assumeIsolated { Self.pointerOwner?.pointerDown() }
        }
    }

    /// The monitor `watchPointerDowns` made, and the controller it tells now.
    @MainActor private static var pointerMonitor: Any?
    @MainActor static weak var pointerOwner: AllInOneIMEInputController?

    /// A mouse down outside our windows while this field is the one typed in (`watchPointerDowns`).
    @MainActor
    func pointerDown() {
        if composer.isComposing { log.notice("a mouse down while composing: what is being typed is dropped") }
        leaveField(.pointerDown, client: nil, insertingRest: true)
    }
}

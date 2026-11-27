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
        stopTyping(insertingRest: insertingRest, waiting: keysWhileStopping.isEmpty)
        if case .blur = event, stopsInsertingRest != nil { stopsInsertingRest = false }
        apply(session.handle(event).outputs, client: target)
    }

    /// `deactivateServer`: the field lost the focus without a click (a click came first, as `pointerDown`). What was
    /// being typed is kept for it by the session (#180: nothing of it in, the panel hidden) and comes back with the
    /// focus (`takeFocus`), unless another field has the focus already: then it goes, as it does once one takes it.
    /// Another input source selected (ABC) is leaving what is typed, not the field losing the focus (the owner,
    /// 2026-11-15): nothing of it stays, whether or not the system had it committed first.
    @MainActor
    func leaveFocus(client: IMKTextInput?) {
        leaveField(.blur, client: client, insertingRest: false)
        guard session.keepsDraft else { return }
        if let other = Self.activeController, other !== self { return dropKeptDraft("another field has the focus") }
        if InputSourceRegistrar.currentSourceID() != InputSourceRegistrar.sourceID { return dropKeptDraft("another input source") }
        Self.draftKeeper = self
        Self.keptDraftCaret = client?.selectedRange()
        log.notice("the focus lost while composing: what is being typed is kept for the field")
    }

    /// `activateServer`: the session is told the field took the focus. A draft kept for a field (`leaveFocus`) comes
    /// back in that field only: another controller's field drops it, and so does another field of this one's client
    /// (a page's fields share one), told by the caret, which is where it was left in the same field (nothing typed went
    /// in). A client that tells no caret can't tell its fields apart: the draft comes back there.
    @MainActor
    func takeFocus(_ field: FieldInfo, client: IMKTextInput?) {
        if let keeper = Self.draftKeeper, keeper !== self { keeper.dropKeptDraft("another field took the focus") }
        if session.keepsDraft, let left = Self.keptDraftCaret, let now = client?.selectedRange(),
           left.location != NSNotFound, now.location != NSNotFound, !NSEqualRanges(left, now) {
            dropKeptDraft("the caret is elsewhere: another field of the app")
        }
        (Self.draftKeeper, Self.keptDraftCaret) = (nil, nil)
        apply(session.handle(.focus(field)).outputs, client: client)
    }

    /// The draft kept for this controller's field goes, nothing of it in (`SessionEvent.cancel`).
    @MainActor
    private func dropKeptDraft(_ why: StaticString) {
        guard session.keepsDraft else { return }
        log.notice("the kept draft is dropped (\(why, privacy: .public))")
        apply(session.handle(.cancel).outputs, client: nil)
    }

    /// The controller whose session keeps a draft for the field it left, and that field's caret as it was left.
    @MainActor private static weak var draftKeeper: AllInOneIMEInputController?
    @MainActor private static var keptDraftCaret: NSRange?

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

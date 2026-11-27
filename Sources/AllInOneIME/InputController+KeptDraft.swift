import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Carbon
import InputMethodKit

// A draft kept for the field that lost the focus without a click (#180, the core's InputSession+KeptDraft.swift), as
// the Mac tells whether the field taking the focus is that one. A different controller's never is. The same
// controller's (a page's fields share one, and so do a window's text fields) only where Accessibility tells the same
// element, a text field or area, has the focus as when the draft was started, with the caret where it was left; where
// that can't be told (Accessibility not allowed, the element not a text field: a page whose app doesn't tell its
// fields), the draft goes, as before #180, rather than show in another field. Never in a password field or while
// secure input is on. It goes too when another input source is selected, the screen locks or sleeps, and after ten
// minutes (the owner, 2026-11-26, after the review of PR #188).

extension AllInOneIMEInputController {
    /// `deactivateServer`: the field lost the focus without a click (a click came first, as `pointerDown`). What was
    /// being typed is kept for it by the session (nothing of it in, the panel hidden) and comes back with the focus
    /// (`takeFocus`), unless another field has the focus already or the field can't be told again: then it goes.
    /// Another input source selected (ABC) is leaving what is typed, not the field losing the focus (the owner,
    /// 2026-11-15): nothing of it stays, whether or not the system had it committed first. Told a second time for the
    /// same draft (the client gone by then), it changes nothing of what was kept the first time.
    @MainActor
    func leaveFocus(client: IMKTextInput?) {
        let keeper = DraftKeeper.shared
        let keptBefore = session.keepsDraft && keeper.owner === self
        leaveField(.blur, client: client, insertingRest: false)
        keeper.verifying += 1  // what was asked for the focus it had is no longer waited for
        guard session.keepsDraft, !keptBefore else { return }
        if let other = Self.activeController, other !== self { return dropKeptDraft("another field has the focus") }
        if !keeper.readers.sourceIsOurs() { return dropKeptDraft("another input source") }
        guard let element = keeper.elementTypedIn(by: self) else { return dropKeptDraft("the field can't be told again") }
        keeper.keep(for: self, element: element, caret: client?.selectedRange())
        log.notice("the focus lost while composing: what is being typed is kept for the field")
    }

    /// `activateServer`: the session is told the field took the focus. A draft kept for a field (`leaveFocus`) comes
    /// back in that field only: another controller's field drops it; this one's holds it (`InputSession.holdKeptDraft`)
    /// until Accessibility told which element has the focus (`DraftKeeper.verify`, off the main thread), and never
    /// with the caret elsewhere or while secure input is on.
    @MainActor
    func takeFocus(_ field: FieldInfo, client: IMKTextInput?) {
        let keeper = DraftKeeper.shared
        if let owner = keeper.owner, owner !== self { owner.dropKeptDraft("another field took the focus") }
        if session.keepsDraft {
            if keeper.owner !== self || keeper.element == nil {
                dropKeptDraft("the field can't be told again")
            } else if services.secureInputActive() {
                dropKeptDraft("secure input is on")
            } else if let left = keeper.caret, let now = client?.selectedRange(), left.location != NSNotFound,
                      now.location != NSNotFound, !NSEqualRanges(left, now) {
                dropKeptDraft("the caret is elsewhere: another field of the app")
            } else {
                session.holdKeptDraft()
                keeper.verify(self, client: client)
            }
        }
        apply(session.handle(.focus(field)).outputs, client: client)
    }

    /// The draft kept for this controller's field goes, nothing of it in (`SessionEvent.cancel`), and nothing of it is
    /// remembered.
    @MainActor
    func dropKeptDraft(_ why: StaticString) {
        if DraftKeeper.shared.owner === self { DraftKeeper.shared.forget() }
        guard session.keepsDraft else { return }
        log.notice("the kept draft is dropped (\(why, privacy: .public))")
        apply(session.handle(.cancel).outputs, client: nil)
    }

    /// The field Accessibility told to be the one left: the panel and the draft as they were (`InputSession.releaseKeptDraft`).
    @MainActor
    func showKeptDraft(client: IMKTextInput?) {
        log.notice("back in the field: the kept draft shows again")
        apply(session.releaseKeptDraft(), client: client)
    }

    /// A key started a draft (`handleNewKeyDown`): which element has the focus is asked now, while the field is typed
    /// in, for telling it again should it lose the focus (`DraftKeeper.typedIn`). Never for the self-test's fields (it
    /// would read the user's own frontmost app).
    @MainActor
    func draftStarted() {
        guard clientOverride == nil else { return }
        DraftKeeper.shared.typedIn(by: self)
    }

    @MainActor
    func hidePanelIfOwned() {
        let panel = CandidatePanel.shared
        if panel.owner == nil || panel.owner === self {
            panel.hide()
        }
    }
}

/// Which element has the focus, as Accessibility tells it (`FocusedField.identity`): one field told from another of the
/// same app. `secure`: a password field.
struct FieldIdentity: Equatable, @unchecked Sendable {
    /// An `AXUIElement` (a test's: any CF value), compared as Core Foundation compares them.
    let element: CFTypeRef
    var secure = false

    static func == (a: FieldIdentity, b: FieldIdentity) -> Bool { CFEqual(a.element, b.element) }
}

/// What keeping a draft asks of this Mac, or of a test: the element with the focus (off the main thread: it may wait on
/// an app), whether the input source selected is this input method's, and where the system tells every process of
/// the screen locked and of another input source selected.
struct DraftKeeperReaders {
    var identity: @Sendable () -> FieldIdentity? = { FocusedField.identity() }
    var sourceIsOurs: @MainActor () -> Bool = { InputSourceRegistrar.currentSourceID() == InputSourceRegistrar.sourceID }
    var distributed: NotificationCenter = DistributedNotificationCenter.default()
}

/// The one draft kept for a field that lost the focus (`AllInOneIMEInputController.leaveFocus`): whose it is, the
/// element and the caret it was left in, and what ends it without the field (`watch`, `life`).
@MainActor
final class DraftKeeper {
    static let shared = DraftKeeper()

    var readers = DraftKeeperReaders()
    /// How long a draft is kept, as the session has it (`InputSession.keptDraftLife`); how long after the focus the
    /// element is asked (the app in front and its focused element settle after the input method is told).
    var life = InputSession.keptDraftLife
    var settle: TimeInterval = 0.1

    /// The controller whose session keeps a draft, the element its field is and the caret as it was left.
    private(set) weak var owner: AllInOneIMEInputController?
    private(set) var element: FieldIdentity?
    private(set) var caret: NSRange?
    /// Counts what ends a wait for the element with the focus (`verify`): an answer for an earlier one is dropped.
    var verifying = 0
    /// The element told while a draft was started: by which controller, in which of its activations.
    private var typing: (by: WeakBox<AllInOneIMEInputController>, session: Int, element: FieldIdentity?)?
    private var expiry: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    /// A draft started in `controller`'s field: the element with the focus is asked, off the main thread, and kept if
    /// the field is still the one typed in when it is told.
    func typedIn(by controller: AllInOneIMEInputController) {
        let (box, session, read) = (WeakBox(controller), controller.fieldSession, readers.identity)
        typing = (box, session, nil)
        DispatchQueue.global(qos: .userInitiated).async {
            let element = read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let controller = box.value, controller.fieldSession == session,
                          let typing = self.typing, typing.by === box else { return }
                    self.typing?.element = element
                }
            }
        }
    }

    /// The element `controller`'s field was told to be while what it composes was started, in this activation of it.
    /// Nil: not told (yet), no text field, a password field.
    func elementTypedIn(by controller: AllInOneIMEInputController) -> FieldIdentity? {
        guard let typing, typing.by.value === controller, typing.session == controller.fieldSession,
              typing.element?.secure == false else { return nil }
        return typing.element
    }

    /// `controller`'s session keeps a draft for the field `element` is, left with `caret`: until it is back there, or
    /// `life` went by. A draft another controller still kept goes.
    func keep(for controller: AllInOneIMEInputController, element: FieldIdentity, caret: NSRange?) {
        if let owner, owner !== controller { owner.dropKeptDraft("another field keeps a draft") }
        (owner, self.element, self.caret) = (controller, element, caret)
        watch()
        expiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.drop("kept longer than ten minutes") } }
        self.expiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + life, execute: expiry)
    }

    /// Nothing is kept any more (the draft came back, or went).
    func forget() {
        (owner, element, caret) = (nil, nil, nil)
        verifying += 1
        expiry?.cancel()
        expiry = nil
    }

    /// The draft kept goes, whichever field has it.
    func drop(_ why: StaticString) {
        owner?.dropKeptDraft(why)
        forget()
    }

    /// `controller`'s field took the focus with its draft held: the element with the focus is asked once the focus
    /// settled, off the main thread, and the draft shows if it is the one it was kept for, no password field, with
    /// secure input still off; else it goes. Not once the field was left again or the draft went meanwhile.
    func verify(_ controller: AllInOneIMEInputController, client: IMKTextInput?) {
        verifying += 1
        let (token, box, held, read) = (verifying, WeakBox(controller), MainThreadBox(client), readers.identity)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + settle) {
            let now = read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard token == self.verifying, let controller = box.value, self.owner === controller else { return }
                    guard controller.session.keepsDraft else { return self.forget() }
                    guard let now, now == self.element, !now.secure, !controller.services.secureInputActive() else {
                        return controller.dropKeptDraft("another element has the focus, or none told")
                    }
                    self.forget()
                    // Typed in again, in this activation: told as the same field should it lose the focus again.
                    self.typing = (box, controller.fieldSession, now)
                    controller.showKeptDraft(client: held.value)
                }
            }
        }
    }

    /// What ends a kept draft without its field, watched from the first one kept: another input source selected (any),
    /// the session switched away from, the screen locked, the displays or the Mac asleep.
    private func watch() {
        guard observers.isEmpty else { return }
        let drop: @Sendable (StaticString) -> @Sendable (Notification) -> Void = { why in
            { _ in MainActor.assumeIsolated { DraftKeeper.shared.drop(why) } }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.willSleepNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main, using: drop("the screen or the Mac sleeps")))
        }
        let distributed = readers.distributed
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main,
                                                 using: drop("the screen locked")))
        observers.append(distributed.addObserver(forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                                                 object: nil, queue: .main, using: drop("another input source selected")))
    }
}

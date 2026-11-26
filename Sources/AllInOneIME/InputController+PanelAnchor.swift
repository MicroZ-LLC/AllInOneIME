import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import InputMethodKit

/// The candidate panel asked of the field again after it told no rect to trust, and kept clear of autocomplete's gray
/// text. Asking the field waits on its app over XPC, running the run loop, so a key can be handled inside the call: what
/// it reads and writes (`panelAnchor`) is copied, never held open across the field's answer (a crash, 2026-11-22).
extension AllInOneIMEInputController {
    /// Each app's last panel rect to trust, whatever its field (`anchor`: the fallback where a field has none yet).
    @MainActor static var lastAnchorByApp: [String: NSRect] = [:]

    /// `model` shown in the panel at its place in `client` (`anchor`), unless the panel changed while the field was asked
    /// where that is (a key handled meanwhile showed it anew, or hid it): what that key left is newer. False: not shown.
    /// `keepingUnchanged`: not shown again where it already shows the same, there (nothing moves).
    @MainActor @discardableResult
    func show(_ model: PanelModel, anchoredIn client: IMKTextInput, keepingUnchanged: Bool = false) -> Bool {
        let panel = CandidatePanel.shared
        let (placed, showing, shown, owner) = (placements, panel.isShowing, panel.view.model, panel.owner)
        let rect = anchor(client)
        guard placements == placed + 1, panel.isShowing == showing, panel.view.model == shown, panel.owner === owner else {
            return false
        }
        if !keepingUnchanged || !panel.shows(model, anchor: rect) { panel.show(model, anchor: rect) }
        return true
    }

    /// The field asked again for the panel's rect (`PanelAnchor.reaskDelays`) after it told none to trust: the panel
    /// moves there once it tells one. Not after a key, the panel placed anew or hidden, the field left.
    @MainActor
    func reaskAnchor(_ client: IMKTextInput) {
        let token = anchorToken
        for (index, delay) in PanelAnchor.reaskDelays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, token == self.anchorToken else { return }
                let panel = CandidatePanel.shared
                guard panel.isShowing, panel.owner === self else { return }
                guard let (found, told) = self.reasked(client, token: token) else { return }
                guard let rect = found else {
                    if index == PanelAnchor.reaskDelays.count - 1 {
                        log.debug("panel anchor: still not trusted \(Int(delay * 1000)) ms later, told \(Self.describe(told), privacy: .public)")
                    }
                    return
                }
                self.anchorToken += 1  // found: not asked again
                self.anchorSaid = nil
                log.notice("panel anchor: trusted \(Int(delay * 1000)) ms later, \(Self.describe(rect), privacy: .public); the panel moved there")
                let model = panel.view.model
                if !panel.shows(model, anchor: rect) { panel.show(model, anchor: rect) }
                self.hideGhostBehindRows()
            }
        }
    }

    /// The field asked again once (`reaskAnchor`) for the panel's rect, unless a key or a new placement came since
    /// `token`: the rect to move the panel to (nil: it stays), and the rect it went by.
    @MainActor
    func reasked(_ client: IMKTextInput, token: Int) -> (rect: CGRect?, told: CGRect)? {
        guard token == anchorToken else { return nil }
        // The caret's rect, which the field is really asked for each time (`FieldAnchor.reasked`), with a copy of
        // `panelAnchor`: the field's answer runs the run loop, and a key handled meanwhile places the panel anew.
        var memory = panelAnchor
        let found = FieldAnchor.reasked(in: client, selection: composer.selection?.range, memory: &memory,
                                        screens: NSScreen.screens.map(\.frame))
        guard token == anchorToken else { return nil }
        panelAnchor = memory
        return found
    }

    /// Rows hold the caret (spec 0): autocomplete's gray text, still up where they are now (its placing waits a moment),
    /// goes, as the session ends it. Never a window of ours behind the rows.
    @MainActor
    func hideGhostBehindRows() {
        let panel = CandidatePanel.shared
        if !panel.view.model.rows.isEmpty, GhostOverlay.shared.isVisible, GhostOverlay.shared.frame.intersects(panel.frame) {
            GhostOverlay.shared.hide()
        }
    }

    /// The rect `client` tells for a panel (`FieldAnchor.told`): its marked text's line; for a command on the selection,
    /// the selection's last character (nothing is marked to go by).
    @MainActor
    func toldAnchor(_ client: IMKTextInput) -> NSRect {
        FieldAnchor.told(client, selection: composer.selection?.range)
    }

    /// What Accessibility tells of the caret in `app`, the field's app (`FocusedField.caret`; the page's frame till it is
    /// known), for `anchor`: never read with the key (an app slow to answer would hold typing up), but off the main thread,
    /// and the panel placed again once it is in (`placeAgain`); meanwhile the last one read in this field, or none. Never
    /// during secure input or in a password field, never for the self-test's fields (it would read the user's own
    /// frontmost app).
    @MainActor
    func accessibilityCaret(in app: String?, page: Bool, field: PanelAnchor.Field, client: IMKTextInput) -> PanelAnchor.Accessibility? {
        if anchorReads.fresh, anchorReads.field == field {
            anchorReads.fresh = false
            return anchorReads.caret
        }
        // The app in front asked here, on the main thread: `app` not the one in front, nothing to read.
        if anchorReads.reading != field, clientOverride == nil, !session.secureInputActive(), let app,
           let pid = PageContextReader.runningPID(app) {
            anchorReads.reading = field
            let (box, held, top) = (WeakBox(self), MainThreadBox(client), FocusedField.screenTop)
            DispatchQueue.global(qos: .userInitiated).async {
                let read = FocusedField.caret(pid: pid, page: page, top: top)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self = box.value else { return }
                        if self.anchorReads.reading == field { self.anchorReads.reading = nil }
                        guard self.panelAnchor.field == field else { return }
                        self.anchorReads = AnchorReads(field: field, caret: read, fresh: true)
                        self.placeAgain(held.value)
                    }
                }
            }
        }
        return anchorReads.field == field ? anchorReads.caret : nil
    }

    /// The focused window's frame in `app`, for `anchor` (`PanelAnchor.Memory.learnWindow`): as the window server lists it,
    /// at once; else Accessibility's, read off the main thread, learned once it is in (`PanelAnchor.Memory.learned`) and
    /// the panel placed again by it. Nil meanwhile.
    @MainActor
    func windowFrame(in app: String, for field: PanelAnchor.Field, client: IMKTextInput) -> (frame: CGRect?, timedOut: Bool)? {
        if let listed = FocusedField.listedWindowFrame(in: app) { return (listed, false) }
        guard let pid = PageContextReader.runningPID(app) else { return nil }  // not the app in front: nothing to read
        let (box, held, top) = (WeakBox(self), MainThreadBox(client), FocusedField.screenTop)
        DispatchQueue.global(qos: .userInitiated).async {
            let told = FocusedField.windowFrame(pid: pid, top: top)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self = box.value, let told, self.panelAnchor.field == field else { return }
                    self.panelAnchor.learned(window: told)
                    self.placeAgain(held.value)
                }
            }
        }
        return nil
    }

    /// The panel this field shows placed again (`show`), now that Accessibility told more of where it goes.
    @MainActor
    func placeAgain(_ client: IMKTextInput) {
        let panel = CandidatePanel.shared
        guard panel.isShowing, panel.owner === self else { return }
        show(panel.view.model, anchoredIn: client, keepingUnchanged: true)
    }
}

/// What Accessibility told of the caret in a field (`field`; nil: not asked yet), read off the main thread for the panel's
/// anchor (`accessibilityCaret`): `fresh` until a placement went by it; and the field it is being read in now.
struct AnchorReads {
    var field: PanelAnchor.Field?
    var caret: PanelAnchor.Accessibility?
    var fresh = false
    var reading: PanelAnchor.Field?
}

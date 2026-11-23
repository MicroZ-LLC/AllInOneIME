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
    /// known): never during secure input or in a password field, never for the self-test's fields (it would read the
    /// user's own frontmost app).
    @MainActor
    func caretByAccessibility(in app: String?, page: Bool) -> PanelAnchor.Accessibility? {
        guard clientOverride == nil, !session.secureInputActive(), let app else { return nil }
        return FocusedField.caret(in: app, page: page)
    }
}

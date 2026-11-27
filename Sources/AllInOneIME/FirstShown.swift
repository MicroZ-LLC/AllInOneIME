import AllInOneIMEMac
import Foundation

// What a launch shows first, of its own. Moved to this system identity (from a version before it, by its update or the
// installer): macOS asks again for the permissions it keeps by bundle ID. Said once: About, its update row saying which
// (`UpdateText.moved`), with Troubleshoot outlined, which lists those still to allow, once the input method has started.
// Its input source not added yet (macOS leaves that to the user; nothing of AllInOneIME types until then): About from its
// top, that step the first thing shown (`InputSourceStepSection`; a settings window asked for at launch, or by a reopen
// before it is decided, opens on it too: `whenFirstShown`), and Troubleshoot outlined once it is added. Which of the two
// waits for the first look at the input source (`InputSourceStatus.whenKnown`, which never holds the main thread); any
// other launch is decided at once.

extension UpdateController {
    /// At launch (`start`), after `result`, what the last update did (nil: none).
    func decideFirstShown(after result: UpdateResult?) {
        guard let result, SystemIdentity.moved(result) else { return decided(.nothing) }
        InputSourceStatus.shared.whenKnown { [weak self] enabled in
            self?.decided(SystemIdentity.firstShown(after: result, inputSourceEnabled: enabled))
        }
    }

    /// `body` with what this launch shows first: now if it is decided, else once it is.
    func whenFirstShown(_ body: @escaping (SystemIdentity.FirstShown) -> Void) {
        guard let firstShown else { return waitingForFirstShown.append(body) }
        body(firstShown)
    }

    /// The input method opened again (the AllInOneIME Settings app does that): the settings window. Before this launch
    /// has decided what it shows first (right after the move, the first look at the input source hasn't answered), once
    /// it has, and not over the step, which shows About itself: no other page before it. Decided, at once, every time.
    func settingsReopened() {
        guard firstShown == nil else { return SettingsWindow.shared.show() }
        whenFirstShown { first in
            if first != .inputSourceStep { SettingsWindow.shared.show() }
        }
    }

    private func decided(_ first: SystemIdentity.FirstShown) {
        firstShown = first
        switch first {
        case .nothing:
            break
        case .inputSourceStep:
            log.notice("moved to this system identity: About shows the step to add the input source first, then the permissions")
            DispatchQueue.main.async { SettingsWindow.shared.show(page: .about) }
            InputSourceStatus.shared.whenAdded = { SettingsWindow.shared.show(page: .about, spot: .troubleshoot) }
        case .permissions:
            log.notice("moved to this system identity: the permissions are told on the About page")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SettingsWindow.shared.show(page: .about, spot: .troubleshoot) }
        }
        let waiting = waitingForFirstShown
        waitingForFirstShown = []
        for body in waiting { body(first) }
    }
}

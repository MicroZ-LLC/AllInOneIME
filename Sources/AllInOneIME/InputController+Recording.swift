import AllInOneIMEMac
import AppKit
import InputMethodKit

/// The keys' IMK entry points, and the field's client as the controller asks it: IMK's own, or, while a developer
/// records the calls made of it (`IMKRecorder`, off unless `ALLINONEIME_IMK_RECORD` is set when the input method
/// starts), a proxy that records each call and its answer, with the key or change it came in.
extension AllInOneIMEInputController {
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        let recorder = IMKRecorder.shared
        guard recorder.isOn else { return handleEvent(event, client: sender as? IMKTextInput) }
        recorder.event(event)
        let handled = MainActor.assumeIsolated { handleEvent(event, client: recorder.recording(sender: sender)) }
        recorder.event(event, handled: handled)
        return handled
    }

    private func handleEvent(_ event: NSEvent, client: IMKTextInput?) -> Bool {
        switch event.type {
        case .keyDown:
            return MainActor.assumeIsolated { handleKeyDown(event, client: client) }
        case .flagsChanged:
            MainActor.assumeIsolated { handleFlagsChanged(event, client: client) }
            return false  // the application must see modifier changes too
        default:
            return false
        }
    }

    /// IMK's client, through the recorder's proxy while it records: every call the controller makes of the field
    /// recorded, wherever it asks for the client (its outputs after a key, a timer's, the session's work's).
    override func client() -> (any IMKTextInput & NSObjectProtocol)! {
        let client = super.client()
        guard IMKRecorder.shared.isOn else { return client }
        return MainActor.assumeIsolated { IMKRecorder.shared.recording(client) }
    }
}

import AppKit
import ApplicationServices
import os

/// Keys a panel of ours takes are kept from every app (0.6.8.1, the owner: "所有 app 都应该进行拦截，输入优先级最高"). An
/// input method is handed a key through the app, and only tells it whether it took it: AppKit's and WebKit's fields
/// honor that, but Chromium's pages, terminals and other toolkits act on a key the input method took unless marked text
/// is in the field during it. While nothing is marked, suggestion rows and clipboard history's panel take keys (↓ ↑ →
/// Esc ⏎ Tab, ⌃V opening the panel), so those keys went to Slack's page and to the shell.
///
/// So the keys are taken before any app sees them: a session event tap (`CGEvent.tapCreate`), on while this input
/// method is the one in use (`AllInOneIMEInputController.activeController`), hands each key down to the input
/// controller itself (`keyAtTap`) while a panel shows with nothing marked, and ⌃V always; the key goes no further when
/// the controller took it (and its key up neither), and on as usual when it didn't (the controller answers the same key
/// handed over again by the app as it did here: `KeyEchoes`). Every app, whatever it's built with, the same.
///
/// The tap is on only while this input method is in use (a field of its own attached): with another input method no key
/// of any app waits on this process.
///
/// The tap needs the Accessibility permission (as terminal paste does). Without it there is none, and what keeps the
/// keys is the marked text of 0.6.7.3 and 0.6.8.1 (Chromium and Electron apps: `ChromiumApps`; terminals:
/// `keepFromTerminal`). Keys we post ourselves (`TerminalPaste.marker`) pass untouched.
@MainActor
final class KeyGuard {
    static let shared = KeyGuard()
    private let log = Logger(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "KeyGuard")

    private var tap: CFMachPort?
    /// Keys whose key down the tap took: their key up is taken too.
    private var takenKeys: Set<Int64> = []
    /// Asked for each key down: nil, not one for the input method now (it goes on untouched); true, the input method took
    /// it (it goes no further); false, the input method had it and left it to the app.
    private var handler: ((NSEvent) -> Bool?)?
    private var saidUntrusted = false
    private weak var owner: AnyObject?

    /// Whether keys are taken at the tap now (the permission given and the tap made).
    var isOn: Bool { tap != nil && handler != nil }

    /// Off for the self-test: its controller drives fake fields, and the user's real keys meanwhile are no keys for it.
    var disabled = false

    /// `owner`'s handler, from its field's activation: the tap made first if it isn't yet and Accessibility allows it.
    func attach(_ owner: AnyObject, handler: @escaping (NSEvent) -> Bool?) {
        guard !disabled else { return }
        self.owner = owner
        self.handler = handler
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) } else { makeTap() }
    }

    /// Whether `owner`'s handler is the one asked (a field typed in without an activation of its own first: the input
    /// method started again while the field had the focus, after an update).
    func isAttached(_ owner: AnyObject) -> Bool { disabled || self.owner === owner }

    /// `owner`'s handler gone (its field deactivated); another's, set since, stays.
    func detach(_ owner: AnyObject) {
        guard self.owner === owner else { return }
        self.owner = nil
        handler = nil
        takenKeys.removeAll()
        // Off while another input method (or none) is in use: no key of any app waits on this process then.
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    private func makeTap() {
        guard AXIsProcessTrusted() else {
            if !saidUntrusted {
                saidUntrusted = true
                log.notice("the key tap is off: Accessibility isn't allowed (keys a panel takes are kept from apps by marked text)")
            }
            return
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let made = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: keyGuardCallback, userInfo: nil) else {
            log.error("the key tap couldn't be made: keys a panel takes are kept from apps by marked text only")
            return
        }
        tap = made
        let source = CFMachPortCreateRunLoopSource(nil, made, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: made, enable: true)
        log.notice("the key tap is on: keys a panel takes are kept from every app")
    }

    /// Marked text had to keep a key from an app (a Chromium page, a terminal): the tap isn't on. Made now where
    /// Accessibility allows it (macOS may tell a process just started that it isn't allowed yet: the tap is tried again
    /// here, for the next key); else Accessibility asked for once, ever (macOS shows its own prompt then).
    func markedInstead() {
        guard !disabled, tap == nil, handler != nil else { return }
        if AXIsProcessTrusted() { makeTap(); return }
        let key = "keyGuardAskedForAccessibility"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        log.notice("Accessibility asked for, once: keys a panel takes are kept from apps by marked text until it's allowed")
    }

    /// The tap turned off by macOS (a callback too slow, or secure input's user input): on again, while it's wanted.
    fileprivate func reenable() {
        if let tap, handler != nil { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Whether the tap takes `event` (true: it goes no further).
    fileprivate func takes(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard let handler else { return false }
        if event.getIntegerValueField(.eventSourceUserData) == TerminalPaste.marker { return false }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp { return takenKeys.remove(code) != nil }
        guard type == .keyDown, let key = NSEvent(cgEvent: event), let took = handler(key) else { return false }
        if took { takenKeys.insert(code) }
        return took
    }
}

/// The tap's callback (a C function: no captures). It runs on the main run loop, where the tap's source is.
private let keyGuardCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { KeyGuard.shared.reenable() }
        return Unmanaged.passUnretained(event)
    }
    let taken = MainActor.assumeIsolated { KeyGuard.shared.takes(type, event) }
    return taken ? nil : Unmanaged.passUnretained(event)
}

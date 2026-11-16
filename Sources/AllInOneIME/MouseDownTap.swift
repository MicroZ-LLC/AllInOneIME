import AppKit
import ApplicationServices
import os

/// Mouse downs, told to the input method before any app has them (#116; the owner, 2026-11-15: leaving a field while
/// pinyin is typed leaves nothing of it there). Apps end the marked text themselves on a mouse down, before they tell
/// the input method anything: Chromium's view commits it on the spot (`finishComposingText`), NSTextField keeps it as
/// text when another field takes the focus, and no AppKit field hands the click over through IMK. So a session event
/// tap, its own (`KeyGuard`'s needs Accessibility for keys), listens for mouse downs while this input method is the one
/// in use and holds each until the input method has dropped what it marked (`CompositionLeave`); the click then goes on
/// to the app untouched. Without the tap (macOS refused it) the app keeps what it commits itself, and the input method
/// puts nothing in after it.
@MainActor
final class MouseDownTap {
    private let log = Logger(subsystem: "com.allinoneime.inputmethod.AllInOneIME", category: "KeyGuard")
    private var tap: CFMachPort?
    private var handler: ((CGEvent) -> Void)?
    private var saidRefused = false

    /// `handler` asked for each mouse down from now on, the tap made first if it isn't yet.
    func attach(_ handler: @escaping (CGEvent) -> Void) {
        self.handler = handler
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) } else { makeTap() }
    }

    /// Off while another input method (or none) is in use: no click of any app waits on this process then.
    func detach() {
        handler = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    private func makeTap() {
        let mask = [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let made = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: mouseDownTapCallback, userInfo: refcon) else {
            if !saidRefused {
                saidRefused = true
                log.notice("the mouse tap couldn't be made: a click may leave the pinyin in apps that commit it themselves")
            }
            return
        }
        tap = made
        let source = CFMachPortCreateRunLoopSource(nil, made, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: made, enable: true)
        log.notice("the mouse tap is on (Accessibility \(AXIsProcessTrusted() ? "allowed" : "not allowed", privacy: .public))")
    }

    fileprivate func received(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, handler != nil { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        handler?(event)
    }
}

/// The tap's callback (a C function: no captures), on the main run loop, where the tap's source is. The event always goes
/// on.
private let mouseDownTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    if let refcon {
        let tap = Unmanaged<MouseDownTap>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { tap.received(type, event) }
    }
    return Unmanaged.passUnretained(event)
}

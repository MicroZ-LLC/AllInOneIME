import Carbon.HIToolbox
import Foundation
import IOKit
import IOKit.hidsystem

/// The Caps Lock key as the Mac has it (0.7.4: with Caps Lock the switch key, `Config.switchKey`, a press of it switches
/// the input language as a tap of Shift does). IMK hands the input method one modifier change when the lock goes on or
/// off, not the key's press and release; the lock its press turned on is turned off again through IOKit (no entitlement,
/// no permission).
enum CapsLockKey {
    static let keyCode = UInt16(kVK_CapsLock)

    /// Turns the lock off and keeps it off for `keptOff`: macOS sometimes drops a lock turned off just as it turned the
    /// lock on (the key released within those milliseconds: seen on the owner's iMac, about one fast press in thirty,
    /// with no error), leaving capitals on until the next press. Checked every `checkEvery`, turned off again while on.
    /// A new press within that time turns the lock on and its change still reaches the session, whose switch turns it off
    /// and starts this again.
    @MainActor
    static func keepOff() {
        setLock(false)
        keeping?.invalidate()
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: checkEvery, repeats: true) { timer in
            MainActor.assumeIsolated {
                if isOn() {
                    log.notice("Caps Lock: on again after it was turned off, turned off again")
                    setLock(false)
                }
                if ProcessInfo.processInfo.systemUptime - started > keptOff {
                    timer.invalidate()
                    if keeping === timer { keeping = nil }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        keeping = timer
    }

    static let keptOff: TimeInterval = 1
    static let checkEvery: TimeInterval = 0.015
    @MainActor private static var keeping: Timer?

    /// Whether the lock is on, as IOHIDSystem keeps it.
    static func isOn() -> Bool {
        withConnection { connect in
            var on = false
            return IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &on) == KERN_SUCCESS && on
        } ?? false
    }

    private static func withConnection<T>(_ body: (io_connect_t) -> T) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(connect) }
        return body(connect)
    }

    /// Turns the lock (its light, capitals) on or off, as IOHIDSystem keeps it; logged if it can't be.
    static func setLock(_ on: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != IO_OBJECT_NULL else {
            log.error("Caps Lock: no IOHIDSystem service, its lock left as it is")
            return
        }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        let opened = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect)
        guard opened == KERN_SUCCESS else {
            log.error("Caps Lock: IOHIDSystem not opened (\(opened, privacy: .public)), its lock left as it is")
            return
        }
        defer { IOServiceClose(connect) }
        let set = IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), on)
        if set != KERN_SUCCESS {
            log.error("Caps Lock: its lock not turned \(on ? "on" : "off", privacy: .public) (\(set, privacy: .public))")
        }
    }
}

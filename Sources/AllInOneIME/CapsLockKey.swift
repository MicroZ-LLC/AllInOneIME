import Carbon.HIToolbox
import IOKit
import IOKit.hidsystem

/// The Caps Lock key as the Mac has it (0.7.4: with Caps Lock the switch key, `Config.switchKey`, a press of it switches
/// the input language as a tap of Shift does). IMK hands the input method one modifier change when the lock goes on or
/// off, not the key's press and release; the lock its press turned on is turned off again through IOKit (no entitlement,
/// no permission).
enum CapsLockKey {
    static let keyCode = UInt16(kVK_CapsLock)

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

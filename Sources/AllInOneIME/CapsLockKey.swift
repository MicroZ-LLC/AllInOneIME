import Carbon.HIToolbox
import CoreGraphics
import IOKit
import IOKit.hidsystem

/// The Caps Lock key as the Mac has it (0.7.4: a tap of it switches Chinese and English, as a tap of Shift does). IMK
/// hands the input method one modifier change when the lock goes on or off, not the key's press and release: whether the
/// key is down is asked of the HID system, and its lock turned off again through IOKit (no entitlement, no permission).
enum CapsLockKey {
    static let keyCode = UInt16(kVK_CapsLock)

    /// Whether Caps Lock is down now, as the HID system has it.
    static func isDown() -> Bool {
        CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode))
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

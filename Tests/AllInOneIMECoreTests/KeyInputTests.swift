import Testing
@testable import AllInOneIMECore

/// The key model (Session/KeyInput.swift). The usages are checked against the USB HID Usage Tables (1.12, page 7 "Keyboard/
/// Keypad"), the Mac codes against HIToolbox/Events.h, the Windows ones against Microsoft's "USB HID to PS/2 Scan Code
/// Translation Table" and Virtual-Key Codes reference; Chromium's dom_code_data.inc lists all three and agrees.
struct KeyInputTests {
    /// Every key code the code base names (`VirtualKey`, and F13–F20, which the action key's keys that type nothing had),
    /// its key and usage.
    static let namedCodes: [(UInt16, Key, UInt16)] = [
        (VirtualKey.returnKey, .enter, 0x28), (VirtualKey.keypadEnter, .keypadEnter, 0x58), (VirtualKey.tab, .tab, 0x2B),
        (VirtualKey.space, .space, 0x2C), (VirtualKey.delete, .backspace, 0x2A), (VirtualKey.escape, .escape, 0x29),
        (VirtualKey.forwardDelete, .forwardDelete, 0x4C), (VirtualKey.home, .home, 0x4A), (VirtualKey.end, .end, 0x4D),
        (VirtualKey.pageUp, .pageUp, 0x4B), (VirtualKey.pageDown, .pageDown, 0x4E),
        (VirtualKey.left, .arrow(.left), 0x50), (VirtualKey.right, .arrow(.right), 0x4F),
        (VirtualKey.down, .arrow(.down), 0x51), (VirtualKey.up, .arrow(.up), 0x52),
        (VirtualKey.leftShift, .modifier(.shift, .left), 0xE1), (VirtualKey.rightShift, .modifier(.shift, .right), 0xE5),
        (VirtualKey.leftOption, .modifier(.option, .left), 0xE2), (VirtualKey.rightOption, .modifier(.option, .right), 0xE6),
        (0x37, .modifier(.command, .left), 0xE3), (0x36, .modifier(.command, .right), 0xE7),
        (0x3B, .modifier(.control, .left), 0xE0), (0x3E, .modifier(.control, .right), 0xE4),
        (0x69, .f(13), 0x68), (0x6B, .f(14), 0x69), (0x71, .f(15), 0x6A), (0x6A, .f(16), 0x6B),
        (0x40, .f(17), 0x6C), (0x4F, .f(18), 0x6D), (0x50, .f(19), 0x6E), (0x5A, .f(20), 0x6F),
    ]

    @Test func everyNamedMacCodeRoundTrips() {
        for (code, key, usage) in Self.namedCodes {
            #expect(MacKeyCodes.key(code) == key, "kVK \(code)")
            #expect(MacKeyCodes.usage(code) == usage, "kVK \(code)")
            #expect(MacKeyCodes.code(usage: usage) == code, "usage \(usage)")
        }
        for (i, code) in VirtualKey.functionKeys.enumerated() {
            #expect(MacKeyCodes.key(code) == .f(i + 1))
            #expect(MacKeyCodes.usage(code) == 0x3A + UInt16(i))  // F1 … F12 are 0x3A … 0x45
            #expect(MacKeyCodes.code(usage: MacKeyCodes.usage(code)) == code)
        }
    }

    @Test func macTableIsOneToOne() {
        let codes = MacKeyCodes.entries.map(\.code)
        #expect(Set(codes).count == codes.count)
        let usages = MacKeyCodes.entries.map(\.usage).filter { $0 != 0 }
        #expect(Set(usages).count == usages.count)
        for entry in MacKeyCodes.entries where entry.usage != 0 {
            #expect(MacKeyCodes.code(usage: entry.usage) == entry.code)
        }
        #expect(MacKeyCodes.key(0x3F) == .function)  // fn: Apple's own usage page, none on page 7
        #expect(MacKeyCodes.usage(0x3F) == 0)
        #expect(MacKeyCodes.key(0x34) == .other)  // no such key
        #expect(MacKeyCodes.usage(0x34) == 0)
    }

    @Test func macLettersDigitsAndPunctuationAtTheirHIDUsages() {
        // HID: a … z are 0x04 … 0x1D, 1 … 9 0 are 0x1E … 0x27.
        let letters: [UInt16] = [0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E, 0x2D,
                                 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06]  // kVK_ANSI_A … Z
        for (i, code) in letters.enumerated() {
            #expect(MacKeyCodes.usage(code) == 0x04 + UInt16(i))
            #expect(MacKeyCodes.key(code) == .character)
        }
        let digits: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]  // kVK_ANSI_1 … 9, 0
        for (i, code) in digits.enumerated() { #expect(MacKeyCodes.usage(code) == 0x1E + UInt16(i)) }
        #expect(MacKeyCodes.usage(0x32) == 0x35)  // ` (Grave Accent and Tilde)
        #expect(MacKeyCodes.usage(0x0A) == 0x64)  // ISO § (Non-US \ and |)
        #expect(MacKeyCodes.usage(0x5D) == 0x89)  // JIS ¥ (International3)
        #expect(MacKeyCodes.usage(0x5E) == 0x87)  // JIS _ (International1)
        #expect(MacKeyCodes.usage(0x72) == 0x49)  // Help where Insert is
        #expect(MacKeyCodes.key(0x52) == .character)  // keypad 0 types
        #expect(MacKeyCodes.usage(0x52) == 0x62)
    }

    @Test func windowsScanCodes() {
        #expect(WindowsKeyCodes.usage(scanCode: 0x1E, extended: false) == 0x04)  // A
        #expect(WindowsKeyCodes.usage(scanCode: 0x2C, extended: false) == 0x1D)  // Z
        #expect(WindowsKeyCodes.usage(scanCode: 0x02, extended: false) == 0x1E)  // 1
        #expect(WindowsKeyCodes.usage(scanCode: 0x0B, extended: false) == 0x27)  // 0
        #expect(WindowsKeyCodes.usage(scanCode: 0x1C, extended: false) == 0x28)  // Enter
        #expect(WindowsKeyCodes.usage(scanCode: 0x1C, extended: true) == 0x58)  // keypad Enter
        #expect(WindowsKeyCodes.usage(scanCode: 0x48, extended: true) == 0x52)  // ↑
        #expect(WindowsKeyCodes.usage(scanCode: 0x48, extended: false) == 0x60)  // keypad 8
        #expect(WindowsKeyCodes.usage(scanCode: 0x53, extended: true) == 0x4C)  // Delete
        #expect(WindowsKeyCodes.usage(scanCode: 0x0E, extended: false) == 0x2A)  // Backspace
        #expect(WindowsKeyCodes.usage(scanCode: 0x3B, extended: false) == 0x3A)  // F1
        #expect(WindowsKeyCodes.usage(scanCode: 0x57, extended: false) == 0x44)  // F11
        #expect(WindowsKeyCodes.usage(scanCode: 0x64, extended: false) == 0x68)  // F13
        #expect(WindowsKeyCodes.usage(scanCode: 0x2A, extended: false) == 0xE1)  // left Shift
        #expect(WindowsKeyCodes.usage(scanCode: 0x36, extended: false) == 0xE5)  // right Shift
        #expect(WindowsKeyCodes.usage(scanCode: 0x1D, extended: true) == 0xE4)  // right Ctrl
        #expect(WindowsKeyCodes.usage(scanCode: 0x38, extended: true) == 0xE6)  // right Alt
        #expect(WindowsKeyCodes.usage(scanCode: 0x5B, extended: true) == 0xE3)  // left Windows key
        #expect(WindowsKeyCodes.usage(scanCode: 0x56, extended: false) == 0x64)  // ISO \
        #expect(WindowsKeyCodes.usage(scanCode: 0x7D, extended: false) == 0x89)  // JIS ¥
        #expect(WindowsKeyCodes.usage(scanCode: 0x5B, extended: false) == 0)  // not a key
        let usages = Array(WindowsKeyCodes.usageByScanCode.values)
        #expect(Set(usages).count == usages.count)
    }

    @Test func windowsVirtualKeys() {
        #expect(WindowsKeyCodes.key(virtualKey: 0x0D, usage: 0x28) == .enter)  // VK_RETURN
        #expect(WindowsKeyCodes.key(virtualKey: 0x0D, usage: 0x58) == .keypadEnter)
        #expect(WindowsKeyCodes.key(virtualKey: 0x08, usage: 0x2A) == .backspace)  // VK_BACK
        #expect(WindowsKeyCodes.key(virtualKey: 0x2E, usage: 0x4C) == .forwardDelete)  // VK_DELETE
        #expect(WindowsKeyCodes.key(virtualKey: 0x1B, usage: 0x29) == .escape)
        #expect(WindowsKeyCodes.key(virtualKey: 0x21, usage: 0x4B) == .pageUp)  // VK_PRIOR
        #expect(WindowsKeyCodes.key(virtualKey: 0x25, usage: 0x50) == .arrow(.left))
        #expect(WindowsKeyCodes.key(virtualKey: 0x28, usage: 0x51) == .arrow(.down))
        #expect(WindowsKeyCodes.key(virtualKey: 0x70, usage: 0x3A) == .f(1))  // VK_F1
        #expect(WindowsKeyCodes.key(virtualKey: 0x87, usage: 0x73) == .f(24))  // VK_F24
        #expect(WindowsKeyCodes.key(virtualKey: 0x10, usage: 0xE1) == .modifier(.shift, .left))  // VK_SHIFT
        #expect(WindowsKeyCodes.key(virtualKey: 0x10, usage: 0xE5) == .modifier(.shift, .right))
        #expect(WindowsKeyCodes.key(virtualKey: 0x12, usage: 0xE6) == .modifier(.option, .right))  // VK_MENU: right Alt
        #expect(WindowsKeyCodes.key(virtualKey: 0xA3, usage: 0xE4) == .modifier(.control, .right))  // VK_RCONTROL
        #expect(WindowsKeyCodes.key(virtualKey: 0x5B, usage: 0xE3) == .modifier(.command, .left))  // VK_LWIN
        #expect(WindowsKeyCodes.key(virtualKey: 0x41, usage: 0x04) == .character)  // A
        #expect(WindowsKeyCodes.key(virtualKey: 0x60, usage: 0x62) == .character)  // VK_NUMPAD0
        #expect(WindowsKeyCodes.key(virtualKey: 0xBA, usage: 0x33) == .character)  // VK_OEM_1
        #expect(WindowsKeyCodes.key(virtualKey: 0xE2, usage: 0x64) == .character)  // VK_OEM_102
        #expect(WindowsKeyCodes.key(virtualKey: 0x14, usage: 0x39) == .capsLock)
        #expect(WindowsKeyCodes.key(virtualKey: 0x2C, usage: 0x46) == .other)  // VK_SNAPSHOT
    }

    /// Every key of the Mac's is on a PC keyboard too: the usage is what the two systems' codes meet at.
    @Test func everyMacKeyHasAWindowsScanCode() {
        let windows = Set(WindowsKeyCodes.usageByScanCode.values)
        for entry in MacKeyCodes.entries where entry.usage != 0 {
            #expect(windows.contains(entry.usage), "kVK \(entry.code), usage \(entry.usage)")
        }
    }

    @Test func keyEventCarriesKeyAndUsage() {
        let enter = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r")
        #expect(enter.key == .enter)
        #expect(enter.usage == 0x28)
        var event = KeyEvent(keyCode: 0, characters: "a")
        #expect(event.key == .character)
        #expect(event.usage == 0x04)
        event.keyCode = VirtualKey.up  // follows the code
        #expect(event.key == .arrow(.up))
        #expect(event.usage == 0x52)
        // Another system's event: the Mac's code where the Mac has the key.
        let windows = KeyEvent(key: .enter, usage: 0x28, characters: "\r")
        #expect(windows.keyCode == VirtualKey.returnKey)
        #expect(windows == enter)
        #expect(KeyEvent(key: .other, usage: 0x46, characters: "").keyCode == KeyEvent.noKeyCode)  // Print Screen
    }

    @Test func modifierBitsAreUnchanged() {
        // In the config (`KeyShortcut.modifiers`): the old bits keep their values.
        #expect(KeyModifiers.shift.rawValue == 1)
        #expect(KeyModifiers.control.rawValue == 2)
        #expect(KeyModifiers.option.rawValue == 4)
        #expect(KeyModifiers.command.rawValue == 8)
        #expect(KeyModifiers.capsLock.rawValue == 16)
        #expect(KeyModifiers.leftOption.rawValue == 32)
        #expect(KeyModifiers.rightOption.rawValue == 64)
        #expect(KeyModifiers.function.rawValue == 128)
        #expect(Modifiers.side(.right, of: .option) == .rightOption)
        #expect(Modifiers.sides(of: .option) == [.leftOption, .rightOption])
        #expect(Modifiers.kind(.command) == .command)
        #expect(Modifiers.sides.isDisjoint(with: [.shift, .control, .option, .command, .capsLock, .function]))
    }

    @Test func macRoles() {
        #expect(ModifierRoles.mac.primary == .command)
        #expect(ModifierRoles.mac.voiceHold == .modifier(.option, .right))
        #expect(ModifierRoles.mac.actionTap == .option)
    }
}

import Testing
@testable import AllInOneIMECore

/// The key's place from the code macOS reports (`MacKeyboard`): an ISO keyboard's § and ` keys swapped, nothing else.
struct MacKeyboardTests {
    @Test func anISOKeyboardsTwoKeysAreSwapped() {
        // § left of 1 is reported as kVK_ISO_Section: its place is Grave's (0x35); the key next to the left Shift,
        // reported as kVK_ANSI_Grave, is at Non-US \ (0x64).
        #expect(MacKeyboard.usage(0x0A, iso: true) == 0x35)
        #expect(MacKeyboard.usage(0x32, iso: true) == 0x64)
        #expect(MacKeyboard.keyCode(usage: 0x35, iso: true) == 0x0A)
        #expect(MacKeyboard.keyCode(usage: 0x64, iso: true) == 0x32)
        // ANSI and JIS: the table's.
        #expect(MacKeyboard.usage(0x0A, iso: false) == 0x64 && MacKeyboard.usage(0x32, iso: false) == 0x35)
        for entry in MacKeyCodes.entries where entry.usage != 0 {
            #expect(MacKeyboard.usage(entry.code, iso: false) == entry.usage)
            #expect(MacKeyboard.keyCode(usage: entry.usage, iso: false) == entry.code)
            // Every other key is where the table has it on ISO too, and the swap goes back to the code reported.
            if entry.code != 0x0A, entry.code != 0x32 { #expect(MacKeyboard.usage(entry.code, iso: true) == entry.usage) }
            #expect(MacKeyboard.keyCode(usage: MacKeyboard.usage(entry.code, iso: true), iso: true) == entry.code)
        }
        #expect(MacKeyboard.keyCode(usage: 0x46, iso: true) == nil)  // Print Screen: no Mac key
    }

    /// The swap changes nothing the Mac does: neither key is a jamo or a key with its own handling, either way.
    @Test func theSwappedKeysTypeAsBefore() {
        for code: UInt16 in [0x0A, 0x32] {
            #expect(MacKeyCodes.key(code) == .character)
            #expect(PackData.hangul.jamo(keyCode: code, shift: false) == nil && PackData.hangul.jamo(keyCode: code, shift: true) == nil)
            for iso in [false, true] {
                let event = KeyEvent(keyCode: code, usage: MacKeyboard.usage(code, iso: iso), characters: "§")
                #expect(event.key == .character && event.keyCode == code)
                #expect(PackData.hangul.jamo(usage: event.usage, shift: false) == nil)
            }
        }
    }
}

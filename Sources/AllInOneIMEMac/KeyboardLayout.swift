import Carbon
import AllInOneIMECore

/// A keyboard layout's key table (`uchr`), dead keys included.
public struct KeyboardLayout: KeyTranslator, @unchecked Sendable {
    public let id: String
    private let data: CFData

    public init?(source: TISInputSource) {
        guard let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
              let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        id = Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String
        data = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue()
    }

    /// An installed layout by its input source ID ("com.apple.keylayout.French"), enabled or not.
    public init?(id: String) {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let source = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first
        else { return nil }
        self.init(source: source)
    }

    /// The layout the keys come from. Under an input method macOS uses the last ASCII-capable one the
    /// user had (AZERTY, QWERTZ, US International …; never Russian or Hindi, which can't type Latin letters).
    public static func current() -> KeyboardLayout? {
        for source in [TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentASCIICapableKeyboardLayoutInputSource()] {
            if let source = source?.takeRetainedValue(), let layout = KeyboardLayout(source: source) { return layout }
        }
        return nil
    }

    /// `translate(_:…)` by the key's usage (`KeyTranslator`): the key code macOS reports at that place on this keyboard
    /// (`MacKeyboard`); nothing where the Mac has no such key.
    public func translate(usage: UInt16, _ modifiers: KeyModifiers, state: inout UInt32, deadKeys: Bool) -> String {
        guard let keyCode = MacKeyboard.keyCode(usage: usage) else {
            state = 0
            return ""
        }
        return translate(keyCode, modifiers, state: &state, deadKeys: deadKeys)
    }

    /// What `keyCode` types with `modifiers` after the dead-key `state`, which becomes the state the key
    /// leaves (non-zero, with nothing typed: a dead key). Without `deadKeys` a dead key types its accent.
    public func translate(_ keyCode: UInt16, _ modifiers: KeyModifiers, state: inout UInt32, deadKeys: Bool = true) -> String {
        var carbon = 0
        if modifiers.contains(.shift) { carbon |= shiftKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.capsLock) { carbon |= alphaLock }
        if modifiers.contains(.control) { carbon |= controlKey }
        if modifiers.contains(.command) { carbon |= cmdKey }
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        let status = CFDataGetBytePtr(data).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), UInt32((carbon >> 8) & 0xFF), UInt32(LMGetKbdType()),
                           deadKeys ? 0 : OptionBits(kUCKeyTranslateNoDeadKeysMask), &state, chars.count, &length, &chars)
        }
        guard status == noErr else {
            state = 0
            return ""
        }
        return String(utf16CodeUnits: chars, count: length)
    }
}

/// Where a key is on this Mac's keyboard (its usage, `KeyEvent.usage`) from the key code macOS reports, and back. On
/// Apple's ISO keyboards macOS reports the key left of 1 (§) as kVK_ISO_Section and the one next to the left Shift as
/// kVK_ANSI_Grave, the other way round from the keys' places (`MacKeyCodes` has each code where an ANSI keyboard, or
/// the HID usage table, has it): there the two codes are swapped before the usage, as Chromium and Firefox do, so the
/// usage is the key's place. Nothing in the composer or the Korean pack goes by those two keys; recorded shortcuts and
/// other systems do.
public enum MacKeyboard {
    /// The keyboard typed on last is an ISO one (`KBGetLayoutType`; JIS and ANSI aren't swapped).
    public static var isISO: Bool { KBGetLayoutType(Int16(LMGetKbdType())) == PhysicalKeyboardLayoutType(kKeyboardISO) }

    /// The usage of the key macOS reports as `keyCode`: 0 for one the table doesn't have.
    public static func usage(_ keyCode: UInt16, iso: Bool = isISO) -> UInt16 {
        MacKeyCodes.usage(iso ? isoSwapped(keyCode) : keyCode)
    }

    /// The key code macOS reports for the key at `usage`: nil where the Mac has no such key.
    public static func keyCode(usage: UInt16, iso: Bool = isISO) -> UInt16? {
        MacKeyCodes.code(usage: usage).map { iso ? isoSwapped($0) : $0 }
    }

    /// kVK_ISO_Section ↔ kVK_ANSI_Grave; any other code as it is.
    static func isoSwapped(_ keyCode: UInt16) -> UInt16 {
        switch keyCode {
        case 0x0A: return 0x32
        case 0x32: return 0x0A
        default: return keyCode
        }
    }
}

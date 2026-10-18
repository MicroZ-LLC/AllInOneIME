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

    /// `translate(_:…)` by the key's usage (`KeyTranslator`): the key code at that place (`MacKeyCodes`); nothing where
    /// the Mac has no such key.
    public func translate(usage: UInt16, _ modifiers: KeyModifiers, state: inout UInt32, deadKeys: Bool) -> String {
        guard let keyCode = MacKeyCodes.code(usage: usage) else {
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

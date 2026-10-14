import Carbon

/// A keyboard layout's key table (`uchr`), dead keys included.
public struct KeyboardLayout: @unchecked Sendable {
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

/// Dead keys under the input method. macOS composes them only for a plain keyboard layout: with an input
/// method selected, ⌥E then E (US), ^ then e (AZERTY) or ' then a (US International) reach it as "´" and
/// "e", and the app, given the keys back, types just "e". So they are composed here, from the same layout
/// (`KeyboardLayout.current`): the dead key is marked `isDeadKey`, the key after it carries `composed`.
public struct DeadKeyComposer {
    private var state: UInt32 = 0

    public init() {}

    /// Forgets a dead key typed before (the composer didn't take it, or dropped it).
    public mutating func reset() { state = 0 }

    public mutating func compose(_ event: KeyEvent, in layout: KeyboardLayout?) -> KeyEvent {
        let before = state
        state = 0
        guard let layout, event.modifiers.isDisjoint(with: [.command, .control]) else { return event }
        // Only when the layout is the one the key was typed in: alone, it types the key's characters.
        var none: UInt32 = 0
        let alone = layout.translate(event.keyCode, event.modifiers, state: &none, deadKeys: false)
        guard !alone.isEmpty, event.characters.isEmpty || event.characters == alone else { return event }
        var after = before
        let typed = layout.translate(event.keyCode, event.modifiers, state: &after)
        var key = event
        if typed.isEmpty, after != 0 {
            state = after
            key.isDeadKey = true
            key.characters = alone  // the accent, shown while waiting for the letter
            return key
        }
        guard before != 0, !typed.isEmpty, typed.unicodeScalars.allSatisfy(KeyEvent.isPrintable) else { return event }
        key.composed = typed
        return key
    }
}

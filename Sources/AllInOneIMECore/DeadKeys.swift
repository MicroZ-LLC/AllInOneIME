import Foundation

/// A keyboard layout's key table, as the composer reads it: what a key types (macOS: `KeyboardLayout`, Carbon's
/// `UCKeyTranslate`; Windows: `ToUnicodeEx`).
public protocol KeyTranslator: Sendable {
    /// What `keyCode` types with `modifiers` after the dead-key `state`, which becomes the state the key
    /// leaves (non-zero, with nothing typed: a dead key). Without `deadKeys` a dead key types its accent.
    func translate(_ keyCode: UInt16, _ modifiers: KeyModifiers, state: inout UInt32, deadKeys: Bool) -> String
}

/// Dead keys under the input method. macOS composes them only for a plain keyboard layout: with an input
/// method selected, ⌥E then E (US), ^ then e (AZERTY) or ' then a (US International) reach it as "´" and
/// "e", and the app, given the keys back, types just "e". So they are composed here, from the same layout
/// (`KeyboardLayout.current`, the macOS shell's): the dead key is marked `isDeadKey`, the key after it carries `composed`.
public struct DeadKeyComposer {
    private var state: UInt32 = 0

    public init() {}

    /// Forgets a dead key typed before (the composer didn't take it, or dropped it).
    public mutating func reset() { state = 0 }

    public mutating func compose(_ event: KeyEvent, in layout: (any KeyTranslator)?) -> KeyEvent {
        let before = state
        state = 0
        guard let layout, event.modifiers.isDisjoint(with: [.command, .control]) else { return event }
        // Only when the layout is the one the key was typed in: alone, it types the key's characters.
        var none: UInt32 = 0
        let alone = layout.translate(event.keyCode, event.modifiers, state: &none, deadKeys: false)
        guard !alone.isEmpty, event.characters.isEmpty || event.characters == alone else { return event }
        var after = before
        let typed = layout.translate(event.keyCode, event.modifiers, state: &after, deadKeys: true)
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

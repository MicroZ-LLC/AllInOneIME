import Foundation

/// A tap of an Option key (`ModifierRoles.actionTap`) as `handleFlagsChanged` tells one, the one tap logic for both of
/// its uses: with the `optionTap` action key either key's tap is that key; with another, the right one's while pinyin
/// is typed with shape codes on is "`" (`shapeCodeTap`, issue 168).
extension Composer {
    /// What is kept of the Option keys between changes of the modifiers.
    struct OptionTap {
        /// Which Option key (the action tap's: `ModifierRoles.actionTap`) went down on its own, and when (nil once
        /// anything else happens).
        var pressed: (key: Key, at: TimeInterval)?
        /// The last change of the modifiers was the release that typed "`" (`shapeCodeTap`).
        var typedShapeCode = false
    }

    /// `OptionTap.pressed`. Read by `optionTapHeld`.
    var optionPressed: (key: Key, at: TimeInterval)? {
        get { optionTap.pressed }
        set { optionTap.pressed = newValue }
    }

    /// Whether the change of the modifiers told last (`handleFlagsChanged`) is the composer's alone, not the app's as
    /// well: the release of the right Option's tap that typed "`" for the shape codes (the owner, 2026-11-26: an app
    /// that acts on a bare Option, a menu bar shown, a terminal's Meta, doesn't get the tap that was a key here). Every
    /// other change is the app's too, as it always was.
    public var tookModifierChange: Bool { optionTap.typedShapeCode }

    /// A change of the modifiers may have gone untold (secure input took the keys, the field was left with the key
    /// down): no press is remembered, so the next one starts anew.
    public func modifierChangesMissed() {
        optionTap = OptionTap()
    }

    /// Tracks the Option keys. True for the release of one that went down on its own and came back
    /// up within `optionTapWindow`, with no key or other modifier (including the other Option) between:
    /// how long it was held. Nil otherwise.
    func optionTapHeld(key: Key, modifiers: KeyModifiers, timestamp: TimeInterval) -> TimeInterval? {
        optionTap.typedShapeCode = false
        guard case let .modifier(kind, keySide) = key, kind == modifierRoles.actionTap else {
            optionPressed = nil  // another modifier changed
            return nil
        }
        let side = Modifiers.side(keySide, of: kind), either = Modifiers.kind(kind)
        let sided = !modifiers.isDisjoint(with: Modifiers.sides(of: kind))
        let down = sided ? modifiers.contains(side) : modifiers.contains(either)
        if down {
            let alone = modifiers.subtracting([either, side, .capsLock]).isEmpty
            // The key told down again while it is held (Caps Lock's light, another app's event tap): the same press,
            // timed from when it first went down.
            if alone, optionPressed?.key == key { return nil }
            optionPressed = alone && optionPressed == nil ? (key, timestamp) : nil
            return nil
        }
        defer { optionPressed = nil }
        guard let pressed = optionPressed, pressed.key == key else { return nil }
        let held = timestamp - pressed.at
        return held <= Self.optionTapWindow ? max(held, 0) : nil
    }

    /// A tap (`optionTapHeld`) of `key` that is the right Option (the one held to dictate, `ModifierRoles.voiceHold`)
    /// while pinyin is typed with shape codes on (`shapeCode`; never in Zhuyin, which has none): "`" (`ShapeCode.trigger`),
    /// through the path its key takes, so all is as after that key. Nil otherwise, the tap left as it was: the action
    /// key's with `optionTap` (its "`" key still types one), and with no pinyin or shape codes off the app's alone.
    /// The release that typed it is kept from the app (`tookModifierChange`).
    func shapeCodeTap(_ key: Key) -> [Effect]? {
        guard actionKey != .optionTap, key == modifierRoles.voiceHold.key, shapeCode != nil, !typesZhuyin,
              inputLanguage == .chinese, engineState.isComposing, voice == .off else { return nil }
        let typed = handleKeyDown(Self.shapeCodeKey)
        optionTap.typedShapeCode = typed.handled
        return typed.effects
    }

    /// The "`" key: its place (USB usage 0x35, left of 1 on a US keyboard) and its text, as the shape codes take it.
    static let shapeCodeKey = KeyEvent(key: .character, usage: 0x35, characters: ShapeCode.trigger)
}

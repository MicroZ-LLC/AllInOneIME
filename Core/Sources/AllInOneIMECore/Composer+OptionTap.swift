import Foundation

/// A tap of an Option key (`ModifierRoles.actionTap`) as `handleFlagsChanged` tells one, the one tap logic for both of
/// its uses: with the `optionTap` action key either key's tap is that key; with another, the right one's while pinyin
/// is typed with shape codes on is "`" (`shapeCodeTap`, issue 168).
extension Composer {
    /// Tracks the Option keys. True for the release of one that went down on its own and came back
    /// up within `optionTapWindow`, with no key or other modifier (including the other Option) between:
    /// how long it was held. Nil otherwise.
    func optionTapHeld(key: Key, modifiers: KeyModifiers, timestamp: TimeInterval) -> TimeInterval? {
        guard case let .modifier(kind, keySide) = key, kind == modifierRoles.actionTap else {
            optionPressed = nil  // another modifier changed
            return nil
        }
        let side = Modifiers.side(keySide, of: kind), either = Modifiers.kind(kind)
        let sided = !modifiers.isDisjoint(with: Modifiers.sides(of: kind))
        let down = sided ? modifiers.contains(side) : modifiers.contains(either)
        if down {
            let alone = modifiers.subtracting([either, side, .capsLock]).isEmpty && optionPressed == nil
            optionPressed = alone ? (key, timestamp) : nil
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
    func shapeCodeTap(_ key: Key) -> [Effect]? {
        guard actionKey != .optionTap, key == modifierRoles.voiceHold.key, shapeCode != nil, !typesZhuyin,
              inputLanguage == .chinese, engineState.isComposing, voice == .off else { return nil }
        return handleKeyDown(Self.shapeCodeKey).effects
    }

    /// The "`" key: its place (USB usage 0x35, left of 1 on a US keyboard) and its text, as the shape codes take it.
    static let shapeCodeKey = KeyEvent(key: .character, usage: 0x35, characters: ShapeCode.trigger)
}

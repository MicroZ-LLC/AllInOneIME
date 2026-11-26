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
        /// The Option keys told down and not yet up, whether on their own or not: one told down again is the same
        /// press (`optionTapHeld`), never a new one.
        var down: [Key] = []
        /// The key whose press was kept from the app (`keepsPress`), until the app is told of it another way or it is
        /// released: its release is kept too.
        var kept: Key?
        /// The last change of the modifiers was kept from the app (`tookModifierChange`).
        var tookChange = false
    }

    /// `OptionTap.pressed`. Read by `optionTapHeld`.
    var optionPressed: (key: Key, at: TimeInterval)? {
        get { optionTap.pressed }
        set { optionTap.pressed = newValue }
    }

    /// Whether the change of the modifiers told last (`handleFlagsChanged`) is the composer's alone, not the app's as
    /// well: the press of the right Option on its own while pinyin is typed with shape codes on, which may be the tap
    /// that types "`" (the owner, 2026-11-26: an app that acts on a bare Option, a menu bar shown, a terminal's Meta,
    /// doesn't get the tap that was a key here), that press told again, and its release. Both or neither: an app that
    /// follows the modifiers from their changes (a Chromium page's Alt keydown and keyup) never gets the press without
    /// the release, so the press is kept before it is known to be a tap. A press that turns out to be none (held on, a
    /// key typed with it) can't be handed to the app late (an input method answers each event as it comes), so the app
    /// isn't told of that press at all, nor of its release: the key typed with it carries Option among its modifiers, as
    /// the pointer's events do. Only where another modifier's change reached the app meanwhile, with Option among its
    /// flags, does the app know the key is down: it gets the release then. Every other change is the app's too, as it
    /// always was.
    public var tookModifierChange: Bool { optionTap.tookChange }

    /// A change of the modifiers may have gone untold (secure input took the keys, the field was left with the key
    /// down): no press is remembered, so the next one starts anew.
    public func modifierChangesMissed() {
        optionTap = OptionTap()
    }

    /// A key that secure input took, never told as a key (`handleKeyDown`): no tap or hold goes on across it, as across
    /// any key, and a key parked for the selection read after the "@" key is done first, as if nothing were selected.
    public func secureInputTookKey() -> [Effect] {
        (shiftPressedAt, optionPressed, voiceArmed) = (nil, nil, false)
        return selectionRead(nil)
    }

    /// A key typed: an Option down with it is a shortcut's, no tap; with none among the key's modifiers, any Option
    /// remembered down was released untold.
    func optionTapEnded(by event: KeyEvent) {
        optionPressed = nil
        if !event.modifiers.contains(Modifiers.kind(modifierRoles.actionTap)) { (optionTap.down, optionTap.kept) = ([], nil) }
    }

    /// Tracks the Option keys. True for the release of one that went down on its own and came back
    /// up within `optionTapWindow`, with no key or other modifier (including the other Option, and fn) between:
    /// how long it was held. Nil otherwise. `modifiers` with fn, if it is held.
    func optionTapHeld(key: Key, modifiers: KeyModifiers, timestamp: TimeInterval) -> TimeInterval? {
        optionTap.tookChange = false
        guard case let .modifier(kind, keySide) = key, kind == modifierRoles.actionTap else {
            // Another modifier changed: no tap, and its change tells the app which Option keys are down.
            (optionTap.pressed, optionTap.kept) = (nil, nil)
            if !modifiers.contains(Modifiers.kind(modifierRoles.actionTap)) { optionTap.down = [] }  // a release untold
            return nil
        }
        let side = Modifiers.side(keySide, of: kind), either = Modifiers.kind(kind)
        let sided = !modifiers.isDisjoint(with: Modifiers.sides(of: kind))
        let down = sided ? modifiers.contains(side) : modifiers.contains(either)
        if down {
            let alone = modifiers.subtracting([either, side, .capsLock]).isEmpty
            // The key told down again while it is held (Caps Lock's light, another app's event tap): the same press,
            // timed from when it first went down, the app's or not as it was; no new press after a chord either.
            if optionTap.down.contains(key) {
                if !alone { optionPressed = nil }
                optionTap.tookChange = optionTap.kept == key
                return nil
            }
            optionTap.down.append(key)
            optionPressed = alone && optionPressed == nil ? (key, timestamp) : nil
            optionTap.kept = optionPressed != nil && mayTypeShapeCode(key) ? key : nil
            optionTap.tookChange = optionTap.kept != nil
            return nil
        }
        defer { optionPressed = nil }
        optionTap.down.removeAll { $0 == key }
        if optionTap.kept == key { (optionTap.kept, optionTap.tookChange) = (nil, true) }
        guard let pressed = optionPressed, pressed.key == key else { return nil }
        let held = timestamp - pressed.at
        return held <= Self.optionTapWindow ? max(held, 0) : nil
    }

    /// Whether a tap of `key` now would type "`" (`shapeCodeTap`): the right Option (the one held to dictate,
    /// `ModifierRoles.voiceHold`) while pinyin is typed with shape codes on (`shapeCode`; never in Zhuyin, which has
    /// none), with another action key than `optionTap`.
    private func mayTypeShapeCode(_ key: Key) -> Bool {
        actionKey != .optionTap && key == modifierRoles.voiceHold.key && shapeCode != nil && !typesZhuyin
            && inputLanguage == .chinese && engineState.isComposing && voice == .off
    }

    /// A tap (`optionTapHeld`) of `key` that may type "`" (`mayTypeShapeCode`): "`" (`ShapeCode.trigger`), through the
    /// path its key takes, so all is as after that key. Nil otherwise, the tap left as it was: the action key's with
    /// `optionTap` (its "`" key still types one), and with no pinyin or shape codes off the app's alone. Its press and
    /// its release are kept from the app (`tookModifierChange`).
    func shapeCodeTap(_ key: Key) -> [Effect]? {
        guard mayTypeShapeCode(key) else { return nil }
        return handleKeyDown(Self.shapeCodeKey).effects
    }

    /// The "`" key: its place (USB usage 0x35, left of 1 on a US keyboard) and its text, as the shape codes take it.
    static let shapeCodeKey = KeyEvent(key: .character, usage: 0x35, characters: ShapeCode.trigger)
}

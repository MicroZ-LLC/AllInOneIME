import Foundation

extension InputSession {
    /// Changes of the modifiers may have gone unseen (secure input took the keys, another app became active): no long
    /// press of Shift (`suggestionsModifiersMissed`), and no press of Option remembered for a tap
    /// (`Composer.modifierChangesMissed`), so the next press of either starts anew.
    func modifiersMissed(shiftDown: Bool) {
        composer.modifierChangesMissed()
        suggestionsModifiersMissed(shiftDown: shiftDown)
    }

    /// A change of the modifiers told while a password field or secure input has the keys: any recording stops (its
    /// release may never arrive here), and what follows of this press isn't told. Caps Lock is the system's here: no
    /// switch, its lock left alone.
    func modifiersInSecureInput(_ change: ModifierChange) {
        if composer.voice != .off { perform(composer.passwordFieldTakesOver()) }
        modifiersMissed(shiftDown: change.modifiers.contains(.shift))
    }
}

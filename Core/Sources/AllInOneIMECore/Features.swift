/// The switches of parts of the product kept in the code but turned off for now. Whatever belongs to one goes by its
/// switch here, on every platform (the session, the settings document Windows' Settings app draws, the Assistant, the
/// Mac's windows, doctor and self-test), so turning the switch on brings the part back whole.
public enum Features {
    /// Voice input (hold the right ⌥ to dictate) is off for now. Holding the key starts nothing
    /// (`Composer.voiceEnabled` is false whatever the `voiceInput` setting says); no settings page, setting, hint,
    /// doctor check or Assistant text tells of it; the microphone and speech recognition are never asked for. The
    /// user's `voiceInput` setting is kept as it is (and synced), and counts again once this is on.
    ///
    /// To bring it back: make `voiceInputShipped` true, and say so again in the READMEs, docs/ and the CHANGELOG.
    public static var voiceInput: Bool { voiceInputInTests ?? voiceInputShipped }

    /// The switch itself: false, voice input off for now.
    static let voiceInputShipped = false

    /// `voiceInput` for one task (and the tasks it starts), the shipped switch left as it is: the tests of dictation
    /// through the session (`Features.$voiceInputInTests.withValue(true) { … }`). Internal: no shell can turn it on.
    @TaskLocal static var voiceInputInTests: Bool?
}

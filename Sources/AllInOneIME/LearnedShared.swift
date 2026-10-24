import AllInOneIMECore
import AllInOneIMEMac
import Foundation

/// What is learned on this Mac (Settings v2 §3.2: `LearnedStore`), one store for every field and for Settings: the
/// starting input each app learned, the apps whose text fields didn't take a typo's fix as asked (`TypeOut.Typist`: they
/// get no typos again), the suggestion rows picked, and what autocomplete learned and the models that refuse a
/// temperature, reached through it. In the app's data folder, never in the config file, never synced.
@MainActor
enum LearnedShared {
    /// The input method's own (the self-test's, in memory, while it runs).
    static var store = LearnedStore(file: LearnedStore.defaultURL, autocomplete: AutocompleteSwitch.store, temperature: .shared)

    /// What 0.6.6 and earlier learned outside the store (`LegacyLearned`), moved in at launch, before any field.
    static func moveInWhatWasLearnedBefore() {
        switch LegacyLearned.move(into: store) {
        case .nothingToMove:
            break
        case let .moved(typosOff, picks):
            log.notice("learned: moved in what was kept before (\(typosOff) apps without typos, \(picks) rows picked)")
        case .failed:
            log.error("learned: the store couldn't be written; what was kept before stays where it is")
        }
    }
}

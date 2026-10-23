import Foundation
@testable import AllInOneIMECore

// The Code input (decision 22) in the suggestions rig (Acceptance/SuggestionsAcceptanceTests.swift): a world with Code
// among its inputs, and fields that start in it.

extension SuggestionsWorld {
    /// This world with the Code input in `language` and `packs` installed (Code's rows come from `language`'s alone).
    func addCode(_ language: String, packs: [CodingLanguagePack]) {
        config.codingLanguage = language
        self.packs = packs
    }

    /// A field of `app` that starts in Code: the app's starting input (Settings → Apps), as a user sets it; with
    /// `adjust`'s services.
    func codeField(app: String = "com.example.editor", terminal: Bool = false,
                   _ adjust: (inout SessionServices) -> Void = { _ in }) -> SuggestionsField {
        config.changeProfile(for: app) { $0.startingInput = .code }
        return field(app: app, terminal: terminal, adjust)
    }
}

// Coding mode, the shell's flag before decision 22 made Code an input, is gone. The acceptance tests written for it
// (decision 13's chooser) still hand the session one; here it does nothing, so they compile (and fail where they count on
// it) until they are written again for decision 22.
extension SuggestionsServices {
    var codingMode: () -> Bool {
        get { { false } }
        set {}
    }

    var setCodingMode: (Bool) -> Void {
        get { { _ in } }
        set {}
    }
}

import Foundation
import Testing

/// Caps Lock changes the language inside this one input source. macOS still lists it under English,
/// and the system's own input-source shortcut still switches between ABC and AllInOneIME.
struct CapsLockInputSourceAcceptanceTests {
    private let group = InputSourceGroupTests()

    @Test func capsLockKeepsAllInOneIMEInTheEnglishInputSourceGroup() throws {
        try group.theInputMethodIsListedUnderEnglish()
        let plist = try group.inputMethodPlist()
        #expect(plist["TISIntendedLanguage"] as? String == "en")
        #expect((plist["tsInputMethodCharacterRepertoireKey"] as? [String])?.first == "Latn")
    }

    @Test func capsLockDoesNotCreateAnotherInputSource() throws {
        try group.theInputSourceKeepsItsID()
        let plist = try group.inputMethodPlist()
        #expect(plist["ComponentInputModeDict"] == nil)
        #expect(plist["tsInputModeListKey"] == nil)
    }
}

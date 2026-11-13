import Foundation
import Testing

/// The owner's rule (2026-11-08, again 2026-11-13): AllInOneIME is listed under English in System Settings → Keyboard →
/// Input Sources → +, never under Chinese. macOS takes the group from the input method's Info.plist: TISIntendedLanguage
/// and the first script of tsInputMethodCharacterRepertoireKey. Changing either moves it to another group (0.7.4's
/// first builds did, for Caps Lock), and a move of group or identity needed a logout to show (0.7.2). Change this test
/// only with the owner's OK.
struct InputSourceGroupTests {
    /// The repository root (this file is Tests/AllInOneIMEMacTests/InputSourceGroupTests.swift).
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func inputMethodPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func theInputMethodIsListedUnderEnglish() throws {
        let plist = try inputMethodPlist()
        #expect(plist["TISIntendedLanguage"] as? String == "en",
                "AllInOneIME must stay under English in Input Sources (owner's rule); TISIntendedLanguage is \(String(describing: plist["TISIntendedLanguage"]))")
        let repertoire = plist["tsInputMethodCharacterRepertoireKey"] as? [String]
        #expect(repertoire?.first == "Latn",
                "the first script names the group: Latn keeps it under English; it is \(String(describing: repertoire))")
    }

    /// Its source and bundle ID stay as 0.7.2.1 moved them: another ID is another input source, which users would have
    /// to add again.
    @Test func theInputSourceKeepsItsID() throws {
        let plist = try inputMethodPlist()
        #expect(plist["TISInputSourceID"] as? String == "com.allinoneime.inputmethod.AllInOneIME")
        #expect(plist["CFBundleIdentifier"] as? String == "com.allinoneime.inputmethod.AllInOneIME")
    }
}

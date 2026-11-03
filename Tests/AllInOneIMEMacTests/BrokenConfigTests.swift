import Foundation
import Testing

/// What deletes, trims or starts recording anything goes by the config file only as it parses
/// (`LiveConfig.currentIfValid`), never by the defaults a file that doesn't parse reads as (`LiveConfig.current`): their
/// limit of 20 would drop the rest of a clipboard history of 100 (its images too), a history turned off would record
/// again, their sources (none approved) would delete every cached list of suggestions, the session's prune too
/// (`SuggestionsServices.settingsValid`), and Rime's fuzzy pinyin patch would be written again without the user's pairs
/// or characters (at Rime's start, after a personal dictionary is imported or removed, as the characters follow the
/// system's languages). Read from the sources, as the input method can't be run here.
struct BrokenConfigTests {
    /// Each place that does: the file and the function.
    static let destructive = [("ClipboardHistory.swift", "tick"), ("Suggestions.swift", "settingsChanged"),
                              ("LanguagePacks.swift", "start"), ("PersonalDictionariesSettings.swift", "change")]

    @Test(arguments: destructive)
    func itGoesByTheFileOnlyAsItParses(_ file: String, _ function: String) throws {
        let body = try #require(InputMenuWritesTests.body(of: function, in: try InputMenuWritesTests.source(file)), "\(file): \(function)")
        #expect(body.contains("LiveConfig.currentIfValid"), "\(file): \(function)")
        #expect(!Self.readsTheDefaults(body), "\(file): \(function)")
    }

    /// The fields' sessions are told whether the settings their suggestions read are the user's.
    @Test func theSessionsAreToldWhetherTheSettingsAreTheUsers() throws {
        let body = try #require(InputMenuWritesTests.body(of: "services", in: try InputMenuWritesTests.source("Suggestions.swift")))
        #expect(body.contains("services.settingsValid = { MainActor.assumeIsolated { LiveConfig.currentIfValid != nil } }"))
    }

    /// What iCloud sync brought in, fuzzy pinyin or the characters, is applied to Rime from the file as it parses too.
    @Test func syncsFuzzyPinyinGoesByTheFileAsItParses() throws {
        let body = try #require(InputMenuWritesTests.body(of: "applyLive", in: try InputMenuWritesTests.source("ICloudSyncController.swift")))
        let code = body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(code.contains(#"if report.configKeys.contains("fuzzyPinyin") || report.configKeys.contains("chineseCharacters"), let valid = LiveConfig.currentIfValid { RimeFuzzy.apply(valid.fuzzyPinyin, characters: valid.typedChinese) }"#))
    }

    /// The characters following the system's languages (`RimeFuzzy.follow`, as a field is focused or the languages
    /// change) write the patch from the file as it parses, not from its defaults.
    @Test(arguments: [("InputController.swift", "activateServer"), ("main.swift", "runServer")])
    func followingTheSystemsLanguagesGoesByTheFileAsItParses(_ file: String, _ function: String) throws {
        let body = try #require(InputMenuWritesTests.body(of: function, in: try InputMenuWritesTests.source(file)), "\(file): \(function)")
        #expect(body.contains("RimeFuzzy.follow(LiveConfig.currentIfValid)"), "\(file): \(function)")
        #expect(!body.contains("RimeFuzzy.follow(LiveConfig.current)"), "\(file): \(function)")
    }

    /// Whether `text` reads `LiveConfig.current` (the defaults while the file doesn't parse), not `currentIfValid`.
    static func readsTheDefaults(_ text: Substring) -> Bool {
        text.ranges(of: "LiveConfig.current").contains { !text[$0.upperBound...].hasPrefix("IfValid") }
    }
}

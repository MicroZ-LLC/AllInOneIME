import Foundation
import Testing

/// What deletes, trims or starts recording anything goes by the config file only as it parses
/// (`LiveConfig.currentIfValid`), never by the defaults a file that doesn't parse reads as (`LiveConfig.current`): their
/// limit of 20 would drop the rest of a clipboard history of 100 (its images too), a history turned off would record
/// again, and their sources (none approved) would delete every cached list of suggestions, the session's prune too
/// (`SuggestionsServices.settingsValid`). Read from the sources, as the input method can't be run here.
struct BrokenConfigTests {
    /// Each place that does: the file and the function.
    static let destructive = [("ClipboardHistory.swift", "tick"), ("Suggestions.swift", "settingsChanged")]

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

    /// Whether `text` reads `LiveConfig.current` (the defaults while the file doesn't parse), not `currentIfValid`.
    static func readsTheDefaults(_ text: Substring) -> Bool {
        text.ranges(of: "LiveConfig.current").contains { !text[$0.upperBound...].hasPrefix("IfValid") }
    }
}

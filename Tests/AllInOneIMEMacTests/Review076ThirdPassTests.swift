import Foundation
import Testing

/// What the third review of the 0.7.6 review's fixes found in the input method's own code, each test one finding
/// (the child: Review076SecondPassChild.swift, with this suite's ways, Review076ThirdPassChild.swift).
@Suite("0.7.6 review, third pass: keys changed after a failed listing, a fast fallback not looked at yet, Settings told", .serialized)
struct Review076ThirdPassTests {
    @Test func aKeyRemovedOrSavedAfterACopyBackThatCouldNotListIsLeftAsItIs() throws {
        let report = try Review076SecondPassChild.run("copy-back-changed-later")
        #expect(report["notListedYet"] == "true" && report["removed"] == "true" && report["saved"] == "true" && report["listed"] == "true",
                "not a failed listing, the keys changed, then a listing: \(report)")
        #expect(report["removedKey"] == "none", "the next run copied the removed key back: \(report)")
        #expect(report["savedKey"] == "sk-test-new-EXAMPLE", "the next run wrote over the key saved here: \(report)")
    }

    /// The new fast fallback has no key: named at once (item 21's acceptance test), but never as able to run.
    @Test func aFastFallbackJustChosenWithoutAKeyIsNotShownAsAvailable() throws {
        let report = try Review076SecondPassChild.run("menu-no-key-yet")
        #expect(report["before"] == "openai true true", "the first fallback was not established: \(report)")
        #expect(report["atOnceProvider"] == "anthropic" && report["atOnceLine"] == report["destination"] && report["atOnceModel"] != "",
                "the new destination isn't shown at once: \(report)")
        #expect(report["atOnceAvailable"] == "false" && report["atOnceOn"] == "false", "shown as able to run before anything looked: \(report)")
        #expect(report["answered"] == "true", "the look never came back: \(report)")
        #expect(report["laterProvider"] == report["route"], "the switch and the requests disagree: \(report)")
        #expect(report["laterAvailable"] == (report["route"] == "none" ? "false" : "true"), "\(report)")
    }

    /// The new fast fallback has a key: not to be turned on until the look says so, then on as the settings have it.
    @Test func aFastFallbackJustChosenIsAvailableOnceLookedAt() throws {
        let report = try Review076SecondPassChild.run("menu-key-not-looked-at")
        #expect(report["before"] == "openai true true", "the first fallback was not established: \(report)")
        #expect(report["atOnceProvider"] == "gemini" && report["atOnceLine"] == report["destination"], "the new destination isn't shown at once: \(report)")
        #expect(report["atOnceAvailable"] == "false" && report["atOnceOn"] == "false", "shown as able to run before anything looked: \(report)")
        #expect(report["answered"] == "true" && report["route"] == "gemini", "the look never came back: \(report)")
        #expect(report["laterProvider"] == "gemini" && report["laterAvailable"] == "true" && report["laterOn"] == "true",
                "not on again once looked at: \(report)")
    }

    @Test func settingsToldOfAChangedConfigOrAKeyFieldDoesNotReadItOnTheMainThread() throws {
        let report = try Review076SecondPassChild.run("settings-told")
        #expect(report["shown"] == "true" && report["reloaded0"] == "true" && report["reloaded1"] == "true",
                "the changed config was not read again: \(report)")
        // Told the config changed (0), and asked for a key's field (1).
        for step in 0..<2 {
            let from = try #require(report.opened.firstIndex(where: { $0.path == report["from\(step)"] }), "no mark before step \(step)")
            let end = try #require(report.opened.firstIndex(where: { $0.path == report["to\(step)"] }), "no mark after step \(step)")
            let reads = report.opened[(from + 1)..<end].filter { $0.path == report["config"] }
            #expect(!reads.isEmpty, "the config file was not read again (\(step)): \(report)")
            #expect(!reads.contains(where: { $0.main }), "config.json was read on the main thread (\(step)): \(report)")
        }
    }
}

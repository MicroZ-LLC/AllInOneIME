import Foundation
import Testing

/// What the second review of the 0.7.6 review's fixes found in the input method's own code, each test one finding
/// (the child: Review076SecondPassChild.swift).
@Suite("0.7.6 review, second pass: autocomplete's switch, keys, a settling stop, Settings opened", .serialized)
struct Review076SecondPassTests {
    @Test func aLateLookForTheSameSettingsAskedAgainDoesNotReplaceTheNewOne() throws {
        let report = try Review076SecondPassChild.run("menu-same-again")
        #expect(report["otherAnswered"] == "true" && report["firstAnswered"] == "true" && report["lastAnswered"] == "true",
                "the looks did not all come back: \(report)")
        #expect(report["route"] == "openai", "the requests don't go to the key just saved: \(report)")
        #expect(report["shownProvider"] == report["route"], "the first look's late answer replaced the new one: \(report)")
    }

    @Test func aKeyRemovedBeforeACopyBackThatCouldNotListStaysRemoved() throws {
        let report = try Review076SecondPassChild.run("copy-back-listed-later")
        #expect(report["removed"] == "true" && report["notListedYet"] == "true", "the first run was not the one that can't list: \(report)")
        #expect(report["loginHasKey"] == "false", "the next run copied the removed key back: \(report)")
    }

    /// The stop settles after the field is left: the typo is taken out, the rest isn't typed (the acceptance test of
    /// item 13 looks only before the stop has settled).
    @Test func aStopSettlingWhenTheFieldIsLeftDropsItsRestOnceItSettles() throws {
        let report = try Review076SecondPassChild.run("settling-left")
        try expectRestDropped(report)
    }

    @Test func aStopSettlingWhenTheCompositionIsCancelledDropsItsRest() throws {
        let report = try Review076SecondPassChild.run("settling-cancelled")
        try expectRestDropped(report)
    }

    private func expectRestDropped(_ report: Review076P2Child.Report) throws {
        let typed = try #require(report["typed"]), intended = try #require(report["intended"])
        #expect(report["caught"] == "true" && report["settled"] == "true", "the settling stop was not reached, or never settled: \(report)")
        #expect(typed != intended, "the rest was typed into the field: \(report)")
        #expect(intended.hasPrefix(typed) && typed.count >= 2, "a typo left in the field: \(report)")
    }

    @Test func openingSettingsOnAnAICardDoesNotReadConfigOnTheMainThread() throws {
        let report = try Review076SecondPassChild.run("settings-opened")
        #expect(report["reloaded0"] == "true" && report["reloaded1"] == "true" && report["sameModel"] == "true",
                "the changed config was not read again: \(report)")
        // Opened on the settings the start built (0), and opened again once closed (1).
        for step in 0..<2 {
            #expect(report["closed\(step)"] == "true", "the window was not closed: \(report)")
            let from = try #require(report.opened.firstIndex(where: { $0.path == report["from\(step)"] }), "no mark before step \(step)")
            let end = try #require(report.opened.firstIndex(where: { $0.path == report["to\(step)"] }), "no mark after step \(step)")
            let reads = report.opened[(from + 1)..<end].filter { $0.path == report["config"] }
            #expect(!reads.isEmpty, "the config file was not read again (\(step)): \(report)")
            #expect(!reads.contains(where: { $0.main }), "config.json was read on the main thread (\(step)): \(report)")
        }
    }

    @Test func theAssistantCountsAKeyOnlyForTheHostItWasSavedFor() throws {
        let report = try Review076SecondPassChild.run("assistant-keys")
        #expect(report["own"] == "true", "the key is not counted for its own host: \(report)")
        #expect(report["relayed"] == "false", "a key saved for api.openai.com counts for relay.example.com: \(report)")
    }
}

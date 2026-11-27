import Foundation
import Testing

/// What the review of the look at the input source off the main thread found in the input method's own code, each test
/// one finding (the child: Review076SecondPassChild.swift, with this suite's ways, AboutOffMainReviewChild.swift).
@Suite("About off the main thread, review: Settings reopened before the first look, a look answered after leaving", .serialized)
struct AboutOffMainReviewTests {
    /// Right after the move, the source not added: Settings opened again before the first look answered shows nothing
    /// until it does, then About with the step, and no other page before it.
    @Test func settingsOpenedAgainBeforeTheFirstLookShowsOnlyTheStep() throws {
        let report = try Review076SecondPassChild.run("reopen-undecided-step")
        #expect(report["undecided"] == "true" && report["decided"] == "true", "the launch was decided too early or never: \(report)")
        #expect(report["shownAtOnce"] == "false", "Settings came up before the launch decided it shows the step: \(report)")
        #expect(report["first"] == "inputSourceStep" && report["shown"] == "true" && report["pages"] == "about",
                "not About with the step alone: \(report)")
    }

    /// Any other launch: shown once decided (at once, as no look is waited for).
    @Test func settingsOpenedAgainBeforeANothingDecisionShowsOnceDecided() throws {
        let report = try Review076SecondPassChild.run("reopen-undecided-nothing")
        #expect(report["undecided"] == "true" && report["decided"] == "true", "\(report)")
        #expect(report["shownAtOnce"] == "false", "Settings came up before the launch was decided: \(report)")
        #expect(report["first"] == "nothing" && report["shown"] == "true", "Settings never came up: \(report)")
    }

    /// Decided (the step shown): a later reopen still shows Settings, at once.
    @Test func settingsOpenedAgainOnceDecidedShowsAtOnce() throws {
        let report = try Review076SecondPassChild.run("reopen-decided")
        #expect(report["shownAtOnce"] == "true", "a reopen after the launch was decided showed nothing: \(report)")
    }

    /// The look asked for when the app became active answers after the user left it: About isn't brought back over the
    /// app they went to.
    @Test func aLookAnsweredAfterTheUserLeftDoesNotBringSettingsBack() throws {
        let report = try Review076SecondPassChild.run("added-while-away")
        #expect(report["notAdded"] == "true" && report["added"] == "true" && report["looks"] == "2", "\(report)")
        #expect(report["told"] == "0", "whenAdded ran with the app no longer active: \(report)")
    }

    @Test func aLookAnsweredWithTheUserStillBackBringsSettingsBack() throws {
        let report = try Review076SecondPassChild.run("added-while-back")
        #expect(report["notAdded"] == "true" && report["added"] == "true" && report["looks"] == "2", "\(report)")
        #expect(report["told"] == "1", "whenAdded didn't run once, the app active: \(report)")
    }
}

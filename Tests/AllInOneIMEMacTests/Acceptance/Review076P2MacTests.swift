import Foundation
import Testing

@Suite("0.7.6 review: typing, startup, keys and autocomplete", .serialized)
struct Review076P2MacTests {
    @Test func firstEnglishLearningDoesNotReadTheWordListOnTheTypingThread() throws {
        let report = try Review076P2Child.run("words")
        let reads = report.opened.filter { $0.path.hasSuffix("/RedactionWords.txt") }
        #expect(!reads.isEmpty, "the real bundled word list was never read: \(report)")
        #expect(!reads.contains(where: { $0.main }), "a typing-thread read of RedactionWords.txt: \(report)")
    }

    @Test func leavingAFieldDoesNotInsertThePendingTypeOutRemainder() throws {
        let report = try Review076P2Child.run("leave")
        #expect(report["caught"] == "true", "the pending type-out was not reached: \(report)")
        #expect(report["typed"] == report["before"], "leaving inserted the rest into the old field: \(report)")
    }

    @Test func replayedKeysClearChromiumsTemporaryMarkedText() throws {
        let control = try Review076P2Child.run("held-control")
        let report = try Review076P2Child.run("held-keys")
        #expect(report["caught"] == "true", "the keys were not held during a type-out: \(report)")
        #expect(control["markedBeforeEachKey"] == "[][]", "the temporary mark was not cleared before the next ordinary key: \(control)")
        #expect(report["markedAfterReplay"] == "[]", "replay left temporary marked text for the next key: \(report)")
    }

    @Test func pointingAtAnAICardDoesNotReadConfigOnTheMainThread() throws {
        let report = try Review076P2Child.run("config-read")
        #expect(report["reloaded"] == "true", "the changed config was not reloaded: \(report)")
        let marker = try #require(report.opened.firstIndex(where: { $0.path == report["mark"] }), "the phase marker was not opened")
        let reads = report.opened.suffix(from: marker + 1).filter { $0.path == report["config"] }
        #expect(!reads.isEmpty, "the real config file was not observed: \(report)")
        #expect(!reads.contains(where: { $0.main }), "config.json was read on the main thread: \(report)")
    }

    @Test func startWindowInstallsTheEditMenuForItsPracticeField() throws {
        let source = Review076P2Child.repository.appendingPathComponent("Sources/AllInOneIME/StartWindow.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let start = try #require(text.range(of: "static func show() {"))
        let end = try #require(text.range(of: "static func close()", range: start.upperBound..<text.endIndex))
        let showing = text[start.lowerBound..<end.lowerBound]
        let installed = showing.contains("EditMenu.install()")
        #expect(installed, "the start window opens without the Edit menu used by its text field")
    }

    @Test(arguments: ["copy-back-listed", "copy-back-done"])
    func removingAKeyDuringStartupDoesNotRestoreItsICloudCopy(_ way: String) throws {
        let report = try Review076P2Child.run(way)
        #expect(report["removed"] == "true", "the key was not removed first: \(report)")
        #expect(report["loginHasKey"] == "false", "startup restored the deleted login key: \(report)")
    }

    @Test func terminalRollbackTimeoutIsNotReportedAsAgentLaunched() throws {
        let report = try Review076P2Child.run("terminal-rollback")
        #expect(report["markerExists"] == "false", "the fake Terminal unexpectedly started the command: \(report)")
        #expect(report["launched"] == "false", "a timed-out Terminal query was reported as success: \(report)")
    }

    @Test func changedFastFallbackIsShownAsTheNewDestinationImmediately() throws {
        let report = try Review076P2Child.run("menu-switch")
        #expect(report["beforeProvider"] == "openai", "the first fallback was not established: \(report)")
        #expect(report["route"] == "gemini", "the actual route did not change: \(report)")
        #expect(report["atOnceProvider"] == "gemini", "the menu still names the old fallback: \(report)")
    }

    @Test func aLateOldLookupDoesNotReplaceTheNewAutocompleteDestination() throws {
        let report = try Review076P2Child.run("menu-race")
        #expect(report["nowAnswered"] == "true" && report["beforeAnswered"] == "true", "both lookups did not finish: \(report)")
        #expect(report["afterLateAnswerProvider"] == report["route"], "an old lookup replaced the new route: \(report)")
    }

    @Test func autocompleteOffWithCLIChosenDoesNotReadAKeyAtLaunchOrMenuOpen() throws {
        let launch = try Review076P2Child.run("menu-off")
        let menu = try Review076P2Child.run("menu-only")
        #expect(launch["readsAtLaunch"] == "", "launch read a key while autocomplete is off: \(launch)")
        #expect(menu["readsAtMenu"] == "", "opening the menu read a key while autocomplete is off: \(menu)")
    }

    @Test func settingsRejectsAKeyBoundToAnotherHostAsTheRequestDoes() throws {
        let report = try Review076P2Child.run("bound-key")
        #expect(report["looked"] == "true", "the settings key state did not finish loading: \(report)")
        #expect(report["requestRefused"] != "none", "the request accepted the other host's key: \(report)")
        #expect(report["settingsFast"] == report["routeFast"], "settings and the request disagree on the fallback: \(report)")
    }
}

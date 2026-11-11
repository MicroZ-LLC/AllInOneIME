import Foundation
import Testing

/// The command editor's Test run (Sources/AllInOneIME/CommandEditor.swift, in the app's executable target, which this
/// target can't import: read as source, as `CustomCommandEditorAcceptanceTests` does). What a run shows is the form's
/// only while what it runs and its sample are as they were: a change to either stops it and clears what it showed, and
/// what it gives after that isn't set (its task cancelled, asked before the outcome is set, both on the main actor).
struct CommandEditorTrialTests {
    /// The repository root (this file is Tests/AllInOneIMEMacTests/CommandEditorTrialTests.swift).
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func aChangedSampleOrDefinitionStopsTheRunAndClearsItsOutcome() throws {
        let source = try String(contentsOf: root.appendingPathComponent("Sources/AllInOneIME/CommandEditor.swift"), encoding: .utf8)
        for changed in ["runnable", "sample"] {
            #expect(source.contains(".onChange(of: \(changed)) { stopTrial() }"), "a changed \(changed) leaves the Test run's outcome")
        }
        let stop = try #require(source.range(of: "private func stopTrial() {"))
        let body = source[stop.upperBound...].prefix { $0 != "}" }
        #expect(body.contains("trialTask?.cancel()") && body.contains("trial = nil"))
        #expect(source.contains("guard !Task.isCancelled else { return }\n            trial = outcome"))
        // The AI's question is the core's (`CommandTrial.confirmation`): the settings service's words, one translation.
        #expect(source.contains(".confirmationDialog(CommandTrial.confirmation(config),"))
        #expect(!source.contains("This sends the sample to"))
    }
}

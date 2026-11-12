import AllInOneIMECore
import AllInOneIMEMac
import Foundation
import Testing

/// The command editor's Test run (`CommandEditorTrial`): what a run shows is the form's only while its sample and what
/// it runs are as they were. A new sample stops the run and clears what it showed, and what that run gives after never
/// shows, not on the new sample nor on its own run; a run started after another is the only one shown. The AI is a
/// stand-in whose answers come when the test lets them.
@MainActor
struct CommandEditorTrialTests {
    /// The stand-in AI's answers, each held until the test lets the one for its sample come.
    actor Answers {
        private var given = Set<String>()
        private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
        private(set) var asked: [String] = []

        func answer(_ sample: String) async -> String {
            asked.append(sample)
            if !given.contains(sample) {
                await withCheckedContinuation { waiting[sample, default: []].append($0) }
            }
            return "the answer to \(sample)"
        }

        func give(_ sample: String) {
            given.insert(sample)
            waiting.removeValue(forKey: sample)?.forEach { $0.resume() }
        }
    }

    private let polite = CustomCommand(name: "polite", type: .prompt, prompt: "Be polite")

    /// Waits (on the main actor, letting the runs finish) until `condition` holds; false after `timeout` seconds.
    private func eventually(timeout: Double = 5, _ condition: () async -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return await condition()
    }

    @Test func sampleBNeverShowsWhatTheRunOnSampleAGave() async throws {
        let (trial, answers) = (CommandEditorTrial(sample: "A"), Answers())
        trial.start(polite) { _, sample in await answers.answer(sample) }
        #expect(trial.outcome == .running)
        #expect(try await eventually { await answers.asked == ["A"] })

        trial.sample = "B"
        #expect(trial.outcome == nil && trial.sample == "B")
        // A's answer comes after: never shown on B.
        await answers.give("A")
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(trial.outcome == nil)

        trial.start(polite) { _, sample in await answers.answer(sample) }
        #expect(trial.outcome == .running)
        await answers.give("B")
        #expect(try await eventually { trial.outcome == .passed("the answer to B") })
        // The same sample typed again (the field set to what it has) keeps what it shows.
        trial.sample = "B"
        #expect(trial.outcome == .passed("the answer to B"))
        // Then another sample: gone.
        trial.sample = "C"
        #expect(trial.outcome == nil)
    }

    @Test func aRunStartedAfterAnotherIsTheOnlyOneShownAndAStoppedOneNever() async throws {
        let (trial, answers) = (CommandEditorTrial(sample: "A"), Answers())
        trial.start(polite) { _, _ in await answers.answer("first") }
        #expect(try await eventually { await answers.asked == ["first"] })
        trial.start(polite) { _, _ in await answers.answer("second") }
        await answers.give("second")
        #expect(try await eventually { trial.outcome == .passed("the answer to second") })
        await answers.give("first")
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(trial.outcome == .passed("the answer to second"))

        // What it runs changed (the form calls `stop`), the editor closed: the run's answer never shows.
        trial.start(polite) { _, _ in await answers.answer("stopped") }
        #expect(try await eventually { await answers.asked.contains("stopped") })
        trial.stop()
        #expect(trial.outcome == nil)
        await answers.give("stopped")
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(trial.outcome == nil)
    }

    @Test func aRunShowsWhyItGaveNothing() async throws {
        let trial = CommandEditorTrial()
        trial.start(polite) { _, _ in "unused" }
        #expect(try await eventually { trial.outcome != .running })
        guard case let .failed(reason)? = trial.outcome else { Issue.record("\(String(describing: trial.outcome))"); return }
        #expect(!reason.isEmpty)
    }

    /// The editor's form uses it: the sample field is the trial's, and a change to what it runs stops the run (read as
    /// source: the editor is in the app's executable target, which this target can't import).
    @Test func theEditorUsesItsTrial() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/AllInOneIME/CommandEditor.swift"), encoding: .utf8)
        #expect(source.contains("text: $trial.sample") && source.contains(".onChange(of: runnable) { trial.stop() }"))
        #expect(source.contains(".confirmationDialog(CommandTrial.confirmation(config),") && !source.contains("This sends the sample to"))
    }
}

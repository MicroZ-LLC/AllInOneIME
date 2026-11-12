import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A custom command's Test run in the settings service (`SettingsService.commandTest`, the Mac's document's) is the
/// command's as it was when it started: saving the command or deleting it stops a run still under way (its request is
/// answered `cancelled`), and what that run finds after never shows on the command of that name, not even on one made
/// again with the name. A config file of its own; the AI is a stand-in that answers when the test lets it.
@Suite(.serialized, MemorySecrets())
struct CommandTestRunStopsTests {
    /// Holds the stand-in's answer until it's opened.
    final class Gate: Sendable {
        private let state = Locked<(open: Bool, waiting: [CheckedContinuation<Void, Never>])>(initialState: (false, []))

        func wait() async {
            await withCheckedContinuation { continuation in
                let open = state.withLock { state -> Bool in
                    if !state.open { state.waiting.append(continuation) }
                    return state.open
                }
                if open { continuation.resume() }
            }
        }

        func open() {
            let waiting = state.withLock { state -> [CheckedContinuation<Void, Never>] in
                state.open = true
                defer { state.waiting = [] }
                return state.waiting
            }
            waiting.forEach { $0.resume() }
        }
    }

    private func fixture() throws -> (SettingsService, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("command-test-run-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("config.json")
        try Data(#"{"provider":"openai"}"#.utf8).write(to: file)
        return (SettingsService(store: SettingsStore(configURL: file), platform: .mac,
                                library: PluginLibrary(directory: dir.appendingPathComponent("plugins"))), file)
    }

    private func definition(_ prompt: String) -> AIConfig.JSONValue {
        .object(["name": .string("polite"), "type": .string("prompt"), "prompt": .string(prompt)])
    }

    private func item(_ service: SettingsService) -> SettingsDocument.Item? {
        service.document().field("commands.custom")?.items?.first { $0.id == "polite" }
    }

    @Test(arguments: ["save", "delete"])
    func aSaveOrADeleteStopsTheRunAndWhatItFindsNeverShows(_ change: String) async throws {
        let (service, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await service.perform(SettingsAction(field: "commands.custom", name: "save", value: definition("Be polite"))).get()
        let (gate, asked, answered) = (Gate(), Locked(initialState: false), Locked(initialState: false))
        service.commandTestAI = { (_: CustomCommand, _: String) async throws -> String in
            asked.withLock { $0 = true }
            await gate.wait()
            answered.withLock { $0 = true }
            return "the answer as it was"
        }
        let run = Task {
            await service.perform(SettingsAction(field: "commands.custom", name: "test", item: "polite",
                                                 value: .object(["sample": .string("hi"), "confirmed": .bool(true)])))
        }
        for _ in 0..<500 where !asked.withLock({ $0 }) { try await Task.sleep(nanoseconds: 10_000_000) }
        try #require(asked.withLock { $0 } && item(service)?.running == true)

        if change == "save" {
            try await service.perform(SettingsAction(field: "commands.custom", name: "save", item: "polite",
                                                     value: definition("Be very polite"))).get()
        } else {
            try await service.perform(SettingsAction(field: "commands.custom", name: "delete", item: "polite")).get()
            try await service.perform(SettingsAction(field: "commands.custom", name: "save", value: definition("Be brief"))).get()
        }
        // Stopped at once: no longer shown running, though its program (the stand-in) hasn't answered.
        #expect(item(service)?.running != true)

        // Its answer, given after: its request is answered `cancelled`, and it never shows on the command of that name.
        gate.open()
        let result = await run.value
        guard case let .failure(problem) = result else { Issue.record("the run went on: \(result)"); return }
        #expect(problem.code == .cancelled)
        for _ in 0..<500 where !answered.withLock({ $0 }) { try await Task.sleep(nanoseconds: 10_000_000) }
        try #require(answered.withLock { $0 })
        try await Task.sleep(nanoseconds: 300_000_000)
        let shown = try #require(item(service))
        #expect(shown.detail?.contains("the answer as it was") != true, "\(shown.detail ?? "")")
    }

    /// Saved or deleted right after its Test run was asked for, before the run started: nothing runs at all, neither the
    /// command as it was nor as it is now (the AI isn't asked), and the request is answered `cancelled`.
    @Test(arguments: ["save", "delete"])
    func aSaveOrADeleteBeforeTheRunStartsRunsNothing(_ change: String) async throws {
        let (service, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await service.perform(SettingsAction(field: "commands.custom", name: "save", value: definition("Be polite"))).get()
        let (gate, started, asked) = (Gate(), Locked(initialState: false), Locked(initialState: [String]()))
        service.actionStarts = {
            started.withLock { $0 = true }
            await gate.wait()
        }
        service.commandTestAI = { (command: CustomCommand, _: String) async throws -> String in
            asked.withLock { $0.append(command.prompt ?? "") }
            return "an answer"
        }
        let run = Task {
            await service.perform(SettingsAction(field: "commands.custom", name: "test", item: "polite",
                                                 value: .object(["sample": .string("hi"), "confirmed": .bool(true)])))
        }
        for _ in 0..<500 where !started.withLock({ $0 }) { try await Task.sleep(nanoseconds: 10_000_000) }
        try #require(started.withLock { $0 } && item(service)?.running == true)

        if change == "save" {
            try await service.perform(SettingsAction(field: "commands.custom", name: "save", item: "polite",
                                                     value: definition("Be very polite"))).get()
        } else {
            try await service.perform(SettingsAction(field: "commands.custom", name: "delete", item: "polite")).get()
            try await service.perform(SettingsAction(field: "commands.custom", name: "save", value: definition("Be brief"))).get()
        }
        gate.open()
        let result = await run.value
        guard case let .failure(problem) = result else { Issue.record("the run went on: \(result)"); return }
        #expect(problem.code == .cancelled)
        // What the stopped run would still do, given the time.
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(asked.withLock { $0 }.isEmpty)
        #expect(item(service)?.detail?.contains("an answer") != true)
    }

    /// A Test run is the command as it was when it was asked for: changed in config.json by something else meanwhile (a
    /// sync, an editor), which stops nothing, the run asks the AI with the instruction it had, and what it finds isn't
    /// shown on the command as it is now (answered `cancelled`).
    @Test func aRunIsTheCommandAsItWasWhenAskedFor() async throws {
        let (service, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await service.perform(SettingsAction(field: "commands.custom", name: "save", value: definition("Be polite"))).get()
        let (gate, started, asked) = (Gate(), Locked(initialState: false), Locked(initialState: [String]()))
        service.actionStarts = {
            started.withLock { $0 = true }
            await gate.wait()
        }
        service.commandTestAI = { (command: CustomCommand, _: String) async throws -> String in
            asked.withLock { $0.append(command.prompt ?? "") }
            return "an answer"
        }
        let run = Task {
            await service.perform(SettingsAction(field: "commands.custom", name: "test", item: "polite",
                                                 value: .object(["sample": .string("hi"), "confirmed": .bool(true)])))
        }
        for _ in 0..<500 where !started.withLock({ $0 }) { try await Task.sleep(nanoseconds: 10_000_000) }
        try #require(started.withLock { $0 })

        let edited = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(of: "Be polite", with: "Be rude")
        try #require(edited.contains("Be rude"))
        try Data(edited.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        service.checkForChanges()
        try #require(item(service)?.running == true)

        gate.open()
        let result = await run.value
        #expect(asked.withLock { $0 } == ["Be polite"])
        guard case let .failure(problem) = result else { Issue.record("shown on the command as it is now: \(result)"); return }
        #expect(problem.code == .cancelled)
        #expect(item(service)?.detail?.contains("an answer") != true)
    }

    /// `CommandTrial.run` stopped before it starts runs nothing: no snippet filled, no AI asked, no program.
    @Test(arguments: [CustomCommand(name: "sig", type: .snippet, text: "Best, {input}"),
                      CustomCommand(name: "polite", type: .prompt, prompt: "Be polite"),
                      CustomCommand(name: "upper", type: .run, argv: ["/usr/bin/touch", "{input}"])])
    func aTrialStoppedBeforeItStartsRunsNothing(_ command: CustomCommand) async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("command-trial-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let touched = dir.appendingPathComponent("ran").path
        let asked = Locked(initialState: false)
        let trial = Task { () -> Error? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await CommandTrial.run(command, sample: command.type == .run ? touched : "Ann") { _, _ in
                    asked.withLock { $0 = true }
                    return "an answer"
                }
                return nil
            } catch {
                return error
            }
        }
        let error = await trial.value
        #expect(error is CancellationError, "\(String(describing: error))")
        #expect(!asked.withLock { $0 } && !FileManager.default.fileExists(atPath: touched))
    }
}

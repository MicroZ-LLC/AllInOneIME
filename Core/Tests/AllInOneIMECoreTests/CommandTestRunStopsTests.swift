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
}

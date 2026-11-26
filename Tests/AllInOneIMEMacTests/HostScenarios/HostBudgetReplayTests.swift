import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMETestSupport
import Foundation
import Testing

/// The core's call budget (AllInOneIMEHostTests/HostBudgetTests) through the Mac's own reading code (`FieldReading`,
/// `FieldTextReading`, `FieldAnchor`, `TypingField`) over each profile's IMK client: every scenario file and 25 stress
/// scenarios, the host answering in time, slowly, or with garbage.
@MainActor
struct HostBudgetReplayTests {
    /// Every turn of every scenario file and `stressSeeds` stress scenarios on `profile`, the client set up by `setUp`.
    static func turns(on profile: HostProfile, stressSeeds: Int = 25,
                      _ setUp: (ProfiledTextClient) -> Void = { _ in }) throws -> [(what: String, calls: [String: Int], spent: TimeInterval)] {
        var scenarios = try HostScenarioTests.files.map { try HostCase.parse(String(contentsOf: $0, encoding: .utf8), source: $0.lastPathComponent) }
            .filter { $0.profiles.contains(profile) }
        for seed in UInt64(1)...UInt64(stressSeeds) {
            let (header, steps) = HostStress.scenario(seed: seed, HostStress.Options(drafts: false))
            scenarios.append(try HostCase.parse(HostStress.text(header, steps), source: "stress \(seed)"))
        }
        return scenarios.flatMap { scenario in
            let replayer = HostReplayer(scenario, profile: profile)
            setUp(replayer.client)
            replayer.run()
            return replayer.everyTurn
        }
    }

    /// A key's limits: substring calls, and calls in all (today's worst: one substring, nine in all with the panel's
    /// anchor and the commit, measured 2026-11-25), a modifier change's; a slow host's cost for a key.
    static let keySubstrings = 2, keyCalls = 12, modifierCalls = 3
    static let slow: [String: TimeInterval] = ["substring": 0.5, "length": 0.05, "selectedRange": 0.05, "markedRange": 0.05,
                                               "firstRect": 0.05, "attributes": 0.05, "insertText": 0.05, "setMarkedText": 0.05]
    static let slowKey: TimeInterval = 1.25

    /// The turns over the limits, each with its calls.
    static func over(_ turns: [(what: String, calls: [String: Int], spent: TimeInterval)]) -> [String] {
        turns.compactMap { turn in
            let total = turn.calls.values.reduce(0, +), substrings = turn.calls["substring", default: 0]
            let over = turn.what == "modifiers" ? total > modifierCalls : turn.what == "key" && (substrings > keySubstrings || total > keyCalls)
            return over ? "\(turn.what): \(turn.calls)" : nil
        }
    }

    @Test(arguments: HostProfile.allCases)
    func everyKeyStaysWithinItsCalls(_ profile: HostProfile) throws {
        let over = Self.over(try Self.turns(on: profile))
        #expect(over.isEmpty, "\(over.count) over: \(over.prefix(5))")
    }

    /// A slow host (a substring half a second, the other calls 50 ms; the run's own time): no key waits on it longer
    /// than `slowKey`.
    @Test(arguments: HostProfile.allCases)
    func aSlowHostDoesntHoldUpAKey(_ profile: HostProfile) throws {
        let turns = try Self.turns(on: profile) { $0.latency = Self.slow }.filter { $0.what == "key" }
        let slow = turns.filter { $0.spent > Self.slowKey }.map { "\($0.spent) s: \($0.calls)" }
        #expect(slow.isEmpty, "\(slow.count) keys over \(Self.slowKey) s: \(slow.prefix(5))")
    }

    /// Garbage a third of the time: every scenario still runs through (nothing crashes in the Mac's reading and anchoring
    /// code), and no key asks more for it.
    @Test(arguments: HostProfile.allCases)
    func garbageAnswersNeitherCrashNorMultiplyTheCalls(_ profile: HostProfile) throws {
        let turns = try Self.turns(on: profile) {
            $0.garbageEvery = 3
            $0.random = HostStress.SplitMix(seed: 76)
        }
        let over = Self.over(turns)
        #expect(over.isEmpty, "\(over.count) over: \(over.prefix(5))")
        #expect(turns.count > 500)
    }

    /// The read after a pause (autocomplete's, `id` 1; Code's words, `id` -1: `FieldReading.contextAfterPause`), once per
    /// pause, on the main thread: today's substring calls, with text after the caret, are many where the field tells no
    /// length and answers nil past its end (Chromium, Electron, WebKit: `FieldTextReading.readAfter`'s search, 12 and 15
    /// measured 2026-11-25), a few elsewhere; a slow host then holds the main thread that many times (6 s at 0.5 s a
    /// call). Kept from growing here; making it fewer changes what autocomplete reads, which is a change of its own.
    @Test(arguments: HostProfile.allCases)
    func aReadAfterAPauseStaysWithinItsCalls(_ profile: HostProfile) throws {
        let limits = profile.tellsLength || profile == .qt || profile == .tellsnothing ? (4, 4) : (13, 16)
        for markup in ["Hello wor|ld", "Hi|", String(repeating: "word ", count: 80) + "|" + String(repeating: "next ", count: 80), "|"] {
            let text = try HostText(markup: markup)
            let client = ProfiledTextClient(profile, text: text.text, selection: text.selection, marked: text.marked)
            let reading = FieldReading(isTerminal: { _ in false }, secureInputActive: { false })
            _ = reading.contextAfterPause(in: client, id: 1)
            let autocomplete = client.calls["substring", default: 0]
            client.resetCalls()
            _ = reading.contextAfterPause(in: client, id: -1)
            let words = client.calls["substring", default: 0]
            #expect(autocomplete <= limits.0 && words <= limits.1, "\(markup.prefix(12)): \(autocomplete), \(words)")
        }
    }
}

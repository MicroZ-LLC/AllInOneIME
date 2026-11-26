import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// What a key may cost in calls of the host's text-input API, on every profile, however slowly or wrongly the host
/// answers: every call is a wait on the app on the main thread (InputMethodKit calls in there), so a host that answers
/// late (50–500 ms) must not have it asked again and again in one key, and garbage (a range past the text, a length of
/// 2147483647, a substring of another length) must neither crash the session nor have it ask more. The limits are
/// today's worst over every scenario file and 30 stress scenarios (measured 2026-11-25, after `.` `,` `:` stopped
/// reading the text around the caret) and a margin; no app is listed anywhere.
struct HostBudgetTests {
    /// The most calls of each kind one key may make, and one timer's work (autocomplete's read after a pause: what is
    /// after the caret, found call by call where the field tells no length).
    static let keyLimits: [HostCall: Int] = [.substring: 2, .total: 6]
    static let timerLimits: [HostCall: Int] = [.substring: 9, .total: 15]
    /// A host as slow as a busy one: each substring half a second, each other call 50 ms (the run's own time: nothing
    /// sleeps). A key's calls may take this long in all: today's worst is one substring and three other calls (0.65 s).
    static let slow: [HostCall: TimeInterval] = [.substring: 0.5, .length: 0.05, .selectedRange: 0.05, .markedRange: 0.05]
    static let slowKey: TimeInterval = 1.0

    /// Every scenario file and `stressSeeds` stress scenarios on `profile`, the host answering as `answers` says: every
    /// key's, modifier change's and timer's calls, and the runs' failures.
    static func turns(on profile: HostProfile, answers: HostAnswers = HostAnswers(),
                      stressSeeds: Int = 30) -> (turns: [HostTurnCalls], failures: [HostFailure]) {
        var scenarios = HostScenarioFiles.all().compactMap { try? HostScenarioFiles.read($0) }.filter { $0.profiles.contains(profile) }
        for seed in UInt64(1)...UInt64(stressSeeds) {
            let (header, steps) = HostStress.scenario(seed: seed)
            if let scenario = try? HostCaseParser.parse(HostStress.text(header, steps), fallbackName: "stress") { scenarios.append(scenario) }
        }
        return UIText.$scopedInterface.withValue(UIText.ScopedInterface(choice: "en", commandTrigger: "@")) {
            var all: (turns: [HostTurnCalls], failures: [HostFailure]) = ([], [])
            for scenario in scenarios {
                let run = HostRun(scenario, profile: profile)
                run.field.answers = answers
                all.failures += run.run().map { HostFailure(line: $0.line, message: "\(scenario.name): \($0.message)") }
                all.turns += run.everyTurn
            }
            return all
        }
    }

    /// The turns over a limit: each with what it made.
    static func over(_ turns: [HostTurnCalls]) -> [String] {
        turns.compactMap { turn in
            let limits = turn.what == "timer" ? timerLimits : keyLimits
            let over = limits.filter { turn.calls[$0.key] > $0.value }
            return over.isEmpty ? nil : "\(turn.what) (line \(turn.line)): \(turn.calls)"
        }
    }

    @Test(arguments: HostProfile.allCases)
    func everyKeyStaysWithinItsCalls(_ profile: HostProfile) {
        let over = Self.over(Self.turns(on: profile).turns)
        #expect(over.isEmpty, "\(over.count) over \(Self.keyLimits) / \(Self.timerLimits): \(over.prefix(5))")
    }

    /// A slow host: no key waits on it longer than `slowKey`, and none asks it for a substring more than twice (the one
    /// call that is slowest in a busy web page).
    @Test(arguments: HostProfile.allCases)
    func aSlowHostDoesntHoldUpAKey(_ profile: HostProfile) {
        let turns = Self.turns(on: profile, answers: HostAnswers(latency: Self.slow)).turns.filter { $0.what != "timer" }
        let slow = turns.filter { $0.spent > Self.slowKey }.map { "\($0.what) (line \($0.line)): \($0.spent) s, \($0.calls)" }
        #expect(slow.isEmpty, "\(slow.count) keys over \(Self.slowKey) s: \(slow.prefix(5))")
        #expect(!turns.contains { $0.calls[.substring] > 2 })
    }

    /// Garbage now and then, a third of the calls: the run goes through every scenario (nothing crashes), the caret
    /// stays in the text, and no key or timer asks more than the limits for it.
    @Test(arguments: HostProfile.allCases)
    func garbageAnswersNeitherCrashNorMultiplyTheCalls(_ profile: HostProfile) {
        let (turns, failures) = Self.turns(on: profile, answers: HostAnswers(garbageEvery: 3, random: HostStress.SplitMix(seed: 76)))
        let over = Self.over(turns)
        #expect(over.isEmpty, "\(over.count) over the limits: \(over.prefix(5))")
        let broken = failures.filter { $0.message.contains("past the text's end") || $0.message.contains("still composed") }
        #expect(broken.isEmpty, "\(broken.prefix(5))")
        #expect(turns.count > 1000)
    }

    /// The budget catches what it is for: `.` reading the text around the caret, as it did before (13 calls, 8 of them
    /// substrings, on a field that tells no length) would be over it.
    @Test func theLimitsCatchAKeyReadingTheWholeText() {
        let reading = HostTurnCalls(line: 1, what: ".", calls: {
            var calls = HostCallCount()
            for _ in 0..<8 { calls.add(.substring) }
            for _ in 0..<5 { calls.add(.selectedRange) }
            return calls
        }(), spent: 0)
        #expect(Self.over([reading]).count == 1)
    }
}

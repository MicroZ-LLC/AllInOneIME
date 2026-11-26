import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Random scenarios (`HostStress`) from fixed seeds, on every profile, checked after every step
/// (`HostRun.checkStrictInvariants`): nothing typed lost or doubled, nothing marked in the field, the panel there while
/// something is composed and only then, and gone from a field that lost the focus. A failure is shrunk to the fewest
/// steps that still fail the same way and reported as a scenario file, to keep as a fixed one (Tests/HostScenarios, or
/// `HostKnownIssues` while it waits for the owner). `ALLINONEIME_HOST_STRESS=<runs>` (and
/// `ALLINONEIME_HOST_STRESS_SEED=<first>`) for a long run.
struct HostStressTests {
    /// CI's runs on each profile (the profiles side by side): a second or two.
    static let fixedRuns = 60
    /// Failures shrunk and reported on a profile in one run, at most.
    static let reported = 4

    @Test(arguments: HostProfile.allCases)
    func randomScenariosHold(on profile: HostProfile) {
        var reports: Set<String> = []
        for seed in HostStress.seeds(fixed: Self.fixedRuns) {
            let (header, steps) = HostStress.scenario(seed: seed)
            guard let failure = HostRun.firstStrictFailure(header, steps, on: profile) else { continue }
            let kind = HostRun.kind(of: failure.message)
            let minimal = HostStress.shrink(steps) { trial in
                HostRun.firstStrictFailure(header, trial, on: profile).map { HostRun.kind(of: $0.message) == kind } ?? false
            }
            let file = HostStress.text(header.map { $0.hasPrefix("PROFILES") ? "PROFILES \(profile.rawValue)" : $0 }, minimal)
            guard !reports.contains(file), reports.count < Self.reported else { continue }
            reports.insert(file)
            let shrunk = HostRun.firstStrictFailure(header, minimal, on: profile)
            let report = Comment(rawValue: """
                seed \(seed) [\(profile.rawValue)]: \(failure.message)
                minimal (\(minimal.count) of \(steps.count) steps), failing at line \(shrunk?.line ?? 0): \(shrunk?.message ?? "")
                \(file)
                """)
            if let known = HostKnownIssues.matching(minimal, kind: kind, on: profile) {
                withKnownIssue(Comment(rawValue: known)) { Issue.record(report) }
            } else {
                Issue.record(report)
            }
        }
    }

    /// The same seed makes the same scenario, and shrinking keeps what still fails.
    @Test func theGeneratorIsSeededAndShrinks() {
        #expect(HostStress.scenario(seed: 7).steps == HostStress.scenario(seed: 7).steps)
        #expect(HostStress.scenario(seed: 7).steps != HostStress.scenario(seed: 8).steps)
        let steps = (0..<30).map { "TYPE a\($0)" }
        let minimal = HostStress.shrink(steps) { $0.contains("TYPE a7") && $0.contains("TYPE a21") }
        #expect(minimal == ["TYPE a7", "TYPE a21"])
        #expect(HostStress.seeds(fixed: 3, environment: [:]) == [1, 2, 3])
        #expect(HostStress.seeds(fixed: 3, environment: ["ALLINONEIME_HOST_STRESS": "2", "ALLINONEIME_HOST_STRESS_SEED": "50"]) == [50, 51])
    }

    /// Every generated scenario reads, in the format both runners take.
    @Test func everyGeneratedScenarioReads() throws {
        for seed in UInt64(1)...50 {
            let (header, steps) = HostStress.scenario(seed: seed)
            _ = try HostCaseParser.parse(HostStress.text(header, steps), fallbackName: "stress")
        }
    }
}

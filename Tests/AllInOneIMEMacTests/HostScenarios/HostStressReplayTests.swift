import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMETestSupport
import Foundation
import Testing

/// The core's random scenarios (`HostStress`, the same seeds) replayed through the Mac's own reading and anchoring code
/// (`HostReplayer`) on each of its profiles, checked after every step: nothing typed lost or doubled, nothing left
/// marked in the field. Without "@" drafts: the replayer's session has the default AI provider, and nothing may leave
/// the process. A failure is shrunk to the fewest steps that still fail and reported as a scenario file.
/// `ALLINONEIME_HOST_STRESS=<runs>` for a long run, as the core's.
@MainActor
struct HostStressReplayTests {
    static let fixedRuns = 25

    @Test(arguments: HostProfile.allCases)
    func randomScenariosHoldThroughTheMacsCode(on profile: HostProfile) throws {
        var reported = 0
        for seed in HostStress.seeds(fixed: Self.fixedRuns) {
            let (header, steps) = HostStress.scenario(seed: seed, HostStress.Options(drafts: false))
            guard let failure = try Self.firstFailure(header, steps, on: profile), reported < 3 else { continue }
            reported += 1
            let minimal = HostStress.shrink(steps) { (try? Self.firstFailure(header, $0, on: profile)) != nil }
            let file = HostStress.text(header.map { $0.hasPrefix("PROFILES") ? "PROFILES \(profile.rawValue)" : $0 }, minimal)
            Issue.record(Comment(rawValue: "seed \(seed) [\(profile.rawValue)]: \(failure)\nminimal:\n\(file)"))
        }
    }

    /// The first failure of `steps` on `profile`, each step followed by the checks; nil: none.
    static func firstFailure(_ header: [String], _ steps: [String], on profile: HostProfile) throws -> String? {
        let checked = steps.flatMap { [$0, "EXPECT nolost", "EXPECT marked none"] }
        let scenario = try HostCase.parse(HostStress.text(header, checked), source: "stress")
        let replayer = HostReplayer(scenario, profile: profile)
        replayer.run()
        return replayer.failures.first
    }
}

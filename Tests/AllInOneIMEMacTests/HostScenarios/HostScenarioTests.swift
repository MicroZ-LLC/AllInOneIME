import AllInOneIMECore
import AllInOneIMEMac
import Foundation
import Testing

/// The host scenarios (`Core/Tests/HostScenarios/*.hostcase`, the host scenario contract v1) replayed through the input
/// method's own reading and anchoring code (`HostReplayer`), on every profile each names: what the core's runner checks
/// against its model of a host, checked here against the Mac's code over an `IMKTextInput` that behaves as each host
/// does (`ProfiledTextClient`).
@MainActor
struct HostScenarioTests {
    /// The scenario files, where the core's tests keep them.
    nonisolated static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Core/Tests/HostScenarios")

    nonisolated static var files: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "hostcase" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Every scenario file, on each of its profiles: each expectation that doesn't hold is an issue, with the file and
    /// line, the profile, and what happened before it.
    @Test(.enabled(if: !files.isEmpty, "no Core/Tests/HostScenarios/*.hostcase yet"))
    func theScenarioFilesHoldOnEveryProfile() throws {
        for file in Self.files {
            let scenario = try HostCase.parse(String(contentsOf: file, encoding: .utf8), source: file.lastPathComponent)
            for profile in scenario.profiles {
                Self.replay(scenario, on: profile)
            }
        }
    }

    /// The local smoke cases, on each of their profiles.
    @Test(arguments: HostSmokeCases.all)
    func smokeCase(_ smoke: HostSmokeCases.Case) throws {
        let scenario = try HostCase.parse(smoke.text, source: smoke.name)
        #expect(!scenario.steps.isEmpty)
        for profile in scenario.profiles {
            Self.replay(scenario, on: profile)
        }
    }

    /// Replays `scenario` on `profile`: an issue for each expectation that didn't hold.
    @discardableResult
    static func replay(_ scenario: HostCase, on profile: HostProfile, sourceLocation: SourceLocation = #_sourceLocation) -> HostReplayer {
        let replayer = HostReplayer(scenario, profile: profile)
        replayer.run()
        for failure in replayer.failures {
            Issue.record("\(scenario.source) [\(profile)] \(scenario.name): \(failure)\n\(replayer.trace.suffix(30).joined(separator: "\n"))",
                         sourceLocation: sourceLocation)
        }
        return replayer
    }
}

/// Three scenarios of the replayer's own, written in the contract's format: until the scenario authors' files are there,
/// they show the replay works end to end on every profile.
enum HostSmokeCases {
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var text: String
        var testDescription: String { name }
    }

    static let all = [pinyinCommitsOnce, shiftTapSwitchesOnce, autocompleteReadsWhatTheFieldTells]

    /// Pinyin typed and picked with Space goes into the field once, after what was there, nothing left marked, the panel
    /// gone; no key asks the field's length more than once.
    static let pinyinCommitsOnce = Case(name: "pinyin commits once", text: #"""
        NAME   typed pinyin goes in once with Space
        PROFILES all
        LANG   chinese
        TEXT   "Hi Bob|"
        TYPE   nihao
        EXPECT panel shown
        KEY    space
        EXPECT doc "Hi Bob你好"
        EXPECT marked none
        EXPECT panel hidden
        EXPECT nolost
        EXPECT calls length<=1
        """#)

    /// A tap of Shift switches the input language once, whatever copies of its changes the host sends, and the next tap
    /// switches it back.
    static let shiftTapSwitchesOnce = Case(name: "a tap of Shift switches once", text: #"""
        NAME   a tap of Shift switches the language once, its copies don't
        PROFILES all
        LANG   chinese
        TEXT   "|"
        KEY    shift
        WAIT   300ms              # Electron's copies come late
        EXPECT lang english
        EXPECT switches 1
        TYPE   ok
        EXPECT doc "ok"
        KEY    shift
        WAIT   300ms
        EXPECT lang chinese
        EXPECT switches 1
        """#)

    /// What autocomplete and the AI read before the caret, as each field tells it (a field that tells no length tells
    /// nothing to read: a local case, with the profiles' differences as they are today).
    static let autocompleteReadsWhatTheFieldTells = Case(name: "what autocomplete reads", text: #"""
        NAME   what autocomplete reads before the caret
        PROFILES all
        LANG   english
        TEXT   "Hello wor|ld"
        EXPECT context before "Hello wor"   @profile nstextview
        EXPECT context unreadable           @profile chromium electron tellsnothing
        CLICK  inside 5
        EXPECT context before "Hello"       @profile nstextview
        """#)
}

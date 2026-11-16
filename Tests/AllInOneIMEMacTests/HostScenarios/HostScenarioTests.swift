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

    /// Leaving a field mid-composition (#115, #116), on each of their profiles: nothing is marked in the field, so no host
    /// has anything to commit, and the click reaches the input method as `SessionEvent.pointerDown` (contract v1.4).
    @Test(arguments: LeavingCases.all)
    func leavingCase(_ leaving: HostSmokeCases.Case) throws {
        let scenario = try HostCase.parse(leaving.text, source: leaving.name)
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

    /// What autocomplete and the AI read before the caret, as each field tells it: Chromium and Electron tell length 0
    /// but read back up to the caret (`FieldTextReading.readToTheCaret`); a field that tells no caret, nothing.
    static let autocompleteReadsWhatTheFieldTells = Case(name: "what autocomplete reads", text: #"""
        NAME   what autocomplete reads before the caret
        PROFILES all
        LANG   english
        TEXT   "Hello wor|ld"
        EXPECT context before "Hello wor"   @profile nstextview chromium electron
        EXPECT context unreadable           @profile tellsnothing
        CLICK  inside 5
        EXPECT context before "Hello"       @profile nstextview
        """#)
}

/// Leaving a field while pinyin is typed and not yet confirmed leaves nothing of it there, and hides the panel, in every
/// app (the owner, 2026-11-15; #116): what is typed is only ever in the panel's input line (`EXPECT preedit`), never
/// marked in the field. Real-Mac runs in Brave and an AppKit harness are in the PR.
enum LeavingCases {
    static let all = [clickElsewhere, clickInside, closeWindow]

    /// A click in another field (or anywhere else) mid-composition: nothing goes in, the panel goes; the next key in the
    /// field starts afresh.
    static let clickElsewhere = HostSmokeCases.Case(name: "a click elsewhere leaves nothing", text: #"""
        NAME   a click elsewhere mid-composition leaves nothing of it
        PROFILES all
        LANG   chinese
        TEXT   "Hi |"
        TYPE   nihao
        EXPECT marked none
        EXPECT preedit "nihao|"
        EXPECT panel shown
        CLICK  outside
        EXPECT doc "Hi "
        EXPECT preedit none
        EXPECT panel hidden
        FOCUS  back
        TYPE   wo
        EXPECT preedit "wo"
        KEY    space
        EXPECT doc "Hi 我"
        EXPECT nolost
        """#)

    /// A click inside the same field: the same, the next key composes afresh at the caret.
    static let clickInside = HostSmokeCases.Case(name: "a click inside the field leaves nothing", text: #"""
        NAME   a click in the same field mid-composition leaves nothing of it
        PROFILES all
        LANG   chinese
        TEXT   "Hi |"
        TYPE   nihao
        CLICK  inside 0
        EXPECT doc "Hi "
        EXPECT marked none
        EXPECT preedit none
        EXPECT panel hidden
        TYPE   wo
        EXPECT preedit "wo"
        KEY    space
        EXPECT doc "我Hi "
        EXPECT nolost
        """#)

    /// The window (a tab) closes mid-composition: nothing goes in.
    static let closeWindow = HostSmokeCases.Case(name: "closing the window leaves nothing", text: #"""
        NAME   closing the window mid-composition leaves nothing of it
        PROFILES all
        LANG   chinese
        TEXT   "Hi |"
        TYPE   nihao
        FOCUS  closewindow
        EXPECT doc "Hi "
        EXPECT marked none
        EXPECT panel hidden
        """#)
}

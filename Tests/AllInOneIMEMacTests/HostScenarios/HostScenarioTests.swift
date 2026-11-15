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

    /// Leaving a field mid-composition, and the app emptying it (#115, #116), on each of their profiles. Chromium's and
    /// Electron's are known issues where the page ends the marked text before the input method is told anything (a
    /// real Brave, 2026-11-15): a click (the page commits it on the mouse down, unless the mouse tap is on), the tab
    /// closed or the focus lost otherwise (the page commits it on blur), the page emptying the field (it says nothing);
    /// so is a click in the marked text on every host without the tap (none tells it: a real NSTextField and NSTextView).
    @Test(arguments: LeavingCases.all)
    func leavingCase(_ leaving: HostSmokeCases.Case) throws {
        let scenario = try HostCase.parse(leaving.text, source: leaving.name)
        for profile in scenario.profiles {
            // Without the tap no host tells the input method of a click in the marked text: it stays marked (#116).
            if profile.isChromium || leaving.name == LeavingCases.clickInside.name {
                withKnownIssue("the host ends or keeps the marked text before the input method is told (#115, #116)") {
                    Self.replay(scenario, on: profile)
                }
            } else {
                Self.replay(scenario, on: profile)
            }
        }
    }

    /// With the mouse tap on (Accessibility allowed), the input method drops what is marked on a mouse down before any
    /// host has the click: a click leaves nothing in every host, Chromium's too.
    @Test(arguments: [LeavingCases.clickElsewhere, LeavingCases.clickInside])
    func withTheMouseTapAClickLeavesNothing(_ leaving: HostSmokeCases.Case) throws {
        let scenario = try HostCase.parse(leaving.text, source: leaving.name)
        for profile in scenario.profiles {
            let replayer = HostReplayer(scenario, profile: profile)
            replayer.tapAllowed = true
            replayer.run()
            for failure in replayer.failures {
                Issue.record("[\(profile)] \(failure)\n\(replayer.trace.suffix(30).joined(separator: "\n"))")
            }
        }
    }

    /// Without the tap, a Chromium page commits the pinyin as shown on a click: the input method puts nothing more in.
    @Test func withoutTheTapChromiumKeepsWhatItCommitsAndNothingMore() throws {
        Self.replay(try HostCase.parse(LeavingCases.chromiumClickWithoutTheTap, source: "no tap, chromium"), on: .chromium)
        Self.replay(try HostCase.parse(LeavingCases.chromiumClickWithoutTheTap, source: "no tap, electron"), on: .electron)
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

/// Leaving a field while pinyin is typed and not yet confirmed leaves nothing of it there, and hides the panel, in every
/// app (the owner, 2026-11-15; #116); a field the app empties mid-composition starts afresh on the next key, as AppKit's
/// fields do (#115). Real-Mac runs in Brave and an AppKit harness are in the PR; the AppKit profile's hold there (but a
/// click, which NSTextField and NSTextView don't tell the input method of without the mouse tap).
enum LeavingCases {
    static let all = [clickElsewhere, clickInside, closeWindow, appClears]

    /// A click in another field (or anywhere else) mid-composition: nothing goes in, the panel goes; the next key in the
    /// field starts afresh.
    static let clickElsewhere = HostSmokeCases.Case(name: "a click elsewhere leaves nothing", text: #"""
        NAME   a click elsewhere mid-composition leaves nothing of it
        PROFILES all
        LANG   chinese
        TEXT   "Hi |"
        TYPE   nihao
        EXPECT marked "nihao"
        EXPECT panel shown
        CLICK  outside
        EXPECT doc "Hi "
        EXPECT marked none
        EXPECT panel hidden
        FOCUS  back
        TYPE   wo
        EXPECT marked "wo"
        KEY    space
        EXPECT doc "Hi 我"
        EXPECT nolost
        """#)

    /// A click inside the same field, in the pinyin or after it: the same, the next key composes afresh at the caret.
    static let clickInside = HostSmokeCases.Case(name: "a click inside the field leaves nothing", text: #"""
        NAME   a click in the same field mid-composition leaves nothing of it
        PROFILES all
        LANG   chinese
        TEXT   "Hi |"
        TYPE   nihao
        CLICK  inside 5
        EXPECT doc "Hi "
        EXPECT marked none
        EXPECT panel hidden
        TYPE   wo
        EXPECT marked "wo"
        KEY    space
        EXPECT doc "Hi 我"
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

    /// The page empties the field mid-composition (a chat app's send) and tells nothing: the next key drops what was
    /// composed and starts afresh, as AppKit's fields do; what was typed before doesn't come back. (A field that tells no
    /// marked range, a terminal or WeChat, gives nothing to see it by.)
    static let appClears = HostSmokeCases.Case(name: "the app empties the field", text: #"""
        NAME   a field emptied mid-composition starts afresh on the next key
        PROFILES nstextview chromium electron
        LANG   chinese
        TEXT   "|"
        TYPE   nihao
        APP    clears
        TYPE   wo
        EXPECT marked "wo"
        KEY    space
        EXPECT doc "我"
        EXPECT marked none
        EXPECT panel hidden
        EXPECT nolost
        """#)

    /// Without the tap, a Chromium page commits the pinyin as shown on the mouse down, before the input method is told
    /// anything (the fallback, #116): the input method puts nothing more in, and its next key starts afresh.
    static let chromiumClickWithoutTheTap = #"""
        NAME   without the tap, Chromium keeps what it committed itself and nothing more
        PROFILES chromium electron
        LANG   chinese
        TEXT   "Hi |"
        TYPE   nihao
        CLICK  outside
        EXPECT doc "Hi nihao"
        EXPECT marked none
        EXPECT panel hidden
        EXPECT nolost
        FOCUS  back
        TYPE   wo
        EXPECT marked "wo"
        """#
}

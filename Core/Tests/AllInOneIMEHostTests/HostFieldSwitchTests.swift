import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The review of #180 (PR #188), on every profile: a draft kept for a field that lost the focus never shows in another
/// field of the same app (`FOCUS otherfield`: the same `FieldInfo` to the session, so the shell tells the fields apart,
/// holding the draft through the focus and dropping it: `InputSession.holdKeptDraft`, `SessionEvent.cancel`), and the
/// runs' own check catches a draft still kept once the input source is ABC.
struct HostFieldSwitchTests {
    private static func run(_ source: String, on profile: HostProfile) throws -> (run: HostRun, failures: [HostFailure]) {
        let scenario = try HostCaseParser.parse(source, fallbackName: "field-switch")
        return UIText.$scopedInterface.withValue(UIText.ScopedInterface(choice: "en", commandTrigger: "@")) {
            let run = HostRun(scenario, profile: profile)
            return (run, run.run())
        }
    }

    /// `@q` + the focus lost without a click + another field of the same app: nothing of `"@q"` shows or goes in
    /// there, it types as any field, and the first field doesn't get `"@q"` back later.
    @Test(arguments: HostProfile.allCases)
    func atListDroppedWhenAnotherFieldOfTheSameAppTakesTheFocus(_ profile: HostProfile) throws {
        let (run, failures) = try Self.run("""
            LANG english
            TEXT "你好|"
            TYPE "@q"
            EXPECT preedit "q"
            EXPECT panel shown
            FOCUS away
            EXPECT doc "你好"
            EXPECT panel hidden
            EXPECT nolost
            FOCUS otherfield
            EXPECT doc ""
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            TYPE "abc"
            EXPECT doc "abc"
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            EXPECT nolost
            FOCUS away
            FOCUS back
            EXPECT doc "你好"
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            EXPECT nolost
            """, on: profile)
        #expect(failures.isEmpty, "[\(profile.rawValue)] \(failures)")
        #expect(run.host.document == "你好" && !run.host.session.keepsDraft, "[\(profile.rawValue)] \(run.host.document)")
    }

    /// The same with pinyin, the focus going straight to the other field (no `FOCUS away` first): it composes its own.
    @Test(arguments: HostProfile.allCases)
    func pinyinDroppedWhenAnotherFieldOfTheSameAppTakesTheFocus(_ profile: HostProfile) throws {
        let (run, failures) = try Self.run("""
            LANG chinese
            TEXT "Hi |"
            TYPE nihao
            EXPECT preedit "ni hao"
            FOCUS otherfield
            EXPECT doc ""
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            TYPE wo
            EXPECT preedit "wo"
            KEY space
            EXPECT doc "我"
            EXPECT panel hidden
            EXPECT nolost
            FOCUS away
            FOCUS back
            EXPECT doc "Hi "
            EXPECT panel hidden
            EXPECT preedit none
            EXPECT nolost
            """, on: profile)
        #expect(failures.isEmpty, "[\(profile.rawValue)] \(failures)")
        #expect(run.host.document == "Hi " && !run.host.session.keepsDraft, "[\(profile.rawValue)] \(run.host.document)")
    }

    /// The runs' check (`HostRun.checkInvariants`): a draft the session still keeps once the input source is ABC is
    /// a failure, with nothing showing too (the check let it by while it was only told "kept, and no panel").
    @Test func aDraftKeptOnceTheInputSourceIsABCIsCaught() throws {
        let (run, failures) = try Self.run("LANG chinese\nTEXT \"Hi |\"\nTYPE nihao\nFOCUS away", on: .nstextview)
        #expect(failures.isEmpty && run.host.session.keepsDraft && run.host.panel == nil, "\(failures)")
        run.checkInvariants()
        #expect(run.failures.isEmpty, "kept for the field, nothing showing: allowed. \(run.failures)")
        run.inABC = true
        run.checkInvariants()
        #expect(run.failures.count == 1 && run.failures.first?.message.contains("ABC") == true, "\(run.failures)")
        // As a scenario has it: the system has the input method commit first, and nothing is kept.
        let (switched, none) = try Self.run("LANG chinese\nTEXT \"Hi |\"\nTYPE nihao\nSWITCH abc\nEXPECT doc \"Hi \"", on: .nstextview)
        #expect(none.isEmpty && !switched.host.session.keepsDraft && !switched.host.composer.isComposing, "\(none)")
    }
}

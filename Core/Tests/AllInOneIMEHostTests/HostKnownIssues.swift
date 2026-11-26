import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// What the stress runs (`HostStressTests`) found that differs from profile to profile and isn't fixed: each a minimal
/// scenario, replayed here as a known issue (it fails where it says, and this test says so once it no longer does), and
/// recognised in a stress run's failures so that a run finds what is new. Each waits for the owner: the fix is a choice
/// of what the user sees (AGENTS.md rule 1), not a small fix.
enum HostKnownIssues {
    /// The "@" list's text ("@q", a command's name not picked yet) is put in when the field loses the focus without a
    /// click (⌘-Tab, Tab to another field, the window closing): the session commits it on `blur`. A field that takes text
    /// while the input method lets it go (AppKit's, Qt's, a terminal, WeChat) gets "@q"; one that has already let go
    /// (Chromium, Electron, WebKit: `HostProfile.blurDropsComposition`) drops it, and what was typed is gone. Pinyin is
    /// dropped on every profile then, and so is a command picked with its text (49_draft_focus_away): only this differs.
    /// A click doesn't (`pointerDown` drops it first everywhere), nor switching to ABC (`commit` comes before `blur`).
    /// Owner's question: drop "@…" as pinyin is, or keep it everywhere (which a page can't take after its blur)?
    static let atListLostOnBlur = """
        NAME the "@" list's text when the field loses the focus
        PROFILES all
        LANG english
        TEXT "你好|"
        TYPE "@q"
        FOCUS away
        EXPECT nolost
        """

    static let atListLostOnBlurSummary = "\"@…\" committed on blur is lost where the field let go first (HostKnownIssues.atListLostOnBlur)"

    /// Which known issue a stress failure is, from its minimal steps, its kind and its profile; nil: none.
    static func matching(_ steps: [String], kind: String, on profile: HostProfile) -> String? {
        let draft = steps.contains { $0.hasPrefix("TYPE \"@") }
        let blur = steps.contains { $0.hasPrefix("FOCUS away") || $0.hasPrefix("FOCUS otherapp") || $0.hasPrefix("FOCUS closewindow") }
        if draft, blur, profile.blurDropsComposition, kind == "characters lost or doubled:" { return atListLostOnBlurSummary }
        return nil
    }
}

struct HostKnownIssuesTests {
    /// `HostKnownIssues.atListLostOnBlur` on every profile: lost where the field let go first, in everywhere else.
    @Test(arguments: HostProfile.allCases)
    func atListLostOnBlur(_ profile: HostProfile) throws {
        let scenario = try HostCaseParser.parse(HostKnownIssues.atListLostOnBlur, fallbackName: "known")
        let failures = UIText.$scopedInterface.withValue(UIText.ScopedInterface(choice: "en", commandTrigger: "@")) {
            HostRun(scenario, profile: profile).run()
        }
        withKnownIssue(Comment(rawValue: HostKnownIssues.atListLostOnBlurSummary)) {
            for failure in failures { Issue.record(Comment(rawValue: "line \(failure.line): \(failure.message)")) }
        } when: {
            profile.blurDropsComposition
        }
        if !profile.blurDropsComposition { #expect(failures.isEmpty, "\(failures)") }
    }
}

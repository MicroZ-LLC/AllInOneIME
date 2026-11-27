import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Acceptance tests for GitHub #180 (owner decision: keep the draft when focus is lost without a click).
///
/// One behaviour in every app/profile (`HostProfile.allCases`):
/// 1. Non-click blur (`FOCUS away`, `FOCUS otherapp`): the panel hides, and the draft (pinyin, or what was typed for
///    the `@` list, e.g. `"@q"`) is kept for that field — nothing of it goes into the field, and nothing is lost.
/// 2. Back in the same field (`FOCUS back`): the panel and the draft come back as they were (same draft text, same
///    pinyin, the `@` list again), and typing goes on from there (`Return`, `Tab`, `Space`, etc. act as before).
/// 3. Focus went to another field instead (`FOCUS other`): the old draft is dropped, and the new field starts clean
///    (returning to the first field later does not resurrect it).
/// 4. Focus lost by a click (`CLICK inside`, `CLICK outside`): unchanged from today.
struct BlurDraftAcceptanceTests {
    private static func run(_ source: String, on profile: HostProfile) throws -> (run: HostRun, failures: [HostFailure]) {
        let scenario = try HostCaseParser.parse(source, fallbackName: "blur-draft")
        return UIText.$scopedInterface.withValue(UIText.ScopedInterface(choice: "en", commandTrigger: "@")) {
            let run = HostRun(scenario, profile: profile)
            return (run, run.run())
        }
    }

    // MARK: - 1 & 2. Non-click blur keeps draft; returning to the same field restores it

    /// `@q` (open `@` list) + non-click blur (`FOCUS away`) + return to the same field (`FOCUS back`):
    /// while unfocused, panel hides and nothing enters or is dropped by the field; on return, the `@` list and `"@q"`
    /// come back, and pressing Return picks `@question` and continues typing as before.
    @Test(arguments: HostProfile.allCases)
    func atListKeptOnBlurAndRestoredOnReturn(_ profile: HostProfile) throws {
        let (run, failures) = try Self.run("""
            LANG english
            TEXT "你好|"
            TYPE "@q"
            EXPECT doc "你好|"
            EXPECT marked none
            EXPECT preedit "q"
            EXPECT panel shown
            FOCUS away
            EXPECT doc "你好"
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            EXPECT nolost
            FOCUS back
            EXPECT doc "你好"
            EXPECT marked none
            EXPECT panel shown
            EXPECT preedit "q"
            KEY enter
            TYPE "hi"
            EXPECT doc "你好"
            EXPECT marked none
            EXPECT panel shown
            EXPECT preedit "question › hi"
            EXPECT nolost
            """, on: profile)
        #expect(failures.isEmpty, "[\(profile.rawValue)] \(failures)")
        #expect(run.host.document == "你好", "[\(profile.rawValue)] field text: \(run.host.document)")
    }

    /// `@q` + `FOCUS otherapp` (e.g. ⌘Tab away) + `FOCUS back`, then typing more filter letters and picking with Tab.
    @Test(arguments: HostProfile.allCases)
    func atListKeptAcrossOtherAppAndTypingContinues(_ profile: HostProfile) throws {
        let (run, failures) = try Self.run("""
            LANG english
            TEXT "你好|"
            TYPE "@q"
            EXPECT preedit "q"
            EXPECT panel shown
            FOCUS otherapp
            EXPECT doc "你好"
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            EXPECT nolost
            FOCUS back
            EXPECT doc "你好"
            EXPECT marked none
            EXPECT panel shown
            EXPECT preedit "q"
            TYPE "u"
            EXPECT preedit "qu"
            EXPECT panel shown
            KEY tab
            TYPE "ok"
            EXPECT preedit "question › ok"
            EXPECT panel shown
            EXPECT doc "你好"
            KEY escape
            EXPECT doc "你好"
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            EXPECT nolost
            """, on: profile)
        #expect(failures.isEmpty, "[\(profile.rawValue)] \(failures)")
        #expect(run.host.document == "你好", "[\(profile.rawValue)] field text: \(run.host.document)")
    }

    /// Unpicked pinyin (`nihao`) + non-click blur (`FOCUS away`) + return to the same field (`FOCUS back`):
    /// while unfocused, panel hides and nothing goes into the field; on return, the panel and `"ni hao"` come back,
    /// and Space confirms `"你好"` as before the focus loss.
    @Test(arguments: HostProfile.allCases)
    func pinyinKeptOnBlurAndRestoredOnReturn(_ profile: HostProfile) throws {
        let (run, failures) = try Self.run("""
            LANG chinese
            TEXT "Hi |"
            TYPE nihao
            EXPECT doc "Hi |"
            EXPECT marked none
            EXPECT preedit "ni hao"
            EXPECT panel shown
            FOCUS away
            EXPECT doc "Hi "
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            EXPECT nolost
            FOCUS back
            EXPECT doc "Hi "
            EXPECT marked none
            EXPECT panel shown
            EXPECT preedit "ni hao"
            KEY space
            EXPECT doc "Hi 你好"
            EXPECT marked none
            EXPECT preedit none
            EXPECT panel hidden
            EXPECT nolost
            """, on: profile)
        #expect(failures.isEmpty, "[\(profile.rawValue)] \(failures)")
        #expect(run.host.document == "Hi 你好", "[\(profile.rawValue)] field text: \(run.host.document)")
    }

    /// Partial pinyin (`ni`) + `FOCUS otherapp` (⌘Tab away) + `FOCUS back`, then typing `hao` and confirming with Space.
    @Test(arguments: HostProfile.allCases)
    func pinyinKeptAcrossOtherAppAndTypingContinues(_ profile: HostProfile) throws {
        let (run, failures) = try Self.run("""
            LANG chinese
            TEXT "Hi |"
            TYPE ni
            EXPECT doc "Hi |"
            EXPECT marked none
            EXPECT preedit "ni"
            EXPECT panel shown
            FOCUS otherapp
            EXPECT doc "Hi "
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            EXPECT nolost
            FOCUS back
            EXPECT doc "Hi "
            EXPECT marked none
            EXPECT panel shown
            EXPECT preedit "ni"
            TYPE hao
            EXPECT preedit "ni hao"
            EXPECT panel shown
            KEY space
            EXPECT doc "Hi 你好"
            EXPECT marked none
            EXPECT preedit none
            EXPECT panel hidden
            EXPECT nolost
            """, on: profile)
        #expect(failures.isEmpty, "[\(profile.rawValue)] \(failures)")
        #expect(run.host.document == "Hi 你好", "[\(profile.rawValue)] field text: \(run.host.document)")
    }

    /// Unpicked pinyin (`nihao`) + `FOCUS away` + `FOCUS back` + Return commits raw letters as before the focus loss.
    @Test(arguments: HostProfile.allCases)
    func pinyinRestoredOnReturnStillRespondsToReturn(_ profile: HostProfile) throws {
        let (run, failures) = try Self.run("""
            LANG chinese
            TEXT "Hi |"
            TYPE nihao
            EXPECT preedit "ni hao"
            EXPECT panel shown
            FOCUS away
            EXPECT doc "Hi "
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            EXPECT nolost
            FOCUS back
            EXPECT panel shown
            EXPECT preedit "ni hao"
            KEY enter
            EXPECT doc "Hi nihao"
            EXPECT marked none
            EXPECT preedit none
            EXPECT panel hidden
            EXPECT nolost
            """, on: profile)
        #expect(failures.isEmpty, "[\(profile.rawValue)] \(failures)")
        #expect(run.host.document == "Hi nihao", "[\(profile.rawValue)] field text: \(run.host.document)")
    }

    // MARK: - 3. Focus moves to another field instead: old draft dropped, new field starts clean

    /// `@q` + non-click blur + `FOCUS other`: nothing of `"@q"` entered the first field or was lost; the new field
    /// starts clean and accepts normal typing; returning to the first field later does not bring `"@q"` back.
    @Test(arguments: HostProfile.allCases)
    func atListDroppedWhenFocusMovesToOtherField(_ profile: HostProfile) throws {
        let (run, failures) = try Self.run("""
            LANG english
            TEXT "你好|"
            TYPE "@q"
            EXPECT preedit "q"
            EXPECT panel shown
            FOCUS away
            EXPECT doc "你好"
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            EXPECT nolost
            FOCUS other
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
        #expect(run.host.document == "你好", "[\(profile.rawValue)] field text: \(run.host.document)")
    }

    /// `nihao` (pinyin) + non-click blur + `FOCUS other`: nothing of `nihao` entered the first field; the new field
    /// starts clean and composes fresh pinyin; returning to the first field later does not bring `nihao` back.
    @Test(arguments: HostProfile.allCases)
    func pinyinDroppedWhenFocusMovesToOtherField(_ profile: HostProfile) throws {
        let (run, failures) = try Self.run("""
            LANG chinese
            TEXT "Hi |"
            TYPE nihao
            EXPECT preedit "ni hao"
            EXPECT panel shown
            FOCUS away
            EXPECT doc "Hi "
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            EXPECT nolost
            FOCUS other
            EXPECT doc ""
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            TYPE wo
            EXPECT preedit "wo"
            EXPECT panel shown
            KEY space
            EXPECT doc "我"
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            EXPECT nolost
            FOCUS away
            FOCUS back
            EXPECT doc "Hi "
            EXPECT marked none
            EXPECT panel hidden
            EXPECT preedit none
            EXPECT nolost
            """, on: profile)
        #expect(failures.isEmpty, "[\(profile.rawValue)] \(failures)")
        #expect(run.host.document == "Hi ", "[\(profile.rawValue)] field text: \(run.host.document)")
    }

    // MARK: - 4. Click cases: unchanged from today

    /// Clicking elsewhere inside the field drops unpicked pinyin and moves the caret; subsequent typing starts clean.
    @Test(arguments: HostProfile.allCases)
    func clickInsideFieldDropsPinyin(_ profile: HostProfile) throws {
        let (run, failures) = try Self.run("""
            LANG chinese
            TEXT "Hi |"
            TYPE nihao
            EXPECT marked none
            EXPECT preedit "ni hao"
            EXPECT panel shown
            CLICK inside 0
            EXPECT doc "|Hi "
            EXPECT marked none
            EXPECT preedit none
            EXPECT panel hidden
            EXPECT nolost
            TYPE wo
            KEY space
            EXPECT doc "我|Hi "
            EXPECT marked none
            EXPECT preedit none
            EXPECT panel hidden
            EXPECT nolost
            """, on: profile)
        #expect(failures.isEmpty, "[\(profile.rawValue)] \(failures)")
        #expect(run.host.document == "我Hi ", "[\(profile.rawValue)] field text: \(run.host.document)")
    }

    /// Clicking outside the field drops unpicked pinyin; even if focus leaves and returns, the clicked-away pinyin does
    /// not come back.
    @Test(arguments: HostProfile.allCases)
    func clickOutsideFieldDropsPinyinAndReturnStaysClean(_ profile: HostProfile) throws {
        let (run, failures) = try Self.run("""
            LANG chinese
            TEXT "Hi |"
            TYPE nihao
            EXPECT marked none
            EXPECT preedit "ni hao"
            EXPECT panel shown
            CLICK outside
            EXPECT doc "Hi "
            EXPECT marked none
            EXPECT preedit none
            EXPECT panel hidden
            EXPECT nolost
            FOCUS away
            FOCUS back
            EXPECT doc "Hi "
            EXPECT marked none
            EXPECT preedit none
            EXPECT panel hidden
            EXPECT nolost
            """, on: profile)
        #expect(failures.isEmpty, "[\(profile.rawValue)] \(failures)")
        #expect(run.host.document == "Hi ", "[\(profile.rawValue)] field text: \(run.host.document)")
    }

    /// Clicking inside the field while the `@` list is open (`"@q"`): unchanged from today (`pointerDown` commits `"@q"`
    /// into the field before moving the caret and hides the panel on every profile).
    @Test(arguments: HostProfile.allCases)
    func clickInsideFieldWithAtListUnchanged(_ profile: HostProfile) throws {
        let (run, failures) = try Self.run("""
            LANG english
            TEXT "你好|"
            TYPE "@q"
            EXPECT marked none
            EXPECT preedit "q"
            EXPECT panel shown
            CLICK inside 0
            EXPECT doc "|你好@q"
            EXPECT marked none
            EXPECT preedit none
            EXPECT panel hidden
            EXPECT nolost
            """, on: profile)
        #expect(failures.isEmpty, "[\(profile.rawValue)] \(failures)")
        #expect(run.host.document == "你好@q", "[\(profile.rawValue)] field text: \(run.host.document)")
    }

    /// Clicking outside the field while the `@` list is open (`"@q"`): unchanged from today (`pointerDown` commits `"@q"`
    /// into the field and hides the panel on every profile; subsequent blur/return leaves it settled).
    @Test(arguments: HostProfile.allCases)
    func clickOutsideFieldWithAtListUnchanged(_ profile: HostProfile) throws {
        let (run, failures) = try Self.run("""
            LANG english
            TEXT "你好|"
            TYPE "@q"
            EXPECT marked none
            EXPECT preedit "q"
            EXPECT panel shown
            CLICK outside
            EXPECT doc "你好@q"
            EXPECT marked none
            EXPECT preedit none
            EXPECT panel hidden
            EXPECT nolost
            FOCUS away
            FOCUS back
            EXPECT doc "你好@q"
            EXPECT marked none
            EXPECT preedit none
            EXPECT panel hidden
            EXPECT nolost
            """, on: profile)
        #expect(failures.isEmpty, "[\(profile.rawValue)] \(failures)")
        #expect(run.host.document == "你好@q", "[\(profile.rawValue)] field text: \(run.host.document)")
    }
}

import Foundation
import Testing

/// This week's stats in the input method, where the store and the session meet the windows and the fields: `@stats`'s
/// ⌘C tells its outcome in the field that asked, Forget All forgets at the click, and the user's own commands are kept by
/// the names the stats count them by. Read from the sources, as the input method can't be run here.
struct WeekStatsShellTests {
    /// The picture copied (or not) is told in the field whose ⌘C asked for it, while it is still that field's session;
    /// never in the field typed in by then, and nowhere once it was left.
    @Test func theCopiedNoticeGoesToTheFieldThatAsked() throws {
        let source = try AppAutocompleteDestinationTests.source("InputController.swift")
        let part = try #require(AppAutocompleteDestinationTests.part(source, from: "case .platform(.copyWeekStatsImage):",
                                                                     to: "// A row the key put in"))
        #expect(!part.contains("activeController"), "\(part)")
        #expect(part.contains("let asked = fieldSession"), "\(part)")
        #expect(part.contains("guard let self, self.fieldSession == asked else { return }"), "\(part)")
        #expect(part.contains("self.apply(self.session.weekStatsImageCopied(copied), client: nil)"), "\(part)")
    }

    /// Forget All (and the stats' own Forget) forgets in memory at the click, not in a task that starts later: a count
    /// between the two would be forgotten too.
    @Test func forgetAllForgetsAtTheClick() throws {
        let source = try AppAutocompleteDestinationTests.source("SettingsWindow.swift")
        let body = try #require(InputMenuWritesTests.body(of: "forgetWeekStats", in: source))
        #expect(body.contains("WeekStatsShared.store.forgetAll()"), "\(body)")
        #expect(!body.contains("Task") && !body.contains("await"), "\(body)")
        let all = try #require(InputMenuWritesTests.body(of: "forgetAllLearned", in: source))
        #expect(all.contains("forgetWeekStats()") && !all.contains("Task"), "\(all)")
    }

    /// The user's own commands are kept by the names the stats count them by (the command list's, in lower case), the
    /// same a run answered late is checked against.
    @Test func ownCommandsAreKeptByTheNamesTheStatsCount() throws {
        let source = try AppAutocompleteDestinationTests.source("WeekStatsSettings.swift")
        let body = try #require(InputMenuWritesTests.body(of: "keepOwnCommands", in: source))
        #expect(body.contains("store.stats.keepCommands(WeekStats.ownCommandNames(config), from: .own)"), "\(body)")
    }
}

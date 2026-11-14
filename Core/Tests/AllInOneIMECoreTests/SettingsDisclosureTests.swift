import Testing
@testable import AllInOneIMECore

@Suite("A folded part of Settings")
struct SettingsDisclosureTests {
    /// Something set in it opens it to begin with, and a click still folds it (it couldn't be folded before: "clicked or
    /// opens by itself").
    @Test func aClickFoldsWhatOpenedByItself() {
        var more = SettingsDisclosure()
        #expect(more.isExpanded(opensByItself: true))
        more.click(false)
        #expect(!more.isExpanded(opensByItself: true))
        more.click(true)
        #expect(more.isExpanded(opensByItself: true))
    }

    @Test func untilClickedItFollowsWhatOpensIt() {
        var folders = SettingsDisclosure()
        #expect(!folders.isExpanded(opensByItself: false))
        // A Git extension source added: open.
        #expect(folders.isExpanded(opensByItself: true))
        folders.click(true)
        #expect(folders.isExpanded(opensByItself: false), "opened by a click, it stays open")
        folders.click(false)
        #expect(!folders.isExpanded(opensByItself: true))
        // A new window (or the search pointing into it) starts over.
        folders.reset()
        #expect(folders.isExpanded(opensByItself: true) && !folders.isExpanded(opensByItself: false))
    }
}

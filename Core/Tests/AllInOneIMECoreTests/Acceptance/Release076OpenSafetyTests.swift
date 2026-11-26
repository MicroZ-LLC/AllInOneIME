import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Return after Tab completes a folder opens that folder; rows for its children remain available below it.
@Suite(.serialized)
struct Release076OpenSafetyTests {
    @Test func completedFolderIsTheFirstRowAndReturnOpensIt() async {
        await withInterfaceLanguage("en") {
            let folder = SearchResult(name: "Documents", path: "/Users/example/Documents", isFolder: true)
            let child = SearchResult(name: "Launch.app", path: "/Users/example/Documents/Launch.app")
            var config = Config.default
            config.uiLanguage = "en"
            config.setOrder([Language.english, .chinese])
            let fixed = config
            var services = SessionServices(loadSettings: { fixed })
            services.levelOne = { .engine(FakeEngine()) }
            services.programInstalled = { _ in true }
            services.instantResults = { query, _ in
                switch query {
                case "~/Doc": [folder]
                case "/Users/example/Documents/": [child]
                default: []
                }
            }
            let host = FakeHost(services: services)
            host.focus()
            host.type("@open ~/Doc")
            #expect(host.press(FakeHost.tab))
            #expect(host.composer.draft == "@open /Users/example/Documents/")
            #expect(host.panel?.rows.first?.text == "Documents", "the completed folder precedes its children")
            #expect(host.panel?.rows.dropFirst().contains { $0.text == "Launch.app" } == true)
            #expect(host.press(FakeHost.enter))
            #expect(host.opened == [folder.path], "Return without moving the highlight opens the folder")
        }
    }

    @Test func fileResultNamesStripBidiAndControlCharacters() async {
        await withInterfaceLanguage("en") {
            let unsafe = SearchResult(name: "report\u{202E}exe\u{0007}.txt", path: "/Users/example/report.txt")
            var config = Config.default
            config.uiLanguage = "en"
            config.setOrder([Language.english, .chinese])
            let fixed = config
            var services = SessionServices(loadSettings: { fixed })
            services.levelOne = { .engine(FakeEngine()) }
            services.programInstalled = { _ in true }
            services.instantResults = { query, _ in query == "report" ? [unsafe] : [] }
            let host = FakeHost(services: services)
            host.focus()
            host.type("@open report")
            let row = host.panel?.rows.first?.text ?? ""
            #expect(row == "reportexe.txt", "the display name must remove bidi and control characters: \(row)")
        }
    }
}

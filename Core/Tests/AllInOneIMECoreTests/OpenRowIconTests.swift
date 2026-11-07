import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A row that opens an app, a folder or a file carries that thing's own icon, by its path (`IconToken.Glyph.item`, the
/// shell draws it; `@open`'s symbol where it can't): one @'s rows for what is known at once and Spotlight's files, and
/// `@open`'s as its text is typed. A web address keeps `@open`'s symbol in one @ and no icon in `@open`, as before;
/// every other row keeps its command's.
struct OpenRowIconTests {
    static let safari = SearchResult(name: "Safari", path: "/Applications/Safari.app")
    static let sales = SearchResult(name: "Sales", path: "/Users/me/Documents/Sales", isFolder: true)
    static let report = SearchResult(name: "Sales report.pdf", path: "/Users/me/Documents/Sales report.pdf")
    static let found = SearchResult(name: "Sales 2026.numbers", path: "/Users/me/Desktop/Sales 2026.numbers")

    /// A field (English) whose instant results are `instant` for every text, and whose Spotlight finds `files`.
    func field(instant: [SearchResult], files: [SearchResult] = []) -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        let fixed = config
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(FakeEngine()) }
        services.instantResults = { _, _ in instant }
        services.searchFileNames = { _, _ in files }
        services.searchFiles = { _, _ in [] }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    static func own(_ result: SearchResult) -> IconToken { IconToken(.item(path: result.path, fallback: .open), color: .gray) }

    @Test func theTokenNamesTheItemAndFallsBackToOpen() {
        #expect(IconToken.item(Self.safari) == Self.own(Self.safari))
        #expect(IconToken.item(Self.sales)?.fallback == .open && IconToken.item(Self.sales)?.color == IconToken.command(.open).color)
        #expect(IconToken.item(SearchResult.web("github.com/apple/swift")!) == nil, "a web address has none of its own")
    }

    /// One @: the app, the folder and the file it knows at once each with its own icon, then the file Spotlight found
    /// below; the writing actions keep their commands' icons.
    @Test func oneAtsOpenRowsCarryTheirItemsIcon() async {
        await withInterfaceLanguage("en") {
            let host = field(instant: [Self.safari, Self.sales, Self.report], files: [Self.found])
            host.type("@sales")
            #expect(host.settle(timeout: 5) { host.composer.oneAtRows.contains(.open(Self.found)) }, "\(host.composer.oneAtRows.map(\.id))")
            // The rows shown first, then the last ones (↑ from the first goes round to the last): each drawn as it is.
            var opened: Set<String> = []
            for key in [nil, FakeHost.up] {
                if let key { host.press(key) }
                let shown = Array(host.composer.oneAtVisible), panel = host.panel?.rows ?? []
                #expect(panel.count == shown.count, "\(panel.map(\.text))")
                for (row, drawn) in zip(shown, panel) {
                    switch row {
                    case let .open(result):
                        opened.insert(result.path)
                        #expect(drawn.icon == Self.own(result), "\(drawn.text): \(String(describing: drawn.icon))")
                    case let .command(command), let .write(command):
                        #expect(drawn.icon == IconToken.command(command), "\(drawn.text)")
                    default:
                        if case .item? = drawn.icon?.glyph { Issue.record("\(drawn.text): an item's icon") }
                    }
                }
            }
            #expect(opened == Set([Self.safari, Self.sales, Self.report, Self.found].map(\.path)), "\(host.composer.oneAtRows.map(\.id))")
        }
    }

    /// One @ with a web address: its row keeps `@open`'s symbol.
    @Test func aWebAddressKeepsOpensSymbol() async {
        await withInterfaceLanguage("en") {
            let host = field(instant: [])
            host.type("@github.com/apple/swift")
            #expect(host.composer.oneAtRows.first == .open(SearchResult.web("github.com/apple/swift")!), "\(host.composer.oneAtRows.map(\.id))")
            #expect(host.panel?.rows.first?.icon == IconToken.command(.open), "\(String(describing: host.panel?.rows.first?.icon))")
        }
    }

    /// `@open` as its text is typed: each app, folder and file with its own icon; a web address with none, as before.
    @Test func opensRowsCarryTheirItemsIcon() async {
        await withInterfaceLanguage("en") {
            let web = SearchResult.web("sales.example.com")!
            let host = field(instant: [Self.safari, Self.sales, Self.report, web])
            host.type("@ope")
            host.press(FakeHost.tab)
            host.type("sales")
            let rows = host.panel?.rows ?? []
            #expect(host.composer.currentLiveResults.count == 4 && rows.count == 4, "\(rows.map(\.text))")
            for (result, row) in zip(host.composer.currentLiveResults, rows) {
                #expect(row.icon == (result.webURL == nil ? Self.own(result) : nil), "\(row.text): \(String(describing: row.icon))")
            }
        }
    }
}

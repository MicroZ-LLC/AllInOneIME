import Foundation
import Testing
@testable import AllInOneIMECore

/// Settings → Input → Show key hints off (`Config.keyHints`) applies to the session's own panels too, not only the
/// composer's (review of #99): clipboard history's and suggestion rows' footers lose their keys, their detail stays.
extension ClipboardHistorySessionTests {
    @Test func showKeyHintsOffAlsoLeavesClipboardHistorysKeysOut() async {
        await inEnglish {
            let on = host()
            #expect(on.press(FakeHost.controlV))
            #expect(on.panel?.footer.isEmpty == false, "with them on, as before: \(on.panel?.footer ?? "-")")

            let settings = Settings()
            settings.config.keyHints = false
            let off = host(settings: settings)
            #expect(off.press(FakeHost.controlV))
            #expect(texts(off) == ["gamma", "beta", "alpha"], "the rows as with them on: \(texts(off))")
            #expect(off.panel?.footer == "" && off.panel?.hints.isEmpty == true && off.panel?.footerHints.hints.isEmpty == true,
                    "no keys: \(off.panel?.footer ?? "-")")
            #expect(off.panel?.detail == "Clipboard", "the detail stays: \(off.panel?.detail ?? "-")")
        }
    }
}

extension SuggestionsHighlightTests {
    @Test func showKeyHintsOffAlsoLeavesSuggestionRowsKeysOut() async throws {
        try await inEnglish {
            for keyHints in [true, false] {
                let world = SuggestionsWorld()
                world.config.keyHints = keyHints
                world.addCode("python", packs: [try SuggestionsCodingPacksTests.shipped("python")])
                let field = world.codeField(app: "com.apple.Notes")
                field.type("for")
                #expect(!field.rows.isEmpty, "\(field)")
                let panel = try #require(field.host.panel)
                #expect(panel.footer.isEmpty == !keyHints && panel.footerHints.hints.isEmpty == !keyHints,
                        "keyHints \(keyHints): \(panel.footer)")
                #expect(panel.detail?.isEmpty == false, "the detail stays: \(panel.detail ?? "-")")
            }
        }
    }
}

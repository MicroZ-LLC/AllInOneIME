import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The Mac and other shells draw PanelPresenter rows; FakeHost drives the same Composer with real keys.
struct RewriteNumberingTests {
    private let answer = ConversionResult(
        versions: [CandidateLine("The draft reads clearly."), CandidateLine("This draft is easy to read.")],
        rewrites: [
            Rewrite(style: "润色", line: CandidateLine("The writing flows clearly.")),
            Rewrite(style: "简洁", line: CandidateLine("Clear draft.")),
        ])

    private func host() -> (FakeHost, Config) {
        var config = Config.default
        config.uiLanguage = "en"
        config.actionKey = .enter
        config.rewriteStyles = ["润色", "简洁"]
        let composer = Composer(engine: FakeEngine(), actionKey: .enter)
        composer.setInputMode(.english)
        let host = FakeHost(services: SessionServices(loadSettings: { config }), composer: composer)
        host.focus()
        host.type("@improve draft")
        #expect(host.press(FakeHost.enter))
        _ = host.composer.receive(answer, isFinal: true, id: 1)
        return (host, config)
    }

    @Test func shownRewriteLabelsFollowTheTwoResultsWithoutAGap() {
        let (host, config) = host()
        let rows = PanelPresenter(config: config, language: "en").model(for: host.composer).rows
        #expect(rows.map(\.label) == ["0", "1", "2", "3", "4"])
        #expect(rows.map(\.text).suffix(2) == ["The writing flows clearly.", "Clear draft."])
    }

    @Test func eachDisplayedDigitPicksItsOwnRewrite() {
        for (digit, expected) in [("3", "The writing flows clearly."), ("4", "Clear draft.")] {
            let (host, _) = host()
            #expect(host.press(KeyEvent(keyCode: 0, characters: digit)))
            #expect(host.document == expected, "Digit \(digit) must insert the rewrite shown beside that digit")
        }
    }
}

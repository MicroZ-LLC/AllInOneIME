import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Review item 32: a named AI command remains in one @'s list in a No AI app or a password field, but its row
/// says why it cannot run and is disabled. The existing `PanelModel.Row.pickable`, `choice` and `comment` are the
/// presentation seam; `Composer.aiAllowed` and `secureInputActive` stand in for the two field contexts. Return on
/// the disabled row leaves the draft alone and gives a notice, with no provider or network in this test.
struct UnavailableNamedAICommandsAcceptanceTests {
    private func composer(noAI: Bool, secure: Bool) -> Composer {
        let composer = Composer(engine: FakeEngine(), actionKey: .enter)
        composer.commands = Command.builtins
        composer.setInputMode(.english)
        composer.aiAllowed = { !noAI }
        composer.secureInputActive = { secure }
        for letter in "@que" { _ = composer.handleKeyDown(k(String(letter))) }
        return composer
    }

    @Test(arguments: [(true, false, "No AI"), (false, true, "password")])
    func namedAICommandIsDisabledWithItsReason(noAI: Bool, secure: Bool, reason: String) throws {
        let field = composer(noAI: noAI, secure: secure)
        let rows = PanelPresenter(config: .default, language: "en", terms: .mac).model(for: field).rows
        let row = try #require(rows.first { $0.text == "question" }, "The named AI command should stay listed: \(rows)")
        #expect(!row.pickable && row.choice == nil, "The unavailable AI row can still be picked: \(row)")
        #expect(row.comment.localizedCaseInsensitiveContains(reason), "The row does not explain \(reason): \(row)")
        let draft = field.draft
        let result = field.handleKeyDown(enterKey)
        #expect(field.draft == draft, "Return changed the draft on a disabled AI row")
        #expect(result.effects.contains { if case .notice = $0 { return true }; return false },
                "Return on a disabled AI row did not say why")
    }
}

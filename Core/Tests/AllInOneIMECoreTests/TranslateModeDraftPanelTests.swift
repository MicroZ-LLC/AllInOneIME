@testable import AllInOneIMECore
import Testing

/// Translate as You Type's draft shows on the candidate panel's input line, with the chip over it, as everything being
/// typed does since nothing is marked in the field (0.7.5, no inline preedit). Found by the 0.7.5 on-screen self-test:
/// after Space picked 你好 the panel lost its chip and the draft was shown nowhere.
struct TranslateModeDraftPanelTests {
    let presenter = PanelPresenter(config: .default, language: "en",
                                   chip: { TranslateMode.Chip(source: .chinese, target: .english, choices: nil, chinese: .simplified) })

    func composer() -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.commands = Command.builtins
        _ = c.setTranslateMode(TranslateMode.Session(target: .english))
        return c
    }

    func type(_ text: String, _ c: Composer) {
        for ch in text { _ = c.handleKeyDown(k(String(ch))) }
    }

    @Test func theDraftIsOnThePanelsInputLineUnderTheChip() {
        let c = composer()
        type("nihao", c)
        _ = c.handleKeyDown(spaceKey)
        #expect(c.draft == "你好" && c.wantsPanel, "the draft wants the panel: nothing shows it in the field")
        let model = presenter.model(for: c)
        #expect(model.input?.text == "你好", "\(String(describing: model.input))")
        #expect(model.chip != nil && model.rows.isEmpty)
    }

    @Test func whileItTranslatesThePanelSaysSo() {
        let c = composer()
        type("nihao", c)
        _ = c.handleKeyDown(spaceKey)
        _ = c.handleKeyDown(enterKey)
        #expect(c.markedText == "你好 · 翻译中…" && c.wantsPanel)
        let model = presenter.model(for: c)
        #expect(model.input?.text.hasPrefix("你好") == true && model.chip != nil && model.rows.isEmpty)
    }
}

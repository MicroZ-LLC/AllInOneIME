import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Translate as You Type, while the draft is being translated (after ⏎, before the result): the candidate panel says
/// what is happening and which keys work (owner, 0.7.5).
/// 1. The status is a loading status that it is translating ("AI 翻译中…" / "Translating…"), always in this mode,
///    whatever the config's output language: with the output language Chinese and the mode Chinese → English it is
///    still translating, never "AI 润色中…" / "Polishing…".
/// 2. The footer names only the keys that work here: Esc stops and keeps the draft, ⇧⏎ inserts the draft as typed.
///    No "0 原文" / "0 original" (there is no original row in this mode), not the generic "生成中… · 0 原文 · Esc 返回".
/// Independent acceptance test (AGENTS.md rules 11/20); the implementer doesn't edit it.
struct TranslateModeWaitingPanelTests {
    static let shiftEnter = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift)

    static var chineseOutput: Config {
        var config = Config.default
        config.setOrder([OutputLanguage.chinese])
        return config
    }

    static let configs: [(name: String, config: Config)] = [("default", .default), ("outputLanguage zh", chineseOutput)]

    func presenter(_ config: Config, _ language: String) -> PanelPresenter {
        PanelPresenter(config: config, language: language)
    }

    func composer() -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.commands = Command.builtins
        _ = c.setTranslateMode(TranslateMode.Session(target: .english))
        return c
    }

    /// "nihao", Space (the draft 你好), ⏎: the translation starts.
    func translatingNihao() -> Composer {
        let c = composer()
        for ch in "nihao" { _ = c.handleKeyDown(k(String(ch))) }
        _ = c.handleKeyDown(spaceKey)
        #expect(c.draft == "你好")
        _ = c.handleKeyDown(enterKey)
        if case .translating = c.phase {} else { Issue.record("⏎ starts the translation: \(c.phase)") }
        return c
    }

    // MARK: 1. The status says it is translating

    @Test(arguments: [0, 1])
    func statusSaysTranslatingInChinese(_ index: Int) {
        let (name, config) = Self.configs[index]
        #expect(config.outputLanguage == (index == 0 ? .english : .chinese))
        let model = presenter(config, "zh-Hans").model(for: translatingNihao())
        guard case let .loading(text) = model.status else {
            Issue.record("[\(name)] status should be loading, is \(model.status)"); return
        }
        #expect(text == "AI 翻译中…", "[\(name)] \(text)")
        #expect(!text.contains("润色"), "[\(name)] \(text)")
    }

    @Test(arguments: [0, 1])
    func statusSaysTranslatingInEnglish(_ index: Int) {
        let (name, config) = Self.configs[index]
        let model = presenter(config, "en").model(for: translatingNihao())
        guard case let .loading(text) = model.status else {
            Issue.record("[\(name)] status should be loading, is \(model.status)"); return
        }
        #expect(text == "Translating…", "[\(name)] \(text)")
        #expect(!text.contains("Polishing"), "[\(name)] \(text)")
    }

    // MARK: 2. The footer names the keys that work

    @Test(arguments: [0, 1])
    func footerNamesEscAndShiftReturnInChinese(_ index: Int) {
        let (name, config) = Self.configs[index]
        let footer = presenter(config, "zh-Hans").model(for: translatingNihao()).footer
        #expect(footer.contains("Esc"), "[\(name)] \(footer)")
        #expect(footer.contains("⇧⏎"), "[\(name)] \(footer)")
        #expect(!footer.contains("0 原文"), "[\(name)] \(footer)")
        #expect(footer != "生成中… · 0 原文 · Esc 返回", "[\(name)] \(footer)")
    }

    @Test(arguments: [0, 1])
    func footerNamesEscAndShiftReturnInEnglish(_ index: Int) {
        let (name, config) = Self.configs[index]
        let footer = presenter(config, "en").model(for: translatingNihao()).footer
        #expect(footer.contains("Esc"), "[\(name)] \(footer)")
        #expect(footer.contains("⇧⏎"), "[\(name)] \(footer)")
        #expect(!footer.contains("0 original"), "[\(name)] \(footer)")
        #expect(footer != "Generating… · 0 original · Esc back", "[\(name)] \(footer)")
    }

    // MARK: The keys do what the footer says

    @Test func escStopsAndKeepsTheDraft() {
        let c = translatingNihao()
        let esc = c.handleKeyDown(escKey)
        #expect(esc.effects.contains(.cancelConversion) && commits(esc).isEmpty)
        #expect(c.phase == .drafting && c.draft == "你好")
    }

    @Test func shiftReturnInsertsTheDraftAsTyped() {
        let c = translatingNihao()
        let asTyped = c.handleKeyDown(Self.shiftEnter)
        #expect(commits(asTyped) == ["你好"])
    }
}

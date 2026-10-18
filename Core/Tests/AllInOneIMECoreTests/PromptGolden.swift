import Foundation
@testable import AllInOneIMECore

/// The requests every normal (not refining) command sends, by name: @improve, @translate and both in English and
/// Chinese output, with the jargon style, and the AI commands. `Fixtures/prompts-release-0.6.3.json` holds them as
/// release 0.6.3 built them; `RefineTests` checks they are still byte for byte the same.
enum PromptGolden {
    static func requests() -> [String: ConverseRequest] {
        var out: [String: ConverseRequest] = [:]
        var english = Config.default
        english.setOrder([OutputLanguage.english, .chinese])
        var chinese = Config.default
        chinese.setOrder([OutputLanguage.chinese, .english])
        var jargon = Config.default
        jargon.rewriteStyles = ["润色", "黑话"]
        let entries = [JargonEntry(term: "对齐", meaning: "agree on"), JargonEntry(term: "抓手")]
        let sentences = ["zh": "我今天有点不舒服", "en": "this bug is blocker your team need fix it asap"]
        let modes: [WritingMode] = [.improve, .translate, .both]
        for (configName, config) in [("en", english), ("zh", chinese)] {
            for (language, sentence) in sentences {
                for mode in modes {
                    out["\(configName)-\(language)-\(mode.rawValue)"] = Prompt.request(for: sentence, mode: mode, config: config)
                }
            }
        }
        out["jargon-zh-improve"] = Prompt.request(for: sentences["zh"]!, mode: .improve, config: jargon, jargon: entries)
        let respond = Command.catalog([CustomCommand(name: "respond", type: .prompt, prompt: "Reply politely.")]).last!
        out["question"] = Prompt.commandRequest(.question, input: "量子计算是什么", config: english)
        out["question-about-selection"] = Prompt.commandRequest(
            .question, input: Prompt.question("这是什么意思", about: "Lorem ipsum"), config: english)
        out["edit"] = Prompt.commandRequest(
            .edit, input: Prompt.editRequest(instruction: "improve: more formal", text: "hi\nthere"), config: english)
        out["custom-prompt"] = Prompt.commandRequest(respond, input: "明天见", config: english)
        return out
    }

    /// `requests()` as JSON, keys sorted: what the fixture holds. `withoutLiveDataRule`: @question's system prompt
    /// without the rule 0.6.4 added (`Prompt.liveDataRule`), as 0.6.3 sent it.
    static func json(withoutLiveDataRule: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        var all = requests()
        if withoutLiveDataRule {
            for (name, request) in all where name.hasPrefix("question") {
                all[name]?.system = request.system.map { .init($0.text.replacingOccurrences(of: " " + Prompt.liveDataRule, with: "")) }
            }
        }
        return try encoder.encode(all)
    }
}

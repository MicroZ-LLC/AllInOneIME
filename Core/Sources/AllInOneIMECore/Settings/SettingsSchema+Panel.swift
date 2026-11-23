import Foundation

/// How the candidate panel looks, in Input: how a word's candidates are laid out (`Config.candidateLayout`), and whether
/// the keys are explained at its bottom (`Config.keyHints`).
extension SettingsSchema {
    mutating func panel(_ fields: inout [Field]) {
        let store = store
        add(choice("candidateLayout", tr("候选排列", "Candidate layout"),
                   config.candidateLayout == .horizontal
                       ? tr("选词（拼音、印地语）的候选并排，像系统自带的输入法：← → 选词，↑↓ 或 - = 翻页。",
                            "Word candidates (pinyin, Hindi) side by side, like the system's own input methods: ← → choose, ↑↓ or - = turn the page.")
                       : tr("选词（拼音、印地语）的候选一个一个往下排：↑↓ 选词，← → 或 - = 翻页。",
                            "Word candidates (pinyin, Hindi) one under the other: ↑↓ choose, ← → or - = turn the page."),
                   value: .string(config.candidateLayout.rawValue),
                   choices: [(Choice("vertical", tr("竖排", "Vertical")), nil), (Choice("horizontal", tr("横排", "Horizontal")), nil)]),
            to: &fields) { value in
            store.config.candidateLayout = value.string.flatMap(CandidateArrangement.init(rawValue:)) ?? store.config.candidateLayout
        }
        add(toggle("keyHints", tr("显示按键提示", "Show key hints"), UIText.keyHintsHelp(terms: terms), config.keyHints),
            to: &fields) { store.config.keyHints = Self.bool($0) }
    }
}

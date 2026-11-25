import Foundation

extension PanelPresenter {
    /// An @question conversation's footers that name Esc (`chatModel`): it closes the conversation, and on a saved answer
    /// picked from the recent questions it goes back to the list (`Composer.handleChatKey`). `composing`: while the next
    /// question's pinyin is typed; `handoff`: after where it can go on (the shortcuts first); `idle`: an answer in.
    /// `pick`: the digits that pick an answer ("1–5").
    func chatFooters(savedAnswer: Bool, pick: String) -> (composing: String, handoff: String, idle: String) {
        let copy = terms.copy, enter = terms.enter, shiftEnter = terms.shiftEnter
        guard savedAnswer else {
            return (t.tr("空格 选词 · \(enter) 追问 · \(shiftEnter) 上屏答案 · Esc 关闭",
                         "Space picks · \(enter) ask · \(shiftEnter) insert the answer · Esc close"),
                    t.tr(" · \(shiftEnter) 上屏 · \(pick) 选 · \(copy) 复制 · Esc 关闭", " · \(shiftEnter) insert · \(pick) pick · \(copy) copy · Esc close"),
                    t.tr("\(enter) 追问 · \(shiftEnter) 上屏 · \(pick) 选 · \(copy) 复制 · Esc 关闭",
                         "\(enter) ask · \(shiftEnter) insert · \(pick) pick · \(copy) copy · Esc close"))
        }
        return (t.tr("空格 选词 · \(enter) 追问 · \(shiftEnter) 上屏答案 · Esc 返回",
                     "Space picks · \(enter) ask · \(shiftEnter) insert the answer · Esc back"),
                t.tr(" · \(shiftEnter) 上屏 · \(pick) 选 · \(copy) 复制 · Esc 返回", " · \(shiftEnter) insert · \(pick) pick · \(copy) copy · Esc back"),
                t.tr("\(enter) 追问 · \(shiftEnter) 上屏 · \(pick) 选 · \(copy) 复制 · Esc 返回",
                     "\(enter) ask · \(shiftEnter) insert · \(pick) pick · \(copy) copy · Esc back"))
    }

    // MARK: - Numbers that ⌥ picks

    /// ⌥ (Alt) and a number picks one @'s row or a place a conversation goes on by its place (`Composer.handleNumberedPick`):
    /// each shows its number, plain ("1", "2" …), and the key is said once in the hints, `pickByNumber` (owner, 0.7.5). Both
    /// are key hints: with them off (`Config.keyHints`), no numbers.
    func numbered(_ rows: [PanelModel.Row]) -> [PanelModel.Row] {
        rows.enumerated().map { place, row in
            var row = row
            row.label = config.keyHints && place < 9 ? String(place + 1) : ""
            return row
        }
    }

    /// `numbered` for where a conversation goes on.
    func numbered(_ choices: [PanelModel.Handoff.Choice]) -> [PanelModel.Handoff.Choice] {
        choices.enumerated().map { place, choice in
            PanelModel.Handoff.Choice(shortcut: config.keyHints && place < 9 ? String(place + 1) : "", name: choice.name)
        }
    }

    /// The key that picks by number, as the hints say it: "⌥+数字", "⌥+number"; "Alt+number" on Windows.
    var pickByNumber: String { terms.name(terms.roles.pick) + "+" + t.tr("数字", "number") }

    /// Translate as You Type's draft being translated: the keys that work then (`Composer.handleModeTranslatingKey`), no
    /// original to pick: ⇧⏎ inserts the draft as typed, Esc stops it with the draft kept.
    var modeTranslatingFooter: String {
        let shiftEnter = terms.shiftEnter
        return t.tr("翻译中… · \(shiftEnter) 原样上屏 · Esc 停止，草稿保留", "Translating… · \(shiftEnter) insert as typed · Esc stop, draft kept")
    }
}

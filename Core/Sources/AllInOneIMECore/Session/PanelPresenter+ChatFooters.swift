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
}

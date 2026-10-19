import AllInOneIMECore
import Foundation

/// What the candidate window shows, whatever draws it: the rows with their numbers, the highlight, a status line (a
/// hint, a request under way, an error), the footer with the keys and, on its right, a detail (a notice, the page, how
/// long a request took). It is the engine's own until the core's platform-neutral panel model replaces it; the window
/// (`PanelPresenter`) only ever sees this.
public struct PanelModel: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public enum Style: Equatable, Sendable {
            /// A word being typed, a command, a file: the plain row.
            case candidate
            /// The text as typed (level two's row 0), dimmed.
            case original
            /// A version, a translation, an answer.
            case result
        }

        public var label: String
        public var text: String
        public var comment: String
        public var style: Style
        /// A click picks it (not a row still coming in, nor a line a script only shows).
        public var pickable: Bool
        /// Still streaming in: drawn dimmed.
        public var complete: Bool

        public init(label: String, text: String, comment: String = "", style: Style = .candidate, pickable: Bool = true,
                    complete: Bool = true) {
            self.label = label
            self.text = text
            self.comment = comment
            self.style = style
            self.pickable = pickable
            self.complete = complete
        }
    }

    public enum Status: Equatable, Sendable {
        case none
        case hint(String)
        case loading(String)
        case error(String)
    }

    public var rows: [Row] = []
    public var highlighted: Int?
    public var status: Status = .none
    /// The command being written when it isn't in the field (a command on the selection), or a refine instruction.
    public var input: String?
    /// What the panel works on (the text selected in the field).
    public var header: String?
    public var footer = ""
    public var detail: String?
    /// The rows side by side (`Config.candidateLayout`): the engine's candidates only.
    public var horizontal = false

    public init(rows: [Row] = [], highlighted: Int? = nil, status: Status = .none, input: String? = nil,
                header: String? = nil, footer: String = "", detail: String? = nil, horizontal: Bool = false) {
        self.rows = rows
        self.highlighted = highlighted
        self.status = status
        self.input = input
        self.header = header
        self.footer = footer
        self.detail = detail
        self.horizontal = horizontal
    }

    /// Only a notice (`Composer.Effect.notice`), for when nothing else is shown.
    public static func notice(_ text: String) -> PanelModel { PanelModel(status: .hint(text)) }

    public var isEmpty: Bool { rows.isEmpty && status == .none && input == nil && header == nil && footer.isEmpty && detail == nil }
}

/// Builds the panel from what the Composer exposes, as the Mac's `InputController.panelModel()` does, for the states
/// the Windows engine has: pinyin candidates, the command list, level two's results (and its request under way, its
/// failure), a script's list, `@open` as it is typed, the recent questions, and a draft's hint. Row `i` is what
/// `Composer.choose(index: i)` picks, as on the Mac.
public struct PanelBuilder {
    public var config: Config
    /// The interface language is Chinese (`InterfaceLanguage`).
    public var chinese: Bool
    /// The last request's time, and whether it came from the cache: the detail beside the footer.
    public var elapsed: TimeInterval?
    public var fromCache = false

    public init(config: Config, chinese: Bool, elapsed: TimeInterval? = nil, fromCache: Bool = false) {
        self.config = config
        self.chinese = chinese
        self.elapsed = elapsed
        self.fromCache = fromCache
    }

    func tr(_ zh: String, _ en: String) -> String { chinese ? zh : en }

    /// The action key's name: "Enter", "空格" …
    public func name(_ key: ActionKey) -> String {
        switch key {
        case .enter: return tr("回车", "Enter")
        case .space: return tr("空格", "Space")
        case .optionTap: return tr("单按 Alt", "Tap Alt")
        case .optionSpace: return "Alt+" + tr("空格", "Space")
        case let .shortcut(shortcut): return shortcut.name
        }
    }

    public func build(_ composer: Composer) -> PanelModel {
        var model = PanelModel()
        let key = name(composer.actionKey)
        if composer.refineIsComposing {
            let state = composer.engineState
            model.rows = state.candidates.map { PanelModel.Row(label: $0.label, text: $0.text, comment: $0.comment) }
            model.highlighted = state.highlighted
            model.horizontal = composer.horizontalCandidates
            model.footer = tr("空格 选词 · Shift+回车 按这句修改结果 · 回车 上屏 · Esc 清除拼音",
                              "Space picks · Shift+Enter refine · Enter insert · Esc clear the pinyin")
        } else if composer.isLevelTwo {
            levelTwo(composer, into: &model)
        } else if composer.engineState.isComposing {
            let state = composer.engineState
            model.rows = state.candidates.map { PanelModel.Row(label: $0.label, text: $0.text, comment: $0.comment) }
            model.highlighted = state.highlighted
            model.horizontal = composer.horizontalCandidates
            if let command = composer.draftCommand {
                model.footer = tr("空格 选词 · \(key) 执行 @\(command.name)", "Space picks · \(key) runs @\(command.name)")
            } else {
                model.footer = tr("空格 选词 · 数字 选择 · Shift 切换中英 · 开头打 @ 用命令",
                                  "Space picks · digits choose · Shift switches 中/英 · type @ first for commands")
            }
            if state.pageNumber > 0 || !state.isLastPage {
                model.detail = tr("第 \(state.pageNumber + 1) 页", "page \(state.pageNumber + 1)")
            }
        } else if composer.paletteQuery != nil {
            let first = composer.paletteFirstVisible, total = composer.paletteMatches.count
            model.rows = composer.paletteVisible.enumerated().map {
                PanelModel.Row(label: String($0.offset + 1), text: "@" + $0.element.name, comment: summary($0.element))
            }
            model.highlighted = composer.paletteHighlighted - first
            if total > Composer.paletteRows { model.detail = "\(first + 1)–\(first + model.rows.count) / \(total)" }
            model.footer = tr("回车 / Tab / 空格 选择 · Esc 取消", "Enter / Tab / Space choose · Esc cancel")
        } else if let list = composer.currentList {
            let choices = Composer.itemChoicesForPanel(list.items)
            model.rows = choices.map {
                PanelModel.Row(label: $0.label, text: Self.preview($0.text), comment: $0.detail.map { Self.preview($0) } ?? "",
                               style: $0.label.isEmpty ? .original : .candidate, pickable: Composer.picks($0))
            }
            model.highlighted = composer.listItem == nil ? nil : composer.listHighlight
            if list.items.isEmpty { model.status = .hint(tr("没有结果", "No results")) }
            model.footer = tr("\(key) 选中这一项 · ↑↓ 选择 · Esc 取消", "\(key) pick · ↑↓ choose · Esc cancel")
        } else if !composer.currentLiveResults.isEmpty {
            model.rows = composer.currentLiveResults.map { result in
                PanelModel.Row(label: result.isFolder ? "›" : "", text: result.name, comment: Self.preview(result.path, limit: 60))
            }
            model.highlighted = composer.liveHighlight
            model.footer = composer.opensLiveResult
                ? tr("回车 打开 · Tab 补全路径 · ↑↓ 选择 · Esc 取消", "Enter open · Tab complete path · ↑↓ choose · Esc cancel")
                : tr("回车 列出来选 · Tab 补全路径 · ↑↓ 选择 · Esc 取消", "Enter pick from a list · Tab complete path · ↑↓ choose · Esc cancel")
        } else if !composer.questionMatches.isEmpty {
            let digits = composer.questionDigitsPick
            model.rows = composer.questionMatches.enumerated().map { index, entry in
                PanelModel.Row(label: digits ? String(index + 1) : "", text: Self.preview(entry.question.replacingOccurrences(of: "\n", with: " ")))
            }
            model.highlighted = composer.questionHighlight
            model.status = .hint(composer.sentText.isEmpty
                                 ? tr("最近问过的：选一个看当时的答案，或者写新问题", "Recently asked: pick one to see its answer again, or write a new question")
                                 : draftHint(composer))
            model.footer = tr("\(key) 提问 · ↑↓ 选一个看答案 · Esc 清除", "\(key) ask · ↑↓ pick one to see its answer · Esc clear")
        } else if !composer.draft.isEmpty {
            model.status = .hint(draftHint(composer))
            model.footer = composer.selection != nil
                ? tr("Ctrl+V 粘贴 · 退格 删字 · Esc 取消，选中的文字不变", "Ctrl+V paste · Backspace delete · Esc cancel, the selection stays")
                : tr("Ctrl+V 粘贴 · 退格 删字 · Esc 清除", "Ctrl+V paste · Backspace delete · Esc clear")
        }
        let line = composer.isQuestionChat ? tr("追问 › ", "question › ") : tr("修改 › ", "refine › ")
        model.input = composer.refineLine.map { line + $0 + "▏" } ?? (composer.draftInPanel ? composer.markedText + "▏" : nil)
        if let selected = composer.selectionInUse {
            model.header = tr("选中的文字：", "Selected: ") + Self.preview(selected, limit: 60)
        }
        return model
    }

    private func levelTwo(_ composer: Composer, into model: inout PanelModel) {
        let choices = composer.choices
        model.rows = choices.map { choice in
            switch choice.kind {
            case .original:
                return PanelModel.Row(label: choice.label, text: Self.preview(choice.text), comment: tr("原文", "original"), style: .original)
            case .version:
                return PanelModel.Row(label: choice.label, text: Self.preview(choice.text), style: .result, complete: choice.isComplete)
            case let .translation(code):
                return PanelModel.Row(label: choice.label, text: Self.preview(choice.text), comment: OutputLanguage(code).code,
                                      style: .result, complete: choice.isComplete)
            case let .rewrite(style):
                return PanelModel.Row(label: choice.label, text: Self.preview(choice.text), comment: style, style: .result,
                                      complete: choice.isComplete)
            case .answer:
                return PanelModel.Row(label: choice.label, text: Self.preview(choice.text.replacingOccurrences(of: "\n", with: " ↵ ")),
                                      comment: choice.detail.map { Self.preview($0) } ?? tr("回答", "answer"), style: .result,
                                      complete: choice.isComplete)
            case .shown:
                return PanelModel.Row(label: "", text: Self.preview(choice.text), comment: choice.detail.map { Self.preview($0) } ?? "",
                                      pickable: false)
            case let .item(item):
                return PanelModel.Row(label: choice.label, text: Self.preview(choice.text),
                                      comment: choice.detail.map { Self.preview($0) } ?? "", pickable: item.valid)
            case let .file(path):
                let result = composer.searchResults.first { $0.path == path }
                return PanelModel.Row(label: choice.label, text: result?.name ?? choice.text, comment: Self.preview(path, limit: 60))
            case .reminder, .send, .issue:
                return PanelModel.Row(label: choice.label, text: Self.preview(choice.text), style: .result, complete: choice.isComplete)
            }
        }
        for (index, choice) in choices.enumerated() where model.rows.indices.contains(index) {
            model.rows[index].pickable = model.rows[index].pickable && Composer.picks(choice)
        }
        model.highlighted = composer.highlighted
        let command = composer.activeCommand
        let timing = fromCache ? tr("缓存", "cached") : elapsed.map { String(format: "%.1fs", $0) }
        switch composer.phase {
        case .translating:
            let polishing = config.language(of: composer.selectionInUse ?? composer.sentText).matches(config.outputLanguage)
            let loading = command?.kind == .generate ? tr("AI 回答中…", "Answering…")
                : command == .webSearch || command == .open ? tr("搜索中…", "Searching…")
                : command?.script.map { tr("正在运行 \($0.title)…", "Running \($0.title)…") }
                ?? (command?.kind == .run ? tr("运行中…", "Running…")
                    : polishing ? tr("AI 润色中…", "Polishing…") : tr("AI 翻译中…", "Translating…"))
            model.status = choices.count <= 1 ? .loading(loading) : .none
            model.footer = command?.script != nil || command?.kind == .run ? tr("运行中… · Esc 停止", "Running… · Esc stop")
                : composer.isRefining ? tr("修改中… · Esc 回到上一版", "Refining… · Esc previous results")
                : tr("生成中… · 0 原文 · Esc 返回", "Generating… · 0 original · Esc back")
        case .choosing:
            model.footer = command == .open
                ? tr("空格 / 回车 打开 · 数字选择 · Esc 返回", "Space / Enter open · digits pick · Esc back")
                : composer.refineLine != nil
                ? tr("Shift+回车 修改 · 回车 上屏 · Esc 清除 · ↑↓ 选择", "Shift+Enter refine · Enter insert · Esc clear · ↑↓ choose")
                : composer.canRefine
                ? tr("打字后 Shift+回车 修改 · 空格 / 回车 上屏 · 数字选择 · 0 原文 · Esc 返回",
                     "Type, Shift+Enter refine · Space / Enter insert · digits pick · 0 original · Esc back")
                : tr("空格 / 回车 上屏 · 数字选择 · 0 原文 · Esc 返回", "Space / Enter insert · digits pick · 0 original · Esc back")
            if let error = composer.refineError { model.status = .error(error) }
            if command != .open { model.detail = timing }
        case let .failed(message):
            model.status = .error(message)
            model.highlighted = nil  // the action key retries; nothing is selected
            model.footer = composer.actionKey == .enter
                ? tr("空格 / 回车 重试 · 0 原文 · Esc 返回", "Space / Enter retry · 0 original · Esc back")
                : tr("空格 重试 · 回车 上屏原文 · Esc 返回", "Space retry · Enter insert original · Esc back")
        case .idle, .drafting:
            break
        }
    }

    /// The hint under a pending draft: "回车 → 英文润色", "Enter → translate to English" …
    func draftHint(_ composer: Composer) -> String {
        guard let command = composer.draftCommand else { return "" }
        let key = composer.actionKey
        let how = key != .space ? name(key) : composer.spaceActs ? name(.space) : tr("连按两次空格", "Space twice")
        if let preview = composer.snippetPreview { return "\(how) → “" + Self.preview(preview, limit: 80) + "”" }
        if command == .reply, composer.sentText.isEmpty, composer.attachment == nil {
            return tr("回复对方：Ctrl+V 粘贴消息", "Reply: Ctrl+V their message")
        }
        if composer.sentText.isEmpty, composer.selectionInUse == nil, command.kind == .convert || command.kind == .generate {
            return tr("先写要发给 @\(command.name) 的文字", "Type the text for @\(command.name) first")
        }
        return "\(how) → " + action(command, composer: composer)
    }

    /// What the action key does with the draft's command.
    func action(_ command: Command, composer: Composer) -> String {
        switch command {
        case .improve, .translate:
            let output = config.outputLanguage
            let language = config.language(of: composer.selectionInUse ?? composer.sentText)
            let outputName = chinese ? output.name(chinese: true) : output.name(chinese: false)
            if command == .improve, language.matches(output) { return tr("\(outputName)润色", "polish in \(outputName)") }
            return tr("翻译成\(outputName)", "translate to \(outputName)")
        case .question: return tr("问 AI", "ask the AI")
        case .open: return tr("打开", "open")
        default: return tr("执行 @\(command.name)", "run @\(command.name)")
        }
    }

    /// A command's line in the list.
    func summary(_ command: Command) -> String {
        if let custom = command.custom { return custom.summary ?? "" }
        if let script = command.script { return script.title }
        if let plugin = command.plugin { return plugin.manifest.summary?.text(chinese: chinese) ?? "" }
        switch command {
        case .improve: return tr("润色或翻译", "polish or translate")
        case .translate: return tr("翻译", "translate")
        case .question: return tr("问 AI", "ask the AI")
        case .agent: return tr("交给编程助手", "hand to a coding agent")
        case .open: return tr("打开文件或网址", "open a file or address")
        case .reply: return tr("回复消息", "reply to a message")
        case .read: return tr("读网页", "read a web page")
        case .note: return tr("记笔记", "save a note")
        case .reminder: return tr("提醒事项（macOS）", "reminder (macOS)")
        case .py: return "Python"
        case .js: return "JavaScript"
        case .webSearch: return tr("搜索网络", "search the web")
        case .settings: return tr("设置", "settings")
        default: return ""
        }
    }

    /// A long text shortened for a row (the full text goes in).
    static func preview(_ text: String, limit: Int = 120) -> String {
        let flat = text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}

import Foundation

/// Makes the candidate panel (`PanelModel`) from the composer's state, in the interface language it is given
/// (`language`): the rows, which one is highlighted, the status, the footer saying what the keys do, the lines above the
/// rows, the notice. The same on every platform; the shell draws what comes out. Made afresh for each panel shown, from
/// what the text field's session knows besides the composer. It never reads the process's language (`UIText.language`):
/// two sessions (two text fields, on Windows two contexts) may show theirs in two.
public struct PanelPresenter {
    /// The settings, as they are now.
    public var config: Config
    /// The interface language's code (`InterfaceLanguage`): "zh-Hans", "en", …
    public var language: String
    /// What the keys and places are called where it is drawn (⌘C or Ctrl+C …). Which key does what (`roles`) is the
    /// composer's, whatever these came with: the panel names the keys the composer acts on (`model(for:)`).
    public var terms: PlatformTerms
    /// The app the text field is in (its per-app settings, for the draft's hint).
    public var app: String?
    /// The notice up now ("已复制" …): on the footer's right, over what is there.
    public var notice: String?
    /// How long the last AI result took, and whether it came from the cache.
    public var elapsed: TimeInterval?
    public var fromCache: Bool
    /// How many values the last request hid from the AI (`Redaction`), and whether a conversation's earlier rounds were
    /// shortened to fit the model.
    public var hidden: Int
    public var shortened: Bool
    /// The agent `@agent` hands to, and the custom one's command: where an `@question` conversation can go on.
    public var agent: AgentKind
    public var agentCommand: [String]
    /// The user's jargon list, read when a jargon (黑话) result is shown.
    public var jargon: () -> [JargonEntry]
    /// A script extension's status line (`ScriptCommand.status`), shown beside its name in the command list.
    public var scriptStatus: (ScriptCommand) -> String?
    /// Translate as You Type's chip in this field, if it's shown here.
    public var chip: () -> TranslateMode.Chip?

    public init(config: Config, language: String, terms: PlatformTerms = Platform.current.terms, app: String? = nil,
                notice: String? = nil, elapsed: TimeInterval? = nil, fromCache: Bool = false, hidden: Int = 0,
                shortened: Bool = false, agent: AgentKind = .claude, agentCommand: [String] = [],
                jargon: @escaping () -> [JargonEntry] = { [] }, scriptStatus: @escaping (ScriptCommand) -> String? = { _ in nil },
                chip: @escaping () -> TranslateMode.Chip? = { nil }) {
        self.config = config
        self.language = language
        self.terms = terms
        self.app = app
        self.notice = notice
        self.elapsed = elapsed
        self.fromCache = fromCache
        self.hidden = hidden
        self.shortened = shortened
        self.agent = agent
        self.agentCommand = agentCommand
        self.jargon = jargon
        self.scriptStatus = scriptStatus
        self.chip = chip
    }

    /// The most of an earlier question or answer of a conversation shown (the latest answer is shown whole, up to
    /// `latestLimit`).
    public static let earlierLimit = 160
    public static let latestLimit = 4000

    /// The interface text in `language`.
    private var t: InterfaceWords { InterfaceWords(language: language) }

    /// The action key, as `terms` call it.
    private func name(_ key: ActionKey) -> String { t.name(key, terms: terms) }

    /// The time the last result took ("1.2s"), or that it was cached.
    private var time: String? { fromCache ? t.tr("缓存", "cached") : elapsed.map { String(format: "%.1fs", $0) } }

    // MARK: - The panel

    /// The panel for `composer` as it is now, its keys named by the roles the composer acts on (`Composer.modifierRoles`).
    public func model(for composer: Composer) -> PanelModel {
        var presenter = self
        presenter.terms.roles = composer.modifierRoles
        return presenter.panel(for: composer)
    }

    /// `model(for:)`, with `terms`' roles the composer's.
    private func panel(for composer: Composer) -> PanelModel {
        typealias Row = PanelModel.Row
        var model = PanelModel()
        let config = config
        let copy = terms.copy, paste = terms.paste, enter = terms.enter, shiftEnter = terms.shiftEnter, backspace = terms.backspace
        // An @question conversation: its questions and answers, the next question's line.
        if composer.isQuestionChat, !composer.refineIsComposing { return chatModel(for: composer) }
        if composer.refineIsComposing {
            // Pinyin of a refine instruction: its candidates, as when typing (the results come back once it's picked).
            let state = composer.engineState
            model.rows = state.candidates.map {
                Row(label: $0.label, text: $0.text, comment: $0.comment, kind: .candidate)
            }
            model.highlighted = state.highlighted
            model.horizontal = composer.horizontalCandidates
            model.footer = composer.isQuestionChat
                ? t.tr("空格 选词 · \(shiftEnter) 追问 · \(enter) 上屏答案 · Esc 清除拼音",
                       "Space picks · \(shiftEnter) ask · \(enter) insert the answer · Esc clear the pinyin")
                : t.tr("空格 选词 · \(shiftEnter) 按这句修改结果 · \(enter) 上屏 · Esc 清除拼音",
                       "Space picks · \(shiftEnter) refine · \(enter) insert · Esc clear the pinyin")
        } else if composer.isLevelTwo {
            let choices = composer.choices
            model.rows = choices.map { choice in
                // Long rows (a pasted paragraph and its versions) are shortened here; the full text goes in.
                switch choice.kind {
                case .original:
                    return Row(label: choice.label, text: SessionText.preview(choice.text), comment: t.tr("原文", "original"),
                               kind: .original)
                case .version:
                    return Row(label: choice.label, text: SessionText.preview(choice.text), kind: .translation,
                               isComplete: choice.isComplete)
                case let .translation(code):
                    return Row(label: choice.label, text: SessionText.preview(choice.text),
                               comment: t.name(OutputLanguage(code)), kind: .translation,
                               isComplete: choice.isComplete)
                case let .rewrite(style):
                    // A jargon (黑话) line notes what the terms from the user's jargon list in it mean.
                    let note = style == RewriteStyle.jargonName
                        ? JargonLibrary.annotation(for: choice.text, entries: jargon(), chinese: t.chinese) : nil
                    let name = RewriteStyle.named(style).map(t.name) ?? style
                    return Row(label: choice.label, text: SessionText.preview(choice.text),
                               comment: note.map { "\(name) · \($0)" } ?? name,
                               kind: .translation, isComplete: choice.isComplete)
                case .answer:
                    // A program's output may have several lines; they are inserted as printed. A script's summary
                    // has its detail beside it.
                    let text = choice.text.replacingOccurrences(of: "\n", with: " ↵ ")
                    return Row(label: choice.label, text: SessionText.preview(text),
                               comment: choice.detail.map { SessionText.preview($0) } ?? t.answerLabel(composer.activeCommand),
                               kind: .translation, isComplete: choice.isComplete)
                case .shown:
                    // What a `show` script printed: shown as it comes, never inserted (nor clicked).
                    return Row(label: "", text: SessionText.preview(choice.text), comment: choice.detail.map { SessionText.preview($0) } ?? "",
                               kind: .candidate, pickable: false)
                case let .item(item):
                    return Row(label: choice.label, text: SessionText.preview(choice.text),
                               comment: choice.detail.map { SessionText.preview($0) } ?? "", kind: .candidate, pickable: item.valid)
                case let .file(path) where path.hasPrefix(SearchResult.agentPrefix):
                    // A background task: its last reply, shortened.
                    let reply = composer.searchResults.first { $0.path == path }?.detail ?? ""
                    let preview = reply.replacingOccurrences(of: "\n", with: " ")
                    // Its state as an icon instead of the mark before its name.
                    let marks: [(String, AgentSession.Progress)] = [("✓ ", .done), ("⚠︎ ", .needsYou), ("… ", .working)]
                    let state = marks.first { choice.text.hasPrefix($0.0) }
                    return Row(label: choice.label, text: state.map { String(choice.text.dropFirst($0.0.count)) } ?? choice.text,
                               comment: preview.count > 60 ? String(preview.prefix(60)) + "…" : preview, kind: .candidate,
                               icon: state.map { IconToken.progress($0.1) })
                case .send:
                    // 「发给 张三（+1 555…）：…」: who it goes to and the text, to confirm; Return sends it (its label).
                    let to = composer.messageRecipient.map { $0.name.isEmpty ? $0.handle : "\($0.name)（\($0.handle)）" } ?? ""
                    return Row(label: enter,
                               text: t.tr("发给 \(to)：", "Send to \(to): ") + SessionText.preview(choice.text.replacingOccurrences(of: "\n", with: " ↵ ")),
                               kind: .translation, isComplete: choice.isComplete,
                               icon: composer.activeCommand.map(IconToken.command))
                case let .file(path):
                    // A file, folder, app or web address: drawn as when typing.
                    let result = composer.searchResults.first { $0.path == path } ?? SearchResult(name: choice.text, path: path)
                    let row = SessionText.openRow(result, language: language, terms: terms)
                    return Row(label: choice.label, text: row.text, comment: row.comment, kind: .candidate)
                case let .reminder(reminder):
                    // To confirm: what to be reminded of, and when as read from the text (「明天 15:00」).
                    return Row(label: choice.label, text: SessionText.preview(choice.text),
                               comment: t.when(reminder), kind: .candidate)
                case .issue:
                    // To confirm: the issue's title (none: written on GitHub); what goes with it is the status below. Return
                    // opens it (its label).
                    return Row(label: enter,
                               text: choice.text.isEmpty ? t.tr("（标题在 GitHub 上写）", "(write the title on GitHub)") : choice.text,
                               comment: t.tr("在 GitHub 上新建问题", "new issue on GitHub"), kind: .translation,
                               icon: composer.activeCommand.map(IconToken.command))
                }
            }
            // Only rows a click picks light up under the pointer (not one still coming in).
            for (index, choice) in choices.enumerated() where model.rows.indices.contains(index) {
                model.rows[index].pickable = Composer.picks(choice)
            }
            model.highlighted = composer.highlighted
            let command = composer.activeCommand
            switch composer.phase {
            case .translating:
                let polishing = config.language(of: composer.selectionInUse ?? composer.sentText).matches(config.outputLanguage)
                let loading = command?.kind == .generate ? t.tr("AI 回答中…", "Answering…")
                    : command == .webSearch ? t.tr("搜索中…", "Searching…")
                    : command?.script.map { t.tr("正在运行 \($0.title)…", "Running \($0.title)…") }
                    ?? (command?.kind == .run ? t.tr("运行中…", "Running…")
                    : command?.kind == .link ? t.tr("运行句中的命令，然后在浏览器打开…", "Running the commands inside, then opening the browser…")
                    : command == .open ? t.tr("搜索中…", "Searching…")
                    : command == .tasks ? t.tr("读取后台任务…", "Reading the background tasks…")
                    : command?.kind == .message ? t.tr("运行句中的命令…", "Running the commands in the message…")
                    : polishing ? t.tr("AI 润色中…", "Polishing…") : t.tr("AI 翻译中…", "Translating…"))
                let refining = composer.refineHistory.last.map {
                    t.tr("按「\(SessionText.preview($0, limit: 40))」修改中…", "Refining: \(SessionText.preview($0, limit: 40))…")
                }
                model.status = choices.count <= 1 ? .loading(composer.isRefining ? refining ?? loading : loading) : .none
                model.footer = command == .open ? t.tr("搜索中… · Esc 返回", "Searching… · Esc back")
                    : command?.kind == .link ? t.tr("完成后在浏览器打开 · Esc 返回", "Opens in the browser when done · Esc back")
                    : command?.script?.output == .show
                    ? t.tr("运行中… · \(copy) 复制 · Esc 停止 · 离开输入框后在后台继续",
                           "Running… · \(copy) copy · Esc stop · goes on in the background if you leave")
                    : command?.script != nil ? t.tr("运行中… · Esc 停止", "Running… · Esc stop")
                    : composer.isRefining ? t.tr("修改中… · 可以接着打下一步要求 · Esc 回到上一版",
                                               "Refining… · type the next step meanwhile · Esc previous results")
                    : t.tr("生成中… · 0 原文 · Esc 返回", "Generating… · 0 original · Esc back")
            case .choosing where command?.kind == .message:
                model.footer = t.tr("\(enter) 发送 · Esc 返回修改", "\(enter) send · Esc back to editing")
            case .choosing where command?.kind == .report:
                // Everything the page will hold besides the title, before it opens.
                if let issue = composer.pendingIssue {
                    model.status = .list(t.tr("会一起填进去（不含你打的其他字、路径、密钥和命令名）：",
                                              "Also filled in (no other text you typed, no paths, keys or command names):"),
                                         items: issue.lines)
                }
                model.footer = t.tr("\(enter) 在浏览器打开，在 GitHub 上点提交 · Esc 返回", "\(enter) open in the browser, submit it on GitHub · Esc back")
            case .choosing where composer.offersMoreReplies && composer.refineLine == nil && composer.refineError == nil:
                // @reply's three: ⌘R three more; a letter starts an instruction for them, as for any AI's results.
                model.footer = t.tr("\(terms.again) 再写三条 · 打字后 \(shiftEnter) 修改 · 空格 / \(enter) 上屏 · 数字选择 · Esc 返回",
                                    "\(terms.again) three more · Type, \(shiftEnter) refine · Space / \(enter) insert · digits pick · Esc back")
                model.detail = time
            case .choosing where command == .tasks:
                model.footer = terms.terminal == .terminalApp
                    ? t.tr("\(enter) 在终端打开 · 数字选择 · \(copy) 复制回复 · Esc 返回",
                           "\(enter) open in Terminal · digits pick · \(copy) copy the reply · Esc back")
                    : t.tr("\(enter) 在终端打开 · 数字选择 · \(copy) 复制回复 · Esc 返回",
                           "\(enter) open in a terminal · digits pick · \(copy) copy the reply · Esc back")
            case .choosing where command?.script != nil:
                let picks = composer.choices.contains { if case .item = $0.kind { return true } else { return false } }
                model.footer = command?.script?.output == .show && !picks
                    ? t.tr("\(enter) 关闭 · \(copy) 复制全部 · Esc 返回", "\(enter) close · \(copy) copy all · Esc back")
                    : picks ? t.tr("\(enter) 选中这一项 · 数字选择 · \(copy) 复制 · Esc 返回", "\(enter) pick · digits pick · \(copy) copy · Esc back")
                    : t.tr("空格 / \(enter) 上屏 · 数字选择 · \(copy) 复制 · Esc 返回", "Space / \(enter) insert · digits pick · \(copy) copy · Esc back")
                model.detail = elapsed.map { String(format: "%.1fs", $0) }
            case .choosing:
                model.footer = command == .open
                    ? t.tr("空格 / \(enter) 打开 · 数字选择 · \(copy) 复制路径 · Esc 返回", "Space / \(enter) open · digits pick · \(copy) copy path · Esc back")
                    : command == .reminder
                    ? t.tr("\(enter) / 空格 加到提醒事项 · Esc 返回修改 · \(copy) 复制", "\(enter) / Space add to Reminders · Esc back to edit · \(copy) copy")
                    : composer.refineLine != nil
                    ? t.tr("\(shiftEnter) 修改 · \(enter) 上屏 · \(backspace) 删字 · Esc 清除 · ↑↓ 选择",
                           "\(shiftEnter) refine · \(enter) insert · \(backspace) delete · Esc clear · ↑↓ choose")
                    : composer.canRefine
                    // AI results: a letter starts a follow-up instruction (`Composer.refineText`), ⇧⏎ sends it; 0 still
                    // picks the original.
                    ? (composer.refineHistory.isEmpty
                        ? t.tr("打字后 \(shiftEnter) 修改 · 空格 / \(enter) 上屏 · 数字选择 · 0 原文 · \(copy) 复制 · Esc 返回",
                               "Type, \(shiftEnter) refine · Space / \(enter) insert · digits pick · 0 original · \(copy) copy · Esc back")
                        : t.tr("打字后 \(shiftEnter) 再改 · 空格 / \(enter) 上屏 · 数字选择 · 0 原文 · Esc 上一版",
                             "Type, \(shiftEnter) refine · Space / \(enter) insert · digits pick · 0 original · Esc previous"))
                    : t.tr("空格 / \(enter) 上屏 · 数字选择 · 0 原文 · \(copy) 复制 · Esc 返回",
                           "Space / \(enter) insert · digits pick · 0 original · \(copy) copy · Esc back")
                // A refine that failed: the results before it stay, its instruction back in the line.
                if let error = composer.refineError { model.status = .error(error) }
                if command != .open && command != .reminder {
                    model.detail = time
                }
            case let .failed(message):
                model.status = .error(message)
                model.highlighted = nil  // Space retries; nothing is selected
                // A reminder without anything to be reminded of: write it in. One put right in the settings (nothing to
                // translate into): they open.
                model.footer = command == .reminder
                    ? t.tr("Esc 返回修改", "Esc back to edit")
                    : composer.failureFixedIn != nil
                    ? t.tr("空格 / \(enter) 打开设置 · 0 原文 · Esc 返回", "Space / \(enter) open the settings · 0 original · Esc back")
                    : composer.actionKey == .enter
                    ? t.tr("空格 / \(enter) 重试 · 0 原文 · Esc 返回", "Space / \(enter) retry · 0 original · Esc back")
                    : t.tr("空格 重试 · \(enter) 上屏原文 · Esc 返回", "Space retry · \(enter) insert original · Esc back")
            case .idle, .drafting:
                break
            }
            // A saved @question answer was sent nowhere now: what the last request hid isn't about it.
            PanelRedaction.annotate(&model, choices: choices, hidden: composer.showsSavedAnswer ? 0 : hidden, phase: composer.phase,
                                    language: language)
        } else if composer.voice != .off {
            let heard = composer.voice.text
            if case .listening = composer.voice {
                model.status = .hint("🎙 " + (heard.isEmpty ? t.tr("正在听…", "Listening…") : heard))
                // The action key while the right voice key (⌥) is still held (⌥Return, or Space = ⌥Space): stop and run it.
                let key = composer.actionKey, voice = terms.voiceKey
                let runs = composer.draftCommand != nil
                model.footer = runs && (key == .optionSpace || key == .enter)
                    ? (key == .enter ? t.tr("松开右 \(voice) 结束 · \(enter) 直接执行 · Esc 取消", "Release right \(voice) to stop · \(enter) run now · Esc cancel")
                                     : t.tr("松开右 \(voice) 结束 · 空格 直接执行 · Esc 取消",
                                            "Release right \(voice) to stop · Space run now · Esc cancel"))
                    : t.tr("松开右 \(voice) 结束 · Esc 取消", "Release right \(voice) to stop · Esc cancel")
            } else {
                model.status = .hint("🎙 " + (heard.isEmpty ? t.tr("识别中…", "Recognizing…") : heard))
                model.footer = composer.actsAfterVoice
                    ? t.tr("识别完就发送 · Esc 取消", "Sends once recognized · Esc cancel")
                    : t.tr("识别中… · Esc 取消", "Recognizing… · Esc cancel")
            }
            model.detail = composer.messages.mode(composer.inputLanguage)
        } else if composer.engineState.isComposing {
            let state = composer.engineState
            model.rows = state.candidates.map {
                Row(label: $0.label, text: $0.text, comment: $0.comment, kind: .candidate)
            }
            model.highlighted = state.highlighted
            // A word's candidates in a row, as macOS's own panel, if set so (every other list is a column); as the
            // composer takes the arrow keys, from the settings the text field was given.
            model.horizontal = composer.horizontalCandidates
            let key = composer.actionKey
            if let command = composer.draftCommand {
                // Pinyin (or Hindi) in an @ command: the action key converts it and runs the command.
                let action = t.action(command, input: composer.textLanguage(config: config), config: config, draft: composer.draft,
                                      terms: terms)
                model.footer = t.tr("空格 选词 · \(name(key)) \(action)", "Space picks · \(name(key)) to \(action)")
            } else {
                model.footer = SessionText.translateModeFooter(composer, language: language, terms: terms) ?? t.tr("空格 选词 · 开头打 @ 用命令", "Space picks · type @ first for commands")
            }
            if state.pageNumber > 0 || !state.isLastPage {
                model.detail = t.tr("第 \(state.pageNumber + 1) 页", "page \(state.pageNumber + 1)")
            }
        } else if composer.paletteQuery != nil {
            // "@…": the commands that start with what was typed.
            // Five at a time; the rest scroll into view (the position on the right).
            let first = composer.paletteFirstVisible, total = composer.paletteMatches.count
            model.rows = composer.paletteVisible.enumerated().map {
                Row(label: String($0.offset + 1), text: "@" + $0.element.name,
                    comment: t.summary($0.element, status: $0.element.script.flatMap(scriptStatus), terms: terms),
                    kind: .candidate, icon: IconToken.command($0.element))
            }
            model.highlighted = composer.paletteHighlighted - first
            if total > Composer.paletteRows { model.detail = "\(first + 1)–\(first + model.rows.count) / \(total)" }
            // A script extension that takes no input: the action key runs it, Tab and Space only pick it.
            let matches = composer.paletteMatches, key = name(composer.actionKey)
            model.footer = matches.indices.contains(composer.paletteHighlighted)
                && matches[composer.paletteHighlighted].script?.input == ScriptCommand.Input.none
                ? t.tr("\(key) 运行 · Tab / 空格 选择 · Esc 取消", "\(key) run · Tab / Space choose · Esc cancel")
                : t.tr("\(enter) / Tab / 空格 选择 · Esc 取消", "\(enter) / Tab / Space choose · Esc cancel")
        } else if let list = composer.currentList {
            // A script's list as you type: its rows (those of information unnumbered and dimmed).
            let choices = Composer.itemChoicesForPanel(list.items)
            model.rows = choices.map {
                Row(label: $0.label, text: SessionText.preview($0.text), comment: $0.detail.map { SessionText.preview($0) } ?? "",
                    kind: $0.label.isEmpty ? .original : .candidate, pickable: Self.picks($0))
            }
            model.highlighted = composer.listItem == nil ? nil : composer.listHighlight
            if list.items.isEmpty { model.status = .hint(t.tr("没有结果", "No results")) }
            let key = name(composer.actionKey)
            model.footer = t.tr("\(key) 选中这一项 · ↑↓ 选择 · Tab 补全 · \(copy) 复制 · Esc 取消",
                                "\(key) pick · ↑↓ choose · Tab complete · \(copy) copy · Esc cancel")
        } else if !composer.currentLiveResults.isEmpty {
            // "@open …" as you type: what matches now.
            model.rows = composer.currentLiveResults.map { result in
                let row = SessionText.openRow(result, language: language, terms: terms)
                return Row(label: result.isFolder ? "›" : "", text: row.text, comment: row.comment, kind: .candidate)
            }
            model.highlighted = composer.liveHighlight
            // Only content matches: ⏎ lists them to pick from rather than open the first (`opensLiveResult`).
            model.footer = composer.opensLiveResult
                ? t.tr("\(enter) 打开 · Tab 补全路径 · ↑↓ 选择 · \(copy) 复制路径 · Esc 取消",
                       "\(enter) open · Tab complete path · ↑↓ choose · \(copy) copy path · Esc cancel")
                : t.tr("\(enter) 列出来选 · Tab 补全路径 · ↑↓ 选择 · \(copy) 复制路径 · Esc 取消",
                       "\(enter) pick from a list · Tab complete path · ↑↓ choose · \(copy) copy path · Esc cancel")
        } else if composer.recipientQuery != nil {
            // "@imessage zs": the contacts that match, to pick the recipient.
            let found = composer.currentRecipients
            model.rows = found.enumerated().map { index, recipient in
                Row(label: String(index + 1), text: recipient.displayName,
                    comment: recipient.name.isEmpty ? t.tr("直接发送到这个号码 / 邮箱", "send to this number / email") : recipient.handle,
                    kind: .candidate)
            }
            model.highlighted = found.isEmpty ? nil : composer.recipientHighlight
            if let note = composer.recipientNote { model.status = .hint(note) }
            model.footer = t.tr("\(enter) / Tab 选择收件人 · ↑↓ · Esc 取消", "\(enter) / Tab pick the recipient · ↑↓ · Esc cancel")
        } else if !composer.questionMatches.isEmpty {
            // "@question " and nothing (or a few words) after it: the recent questions with them, newest first; one picked
            // shows its saved answer.
            let digits = composer.questionDigitsPick, key = name(composer.actionKey)
            model.rows = composer.questionMatches.enumerated().map { index, entry in
                Row(label: digits ? String(index + 1) : "", text: SessionText.preview(entry.question.replacingOccurrences(of: "\n", with: " ")),
                    comment: t.ago(entry.date), kind: .candidate)
            }
            model.highlighted = composer.questionHighlight
            model.status = .hint(composer.sentText.isEmpty
                                 ? t.tr("最近问过的：选一个看当时的答案，或者写新问题", "Recently asked: pick one to see its answer again, or write a new question")
                                 : SessionText.draftHint(composer, config: config.applying(app: app), language: language, terms: terms))
            model.footer = composer.questionHighlight != nil
                ? t.tr("\(key) 看保存的答案 · ↑↓ 选择 · Esc 清除", "\(key) show the saved answer · ↑↓ choose · Esc clear")
                : digits ? t.tr("数字 / ↑↓ 选一个看答案 · \(paste) 粘贴 · Esc 清除", "Digits / ↑↓ pick one to see its answer · \(paste) paste · Esc clear")
                : t.tr("\(key) 问这个新问题 · ↑↓ 选一个看答案 · Esc 清除", "\(key) ask it · ↑↓ pick one to see its answer · Esc clear")
        } else if !composer.draft.isEmpty {
            // An @ command with what follows it (a command being typed is the palette, above).
            model.status = .hint(SessionText.draftHint(composer, config: config.applying(app: app), language: language, terms: terms))
            model.footer = composer.selection != nil
                ? t.tr("\(paste) 粘贴 · \(backspace) 删字 · Esc 取消，选中的文字不变", "\(paste) paste · \(backspace) delete · Esc cancel, the selection stays")
                : t.tr("\(paste) 粘贴 · \(backspace) 删字 · Esc 清除", "\(paste) paste · \(backspace) delete · Esc clear")
        }
        // The refine instruction being typed, as a line of input with its caret at its end, in place of the command's.
        // (An @question conversation's next question while its pinyin is typed.)
        let line = composer.isQuestionChat ? t.tr("追问 › ", "question › ") : t.tr("修改 › ", "refine › ")
        model.input = composer.refineLine.map { PanelModel.Input(prompt: line, text: $0, caret: $0.count) }
            ?? SessionText.panelInput(composer)
        model.header = [SessionText.selectionHeader(composer, language: language)].compactMap { $0 }
            + SessionText.attachmentHeader(composer, language: language, terms: terms)
            + [SessionText.refineHeader(composer, language: language)].compactMap { $0 }
        // A click on a row picks what its number would.
        for index in model.rows.indices { model.rows[index].choice = index }
        if let notice { model.detail = notice }
        // Translate as You Type's pinyin (or dictation): its chip on top.
        if composer.inModeComposition { model.chip = chip().map { PanelModel.Chip($0, language: language) } }
        return model
    }

    /// Whether a list row can be picked (a click, the pointer over it): not a row of information.
    private static func picks(_ choice: Composer.Choice) -> Bool {
        if case let .item(item) = choice.kind { return item.valid }
        return true
    }

    // MARK: - An @question conversation

    /// The panel of an `@question` conversation (`Composer.isQuestionChat`): the next question's line at the top (or where
    /// the conversation can go on, after its last round or ⌘⏎), then the rounds, oldest first, as 问/答 (Q/A) rows, the
    /// earlier ones dimmed and shortened, the latest answer in full. The panel grows with them up to about half the
    /// screen, then scrolls, the latest at the bottom (`PanelModel.transcript`).
    func chatModel(for composer: Composer) -> PanelModel {
        var model = PanelModel()
        model.transcript = true
        let rounds = composer.chatRounds
        let choices = composer.choices
        let answering: Bool
        if case .translating = composer.phase { answering = true } else { answering = false }
        func line(_ text: String) -> String { text.split(whereSeparator: \.isNewline).joined(separator: " ↵ ") }
        for (index, round) in rounds.enumerated() {
            let latest = index == rounds.count - 1
            model.rows.append(PanelModel.Row(label: "", text: t.tr("问：", "Q: ") + SessionText.preview(line(round.question), limit: Self.earlierLimit),
                                             kind: .original, pickable: false, choice: nil))
            let answer = latest ? SessionText.preview(round.answer, limit: Self.latestLimit)
                : SessionText.preview(line(round.answer), limit: Self.earlierLimit)
            let choice = choices.indices.contains(index) ? choices[index] : nil
            model.rows.append(PanelModel.Row(label: String(index + 1), text: t.tr("答：", "A: ") + answer,
                                             kind: latest ? .translation : .original, isComplete: choice?.isComplete ?? true,
                                             pickable: choice.map(Composer.picks) ?? false, choice: index))
        }
        model.highlighted = 2 * composer.highlighted + 1
        // The values hidden from the AI, and an answer whose placeholder it changed past telling.
        if hidden > 0 {
            let original = rounds.first?.question ?? ""
            for (index, choice) in choices.enumerated() where choice.isComplete && Redaction.isAltered(choice.text, original: original) {
                let row = 2 * index + 1
                if model.rows.indices.contains(row) { model.rows[row].comment = PanelRedaction.changed(language: language) }
            }
        }
        // On top: where the conversation can go on (and what was typed to take along), or the next question, the caret
        // after what is typed.
        let typed = composer.refineLine ?? ""
        if composer.showsHandoff {
            let title = composer.chatAtLimit
                ? t.tr("已经聊了 \(composer.chatRound) 轮：在 Claude 或别的 AI 里接着聊", "\(composer.chatRound) rounds in: continue in Claude or another AI")
                : t.tr("在 Claude 或别的 AI 里接着聊", "Continue in Claude or another AI")
            model.handoff = PanelModel.Handoff(title: title, choices: composer.handoffChoices.enumerated().map {
                PanelModel.Handoff.Choice(shortcut: terms.pick($0.offset + 1),
                                          name: SessionText.shortName($0.element, picked: agent, custom: agentCommand, language: language))
            })
            model.input = composer.refineLine.map { PanelModel.Input(prompt: t.tr("接着说 › ", "then › "), text: $0, caret: $0.count) }
        } else if composer.typesRefine {
            let next = min(composer.chatRound + 1, QuestionChat.rounds(composer.questionRounds))
            model.input = PanelModel.Input(prompt: t.tr("追问 \(next)/\(QuestionChat.rounds(composer.questionRounds)) › ",
                                                        "question \(next)/\(QuestionChat.rounds(composer.questionRounds)) › "),
                                           text: typed, caret: typed.count)
        }
        model.header = [SessionText.selectionHeader(composer, language: language)].compactMap { $0 }
        if let error = composer.refineError { model.status = .error(error) }
        if answering, rounds.last?.answer.isEmpty ?? true { model.status = .loading(t.tr("AI 回答中…", "Answering…")) }
        let count = composer.handoffChoices.count
        let copy = terms.copy, again = terms.again, enter = terms.enter, shiftEnter = terms.shiftEnter
        // The digits that pick an answer: up to the round limit, 9 at most (no digit after it).
        let pick = "1–\(min(QuestionChat.rounds(composer.questionRounds), 9))"
        if answering {
            model.footer = composer.refinements.isEmpty ? t.tr("回答中… · Esc 返回", "Answering… · Esc back")
                : t.tr("回答中… · 可以接着打下一个问题 · Esc 回到上一轮", "Answering… · type the next question meanwhile · Esc previous round")
        } else if composer.showsHandoff {
            model.footer = terms.picks(count) + " " + t.tr("接着聊", "continue")
                + (composer.refineLine == nil ? "" : t.tr("，打的字一起带过去", ", with what you typed"))
                + t.tr(" · \(enter) 上屏 · \(pick) 选 · \(copy) 复制 · Esc 返回", " · \(enter) insert · \(pick) pick · \(copy) copy · Esc back")
        } else if composer.showsSavedAnswer, composer.refineLine == nil {
            // A saved answer: ⌘R asks it again for a fresh one (a conversation's latest question).
            model.footer = composer.refinements.isEmpty
                ? t.tr("\(shiftEnter) 追问 · \(enter) 上屏 · \(again) 重新问 · \(copy) 复制 · Esc 返回",
                       "\(shiftEnter) ask · \(enter) insert · \(again) re-ask · \(copy) copy · Esc back")
                : t.tr("\(shiftEnter) 追问 · \(enter) 上屏 · \(pick) 选 · \(again) 重新问 · \(copy) 复制 · Esc 返回",
                       "\(shiftEnter) ask · \(enter) insert · \(pick) pick · \(again) re-ask · \(copy) copy · Esc back")
        } else {
            model.footer = t.tr("\(shiftEnter) 追问 · \(enter) 上屏 · \(pick) 选 · \(copy) 复制 · Esc 返回",
                                "\(shiftEnter) ask · \(enter) insert · \(pick) pick · \(copy) copy · Esc back")
        }
        // When it was saved, or how long the answer took; that earlier rounds were shortened to fit the model.
        var details: [String] = []
        if hidden > 0, !composer.showsSavedAnswer { details.append(PanelRedaction.hiddenLine(hidden, language: language)) }
        if shortened, !composer.showsSavedAnswer { details.append(t.tr("前面几轮已缩短", "earlier rounds shortened")) }
        if !answering {
            if let date = composer.savedAnswerDate {
                details.append(t.tr("保存于\(t.ago(date))", "saved \(t.ago(date))"))
            } else if let time {
                details.append(time)
            }
        }
        model.detail = details.isEmpty ? nil : details.joined(separator: " · ")
        if let notice { model.detail = notice }
        return model
    }

    // MARK: - Translate as You Type's chip

    /// The panel when the composer has nothing to show in it but Translate as You Type's chip: the chip, under it its
    /// list of output languages (the target checked), and the notice.
    public static func chipModel(_ chip: TranslateMode.Chip, notice: String?, language: String) -> PanelModel {
        let t = InterfaceWords(language: language)
        var model = PanelModel()
        model.chip = PanelModel.Chip(chip, language: language)
        model.rows = (chip.choices ?? []).enumerated().map {
            PanelModel.Row(label: chip.checks($0.element) ? "✓" : "", text: t.name($0.element), kind: .candidate, choice: $0.offset)
        }
        if let notice { model.status = .hint(notice) }
        return model
    }
}

/// What the candidate panel says when values were hidden from the AI (`Redaction`): one quiet line beside the time, and
/// a row whose placeholder the model changed past telling (`Redaction.isAltered`) marked, its text as the model wrote it.
public enum PanelRedaction {
    /// "1 item hidden from the AI", in `language`.
    public static func hiddenLine(_ count: Int, language: String) -> String {
        let t = InterfaceWords(language: language)
        return count == 1 ? t.tr("已对 AI 隐藏 1 项", "1 item hidden from the AI")
            : t.tr("已对 AI 隐藏 \(count) 项", "\(count) items hidden from the AI")
    }

    /// The mark of a changed placeholder, in `language`.
    public static func changed(language: String) -> String {
        InterfaceWords(language: language).tr("⚠ 占位符被改动", "⚠ placeholder changed")
    }

    /// `model`'s rows marked (the row of each choice, in order), and the line about what was hidden before its detail,
    /// while results are shown.
    public static func annotate(_ model: inout PanelModel, choices: [Composer.Choice], hidden: Int, phase: Composer.Phase,
                                language: String) {
        guard hidden > 0 else { return }
        switch phase {
        case .translating, .choosing: break
        default: return
        }
        let changed = changed(language: language)
        let original = choices.first { $0.kind == .original }?.text ?? ""
        for (index, choice) in choices.enumerated() where model.rows.indices.contains(index) && choice.kind != .original
            && choice.isComplete && Redaction.isAltered(choice.text, original: original) {
            let comment = model.rows[index].comment
            model.rows[index].comment = comment.isEmpty ? changed : comment + " · " + changed
        }
        model.detail = [hiddenLine(hidden, language: language), model.detail].compactMap { $0 }.joined(separator: " · ")
    }
}

import Foundation

// One @'s panel (`Composer.oneAtRows`), as `PanelPresenter.model(for:)` draws it.
extension PanelPresenter {
    /// The one @ list (`Composer.oneAtRows`): each row says what ⏎ does, its command's name dimmed on the right (a command
    /// found by name: the name, and what it does), each its number (`numbered`); the first highlighted, ↑↓ move.
    func oneAtPanel(_ composer: Composer, into model: inout PanelModel) {
        let all = composer.oneAtRows, first = composer.oneAtFirstVisible
        model.rows = numbered(composer.oneAtVisible.map { oneAtRow($0, composer) })
        model.highlighted = all.isEmpty ? nil : composer.oneAtHighlighted - first
        if all.count > Composer.oneAtRowsShown { model.detail = "\(first + 1)–\(first + model.rows.count) / \(all.count)" }
        let enter = terms.enter, lone = composer.draft == composer.commandTrigger && !composer.engineState.isComposing
        if all.isEmpty, composer.selection == nil, lone || composer.draft != composer.commandTrigger {
            // Nothing to do with the text here (no AI in this app), or nothing offered for the magic key alone: ⏎ types it as
            // it is (Esc gives the key alone up).
            model.footer = lone ? t.tr("\(enter) 原样输入 · Esc 取消", "\(enter) types it as typed · Esc cancel")
                : t.tr("\(enter) 原样输入 · Esc 原样输入", "\(enter) types it as typed · Esc as typed")
        } else if composer.engineState.isComposing {
            model.footer = t.tr("空格 选词 · \(enter) 执行选中的一行 · ↑↓ 选择", "Space picks a word · \(enter) do the highlighted row · ↑↓ choose")
            // While pinyin is composed → is the engine's: Esc gives the keys back.
            model.hints = [PanelModel.Hint("Esc", t.tr("交还给 App", "back to the app"))]
        } else if composer.selection != nil {
            model.footer = t.tr("\(enter) 执行 · ↑↓ 选择 · Esc 取消，选中的文字不变", "\(enter) do it · ↑↓ choose · Esc cancel, the selection stays")
        } else if lone {
            // ⏎ does the highlighted row as after a name; Esc gives the magic key up (nothing goes in), as before.
            model.footer = t.tr("打命令名，或者想做的事 · \(enter) / Tab 选择 · ↑↓ · Esc 取消",
                                "Type a command's name, or what you want · \(enter) / Tab picks · ↑↓ · Esc cancel")
        } else {
            model.footer = t.tr("\(enter) 执行 · ↑↓ 选择 · Esc 原样输入", "\(enter) do it · ↑↓ choose · Esc as typed")
        }
        // → gives the keys back (the text as typed, → on in the app); ⏎ is said on the highlighted row (`Row.action`).
        if !all.isEmpty || composer.selection != nil, !composer.engineState.isComposing {
            model.hints = [PanelModel.Hint("→", t.tr("交还给 App", "back to the app"))]
        }
        // `@stats`'s row: its keys are the input method's, ⏎ opens the page, ⌘C copies the picture, Esc cancels.
        if composer.oneAtStatsHighlighted {
            let words = WeekStatsWords(language: language), copy = terms.copy
            model.footer = "\(enter) \(words.openStats) · \(copy) \(words.copyImageHint) · Esc \(words.cancel)"
            model.hints = [PanelModel.Hint(enter, words.openStats), PanelModel.Hint(copy, words.copyImageHint),
                           PanelModel.Hint("Esc", words.cancel)]
        }
        // ⌥ and a row's number picks it: said once in the keys at the bottom (owner, 0.7.5).
        if !model.rows.isEmpty { model.hints.append(PanelModel.Hint(pickByNumber, t.tr("直接选", "pick", key: "oneAt.pickByPlace"))) }
    }

    /// A row of the one @ list: what ⏎ does, in the interface language, and the command's name with the magic key.
    private func oneAtRow(_ action: OneAt.Action, _ composer: Composer) -> PanelModel.Row {
        typealias Row = PanelModel.Row
        let trigger = composer.commandTrigger
        func named(_ command: Command) -> String { trigger + command.name }
        switch action {
        case let .command(command):
            if command == .stats, let week = weekStats() {
                // `@stats`: the week in a line, how it compares beside it, where the commands came from under it.
                let text = WeekStatsText(week, language: language)
                return Row(label: "", text: text.atStatsTitle,
                           comment: (text.atStatsComparison.map { $0 + " · " } ?? "") + text.sourceSummary, kind: .candidate,
                           icon: IconToken.command(.stats), action: text.openAction, secondLine: text.sourceSummary)
            }
            // An AI command typed by its name where AI isn't used (an app with No AI, a password field): listed, dimmed (as a
            // list's information is) with why in place of its summary, and nothing picks it (`Composer.oneAtUnavailable`).
            if let unavailable = composer.oneAtUnavailable(action) {
                return Row(label: "", text: command.name, comment: unavailable.reason(t), kind: .original,
                           icon: IconToken.command(command), pickable: false)
            }
            // The name alone, as the command list shows it; its summary's examples written with the trigger in use. ⏎ picks
            // it, or runs one that takes no text. A built-in's name says enough: its summary may be left out.
            let runs = command.script?.input == ScriptCommand.Input.none
            return Row(label: "", text: command.name,
                       comment: Self.withTrigger(t.summary(command, status: command.script.flatMap(scriptStatus), terms: terms), trigger),
                       kind: .candidate, icon: IconToken.command(command), action: runs ? t.tr("运行", "run") : t.tr("选择", "choose"),
                       commentDescribes: Command.builtins.contains(command))
        case let .value(value):
            // The sum it answers, before it.
            let sum = (composer.oneAt?.text ?? "").trimmingCharacters(in: .whitespaces)
            return Row(label: "", text: "= " + value, comment: t.tr("上屏", "insert"), kind: .candidate, action: t.tr("上屏", "insert"),
                       lead: sum.isEmpty ? nil : sum)
        case let .open(result):
            let row = SessionText.openRow(result, language: language, terms: terms)
            // An app, a folder or a file with its own icon; a web address with `@open`'s.
            return Row(label: "", text: t.tr("打开 \(row.text)", "Open \(row.text)"), comment: row.comment + " · " + named(.open),
                       kind: .candidate, icon: IconToken.item(result) ?? IconToken.command(.open), action: SessionText.openAction(result, t, terms: terms))
        case let .reminder(reminder):
            // When as read, as the system shows times (「明天 15:00」 or 「明天 下午3:00」), as `@reminder`'s row says it.
            let when = t.when(reminder)
            return Row(label: "", text: t.tr("提醒：\(when) \(reminder.title)", "Reminder: \(when) \(reminder.title)"),
                       comment: named(.reminder), kind: .candidate, icon: IconToken.command(.reminder),
                       action: t.tr("加到提醒事项", "add to Reminders"))
        case let .write(command):
            return Row(label: "", text: oneAtWriting(command, composer), comment: named(command), kind: .candidate,
                       icon: IconToken.command(command), action: t.tr("执行", "do it"))
        case .edit:
            return Row(label: "", text: t.tr("按这句话改选中的文字", "Rewrite the selection as it says"), comment: named(.improve),
                       kind: .candidate, icon: IconToken.command(.improve), action: t.tr("执行", "do it"))
        }
    }

    /// What a writing action does, in a few words: 「改写」, 「翻译成英文」 (the languages `@translate` would translate the
    /// text into), 「问 AI」, 「回复」; one of the user's by its summary.
    private func oneAtWriting(_ command: Command, _ composer: Composer) -> String {
        switch command {
        case .improve: return t.tr("改写", "Improve")
        case .translate:
            let text = composer.selection?.text ?? composer.oneAt?.text ?? ""
            let plan = WritingPlan.make(.translate, text: text, config: config)
            let targets = ([plan.versions].compactMap { $0 }.filter { $0 != plan.input }) + plan.translations
            guard !targets.isEmpty else { return t.tr("翻译", "Translate") }
            let names = targets.map { t.name($0, typing: config.typedChinese) }.joined(separator: t.tr("、", ", "))
            return t.tr("翻译成\(names)", "Translate into \(names)")
        case .question: return t.tr("问 AI", "Ask AI")
        case .reply: return t.tr("回复", "Reply")
        default:
            let summary = t.summary(command, terms: terms)
            return summary.isEmpty ? command.name : summary
        }
    }
}

import Foundation

/// What a text field's session says around the composer, in the interface language it is given (`language`, an
/// `InterfaceLanguage` code: "zh-Hans", "en" …), the same on every platform: the hint under a draft, the lines above the
/// candidate panel's rows, how a long text is shortened in it, an `@open` row, the names of where a conversation can go
/// on, and the small rules the menus and the settings share. Pure: the composer's state, the config and the interface
/// language in, text out; it never reads the process's language (`UIText.language`).
public enum SessionText {
    // MARK: - Shortened text

    /// The start of a selection on one line, for the panel: its first `limit` characters, line breaks shown as "↵".
    public static func selectionPreview(_ text: String, limit: Int = 60) -> String {
        let line = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).joined(separator: " ↵ ")
            .trimmingCharacters(in: .whitespaces)
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
    }

    /// A long answer as the panel shows it (the whole text is inserted).
    public static func preview(_ text: String, limit: Int = 280) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// An `@open` result's row, as you type and after ⏎: its name in the interface language (计算器 in a
    /// Chinese one), and where it is: 「应用」, or its folder (a folder's ends in "/"), after 「内容 · 」 when it
    /// was found by what is in it. A web address says it opens in the browser.
    public static func openRow(_ result: SearchResult, language: String) -> (text: String, comment: String) {
        let t = InterfaceWords(language: language)
        if result.webURL != nil { return (result.name, t.tr("在浏览器中打开", "open in the browser", key: "openRow.inBrowser")) }
        let folder = abbreviatingHome((result.path as NSString).deletingLastPathComponent)
        let place = result.path.hasSuffix(".app") ? t.tr("应用", "app")
            : result.isFolder && !folder.hasSuffix("/") ? folder + "/" : folder
        // The Chinese name is the simplified one: Traditional Chinese has Finder's name, as the other languages.
        return (InterfaceLanguage.isSimplifiedChinese(language) ? result.chineseName ?? result.name : result.name,
                result.matchedContent ? t.tr("内容", "content") + " · " + place : place)
    }

    /// `path` with the home folder written "~".
    static func abbreviatingHome(_ path: String) -> String {
        #if canImport(Darwin)
        return (path as NSString).abbreviatingWithTildeInPath
        #else
        // swift-corelibs-foundation has no abbreviatingWithTildeInPath: the same, by hand.
        let home = CorePaths.home.path
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        #endif
    }

    // MARK: - Inserting after a selection

    /// What of `text` goes in after `selection` and where (at the selection's end, in UTF-16), when `text` starts with
    /// it and the field told where it is; nil otherwise (it's replaced).
    public static func afterSelection(_ text: String, _ selection: Composer.Selection) -> (text: String, at: Int)? {
        guard let range = selection.range, !selection.text.isEmpty, text.hasPrefix(selection.text) else { return nil }
        let rest = (text as NSString).substring(from: (selection.text as NSString).length)
        guard !rest.isEmpty else { return nil }
        return (rest, range.upperBound)
    }

    // MARK: - Notices

    /// How long a notice stays up: by its length, and longer for what the user has to act on.
    public static func noticeDuration(_ text: String, long: Bool) -> TimeInterval {
        long ? 12 : min(5, 1.2 + Double(text.count) * 0.06)
    }

    /// Whether `config` has a language to translate `input` into other than its own.
    public static func hasTranslationTarget(for input: String, config: Config) -> Bool {
        let own = OutputLanguage(config.language(of: input))
        return config.outputLanguages.contains { $0 != own }
    }

    // MARK: - The panel's lines

    /// The hint under a pending draft: "单按 ⌥ → 翻译成英文 / 改写", "Tap ⌥ → translate to English / rewrite" …
    public static func draftHint(_ composer: Composer, config: Config, language: String) -> String {
        guard let command = composer.draftCommand else { return "" }  // a draft always starts with one
        let t = InterfaceWords(language: language)
        let key = composer.actionKey
        let how = key != .space ? t.name(key)
            : composer.spaceActs ? t.name(ActionKey.space) : t.tr("连按两次空格", "Space twice")
        // A snippet: what it will insert, with the blanks typed so far.
        if let preview = composer.snippetPreview { return "\(how) → “" + selectionPreview(preview, limit: 80) + "”" }
        // On the selection: what the action key does with it; `@improve` / `@translate` with something typed rewrite it as asked.
        if let selected = composer.selectionInUse {
            if command.kind == .convert, !WritingMode.parse(command, composer.sentText).text.isEmpty {
                return "\(how) → " + t.tr("按你写的要求改选中的文字", "rewrite the selection as you asked")
            }
            let text = composer.sentText.isEmpty ? selected : composer.sentText
            return "\(how) → " + t.action(command, input: config.language(of: text), config: config, draft: composer.draft)
        }
        // @reply with nothing to reply to yet: what it takes.
        if command == .reply, composer.sentText.isEmpty, composer.attachment == nil {
            return t.tr("回复对方：⌃V 粘贴消息或截图", "Reply: ⌃V their message or a screenshot")
        }
        // A screenshot being read: the action key waits for it.
        if composer.readingScreenshot { return composer.messages.reply.reading }
        // A command with nothing after it yet: what to do (the action key alone only hints); with a screenshot or a
        // message attached, what the action key does with it.
        if composer.sentText.isEmpty, composer.attachment == nil {
            return t.tr("写点内容，或按 ⌃V 粘贴", "Write something, or ⌃V to paste")
        }
        return "\(how) → " + t.action(command, input: config.language(of: composer.sentText), config: config, draft: composer.draft)
    }

    /// The instructions the results shown were refined with, oldest first ("Refined: shorter · more formal"); Esc goes
    /// back one. Nil before any.
    public static func refineHeader(_ composer: Composer, language: String) -> String? {
        let history = composer.refineHistory
        guard composer.isLevelTwo, !history.isEmpty, !composer.isQuestionChat else { return nil }
        let steps = history.map { preview($0, limit: 30) }.joined(separator: " · ")
        return InterfaceWords(language: language).tr("已修改：", "Refined: ") + steps
    }

    /// The line about what the draft has attached (`Composer.attachment`): a screenshot being read or read (on this
    /// device: only its text is sent), or the message copied into `@reply`.
    public static func attachmentHeader(_ composer: Composer, language: String) -> String? {
        let t = InterfaceWords(language: language)
        switch composer.attachment {
        case .screenshot(.recognizing)?:
            return composer.messages.reply.reading
        case let .screenshot(.ready(text))?:
            let lines = text.lineCount
            return t.tr("截图 · \(lines) 行（本机识别）", "Screenshot · \(lines) lines (read on this Mac)") + "\n"
                + t.tr("图片不会离开这台 Mac，只发送认出的文字", "The image stays on this Mac; only its text is sent")
        case let .copiedText(message)?:
            let count = message.count
            return t.tr("复制的消息 · \(count) 字", "Copied message · \(count) characters")
        case nil:
            return nil
        }
    }

    /// The line under the command being written on the selection (`Composer.selection`): what it works on, with its
    /// start and length; or that the command doesn't use it, or that it's too long (either way it's left as it is).
    public static func selectionHeader(_ composer: Composer, language: String) -> String? {
        guard let selection = composer.selection?.text else { return nil }
        let t = InterfaceWords(language: language)
        let count = selection.count
        if composer.selectionTooLong {
            return t.tr("选中的文字太长（\(count) 字，最多 \(Composer.maxSelectionLength) 字），命令不用它",
                        "The selection is too long (\(count) characters, \(Composer.maxSelectionLength) at most): not used")
        }
        if let command = composer.draftCommand, !Composer.usesSelection(command) {
            return t.tr("@\(command.name) 不用选中的文字，它保持原样", "@\(command.name) doesn't use the selection; it stays as it is")
        }
        return t.tr("对选中的文字：“\(selectionPreview(selection))”（\(count) 字）",
                    "On the selection: “\(selectionPreview(selection))” (\(count) characters)")
    }

    /// The command being written on the selection, for the panel's input line: as it would be marked, with its caret
    /// (`Composer.markedCursor`) while it's written.
    public static func panelInput(_ composer: Composer) -> String? {
        guard composer.draftInPanel else { return nil }
        let text = composer.markedText
        guard !composer.isLevelTwo else { return text }
        let at = min(max(composer.markedCursor, 0), text.count)
        return String(text.prefix(at)) + "▏" + String(text.dropFirst(at))
    }

    /// The candidate panel's footer while pinyin is typed in Translate as You Type: what ⏎ and ⇧⏎ do.
    public static func translateModeFooter(_ composer: Composer, language: String) -> String? {
        guard composer.inModeComposition, let target = composer.translateMode?.target else { return nil }
        let t = InterfaceWords(language: language)
        let name = t.name(target)
        return t.tr("空格 选词 · ⏎ 翻译成\(name)上屏 · ⇧⏎ 原文上屏", "Space picks · ⏎ translate to \(name) and insert · ⇧⏎ as typed")
    }

    // MARK: - An @question conversation

    /// The answer a click on row `row` of a conversation picks (rows alternate: a question, then its answer).
    public static func chatChoice(row: Int) -> Int? { row % 2 == 1 ? row / 2 : nil }

    /// A destination's name in the panel and the settings: an agent by its name ("Claude Code", "Gemini CLI" …; the custom
    /// one's from `custom`, its command), `.atAgent` by `picked`'s ("@agent's agent (Gemini CLI)").
    public static func name(_ destination: ChatHandoff.Destination, picked: AgentKind = .claude, custom: [String] = [],
                            language: String) -> String {
        let t = InterfaceWords(language: language)
        switch destination {
        case .atAgent, .claudeCode, .geminiCLI, .kiroCLI, .customAgent:
            return shortName(destination, picked: picked, custom: custom, language: language)
        case .claudeWeb: return t.tr("Claude 网页版", "Claude (web)")
        case .chatgpt: return t.tr("ChatGPT 网页版", "ChatGPT (web)")
        case .gemini: return t.tr("Gemini 网页版", "Gemini (web)")
        case .copy: return t.tr("复制对话", "Copy the conversation")
        }
    }

    /// A destination's short name, for the panel's choices and the settings' chips (the agent by its name, the web ones
    /// are the web's; "Copy" copies the conversation).
    public static func shortName(_ destination: ChatHandoff.Destination, picked: AgentKind = .claude, custom: [String] = [],
                                 language: String) -> String {
        let t = InterfaceWords(language: language)
        switch destination {
        case .atAgent:
            let name = picked.displayName(custom: custom)
            return t.tr("@agent 的 agent（\(name)）", "@agent's agent (\(name))")
        case .claudeCode, .geminiCLI, .kiroCLI, .customAgent: return destination.agent?.displayName(custom: custom) ?? ""
        case .claudeWeb: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        case .copy: return t.tr("复制", "Copy")
        }
    }

    // MARK: - Menus and settings

    /// An input language as the menu and the settings name it: "中文（拼音）", "英文".
    public static func inputName(_ input: Language, language: String) -> String {
        let t = InterfaceWords(language: language)
        return input == .chinese ? t.tr("中文（拼音）", "Chinese (pinyin)") : t.name(input)
    }

    /// Turns a preset on or off, keeping the user's order: one turned on goes last.
    public static func toggled(_ name: String, in current: [String]) -> [String] {
        let enabled = RewriteStyle.resolve(current).map(\.name)
        if enabled.contains(name) { return enabled.filter { $0 != name } }
        return enabled + [name]
    }

    /// `languages` with `language` removed, or added at the end; the last one stays.
    public static func toggled(_ language: Language, in languages: [Language]) -> [Language] {
        if languages.contains(language) { return languages == [language] ? languages : languages.filter { $0 != language } }
        return languages + [language]
    }
}

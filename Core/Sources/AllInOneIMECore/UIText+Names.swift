import Foundation

// The interface text the core makes about its own types (the action key, providers, languages, commands, script
// extensions, reminders): what the candidate panel, the notices and the settings say, the same on every platform. In
// one interface language, `InterfaceWords`' (what the candidate panel and the session's lines are made with,
// `PanelPresenter` and `SessionText`, in the language they are given), and the same as `UIText`'s, in the process's
// interface language (`UIText.language`, `tr`), for a shell's own text and the settings. Errors are in
// UIText+Errors.swift.
extension InterfaceWords {
    /// The language as Chinese or English: what script plugins are told (`run(input, {language})`, "zh" or "en").
    public var pluginLanguage: Language { chinese ? .chinese : .english }

    /// "⏎", "单按 ⌥" / "Tap ⌥", "⌥Space", a recorded "⌘J" …; on Windows "Enter", "Tap Ctrl", "Ctrl+Space", "Ctrl+J"
    /// (`terms`).
    public func name(_ key: ActionKey, terms: PlatformTerms = Platform.current.terms) -> String {
        switch key {
        case .enter: return terms.enter
        case .optionTap: return tr("单按 \(terms.actionTap)", "Tap \(terms.actionTap)")
        case .optionSpace:
            // The Mac's own way to write it in each language (「⌥空格」, "⌥-Leertaste"); elsewhere the key's name and
            // Space's ("Ctrl+Leertaste").
            return terms.keyStyle == .symbols ? tr("⌥空格", "⌥Space") : terms.shortcut(terms.roles.actionTap, tr("空格", "Space"))
        case .space: return tr("空格", "Space")
        case let .shortcut(key): return terms.name(key, space: tr("空格", "Space"))
        }
    }

    /// An input language in this language: "法语" / "French" / "français".
    public func name(_ language: Language) -> String { language.name(in: self.language) }

    /// An output language in this language: "日语" / "Japanese".
    public func name(_ language: OutputLanguage) -> String { language.name(in: self.language) }

    /// A rewrite preset's name ("简洁" / "Concise"); the config keeps the Chinese name.
    public func name(_ style: RewriteStyle) -> String { style.name(in: language) }

    public func summary(_ style: RewriteStyle) -> String { style.summary(in: language) }

    /// What the action key does to a sentence in `input`: "翻译成英文 / 改写", "translate to English / rewrite", …
    public func action(input: Language, config: Config) -> String {
        action(config.improveTranslates ? WritingMode.both : .improve, input: input, config: config)
    }

    /// What `@improve` / `@translate` (or both) do with a sentence in `input`: "润色 / 改写",
    /// "翻译成英文、日语", "translate to English / rewrite".
    public func action(_ mode: WritingMode, input: Language, config: Config) -> String {
        let plan = WritingPlan.make(mode, input: OutputLanguage(input), config: config)
        var parts: [String] = []
        let targets = ([plan.versions].compactMap { $0 }.filter { $0 != plan.input }) + plan.translations
        if !targets.isEmpty {
            let names = targets.map(name).joined(separator: tr("、", ", "))
            parts.append(tr("翻译成\(names)", "translate to \(names)"))
        } else if plan.versions != nil {
            parts.append(tr("润色", "polish"))
        }
        if !plan.styles.isEmpty { parts.append(tr("改写", "rewrite")) }
        return parts.joined(separator: " / ")
    }

    /// What a command does, in the palette: "提问，答案可以直接上屏" / "Ask a question; insert the answer".
    public func summary(_ command: Command, terms: PlatformTerms = Platform.current.terms) -> String {
        if let plugin = command.plugin {
            return plugin.manifest.summary?.text(chinese: chinese) ?? tr("插件", "Plugin")
        }
        if let row = command.snippetRowText {
            return command.bundle.map { row + " · " + tr("来自 \($0)", "From \($0)") } ?? row
        }
        if let custom = command.custom { return custom.summary ?? customKind(custom, terms: terms) }
        if let script = command.script { return summary(script) }
        let agentName = UIText.agentName, paste = terms.paste
        switch command {
        case .improve: return tr("润色，再给几种改写（不翻译）", "Polish in the same language, plus rewrites")
        case .translate: return UIText.triggered(tr("翻译成你加的语言；和 @improve 一起写就翻译加改写", "Translate into your languages; with @improve, both"))
        case .question: return tr("提问，答案可以直接上屏", "Ask a question; insert the answer")
        case .reply: return tr("回复对方：\(paste) 粘贴消息或截图", "Reply: \(paste) their message or a screenshot")
        case .agent: return tr("交给 \(agentName) 去做", "Hand it to \(agentName)")
        case .open: return tr("找文件、文件夹或 App 并打开", "Find a file, folder or app and open it")
        case .read: return tr("读网页正文，可放在句中给 AI 当上下文", "Read a web page; inside a sentence, context for the AI")
        case .tasks: return tr("后台 Claude 任务的进度和回复", "Background Claude tasks: progress and replies")
        case .settings: return tr("打开设置", "Open the settings")
        case .note: return tr("存一条笔记到\(UIText.afterChineseWord(noteDestinationName))", "Save a note to \(noteDestinationName)")
        case .reminder: return tr("加到提醒事项，时间直接写在里面", "Add to Reminders; write the time in it")
        case .py: return tr("运行 Python，结果可以直接上屏", "Run Python; insert the result")
        case .js: return tr("运行 JavaScript，结果可以直接上屏", "Run JavaScript; insert the result")
        case .webSearch: return tr("搜索网页，可放在句中给 AI 当上下文", "Search the web; inside a sentence, context for the AI")
        case .imessage: return tr("发 iMessage：选联系人，写好后确认再发", "Send an iMessage: pick someone, write, confirm")
        case .reportIssue: return tr("报告问题：在 GitHub 上新建问题，附上版本等信息", "Report an issue on GitHub, with your versions and settings")
        default: return ""
        }
    }

    /// A script extension in the list: its title and group ("Flights · Travel"), "(Raycast)" for a Raycast script,
    /// and its status line if it has one ("Pomodoro · 12:04 left").
    public func summary(_ script: ScriptCommand, status: String? = nil) -> String {
        let group = (script.group ?? "").isEmpty || script.group == script.title ? "" : " · " + script.group!
        let raycast = script.source == .raycast ? tr("（Raycast）", " (Raycast)") : ""
        return script.title + group + raycast + (status.map { " · " + $0 } ?? "")
    }

    /// `summary(_ command:)`, with a script extension's status line.
    public func summary(_ command: Command, status: String?, terms: PlatformTerms = Platform.current.terms) -> String {
        command.script.map { summary($0, status: status) } ?? summary(command, terms: terms)
    }

    /// What a script's text should hold: its arguments' placeholders, with commas between ("from city, to city").
    public func placeholders(_ script: ScriptCommand) -> String {
        script.arguments.enumerated().map { index, argument in
            (argument.placeholder.isEmpty ? "$\(index + 1)" : argument.placeholder) + (argument.optional ? tr("（可选）", " (optional)") : "")
        }.joined(separator: ", ")
    }

    /// A custom command without a summary of its own, by what it does.
    public func customKind(_ custom: CustomCommand, terms: PlatformTerms = Platform.current.terms) -> String {
        let program = custom.argv?.first.map { ($0 as NSString).lastPathComponent } ?? ""
        switch custom.type {
        case .prompt: return tr("自定义 AI 指令", "Your own AI instruction")
        case .run: return tr("运行 ", "Run ") + program
        case .terminal:
            return (terms.terminal == .terminalApp ? tr("在终端运行 ", "Run in Terminal: ") : tr("在终端运行 ", "Run in a terminal: "))
                + program
        case .link: return tr("在浏览器打开 ", "Open in the browser: ") + (LinkTemplate.host(custom.url) ?? "")
        case .snippet: return tr("插入文字", "Insert text")
        }
    }

    /// What the action key does with a command draft, after "⏎ →".
    /// `draft`: the text typed, so `@translate @improve …` reads as both.
    public func action(_ command: Command, input: Language, config: Config, draft: String = "",
                       terms: PlatformTerms = Platform.current.terms) -> String {
        if command.plugin != nil, command.kind == .run { return tr("运行插件", "run the plugin") }
        if let script = command.script {
            if script.output == .list { return tr("选中这一项", "pick") }
            let run = script.background ? tr("在后台运行", "run in the background") : tr("运行", "run")
            return script.arguments.isEmpty || placeholders(script) == "$1" ? run : run + tr("（\(placeholders(script))）", " (\(placeholders(script)))")
        }
        if command.kind == .link { return tr("在浏览器打开", "open in the browser") }
        switch command.custom?.type {
        case .prompt?: return tr("AI 生成", "generate")
        case .run?: return tr("运行", "run")
        case .terminal?: return terms.terminal == .terminalApp ? tr("在终端运行", "run in Terminal") : tr("在终端运行", "run in a terminal")
        case .snippet?: return tr("插入文字", "Insert text")
        case .link?, nil: break
        }
        switch command {
        case .improve, .translate:
            return action(WritingMode.parse(command, draft, improveTranslates: config.improveTranslates,
                                            trigger: config.commandTrigger).mode, input: input, config: config)
        case .question: return tr("提问", "ask")
        case .reply: return tr("写三条回复", "write three replies")
        case .agent:
            let agent = config.agent.displayName(custom: config.agentCommand)
            if config.claudeInBackground && config.agent.supportsBackground {
                return tr("交给 \(agent) 在后台做", "hand it to \(agent) in the background")
            }
            return terms.terminal == .terminalApp ? tr("在终端打开 \(agent)", "open \(agent) in Terminal")
                : tr("在终端打开 \(agent)", "open \(agent) in a terminal")
        case .open: return tr("搜索并打开", "search and open")
        case .read: return tr("读网页", "read the page")
        case .tasks: return tr("查看后台任务", "show the background tasks")
        case .settings: return tr("打开设置", "open the settings")
        case .note: return tr("存到\(UIText.afterChineseWord(noteDestinationName))", "save to \(noteDestinationName)")
        case .reminder: return tr("看一下再加到提醒事项", "check, then add to Reminders")
        case .py: return tr("运行 Python", "run Python")
        case .js: return tr("运行 JavaScript", "run JavaScript")
        case .webSearch: return tr("搜索网页", "search the web")
        case .imessage: return tr("确认后发送", "check, then send")
        case .reportIssue: return tr("看一下再在 GitHub 上新建问题", "check, then open a new issue on GitHub")
        default: return ""
        }
    }

    /// When a reminder is due, as its row and the notice say it: 「明天 15:00」 (or 「明天 下午3:00」, following the
    /// Mac's 12/24-hour setting, or `UIText.clock24`), 「10月15日 周四」, 「未设时间」 ("tomorrow 3:00 PM", "Thu, Oct 15",
    /// "no date"), with 「已过」 / "overdue" once that time is over.
    public func when(_ reminder: ReminderDraft, now: Date = Platform.current.clock.now) -> String {
        reminder.when(now: now, language: language, clock24: UIText.clock24 ?? ReminderDraft.systemUses24HourClock)
    }

    /// Where `@note` saves, by name (`UIText.noteDestinationName`, as the session set it with the settings); until then
    /// 备忘录 / Notes in this language.
    public var noteDestinationName: String { UIText.noteDestinationState.withLock { $0 } ?? tr("备忘录", "Notes") }

    /// The row comment of an answer: "回答" / "answer", the agent's name.
    public func answerLabel(_ command: Command?) -> String {
        if command == .webSearch { return tr("搜索结果", "results") }
        if command?.kind == .run { return command?.plugin.map { UIText.commandTrigger + $0.name } ?? tr("输出", "output") }
        if command == .reply { return tr("回复", "reply") }
        return command == .agent ? UIText.agentName : tr("回答", "answer")
    }

    /// How long ago `date` was, in words (`RelativeTime.Style.words`): "刚刚" / "just now", "3 小时前" / "3 hours ago" …
    public func ago(_ date: Date, now: Date = Platform.current.clock.now) -> String {
        RelativeTime.ago(date, now: now, language: language, style: .words)
    }
}

extension UIText {
    /// The same, as Chinese or English: what script plugins are told (`run(input, {language})`, "zh" or "en").
    public static var pluginLanguage: Language { words.pluginLanguage }

    /// "单按 ⌥" / "Tap ⌥", …
    public static func name(_ key: ActionKey) -> String { words.name(key) }

    /// The action key in the settings picker: "⏎ 回车" / "⏎ Return" (on Windows "Enter 键" / "Enter"), otherwise as `name`,
    /// the keys named as `terms` names them.
    public static func pickerName(_ key: ActionKey, terms: PlatformTerms = Platform.current.terms) -> String {
        guard key == .enter else { return words.name(key, terms: terms) }
        return terms.keyStyle == .symbols ? tr("⏎ 回车", "⏎ Return") : tr("Enter 键", "Enter")
    }

    /// "单按 ⌥" / "tap ⌥", "按空格" / "press Space", …
    public static func howToPress(_ key: ActionKey) -> String {
        switch key {
        case .enter: return tr("按 ⏎", "press Return")
        case .optionTap: return tr("单按 ⌥", "tap ⌥")
        case .optionSpace: return tr("按 ⌥空格", "press ⌥Space")
        case .space: return tr("按空格", "press Space")
        case let .shortcut(key): return tr("按 \(key.name)", "press \(key.name)")
        }
    }

    public static func name(_ provider: Provider) -> String {
        switch provider {
        case .openai: return tr("兼容 OpenAI 的服务", "OpenAI-compatible API")
        case .hosted: return tr("AllInOneIME 云（登录即用）", "AllInOneIME Cloud (sign in)")
        case .apple: return tr("Apple Intelligence（本机）", "Apple Intelligence (on this Mac)")
        default: return provider.displayName
        }
    }

    /// Why Apple Intelligence can't be used here, in a few words (the provider picker).
    public static func reason(_ availability: AppleModelAvailability) -> String {
        switch availability {
        case .available: return ""
        case .unsupportedSystem: return tr("需要 macOS 26", "needs macOS 26")
        case .deviceNotEligible: return tr("这台 Mac 不支持", "not supported on this Mac")
        case .appleIntelligenceNotEnabled: return tr("未打开", "turned off")
        case .modelNotReady: return tr("模型还没准备好", "model not ready")
        }
    }

    /// An input language in the interface language: "法语" / "French" / "français".
    public static func name(_ language: Language) -> String { words.name(language) }

    /// An output language in the interface language: "日语" / "Japanese".
    public static func name(_ language: OutputLanguage) -> String { words.name(language) }

    /// A rewrite preset's name in the window ("简洁" / "Concise"); the config keeps the Chinese name.
    public static func name(_ style: RewriteStyle) -> String { words.name(style) }

    public static func summary(_ style: RewriteStyle) -> String { words.summary(style) }

    /// What the action key does to a sentence in `input`: "翻译成英文 / 改写", "translate to English / rewrite", …
    public static func action(input: Language, config: Config) -> String { words.action(input: input, config: config) }

    /// What `@improve` / `@translate` (or both) do with a sentence in `input`: "润色 / 改写",
    /// "翻译成英文、日语", "translate to English / rewrite".
    public static func action(_ mode: WritingMode, input: Language, config: Config) -> String {
        words.action(mode, input: input, config: config)
    }

    /// What a command does, in the palette: "提问，答案可以直接上屏" / "Ask a question; insert the answer".
    public static func summary(_ command: Command) -> String { words.summary(command) }

    /// A script extension in the list: its title and group ("Flights · Travel"), "(Raycast)" for a Raycast script,
    /// and its status line if it has one ("Pomodoro · 12:04 left").
    public static func summary(_ script: ScriptCommand, status: String? = nil) -> String { words.summary(script, status: status) }

    /// `summary(_ command:)`, with a script extension's status line.
    public static func summary(_ command: Command, status: String?) -> String { words.summary(command, status: status) }

    /// What a script's text should hold: its arguments' placeholders, with commas between ("from city, to city").
    public static func placeholders(_ script: ScriptCommand) -> String { words.placeholders(script) }

    /// Why a script, a bundle or a command of one isn't loaded (Settings).
    public static func describe(_ problem: ScriptCommand.Problem, file: URL) -> String {
        switch problem {
        case let .missing(key): return tr("缺少 \(key)", "\(key) is missing")
        case let .newerProtocol(version):
            return tr("要更新版的 AllInOneIME（协议版本 \(version)，这一版支持 \(ScriptCommand.protocolVersion)）",
                      "Needs a newer AllInOneIME (protocol \(version); this one speaks \(ScriptCommand.protocolVersion))")
        case let .badValue(key, value): return tr("\(key) 的值用不了：\(value)", "\(key) can't be “\(value)”")
        case let .badArgument(n): return tr("argument\(n) 读不懂（要是 JSON，前面的参数也要有）",
                                            "argument\(n) can't be read (it must be JSON, after the ones before it)")
        case .notRunnable: return tr("不能运行：没有执行权限，第一行也不是 #!", "Can't be run: not executable, and no #! line")
        case .noName: return tr("文件名里没有英文字母，做不了命令名", "No letter in the file name to name the command")
        case .notForMac: return tr("不是给 macOS 用的（platform）", "Not for macOS (platform)")
        case let .badBundle(problem):
            switch problem {
            case .notJSON: return tr("extension.json 不是 JSON 对象", "extension.json isn't a JSON object")
            case .badName: return tr("扩展包的 name 只能用字母、数字、- 和 _", "The bundle's name must be letters, digits, - or _")
            case .noCommands: return tr("extension.json 里没有命令", "extension.json names no commands")
            case .badPreference: return tr("有一个偏好设置没有 name，或者 type 不认识", "A preference has no name, or a type this app doesn't know")
            }
        case .brokenLink: return tr("这个替身（符号链接）指向的东西不在了", "A link to something that isn't there")
        case .bundleTaken: return tr("已经有一个同名的扩展包", "Another bundle with this name is loaded")
        case let .nameTaken(taken, owner):
            let name = UIText.commandTrigger + taken
            switch owner {
            case .builtIn: return tr("\(name) 是内置命令的名字", "\(name) is a built-in command")
            case .plugin: return tr("\(name) 是一个插件的名字", "\(name) is a plugin's name")
            case .custom: return tr("\(name) 是一个自定义命令的名字", "\(name) is one of your custom commands")
            case let .command(id):
                return tr("这个名字已经给了 \(id)（先找到的生效）", "The name is taken by \(id), found first")
            case let .snippet(id):
                return tr("这个名字已经给了片段 \(id)（先找到的生效）", "The name is taken by the snippet \(id), found first")
            }
        }
    }

    /// What a script extension does with what it prints, as Settings lists it.
    public static func name(_ output: ScriptCommand.Output) -> String {
        switch output {
        case .insert: return tr("上屏", "insert")
        case .show: return tr("显示", "show")
        case .list: return tr("列表", "list")
        case .silent: return tr("提示", "notice")
        }
    }

    /// A custom command without a summary of its own, by what it does.
    public static func customKind(_ custom: CustomCommand) -> String { words.customKind(custom) }

    /// What the action key does with a command draft, after "⏎ →".
    /// `draft`: the text typed, so `@translate @improve …` reads as both.
    public static func action(_ command: Command, input: Language, config: Config, draft: String = "") -> String {
        words.action(command, input: input, config: config, draft: draft)
    }

    /// When a reminder is due, as its row and the notice say it: 「明天 15:00」 (or 「明天 下午3:00」, following the
    /// Mac's 12/24-hour setting, or `clock24`), 「10月15日 周四」, 「未设时间」 ("tomorrow 3:00 PM", "Thu, Oct 15", "no
    /// date"), with 「已过」 / "overdue" once that time is over.
    public static func when(_ reminder: ReminderDraft, now: Date = Platform.current.clock.now) -> String {
        words.when(reminder, now: now)
    }

    /// Times shown with the 24-hour clock (true) or the 12-hour one (false) whatever the system uses; nil follows
    /// the system (on the Mac, System Settings → General → Date & Time). The self-test pins it, so the README images read
    /// the same on every Mac.
    public static var clock24: Bool? {
        get { clock24State.withLock { $0 } }
        set { clock24State.withLock { $0 = newValue } }
    }

    /// The agent `@agent` hands the text to, by name (`AgentKind.displayName`; the session sets it with the settings).
    public static var agentName: String {
        get { agentNameState.withLock { $0 } }
        set { agentNameState.withLock { $0 = newValue } }
    }

    /// Where `@note` saves, by name (`NoteDestination.name`: 备忘录 / Notes, Notion, Obsidian, “Inbox”; the session
    /// sets it with the settings). Until then 备忘录 / Notes, in the interface language as it is when read.
    public static var noteDestinationName: String {
        get { words.noteDestinationName }
        set { noteDestinationState.withLock { $0 = newValue } }
    }

    /// The symbol that starts a command (`Config.commandTrigger`; the session and Settings set it with the settings, a
    /// settings document's is its config's: `scopedCommandTrigger`): what the interface's "@" is (`triggered`). @ until
    /// then.
    public static var commandTrigger: String {
        get { scopedCommandTrigger ?? commandTriggerState.withLock { $0 } }
        set { commandTriggerState.withLock { $0 = newValue } }
    }

    /// The command trigger of what one task makes (or one synchronous scope: `$scopedCommandTrigger.withValue`), the
    /// process's left as it is: a settings document's (`SettingsService`). Nil: the process's.
    @TaskLocal public static var scopedCommandTrigger: String?

    /// Interface text that names commands ("@improve", "@ commands") with the command trigger in place of each "@" of the
    /// text itself (the translations keep the ASCII @ for this); what the user gave in it (an agent's program, a plugin's
    /// version or hosts) goes in through `verbatim`, its own "@" left as it is.
    public static func triggered(_ text: String) -> String { triggered(text, trigger: commandTrigger) }

    /// `text` naming commands with `trigger`: a window's own settings' (the Mac's Settings window draws with its config's,
    /// whatever the process's is when it draws).
    public static func triggered(_ text: String, trigger: String) -> String {
        let named = trigger == "@" ? text : text.replacingOccurrences(of: "@", with: trigger)
        return named.contains(verbatimAt) ? named.replacingOccurrences(of: verbatimAt, with: "@") : named
    }

    /// `argument`, something the user gave (or a plugin's author), as it goes into text that names commands (`triggered`):
    /// its "@"s are no command's, and stay. Only inside `triggered`'s text, which puts them back.
    public static func verbatim(_ argument: String) -> String { argument.replacingOccurrences(of: "@", with: verbatimAt) }

    /// What stands for an argument's "@" until `triggered` puts it back: a noncharacter, never in text.
    static let verbatimAt = String(Character(Unicode.Scalar(0xFDD0)!))  // a literal can't hold one

    private static let clock24State = Locked<Bool?>(initialState: nil)
    private static let commandTriggerState = Locked(initialState: "@")
    private static let agentNameState = Locked(initialState: AgentKind.claude.displayName())
    /// The name the session set (`noteDestinationName`); nil until then.
    static let noteDestinationState = Locked<String?>(initialState: nil)

    /// `name` as it follows a Chinese word ("存到"): straight after it when it starts with Chinese or a full-width mark
    /// (备忘录, “收件箱”, 「…」), else after a space (Notion, Obsidian).
    public static func afterChineseWord(_ name: String) -> String {
        guard let first = name.unicodeScalars.first else { return name }
        let joined = first.properties.isIdeographic || [0x201C, 0x2018].contains(first.value)
            || (0x2E80...0x303F).contains(first.value) || (0x3040...0x30FF).contains(first.value)
            || (0xAC00...0xD7AF).contains(first.value) || (0xFF00...0xFFEF).contains(first.value)
        return joined ? name : " " + name
    }

    /// Added to the notice when `@agent` took the Chrome page along: " · 带上了网页「标题」".
    public static func withPage(_ title: String) -> String {
        let short = title.count > 40 ? String(title.prefix(40)) + "…" : title
        guard !short.isEmpty else { return tr(" · 带上了网页", " · with the page") }
        return tr(" · 带上了网页「\(short)」", " · with the page “\(short)”")
    }

    /// The agent `config` picks, by name.
    public static func agentName(_ config: Config) -> String { config.agent.displayName(custom: config.agentCommand) }

    /// The row comment of an answer: "回答" / "answer", the agent's name.
    public static func answerLabel(_ command: Command?) -> String { words.answerLabel(command) }

    /// How long ago `date` was, in the interface language: "刚刚" / "just now", "3 小时前" / "3 hours ago" …
    public static func ago(_ date: Date, now: Date = Platform.current.clock.now) -> String { words.ago(date, now: now) }
}

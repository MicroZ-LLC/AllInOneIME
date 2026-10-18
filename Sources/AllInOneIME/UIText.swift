import AllInOneIMECore
import Foundation

/// Interface language (settings window, candidate panel, notices, input menu): the one picked in the
/// settings (config `uiLanguage`), else the first of the system's preferred languages that the app ships
/// (`InterfaceLanguage.pick`; System Settings → General → Language & Region). Simplified Chinese and English come from
/// the code (`tr`), the others from Resources/Localizable.xcstrings.
enum UIText {
    /// Picked in the settings (config `uiLanguage`: "zh", "en" or a shipped code; applied from the config when a
    /// text field or the window opens); nil follows the system. Main thread only.
    static var choice: String? {
        didSet {
            guard choice != oldValue else { return }
            language = picked()
            // The floating panel, on screen all along, redraws in the new language.
            NotificationCenter.default.post(name: .allInOneIMEInterfaceLanguageChanged, object: nil)
        }
    }
    /// Where the translations are (`<code>.lproj`): the app; a stand-in while the self-test checks them. Main thread only.
    static var app = Bundle.main {
        didSet {
            shipped = InterfaceLanguage.shipped(in: app)
            language = picked()
            InterfaceText.lookup = InterfaceText.bundleLookup(app: app)
        }
    }
    /// The languages `app` ships: "en", "zh-Hans" and its other `.lproj` folders.
    private(set) static var shipped = InterfaceLanguage.shipped()
    /// Read once per process (macOS relaunches apps after a language change).
    static let systemLanguage = InterfaceLanguage.pick(preferred: Locale.preferredLanguages, shipped: shipped)

    /// The interface language's code: "zh-Hans", "en", … Worked out when `choice` or `app` changes, not per text: `tr`
    /// reads it on the candidate panel's hot path. The first read hands the core the app's translations (`useApp`).
    private(set) static var language: String = {
        useApp()
        return picked()
    }() {
        didSet { chinese = InterfaceLanguage.isChinese(language) }
    }

    private static func picked() -> String { InterfaceLanguage.code(forSetting: choice, shipped: shipped) ?? systemLanguage }

    /// Points `InterfaceText.lookup`, which the core's texts and `tr` look translations up through, at `app`'s compiled
    /// `<code>.lproj` bundles (each found once).
    static func useApp() { InterfaceText.lookup = InterfaceText.bundleLookup(app: app) }

    /// Whether the interface is Chinese: what only comes in Chinese and English (key names, …) is Chinese then.
    private(set) static var chinese = InterfaceLanguage.isChinese(language)

    /// The same, as Chinese or English: what script plugins are told (`run(input, {language})`, "zh" or "en").
    static var pluginLanguage: Language { chinese ? .chinese : .english }

    /// Text written only in Simplified Chinese and English, without a catalog entry (an error's Chinese, a short
    /// language name), for the Chinese interface: as it is in Simplified Chinese, in Traditional characters in
    /// Traditional Chinese (ICU's Hans-Hant transform), never Simplified Chinese there.
    static func chineseOnly(_ text: String) -> String {
        guard !InterfaceLanguage.isSimplifiedChinese(language) else { return text }
        return text.applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false) ?? text
    }

    /// "单按 ⌥" / "Tap ⌥", …
    static func name(_ key: ActionKey) -> String {
        switch key {
        case .enter: return "⏎"
        case .optionTap: return tr("单按 ⌥", "Tap ⌥")
        case .optionSpace: return tr("⌥空格", "⌥Space")
        case .space: return tr("空格", "Space")
        case let .shortcut(key): return key.name
        }
    }

    /// The action key in the settings picker: "⏎ 回车" / "⏎ Return", otherwise as `name`.
    static func pickerName(_ key: ActionKey) -> String {
        key == .enter ? tr("⏎ 回车", "⏎ Return") : name(key)
    }

    /// "单按 ⌥" / "tap ⌥", "按空格" / "press Space", …
    static func howToPress(_ key: ActionKey) -> String {
        switch key {
        case .enter: return tr("按 ⏎", "press Return")
        case .optionTap: return tr("单按 ⌥", "tap ⌥")
        case .optionSpace: return tr("按 ⌥空格", "press ⌥Space")
        case .space: return tr("按空格", "press Space")
        case let .shortcut(key): return tr("按 \(key.name)", "press \(key.name)")
        }
    }

    static func name(_ provider: Provider) -> String {
        switch provider {
        case .openai: return tr("兼容 OpenAI 的服务", "OpenAI-compatible API")
        case .hosted: return tr("AllInOneIME 云（登录即用）", "AllInOneIME Cloud (sign in)")
        case .apple: return tr("Apple Intelligence（本机）", "Apple Intelligence (on this Mac)")
        default: return provider.displayName
        }
    }

    /// Why Apple Intelligence can't be used here, in a few words (the provider picker).
    static func reason(_ availability: AppleModelAvailability) -> String {
        switch availability {
        case .available: return ""
        case .unsupportedSystem: return tr("需要 macOS 26", "needs macOS 26")
        case .deviceNotEligible: return tr("这台 Mac 不支持", "not supported on this Mac")
        case .appleIntelligenceNotEnabled: return tr("未打开", "turned off")
        case .modelNotReady: return tr("模型还没准备好", "model not ready")
        }
    }

    /// An input language in the interface language: "法语" / "French" / "français".
    static func name(_ language: Language) -> String { language.name(in: self.language) }

    /// An output language in the interface language: "日语" / "Japanese".
    static func name(_ language: OutputLanguage) -> String { language.name(in: self.language) }

    /// A rewrite preset's name in the window ("简洁" / "Concise"); the config keeps the Chinese name.
    static func name(_ style: RewriteStyle) -> String { style.name(in: language) }

    static func summary(_ style: RewriteStyle) -> String { style.summary(in: language) }

    /// What the action key does to a sentence in `input`: "翻译成英文 / 改写", "translate to English / rewrite", …
    static func action(input: Language, config: Config) -> String {
        action(config.improveTranslates ? WritingMode.both : .improve, input: input, config: config)
    }

    /// What `@improve` / `@translate` (or both) do with a sentence in `input`: "润色 / 改写",
    /// "翻译成英文、日语", "translate to English / rewrite".
    static func action(_ mode: WritingMode, input: Language, config: Config) -> String {
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
    static func summary(_ command: Command) -> String {
        if let plugin = command.plugin {
            return plugin.manifest.summary?.text(chinese: chinese) ?? tr("插件", "Plugin")
        }
        if let row = command.snippetRowText {
            return command.bundle.map { row + " · " + tr("来自 \($0)", "From \($0)") } ?? row
        }
        if let custom = command.custom { return custom.summary ?? customKind(custom) }
        if let script = command.script { return summary(script) }
        switch command {
        case .improve: return tr("润色，再给几种改写（不翻译）", "Polish in the same language, plus rewrites")
        case .translate: return tr("翻译成你加的语言；和 @improve 一起写就翻译加改写", "Translate into your languages; with @improve, both")
        case .question: return tr("提问，答案可以直接上屏", "Ask a question; insert the answer")
        case .reply: return tr("回复对方：⌃V 粘贴消息或截图", "Reply: ⌃V their message or a screenshot")
        case .agent: return tr("交给 \(agentName) 去做", "Hand it to \(agentName)")
        case .open: return tr("找文件、文件夹或 App 并打开", "Find a file, folder or app and open it")
        case .read: return tr("读网页正文，可放在句中给 AI 当上下文", "Read a web page; inside a sentence, context for the AI")
        case .tasks: return tr("后台 Claude 任务的进度和回复", "Background Claude tasks: progress and replies")
        case .settings: return tr("打开设置", "Open the settings")
        case .note: return tr("存到备忘录", "Save to Notes")
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
    static func summary(_ script: ScriptCommand, status: String? = nil) -> String {
        let group = (script.group ?? "").isEmpty || script.group == script.title ? "" : " · " + script.group!
        let raycast = script.source == .raycast ? tr("（Raycast）", " (Raycast)") : ""
        return script.title + group + raycast + (status.map { " · " + $0 } ?? "")
    }

    /// `summary(_ command:)`, with a script extension's status line.
    static func summary(_ command: Command, status: String?) -> String {
        command.script.map { summary($0, status: status) } ?? summary(command)
    }

    /// What a script's text should hold: its arguments' placeholders, with commas between ("from city, to city").
    static func placeholders(_ script: ScriptCommand) -> String {
        script.arguments.enumerated().map { index, argument in
            (argument.placeholder.isEmpty ? "$\(index + 1)" : argument.placeholder) + (argument.optional ? tr("（可选）", " (optional)") : "")
        }.joined(separator: ", ")
    }

    /// Why a script, a bundle or a command of one isn't loaded (Settings).
    static func describe(_ problem: ScriptCommand.Problem, file: URL) -> String {
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
            let name = "@" + taken
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
    static func name(_ output: ScriptCommand.Output) -> String {
        switch output {
        case .insert: return tr("上屏", "insert")
        case .show: return tr("显示", "show")
        case .list: return tr("列表", "list")
        case .silent: return tr("提示", "notice")
        }
    }

    /// A custom command without a summary of its own, by what it does.
    static func customKind(_ custom: CustomCommand) -> String {
        switch custom.type {
        case .prompt: return tr("自定义 AI 指令", "Your own AI instruction")
        case .run: return tr("运行 ", "Run ") + (custom.argv?.first.map { ($0 as NSString).lastPathComponent } ?? "")
        case .terminal: return tr("在终端运行 ", "Run in Terminal: ") + (custom.argv?.first.map { ($0 as NSString).lastPathComponent } ?? "")
        case .link: return tr("在浏览器打开 ", "Open in the browser: ") + (LinkTemplate.host(custom.url) ?? "")
        case .snippet: return tr("插入文字", "Insert text")
        }
    }

    /// What the action key does with a command draft, after "⏎ →".
    /// `draft`: the text typed, so `@translate @improve …` reads as both.
    static func action(_ command: Command, input: Language, config: Config, draft: String = "") -> String {
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
        case .terminal?: return tr("在终端运行", "run in Terminal")
        case .snippet?: return tr("插入文字", "Insert text")
        case .link?, nil: break
        }
        switch command {
        case .improve, .translate:
            return action(WritingMode.parse(command, draft, improveTranslates: config.improveTranslates).mode, input: input, config: config)
        case .question: return tr("提问", "ask")
        case .reply: return tr("写三条回复", "write three replies")
        case .agent:
            let agent = config.agent.displayName(custom: config.agentCommand)
            return config.claudeInBackground && config.agent.supportsBackground
                ? tr("交给 \(agent) 在后台做", "hand it to \(agent) in the background")
                : tr("在终端打开 \(agent)", "open \(agent) in Terminal")
        case .open: return tr("搜索并打开", "search and open")
        case .read: return tr("读网页", "read the page")
        case .tasks: return tr("查看后台任务", "show the background tasks")
        case .settings: return tr("打开设置", "open the settings")
        case .note: return tr("存到备忘录", "save to Notes")
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
    /// Mac's 12/24-hour setting, or `clock24`), 「10月15日 周四」, 「未设时间」 ("tomorrow 3:00 PM", "Thu, Oct 15", "no
    /// date"), with 「已过」 / "overdue" once that time is over.
    static func when(_ reminder: ReminderDraft, now: Date = Date()) -> String {
        reminder.when(now: now, language: language, clock24: clock24 ?? ReminderDraft.systemUses24HourClock)
    }

    /// Times shown with the 24-hour clock (true) or the 12-hour one (false) whatever the Mac uses; nil follows
    /// the Mac (System Settings → General → Date & Time). The self-test pins it, so the README images read the
    /// same on every Mac. Main thread only.
    static var clock24: Bool?

    /// The agent `@agent` hands the text to, by name (`AgentKind.displayName`; the controller sets it with the settings).
    /// Main thread only.
    static var agentName = AgentKind.claude.displayName()

    /// Added to the notice when `@agent` took the Chrome page along: " · 带上了网页「标题」".
    static func withPage(_ title: String) -> String {
        let short = title.count > 40 ? String(title.prefix(40)) + "…" : title
        guard !short.isEmpty else { return tr(" · 带上了网页", " · with the page") }
        return tr(" · 带上了网页「\(short)」", " · with the page “\(short)”")
    }

    /// The agent `config` picks, by name.
    static func agentName(_ config: Config) -> String { config.agent.displayName(custom: config.agentCommand) }

    /// The row comment of an answer: "回答" / "answer", the agent's name.
    static func answerLabel(_ command: Command?) -> String {
        if command == .webSearch { return tr("搜索结果", "results") }
        if command?.kind == .run { return command?.plugin.map { "@" + $0.name } ?? tr("输出", "output") }
        if command == .reply { return tr("回复", "reply") }
        return command == .agent ? agentName : tr("回答", "answer")
    }

    /// An error as the settings window shows it.
    static func describe(_ error: Error) -> String {
        // One line that says what to do ("SSO sign-in expired: run aws sso login --profile X").
        if let error = error as? AWSCredentialError { return error.shortMessage(language: language) }
        if let error = error as? WebReader.ReadError {
            switch error {
            case let .invalidURL(text): return tr("不是网址：\(text)", "Not a web address: \(text)")
            case let .http(status): return tr("网页返回 HTTP \(status)", "The page answered HTTP \(status)")
            case let .unsupported(type): return tr("读不了这种内容（\(type)）", "Can't read this kind of content (\(type))")
            case .empty: return tr("网页上没有找到文字（要靠 JavaScript 显示的网页读不了）",
                                   "No text found on the page (pages that need JavaScript can't be read)")
            case .tooLarge: return tr("网页太大（超过 2 MB）", "The page is larger than 2 MB")
            }
        }
        if let error = error as? WebSearch.SearchError { return describe(error) }
        if let error = error as? CommandPipelineError, case let .inner(name, underlying) = error,
           [Command.read, .py, .js, .webSearch].contains(where: { $0.name == name }) {
            return "@" + name + tr("：", ": ") + underlying
        }
        if let error = error as? NotesBridge.NotesError {
            switch error {
            case .notPermitted:
                return tr("没有权限控制「备忘录」：在 系统设置 → 隐私与安全性 → 自动化 里允许 AllInOneIME",
                          "Not allowed to control Notes: allow AllInOneIME in System Settings → Privacy & Security → Automation")
            case let .failed(number):
                // Our words and AppleScript's number, never its message (in the system's language).
                return tr("没有存到备忘录（错误 \(number)）", "Not saved to Notes (error \(number))")
            }
        }
        if let error = error as? RemindersBridge.RemindersError {
            switch error {
            case .notPermitted:
                return tr("没有权限使用「提醒事项」：在 系统设置 → 隐私与安全性 → 提醒事项 里允许 AllInOneIME",
                          "Not allowed to use Reminders: allow AllInOneIME in System Settings → Privacy & Security → Reminders")
            case .noAccount:
                return tr("没有能放提醒事项的账户：先打开「提醒事项」App 看看", "No account for reminders: open the Reminders app to set one up")
            case .notFound: return tr("这条提醒事项已经不在了", "That reminder is gone")
            // Our words and EventKit's code, never its message (in the system's language).
            case let .failed(code): return tr("提醒事项出错（错误 \(code)）", "Reminders failed (error \(code))")
            }
        }
        if let error = error as? MessageSendError {
            switch error {
            case .notPermitted:
                return tr("没有控制「信息」的权限：系统设置 → 隐私与安全性 → 自动化 → AllInOneIME → 打开「信息」",
                          "Not allowed to control Messages: System Settings → Privacy & Security → Automation → AllInOneIME → turn on Messages")
            case .appMissing: return tr("这台 Mac 上没有「信息」App", "The Messages app isn't on this Mac")
            case let .failed(code):
                return tr("「信息」没有发出去（错误 \(code)）：看看「信息」里是否登录了 iMessage，号码 / 邮箱是否正确",
                          "Messages didn't send it (error \(code)): check that iMessage is signed in and the number or email is right")
            }
        }
        if let error = error as? CommandRunner.RunError {
            switch error {
            case let .notFound(program): return tr("找不到程序 \(program)", "Program not found: \(program)")
            case let .failed(status, message):
                return message.isEmpty ? tr("程序出错（退出码 \(status)）", "The program failed (exit status \(status))") : message
            case let .timedOut(seconds):
                let n = Int(seconds.rounded())
                return tr("运行超过 \(n) 秒，已停止", "Stopped after \(n) seconds")
            case .tooMuchOutput: return tr("输出太多，已停止", "Stopped: too much output")
            }
        }
        if let error = error as? ProviderError {
            switch error {
            case let .missingKey(p): return tr("\(name(p)) 还没有 API key：在设置里添上", "No API key for the \(name(p)): add one in the settings")
            case let .missingModel(p): return tr("\(name(p)) 还没有设置模型", "No model set for the \(name(p))")
            case let .invalidBaseURL(url): return tr("Base URL 无效：\(url)", "Invalid base URL: \(url)")
            case let .insecureBaseURL(url):
                return tr("不通过 http:// 发到互联网（只允许本机或局域网）：\(url)",
                          "Not sent over http:// to the internet (only to this Mac or the local network): \(url)")
            case let .keyForAnotherHost(p, saved):
                return tr("\(name(p)) 的 API key 是为 \(saved) 保存的，不会发给现在的 Base URL：请为它重新保存 key",
                          "The \(name(p)) API key was saved for \(saved), not this base URL: save the key again for it")
            case let .http(p, status, type, message): return "\(name(p)) \(type ?? "HTTP \(status)")" + tr("：", ": ") + message
            case let .stream(p, type, message): return "\(name(p)) \(type)" + tr("：", ": ") + message
            case .refused(.apple): return tr("Apple Intelligence 拒绝了这个请求", "Apple Intelligence declined this request")
            case let .refused(p): return tr("\(name(p)) 拒绝了这个请求", "The \(name(p)) declined this request")
            case let .invalidResponse(p, detail):
                return tr("\(name(p)) 的响应无法解析：\(detail)", "Couldn't read the \(name(p)) response: \(detail)")
            // With Apple Intelligence here, Settings → Assistant can switch to it (it runs on it then); without, it would fail the same way.
            case .signedOut:
                return AppleModel.system.availability == .available
                    ? tr("请先在设置里登录 AllInOneIME 云，或者在设置 → 助手里改用 Apple 智能",
                         "Sign in to AllInOneIME Cloud in the settings, or switch to Apple Intelligence in Settings → Assistant")
                    : tr("请先在设置里登录 AllInOneIME 云，或者填自己的 API key", "Sign in to AllInOneIME Cloud in the settings, or add your own API key")
            case .quotaExhausted:
                return AppleModel.system.availability == .available
                    ? tr("今天的免费次数用完了：可以在设置里订阅、填自己的 API key，或者在设置 → 助手里改用 Apple 智能",
                         "No requests left today: subscribe or add your own API key in the settings, or switch to Apple Intelligence in Settings → Assistant")
                    : tr("今天的免费次数用完了：可以在设置里订阅，或者填自己的 API key",
                         "No requests left today: subscribe, or add your own API key in the settings")
            }
        }
        if let error = error as? AppleModelError { return describe(error) }
        if chinese, let error = error as? PluginLibraryError { return chineseOnly(describeInChinese(error)) }
        guard !chinese else { return chineseOnly(AllInOneIMEInputController.describe(error)) }
        switch error {
        case let error as URLError:
            switch error.code {
            case .timedOut: return "The request timed out"
            case .notConnectedToInternet, .networkConnectionLost: return "No network connection"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "Can't reach the AI service"
            default: return error.localizedDescription
            }
        case let AWSConfigError.profileNotFound(profile):
            return "AWS profile '\(profile)' not found (~/.aws/credentials, ~/.aws/config)"
        case let AWSConfigError.unsupportedProfile(profile, kind):
            return "AWS profile '\(profile)' uses \(kind); only static access keys are supported"
        case let AWSConfigError.missingKeys(profile):
            return "AWS profile '\(profile)' has no aws_access_key_id / aws_secret_access_key"
        case let BedrockError.invalidRegion(region): return "Invalid region: \(region)"
        case let BedrockError.http(status, type, message): return "Bedrock \(type ?? "HTTP \(status)"): \(message)"
        case let BedrockError.stream(type, message): return "Bedrock \(type): \(message)"
        case let BedrockError.invalidResponse(detail): return "Couldn't read the Bedrock response: \(detail)"
        case let ConfigError.malformed(path, detail): return "The config file is malformed (\(path)): \(detail)"
        case let error as VoiceError:
            switch error {
            case .unsupportedSystem: return "Voice input needs macOS 26 or later"
            case .unsupportedLanguage: return "This Mac can't recognize speech in this language"
            case let .modelMissing(language): return "The \(name(language)) speech model isn't installed"
            case .noMicrophone: return "No microphone available"
            case .noAudioFormat: return "Speech recognition can't use this audio format"
            }
        default:
            return (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// A plugin library's error in Simplified Chinese (`describe`).
    private static func describeInChinese(_ error: PluginLibraryError) -> String {
        switch error {
        case let .unreachable(host): return "连不上 \(host)"
        case let .http(status, file): return "插件库返回 HTTP \(status)（\(file)）"
        case let .tooLarge(file): return "\(file) 太大"
        case .missingSignature: return "插件库的索引没有签名"
        case .badSignature: return "插件库的索引没有通过签名验证（可能正在更新，过几分钟再试）"
        case let .unsupportedSchema(schema): return "插件库需要更新版本的 AllInOneIME（索引格式 \(schema)）"
        case .malformedIndex: return "读不懂插件库的索引"
        case let .invalidName(name): return "插件名字不合规：\(name)"
        case let .invalidFile(file): return "插件里有不合规的文件：\(file)"
        case let .hashMismatch(file): return "\(file) 和签名的索引对不上；什么都没有改"
        case let .invalidManifest(detail): return "插件的 plugin.json 有问题：\(detail)"
        case let .incompatible(problem): return "这个插件不能用：\(problem)"
        case let .localPlugin(name): return "已经有一个叫 \(name) 的本地插件；先删除它才能装插件库里的"
        }
    }

    /// An error of Apple Intelligence on this Mac: what to do about it.
    static func describe(_ error: AppleModelError) -> String {
        guard chinese else { return error.errorDescription ?? "\(error)" }
        return chineseOnly(describeInChinese(error))
    }

    /// An error of Apple Intelligence in Simplified Chinese (`describe`).
    private static func describeInChinese(_ error: AppleModelError) -> String {
        switch error {
        case let .unavailable(reason):
            switch reason {
            case .available: return ""
            case .unsupportedSystem: return "本机的 Apple Intelligence 需要 macOS 26 或更新的系统"
            case .deviceNotEligible: return "这台 Mac 不能运行 Apple Intelligence：请在设置里换一个 AI 服务"
            case .appleIntelligenceNotEnabled: return "Apple Intelligence 没有打开：在 系统设置 → Apple 智能与 Siri 里打开"
            case .modelNotReady: return "Apple Intelligence 还没准备好（模型可能还在下载）：稍后再试"
            }
        case .contextExceeded: return "内容太长，本机的 Apple Intelligence 处理不了（它的上下文很小）：缩短一些，或换一个 AI 服务"
        case .unsupportedLanguage: return "本机的 Apple Intelligence 不支持这种语言：这种语言请换一个 AI 服务"
        case .busy: return "Apple Intelligence 正忙：稍后再试"
        case let .timedOut(seconds): return "Apple Intelligence \(Int(seconds)) 秒内没有回应"
        case let .failed(detail): return "Apple Intelligence：\(detail)"
        }
    }

    /// A web search error (`@search`): where to add the key, what the service said.
    static func describe(_ error: WebSearch.SearchError) -> String {
        switch error {
        case let .missingKey(variable):
            return tr("网页搜索还没有 API key：在设置 → 网页搜索里添上（或在 shell 里设置 \(variable)）",
                      "No API key for web search: add one in Settings → Web Search (or set \(variable) in your shell)")
        case .emptyQuery: return tr("在 @search 后面写上要搜的内容", "Type what to search for after @search")
        case .queryTooLong:
            return tr("要搜的内容太长：最多 \(WebSearch.maxQueryLength) 个字、\(WebSearch.maxQueryWords) 个词",
                      "The search is too long: \(WebSearch.maxQueryLength) characters and \(WebSearch.maxQueryWords) words at most")
        case let .rejectedKey(service):
            return tr("\(service) 不接受这个 API key：在设置 → 网页搜索里检查一下",
                      "\(service) didn't accept the API key: check it in Settings → Web Search")
        case let .rateLimited(service):
            return tr("\(service) 搜索太频繁，稍后再试", "Too many searches at once for \(service): try again in a moment")
        case let .quotaExceeded(service):
            return tr("\(service) 的额度用完了：在它的控制台里看看用量和上限",
                      "No \(service) credit left: see the usage and limits in its dashboard")
        case let .notInPlan(service): return tr("你的 \(service) 套餐不支持这种搜索", "Your \(service) plan doesn't include this search")
        case let .unreachable(service): return tr("无法连接 \(service)", "Can't reach \(service)")
        case let .http(service, status, detail): return "\(service) HTTP \(status)" + (detail.map { tr("：", ": ") + $0 } ?? "")
        case let .invalidResponse(service): return tr("\(service) 的响应无法解析", "Couldn't read the \(service) response")
        case let .tooLarge(service): return tr("\(service) 的响应太大", "The \(service) response is too large")
        case .noResults: return tr("网页搜索没有找到结果", "No web results for this search")
        }
    }
}

/// Interface text in the interface language (see `UIText`): `chinese` for Simplified Chinese, `english` for English,
/// else the translation of `english` in the app's `<language>.lproj` (compiled from Resources/Localizable.xcstrings;
/// through `InterfaceText.lookup`, as the core's texts), or `english` without one. The English text, as
/// `UIString.format` ("%@ items"), is the catalog's key.
///
/// `key`: where the same English text means something else elsewhere (`make strings` reports those), a key of its
/// own: a short dotted name for where or how it is used ("remove.delete"), whose English in the catalog is `english`.
func tr(_ chinese: UIString, _ english: UIString, key: String? = nil) -> String {
    InterfaceText.text(chinese, english, key: key, language: UIText.language)
}

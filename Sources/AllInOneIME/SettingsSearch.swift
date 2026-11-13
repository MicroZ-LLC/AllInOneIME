import AllInOneIMECore
import SwiftUI

/// A row of the settings window: what the sidebar's search finds, by its title, what it says and the words it goes by,
/// and what the window is opened to point at (`SettingsWindow.show(page:spot:)`). The row picked is outlined on its page
/// until it is used or another page is shown. A setting inside an input's chip (fuzzy pinyin in Chinese's) points at the
/// input languages' row and opens that chip.
enum SettingsSpot: String, CaseIterable {
    // Input
    case inputLanguages, pinyinScheme, chineseCharacters, fuzzyPinyin, personalDictionaries, removedCandidates, englishWords, codingLanguage
    case candidateLayout
    // General
    case outputLanguages, rewriteStyles, improveTranslates, jargonList
    case autocomplete, suggestions, suggestionsInsert, appInserts, clipboardHistory
    case magicKey, actionKey, menuBarIcon, interfaceLanguage, iCloudSync
    // AI
    case provider, model, apiKey, awsProfile, baseURL, testConnection
    // Privacy
    case hideSensitive, wordsToHide, appsWithoutAI, pageContext, rememberQuestions, learnEnglishWords, learned, installID
    // Commands
    case customCommands, agent, questionContinueIn, notes, webSearch, plugins, scriptExtensions, extensionSources
    // Advanced
    case typeOut, useSelection, previousAppSettings, configFile, rimeFolder
    // About
    case updates, troubleshoot, reportIssue

    /// The page it's on.
    var page: SettingsPage {
        switch self {
        case .inputLanguages, .pinyinScheme, .chineseCharacters, .fuzzyPinyin, .personalDictionaries, .removedCandidates, .englishWords,
             .codingLanguage, .candidateLayout: return .input
        case .outputLanguages, .rewriteStyles,
             .improveTranslates, .jargonList, .autocomplete, .suggestions, .suggestionsInsert, .appInserts, .clipboardHistory, .magicKey, .actionKey,
             .menuBarIcon, .interfaceLanguage, .iCloudSync:
            return .general
        case .provider, .model, .apiKey, .awsProfile, .baseURL, .testConnection: return .ai
        case .hideSensitive, .wordsToHide, .appsWithoutAI, .pageContext, .rememberQuestions, .learnEnglishWords, .learned, .installID:
            return .privacy
        case .customCommands, .agent, .questionContinueIn, .notes, .webSearch, .plugins, .scriptExtensions, .extensionSources:
            return .commands
        case .typeOut, .useSelection, .previousAppSettings, .configFile, .rimeFolder: return .advanced
        case .updates, .troubleshoot, .reportIssue: return .about
        }
    }

    /// The row outlined for it: its own, or the input languages' for what is in a chip.
    var row: SettingsSpot {
        chip == nil ? self : .inputLanguages
    }

    /// The input whose chip holds it.
    var chip: Input? {
        switch self {
        case .pinyinScheme, .chineseCharacters, .fuzzyPinyin, .personalDictionaries, .removedCandidates: return .language(.chinese)
        case .englishWords: return .language(.english)
        case .codingLanguage: return .code
        default: return nil
        }
    }

    /// Its name, as its row says it.
    var title: String {
        switch self {
        case .inputLanguages: return tr("输入语言", "Input languages")
        case .pinyinScheme: return UIText.pinyinSchemeLabel
        case .chineseCharacters: return UIText.chineseCharactersLabel
        case .fuzzyPinyin: return tr("模糊音", "Fuzzy pinyin")
        case .personalDictionaries: return tr("个人词库", "Personal Dictionaries")
        case .removedCandidates: return tr("删掉的候选词", "Removed candidates")
        case .englishWords: return tr("你的英文词", "Your English words")
        case .codingLanguage: return tr("代码", "Code")
        case .outputLanguages: return tr("翻译成", "Translate to")
        case .rewriteStyles: return tr("改写风格", "Rewrite styles")
        case .improveTranslates: return UIText.triggered(tr("@improve 同时翻译", "@improve also translates"))
        case .jargonList: return tr("黑话库", "Jargon list")
        case .autocomplete: return tr("续写（Beta）", "Autocomplete (Beta)")
        case .suggestions: return tr("建议", "Suggestions")
        case .suggestionsInsert: return tr("插入", "Insert")
        case .appInserts: return tr("在这些 App 里", "In these apps")
        case .clipboardHistory: return tr("剪贴板历史", "Clipboard history")
        case .magicKey: return tr("魔法键", "Magic key")
        case .actionKey: return tr("执行键", "Action key")
        case .menuBarIcon: return tr("在菜单栏显示图标", "Show in Menu Bar")
        case .interfaceLanguage: return tr("界面语言", "Interface language")
        case .iCloudSync: return tr("通过 iCloud 同步", "Sync through iCloud")
        case .previousAppSettings: return tr("以前的按 App 设置", "Previous per-app settings")
        case .provider: return tr("选择 AI", "Choose the AI")
        case .model: return tr("模型", "Model")
        case .apiKey: return "API key"
        case .awsProfile: return "AWS profile"
        case .baseURL: return tr("Base URL", "Base URL")
        case .testConnection: return tr("测试连接", "Test Connection")
        case .hideSensitive: return tr("发送前隐藏敏感信息", "Hide sensitive information before sending")
        case .wordsToHide: return tr("要隐藏的词", "Words to hide")
        case .appsWithoutAI: return tr("不用 AI 的 App", "Apps without AI")
        case .pageContext: return UIText.triggered(tr("@agent 和 @reply 带上 Chrome 里的网页", "@agent and @reply take the Chrome page along"))
        case .rememberQuestions: return tr("记住最近的问题", "Remember recent questions")
        case .learnEnglishWords: return tr("学习英文词", "Learn English words")
        case .learned: return tr("学到的内容", "Learned")
        case .installID: return tr("每日检查更新时附带匿名安装 ID", "Send an anonymous install ID with the daily update check")
        case .customCommands: return tr("你的命令", "Your Commands")
        case .agent: return UIText.triggered(tr("@agent 交给", "@agent hands it to"))
        case .questionContinueIn: return tr("对话接着在哪里聊", "Continue a conversation in")
        case .notes: return UIText.triggered(tr("笔记（@note）", "Notes (@note)"))
        case .webSearch: return UIText.triggered(tr("网页搜索（@search）", "Web Search (@search)"))
        case .plugins: return tr("插件", "Plugins")
        case .scriptExtensions: return tr("脚本扩展", "Script Extensions")
        case .extensionSources: return tr("扩展来源", "Extension Sources")
        case .typeOut: return tr("逐字上屏", "Type results out")
        case .candidateLayout: return tr("候选排列", "Candidate layout")
        case .useSelection: return tr("使用选中的文字", "Use the selected text")
        case .configFile: return tr("配置文件", "Config file")
        case .rimeFolder: return tr("Rime 用户目录", "Rime user folder")
        case .updates: return tr("软件更新", "Software Update")
        case .troubleshoot: return tr("排查问题", "Troubleshoot")
        case .reportIssue: return tr("报告问题…", "Report an Issue…")
        }
    }

    /// What its row says, where that doesn't depend on the settings: one sentence, also searched.
    var note: String? {
        switch self {
        case .pinyinScheme: return UIText.pinyinSchemeHelp
        case .chineseCharacters: return UIText.chineseCharactersHelp
        case .fuzzyPinyin: return tr("分不清的音两种拼法都能打出来，比如 zh 和 z：打 zi 也有「之」", "Sounds you don't tell apart typed either way, e.g. zh and z: zi also offers 之")
        case .personalDictionaries: return tr("UTF-8 Rime .dict.yaml，最多 32 MiB", "UTF-8 Rime .dict.yaml, up to 32 MiB")
        case .autocomplete: return tr("停一下，光标后出现灰字，按 Tab 接受", "Pause, and the rest of the sentence shows in gray after the caret; Tab takes it")
        case .suggestions:
            return tr("插件的补全和代码输入的关键字、代码片段：光标下面列出几行，按 Tab 插入。",
                      "Plugins' completions and Code's keywords and snippets, a few rows under the caret; Tab inserts.")
        case .suggestionsInsert: return SuggestionsInsert.help
        case .appInserts:
            return tr("这里的 App 用它自己的选择；选「关闭」，那个 App 里就不显示建议。", "An app here inserts its own choice; with Off it shows no suggestions.")
        case .clipboardHistory: return UIText.clipboardHistoryHelp()
        case .magicKey: return tr("打在句首打开命令列表。", "Typed at the start of a sentence, it opens the commands.")
        case .menuBarIcon: return tr("笔记、提醒和后台的 Claude 任务，点一下就下拉出来", "Your notes, reminders and Claude tasks, a click away")
        case .iCloudSync: return Self.iCloudNote
        case .previousAppSettings: return Self.previousNote
        case .provider: return tr("选一家，所有 AI 功能都用它", "Pick one, and every AI feature uses it")
        case .hideSensitive:
            return tr("邮箱、电话、卡号、密钥这些先换成 [EMAIL_1] 这样的占位符再发给 AI，结果里再换回真实内容。",
                      "Emails, numbers and keys are replaced with placeholders such as [EMAIL_1] before the AI sees the text, and put back in the results.")
        case .wordsToHide: return tr("也要隐藏的名字、代号等词，不分大小写。", "Names, codenames and other words to hide as well, in any case.")
        case .appsWithoutAI:
            return UIText.triggered(tr("@improve、@translate、@question、@agent 等不会发给 AI，打字和别的命令照常。",
                                       "@improve, @translate, @question, @agent and the like send nothing to the AI; typing and the other commands work."))
        case .pageContext: return Self.pageContextNote
        case .learnEnglishWords: return Self.learnEnglishWordsNote
        case .learned:
            return tr("从你的用法里学到的，比如 App 用哪种输入开始、你选过的建议行，只存在这台 Mac 上。",
                      "What was learned from how you type, such as the input an app starts in or the rows you picked, kept on this Mac only.")
        case .installID:
            return tr("一个本机随机生成的编号，只用于统计安装数，不含其他信息。",
                      "A random number made on this Mac, so we can count installs. Nothing else is sent.")
        case .typeOut: return Self.typeOutNote
        case .useSelection: return Self.useSelectionNote
        case .rimeFolder: return tr("学到的词和你自己的 Rime 设置", "Learned words and your own Rime settings")
        case .troubleshoot:
            return tr("检查这台 Mac 上的设置，也可以描述遇到的问题让 AI 帮你看。", "Checks the setup on this Mac, and can ask the AI about a problem you describe.")
        default: return nil
        }
    }

    /// Words its settings go by besides its title and note, in both languages.
    private var keywords: String {
        switch self {
        case .inputLanguages: return "pinyin english chinese french korean hindi shift default chips 拼音 中文 英文 法语 韩语 印地语 默认 语言包 language pack"
        // The schemes by their names in either language (`PinyinScheme.name`), as their menu lists them; Zhuyin by its
        // other names too (Bopomofo, 注音符號, 大千, ㄅㄆㄇ).
        case .pinyinScheme:
            return "shuangpin double pinyin full pinyin typing scheme 双拼 全拼 雙拼 输入方式 方案 拼音 中文 "
                + "zhuyin bopomofo daqian taiwan 注音 注音符號 注音符号 大千 標準 标准 ㄅㄆㄇ 台灣 台湾 "
                + PinyinScheme.others.map { $0.name(in: "en") + " " + $0.name(in: "zh-Hans") }.joined(separator: " ")
        case .chineseCharacters: return "simplified traditional taiwan hong kong characters chinese pinyin 简体 繁体 繁體 台湾 台灣 香港 字形 中文 拼音"
        case .fuzzyPinyin: return "zh ch sh z c s 拼音 pinyin"
        case .personalDictionaries: return "dictionary import dict yaml vocabulary 词库 导入 个人"
        case .removedCandidates: return "removed candidates delete remove right-click ⌃⌦ control delete restore 删掉 删除 候选词 右键 恢复 不再出现"
        // Not "learn": learning them is Privacy's switch (`learnEnglishWords`), which the search would otherwise rank
        // after this chip in a Chinese interface.
        case .englishWords: return "english words dictionary bedrock 英文词 词典"
        case .codingLanguage: return "code coding languages programming packs python java go typescript javascript c++ keywords snippets 代码 编程语言 语言包 关键字 代码片段"
        case .outputLanguages: return "@translate translate languages 翻译 语言"
        case .rewriteStyles: return "@improve rewrite styles polish concise formal casual tactful jargon 改写 润色 简洁 正式 口语 委婉 黑话 风格"
        case .improveTranslates: return "improve translate 润色 翻译"
        case .jargonList: return "jargon terms team 黑话 术语 团队"
        case .autocomplete: return "autocomplete continue ghost gray tab 续写 灰字"
        case .suggestions: return "suggestions completions plugins # issues github code snippets 建议 补全 插件"
        case .suggestionsInsert: return "insert id title link 插入 标题 链接"
        case .appInserts: return "apps per-app insert off 每个 应用 插入 关闭"
        case .clipboardHistory: return "clipboard history paste copy copied ctrl v ⌃v clear keep privacy 剪贴板 历史 粘贴 复制 清除 保留 隐私"
        case .magicKey: return "trigger @ ~ symbol commands 触发 符号 命令"
        case .actionKey: return "action key return enter run 执行键 回车"
        case .menuBarIcon: return "menu bar panel 菜单栏 面板"
        case .interfaceLanguage: return "interface language 界面语言 english chinese"
        case .iCloudSync: return "icloud drive sync macs learned words hidden words recent questions sync now remove 同步 云盘 多台 学到的词 隐藏的词 最近的问题 立即同步 移除"
        case .previousAppSettings: return "per-app app profiles starts in translate as you type autocomplete type out rewrite styles 按 App 开始 边打边译 续写 逐字上屏 改写 移除"
        case .provider: return "ai provider change claude code codex gemini cli kiro cli subscription session sign in login @question api key anthropic claude api openai compatible deepseek ollama gemini api amazon bedrock aws allinoneime cloud apple intelligence on-device local 更换 订阅 会话 登录 提问 服务 本机 苹果 云"
        case .model: return "model id 模型"
        case .apiKey: return "api key keychain 密钥 钥匙串"
        case .awsProfile: return "aws profile region sso role assume credential_process sts mfa 区域 角色 登录"
        case .baseURL: return "base url more compatible services 更多 地址 常用服务"
        case .testConnection: return "test connection 测试连接"
        case .hideSensitive: return "privacy hide sensitive information redact placeholder email phone card key token ip address 隐私 隐藏 敏感信息 脱敏 占位符 邮箱 电话 卡号 地址"
        case .wordsToHide: return "words codename names hide 词 代号 名字"
        case .appsWithoutAI: return "no ai apps off 不用 AI 关掉"
        case .pageContext: return "@agent @reply chrome page context accessibility 网页 辅助功能"
        case .rememberQuestions: return "@question recent questions history forget 最近的问题 提问 记录 历史 忘掉"
        case .learnEnglishWords: return "learn english words 学习 英文词"
        case .installID: return "install id anonymous count installs statistics update check user agent 安装 编号 匿名 统计 安装数 检查更新"
        case .learned: return "learned forget starts in starting input autocomplete stopped typos picked rows suggestions temperature models 学到的内容 忘掉 开始 输入 续写 停下 打错 选过的行 建议 模型"
        case .customCommands: return "custom commands prompt program terminal link snippet 自定义 命令 程序 终端 网页"
        case .agent: return "@agent coding agent claude code gemini cli kiro custom command terminal installed background notify tasks @tasks claude tasks 编程 交给 终端 已安装 后台 通知 任务"
        case .questionContinueIn: return "@question continue conversation claude code chatgpt gemini copy 接着聊 对话 追问 复制"
        case .notes: return "@note note notes save to notion obsidian folder markdown vault token integration 笔记 备忘录 存到 文件夹 令牌 集成"
        case .webSearch: return "@search search web brave api key 搜索 网页"
        case .plugins: return "plugins library stock xe completions preferences password 插件 插件库 补全 偏好 密码"
        case .scriptExtensions: return "raycast script commands scripts extensions bundles preferences folder spotlight 脚本 扩展 扩展包 偏好 文件夹 聚焦"
        case .extensionSources: return "extension sources git repository link clone update pin ssh trust its updates suggestions 扩展来源 仓库 链接 克隆 更新 固定 信任 建议"
        case .typeOut: return "type out typing speed typos mistakes 打字速度 打错"
        case .candidateLayout: return "candidate layout horizontal vertical 候选 排列 横排 竖排"
        case .useSelection: return "selection selected text 选中 文字"
        case .configFile: return "config file json 配置文件"
        case .rimeFolder: return "rime folder 目录"
        case .updates: return "updates version check automatically notify notification 更新 版本 自动检查 通知"
        case .troubleshoot: return "doctor check problems fix diagnose troubleshoot 检查 问题 修复 诊断"
        case .reportIssue: return "report issue bug feedback github 报告 问题 反馈"
        }
    }

    /// Whether every word of `query` is in its title, what it says or its words; a command named with the command trigger
    /// (`trigger`: "~agent") as its words name it ("@agent").
    func matches(_ query: String, trigger: String = "@") -> Bool {
        matches(Self.words(query, trigger: trigger), trigger: trigger)
    }

    /// `matches` with the query's words (`words`) split already: the search splits them once for every row.
    private func matches(_ words: [Substring], trigger: String) -> Bool {
        guard !words.isEmpty else { return false }
        let text = [title, note ?? "", keywords, page.title].joined(separator: " ").lowercased()
            .replacingOccurrences(of: trigger, with: "@")
        return words.allSatisfy { text.contains($0) }
    }

    private static func words(_ query: String, trigger: String) -> [Substring] {
        query.lowercased().replacingOccurrences(of: trigger, with: "@").split(whereSeparator: \.isWhitespace)
    }

    /// The rows `query` finds, the rows `config` doesn't show left out: those whose title has its words first (the shorter
    /// title first), then those whose title and words have them, then the others, each in the pages' order.
    static func search(_ query: String, trigger: String, config: Config) -> [SettingsSpot] {
        let words = Self.words(query, trigger: trigger)
        func has(_ text: String) -> Bool {
            let text = text.lowercased().replacingOccurrences(of: trigger, with: "@")
            return words.allSatisfy { text.contains($0) }
        }
        func rank(_ spot: SettingsSpot) -> (Int, Int) {
            if has(spot.title) { return (0, spot.title.count) }
            return has(spot.title + " " + spot.keywords) ? (1, 0) : (2, 0)
        }
        // Each row found ranked once, not again at each comparison of the sort.
        let found = allCases.enumerated().filter { $0.element.isShown(config) && $0.element.matches(words, trigger: trigger) }
            .map { (spot: $0.element, offset: $0.offset, rank: rank($0.element)) }
        return found.sorted { a, b in a.rank != b.rank ? a.rank < b.rank : a.offset < b.offset }.map(\.spot)
    }

    /// Whether its row is there with `config`: a provider's own rows only with that provider chosen as the AI, the jargon
    /// list with its style or file, the English words under an input that shows them, the previous per-app settings only
    /// while an app has one.
    func isShown(_ config: Config) -> Bool {
        switch self {
        case .apiKey, .baseURL: return config.ai.provider?.needsKey == true
        case .awsProfile: return config.ai == .provider(.bedrock)
        case .model: return config.ai.provider.map { $0 != .hosted && $0 != .apple } ?? false
        case .testConnection: return config.ai.provider != nil
        case .jargonList: return SettingsView.showsJargon(config)
        case .previousAppSettings: return config.appProfiles.values.contains { !$0.previousFields.isEmpty }
        case .pinyinScheme, .chineseCharacters, .fuzzyPinyin, .personalDictionaries, .removedCandidates:
            return config.inputLanguages.contains(.chinese)
        case .englishWords: return config.inputLanguages.contains { SettingsView.showsEnglishWords(under: $0, config) }
        case .webSearch: return Command.webSearchOffered
        default: return true
        }
    }

    // MARK: Text more than one place says

    static var iCloudNote: String {
        tr("设置、自定义命令和学到的词在你所有的 Mac 上都一样，只经过你自己的 iCloud。",
           "Your settings, custom commands and learned words, the same on all your Macs, through your own iCloud only.")
    }

    static var previousNote: String {
        tr("在以前的版本里按 App 设的，仍然生效；「移除」清掉那个 App 的这些设置。",
           "Set for an app in an earlier version and still used; Remove clears them for that app.")
    }

    static var pageContextNote: String {
        UIText.triggered(tr("在 Chrome 里，@agent 和 @reply（没有选中消息时）也会带上网址、你所在的输入框和屏幕上看得到的内容，不读密码框；需要「辅助功能」权限。",
                            "In Chrome, @agent and @reply (with no message selected) also send the address, your field and what's visible on screen, never a password field; needs Accessibility."))
    }

    static var learnEnglishWordsNote: String {
        tr("打拼音时原样上屏两次的字母，或英文模式下打了两次的词，以后会出现在拼音的候选里；密码框、终端和不用 AI 的 App 里不学。需要辅助功能权限，用来认出密码框。",
           "A word put in as typed twice while typing pinyin, or typed twice in English mode, comes up among pinyin's candidates; never in password fields, terminals or apps without AI. It needs Accessibility, which tells password fields apart.")
    }

    static var typeOutNote: String {
        tr("命令的结果像人打字一样一个字一个字打进去；按 Esc 停下，按别的键把剩下的一次打完。",
           "A command's result is typed in character by character, like a person typing; Esc stops it, any other key types the rest at once.")
    }

    static var useSelectionNote: String {
        tr("选中文字后打命令就处理选中的文字，选好的结果替换它；哪个 App 里不正常就关掉。",
           "Commands typed with text selected work on it, and the result you pick replaces it; turn it off if it misbehaves in an app.")
    }
}

extension View {
    /// A row the search and `SettingsWindow.show(page:spot:)` point at: the place the page scrolls to, outlined while
    /// `shown` is it.
    func settingsRow(_ spot: SettingsSpot, shown: SettingsSpot?) -> some View {
        id(spot).overlay {
            if shown?.row == spot {
                RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2.5).padding(-4)
                    .allowsHitTesting(false)
            }
        }
    }

    /// `settingsRow(spot, shown:)` that also stands in for `others`, rows not shown now (Words to hide with hiding off):
    /// pointed at one of them, this row is scrolled to and outlined in its place.
    func settingsRow(_ spot: SettingsSpot, standingIn others: [SettingsSpot], shown: SettingsSpot?) -> some View {
        settingsRow(shown.map(\.row).flatMap { others.contains($0) ? $0 : nil } ?? spot, shown: shown)
    }
}

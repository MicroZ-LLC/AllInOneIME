import Foundation

extension AIConfig {
    /// What the preview says, in the interface language: the labels Settings uses, values as Settings shows them, and the
    /// reasons a part is refused.
    public struct Text: Sendable {
        public var chinese: Bool

        public init(chinese: Bool) { self.chinese = chinese }

        func tr(_ zh: String, _ en: String) -> String { chinese ? zh : en }

        // MARK: Labels

        public func label(_ setting: Setting) -> String {
            switch setting {
            case .outputLanguages: return tr("翻译语言", "Translation languages")
            case .inputLanguages: return tr("输入语言", "Input languages")
            case .defaultInput: return tr("默认输入语言", "Default input language")
            case .rewriteStyles: return tr("改写风格", "Rewrite styles")
            case .candidateLayout: return tr("候选排列", "Candidate layout")
            case .typeOut: return tr("逐字上屏", "Type results out")
            case .typeOutRate: return tr("打字速度", "Typing speed")
            case .typeOutVaries: return tr("忽快忽慢（像真人打字）", "Speed up and slow down (like a person)")
            case .typeOutMistakes: return tr("偶尔打错再改", "Make occasional typos and fix them")
            case .useSelection: return tr("使用选中的文字", "Use the selected text")
            case .rememberQuestions: return tr("记住最近的问题", "Remember recent questions")
            case .redactionEnabled: return tr("发送前隐藏敏感信息", "Hide sensitive information before sending")
            case .redactionEmails: return tr("隐藏 · 邮箱地址", "Hide · Email addresses")
            case .redactionPhones: return tr("隐藏 · 电话号码", "Hide · Phone numbers")
            case .redactionCards: return tr("隐藏 · 银行卡号", "Hide · Payment card numbers")
            case .redactionKeys: return tr("隐藏 · API 密钥和令牌", "Hide · API keys and tokens")
            case .redactionIPs: return tr("隐藏 · IP 地址", "Hide · IP addresses")
            case .redactionWordsAdd: return tr("也隐藏这些词", "Also hide these words")
            case .checkForUpdates: return tr("自动检查更新", "Check for updates automatically")
            case .provider: return tr("AI 服务", "AI provider")
            case .awsProfile: return "AWS Profile"
            case .region: return tr("区域", "Region")
            case .modelId: return tr("模型（Amazon Bedrock）", "Model (Amazon Bedrock)")
            case .anthropicModel: return tr("模型（Claude API）", "Model (Claude API)")
            case .geminiModel: return tr("模型（Gemini API）", "Model (Gemini API)")
            case .openaiModel: return tr("模型（兼容 OpenAI 的服务）", "Model (OpenAI-compatible API)")
            case .openaiBaseURL: return "Base URL"
            }
        }

        /// "按 App · 微信 · 开始的输入语言" / "Apps · WeChat · Starts in".
        public func appLabel(_ app: String, _ field: AppField) -> String {
            let name: String
            switch field {
            case .inputLanguage: name = tr("开始的输入语言", "Starts in")
            case .rewriteStyles: name = tr("改写风格", "Rewrite styles")
            case .typeOut: name = tr("逐字上屏", "Type results out")
            case .noAI: name = tr("这个 App 里不用 AI", "No AI in this app")
            }
            return tr("按 App · ", "Apps · ") + app + " · " + name
        }

        public func keyLabel(_ provider: Provider?) -> String {
            guard let provider else { return "API key" }
            return "API key" + tr("（\(self.provider(provider))）", " (\(self.provider(provider)))")
        }

        // MARK: Values

        var separator: String { tr("、", ", ") }

        public func onOff(_ on: Bool) -> String { on ? tr("开", "on") : tr("关", "off") }

        public func outputs(_ languages: [OutputLanguage]) -> String {
            languages.map { $0.name(chinese: chinese) }.joined(separator: separator)
        }

        public func input(_ language: Language) -> String { chinese ? language.displayName : language.englishName }

        public func inputs(_ languages: [Language]) -> String { languages.map(input).joined(separator: separator) }

        public func styles(_ names: [String]) -> String {
            let styles = RewriteStyle.resolve(names)
            return styles.isEmpty ? tr("无", "none") : styles.map { chinese ? $0.name : Self.englishStyle($0) }.joined(separator: separator)
        }

        public func layout(_ layout: CandidateArrangement) -> String {
            layout == .vertical ? tr("竖排", "Vertical") : tr("横排", "Horizontal")
        }

        /// As Settings' label beside the slider: "每秒 16 个字" / "16 a second", "6 秒一个字" / "6 s each".
        public func rate(_ rate: Double) -> String {
            if rate >= 1 { return tr("每秒 \(Int(rate.rounded())) 个字", "\(Int(rate.rounded())) a second") }
            let seconds = 1 / rate
            let shown = seconds < 2 ? String(format: "%.1f", seconds) : String(Int(seconds.rounded()))
            return tr("\(shown) 秒一个字", "\(shown) s each")
        }

        public func wordCount(_ count: Int) -> String { tr("\(count) 个词", count == 1 ? "1 word" : "\(count) words") }

        public func added(_ words: [String]) -> String { "+ " + words.joined(separator: separator) }

        public func provider(_ provider: Provider) -> String {
            switch provider {
            case .openai: return tr("兼容 OpenAI 的服务", "OpenAI-compatible API")
            case .hosted: return tr("AllInOneIME 云", "AllInOneIME Cloud")
            case .apple: return tr("Apple Intelligence（本机）", "Apple Intelligence (on this Mac)")
            default: return provider.displayName
            }
        }

        var everywhere: String { tr("跟全局一样", "Same as everywhere") }
        var byDefault: String { tr("默认", "default") }
        var profileRegion: String { tr("profile 的区域", "the profile's region") }

        func appInput(_ language: Language?) -> String { language.map(input) ?? everywhere }
        func appStyles(_ names: [String]?) -> String { names.map(styles) ?? everywhere }
        func appFlag(_ on: Bool?) -> String { on.map(onOff) ?? everywhere }

        /// A style's name in English ("Concise"), as Settings shows it.
        static func englishStyle(_ style: RewriteStyle) -> String {
            switch style.tag {
            case "POLISH": return "Polish"
            case "CONCISE": return "Concise"
            case "FORMAL": return "Formal"
            case "CASUAL": return "Casual"
            case "TACTFUL": return "Tactful"
            case "JARGON": return "Jargon"
            default: return style.name
            }
        }

        // MARK: Reasons

        var notHere: String { tr("不能在这里改，请打开设置", "can't be set here: open Settings") }
        var secretRefused: String { tr("请在设置里填（不会发给 AI）", "enter it in Settings (never sent to the AI)") }
        func enterKey(_ provider: Provider) -> String {
            provider == .hosted ? tr("在设置里登录", "sign in in Settings") : tr("在设置里填（不会发给 AI）", "enter it in Settings (never sent to the AI)")
        }
        var notValid: String { tr("不是有效的值", "not a valid value") }
        func unknownLanguage(_ code: String) -> String { tr("不认识的语言「\(code)」", "unknown language “\(code)”") }
        var atLeastOne: String { tr("至少要有一种", "at least one is needed") }
        func tooMany(_ limit: Int) -> String { tr("最多 \(limit) 种", "at most \(limit)") }
        func needsPack(_ language: Language) -> String {
            tr("需要\(language.displayName)语言包（在设置 → 输入里下载）",
               "needs the \(language.englishName) language pack (download it in Settings → Input)")
        }
        func notAnInputLanguage(_ language: Language) -> String {
            tr("\(language.displayName)还不是输入语言", "\(language.englishName) isn't one of your input languages")
        }
        func unknownStyle(_ name: String) -> String { tr("没有「\(name)」这个风格", "no style called “\(name)”") }
        var outOfRange: String { tr("超出范围", "out of range") }
        var notOffered: String { tr("这台 Mac 上没有这个服务", "not offered on this Mac") }
        var unknownProfile: String { tr("~/.aws 里没有这个 profile", "no such profile in ~/.aws") }
        var unknownRegion: String { tr("不是有效的 AWS 区域", "not a valid AWS region") }
        var unknownModel: String { tr("不在已知的模型里，请在设置里填", "not a model the app knows: enter it in Settings") }
        var httpsOnly: String { tr("只能是 https:// 地址", "https:// addresses only") }
        var unknownApp: String { tr("找不到这个 App", "no such app found") }
        func ambiguousApp(_ names: [String]) -> String {
            tr("有好几个：", "several match: ") + names.prefix(3).joined(separator: separator)
        }

        // MARK: Lines

        /// The one line the panel shows when nothing can be applied.
        public func failure(_ failure: Failure) -> String {
            switch failure {
            case .notUnderstood: return tr("没能把这句话变成设置", "Couldn't turn that into a setting")
            case .notAllowed: return tr("这些不能在这里改：请打开设置", "Those can't be set here: open Settings")
            case .alreadySet: return tr("已经是这样设置的了", "Already set that way")
            }
        }

        /// A key typed into the sentence, with nothing else in it: nothing is sent, and the key field opens.
        public var droppedKey: String {
            tr("别在这里打密钥：没有发出去，我打开了填密钥的地方", "Don't type keys here; I opened the key field instead.")
        }

        /// The warning over the preview when a key typed into the sentence was dropped before the request.
        public var droppedKeyPreview: String {
            tr("别在这里打密钥：它没有发出去，⏎ 会打开填密钥的地方", "Don't type keys here: it wasn't sent, and ⏎ opens the key field.")
        }

        /// The confirmation once applied: "Changed 2 settings".
        public func applied(_ count: Int) -> String {
            tr("已修改 \(count) 项设置", count == 1 ? "Changed 1 setting" : "Changed \(count) settings")
        }

        public var undone: String { tr("已撤销刚才的设置修改", "Undone: the settings are as they were") }
        public var nothingToUndo: String { tr("10 分钟内没有可以撤销的设置修改", "Nothing to undo from the last 10 minutes") }
    }
}

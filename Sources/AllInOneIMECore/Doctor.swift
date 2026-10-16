import Foundation

/// `@doctor`: the setup checked on this Mac, a row per finding (✗ problems first, then ⚠, then ✓), each with a short
/// fix; the safe, local fixes go through `@config`'s preview, apply and undo (`fixPreview`). The checks read only what the
/// input method already knows (`Facts`, gathered by the app's probes; the tests give their own) and never send anything.
/// `@doctor <question>` then has the model explain the likely cause from them (`DoctorService`).
public enum Doctor {
    public enum Status: Int, Comparable, Sendable {
        case problem, warning, ok

        public static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }

        public var mark: String {
            switch self {
            case .problem: return "✗"
            case .warning: return "⚠"
            case .ok: return "✓"
            }
        }
    }

    /// What a check is about; also the on-device model's tools (`DoctorService`), one per area.
    public enum Area: String, CaseIterable, Sendable {
        case inputMethod, provider, connection, appleIntelligence, permissions, secureInput, languagePacks, config, extensions,
             updates, recentErrors
    }

    /// A System Settings privacy pane.
    public enum PrivacyPane: String, Equatable, Sendable {
        case accessibility = "Privacy_Accessibility", microphone = "Privacy_Microphone", automation = "Privacy_Automation"

        public var url: URL { URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")! }
    }

    /// What fixes a finding: only local, safe things; none deletes the user's data or touches a key.
    public enum Fix: Equatable, Sendable {
        /// Registers, enables and lists the input method again (as the installer does).
        case enableInputMethod
        case openPrivacy(PrivacyPane)
        /// Downloads a language pack (confirmed in the preview first).
        case downloadPack(Language)
        /// Settings changed through `@config`'s checks and apply/undo.
        case repairConfig([AIConfig.Change])
        /// The config file written again as Settings writes it (repeats gone); its values stay as they read.
        case resaveConfig
        /// Settings → AI Provider at the key field.
        case openKeyField(Provider)
        case openAppleIntelligenceSettings
        /// "Check for Updates" as in the input menu.
        case checkForUpdates

        /// One that ⏎ applies with the others ("fix all safe ones"): it changes only this app's settings, or checks.
        /// Opening windows, panes and downloads are picked one by one.
        public var isSafe: Bool {
            switch self {
            case .repairConfig, .resaveConfig, .enableInputMethod, .checkForUpdates: return true
            case .openPrivacy, .downloadPack, .openKeyField, .openAppleIntelligenceSettings: return false
            }
        }
    }

    public struct Finding: Equatable, Sendable {
        public var area: Area
        public var status: Status
        /// "AI provider: no API key for the Claude API".
        public var title: String
        /// What to do, or more about it (shown after the title).
        public var detail: String?
        public var fix: Fix?

        public init(area: Area, status: Status, title: String, detail: String? = nil, fix: Fix? = nil) {
            self.area = area
            self.status = status
            self.title = title
            self.detail = detail
            self.fix = fix
        }

        public func text(chinese: Bool) -> String {
            status.mark + " " + title + (detail.map { " — " + $0 } ?? "")
        }
    }

    // MARK: - What the probes found

    /// What the app's probes found: plain values, nothing secret (whether a key exists, never the key).
    public struct Facts: Equatable, Sendable {
        public struct InputMethod: Equatable, Sendable {
            public var registered = true, enabled = true, listed = true, selectable = true, selected = false
            public var version = AppVersion.string
            public init() {}
        }

        public enum Permission: Equatable, Sendable { case granted, denied, notDetermined, unknown }

        public enum Pack: Equatable, Sendable { case installed, missing, damaged, downloading }

        public enum Connection: Equatable, Sendable {
            case notRun
            case running
            case ok(String)
            case failed(String)
        }

        public struct Updates: Equatable, Sendable {
            public var version = AppVersion.string
            /// A newer version this Mac can install.
            public var available: String?
            public var checkEnabled = true
            public var lastError: String?
            public init() {}
        }

        public var inputMethod = InputMethod()
        /// The config as read, or nil when it can't be (`configError`).
        public var config: Config?
        public var configData: Data?
        public var configError: String?
        public var keySaved: [Provider: Bool] = [:]
        /// Bedrock: the profile's region when its credentials resolve, else why not.
        public var awsProfile: Result<String, ProbeError>?
        public var apple: AppleModelAvailability = .unsupportedSystem
        public var connection: Connection = .notRun
        public var accessibility: Permission = .unknown
        public var microphone: Permission = .unknown
        /// The apps the commands control (Notes, Reminders, Terminal, Messages) and whether that's allowed (unknown: not
        /// told without asking).
        public var automation: [String: Permission] = [:]
        /// Who holds secure input now (nil: off).
        public var secureInput: String?
        public var packs: [Language: Pack] = [:]
        /// Extension commands left out, as "name: why".
        public var skippedExtensions: [String] = []
        public var pluginErrors: [String] = []
        public var updates = Updates()
        /// The last few error lines of the app's own logs, summarised (`summarizeLogLines`).
        public var recentErrors: [String] = []

        public init() {}
    }

    /// A probe's failure, as text (a profile not found …): equatable and sendable.
    public struct ProbeError: Error, Equatable, Sendable {
        public var message: String
        public init(_ message: String) { self.message = message }
    }

    // MARK: - The findings

    /// Every finding for `facts`, problems first (then warnings, then what is fine), in the areas' order within each.
    public static func findings(_ facts: Facts, chinese: Bool) -> [Finding] {
        let t = Words(chinese: chinese)
        var out: [Finding] = []
        out += inputMethod(facts, t)
        out += provider(facts, t)
        out += configFindings(data: facts.configData, error: facts.configError, config: facts.config, chinese: chinese)
        out += permissions(facts, t)
        if let owner = facts.secureInput {
            out.append(Finding(area: .secureInput, status: .warning, title: t.tr("安全输入开着（\(owner)）", "Secure input is on (\(owner))"),
                               detail: t.tr("关掉之前不会把文字发给 AI；关掉密码框或那个 App 的安全输入", "nothing goes to the AI until it's off: leave the password field, or that app")))
        } else {
            out.append(Finding(area: .secureInput, status: .ok, title: t.tr("安全输入没开", "Secure input is off")))
        }
        out += packs(facts, t)
        out += extensions(facts, t)
        out += updates(facts, t)
        if facts.recentErrors.isEmpty {
            out.append(Finding(area: .recentErrors, status: .ok, title: t.tr("最近的日志里没有错误", "No recent errors in the logs")))
        } else {
            out.append(Finding(area: .recentErrors, status: .warning,
                               title: t.tr("最近的日志里有 \(facts.recentErrors.count) 个错误", "\(facts.recentErrors.count) recent errors in the logs"),
                               detail: facts.recentErrors.last))
        }
        let order = Area.allCases
        return out.enumerated().sorted { a, b in
            (a.element.status, order.firstIndex(of: a.element.area) ?? 0, a.offset)
                < (b.element.status, order.firstIndex(of: b.element.area) ?? 0, b.offset)
        }.map(\.element)
    }

    static func inputMethod(_ facts: Facts, _ t: Words) -> [Finding] {
        let im = facts.inputMethod
        func problem(_ zh: String, _ en: String, _ status: Status = .problem) -> [Finding] {
            [Finding(area: .inputMethod, status: status, title: t.tr(zh, en), detail: t.tr("可以重新启用", "it can be enabled again"),
                     fix: .enableInputMethod)]
        }
        if !im.registered { return problem("输入法没有注册", "The input method isn't registered") }
        if !im.enabled { return problem("输入法没有启用", "The input method isn't enabled") }
        if !im.listed { return problem("输入法不在你的输入法列表里（⌃空格切换不到它）", "The input method isn't in your input sources (Ctrl-Space doesn't reach it)", .warning) }
        if !im.selectable { return problem("输入法现在不能选", "The input method can't be selected now", .warning) }
        return [Finding(area: .inputMethod, status: .ok, title: t.tr("AllInOneIME \(im.version) 已安装并启用", "AllInOneIME \(im.version) is installed and enabled"),
                        detail: im.selected ? t.tr("正在使用", "in use now") : nil)]
    }

    static func provider(_ facts: Facts, _ t: Words) -> [Finding] {
        guard let config = facts.config else { return [] }
        var out: [Finding] = []
        let name = AIConfig.Text(chinese: t.chinese).provider(config.provider)
        let label = t.tr("AI 服务：", "AI provider: ") + name
        switch config.provider {
        case .apple:
            if facts.apple == .available {
                out.append(Finding(area: .provider, status: .ok, title: label, detail: t.tr("这台 Mac 上可以用", "ready on this Mac")))
            } else {
                let fixable = facts.apple == .appleIntelligenceNotEnabled || facts.apple == .modelNotReady
                out.append(Finding(area: .provider, status: .problem, title: label, detail: t.appleReason(facts.apple),
                                   fix: fixable ? .openAppleIntelligenceSettings : nil))
            }
        case .bedrock:
            switch facts.awsProfile {
            case let .success(region)?:
                out.append(Finding(area: .provider, status: .ok, title: label,
                                   detail: t.tr("profile \(config.awsProfile)，区域 \(config.region ?? region)，找到了密钥",
                                                "profile \(config.awsProfile), region \(config.region ?? region), credentials found")))
            case let .failure(error)?:
                out.append(Finding(area: .provider, status: .problem, title: label, detail: error.message, fix: .openKeyField(.bedrock)))
            case nil:
                out.append(Finding(area: .provider, status: .ok, title: label))
            }
        case .anthropic, .gemini, .openai, .hosted:
            if facts.keySaved[config.provider] == true {
                out.append(Finding(area: .provider, status: .ok, title: label,
                                   detail: config.provider == .hosted ? t.tr("已登录", "signed in") : t.tr("已保存 API key", "API key saved")))
            } else {
                out.append(Finding(area: .provider, status: .problem, title: label,
                                   detail: config.provider == .hosted ? t.tr("没有登录：在设置里登录", "not signed in: sign in in Settings")
                                       : t.tr("没有 API key：在设置里填（不会发给 AI）", "no API key: enter it in Settings (never sent to the AI)"),
                                   fix: .openKeyField(config.provider)))
            }
        }
        switch facts.connection {
        case .notRun: break
        case .running:
            out.append(Finding(area: .connection, status: .warning, title: t.tr("正在测试连接…", "Testing the connection…")))
        case let .ok(line):
            out.append(Finding(area: .connection, status: .ok, title: t.tr("连接正常", "The connection works"), detail: line))
        case let .failed(line):
            out.append(Finding(area: .connection, status: .problem, title: t.tr("连接失败", "The connection failed"), detail: line))
        }
        // @config and @doctor use the on-device model whatever the provider: say whether they can.
        if config.provider != .apple, facts.apple != .unsupportedSystem {
            if facts.apple == .available {
                out.append(Finding(area: .appleIntelligence, status: .ok,
                                   title: t.tr("Apple 智能可以用（@config 和 @doctor 在本机运行）", "Apple Intelligence is ready (@config and @doctor run on this Mac)")))
            } else {
                let fixable = facts.apple == .appleIntelligenceNotEnabled
                out.append(Finding(area: .appleIntelligence, status: .warning, title: t.tr("Apple 智能不能用", "Apple Intelligence isn't available"),
                                   detail: t.appleReason(facts.apple), fix: fixable ? .openAppleIntelligenceSettings : nil))
            }
        }
        return out
    }

    static func permissions(_ facts: Facts, _ t: Words) -> [Finding] {
        var out: [Finding] = []
        switch facts.accessibility {
        case .granted:
            out.append(Finding(area: .permissions, status: .ok, title: t.tr("辅助功能权限已允许", "Accessibility is allowed")))
        case .denied, .notDetermined:
            out.append(Finding(area: .permissions, status: .warning, title: t.tr("辅助功能权限没有允许", "Accessibility isn't allowed"),
                               detail: t.tr("有的 App 里读不到选中的文字", "the selection can't be read in some apps"),
                               fix: .openPrivacy(.accessibility)))
        case .unknown: break
        }
        if facts.config?.voiceInput != false {
            switch facts.microphone {
            case .granted: out.append(Finding(area: .permissions, status: .ok, title: t.tr("麦克风已允许", "The microphone is allowed")))
            case .denied:
                out.append(Finding(area: .permissions, status: .problem, title: t.tr("麦克风没有允许", "The microphone isn't allowed"),
                                   detail: t.tr("语音输入用不了", "voice input can't work"), fix: .openPrivacy(.microphone)))
            case .notDetermined:
                out.append(Finding(area: .permissions, status: .ok, title: t.tr("麦克风：第一次说话时会问", "The microphone: asked the first time you dictate")))
            case .unknown: break
            }
        }
        let denied = facts.automation.filter { $0.value == .denied }.keys.sorted()
        if !denied.isEmpty {
            out.append(Finding(area: .permissions, status: .warning,
                               title: t.tr("不能控制：", "Not allowed to control: ") + denied.joined(separator: t.tr("、", ", ")),
                               detail: t.tr("在「自动化」里允许", "allow it under Automation"), fix: .openPrivacy(.automation)))
        }
        let allowed = facts.automation.filter { $0.value == .granted }.keys.sorted()
        if !allowed.isEmpty {
            out.append(Finding(area: .permissions, status: .ok, title: t.tr("可以控制：", "Allowed to control: ") + allowed.joined(separator: t.tr("、", ", "))))
        }
        return out
    }

    static func packs(_ facts: Facts, _ t: Words) -> [Finding] {
        guard let config = facts.config else { return [] }
        var out: [Finding] = [], installed: [String] = []
        for language in config.inputLanguages where LanguagePack.for(language) != nil {
            let name = t.chinese ? language.displayName : language.englishName
            switch facts.packs[language] ?? .missing {
            case .installed: installed.append(name)
            case .downloading:
                out.append(Finding(area: .languagePacks, status: .warning, title: t.tr("\(name)语言包正在下载", "The \(name) language pack is downloading")))
            case .missing:
                out.append(Finding(area: .languagePacks, status: .problem, title: t.tr("\(name)语言包没有装", "The \(name) language pack isn't installed"),
                                   detail: t.tr("装好以前打不了\(name)", "\(name) can't be typed until it is"), fix: .downloadPack(language)))
            case .damaged:
                out.append(Finding(area: .languagePacks, status: .problem, title: t.tr("\(name)语言包坏了", "The \(name) language pack is damaged"),
                                   detail: t.tr("可以重新下载", "it can be downloaded again"), fix: .downloadPack(language)))
            }
        }
        if !installed.isEmpty {
            out.append(Finding(area: .languagePacks, status: .ok, title: t.tr("语言包已安装：", "Language packs installed: ") + installed.joined(separator: t.tr("、", ", "))))
        }
        return out
    }

    static func extensions(_ facts: Facts, _ t: Words) -> [Finding] {
        var out: [Finding] = []
        if !facts.skippedExtensions.isEmpty {
            out.append(Finding(area: .extensions, status: .warning,
                               title: t.tr("\(facts.skippedExtensions.count) 个扩展命令没有加载", "\(facts.skippedExtensions.count) extension commands weren't loaded"),
                               detail: facts.skippedExtensions.prefix(3).joined(separator: t.tr("；", "; "))))
        }
        if !facts.pluginErrors.isEmpty {
            out.append(Finding(area: .extensions, status: .warning, title: t.tr("插件有问题", "Plugin problems"),
                               detail: facts.pluginErrors.prefix(3).joined(separator: t.tr("；", "; "))))
        }
        if out.isEmpty { out.append(Finding(area: .extensions, status: .ok, title: t.tr("扩展和插件都正常", "Extensions and plugins load fine"))) }
        return out
    }

    static func updates(_ facts: Facts, _ t: Words) -> [Finding] {
        let u = facts.updates
        var out: [Finding] = []
        if let available = u.available {
            out.append(Finding(area: .updates, status: .warning, title: t.tr("有新版本 \(available)（现在是 \(u.version)）", "AllInOneIME \(available) is available (you have \(u.version))"),
                               detail: t.tr("可以检查并更新", "check for updates to install it"), fix: .checkForUpdates))
        } else {
            out.append(Finding(area: .updates, status: .ok, title: t.tr("AllInOneIME \(u.version)", "AllInOneIME \(u.version)"),
                               detail: u.checkEnabled ? t.tr("自动检查更新", "checks for updates automatically") : t.tr("没有自动检查更新", "doesn't check for updates automatically"),
                               fix: nil))
        }
        if let error = u.lastError {
            out.append(Finding(area: .updates, status: .warning, title: t.tr("上次更新没有成功", "The last update didn't work"), detail: error, fix: .checkForUpdates))
        }
        return out
    }

    // MARK: - The config file

    /// The keys a config file may have (those this version writes, and the ones it still reads or another version
    /// writes).
    public static let knownConfigKeys: Set<String> = {
        var keys = Set<String>()
        if let data = try? JSONEncoder().encode(Config.default), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            keys.formUnion(object.keys)
        }
        return keys.union(["typeOutSpeed", "appProfiles", "extensionSources"])
    }()

    /// What is wrong with the config file: it can't be read (no automatic fix: it is never replaced), keys this version
    /// doesn't know, values out of range, a language listed twice, more than 5 translation languages. The fixes go
    /// through `@config` (`repairConfig`, checked like any change) or write the file again as Settings does.
    public static func configFindings(data: Data?, error: String?, config: Config?, chinese: Bool) -> [Finding] {
        let t = Words(chinese: chinese)
        if let error {
            return [Finding(area: .config, status: .problem, title: t.tr("config.json 读不了", "config.json can't be read"),
                            detail: error + t.tr("（打开设置 → 高级 → 配置文件修正它；不会自动删除）", " (fix it in the file, Settings → Advanced; it's never deleted for you)"))]
        }
        guard let config else { return [] }
        var out: [Finding] = []
        let raw = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let unknown = Set(raw.keys).subtracting(knownConfigKeys).sorted()
        if !unknown.isEmpty {
            out.append(Finding(area: .config, status: .warning, title: t.tr("config.json 里有不认识的键", "config.json has keys this version doesn't know"),
                               detail: unknown.prefix(5).joined(separator: ", ") + t.tr("（会被忽略）", " (ignored)")))
        }
        if config.typeOutRate < TypeOut.slowestRate * 0.999 || config.typeOutRate > TypeOut.fastestRate {
            out.append(Finding(area: .config, status: .problem, title: t.tr("打字速度超出范围", "The typing speed is out of range"),
                               detail: "\(config.typeOutRate)", fix: .repairConfig([.init(key: .setting(.typeOutRate), value: .number(TypeOut.defaultRate))])))
        }
        if config.maxTokens < 1 || config.timeoutSeconds <= 0 || (config.temperature.map { $0 < 0 || $0 > 2 } ?? false) {
            out.append(Finding(area: .config, status: .problem, title: t.tr("高级设置里的值超出范围", "An Advanced setting is out of range"),
                               detail: t.tr("在设置 → 高级里改（最多输出 tokens、超时、temperature）", "change it in Settings → Advanced (output tokens, timeout, temperature)")))
        }
        if config.outputLanguages.count > AIConfig.maxOutputLanguages {
            let kept = config.outputLanguages.prefix(AIConfig.maxOutputLanguages).map { AIConfig.JSONValue.string($0.code) }
            out.append(Finding(area: .config, status: .problem, title: t.tr("翻译语言超过 \(AIConfig.maxOutputLanguages) 种", "More than \(AIConfig.maxOutputLanguages) translation languages"),
                               detail: t.tr("留下前 \(AIConfig.maxOutputLanguages) 种", "keep the first \(AIConfig.maxOutputLanguages)"),
                               fix: .repairConfig([.init(key: .setting(.outputLanguages), value: .array(kept))])))
        }
        func repeats(_ key: String) -> Bool {
            guard let list = raw[key] as? [String] else { return false }
            return Set(list).count < list.count
        }
        if repeats("outputLanguages") || repeats("inputLanguages") {
            out.append(Finding(area: .config, status: .warning, title: t.tr("config.json 里有重复的语言", "A language is listed twice in config.json"),
                               detail: t.tr("重新保存一次就去掉", "saving it again removes it"), fix: .resaveConfig))
        }
        if out.isEmpty { out.append(Finding(area: .config, status: .ok, title: t.tr("config.json 正常", "config.json is fine"))) }
        return out
    }

    // MARK: - Logs

    /// Error lines of the app's own logs, as `@doctor` may show and send them: the newest `limit`, each its message
    /// only (no timestamps, no source file), the home folder as "~", quoted text (which may be the user's) left out,
    /// cut to 120 characters.
    public static func summarizeLogLines(_ lines: [String], home: String = NSHomeDirectory(), limit: Int = 3) -> [String] {
        let errors = lines.filter { line in
            let lower = line.lowercased()
            return line.hasPrefix("E") && line.count > 1 && line.dropFirst().first?.isNumber == true
                || lower.contains("error") || lower.contains("failed")
        }
        return errors.suffix(limit).map { line in
            var text = line
            // glog: "E20261008 15:45:58.123 1234 file.cc:56] message"
            if let bracket = text.range(of: "] ") { text = String(text[bracket.upperBound...]) }
            text = text.replacingOccurrences(of: home, with: "~")
            text = text.replacingOccurrences(of: #""[^"]*""#, with: "\"…\"", options: .regularExpression)
            text = text.replacingOccurrences(of: #"'[^']*'"#, with: "'…'", options: .regularExpression)
            text = text.trimmingCharacters(in: .whitespaces)
            return text.count > 120 ? String(text.prefix(120)) + "…" : text
        }
    }

    // MARK: - For the model

    /// The findings as the model reads them (English, one per line, each with its id when it has a fix: "F3"): what
    /// `@doctor <question>` sends, nothing else (no paths beyond ~, no keys, none of the user's text).
    public static func report(_ findings: [Finding], areas: Set<Area>? = nil) -> String {
        findings.enumerated().compactMap { index, finding in
            guard areas?.contains(finding.area) ?? true else { return nil }
            let id = finding.fix == nil ? "" : " [fix F\(index + 1)]"
            return "- \(finding.area.rawValue): \(finding.text(chinese: false))\(id)"
        }.joined(separator: "\n")
    }

    /// "2 problems, 1 warning, 9 fine".
    public static func summary(_ findings: [Finding], chinese: Bool) -> String {
        let t = Words(chinese: chinese)
        let problems = findings.filter { $0.status == .problem }.count, warnings = findings.filter { $0.status == .warning }.count
        let fine = findings.count - problems - warnings
        if problems == 0, warnings == 0 { return t.tr("全部正常（\(fine) 项）", "All \(fine) checks are fine") }
        return t.tr("\(problems) 个问题，\(warnings) 个提醒，\(fine) 项正常",
                    "\(problems) \(problems == 1 ? "problem" : "problems"), \(warnings) \(warnings == 1 ? "warning" : "warnings"), \(fine) fine")
    }

    struct Words {
        let chinese: Bool
        func tr(_ zh: String, _ en: String) -> String { chinese ? zh : en }

        func appleReason(_ availability: AppleModelAvailability) -> String {
            switch availability {
            case .available: return tr("可以用", "ready")
            case .unsupportedSystem: return tr("需要 macOS 26", "needs macOS 26")
            case .deviceNotEligible: return tr("这台 Mac 不支持", "not supported on this Mac")
            case .appleIntelligenceNotEnabled: return tr("在系统设置 → Apple 智能与 Siri 里打开", "turn it on in System Settings → Apple Intelligence & Siri")
            case .modelNotReady: return tr("模型还没准备好（可能还在下载）", "the model isn't ready yet (it may still be downloading)")
            }
        }
    }
}

extension Doctor {
    /// `fixes` as `@config`'s preview: settings repaired through its checks (rows old → new), the rest as action rows
    /// ("→ Download the Korean language pack") and a key row. Nil when none of them can be applied.
    public static func fixPreview(_ fixes: [Fix], config: Config, environment env: AIConfig.Environment) -> AIConfig.Preview? {
        let t = Words(chinese: env.chinese)
        var rows: [AIConfig.Row] = []
        var working = config
        for fix in fixes {
            func action(_ zh: String, _ en: String, _ action: AIConfig.Action) {
                rows.append(AIConfig.Row(key: "doctor", label: t.tr(zh, en), status: .action, action: action))
            }
            switch fix {
            case let .repairConfig(changes):
                let checked = AIConfig.check(AIConfig.Proposal(changes: changes), config: working, environment: env).rows.filter { !$0.isRefused }
                AIConfig.apply(checked.compactMap(\.edit), to: &working)
                rows += checked
            case .resaveConfig:
                action("重新保存 config.json（去掉重复的语言，值不变）", "Save config.json again (repeated languages go; values stay)", .resaveConfig)
            case .enableInputMethod:
                action("重新启用 AllInOneIME 输入法", "Enable the AllInOneIME input method again", .enableInputMethod)
            case let .openPrivacy(pane):
                let name: (String, String)
                switch pane {
                case .accessibility: name = ("辅助功能", "Accessibility")
                case .microphone: name = ("麦克风", "Microphone")
                case .automation: name = ("自动化", "Automation")
                }
                action("打开系统设置 → 隐私与安全性 → \(name.0)", "Open System Settings → Privacy & Security → \(name.1)", .openPrivacy(pane))
            case let .downloadPack(language):
                action("下载\(language.displayName)语言包", "Download the \(language.englishName) language pack", .downloadPack(language))
            case .openAppleIntelligenceSettings:
                action("打开系统设置 → Apple 智能与 Siri", "Open System Settings → Apple Intelligence & Siri", .openAppleIntelligenceSettings)
            case .checkForUpdates:
                action("检查更新", "Check for updates", .checkForUpdates)
            case let .openKeyField(provider):
                let text = AIConfig.Text(chinese: env.chinese)
                rows.append(AIConfig.Row(key: "\(provider.rawValue).apiKey", label: text.keyLabel(provider),
                                         new: provider == .bedrock ? t.tr("在设置 → AI 服务里看 AWS profile", "check the AWS profile in Settings → AI Provider")
                                             : text.enterKey(provider), status: .needsKey(provider)))
            }
        }
        let preview = AIConfig.Preview(rows: rows)
        return preview.canApply ? preview : nil
    }
}

import Foundation

/// Settings → Assistant's "Check for problems": the setup checked on this Mac, a row per finding (✗ problems first,
/// then ⚠, then ✓), each with a short fix; the config fixes go through the request's preview, apply and undo
/// (`fixPreview`). The checks read only what the
/// input method already knows (`Facts`, gathered by the app's probes; the tests give their own) and never send anything.
/// A question then has the model explain the likely cause from them (`DoctorService`).
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
             updates, iCloudSync, recentErrors
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
        /// Settings changed through `AIConfig`'s checks and apply/undo.
        case repairConfig([AIConfig.Change])
        /// The repeated languages taken out of the config file (`removeRepeatedLanguages`): nothing else in it changes,
        /// keys this version doesn't know included.
        case resaveConfig
        /// Settings → AI Provider at the key field.
        case openKeyField(Provider)
        /// A command for Terminal on the clipboard (`aws sso login --profile X`): what fixes it needs a person.
        case copyCommand(String)
        case openAppleIntelligenceSettings
        /// "Check for Updates" as in the input menu.
        case checkForUpdates
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
        /// Bedrock: the profile's kind, its credentials' expiry and the last refresh's error (`AWSCredentialResolver.status`).
        public var awsStatus: AWSProfileStatus?
        public var apple: AppleModelAvailability = .unsupportedSystem
        public var connection: Connection = .notRun
        public var accessibility: Permission = .unknown
        /// Unknown, so not checked, while voice input is off (`Features.voiceInput`): the shell doesn't look.
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
        /// Sync through iCloud (`ICloudSync`).
        public var iCloudSync = ICloudSyncFacts()

        public init() {}
    }

    /// A probe's failure, as text (a profile not found …): equatable and sendable.
    public struct ProbeError: Error, Equatable, Sendable {
        public var message: String
        public init(_ message: String) { self.message = message }
    }

    // MARK: - The findings

    /// Every finding for `facts`, problems first (then warnings, then what is fine), in the areas' order within each; in
    /// the interface language `language` (`InterfaceLanguage`).
    public static func findings(_ facts: Facts, language: String) -> [Finding] {
        let t = Words(language: language)
        var out: [Finding] = []
        out += inputMethod(facts, t)
        out += provider(facts, t)
        out += configFindings(data: facts.configData, error: facts.configError, config: facts.config, language: language)
        out += permissions(facts, t)
        if let owner = facts.secureInput {
            out.append(Finding(area: .secureInput, status: .warning, title: t.tr("安全输入开着（\(owner)）", "Secure input is on (\(owner))"),
                               detail: t.tr("关掉之前不会把文字发给 AI；关掉密码框或那个 App 的安全输入",
                                            "nothing goes to the AI until it's off: leave the password field, or that app")))
        } else {
            out.append(Finding(area: .secureInput, status: .ok, title: t.tr("安全输入没开", "Secure input is off")))
        }
        out += packs(facts, t)
        out += extensions(facts, t)
        out += updates(facts, t)
        out += iCloudSync(facts, t)
        // Lines no known event matches ("2 other log lines") aren't counted as errors.
        let errors = facts.recentErrors.filter { !isOtherLogLines($0) && !isResolvedLogEvent($0) }.count
        let logDetail = facts.recentErrors.map { localizedLogEvent($0, t) }.joined(separator: t.tr("；", "; "))
        if facts.recentErrors.isEmpty {
            out.append(Finding(area: .recentErrors, status: .ok, title: t.tr("最近的日志里没有错误", "No recent errors in the logs")))
        } else if errors == 0 {
            // Fine only when all there is is an error resolved since: other lines beside it are still worth a look.
            let resolvedOnly = facts.recentErrors.allSatisfy(isResolvedLogEvent)
            out.append(Finding(area: .recentErrors, status: resolvedOnly ? .ok : .warning,
                               title: resolvedOnly ? t.tr("之前的 Rime 错误已解决", "An earlier Rime error is resolved")
                                   : t.tr("日志里有别的记录", "Other lines in the logs"), detail: logDetail))
        } else {
            out.append(Finding(area: .recentErrors, status: .warning,
                               title: errors == 1 ? t.tr("最近的日志里有 1 个错误", "1 recent error in the logs")
                                   : t.tr("最近的日志里有 \(errors) 个错误", "\(errors) recent errors in the logs"),
                               detail: logDetail))
        }
        // What the probes reported may hold a full path or a key (an error that echoes one): never shown or sent so.
        out = out.map { finding in
            var finding = finding
            finding.title = scrub(finding.title)
            finding.detail = finding.detail.map { scrub($0) }
            return finding
        }
        let order = Area.allCases
        return out.enumerated().sorted { a, b in
            (a.element.status, order.firstIndex(of: a.element.area) ?? 0, a.offset)
                < (b.element.status, order.firstIndex(of: b.element.area) ?? 0, b.offset)
        }.map(\.element)
    }

    /// `findings` in Simplified Chinese or English.
    public static func findings(_ facts: Facts, chinese: Bool) -> [Finding] {
        findings(facts, language: InterfaceLanguage.code(chinese: chinese))
    }

    static func inputMethod(_ facts: Facts, _ t: Words) -> [Finding] {
        let im = facts.inputMethod
        func problem(_ title: String, _ status: Status = .problem) -> [Finding] {
            [Finding(area: .inputMethod, status: status, title: title, detail: t.tr("可以重新启用", "it can be enabled again"),
                     fix: .enableInputMethod)]
        }
        if !im.registered { return problem(t.tr("输入法没有注册", "The input method isn't registered")) }
        if !im.enabled { return problem(t.tr("输入法没有启用", "The input method isn't enabled")) }
        if !im.listed { return problem(t.tr("输入法不在你的输入法列表里（⌃空格切换不到它）",
                                            "The input method isn't in your input sources (Ctrl-Space doesn't reach it)"), .warning) }
        if !im.selectable { return problem(t.tr("输入法现在不能选", "The input method can't be selected now"), .warning) }
        return [Finding(area: .inputMethod, status: .ok,
                        title: t.tr("AllInOneIME \(im.version) 已安装并启用", "AllInOneIME \(im.version) is installed and enabled"),
                        detail: im.selected ? t.tr("正在使用", "in use now") : nil)]
    }

    static func provider(_ facts: Facts, _ t: Words) -> [Finding] {
        guard let config = facts.config else { return [] }
        var out: [Finding] = []
        let name = AIConfig.Text(language: t.language).provider(config.provider)
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
            out += bedrockProfile(facts, config: config, label: label, t)
        case .anthropic, .gemini, .openai, .hosted:
            if facts.keySaved[config.provider] == true {
                out.append(Finding(area: .provider, status: .ok, title: label,
                                   detail: config.provider == .hosted ? t.tr("已登录", "signed in") : t.tr("已保存 API key", "API key saved")))
            } else {
                // As the Assistant's preview says it of a provider without a key; its fix opens Settings at the key field.
                out.append(Finding(area: .provider, status: .problem, title: label,
                                   detail: config.provider == .hosted ? t.tr("需要登录：在设置里登录", "needs a sign-in: sign in in Settings")
                                       : t.tr("需要 API key：在设置里填（不会发给 AI）", "needs an API key: add it in Settings (never sent to the AI)"),
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
        // Settings' own requests (the search's "Change:", Troubleshoot's question) use the on-device model whatever the
        // provider: say whether they can.
        if config.provider != .apple, facts.apple != .unsupportedSystem {
            if facts.apple == .available {
                out.append(Finding(area: .appleIntelligence, status: .ok,
                                   title: t.tr("Apple 智能可以用", "Apple Intelligence is ready"),
                                   detail: t.tr("设置里的「修改：」和「排查问题」在本机处理", "Settings' “Change:” and Troubleshoot are handled on this Mac")))
            } else {
                let fixable = facts.apple == .appleIntelligenceNotEnabled
                out.append(Finding(area: .appleIntelligence, status: .warning,
                                   title: t.tr("Apple 智能不能用", "Apple Intelligence isn't available"),
                                   detail: t.appleReason(facts.apple) + t.tr("；设置里的「修改：」和「排查问题」会发给你选的 AI 服务",
                                                                            "; Settings' “Change:” and Troubleshoot go to your AI provider"),
                                   fix: fixable ? .openAppleIntelligenceSettings : nil))
            }
        }
        return out
    }

    /// Bedrock's AWS profile: its kind and when its credentials expire, or what's wrong (an SSO sign-in to renew is
    /// fixed with its command on the clipboard).
    static func bedrockProfile(_ facts: Facts, config: Config, label: String, _ t: Words) -> [Finding] {
        let status = facts.awsStatus
        let kind = status?.kind.map { " (" + $0.label(language: t.language) + ")" } ?? ""
        let fix = status?.fixCommand.map(Fix.copyCommand)
        switch facts.awsProfile {
        case let .success(region)?:
            // A profile whose credentials are fetched says so as the status line does ("credentials expire at 15:30",
            // "assumed when a request needs it"); static keys and the environment's as before.
            let held = status.flatMap { $0.kind?.refreshes == true ? $0.credentials(language: t.language) : nil }
                ?? t.tr("找到了密钥", "credentials found")
            var out = [Finding(area: .provider, status: .ok, title: label,
                               detail: t.tr("profile \(config.awsProfile)\(kind)，区域 \(config.region ?? region)，\(held)",
                                            "profile \(config.awsProfile)\(kind), region \(config.region ?? region), \(held)"))]
            // Credentials still held, but the next refresh will fail (an SSO sign-in that expired); or the last one failed.
            if let problem = status?.problem {
                out.append(Finding(area: .provider, status: .warning,
                                   title: t.tr("AWS 凭证下次刷新会失败", "AWS credentials: the next refresh will fail"),
                                   detail: problem.message(language: t.language), fix: problem.fixCommand.map(Fix.copyCommand)))
            }
            if let failed = status?.lastError, failed != status?.problem {
                out.append(Finding(area: .provider, status: .warning,
                                   title: t.tr("AWS 凭证上次刷新失败", "AWS credentials: the last refresh failed"),
                                   detail: failed.message(language: t.language), fix: failed.fixCommand.map(Fix.copyCommand)))
            }
            return out
        case let .failure(error)?:
            let detail = status?.problem.map { $0.message(language: t.language) } ?? error.message
            return [Finding(area: .provider, status: .problem, title: label + kind, detail: detail, fix: fix ?? .openKeyField(.bedrock))]
        case nil:
            return [Finding(area: .provider, status: .ok, title: label)]
        }
    }

    static func permissions(_ facts: Facts, _ t: Words) -> [Finding] {
        var out: [Finding] = []
        switch facts.accessibility {
        case .granted:
            out.append(Finding(area: .permissions, status: .ok, title: t.tr("辅助功能权限已允许", "Accessibility is allowed")))
        case .denied, .notDetermined:
            // Not allowed for the build that runs, though System Settings may show the switch on: after an update macOS
            // can keep it for the previous build's signature.
            out.append(Finding(area: .permissions, status: .warning, title: t.tr("辅助功能权限没有允许", "Accessibility isn't allowed"),
                               detail: t.tr("有的 App 里读不到选中的文字。如果系统设置 → 隐私与安全性 → 辅助功能里 AllInOneIME 已经打开，先关掉再打开（macOS 可能还留着上一个版本的权限）",
                                            "the selection can't be read in some apps. If AllInOneIME is already on in System Settings → Privacy & Security → Accessibility, turn it off and on again (macOS can keep the permission for the previous version)"),
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
                out.append(Finding(area: .permissions, status: .ok,
                                   title: t.tr("麦克风：第一次说话时会问", "The microphone: asked the first time you dictate")))
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
            out.append(Finding(area: .permissions, status: .ok,
                               title: t.tr("可以控制：", "Allowed to control: ") + allowed.joined(separator: t.tr("、", ", "))))
        }
        return out
    }

    static func packs(_ facts: Facts, _ t: Words) -> [Finding] {
        guard let config = facts.config else { return [] }
        var out: [Finding] = [], installed: [String] = []
        for language in config.inputLanguages where LanguagePack.for(language) != nil {
            let name = language.name(in: t.language)
            switch facts.packs[language] ?? .missing {
            case .installed: installed.append(name)
            case .downloading:
                out.append(Finding(area: .languagePacks, status: .warning,
                                   title: t.tr("\(name)语言包正在下载", "The \(name) language pack is downloading")))
            case .missing:
                out.append(Finding(area: .languagePacks, status: .problem,
                                   title: t.tr("\(name)语言包没有装", "The \(name) language pack isn't installed"),
                                   detail: t.tr("装好以前打不了\(name)", "\(name) can't be typed until it is"), fix: .downloadPack(language)))
            case .damaged:
                out.append(Finding(area: .languagePacks, status: .problem,
                                   title: t.tr("\(name)语言包坏了", "The \(name) language pack is damaged"),
                                   detail: t.tr("可以重新下载", "it can be downloaded again"), fix: .downloadPack(language)))
            }
        }
        if !installed.isEmpty {
            out.append(Finding(area: .languagePacks, status: .ok,
                               title: t.tr("语言包已安装：", "Language packs installed: ") + installed.joined(separator: t.tr("、", ", "))))
        }
        return out
    }

    static func extensions(_ facts: Facts, _ t: Words) -> [Finding] {
        var out: [Finding] = []
        if !facts.skippedExtensions.isEmpty {
            out.append(Finding(area: .extensions, status: .warning,
                               title: facts.skippedExtensions.count == 1 ? t.tr("1 个扩展命令没有加载", "1 extension command wasn't loaded")
                                   : t.tr("\(facts.skippedExtensions.count) 个扩展命令没有加载",
                                          "\(facts.skippedExtensions.count) extension commands weren't loaded"),
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
            out.append(Finding(area: .updates, status: .warning,
                               title: t.tr("有新版本 \(available)（现在是 \(u.version)）",
                                           "AllInOneIME \(available) is available (you have \(u.version))"),
                               detail: t.tr("可以检查并更新", "check for updates to install it"), fix: .checkForUpdates))
        } else {
            // Named by what is checked: the version is the input method's row's title already.
            out.append(Finding(area: .updates, status: .ok,
                               title: u.checkEnabled ? t.tr("更新：自动检查", "Updates: checked automatically")
                                   : t.tr("更新：不自动检查", "Updates: not checked automatically"),
                               detail: t.tr("当前版本 \(u.version)", "you have \(u.version)")))
        }
        if let error = u.lastError {
            out.append(Finding(area: .updates, status: .warning, title: t.tr("上次更新没有成功", "The last update didn't work"), detail: error,
                               fix: .checkForUpdates))
        }
        return out
    }

    /// Whether Test Connection can tell anything: the config reads, and the provider has what it needs (the on-device
    /// model available, the Bedrock profile's credentials found, a key saved or the hosted service signed in to). Without
    /// it the provider's own row says what is missing, and no second ✗ row is added.
    public static func canTestConnection(_ facts: Facts) -> Bool {
        guard let config = facts.config else { return false }
        switch config.provider {
        case .apple: return facts.apple == .available
        case .bedrock: if case .success? = facts.awsProfile { return true } else { return false }
        case .anthropic, .gemini, .openai, .hosted: return facts.keySaved[config.provider] == true
        }
    }

    // MARK: - The config file

    /// The keys a config file may have: `Config`'s coding keys (those it writes, and those it only reads).
    public static let knownConfigKeys = Set(Config.allKeys)

    /// What is wrong with the config file: it can't be read (no automatic fix: it is never replaced), keys this version
    /// doesn't know, values out of range, a language listed twice, more than 5 translation languages. The fixes go
    /// through `AIConfig` (`repairConfig`, checked like any change) or write the file again as Settings does.
    public static func configFindings(data: Data?, error: String?, config: Config?, chinese: Bool) -> [Finding] {
        configFindings(data: data, error: error, config: config, language: InterfaceLanguage.code(chinese: chinese))
    }

    /// `configFindings` in the interface language `language`.
    public static func configFindings(data: Data?, error: String?, config: Config?, language: String) -> [Finding] {
        let t = Words(language: language)
        if let error {
            return [Finding(area: .config, status: .problem, title: t.tr("config.json 读不了", "config.json can't be read"),
                            detail: error + t.tr("（打开设置 → 高级 → 配置文件修正它；不会自动删除）",
                                                 " (fix it in the file, Settings → Advanced; it's never deleted for you)"))]
        }
        guard let config else { return [] }
        var out: [Finding] = []
        let raw = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let unknown = Set(raw.keys).subtracting(knownConfigKeys).sorted()
        if !unknown.isEmpty {
            out.append(Finding(area: .config, status: .warning,
                               title: t.tr("config.json 里有不认识的键", "config.json has keys this version doesn't know"),
                               detail: unknown.prefix(5).joined(separator: ", ") + t.tr("（会被忽略）", " (ignored)")))
        }
        if config.typeOutRate < TypeOut.slowestRate * 0.999 || config.typeOutRate > TypeOut.fastestRate {
            // What the file says, and the range Settings' slider allows (characters a second).
            func number(_ value: Double) -> String {
                value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
            }
            let (rate, slowest, fastest) = ("\(config.typeOutRate)", number(TypeOut.slowestRate), number(TypeOut.fastestRate))
            out.append(Finding(area: .config, status: .problem, title: t.tr("打字速度超出范围", "The typing speed is out of range"),
                               detail: t.tr("每秒 \(rate) 个字（应在 \(slowest) 到 \(fastest) 之间）",
                                            "\(rate) characters a second (should be between \(slowest) and \(fastest))"),
                               fix: .repairConfig([.init(key: .setting(.typeOutRate), value: .number(TypeOut.defaultRate))])))
        }
        // The Mac shows them under AI (Settings v2: each set otherwise than its default with Restore Default).
        if config.maxTokens < 1 || config.timeoutSeconds <= 0 || (config.temperature.map { $0 < 0 || $0 > 2 } ?? false) {
            let mac = Platform.current.terms.device == .mac
            out.append(Finding(area: .config, status: .problem,
                               title: mac ? t.tr("模型参数超出范围", "A model setting is out of range")
                                   : t.tr("高级设置里的值超出范围", "An Advanced setting is out of range"),
                               detail: mac ? t.tr("在设置 → AI 里恢复默认（最多输出 tokens、超时、temperature）",
                                                  "restore its default in Settings → AI (output tokens, timeout, temperature)")
                                   : t.tr("在设置 → 高级里改（最多输出 tokens、超时、temperature）",
                                          "change it in Settings → Advanced (output tokens, timeout, temperature)")))
        }
        if config.outputLanguages.count > AIConfig.maxOutputLanguages {
            let kept = config.outputLanguages.prefix(AIConfig.maxOutputLanguages).map { AIConfig.JSONValue.string($0.code) }
            out.append(Finding(area: .config, status: .problem,
                               title: t.tr("翻译语言超过 \(AIConfig.maxOutputLanguages) 种",
                                           "More than \(AIConfig.maxOutputLanguages) translation languages"),
                               detail: t.tr("留下前 \(AIConfig.maxOutputLanguages) 种", "keep the first \(AIConfig.maxOutputLanguages)"),
                               fix: .repairConfig([.init(key: .setting(.outputLanguages), value: .array(kept))])))
        }
        func repeats(_ key: String) -> Bool {
            guard let list = raw[key] as? [String] else { return false }
            return Set(list).count < list.count
        }
        if repeats("outputLanguages") || repeats("inputLanguages") {
            // Only those lists change (`removeRepeatedLanguages`): nothing else in the file.
            out.append(Finding(area: .config, status: .warning,
                               title: t.tr("config.json 里有重复的语言", "A language is listed twice in config.json"),
                               detail: t.tr("可以只去掉重复的，别的不动", "the repeats can be removed, nothing else changes"),
                               fix: .resaveConfig))
        }
        if out.isEmpty { out.append(Finding(area: .config, status: .ok, title: t.tr("config.json 正常", "config.json is fine"))) }
        return out
    }

    // MARK: - Logs

    /// Error lines of the app's own logs, as the checks may show and send them: each event as a fixed phrase ("update
    /// check failed (network, -1009)", "Rime dictionary failed to load", "plugin weather failed to load"), with a reason
    /// from a fixed list or an error code or domain, once, with how many times it came up when more than once ("…, 3
    /// times"): the newest `limit` events, oldest first. Of the line's own text only two things may be kept: a `~/…` path
    /// in a Rime dictionary event (which of its files), and a plugin's name when it looks like one (letters, digits, - _ .).
    /// Lines no known event matches are counted on one last line ("2 other log lines"). `lunarDatabaseAvailable`: the Rime
    /// user folder has lua/lunar.db now, so the runs that missed it were earlier ones (`providedLunarDatabase`).
    public static func summarizeLogLines(_ lines: [String], home: String = NSHomeDirectory(), limit: Int = 3,
                                         lunarDatabaseAvailable: Bool = false) -> [String] {
        let errors = lines.filter { line in
            let lower = line.lowercased()
            return line.hasPrefix("E") && line.count > 1 && line.dropFirst().first?.isNumber == true
                || lower.contains("error") || lower.contains("failed") || line.hasPrefix("✗")
        }
        // Each event: how many times, and the line it came on last.
        var counts: [String: Int] = [:], last: [String: Int] = [:], others = 0
        for (index, line) in errors.enumerated() {
            guard var event = logEvent(line, home: home) else {
                others += 1
                continue
            }
            if lunarDatabaseAvailable, event == missingLunarDatabase { event = providedLunarDatabase }
            event = event.count > 120 ? String(event.prefix(120)) + "…" : event
            counts[event, default: 0] += 1
            last[event] = index
        }
        var out = last.sorted { $0.value < $1.value }.suffix(limit).map { event, _ in
            let count = counts[event] ?? 1
            return count > 1 ? "\(event), \(count) times" : event
        }
        if others > 0 { out.append(others == 1 ? "1 other log line" : "\(others) other log lines") }
        return out
    }

    /// The last line of `summarizeLogLines` that counts the lines no known event matched.
    static func isOtherLogLines(_ line: String) -> Bool {
        line.range(of: #"^\d+ other log lines?$"#, options: .regularExpression) != nil
    }

    /// librime couldn't open rime-ice's lunar date database, lua/lunar.db in the Rime user folder: reported by its
    /// mapped file and again by the reverse lookup that reads it. Since 0.6.7 the app puts it there as Rime starts
    /// (`RimeService.prepareLunarDatabase`); when it is there now, those runs were earlier ones, and the event is
    /// `providedLunarDatabase` instead, not an error.
    static let missingLunarDatabase = "Rime: a file it needs is missing: lua/lunar.db (the lunar date)"
    static let providedLunarDatabase = "Earlier Rime run: lua/lunar.db was missing; this version provides it"

    static func isResolvedLogEvent(_ line: String) -> Bool { line.hasPrefix(providedLunarDatabase) }

    /// A line of `summarizeLogLines` as the findings show it: the lunar database's phrases and the count in the
    /// interface language (the other phrases stay in English, as the logs are).
    static func localizedLogEvent(_ line: String, _ t: Words) -> String {
        var event = line, count: Int?
        if let range = line.range(of: #", \d+ times$"#, options: .regularExpression) {
            count = Int(line[range].filter(\.isNumber))
            event = String(line[..<range.lowerBound])
        }
        switch event {
        case missingLunarDatabase:
            event = t.tr("Rime：缺少所需文件 lua/lunar.db（农历日期）", "Rime: a file it needs is missing: lua/lunar.db (the lunar date)")
        case providedLunarDatabase:
            event = t.tr("之前运行 Rime 时缺少 lua/lunar.db；此版本已提供该文件", "Earlier Rime run: lua/lunar.db was missing; this version provides it")
        default: break
        }
        return event + (count.map { t.tr("，\($0) 次", ", \($0) times") } ?? "")
    }

    /// The phrase for the event `line` records, or nil when it is none the app knows.
    static func logEvent(_ line: String, home: String) -> String? {
        var text = line
        // Quoted text may be the user's: in straight, typographic and CJK quotes alike, gone before anything is read.
        for (open, close) in quotes {
            text = text.replacingOccurrences(of: NSRegularExpression.escapedPattern(for: open) + "[^" + close + "]*"
                                                 + NSRegularExpression.escapedPattern(for: close),
                                             with: " ", options: .regularExpression)
        }
        if !home.isEmpty { text = text.replacingOccurrences(of: home, with: "~") }
        let reason = logReason(text).map { " (\($0))" } ?? ""
        // librime (glog): "E20261008 15:45:58.123 1234 dictionary.cc:56] message".
        if let glog = text.range(of: #"^E\d{8} [^\]]*\] "#, options: .regularExpression) {
            let source = text[glog].range(of: #"[A-Za-z_]+(?=\.(cc|cpp|h):\d+\])"#, options: .regularExpression)
                .map { String(text[glog][$0]) }
            let message = text[glog.upperBound...].lowercased()
            // The quoted path is gone from `text`: the line itself says which file, matched as a whole, and only the
            // fixed phrase goes on.
            if source == "mapped_file" || source == "reverse_lookup_dictionary",
               line.contains("lua/lunar.db") || line.contains(#"lua\lunar.db"#),
               line.contains("non-existent file") || line.contains("Error opening reversedb") {
                return missingLunarDatabase
            }
            if message.contains("lookup") { return "Rime lookup failed" + reason }
            if message.contains("deploy") || source == "deployer" || source == "deployment_tasks" {
                return "Rime deployment failed" + reason
            }
            let dictionary = ["dict", "table", "prism", "schema", ".yaml", ".bin"].contains { message.contains($0) }
                || ["dictionary", "table", "prism", "schema", "config"].contains(source ?? "")
            if message.contains("load"), dictionary {
                // A path under the home folder is the Rime folder's: it says which file.
                let path = String(text[glog.upperBound...]).split(whereSeparator: \.isWhitespace).first { $0.hasPrefix("~/") }
                return "Rime dictionary failed to load" + (path.map { ": " + $0 } ?? reason)
            }
            let components: Set<String> = ["engine", "dictionary", "deployer", "schema", "switcher", "table", "prism", "user_db", "levers"]
            return "error in Rime" + (source.map { components.contains($0) ? " (\($0))" : "" } ?? "")
        }
        let lower = text.lowercased()
        func has(_ words: String...) -> Bool { words.contains { lower.contains($0) } }
        if has("update check") { return "update check failed" + reason }
        if has("rolling back") || lower.hasPrefix("✗") || has("update") && has("install", "move", "stag", "helper", "register", "swap") {
            return "update failed to install" + reason
        }
        if has("download") { return (has("pack") ? "language pack download failed" : "download failed") + reason }
        if has("plugin") {
            // Its name, when it looks like one (letters, digits, - _ .), never anything else from the line.
            let name = text.range(of: #"(?i)plugin[ :]+([a-z0-9][a-z0-9._-]{0,31})\b"#, options: .regularExpression)
                .flatMap { range -> String? in
                    let word = text[range].split(whereSeparator: { $0 == " " || $0 == ":" }).last.map(String.init)
                    return word.flatMap { ["failed", "error", "can't", "couldn't", "is", "was"].contains($0.lowercased()) ? nil : $0 }
                }
            return (name.map { "plugin \($0) failed to load" } ?? "a plugin failed to load") + reason
        }
        if has("extension", "script") { return "an extension failed to run" + reason }
        if has("keychain") { return "keychain access failed" + reason }
        if has("config.json", "config file") { return "config.json couldn't be read" + reason }
        if has("bedrock", "anthropic", "gemini", "openai", "provider", "request") { return "AI request failed" + reason }
        return nil
    }

    /// Why an event failed, from a fixed list, or the error code or domain the line names; nil when it says neither.
    static func logReason(_ text: String) -> String? {
        let lower = text.lowercased()
        func code(_ pattern: String) -> String? { text.range(of: pattern, options: .regularExpression).map { String(text[$0]) } }
        let urlCode = code(#"-10(0[0-9]|1[0-9]|20)\b"#)
        if lower.contains("timed out") || lower.contains("timeout") || urlCode == "-1001" { return "timed out" }
        if lower.contains("offline") || lower.contains("not connected") || lower.contains("network") || lower.contains("could not connect")
            || lower.contains("cannot find host") || urlCode != nil || lower.contains("nsurlerrordomain") {
            return "network" + (urlCode.map { ", \($0)" } ?? "")
        }
        if lower.contains("signature") { return "signature" }
        if lower.contains("checksum") || lower.contains("sha256") || lower.contains("mismatch") { return "checksum" }
        if lower.contains("permission") || lower.contains("denied") || lower.contains("not permitted") || text.contains("EACCES") {
            return "permission"
        }
        if lower.contains("no space") || lower.contains("disk full") || text.contains("ENOSPC") { return "disk full" }
        if lower.contains("not found") || lower.contains("no such file") || text.contains("ENOENT") { return "not found" }
        if lower.contains("http") || lower.contains("status"), let status = code(#"\b[1-5][0-9][0-9]\b"#) { return "HTTP \(status)" }
        if let name = code(#"\b[A-Z][A-Za-z]*(Exception|ErrorDomain)\b"#) {
            return name + (code(#"(?<=\s)-?\d{1,6}\b"#).map { " \($0)" } ?? "")
        }
        if let constant = code(#"\bE[A-Z]{3,}\b"#) { return constant }
        return nil
    }

    /// The quotes whose text `summarizeLogLines` leaves out.
    static let quotes: [(String, String)] = [("\"", "\""), ("“", "”"), ("‘", "’"), ("「", "」"), ("『", "』"), ("«", "»"), ("'", "'")]

    /// `text` as a finding shows it and the model may get it: the home folder as "~", any other absolute path as
    /// "…/<last component>" (`maskingAbsolutePaths`), anything that looks like a key (`Redaction`'s key detection, whatever
    /// the user's hiding settings) as "[KEY]".
    public static func scrub(_ text: String, home: String = NSHomeDirectory()) -> String {
        let homeless = home.isEmpty ? text : text.replacingOccurrences(of: home, with: "~")
        return AIConfig.maskingKeys(maskingAbsolutePaths(homeless), with: "[KEY]")
    }

    /// An absolute path (not one under ~, not part of a web address or a relative path) as "…/<last component>": a folder
    /// name may be the user's. A folder's name may hold spaces (it ends before a "/"); the last component's only before a
    /// word that doesn't start in lowercase ("Report Q3 2026.zip"), so the text after a path ("… to /tmp") stays.
    static func maskingAbsolutePaths(_ text: String) -> String {
        let folder = #"[^/\n:"“”'‘’「」]*[^/\s:"“”'‘’「」]"#
        let last = #"[^/\s:"“”'‘’「」,;()]+(?:[ \t](?![a-z])[^/\s:"“”'‘’「」,;()]+)*"#
        // A file URL's path too ("file:///Users/…", "file://localhost/…"); not one masked already ("…/a.zip").
        let fileURL = try! NSRegularExpression(pattern: #"(?i)(file://)(?:localhost)?/(?:\#(folder)/)*\#(last)"#)
        let path = try! NSRegularExpression(pattern: #"(?<![\w~./:\\…-])/(?:\#(folder)/)*\#(last)"#)
        var out = text
        for (regex, keepsScheme) in [(fileURL, true), (path, false)] {
            let ns = out as NSString
            let masked = NSMutableString(string: out)
            for match in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed() {
                let found = ns.substring(with: match.range)
                let scheme = keepsScheme ? ns.substring(with: match.range(at: 1)) : ""
                // A file URL's path is percent-encoded: its last component as it reads.
                let lastComponent = found.split(separator: "/").last.map(String.init) ?? ""
                masked.replaceCharacters(in: match.range, with: scheme + "…/" + (lastComponent.removingPercentEncoding ?? lastComponent))
            }
            out = masked as String
        }
        return out
    }

    /// The repeated languages taken out of `outputLanguages` and `inputLanguages` in the config file at `url`, the first
    /// of each kept, at the JSON level (`AIConfig.patchingFile`): every other key, one this version doesn't know too,
    /// stays as it was.
    public static func removeRepeatedLanguages(at url: URL) throws {
        try AIConfig.patchingFile(at: url) { file in
            for key in ["outputLanguages", "inputLanguages"] {
                guard case let .array(items)? = file[key] else { continue }
                var seen: [AIConfig.JSONValue] = []
                for item in items where !seen.contains(item) { seen.append(item) }
                file[key] = .array(seen)
            }
        }
    }

    // MARK: - For the model

    /// The findings as the model reads them, one per line, each with its id when it has a fix ("F3"): what
    /// a question sends, nothing else. In the language they were made in: the controller makes them in English
    /// for the model (`findings(_:chinese: false)`, in the same order as the panel's). Each line is scrubbed again
    /// (`scrub`): no paths beyond ~ ("…/<last>" for others), no keys; the user's text was never in them.
    public static func report(_ findings: [Finding], areas: Set<Area>? = nil) -> String {
        findings.enumerated().compactMap { index, finding in
            guard areas?.contains(finding.area) ?? true else { return nil }
            let id = finding.fix == nil ? "" : " [fix F\(index + 1)]"
            return "- \(finding.area.rawValue): \(scrub(finding.text(chinese: false)))\(id)"
        }.joined(separator: "\n")
    }

    /// "2 problems, 1 warning, 9 fine"; a count that is 0 left out ("2 problems, 10 fine").
    public static func summary(_ findings: [Finding], language: String) -> String {
        let t = Words(language: language)
        let problems = findings.filter { $0.status == .problem }.count, warnings = findings.filter { $0.status == .warning }.count
        let fine = findings.count - problems - warnings
        if problems == 0, warnings == 0 { return t.tr("全部正常（\(fine) 项）", "All \(fine) checks are fine") }
        let problemCount = problems == 1 ? t.tr("1 个问题", "1 problem") : t.tr("\(problems) 个问题", "\(problems) problems")
        let warningCount = warnings == 1 ? t.tr("1 个提醒", "1 warning") : t.tr("\(warnings) 个提醒", "\(warnings) warnings")
        let fineCount = t.tr("\(fine) 项正常", "\(fine) fine")
        if problems == 0 { return t.tr("\(warningCount)，\(fineCount)", "\(warningCount), \(fineCount)") }
        if warnings == 0 { return t.tr("\(problemCount)，\(fineCount)", "\(problemCount), \(fineCount)") }
        return t.tr("\(problemCount)，\(warningCount)，\(fineCount)", "\(problemCount), \(warningCount), \(fineCount)")
    }

    /// `summary` in Simplified Chinese or English.
    public static func summary(_ findings: [Finding], chinese: Bool) -> String {
        summary(findings, language: InterfaceLanguage.code(chinese: chinese))
    }

    /// The findings' text in one interface language (`InterfaceWords`), and the words only they use.
    typealias Words = InterfaceWords
}

extension InterfaceWords {
    func appleReason(_ availability: AppleModelAvailability) -> String {
        switch availability {
        case .available: return tr("可以用", "ready")
        case .unsupportedSystem: return tr("需要 macOS 26", "needs macOS 26")
        case .deviceNotEligible: return tr("这台 Mac 不支持", "not supported on this Mac")
        case .appleIntelligenceNotEnabled: return tr("在系统设置 → Apple 智能与 Siri 里打开",
                                                     "turn it on in System Settings → Apple Intelligence & Siri")
        case .modelNotReady: return tr("模型还没准备好（可能还在下载）", "the model isn't ready yet (it may still be downloading)")
        }
    }
}

extension Doctor {
    /// `fixes` as the Assistant's preview: settings repaired through its checks (rows old → new), the rest as action rows
    /// ("→ Download the Korean language pack") and a key row. Nil when none of them can be applied.
    public static func fixPreview(_ fixes: [Fix], config: Config, environment env: AIConfig.Environment) -> AIConfig.Preview? {
        let t = Words(language: env.language)
        var rows: [AIConfig.Row] = []
        var working = config
        for fix in fixes {
            func action(_ label: String, _ action: AIConfig.Action) {
                rows.append(AIConfig.Row(key: "doctor", label: label, status: .action, action: action))
            }
            switch fix {
            case let .repairConfig(changes):
                let checked = AIConfig.check(AIConfig.Proposal(changes: changes), config: working, environment: env).rows
                    .filter { !$0.isRefused }
                AIConfig.apply(checked.compactMap(\.edit), to: &working)
                rows += checked
            case .resaveConfig:
                action(t.tr("去掉 config.json 里重复的语言（别的不动）",
                            "Remove the repeated languages from config.json (nothing else changes)"), .resaveConfig)
            case .enableInputMethod:
                action(t.tr("重新启用 AllInOneIME 输入法", "Enable the AllInOneIME input method again"), .enableInputMethod)
            case let .openPrivacy(pane):
                let label: String
                switch pane {
                case .accessibility:
                    label = t.tr("打开系统设置 → 隐私与安全性 → 辅助功能", "Open System Settings → Privacy & Security → Accessibility")
                case .microphone:
                    label = t.tr("打开系统设置 → 隐私与安全性 → 麦克风", "Open System Settings → Privacy & Security → Microphone")
                case .automation:
                    label = t.tr("打开系统设置 → 隐私与安全性 → 自动化", "Open System Settings → Privacy & Security → Automation")
                }
                action(label, .openPrivacy(pane))
            case let .downloadPack(language):
                action(t.tr("下载\(language.displayName)语言包", "Download the \(language.name(in: t.language)) language pack"),
                       .downloadPack(language))
            case .openAppleIntelligenceSettings:
                action(t.tr("打开系统设置 → Apple 智能与 Siri", "Open System Settings → Apple Intelligence & Siri"), .openAppleIntelligenceSettings)
            case .checkForUpdates:
                action(t.tr("检查更新", "Check for updates"), .checkForUpdates)
            case let .copyCommand(command):
                action(t.tr("复制命令到剪贴板，在终端里运行：\(command)", "Copy the command to run in Terminal: \(command)"), .copyCommand(command))
            case let .openKeyField(provider):
                let text = AIConfig.Text(language: env.language)
                // The row a request's preview shows for a provider without a key (it is the one in use here: nothing to choose).
                rows.append(provider == .bedrock
                    ? AIConfig.Row(key: "\(provider.rawValue).apiKey", label: text.keyLabel(provider),
                                   new: Platform.current.terms.device == .mac
                                       ? t.tr("在设置 → AI 里看 AWS profile", "check the AWS profile in Settings → AI")
                                       : t.tr("在设置 → AI 服务里看 AWS profile", "check the AWS profile in Settings → AI Provider"),
                                   status: .needsKey(provider))
                    : AIConfig.Row(key: "\(provider.rawValue).apiKey", label: text.needsKey(provider),
                                   new: text.addKey(provider, choose: false), status: .needsKey(provider)))
            }
        }
        let preview = AIConfig.Preview(rows: rows)
        return preview.canApply ? preview : nil
    }
}

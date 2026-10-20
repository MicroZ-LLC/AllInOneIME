import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An error of a shell's own (the Mac's Notes and Reminders bridges, its voice input) that says what it is in the
/// interface language: `UIText.describe` asks it before anything else it doesn't know.
public protocol InterfaceDescribedError: Error {
    /// What it is in the interface language (`tr`); nil: described as any other error (in English, its
    /// `LocalizedError` text, or in Chinese that one, which is Chinese, through `UIText.chineseOnly`).
    var interfaceDescription: String? { get }
}

// Errors in the interface language: what the candidate panel, the notices and the settings say when something fails.
extension UIText {
    /// An error as the settings window shows it.
    public static func describe(_ error: Error) -> String {
        // One line that says what to do ("SSO sign-in expired: run aws sso login --profile X").
        if let error = error as? AWSCredentialError { return error.shortMessage(language: language) }
        // Settings → Assistant's request too long for Apple Intelligence on this Mac: a shorter one, or the provider to set up.
        if let error = error as? AIConfigService.TooLong { return error.line(language: language, describe: { describe($0) }) }
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
        if let error = error as? NoteError { return error.message(language: language) }
        // A shell's own (the Mac's Notes and Reminders, its voice input): as it says itself.
        if let error = error as? InterfaceDescribedError, let text = error.interfaceDescription { return text }
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
        guard !chinese else { return chineseOnly(chineseDescription(error)) }
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

    /// An error of Apple Intelligence on this Mac: what to do about it. Too long for its context (@improve on a long text,
    /// say): in every interface language, as Settings → Assistant says it (`AIConfigService.TooLong`); the others in
    /// Chinese and English.
    public static func describe(_ error: AppleModelError) -> String {
        if error == .contextExceeded {
            return tr("内容太长，本机的 Apple Intelligence 处理不了（它的上下文很小）：缩短一些，或换一个 AI 服务",
                      "Too long for Apple Intelligence on this Mac (its context is small): shorten the text or use another provider")
        }
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
        case .contextExceeded: return describe(error)
        case .unsupportedLanguage: return "本机的 Apple Intelligence 不支持这种语言：这种语言请换一个 AI 服务"
        case .busy: return "Apple Intelligence 正忙：稍后再试"
        case let .timedOut(seconds): return "Apple Intelligence \(Int(seconds)) 秒内没有回应"
        case let .failed(detail): return "Apple Intelligence：\(detail)"
        }
    }

    /// A web search error (`@search`): where to add the key, what the service said.
    public static func describe(_ error: WebSearch.SearchError) -> String {
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

    /// An error in Simplified Chinese, for what has no words of its own here: a network failure's, or its
    /// `LocalizedError` text (the core's are Chinese), or how Swift prints it.
    public static func chineseDescription(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "请求超时"
            case .notConnectedToInternet, .networkConnectionLost: return "网络连接失败"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "无法连接 AI 服务"
            default: return urlError.localizedDescription
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

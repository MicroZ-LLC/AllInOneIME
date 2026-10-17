import Foundation

/// Why an AWS profile gave no credentials (`AWSCredentialResolver`): each says what to do, in a line. None holds a key,
/// a secret, a session token or an SSO token: a program's standard error is shown with anything like a key masked
/// (`AIConfig.maskingKeys`), and what it printed on standard output never.
public enum AWSCredentialError: Error, LocalizedError, Equatable, Sendable {
    /// No such profile in the config or credentials file (and, for "default", no keys in the environment).
    case profileNotFound(String)
    /// The profile has none of the settings that give credentials (only a region, say).
    case noCredentials(profile: String)
    /// A setting that can't work as written ("role_arn needs source_profile or credential_source").
    case invalidProfile(profile: String, reason: String)
    /// `role_arn` with `mfa_serial`: an MFA code would be needed, and an input method can't ask for one.
    case needsMFA(profile: String)
    /// `credential_source` other than `Environment` (EC2 instance metadata, an ECS container: not on a Mac).
    case unsupportedCredentialSource(profile: String, source: String)
    /// A kind of profile this app doesn't resolve (web identity).
    case unsupported(profile: String, kind: String)
    /// `source_profile` going round: the profiles in order, the first one again at the end.
    case sourceProfileLoop([String])
    /// `credential_source = Environment` (or the "default" profile from the environment) without the keys set.
    case environmentMissing(profile: String)
    /// `credential_process`: the command can't be split into arguments (an unclosed quote) or is empty.
    case invalidCommand(profile: String, reason: String)
    /// `credential_process`: its program isn't there (or not executable) on the login shell's PATH.
    case processNotFound(profile: String, program: String)
    /// `credential_process`: stopped after the timeout (60 s).
    case processTimedOut(profile: String, program: String, seconds: Int)
    /// `credential_process`: exited with a non-zero status; the last lines of its standard error, keys masked.
    case processFailed(profile: String, program: String, status: Int32, stderr: String)
    /// `credential_process`: what it printed isn't the JSON the AWS CLI expects; why (never what it printed), and the last
    /// lines of its standard error, keys masked.
    case processOutputInvalid(profile: String, program: String, reason: String, stderr: String)
    /// SSO: no sign-in cached by the AWS CLI for this profile's session.
    case ssoNotSignedIn(profile: String)
    /// SSO: the sign-in the AWS CLI cached has expired (or the portal no longer accepts it).
    case ssoExpired(profile: String)
    /// SSO: the portal refused the role, or answered something else.
    case ssoFailed(profile: String, status: Int, message: String)
    /// STS `AssumeRole` refused (its error code and message).
    case stsFailed(profile: String, code: String?, message: String)
    /// STS or the SSO portal couldn't be reached.
    case network(profile: String, message: String)
    /// A response that couldn't be read.
    case invalidResponse(profile: String, detail: String)

    /// The profile the problem is in (for a role, maybe its source profile).
    public var profile: String {
        switch self {
        case let .profileNotFound(p), let .noCredentials(p), let .invalidProfile(p, _), let .needsMFA(p),
             let .unsupportedCredentialSource(p, _), let .unsupported(p, _), let .environmentMissing(p),
             let .invalidCommand(p, _), let .processNotFound(p, _), let .processTimedOut(p, _, _), let .processFailed(p, _, _, _),
             let .processOutputInvalid(p, _, _, _), let .ssoNotSignedIn(p), let .ssoExpired(p), let .ssoFailed(p, _, _),
             let .stsFailed(p, _, _), let .network(p, _), let .invalidResponse(p, _):
            return p
        case let .sourceProfileLoop(chain): return chain.first ?? ""
        }
    }

    /// The command that fixes it in Terminal, when there is one: signing in to SSO again.
    public var fixCommand: String? {
        switch self {
        case let .ssoNotSignedIn(p), let .ssoExpired(p): return "aws sso login --profile \(AWSCredentialError.shellWord(p))"
        default: return nil
        }
    }

    /// Whether running `fixCommand` (a person, in Terminal) is what it takes.
    public var needsSignIn: Bool { fixCommand != nil }

    public var errorDescription: String? { message(chinese: false) }

    /// What the settings, `@doctor` and the logs say.
    public func message(chinese: Bool) -> String {
        func tr(_ zh: String, _ en: String) -> String { chinese ? zh : en }
        switch self {
        case let .profileNotFound(p):
            return tr("找不到 AWS profile '\(p)'（~/.aws/config、~/.aws/credentials）",
                      "AWS profile '\(p)' not found (~/.aws/config, ~/.aws/credentials)")
        case let .noCredentials(p):
            return tr("AWS profile '\(p)' 里没有能拿到凭证的设置（密钥、credential_process、role_arn 或 SSO）",
                      "AWS profile '\(p)' has no credentials: no keys, credential_process, role_arn or SSO settings")
        case let .invalidProfile(p, reason):
            return tr("AWS profile '\(p)' 的设置有问题：\(reason)", "AWS profile '\(p)': \(reason)")
        case let .needsMFA(p):
            return tr("AWS profile '\(p)' 需要 MFA 验证码，输入法没法问你要；请改用 credential_process 或 SSO，或者先用 AWS CLI 缓存好凭证",
                      "AWS profile '\(p)': this profile needs an MFA code; use credential_process or SSO, or run your CLI to cache credentials")
        case let .unsupportedCredentialSource(p, source):
            return tr("AWS profile '\(p)' 用的 credential_source = \(source) 在 Mac 上用不了（\(Self.sourceReason(source, chinese: true))）；只支持 Environment",
                      "AWS profile '\(p)' uses credential_source = \(source), which is unsupported here: \(Self.sourceReason(source, chinese: false)); only Environment is supported")
        case let .unsupported(p, kind):
            return tr("AWS profile '\(p)' 用的是 \(kind)，暂不支持", "AWS profile '\(p)' uses \(kind), which isn't supported")
        case let .sourceProfileLoop(chain):
            return tr("AWS profile 的 source_profile 绕成了圈：\(chain.joined(separator: " → "))",
                      "AWS profiles' source_profile go round in a loop: \(chain.joined(separator: " → "))")
        case let .environmentMissing(p):
            return tr("AWS profile '\(p)' 要用环境变量里的密钥，但 shell 里没有设置 AWS_ACCESS_KEY_ID 和 AWS_SECRET_ACCESS_KEY",
                      "AWS profile '\(p)' takes its keys from the environment, but AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY aren't set in your shell")
        case let .invalidCommand(p, reason):
            return tr("AWS profile '\(p)' 的 credential_process 写得不对：\(reason)", "AWS profile '\(p)': credential_process can't be run: \(reason)")
        case let .processNotFound(p, program):
            return tr("AWS profile '\(p)' 的 credential_process 找不到程序 \(program)（按登录 shell 的 PATH 找）",
                      "AWS profile '\(p)': credential_process program \(program) not found (on your login shell's PATH)")
        case let .processTimedOut(p, program, seconds):
            return tr("AWS profile '\(p)' 的 credential_process（\(program)）\(seconds) 秒没有结束，已停止",
                      "AWS profile '\(p)': credential_process (\(program)) didn't finish in \(seconds) s and was stopped")
        case let .processFailed(p, program, status, stderr):
            let said = stderr.isEmpty ? "" : tr("：", ": ") + stderr
            return tr("AWS profile '\(p)' 的 credential_process（\(program)）失败了（退出码 \(status)）", "AWS profile '\(p)': credential_process (\(program)) failed (exit status \(status))") + said
        case let .processOutputInvalid(p, program, reason, stderr):
            let said = stderr.isEmpty ? "" : tr("；它说：", "; it said: ") + stderr
            return tr("AWS profile '\(p)' 的 credential_process（\(program)）输出的不是 AWS CLI 要的 JSON：\(reason)",
                      "AWS profile '\(p)': credential_process (\(program)) didn't print the JSON the AWS CLI expects: \(reason)") + said
        case let .ssoNotSignedIn(p):
            return tr("AWS profile '\(p)' 还没有 SSO 登录。在终端里运行 `\(fixCommand!)`",
                      "You haven't signed in to SSO for profile \(p). Run `\(fixCommand!)` in Terminal")
        case let .ssoExpired(p):
            return tr("AWS profile '\(p)' 的 SSO 登录已过期。在终端里运行 `\(fixCommand!)`",
                      "Your SSO sign-in for profile \(p) has expired. Run `\(fixCommand!)` in Terminal")
        case let .ssoFailed(p, status, message):
            return tr("AWS profile '\(p)' 的 SSO 没有给凭证（HTTP \(status)）：\(message)",
                      "AWS profile '\(p)': SSO gave no credentials (HTTP \(status)): \(message)")
        case let .stsFailed(p, code, message):
            return tr("AWS profile '\(p)' 切换角色失败（STS \(code ?? "error")）：\(message)",
                      "AWS profile '\(p)': assuming the role failed (STS \(code ?? "error")): \(message)")
        case let .network(p, message):
            return tr("AWS profile '\(p)' 取凭证时连不上 AWS：\(message)", "AWS profile '\(p)': couldn't reach AWS for credentials: \(message)")
        case let .invalidResponse(p, detail):
            return tr("AWS profile '\(p)' 取凭证时 AWS 的回答读不懂：\(detail)", "AWS profile '\(p)': couldn't read AWS's answer for credentials: \(detail)")
        }
    }

    /// One line for the candidate panel: what happened and what to do, short ("SSO sign-in expired: run aws sso login
    /// --profile X").
    public func shortMessage(chinese: Bool) -> String {
        func tr(_ zh: String, _ en: String) -> String { chinese ? zh : en }
        switch self {
        case .ssoExpired: return tr("SSO 登录已过期：运行 \(fixCommand!)", "SSO sign-in expired: run \(fixCommand!)")
        case .ssoNotSignedIn: return tr("还没有 SSO 登录：运行 \(fixCommand!)", "Not signed in to SSO: run \(fixCommand!)")
        default: return message(chinese: chinese)
        }
    }

    static func sourceReason(_ source: String, chinese: Bool) -> String {
        switch source.lowercased() {
        case "ec2instancemetadata":
            return chinese ? "EC2 实例元数据只在 EC2 实例上才有" : "EC2 instance metadata only exists on an EC2 instance, not on a Mac"
        case "ecscontainer":
            return chinese ? "ECS 容器凭证只在 ECS 任务里才有" : "ECS container credentials only exist inside an ECS task, not on a Mac"
        default:
            return chinese ? "不认识这个来源" : "it isn't a known source"
        }
    }

    /// `word` as one word for the shell: as it is when it's plain, else in single quotes.
    public static func shellWord(_ word: String) -> String {
        let plain = !word.isEmpty && word.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || "-_.@+=,/:".unicodeScalars.contains($0)
        }
        return plain ? word : "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

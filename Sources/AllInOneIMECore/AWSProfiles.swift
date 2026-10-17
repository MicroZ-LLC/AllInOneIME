#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Where the AWS CLI's files are: `AWS_CONFIG_FILE` and `AWS_SHARED_CREDENTIALS_FILE` when set (`~` expanded), else
/// `~/.aws/config` and `~/.aws/credentials`, and the SSO sign-ins it caches in `~/.aws/sso/cache`; the home folder is
/// `HOME` when set, as the CLI reads it.
public struct AWSFileLocations: Equatable, Sendable {
    public var config: URL
    public var credentials: URL
    public var ssoCache: URL
    /// Where `credential_process` runs.
    public var home: URL

    public init(config: URL, credentials: URL, ssoCache: URL, home: URL) {
        self.config = config
        self.credentials = credentials
        self.ssoCache = ssoCache
        self.home = home
    }

    public init(environment: [String: String]) {
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? CorePaths.home
        func file(_ variable: String, _ fallback: String) -> URL {
            guard let value = environment[variable], !value.isEmpty else { return home.appendingPathComponent(fallback) }
            if value == "~" { return home }
            return value.hasPrefix("~/") ? home.appendingPathComponent(String(value.dropFirst(2))) : URL(fileURLWithPath: value)
        }
        self.init(config: file("AWS_CONFIG_FILE", ".aws/config"), credentials: file("AWS_SHARED_CREDENTIALS_FILE", ".aws/credentials"),
                  ssoCache: home.appendingPathComponent(".aws/sso/cache", isDirectory: true), home: home)
    }
}

/// The environment variables the AWS settings are read from: the input method's own, else the login shell's
/// (`ShellEnvironment.login`, which reads these too).
public enum AWSEnvironment {
    public static let variables = ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_REGION",
                                   "AWS_DEFAULT_REGION", "AWS_CONFIG_FILE", "AWS_SHARED_CREDENTIALS_FILE"]

    /// `own` (the process's) over `login` (the login shell's), these variables only, and `HOME`.
    public static func merged(own: [String: String], login: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for name in variables {
            if let value = own[name], !value.isEmpty { out[name] = value } else if let value = login[name], !value.isEmpty { out[name] = value }
        }
        if let home = own["HOME"], !home.isEmpty { out["HOME"] = home }
        return out
    }

    /// The keys in `environment`, when both the key ID and the secret are set.
    static func credentials(_ environment: [String: String]) -> AWSCredentials? {
        guard let id = environment["AWS_ACCESS_KEY_ID"], !id.isEmpty,
              let secret = environment["AWS_SECRET_ACCESS_KEY"], !secret.isEmpty else { return nil }
        let token = environment["AWS_SESSION_TOKEN"].flatMap { $0.isEmpty ? nil : $0 }
        return AWSCredentials(accessKeyId: id, secretAccessKey: secret, sessionToken: token)
    }

    static func region(_ environment: [String: String]) -> String? {
        [environment["AWS_REGION"], environment["AWS_DEFAULT_REGION"]].compactMap { $0 }.first { !$0.isEmpty }
    }
}

/// How a profile gets its credentials, as the settings and their checks name it. Nothing secret.
public enum AWSProfileKind: Equatable, Sendable {
    /// `aws_access_key_id` and `aws_secret_access_key` (and maybe `aws_session_token`).
    case staticKeys
    case credentialProcess
    /// `role_arn` assumed with the credentials of `source`: a profile's name, or "Environment" (`credential_source`).
    case role(source: String)
    case sso
    /// "default" with no such profile: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
    case environment
    /// None of the settings that give credentials.
    case noCredentials

    /// "Static keys", "credential_process", "Role via base", "SSO", "Environment variables".
    public func label(language: String) -> String {
        let t = InterfaceWords(language: language)
        switch self {
        case .staticKeys: return t.tr("静态密钥", "Static keys")
        case .credentialProcess: return "credential_process"
        case let .role(source): return t.tr("通过 \(source) 的角色", "Role via \(source)")
        case .sso: return "SSO"
        case .environment: return t.tr("环境变量", "Environment variables")
        case .noCredentials: return t.tr("没有凭证", "No credentials")
        }
    }

    /// `label` in Simplified Chinese or English.
    public func label(chinese: Bool) -> String { label(language: InterfaceLanguage.code(chinese: chinese)) }

    /// Whether its credentials expire and are fetched again (a program, STS, the SSO portal).
    public var refreshes: Bool {
        switch self {
        case .credentialProcess, .role, .sso: return true
        case .staticKeys, .environment, .noCredentials: return false
        }
    }
}

/// A profile as the AWS Profile picker lists it: its name, region and kind. Reading these runs nothing.
public struct AWSProfileSummary: Equatable, Sendable {
    public var name: String
    public var region: String?
    public var kind: AWSProfileKind

    public init(name: String, region: String?, kind: AWSProfileKind) {
        self.name = name
        self.region = region
        self.kind = kind
    }
}

/// The two AWS files, parsed: each profile's settings in the credentials file and in the config file, and the config
/// file's `[sso-session name]` sections. In the config file `[profile name]` is the profile `name` and `[default]` is
/// `default`; another section without the prefix counts as a profile too (as this app read it before), except
/// `[sso-session …]` and `[services …]`. Keys are lowercased; indented lines (nested settings) are skipped.
public struct AWSProfileFiles: Equatable, Sendable {
    public var credentials: [String: [String: String]]
    public var config: [String: [String: String]]
    public var ssoSessions: [String: [String: String]]

    public init(credentials: String?, config: String?) {
        self.credentials = credentials.map { Self.sections($0, isConfig: false).profiles } ?? [:]
        let parsed = config.map { Self.sections($0, isConfig: true) }
        self.config = parsed?.profiles ?? [:]
        self.ssoSessions = parsed?.ssoSessions ?? [:]
    }

    public static func read(_ files: AWSFileLocations) -> AWSProfileFiles {
        AWSProfileFiles(credentials: try? String(contentsOf: files.credentials, encoding: .utf8),
                        config: try? String(contentsOf: files.config, encoding: .utf8))
    }

    /// Every profile's name, "default" first, then by name.
    public var names: [String] {
        Set(credentials.keys).union(config.keys).sorted { a, b in a == "default" ? b != "default" : b == "default" ? false : a < b }
    }

    public func contains(_ profile: String) -> Bool { credentials[profile] != nil || config[profile] != nil }

    /// The profile's settings: the config file's, with the credentials file's over them (as the AWS CLI merges them).
    public func settings(_ profile: String) -> [String: String]? {
        guard contains(profile) else { return nil }
        return (config[profile] ?? [:]).merging(credentials[profile] ?? [:]) { _, fromCredentials in fromCredentials }
    }

    /// The config file's region first, else the credentials file's.
    public func region(_ profile: String) -> String? {
        Self.value(config[profile]?["region"]) ?? Self.value(credentials[profile]?["region"])
    }

    /// The static keys in one file's section of the profile: never a key of one file with the secret or token of the other.
    func staticKeys(_ profile: String, inCredentialsFile: Bool) -> AWSCredentials? {
        guard let section = inCredentialsFile ? credentials[profile] : config[profile],
              let id = Self.value(section["aws_access_key_id"]), let secret = Self.value(section["aws_secret_access_key"]) else { return nil }
        return AWSCredentials(accessKeyId: id, secretAccessKey: secret, sessionToken: Self.value(section["aws_session_token"]))
    }

    /// Whether the profile has any static key setting (botocore's test for a source profile: then its keys are used, not
    /// its role).
    func hasStaticKeys(_ profile: String) -> Bool {
        guard let settings = settings(profile) else { return false }
        return ["aws_access_key_id", "aws_secret_access_key", "aws_session_token"].contains { Self.value(settings[$0]) != nil }
    }

    static func value(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    static func sections(_ text: String, isConfig: Bool) -> (profiles: [String: [String: String]], ssoSessions: [String: [String: String]]) {
        var profiles: [String: [String: String]] = [:], sessions: [String: [String: String]] = [:]
        enum Target { case profile(String), session(String), ignored }
        var current: Target?
        // `[profile default]` wins over `[default]` in the config file, as in the AWS CLI.
        var explicitDefault = false
        for rawLine in text.components(separatedBy: .newlines) {
            if let first = rawLine.first, first == " " || first == "\t" { continue }
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                func after(_ prefix: String) -> String? {
                    guard name.hasPrefix(prefix) else { return nil }
                    let rest = name.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                    return rest.isEmpty ? nil : rest
                }
                if isConfig, let profile = after("profile ") {
                    if profile == "default" {
                        if !explicitDefault { profiles["default"] = [:] }
                        explicitDefault = true
                    }
                    current = .profile(profile)
                } else if isConfig, let session = after("sso-session ") {
                    current = .session(session)
                } else if isConfig, name.hasPrefix("services ") || name == "plugins" {
                    current = .ignored
                } else if isConfig, name == "default", explicitDefault {
                    current = .ignored
                } else {
                    current = name.isEmpty ? .ignored : .profile(name)
                }
                switch current {
                case let .profile(p)? where profiles[p] == nil: profiles[p] = [:]
                case let .session(s)? where sessions[s] == nil: sessions[s] = [:]
                default: break
                }
                continue
            }
            guard let target = current, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            switch target {
            case let .profile(p): profiles[p]?[key] = value
            case let .session(s): sessions[s]?[key] = value
            case .ignored: break
            }
        }
        return (profiles, sessions)
    }
}

/// How one profile's credentials are got: what the resolver does for it, from its settings (`plan`).
enum AWSProfilePlan: Equatable, Sendable {
    case staticKeys(AWSCredentials)
    case environment(AWSCredentials)
    case process(command: String)
    case role(Role)
    case sso(SSO)

    struct Role: Equatable, Sendable {
        enum Source: Equatable, Sendable { case profile(String), environment }
        var roleArn: String
        var source: Source
        var sessionName: String?
        var externalId: String?
        var durationSeconds: Int?
        /// `AWS_REGION` (or `AWS_DEFAULT_REGION`), else the role profile's region: STS is asked there (else us-east-1).
        var region: String?
    }

    struct SSO: Equatable, Sendable {
        var startURL: String
        var region: String
        var accountId: String
        var roleName: String
        /// The session's name (`sso_session`), or the start URL (an older profile): its SHA-1 names the cached sign-in.
        var cacheKey: String
    }

    var kind: AWSProfileKind {
        switch self {
        case .staticKeys: return .staticKeys
        case .environment: return .environment
        case .process: return .credentialProcess
        case let .role(role):
            switch role.source {
            case let .profile(name): return .role(source: name)
            case .environment: return .role(source: "Environment")
            }
        case .sso: return .sso
        }
    }

    /// The profile's plan, in the AWS CLI's (botocore's) order for a named profile: `role_arn` (assume the role), SSO,
    /// static keys in the credentials file, `credential_process`, static keys in the config file. The profile setting
    /// "default" (or empty) takes the environment's keys first, when both are set; a named profile never does.
    /// `asSource`: resolved as a role's `source_profile`: never from the environment, and a profile with static keys
    /// (any of them) isn't assumed as a role itself, as botocore resolves a source (its own keys, a self-reference too).
    static func make(_ profile: String, files: AWSProfileFiles, environment: [String: String], asSource: Bool = false) throws -> AWSProfilePlan {
        let name = profile.isEmpty ? "default" : profile
        if !asSource, name == "default", let keys = AWSEnvironment.credentials(environment) { return .environment(keys) }
        guard let settings = files.settings(name) else { throw AWSCredentialError.profileNotFound(name) }
        func value(_ key: String) -> String? { AWSProfileFiles.value(settings[key]) }
        // 1. A role (not one for web identity, which isn't supported).
        if let roleArn = value("role_arn"), !(asSource && files.hasStaticKeys(name)) {
            if value("web_identity_token_file") != nil { throw AWSCredentialError.unsupported(profile: name, kind: "web_identity_token_file") }
            if value("mfa_serial") != nil { throw AWSCredentialError.needsMFA(profile: name) }
            let sourceProfile = value("source_profile"), credentialSource = value("credential_source")
            let source: Role.Source
            switch (sourceProfile, credentialSource) {
            case let (profile?, nil): source = .profile(profile)
            case let (nil, credential?):
                guard credential.lowercased() == "environment" else {
                    throw AWSCredentialError.unsupportedCredentialSource(profile: name, source: credential)
                }
                source = .environment
            case (_?, _?):
                throw AWSCredentialError.invalidProfile(profile: name, reason: "role_arn has both source_profile and credential_source; keep one")
            case (nil, nil):
                throw AWSCredentialError.invalidProfile(profile: name, reason: "role_arn needs source_profile or credential_source")
            }
            var duration: Int?
            if let text = value("duration_seconds") {
                guard let seconds = Int(text), seconds > 0 else {
                    throw AWSCredentialError.invalidProfile(profile: name, reason: "duration_seconds isn't a number of seconds: \(text)")
                }
                duration = seconds
            }
            return .role(Role(roleArn: roleArn, source: source, sessionName: value("role_session_name"), externalId: value("external_id"),
                              durationSeconds: duration, region: AWSEnvironment.region(environment) ?? files.region(name)))
        }
        // 2. SSO: a profile with an account or a role name for it.
        if value("sso_account_id") != nil || value("sso_role_name") != nil {
            guard let account = value("sso_account_id"), let role = value("sso_role_name") else {
                throw AWSCredentialError.invalidProfile(profile: name, reason: "an SSO profile needs sso_account_id and sso_role_name")
            }
            if let session = value("sso_session") {
                guard let sessionSettings = files.ssoSessions[session] else {
                    throw AWSCredentialError.invalidProfile(profile: name, reason: "sso_session \(session) has no [sso-session \(session)] section")
                }
                func sessionValue(_ key: String) -> String? { AWSProfileFiles.value(sessionSettings[key]) }
                guard let start = sessionValue("sso_start_url"), let region = sessionValue("sso_region") else {
                    throw AWSCredentialError.invalidProfile(profile: name, reason: "[sso-session \(session)] needs sso_start_url and sso_region")
                }
                return .sso(SSO(startURL: start, region: region, accountId: account, roleName: role, cacheKey: session))
            }
            guard let start = value("sso_start_url") else {
                throw AWSCredentialError.invalidProfile(profile: name, reason: "an SSO profile needs sso_session (or sso_start_url)")
            }
            guard let region = value("sso_region") else {
                throw AWSCredentialError.invalidProfile(profile: name, reason: "an SSO profile needs sso_region")
            }
            return .sso(SSO(startURL: start, region: region, accountId: account, roleName: role, cacheKey: start))
        }
        // 3. Static keys in the credentials file, 4. credential_process, 5. static keys in the config file.
        if let keys = files.staticKeys(name, inCredentialsFile: true) { return .staticKeys(keys) }
        if let command = value("credential_process") { return .process(command: command) }
        if let keys = files.staticKeys(name, inCredentialsFile: false) { return .staticKeys(keys) }
        if value("sso_session") != nil || value("sso_start_url") != nil {
            throw AWSCredentialError.invalidProfile(profile: name, reason: "an SSO profile needs sso_account_id and sso_role_name")
        }
        if value("web_identity_token_file") != nil { throw AWSCredentialError.unsupported(profile: name, kind: "web_identity_token_file") }
        throw AWSCredentialError.noCredentials(profile: name)
    }

    /// What the cached credentials depend on: the profile's own settings (and its SSO session's), never kept as text.
    static func fingerprint(_ profile: String, files: AWSProfileFiles) -> String {
        var parts = (files.settings(profile) ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        if let session = files.settings(profile)?["sso_session"], let settings = files.ssoSessions[session] {
            parts += settings.sorted { $0.key < $1.key }.map { "sso-session.\($0.key)=\($0.value)" }
        }
        return SHA256.hash(data: Data(parts.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

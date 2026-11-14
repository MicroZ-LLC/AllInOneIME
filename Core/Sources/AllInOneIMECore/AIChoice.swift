import Foundation

/// The AI (Settings → AI): one choice among every way the input method reaches a model, grouped by how it connects
/// (`Group`): a coding agent's CLI on this Mac with the user's own subscription (`cli`: its session answers `@question`,
/// `ClaudeSessionManager`), an API key, a cloud service, or Apple's on-device model (`provider`). In the config it is
/// two keys (`Config.ai`): `questionBackend` names the CLI (this Mac's own, never synced: whether one is installed and
/// signed in is this Mac's), else the AI is `provider`. With a CLI chosen `provider` stays as it was: what has to be
/// fast goes there (`Config.fastProvider`).
public enum AIChoice: Hashable, Sendable {
    /// A CLI on this Mac (Claude Code, Codex, Antigravity, Kiro CLI), signed in with its own account.
    case cli(SessionAgent)
    /// An API-key provider, a cloud service, or Apple's on-device model.
    case provider(Provider)

    /// How a choice connects: the groups of Settings → AI, in this order.
    public enum Group: String, CaseIterable, Sendable {
        case subscription, apiKey, cloud, onDevice

        public var title: String {
            switch self {
            case .subscription: return tr("用你的订阅", "With your subscription")
            case .apiKey: return tr("用 API Key", "With an API key")
            case .cloud: return tr("云服务", "Cloud services")
            case .onDevice: return tr("本机", "On this Mac", key: "ai.group.onDevice")
            }
        }

        /// What the group's choices have in common, after its title.
        public var note: String {
            switch self {
            case .subscription: return tr("本机装的 CLI，不用 API Key", "A CLI installed on this Mac, no API key")
            case .apiKey: return tr("按用量付费", "Pay as you go")
            case .cloud: return tr("公司账号常用", "Common with work accounts")
            case .onDevice: return tr("不出这台 Mac", "Nothing leaves this Mac")
            }
        }
    }

    /// Every choice, in the order Settings lists them: each group's, the groups in order.
    public static let all: [AIChoice] = QuestionBackend.sessionAgents.map(AIChoice.cli)
        + [Provider.anthropic, .openai, .gemini, .bedrock, .hosted, .apple].map(AIChoice.provider)

    /// The choices Settings offers, by group (a group with none left out): AllInOneIME Cloud once the service is set up
    /// (`hosted`), Apple's model on a system that has it (`apple`), and `current` whatever they say, so that the one in
    /// use is always there.
    public static func groups(hosted: Bool = HostedService.isConfigured, apple: AppleModelAvailability,
                              keeping current: AIChoice? = nil) -> [(group: Group, choices: [AIChoice])] {
        let offered = all.filter { choice in
            if choice == current { return true }
            switch choice {
            case .provider(.hosted): return hosted
            case .provider(.apple): return apple.isOffered
            default: return true
            }
        }
        return Group.allCases.compactMap { group in
            let choices = offered.filter { $0.group == group }
            return choices.isEmpty ? nil : (group, choices)
        }
    }

    /// Its value where a choice is written as text (the settings document): the CLI's `QuestionBackend` ("claudeSession"),
    /// the provider's own ("bedrock"), as the config file has them.
    public var id: String {
        switch self {
        case let .cli(agent): return QuestionBackend(agent).rawValue
        case let .provider(provider): return provider.rawValue
        }
    }

    /// The choice an `id` names, nil for none (and for "provider", which names no choice: `QuestionBackend.provider`).
    public init?(id: String) {
        if let agent = QuestionBackend(rawValue: id)?.agent {
            self = .cli(agent)
        } else if let provider = Provider(rawValue: id) {
            self = .provider(provider)
        } else {
            return nil
        }
    }

    public var group: Group {
        switch self {
        case .cli: return .subscription
        case .provider(.anthropic), .provider(.openai), .provider(.gemini): return .apiKey
        case .provider(.bedrock), .provider(.hosted): return .cloud
        case .provider(.apple): return .onDevice
        }
    }

    /// The CLI, nil for a provider.
    public var agent: SessionAgent? {
        if case let .cli(agent) = self { return agent }
        return nil
    }

    /// The provider, nil for a CLI.
    public var provider: Provider? {
        if case let .provider(provider) = self { return provider }
        return nil
    }

    /// Its name on its card: "Claude Code", "Claude API", "Apple on-device".
    public var name: String {
        switch self {
        case let .cli(agent): return agent.displayName
        case .provider(.openai): return tr("OpenAI 兼容", "OpenAI-compatible")
        case .provider(.apple): return tr("Apple 本机", "Apple on-device")
        case let .provider(provider): return provider.displayName
        }
    }

    /// The line under the chosen one's name (Settings → AI, collapsed): how a CLI connects, then its `status`.
    public func detail(_ status: AIStatus) -> String {
        guard case .cli = self else { return status.text }
        return tr("通过本机 CLI，用你自己的订阅", "Through the CLI on this Mac, with your own subscription") + " · " + status.text
    }
}

/// What a choice's card says of it (Settings → AI), from what this Mac has (`AIFacts`): a CLI signed in, signed out, not
/// installed or unable to start; an API key added or not; Bedrock's AWS profile and region; AllInOneIME Cloud signed in
/// or not; Apple's model available or why not. `isReady`: it has what it needs to answer (a request may still fail: the
/// network, a model the account can't use); the fast fallback goes by it (`Config.fastProvider`).
public enum AIStatus: Equatable, Sendable {
    /// Not looked at yet (a CLI's sign-in is looked at as Settings shows it).
    case unknown
    case signedIn
    case signedOut
    /// The CLI's `program` isn't on this Mac.
    case notInstalled(program: String)
    /// The CLI's session couldn't be used when a question was asked (`ClaudeSession.Availability.cannotStart`): it
    /// ended before it started, it couldn't be kept to the web, or its program couldn't be launched.
    case cannotStart
    /// An API key: saved, in the shell, or none (`KeyState`).
    case key(KeyState)
    /// Bedrock: the AWS profile, and the region requests go to.
    case aws(profile: String, region: String)
    /// Bedrock: no such AWS profile on this Mac.
    case noAWSProfile(String)
    /// Bedrock: the AWS profile has nothing to sign a request with (`AWSProfileKind.noCredentials`).
    case noAWSCredentials(String)
    /// Apple's on-device model.
    case apple(AppleModelAvailability)

    public var isReady: Bool {
        switch self {
        case .signedIn, .aws: return true
        case let .key(state): return state.isSet
        case let .apple(availability): return availability == .available
        case .unknown, .signedOut, .notInstalled, .cannotStart, .noAWSProfile, .noAWSCredentials: return false
        }
    }

    /// Not ready for a reason the user can do something about (drawn in orange): neither ready nor still to be looked at.
    public var isProblem: Bool {
        switch self {
        case .unknown, .key(.loading): return false
        default: return !isReady
        }
    }

    /// The line on the card: "已登录", "没装", "没填 Key", "default · us-west-2", "可用".
    public var text: String {
        switch self {
        case .unknown, .key(.loading): return tr("正在查看…", "Checking…")
        case .signedIn: return tr("已登录", "Signed in")
        case .signedOut: return tr("没登录", "Not signed in")
        case .notInstalled: return tr("没装", "Not installed", key: "ai.status.notInstalled")
        case .cannotStart: return tr("启动不了", "Can't start")
        case .key(.saved): return tr("已填 Key", "Key added")
        case let .key(.shell(name)): return tr("用 $\(name)", "Uses $\(name)")
        case .key: return tr("没填 Key", "No key")
        case let .aws(profile, region): return profile + " · " + region
        case .noAWSProfile: return tr("没有这个 AWS profile", "No such AWS profile")
        case let .noAWSCredentials(profile): return profile + " · " + tr("没有凭证", "No credentials")
        case .apple(.available): return tr("可用", "Ready", key: "ai.status.ready")
        case let .apple(availability): return UIText.reason(availability)
        }
    }
}

/// What this Mac has, for each choice's status (`status`): each CLI's sign-in (`ClaudeSessionManager.availability`),
/// the API keys (`KeyState`, by provider: never the keys themselves), whether AllInOneIME Cloud is signed in to, the AWS
/// profiles with their regions and kinds (`AWSCredentialResolver.requestProfiles`), and Apple's model.
public struct AIFacts: Equatable, Sendable {
    public var sessions: [SessionAgent: ClaudeSession.Availability]
    public var keys: [Provider: KeyState]
    public var hostedSignedIn: Bool
    /// The AWS profiles, each with its region and kind (`AWSCredentialResolver.requestProfiles`); nil: not read yet.
    public var awsProfiles: [AWSProfileSummary]?
    public var apple: AppleModelAvailability

    public init(sessions: [SessionAgent: ClaudeSession.Availability] = [:], keys: [Provider: KeyState] = [:],
                hostedSignedIn: Bool = false, awsProfiles: [AWSProfileSummary]? = nil,
                apple: AppleModelAvailability = .unsupportedSystem) {
        self.sessions = sessions
        self.keys = keys
        self.hostedSignedIn = hostedSignedIn
        self.awsProfiles = awsProfiles
        self.apple = apple
    }

    /// What `choice`'s card says with `config` (its AWS profile and region).
    public func status(_ choice: AIChoice, config: Config) -> AIStatus {
        switch choice {
        case let .cli(agent):
            switch sessions[agent] ?? .unknown {
            case .ready: return .signedIn
            case .signedOut: return .signedOut
            case .notInstalled: return .notInstalled(program: agent.program)
            case .cannotStart: return .cannotStart
            case .unknown: return .unknown
            }
        case .provider(.anthropic), .provider(.gemini), .provider(.openai):
            return .key(keys[choice.provider!] ?? .loading)
        case .provider(.hosted):
            return hostedSignedIn ? .signedIn : .signedOut
        case .provider(.bedrock):
            // Ready only with credentials a request can be signed with, as the client finds them (not just a region).
            guard let awsProfiles else { return .unknown }
            guard let profile = awsProfiles.first(where: { $0.name == config.awsProfile }) else { return .noAWSProfile(config.awsProfile) }
            guard profile.kind.canAuthenticate else { return .noAWSCredentials(config.awsProfile) }
            return .aws(profile: config.awsProfile, region: Self.region(config.region) ?? profile.region ?? "us-east-1")
        case .provider(.apple):
            return .apple(apple)
        }
    }

    /// Whether `provider` has what it needs to answer (`AIStatus.isReady`).
    public func isReady(_ provider: Provider, config: Config) -> Bool { status(.provider(provider), config: config).isReady }

    /// A region set in the settings, nil for none (or blank).
    static func region(_ region: String?) -> String? {
        guard let region = region?.trimmingCharacters(in: .whitespaces), !region.isEmpty else { return nil }
        return region
    }
}

extension Config {
    /// The AI chosen (Settings → AI, `AIChoice`): the CLI `questionBackend` names, else `provider`. Choosing a CLI keeps
    /// `provider` as it is (the fast fallback, `fastProvider`); choosing a provider sets it and forgets the CLI. Every
    /// provider's settings and keys stay whatever is chosen. A file from before (no `questionBackend`, or "provider", the
    /// earlier choice of the provider) is on its provider, as it always was.
    public var ai: AIChoice {
        get { questionSessionAgent.map(AIChoice.cli) ?? .provider(provider) }
        set {
            switch newValue {
            case let .cli(agent):
                questionBackend = QuestionBackend(agent)
            case let .provider(chosen):
                provider = chosen
                questionBackend = nil
            }
        }
    }

    /// Where what has to be fast goes (rewriting, translating, replies, custom prompt commands, autocomplete: a CLI
    /// takes a second or more to answer): with a provider chosen, that provider. With a CLI chosen, the provider set up
    /// before (`provider`, when `ready` says it has what it needs: a key, an AWS profile with credentials, a sign-in),
    /// else Apple's on-device model when it is `available`; nil when neither can: autocomplete is off then, and the rest
    /// goes to the CLI's session.
    public func fastProvider(ready: (Provider) -> Bool, apple: AppleModelAvailability) -> Provider? {
        guard case .cli = ai else { return provider }
        if provider != .apple, ready(provider) { return provider }
        return apple == .available ? .apple : nil
    }

    /// `fastProvider` by what `facts` say.
    public func fastProvider(_ facts: AIFacts) -> Provider? {
        fastProvider(ready: { facts.isReady($0, config: self) }, apple: facts.apple)
    }
}

extension AIChoice {
    /// What Settings says under a CLI chosen (`cli`), with its fast fallback (`Config.fastProvider`): that the questions go
    /// to it and what goes elsewhere.
    public static func fallbackNote(_ fast: Provider?) -> String {
        let note: String
        if let fast {
            let name = AIChoice.provider(fast).name
            note = tr("@question 走 CLI（要 1 秒以上）；改写、翻译、续写这些要快的，自动用「\(name)」。",
                      "@question goes to the CLI (a second or more); what has to be fast (rewriting, translating, autocomplete) uses \(name).")
        } else {
            note = tr("@question 走 CLI（要 1 秒以上）；没有更快的 AI，续写关闭，改写、翻译也走它，会慢一些。",
                      "@question goes to the CLI (a second or more); with no faster AI, autocomplete is off, and rewriting and translating go to it too, more slowly.")
        }
        return UIText.triggered(note)
    }
}

import Foundation

/// A problem to report (`@reportissue`, the input menu's "Report an Issue…", Settings → About): GitHub's page for
/// a new issue on the app's repository, opened in the browser with its title and a body filled in. The user reads
/// it there and clicks Submit (or doesn't): no account or key of theirs is used, and nothing is sent by the input
/// method itself.
///
/// The body asks what happened and what was expected, and carries a few diagnostics (`Diagnostics`): versions, the
/// languages, which kind of AI provider (and a public model by its id, `publicModel`, else "custom") and the action
/// key, and how many commands of each kind there are. Nothing personal: no file paths, no text typed but the title,
/// no keys, profile names or addresses, no names of the user's commands, plugins or extensions. `lines` is what the panel shows before the page is opened.
public struct IssueReport: Equatable, Sendable {
    /// Where new issues are written.
    public static let newIssueAddress = "https://github.com/MicroZ-LLC/AllInOneIME/issues/new"
    /// The longest address made: GitHub answers 414 (URI too long) past about 8000 characters, and browsers vary;
    /// the diagnostics are cut first, then the title. (No `labels`: GitHub answers 404 when the user may not label
    /// issues, as anyone outside the project may not.)
    public static let maxURLLength = 6000
    /// The longest title kept, in Characters (GitHub's own limit is 256).
    public static let maxTitleLength = 200

    /// What the report says about this Mac and the settings. Each value is what may be shown; `init(config:…)`
    /// picks them from the settings, leaving out anything personal.
    public struct Diagnostics: Equatable, Sendable {
        public var appVersion: String
        /// "26.1" (macOS's version).
        public var macOS: String
        /// "arm64" (Apple silicon) or "x86_64" (Intel), with " (Rosetta)" for an Intel build on Apple silicon.
        public var architecture: String
        /// "en", "zh", or "system (en)" when it follows the system.
        public var interfaceLanguage: String
        /// Codes, in order: ["en", "zh"].
        public var inputLanguages: [String]
        /// The installed language packs with their versions: ["zh-pinyin 1.0.0"].
        public var languagePacks: [String]
        /// The provider's kind ("bedrock", "anthropic", …), always, and its model: a public model's id as it is
        /// (`publicModel`), else "custom"; nil when none is set.
        public var provider: String
        public var model: String?
        /// "enter", "optionTap", … or the name of a recorded key ("⌃⏎").
        public var actionKey: String
        public var customCommands: Int
        public var plugins: Int
        public var extensions: Int

        public init(appVersion: String, macOS: String, architecture: String, interfaceLanguage: String,
                    inputLanguages: [String], languagePacks: [String], provider: String, model: String?, actionKey: String,
                    customCommands: Int, plugins: Int, extensions: Int) {
            self.appVersion = appVersion
            self.macOS = macOS
            self.architecture = architecture
            self.interfaceLanguage = interfaceLanguage
            self.inputLanguages = inputLanguages
            self.languagePacks = languagePacks
            self.provider = provider
            self.model = model
            self.actionKey = actionKey
            self.customCommands = customCommands
            self.plugins = plugins
            self.extensions = extensions
        }

        /// From the settings and what the app knows of itself: only the kinds and counts above. The custom commands
        /// are counted, never named; the profile, region, base addresses and folders are left out; a model by its id
        /// only when it's a public model's (`publicModel`), else "custom".
        public init(config: Config, appVersion: String = AppVersion.string, macOS: String, architecture: String,
                    interfaceLanguage: String, languagePacks: [String], plugins: Int, extensions: Int) {
            let actionKey: String
            switch config.actionKey {
            // A recorded key's name is the app's own ("⌃⏎", "F5"), from the keys pressed.
            case let .shortcut(key): actionKey = key.name.count <= 16 ? key.name : "shortcut"
            default: actionKey = config.actionKey.rawName ?? "-"
            }
            self.init(appVersion: appVersion, macOS: macOS, architecture: architecture, interfaceLanguage: interfaceLanguage,
                      inputLanguages: config.inputLanguages.map(\.rawValue), languagePacks: languagePacks,
                      provider: config.provider.rawValue,
                      model: config.provider == .hosted || config.provider == .apple ? nil : config.settings(for: config.provider).model.map { IssueReport.publicModel($0) ?? "custom" },
                      actionKey: actionKey, customCommands: config.customCommands.count, plugins: plugins, extensions: extensions)
        }
    }

    /// One line, without control characters, at most `maxTitleLength` (the text after `@reportissue`).
    public var title: String
    public var diagnostics: Diagnostics

    public init(title: String, diagnostics: Diagnostics) {
        self.title = Self.oneLine(title)
        self.diagnostics = diagnostics
    }

    /// The diagnostics as the body lists them, and as the panel shows them first.
    public var lines: [String] {
        let d = diagnostics
        return [
            "AllInOneIME: \(d.appVersion)",
            "macOS: \(d.macOS) (\(d.architecture))",
            "Interface language: \(d.interfaceLanguage)",
            "Input languages: " + (d.inputLanguages.isEmpty ? "-" : d.inputLanguages.joined(separator: ", ")),
            "Language packs: " + (d.languagePacks.isEmpty ? "none" : d.languagePacks.joined(separator: ", ")),
            "AI provider: \(d.provider)" + (d.model.map { " (\($0))" } ?? ""),
            "Action key: \(d.actionKey)",
            "Custom commands: \(d.customCommands), plugins: \(d.plugins), extensions: \(d.extensions)",
        ]
    }

    /// The issue's text: what happened and what was expected (for the user to write), then `lines`, or as many of
    /// them as fit (`url`).
    public func body(lines: [String]) -> String {
        """
        ### What happened

        <!-- What did you type or do, and what went wrong? A screenshot helps. -->


        ### What you expected



        ### Diagnostics

        <!-- Added by AllInOneIME: no text you typed, no paths, keys or names of your commands. -->
        \(lines.map { "- " + $0 }.joined(separator: "\n"))
        """
    }

    /// The new-issue page with the title and the body in it, no longer than `maxURLLength`: diagnostics are cut
    /// from the end first ("- …" says so), then the title.
    public var url: URL {
        var kept = lines, title = self.title, cut = false
        func address() -> String {
            Self.newIssueAddress + "?title=" + LinkTemplate.encode(title)
                + "&body=" + LinkTemplate.encode(body(lines: cut ? kept + ["…"] : kept))
        }
        var made = address()
        while made.count > Self.maxURLLength, !kept.isEmpty {
            kept.removeLast()
            cut = true
            made = address()
        }
        while made.count > Self.maxURLLength, !title.isEmpty {
            title = String(title.dropLast(max(1, title.count / 4)))
            made = address()
        }
        return URL(string: made)!  // percent-encoded: always a valid address
    }

    /// `title` as one line: line breaks and tabs are spaces, other control characters go, the ends are trimmed, and
    /// it's cut to `maxTitleLength`.
    static func oneLine(_ text: String) -> String {
        let scalars = text.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            if CharacterSet.newlines.contains(scalar) || scalar == "\t" { return " " }
            return scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .format ? nil : scalar
        }
        let line = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
        return String(line.prefix(maxTitleLength))
    }

    /// A model's id as it may go in a report, nil when it isn't a public model's (it's then "custom"). Allow-listed as a
    /// whole, not filtered: every part of the name must be known.
    /// - At most a known vendor before it: "anthropic/", "meta-llama/" (OpenRouter, Hugging Face), Bedrock's
    ///   "[region.]vendor." ("us.anthropic.").
    /// - The name: a known family ("claude", "gpt", "llama3.1": a family and its version run together), then parts
    ///   between "-" or "_", each a version, size or date ("4o", "3.8", "v1", "70b", "128k", "20251001", "k2"), a single
    ///   letter, or a known word ("mini", "flash", "haiku", "instruct", "latest" …: `modelWords`).
    /// - At most one tag after a colon: a number (Bedrock's ":0"), a size (":8b"), ":latest" or ":free".
    ///
    /// A fine-tuned model ("ft:…:acmecorp:…"), an ARN (an account, a profile's id), or any name with a part of its own
    /// ("gpt-4o-acmecorp-prod", "claude-acme-support", "o3-contoso-eastus") is "custom".
    public static func publicModel(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 80, value.allSatisfy({ $0.isASCII }) else { return nil }
        var rest = Substring(value.lowercased())
        if let colon = rest.firstIndex(of: ":") {
            let tag = String(rest[rest.index(after: colon)...])
            guard tag == "latest" || tag == "free" || tag.allSatisfy(\.isNumber) && !tag.isEmpty || isSize(tag) else { return nil }
            rest = rest[..<colon]
        }
        if let slash = rest.firstIndex(of: "/") {
            guard knownVendors.contains(String(rest[..<slash])) else { return nil }
            rest = rest[rest.index(after: slash)...]
        } else {
            let parts = rest.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3, bedrockRegions.contains(String(parts[0])), knownVendors.contains(String(parts[1])) {
                rest = parts[2]
            } else if parts.count >= 2, knownVendors.contains(String(parts[0])) {
                rest = rest[rest.index(rest.startIndex, offsetBy: parts[0].count + 1)...]
            }
        }
        let tokens = rest.split(separator: "-", omittingEmptySubsequences: false).flatMap { $0.split(separator: "_", omittingEmptySubsequences: false) }
        guard let first = tokens.first, !tokens.contains(where: \.isEmpty),
              let family = knownFamilies.filter({ first.hasPrefix($0) }).max(by: { $0.count < $1.count }) else { return nil }
        let version = first.dropFirst(family.count)
        guard version.isEmpty || isVersion(String(version)) else { return nil }
        guard tokens.dropFirst().allSatisfy({ isVersion(String($0)) || $0.count == 1 && $0.first!.isLetter || modelWords.contains(String($0)) })
        else { return nil }
        return value
    }

    /// A version, size or date: "4o", "3.8", "2.5", "v1", "k2", "r1", "70b", "0.5b", "128k", "a3b", "20251001", "2407", "8x7b".
    static func isVersion(_ token: String) -> Bool {
        token.range(of: #"^[a-z]?[0-9]+(\.[0-9]+)*[a-z]?$"#, options: .regularExpression) != nil
            || token.range(of: #"^[0-9]+x[0-9]+b$"#, options: .regularExpression) != nil
    }

    /// A model's size as a tag: "8b", "0.5b", "70b".
    static func isSize(_ tag: String) -> Bool { tag.range(of: #"^[0-9]+(\.[0-9]+)?[bm]$"#, options: .regularExpression) != nil }

    /// The words public models' names are made of, after their family.
    static let modelWords: Set<String> = [
        "mini", "nano", "micro", "tiny", "small", "medium", "large", "pro", "plus", "max", "ultra", "lite", "light", "flash",
        "turbo", "instruct", "chat", "latest", "preview", "exp", "experimental", "haiku", "sonnet", "opus", "coder", "code",
        "codex", "reasoner", "reasoning", "vision", "thinking", "base", "it", "omni", "audio", "realtime", "search", "long",
        "air", "oss", "luna", "embed", "embedding", "nemo", "saba", "versatile", "instant", "fast", "high", "low", "distill",
        "online", "image", "tts", "transcribe", "hf", "moe", "vl", "math", "next", "premier", "edge", "maverick", "scout",
    ]

    /// Public model vendors, as they prefix an id ("anthropic/claude-…", "us.anthropic.claude-…").
    static let knownVendors: Set<String> = [
        "anthropic", "openai", "google", "meta", "meta-llama", "mistral", "mistralai", "deepseek", "deepseek-ai", "qwen", "x-ai",
        "xai", "moonshotai", "z-ai", "zhipuai", "thudm", "cohere", "microsoft", "nvidia", "amazon", "ai21", "perplexity", "writer",
        "minimax", "baidu", "bytedance", "tencent", "01-ai", "nousresearch", "openrouter",
    ]
    /// Bedrock's cross-region prefixes ("us.anthropic.claude-…").
    static let bedrockRegions: Set<String> = ["us", "eu", "apac", "global", "jp", "au", "ca", "us-gov"]
    /// Public model families, as an id starts.
    static let knownFamilies: [String] = [
        "claude", "gpt", "chatgpt", "o1", "o3", "o4", "gemini", "gemma", "llama", "codellama", "mistral", "mixtral", "codestral",
        "ministral", "magistral", "devstral", "pixtral", "deepseek", "qwen", "qwq", "kimi", "moonshot", "glm", "chatglm", "grok",
        "command", "phi", "nova", "titan", "jamba", "palmyra", "sonar", "yi", "ernie", "doubao", "hunyuan", "minimax", "abab",
        "baichuan", "step", "hermes", "auto",
    ]
}

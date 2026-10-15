import Foundation

/// A problem to report (`@reportissue`, the input menu's "Report an Issue…", Settings → About): GitHub's page for
/// a new issue on the app's repository, opened in the browser with its title and a body filled in. The user reads
/// it there and clicks Submit (or doesn't): no account or key of theirs is used, and nothing is sent by the input
/// method itself.
///
/// The body asks what happened and what was expected, and carries a few diagnostics (`Diagnostics`): versions, the
/// languages, which kind of AI provider and the action key, and how many commands of each kind there are. Nothing
/// personal: no file paths, no text typed but the title, no keys, profile names or addresses, no names of the
/// user's commands, plugins or extensions. `lines` is what the panel shows before the page is opened.
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
        /// The provider's kind ("bedrock", "anthropic", …) and its model, if one may be shown (`safe`).
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
        /// are counted, never named; the profile, region, base addresses and folders are left out; a model only as
        /// `safe` lets it be.
        public init(config: Config, appVersion: String = AppVersion.string, macOS: String, architecture: String,
                    interfaceLanguage: String, languagePacks: [String], plugins: Int, extensions: Int) {
            let actionKey: String
            switch config.actionKey {
            case let .shortcut(key): actionKey = IssueReport.safe(key.name) ?? "shortcut"
            default: actionKey = config.actionKey.rawName ?? "-"
            }
            self.init(appVersion: appVersion, macOS: macOS, architecture: architecture, interfaceLanguage: interfaceLanguage,
                      inputLanguages: config.inputLanguages.map(\.rawValue), languagePacks: languagePacks,
                      provider: config.provider.rawValue,
                      model: config.provider == .hosted ? nil : config.settings(for: config.provider).model.flatMap(IssueReport.safe),
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

    /// A value from the settings as it may go in a report (a model's name, a key's): nil when it may say something
    /// about the user. A path ("/Users/…", "~/…", "file:"), an address or an email (with "@" or "://"), what looks
    /// like a key ("sk-…", "AKIA…", a long run of letters and digits) or anything long is left out; an AWS ARN keeps
    /// its model and region, its account number cut ("arn:aws:bedrock:us-west-2:…:inference-profile/us.anthropic.…").
    public static func safe(_ value: String) -> String? {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 120 else { return nil }
        if value.hasPrefix("arn:") {
            var parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            if parts.count > 4 { parts[4] = "…" }
            value = parts.joined(separator: ":")
        }
        if value.hasPrefix("/") || value.hasPrefix("~") || value.lowercased().hasPrefix("file:") || value.contains("://")
            || value.contains("@") || value.contains("\\") { return nil }
        let lower = value.lowercased()
        if lower.hasPrefix("sk-") || lower.hasPrefix("sk_") || value.hasPrefix("AKIA") || value.hasPrefix("ASIA")
            || value.hasPrefix("AIza") || lower.hasPrefix("ghp_") || lower.hasPrefix("xox") { return nil }
        // A long run without separators is more likely a token than a model's name.
        let runs = value.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if runs.contains(where: { $0.count >= 24 }) { return nil }
        // Twelve digits in a row: an AWS account number.
        if runs.contains(where: { $0.count >= 12 && $0.allSatisfy(\.isNumber) }) { return nil }
        return value
    }
}

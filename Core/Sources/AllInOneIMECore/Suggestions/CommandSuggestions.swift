import Foundation

/// A custom command of type `suggestions` as a completion source (spec Suggestions v1, decision 24): read by the rules of
/// a plugin's `completions` entry, its program's arguments for its list and its queries, and the editor's insert presets.
extension CustomCommand {
    /// The command as a completion source: its keys read as a plugin's `completions` entry's are
    /// (`CompletionDeclaration`, docs/plugins.md: the same limits, defaults and reasons), with what a custom command adds:
    /// a prefix is required (no source without one), the list is always on (its program run with no input), and
    /// `timeoutSeconds` is 20 at most (a list must load within that). Its name is its own in small letters; its title, its
    /// summary (else its name). A refusal says why it isn't used, as Settings shows it. Nil: not a `suggestions` command.
    public var suggestionSource: Result<CompletionSource, CompletionRefusal>? {
        guard type == .suggestions else { return nil }
        let name = name.lowercased()
        guard let prefix, !prefix.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure(CompletionRefusal(name: name, reason: "a suggestions command needs a prefix"))
        }
        typealias JSON = AIConfig.JSONValue
        let summary = (self.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: JSON] = ["name": .string(name), "title": .string(summary.isEmpty ? name : summary),
                                      "prefix": .string(prefix), "list": .bool(true)]
        if let minChars { fields["minChars"] = .number(Double(minChars)) }
        if let compare { fields["compare"] = .string(compare) }
        if let refresh { fields["refresh"] = .string(refresh) }
        if let query { fields["query"] = .bool(query) }
        if let queryMinChars { fields["queryMinChars"] = .number(Double(queryMinChars)) }
        if let insert { fields["insert"] = insert }
        let read = CompletionDeclaration.read(.array([.object(fields)]), type: .script, timeoutSeconds: timeout)
        if let source = read.sources.first { return .success(source) }
        return .failure(read.refused.first ?? CompletionRefusal(name: name, reason: "not a suggestion source"))
    }

    /// What keeps a `suggestions` command from being saved, for the editors (`problem(among:)`): its prefix (none, not
    /// one, or the magic key `trigger` at its start), its timeout, its templates, then whatever else the source's rules
    /// refuse (a value out of range, from config.json).
    func suggestionProblem(trigger: String) -> Problem? {
        guard let prefix = prefix.flatMap(CompletionDeclaration.prefix) else { return .badPrefix }
        if String(prefix.first!) == trigger { return .prefixIsMagicKey(trigger) }
        if timeout > PluginManifest.maxTimeout { return .timeoutTooLong }
        if case .failure = CompletionDeclaration.insert(insert) { return .badTemplate }
        if case let .failure(refusal)? = suggestionSource { return .suggestions(refusal.reason) }
        return nil
    }

    /// How long its query may take: 3 seconds, or its `timeoutSeconds` if less (a list takes `timeout`).
    public var queryTimeout: Double { min(timeout, 3) }

    /// The program and its arguments for its list (`query` nil: no input, an argument that is only `{input}` left out,
    /// the placeholder taken out of the others) or for a query: `query` in place of `{input}` where argv writes it (each
    /// argument stays one: no shell unless argv starts one), else as the last argument. The program (`argv[0]`) as it is.
    public func suggestionArguments(query text: String?) -> [String] {
        guard let argv, let program = argv.first else { return [] }
        let arguments = argv.dropFirst()
        guard let text else {
            return [program] + arguments.filter { $0 != Self.placeholder }.map { $0.replacingOccurrences(of: Self.placeholder, with: "") }
        }
        guard arguments.contains(where: { $0.contains(Self.placeholder) }) else { return argv + [text] }
        return [program] + arguments.map { $0.replacingOccurrences(of: Self.placeholder, with: text) }
    }

    /// What the editor's Insert offers (`insert`): the match alone, with its title, or (in chat apps) its link too. Any
    /// other `insert` is the user's own templates (Advanced).
    public enum InsertPreset: String, CaseIterable, Sendable {
        /// "Just the match": `{arg}` (the default, written as none).
        case match
        /// "With its title": `{arg} {title}`, `{arg}` for an item without one.
        case title
        /// "With title and link": as `title`, and in chat apps `{arg} {title} {url}` (`{arg} {title}`, `{arg}` for an
        /// item without them).
        case titleAndLink

        /// Its `insert`, as config.json writes it (nil: the default's).
        public var insert: AIConfig.JSONValue? {
            typealias JSON = AIConfig.JSONValue
            let titled: JSON = .array([.string("{arg} {title}"), .string("{arg}")])
            switch self {
            case .match: return nil
            case .title: return .object(["default": titled])
            case .titleAndLink:
                return .object(["default": titled,
                                "chat": .array([.string("{arg} {title} {url}"), .string("{arg} {title}"), .string("{arg}")])])
            }
        }

        /// The preset `insert` is (the same rows in every class of app, however written); nil: none of them.
        public init?(_ insert: AIConfig.JSONValue?) {
            guard let read = Self.rows(insert), let preset = Self.allCases.first(where: { Self.rows($0.insert) == read }) else {
                return nil
            }
            self = preset
        }

        /// What `insert` puts in per class of app: its templates in ordinary and chat apps, and whether there are rows in
        /// terminals (any template is `{match}` there).
        private static func rows(_ insert: AIConfig.JSONValue?) -> [CompletionInsert.Templates]? {
            guard case let .success(read) = CompletionDeclaration.insert(insert) else { return nil }
            let terminal = read.terminal ?? read.default
            return [read.default, read.chat ?? read.default, terminal == .off ? .off : .templates(["{match}"])]
        }
    }
}

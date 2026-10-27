import Foundation

/// A command typed at the start of a draft, e.g. "@question 量子计算是什么". The action key then
/// runs it on the rest of the draft. Without one, nothing is sent: the input method just types.
/// The built-in commands come first; the user's own (`Config.customCommands`) and script extensions
/// (`ScriptCommand`) follow them (`catalog`).
public struct Command: Hashable, Sendable {
    public let name: String
    public let kind: Kind
    /// The user's definition, for a command from the config (nil for the built-in ones).
    public let custom: CustomCommand?
    /// The installed plugin, for a command from one.
    public let plugin: InstalledPlugin?
    /// The script extension, for a command from one (a `.run` command).
    public let script: ScriptCommand?
    /// The extension bundle a snippet comes from (`ExtensionIndex.snippets`): its name ("team"); nil for every other
    /// command, a snippet of the config's too.
    public let bundle: String?
    /// A snippet's text, read (`SnippetTemplate`): `custom.text`. Nil for every other command.
    public let snippet: SnippetTemplate?

    public enum Kind: Equatable, Sendable {
        /// The improve conversion (versions and rewrites).
        case convert
        /// One text written by the model from the input (`Prompt.commandRequest`).
        case generate
        /// A program run in a terminal window with the input.
        case terminal
        /// A Spotlight search; picking a result opens it.
        case search
        /// A program run in the background with the input; what it prints can be inserted.
        case run
        /// The background Claude Code tasks (`@tasks`): picking one opens it.
        case agents
        /// Opens the settings window (`@settings`), right when it is picked.
        case settings
        /// The text is saved to Apple Notes; nothing is inserted.
        case note
        /// A reminder for Apple Reminders, its time read from the text (`ReminderParser`): shown to
        /// confirm, then added; nothing is inserted.
        case reminder
        /// Opens a web address with the text in it (`LinkTemplate`) in the browser; nothing is inserted.
        case link
        /// Sends the text to someone picked in the panel (`@imessage`), after the user confirms it.
        case message
        /// Opens GitHub's page for a new issue with the text as its title and a few diagnostics (`IssueReport`),
        /// shown in the panel first; nothing is sent or inserted.
        case report
        /// Inserts a saved text (`custom.text`, `SnippetTemplate`) with its placeholders filled: no AI, no program.
        case snippet
    }

    init(name: String, kind: Kind, custom: CustomCommand? = nil, plugin: InstalledPlugin? = nil, script: ScriptCommand? = nil,
         bundle: String? = nil) {
        self.name = name
        self.kind = kind
        self.custom = custom
        self.plugin = plugin
        self.script = script
        self.bundle = bundle
        snippet = kind == .snippet ? SnippetTemplate.parse(custom?.text ?? "") : nil
    }

    /// What a snippet's row in the command list says: its summary, or else the start of its text (at most
    /// `rowTextLength` characters, line breaks as "↵"). Nil for every other command.
    public var snippetRowText: String? {
        guard kind == .snippet, let custom else { return nil }
        if let summary = custom.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty { return summary }
        let text = (custom.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let line = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ↵ ")
        return line.count > Self.rowTextLength ? String(line.prefix(Self.rowTextLength)) + "…" : line
    }

    public static let rowTextLength = 40

    /// Polish in the sentence's own language, with the rewrite styles (`WritingMode.improve`).
    public static let improve = Command(name: "improve", kind: .convert)
    /// Translate into the output languages the user added (`WritingMode.translate`); written together
    /// with `@improve`, one request does both.
    public static let translate = Command(name: "translate", kind: .convert)
    /// Answer a question; the answer can be inserted.
    public static let question = Command(name: "question", kind: .generate)
    /// Three replies to the message being answered (selected, copied, or a screenshot pasted with ⌃V), in the other
    /// party's language and the app's tone; what is typed after it says what to reply (`ReplyContext`, Reply.swift).
    public static let reply = Command(name: "reply", kind: .generate)
    /// Hand the text to the coding agent picked in Settings (`Config.agent`: Claude Code, Gemini CLI, Kiro CLI or a
    /// custom one), in Terminal with the text as its first message (long work, conversations); nothing is inserted.
    public static let agent = Command(name: "agent", kind: .terminal)
    /// Find files and apps by name (Spotlight) or path, as you type, and open the one picked.
    public static let open = Command(name: "open", kind: .search)

    /// A web page's title and text (`WebReader`), mostly inside another command's text as context:
    /// `@question 总结一下 @read https://…`.
    public static let read = Command(name: "read", kind: .run)
    /// Save the text to Apple Notes (a folder named "AllInOneIME").
    public static let note = Command(name: "note", kind: .note)
    /// Add a reminder to Apple Reminders (a list named "AllInOneIME"), with the time written in the text:
    /// `@reminder 明天下午3点给张三打电话`.
    public static let reminder = Command(name: "reminder", kind: .reminder)

    /// Python code (`InlineCode`): the value of its last expression, or what it prints, can be inserted:
    /// `@py 2**100`. It runs with the user's `python3`.
    public static let py = Command(name: "py", kind: .run)
    /// JavaScript code, the same way: `@js [1, 2, 3].map(x => x * 2)`. It runs in the platform's JavaScript
    /// (JavaScriptCore on the Mac, QuickJS-ng off Apple platforms), in this app's own child process (no files,
    /// programs or network).
    public static let js = Command(name: "js", kind: .run)

    /// `@search`: a web search with the user's own key (`WebSearch`). On its own, a list of the top
    /// results to insert; inside another command's text, their titles, snippets and addresses as context:
    /// `@question 用一句话总结 @search 苹果发布会`.
    public static let webSearch = Command(name: "search", kind: .run)

    /// The background tasks `@agent` started (Claude Code's): how they're doing and what they replied.
    public static let tasks = Command(name: "tasks", kind: .agents)

    /// The settings window.
    public static let settings = Command(name: "settings", kind: .settings)

    /// Send an iMessage: pick the recipient in the panel, write the message, confirm it in the panel.
    public static let imessage = Command(name: "imessage", kind: .message)

    /// Report a problem: GitHub's page for a new issue, the text its title, with the versions and settings that
    /// help (`IssueReport`); the user submits it there.
    public static let reportIssue = Command(name: "reportissue", kind: .report)

    /// The text selected in the field, rewritten as an instruction says: `@improve` or `@translate` on a selection with
    /// something typed after them ("@translate ja", "@improve more formal"), or on a selection of several lines (the
    /// writing commands' answer has a line per version). One answer, which replaces the selection (`Prompt.editSystem`).
    /// Never offered in the list: the composer starts it (`Composer.selection`).
    public static let edit = Command(name: "edit", kind: .generate)

    /// `@reply` after the first five: the list opens on the ones it always had.
    public static let builtins: [Command] = [.improve, .translate, .question, .agent, .open, .reply, .read, .note, .reminder,
                                             .py, .js, .webSearch, .tasks, .settings, .imessage, .reportIssue]

    /// Built-ins that are off for now: left out of `catalog` (what the input method offers), their names
    /// still taken; their code and tests stay. `@search` (Brave Search with the user's own key) and
    /// `@read` (a web page's text): `@open` opens web addresses, which is enough. Take one out of here to
    /// bring it back (with `@search`, its settings come back too).
    public static let off: [Command] = [.webSearch, .read]

    public static var webSearchOffered: Bool { !off.contains(.webSearch) }

    /// `@py`, `@js`: the text is code to run (`InlineCode`), used exactly as typed: other commands in it
    /// don't run, so nothing they return (a web page, a program's output) is ever executed.
    public var isCode: Bool { self == .py || self == .js }

    /// Its text goes to code or a program the user wrote: `@py`, `@js`, a custom `run` command, a script
    /// extension. None of it runs inside another command's text unless typed there (`Composer`: not from a paste,
    /// dictation or a restored draft), and other commands don't run inside its text.
    public var runsCode: Bool { isCode || (custom != nil || script != nil) && kind == .run }

    /// The text after the command is typed as Latin letters (file names, paths, code): picking the
    /// command switches the engine to English, and Chinese comes back when the command is done.
    public var typesLatin: Bool { self == .open || self == .read || isCode || custom?.typesLatin == true || plugin?.manifest.typesLatin == true }

    /// `program(agent:)` with Claude Code as the agent.
    public var program: String? { program(agent: .claude) }

    /// The program this command needs on the Mac: the agent's for `@agent` (`AgentKind.program`; `agentCommand` is a
    /// custom agent's), `python3` for `@py`, `argv[0]` for a custom `run` or `terminal` command, the app that sends for a
    /// send command (an absolute ".app" path); nil when it needs none.
    public func program(agent: AgentKind, custom agentCommand: [String] = []) -> String? {
        if self == .agent { return agent.program(custom: agentCommand) }
        if self == .py { return InlineCode.python }
        if self == .imessage { return "/System/Applications/Messages.app" }
        guard let custom, custom.type == .run || custom.type == .terminal else { return nil }
        return custom.argv?.first
    }

    /// A `link` command's address, with `{input}` (`LinkTemplate`).
    public var linkTemplate: String? {
        guard kind == .link else { return nil }
        return custom?.url ?? plugin?.manifest.url
    }

    /// The built-in commands, then the installed plugins, then the user's valid ones
    /// (`CustomCommand.isValid`) whose names are still free, in the order of the config, then the script
    /// extensions (`ExtensionIndex.commands`: a bundle's, a single script's, a Raycast script's) likewise, one
    /// whose name is taken under its `alias` if that's free. When names clash, built-in > plugin > custom >
    /// extension; a plugin or custom command hidden by a built-in is logged (`logHidden`), an extension's
    /// shows in Settings (`hiddenScripts`). The bundles' snippets (`ExtensionIndex.snippets`) are extensions too: after
    /// the bundles' commands, before single scripts and Raycast's.
    /// What is no @ command takes its name all the same, so that no other command changes name with it, and isn't
    /// offered: a custom command of type `suggestions` (used by its prefix alone, its source read from the config:
    /// `SuggestionsSettings.commands`), and a plugin or script extension with suggestions taken out of the list
    /// (`hidden`: `Config.hiddenFromCommandList`, `hidesFromCommandList`), its suggestions as they were.
    public static func catalog(_ custom: [CustomCommand], plugins: [InstalledPlugin] = [],
                               scripts: [ScriptCommand] = [], snippets: [BundleSnippet] = [], hidden: [String] = []) -> [Command] {
        let builtinNames = Set(builtins.map(\.name))
        var taken = builtinNames
        let fromPlugins = plugins.compactMap { plugin -> Command? in
            guard taken.insert(plugin.name).inserted else {
                if builtinNames.contains(plugin.name) { logHidden("plugin", plugin.name) }
                return nil
            }
            if plugin.hidesFromCommandList(hidden) { return nil }
            switch plugin.manifest.type {
            case .script:
                return Command(name: plugin.name, kind: .run, plugin: plugin)
            case .prompt:
                // An AI instruction: the request is built like a custom prompt command's.
                let definition = CustomCommand(name: plugin.name, type: .prompt, summary: plugin.manifest.summary?.en,
                                               prompt: plugin.manifest.prompt, ascii: plugin.manifest.ascii)
                return Command(name: plugin.name, kind: .generate, custom: definition, plugin: plugin)
            case .link:
                return Command(name: plugin.name, kind: .link, plugin: plugin)
            }
        }
        // A built-in that's off isn't offered, but its name stays taken.
        let offered = builtins.filter { !off.contains($0) }
        let all = offered + fromPlugins + custom.compactMap { definition in
            let name = definition.name.lowercased()
            guard definition.isValid, taken.insert(name).inserted else {
                if definition.isValid, builtinNames.contains(name) { logHidden("custom command", name) }
                return nil
            }
            let kind: Kind
            switch definition.type {
            case .prompt: kind = .generate
            case .run: kind = .run
            case .terminal: kind = .terminal
            case .link: kind = .link
            case .snippet: kind = .snippet
            case .suggestions: return nil
            }
            return Command(name: name, kind: kind, custom: definition)
        } + extensionTier(scripts, snippets).compactMap { item in
            switch item {
            case let .script(script):
                guard let name = script.names.first(where: { taken.insert($0).inserted }), !script.hidesFromCommandList(hidden) else {
                    return nil
                }
                return Command(name: name, kind: .run, script: script)
            case let .snippet(snippet):
                return snippet.names.first { taken.insert($0).inserted }.map {
                    Command(name: $0, kind: .snippet, custom: snippet.definition, bundle: snippet.bundle)
                }
            }
        }
        // Without child processes (iOS, Android) the commands that run a program aren't offered.
        return Platform.current.processes.canLaunch ? all : all.filter { !$0.needsChildProcess }
    }

    /// An extension in the order its names are given out: the bundles' commands, their snippets, then the rest.
    private enum Extension {
        case script(ScriptCommand)
        case snippet(BundleSnippet)

        var names: [String] {
            switch self {
            case let .script(script): return script.names
            case let .snippet(snippet): return snippet.names
            }
        }
    }

    private static func extensionTier(_ scripts: [ScriptCommand], _ snippets: [BundleSnippet]) -> [Extension] {
        guard !snippets.isEmpty else { return scripts.map(Extension.script) }
        let bundled = scripts.prefix { $0.source.bundleName != nil }
        return bundled.map(Extension.script) + snippets.map(Extension.snippet) + scripts.dropFirst(bundled.count).map(Extension.script)
    }

    /// It runs a program in a child process (`ProcessLauncher`): `@py`, `@js`, a custom `run` command, a script
    /// extension, a plugin's script.
    public var needsChildProcess: Bool {
        isCode || kind == .run && (custom != nil || script != nil || plugin != nil)
    }

    /// The extensions `catalog` leaves out because another command has their name (and alias), and which.
    public static func hiddenScripts(_ scripts: [ScriptCommand], custom: [CustomCommand], plugins: [InstalledPlugin] = [],
                                     snippets: [BundleSnippet] = []) -> [(script: ScriptCommand, owner: ScriptCommand.Owner)] {
        hiddenExtensions(scripts, custom: custom, plugins: plugins, snippets: snippets).scripts
    }

    /// The bundles' snippets `catalog` leaves out because other commands have their name and alias, and which.
    public static func hiddenSnippets(_ snippets: [BundleSnippet], scripts: [ScriptCommand], custom: [CustomCommand],
                                      plugins: [InstalledPlugin] = []) -> [(snippet: BundleSnippet, owner: ScriptCommand.Owner)] {
        hiddenExtensions(scripts, custom: custom, plugins: plugins, snippets: snippets).snippets
    }

    private static func hiddenExtensions(_ scripts: [ScriptCommand], custom: [CustomCommand], plugins: [InstalledPlugin],
                                         snippets: [BundleSnippet])
        -> (scripts: [(script: ScriptCommand, owner: ScriptCommand.Owner)], snippets: [(snippet: BundleSnippet, owner: ScriptCommand.Owner)]) {
        var owners: [String: ScriptCommand.Owner] = [:]
        for command in builtins { owners[command.name] = .builtIn }
        for plugin in plugins where owners[plugin.name] == nil { owners[plugin.name] = .plugin }
        for definition in custom where definition.isValid && owners[definition.name.lowercased()] == nil {
            owners[definition.name.lowercased()] = .custom
        }
        var hidden: [(script: ScriptCommand, owner: ScriptCommand.Owner)] = []
        var hiddenSnippets: [(snippet: BundleSnippet, owner: ScriptCommand.Owner)] = []
        for item in extensionTier(scripts, snippets) {
            let owner: ScriptCommand.Owner
            switch item {
            case let .script(script): owner = .command(script.id)
            case let .snippet(snippet): owner = .snippet(snippet.id)
            }
            if let free = item.names.first(where: { owners[$0] == nil }) {
                owners[free] = owner
            } else if let owner = owners[item.names[0]] {
                switch item {
                case let .script(script): hidden.append((script, owner))
                case let .snippet(snippet): hiddenSnippets.append((snippet, owner))
                }
            }
        }
        return (hidden, hiddenSnippets)
    }

    private static let catalogLog = CoreLog(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "commands")
    private static let loggedHidden = Locked(initialState: Set<String>())

    /// A plugin or custom command a built-in one hides (say a custom "@note" from before @note was built in):
    /// logged once per process, with no UI. The catalog is made on most keystrokes, hence once. The name is
    /// the built-in's, so it may be logged.
    private static func logHidden(_ kind: String, _ name: String) {
        guard loggedHidden.withLock({ $0.insert(kind + " " + name).inserted }) else { return }
        catalogLog.notice("\(kind) @\(name) is hidden: a built-in command has that name")
    }

    /// The draft's command and the text after it: "@question 量子计算" → (.question, "量子计算").
    /// Nil without a known command (the "@" must be first, the name followed by a space).
    public static func parse(_ draft: String, in commands: [Command] = builtins,
                             trigger: String = "@") -> (command: Command, content: String)? {
        guard draft.hasPrefix(trigger), let space = draft.firstIndex(of: " ") else { return nil }
        let name = draft[draft.index(after: draft.startIndex)..<space].lowercased()
        guard let command = commands.first(where: { $0.name == name }) else { return nil }
        return (command, String(draft[draft.index(after: space)...]))
    }

    /// Commands whose name starts with `prefix` (case-insensitive), in catalog order.
    public static func matching(_ prefix: String, in commands: [Command] = builtins) -> [Command] {
        let prefix = prefix.lowercased()
        return commands.filter { $0.name.hasPrefix(prefix) }
    }
}

// MARK: - Show in the @ list

// A plugin or script extension command with suggestions can be taken out of the command list (Settings → Commands,
// "Show in the @ list" under it, on by default), its suggestions as they are: kept in `Config.hiddenFromCommandList` by
// a plugin's name or a command's id (`ScriptCommand.id`, which has a "/": never a plugin's name). Only while it has a
// suggestion source: one that has none any more is in the list again, whatever the config says. A custom command of
// type `suggestions` is never in it, and a built-in always is.

extension InstalledPlugin {
    /// It has a suggestion source: its plugin.json declares completions that were read (not only refused ones).
    public var hasSuggestions: Bool { !manifest.completions.isEmpty }

    /// Left out of the command list (`Command.catalog`): it has suggestions and its name is in `hidden`.
    public func hidesFromCommandList(_ hidden: [String]) -> Bool { hasSuggestions && hidden.contains(name) }
}

extension ScriptCommand {
    /// It has a suggestion source: a completion it declares that was read (not refused).
    public var hasSuggestions: Bool {
        if case .success? = completion { return true }
        return false
    }

    /// Left out of the command list (`Command.catalog`): it has suggestions and its id is in `hidden`.
    public func hidesFromCommandList(_ hidden: [String]) -> Bool { hasSuggestions && hidden.contains(id) }
}

extension Config {
    /// Whether the plugin or script extension command `id` (a plugin's name, a command's id) is shown in the command list
    /// as far as "Show in the @ list" goes (`hiddenFromCommandList`): what its switch shows.
    public func showsInCommandList(_ id: String) -> Bool { !hiddenFromCommandList.contains(id) }

    /// "Show in the @ list" for `id` turned on (taken off `hiddenFromCommandList`) or off (put on it once).
    public mutating func setShownInCommandList(_ id: String, _ shown: Bool) {
        hiddenFromCommandList.removeAll { $0 == id }
        if !shown { hiddenFromCommandList.append(id) }
    }
}

/// A command the user added in the config (`customCommands`), e.g.
///
///     { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"] }
///
/// - `prompt`: the text goes to the model with `prompt` as the instruction; the answer can be inserted.
/// - `run`: `argv` runs in the background (no shell) with `{input}` replaced by the text, or the text
///   on standard input (`stdin`); what it prints can be inserted.
/// - `terminal`: `argv` runs in a new Terminal window; nothing is inserted.
/// - `link`: `url` (with `{input}` in its query) opens in the browser with the text in it; nothing is
///   inserted (`LinkTemplate`): `{ "name": "google", "type": "link", "url": "https://www.google.com/search?q={input}" }`.
/// - `snippet`: `text` is inserted, its placeholders filled (`SnippetTemplate`); no AI, no program:
///   `{ "name": "sig", "type": "snippet", "summary": "Email signature", "text": "Best,\nWei\n{cursor}" }`.
/// - `suggestions`: a suggestion source, as a plugin's `completions` entry is (spec Suggestions v1, decision 24): typing
///   `prefix` in any text field shows rows of what `argv` prints (its list, run with no input; with `query`, also run
///   with what follows the prefix), Tab inserts one (`suggestionSource`, CommandSuggestions.swift). It is no @ command:
///   never in the command list, its name after the magic key a word like any other (`Command.catalog`); its name is a
///   custom command's all the same, unique among them, the built-ins' and the plugins':
///   `{ "name": "jira", "type": "suggestions", "summary": "Jira issues", "prefix": "JIRA-", "argv": ["jira-list"] }`.
///
/// `{input}` always stays inside the one argument it is written in: the text is never parsed by a
/// shell unless `argv` itself says so (`["zsh", "-c", "{input}"]`).
public struct CustomCommand: Codable, Hashable, Sendable {
    public enum CommandType: String, Codable, Sendable {
        case prompt, run, terminal, link, snippet, suggestions
    }

    /// Letters only, as typed after "@" (digits pick from the command list).
    public var name: String
    public var type: CommandType
    /// Shown next to the name in the command list.
    public var summary: String?
    /// `prompt`: the instruction for the model.
    public var prompt: String?
    /// `run`, `terminal`, `suggestions`: the program and its arguments. A program without a "/" is looked up in the
    /// user's shell PATH.
    public var argv: [String]?
    /// `run`: what goes to the program's standard input (`{input}` is replaced); nil: nothing.
    public var stdin: String?
    /// Type the text as Latin letters (code, paths). Default: true for `run` and `terminal`.
    public var ascii: Bool?
    /// `run`, `suggestions`: the program is stopped after this many seconds (default 10; a source's 20 at most, its
    /// query's 3).
    public var timeoutSeconds: Double?
    /// Its icon in the command list: an SF Symbol name ("chart.bar"), and a color (a system color's
    /// name, "blue", or "#RRGGBB"); unset, one for its type.
    public var icon: String?
    public var color: String?
    /// `link`: the web address, with `{input}` in its query (`LinkTemplate`).
    public var url: String?
    /// `snippet`: the text it inserts, with its placeholders (`SnippetTemplate`).
    public var text: String?
    /// `suggestions`: what a plugin's `completions` entry declares by these names, with its rules, limits and defaults
    /// (docs/plugins.md, `CompletionDeclaration`; read as a source by `suggestionSource`), kept as config.json writes
    /// them so that one that breaks a rule is refused with its reason (Settings shows it) rather than unreadable:
    /// `prefix` the text a token starts with ("JIRA-"; required, not the magic key), `minChars` how many characters after
    /// it before rows show (1), `compare` "prefix" or "exact" ("prefix"), `refresh` how often the list is run again
    /// ("5m"…"7d", "1h"), `query` whether the program is also run with what follows the prefix (false), `queryMinChars`
    /// from how many characters on (3), `insert` what a row inserts per app class (`{"default": "{arg}"}`;
    /// `InsertPreset`).
    public var prefix: String?
    public var minChars: Int?
    public var compare: String?
    public var refresh: String?
    public var query: Bool?
    public var queryMinChars: Int?
    public var insert: AIConfig.JSONValue?

    public init(name: String, type: CommandType, summary: String? = nil, prompt: String? = nil,
                argv: [String]? = nil, stdin: String? = nil, ascii: Bool? = nil, timeoutSeconds: Double? = nil,
                icon: String? = nil, color: String? = nil, url: String? = nil, text: String? = nil,
                prefix: String? = nil, minChars: Int? = nil, compare: String? = nil, refresh: String? = nil,
                query: Bool? = nil, queryMinChars: Int? = nil, insert: AIConfig.JSONValue? = nil) {
        self.name = name
        self.type = type
        self.summary = summary
        self.prompt = prompt
        self.argv = argv
        self.stdin = stdin
        self.ascii = ascii
        self.timeoutSeconds = timeoutSeconds
        self.icon = icon
        self.color = color
        self.url = url
        self.text = text
        self.prefix = prefix
        self.minChars = minChars
        self.compare = compare
        self.refresh = refresh
        self.query = query
        self.queryMinChars = queryMinChars
        self.insert = insert
    }

    public static let placeholder = "{input}"
    public static let defaultTimeout: Double = 10

    /// A name of letters (what the command list can type), and what its type needs.
    public var isValid: Bool {
        guard !name.isEmpty, name.count <= 24, name.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        switch type {
        case .prompt: return !(prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .run, .terminal: return !(argv?.first ?? "").isEmpty
        case .link: return LinkTemplate.problem(url) == nil
        case .snippet: return Self.snippetProblem(text) == nil
        case .suggestions: return !(argv?.first ?? "").isEmpty && (try? suggestionSource?.get()) != nil
        }
    }

    /// What keeps a snippet's text from being used: blank, or `{cursor}` twice.
    static func snippetProblem(_ text: String?) -> Problem? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .emptyText }
        return SnippetTemplate.parse(text).cursorCount > 1 ? .twoCursors : nil
    }

    public var typesLatin: Bool { ascii ?? Self.typesLatinByDefault(type) }

    /// Programs take code and paths, typed as Latin letters; the AI and web pages take text as typed.
    public static func typesLatinByDefault(_ type: CommandType) -> Bool { type == .run || type == .terminal }

    public var timeout: Double { max(timeoutSeconds ?? Self.defaultTimeout, 0.1) }

    /// `argv` with `{input}` replaced in each argument (each stays one argument).
    public func arguments(for input: String) -> [String] {
        let text = typesLatin ? Self.halfWidth(input) : input
        return (argv ?? []).map { $0.replacingOccurrences(of: Self.placeholder, with: text) }
    }

    /// What goes to standard input, if anything.
    public func standardInput(for input: String) -> String? {
        let text = typesLatin ? Self.halfWidth(input) : input
        return stdin.map { $0.replacingOccurrences(of: Self.placeholder, with: text) }
    }

    /// Full-width punctuation a Chinese keyboard layout types, as the ASCII that code means by it:
    /// `print（“牛逼”）` → `print("牛逼")`. Letters and Chinese text stay as they are.
    public static func halfWidth(_ text: String) -> String {
        let map: [Character: String] = [
            "（": "(", "）": ")", "【": "[", "】": "]", "「": "\"", "」": "\"", "『": "'", "』": "'",
            "“": "\"", "”": "\"", "‘": "'", "’": "'", "，": ",", "。": ".", "：": ":", "；": ";",
            "！": "!", "？": "?", "《": "<", "》": ">", "、": "\\", "～": "~", "｜": "|", "＝": "=",
            "＋": "+", "－": "-", "＊": "*", "／": "/", "＃": "#", "＄": "$", "％": "%", "＆": "&",
            "＠": "@", "｛": "{", "｝": "}", "［": "[", "］": "]", "＜": "<", "＞": ">", "…": "...",
            "·": "`", "　": " ",
        ]
        return String(text.flatMap { map[$0].map(Array.init) ?? [$0] })
    }
}

extension CustomCommand {
    /// Its name as Settings shows it: after the magic key (`@issues`), except a Suggestions command's, which is no @
    /// command (0.6.8): used by its prefix, it is shown by its name alone.
    public func shownName(trigger: String) -> String { type == .suggestions ? name : trigger + name }

    /// What keeps a definition from being saved, for the settings' editor.
    public enum Problem: Equatable, Sendable {
        case emptyName
        /// Only letters can be typed after "@" (digits pick from the command list).
        case nameNotLetters
        /// A built-in command, or another custom one, has this name.
        case nameTaken
        case emptyPrompt
        case emptyCommand
        /// A quote in the command line isn't closed.
        case unbalancedQuote
        /// A `link` command's address can't be used.
        case link(LinkTemplate.Problem)
        /// A snippet without text.
        case emptyText
        /// A snippet with `{cursor}` more than once.
        case twoCursors
        /// A suggestion source without a prefix, or with one that isn't 1–16 letters, digits or . _ - # (not starting
        /// with @).
        case badPrefix
        /// A suggestion source whose prefix starts with the magic key (`Config.commandTrigger`), which opens the command
        /// list there.
        case prefixIsMagicKey(String)
        /// A suggestion source's `insert` with a template that isn't one (a `{` not closed).
        case badTemplate
        /// A suggestion source stopped after more seconds than a list may take (`PluginManifest.maxTimeout`).
        case timeoutTooLong
        /// Anything else the rules of a source refuse (a value out of range in config.json): the reason, as for a
        /// plugin's completion entry (`CompletionRefusal.reason`, in English).
        case suggestions(String)
    }

    /// The first problem with this definition among `others` (the other custom commands), the installed plugins'
    /// names and `unread` (the names of the custom commands a later version wrote: `Config.unreadCustomCommandNames`),
    /// or nil; a suggestion source's prefix also may not start with `trigger`, the magic key.
    public func problem(among others: [CustomCommand], plugins: [String] = [], unread: [String] = [],
                        trigger: String = "@") -> Problem? {
        let name = name.lowercased()
        if name.isEmpty { return .emptyName }
        if !name.allSatisfy({ $0.isASCII && $0.isLetter }) || name.count > 24 { return .nameNotLetters }
        if Command.builtins.contains(where: { $0.name == name }) || plugins.contains(name)
            || others.contains(where: { $0.name.lowercased() == name }) || unread.contains(where: { $0.lowercased() == name }) {
            return .nameTaken
        }
        switch type {
        case .prompt:
            if (prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyPrompt }
        case .run, .terminal:
            if (argv?.first ?? "").isEmpty { return .emptyCommand }
        case .link:
            if let problem = LinkTemplate.problem(url) { return .link(problem) }
        case .snippet:
            if let problem = Self.snippetProblem(text) { return problem }
        case .suggestions:
            if (argv?.first ?? "").isEmpty { return .emptyCommand }
            if let problem = suggestionProblem(trigger: trigger) { return problem }
        }
        return nil
    }

    // MARK: Editing the list by name

    // Settings edits and deletes a command by the name it had when the editor or the Delete dialog opened, never by its
    // place in the list: sync through iCloud may change the list meanwhile (another Mac deleted or added one), and a
    // place would then be another command's, or none.

    /// The commands of `list` other than the one named `original` (the one being edited; nil: one being added), names
    /// matched ignoring case: what an edit's name is checked against (`problem(among:)`).
    public static func others(than original: String?, in list: [CustomCommand]) -> [CustomCommand] {
        guard let original = original?.lowercased() else { return list }
        return list.filter { $0.name.lowercased() != original }
    }

    /// `list` with `command` saved: in place of the one named `original` wherever it is now, else (added, or deleted
    /// elsewhere meanwhile) at the end. Nil when another command has its name by now.
    /// Of two of one name (only a config edited by hand has them), the one that is `shown` (the command as the editor
    /// or the Delete dialog opened on it) when it is still there, else the first.
    public static func saving(_ command: CustomCommand, as original: String?, in list: [CustomCommand],
                              shown: CustomCommand? = nil) -> [CustomCommand]? {
        let name = command.name.lowercased()
        guard !others(than: original, in: list).contains(where: { $0.name.lowercased() == name }) else { return nil }
        var out = list
        if let original, let index = index(of: original, shown: shown, in: out) {
            out[index] = command
        } else {
            out.append(command)
        }
        return out
    }

    /// `list` without the command named `name` (ignoring case): one only, of two of that name the one `shown` when it
    /// is still there (see `saving`); as it is when there is none by now.
    public static func removing(_ name: String, from list: [CustomCommand], shown: CustomCommand? = nil) -> [CustomCommand] {
        guard let index = index(of: name, shown: shown, in: list) else { return list }
        var out = list
        out.remove(at: index)
        return out
    }

    /// Where the command named `name` (ignoring case) is in `list`: `shown` if it is there under that name, else the
    /// first of that name.
    static func index(of name: String, shown: CustomCommand?, in list: [CustomCommand]) -> Int? {
        let name = name.lowercased()
        if let shown, shown.name.lowercased() == name, let index = list.firstIndex(of: shown) { return index }
        return list.firstIndex { $0.name.lowercased() == name }
    }

    /// How a command line is written and split into arguments: as the Mac's command editor does it, or as a Windows
    /// program reads its own, where `\` separates a path's folders (`C:\Tools\run.exe`) rather than escaping.
    public enum LineRules: Sendable {
        /// A shell's words without its syntax: spaces separate them, "…" and '…' quote, \ escapes the next character.
        case shell
        /// `CommandLineToArgvW`'s: spaces and tabs separate the arguments, "…" quotes, and a backslash is itself
        /// except before a `"` (2n of them and a `"` are n and a quote that opens or closes; 2n + 1 are n and a `"`).
        /// The program, first, is read as Windows reads a program's path: to the next space, or in quotes to the
        /// next `"`, its backslashes as they are.
        case windows

        /// The rules of the system the settings are made for: what a window there shows and sends is its line.
        public init(_ platform: SettingsPlatform) { self = platform == .windows ? .windows : .shell }
    }

    /// Arguments as one line, quoted where needed: ["python3", "-c", "{input}"] → `python3 -c {input}`. With `.windows`,
    /// an argument with a space, a tab or a `"` (or none at all) in quotes, its `"` and the backslashes before one
    /// escaped; a path's backslashes as they are: `C:\Tools\run.exe "C:\My Files\a.txt"`.
    public static func commandLine(_ argv: [String], rules: LineRules = .shell) -> String {
        guard rules == .windows else {
            return argv.map { arg in
                guard arg.isEmpty || arg.contains(where: { " \t\"'\\".contains($0) }) else { return arg }
                return "\"" + arg.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
            }.joined(separator: " ")
        }
        return argv.enumerated().map { index, arg in
            let plain = !arg.isEmpty && !arg.unicodeScalars.contains { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\u{0B}" || $0 == "\"" }
            if plain { return arg }
            // The program: in quotes as it is (a file name has no `"`).
            if index == 0 { return "\"" + arg + "\"" }
            var out = "\""
            var backslashes = 0
            for scalar in arg.unicodeScalars {
                if scalar == "\\" {
                    backslashes += 1
                } else {
                    // n backslashes before a `"` become 2n + 1: the `"` escaped.
                    if scalar == "\"" { out += String(repeating: "\\", count: backslashes + 1) }
                    backslashes = 0
                }
                out.unicodeScalars.append(scalar)
            }
            // n backslashes before the closing `"` become 2n.
            return out + String(repeating: "\\", count: backslashes) + "\""
        }.joined(separator: " ")
    }

    /// A command line split into arguments (`rules`; by default the Mac's): spaces separate them, "…" and '…' quote, \
    /// escapes the next character. No other shell syntax: `;`, `|`, `$` are plain text. Nil if a quote isn't closed.
    public static func arguments(fromCommandLine line: String, rules: LineRules = .shell) -> [String]? {
        if rules == .windows { return windowsArguments(line) }
        var args: [String] = []
        var current = ""
        var inArgument = false
        var quote: Character?
        var escaped = false
        for c in line {
            if escaped {
                current.append(c)
                escaped = false
                continue
            }
            if c == "\\", quote != "'" {
                escaped = true
                inArgument = true
                continue
            }
            if let q = quote {
                if c == q { quote = nil } else { current.append(c) }
                continue
            }
            if c == "\"" || c == "'" {
                quote = c
                inArgument = true
            } else if c == " " || c == "\t" {
                if inArgument { args.append(current) }
                current = ""
                inArgument = false
            } else {
                current.append(c)
                inArgument = true
            }
        }
        if quote != nil || escaped { return nil }
        if inArgument { args.append(current) }
        return args
    }

    /// `line` split as `CommandLineToArgvW` splits it (Wine's reading of it, which Windows' own agrees with): the
    /// program to the first space or tab, or in quotes to the next `"`; then the arguments, where three `"` in a row in
    /// quotes are a `"`. Unlike it, a line of blanks is no argument (not the program's own path), the blanks before the
    /// program are skipped, and a quote not closed is nil, as with the Mac's rules.
    private static func windowsArguments(_ line: String) -> [String]? {
        func isBlank(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" }
        var rest = Array(line.unicodeScalars)[...]
        while let c = rest.first, isBlank(c) { rest = rest.dropFirst() }
        guard !rest.isEmpty else { return [] }
        var program = String.UnicodeScalarView()
        if rest.first == "\"" {
            rest = rest.dropFirst()
            var closed = false
            while let c = rest.popFirst() {
                if c == "\"" {
                    closed = true
                    break
                }
                program.append(c)
            }
            guard closed else { return nil }
        } else {
            while let c = rest.first, !isBlank(c) {
                program.append(c)
                rest = rest.dropFirst()
            }
        }
        var args = [String(program)]
        while let c = rest.first, isBlank(c) { rest = rest.dropFirst() }
        guard !rest.isEmpty else { return args }
        var current = String.UnicodeScalarView()
        // Quotes: odd while in quotes. Backslashes: those just before, which a `"` makes half as many.
        var quotes = 0, backslashes = 0
        while let c = rest.first {
            if isBlank(c), quotes == 0 {
                args.append(String(current))
                current = String.UnicodeScalarView()
                backslashes = 0
                while let blank = rest.first, isBlank(blank) { rest = rest.dropFirst() }
                if rest.isEmpty { return args }
                continue
            }
            rest = rest.dropFirst()
            if c == "\\" {
                current.append(c)
                backslashes += 1
                continue
            }
            guard c == "\"" else {
                current.append(c)
                backslashes = 0
                continue
            }
            if backslashes % 2 == 0 {
                current.removeLast(backslashes / 2)
                quotes += 1
            } else {
                current.removeLast(backslashes / 2 + 1)
                current.append("\"")
            }
            backslashes = 0
            while rest.first == "\"" {
                rest = rest.dropFirst()
                quotes += 1
                if quotes == 3 {
                    current.append("\"")
                    quotes = 0
                }
            }
            if quotes == 2 { quotes = 0 }
        }
        guard quotes == 0 else { return nil }
        args.append(String(current))
        return args
    }
}

/// A file, folder or app found for `@open`.
public struct SearchResult: Equatable, Sendable {
    /// Shown in the panel ("Calculator", "报告.pdf").
    public var name: String
    public var path: String
    /// A folder (not an app bundle): Tab goes into it.
    public var isFolder: Bool
    /// Shown next to the name; what ⌘C copies instead of the path (a task's reply).
    public var detail: String?
    /// Found by what is in it, not by its name: its row says so (「内容」).
    public var matchedContent: Bool
    /// The name a Chinese interface shows instead of `name`, when known (an app's 计算器). Picked when the
    /// row is drawn: the interface language may change while the results are up.
    public var chineseName: String?

    public init(name: String, path: String, isFolder: Bool = false, detail: String? = nil, matchedContent: Bool = false,
                chineseName: String? = nil) {
        self.name = name
        self.path = path
        self.isFolder = isFolder
        self.detail = detail
        self.matchedContent = matchedContent
        self.chineseName = chineseName
    }

    /// A background task in the list (`@tasks`): its "path" names the session to open.
    public static let agentPrefix = "claude-agent:"
    public var agentID: String? { path.hasPrefix(Self.agentPrefix) ? String(path.dropFirst(Self.agentPrefix.count)) : nil }

    /// A web address in the list (`@open github.com`): opened in the default browser.
    public var webURL: URL? {
        let scheme = path.prefix(8).lowercased()
        guard scheme.hasPrefix("http://") || scheme.hasPrefix("https://") else { return nil }  // HTTPS:// too
        return URL(string: path)
    }

    /// The query as a web address to open, or nil: "https://…" and "www.…" always; a bare
    /// "name.tld/…" only for common top-level domains, so "report.pdf" or "Safari.app" stay file names;
    /// localhost and IP addresses, with a port or not ("localhost:3000", "192.168.1.1"), over http: a server
    /// on this Mac or the network, which mostly has no certificate.
    public static func web(_ query: String) -> SearchResult? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace), !text.hasPrefix("/"), !text.hasPrefix("~") else { return nil }
        let lower = text.lowercased()
        let explicit = lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.")
        if !explicit, let url = URL(string: "http://" + text), url.user == nil,
           let host = url.host?.lowercased(), host == "localhost" || isIPv4(host) {
            return SearchResult(name: name(of: url, host: host), path: url.absoluteString)
        }
        guard let url = WebReader.url(from: text), let host = url.host?.lowercased() else { return nil }
        if !explicit {
            guard let tld = host.split(separator: ".").last, commonDomains.contains(String(tld)) else { return nil }
        }
        return SearchResult(name: name(of: url, host: host), path: url.absoluteString)
    }

    /// How a web address is listed: its host, port and path ("github.com/…", "localhost:3000").
    private static func name(of url: URL, host: String) -> String {
        host + (url.port.map { ":\($0)" } ?? "") + (url.path.count > 1 ? url.path : "")
    }

    /// Four numbers from 0 to 255 with dots between: 127.0.0.1, 192.168.1.1 (not 1.2.3, 999.1.1.1).
    static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            (1...3).contains(part.count) && part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber) && Int(part).map { $0 <= 255 } == true
        }
    }

    static let commonDomains: Set<String> = [
        "com", "org", "net", "io", "ai", "dev", "co", "me", "gov", "edu", "info", "xyz", "tech", "site", "so", "gg", "tv",
        "cn", "hk", "tw", "jp", "kr", "sg", "uk", "us", "ca", "au", "de", "fr", "eu", "in", "ru", "br",
    ]
}

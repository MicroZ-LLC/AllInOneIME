import Foundation
import os

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
        /// Settings changed by describing them (`@config`, `AIConfig`): the changes are shown to confirm, then applied;
        /// nothing is inserted.
        case config
        /// The setup checked on this Mac (`@doctor`, `Doctor`), with fixes through `@config`'s preview; nothing is inserted.
        case doctor
    }

    init(name: String, kind: Kind, custom: CustomCommand? = nil, plugin: InstalledPlugin? = nil, script: ScriptCommand? = nil) {
        self.name = name
        self.kind = kind
        self.custom = custom
        self.plugin = plugin
        self.script = script
    }

    /// Polish in the sentence's own language, with the rewrite styles (`WritingMode.improve`).
    public static let improve = Command(name: "improve", kind: .convert)
    /// Translate into the output languages the user added (`WritingMode.translate`); written together
    /// with `@improve`, one request does both.
    public static let translate = Command(name: "translate", kind: .convert)
    /// Answer a question; the answer can be inserted.
    public static let question = Command(name: "question", kind: .generate)
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

    /// Arithmetic worked out on this Mac (`Calculator`): `@calculate 23*17` → `391`, also inside another
    /// command's text: `@reply 总价是 @calculate 23*17 元`.
    public static let calc = Command(name: "calculate", kind: .run)

    /// Python code (`InlineCode`): the value of its last expression, or what it prints, can be inserted:
    /// `@py 2**100`. It runs with the user's `python3`.
    public static let py = Command(name: "py", kind: .run)
    /// JavaScript code, the same way: `@js [1, 2, 3].map(x => x * 2)`. It runs in JavaScriptCore, in this
    /// app's own child process (no files, programs or network).
    public static let js = Command(name: "js", kind: .run)

    /// `@search`: a web search with the user's own key (`WebSearch`). On its own, a list of the top
    /// results to insert; inside another command's text, their titles, snippets and addresses as context:
    /// `@question 用一句话总结 @search 苹果发布会`.
    public static let webSearch = Command(name: "search", kind: .run)

    /// The background tasks `@agent` started (Claude Code's): how they're doing and what they replied.
    public static let tasks = Command(name: "tasks", kind: .agents)

    /// The settings window.
    public static let settings = Command(name: "settings", kind: .settings)

    /// Change settings by describing them (`AIConfig`): `@config output languages English and French`.
    public static let config = Command(name: "config", kind: .config)

    /// Check the setup and fix what can be fixed (`Doctor`): `@doctor`, or `@doctor why doesn't translate work`.
    public static let doctor = Command(name: "doctor", kind: .doctor)

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

    public static let builtins: [Command] = [.improve, .translate, .question, .agent, .open, .read, .note, .reminder, .calc,
                                             .py, .js, .webSearch, .tasks, .settings, .config, .doctor, .imessage, .reportIssue]

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
    public var typesLatin: Bool { self == .open || self == .read || self == .calc || isCode || custom?.typesLatin == true || plugin?.manifest.typesLatin == true }

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
    /// shows in Settings (`hiddenScripts`).
    public static func catalog(_ custom: [CustomCommand], plugins: [InstalledPlugin] = [],
                               scripts: [ScriptCommand] = []) -> [Command] {
        let builtinNames = Set(builtins.map(\.name))
        var taken = builtinNames
        let fromPlugins = plugins.compactMap { plugin -> Command? in
            guard taken.insert(plugin.name).inserted else {
                if builtinNames.contains(plugin.name) { logHidden("plugin", plugin.name) }
                return nil
            }
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
        return offered + fromPlugins + custom.compactMap { definition in
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
            }
            return Command(name: name, kind: kind, custom: definition)
        } + scripts.compactMap { script in
            script.names.first { taken.insert($0).inserted }.map { Command(name: $0, kind: .run, script: script) }
        }
    }

    /// The extensions `catalog` leaves out because another command has their name (and alias), and which.
    public static func hiddenScripts(_ scripts: [ScriptCommand], custom: [CustomCommand],
                                     plugins: [InstalledPlugin] = []) -> [(script: ScriptCommand, owner: ScriptCommand.Owner)] {
        var owners: [String: ScriptCommand.Owner] = [:]
        for command in builtins { owners[command.name] = .builtIn }
        for plugin in plugins where owners[plugin.name] == nil { owners[plugin.name] = .plugin }
        for definition in custom where definition.isValid && owners[definition.name.lowercased()] == nil {
            owners[definition.name.lowercased()] = .custom
        }
        var hidden: [(ScriptCommand, ScriptCommand.Owner)] = []
        for script in scripts {
            if let free = script.names.first(where: { owners[$0] == nil }) {
                owners[free] = .command(script.id)
            } else if let owner = owners[script.name] {
                hidden.append((script, owner))
            }
        }
        return hidden
    }

    private static let catalogLog = Logger(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "commands")
    private static let loggedHidden = Locked(initialState: Set<String>())

    /// A plugin or custom command a built-in one hides (say a custom "@note" from before @note was built in):
    /// logged once per process, with no UI. The catalog is made on most keystrokes, hence once. The name is
    /// the built-in's, so it may be logged.
    private static func logHidden(_ kind: String, _ name: String) {
        guard loggedHidden.withLock({ $0.insert(kind + " " + name).inserted }) else { return }
        catalogLog.notice("\(kind, privacy: .public) @\(name, privacy: .public) is hidden: a built-in command has that name")
    }

    /// The draft's command and the text after it: "@question 量子计算" → (.question, "量子计算").
    /// Nil without a known command (the "@" must be first, the name followed by a space).
    public static func parse(_ draft: String, in commands: [Command] = builtins) -> (command: Command, content: String)? {
        guard draft.hasPrefix("@"), let space = draft.firstIndex(of: " ") else { return nil }
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
///
/// `{input}` always stays inside the one argument it is written in: the text is never parsed by a
/// shell unless `argv` itself says so (`["zsh", "-c", "{input}"]`).
public struct CustomCommand: Codable, Hashable, Sendable {
    public enum CommandType: String, Codable, Sendable {
        case prompt, run, terminal, link
    }

    /// Letters only, as typed after "@" (digits pick from the command list).
    public var name: String
    public var type: CommandType
    /// Shown next to the name in the command list.
    public var summary: String?
    /// `prompt`: the instruction for the model.
    public var prompt: String?
    /// `run`, `terminal`: the program and its arguments. A program without a "/" is looked up in the
    /// user's shell PATH.
    public var argv: [String]?
    /// `run`: what goes to the program's standard input (`{input}` is replaced); nil: nothing.
    public var stdin: String?
    /// Type the text as Latin letters (code, paths). Default: true for `run` and `terminal`.
    public var ascii: Bool?
    /// `run`: the program is stopped after this many seconds (default 10).
    public var timeoutSeconds: Double?
    /// Its icon in the command list: an SF Symbol name ("chart.bar"), and a color (a system color's
    /// name, "blue", or "#RRGGBB"); unset, one for its type.
    public var icon: String?
    public var color: String?
    /// `link`: the web address, with `{input}` in its query (`LinkTemplate`).
    public var url: String?

    public init(name: String, type: CommandType, summary: String? = nil, prompt: String? = nil,
                argv: [String]? = nil, stdin: String? = nil, ascii: Bool? = nil, timeoutSeconds: Double? = nil,
                icon: String? = nil, color: String? = nil, url: String? = nil) {
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
        }
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
    }

    /// The first problem with this definition among `others` (the other custom commands) and the
    /// installed plugins' names, or nil.
    public func problem(among others: [CustomCommand], plugins: [String] = []) -> Problem? {
        let name = name.lowercased()
        if name.isEmpty { return .emptyName }
        if !name.allSatisfy({ $0.isASCII && $0.isLetter }) || name.count > 24 { return .nameNotLetters }
        if Command.builtins.contains(where: { $0.name == name }) || plugins.contains(name)
            || others.contains(where: { $0.name.lowercased() == name }) {
            return .nameTaken
        }
        switch type {
        case .prompt:
            if (prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyPrompt }
        case .run, .terminal:
            if (argv?.first ?? "").isEmpty { return .emptyCommand }
        case .link:
            if let problem = LinkTemplate.problem(url) { return .link(problem) }
        }
        return nil
    }

    /// Arguments as one line, quoted where needed: ["python3", "-c", "{input}"] → `python3 -c {input}`.
    public static func commandLine(_ argv: [String]) -> String {
        argv.map { arg in
            guard arg.isEmpty || arg.contains(where: { " \t\"'\\".contains($0) }) else { return arg }
            return "\"" + arg.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }.joined(separator: " ")
    }

    /// A command line split into arguments: spaces separate them, "…" and '…' quote, \ escapes the
    /// next character. No other shell syntax: `;`, `|`, `$` are plain text. Nil if a quote isn't closed.
    public static func arguments(fromCommandLine line: String) -> [String]? {
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

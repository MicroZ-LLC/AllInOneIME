import Foundation

// Suggestions v1 (.spec/spec-suggestions-v1.md, 2026-10-22, with its section 6, the decisions on the tests' questions):
// plugin completions, coding mode, one Tab. What the acceptance tests
// (Tests/AllInOneIMECoreTests/Acceptance/Suggestions*AcceptanceTests.swift) are written against, written before the
// implementation by the tests' author: protocols and plain data. The implementation fills in what had a stub
// (`PluginManifest.completions`, `preferences` and `refusedCompletions` in Plugin.swift, read by CompletionDeclaration.swift;
// `inactiveReason`; `SuggestionsStore`, SuggestionsStore.swift) without changing what they mean; the session's side is
// Session/InputSession+Suggestions.swift, the plugin's runtime PluginCompletionRuntime.swift.
//
// The one hook outside this file: `SessionServices.suggestions` (SessionServices.swift), what a session asks of the
// shell for suggestions. Everything a test observes goes through `InputSession` as today: keys in, outputs out (rows are
// the candidate panel's `PanelModel.rows`, an insertion a `commit`, the caret into a snippet `moveCaret`).

// MARK: - Plugin completions: the declaration (spec 1.1)

/// A completion source a `script` plugin declares (`plugin.json`'s `completions`, read into
/// `PluginManifest.completions`), with the spec's defaults filled in where the manifest leaves a key out.
public struct CompletionSource: Equatable, Hashable, Sendable {
    /// How a token is compared with an item's `match`, Latin letters in any case (the prefix's too: `proj-12` is
    /// `PROJ-12`'s start): its start (`#12` shows `#1234`), or the whole of it (an account id shows only once typed in
    /// full). A source without `prefix` is `exact` (left out, it is), and only for tokens of digits (spec 6.7, 6.8).
    public enum Compare: String, Equatable, Hashable, Sendable {
        case prefix, exact
    }

    /// `[a-z0-9]{1,24}`, unique in the plugin.
    public var name: String
    /// Shown in Settings and in the rows' footer.
    public var title: LocalizedText
    /// The literal text a token starts with (`#`, `PROJ-`); full-width forms count (`＃` is `#`). Nil: none.
    public var prefix: String?
    /// The characters after the prefix before rows can show: 1 with a prefix, 3 without, unless declared.
    public var minChars: Int
    /// `prefix` unless declared; without a prefix, `exact` (the only one it may declare).
    public var compare: Compare
    /// The script exports `load(ctx)`: the whole list, kept in memory (its last good one).
    public var list: Bool
    /// How often the list is loaded again, in seconds: 1 h unless declared ("5m" … "7d").
    public var refresh: TimeInterval
    /// The script exports `query(text, ctx)`: a live lookup. Only with a `prefix` (a declaration without one is refused:
    /// any number typed anywhere would go out).
    public var query: Bool
    /// The characters after the prefix before `query` is first called: 3 unless declared (1 at least). After that it is
    /// called again (150 ms after the last key, one call at a time) only when what is kept of the answers for the
    /// longest text asked leaves fewer than 5 rows for the token (spec 6.4).
    public var queryMinChars: Int
    /// What a row inserts, per app class.
    public var insert: CompletionInsert

    public init(name: String, title: LocalizedText, prefix: String? = nil, minChars: Int? = nil, compare: Compare? = nil,
                list: Bool = false, refresh: TimeInterval = 3600, query: Bool = false, queryMinChars: Int = 3,
                insert: CompletionInsert = .standard) {
        self.name = name
        self.title = title
        self.prefix = prefix
        self.minChars = minChars ?? (prefix == nil ? 3 : 1)
        self.compare = compare ?? (prefix == nil ? .exact : .prefix)
        self.list = list
        self.refresh = refresh
        self.query = query
        self.queryMinChars = queryMinChars
        self.insert = insert
    }
}

/// What a source's row inserts (`insert`), per app class: `default` (ordinary apps), `chat` and `terminal` (a class not
/// declared uses `default`'s). Templates name an item's variables in braces: `{match}`, `{arg}`, and the item's own
/// `variables` (`{url}`). The terminal and code editor class only says whether there are rows there: `null`, none;
/// anything else, `{match}` is what goes in (spec 6.10). A row whose insertion doesn't start with what was typed (in any
/// case) isn't offered for that token (spec 6.13).
public struct CompletionInsert: Equatable, Hashable, Sendable {
    public enum Templates: Equatable, Hashable, Sendable {
        /// A template, or several tried in turn: the first whose variables the item all has.
        case templates([String])
        /// `null`: no completions from this source in that class of app.
        case off
    }

    public var `default`: Templates
    /// Nil: as `default`.
    public var chat: Templates?
    public var terminal: Templates?

    public init(default: Templates, chat: Templates? = nil, terminal: Templates? = nil) {
        self.default = `default`
        self.chat = chat
        self.terminal = terminal
    }

    /// `{"default": "{arg}"}`, a source's unless it declares its own.
    public static let standard = CompletionInsert(default: .templates(["{arg}"]))
}

/// A plugin's own setting (`plugin.json`'s `preferences`, read into `PluginManifest.preferences`): shown in Settings
/// under the plugin, given to its script as `ctx.preferences`.
public struct PluginPreference: Equatable, Hashable, Sendable {
    public enum Kind: String, Equatable, Hashable, Sendable {
        /// Kept in the settings.
        case text
        /// Kept in the secret store, as extensions' passwords are: given to the script only, never logged.
        case password
    }

    public var name: String
    public var kind: Kind
    public var title: LocalizedText
    public var placeholder: String?
    /// What the script gets while the user has set nothing.
    public var defaultValue: String?

    public init(name: String, kind: Kind, title: LocalizedText, placeholder: String? = nil, defaultValue: String? = nil) {
        self.name = name
        self.kind = kind
        self.title = title
        self.placeholder = placeholder
        self.defaultValue = defaultValue
    }
}

// `PluginManifest.completions`, `refusedCompletions` and `preferences` are stored (Plugin.swift), read from plugin.json by
// `CompletionDeclaration` (CompletionDeclaration.swift).

/// A completion entry of a plugin.json refused, and why, as Settings → Plugins says it (spec 6.9).
public struct CompletionRefusal: Equatable, Hashable, Sendable {
    /// The entry's `name` as declared (nil: it has none that is text, or `completions` isn't a list at all).
    public var name: String?
    public var reason: String

    public init(name: String?, reason: String) {
        self.name = name
        self.reason = reason
    }
}

extension CompletionSource {
    /// Why the source is inactive with `config`, as Settings says it (nil: it isn't): the command trigger
    /// (`Config.commandTrigger`) is its prefix, or starts it, and the trigger wins (spec 6.14).
    public func inactiveReason(_ config: Config) -> String? {
        guard isShadowed(by: config.commandTrigger) else { return nil }
        let trigger = config.commandTrigger
        return tr("\(trigger) 是魔法键，打 \(trigger) 会打开命令列表，所以这个补全不会出现（在「通用」里换一个魔法键就行）",
                  "\(trigger) is the magic key: typing it opens the command list, so these completions can't show (pick another magic key in General)")
    }
}

extension CompletionSource {
    /// Its prefix starts with `trigger`, the magic key (`Config.commandTrigger`): typing it opens the command list.
    public func isShadowed(by trigger: String) -> Bool {
        prefix?.first.map { String($0) == trigger } ?? false
    }
}

// MARK: - Plugin completions: the script's side (spec 1.2)

/// One item of a list or of a query's answer, as a script returns it: `match` (1–64 characters of letters, digits and
/// `. _ - @ #`, the prefix included; digits only without a prefix) is what a token is compared with; `arg` (default:
/// `match`) and `variables` fill the templates; `title` and `subtitle` are shown. Its place in the list is its rank.
/// Control, bidi and zero-width characters are taken out of all of it first; an item whose `match` breaks the rules then
/// is dropped, on its own (spec 6.5, 6.6).
public struct CompletionItem: Codable, Equatable, Hashable, Sendable {
    public var match: String
    public var title: String?
    public var subtitle: String?
    public var arg: String?
    public var variables: [String: String]?

    public init(match: String, title: String? = nil, subtitle: String? = nil, arg: String? = nil,
                variables: [String: String]? = nil) {
        self.match = match
        self.title = title
        self.subtitle = subtitle
        self.arg = arg
        self.variables = variables
    }
}

/// What `load(ctx)` returns (`{ items, fetchedAt? }`, at most 20,000 items and 4 MiB) and `query(text, ctx)` returns
/// (`{ items }`). `fetchedAt`: when the list was made, in seconds since 1970 (nil: when it was loaded). An output that
/// isn't a JSON object with an `items` array, or is larger, is a failure (the old list is kept); bad items in a good one
/// are dropped one by one (spec 6.5).
public struct CompletionList: Codable, Equatable, Sendable {
    public var items: [CompletionItem]
    public var fetchedAt: Double?

    public init(items: [CompletionItem], fetchedAt: Double? = nil) {
        self.items = items
        self.fetchedAt = fetchedAt
    }

    public static let maxItems = 20_000
    public static let maxBytes = 4 << 20
}

/// The script's `ctx`: the source's name, the plugin's preferences (passwords too, for the script only) and the interface
/// language (`UIText.pluginLanguage`). Nothing else: no app, no field, no text around the caret.
public struct CompletionContext: Equatable, Sendable {
    public var source: String
    public var preferences: [String: String]
    public var language: Language

    public init(source: String, preferences: [String: String], language: Language) {
        self.source = source
        self.preferences = preferences
        self.language = language
    }
}

/// A call into a plugin's completion script: which plugin and source, its `ctx`, and how long it may take (`load`: the
/// plugin's `timeoutSeconds`, 20 s at most, `PluginManifest.timeout`; `query`: 3 s at most). The runtime stops it then
/// and throws. `hosts`: those the user approved with the source (`CompletionSourceApproval.hosts`): the script may
/// fetch from those only (that its plugin.json still lists when it runs); none, from none. `scriptSHA256`: the script's
/// the user approved (`CompletionSourceApproval.scriptSHA256`): only that script runs (one changed since, or none
/// given: the call fails).
public struct CompletionCall: Equatable, Sendable {
    public var plugin: InstalledPlugin
    public var source: CompletionSource
    public var context: CompletionContext
    public var timeout: TimeInterval
    public var hosts: [String]
    public var scriptSHA256: String?

    public init(plugin: InstalledPlugin, source: CompletionSource, context: CompletionContext, timeout: TimeInterval,
                hosts: [String] = [], scriptSHA256: String? = nil) {
        self.plugin = plugin
        self.source = source
        self.context = context
        self.timeout = timeout
        self.hosts = hosts
        self.scriptSHA256 = scriptSHA256
    }
}

/// What runs plugins' completion scripts (spec 1.2: QuickJS, the process model and `fetch` rules of script plugins
/// today: HTTPS to the plugin's `hosts` only). It hands back what the script returned, as JSON (a `CompletionList`'s
/// form), unchecked: the core checks it (sizes, `match`, duplicates) and strips control, bidi and zero-width characters
/// from what it shows or inserts. Called off the session's thread; a call the core no longer wants (a newer token's
/// query in its place) is cancelled as a task is.
public protocol CompletionRuntime: Sendable {
    /// `load(ctx)`.
    func load(_ call: CompletionCall) async throws -> Data
    /// `query(text, ctx)`: `text` is what follows the prefix (`"12"` for `#12`).
    func query(_ text: String, _ call: CompletionCall) async throws -> Data
}

// MARK: - Trust, switches, what is kept (spec 1.4, 1.5, 3)

/// A completion source the user enabled in Settings → Plugins, and what they enabled: the plugin's `hosts`, whether the
/// source queries, the SHA-256 (lowercase hex) of its script file, and what else its switch said (`terms`). A plugin
/// whose hosts, query, script or terms differ now needs enabling again: until then the source is off, its approval kept
/// and marked `lapsed` (Settings says it changed since it was turned on).
public struct CompletionSourceApproval: Codable, Equatable, Hashable, Sendable {
    /// What a source's switch says besides its hosts and whether it queries ("sends what you type after # to …"): its
    /// prefix, how many characters after it before its query is first asked, how it compares.
    public struct Terms: Codable, Equatable, Hashable, Sendable {
        public var prefix: String?
        public var queryMinChars: Int
        public var compare: CompletionSource.Compare

        public init(_ source: CompletionSource) {
            prefix = source.prefix
            queryMinChars = source.queryMinChars
            compare = source.compare
        }
    }

    public var plugin: String
    public var source: String
    public var hosts: [String]
    public var query: Bool
    public var scriptSHA256: String
    /// Nil: not kept (an approval made before they were), which holds no more, whatever they are now: the source is off
    /// until turned on again, as when it lapsed (a plugin updated since may have dropped its prefix, and what is typed
    /// would be sent). Settings always keeps them (`init(enabling:of:)`).
    public var terms: Terms?
    /// Its plugin was found changed since (`lapsed(_:plugins:sha256:)`): it holds no more, whatever the plugin is now,
    /// until the source is turned on again (a new approval). Written only when set.
    public var lapsed: Bool

    public init(plugin: String, source: String, hosts: [String], query: Bool, scriptSHA256: String, terms: Terms? = nil,
                lapsed: Bool = false) {
        self.plugin = plugin
        self.source = source
        self.hosts = hosts
        self.query = query
        self.scriptSHA256 = scriptSHA256
        self.terms = terms
        self.lapsed = lapsed
    }

    private enum CodingKeys: String, CodingKey {
        case plugin, source, hosts, query, scriptSHA256, terms, lapsed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plugin = try c.decode(String.self, forKey: .plugin)
        source = try c.decode(String.self, forKey: .source)
        hosts = try c.decode([String].self, forKey: .hosts)
        query = try c.decode(Bool.self, forKey: .query)
        scriptSHA256 = try c.decode(String.self, forKey: .scriptSHA256)
        terms = try c.decodeIfPresent(Terms.self, forKey: .terms)
        lapsed = try c.decodeIfPresent(Bool.self, forKey: .lapsed) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(plugin, forKey: .plugin)
        try c.encode(source, forKey: .source)
        try c.encode(hosts, forKey: .hosts)
        try c.encode(query, forKey: .query)
        try c.encode(scriptSHA256, forKey: .scriptSHA256)
        try c.encodeIfPresent(terms, forKey: .terms)
        if lapsed { try c.encode(true, forKey: .lapsed) }
    }
}

extension CompletionSource.Compare: Codable {}

/// The switches suggestions follow, as the shell has them from its settings: the input menu's "Suggestions" (nil: the
/// default, on once a source is enabled), Settings → Apps' per-app "Suggestions" by app id (absent: the default), the
/// completion sources enabled (one disabled: its cached list is deleted), the custom commands that are sources, and
/// "Refresh now" pressed for a source. (No AI in an app doesn't turn completions off: no AI is involved.)
public struct SuggestionsSettings: Equatable, Sendable {
    public var master: Bool?
    public var apps: [String: Bool]
    public var enabled: [CompletionSourceApproval]
    /// "Refresh now" (Settings → Plugins, or a custom command's editor), the latest for each source: one newer than the
    /// source's last load loads it again now, paused or not (spec 3, 6.17).
    public var refreshes: [CompletionSourceRefresh]
    /// The custom commands of type `suggestions` (`Config.customCommands`'), each a source while it exists, with no
    /// approval (decision 24: the user's own); one removed: its cached list is deleted. A command of another type, or
    /// one refused (`CustomCommand.suggestionSource`), is none.
    public var commands: [CustomCommand]

    public init(master: Bool? = nil, apps: [String: Bool] = [:], enabled: [CompletionSourceApproval] = [],
                refreshes: [CompletionSourceRefresh] = [], commands: [CustomCommand] = []) {
        self.master = master
        self.apps = apps
        self.enabled = enabled
        self.refreshes = refreshes
        self.commands = commands
    }
}

/// "Refresh now" pressed for a completion source in Settings → Plugins, and when.
public struct CompletionSourceRefresh: Codable, Equatable, Hashable, Sendable {
    public var plugin: String
    public var source: String
    public var requested: Date

    public init(plugin: String, source: String, requested: Date) {
        self.plugin = plugin
        self.source = source
        self.requested = requested
    }
}

/// A row the user picked (inserted), by its source and `match`: rows picked before come first, the one picked last
/// first (spec 6.17). Kept on this device only.
public struct SuggestionPick: Codable, Equatable, Hashable, Sendable {
    public var plugin: String
    public var source: String
    public var match: String

    public init(plugin: String, source: String, match: String) {
        self.plugin = plugin
        self.source = source
        self.match = match
    }
}

/// How a completion source is doing, for Settings → Plugins: how many items its list has, when it was last loaded, the
/// last error (nil: none since), and whether it is paused. Failures back off (the next load 1 min, 5 min, 30 min, 2 h
/// after each); the fifth in a row pauses the source (`error` says why) until "Refresh now", an update of the plugin, or
/// 24 hours later (spec 6.17).
public struct CompletionSourceStatus: Equatable, Sendable {
    public var plugin: String
    public var source: String
    public var items: Int
    public var refreshed: Date?
    public var error: String?
    public var paused: Bool

    public init(plugin: String, source: String, items: Int, refreshed: Date?, error: String?, paused: Bool) {
        self.plugin = plugin
        self.source = source
        self.items = items
        self.refreshed = refreshed
        self.error = error
        self.paused = paused
    }
}

// MARK: - Custom commands as a source (decision 24)

// A custom command of type `suggestions` (`CustomCommand.CommandType.suggestions`; its keys `prefix`, `minChars`,
// `compare`, `refresh`, `query`, `queryMinChars`, `insert`, `argv` and `timeoutSeconds`, Command.swift) is a completion
// source as a plugin's `completions` entry is, its keys read by the same rules, limits and defaults
// (`CustomCommand.suggestionSource`, CommandSuggestions.swift: a prefix required, the list always on). One kind of
// source: the session takes it with the plugins' (`SuggestionsSettings.commands`, no approval), the store keeps it as
// theirs under `CompletionSourceKey(command:)` (its list, the disk cache, back-off and pause, statuses, "Refresh now",
// the picks), its rows, keys and insertions are theirs. What differs is where its items come from: its program, run as a
// `run` command's is (`CommandCompletionRuntime`), and what it may print (`CompletionOutput.readProgram`: the plugins'
// JSON, or lines "match<TAB>title<TAB>url"). Typed as a command itself (`@jira`), it only says what it is.

extension CompletionSourceKey {
    /// What custom commands' sources are kept under (their `plugin`): a name no plugin can have.
    public static let customCommands = "custom-commands"

    /// The source of the custom command named `name` (its name in small letters: names are the same in any case).
    public init(command name: String) {
        self.init(plugin: Self.customCommands, source: name.lowercased())
    }

    /// It is a custom command's source.
    public var isCustomCommand: Bool { plugin == Self.customCommands }
}

/// What runs a custom command's program for its suggestions (decision 24), as a `run` command's runs
/// (`CommandRunner`: `argv` without a shell unless it says so, a program without "/" looked up in the user's shell PATH,
/// `timeoutSeconds`): what it printed, as it is (the core reads it, `CompletionOutput.readProgram`). `list`: run with no
/// input (`CustomCommand.suggestionArguments(query: nil)`); `query`: with what follows the prefix as one argument, in
/// place of `{input}` where argv writes it, else the last; 3 seconds at most. Nothing else of the field goes to it, and
/// nothing in its environment. Called off the session's thread; a call the core no longer wants is cancelled as a task
/// is, which stops the program.
public protocol CommandCompletionRuntime: Sendable {
    func list(_ command: CustomCommand) async throws -> Data
    func query(_ text: String, _ command: CustomCommand) async throws -> Data
}

// MARK: - Coding languages (spec 2)

/// A coding language pack (JSON), downloaded and verified like a language pack: its keywords and snippets are
/// suggestions while coding mode is on. A snippet's `body` is inserted as text, its line breaks kept: `${n:text}` as its
/// text, `$n` as nothing, the caret at `$0` (where the field reports ranges; else at the end).
public struct CodingLanguagePack: Codable, Equatable, Sendable {
    public struct Snippet: Codable, Equatable, Sendable {
        public var trigger: String
        public var body: String
        public var title: String?

        public init(trigger: String, body: String, title: String? = nil) {
            self.trigger = trigger
            self.body = body
            self.title = title
        }
    }

    /// Its id ("python").
    public var language: String
    public var title: String
    public var version: String
    public var keywords: [String]
    public var snippets: [Snippet]

    public init(language: String, title: String, version: String, keywords: [String], snippets: [Snippet]) {
        self.language = language
        self.title = title
        self.version = version
        self.keywords = keywords
        self.snippets = snippets
    }
}

// MARK: - What a session asks of the shell

/// What a text field's session asks of the shell for suggestions (`SessionServices.suggestions`). The same for every
/// field of a launch: what the core keeps in memory across fields (the lists) is its `store`. The session's time is `now`
/// (list ages, refreshes, back-offs; the long press of Shift and the queries' 150 ms may go by `SessionServices.uptime`
/// too, which a test moves with it), its waits are timers (`SessionOutput.startTimer`, back as `SessionEvent.timer`). The
/// defaults do nothing and keep nothing.
public struct SuggestionsServices {
    /// What the core keeps for the fields of one launch, in memory (`SuggestionsStore`).
    public var store: SuggestionsStore
    /// Runs plugins' `load` and `query`.
    public var runtime: any CompletionRuntime
    /// Runs custom commands' programs for their lists and queries.
    public var commandRuntime: any CommandCompletionRuntime
    /// The switches (read again as the settings change).
    public var settings: () -> SuggestionsSettings
    /// The time now.
    public var now: @Sendable () -> Date
    /// Where the lists are cached on disk, a file of each source's, readable by the user only (0600): the shell's
    /// `~/Library/Caches/AllInOneIME/suggestions/`, Windows' under `%LOCALAPPDATA%`. A source's file is deleted when it is
    /// disabled; the next launch shows a cached list (with its age) while it loads again. Nil: none kept (the default).
    public var cacheFolder: URL?
    /// A plugin's preferences as the user set them (texts from the settings, passwords from the secret store), by name; a
    /// preference not set gets its `default` from the manifest (the core fills it in). Never while a key is handled.
    public var preferences: @Sendable (InstalledPlugin) -> [String: String]
    /// The coding language packs installed (all of them apply: a field can't tell its language in v1).
    public var codingPacks: () -> [CodingLanguagePack]
    /// Coding mode, which the shell keeps across fields and apps until it is turned off (as Translate as You Type).
    /// The session turns it on and off from the chooser a long press of Shift opens, which it shows (the shell only draws
    /// it; spec 6.2).
    public var codingMode: () -> Bool
    public var setCodingMode: (Bool) -> Void
    /// Translate as You Type, the shell's (`TranslateMode`): whether it is on, and turning it on or off (from the same
    /// chooser; the two modes are exclusive).
    public var translateAsYouType: () -> Bool
    public var setTranslateAsYouType: (Bool) -> Void
    /// The rows picked before (kept on this device only), in the order they were picked, the latest last (a row picked
    /// again: its latest counts), and keeping one.
    public var loadPicks: () -> [SuggestionPick]
    public var recordPick: (SuggestionPick) -> Void
    /// A source's status changed (Settings → Plugins shows it). From any thread.
    public var reportStatus: @Sendable (CompletionSourceStatus) -> Void
    /// These approvals no longer hold (`CompletionSourceApproval.lapsed`: their plugin changed since in a way that needs
    /// enabling again): the shell marks them lapsed in the settings (`Config.markLapsed`), which keep them and say so, and
    /// the source stays off until enabled again, the plugin as it was again too. Their cached lists are kept: those go
    /// with the approval (the source disabled, the plugin removed).
    public var approvalsLapsed: ([CompletionSourceApproval]) -> Void
    /// Where the pointer is (screen points) and whether Sticky Keys is on, for the long press of Shift
    /// (`TranslateMode.ShiftHold`: the pointer moved while Shift is held is a Shift-click being aimed; with Sticky Keys
    /// Shift is latched, never held). The defaults: nowhere, off.
    public var pointer: () -> CGPoint
    public var stickyKeys: () -> Bool
    /// Whether Shift is down now as the system has it (and no mouse button), asked when the long press's time comes: a
    /// release that went unseen opens no chooser. The default: yes.
    public var shiftHeld: () -> Bool
    /// Whether Shift is down now as the system has it, asked as a field takes the focus: Shift's changes while another
    /// field had it went there, and the long press goes on from Shift as it is now (`TranslateMode.ShiftHold.resync`).
    /// The default: no.
    public var shiftDown: () -> Bool
    /// What the long press of Shift says half way to the chooser ("Keep holding → …", the shell's wording; nil: nothing).
    public var chooserHint: () -> String?

    public init() {
        store = SuggestionsStore()
        runtime = NoCompletionRuntime()
        commandRuntime = NoCommandCompletionRuntime()
        settings = { SuggestionsSettings() }
        now = { Date() }
        cacheFolder = nil
        preferences = { _ in [:] }
        codingPacks = { [] }
        codingMode = { false }
        setCodingMode = { _ in }
        translateAsYouType = { false }
        setTranslateAsYouType = { _ in }
        loadPicks = { [] }
        recordPick = { _ in }
        reportStatus = { _ in }
        approvalsLapsed = { _ in }
        pointer = TranslateMode.ShiftHold.noPointer
        stickyKeys = { false }
        shiftHeld = { true }
        shiftDown = { false }
        chooserHint = { nil }
    }
}

// `SuggestionsStore`, what the core keeps in memory for the fields of one launch, which the shell gives every field (as
// `SessionServices.autocomplete`'s store): the lists and the queries' answers, the failures and pauses, what was asked
// last; its contents are the core's, a new one is a new launch (SuggestionsStore.swift).

/// The runtime where the shell gave none: every call fails.
public struct NoCompletionRuntime: CompletionRuntime {
    public init() {}
    public func load(_ call: CompletionCall) async throws -> Data { throw SessionServicesError.unsupported }
    public func query(_ text: String, _ call: CompletionCall) async throws -> Data { throw SessionServicesError.unsupported }
}

/// Custom commands' runtime where the shell gave none: every call fails.
public struct NoCommandCompletionRuntime: CommandCompletionRuntime {
    public init() {}
    public func list(_ command: CustomCommand) async throws -> Data { throw SessionServicesError.unsupported }
    public func query(_ text: String, _ command: CustomCommand) async throws -> Data { throw SessionServicesError.unsupported }
}

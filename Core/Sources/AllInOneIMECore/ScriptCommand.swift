import Foundation

/// An @ command that is a program outside the app: a script extension (docs/extensions.md). Three front ends
/// make the same value, so running it, its output and the interface only know this one shape:
///
/// - a script with `@allinoneime.<key> <value>` lines in its comments (the protocol's own keys),
/// - a Raycast Script Command, its `@raycast.<key>` lines read as they are (`raycastKeys` maps them),
/// - a command in a bundle's `extension.json` (`ExtensionBundle`), with the same keys in JSON.
///
///     #!/bin/bash
///     # @allinoneime.schemaVersion 1
///     # @allinoneime.title Flights
///     # @allinoneime.argument1 {"type": "text", "placeholder": "from city"}
///     # @allinoneime.argument2 {"type": "text", "placeholder": "to city"}
///
/// `flights.sh` is `@flights`; `@flights beijing, new york` runs it with "beijing" and "new york" as $1 and
/// $2 (`arguments(from:)`); what it prints is used as its `output` says (`ScriptOutput`).
public struct ScriptCommand: Hashable, Sendable {
    /// The protocol version this app speaks: a newer `schemaVersion` is reported, not run. Within a version,
    /// changes only add things (unknown keys are ignored).
    public static let protocolVersion = 1

    /// Where a command comes from: also its rank when names clash (a bundle's before a single script's,
    /// before a Raycast script's).
    public enum Source: Hashable, Sendable, Comparable {
        /// In the bundle of this name (`ExtensionBundle.name`).
        case bundle(String)
        /// A single script with `@allinoneime.` keys.
        case script
        /// A Raycast Script Command.
        case raycast

        var rank: Int {
            switch self {
            case .bundle: return 0
            case .script: return 1
            case .raycast: return 2
            }
        }

        public static func < (a: Source, b: Source) -> Bool { a.rank < b.rank }

        public var bundleName: String? {
            if case let .bundle(name) = self { return name }
            return nil
        }
    }

    /// What it needs after its name.
    public enum Input: String, Hashable, Sendable {
        /// Nothing: the text after it is ignored; the action key on its name runs it.
        case none
        /// Text if there is some (its arguments are all optional).
        case optional
        /// Text, else a notice says what's missing.
        case required
    }

    /// What becomes of what it prints.
    public enum Output: String, Hashable, Sendable, CaseIterable {
        /// Candidates to insert: all of it, and each line on its own.
        case insert
        /// Shown in the panel as it's printed (progress); nothing is inserted.
        case show
        /// A list in Alfred's Script Filter JSON, run again as the text changes (`ScriptList`).
        case list
        /// The last line as a notice near the caret; nothing is inserted.
        case silent
    }

    public enum Icon: Hashable, Sendable {
        case emoji(String)
        /// An SF Symbol's name.
        case symbol(String)
        /// An image file.
        case image(URL)
    }

    /// One of `argument1`…`argument3`, in Raycast's JSON: `{"type": "text", "placeholder": "city", "optional": true}`.
    public struct Argument: Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable {
            case text, password, dropdown
        }

        /// A `dropdown` choice: the title is typed or shown, the value is passed.
        public struct Choice: Hashable, Sendable {
            public var title: String
            public var value: String

            public init(title: String, value: String) {
                self.title = title
                self.value = value
            }
        }

        public var kind: Kind
        public var placeholder: String
        public var optional: Bool
        /// The value is percent-encoded before it is passed (for a web address).
        public var percentEncoded: Bool
        public var choices: [Choice]

        public init(kind: Kind = .text, placeholder: String = "", optional: Bool = false, percentEncoded: Bool = false,
                    choices: [Choice] = []) {
            self.kind = kind
            self.placeholder = placeholder
            self.optional = optional
            self.percentEncoded = percentEncoded
            self.choices = choices
        }
    }

    /// A program whose first line is shown beside the name in the command list (`status`), every `refresh`
    /// seconds at most.
    public struct Status: Hashable, Sendable {
        public var launch: [String]
        public var refresh: TimeInterval
        /// Its own script, run with `ALLINONEIME_STATUS=1` (`status self`, a Raycast `inline` script).
        public var isSelf: Bool

        public static let minimumRefresh: TimeInterval = 10
        public static let defaultRefresh: TimeInterval = 60
        /// A status that takes longer is stopped: the list never waits for it.
        public static let timeout: Double = 5
    }

    /// Why a file or an entry isn't a command (shown in Settings).
    public enum Problem: Error, Hashable, Sendable {
        /// A required key (`schemaVersion`; for Raycast, `title` and `mode`) is missing.
        case missing(String)
        /// A protocol version this app doesn't speak yet: it needs a newer AllInOneIME.
        case newerProtocol(Int)
        /// A key whose value can't be used.
        case badValue(key: String, value: String)
        /// `argumentN` isn't JSON this understands, or comes after a missing one.
        case badArgument(Int)
        /// Not executable, and no "#!" line to run it with (or a bundle's `script` that isn't there).
        case notRunnable
        /// No name to type after "@" (no letter in the file name).
        case noName
        /// Its `platform` leaves out macOS (Raycast).
        case notForMac
        /// A bundle's `extension.json` that can't be used, and why.
        case badBundle(BundleProblem)
        /// Another bundle with this name is loaded already.
        case bundleTaken
        /// Another command has its name (and its `alias`, if any): the name, and what has it.
        case nameTaken(String, by: Owner)
        /// A symbolic link to nothing.
        case brokenLink
    }

    /// What's wrong with an `extension.json`.
    public enum BundleProblem: Hashable, Sendable {
        /// It isn't a JSON object.
        case notJSON
        /// Its `name` isn't letters, digits, "-" and "_".
        case badName
        /// It names no commands.
        case noCommands
        /// A preference without a name, or of a type this app doesn't know.
        case badPreference
    }

    /// What has a name a command wanted.
    public enum Owner: Hashable, Sendable {
        case builtIn, plugin, custom
        /// An extension command found before it (its id).
        case command(String)
        /// A bundle's snippet found before it (its id, "<bundle>/<name>").
        case snippet(String)
    }

    /// What keeps the text typed after the command from running it (shown as a notice).
    public enum ArgumentProblem: Error, Equatable, Sendable {
        /// Required arguments left empty: their placeholders.
        case missing([String])
        /// A dropdown value that isn't one of its choices: the placeholder, and the choices' titles.
        case notAChoice(String, [String])
    }

    /// Stable across launches, for turning it off and for its status: the file ("~/…"), or the bundle's
    /// name and the command's ("tools/convert").
    public var id: String
    public var source: Source
    public var file: URL
    /// What follows "@" (`isValidName`).
    public var name: String
    /// The name it takes when `name` is another command's (a bundle's way out of a clash).
    public var alias: String?
    public var title: String { didSet { searchTerms = Self.terms(title, keywords) } }
    public var description: String?
    /// Shown after the title in the command list: a Raycast `packageName`, a bundle's title.
    public var group: String?
    /// More words the command list finds it by, besides its name and title.
    public var keywords: [String] { didSet { searchTerms = Self.terms(title, keywords) } }
    /// The words the command list finds it by besides its name: its title's words and its keywords, lowercased
    /// (kept, not split again on each key).
    public private(set) var searchTerms: [String]
    public var icon: Icon?
    public var input: Input
    public var arguments: [Argument]
    public var output: Output
    /// Keeps running when the field is left (it starts and the draft is done), then a notification says how it went.
    public var background: Bool
    public var status: Status?
    /// The action key asks once more before it runs.
    public var confirm: Bool
    public var timeout: Double
    /// `list`: seconds after the last key before it runs again.
    public var queryDelay: Double
    /// Where it runs: its folder, or `currentDirectoryPath`.
    public var directory: URL
    /// The bundle's folder, or the script's (`ALLINONEIME_EXTENSION_DIR`).
    public var extensionDirectory: URL
    /// How it is started, before its arguments: the file when it is executable, else its "#!" line's program.
    public var launch: [String]

    public init(id: String? = nil, source: Source = .script, file: URL, name: String, alias: String? = nil, title: String? = nil,
                description: String? = nil, group: String? = nil, keywords: [String] = [], icon: Icon? = nil,
                input: Input = .required, arguments: [Argument] = [Argument()], output: Output = .insert,
                background: Bool = false, status: Status? = nil, confirm: Bool = false, timeout: Double? = nil,
                queryDelay: Double = Self.defaultQueryDelay, directory: URL? = nil, extensionDirectory: URL? = nil,
                launch: [String]? = nil) {
        self.id = id ?? file.path
        self.source = source
        self.file = file
        self.name = name
        self.alias = alias
        self.title = title ?? name
        self.description = description
        self.group = group
        self.keywords = keywords
        self.searchTerms = Self.terms(title ?? name, keywords)
        self.icon = icon
        self.input = input
        self.arguments = input == .none ? [] : arguments
        self.output = output
        self.background = background
        self.status = status
        self.confirm = confirm
        self.timeout = timeout ?? (background ? Self.backgroundTimeout : Self.defaultTimeout)
        self.queryDelay = queryDelay
        self.directory = directory ?? file.deletingLastPathComponent()
        self.extensionDirectory = extensionDirectory ?? file.deletingLastPathComponent()
        self.launch = launch ?? [file.path]
    }

    public static let defaultTimeout: Double = 10
    public static let backgroundTimeout: Double = 600
    public static let defaultQueryDelay: Double = 0.15
    /// Raycast's own limit.
    public static let maxArguments = 3
    public static let maxNameLength = 24

    /// The names it answers to, in order (its alias only when its name is taken).
    public var names: [String] { [name] + (alias.map { [$0] } ?? []) }

    /// Letters and digits, a letter first, lowercase, at most 24 (`base64` but not `64base` or `my-tool`).
    public static func isValidName(_ name: String) -> Bool {
        guard let first = name.first, first.isASCII, first.isLowercase, name.count <= maxNameLength else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
    }

    /// The name for `file`: its name without the extension, letters and digits from the first letter on,
    /// lowercased (`convert-timestamp.sh` → "converttimestamp", `base64.py` → "base64").
    public static func commandName(for file: URL) -> String {
        let kept = file.deletingPathExtension().lastPathComponent.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return String(kept.drop { !$0.isLetter }.prefix(maxNameLength))
    }

    /// Raycast leaves out files named like `name.template.sh`: they are filled in before use. So does this.
    public static func isTemplate(_ file: URL) -> Bool { file.lastPathComponent.contains(".template.") }

    static func terms(_ title: String, _ keywords: [String]) -> [String] {
        title.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init) + keywords.map { $0.lowercased() }
    }

    /// The emoji of its icon, if that's what it is.
    public var emoji: String? {
        if case let .emoji(emoji)? = icon { return emoji }
        return nil
    }

    /// Whether `text` is one emoji ("♊️", "👩🏽‍💻"), not a letter, digit or symbol name.
    static func isEmoji(_ text: String) -> Bool {
        guard text.count == 1, let first = text.unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || text.unicodeScalars.contains { $0.properties.isEmoji && $0.value > 0xFF }
    }
}

// MARK: - Reading the metadata

extension ScriptCommand {
    /// The two kinds of metadata lines.
    public enum FrontEnd: String, Hashable, Sendable {
        case native = "allinoneime"
        case raycast
    }

    /// The `@allinoneime.` (or else `@raycast.`) keys in `text` and their values: comment lines in any language
    /// (`# @allinoneime.title X`, `// …`, `-- …`). The first of a key wins; nil when there are none.
    public static func metadata(in text: String) -> (front: FrontEnd, keys: [String: String])? {
        var found: [FrontEnd: [String: String]] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            for front in [FrontEnd.native, .raycast] {
                guard let at = line.range(of: "@\(front.rawValue).") else { continue }
                // A comment mark before it, and nothing else (a line of text that mentions a key isn't metadata).
                let before = line[..<at.lowerBound]
                guard before.contains(where: { "#/-;%'*".contains($0) }),
                      before.allSatisfy({ $0.isWhitespace || "#/-;%'*".contains($0) }) else { continue }
                let rest = line[at.upperBound...]
                let key = rest.prefix { $0.isLetter || $0.isNumber }
                let value = rest.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty, !value.isEmpty, found[front]?[String(key)] == nil else { continue }
                found[front, default: [:]][String(key)] = value
            }
        }
        if let keys = found[.native] { return (.native, keys) }
        if let keys = found[.raycast] { return (.raycast, keys) }
        return nil
    }

    /// A Raycast script's keys as the protocol's (docs/extensions.md, "Raycast Script Commands"): `fullOutput`
    /// shows, `compact` and `silent` are silent, `inline` with `refreshTime` is a status (the script itself);
    /// `needsConfirmation` confirms; `packageName` is the group (the folder's name by default); no arguments is
    /// `input: none`.
    static func nativeKeys(fromRaycast raycast: [String: String], folder: URL) -> Result<[String: String], Problem> {
        for key in ["schemaVersion", "title", "mode"] where raycast[key] == nil { return .failure(.missing(key)) }
        // Raycast's own schema version (only 1 exists), not this protocol's.
        guard raycast["schemaVersion"] == "1" else { return .failure(.badValue(key: "schemaVersion", value: raycast["schemaVersion"]!)) }
        if let platform = raycast["platform"]?.lowercased(), !platform.contains("mac") { return .failure(.notForMac) }
        var keys = raycast.filter { ["schemaVersion", "title", "description", "icon", "currentDirectoryPath",
                                     "argument1", "argument2", "argument3"].contains($0.key) }
        switch raycast["mode"]! {
        case "fullOutput": keys["output"] = "show"
        case "compact", "silent": keys["output"] = "silent"
        case "inline":
            keys["output"] = "silent"
            if let refresh = raycast["refreshTime"] {
                keys["status"] = "self"
                keys["statusRefresh"] = refresh
            }
        case let mode: return .failure(.badValue(key: "mode", value: mode))
        }
        if raycast["needsConfirmation"]?.lowercased() == "true" { keys["confirm"] = "true" }
        keys["group"] = raycast["packageName"] ?? folder.lastPathComponent
        if !(1...maxArguments).contains(where: { raycast["argument\($0)"] != nil }) { keys["input"] = "none" }
        return .success(keys)
    }

    /// The command a file's text describes, or why it can't be one; nil without metadata (any other file in
    /// a folder). `executable`: the file may be run as it is.
    public static func read(_ text: String, file: URL, executable: Bool) -> Result<ScriptCommand, Problem>? {
        read(metadata(in: text), firstLine: firstLine(of: text), file: file, executable: executable)
    }

    /// `read`, from what a file's text holds that matters: its metadata and its first line (`ExtensionCache`
    /// keeps only these).
    static func read(_ metadata: (front: FrontEnd, keys: [String: String])?, firstLine: String,
                     file: URL, executable: Bool) -> Result<ScriptCommand, Problem>? {
        guard let (front, found) = metadata else { return nil }
        var keys = found
        if front == .raycast {
            switch nativeKeys(fromRaycast: found, folder: file.deletingLastPathComponent()) {
            case let .success(mapped): keys = mapped
            case let .failure(problem): return .failure(problem)
            }
        }
        guard let launch = launch(for: file, firstLine: firstLine, executable: executable) else { return .failure(.notRunnable) }
        return make(keys, source: front == .raycast ? .raycast : .script, file: file, launch: launch)
    }

    /// The first line of `text`.
    static func firstLine(of text: String) -> String {
        String(text.prefix { $0 != "\n" && $0 != "\r" })
    }

    /// How `file` is started, as a shell would: an executable runs as itself (a compiled program, `binary`, or a
    /// script with a "#!" line the system reads); a script that isn't executable, or whose "#!" line follows a
    /// byte order mark (the system doesn't read it then), runs through the program on that line ("#!/usr/bin/env
    /// python3" → /usr/bin/env python3 file); an executable text file without one runs with /bin/sh, as a shell
    /// does when the system can't run it (ENOEXEC). Nil when it's neither executable nor has a "#!" line.
    /// On Windows, which has no executable bit and reads no "#!" line, the file itself, which the launcher starts by its
    /// kind (`WindowsPrograms`): a program or batch file (`executable`), or a script through its interpreter (.sh, .ps1,
    /// .py, or one with a "#!" line); nil for any other file.
    static func launch(for file: URL, firstLine: String, executable: Bool, binary: Bool = false) -> [String]? {
        #if os(Windows)
        let line = firstLine.hasPrefix("\u{FEFF}") ? String(firstLine.dropFirst()) : firstLine
        let script = ["sh", "ps1", "py", "pyw"].contains(file.pathExtension.lowercased())
        return executable || script || line.hasPrefix("#!") ? [file.path] : nil
        #else
        if executable, binary { return [file.path] }
        let bom = firstLine.hasPrefix("\u{FEFF}")
        let line = bom ? String(firstLine.dropFirst()) : firstLine
        guard line.hasPrefix("#!") else { return executable ? ["/bin/sh", file.path] : nil }
        if executable, !bom { return [file.path] }
        let words = line.dropFirst(2).split(whereSeparator: \.isWhitespace).map(String.init)
        return words.isEmpty ? nil : words + [file.path]
        #endif
    }

    /// The command for the protocol's `keys` (a script's, a Raycast script's mapped, a bundle entry's), or the
    /// first key that can't be used. Keys it doesn't know are ignored: a newer extension still loads.
    public static func make(_ keys: [String: String], source: Source, file: URL, launch: [String], id: String? = nil,
                            extensionDirectory: URL? = nil) -> Result<ScriptCommand, Problem> {
        func bad(_ key: String) -> Problem { .badValue(key: key, value: keys[key] ?? "") }
        func bool(_ key: String) -> Bool? {
            guard let value = keys[key]?.lowercased() else { return false }
            return value == "true" ? true : value == "false" ? false : nil
        }
        guard let version = keys["schemaVersion"] else { return .failure(.missing("schemaVersion")) }
        guard let number = Int(version), number >= 1 else { return .failure(bad("schemaVersion")) }
        guard number <= protocolVersion else { return .failure(.newerProtocol(number)) }

        let name = keys["name"]?.lowercased() ?? commandName(for: file)
        if keys["name"] != nil, !isValidName(name) { return .failure(bad("name")) }
        guard !name.isEmpty else { return .failure(.noName) }
        let alias = keys["alias"]?.lowercased()
        if let alias, !isValidName(alias) { return .failure(bad("alias")) }
        var output = Output.insert
        if let value = keys["output"] {
            guard let known = Output(rawValue: value) else { return .failure(bad("output")) }
            output = known
        }
        var declared: Input?
        if let value = keys["input"] {
            guard let known = Input(rawValue: value) else { return .failure(bad("input")) }
            declared = known
        }

        var arguments: [Argument] = []
        for n in 1...maxArguments {
            guard let json = keys["argument\(n)"] else { continue }
            guard arguments.count == n - 1, let argument = argument(json) else { return .failure(.badArgument(n)) }
            arguments.append(argument)
        }
        // None declared: one free-text argument, required unless the input says otherwise.
        if arguments.isEmpty { arguments = [Argument()] }
        if declared == .optional { arguments = arguments.map { var a = $0; a.optional = true; return a } }
        // `required`: something must be written, so the first argument is, whatever it says.
        if declared == .required, arguments.allSatisfy(\.optional) { arguments[0].optional = false }
        let input = declared ?? (arguments.allSatisfy(\.optional) ? .optional : .required)

        guard let background = bool("background") else { return .failure(bad("background")) }
        guard let confirm = bool("confirm") else { return .failure(bad("confirm")) }
        var timeout: Double?
        if let value = keys["timeout"] {
            guard let seconds = Double(value), seconds > 0 else { return .failure(bad("timeout")) }
            timeout = seconds
        }
        var queryDelay = defaultQueryDelay
        if let value = keys["queryDelay"] {
            guard let ms = Double(value), ms >= 0 else { return .failure(bad("queryDelay")) }
            queryDelay = ms / 1000
        }
        let folder = file.deletingLastPathComponent()
        // A bundle's (a repository's) paths name its own files: from the script's folder as written, never out of it
        // (`CorePaths.file`, the rule its `"script"` has; nil when one leads out). A script of the user's own may point anywhere.
        let fromBundle: Bool
        if case .bundle = source { fromBundle = true } else { fromBundle = false }
        func anywhere(_ value: String) -> URL {
            let expanded = (value as NSString).expandingTildeInPath
            return (CorePaths.isAbsolute(expanded) ? URL(fileURLWithPath: expanded) : folder.appendingPathComponent(expanded)).standardizedFileURL
        }
        func path(_ value: String) -> URL? { fromBundle ? CorePaths.file(value, in: folder)?.standardizedFileURL : anywhere(value) }
        var status: Status?
        if let value = keys["status"] {
            var refresh = Status.defaultRefresh
            if let text = keys["statusRefresh"] {
                guard let seconds = duration(text) else { return .failure(bad("statusRefresh")) }
                refresh = max(seconds, Status.minimumRefresh)
            }
            if value == "self" || value == "true" {
                status = Status(launch: launch, refresh: refresh, isSelf: true)
            } else {
                // A command line (no shell), its program from the script's folder when it's there; a bare name that isn't
                // is a program the system finds (PATH). A bundle's program given as a path is one of the bundle's files.
                guard var argv = CustomCommand.arguments(fromCommandLine: value), let program = argv.first else {
                    return .failure(bad("status"))
                }
                if program.contains(where: CorePaths.isSeparator) || FileManager.default.fileExists(atPath: folder.appendingPathComponent(program).path) {
                    guard let url = path(program) else { return .failure(bad("status")) }
                    argv[0] = url.path
                }
                status = Status(launch: argv, refresh: refresh, isSelf: false)
            }
        }
        var icon: Icon?
        if let value = keys["icon"] {
            let images = ["png", "jpg", "jpeg", "gif", "tiff", "icns", "pdf", "heic"]
            if isEmoji(value) {
                icon = .emoji(value)
            } else if value.contains("://") {
                icon = nil  // never fetched
            } else if images.contains((value as NSString).pathExtension.lowercased()) {
                guard let url = path(value) else { return .failure(bad("icon")) }
                icon = .image(url)
            } else {
                icon = .symbol(value)
            }
        }
        var directory: URL?
        if let value = keys["currentDirectoryPath"] {
            // A bundle's from its script's folder stays in the bundle ("." is that folder); the home folder ("~/…") or an
            // absolute path is taken as it is: where it runs isn't what it runs.
            if fromBundle, !value.hasPrefix("~"), !CorePaths.isAbsolute(value) {
                let itself = CorePaths.isPlainRelative(value) && CorePaths.components(value).allSatisfy { $0 == "." }
                guard let url = itself ? folder.standardizedFileURL : path(value) else { return .failure(bad("currentDirectoryPath")) }
                directory = url
            } else {
                directory = anywhere(value)
            }
        }
        return .success(ScriptCommand(
            id: id, source: source, file: file, name: name, alias: alias, title: keys["title"] ?? name,
            description: keys["description"], group: keys["group"],
            keywords: keys["keywords"].map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } ?? [],
            icon: icon, input: input, arguments: arguments, output: output, background: background, status: status,
            confirm: confirm, timeout: timeout, queryDelay: queryDelay, directory: directory,
            extensionDirectory: extensionDirectory, launch: launch))
    }

    /// "10s", "5m", "1h", "1d", or plain seconds; nil for anything else.
    static func duration(_ text: String) -> TimeInterval? {
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        let units: [Character: Double] = ["s": 1, "m": 60, "h": 3600, "d": 86400]
        if let unit = text.last, let factor = units[unit], let value = Double(text.dropLast()), value > 0 { return value * factor }
        return Double(text).flatMap { $0 > 0 ? $0 : nil }
    }

    /// An `argumentN` value: `{"type": "dropdown", "placeholder": "unit", "data": [{"title": "Celsius", "value": "c"}]}`.
    /// Raycast's older `"secure": true` is a password.
    static func argument(_ json: String) -> Argument? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return nil }
        guard let kind = Argument.Kind(rawValue: object["type"] as? String ?? "text") else { return nil }
        var argument = Argument(kind: (object["secure"] as? Bool) == true ? .password : kind,
                                placeholder: object["placeholder"] as? String ?? "",
                                optional: object["optional"] as? Bool ?? false,
                                percentEncoded: object["percentEncoded"] as? Bool ?? false)
        if kind == .dropdown {
            let data = object["data"] as? [[String: Any]] ?? []
            argument.choices = data.compactMap { item in
                guard let value = item["value"].map({ "\($0)" }) else { return nil }
                return Argument.Choice(title: item["title"].map { "\($0)" } ?? value, value: value)
            }
            if argument.choices.isEmpty { return nil }
        }
        return argument
    }
}

// MARK: - Running

extension ScriptCommand {
    /// The text after the command as its arguments ($1 $2 $3). None: the text is ignored. One: the whole text.
    /// Two or three: split at commas (`,` or `，`), each trimmed; commas past the last split stay in the last
    /// one. A dropdown takes a choice's value or title (any case), and gets its value; `percentEncoded` ones
    /// are encoded. Empty required ones fail with their placeholders.
    public func arguments(from text: String) -> Result<[String], ArgumentProblem> {
        guard !arguments.isEmpty else { return .success([]) }
        let parts = Self.split(text, into: arguments.count)

        let missing = zip(arguments, parts).enumerated().filter { !$0.element.0.optional && $0.element.1.isEmpty }
            .map { $0.element.0.placeholder.isEmpty ? "$\($0.offset + 1)" : $0.element.0.placeholder }
        guard missing.isEmpty else { return .failure(.missing(missing)) }
        var values: [String] = []
        for (argument, part) in zip(arguments, parts) {
            var value = part
            if argument.kind == .dropdown, !part.isEmpty {
                let typed = part.lowercased()
                guard let choice = argument.choices.first(where: { $0.value.lowercased() == typed || $0.title.lowercased() == typed })
                else { return .failure(.notAChoice(argument.placeholder, argument.choices.map(\.title))) }
                value = choice.value
            }
            if argument.percentEncoded { value = value.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? value }
            values.append(value)
        }
        return .success(values)
    }

    /// `text` as `count` values, the way the arguments are read: split on "," or "，", the last taking the rest, each
    /// without the blank space at its ends; those not written are empty. (A snippet's blanks too: `SnippetTemplate`.)
    public static func split(_ text: String, into count: Int) -> [String] {
        guard count > 0 else { return [] }
        var parts: [String] = []
        var rest = Substring(text)
        while parts.count < count - 1, let comma = rest.firstIndex(where: { $0 == "," || $0 == "，" }) {
            parts.append(String(rest[..<comma]))
            rest = rest[rest.index(after: comma)...]
        }
        parts.append(String(rest))
        parts = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        while parts.count < count { parts.append("") }
        return parts
    }

    /// What a web address leaves as it is in a value (RFC 3986), like JavaScript's encodeURIComponent.
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

/// What a script is told about where it runs, besides its arguments (`environment`).
public struct ScriptContext: Equatable, Sendable {
    /// The interface language: "en" or "zh".
    public var language: String
    /// The input language being typed: "en", "zh", "fr", "ko" or "hi".
    public var inputLanguage: String
    /// The bundle id of the app being typed in.
    public var app: String?
    /// All the text after the command.
    public var query: String

    public init(language: String, inputLanguage: String, app: String?, query: String) {
        self.language = language
        self.inputLanguage = inputLanguage
        self.app = app
        self.query = query
    }

    /// The environment `command` runs with: `base` (the login shell's PATH and the rest), the protocol's
    /// `ALLINONEIME_*` variables and its bundle's preferences as `ALLINONEIME_PREF_<NAME>`. `status`: for its
    /// status line (`ALLINONEIME_STATUS=1`); `action`: a list item's `run` action (`ALLINONEIME_ACTION=run`).
    public func environment(for command: ScriptCommand, base: [String: String], preferences: [String: String] = [:],
                            status: Bool = false, action: Bool = false) -> [String: String] {
        var env = base
        env["ALLINONEIME_PROTOCOL"] = String(ScriptCommand.protocolVersion)
        env["ALLINONEIME_VERSION"] = AppVersion.string
        env["ALLINONEIME_LANGUAGE"] = language
        env["ALLINONEIME_INPUT_LANGUAGE"] = inputLanguage
        env["ALLINONEIME_APP"] = app ?? ""
        // A password argument's value isn't repeated in the environment, where any program it starts could read it.
        env["ALLINONEIME_QUERY"] = command.arguments.contains { $0.kind == .password } ? "" : query
        env["ALLINONEIME_EXTENSION_DIR"] = command.extensionDirectory.path
        if status { env["ALLINONEIME_STATUS"] = "1" }
        if action { env["ALLINONEIME_ACTION"] = "run" }
        for (name, value) in preferences { env[ExtensionBundle.Preference.variable(name)] = value }
        return env
    }
}

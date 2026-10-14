import Foundation

/// A Raycast Script Command (github.com/raycast/script-commands): a script in any language whose
/// comments carry `@raycast.*` metadata, run as an @ command named after its file:
///
///     #!/bin/bash
///     # @raycast.schemaVersion 1
///     # @raycast.title Flights
///     # @raycast.mode compact
///     # @raycast.argument1 { "type": "text", "placeholder": "from city" }
///     # @raycast.argument2 { "type": "text", "placeholder": "to city" }
///
/// `flights.sh` is `@flights`; `@flights beijing, new york` runs it with "beijing" and "new york" as
/// $1 and $2 (`arguments(from:)`). How its output is used follows its `mode` (`result(for:)`).
public struct RaycastScript: Hashable, Sendable {
    public enum Mode: String, Hashable, Sendable, CaseIterable {
        /// Everything it printed, to insert (and each line on its own).
        case fullOutput
        /// The last line it printed, to insert.
        case compact
        /// The last line it printed, as a notice; nothing is inserted.
        case silent
        /// Raycast refreshes its first line in the list; here it is `compact` (no refreshing).
        case inline
    }

    /// One of `argument1`…`argument3`: `{"type": "text", "placeholder": "city", "optional": true}`.
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

    /// Why a file with `@raycast.` metadata isn't a command (shown in Settings).
    public enum Problem: Error, Hashable, Sendable {
        /// A required key (`schemaVersion`, `title`, `mode`) is missing.
        case missing(String)
        /// A `schemaVersion` other than 1.
        case schemaVersion(String)
        case unknownMode(String)
        /// `argumentN` isn't JSON this understands, or comes after a missing one.
        case badArgument(Int)
        /// Not executable, and no "#!" line to run it with.
        case notRunnable
        /// No letters in the file name to type after "@".
        case noName
        /// Its `platform` leaves out macOS.
        case notForMac
        /// Another command already has its name (the first one wins).
        case nameTaken(by: Owner)
    }

    /// What has a name a script wanted.
    public enum Owner: Hashable, Sendable {
        case builtIn, plugin, custom
        /// An earlier script, in this file.
        case script(URL)
    }

    /// What keeps the text typed after the command from running it (shown as a notice).
    public enum ArgumentProblem: Error, Equatable, Sendable {
        /// Required arguments left empty: their placeholders.
        case missing([String])
        /// A dropdown value that isn't one of its choices: the placeholder, and the choices' titles.
        case notAChoice(String, [String])
    }

    public var file: URL
    /// What follows "@": the file name's letters, lowercased (`commandName(for:)`).
    public var name: String
    public var title: String
    public var mode: Mode
    /// Shown after the title; the folder's name unless the script names one.
    public var packageName: String
    /// An emoji, an image file or a web address (only an emoji is shown).
    public var icon: String?
    public var description: String?
    public var author: String?
    /// Asks before running: the action key once shows what will run, again runs it.
    public var needsConfirmation: Bool
    public var arguments: [Argument]
    /// Where it runs: its `currentDirectoryPath`, else its own folder.
    public var directory: URL
    /// How it is started, before its arguments: the file itself when it is executable, else the "#!"
    /// line's program with the file.
    public var launch: [String]

    public init(file: URL, name: String, title: String, mode: Mode, packageName: String, icon: String? = nil,
                description: String? = nil, author: String? = nil, needsConfirmation: Bool = false,
                arguments: [Argument] = [], directory: URL? = nil, launch: [String]? = nil) {
        self.file = file
        self.name = name
        self.title = title
        self.mode = mode
        self.packageName = packageName
        self.icon = icon
        self.description = description
        self.author = author
        self.needsConfirmation = needsConfirmation
        self.arguments = arguments
        self.directory = directory ?? file.deletingLastPathComponent()
        self.launch = launch ?? [file.path]
    }

    /// Raycast's own limit.
    public static let maxArguments = 3
    /// A `fullOutput` script may take longer (it shows a whole report); the others stop after the run
    /// commands' default (`CustomCommand.defaultTimeout`). Esc stops any of them.
    public static let fullOutputTimeout: Double = 60

    public var timeout: Double { mode == .fullOutput ? Self.fullOutputTimeout : CustomCommand.defaultTimeout }

    /// Picked from the list, it runs at once: nothing is written after it.
    public var runsWhenPicked: Bool { arguments.isEmpty }

    /// The icon when it is an emoji ("♊️"), else nil.
    public var emoji: String? {
        guard let icon, icon.count == 1, let first = icon.unicodeScalars.first else { return nil }
        return first.properties.isEmojiPresentation || icon.unicodeScalars.contains { $0.properties.isEmoji && $0.value > 0xFF }
            ? icon : nil
    }

    // MARK: Reading a file

    /// The command name for `file`: its name without the extension, letters only, lowercased
    /// (`convert-timestamp.sh` → "converttimestamp"); at most 24 letters, as any command's.
    public static func commandName(for file: URL) -> String {
        String(file.deletingPathExtension().lastPathComponent.lowercased().filter { $0.isASCII && $0.isLetter }.prefix(24))
    }

    /// Raycast leaves out files named like `name.template.sh`: they are filled in before use.
    public static func isTemplate(_ file: URL) -> Bool { file.lastPathComponent.contains(".template.") }

    /// The `@raycast.` keys in `text` and their values: comment lines in any language (`# @raycast.title X`,
    /// `// @raycast.title X`, `-- @raycast.title X`). The first of a key wins.
    public static func metadata(in text: String) -> [String: String] {
        var keys: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let at = line.range(of: "@raycast.") else { continue }
            // Only comment marks before it.
            guard line[..<at.lowerBound].allSatisfy({ $0.isWhitespace || "#/-;%'*".contains($0) }) else { continue }
            let rest = line[at.upperBound...]
            let key = rest.prefix { $0.isLetter || $0.isNumber }
            let value = rest.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty, keys[String(key)] == nil else { continue }
            keys[String(key)] = value
        }
        return keys
    }

    /// The script in `file` (its `text`): nil when it has no `@raycast.` metadata (any other file in the
    /// folder), else the script or why it can't be one. `executable`: the file may be run as it is.
    public static func read(_ text: String, file: URL, executable: Bool) -> Result<RaycastScript, Problem>? {
        let keys = metadata(in: text)
        guard !keys.isEmpty else { return nil }
        for key in ["schemaVersion", "title", "mode"] where keys[key] == nil { return .failure(.missing(key)) }
        guard keys["schemaVersion"] == "1" else { return .failure(.schemaVersion(keys["schemaVersion"]!)) }
        guard let mode = Mode(rawValue: keys["mode"]!) else { return .failure(.unknownMode(keys["mode"]!)) }
        if let platform = keys["platform"]?.lowercased(), !platform.contains("mac") { return .failure(.notForMac) }
        var arguments: [Argument] = []
        for n in 1...maxArguments {
            guard let json = keys["argument\(n)"] else { continue }
            guard arguments.count == n - 1, let argument = argument(json) else { return .failure(.badArgument(n)) }
            arguments.append(argument)
        }
        let launch: [String]
        if executable {
            launch = [file.path]
        } else if let shebang = text.split(separator: "\n", maxSplits: 1).first, shebang.hasPrefix("#!") {
            // "#!/usr/bin/env python3" → /usr/bin/env python3 file
            let words = shebang.dropFirst(2).split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty else { return .failure(.notRunnable) }
            launch = words + [file.path]
        } else {
            return .failure(.notRunnable)
        }
        let name = commandName(for: file)
        guard !name.isEmpty else { return .failure(.noName) }
        let folder = file.deletingLastPathComponent()
        let directory = keys["currentDirectoryPath"].map { path in
            let expanded = (path as NSString).expandingTildeInPath
            return expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : folder.appendingPathComponent(expanded)
        }
        return .success(RaycastScript(
            file: file, name: name, title: keys["title"]!, mode: mode,
            packageName: keys["packageName"] ?? folder.lastPathComponent, icon: keys["icon"],
            description: keys["description"], author: keys["author"],
            needsConfirmation: keys["needsConfirmation"]?.lowercased() == "true", arguments: arguments,
            directory: directory, launch: launch))
    }

    /// An `argumentN` value: `{"type": "dropdown", "placeholder": "unit", "data": [{"title": "Celsius", "value": "c"}]}`.
    /// The older `"secure": true` is a password.
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

    // MARK: Running

    /// The text after the command as the script's arguments ($1 $2 $3). None: the text is ignored. One:
    /// the whole text. Two or three: split at commas (`,` or `，`), each trimmed; commas past the last
    /// split stay in the last one. A dropdown takes a choice's value or title (any case), and gets its
    /// value; `percentEncoded` ones are encoded. Empty required ones fail with their placeholders.
    public func arguments(from text: String) -> Result<[String], ArgumentProblem> {
        guard !arguments.isEmpty else { return .success([]) }
        var parts: [String] = []
        var rest = Substring(text)
        while parts.count < arguments.count - 1, let comma = rest.firstIndex(where: { $0 == "," || $0 == "，" }) {
            parts.append(String(rest[..<comma]))
            rest = rest[rest.index(after: comma)...]
        }
        parts.append(String(rest))
        parts = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        while parts.count < arguments.count { parts.append("") }

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

    /// What a web address leaves as it is in a value (RFC 3986), like JavaScript's encodeURIComponent.
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// What it printed (cleaned, `CommandRunner.cleanOutput`), as its result: `fullOutput` all of it, then
    /// each line (when there are several, as many as the list has numbers for); the other modes its last line.
    public func result(for output: String) -> ConversionResult {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        switch mode {
        case .fullOutput:
            guard !output.isEmpty else { return .empty }
            let each = lines.count > 1 ? lines.prefix(8).map { CandidateLine($0) } : []
            return ConversionResult(versions: [CandidateLine(output)] + each)
        case .compact, .silent, .inline:
            return ConversionResult(versions: lines.last.map { [CandidateLine($0)] } ?? [])
        }
    }
}

/// The Raycast scripts in the user's folders: the ones added (`Config.scriptFolders`) and, unless turned
/// off, the ones Spotlight found holding scripts (`discover`), less those hidden.
public enum RaycastScriptStore {
    /// Suggested for scripts of one's own, and in the list from the start.
    public static let defaultFolder = "~/.config/allinoneime/scripts"

    /// A folder looked in: added by the user, or found (`discover`).
    public struct Folder: Hashable, Sendable {
        /// As written in the config ("~/…").
        public var path: String
        public var found: Bool
        public var hidden: Bool

        public init(path: String, found: Bool, hidden: Bool = false) {
            self.path = path
            self.found = found
            self.hidden = hidden
        }

        public var url: URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true) }
    }

    /// A file with `@raycast.` metadata that isn't a command, and why.
    public struct Skipped: Hashable, Sendable {
        public var file: URL
        public var problem: RaycastScript.Problem

        public init(file: URL, problem: RaycastScript.Problem) {
            self.file = file
            self.problem = problem
        }
    }

    /// The folders of `config`: the ones added, in their order, then the ones found (`found`) that aren't
    /// added already, those hidden marked so (with `findRaycastScripts` off, none found).
    public static func folders(_ config: Config, found: [String]) -> [Folder] {
        let added = config.scriptFolders.map { Folder(path: $0, found: false) }
        guard config.findRaycastScripts else { return added }
        let addedURLs = Set(added.map(\.url.standardizedFileURL.path))
        let hidden = Set(config.hiddenScriptFolders.map { Folder(path: $0, found: true).url.standardizedFileURL.path })
        return added + found.compactMap { path in
            let folder = Folder(path: path, found: true)
            let key = folder.url.standardizedFileURL.path
            guard !addedURLs.contains(key) else { return nil }
            return Folder(path: path, found: true, hidden: hidden.contains(key))
        }
    }

    /// The scripts in `folders` (not those hidden), folder by folder, each folder's files by name (not its
    /// subfolders, as in Raycast), and the files with metadata that were skipped. Two scripts with one name:
    /// the first is kept (`nameTaken(by: .script)`).
    public static func load(_ folders: [Folder]) -> (scripts: [RaycastScript], skipped: [Skipped]) {
        var scripts: [RaycastScript] = []
        var skipped: [Skipped] = []
        var byName: [String: URL] = [:]
        for folder in folders where !folder.hidden {
            for file in files(in: folder.url) {
                guard let read = read(file) else { continue }
                switch read {
                case let .success(script):
                    if let first = byName[script.name] {
                        skipped.append(Skipped(file: file, problem: .nameTaken(by: .script(first))))
                    } else {
                        byName[script.name] = file
                        scripts.append(script)
                    }
                case let .failure(problem):
                    skipped.append(Skipped(file: file, problem: problem))
                }
            }
        }
        return (scripts, skipped)
    }

    /// The files in `folder` that may be scripts, by name: not hidden, not templates, not folders.
    static func files(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                        options: [.skipsHiddenFiles]) else { return [] }
        return items.filter { (try? $0.resourceValues(forKeys: Set(keys)))?.isRegularFile == true && !RaycastScript.isTemplate($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Scripts are small: metadata past the first 64 KB isn't looked for.
    static let maxBytes = 64 * 1024

    /// The script in `file`, why it isn't one, or nil for a file without metadata.
    public static func read(_ file: URL) -> Result<RaycastScript, RaycastScript.Problem>? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes), !data.contains(0) else { return nil }  // not a binary
        return RaycastScript.read(String(decoding: data, as: UTF8.self), file: file,
                                  executable: FileManager.default.isExecutableFile(atPath: file.path))
    }

    /// What changes when a script is added, removed or edited in `folders`: each file's modification date.
    /// A listing, cheap enough each time a text field becomes active.
    public static func signature(_ folders: [Folder]) -> [String: Date] {
        var dates: [String: Date] = [:]
        for folder in folders where !folder.hidden {
            let items = (try? FileManager.default.contentsOfDirectory(at: folder.url, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                      options: [.skipsHiddenFiles])) ?? []
            for item in items {
                dates[item.path] = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            }
        }
        return dates
    }

    /// The Spotlight query for files with Raycast metadata (Raycast keeps its own list encrypted).
    static let query = "kMDItemTextContent == \"*@raycast.schemaVersion*\"c"

    /// The folders holding scripts on this Mac, by Spotlight: the parent folders of the files that have
    /// Raycast metadata and are scripts (not code or notes that only mention it), as "~/…", sorted. Not those
    /// in hidden folders or ~/Library (apps' caches and copies), nor templates. Slow (a Spotlight search, and
    /// the files read): never on a keystroke.
    public static func discover(spotlight: Spotlight = Spotlight(until: .now() + 20)) -> [String] {
        guard let data = spotlight.mdfind([query]) else { return [] }
        return folders(fromSpotlight: String(decoding: data, as: UTF8.self))
    }

    /// The folders of the files `mdfind` printed (one path a line) that are scripts (`isScript`).
    static func folders(fromSpotlight output: String, home: String = NSHomeDirectory(),
                        isScript: (URL) -> Bool = { if case .success? = read($0) { true } else { false } }) -> [String] {
        var folders = Set<String>()
        for line in output.split(separator: "\n") {
            let file = URL(fileURLWithPath: String(line))
            let parts = file.pathComponents
            guard !RaycastScript.isTemplate(file), !parts.dropLast().contains(where: { $0.hasPrefix(".") }),
                  !file.path.hasPrefix(home + "/Library/"), !parts.contains("node_modules") else { continue }
            let folder = abbreviated(file.deletingLastPathComponent().path, home: home)
            guard !folders.contains(folder), isScript(file) else { continue }
            folders.insert(folder)
        }
        return folders.sorted()
    }

    /// `path` with the home folder as "~".
    public static func abbreviated(_ path: String, home: String = NSHomeDirectory()) -> String {
        path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

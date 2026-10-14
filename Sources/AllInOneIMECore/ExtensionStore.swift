import Foundation

/// A bundle of script extensions: a folder with an `extension.json` naming its commands, which may share code
/// (a `lib/` folder) and settings (`preferences`). One folder to install, update or remove.
///
///     { "schemaVersion": 1, "name": "units", "title": "Unit Converter", "version": "1.0.0", "author": "…",
///       "preferences": [{ "name": "precision", "type": "textfield", "title": "Decimals", "default": "2" }],
///       "commands": [{ "script": "convert.sh", "name": "convert", "output": "list" }] }
///
/// A command's keys are the protocol's (`ScriptCommand.make`), in JSON; they override the `@allinoneime.`
/// lines in its script, if it has any.
public struct ExtensionBundle: Hashable, Sendable {
    /// A setting of the bundle, in Raycast's shape; its value reaches every command as `ALLINONEIME_PREF_<NAME>`.
    public struct Preference: Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable {
            /// A password is kept in the keychain, never in a file.
            case textfield, password, checkbox, dropdown
        }

        public var name: String
        public var kind: Kind
        public var title: String
        public var description: String?
        public var required: Bool
        public var defaultValue: String?
        /// `dropdown`: its choices.
        public var choices: [ScriptCommand.Argument.Choice]

        public init(name: String, kind: Kind = .textfield, title: String? = nil, description: String? = nil,
                    required: Bool = false, defaultValue: String? = nil, choices: [ScriptCommand.Argument.Choice] = []) {
            self.name = name
            self.kind = kind
            self.title = title ?? name
            self.description = description
            self.required = required
            self.defaultValue = defaultValue
            self.choices = choices
        }

        /// The environment variable: `ALLINONEIME_PREF_` and the name in capitals, anything but letters and
        /// digits as "_" (`apiToken` → `ALLINONEIME_PREF_APITOKEN`).
        public static func variable(_ name: String) -> String {
            "ALLINONEIME_PREF_" + String(name.uppercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "_" })
        }

        /// The keychain account of a password (`APIKeys.save(_:account:label:)`).
        public static func keychainAccount(bundle: String, name: String) -> String { "extension.\(bundle).\(name)" }
    }

    public var folder: URL
    /// Its id: letters, digits, "-" and "_"; two bundles can't share one.
    public var name: String
    public var title: String
    public var version: String?
    public var author: String?
    public var description: String?
    public var preferences: [Preference]

    public init(folder: URL, name: String, title: String? = nil, version: String? = nil, author: String? = nil,
                description: String? = nil, preferences: [Preference] = []) {
        self.folder = folder
        self.name = name
        self.title = title ?? name
        self.version = version
        self.author = author
        self.description = description
        self.preferences = preferences
    }

    public static let manifestName = "extension.json"

    /// The values its commands get: `stored` (what was set; passwords read from the keychain) or each
    /// preference's default. Checkboxes are "true" or "false".
    public func values(_ stored: [String: String]) -> [String: String] {
        var values: [String: String] = [:]
        for preference in preferences {
            if let value = stored[preference.name] ?? preference.defaultValue ?? (preference.kind == .checkbox ? "false" : nil) {
                values[preference.name] = value
            }
        }
        return values
    }

    /// The required preferences that have no value yet: its commands don't run until they're set.
    public func missing(_ stored: [String: String]) -> [Preference] {
        let values = values(stored)
        return preferences.filter { $0.required && (values[$0.name] ?? "").isEmpty }
    }

    /// The bundle in `folder` and its commands' entries (the keys of each, as strings), or why it can't be read.
    static func read(_ data: Data, folder: URL) -> Result<(ExtensionBundle, [[String: String]]), ScriptCommand.Problem> {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.badBundle("extension.json isn't a JSON object"))
        }
        guard let version = json["schemaVersion"] as? Int else { return .failure(.missing("schemaVersion")) }
        guard version <= ScriptCommand.protocolVersion else { return .failure(.newerProtocol(version)) }
        guard let name = json["name"] as? String, !name.isEmpty,
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            return .failure(.badBundle("its name must be letters, digits, - or _"))
        }
        guard let commands = json["commands"] as? [[String: Any]], !commands.isEmpty else {
            return .failure(.badBundle("no commands"))
        }
        var preferences: [Preference] = []
        for item in json["preferences"] as? [[String: Any]] ?? [] {
            guard let name = item["name"] as? String, !name.isEmpty,
                  let kind = Preference.Kind(rawValue: item["type"] as? String ?? "textfield") else {
                return .failure(.badBundle("a preference needs a name and a known type"))
            }
            let choices = (item["data"] as? [[String: Any]] ?? []).compactMap { choice -> ScriptCommand.Argument.Choice? in
                guard let value = choice["value"].map({ "\($0)" }) else { return nil }
                return .init(title: choice["title"].map { "\($0)" } ?? value, value: value)
            }
            let fallback = item["default"].map { value -> String in
                if let flag = value as? Bool { return flag ? "true" : "false" }
                return "\(value)"
            }
            preferences.append(Preference(name: name, kind: kind, title: item["title"] as? String,
                                          description: item["description"] as? String, required: item["required"] as? Bool ?? false,
                                          defaultValue: fallback, choices: choices))
        }
        let bundle = ExtensionBundle(folder: folder, name: name, title: json["title"] as? String, version: json["version"].map { "\($0)" },
                                     author: json["author"] as? String, description: json["description"] as? String,
                                     preferences: preferences)
        // Each entry's keys as the scripts write them: strings as they are, true/false, numbers, JSON for the rest.
        let entries = commands.map { entry in
            var keys: [String: String] = ["schemaVersion": String(version)]
            for (key, value) in entry {
                switch value {
                case let text as String: keys[key] = text
                case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): keys[key] = number.boolValue ? "true" : "false"
                case let number as NSNumber: keys[key] = number.stringValue
                default:
                    if let data = try? JSONSerialization.data(withJSONObject: value) { keys[key] = String(decoding: data, as: UTF8.self) }
                }
            }
            return keys
        }
        return .success((bundle, entries))
    }
}

/// What the folders hold: the commands in the order their names are given out (a bundle's, then single
/// scripts', then Raycast scripts', each in folder order), the bundles, and what was left out and why.
public struct ExtensionIndex: Equatable, Sendable {
    public var commands: [ScriptCommand]
    public var bundles: [ExtensionBundle]
    public var skipped: [ExtensionStore.Skipped]

    public init(commands: [ScriptCommand] = [], bundles: [ExtensionBundle] = [], skipped: [ExtensionStore.Skipped] = []) {
        self.commands = commands
        self.bundles = bundles
        self.skipped = skipped
    }

    public static let empty = ExtensionIndex()

    public func bundle(of command: ScriptCommand) -> ExtensionBundle? {
        command.source.bundleName.flatMap { name in bundles.first { $0.name == name } }
    }

    /// The commands not turned off (`Config.disabledExtensions`: a command's id, or a bundle's name).
    public func enabled(_ disabled: [String]) -> [ScriptCommand] {
        let off = Set(disabled)
        return commands.filter { !off.contains($0.id) && !($0.source.bundleName.map(off.contains) ?? false) }
    }
}

/// The folders of script extensions: the ones added (`Config.extensionFolders`) and, unless turned off, the
/// ones Spotlight found holding Raycast scripts (`discover`), less those hidden.
public enum ExtensionStore {
    /// In the list from the start, for one's own scripts and bundles.
    public static let defaultFolder = "~/.config/allinoneime/extensions"

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

    /// A script or bundle that isn't loaded, or a command left out, and why.
    public struct Skipped: Hashable, Sendable {
        public var file: URL
        public var problem: ScriptCommand.Problem

        public init(file: URL, problem: ScriptCommand.Problem) {
            self.file = file
            self.problem = problem
        }
    }

    /// The folders of `config`: the ones added, in their order, then the ones found (`found`) that aren't
    /// added already, those hidden marked so (with `findRaycastScripts` off, none found).
    public static func folders(_ config: Config, found: [String]) -> [Folder] {
        let added = config.extensionFolders.map { Folder(path: $0, found: false) }
        guard config.findRaycastScripts else { return added }
        let addedPaths = Set(added.map(\.url.standardizedFileURL.path))
        let hidden = Set(config.hiddenExtensionFolders.map { Folder(path: $0, found: true).url.standardizedFileURL.path })
        return added + found.compactMap { path in
            let key = Folder(path: path, found: true).url.standardizedFileURL.path
            guard !addedPaths.contains(key) else { return nil }
            return Folder(path: path, found: true, hidden: hidden.contains(key))
        }
    }

    /// Reads `folders` (not those hidden): each one's bundles (subfolders with `extension.json`) and scripts,
    /// by name, not deeper (as Raycast does). Files are read only when their size or date changed since
    /// `cache` last saw them. Templates (`*.template.*`) and hidden files are left out.
    public static func load(_ folders: [Folder], cache: ExtensionCache = ExtensionCache()) -> ExtensionIndex {
        var bundles: [(ExtensionBundle, [ScriptCommand])] = []
        var scripts: [ScriptCommand] = []
        var skipped: [Skipped] = []
        for folder in folders where !folder.hidden {
            for item in items(in: folder.url) {
                if item.isFolder {
                    let manifest = item.url.appendingPathComponent(ExtensionBundle.manifestName)
                    guard let data = cache.read(manifest)?.data else { continue }
                    switch loadBundle(data, folder: item.url, cache: cache) {
                    case let .success((bundle, commands, problems)):
                        if bundles.contains(where: { $0.0.name == bundle.name }) {
                            skipped.append(Skipped(file: manifest, problem: .bundleTaken))
                            continue
                        }
                        bundles.append((bundle, commands))
                        skipped += problems
                    case let .failure(problem):
                        skipped.append(Skipped(file: manifest, problem: problem))
                    }
                } else if let file = cache.read(item.url), let text = file.text,
                          let read = ScriptCommand.read(text, file: item.url, executable: file.executable) {
                    switch read {
                    case var .success(command):
                        command.id = abbreviated(item.url.path)
                        scripts.append(command)
                    case let .failure(problem): skipped.append(Skipped(file: item.url, problem: problem))
                    }
                }
            }
        }
        // Bundles first, then single scripts, then Raycast's (stable within each).
        let ordered = bundles.flatMap(\.1) + scripts.filter { $0.source == .script } + scripts.filter { $0.source == .raycast }
        return ExtensionIndex(commands: ordered, bundles: bundles.map(\.0), skipped: skipped)
    }

    /// A bundle's commands (each entry's keys over its script's own `@allinoneime.` lines), and the entries
    /// that can't be used.
    static func loadBundle(_ data: Data, folder: URL, cache: ExtensionCache)
        -> Result<(ExtensionBundle, [ScriptCommand], [Skipped]), ScriptCommand.Problem> {
        let bundle: ExtensionBundle, entries: [[String: String]]
        switch ExtensionBundle.read(data, folder: folder) {
        case let .success(read): (bundle, entries) = read
        case let .failure(problem): return .failure(problem)
        }
        var commands: [ScriptCommand] = []
        var skipped: [Skipped] = []
        for entry in entries {
            guard let script = entry["script"], !script.hasPrefix("/"), !script.split(separator: "/").contains("..") else {
                skipped.append(Skipped(file: folder.appendingPathComponent(ExtensionBundle.manifestName), problem: .badValue(key: "script", value: entry["script"] ?? "")))
                continue
            }
            let file = folder.appendingPathComponent(script)
            let read = cache.read(file)
            let text = read?.text ?? ""
            guard let read, let launch = ScriptCommand.launch(for: file, text: text, executable: read.executable) else {
                skipped.append(Skipped(file: file, problem: .notRunnable))
                continue
            }
            var keys = ScriptCommand.metadata(in: text).flatMap { $0.front == .native ? $0.keys : nil } ?? [:]
            keys.merge(entry) { $1 }
            keys["script"] = nil
            let name = keys["name"]?.lowercased() ?? ScriptCommand.commandName(for: file)
            switch ScriptCommand.make(keys, source: .bundle(bundle.name), file: file, launch: launch, id: "\(bundle.name)/\(name)",
                                      extensionDirectory: folder) {
            case var .success(command):
                if command.group == nil { command.group = bundle.title }
                commands.append(command)
            case let .failure(problem): skipped.append(Skipped(file: file, problem: problem))
            }
        }
        return .success((bundle, commands, skipped))
    }

    /// The files and folders in `folder`, by name: not hidden ones, not templates.
    static func items(in folder: URL) -> [(url: URL, isFolder: Bool)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                        options: [.skipsHiddenFiles]) else { return [] }
        return items.filter { !ScriptCommand.isTemplate($0) }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { return (url, true) }
            return values?.isRegularFile == true ? (url, false) : nil
        }
    }

    /// The Spotlight query for files with Raycast metadata (Raycast keeps its own list encrypted).
    static let query = "kMDItemTextContent == \"*@raycast.schemaVersion*\"c"

    /// The folders holding Raycast scripts on this Mac, by Spotlight: the parent folders of the files that have
    /// Raycast metadata and are scripts (not code or notes that only mention it), as "~/…", sorted. Not those
    /// in hidden folders or ~/Library (apps' caches and copies), nor templates. Slow (a Spotlight search, and
    /// the files read): never on a keystroke.
    public static func discover(spotlight: Spotlight = Spotlight(until: .now() + 20)) -> [String] {
        guard let data = spotlight.mdfind([query]) else { return [] }
        return folders(fromSpotlight: String(decoding: data, as: UTF8.self))
    }

    /// The folders of the files `mdfind` printed (one path a line) that are scripts (`isScript`).
    static func folders(fromSpotlight output: String, home: String = NSHomeDirectory(),
                        isScript: (URL) -> Bool = ExtensionStore.isScript) -> [String] {
        var folders = Set<String>()
        for line in output.split(separator: "\n") {
            let file = URL(fileURLWithPath: String(line))
            let parts = file.pathComponents
            guard !ScriptCommand.isTemplate(file), !parts.dropLast().contains(where: { $0.hasPrefix(".") }),
                  !file.path.hasPrefix(home + "/Library/"), !parts.contains("node_modules") else { continue }
            let folder = abbreviated(file.deletingLastPathComponent().path, home: home)
            guard !folders.contains(folder), isScript(file) else { continue }
            folders.insert(folder)
        }
        return folders.sorted()
    }

    static func isScript(_ file: URL) -> Bool {
        guard let read = ExtensionCache().read(file), let text = read.text,
              case .success? = ScriptCommand.read(text, file: file, executable: read.executable) else { return false }
        return true
    }

    /// `path` with the home folder as "~".
    public static func abbreviated(_ path: String, home: String = NSHomeDirectory()) -> String {
        path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// The files read for the index, by path, kept while their size and modification date stay the same: a
/// rebuild only reads what changed. Safe to use from any thread.
public final class ExtensionCache: @unchecked Sendable {
    public struct File: Sendable {
        var date: Date
        var size: Int
        /// The first `maxBytes` (nil for a binary file).
        public var data: Data?
        public var executable: Bool
        public var text: String? { data.map { String(decoding: $0, as: UTF8.self) } }
    }

    private var files: [String: File] = [:]
    private let lock = NSLock()
    /// Metadata past the first 64 KB isn't looked for; an `extension.json` is smaller.
    static let maxBytes = 64 * 1024

    public init() {}

    /// `url`'s first bytes and whether it may run, from the cache when its size and date are the same; nil when
    /// it isn't a readable file.
    public func read(_ url: URL) -> File? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
        let date = attributes[.modificationDate] as? Date ?? .distantPast
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if let cached = lock.withLock({ files[url.path] }), cached.date == date, cached.size == size { return cached }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: Self.maxBytes)) ?? Data()
        let file = File(date: date, size: size, data: data.contains(0) ? nil : data,
                        executable: FileManager.default.isExecutableFile(atPath: url.path))
        lock.withLock { files[url.path] = file }
        return file
    }

    /// How many files it holds (for the tests).
    var count: Int { lock.withLock { files.count } }
}

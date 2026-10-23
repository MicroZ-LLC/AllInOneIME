import Crypto
import Foundation

/// A bundle of script extensions: a folder with an `extension.json` naming its commands, which may share code
/// (a `lib/` folder) and settings (`preferences`). One folder to install, update or remove.
///
///     { "schemaVersion": 1, "name": "units", "title": "Unit Converter", "version": "1.0.0", "author": "…",
///       "preferences": [{ "name": "precision", "type": "textfield", "title": "Decimals", "default": "2" }],
///       "commands": [{ "script": "convert.sh", "name": "convert", "output": "list" }] }
///
/// A command's keys are the protocol's (`ScriptCommand.make`), in JSON; they override the `@allinoneime.`
/// lines in its script, if it has any. A bundle may also ship snippets (texts to insert, `BundleSnippet`), or only them:
///
///     "snippets": [{ "name": "addr", "text": "1 Main Street\nSpringfield", "summary": "Office address", "alias": "teamaddr" }]
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

    /// The bundle in `folder`, its commands' entries and its snippets' (the keys of each, as strings), and what's wrong
    /// in it that doesn't keep the rest from loading (`problems`: a list that isn't one of entries next to one that is, a
    /// snippet whose `text`, `name` … isn't a string); or why it can't be read. It must have a command or a snippet.
    static func read(_ data: Data, folder: URL)
        -> Result<(bundle: ExtensionBundle, commands: [[String: String]], snippets: [[String: String]],
                   problems: [ScriptCommand.Problem]), ScriptCommand.Problem> {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.badBundle(.notJSON))
        }
        guard let version = json["schemaVersion"] as? Int else { return .failure(.missing("schemaVersion")) }
        guard version <= ScriptCommand.protocolVersion else { return .failure(.newerProtocol(version)) }
        guard let name = json["name"] as? String, !name.isEmpty,
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            return .failure(.badBundle(.badName))
        }
        var problems: [ScriptCommand.Problem] = []
        // A list of entries; one that isn't (a string, an object, a number among them) is said, not ignored.
        func entries(_ key: String) -> [[String: Any]] {
            guard let value = json[key] else { return [] }
            if let list = value as? [[String: Any]] { return list }
            problems.append(.badValue(key: key, value: Self.shown(value)))
            return []
        }
        let commands = entries("commands")
        let snippets = entries("snippets")
        guard !commands.isEmpty || !snippets.isEmpty else { return .failure(.badBundle(.noCommands)) }
        var preferences: [Preference] = []
        for item in json["preferences"] as? [[String: Any]] ?? [] {
            guard let name = item["name"] as? String, !name.isEmpty,
                  let kind = Preference.Kind(rawValue: item["type"] as? String ?? "textfield") else {
                return .failure(.badBundle(.badPreference))
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
        func strings(_ entry: [String: Any], _ start: [String: String]) -> [String: String] {
            var keys = start
            for (key, value) in entry {
                switch value {
                case let text as String: keys[key] = text
                case let number as NSNumber where number.isBoolean: keys[key] = number.boolValue ? "true" : "false"
                case let number as NSNumber: keys[key] = number.stringValue
                default:
                    if let data = try? JSONSerialization.data(withJSONObject: value) { keys[key] = String(decoding: data, as: UTF8.self) }
                }
            }
            return keys
        }
        // A snippet's keys are all text: one that isn't (`"text": ["a", "b"]`, `"text": 42`) leaves the snippet out.
        let snippetEntries = snippets.compactMap { entry -> [String: String]? in
            for key in BundleSnippet.keys {
                if let value = entry[key], !(value is String) {
                    problems.append(.badValue(key: key, value: Self.shown(value)))
                    return nil
                }
            }
            return entry.compactMapValues { $0 as? String }
        }
        return .success((bundle, commands.map { strings($0, ["schemaVersion": String(version)]) }, snippetEntries, problems))
    }

    /// A value of `extension.json` as a problem shows it: its JSON, at most 60 characters of it.
    static func shown(_ value: Any) -> String {
        let text: String
        if let string = value as? String {
            text = string
        } else if JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = "\(value)"
        }
        return text.count > 60 ? String(text.prefix(60)) + "…" : text
    }
}

/// A text to insert that an extension bundle ships (`extension.json`'s `snippets`): offered as `@name` like a snippet of
/// the config's (`CustomCommand.CommandType.snippet`), its name taken by the bundle tier's rules (`Command.catalog`: its
/// `alias` when another command has the name). Turned off by `"<bundle>/<name>"` (or the bundle's name) in
/// `Config.disabledExtensions`.
public struct BundleSnippet: Hashable, Sendable {
    /// The bundle's name.
    public var bundle: String
    public var name: String
    public var alias: String?
    public var text: String
    public var summary: String?
    public var icon: String?
    public var color: String?

    public init(bundle: String, name: String, alias: String? = nil, text: String, summary: String? = nil,
                icon: String? = nil, color: String? = nil) {
        self.bundle = bundle
        self.name = name
        self.alias = alias
        self.text = text
        self.summary = summary
        self.icon = icon
        self.color = color
    }

    /// "<bundle>/<name>", as `disabledExtensions` turns it off.
    public var id: String { bundle + "/" + name }

    /// The names it answers to, in order (its alias only when its name is taken).
    public var names: [String] { [name] + (alias.map { [$0] } ?? []) }

    /// As a snippet of the config's: what the composer inserts.
    public var definition: CustomCommand {
        CustomCommand(name: name, type: .snippet, summary: summary, icon: icon, color: color, text: text)
    }

    /// An entry's keys, every one a string (`ExtensionBundle.read` leaves out an entry where one isn't).
    static let keys = ["name", "alias", "text", "summary", "icon", "color"]

    /// The snippet of an entry (its keys, strings), or why it can't be used: a name `ScriptCommand.isValidName` takes
    /// (and alias), a text that isn't blank and has `{cursor}` at most once.
    static func make(_ keys: [String: String], bundle: String) -> Result<BundleSnippet, ScriptCommand.Problem> {
        guard let name = keys["name"]?.lowercased(), !name.isEmpty else { return .failure(.noName) }
        guard ScriptCommand.isValidName(name) else { return .failure(.badValue(key: "name", value: name)) }
        let alias = keys["alias"]?.lowercased()
        if let alias, !ScriptCommand.isValidName(alias) { return .failure(.badValue(key: "alias", value: alias)) }
        guard let text = keys["text"] else { return .failure(.missing("text")) }
        guard CustomCommand.snippetProblem(text) == nil else {
            return .failure(.badValue(key: "text", value: ExtensionBundle.shown(text)))
        }
        func optional(_ key: String) -> String? { keys[key].flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
        return .success(BundleSnippet(bundle: bundle, name: name, alias: alias, text: text, summary: optional("summary"),
                                      icon: optional("icon"), color: optional("color")))
    }
}

/// What the folders hold: the commands in the order their names are given out (a bundle's, then single
/// scripts', then Raycast scripts', each in folder order), the bundles, what was left out and why, and the
/// copies left out because they are byte for byte one loaded before (not a problem: not warned about).
public struct ExtensionIndex: Equatable, Sendable {
    public var commands: [ScriptCommand]
    public var bundles: [ExtensionBundle]
    /// The bundles' snippets, in bundle order.
    public var snippets: [BundleSnippet]
    public var skipped: [ExtensionStore.Skipped]
    /// Scripts, and bundles' `extension.json`, identical to one found before them (another checkout or copy
    /// of the same folder): left out quietly.
    public var identical: [URL]
    /// Counts the indexes that differed from the one before (`LiveExtensions`): the command list is built again
    /// only when it changes, not compared command by command on each key. Not part of `==`.
    public var generation = 0

    public static func == (a: ExtensionIndex, b: ExtensionIndex) -> Bool {
        a.commands == b.commands && a.bundles == b.bundles && a.snippets == b.snippets && a.skipped == b.skipped
            && a.identical == b.identical
    }

    public init(commands: [ScriptCommand] = [], bundles: [ExtensionBundle] = [], snippets: [BundleSnippet] = [],
                skipped: [ExtensionStore.Skipped] = [], identical: [URL] = []) {
        self.commands = commands
        self.bundles = bundles
        self.snippets = snippets
        self.skipped = skipped
        self.identical = identical
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

    /// The snippets not turned off (`Config.disabledExtensions`: "<bundle>/<name>", or the bundle's name).
    public func enabledSnippets(_ disabled: [String]) -> [BundleSnippet] {
        let off = Set(disabled)
        return snippets.filter { !off.contains($0.id) && !off.contains($0.bundle) }
    }
}

/// The folders of script extensions: the ones added (`Config.extensionFolders`) and, unless turned off, the
/// ones Spotlight found holding Raycast scripts (`discover`), less those hidden. An added folder is read whole;
/// from a found one only its Raycast scripts are taken (it may be a copy of anything that holds one).
public enum ExtensionStore {
    /// In the list from the start, for one's own scripts and bundles.
    public static let defaultFolder = "~/.config/allinoneime/extensions"

    /// A folder looked in: added by the user, or found (`discover`).
    public struct Folder: Hashable, Sendable {
        /// As written in the config ("~/…").
        public var path: String
        /// Found by Spotlight, not added: only its Raycast scripts are loaded (no bundles, no `@allinoneime.`
        /// scripts, no broken links reported).
        public var found: Bool
        public var hidden: Bool
        /// Only ever the one bundle it is (an extension source's folder, or one being reviewed): an `extension.json` that
        /// isn't a valid bundle's is reported, and its scripts aren't read as single scripts instead.
        public var bundleOnly: Bool

        public init(path: String, found: Bool, hidden: Bool = false, bundleOnly: Bool = false) {
            self.path = path
            self.found = found
            self.hidden = hidden
            self.bundleOnly = bundleOnly
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
    /// by name, not deeper (as Raycast does); an added folder with an `extension.json` of its own is that one
    /// bundle; from a folder found (`Folder.found`), its Raycast scripts only.
    /// Symbolic links are followed: a linked folder, script or bundle is read as the one it points to (a link to
    /// nothing is reported). A script or bundle byte for byte the same as one before it, under the same name (a
    /// second checkout of a repository, a copied folder), is left out quietly (`ExtensionIndex.identical`); one
    /// with other content under a taken name is reported as before. Files are read only when their size, date
    /// or permissions changed since `cache` last saw them; what it held for files gone is dropped. Templates
    /// (`*.template.*`) and hidden files are left out.
    public static func load(_ folders: [Folder], cache: ExtensionCache = ExtensionCache()) -> ExtensionIndex {
        var bundles: [(bundle: ExtensionBundle, commands: [ScriptCommand], snippets: [BundleSnippet], digest: Data)] = []
        var scripts: [ScriptCommand] = []
        var skipped: [Skipped] = []
        var identical: [URL] = []
        var seen = Set<String>()
        /// What was taken (a command's name, a file left out's name), with the content's digest.
        var copies = Set<String>()
        func read(_ url: URL) -> ExtensionCache.File? {
            seen.insert(url.path)
            return cache.read(url)
        }
        /// Whether `url` is the first with this name and content (else it's noted as an identical copy).
        func first(_ name: String, _ digest: Data, _ url: URL) -> Bool {
            guard copies.insert(name + "\u{0}" + digest.base64EncodedString()).inserted else {
                identical.append(url)
                return false
            }
            return true
        }
        for folder in folders where !folder.hidden {
            // An added folder that is a bundle itself (an extension source's, `ExtensionSources`) is read as that bundle;
            // one whose extension.json isn't a bundle's (another tool's file, a broken one) is read as a folder, as before,
            // unless it is only ever a bundle (`bundleOnly`): then what's wrong with it is reported.
            let manifest = folder.url.appendingPathComponent(ExtensionBundle.manifestName)
            if folder.bundleOnly, !folder.found, read(manifest)?.json == nil {
                skipped.append(Skipped(file: manifest, problem: .missing(ExtensionBundle.manifestName)))
                continue
            }
            let isBundle = !folder.found && (folder.bundleOnly || read(manifest)?.json.map {
                if case .success = ExtensionBundle.read($0, folder: folder.url) { return true } else { return false }
            } == true)
            for item in isBundle ? [(url: folder.url, kind: ItemKind.folder)] : items(in: folder.url) {
                switch item.kind {
                case .brokenLink:
                    if !folder.found { skipped.append(Skipped(file: item.url, problem: .brokenLink)) }
                case .folder:
                    guard !folder.found else { continue }  // bundles only from folders added
                    let manifest = item.url.appendingPathComponent(ExtensionBundle.manifestName)
                    guard let file = read(manifest), let data = file.json else { continue }
                    // The bundle's content: its extension.json and the scripts it names (not the rest of the folder).
                    var hasher = SHA256()
                    hasher.update(data: file.digest)
                    let loaded = loadBundle(data, folder: item.url) { url in
                        let script = read(url)
                        hasher.update(data: Data((String(url.path.dropFirst(item.url.path.count)) + "\u{0}").utf8))
                        hasher.update(data: script?.digest ?? Data())
                        return script
                    }
                    let digest = Data(hasher.finalize())
                    switch loaded {
                    case let .success((bundle, commands, snippets, problems)):
                        guard first("bundle " + bundle.name, digest, manifest) else { continue }
                        if bundles.contains(where: { $0.bundle.name == bundle.name }) {
                            skipped.append(Skipped(file: manifest, problem: .bundleTaken))
                            continue
                        }
                        bundles.append((bundle, commands, snippets, digest))
                        skipped += problems
                    case let .failure(problem):
                        guard first("bundle folder " + item.url.lastPathComponent, digest, manifest) else { continue }
                        skipped.append(Skipped(file: manifest, problem: problem))
                    }
                case .file:
                    guard let file = read(item.url), !folder.found || file.metadata?.front == .raycast,
                          let read = ScriptCommand.read(file.metadata, firstLine: file.firstLine, file: item.url,
                                                        executable: file.executable) else { continue }
                    switch read {
                    case var .success(command):
                        guard first("command " + command.name, file.digest, item.url) else { continue }
                        command.id = abbreviated(item.url.path)
                        scripts.append(command)
                    case let .failure(problem):
                        guard first("file " + item.url.lastPathComponent, file.digest, item.url) else { continue }
                        skipped.append(Skipped(file: item.url, problem: problem))
                    }
                }
            }
        }
        cache.keep(only: seen)
        // Bundles first, then single scripts, then Raycast's (stable within each).
        let ordered = bundles.flatMap(\.commands) + scripts.filter { $0.source == .script } + scripts.filter { $0.source == .raycast }
        return ExtensionIndex(commands: ordered, bundles: bundles.map(\.bundle), snippets: bundles.flatMap(\.snippets), skipped: skipped,
                              identical: identical)
    }

    /// A bundle's commands (each entry's keys over its script's own `@allinoneime.` lines) and snippets, and the
    /// entries that can't be used (two with one name: the first is kept).
    static func loadBundle(_ data: Data, folder: URL, read: (URL) -> ExtensionCache.File?)
        -> Result<(ExtensionBundle, [ScriptCommand], [BundleSnippet], [Skipped]), ScriptCommand.Problem> {
        let bundle: ExtensionBundle, entries: [[String: String]], snippetEntries: [[String: String]], problems: [ScriptCommand.Problem]
        switch ExtensionBundle.read(data, folder: folder) {
        case let .success(read): (bundle, entries, snippetEntries, problems) = read
        case let .failure(problem): return .failure(problem)
        }
        let manifest = folder.appendingPathComponent(ExtensionBundle.manifestName)
        var commands: [ScriptCommand] = []
        var skipped = problems.map { Skipped(file: manifest, problem: $0) }
        for entry in entries {
            // A file of the bundle's folder as written (on every system's terms: no "..", "/x", "C:x", "..\x").
            guard let script = entry["script"], let file = CorePaths.file(script, in: folder) else {
                skipped.append(Skipped(file: folder.appendingPathComponent(ExtensionBundle.manifestName),
                                       problem: .badValue(key: "script", value: entry["script"] ?? "")))
                continue
            }
            guard let found = read(file),
                  let launch = ScriptCommand.launch(for: file, firstLine: found.firstLine, executable: found.executable,
                                                    binary: found.binary) else {
                skipped.append(Skipped(file: file, problem: .notRunnable))
                continue
            }
            var keys = found.metadata.flatMap { $0.front == .native ? $0.keys : nil } ?? [:]
            keys.merge(entry) { $1 }
            keys["script"] = nil
            let name = keys["name"]?.lowercased() ?? ScriptCommand.commandName(for: file)
            let id = "\(bundle.name)/\(name)"
            if commands.contains(where: { $0.id == id }) {
                skipped.append(Skipped(file: file, problem: .nameTaken(name, by: .command(id))))
                continue
            }
            switch ScriptCommand.make(keys, source: .bundle(bundle.name), file: file, launch: launch, id: id, extensionDirectory: folder) {
            case var .success(command):
                if command.group == nil { command.group = bundle.title }
                commands.append(command)
            case let .failure(problem): skipped.append(Skipped(file: file, problem: problem))
            }
        }
        var snippets: [BundleSnippet] = []
        for entry in snippetEntries {
            switch BundleSnippet.make(entry, bundle: bundle.name) {
            case let .success(snippet):
                // A name twice in the bundle (a command's or a snippet's): the first is kept, and named.
                if let command = commands.first(where: { $0.name == snippet.name }) {
                    skipped.append(Skipped(file: manifest, problem: .nameTaken(snippet.name, by: .command(command.id))))
                } else if let first = snippets.first(where: { $0.name == snippet.name }) {
                    skipped.append(Skipped(file: manifest, problem: .nameTaken(snippet.name, by: .snippet(first.id))))
                } else {
                    snippets.append(snippet)
                }
            case let .failure(problem): skipped.append(Skipped(file: manifest, problem: problem))
            }
        }
        return .success((bundle, commands, snippets, skipped))
    }

    enum ItemKind { case file, folder, brokenLink }

    /// The files and folders in `folder` (followed if it's a link), by name, links followed: not hidden ones,
    /// not templates.
    static func items(in folder: URL) -> [(url: URL, kind: ItemKind)] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { !$0.hasPrefix(".") && !$0.contains(".template.") }.sorted().compactMap { name in
            let url = folder.appendingPathComponent(name)
            #if os(Windows)
            // The C library's stat takes no Unicode path and sees no links there: Foundation's calls (which follow links).
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else {
                let type = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
                return type == .typeSymbolicLink ? (url, .brokenLink) : nil
            }
            return (url, isFolder.boolValue ? .folder : .file)
            #else
            var info = stat()
            guard stat(url.path, &info) == 0 else {
                var link = stat()
                return lstat(url.path, &link) == 0 && (link.st_mode & S_IFMT) == S_IFLNK ? (url, .brokenLink) : nil
            }
            switch info.st_mode & S_IFMT {
            case S_IFDIR: return (url, .folder)
            case S_IFREG: return (url, .file)
            default: return nil
            }
            #endif
        }
    }
    /// The folders of the files `mdfind` printed (one path a line) that are scripts (`isScript`): what `discover` (the
    /// macOS shell's) lists.
    public static func folders(fromSpotlight output: String, home: String = NSHomeDirectory(),
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

    /// Whether `file` is there and is a Raycast script that loads (a file of a folder since removed, still in
    /// Spotlight's index, isn't: its folder is dropped).
    @usableFromInline static func isScript(_ file: URL) -> Bool {
        guard let read = ExtensionCache().read(file), read.metadata?.front == .raycast,
              case .success? = ScriptCommand.read(read.metadata, firstLine: read.firstLine, file: file, executable: read.executable)
        else { return false }
        return true
    }

    /// `path` with the home folder as "~".
    public static func abbreviated(_ path: String, home: String = NSHomeDirectory()) -> String {
        path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// Whether `a` and `b`, folders as the config writes them ("~/…" or a path), are the same folder: the same path once
    /// written out, in any case on Windows.
    public static func isSameFolder(_ a: String, _ b: String) -> Bool {
        let (x, y) = (Folder(path: a, found: false).url.standardizedFileURL.path, Folder(path: b, found: false).url.standardizedFileURL.path)
        #if os(Windows)
        return x.caseInsensitiveCompare(y) == .orderedSame
        #else
        return x == y
        #endif
    }

    /// A folder as Windows' settings window shows it: one in the home folder with `%USERPROFILE%` for "~" and Windows'
    /// backslashes ("~/.config/allinoneime/extensions" → "%USERPROFILE%\.config\allinoneime\extensions"), another as
    /// it is.
    public static func windowsShown(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return "%USERPROFILE%" + path.dropFirst().replacingOccurrences(of: "/", with: "\\")
    }

    /// A folder typed in Windows' settings window, as the config keeps it: its `%NAME%`s written out from `environment`
    /// (Windows' names, in any case; one it lacks stays as it is), then, in the home folder (`home`, in any case, written
    /// with either slash), with "~" and forward slashes as the Mac's are: "%USERPROFILE%\Scripts" → "~/Scripts". The
    /// placeholder (`windowsShown`) typed as it is is the default folder.
    public static func typedOnWindows(_ path: String, home: String, environment: [String: String]) -> String {
        let expanded = CorePaths.windowsExpanded(path, environment: environment)
        func slashed(_ text: String) -> String {
            var out = text.replacingOccurrences(of: "\\", with: "/")
            while out.count > 1, out.hasSuffix("/") { out.removeLast() }
            return out
        }
        let folder = slashed(expanded), base = slashed(home)
        guard !base.isEmpty else { return expanded }
        if folder.caseInsensitiveCompare(base) == .orderedSame { return "~" }
        if folder.lowercased().hasPrefix(base.lowercased() + "/") { return "~" + folder.dropFirst(base.count) }
        return expanded
    }
}

/// What the index needs of the files it read, by path, kept while their size, modification date and
/// permissions stay the same: a rebuild only reads what changed. Only that is kept (a script's metadata and
/// first line, an `extension.json`, the content's digest), and files no longer read are dropped (`keep(only:)`).
/// Safe to use from any thread.
public final class ExtensionCache: @unchecked Sendable {
    public struct File: Sendable {
        var date: Date
        var size: Int64
        var mode: UInt16
        /// The `@allinoneime.` or `@raycast.` keys in its first 64 KB.
        public var metadata: (front: ScriptCommand.FrontEnd, keys: [String: String])?
        public var firstLine: String
        /// An `extension.json`'s bytes.
        public var json: Data?
        public var executable: Bool
        /// A compiled program (or any file with a NUL byte): run as it is.
        public var binary: Bool
        /// The SHA-256 of all of it: two copies of one script are told apart from two scripts with one name.
        public var digest: Data
    }

    private var files: [String: File] = [:]
    private let lock = NSLock()
    /// Metadata past the first 64 KB isn't looked for; an `extension.json` is smaller.
    static let maxBytes = 64 * 1024

    public init() {}

    /// What `url` (a link followed) holds for the index, from the cache when its size, date and permissions are
    /// the same; nil when it isn't a readable regular file.
    public func read(_ url: URL) -> File? {
        #if os(Windows)
        // The C library's stat takes no Unicode path there: Foundation's attributes, of the file a link leads to.
        guard let info = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path),
              info[.type] as? FileAttributeType == .typeRegular else { return nil }
        let size = (info[.size] as? NSNumber)?.int64Value ?? 0, mode = UInt16((info[.posixPermissions] as? NSNumber)?.intValue ?? 0)
        #else
        var info = stat()
        guard stat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        let (size, mode) = (Int64(info.st_size), UInt16(info.st_mode))
        #endif
        let date = Platform.current.files.modificationDate(atPath: url.path) ?? .distantPast
        if let cached = lock.withLock({ files[url.path] }), cached.date == date, cached.size == size, cached.mode == mode { return cached }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: Self.maxBytes)) ?? Data()
        // The rest of a longer file is only hashed (once, while it's unchanged), a megabyte at a time.
        var hasher = SHA256()
        hasher.update(data: data)
        if data.count == Self.maxBytes {
            while let more = try? handle.read(upToCount: 1 << 20), !more.isEmpty { hasher.update(data: more) }
        }
        let binary = data.contains(0)
        let text = binary ? "" : String(decoding: data, as: UTF8.self)
        let file = File(date: date, size: size, mode: mode, metadata: binary ? nil : ScriptCommand.metadata(in: text),
                        firstLine: ScriptCommand.firstLine(of: text),
                        json: url.lastPathComponent == ExtensionBundle.manifestName ? data : nil,
                        executable: Self.isExecutable(url), binary: binary, digest: Data(hasher.finalize()))
        lock.withLock { files[url.path] = file }
        return file
    }

    /// Whether the system would run `url` itself: its executable bit; on Windows, which has none, a program it can run.
    static func isExecutable(_ url: URL) -> Bool {
        #if os(Windows)
        FileManager.default.isExecutableFile(atPath: url.path)
        #else
        access(url.path, X_OK) == 0
        #endif
    }

    /// Drops what it holds for any file but `paths` (those gone, or no longer in a folder read).
    public func keep(only paths: Set<String>) {
        lock.withLock { files = files.filter { paths.contains($0.key) } }
    }

    /// How many files it holds (for the tests).
    var count: Int { lock.withLock { files.count } }
}

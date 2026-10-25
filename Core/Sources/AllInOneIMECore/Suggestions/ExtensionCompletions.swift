import Crypto
import Foundation

// Script extensions as completion sources (0.6.7.1 §2): a command of a script extension may declare one completion
// source, with a plugin's `completions` entry's keys and meaning (docs/plugins.md), its name and title the command's. One
// kind of source: the session takes it with the plugins' and the custom commands' (`InputSession.ActiveSource`), the
// store keeps it as theirs under `CompletionSourceKey(extension:)` (its list, the disk cache, back-off and pause, statuses,
// "Refresh now", the picks), its approval is a `CompletionSourceApproval` in `Config.completionSources` (off until turned
// on in Settings → Commands), its rows, keys and insertions are theirs. Turning it on pins its whole extension and its
// terms (query, prefix, queryMinChars, compare); what a change does then depends on where the extension comes from
// (`ExtensionOrigin`, owner 2026-10-24): the user's own, or one from an extension source whose updates they trust, keeps
// it on (the approval follows it, said nowhere, nothing of it read); one from any other source turns it off again, said
// once: that one is pinned by a digest of every file of its source's repository (`ExtensionDigest`), which can't be
// over 2,000 files or 20 MB. What differs is where its items come from: its script, run as its commands run
// (`CommandRunner`) with `ALLINONEIME_COMPLETION` set (`ExtensionCompletionRunner`), a bundle's programs one at a time.

extension CompletionDeclaration {
    /// A script extension's declaration (`completion`: the JSON text of a script's `@allinoneime.completion` line, or of
    /// its bundle entry's `"completion"`) read as a plugin's `completions` entry is (the same keys, limits, defaults and
    /// reasons), its name and title the command's (`name`, `title`: any it gives are the command's anyway). A list loads
    /// within 20 seconds whatever the command's `timeout` (`ExtensionCompletionRunner.loadTimeout`).
    static func extensionSource(_ json: String, name: String, title: String) -> Result<CompletionSource, CompletionRefusal> {
        func refuse(_ reason: String) -> Result<CompletionSource, CompletionRefusal> {
            .failure(CompletionRefusal(name: name, reason: reason))
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]),
              case var .object(fields)? = JSON(object) else { return refuse(tr("completion 必须是 JSON 对象", "completion must be a JSON object")) }
        fields["name"] = .string(name)
        fields["title"] = .string(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? name : title)
        let read = read(.array([.object(fields)]), type: .script, timeoutSeconds: nil)
        if let source = read.sources.first { return .success(source) }
        return .failure(read.refused.first ?? CompletionRefusal(name: name, reason: tr("不是补全来源", "not a completion source")))
    }
}

extension CompletionSourceKey {
    /// What script extensions' sources are kept under (their `plugin`): a name no plugin can have.
    public static let scriptExtensions = "script-extensions"

    /// The completion source of the script extension command `command`: by its id ("units/convert", a single script's
    /// file "~/…"), which stays while it is the same command in the same place.
    public init(extension command: ScriptCommand) {
        self.init(extensionCommand: command.id)
    }

    /// The completion source of the script extension command whose id is `id` (`ScriptCommand.id`).
    public init(extensionCommand id: String) {
        self.init(plugin: Self.scriptExtensions, source: id)
    }

    /// It is a script extension's source.
    public var isScriptExtension: Bool { plugin == Self.scriptExtensions }
}

// MARK: - What turning it on pins

/// What a script extension is, as turning its completion source on pins it (0.6.7.1 §2): the user's own, every file of
/// its bundle (`extension.json`, every script, `lib/`…) or a single script's file; one from an extension source, every
/// file of its source's repository (a script may use files anywhere in it: `../shared/common.sh`, a link to a folder of
/// the clone). Only an extension whose changes turn its source off is read for it (`ExtensionOrigin.followsChanges`
/// false): the user's own and a trusted source's never are.
public enum ExtensionDigest {
    /// The most files (links too) and bytes in all a source's repository may hold to be pinned: it is read again as a
    /// field takes the focus and before each run, which past them can't be cheap.
    public static let maxFiles = 2_000
    public static let maxBytes = 20_000_000
    /// What a repository past them reads as (`repository(_:sha256:)`): a digest no approval has. None can be turned on
    /// with it, and one approved holds no more, as after a change.
    public static let tooLarge = "too-large"

    /// `command`'s, lowercase hex: one from an extension source (its folder in `root`, the extension sources' folder),
    /// its source's repository's (`repository(_:sha256:)`, `repositoryFolder(of:root:)`); else a bundle's command, its
    /// bundle folder's (`folder(_:sha256:)`); a single script, its file's SHA-256 (as a plugin's script is pinned). Nil:
    /// nothing to read. `sha256`: a file's SHA-256 (nil: none).
    public static func of(_ command: ScriptCommand, root: URL = ExtensionSources.directory,
                          sha256: (URL) -> String? = PluginStore.sha256(of:)) -> String? {
        if let clone = repositoryFolder(of: command, root: root) { return repository(clone, sha256: sha256) }
        guard command.source.bundleName != nil else { return sha256(command.file) }
        return folder(command.extensionDirectory, sha256: sha256)
    }

    /// The repository `command` is pinned by when it comes from an extension source: the folder of `root` its folder is
    /// in (a source's clone, `ExtensionSources.cloneFolder`, or one no source has: `ExtensionOrigin.unknownSource`). Nil:
    /// not in `root` (the user's own).
    public static func repositoryFolder(of command: ScriptCommand, root: URL = ExtensionSources.directory) -> URL? {
        let folder = ExtensionSources.comparable(command.extensionDirectory.path)
        let base = ExtensionSources.comparable(root.path)
        if folder == base { return root }
        guard folder.hasPrefix(base + "/"), let first = folder.dropFirst(base.count + 1).split(separator: "/").first else { return nil }
        return root.appendingPathComponent(String(first), isDirectory: true)
    }

    /// The SHA-256 (lowercase hex) of every file under `folder`: each one's path in it with its own SHA-256, in the order
    /// of their paths, so a file added, removed, renamed or changed anywhere in it (a hidden one too) changes it. A link is
    /// read as the file it leads to; one to a folder, or to nothing, as where it leads (that folder isn't walked: it may be
    /// anywhere). What is no file of an extension is left out (`isIgnored`). Nil: `folder` can't be read.
    public static func folder(_ folder: URL, sha256: (URL) -> String?) -> String? {
        let fm = FileManager.default
        guard (try? fm.contentsOfDirectory(atPath: folder.path)) != nil else { return nil }
        var entries: [(path: String, content: String)] = []
        func visit(_ url: URL, _ relative: String) {
            guard let names = try? fm.contentsOfDirectory(atPath: url.path) else {
                entries.append((relative + "/", "unreadable"))
                return
            }
            for name in names where !isIgnored(name) {
                let child = url.appendingPathComponent(name)
                let path = relative.isEmpty ? name : relative + "/" + name
                let kind = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
                if kind?.isSymbolicLink == true {
                    // The file it leads to, hashed by its own path (a hash kept by size and date then sees it change).
                    let target = child.resolvingSymlinksInPath()
                    if (try? target.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                        entries.append((path, sha256(target) ?? "unreadable"))
                    } else {
                        entries.append((path, "link " + ((try? fm.destinationOfSymbolicLink(atPath: child.path)) ?? "")))
                    }
                } else if kind?.isDirectory == true {
                    visit(child, path)
                } else if kind?.isRegularFile == true {
                    entries.append((path, sha256(child) ?? "unreadable"))
                }
            }
        }
        visit(folder, "")
        return digest(entries)
    }

    /// The SHA-256 (lowercase hex) of every file of a source's repository `clone`, as `folder(_:sha256:)` reads a
    /// bundle's but for two things: all but git's own folder (`.git`: a check for updates changes it) and the Finder's
    /// `.DS_Store` are in it, wherever they are (no other name is left out); and a link, anywhere, is pinned as where it
    /// points (its text), never followed: what it leads to in the clone is in the digest anyway, and outside it isn't the
    /// source's. `tooLarge` past `maxFiles` files or `maxBytes` bytes, counted while walking (it stops there, nothing
    /// read). Nil: `clone` can't be read.
    public static func repository(_ clone: URL, sha256: (URL) -> String?) -> String? {
        enum Content { case file(String), link(String), unreadable }
        var entries: [(path: String, content: Content)] = []
        var (files, bytes) = (0, 0)
        /// False: past the limits (read no further); nil: `folder` can't be read.
        func visit(_ folder: String, _ relative: String) -> Bool? {
            eachItem(in: folder) { item in
                guard item.name != ".git", item.name != ".DS_Store" else { return true }
                let (full, path) = (folder + "/" + item.name, relative.isEmpty ? item.name : relative + "/" + item.name)
                switch item.kind {
                case .link:
                    files += 1
                    entries.append((path, .link((try? FileManager.default.destinationOfSymbolicLink(atPath: full)) ?? "")))
                case .folder:
                    switch visit(full, path) {
                    case false?: return false
                    case nil: entries.append((path + "/", .unreadable))
                    case true?: break
                    }
                case .file:
                    files += 1
                    bytes += item.size
                    entries.append((path, .file(full)))
                case .other:
                    break
                }
                return files <= maxFiles && bytes <= maxBytes
            }
        }
        switch visit(clone.path, "") {
        case nil: return nil
        case false?: return tooLarge
        case true?: break
        }
        return digest(entries.map { entry in
            switch entry.content {
            case let .file(full): return (entry.path, sha256(URL(fileURLWithPath: full)) ?? "unreadable")
            case let .link(target): return (entry.path, "link " + target)
            case .unreadable: return (entry.path, "unreadable")
            }
        })
    }

    /// An item of a folder of a repository: its name, what it is (a link as itself, never followed) and its size.
    struct Item {
        enum Kind { case file, folder, link, other }
        var name: String
        var kind: Kind
        var size: Int
    }

    /// Each item of `folder` given to `body` as it is read, until `body` says to stop (false): every name as the file
    /// system has it (on the Mac the file manager leaves out AppleDouble `._` files, which are files of a repository like
    /// any other, so they are read there as `ls -a` reads them). Whether all were read; nil: `folder` can't be read.
    static func eachItem(in folder: String, _ body: (Item) -> Bool) -> Bool? {
        #if canImport(Darwin)
        guard let dir = opendir(folder) else { return nil }
        defer { closedir(dir) }
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) { String(cString: $0) }
            }
            guard name != ".", name != ".." else { continue }
            var info = stat()
            var item = Item(name: name, kind: .other, size: 0)
            if lstat(folder + "/" + name, &info) == 0 {
                switch info.st_mode & S_IFMT {
                case S_IFLNK: item.kind = .link
                case S_IFDIR: item.kind = .folder
                case S_IFREG: item.kind = .file
                default: break
                }
                item.size = Int(info.st_size)
            }
            guard body(item) else { return false }
        }
        return true
        #else
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        guard let children = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder, isDirectory: true),
                                                                           includingPropertiesForKeys: keys, options: [])
        else { return nil }
        for child in children {
            let values = try? child.resourceValues(forKeys: Set(keys))
            let kind: Item.Kind = values?.isSymbolicLink == true ? .link : values?.isDirectory == true ? .folder
                : values?.isRegularFile == true ? .file : .other
            guard body(Item(name: child.lastPathComponent, kind: kind, size: values?.fileSize ?? 0)) else { return false }
        }
        return true
        #endif
    }

    /// The SHA-256 (lowercase hex) of `entries`, each one's path with what it is, in the order of their paths.
    private static func digest(_ entries: [(path: String, content: String)]) -> String {
        var hasher = SHA256()
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            hasher.update(data: Data((entry.path + "\u{0}" + entry.content + "\n").utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Names that are no file of an extension, wherever they are in its folder: the Finder's (`.DS_Store`, AppleDouble
    /// `._` files, a folder's own icon `Icon\r`), Windows Explorer's (`Thumbs.db`, `desktop.ini`), and git's own folder
    /// (`.git`: a check for updates changes it, never the bundle).
    static func isIgnored(_ name: String) -> Bool {
        name == ".DS_Store" || name.hasPrefix("._") || name == "Icon\r" || name == ".git"
            || ["thumbs.db", "desktop.ini"].contains(name.lowercased())
    }
}

/// Where a script extension comes from, as its completion source's approval goes (0.6.7.1 §2, owner 2026-10-24).
public enum ExtensionOrigin: Equatable, Sendable {
    /// The user's own: a folder of theirs (their extensions folder, one they added), not installed from an extension
    /// source. Trusted: its changes never turn its source off.
    case own
    /// Installed from this extension source (`Config.extensionSources`): its updates keep its source on when the user
    /// trusts them (`ExtensionSource.trustUpdates`); else any change turns it off.
    case source(ExtensionSource)
    /// In the extension sources' folder but no source's bundle (a config copied from another Mac), or in a folder two
    /// configured sources would share (`ExtensionSources.sharingFolder`): as a source's not trusted.
    case unknownSource

    /// Whether a change keeps its source on, the approval following it (`CompletionSourceApproval.followed`).
    public var followsChanges: Bool {
        switch self {
        case .own: return true
        case let .source(source): return source.trustUpdates
        case .unknownSource: return false
        }
    }
}

extension Config {
    /// Where the script extension `command` comes from (`ExtensionOrigin`): its folder (`ScriptCommand.extensionDirectory`)
    /// a source's bundle folder in `root`, the extension sources' folder (`ExtensionSources.bundleFolder`), or in it as
    /// no source's (nor one whose folder another configured source would share: which one it is can't be told); anywhere
    /// else, the user's own.
    public func extensionOrigin(of command: ScriptCommand, root: URL = ExtensionSources.directory) -> ExtensionOrigin {
        let folder = ExtensionSources.comparable(command.extensionDirectory.path)
        let base = ExtensionSources.comparable(root.path)
        guard folder == base || folder.hasPrefix(base + "/") else { return .own }
        guard let source = extensionSources.first(where: { ExtensionSources.comparable(ExtensionSources.bundleFolder(for: $0, root: root).path) == folder }),
              ExtensionSources.sharingFolder(with: source.url, in: self) == nil
        else { return .unknownSource }
        return .source(source)
    }

    /// Whether a change to the script extension `command` keeps its completion source on (`ExtensionOrigin.followsChanges`).
    public func followsChanges(of command: ScriptCommand, root: URL = ExtensionSources.directory) -> Bool {
        extensionOrigin(of: command, root: root).followsChanges
    }

    /// The extension source of `url`'s "Trust its updates" switched `on`. Turned off, its extensions' approvals that hold
    /// are first made what they are now (`follow`: their repository read then, by `sha256`), so turning it off turns
    /// nothing off by itself: only a change after it does (one whose repository is too large to read, `ExtensionDigest
    /// .tooLarge`, is turned off at the next check). `commands`: the script extensions as loaded; `root`: the extension
    /// sources' folder. Whether it changed.
    @discardableResult
    public mutating func setTrustUpdates(_ on: Bool, of url: String, extensions commands: [ScriptCommand],
                                         root: URL = ExtensionSources.directory,
                                         sha256: (URL) -> String? = PluginStore.sha256(of:)) -> Bool {
        guard let index = extensionSources.firstIndex(where: { $0.url == url }), extensionSources[index].trustUpdates != on
        else { return false }
        if !on {
            let config = self
            let own = commands.filter { if case let .source(source) = config.extensionOrigin(of: $0, root: root) { return source.url == url } else { return false } }
            let followed = withoutActuallyEscaping(sha256) { sha256 in
                CompletionSourceApproval.followed(completionSources, extensions: own, follows: { _ in true },
                                                  digest: { ExtensionDigest.of($0, root: root, sha256: sha256) })
            }
            follow(followed)
        }
        extensionSources[index].trustUpdates = on
        return true
    }
}

extension CompletionSourceApproval {
    /// What turning on `source`, `command`'s, approves now (0.6.7.1 §2): its extension's digest (`ExtensionDigest`: every
    /// file of its source's repository, of its bundle, a single script's file; `root`: the extension sources' folder),
    /// whether it queries, and its terms as a plugin's (`Terms`: its prefix, from which character it queries, how it
    /// compares). No hosts: what its script reaches is its own. Nil: nothing of it can be read, or its repository is too
    /// large to pin (`ExtensionDigest.tooLarge`).
    public init?(enabling source: CompletionSource, of command: ScriptCommand, root: URL = ExtensionSources.directory,
                 sha256: (URL) -> String? = PluginStore.sha256(of:)) {
        guard let digest = ExtensionDigest.of(command, root: root, sha256: sha256), digest != ExtensionDigest.tooLarge else { return nil }
        self.init(source, of: command, digest: digest)
    }

    /// What turning on the source `command` declares approves now (`init(enabling:of:)`). Nil: it declares none, or one
    /// refused, or nothing of it can be read.
    public init?(enabling command: ScriptCommand) {
        guard case let .success(source)? = command.completion else { return nil }
        self.init(enabling: source, of: command)
    }

    /// `source` of `command` as it is, `digest` its extension's (empty: none read, its changes keeping it on).
    init(_ source: CompletionSource, of command: ScriptCommand, digest: String) {
        let key = CompletionSourceKey(extension: command)
        self.init(plugin: key.plugin, source: key.source, hosts: [], query: source.query, scriptSHA256: digest, terms: Terms(source))
    }

    /// Whether it still pins `source` of `command` as they are now: the same extension (its digest: any file of its
    /// source's repository, of its bundle, a single script's file; `root`: the extension sources' folder), query and terms
    /// (prefix, queryMinChars and compare), compared as a plugin's are. One without terms never holds; nor one once marked
    /// lapsed.
    public func holds(for source: CompletionSource, of command: ScriptCommand, root: URL = ExtensionSources.directory) -> Bool {
        guard let digest = ExtensionDigest.of(command, root: root) else { return false }
        return holds(forScript: source, of: command, digest: digest, follows: false)
    }

    /// Whether it holds for `source` of `command`, `follows` whether a change keeps it on (`Config.followsChanges`): one
    /// that follows holds whatever changed since (nothing of it is read), one pinned only for what it was turned on with
    /// (`holds(for:of:root:)`). Never once marked lapsed: that one stays off until turned on again.
    public func holds(for source: CompletionSource, of command: ScriptCommand, follows: Bool,
                      root: URL = ExtensionSources.directory) -> Bool {
        follows ? holds(forScript: source, of: command, digest: nil, follows: true) : holds(for: source, of: command, root: root)
    }

    /// `holds(for:of:follows:)` with its extension's digest as it is now (nil: none read; one pinned doesn't hold then).
    func holds(forScript source: CompletionSource, of command: ScriptCommand, digest: String?, follows: Bool) -> Bool {
        guard !lapsed, let terms, CompletionSourceKey(plugin: plugin, source: self.source) == CompletionSourceKey(extension: command)
        else { return false }
        if follows { return true }
        return query == source.query && scriptSHA256 == digest && terms == Terms(source)
    }

    /// The approvals of `enabled` not marked lapsed yet that no longer hold for the script extensions' `commands` as they
    /// are now: those pinned (`follows` false: from an extension source whose updates aren't trusted) whose extension,
    /// query or terms changed since, or whose repository grew too large to pin (`ExtensionDigest.tooLarge`). One that
    /// follows its changes never lapses (`followed`), and isn't read. One whose command isn't there, declares none or one
    /// refused, or can't be read, has nothing to compare with: it doesn't lapse (it isn't on meanwhile). `digest`: an
    /// extension's as it is now (`ExtensionDigest.of`; nil: none to read).
    public static func lapsed(_ enabled: [CompletionSourceApproval], extensions commands: [ScriptCommand],
                              follows: (ScriptCommand) -> Bool = { _ in false },
                              digest: (ScriptCommand) -> String? = { ExtensionDigest.of($0) }) -> [CompletionSourceApproval] {
        let extensionApprovals = enabled.filter { !$0.lapsed && $0.plugin == CompletionSourceKey.scriptExtensions }
        guard !extensionApprovals.isEmpty else { return [] }
        return extensionApprovals.filter { approval in
            guard let command = commands.first(where: { $0.id == approval.source }), case let .success(source)? = command.completion,
                  !follows(command), let digest = digest(command) else { return false }
            return !approval.holds(forScript: source, of: command, digest: digest, follows: false)
        }
    }

    /// The approvals of `enabled` not marked lapsed that follow their extension (`follows`: the user's own, or from an
    /// extension source whose updates are trusted) and differ from what it is now, each made what it is now: kept in its
    /// place (`Config.follow`), said nowhere. Without `digest`, nothing of the extension is read: only its query and terms
    /// follow, its digest staying as it was (none, when it was turned on so). With it, its digest too (`Config
    /// .setTrustUpdates`: what it is the moment its changes stop being trusted; one with none to read, or too large to
    /// pin, is left as it was).
    public static func followed(_ enabled: [CompletionSourceApproval], extensions commands: [ScriptCommand],
                                follows: (ScriptCommand) -> Bool,
                                digest: ((ScriptCommand) -> String?)? = nil) -> [CompletionSourceApproval] {
        enabled.compactMap { approval in
            guard !approval.lapsed, approval.plugin == CompletionSourceKey.scriptExtensions,
                  let command = commands.first(where: { $0.id == approval.source }), case let .success(source)? = command.completion,
                  follows(command) else { return nil }
            var now = approval.scriptSHA256
            if let digest {
                guard let read = digest(command), read != ExtensionDigest.tooLarge else { return nil }
                now = read
            }
            let followed = CompletionSourceApproval(source, of: command, digest: now)
            return followed == approval ? nil : followed
        }
    }
}

extension Config {
    /// The approval `source` of the script extension `command` was turned on with (nil: not turned on).
    public func approval(of source: CompletionSource, in command: ScriptCommand) -> CompletionSourceApproval? {
        let key = CompletionSourceKey(extension: command)
        return completionSources.first { $0.plugin == key.plugin && $0.source == key.source }
    }

    /// `source` of the script extension `command` turned on with what it is now, or off. One whose changes keep it on
    /// (`followsChanges`: the user's own, a trusted source's) is turned on with its query and terms, nothing of it read
    /// (no digest); any other with its digest too (`CompletionSourceApproval(enabling:of:root:sha256:)`: not when it
    /// can't be read, or its repository is too large to pin). `root`: the extension sources' folder; `sha256`: a file's.
    public mutating func setCompletionSource(_ source: CompletionSource, of command: ScriptCommand, enabled: Bool,
                                             root: URL = ExtensionSources.directory,
                                             sha256: (URL) -> String? = PluginStore.sha256(of:)) {
        let key = CompletionSourceKey(extension: command)
        completionSources.removeAll { $0.plugin == key.plugin && $0.source == key.source }
        guard enabled else { return }
        if followsChanges(of: command, root: root) {
            completionSources.append(CompletionSourceApproval(source, of: command, digest: ""))
        } else if let approval = CompletionSourceApproval(enabling: source, of: command, root: root, sha256: sha256) {
            completionSources.append(approval)
        }
    }

    /// How `source` of the script extension `command` stands, as Settings shows it under the command
    /// (`ScriptCompletionState`): its extension read only when a change would turn it off (`followsChanges` false), by
    /// `sha256` (Settings': a file read again only when it changed). `root`: the extension sources' folder.
    public func completionState(of source: CompletionSource, in command: ScriptCommand, root: URL = ExtensionSources.directory,
                                sha256: (URL) -> String? = PluginStore.sha256(of:)) -> ScriptCompletionState {
        let approval = approval(of: source, in: command)
        let follows = followsChanges(of: command, root: root)
        let digest = follows ? nil : ExtensionDigest.of(command, root: root, sha256: sha256)
        let tooLarge = digest == ExtensionDigest.tooLarge
        let on = approval?.holds(forScript: source, of: command, digest: digest, follows: follows) ?? false
        return ScriptCompletionState(on: on, changed: approval != nil && !on && !tooLarge, tooLarge: tooLarge)
    }

    /// The approvals `followed` found (`CompletionSourceApproval.followed`) in place of those of their sources: unless one
    /// was turned off or marked lapsed meanwhile. Whether any changed.
    @discardableResult
    public mutating func follow(_ followed: [CompletionSourceApproval]) -> Bool {
        var changed = false
        for approval in followed {
            guard let index = completionSources.firstIndex(where: { $0.plugin == approval.plugin && $0.source == approval.source }),
                  !completionSources[index].lapsed, completionSources[index] != approval else { continue }
            completionSources[index] = approval
            changed = true
        }
        return changed
    }
}

/// How a script extension's completion source stands in Settings, under its command (`Config.completionState`).
public struct ScriptCompletionState: Equatable, Sendable {
    /// Turned on, and holding for the extension as it is now: its rows may show.
    public var on: Bool
    /// Turned on before a change that turned it off (from an extension source whose updates aren't trusted): off until
    /// turned on again (`CompletionSource.scriptChanged`).
    public var changed: Bool
    /// Its source's repository is too large to check for changes (`ExtensionDigest.tooLarge`): it can't be turned on, and
    /// one turned on before it grew so is off (`CompletionSource.repositoryTooLarge`).
    public var tooLarge: Bool

    public init(on: Bool, changed: Bool, tooLarge: Bool) {
        self.on = on
        self.changed = changed
        self.tooLarge = tooLarge
    }
}

extension CompletionSource {
    /// What a script extension's source switch says it does (0.6.7.1 §2), in the interface language: it runs the script in
    /// the background for its rows (its list refreshed while you use it), and one that queries gives it what you type
    /// after the prefix.
    public func scriptSummary(in t: InterfaceWords = InterfaceWords(language: UIText.language)) -> String {
        let start = prefix.map { t.tr("在 \($0) 后面", "after \($0)") } ?? t.tr("打完整个号码后", "once the whole number is typed")
        var text = t.tr("在后台运行这个脚本，\(start)显示它给的行", "Runs this script in the background for rows \(start)")
        if list {
            let every = Self.interval(refresh, in: t)
            text += t.tr("（列表每 \(every)更新一次，只在你用到时）", " (its list refreshed every \(every), while you use it)")
        }
        if query, let prefix {
            text += t.tr("；它还会收到你在 \(prefix) 后面打的字", "; it also gets what you type after \(prefix)")
        }
        return text
    }

    /// What a script extension's source turned on before it changed says (Settings → Commands, the Mac's and the
    /// settings document's): an update from an extension source whose updates aren't trusted changed a file of its
    /// repository, its prefix, query or terms; it is off until turned on again.
    public static var scriptChanged: String {
        tr("打开以后它改过（仓库里的文件、前缀、实时查询或比较方式），已经关掉：要用的话再打开一次。",
           "It changed since you turned it on (a file of its repository, its prefix, live query or how it compares), so it's off: turn it on again to use it.")
    }

    /// What a script extension's source says when its source's repository is too large to pin (`ExtensionDigest
    /// .tooLarge`, Settings → Commands, the Mac's and the settings document's): it can't be turned on.
    public static var repositoryTooLarge: String {
        tr("它的仓库太大，没法检查改动（超过 2,000 个文件或 20 MB）。",
           "Its repository is too large to check for changes (over 2,000 files or 20 MB).")
    }
}

// MARK: - Running it

extension ScriptCommand {
    /// The environment its completion program runs with (0.6.7.1 §2): `base` (as its commands': the login shell's PATH and
    /// the rest) without anything of the protocol's it may hold, then the protocol's version, `ALLINONEIME_COMPLETION`
    /// (`load` or `query`), `ALLINONEIME_LANGUAGE` (the interface's: "en" or "zh"), `ALLINONEIME_EXTENSION_DIR`, and its
    /// bundle's preferences as `ALLINONEIME_PREF_<NAME>` (passwords from the secret store). Nothing of the field: not the
    /// app in front, not the input language, not the token (a query's text is its one argument).
    public func completionEnvironment(_ function: PluginScript.CompletionFunction, base: [String: String], language: String,
                                      preferences: [String: String] = [:]) -> [String: String] {
        var environment = base.filter { !$0.key.uppercased().hasPrefix("ALLINONEIME_") }
        environment["ALLINONEIME_PROTOCOL"] = String(Self.protocolVersion)
        environment["ALLINONEIME_VERSION"] = AppVersion.string
        environment["ALLINONEIME_COMPLETION"] = function.rawValue
        environment["ALLINONEIME_LANGUAGE"] = language
        environment["ALLINONEIME_EXTENSION_DIR"] = extensionDirectory.path
        for (name, value) in preferences { environment[ExtensionBundle.Preference.variable(name)] = value }
        return environment
    }

    /// What its programs share one run at a time (`ExtensionCompletionRunner`): its bundle's name ("bundle:units"), a
    /// single script its own id.
    public var completionTurn: String { source.bundleName.map { "bundle:" + $0 } ?? "script:" + id }
}

/// A call to a script extension's completion program: the command, the environment it runs with
/// (`ScriptCommand.completionEnvironment`), how long it may take (a list 20 seconds, a query 3), and the digest of the
/// extension the user turned its source on with (`ExtensionDigest`: only that one runs; nil: none does), unless it
/// `followsChanges` (the user's own, or from an extension source whose updates are trusted: it runs as it is now, and
/// nothing of it is read). How that digest is read again: `sourcesFolder`, the extension sources' folder (one of a
/// source is pinned by its whole repository), and `sha256`, a file's (the session's: read again only when its size or
/// date changed, `SuggestionsStore.sha256`).
public struct ExtensionCompletionCall: Sendable {
    public var command: ScriptCommand
    public var environment: [String: String]
    public var timeout: TimeInterval
    public var scriptSHA256: String?
    public var followsChanges: Bool
    public var sourcesFolder: URL
    public var sha256: @Sendable (URL) -> String?

    public init(command: ScriptCommand, environment: [String: String], timeout: TimeInterval, scriptSHA256: String?,
                followsChanges: Bool = false, sourcesFolder: URL = ExtensionSources.directory,
                sha256: @escaping @Sendable (URL) -> String? = { PluginStore.sha256(of: $0) }) {
        self.command = command
        self.environment = environment
        self.timeout = timeout
        self.scriptSHA256 = scriptSHA256
        self.followsChanges = followsChanges
        self.sourcesFolder = sourcesFolder
        self.sha256 = sha256
    }
}

/// What runs script extensions' completion programs (0.6.7.1 §2): `load` with no arguments, `query` with what follows the
/// prefix as its one argument; what it printed, as it is (the core reads it as a plugin's script's output,
/// `CompletionOutput.read`). Called off the session's thread; a call the core no longer wants (a newer query) is cancelled
/// as a task is, which stops the program.
public protocol ExtensionCompletionRuntime: Sendable {
    func load(_ call: ExtensionCompletionCall) async throws -> Data
    func query(_ text: String, _ call: ExtensionCompletionCall) async throws -> Data
}

/// Runs script extensions' completion programs as their commands run (`CommandRunner`: its launch, in its folder or its
/// `currentDirectoryPath`, /usr/local/bin on the PATH, its last line on standard error saying why it failed), with the
/// call's environment and limits of its own: a list within 20 seconds, a query within 3, 4 MB of output (a command's
/// 64 KB doesn't apply), nothing on standard input. Only the extension the user turned the source on with runs (its
/// digest, every file of its source's repository or its bundle read again as it starts, by the call's `sha256`: an
/// update may have come since; a repository grown too large to pin, `ExtensionDigest.tooLarge`, doesn't run), unless it
/// follows its changes (`ExtensionCompletionCall.followsChanges`). One program of a bundle at a time (`completionTurn`: they may
/// share state, a cookie file or a cache), the others waiting their turn; cancelling the task, waiting or running, stops
/// it, and one running passes its turn on once its process has exited (SIGTERM, then SIGKILL after half a second).
public struct ExtensionCompletionRunner: ExtensionCompletionRuntime {
    /// How long a list may take to load, whatever the command's own `timeout`.
    public static let loadTimeout: TimeInterval = PluginManifest.maxTimeout
    /// The most a program may print: a list's 4 MiB, with room for its JSON (as a plugin's script).
    static let maxOutput = PluginCompletionRuntime.maxOutput
    /// The turns every runner shares: one program of a bundle at a time in this process.
    static let turns = ProgramTurns()

    public init() {}

    public func load(_ call: ExtensionCompletionCall) async throws -> Data {
        try await run(call, arguments: [])
    }

    public func query(_ text: String, _ call: ExtensionCompletionCall) async throws -> Data {
        try await run(call, arguments: [text])
    }

    private func run(_ call: ExtensionCompletionCall, arguments: [String]) async throws -> Data {
        let command = call.command
        return try await Self.turns.run(command.completionTurn) {
            try Task.checkCancellation()
            if !call.followsChanges {
                guard let sha = call.scriptSHA256,
                      ExtensionDigest.of(command, root: call.sourcesFolder, sha256: call.sha256) == sha.lowercased() else {
                    throw ExtensionCompletionError.scriptChanged
                }
            }
            let output = try await CommandRunner.completionOutput(command, arguments: arguments, environment: call.environment,
                                                                  timeout: call.timeout, maxOutput: Self.maxOutput)
            return Data(output.utf8)
        }
    }
}

/// Why a script extension's completion program didn't run, as Settings says it.
public enum ExtensionCompletionError: Error, LocalizedError, Equatable {
    /// Its extension isn't the one its source was turned on with (a file of its source's repository or of its bundle, a
    /// single script's file), or its repository grew too large to pin.
    case scriptChanged
    /// A required preference of its bundle isn't set: its title.
    case missingPreference(String)

    public var errorDescription: String? {
        switch self {
        case .scriptChanged:
            return tr("扩展在打开补全以后改过，没有运行", "The extension changed since its suggestions were turned on: not run")
        case let .missingPreference(title):
            return tr("先在设置里填好「\(title)」", "Set “\(title)” in the settings first")
        }
    }
}

/// One program at a time for each turn (`ScriptCommand.completionTurn`): the others wait, in the order they came; one
/// cancelled while it waits leaves the line.
actor ProgramTurns {
    private var running: Set<String> = []
    private var waiting: [String: [(id: Int, resume: CheckedContinuation<Void, Error>)]] = [:]
    private var serial = 0

    /// `operation` run once it is `turn`'s turn, the next one's after it.
    func run<T: Sendable>(_ turn: String, _ operation: @Sendable () async throws -> T) async throws -> T {
        try await take(turn)
        defer { pass(turn) }
        return try await operation()
    }

    /// Whether a program of `turn` runs now, and how many wait (for the tests).
    func state(_ turn: String) -> (running: Bool, waiting: Int) { (running.contains(turn), waiting[turn]?.count ?? 0) }

    private func take(_ turn: String) async throws {
        guard running.contains(turn) else {
            running.insert(turn)
            return
        }
        serial += 1
        let id = serial
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiting[turn, default: []].append((id, continuation))
            }
        } onCancel: {
            Task { await self.leave(id, turn) }
        }
    }

    /// The turn passes to the first waiting, else it's free.
    private func pass(_ turn: String) {
        guard var line = waiting[turn], !line.isEmpty else {
            running.remove(turn)
            return
        }
        let next = line.removeFirst()
        waiting[turn] = line.isEmpty ? nil : line
        next.resume.resume()
    }

    /// The call `id` was cancelled: out of the line, if it still waits.
    private func leave(_ id: Int, _ turn: String) {
        guard let index = waiting[turn]?.firstIndex(where: { $0.id == id }) else { return }
        let left = waiting[turn]!.remove(at: index)
        if waiting[turn]?.isEmpty == true { waiting[turn] = nil }
        left.resume.resume(throwing: CancellationError())
    }
}

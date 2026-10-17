import AllInOneIMECore
import Foundation

/// `--add-source`, `--update-sources`, `--list-extensions`: extension sources from a terminal or a script, as Settings
/// does them. Running `--add-source` is the consent the review's Enable button is in Settings. `--config FILE` and
/// `--sources-dir DIR` point them at another config file and clones folder (the self-test's), never needed otherwise.
/// What they change reaches a running input method: it reads the config file again when it changes (`LiveConfig`), its
/// extensions when a text field becomes active, and Settings is told (`ExtensionSourceController.changedNotification`).
enum ExtensionSourceCommands {
    struct Options {
        var configURL = Config.defaultURL
        var root = ExtensionSources.directory
        var positional: [String] = []
        var values: [String: String] = [:]
        /// An option this command doesn't take, or one without its value.
        var problem: String?
    }

    /// Every one of them takes these, with a value.
    static let common: Set<String> = ["--config", "--sources-dir"]

    static func options(_ arguments: [String], allowed: Set<String> = common) -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("-") {
                guard allowed.contains(argument) else {
                    options.problem = "unknown option \(argument)"
                    break
                }
                guard index + 1 < arguments.count else {
                    options.problem = "\(argument) needs a value"
                    break
                }
                options.values[argument] = arguments[index + 1]
                index += 2
                continue
            }
            options.positional.append(argument)
            index += 1
        }
        if let path = options.values["--config"] { options.configURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        if let path = options.values["--sources-dir"] {
            options.root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return options
    }

    /// The error, then for a git error or a timeout the generic hint and the source's own `authHint`.
    private static func fail(_ error: Error, source: ExtensionSource? = nil) -> Int32 {
        printError("✗ " + ((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        hints(for: error, source: source).forEach { printError("  " + $0) }
        return 1
    }

    /// Under a git error or a timeout: "This uses your own git and SSH setup; check that git ls-remote <url> works in
    /// Terminal.", then the source's own hint, if it has one.
    static func hints(for error: Error, source: ExtensionSource?) -> [String] {
        switch error as? ExtensionSourceError {
        case .git?, .timedOut?:
            return ["This uses your own git and SSH setup; check that git ls-remote \(source?.url ?? "<url>") works in Terminal."]
                + (source?.authHint.map { [$0] } ?? [])
        default: return []
        }
    }

    private static func manager(_ options: Options) -> ExtensionSourceManager {
        let git = UpdateCommands.wait { await ProcessGitRunner.user() }
        return ExtensionSourceManager(root: options.root, git: (try? git.get()) ?? ProcessGitRunner(environment: ShellEnvironment.current))
    }

    static let addUsage = "usage: --add-source URL [--path FOLDER] [--branch BRANCH] [--pin TAG-OR-COMMIT]"

    /// `--add-source URL [--path P] [--branch B] [--pin REF]`: cloned into staging, its review printed, then put in place
    /// and enabled. Also how a source whose history was rewritten (a force push) is reviewed again and re-cloned.
    static func add(_ arguments: [String]) -> Int32 {
        let options = options(arguments, allowed: common.union(["--path", "--branch", "--pin"]))
        if let problem = options.problem {
            printError("✗ \(problem)\n\(addUsage)")
            return 2
        }
        guard options.positional.count == 1, let url = options.positional.first else {
            printError(addUsage)
            return 2
        }
        var source = ExtensionSource(url: url, path: options.values["--path"], branch: options.values["--branch"], pin: options.values["--pin"])
        do {
            source.url = try ExtensionSources.validate(url)
            var config = try Config.load(from: options.configURL)
            // An entry the config has for it already (handed out with its hint, say): its settings unless given here.
            if let had = config.extensionSources.first(where: { $0.url == source.url }) {
                source.path = source.path ?? had.path
                source.branch = source.branch ?? had.branch
                source.pin = source.pin ?? had.pin
                source.autoCheck = had.autoCheck
                source.authHint = had.authHint
            }
            let statuses = ExtensionSourceStatus.load(from: options.root.appendingPathComponent(ExtensionSources.statusFileName))
            // Added and reviewed already: only again after a force push, which needs a new review.
            if config.extensionSources.contains(where: { $0.url == source.url }), ExtensionSources.isTrusted(source, statuses[source.url]),
               statuses[source.url]?.fastForward != false {
                throw ExtensionSourceError.alreadyAdded
            }
            let manager = manager(options)
            let cloning = source
            let staged = try UpdateCommands.wait { try await manager.stage(cloning) }.get()
            let path: String
            do {
                path = try ExtensionSources.resolveBundlePath(source.path, in: staged.folder)
            } catch {
                manager.discard(staged)
                throw error
            }
            source.path = path.isEmpty ? nil : path
            var others = config
            let own = ExtensionSources.comparable(ExtensionSources.bundleFolder(for: source, root: options.root).path)
            others.extensionFolders.removeAll { ExtensionSources.comparable($0) == own }
            let review = ExtensionSourceReview.make(bundleFolder: path.isEmpty ? staged.folder : staged.folder.appendingPathComponent(path),
                                                    path: path, url: source.url, commit: staged.status.commit,
                                                    commitDate: staged.status.commitDate, config: others, plugins: PluginStore.load().0,
                                                    found: LiveExtensions.found, repository: staged.folder)
            UIText.choice = "en"
            review.summary(describe: { UIText.describe($0, file: $1) }).forEach { print($0) }
            guard review.bundle != nil else {
                manager.discard(staged)
                printError("✗ the bundle can't be loaded: not enabled")
                return 1
            }
            // Read again: the input method or Settings may have written it meanwhile. An unreviewed folder of the
            // sources folder in its load list goes first, then the reviewed clone takes its place.
            config = try Config.load(from: options.configURL)
            var all = ExtensionSourceStatus.load(from: manager.statusFile)
            ExtensionSources.quarantine(&config, statuses: all, root: options.root)
            let installed: ExtensionSourceManager.Clone
            do {
                installed = try manager.install(staged)
            } catch {
                manager.discard(staged)
                throw error
            }
            // Trusted first, then in the load list: the load list never names a folder the statuses don't vouch for.
            var trusted = installed.status
            trusted.trusted = true
            all = ExtensionSourceStatus.load(from: manager.statusFile)
            all[source.url] = trusted
            try manager.save(all)
            ExtensionSources.enable(source, in: &config, root: options.root)
            try config.write(to: options.configURL)
            ExtensionSourceController.postChanged()
            print("enabled:     \(ExtensionSources.loadPath(for: source, root: options.root))")
            return 0
        } catch {
            return fail(error, source: source)
        }
    }

    /// `--update-sources`: each reviewed source that isn't pinned, fetched and fast-forwarded; what changed printed.
    static func update(_ arguments: [String]) -> Int32 {
        let options = options(arguments)
        if let problem = options.problem ?? (options.positional.isEmpty ? nil : "unexpected \(options.positional[0])") {
            printError("✗ \(problem)\nusage: --update-sources")
            return 2
        }
        let config: Config
        do {
            config = try Config.load(from: options.configURL)
        } catch {
            return fail(error)
        }
        let manager = manager(options)
        var failed = 0
        for source in config.extensionSources {
            let name = source.repositoryName
            var statuses = manager.statuses()
            guard let status = statuses[source.url], ExtensionSources.isTrusted(source, status) else {
                print("\(name): not reviewed and enabled yet (--add-source \(source.url)); skipped")
                continue
            }
            if let pin = source.pin {
                print("\(name): pinned to \(pin); not updated")
                continue
            }
            switch UpdateCommands.wait({ () async throws -> (ExtensionSourceStatus, ExtensionSourceStatus) in
                let checked = try await manager.check(source, status)
                return (checked, checked.updates.isEmpty ? checked : try await manager.update(source, checked))
            }) {
            case let .success((checked, updated)):
                if checked.updates.isEmpty {
                    print("\(name): up to date at \(updated.shortCommit ?? "?")")
                } else {
                    print("\(name): \(status.shortCommit ?? "?") → \(updated.shortCommit ?? "?") (\(checked.updates.count) commit\(checked.updates.count == 1 ? "" : "s"))")
                    for commit in checked.updates { print("  \(commit.shortSHA) \(commit.subject) — \(commit.author)") }
                }
                statuses = manager.statuses()
                statuses[source.url] = updated
                try? manager.save(statuses)
            case let .failure(error):
                failed += 1
                printError("✗ \(name): " + ((error as? LocalizedError)?.errorDescription ?? "\(error)"))
                hints(for: error, source: source).forEach { printError("  " + $0) }
                if case ExtensionSourceError.notFastForward = error {
                    printError("  Review the rewritten history before it's used: --add-source \(source.url)")
                }
                statuses = manager.statuses()
                statuses[source.url]?.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                if case ExtensionSourceError.notFastForward = error { statuses[source.url]?.fastForward = false }
                try? manager.save(statuses)
            }
        }
        ExtensionSourceController.postChanged()
        return failed == 0 ? 0 : 1
    }

    /// `--list-extensions`: the commands the extensions give (name, where from, output), then those left out and why.
    static func list(_ arguments: [String]) -> Int32 {
        let options = options(arguments)
        if let problem = options.problem ?? (options.positional.isEmpty ? nil : "unexpected \(options.positional[0])") {
            printError("✗ \(problem)\nusage: --list-extensions")
            return 2
        }
        let config: Config
        do {
            config = try Config.load(from: options.configURL)
        } catch {
            return fail(error)
        }
        UIText.choice = "en"
        let plugins = PluginStore.load().0
        // As the input method loads them: an extension source's folder only once it's reviewed, and only as its bundle.
        let statuses = ExtensionSourceStatus.load(from: options.root.appendingPathComponent(ExtensionSources.statusFileName))
        let unreviewed = Set(ExtensionSources.untrustedFolders(in: config, statuses: statuses, root: options.root).map(ExtensionSources.comparable))
        let index = ExtensionStore.load(ExtensionSources.loadFolders(config, found: LiveExtensions.found, statuses: statuses, root: options.root))
        let enabled = index.enabled(config.disabledExtensions)
        let names = Dictionary(Command.catalog(config.customCommands, plugins: plugins, scripts: enabled)
            .compactMap { command in command.script.map { ($0.id, command.name) } }, uniquingKeysWith: { first, _ in first })
        let hidden = Dictionary(Command.hiddenScripts(enabled, custom: config.customCommands, plugins: plugins)
            .map { ($0.script.id, ScriptCommand.Problem.nameTaken($0.script.name, by: $0.owner)) }, uniquingKeysWith: { first, _ in first })
        let sources = config.extensionSources.map { ($0.url, ExtensionSources.comparable(ExtensionSources.bundleFolder(for: $0, root: options.root).path)) }
        func origin(_ command: ScriptCommand) -> String {
            let folder = ExtensionSources.comparable(command.extensionDirectory.path)
            return sources.first { $0.1 == folder }?.0 ?? ExtensionStore.abbreviated(command.extensionDirectory.path)
        }
        for command in index.commands {
            let shown = names[command.id].map { "@" + $0 } ?? "@" + command.name
            var note = ""
            if !enabled.contains(command) { note = "  [off]" } else if let problem = hidden[command.id] {
                note = "  [left out: " + UIText.describe(problem, file: command.file) + "]"
            }
            print("\(shown)\t\(command.output.rawValue)\t\(origin(command))\(note)")
        }
        for folder in unreviewed.sorted() {
            print("skipped\t\(ExtensionStore.abbreviated(folder))\tan extension source's folder that isn't reviewed here (--add-source to review it)")
        }
        for skipped in index.skipped {
            print("skipped\t\(ExtensionStore.abbreviated(skipped.file.path))\t" + UIText.describe(skipped.problem, file: skipped.file))
        }
        return 0
    }
}

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
    }

    static func options(_ arguments: [String]) -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--"), index + 1 < arguments.count {
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

    private static func fail(_ error: Error, url: String? = nil) -> Int32 {
        printError("✗ " + ((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        if case ExtensionSourceError.git = error {
            printError("  This uses your own git and SSH setup; check that git ls-remote \(url ?? "<url>") works in Terminal.")
        }
        return 1
    }

    private static func manager(_ options: Options) -> ExtensionSourceManager {
        let git = UpdateCommands.wait { await ProcessGitRunner.user() }
        return ExtensionSourceManager(root: options.root, git: (try? git.get()) ?? ProcessGitRunner(environment: ShellEnvironment.current))
    }

    /// `--add-source URL [--path P] [--branch B] [--pin REF]`: cloned, its review printed, enabled.
    static func add(_ arguments: [String]) -> Int32 {
        let options = options(arguments)
        guard let url = options.positional.first else {
            printError("usage: --add-source URL [--path FOLDER] [--branch BRANCH] [--pin TAG-OR-COMMIT]")
            return 2
        }
        var source = ExtensionSource(url: url, path: options.values["--path"], branch: options.values["--branch"], pin: options.values["--pin"])
        do {
            source.url = try ExtensionSources.validate(url)
            var config = try Config.load(from: options.configURL)
            let statuses = ExtensionSourceStatus.load(from: options.root.appendingPathComponent(ExtensionSources.statusFileName))
            if config.extensionSources.contains(where: { $0.url == source.url }), ExtensionSources.isTrusted(source, statuses[source.url]) {
                throw ExtensionSourceError.alreadyAdded
            }
            let manager = manager(options)
            let cloning = source
            let clone = try UpdateCommands.wait { try await manager.clone(cloning) }.get()
            let path: String
            do {
                path = try ExtensionSources.resolveBundlePath(source.path, in: clone.folder)
            } catch {
                manager.discard(source)
                throw error
            }
            source.path = path.isEmpty ? nil : path
            let review = ExtensionSourceReview.make(bundleFolder: ExtensionSources.bundleFolder(for: source, root: options.root), path: path,
                                                    url: source.url, commit: clone.status.commit, commitDate: clone.status.commitDate,
                                                    config: config, plugins: PluginStore.load().0, found: LiveExtensions.found)
            review.summary.forEach { print($0) }
            guard review.bundle != nil else {
                manager.discard(source)
                printError("✗ the bundle can't be loaded: not enabled")
                return 1
            }
            // Read again: the input method or Settings may have written it meanwhile.
            config = try Config.load(from: options.configURL)
            ExtensionSources.enable(source, in: &config, root: options.root)
            try config.write(to: options.configURL)
            var trusted = clone.status
            trusted.trusted = true
            var all = ExtensionSourceStatus.load(from: manager.statusFile)
            all[source.url] = trusted
            try manager.save(all)
            ExtensionSourceController.postChanged()
            print("enabled:     \(ExtensionSources.loadPath(for: source, root: options.root))")
            return 0
        } catch {
            return fail(error, url: source.url)
        }
    }

    /// `--update-sources`: each trusted source that isn't pinned, fetched and fast-forwarded; what changed printed.
    static func update(_ arguments: [String]) -> Int32 {
        let options = options(arguments)
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
                if case ExtensionSourceError.git = error { printError("  This uses your own git and SSH setup; check that git ls-remote \(source.url) works in Terminal.") }
                if let hint = source.authHint { printError("  \(hint)") }
                statuses = manager.statuses()
                statuses[source.url]?.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                try? manager.save(statuses)
            }
        }
        ExtensionSourceController.postChanged()
        return failed == 0 ? 0 : 1
    }

    /// `--list-extensions`: the commands the extensions give (name, where from, output), then those left out and why.
    static func list(_ arguments: [String]) -> Int32 {
        let options = options(arguments)
        let config: Config
        do {
            config = try Config.load(from: options.configURL)
        } catch {
            return fail(error)
        }
        UIText.choice = .english
        let plugins = PluginStore.load().0
        let index = ExtensionStore.load(ExtensionStore.folders(config, found: LiveExtensions.found))
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
        for skipped in index.skipped {
            print("skipped\t\(ExtensionStore.abbreviated(skipped.file.path))\t" + UIText.describe(skipped.problem, file: skipped.file))
        }
        return 0
    }
}

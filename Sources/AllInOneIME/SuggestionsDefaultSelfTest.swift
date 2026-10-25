import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import SwiftUI

extension SelfTest {
    /// Suggestions on by default (0.6.7.2, owner 2026-10-25) in Settings, with config files, an extensions folder, a
    /// sources folder and a plugins folder of its own (never the user's): an extension of the user's own shows its
    /// suggestions' switch on as it loads, nothing approved; turned off, the choice is saved (`completionSourcesOff`) and
    /// kept as the extensions are read again and in a new window (a restart); turned on again, it is off the list. A
    /// source added (Settings' Enable, then `--add-source` from a local bare repository) has its suggestions on, pinned to
    /// its repository as it is then. A plugin found in the plugins folder for the first time has its source on, approved
    /// as it is; turned off, it stays off as the folder is read again, in a new window, and once removed in Settings and
    /// put in the folder again. Drawn (settings-extension-completion-on.png).
    static func testSuggestionsOnByDefault(snapshotDirectory: URL) {
        section("suggestions: on by default, turned off kept")
        let fm = FileManager.default
        let dir = snapshotDirectory.appendingPathComponent("suggestions-on-by-default", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let realBefore = try? Data(contentsOf: Config.userURL)
        let sources = ExtensionSourceController.shared
        let before = (sources.root, sources.statuses, UIText.choice)
        defer {
            sources.root = before.0
            sources.show(before.1)
            UIText.choice = before.2
        }
        UIText.choice = "en"
        sources.root = dir.appendingPathComponent("Sources", isDirectory: true)
        func write(_ url: URL, _ text: String, executable: Bool = false) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: url)
            if executable { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        }
        /// A bundle `name` whose one command `name` declares suggestions after "NB-", in `folder`.
        func notes(_ name: String, in folder: URL) {
            write(folder.appendingPathComponent("extension.json"), #"""
                {"schemaVersion": 1, "name": "\#(name)", "title": "Notes",
                 "commands": [{"script": "notes.sh", "name": "\#(name)", "title": "Notes",
                               "completion": {"prefix": "NB-", "list": true, "refresh": "1h"}}]}
                """#)
            write(folder.appendingPathComponent("notes.sh"), "#!/bin/sh\necho '{\"items\": []}'\n", executable: true)
        }

        // A switch as VoiceOver finds it: whether it can be pressed, and how it stands.
        func appKitSwitches(_ view: NSView) -> [NSSwitch] { ((view as? NSSwitch).map { [$0] } ?? []) + view.subviews.flatMap(appKitSwitches) }
        func shown<V: View>(_ view: V) -> NSControl.StateValue? {
            let window = NSWindow(contentViewController: NSHostingController(rootView: Form { view }.formStyle(.grouped)))
            window.setContentSize(NSSize(width: 640, height: 220))
            window.orderFront(nil)
            defer { window.close() }
            _ = pump(timeout: 0.5) { false }
            let switches = window.contentView.map(appKitSwitches) ?? []
            return switches.count == 1 && switches[0].isEnabled ? switches[0].state : nil
        }

        // An extension of the user's own.
        let own = dir.appendingPathComponent("extensions", isDirectory: true)
        notes("selftestownnotes", in: own.appendingPathComponent("notes", isDirectory: true))
        let configURL = dir.appendingPathComponent("config.json")
        var fresh = Config.default
        fresh.extensionFolders = [own.path]
        fresh.findRaycastScripts = false
        try? fresh.write(to: configURL)
        func saved() -> Config? { try? Config.load(from: configURL) }
        var model = SettingsModel(configURL: configURL)
        model.refreshExtensions()
        guard let command = model.extensionIndex.commands.first(where: { $0.name == "selftestownnotes" }),
              case let .success(declared)? = command.completion else {
            check(false, "the extension of your own with its suggestions loads (\(model.extensionIndex.commands.map(\.name)))")
            return
        }
        func row() -> NSControl.StateValue? { shown(ScriptCompletionView(model: model, command: command)) }
        check(row() == .on && saved()?.completionSources.isEmpty == true && saved()?.completionSourcesOff.isEmpty == true,
              "an extension of your own: its suggestions' switch on as it loads, nothing approved")
        let image = snapshotDirectory.appendingPathComponent("settings-extension-completion-on.png")
        renderOffscreen(Form { ScriptCompletionView(model: model, command: command) }.formStyle(.grouped), size: NSSize(width: 640, height: 160),
                        to: image)
        check(fm.fileExists(atPath: image.path), "…drawn (\(image.lastPathComponent))")
        model.setCompletionSource(declared, of: command, enabled: false)
        let key = CompletionSourceKey(extension: command)
        check(saved()?.completionSourcesOff == [key] && row() == .off, "turned off: saved (completionSourcesOff), its switch off")
        model.refreshExtensions()
        check(row() == .off, "…kept as the extensions are read again")
        model = SettingsModel(configURL: configURL)
        model.refreshExtensions()
        check(row() == .off, "…and in a new window (a restart)")
        model.setCompletionSource(declared, of: command, enabled: true)
        check(saved()?.completionSourcesOff.isEmpty == true && row() == .on, "turned on again: off the list, its switch on")

        // A source added in Settings (its updates not trusted): its suggestions on, its repository read off the main thread.
        let source = ExtensionSource(url: "https://git.example.com/team/notes.git", path: "ext")
        notes("selftestsourcenotes", in: ExtensionSources.bundleFolder(for: source, root: sources.root))
        write(ExtensionSources.cloneFolder(for: source.url, root: sources.root).appendingPathComponent("README.md"), "Notes.\n")
        let statuses = [source.url: ExtensionSourceStatus(url: source.url, trusted: true, branch: "main",
                                                          commit: "4f2a9c1e0b7d3a6f8e1c2b5d9a0f3e7c6b1d2a4f")]
        try? ExtensionSourceStatus.save(statuses, to: sources.statusFile)
        sources.show(statuses)
        ExtensionSources.enable(source, in: &model.config, root: sources.root)
        model.save()
        model.refreshExtensions()
        _ = pump(timeout: 15) { model.extensionWork == 0 }
        guard let added = model.extensionIndex.commands.first(where: { $0.name == "selftestsourcenotes" }) else {
            check(false, "the source's command with its suggestions loads (\(model.extensionIndex.commands.map(\.name)))")
            return
        }
        check(shown(ScriptCompletionView(model: model, command: added)) == .off, "a source's, before it is added: off (nothing approved it)")
        model.approveAddedSource(source, root: sources.root)
        _ = pump(timeout: 15) { model.extensionWork == 0 }
        let pinned = ExtensionDigest.of(added, root: sources.root)
        check(pinned != nil && saved()?.completionSources.first(where: { $0.source == added.id })?.scriptSHA256 == pinned
              && shown(ScriptCompletionView(model: model, command: added)) == .on,
              "added in Settings: its suggestions on, pinned to its repository as it is then")

        // From the command line: --add-source of a local bare repository whose bundle declares suggestions.
        let bare = dir.appendingPathComponent("remote.git"), work = dir.appendingPathComponent("work")
        func git(_ arguments: [String], in folder: URL = work) -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-c", "user.name=Self Test", "-c", "user.email=selftest@example.com", "-c", "commit.gpgsign=false"] + arguments
            process.currentDirectoryURL = folder
            var env = ProcessInfo.processInfo.environment
            env["GIT_CONFIG_GLOBAL"] = "/dev/null"
            process.environment = env
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }
        notes("selftestclinotes", in: work.appendingPathComponent("ext", isDirectory: true))
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        if git(["init", "-q", "--bare", "-b", "main", bare.path], in: dir), git(["init", "-q", "-b", "main", work.path], in: dir),
           git(["remote", "add", "origin", bare.path]), git(["add", "-A"]), git(["commit", "-q", "-m", "First"]), git(["push", "-q", "origin", "main"]) {
            let cliConfig = dir.appendingPathComponent("cli-config.json"), cliRoot = dir.appendingPathComponent("CLI", isDirectory: true)
            try? fresh.write(to: cliConfig)
            let url = "file://" + bare.path
            let run = runSelf(["--add-source", url, "--config", cliConfig.path, "--sources-dir", cliRoot.path])
            let written = try? Config.load(from: cliConfig)
            let cli = written?.extensionSources.first.map { ExtensionSources.extensions(of: $0, root: cliRoot) }?.first
            check(run.status == 0 && run.output.contains("suggestions: on for selftestclinotes") && cli != nil
                  && written?.completionSources.first(where: { $0.source == cli?.id })?.scriptSHA256 == cli.flatMap { ExtensionDigest.of($0, root: cliRoot) },
                  "--add-source: its suggestions on, pinned to its repository (\(run.status): \(run.output.split(separator: "\n").suffix(2)))")
        } else {
            check(false, "made a local bare repository (git with the command line tools)")
        }

        // A plugin found in the plugins folder for the first time.
        let plugins = dir.appendingPathComponent("plugins", isDirectory: true)
        let pluginFolder = plugins.appendingPathComponent("selftestnotes", isDirectory: true)
        func writePlugin() {
            write(pluginFolder.appendingPathComponent("plugin.json"), #"""
                { "name": "selftestnotes", "version": "1.0.0", "type": "script", "script": "main.js", "hosts": ["notes.example.com"],
                  "completions": [ { "name": "pages", "title": "Pages", "prefix": "NB-", "list": true, "insert": { "default": "{arg}" } } ] }
                """#)
            write(pluginFolder.appendingPathComponent("main.js"), "function load(ctx) { return { items: [] }; }\n")
        }
        writePlugin()
        model.pluginsFolder = plugins
        model.refreshPlugins()
        guard let plugin = model.plugins.first(where: { $0.name == "selftestnotes" }), let pages = plugin.manifest.completions.first else {
            check(false, "the plugin with its suggestions loads (\(model.plugins.map(\.name)), \(model.skippedPlugins))")
            return
        }
        func pluginRow() -> NSControl.StateValue? { shown(PluginCompletionsView(model: model, plugin: plugin)) }
        check(saved()?.pluginsSeen == ["selftestnotes"]
              && saved()?.completionSources.first(where: { $0.plugin == "selftestnotes" }) == CompletionSourceApproval(enabling: pages, of: plugin)
              && pluginRow() == .on, "a plugin found for the first time: its suggestions on, approved as it is (its hosts, script, terms)")
        let pagesKey = CompletionSourceKey(plugin: "selftestnotes", source: "pages")
        model.setCompletionSource(pages, of: plugin, enabled: false)
        check(saved()?.completionSourcesOff.contains(pagesKey) == true && pluginRow() == .off, "turned off: saved, its switch off")
        model.refreshPlugins()
        check(pluginRow() == .off, "…kept as the plugins folder is read again")
        model = SettingsModel(configURL: configURL)
        model.pluginsFolder = plugins
        model.refreshPlugins()
        check(pluginRow() == .off && saved()?.completionSources.contains(where: { $0.plugin == "selftestnotes" }) == false,
              "…and in a new window (a restart)")
        // Removed in Settings, then put in the plugins folder again: found anew, but what the user turned off stays off.
        model.uninstall(plugin)
        check(model.pluginError == nil && !fm.fileExists(atPath: pluginFolder.path) && saved()?.pluginsSeen.isEmpty == true
              && saved()?.completionSourcesOff.contains(pagesKey) == true,
              "…removed in Settings: forgotten that it was found, not that it was turned off (\(saved()?.completionSourcesOff ?? []))")
        writePlugin()
        model.refreshPlugins()
        let again = model.plugins.first { $0.name == "selftestnotes" }
        check(again.flatMap { shown(PluginCompletionsView(model: model, plugin: $0)) } == .off && saved()?.pluginsSeen == ["selftestnotes"]
              && saved()?.completionSources.contains(where: { $0.plugin == "selftestnotes" }) == false,
              "…put in the folder again: found anew, its suggestions still off")
        check((try? Data(contentsOf: Config.userURL)) == realBefore, "the real config file was not touched")
    }
}

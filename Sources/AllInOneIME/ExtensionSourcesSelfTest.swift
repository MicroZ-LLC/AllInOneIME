import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import os
import SwiftUI

extension SelfTest {
    /// Extension sources end to end, against a bare repository made here (file://, never the network), with a config
    /// file and a clones folder of their own (never the user's sources or config): add, review, enable, a new commit
    /// upstream, check, update, a pin, the command line (`--add-source`, `--list-extensions`, `--update-sources`) and a
    /// settings model picking up what it wrote, then remove. Settings → Custom Commands and the review are drawn
    /// (settings-commands-sources*.png, extension-source-review*.png).
    static func testExtensionSources(snapshotDirectory: URL) {
        section("extension sources (a local bare repository)")
        let fm = FileManager.default
        let dir = snapshotDirectory.appendingPathComponent("extension-sources", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let realBefore = try? Data(contentsOf: Config.userURL)
        let sources = ExtensionSourceController.shared
        let before = (sources.root, sources.git, sources.statuses, sources.trashItem)
        defer {
            (sources.root, sources.git, sources.trashItem) = (before.0, before.1, before.3)
            sources.show(before.2)
        }
        let pickedBefore = UIText.choice
        defer { UIText.choice = pickedBefore }
        UIText.choice = "en"

        // The repository: a bundle in ext/ with one command.
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
        func write(_ path: String, _ text: String, executable: Bool = false) {
            let file = work.appendingPathComponent(path)
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: file)
            try? fm.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: file.path)
        }
        func commit(_ message: String) -> Bool { git(["add", "-A"]) && git(["commit", "-q", "-m", message]) && git(["push", "-q", "origin", "main"]) }
        write("ext/extension.json", """
            { "schemaVersion": 1, "name": "selftestgreetings", "title": "Greetings", "version": "1.0.0", "author": "Self Test",
              "description": "Says hello.",
              "preferences": [{ "name": "greeting", "type": "textfield", "title": "Greeting", "default": "hi" }],
              "commands": [{ "script": "hello.sh", "name": "selftesthello", "title": "Say Hello", "description": "Prints a greeting.",
                             "output": "show", "input": "none" }] }
            """)
        write("ext/hello.sh", "#!/bin/sh\necho hi\n", executable: true)
        guard git(["init", "-q", "--bare", "-b", "main", bare.path], in: dir), git(["init", "-q", "-b", "main", work.path], in: dir),
              git(["remote", "add", "origin", bare.path]), commit("First") else {
            check(false, "made a local bare repository (git with the command line tools)")
            return
        }
        let url = "file://" + bare.path

        // Its own clones folder and git (the user's environment: no prompts, batch ssh; file:// needs no network).
        sources.root = dir.appendingPathComponent("Sources", isDirectory: true)
        sources.git = ProcessGitRunner(environment: ExtensionSources.gitEnvironment(base: ShellEnvironment.current, login: ShellEnvironment.login))
        sources.trashItem = { try FileManager.default.removeItem(at: $0) }
        sources.show([:])
        let configURL = dir.appendingPathComponent("config.json")
        var fresh = Config.default
        fresh.extensionFolders = []
        fresh.findRaycastScripts = false
        try? fresh.write(to: configURL)
        let model = SettingsModel(configURL: configURL)

        // Add: cloned into staging for the review; nothing is in place or loads yet.
        var source = ExtensionSource(url: url)
        guard let clone = runAsync(60, { try await sources.stageForReview(source) }) else {
            check(false, "cloned the local repository")
            return
        }
        let installed = ExtensionSources.cloneFolder(for: url, root: sources.root)
        check(clone.bundles == ["ext"] && clone.status.commit?.count == 40 && !clone.status.trusted
              && clone.folder.path.contains("/.staging/") && !fm.fileExists(atPath: installed.path),
              "cloned (shallow) into staging, not in place; the bundle found in ext/")
        source.path = "ext"
        let review = ExtensionSourceReview.make(bundleFolder: clone.folder.appendingPathComponent("ext"), path: "ext",
                                                url: url, commit: clone.status.commit, commitDate: clone.status.commitDate, config: model.config,
                                                repository: clone.folder)
        check(review.bundle?.title == "Greetings" && review.commands.map(\.name) == ["selftesthello"] && review.programs == ["hello.sh"]
              && review.preferences.map(\.name) == ["greeting"],
              "the review: the bundle, its command, the program it runs, its preference")
        check(Command.catalog(model.config.customCommands, scripts: LiveExtensions.load(model.config).commands).allSatisfy { $0.name != "selftesthello" },
              "nothing of it loads before Enable")
        for chinese in [false, true] {
            UIText.choice = chinese ? "zh" : "en"
            let image = snapshotDirectory.appendingPathComponent("extension-source-add\(chinese ? "-zh" : "").png")
            let start = ExtensionSourceSheet.Start(source: ExtensionSource(url: "git@github.com:you/my-extensions.git"), cloneNow: false)
            renderOffscreen(ExtensionSourceSheet(model: model, start: start), size: NSSize(width: 600, height: 600), to: image)
            check(fm.fileExists(atPath: image.path), "the Add from Link sheet renders (\(image.lastPathComponent))")
        }
        for chinese in [false, true] {
            UIText.choice = chinese ? "zh" : "en"
            let image = snapshotDirectory.appendingPathComponent("extension-source-review\(chinese ? "-zh" : "").png")
            renderOffscreen(ExtensionSourceReviewView(review: review).frame(width: 600, height: 620), size: NSSize(width: 600, height: 620), to: image)
            check(fm.fileExists(atPath: image.path), "the review renders (\(image.lastPathComponent))")
        }
        UIText.choice = "en"
        check(ExtensionSourceText.unsigned(url).hasPrefix("This source isn't signed: it will run programs from file://"), "…with its warning")

        // A config that names the folder before it's reviewed (copied from another Mac): it isn't loaded.
        var copied = model.config
        ExtensionSources.enable(source, in: &copied, root: sources.root)
        try? fm.createDirectory(at: installed, withIntermediateDirectories: true)
        try? fm.copyItem(at: clone.folder.appendingPathComponent("ext"), to: installed.appendingPathComponent("ext"))
        check(!LiveExtensions.load(copied).commands.contains { $0.name == "selftesthello" }
              && ExtensionSources.untrustedFolders(in: copied, statuses: sources.statuses, root: sources.root).count == 1,
              "an unreviewed source's folder in the load list doesn't load")
        try? fm.removeItem(at: installed)

        // Enable: the staged clone in place, trusted, the bundle's folder in the load list (saved), and its command loads.
        check((try? sources.install(clone)) != nil && fm.fileExists(atPath: installed.appendingPathComponent("ext/hello.sh").path)
              && !fm.fileExists(atPath: clone.folder.path), "Enable moves the clone into place")
        ExtensionSources.enable(source, in: &model.config, root: sources.root)
        model.save()
        model.refreshExtensions()
        let stored = try? Config.load(from: configURL)
        check(stored?.extensionSources.map(\.url) == [url] && stored.map { ExtensionSources.isEnabled(source, in: $0, root: sources.root) } == true,
              "Enable saves the source and its folder in the load list")
        check(model.extensionIndex.commands.map(\.name) == ["selftesthello"], "…and its command loads (\(model.extensionIndex.commands.map(\.name)))")
        check(ExtensionSourceStatus.load(from: sources.statusFile)[url]?.trusted == true, "…trusted, with its address, in sources.json")

        // A new commit upstream: a check lists it; nothing changes until Update.
        write("ext/hello.sh", "#!/bin/sh\necho hello there\n", executable: true)
        _ = commit("Say more")
        _ = runAsync(60) { await sources.check(source) }
        let status = sources.statuses[url]
        check(status?.updates.map(\.subject) == ["Say more"] && status?.fastForward == true && sources.updateCount(for: model.config.extensionSources) == 1,
              "a check finds the new commit (\(status?.updates.map(\.subject) ?? []), error \(status?.error ?? "none"))")
        let script = installed.appendingPathComponent("ext/hello.sh")
        check((try? String(contentsOf: script, encoding: .utf8))?.contains("echo hi") == true, "…and doesn't apply it")
        for chinese in [false, true] {
            UIText.choice = chinese ? "zh" : "en"
            let image = snapshotDirectory.appendingPathComponent("settings-commands-sources\(chinese ? "-zh" : "").png")
            SettingsImage.render(model, page: .commands, to: image) { _ = pump(timeout: $0) { false } }
            check(fm.fileExists(atPath: image.path), "Custom Commands shows the source with its update (\(image.lastPathComponent))")
        }
        // The menu bar panel's quiet line.
        UIText.choice = "en"
        let notice = snapshotDirectory.appendingPathComponent("panel-extension-sources.png")
        renderOffscreen(ExtensionSourceNotice(sources: sources, configured: { [source] }, open: {}).padding(10).frame(width: 360)
                            .background(Color.white).environment(\.colorScheme, .light),
                        size: NSSize(width: 360, height: 40), to: notice)
        check(fm.fileExists(atPath: notice.path) && sources.updateCount(for: [source]) == 1,
              "the menu bar panel's line says there is 1 update (\(notice.lastPathComponent))")
        UIText.choice = "en"
        _ = runAsync(60) { await sources.update(source) }
        check(sources.statuses[url]?.updates.isEmpty == true && sources.statuses[url]?.commit != clone.status.commit
              && (try? String(contentsOf: script, encoding: .utf8))?.contains("hello there") == true,
              "Update fast-forwards the clone")

        // Pinned: not checked, by itself or with Check Now.
        source.pin = clone.status.commit
        check(!ExtensionSources.shouldCheck(source, status: sources.statuses[url], automatic: true)
              && !ExtensionSources.shouldCheck(source, status: sources.statuses[url], automatic: false), "a pinned source isn't checked")
        let head = sources.statuses[url]?.commit
        _ = runAsync(60) { await sources.pin(source, to: clone.status.commit) }
        check(sources.statuses[url]?.commit == clone.status.commit, "changing the pin checks that commit out")
        source.pin = nil
        let unpinned = runAsync(60) { await sources.pin(source, to: nil) }
        check(unpinned.map { $0 == nil } == true && sources.statuses[url]?.commit == head, "Unpin goes back to the branch's newest commit")

        // A force push: Update is refused; the rewritten history is reviewed (staged) before it replaces the clone.
        write("ext/hello.sh", "#!/bin/sh\necho rewritten\n", executable: true)
        _ = git(["add", "-A"]) && git(["commit", "-q", "--amend", "-m", "Rewritten"]) && git(["push", "-q", "-f", "origin", "main"])
        _ = runAsync(60) { await sources.check(source) }
        check(sources.statuses[url]?.fastForward == false, "a force push is found by a check")
        _ = runAsync(60) { await sources.update(source) }
        check((try? String(contentsOf: script, encoding: .utf8))?.contains("hello there") == true, "…and Update doesn't apply it")
        if let restaged = runAsync(60, { try await sources.stageForReview(source) }) {
            check((try? String(contentsOf: script, encoding: .utf8))?.contains("hello there") == true, "…its review leaves the clone in place as it was")
            _ = try? sources.install(restaged)
            check((try? String(contentsOf: script, encoding: .utf8))?.contains("rewritten") == true
                  && ExtensionSources.isTrusted(source, sources.statuses[url]) && sources.statuses[url]?.fastForward == true,
                  "…and Enable after it puts the new history in place")
        } else {
            check(false, "re-cloned the rewritten history for its review")
        }

        // The command line, on another config: the review printed, enabled; a settings model reading that file follows.
        let cliConfig = dir.appendingPathComponent("cli-config.json")
        try? fresh.write(to: cliConfig)
        let watching = SettingsModel(configURL: cliConfig)
        let options = ["--config", cliConfig.path, "--sources-dir", dir.appendingPathComponent("CLI").path]
        let added = runSelf(["--add-source", url] + options)
        check(added.status == 0 && added.output.contains("WARNING:     This source isn't signed") && added.output.contains("@selftesthello"),
              "--add-source prints the review and enables it (\(added.status))")
        watching.reloadIfChanged()
        check(watching.config.extensionSources.map(\.url) == [url] && watching.config.extensionFolders.count == 1,
              "…and an open settings window reads the config it wrote")
        let listed = runSelf(["--list-extensions"] + options)
        check(listed.status == 0 && listed.output.contains("@selftesthello\tshow\t\(url)"), "--list-extensions lists its command with its source")
        let updated = runSelf(["--update-sources"] + options)
        check(updated.status == 0 && updated.output.contains("up to date"), "--update-sources (\(updated.output.trimmingCharacters(in: .newlines)))")
        let refused = runSelf(["--add-source", "http://example.com/x.git"] + options)
        check(refused.status != 0, "--add-source refuses plain http")
        let unknown = runSelf(["--add-source", url, "--bogus", "x"] + options)
        check(unknown.status == 2 && unknown.output.contains("unknown option --bogus"), "--add-source refuses an option it doesn't know")

        // Remove when the Trash refuses: the status goes anyway, and the failure is told.
        let trashing = sources.trashItem
        sources.trashItem = { _ in throw CocoaError(.fileWriteNoPermission) }
        let other = ExtensionSource(url: "file://" + dir.appendingPathComponent("other.git").path)
        sources.setStatus(ExtensionSourceStatus(url: other.url, trusted: true), for: other.url)
        try? fm.createDirectory(at: ExtensionSources.cloneFolder(for: other.url, root: sources.root), withIntermediateDirectories: true)
        let failed = sources.remove(other)
        check(failed != nil && sources.statuses[other.url] == nil, "Remove drops the status even when the Trash refuses, and says so")
        sources.trashItem = trashing
        try? fm.removeItem(at: ExtensionSources.cloneFolder(for: other.url, root: sources.root))

        // Remove: the clone goes (here deleted; to the Trash for real), the config forgets it, its preferences stay.
        model.config.extensionPreferences["selftestgreetings"] = ["greeting": "yo"]
        _ = sources.remove(source)
        ExtensionSources.remove(source, from: &model.config, root: sources.root)
        model.save()
        check(!fm.fileExists(atPath: installed.path) && sources.statuses[url] == nil && model.config.extensionSources.isEmpty
              && model.config.extensionFolders.isEmpty && model.config.extensionPreferences["selftestgreetings"] != nil,
              "Remove: the clone, the source and its folder go; its preferences stay")
        check((try? Data(contentsOf: Config.userURL)) == realBefore, "the real config file was not touched")
    }

    /// Settings → Commands → Extension Sources' "Trust its updates" (0.6.7.1 §2), on the sample sources with a config file
    /// and a clones folder of its own (never the user's): under each reviewed source, off by default and not written while
    /// off, its line under it; as VoiceOver finds it, a switch named with its source ("Trust its updates: my-extensions",
    /// in Chinese too); pressed, on and saved with its source
    /// (`"trustUpdates": true`), the other sources and keys as they were; pressed again, off, the key gone; the settings
    /// search finds it. Drawn in both languages, one source's on (settings-extension-sources-trust*.png).
    static func testExtensionSourceTrust(snapshotDirectory: URL) {
        section("extension sources: Trust its updates")
        let fm = FileManager.default
        let dir = snapshotDirectory.appendingPathComponent("extension-source-trust", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let realBefore = try? Data(contentsOf: Config.userURL)
        let sources = ExtensionSourceController.shared
        let before = (sources.root, sources.statuses, ExtensionSourcesSection.shownLoaded, UIText.choice)
        defer {
            sources.root = before.0
            sources.show(before.1)
            ExtensionSourcesSection.shownLoaded = before.2
            UIText.choice = before.3
        }
        UIText.choice = "en"
        sources.root = dir.appendingPathComponent("Sources", isDirectory: true)
        // Saved in its own clones folder too: the section reads sources.json again as a window becomes key.
        let statuses = ExtensionSourceSamples.statuses()
        try? ExtensionSourceStatus.save(statuses, to: sources.statusFile)
        sources.show(statuses)
        ExtensionSourcesSection.shownLoaded = ExtensionSourceSamples.loaded
        let configURL = dir.appendingPathComponent("config.json")
        var fresh = Config.default
        fresh.extensionFolders = []
        fresh.findRaycastScripts = false
        for source in ExtensionSourceSamples.sources { ExtensionSources.enable(source, in: &fresh, root: sources.root) }
        try? fresh.write(to: configURL)
        let model = SettingsModel(configURL: configURL)
        let loaded = try? Config.load(from: configURL)
        func saved() -> String { (try? String(contentsOf: configURL, encoding: .utf8)) ?? "" }
        check(model.config.extensionSources.count == 3 && model.config.extensionSources.allSatisfy { !$0.trustUpdates }
              && !saved().contains("trustUpdates"), "Trust its updates is off by default, and not written while off")

        // The section as VoiceOver finds it (`AXEnhancedUserInterface`, as Settings' own checks set it).
        func enhanced(_ on: Bool) {
            _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: on as NSNumber, with: "AXEnhancedUserInterface")
        }
        func ax(_ node: NSObject, _ key: String) -> Any? { node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil }
        func nodes(_ node: NSObject) -> [NSObject] { [node] + ((ax(node, "accessibilityChildren") as? [NSObject]) ?? []).flatMap(nodes) }
        enhanced(true)
        defer { enhanced(false) }
        let window = NSWindow(contentViewController: NSHostingController(rootView: Form { ExtensionSourcesSection(model: model) }.formStyle(.grouped)))
        window.setContentSize(NSSize(width: 680, height: 1000))
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        _ = pump(timeout: 1) { false }
        func trustSwitches(in shown: NSWindow) -> [NSObject] {
            nodes(shown).filter {
                ax($0, "accessibilityRole") as? String == NSAccessibility.Role.checkBox.rawValue
                    && (ax($0, "accessibilityLabel") as? String)?.hasPrefix(ExtensionSourceText.trustUpdates) == true
            }
        }
        func switches() -> [NSObject] { trustSwitches(in: window) }
        func labels(_ found: [NSObject]) -> Set<String> { Set(found.compactMap { ax($0, "accessibilityLabel") as? String }) }
        func value(_ node: NSObject?) -> Int? { node.flatMap { (ax($0, "accessibilityValue") as? NSNumber)?.intValue } }
        // The first source's switch pressed: the window's top switch clicked (this test's own window), as a click does.
        func appKitSwitches(_ view: NSView) -> [NSSwitch] { ((view as? NSSwitch).map { [$0] } ?? []) + view.subviews.flatMap(appKitSwitches) }
        func pressFirst() {
            let top = window.contentView.map(appKitSwitches)?.max { $0.convert($0.bounds, to: nil).maxY < $1.convert($1.bounds, to: nil).maxY }
            if let top { top.performClick(nil) } else { _ = switches().first?.perform(NSSelectorFromString("accessibilityPerformPress")) }
        }
        let texts = nodes(window).compactMap { (ax($0, "accessibilityValue") as? String) ?? (ax($0, "accessibilityLabel") as? String) }
        let found = switches()
        check(found.count == 3 && found.allSatisfy { value($0) == 0 } && texts.contains(ExtensionSourceText.trustUpdatesHelp),
              "each reviewed source has the switch, off, its line under it (\(found.count) switches)")
        check(labels(found) == ["Trust its updates: my-extensions", "Trust its updates: tools", "Trust its updates: drafts"]
              && labels(found) == Set(ExtensionSourceSamples.sources.map(ExtensionSourceText.trustUpdates(of:))),
              "…each named with its source, as VoiceOver says it (\(labels(found).sorted()))")
        UIText.choice = "zh"
        let chinese = NSWindow(contentViewController: NSHostingController(rootView: Form { ExtensionSourcesSection(model: model) }.formStyle(.grouped)))
        chinese.setContentSize(NSSize(width: 680, height: 1000))
        chinese.orderFront(nil)
        _ = pump(timeout: 1) { false }
        let zh = labels(trustSwitches(in: chinese))
        chinese.close()
        UIText.choice = "en"
        check(zh == ["信任它的更新：my-extensions", "信任它的更新：tools", "信任它的更新：drafts"], "…in Chinese too (\(zh.sorted()))")
        check(ExtensionSourceText.trustUpdatesHelp == "Its extensions' suggestions keep running after its updates; turn on only for a source you trust, such as your team's repository.",
              "…the line says what it does and when to turn it on")

        // Pressed: on, saved with its source; the others and the rest of the file as they were.
        pressFirst()
        _ = pump(timeout: 2) { model.config.extensionSources.first?.trustUpdates == true }
        let stored = try? Config.load(from: configURL)
        var expected = loaded
        expected?.extensionSources[0].trustUpdates = true
        check(stored?.extensionSources.map(\.trustUpdates) == [true, false, false] && stored == expected
              && saved().contains(#""trustUpdates" : true"#), "pressed: on, saved with its source (\(stored?.extensionSources.map(\.trustUpdates) ?? []))")
        _ = pump(timeout: 1) { value(switches().first) == 1 }
        check(value(switches().first) == 1, "…and the switch shows it on")
        pressFirst()
        _ = pump(timeout: 2) { model.config.extensionSources.first?.trustUpdates == false }
        check((try? Config.load(from: configURL)) == loaded && !saved().contains("trustUpdates"), "pressed again: off, the key gone")
        check(SettingsSpot.search("trust its updates", trigger: "@", config: fresh).contains(.extensionSources)
              && SettingsSpot.search("信任", trigger: "@", config: fresh).contains(.extensionSources),
              "the settings search finds it under Extension Sources")
        enhanced(false)

        // The images: the first source trusted.
        model.setTrustUpdates(true, of: ExtensionSourceSamples.sources[0], root: sources.root)
        for chinese in [false, true] {
            UIText.choice = chinese ? "zh" : "en"
            let image = snapshotDirectory.appendingPathComponent("settings-extension-sources-trust\(chinese ? "-zh" : "").png")
            renderOffscreen(Form { ExtensionSourcesSection(model: model) }.formStyle(.grouped), size: NSSize(width: 680, height: 660), to: image)
            check(fm.fileExists(atPath: image.path), "Extension Sources with the switch renders (\(image.lastPathComponent))")
        }
        check((try? Data(contentsOf: Config.userURL)) == realBefore, "the real config file was not touched")
    }

    /// What an extension source's suggestions can be pinned by (0.6.7.1 §2), with a config file and a clones folder of its
    /// own (never the user's): a command of a source whose updates aren't trusted, its repository past 2,000 files, says
    /// under it in Settings → Commands that its repository is too large to check for changes, its switch disabled, and
    /// turning it on approves nothing; under the limits, neither. Two addresses whose clones would share a folder (the
    /// same name and 4-byte hash): the second is refused by Add from Link… and by `--add-source`, with the reason, nothing
    /// cloned or written. Drawn (settings-extension-completion-too-large.png).
    static func testExtensionSourceLimits(snapshotDirectory: URL) {
        section("extension sources: what can be pinned, one folder a source")
        let fm = FileManager.default
        let dir = snapshotDirectory.appendingPathComponent("extension-source-limits", isDirectory: true)
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

        // A source's clone: its bundle in ext/ (a command with suggestions), and 2,001 more files elsewhere in it.
        let source = ExtensionSource(url: "https://git.example.com/team/desk.git", path: "ext")
        let clone = ExtensionSources.cloneFolder(for: source.url, root: sources.root)
        let bundle = ExtensionSources.bundleFolder(for: source, root: sources.root)
        func write(_ url: URL, _ text: String, executable: Bool = false) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: url)
            if executable { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        }
        write(bundle.appendingPathComponent("extension.json"), #"""
            {"schemaVersion": 1, "name": "selftestdesk", "title": "Help Desk",
             "commands": [{"script": "tickets.sh", "name": "selftesttickets", "title": "Tickets",
                           "completion": {"prefix": "TCK-", "list": true, "refresh": "1h"}}]}
            """#)
        write(bundle.appendingPathComponent("tickets.sh"), "#!/bin/sh\necho '{\"items\": []}'\n", executable: true)
        let data = clone.appendingPathComponent("data", isDirectory: true)
        try? fm.createDirectory(at: data, withIntermediateDirectories: true)
        for index in 0...ExtensionDigest.maxFiles { try? Data("\(index)\n".utf8).write(to: data.appendingPathComponent("file-\(index).txt")) }
        let configURL = dir.appendingPathComponent("config.json")
        var fresh = Config.default
        fresh.extensionFolders = []
        fresh.findRaycastScripts = false
        ExtensionSources.enable(source, in: &fresh, root: sources.root)
        try? fresh.write(to: configURL)
        let model = SettingsModel(configURL: configURL)
        guard let command = ExtensionStore.load([ExtensionStore.Folder(path: bundle.path, found: false, bundleOnly: true)]).commands.first,
              case let .success(declared)? = command.completion else {
            check(false, "the source's command with its suggestions loads")
            return
        }

        // Its row as VoiceOver finds it: the reason, and the switch.
        func ax(_ node: NSObject, _ key: String) -> Any? { node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil }
        func nodes(_ node: NSObject) -> [NSObject] { [node] + ((ax(node, "accessibilityChildren") as? [NSObject]) ?? []).flatMap(nodes) }
        func appKitSwitches(_ view: NSView) -> [NSSwitch] { ((view as? NSSwitch).map { [$0] } ?? []) + view.subviews.flatMap(appKitSwitches) }
        func shown() -> (texts: [String], switches: [NSSwitch]) {
            let window = NSWindow(contentViewController: NSHostingController(rootView: Form { ScriptCompletionView(model: model, command: command) }
                .formStyle(.grouped)))
            window.setContentSize(NSSize(width: 640, height: 260))
            window.orderFront(nil)
            defer { window.close() }
            _ = pump(timeout: 1) { false }
            let texts = nodes(window).compactMap { (ax($0, "accessibilityValue") as? String) ?? (ax($0, "accessibilityLabel") as? String) }
            return (texts, window.contentView.map(appKitSwitches) ?? [])
        }
        _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true as NSNumber, with: "AXEnhancedUserInterface")
        defer { _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: false as NSNumber, with: "AXEnhancedUserInterface") }
        // Its repository read off the main thread, as when the extensions are read again or the window becomes key.
        func read() {
            model.readExtensionDigests(only: [command])
            _ = pump(timeout: 10) { model.extensionWork == 0 }
        }
        read()
        let large = shown()
        check(large.texts.contains { $0.contains(CompletionSource.repositoryTooLarge) } && large.switches.count == 1
              && large.switches.allSatisfy { !$0.isEnabled && $0.state == .off },
              "a repository past 2,000 files: under the command, why it can't be turned on, its switch disabled (\(large.switches.map(\.isEnabled)))")
        check(CompletionSource.repositoryTooLarge == "Its repository is too large to check for changes (over 2,000 files or 20 MB).",
              "…saying it is too large to check for changes")
        model.setCompletionSource(declared, of: command, enabled: true)
        _ = pump(timeout: 10) { model.extensionWork == 0 }
        check(model.config.completionSources.isEmpty && ((try? Config.load(from: configURL))?.completionSources.isEmpty ?? false),
              "…and turning it on approves nothing")
        UIText.choice = "zh"
        let chinese = shown()
        check(chinese.texts.contains { $0.contains("它的仓库太大，没法检查改动（超过 2,000 个文件或 20 MB）。") }, "…in Chinese too")
        UIText.choice = "en"
        let image = snapshotDirectory.appendingPathComponent("settings-extension-completion-too-large.png")
        renderOffscreen(Form { ScriptCompletionView(model: model, command: command) }.formStyle(.grouped), size: NSSize(width: 640, height: 200), to: image)
        check(fm.fileExists(atPath: image.path), "the command's suggestions, too large, render (\(image.lastPathComponent))")
        try? fm.removeItem(at: data)
        read()
        let small = shown()
        check(!small.texts.contains { $0.contains(CompletionSource.repositoryTooLarge) } && small.switches.allSatisfy(\.isEnabled),
              "under the limits: no such line, the switch enabled")
        model.setCompletionSource(declared, of: command, enabled: true)
        _ = pump(timeout: 10) { model.extensionWork == 0 }
        check(model.config.completionSources.first?.scriptSHA256 == ExtensionDigest.of(command, root: sources.root),
              "…and turning it on pins its repository")

        // Two addresses, one folder ("tools-4317a211"): the second refused while the first is configured.
        let (first, second) = ("https://git.example.com/team47341/tools.git", "https://git.example.com/team67519/tools.git")
        let cliRoot = dir.appendingPathComponent("CLI", isDirectory: true)
        let cliConfig = dir.appendingPathComponent("cli-config.json")
        var shared = fresh
        shared.extensionSources = []
        shared.extensionFolders = []
        ExtensionSources.enable(ExtensionSource(url: first), in: &shared, root: cliRoot)
        try? shared.write(to: cliConfig)
        let written = try? Data(contentsOf: cliConfig)
        let said = "Its folder, tools-4317a211, is already another source's (\(first)): remove that source first."
        check(ExtensionSources.folderName(for: first) == ExtensionSources.folderName(for: second)
              && ExtensionSourceSheet.problem(ExtensionSource(url: second), cloneNow: false, config: shared) == said
              && ExtensionSourceSheet.problem(ExtensionSource(url: first), cloneNow: true, config: shared) == nil,
              "Add from Link… refuses an address whose folder another source has, and says why")
        UIText.choice = "zh"
        check(ExtensionSourceSheet.problem(ExtensionSource(url: second), cloneNow: false, config: shared)
              == "它的文件夹 tools-4317a211 已经是另一个来源（\(first)）的了：先移除那个来源。", "…in Chinese too")
        UIText.choice = "en"
        let refused = runSelf(["--add-source", second, "--config", cliConfig.path, "--sources-dir", cliRoot.path])
        check(refused.status == 1 && refused.output.contains("Its folder, tools-4317a211, is already another source's (\(first))")
              && (try? Data(contentsOf: cliConfig)) == written && !fm.fileExists(atPath: cliRoot.path),
              "--add-source refuses it too, nothing cloned or written (\(refused.status): \(refused.output.trimmingCharacters(in: .newlines)))")
        check((try? Data(contentsOf: Config.userURL)) == realBefore, "the real config file was not touched")
    }

    /// What Settings reads of an extension source for its suggestions, and where (0.6.7.1 §2), with a config file and a
    /// clones folder of its own (never the user's): never on the main thread nor as a row is drawn, but off it, as the
    /// extensions are read again, the window becomes key or a switch changes, the switch showing as it was meanwhile (a
    /// slow read here). Turning suggestions on, and "Trust its updates" off, read first and only then save; a press undone
    /// meanwhile isn't applied. A repository part of which can't be read says so under the command, its switch disabled,
    /// and turning it on approves nothing. A source whose bundle folder an update turned into a link out of its clone loads
    /// nothing, and its row says its folder leads out of the repository.
    static func testExtensionSourceReading(snapshotDirectory: URL) {
        section("extension sources: what Settings reads, and where")
        let fm = FileManager.default
        let dir = snapshotDirectory.appendingPathComponent("extension-source-reading", isDirectory: true)
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

        // A reviewed source (its updates not trusted): its bundle in ext/, a command with suggestions.
        let source = ExtensionSource(url: "https://git.example.com/team/reading.git", path: "ext")
        let clone = ExtensionSources.cloneFolder(for: source.url, root: sources.root)
        let bundle = ExtensionSources.bundleFolder(for: source, root: sources.root)
        func write(_ url: URL, _ text: String, executable: Bool = false) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: url)
            if executable { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        }
        write(bundle.appendingPathComponent("extension.json"), #"""
            {"schemaVersion": 1, "name": "selftestreading", "title": "Reading",
             "commands": [{"script": "tickets.sh", "name": "selftestreading", "title": "Tickets",
                           "completion": {"prefix": "TCK-", "list": true, "refresh": "1h"}}]}
            """#)
        write(bundle.appendingPathComponent("tickets.sh"), "#!/bin/sh\necho '{\"items\": []}'\n", executable: true)
        write(clone.appendingPathComponent("README.md"), "Tickets.\n")
        let statuses = [source.url: ExtensionSourceStatus(url: source.url, trusted: true, branch: "main",
                                                          commit: "4f2a9c1e0b7d3a6f8e1c2b5d9a0f3e7c6b1d2a4f")]
        try? ExtensionSourceStatus.save(statuses, to: sources.statusFile)
        sources.show(statuses)
        let configURL = dir.appendingPathComponent("config.json")
        var fresh = Config.default
        fresh.extensionFolders = []
        fresh.findRaycastScripts = false
        ExtensionSources.enable(source, in: &fresh, root: sources.root)
        try? fresh.write(to: configURL)
        func saved() -> Config? { try? Config.load(from: configURL) }
        let model = SettingsModel(configURL: configURL)

        // A slow read that notes where it runs.
        let reads = OSAllocatedUnfairLock(initialState: (count: 0, onMain: 0, delay: 0.3))
        model.readExtension = { command, root in
            let delay = reads.withLock { state -> Double in
                state.count += 1
                if Thread.isMainThread { state.onMain += 1 }
                return state.delay
            }
            Thread.sleep(forTimeInterval: delay)
            return ExtensionDigest.of(command, root: root)
        }
        func slow(_ delay: Double) { reads.withLock { $0.delay = delay } }
        func settled() -> Bool { pump(timeout: 15) { model.extensionWork == 0 } }
        let started = Date()
        model.refreshExtensions()
        let took = Date().timeIntervalSince(started)
        guard let command = model.extensionIndex.commands.first(where: { $0.name == "selftestreading" }),
              case let .success(declared)? = command.completion else {
            check(false, "the source's command with its suggestions loads (\(model.extensionIndex.commands.map(\.name)))")
            return
        }
        check(model.extensionWork == 1 && took < 0.25, "the extensions read again: its repository read meanwhile, not waited for (\(took) s)")
        check(settled() && reads.withLock { $0.count } == 1 && reads.withLock { $0.onMain } == 0,
              "…once, off the main thread (\(reads.withLock { $0 }))")

        // Its row as VoiceOver finds it.
        func ax(_ node: NSObject, _ key: String) -> Any? { node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil }
        func nodes(_ node: NSObject) -> [NSObject] { [node] + ((ax(node, "accessibilityChildren") as? [NSObject]) ?? []).flatMap(nodes) }
        func appKitSwitches(_ view: NSView) -> [NSSwitch] { ((view as? NSSwitch).map { [$0] } ?? []) + view.subviews.flatMap(appKitSwitches) }
        func shown<V: View>(_ view: V, height: CGFloat = 260, pumping: TimeInterval = 0.5) -> (texts: [String], switches: [NSSwitch]) {
            let window = NSWindow(contentViewController: NSHostingController(rootView: Form { view }.formStyle(.grouped)))
            window.setContentSize(NSSize(width: 640, height: height))
            window.orderFront(nil)
            defer { window.close() }
            _ = pump(timeout: pumping) { false }
            let texts = nodes(window).compactMap { (ax($0, "accessibilityValue") as? String) ?? (ax($0, "accessibilityLabel") as? String) }
            return (texts, window.contentView.map(appKitSwitches) ?? [])
        }
        func row(pumping: TimeInterval = 0.5) -> (texts: [String], switches: [NSSwitch]) {
            shown(ScriptCompletionView(model: model, command: command), pumping: pumping)
        }
        func enabledOff(_ shown: (texts: [String], switches: [NSSwitch])) -> Bool {
            shown.switches.count == 1 && shown.switches[0].isEnabled && shown.switches[0].state == .off
        }
        _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true as NSNumber, with: "AXEnhancedUserInterface")
        defer { _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: false as NSNumber, with: "AXEnhancedUserInterface") }
        let first = row()
        check(reads.withLock { $0.count } == 1 && enabledOff(first) && !first.texts.contains(CompletionSource.repositoryTooLarge),
              "drawing its row reads nothing: off, its switch enabled")

        // Its repository grows past the limits; read again (as when the window becomes key): as it was meanwhile, then
        // too large.
        let data = clone.appendingPathComponent("data", isDirectory: true)
        try? fm.createDirectory(at: data, withIntermediateDirectories: true)
        for index in 0...ExtensionDigest.maxFiles { try? Data("\(index)\n".utf8).write(to: data.appendingPathComponent("file-\(index).txt")) }
        slow(2)
        model.readExtensionDigests()
        let meanwhile = row(pumping: 0.3)
        check(model.extensionWork == 1 && enabledOff(meanwhile) && !meanwhile.texts.contains(CompletionSource.repositoryTooLarge),
              "while it is read again, the switch shows as it was")
        _ = settled()
        let large = row()
        check(large.texts.contains(CompletionSource.repositoryTooLarge) && large.switches.allSatisfy { !$0.isEnabled },
              "…then what was read: too large, its switch disabled")
        try? fm.removeItem(at: data)
        slow(0.3)
        model.readExtensionDigests()
        check(settled() && enabledOff(row()), "under the limits again, once read again")

        // Turned on: nothing saved while it is read, the switch as it was; then on with what was read, and saved.
        slow(1)
        model.setCompletionSource(declared, of: command, enabled: true)
        let pressed = row(pumping: 0.2)
        check(model.config.completionSources.isEmpty && saved()?.completionSources.isEmpty == true && enabledOff(pressed),
              "pressed on: nothing saved while its repository is read, the switch as it was")
        let pinned = ExtensionDigest.of(command, root: sources.root)
        check(settled() && model.config.completionSources.first?.scriptSHA256 == pinned && saved()?.completionSources.first?.scriptSHA256 == pinned
              && pinned != nil && reads.withLock { $0.onMain } == 0, "…then on with what was read, and saved (read off the main thread)")
        let on = row()
        check(on.switches.first?.state == .on, "…and its switch shows it on")
        // Off, on, off again before the read is done: off.
        model.setCompletionSource(declared, of: command, enabled: false)
        model.setCompletionSource(declared, of: command, enabled: true)
        model.setCompletionSource(declared, of: command, enabled: false)
        check(settled() && model.config.completionSources.isEmpty && saved()?.completionSources.isEmpty == true,
              "pressed on and off again while it is read: off, the read not applied")

        // Trust its updates: on (its suggestions follow, nothing read), turned on; off: what it pins read first, then saved.
        slow(0.3)
        model.setTrustUpdates(true, of: source, root: sources.root)
        model.setCompletionSource(declared, of: command, enabled: true)
        let count = reads.withLock { $0.count }
        check(settled() && saved()?.extensionSources.first?.trustUpdates == true && saved()?.completionSources.first?.scriptSHA256 == ""
              && reads.withLock { $0.count } == count, "trusted: turned on at once, nothing read")
        slow(1)
        model.setTrustUpdates(false, of: model.config.extensionSources[0], root: sources.root)
        check(model.config.extensionSources.first?.trustUpdates == true && saved()?.extensionSources.first?.trustUpdates == true,
              "Trust its updates pressed off: nothing saved while what it pins is read, the switch as it was")
        check(settled() && saved()?.extensionSources.first?.trustUpdates == false && saved()?.completionSources.first?.scriptSHA256 == pinned
              && reads.withLock { $0.count } > count && reads.withLock { $0.onMain } == 0,
              "…then off and saved, its suggestions pinned to what was read (off the main thread)")

        // Part of its repository can't be read: said under the command, its switch disabled, turning it on approves nothing.
        slow(0)
        model.setCompletionSource(declared, of: command, enabled: false)
        let locked = clone.appendingPathComponent("private", isDirectory: true)
        write(locked.appendingPathComponent("notes.txt"), "x\n")
        try? fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        model.readExtensionDigests()
        _ = settled()
        let unreadable = row()
        check(unreadable.texts.contains(CompletionSource.repositoryUnreadable) && unreadable.switches.allSatisfy { !$0.isEnabled && $0.state == .off },
              "a folder of its repository that can't be listed: said under the command, its switch disabled")
        check(CompletionSource.repositoryUnreadable == "Some of its files can't be read, so it can't be checked for changes.",
              "…saying some of its files can't be read")
        model.setCompletionSource(declared, of: command, enabled: true)
        check(settled() && model.config.completionSources.isEmpty && saved()?.completionSources.isEmpty == true, "…and turning it on approves nothing")
        UIText.choice = "zh"
        check(row().texts.contains("它有些文件读不了，没法检查改动。"), "…in Chinese too")
        UIText.choice = "en"
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)

        // An update turns its bundle folder into a link out of its clone: nothing of it loads, and its row says why.
        let elsewhere = dir.appendingPathComponent("elsewhere/ext", isDirectory: true)
        try? fm.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.moveItem(at: bundle, to: elsewhere)
        try? fm.createSymbolicLink(at: bundle, withDestinationURL: elsewhere)
        model.refreshExtensions()
        check(!model.extensionIndex.commands.contains { $0.name == "selftestreading" } && ExtensionSources.leavesClone(source, root: sources.root),
              "its bundle folder a link out of its clone: nothing of it loads (\(model.extensionIndex.commands.map(\.name)))")
        let sourceRow = shown(ExtensionSourcesSection(model: model), height: 400)
        check(sourceRow.texts.contains("Nothing loaded: ext leads out of the repository.") && ExtensionSources.isEnabled(source, in: model.config, root: sources.root),
              "…its row says its folder leads out of the repository, the source still enabled (\(sourceRow.texts.filter { $0.contains("loaded") }))")
        UIText.choice = "zh"
        let chinese = shown(ExtensionSourcesSection(model: model), height: 400)
        check(chinese.texts.contains("没有加载：ext 指向仓库外面。"), "…in Chinese too (\(chinese.texts.filter { $0.contains("加载") }))")
        UIText.choice = "en"
        let climbing = ExtensionSource(url: source.url, path: "ext/../../elsewhere")
        check(ExtensionSources.leavesClone(climbing, root: sources.root), "…as a path that climbs out is")
        try? fm.removeItem(at: bundle)
        try? fm.moveItem(at: elsewhere, to: bundle)
        model.refreshExtensions()
        check(model.extensionIndex.commands.contains { $0.name == "selftestreading" }, "put back (a Re-clone): it loads again")
        _ = settled()
        check((try? Data(contentsOf: Config.userURL)) == realBefore, "the real config file was not touched")
    }

    /// This app's executable with `arguments`: its exit status and what it printed (both streams).
    static func runSelf(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// `view` drawn offscreen into a PNG of `size`.
    static func renderOffscreen<V: View>(_ view: V, size: NSSize, to url: URL) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        _ = pump(timeout: 0.6) { false }
        defer { window.close() }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Sample sources for the settings' images (`--settings-image`): made-up addresses and commits, never the user's.
enum ExtensionSourceSamples {
    static var sources: [ExtensionSource] {
        [ExtensionSource(url: "git@github.com:you/my-extensions.git", path: "extensions/team"),
         ExtensionSource(url: "ssh://git.example.com/team/tools.git", pin: "v1.2.0"),
         ExtensionSource(url: "https://git.example.com/you/drafts.git", autoCheck: false,
                         authHint: "Sign in to your network first, then click Check Now.")]
    }

    /// What each sample source loads, as its row says.
    static var loaded: [String: [String]] {
        let s = sources
        return [s[0].url: ["@standup", "@tickets"], s[1].url: ["@deploy", "@logs"], s[2].url: ["@draft"]]
    }

    static func statuses(now: Date = Date()) -> [String: ExtensionSourceStatus] {
        let s = sources
        let day: TimeInterval = 86400
        return [
            s[0].url: ExtensionSourceStatus(url: s[0].url, trusted: true, branch: "main", commit: "4f2a9c1e0b7d3a6f8e1c2b5d9a0f3e7c6b1d2a4f",
                                            commitDate: now.addingTimeInterval(-6 * day), checked: now.addingTimeInterval(-3 * 3600),
                                            updates: [ExtensionSourceCommit(sha: "9b1e7d2c4a6f8e0b1c3d5a7f9e2b4c6d8a0f1e3b", author: "Ann Lee",
                                                                            date: now.addingTimeInterval(-5 * 3600), subject: "Add @standup"),
                                                      ExtensionSourceCommit(sha: "2c4e6a8b0d1f3e5a7c9b1d3f5e7a9c0b2d4f6e8a", author: "Bo Chen",
                                                                            date: now.addingTimeInterval(-26 * 3600), subject: "Faster @tickets list")],
                                            remote: "9b1e7d2c4a6f8e0b1c3d5a7f9e2b4c6d8a0f1e3b"),
            s[1].url: ExtensionSourceStatus(url: s[1].url, trusted: true, branch: "main", commit: "7d3a6f8e1c2b5d9a0f3e7c6b1d2a4f4f2a9c1e0b",
                                            commitDate: now.addingTimeInterval(-40 * day), checked: now.addingTimeInterval(-2 * day)),
            s[2].url: ExtensionSourceStatus(url: s[2].url, trusted: true, branch: "main", commit: "e1c2b5d9a0f3e7c6b1d2a4f4f2a9c1e0b7d3a6f8",
                                            commitDate: now.addingTimeInterval(-9 * day), checked: now.addingTimeInterval(-4 * day),
                                            error: "git@git.example.com: Permission denied (publickey).\nfatal: Could not read from remote repository."),
        ]
    }
}

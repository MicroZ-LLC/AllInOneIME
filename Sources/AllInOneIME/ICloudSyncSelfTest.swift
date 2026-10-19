import AllInOneIMECore
import AllInOneIMERime
import AppKit

extension SelfTest {
    /// Sync through iCloud end to end, with a temporary folder as iCloud Drive (never the user's, nor their config, Rime
    /// folder or questions): the self-test's config syncs as one Mac through the app's controller, a second Mac's config
    /// beside it; a change on each crosses over, the config is written key by key, the learned words go through the
    /// self-test's own Rime folder (librime's sync), a placeholder of `settings.json` waits, a corrupt one is set aside,
    /// Settings → Assistant's checks and Settings → General show it (settings-general-icloud*.png). Everything is put back afterwards.
    static func testICloudSync(snapshotDirectory: URL) {
        section("sync through iCloud (a temporary folder as iCloud Drive)")
        let fm = FileManager.default
        let dir = snapshotDirectory.appendingPathComponent("icloud-sync", isDirectory: true)
        try? fm.removeItem(at: dir)
        let drive = dir.appendingPathComponent("CloudDocs", isDirectory: true)
        try? fm.createDirectory(at: drive, withIntermediateDirectories: true)
        let folder = ICloudSyncFolder(url: drive.appendingPathComponent(ICloudSync.folderName))
        let configURL = Config.defaultURL
        let configBefore = try? Data(contentsOf: configURL)
        let realConfig = try? Data(contentsOf: Config.userURL)
        let sync = ICloudSyncController.shared
        let saved = (sync.engine, sync.applyChanges)
        var applied: [ICloudSyncEngine.Report] = []
        defer {
            sync.stopRime(folder.url.appendingPathComponent(ICloudSync.rimeFolder))
            (sync.engine, sync.applyChanges) = saved
            if let configBefore { try? configBefore.write(to: configURL) }
            try? fm.removeItem(at: dir)
        }
        let language = UIText.choice
        defer { UIText.choice = language }
        UIText.choice = .english
        check(!folder.url.path.contains("Mobile Documents") && folder.url.path.hasPrefix(snapshotDirectory.path),
              "the shared folder is the self-test's own: \(folder.url.path)")

        // This Mac: the self-test's config, sync turned on as Settings does it. The other Mac: a config of its own.
        func edit(_ url: URL, _ change: (inout Config) -> Void) {
            guard var config = try? Config.load(from: url) else { return }
            let before = config
            change(&config)
            try? AIConfig.writing(config, from: before, keys: AIConfig.changedKeys(before, config), at: url)
        }
        edit(configURL) { $0.iCloudSync.enabled = true }
        // Runs go on the sync queue: each Sync Now is waited for.
        func syncNow() {
            sync.syncNow()
            check(pump(timeout: 30) { !sync.running }, "a run finished")
        }
        sync.engine = ICloudSyncEngine(folder: folder, configURL: configURL, stateURL: dir.appendingPathComponent("this-mac/state.json"),
                                       questionsURL: dir.appendingPathComponent("this-mac/questions.json"),
                                       environment: ICloudSync.Environment(hasKey: { _ in false }, awsProfiles: nil),
                                       machineID: MachineIdentity.syncID)
        sync.applyChanges = { applied.append($0) }
        let otherDir = dir.appendingPathComponent("other-mac")
        try? fm.createDirectory(at: otherDir, withIntermediateDirectories: true)
        var otherConfig = Config.default
        otherConfig.iCloudSync.enabled = true
        otherConfig.jargonFile = otherDir.appendingPathComponent("jargon.txt").path
        try? otherConfig.write(to: otherDir.appendingPathComponent("config.json"))
        let other = ICloudSyncEngine(folder: folder, configURL: otherDir.appendingPathComponent("config.json"),
                                     stateURL: otherDir.appendingPathComponent("state.json"),
                                     questionsURL: otherDir.appendingPathComponent("questions.json"))

        syncNow()
        check(sync.status.isSynced && folder.exists, "turned on: synced into the shared folder (\(sync.status))")
        let first = other.run()
        check(first.outcome == .synced && first.uploaded.isEmpty, "the other Mac joins: it takes what is there, puts nothing over it")
        // A change on the other Mac comes here, written into the config key by key.
        edit(otherDir.appendingPathComponent("config.json")) { $0.candidateLayout = .vertical }
        _ = other.run()
        let textBefore = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        syncNow()
        let config = LiveConfig.current
        check(config.candidateLayout == .vertical && applied.last?.configKeys == ["candidateLayout"],
              "the other Mac's change came in (candidates in a column), and Settings and the input method were told")
        let textAfter = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        check(textAfter == textBefore.replacingOccurrences(of: "\"candidateLayout\" : \"horizontal\"", with: "\"candidateLayout\" : \"vertical\""),
              "only that key's text changed in the config file")
        // Settings with the file as it was before that change (the window not yet told): a switch saved there writes that
        // key alone, never the stale rest over what sync wrote.
        let staleText = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        try? Data(textBefore.utf8).write(to: configURL)
        let staleModel = SettingsModel(configURL: configURL)
        try? Data(staleText.utf8).write(to: configURL)
        staleModel.config.voiceInput.toggle()
        staleModel.save()
        let afterSave = LiveConfig.current
        check(afterSave.candidateLayout == .vertical && afterSave.voiceInput == staleModel.config.voiceInput,
              "a Settings save writes only the keys it changed: what sync wrote meanwhile stays")
        staleModel.config.voiceInput.toggle()
        staleModel.save()
        // A change here goes there.
        edit(configURL) { $0.typeOutVaries = true }
        syncNow()
        let back = other.run()
        check(back.applied == ["typeOutVaries"] && (try? Config.load(from: otherDir.appendingPathComponent("config.json")))?.typeOutVaries == true,
              "a change on this Mac reached the other")
        let shared = (try? String(contentsOf: folder.url.appendingPathComponent(ICloudSync.settingsFile), encoding: .utf8)) ?? ""
        check(!shared.contains("extensionFolders") && !shared.contains("iCloudSync") && !shared.contains("jargonFile") && shared.contains("\"by\""),
              "settings.json holds stamped keys, never extension folders, file paths or the sync setting")

        // The learned words: Rime's own sync, into the shared folder's rime/ (the self-test's Rime folder, not the user's).
        if let user = RimeService.shared.userDataDir, user.path.hasPrefix(snapshotDirectory.path) {
            check(RimeService.shared.waitUntilReady(timeout: 60), "Rime ready after the sync")
            let yaml = (try? String(contentsOf: user.appendingPathComponent("installation.yaml"), encoding: .utf8)) ?? ""
            let ids = (try? fm.contentsOfDirectory(atPath: folder.url.appendingPathComponent(ICloudSync.rimeFolder).path)) ?? []
            check(RimeSync.syncDir(in: yaml) == folder.url.appendingPathComponent(ICloudSync.rimeFolder).path && ids.count == 1
                  && yaml.contains("installation_id: \"\(ids.first ?? "-")\""),
                  "learned words: Rime's sync_dir is the shared rime/ folder, with this installation's own folder (\(ids.first ?? "none"))")
        } else {
            check(false, "Rime runs in the self-test's own folder")
        }

        // A settings.json not downloaded yet: waiting, nothing written over it.
        let file = folder.url.appendingPathComponent(ICloudSync.settingsFile)
        try? fm.removeItem(at: file)
        try? Data().write(to: folder.url.appendingPathComponent(ICloudSyncFolder.placeholderName(of: ICloudSync.settingsFile)))
        edit(configURL) { $0.typeOutMistakes = true }
        syncNow()
        check(sync.status == .waiting && !fm.fileExists(atPath: file.path), "a placeholder of settings.json: \"Waiting for iCloud…\", nothing written over it")
        try? fm.removeItem(at: folder.url.appendingPathComponent(ICloudSyncFolder.placeholderName(of: ICloudSync.settingsFile)))
        // A corrupt one: set aside, a new one written.
        try? Data("{ not json".utf8).write(to: file)
        syncNow()
        let files = (try? fm.contentsOfDirectory(atPath: folder.url.path)) ?? []
        let rewritten = (try? Data(contentsOf: file)).flatMap { try? ICloudSync.RemoteSettings.parse($0) }
        check(sync.status.isSynced && files.contains { $0.hasPrefix("settings (unreadable ") } && rewritten?.entries["typeOutMistakes"]?.value == .bool(true),
              "a corrupt settings.json is set aside (\(files.filter { $0.hasPrefix("settings (") }.joined())) and a new one written")

        // Settings → Assistant's checks and Settings → General.
        let facts = sync.facts
        check(facts.enabled && facts.available && facts.lastSync != nil && facts.lastError == nil, "the checks: on, iCloud Drive there, synced just now")
        let rows = Doctor.findings({ var all = Doctor.Facts(); all.iCloudSync = facts; return all }(), chinese: false).filter { $0.area == .iCloudSync }
        check(rows.first?.title.hasPrefix("Synced through iCloud") == true, "the checks say: \(rows.first?.title ?? "nothing")")
        for chinese in [false, true] {
            UIText.choice = chinese ? "zh" : "en"
            let model = SettingsModel(configURL: configURL, persists: false)
            let image = snapshotDirectory.appendingPathComponent("settings-general-icloud\(chinese ? "-zh" : "").png")
            try? fm.removeItem(at: image)
            SettingsImage.render(model, page: .general, to: image) { _ = pump(timeout: $0) { false } }
            check(fm.fileExists(atPath: image.path), "Settings → General with sync on: \(image.lastPathComponent)")
        }

        // Off: nothing more is synced, and the folder stays.
        edit(configURL) { $0.iCloudSync.enabled = false }
        syncNow()
        check(sync.status == .off && folder.exists, "turned off: not synced, the folder in iCloud Drive left as it is")
        check((try? Data(contentsOf: Config.userURL)) == realConfig, "the user's config was not touched")
    }
}

extension ICloudSyncController.Status {
    var isSynced: Bool { if case .synced = self { return true } else { return false } }
}

extension SelfTest {
    /// Settings' lists saved after sync through iCloud changed them in the file (ICloudSyncAppLevelCases.md, from the
    /// re-check of 2026-10-17): the hidden words field saved by a window that missed the reload (S33), and the command
    /// editor and the Delete dialog after another Mac deleted an earlier command (S34, D34b, D34c, D34e, S34-delete). Each
    /// on a temporary config.json of its own, never ~/.config/allinoneime; what counts is the file after the save.
    static func testSettingsListsAfterSync(snapshotDirectory: URL) {
        section("Settings' lists saved after sync through iCloud changed them (hidden words, custom commands)")
        let fm = FileManager.default
        let dir = snapshotDirectory.appendingPathComponent("settings-lists-sync", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        let realConfig = try? Data(contentsOf: Config.userURL)

        /// config.json as `change` sets it, a minute old, and Settings' model on it, as the window holds it.
        func start(_ change: (inout Config) -> Void) -> SettingsModel {
            var config = Config.default
            change(&config)
            try? fm.removeItem(at: url)
            try? config.write(to: url)
            try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: url.path)
            return SettingsModel(configURL: url)
        }
        /// A sync run writes the file: only the keys it brought (`ICloudSync.writeConfig`), with a new modification time.
        func syncWrites(_ change: (inout Config) -> Void) {
            guard let old = try? Config.load(from: url) else { return check(false, "config.json readable before the sync writes it") }
            var new = old
            change(&new)
            _ = try? ICloudSync.writeConfig(new, readAs: old, keys: AIConfig.changedKeys(old, new), at: url)
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        }
        func file() -> Config { (try? Config.load(from: url)) ?? .default }

        // S33: the words field saved by a window that missed the reload bringing another Mac's word.
        func words(_ field: String, reloads: Bool, by way: String) -> (file: [String], model: [String], shown: [String], rest: Bool) {
            let model = start { c in
                c.redaction.enabled = true
                c.redaction.customWords = ["Acme"]
                c.iCloudSync.hiddenWords = true
            }
            let shown = model.config.redaction.customWords  // the field reads "Acme"
            syncWrites { $0.redaction.customWords = ["Acme", "Project Phoenix"] }
            let synced = file()
            if reloads { model.reloadIfChanged() } else {
                check(model.config.redaction.customWords == ["Acme"], "S33 (\(way)): the window missed the reload: it still shows [Acme]")
            }
            // The field edited, then Return (onSubmit) or leaving the page (onDisappear): both save through this.
            let showing = model.saveWords(field: field, shown: shown)
            var rest = file()
            rest.redaction.customWords = synced.redaction.customWords
            return (file().redaction.customWords, model.config.redaction.customWords, showing, rest == synced)
        }
        for way in ["Return", "leaving the page"] {
            let saved = words("Acme, Bolt", reloads: false, by: way)
            check(saved.file.sorted() == ["Acme", "Bolt", "Project Phoenix"] && saved.model.sorted() == saved.file.sorted()
                  && saved.shown.sorted() == saved.file.sorted(),
                  "S33 (\(way)): the hidden words saved as Acme, Bolt keep another Mac's Project Phoenix: file \(saved.file), "
                  + "window \(saved.model), field \(saved.shown)")
            check(saved.rest, "S33 (\(way)): the rest of config.json is as sync left it (the other redaction switches, the other keys)")
        }
        let removed = words("Bolt", reloads: false, by: "a word taken out")
        check(removed.file.sorted() == ["Bolt", "Project Phoenix"] && removed.model.sorted() == removed.file.sorted() && removed.rest,
              "S33: Acme taken out of the field: the file holds Project Phoenix and Bolt (\(removed.file))")
        let reloaded = words("Acme, Bolt", reloads: true, by: "the window reloaded")
        check(reloaded.file.sorted() == ["Acme", "Bolt", "Project Phoenix"] && reloaded.model.sorted() == reloaded.file.sorted() && reloaded.rest,
              "S33 (D33): with the reload, the same: \(reloaded.file)")

        // S34 and its variants: the editor or the Delete dialog opened on the list as it showed, another Mac's delete of
        // alpha synced in (the window reloads), then saved or confirmed.
        func command(_ name: String, _ prompt: String) -> CustomCommand { CustomCommand(name: name, type: .prompt, prompt: prompt) }
        func commands() -> SettingsModel {
            start { $0.customCommands = [command("alpha", "do alpha"), command("beta", "do beta"), command("gamma", "do gamma")] }
        }
        func alphaDeletedElsewhere(_ model: SettingsModel) {
            syncWrites { $0.customCommands = [command("beta", "do beta"), command("gamma", "do gamma")] }
            model.reloadIfChanged()
        }
        func describe(_ list: [CustomCommand]) -> String { list.map { "\($0.name) (\($0.prompt ?? ""))" }.joined(separator: ", ") }
        /// The page's Edit on the command at `index`, the sync, the edit, and the sheet's Save: what the editor checked the
        /// name against, whether it accepted the save, and the file after.
        func edit(_ index: Int, _ change: (inout CustomCommand) -> Void) -> (others: [String], accepted: Bool, file: [CustomCommand]) {
            let model = commands()
            let open = CommandEdit(index: index, command: model.config.customCommands[index])
            alphaDeletedElsewhere(model)
            var draft = open.command
            change(&draft)
            let others = model.otherCommands(than: open.original)
            let accepted = draft.problem(among: others, plugins: model.plugins.map(\.name)) == nil
            if accepted { model.saveCommand(draft, editing: open.original) }
            return (others.map(\.name), accepted, file().customCommands)
        }
        let s34 = edit(1) { $0.prompt = "do beta better" }
        check(s34.accepted && s34.file == [command("beta", "do beta better"), command("gamma", "do gamma")],
              "S34: beta's prompt edited while alpha was deleted elsewhere: accepted (no \"Another command has this name\"), file [\(describe(s34.file))]")
        let d34b = edit(0) { $0.prompt = "do alpha better" }
        check(d34b.accepted && d34b.file == [command("beta", "do beta"), command("gamma", "do gamma"), command("alpha", "do alpha better")],
              "D34b: alpha edited while it was deleted elsewhere: added back, beta and gamma kept: [\(describe(d34b.file))]")
        let d34c = edit(1) { $0.name = "delta" }
        check(d34c.accepted && d34c.file == [command("delta", "do beta"), command("gamma", "do gamma")],
              "D34c: beta renamed delta while alpha was deleted elsewhere: gamma kept, no beta left: [\(describe(d34c.file))]")
        let d34e = edit(2) { $0.name = "omega" }
        check(d34e.accepted && d34e.others == ["beta"] && d34e.file == [command("beta", "do beta"), command("omega", "do gamma")],
              "D34e: the last command (gamma, index 2) renamed omega after its index was gone: no crash, checked against "
              + "\(d34e.others), renamed in place: [\(describe(d34e.file))]")
        // A command of the name being added came in from another Mac while the editor was open: not saved (the editor
        // stays open with "Another command has this name"), the other Mac's kept.
        let clash = commands()
        let added = command("delta", "mine")
        let checked = added.problem(among: clash.otherCommands(than: nil), plugins: clash.plugins.map(\.name)) == nil
        syncWrites { $0.customCommands.append(command("delta", "theirs")) }
        let saved = clash.saveCommand(added, editing: nil)
        let deltas = file().customCommands.filter { $0.name == "delta" }
        check(checked && !saved && deltas == [command("delta", "theirs")],
              "S34-clash: @delta added while another Mac's @delta came in: not saved (the editor stays open), file's delta \(describe(deltas))")
        /// The page's Delete on the command at `index`, the sync, and the dialog's Delete.
        func delete(_ index: Int) -> (asked: String, file: [String]) {
            let model = commands()
            let asked = model.config.customCommands[index].name  // the dialog shows @<name>
            alphaDeletedElsewhere(model)
            model.deleteCommand(named: asked)
            return (asked, file().customCommands.map(\.name))
        }
        let gone = delete(2)
        check(gone.asked == "gamma" && gone.file == ["beta"], "S34-delete: @gamma deleted after alpha was deleted elsewhere: no crash, file \(gone.file)")
        let beta = delete(1)
        check(beta.asked == "beta" && beta.file == ["gamma"], "S34-delete: @beta deleted the same way: file \(beta.file), never [beta]")
        check((try? Data(contentsOf: Config.userURL)) == realConfig, "the user's config was not touched")
    }
}

import AllInOneIMECore
import AllInOneIMERime
import AppKit

extension SelfTest {
    /// Sync through iCloud end to end, with a temporary folder as iCloud Drive (never the user's, nor their config, Rime
    /// folder or questions): the self-test's config syncs as one Mac through the app's controller, a second Mac's config
    /// beside it; a change on each crosses over, the config is written key by key, the learned words go through the
    /// self-test's own Rime folder (librime's sync), a placeholder of `settings.json` waits, a corrupt one is set aside,
    /// `@doctor` and Settings → General show it (settings-general-icloud*.png). Everything is put back afterwards.
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

        // @doctor and Settings → General.
        let facts = sync.facts
        check(facts.enabled && facts.available && facts.lastSync != nil && facts.lastError == nil, "@doctor: on, iCloud Drive there, synced just now")
        let rows = Doctor.findings({ var all = Doctor.Facts(); all.iCloudSync = facts; return all }(), chinese: false).filter { $0.area == .iCloudSync }
        check(rows.first?.title.hasPrefix("Synced through iCloud") == true, "@doctor says: \(rows.first?.title ?? "nothing")")
        for chinese in [false, true] {
            UIText.choice = chinese ? .chinese : .english
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

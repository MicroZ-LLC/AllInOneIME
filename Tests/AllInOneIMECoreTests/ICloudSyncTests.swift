import Foundation
import Testing
@testable import AllInOneIMECore

/// Macs sharing one "iCloud Drive" in a temporary folder, each with its own config, record, jargon list and recent
/// questions there too: nothing of the user's (their iCloud Drive, config, jargon list or questions) is read or written.
final class SyncRig {
    let root: URL
    let drive: URL
    var folder: ICloudSyncFolder { ICloudSyncFolder(url: drive.appendingPathComponent(ICloudSync.folderName)) }
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-sync-tests-\(UUID().uuidString)")
        drive = root.appendingPathComponent("CloudDocs")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// A Mac with sync on and `change` made to its settings (written before it ever syncs).
    func mac(_ name: String, environment: ICloudSync.Environment = .init(), _ change: (inout Config) -> Void = { _ in }) throws -> SyncMac {
        let dir = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var config = Config.default
        config.iCloudSync.enabled = true
        config.jargonFile = dir.appendingPathComponent("jargon.txt").path
        change(&config)
        let mac = SyncMac(dir: dir, engine: ICloudSyncEngine(folder: folder, configURL: dir.appendingPathComponent("config.json"),
                                                               stateURL: dir.appendingPathComponent("state.json"),
                                                               questionsURL: dir.appendingPathComponent("questions.json"),
                                                               environment: environment))
        try config.write(to: mac.configURL)
        try mac.touch(mac.configURL, at: Self.t0.addingTimeInterval(-3600))
        return mac
    }

    func settingsJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: folder.url.appendingPathComponent(ICloudSync.settingsFile))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

struct SyncMac {
    let dir: URL
    var engine: ICloudSyncEngine
    var configURL: URL { engine.configURL }
    var jargonURL: URL { dir.appendingPathComponent("jargon.txt") }

    func config() throws -> Config { try Config.load(from: configURL) }

    /// Changes the settings at `at`, as Settings would (the file's time is the change's).
    func edit(at: Date, _ change: (inout Config) -> Void) throws {
        var config = try config()
        let before = config
        change(&config)
        try AIConfig.writing(config, from: before, keys: AIConfig.changedKeys(before, config), at: configURL)
        try touch(configURL, at: at)
    }

    func touch(_ url: URL, at: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: at], ofItemAtPath: url.path)
    }

    @discardableResult
    func sync(at: Date) -> ICloudSyncEngine.Report {
        var engine = self.engine
        engine.now = { at }
        return engine.run()
    }

    var state: ICloudSync.State { ICloudSync.State.load(from: engine.stateURL) }
}

@Suite(.serialized)
struct ICloudSyncTests {
    let t0 = SyncRig.t0
    func t(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    // MARK: Two Macs

    @Test func differentKeysChangedOnTwoMacsBothArrive() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A"), b = try rig.mac("B")
        #expect(a.sync(at: t(0)).outcome == .synced)
        #expect(b.sync(at: t(1)).outcome == .synced)
        try a.edit(at: t(2)) { $0.typeOut = true }
        try b.edit(at: t(3)) { $0.candidateLayout = .vertical }
        a.sync(at: t(4))
        b.sync(at: t(5))
        a.sync(at: t(6))
        for mac in [a, b] {
            let config = try mac.config()
            #expect(config.typeOut && config.candidateLayout == .vertical)
        }
        let file = try rig.settingsJSON()
        let typeOut = try #require(file["typeOut"] as? [String: Any])
        #expect(typeOut["value"] as? Bool == true && typeOut["by"] as? String == a.state.macID)
        #expect((typeOut["modified"] as? String).flatMap(ICloudSync.date) == t(2))
    }

    @Test func theSameKeyChangedOnBothTheNewerWins() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A"), b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        // Both change the styles before either syncs: B's is the newer.
        try a.edit(at: t(2)) { $0.rewriteStyles = ["简洁"] }
        try b.edit(at: t(3)) { $0.rewriteStyles = ["正式", "润色"] }
        let first = a.sync(at: t(4))
        #expect(first.uploaded == ["rewriteStyles"])
        let second = b.sync(at: t(5))
        #expect(second.uploaded == ["rewriteStyles"] && second.applied.isEmpty)
        let third = a.sync(at: t(6))
        #expect(third.applied == ["rewriteStyles"])
        #expect(try a.config().rewriteStyles == ["正式", "润色"] && b.config().rewriteStyles == ["正式", "润色"])
        // Synced again, nothing moves.
        #expect(a.sync(at: t(7)).applied.isEmpty && b.sync(at: t(8)).uploaded.isEmpty)
    }

    @Test func aDeleteAgainstAnEditTheNewerWins() throws {
        let rig = try SyncRig()
        let slack = "com.tinyspeck.slackmacgap"
        let a = try rig.mac("A") { $0.appProfiles[slack] = AppProfile(typeOut: true) }
        let b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        #expect(try b.config().profile(for: slack)?.typeOut == true)
        // A removes Slack's settings, then B changes them: B's edit is newer and puts them back on A.
        try a.edit(at: t(2)) { $0.removeProfile(for: slack) }
        try b.edit(at: t(3)) { $0.changeProfile(for: slack) { $0.noAI = true } }
        a.sync(at: t(4))
        let tomb = try #require(try rig.settingsJSON()["appProfiles.\(slack)"] as? [String: Any])
        #expect(tomb["deleted"] as? Bool == true && tomb["value"] == nil)
        b.sync(at: t(5))
        a.sync(at: t(6))
        #expect(try a.config().profile(for: slack) == AppProfile(typeOut: true, noAI: true))
        // Now the other way round: B's delete is newer than A's edit.
        try a.edit(at: t(7)) { $0.changeProfile(for: slack) { $0.typeOut = false } }
        try b.edit(at: t(8)) { $0.removeProfile(for: slack) }
        a.sync(at: t(9))
        b.sync(at: t(10))
        a.sync(at: t(11))
        #expect(try a.config().profile(for: slack) == nil && b.config().profile(for: slack) == nil)
    }

    @Test func appProfilesMergePerApp() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A"), b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        try a.edit(at: t(2)) { $0.changeProfile(for: "com.apple.mail") { $0.rewriteStyles = ["正式"] } }
        try b.edit(at: t(3)) { $0.changeProfile(for: "com.tencent.xinWeChat") { $0.inputLanguage = .chinese } }
        a.sync(at: t(4))
        b.sync(at: t(5))
        a.sync(at: t(6))
        for mac in [a, b] {
            let config = try mac.config()
            #expect(config.profile(for: "com.apple.mail")?.rewriteStyles == ["正式"])
            #expect(config.profile(for: "com.tencent.xinWeChat")?.inputLanguage == .chinese)
        }
    }

    @Test func anAppSpelledInAnotherCaseIsTheSameApp() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") { $0.appProfiles["com.apple.Mail"] = AppProfile(typeOut: true) }
        let b = try rig.mac("B") { $0.appProfiles["com.apple.mail"] = AppProfile(noAI: true) }
        a.sync(at: t(0))
        b.sync(at: t(1))
        // B joined: iCloud's (A's) settings for Mail, kept under B's own spelling; one key in settings.json.
        let config = try b.config()
        #expect(config.appProfiles == ["com.apple.mail": AppProfile(typeOut: true)])
        #expect(try rig.settingsJSON().keys.filter { $0.lowercased().hasPrefix("appprofiles.") } == ["appProfiles.com.apple.Mail"])
        try b.edit(at: t(2)) { $0.changeProfile(for: "com.apple.mail") { $0.typeOut = false } }
        #expect(b.sync(at: t(3)).uploaded == ["appProfiles.com.apple.Mail"])
        a.sync(at: t(4))
        #expect(try a.config().appProfiles == ["com.apple.Mail": AppProfile(typeOut: false)])
    }

    @Test func turningSyncOnTakesWhatIsInICloud() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") { $0.setOrder([OutputLanguage("ja"), .english]) }
        a.sync(at: t(0))
        // A Mac with other settings (and the defaults) turns sync on later: A's settings come to it, its own don't go up.
        let b = try rig.mac("B") { $0.typeOutRate = 30 }
        let report = b.sync(at: t(10))
        #expect(report.applied.contains("outputLanguages") && report.applied.contains("typeOutRate"))
        #expect(report.uploaded.isEmpty)
        let config = try b.config()
        #expect(config.outputLanguages == [OutputLanguage("ja"), .english] && config.outputLanguage == OutputLanguage("ja"))
        #expect(config.typeOutRate == Config.default.typeOutRate)
        // A key iCloud doesn't have yet goes up, as from before syncing (older than any change).
        try FileManager.default.removeItem(at: rig.folder.url.appendingPathComponent(ICloudSync.settingsFile))
        let c = try rig.mac("C") { $0.typeOut = true }
        c.sync(at: t(20))
        let typeOut = try #require(try rig.settingsJSON()["typeOut"] as? [String: Any])
        #expect((typeOut["modified"] as? String).flatMap(ICloudSync.date) == Date(timeIntervalSince1970: 0))
    }

    // MARK: Versions

    @Test func aKeyFromANewerVersionIsKeptAndIgnored() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A")
        a.sync(at: t(0))
        // A newer version wrote a key this one doesn't know, with a large number.
        let url = rig.folder.url.appendingPathComponent(ICloudSync.settingsFile)
        var text = try String(contentsOf: url, encoding: .utf8)
        let future = #""laterSetting" : { "by" : "NEWER", "modified" : "2030-01-01T00:00:00Z", "value" : 12345678901234567890 }"#
        text = text.replacingOccurrences(of: "{\n", with: "{\n  " + future + ",\n", options: [], range: text.range(of: "{\n"))
        try Data(text.utf8).write(to: url)
        try a.edit(at: t(1)) { $0.typeOut = true }
        // The config file keeps a key this version doesn't know either.
        var configText = try String(contentsOf: a.configURL, encoding: .utf8)
        configText = configText.replacingOccurrences(of: "{\n", with: "{\n  \"futureKey\" : 98765432109876543210,\n", options: [], range: configText.range(of: "{\n"))
        try Data(configText.utf8).write(to: a.configURL)
        try a.touch(a.configURL, at: t(1))
        let report = a.sync(at: t(2))
        #expect(report.uploaded == ["typeOut"] && report.refused.isEmpty)
        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after.contains(future))
        #expect(try String(contentsOf: a.configURL, encoding: .utf8).contains("\"futureKey\" : 98765432109876543210"))
        let b = try rig.mac("B")
        b.sync(at: t(3))
        #expect(try b.config().typeOut)
        #expect(try String(contentsOf: url, encoding: .utf8).contains(future))
    }

    // MARK: iCloud placeholders, corrupt files

    @Test func aPlaceholderIsNeverEmptySettings() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") { $0.typeOut = true }
        a.sync(at: t(0))
        // On B the file isn't downloaded yet: only its placeholder is there.
        let folder = rig.folder.url
        let real = folder.appendingPathComponent(ICloudSync.settingsFile)
        let saved = try Data(contentsOf: real)
        try FileManager.default.removeItem(at: real)
        try Data().write(to: folder.appendingPathComponent(".settings.json.icloud"))
        let b = try rig.mac("B") { $0.candidateLayout = .vertical }
        let before = try Data(contentsOf: b.configURL)
        let waiting = b.sync(at: t(1))
        #expect(waiting.outcome == .waiting && waiting.applied.isEmpty && waiting.uploaded.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: real.path), "nothing written over the placeholder")
        #expect(try Data(contentsOf: b.configURL) == before)
        // A change on B meanwhile is stamped and goes up once the file is there.
        try b.edit(at: t(2)) { $0.useSelection = false }
        #expect(b.sync(at: t(3)).outcome == .waiting)
        try saved.write(to: real)
        try FileManager.default.removeItem(at: folder.appendingPathComponent(".settings.json.icloud"))
        let report = b.sync(at: t(4))
        #expect(report.outcome == .synced && report.applied.contains("typeOut") && report.applied.contains("candidateLayout"))
        #expect(report.uploaded == ["useSelection"])
        let config = try b.config()
        #expect(config.typeOut && config.candidateLayout == .horizontal && !config.useSelection)
    }

    @Test func aCorruptFileIsSetAsideNeverOverwritten() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") { $0.typeOut = true }
        let url = rig.folder.url.appendingPathComponent(ICloudSync.settingsFile)
        try FileManager.default.createDirectory(at: rig.folder.url, withIntermediateDirectories: true)
        let garbage = Data("{\"typeOut\": {\"value\": fals".utf8)
        try garbage.write(to: url)
        let before = try Data(contentsOf: a.configURL)
        let report = a.sync(at: t(0))
        let aside = try #require(report.setAside)
        #expect(aside.hasPrefix("settings (unreadable ") && aside.hasSuffix(").json"))
        #expect(try Data(contentsOf: rig.folder.url.appendingPathComponent(aside)) == garbage)
        #expect(try Data(contentsOf: a.configURL) == before)
        #expect(report.outcome == .synced && report.uploaded.contains("typeOut"))
        #expect((try rig.settingsJSON()["typeOut"] as? [String: Any])?["value"] as? Bool == true)
        // Another corrupt one later: set aside under another name, the first kept.
        try garbage.write(to: url)
        let again = a.sync(at: t(0))
        #expect(again.setAside != nil && again.setAside != aside)
        #expect(FileManager.default.fileExists(atPath: rig.folder.url.appendingPathComponent(aside).path))
    }

    // MARK: Checks

    @Test func badValuesAreRefusedKeyByKeyAndLoggedOnce() throws {
        let rig = try SyncRig()
        let b = try rig.mac("B", environment: .init(hasKey: { $0 != .gemini }, awsProfiles: { ["default"] }))
        b.sync(at: t(0))
        // Another Mac (or a hand edit) wrote values Settings would never save, next to a good one.
        let url = rig.folder.url.appendingPathComponent(ICloudSync.settingsFile)
        var file = try rig.settingsJSON()
        func entry(_ value: Any) -> [String: Any] { ["value": value, "modified": ICloudSync.dateText(t(5)), "by": "OTHER"] }
        file["outputLanguages"] = entry(["en", "fr", "de", "ja", "ko", "es"])
        file["typeOutRate"] = entry(1000)
        file["typeOut"] = entry("yes")
        file["provider"] = entry("gemini")
        file["awsProfile"] = entry("someone-elses")
        file["customCommands"] = entry([["name": "do it", "type": "run", "argv": ["rm"]]])
        file["candidateLayout"] = entry("vertical")
        try JSONSerialization.data(withJSONObject: file).write(to: url)
        let report = b.sync(at: t(6))
        #expect(report.applied == ["candidateLayout"])
        #expect(report.rejected == ["outputLanguages": .outOfRange, "typeOutRate": .outOfRange, "typeOut": .wrongType,
                                    "provider": .noKey, "awsProfile": .noProfile, "customCommands": .invalidCommand])
        let config = try b.config()
        #expect(config.candidateLayout == .vertical && config.provider == .bedrock && config.typeOutRate == Config.default.typeOutRate)
        // Refused again next time, but not logged again; this Mac's values don't go up over them either.
        let again = b.sync(at: t(7))
        #expect(again.rejected.isEmpty && again.refused.count == 6 && again.uploaded.isEmpty)
        #expect(b.state.rejected.count == 6)
    }

    @Test func aProviderComesInOnceItsKeyIsSaved() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") { $0.provider = .anthropic }
        a.sync(at: t(0))
        let keys = KeyBox()
        let b = try rig.mac("B", environment: .init(hasKey: { _ in keys.saved }))
        #expect(b.sync(at: t(1)).rejected == ["provider": .noKey])
        #expect(try b.config().provider == .bedrock)
        keys.saved = true
        #expect(b.sync(at: t(2)).applied == ["provider"])
        #expect(try b.config().provider == .anthropic && b.state.rejected.isEmpty)
    }

    final class KeyBox: @unchecked Sendable { var saved = false }

    @Test func theRulesSettingsKeeps() {
        let env = ICloudSync.Environment()
        typealias J = AIConfig.JSONValue
        let ok: [(String, J?)] = [
            ("typeOut", .bool(true)), ("maxTokens", .number(1200)), ("temperature", .null), ("timeoutSeconds", .number(30)),
            ("outputLanguages", .array([.string("zh-Hant"), .string("en")])), ("inputLanguages", .array([.string("zh"), .string("xx")])),
            ("region", .string("eu-west-1")), ("region", .null), ("uiLanguage", .null), ("questionRounds", .number(7)),
            ("questionRounds", nil), ("appProfiles.com.apple.mail", nil), ("redaction", .object(["enabled": .bool(true)])),
            (ICloudSync.hiddenWordsKey, .array([.string("Atlas")])), ("actionKey", .string("enter")),
            ("customCommands", .array([.object(["name": .string("py"), "type": .string("run"), "argv": .array([.string("python3")])])])),
        ]
        for (key, value) in ok { #expect(ICloudSync.problem(key, value, environment: env) == nil, "\(key)") }
        let bad: [(String, J?, ICloudSync.Problem)] = [
            ("typeOut", nil, .cannotDelete), ("maxTokens", .number(0), .outOfRange), ("timeoutSeconds", .string("30"), .wrongType),
            ("inputLanguages", .array([]), .outOfRange), ("inputLanguages", .array([.string("xx")]), .outOfRange),
            ("outputLanguages", .array([.string("not a code")]), .unknownValue), ("region", .string("mars-1"), .unknownValue),
            ("candidateLayout", .string("grid"), .unknownValue), ("questionRounds", .number(42), .outOfRange),
            ("uiLanguage", .string("fr"), .unknownValue), ("provider", .string("someone"), .unknownValue),
            ("anthropic", .object(["baseURL": .string("ftp://x")]), .outOfRange), ("redaction", .object(["enabled": .string("on")]), .wrongType),
            ("customCommands", .array([.object(["name": .string("a"), "type": .string("prompt"), "prompt": .string("x")]),
                                       .object(["name": .string("A"), "type": .string("prompt"), "prompt": .string("y")])]), .invalidCommand),
            ("appProfiles.com.apple.mail", .object(["inputLanguage": .string("klingon")]), .unknownValue),
            ("appProfiles.com.apple.mail", .object(["noAI": .string("yes")]), .wrongType),
        ]
        for (key, value, problem) in bad { #expect(ICloudSync.problem(key, value, environment: env) == problem, "\(key)") }
    }

    // MARK: What syncs, what never does

    @Test func neverSyncedKeysNeverGoUp() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") { config in
            config.extensionFolders = ["~/Secret/extensions"]
            config.hiddenExtensionFolders = ["~/Other"]
            config.extensionSources = [ExtensionSource(url: "git@github.com:me/private.git")]
            config.disabledExtensions = ["x"]
            config.extensionPreferences = ["bundle": ["user": "me"]]
            config.redaction.customWords = ["Project Atlas"]
            config.customCommands = [CustomCommand(name: "deploy", type: .run, argv: ["./deploy.sh"])]
        }
        a.sync(at: t(0))
        let text = try String(contentsOf: rig.folder.url.appendingPathComponent(ICloudSync.settingsFile), encoding: .utf8)
        for never in ["extensionFolders", "Secret", "hiddenExtensionFolders", "extensionSources", "private.git", "disabledExtensions",
                      "extensionPreferences", "jargonFile", "iCloudSync", "outputLanguage\"", "defaultInput", "Project Atlas", "apiKey"] {
            #expect(!text.contains(never), "\(never) synced")
        }
        // Custom commands sync with the jargon list (on by default).
        #expect(text.contains("deploy"))
        for key in try rig.settingsJSON().keys { #expect(ICloudSync.category(of: key) != nil, "\(key)") }
        for key in ICloudSync.neverSynced { #expect(ICloudSync.category(of: key) == nil) }
    }

    @Test func theSwitchesChooseWhatSyncs() throws {
        #expect(ICloudSyncSettings().categories.isEmpty)
        #expect(ICloudSyncSettings(enabled: true).categories == [.settings, .jargon, .learnedWords])
        let rig = try SyncRig()
        let a = try rig.mac("A") { config in
            config.iCloudSync = ICloudSyncSettings(enabled: true, settings: false, jargon: true, hiddenWords: true)
            config.typeOut = true
            config.redaction.customWords = ["Atlas"]
        }
        a.sync(at: t(0))
        let file = try rig.settingsJSON()
        #expect(file["typeOut"] == nil && file["redaction"] == nil)
        #expect((file[ICloudSync.hiddenWordsKey] as? [String: Any])?["value"] as? [String] == ["Atlas"])
        // Hidden words are off by default on B: they don't come in.
        let b = try rig.mac("B")
        b.sync(at: t(1))
        #expect(try b.config().redaction.customWords.isEmpty)
        // Settings turned on on A for the first time: it joins, iCloud's (B's) settings come in.
        try a.edit(at: t(2)) { $0.iCloudSync.settings = true }
        #expect(a.sync(at: t(3)).applied.contains("typeOut"))
        #expect(try !a.config().typeOut)
        // Turned off, a change stays here; turned on again, it goes up (stamped when the file changed), and B's
        // change meanwhile comes in.
        try a.edit(at: t(4)) { $0.iCloudSync.settings = false }
        try a.edit(at: t(5)) { $0.candidateLayout = .vertical }
        a.sync(at: t(6))
        #expect((try rig.settingsJSON()["candidateLayout"] as? [String: Any])?["value"] as? String == "horizontal")
        try b.edit(at: t(7)) { $0.typeOutRate = 30 }
        b.sync(at: t(8))
        try a.edit(at: t(9)) { $0.iCloudSync.settings = true }
        let report = a.sync(at: t(10))
        #expect(report.uploaded == ["candidateLayout"] && report.applied == ["typeOutRate"])
        b.sync(at: t(11))
        #expect(try b.config().candidateLayout == .vertical && a.config().typeOutRate == 30)
    }

    @Test func offMeansNothingIsTouched() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") { $0.iCloudSync.enabled = false }
        #expect(a.sync(at: t(0)).outcome == .off)
        #expect(!rig.folder.exists && !FileManager.default.fileExists(atPath: a.engine.stateURL.path))
        // No iCloud Drive: nothing is made.
        let gone = try rig.mac("B")
        var engine = gone.engine
        engine.folder = ICloudSyncFolder(url: rig.root.appendingPathComponent("NoDrive/AllInOneIME"))
        #expect(engine.run().outcome == .unavailable)
        #expect(!FileManager.default.fileExists(atPath: rig.root.appendingPathComponent("NoDrive").path))
    }

    @Test func theConfigIsWrittenOnlyWhenAValueChanges() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A"), b = try rig.mac("B")
        a.sync(at: t(0))
        let before = try Data(contentsOf: b.configURL)
        let date = try FileManager.default.attributesOfItem(atPath: b.configURL.path)[.modificationDate] as? Date
        b.sync(at: t(1))
        b.sync(at: t(2))
        #expect(try Data(contentsOf: b.configURL) == before)
        #expect(try FileManager.default.attributesOfItem(atPath: b.configURL.path)[.modificationDate] as? Date == date)
        // A change from A rewrites only its key.
        try a.edit(at: t(3)) { $0.typeOutVaries = true }
        a.sync(at: t(4))
        #expect(b.sync(at: t(5)).configKeys == ["typeOutVaries"])
        let after = try String(contentsOf: b.configURL, encoding: .utf8)
        #expect(after == String(decoding: before, as: UTF8.self).replacingOccurrences(of: "\"typeOutVaries\" : false", with: "\"typeOutVaries\" : true"))
    }

    // MARK: The jargon list and recent questions

    @Test func theJargonListSyncsOnceItsFileIsHere() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A")
        try Data("抓手：着力点\n".utf8).write(to: a.jargonURL)
        a.sync(at: t(0))
        #expect(try Data(contentsOf: rig.folder.url.appendingPathComponent(ICloudSync.jargonFile)) == Data("抓手：着力点\n".utf8))
        let b = try rig.mac("B")
        b.sync(at: t(1))
        #expect(try String(contentsOf: b.jargonURL, encoding: .utf8) == "抓手：着力点\n")
        // A's newer list: its entry arrives before its file on B (still a placeholder) — B waits, keeping its own.
        try Data("抓手：着力点\n赋能：帮助\n".utf8).write(to: a.jargonURL)
        try a.touch(a.jargonURL, at: t(2))
        a.sync(at: t(3))
        let file = rig.folder.url.appendingPathComponent(ICloudSync.jargonFile)
        let newer = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try Data().write(to: rig.folder.url.appendingPathComponent(".jargon.txt.icloud"))
        #expect(b.sync(at: t(4)).outcome == .waiting)
        #expect(try String(contentsOf: b.jargonURL, encoding: .utf8) == "抓手：着力点\n")
        try newer.write(to: file)
        try FileManager.default.removeItem(at: rig.folder.url.appendingPathComponent(".jargon.txt.icloud"))
        let report = b.sync(at: t(5))
        #expect(report.jargonChanged && report.outcome == .synced)
        #expect(try String(contentsOf: b.jargonURL, encoding: .utf8) == "抓手：着力点\n赋能：帮助\n")
        // Deleted on B only: never deleted elsewhere.
        try FileManager.default.removeItem(at: b.jargonURL)
        b.sync(at: t(6))
        a.sync(at: t(7))
        #expect(FileManager.default.fileExists(atPath: a.jargonURL.path) && FileManager.default.fileExists(atPath: file.path))
    }

    @Test func recentQuestionsOnlyWhenTurnedOnAndMergedWhenBothAsked() throws {
        let rig = try SyncRig()
        let on = ICloudSyncSettings(enabled: true, recentQuestions: true)
        let a = try rig.mac("A") { $0.iCloudSync = on }
        let b = try rig.mac("B") { $0.iCloudSync = on }
        let off = try rig.mac("C")
        var history = QuestionHistory()
        history.record(.init(question: "what is rust", answer: "A language.", date: t(0)))
        try history.write(to: a.engine.questionsURL)
        a.sync(at: t(1))
        b.sync(at: t(2))
        off.sync(at: t(3))
        #expect(QuestionHistory.load(from: b.engine.questionsURL).entries.map(\.question) == ["what is rust"])
        #expect(!FileManager.default.fileExists(atPath: off.engine.questionsURL.path), "off by default")
        // Both ask before either syncs: the two lists are merged, newest first.
        var onA = QuestionHistory.load(from: a.engine.questionsURL)
        onA.record(.init(question: "who made it", answer: "Graydon Hoare.", date: t(4)))
        try onA.write(to: a.engine.questionsURL)
        try a.touch(a.engine.questionsURL, at: t(4))
        var onB = QuestionHistory.load(from: b.engine.questionsURL)
        onB.record(.init(question: "why is it safe", answer: "The borrow checker.", date: t(5)))
        try onB.write(to: b.engine.questionsURL)
        try b.touch(b.engine.questionsURL, at: t(5))
        a.sync(at: t(6))
        b.sync(at: t(7))
        a.sync(at: t(8))
        for mac in [a, b] {
            #expect(QuestionHistory.load(from: mac.engine.questionsURL).entries.map(\.question) == ["why is it safe", "who made it", "what is rust"])
        }
        // Cleared on one Mac: cleared on the other.
        try QuestionHistory().write(to: b.engine.questionsURL)
        b.sync(at: t(9))
        a.sync(at: t(10))
        #expect(QuestionHistory.load(from: a.engine.questionsURL).entries.isEmpty)
    }

    // MARK: The config key, the record

    @Test func theSettingIsThisMacsOwnAndWrittenOnlyOnceSet() throws {
        let data = try JSONEncoder().encode(Config.default)
        #expect(!String(decoding: data, as: UTF8.self).contains("iCloudSync"))
        var config = Config.default
        config.iCloudSync = ICloudSyncSettings(enabled: true, hiddenWords: true)
        let read = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(read.iCloudSync == config.iCloudSync)
        // A switch of the wrong type keeps its default; the file still reads.
        let odd = try JSONDecoder().decode(Config.self, from: Data(#"{"iCloudSync": {"enabled": "yes", "hiddenWords": true}}"#.utf8))
        #expect(odd.iCloudSync == ICloudSyncSettings(enabled: false, hiddenWords: true))
        #expect(Config.allKeys.contains("iCloudSync"))
    }

    @Test func theRecordRoundTrips() throws {
        let rig = try SyncRig()
        let url = rig.root.appendingPathComponent("state.json")
        var state = ICloudSync.State(macID: "MAC-1")
        state.entries = ["typeOut": .init(value: .bool(true), stamp: .init(modified: t(1), by: "MAC-2")),
                         "appProfiles.x.y": .init(value: nil, stamp: .init(modified: t(2), by: "MAC-1"))]
        state.lastSync = t(3)
        state.rejected = ["provider": .init(stamp: .init(modified: t(4), by: "MAC-3"), problem: .noKey)]
        try state.write(to: url)
        #expect(ICloudSync.State.load(from: url) == state)
        // None, or unreadable: a new Mac id.
        try Data("x".utf8).write(to: url)
        #expect(ICloudSync.State.load(from: url).macID != "MAC-1")
    }

    @Test func stampsAndEntries() {
        let a = ICloudSync.Stamp(modified: t(1), by: "A"), b = ICloudSync.Stamp(modified: t(1), by: "B")
        #expect(a < b && ICloudSync.Stamp(modified: t(0), by: "Z") < a && ICloudSync.Stamp.joining("Z") < a)
        let entry = ICloudSync.Entry(value: .array([.string("x")]), stamp: a)
        #expect(ICloudSync.Entry(json: entry.json) == entry)
        let tomb = ICloudSync.Entry(value: nil, stamp: b)
        #expect(ICloudSync.Entry(json: tomb.json) == tomb)
        #expect(ICloudSync.Entry(json: .object(["value": .bool(true)])) == nil)
        #expect(ICloudSync.Entry(json: .object(["value": .bool(true), "deleted": .bool(true), "modified": .string("2026-10-16T18:00:00Z"), "by": .string("A")])) == nil)
        #expect(ICloudSync.date("2026-10-16T18:00:00Z") != nil && ICloudSync.date("2026-10-16T18:00:00.123Z") != nil)
    }

    // MARK: The folder, Rime's sync folder

    @Test func theFolderTellsPlaceholdersAndMissingFilesApart() throws {
        let rig = try SyncRig()
        let folder = rig.folder
        #expect(folder.isAvailable && !folder.exists)
        #expect(try folder.read("settings.json") == .missing)
        try folder.write("settings.json", Data("{}".utf8))
        #expect(try folder.read("settings.json") == .data(Data("{}".utf8)))
        try folder.write("rime/other-mac/.rime_ice.userdb.txt.icloud", Data())
        #expect(try folder.read("rime/other-mac/rime_ice.userdb.txt") == .placeholder)
        #expect(folder.placeholders(in: "rime") == ["rime_ice.userdb.txt"])
        #expect(folder.downloadAll(in: "rime") == 1)
        #expect(ICloudSyncFolder.name(ofPlaceholder: ".questions.json.icloud") == "questions.json")
        #expect(ICloudSyncFolder.name(ofPlaceholder: "questions.json") == nil)
        #expect(ICloudSyncFolder.iCloudDrive(home: URL(fileURLWithPath: "/Users/x")).url.path
                == "/Users/x/Library/Mobile Documents/com~apple~CloudDocs/AllInOneIME")
        #expect(!ICloudSyncFolder(url: rig.root.appendingPathComponent("none/AllInOneIME")).isAvailable)
    }

    @Test func rimeSyncDirKeepsTheInstallationID() throws {
        let yaml = """
            distribution_code_name: AllInOneIME
            installation_id: "6c2b-this-mac"
            sync_dir: "/old/place"
            update_time: "Fri Oct 16 18:00:00 2026"

            """
        let set = RimeSync.installation(yaml, syncDir: "/Users/x/Library/Mobile Documents/com~apple~CloudDocs/AllInOneIME/rime")
        #expect(set.contains(#"installation_id: "6c2b-this-mac""#) && set.contains("update_time"))
        #expect(RimeSync.syncDir(in: set) == "/Users/x/Library/Mobile Documents/com~apple~CloudDocs/AllInOneIME/rime")
        #expect(set.components(separatedBy: "sync_dir:").count == 2)
        let removed = RimeSync.installation(set, syncDir: nil)
        #expect(RimeSync.syncDir(in: removed) == nil && removed.contains("installation_id"))
        #expect(RimeSync.syncDir(in: RimeSync.installation("", syncDir: #"/a "quoted" \ path"#)) == #"/a "quoted" \ path"#)
        let rig = try SyncRig()
        let user = rig.root.appendingPathComponent("Rime")
        #expect(try RimeSync.setSyncDir(rig.folder.url.appendingPathComponent("rime"), userDataDir: user))
        #expect(try !RimeSync.setSyncDir(rig.folder.url.appendingPathComponent("rime"), userDataDir: user), "unchanged: not written")
        #expect(try RimeSync.setSyncDir(nil, userDataDir: user))
        #expect(try String(contentsOf: user.appendingPathComponent("installation.yaml"), encoding: .utf8).isEmpty)
    }

    // MARK: @config, @doctor

    @Test func configTurnsSyncOnOrOffButNeverTheOptIns() throws {
        var config = Config.default
        let env = AIConfig.Environment(chinese: false)
        let on = try AIConfig.preview(AIConfig.parse(#"{"changes": [{"key": "iCloudSync.enabled", "value": true}]}"#), config: config,
                                      environment: env).get()
        #expect(on.edits == [.iCloudSync(true)] && on.rows.first?.text(chinese: false) == "Sync through iCloud: off → on")
        let undo = AIConfig.apply(on.edits, to: &config)
        #expect(config.iCloudSync.enabled && undo == [.iCloudSync(false)])
        for key in ["iCloudSync.hiddenWords", "iCloudSync.recentQuestions", "iCloudSync.settings"] {
            let proposal = try AIConfig.parse(#"{"changes": [{"key": "\#(key)", "value": true}]}"#)
            guard case let .failure(failure) = AIConfig.preview(proposal, config: config, environment: env) else {
                Issue.record("\(key) previewed")
                continue
            }
            let line = AIConfig.failureLine(failure, proposal: proposal, config: config, environment: env)
            #expect(line.contains("Settings"), "\(line)")
        }
        // No iCloud Drive: not turned on.
        let noDrive = AIConfig.Environment(chinese: false, iCloudDriveAvailable: { false })
        let refused = AIConfig.preview(try AIConfig.parse(#"{"changes": [{"key": "iCloudSync.enabled", "value": true}]}"#),
                                       config: .default, environment: noDrive)
        #expect(refused == .failure(.notAllowed))
        let prompt = AIConfigPrompt.request("sync my settings", context: .init(config: config)).system.map(\.text).joined()
        #expect(prompt.contains("iCloudSync.enabled") && !prompt.contains("hiddenWords"))
    }

    @Test func doctorSaysWhetherItSyncs() {
        var facts = Doctor.Facts()
        func rows(_ chinese: Bool = false) -> [Doctor.Finding] { Doctor.findings(facts, chinese: chinese).filter { $0.area == .iCloudSync } }
        #expect(rows().map(\.status) == [.ok] && rows()[0].text(chinese: false).contains("off"))
        facts.iCloudSync.enabled = true
        facts.iCloudSync.available = false
        #expect(rows().map(\.status) == [.problem] && rows()[0].text(chinese: false).contains("System Settings → Apple Account → iCloud"))
        facts.iCloudSync.available = true
        facts.iCloudSync.checked = t(10)
        facts.iCloudSync.lastSync = t(8)
        #expect(rows().map(\.status) == [.ok] && rows()[0].title == "Synced through iCloud 2 min ago")
        #expect(rows(true)[0].title == "已通过 iCloud 同步（2 分钟前）")
        facts.iCloudSync.lastError = "The disk is full"
        #expect(rows().map(\.status) == [.warning] && rows()[0].text(chinese: false).contains("The disk is full"))
        facts.iCloudSync.lastError = nil
        facts.iCloudSync.refused = ["provider": .noKey]
        #expect(rows().map(\.status) == [.warning, .ok] && rows()[0].text(chinese: false).contains("provider (no key for it on this Mac)"))
    }
}

import Foundation
import Testing
@testable import AllInOneIMECore

// Acceptance tests for "sync through iCloud" (spec-icloud-sync.md and the coordinator's decisions on it, with the later
// ones: a first join merges collections, turning sync back on is a rejoin, stamps from the future are accepted), written from
// the spec by an independent reviewer; the implementer may not edit them. Each test's name says what it enforces:
// "what" what syncs, "never" what never does, "merge" newest-wins per key, "join" a Mac turning sync on, "versions" keys
// and names of a newer version, "files" placeholders, missing and corrupt files, "valid" checking incoming values, "off"
// turning it off and Remove from iCloud, "@config", "rime" the learned words' sync_dir, "unavailable" no iCloud Drive.
//
// Two or three "Macs" (`ICAMac`) share one temporary "iCloud Drive" folder (`ICAWorld`). Each has its own config.json,
// sync record, recent questions and jargon list in a temporary home, its own clock, and its own keys and AWS profiles
// (what the checks are told). A change is made as Settings makes it: the config file is rewritten and gets the Mac's
// clock as its modification time. Nothing here touches ~/.config/allinoneime, iCloud Drive, the Rime folder or ~/.aws;
// the one test of "Remove from iCloud…" takes its own uniquely named folder back out of the Trash.

// MARK: - The rig

enum ICA {
    /// The tests' clocks count seconds from here: earlier than the real time, which the files the engine writes get.
    static let base = ISO8601DateFormatter().date(from: "2026-10-16T10:00:00Z")!
    static func t(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    /// ISO 8601, as another Mac writes a stamp.
    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    static func date(_ text: Any?) -> Date? {
        guard let text = text as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// A Mac's settings to start from: the defaults, with sync turned on (the switches under it at their defaults).
    static var syncOn: Config {
        var config = Config.default
        config.iCloudSync.enabled = true
        return config
    }

    static func command(_ name: String) -> CustomCommand {
        CustomCommand(name: name, type: .prompt, prompt: "Rewrite it the \(name) way")
    }

    static func object(_ data: Data?) -> [String: Any]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    /// `config` as its file holds it, key by key.
    static func encoded(_ config: Config) -> [String: Any] {
        object(try? JSONEncoder().encode(config)) ?? [:]
    }

    /// A JSON value as comparable text ("<absent>" for none).
    static func canon(_ any: Any?) -> String {
        guard let any else { return "<absent>" }
        guard let data = try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed, .sortedKeys]) else {
            return "\(any)"
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// A JSON value from its text.
    static func json(_ text: String) -> Any {
        try! JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
    }

    /// What a file holding `file` holds after `after` replaces `before` in it: objects field by field, so fields the
    /// config doesn't know (in neither) stay, as Settings' writes keep them.
    static func merged(file: Any?, before: Any?, after: Any?) -> Any? {
        guard let new = after as? [String: Any], var fields = file as? [String: Any] else { return after }
        let old = before as? [String: Any] ?? [:]
        for (key, value) in new { fields[key] = merged(file: fields[key], before: old[key], after: value) }
        for key in old.keys where new[key] == nil { fields[key] = nil }
        return fields
    }

    /// A jargon list's lines (empty ones left out), in order.
    static func lines(_ text: String?) -> [String] {
        (text ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// A question as the recent questions tell them apart: case and spacing aside.
    static func normalized(_ question: String) -> String {
        question.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Mac B, set up by `setup`, joining what iCloud has for `category`: turning sync on with the category on (its first
    /// sync), or, already syncing with the category off, turning it on later.
    static func join(_ world: ICAWorld, firstSync: Bool, _ category: WritableKeyPath<ICloudSyncSettings, Bool>,
                     _ setup: (inout Config) -> Void, before: (ICAMac) -> Void = { _ in }) -> ICAMac {
        let b = world.mac("B") { c in
            setup(&c)
            c.iCloudSync[keyPath: category] = firstSync
        }
        before(b)
        b.sync(at: 20)
        if !firstSync {
            b.edit(at: 30) { $0.iCloudSync[keyPath: category] = true }
            b.sync(at: 40)
        }
        return b
    }

    static func touch(_ url: URL, _ date: Date) {
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    static func mtime(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Values from iCloud that Settings wouldn't save.
    static let badValues: [ICABadValue] = [
        ICABadValue(key: "maxTokens", json: "99999"),
        ICABadValue(key: "maxTokens", json: "\"lots\""),
        ICABadValue(key: "timeoutSeconds", json: "0"),
        ICABadValue(key: "temperature", json: "5"),
        ICABadValue(key: "typeOutRate", json: "1000"),
        ICABadValue(key: "outputLanguages", json: #"["en","fr","de","ja","ko","es"]"#),
        ICABadValue(key: "inputLanguages", json: "[]"),
        ICABadValue(key: "region", json: "\"mars-1\""),
        ICABadValue(key: "questionRounds", json: "99"),
        ICABadValue(key: "menuBarIcon", json: "\"yes\""),
        ICABadValue(key: "customCommands", json: #"[{"name":"bad name 1","type":"prompt","prompt":"x"}]"#),
        ICABadValue(key: "customCommands", json: #"[{"name":"twin","type":"prompt","prompt":"x"},{"name":"twin","type":"prompt","prompt":"y"}]"#),
        ICABadValue(key: "appProfiles.com.apple.mail", json: #"{"inputLanguage":42}"#),
        ICABadValue(key: "anthropic", json: #"{"baseURL":"not a url"}"#),
        ICABadValue(key: "redaction", json: "\"on\""),
    ]

    /// Two Macs with sync on that have both synced: A first (with `a`'s settings), then B (fresh), then A again.
    static func pair(_ a: (inout Config) -> Void = { _ in }) -> (world: ICAWorld, a: ICAMac, b: ICAMac) {
        let world = ICAWorld()
        let macA = world.mac("A", a)
        let macB = world.mac("B")
        macA.sync(at: 1)
        macB.sync(at: 2)
        macA.sync(at: 3)
        return (world, macA, macB)
    }
}

/// The shared iCloud Drive (a temporary folder standing for com~apple~CloudDocs) and the AllInOneIME folder in it.
final class ICAWorld {
    let root: URL
    let drive: URL
    let folder: ICloudSyncFolder

    init(folderName: String = "AllInOneIME") {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ica-\(UUID().uuidString)", isDirectory: true)
        drive = root.appendingPathComponent("CloudDocs", isDirectory: true)
        try! FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        folder = ICloudSyncFolder(url: drive.appendingPathComponent(folderName, isDirectory: true))
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: drive.path)
        try? FileManager.default.removeItem(at: root)
    }

    /// A Mac whose config is `ICA.syncOn` changed by `setup`, written at `seconds` on its clock.
    func mac(_ name: String, at seconds: TimeInterval = 0, _ setup: (inout Config) -> Void = { _ in }) -> ICAMac {
        let mac = ICAMac(name: name, world: self)
        var config = ICA.syncOn
        config.jargonFile = mac.jargonURL.path
        setup(&config)
        try! FileManager.default.createDirectory(at: mac.home, withIntermediateDirectories: true)
        try! config.write(to: mac.configURL)
        mac.clock = ICA.t(seconds)
        ICA.touch(mac.configURL, mac.clock)
        return mac
    }

    func url(_ name: String) -> URL { folder.url.appendingPathComponent(name) }
    var settingsURL: URL { url("settings.json") }
    var settingsData: Data? { try? Data(contentsOf: settingsURL) }
    var settingsText: String { settingsData.map { String(decoding: $0, as: UTF8.self) } ?? "" }
    var settings: [String: Any] { ICA.object(settingsData) ?? [:] }
    func entry(_ key: String) -> [String: Any]? { settings[key] as? [String: Any] }
    func value(_ key: String) -> Any? { entry(key)?["value"] }

    /// Every file in the shared folder (hidden ones too), by its path in it.
    var snapshot: [String: Data] {
        guard let walker = FileManager.default.enumerator(at: folder.url, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        var out: [String: Data] = [:]
        let prefix = folder.url.resolvingSymlinksInPath().path + "/"
        for case let file as URL in walker {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let data = try? Data(contentsOf: file) else { continue }
            let path = file.resolvingSymlinksInPath().path
            out[path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : file.lastPathComponent] = data
        }
        return out
    }

    var files: Set<String> { Set(snapshot.keys) }

    /// Everything in the shared folder, as text.
    var everything: String { snapshot.values.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") }

    func write(_ name: String, _ data: Data) {
        try! FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        try! data.write(to: url(name))
    }

    /// Entries put into settings.json as another Mac (`by`) writes them, the file's other entries left as they are.
    func put(_ entries: [String: Any], at date: Date, by mac: String = "MacZ") {
        var file = settings
        for (key, value) in entries { file[key] = ["value": value, "modified": ICA.iso(date), "by": mac] }
        write("settings.json", try! JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys]))
    }

    /// `name` not downloaded yet: iCloud Drive's ".<name>.icloud" placeholder in its place. Its data, to "download" later.
    @discardableResult
    func placeholder(_ name: String) -> Data {
        let data = try! Data(contentsOf: url(name))
        try! FileManager.default.removeItem(at: url(name))
        write("." + name + ".icloud", Data("bplist00 placeholder".utf8))
        return data
    }

    /// `name` downloaded: the placeholder replaced by the file.
    func download(_ name: String, _ data: Data) {
        try? FileManager.default.removeItem(at: url("." + name + ".icloud"))
        write(name, data)
    }
}

/// One Mac: its own files, clock, keys and AWS profiles, and the iCloud Drive it sees.
final class ICAMac {
    let name: String
    /// Kept while the Mac is: its files are in the world's temporary folder.
    let world: ICAWorld
    let home: URL
    var clock = ICA.base
    /// The providers with a key on this Mac (all of them unless a test says otherwise).
    var keys: Set<Provider> = Set(Provider.allCases)
    var awsProfiles = ["default", "work"]
    /// The providers Settings offers on this Mac (Apple's model only where Apple Intelligence is).
    var offered: [Provider] = Provider.allCases
    var folder: ICloudSyncFolder

    init(name: String, world: ICAWorld) {
        self.name = name
        self.world = world
        home = world.root.appendingPathComponent("Mac-\(name)", isDirectory: true)
        folder = world.folder
    }

    var configURL: URL { home.appendingPathComponent("config/config.json") }
    var stateURL: URL { home.appendingPathComponent("Application Support/iCloudSync/state.json") }
    var questionsURL: URL { home.appendingPathComponent("Application Support/recent-questions.json") }
    var jargonURL: URL { home.appendingPathComponent("jargon/my-jargon.txt") }

    var engine: ICloudSyncEngine {
        let keys = self.keys, profiles = awsProfiles, offered = self.offered, now = clock
        let environment = ICloudSync.Environment(hasKey: { keys.contains($0) }, awsProfiles: { profiles },
                                                 offeredProviders: offered)
        return ICloudSyncEngine(folder: folder, configURL: configURL, stateURL: stateURL, questionsURL: questionsURL,
                                environment: environment, now: { now })
    }

    /// One sync run at `seconds` on this Mac's clock.
    @discardableResult
    func sync(at seconds: TimeInterval) -> ICloudSyncEngine.Report {
        clock = ICA.t(seconds)
        return engine.run()
    }

    var config: Config {
        do {
            return try Config.load(from: configURL)
        } catch {
            Issue.record("Mac \(name)'s config.json can't be read any more: \(error)")
            return .default
        }
    }

    var configData: Data? { try? Data(contentsOf: configURL) }
    var configText: String { configData.map { String(decoding: $0, as: UTF8.self) } ?? "" }
    /// config.json as JSON, key by key.
    var file: [String: Any] { ICA.object(configData) ?? [:] }

    /// A change made in Settings at `seconds`: the keys it changes rewritten in config.json (the others as they were).
    func edit(at seconds: TimeInterval, _ change: (inout Config) -> Void) {
        let old = config
        var new = old
        change(&new)
        let before = ICA.encoded(old), after = ICA.encoded(new)
        editFile(at: seconds) { file in
            for key in Set(before.keys).union(after.keys) where ICA.canon(before[key]) != ICA.canon(after[key]) {
                file[key] = ICA.merged(file: file[key], before: before[key], after: after[key])
            }
        }
    }

    /// config.json changed as JSON at `seconds` (a hand edit, or a key this version doesn't know).
    func editFile(at seconds: TimeInterval, _ change: (inout [String: Any]) -> Void) {
        clock = ICA.t(seconds)
        var json = file
        change(&json)
        let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try! data.write(to: configURL, options: .atomic)
        ICA.touch(configURL, clock)
    }

    /// An @question answered at `seconds`, remembered as the app remembers it.
    func ask(_ question: String, at seconds: TimeInterval) {
        clock = ICA.t(seconds)
        var history = QuestionHistory.load(from: questionsURL)
        history.record(.init(question: question, answer: "Answer to: \(question)", date: clock))
        try! history.write(to: questionsURL)
        ICA.touch(questionsURL, clock)
    }

    /// "Clear" in the recent questions.
    func clearQuestions(at seconds: TimeInterval) {
        clock = ICA.t(seconds)
        try! QuestionHistory().write(to: questionsURL)
        if ICA.exists(questionsURL) { ICA.touch(questionsURL, clock) }
    }

    var history: QuestionHistory { QuestionHistory.load(from: questionsURL) }
    var questions: [String] { history.entries.map(\.question) }

    func writeJargon(_ text: String, at seconds: TimeInterval) {
        clock = ICA.t(seconds)
        try! FileManager.default.createDirectory(at: jargonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(text.utf8).write(to: jargonURL)
        ICA.touch(jargonURL, clock)
    }

    var jargon: String? { (try? Data(contentsOf: jargonURL)).map { String(decoding: $0, as: UTF8.self) } }
}

/// A value from iCloud Settings wouldn't save (as JSON text), for the parameterized check.
struct ICABadValue: Sendable, CustomTestStringConvertible {
    var key: String
    var json: String
    var testDescription: String { "\(key) = \(json)" }
}

// MARK: - The tests

@Suite("ICloudSyncAcceptance")
struct ICloudSyncAcceptanceTests {

    // MARK: What syncs

    @Test("what: off by default; Settings, jargon and learned words on under it, hidden words and recent questions off")
    func defaults() throws {
        let sync = Config.default.iCloudSync
        #expect(sync.enabled == false)
        #expect(sync.settings && sync.jargon && sync.learnedWords)
        #expect(sync.hiddenWords == false)
        #expect(sync.recentQuestions == false)
        // A config file from before sync has none of it: the same.
        let world = ICAWorld()
        let old = world.mac("Old") { $0.iCloudSync.enabled = false }
        old.editFile(at: 1) { $0["iCloudSync"] = nil }
        #expect(old.config.iCloudSync == ICloudSyncSettings())
        // Off: nothing is read or written in iCloud.
        let report = old.sync(at: 2)
        #expect(report.outcome == .off)
        #expect(!ICA.exists(world.folder.url))
    }

    @Test("what: every setting in Settings reaches another Mac")
    func settingsReachAnotherMac() throws {
        let world = ICAWorld()
        let a = world.mac("A") { c in
            c.provider = .anthropic
            c.awsProfile = "work"
            c.region = "eu-west-1"
            c.modelId = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
            c.anthropic.model = "claude-opus-4-1"
            c.openai.baseURL = "https://api.deepseek.com/v1"
            c.maxTokens = 2000
            c.temperature = 0.7
            c.timeoutSeconds = 30
            c.setOrder([OutputLanguage("ja"), OutputLanguage(.english)])
            c.setOrder([Language.chinese, .english, .french])
            c.rewriteStyles = ["口语", "正式"]
            c.improveTranslates = true
            c.voiceInput = false
            c.actionKey = .optionTap
            c.uiLanguage = .chinese
            c.claudeInBackground = false
            c.rememberQuestions = false
            c.questionRounds = 8
            c.questionContinueIn = [.chatgpt, .copy]
            c.menuBarIcon = false
            c.typeOut = true
            c.typeOutRate = 8
            c.typeOutVaries = true
            c.typeOutMistakes = true
            c.fuzzyPinyin = ["z-zh", "n-l"]
            c.keyboardLayouts = ["fr": "com.apple.keylayout.French-PC"]
            c.candidateLayout = .vertical
            c.checkForUpdates = false
            c.useSelection = false
            c.appProfiles = ["com.apple.mail": AppProfile(inputLanguage: .chinese, typeOut: true)]
            c.redaction.enabled = true
            c.redaction.emails = false
            c.customCommands = [ICA.command("shout")]
        }
        let mine = a.config
        let b = world.mac("B")
        #expect(a.sync(at: 10).outcome == .synced)
        #expect(b.sync(at: 20).outcome == .synced)
        a.sync(at: 30)
        let theirs = ICA.encoded(b.config), ours = ICA.encoded(mine)
        let keys = ["provider", "awsProfile", "region", "modelId", "anthropic", "gemini", "openai", "maxTokens", "temperature",
                    "timeoutSeconds", "outputLanguage", "outputLanguages", "inputLanguages", "defaultInput", "rewriteStyles",
                    "improveTranslates", "voiceInput", "actionKey", "uiLanguage", "claudeInBackground", "rememberQuestions",
                    "questionRounds", "questionContinueIn", "menuBarIcon", "typeOut", "typeOutRate", "typeOutVaries",
                    "typeOutMistakes", "fuzzyPinyin", "keyboardLayouts", "candidateLayout", "checkForUpdates", "useSelection",
                    "appProfiles", "redaction", "customCommands"]
        for key in keys {
            #expect(ICA.canon(theirs[key]) == ICA.canon(ours[key]), "\(key) didn't reach B")
        }
        // A's own settings are as they were.
        #expect(a.config == mine)
    }

    @Test("what: the switches are each Mac's own; Settings off on one Mac leaves its settings, jargon still syncs")
    func switchesArePerMac() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.maxTokens = 2000; $0.customCommands = [ICA.command("alpha")] }
        let off = world.mac("Off") { $0.iCloudSync.enabled = false; $0.maxTokens = 500 }
        let noSettings = world.mac("NoSettings") { $0.iCloudSync.settings = false; $0.maxTokens = 600 }
        a.sync(at: 10)
        let offBefore = off.configData
        #expect(off.sync(at: 20).outcome == .off)
        #expect(off.configData == offBefore)
        noSettings.sync(at: 30)
        #expect(noSettings.config.maxTokens == 600)
        #expect(noSettings.config.customCommands.map(\.name) == ["alpha"])
        a.sync(at: 40)
        #expect(a.config.maxTokens == 2000)
        // A turning sync on (and its switches) didn't turn anything on elsewhere.
        #expect(off.config.iCloudSync.enabled == false)
        #expect(noSettings.config.iCloudSync.settings == false)
    }

    @Test("what: the jargon list syncs into each Mac's own jargon file, newest wins; its path never syncs")
    func jargonSyncs() throws {
        let world = ICAWorld()
        let a = world.mac("A")
        let b = world.mac("B")
        a.writeJargon("赋能 = enable\n抓手 = lever\n", at: 5)
        a.sync(at: 10)
        b.sync(at: 20)
        #expect(b.jargon == "赋能 = enable\n抓手 = lever\n")
        #expect(b.config.jargonFile == b.jargonURL.path)
        #expect(!world.everything.contains(a.jargonURL.path))
        #expect(world.settings["jargonFile"] == nil)
        // Edited on both: the newer list wins, on both.
        a.writeJargon("A's version\n", at: 100)
        b.writeJargon("B's version\n", at: 150)
        a.sync(at: 200)
        b.sync(at: 210)
        a.sync(at: 220)
        #expect(a.jargon == "B's version\n")
        #expect(b.jargon == "B's version\n")
    }

    @Test("what: a jargon list deleted on one Mac is never deleted elsewhere")
    func deletedJargonKeptElsewhere() throws {
        let world = ICAWorld()
        let a = world.mac("A")
        let b = world.mac("B")
        a.writeJargon("shared list\n", at: 5)
        a.sync(at: 10)
        b.sync(at: 20)
        #expect(b.jargon == "shared list\n")
        try FileManager.default.removeItem(at: a.jargonURL)
        a.sync(at: 100)
        b.sync(at: 110)
        a.sync(at: 120)
        #expect(b.jargon == "shared list\n")
        // Nor in iCloud: a Mac joining later still gets it.
        let c = world.mac("C", at: 200)
        c.sync(at: 210)
        #expect(c.jargon == "shared list\n")
    }

    // MARK: Never synced

    @Test("never: extension sources, extension folders and plugins, apps without typos, recent apps, the jargon path and the sync switches stay on their Mac")
    func neverSyncedStayHome() throws {
        let world = ICAWorld()
        let a = world.mac("A") { c in
            c.extensionSources = [ExtensionSource(url: "https://github.com/a-only/extensions.git")]
            c.extensionFolders = ["~/A-only-extensions"]
            c.hiddenExtensionFolders = ["~/A-only-hidden-scripts"]
            c.findRaycastScripts = false
            c.disabledExtensions = ["a-only-disabled"]
            c.extensionPreferences = ["a-only-bundle": ["city": "A-only-city"]]
            c.iCloudSync.learnedWords = false
            c.maxTokens = 1234
        }
        a.editFile(at: 1) { file in
            file["typeOutNoTyposApps"] = ["com.a-only.typo-app"]
            file["recentApps"] = ["com.a-only.recent-app"]
            file["plugins"] = ["~/A-only-plugin"]
        }
        let b = world.mac("B") { c in
            c.extensionFolders = ["~/B-extensions"]
            c.disabledExtensions = ["b-disabled"]
        }
        let aBefore = a.config
        a.sync(at: 10)
        b.sync(at: 20)
        a.sync(at: 30)
        let bc = b.config
        #expect(bc.maxTokens == 1234, "the run didn't sync at all")
        #expect(bc.extensionSources.isEmpty)
        #expect(bc.extensionFolders == ["~/B-extensions"])
        #expect(bc.hiddenExtensionFolders.isEmpty)
        #expect(bc.findRaycastScripts == true)
        #expect(bc.disabledExtensions == ["b-disabled"])
        #expect(bc.extensionPreferences.isEmpty)
        #expect(bc.jargonFile == b.jargonURL.path)
        #expect(bc.iCloudSync == ICA.syncOn.iCloudSync)
        #expect(b.file["typeOutNoTyposApps"] == nil)
        #expect(b.file["recentApps"] == nil)
        #expect(b.file["plugins"] == nil)
        #expect(a.config == aBefore)
        let names = ["extensionSources", "extensionFolders", "hiddenExtensionFolders", "findRaycastScripts", "disabledExtensions",
                     "extensionPreferences", "jargonFile", "typeOutNoTyposApps", "recentApps", "plugins", "iCloudSync"]
        for key in world.settings.keys {
            #expect(!names.contains { key == $0 || key.hasPrefix($0 + ".") }, "\(key) is in settings.json")
        }
        let text = world.everything.lowercased()
        #expect(!text.contains("a-only"), "something only for Mac A is in iCloud")
        #expect(!text.contains(a.home.path.lowercased()))
    }

    @Test("never: values for keys that never sync are ignored when they come from iCloud")
    func neverSyncedIgnoredFromICloud() throws {
        let world = ICAWorld()
        let b = world.mac("B") { $0.extensionFolders = ["~/B-extensions"] }
        b.editFile(at: 1) { $0["typeOutNoTyposApps"] = ["com.b.app"] }
        let before = b.file
        world.put([
            "maxTokens": 2222,
            "extensionSources": [["url": "https://github.com/someone/extensions.git"]],
            "extensionFolders": ["~/Elsewhere"],
            "hiddenExtensionFolders": ["~/ElsewhereHidden"],
            "findRaycastScripts": false,
            "disabledExtensions": ["elsewhere"],
            "extensionPreferences": ["elsewhere": ["k": "v"]],
            "jargonFile": "/tmp/elsewhere-jargon.txt",
            "typeOutNoTyposApps": ["com.elsewhere"],
            "recentApps": ["com.elsewhere"],
            "iCloudSync": ["enabled": false, "settings": false, "hiddenWords": true, "recentQuestions": true],
            "iCloudSync.hiddenWords": true,
            "iCloudSync.enabled": false,
        ], at: ICA.t(5))
        let report = b.sync(at: 10)
        #expect(b.config.maxTokens == 2222, "settings.json wasn't read")
        let after = b.file
        for key in ["extensionSources", "extensionFolders", "hiddenExtensionFolders", "findRaycastScripts", "disabledExtensions",
                    "extensionPreferences", "jargonFile", "typeOutNoTyposApps", "recentApps", "iCloudSync"] {
            #expect(ICA.canon(after[key]) == ICA.canon(before[key]), "\(key) came in from iCloud")
            #expect(!report.applied.contains(key))
        }
        #expect(b.config.iCloudSync == ICA.syncOn.iCloudSync)
    }

    @Test("never: API keys, tokens and passwords never reach iCloud, wherever they are in the config file")
    func secretsNeverLeave() throws {
        let world = ICAWorld()
        let a = world.mac("A")
        a.editFile(at: 1) { file in
            var anthropic = file["anthropic"] as? [String: Any] ?? [:]
            anthropic["apiKey"] = "sk-ant-api03-ICASECRET1"
            anthropic["model"] = "claude-sonnet-4-5"
            file["anthropic"] = anthropic
            var openai = file["openai"] as? [String: Any] ?? [:]
            openai["apiKey"] = "sk-proj-ICASECRET2"
            openai["baseURL"] = "https://api.deepseek.com/v1"
            file["openai"] = openai
            file["geminiApiKey"] = "AIzaICASECRET3"
            file["awsSecretAccessKey"] = "ICASECRET4"
            file["hosted"] = ["token": "ICASECRET5"]
            file["password"] = "ICASECRET6"
        }
        a.sync(at: 10)
        let b = world.mac("B")
        b.sync(at: 20)
        #expect(b.config.anthropic.model == "claude-sonnet-4-5", "the provider settings didn't sync")
        #expect(b.config.openai.baseURL == "https://api.deepseek.com/v1")
        #expect(!world.everything.contains("ICASECRET"), "a secret is in iCloud")
        #expect(!b.configText.contains("ICASECRET"), "a secret reached the other Mac")
        // A's file keeps them (local data is A's).
        #expect(a.configText.contains("ICASECRET1"))
    }

    @Test("never (opt-in): hidden words stay on their Mac while the switch is off, as it is by default; the redaction switches sync")
    func hiddenWordsOffByDefault() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.redaction.enabled = true; $0.redaction.customWords = ["Project Falcon", "Alice Zhang"] }
        let b = world.mac("B") { $0.redaction.customWords = ["Nightjar"] }
        a.sync(at: 10)
        b.sync(at: 20)
        #expect(b.config.redaction.enabled == true, "the redaction switch didn't sync")
        #expect(b.config.redaction.customWords == ["Nightjar"])
        // A switch changed on B reaches A; each Mac's words stay its own.
        b.edit(at: 30) { $0.redaction.emails = false }
        b.sync(at: 40)
        a.sync(at: 50)
        #expect(a.config.redaction.emails == false)
        #expect(a.config.redaction.customWords == ["Project Falcon", "Alice Zhang"])
        #expect(b.config.redaction.customWords == ["Nightjar"])
        for word in ["Falcon", "Alice Zhang", "Nightjar"] {
            #expect(!world.everything.contains(word), "\(word) is in iCloud")
        }
    }

    @Test("what (opt-in): hidden words sync between the Macs that chose them in Settings")
    func hiddenWordsWhenChosen() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.iCloudSync.hiddenWords = true; $0.redaction.customWords = ["Project Falcon"] }
        let b = world.mac("B")
        a.sync(at: 10)
        b.sync(at: 20)
        #expect(b.config.redaction.customWords.isEmpty, "B didn't choose them")
        b.edit(at: 30) { $0.iCloudSync.hiddenWords = true }
        b.sync(at: 40)
        #expect(b.config.redaction.customWords == ["Project Falcon"])
        b.edit(at: 50) { $0.redaction.customWords.append("Nightjar") }
        b.sync(at: 60)
        a.sync(at: 70)
        #expect(a.config.redaction.customWords == ["Project Falcon", "Nightjar"])
    }

    @Test("never (opt-in): recent questions stay on their Mac while the switch is off, as it is by default")
    func questionsOffByDefault() throws {
        let world = ICAWorld()
        let a = world.mac("A")
        let b = world.mac("B")
        a.ask("What is the capital of Burkina Faso", at: 1)
        b.ask("How tall is Kilimanjaro", at: 2)
        a.sync(at: 10)
        b.sync(at: 20)
        a.sync(at: 30)
        #expect(a.questions == ["What is the capital of Burkina Faso"])
        #expect(b.questions == ["How tall is Kilimanjaro"])
        #expect(!world.everything.contains("Burkina"))
        #expect(!world.everything.contains("Kilimanjaro"))
        #expect(!world.files.contains("questions.json"))
    }

    @Test("what (opt-in): recent questions sync between Macs that chose them; lists from two Macs are merged")
    func questionsMerge() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.iCloudSync.recentQuestions = true }
        let b = world.mac("B") { $0.iCloudSync.recentQuestions = true }
        a.ask("Q one", at: 1)
        a.sync(at: 10)
        b.sync(at: 20)
        #expect(b.questions == ["Q one"])
        a.ask("Q two", at: 30)
        b.ask("Q three", at: 40)
        a.sync(at: 50)
        b.sync(at: 60)
        a.sync(at: 70)
        #expect(Set(a.questions) == ["Q one", "Q two", "Q three"])
        #expect(Set(b.questions) == ["Q one", "Q two", "Q three"])
        #expect(b.history.entries.first { $0.question == "Q two" }?.answer == "Answer to: Q two")
        #expect(a.history.entries.first { $0.question == "Q three" }?.answer == "Answer to: Q three")
    }

    @Test("what (opt-in): clearing the recent questions on one Mac clears them on the others")
    func questionsClearPropagates() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.iCloudSync.recentQuestions = true }
        let b = world.mac("B") { $0.iCloudSync.recentQuestions = true }
        a.ask("Q one", at: 1)
        a.ask("Q two", at: 2)
        a.sync(at: 10)
        b.sync(at: 20)
        #expect(Set(b.questions) == ["Q one", "Q two"])
        a.clearQuestions(at: 30)
        a.sync(at: 40)
        b.sync(at: 50)
        a.sync(at: 60)
        #expect(b.questions.isEmpty)
        #expect(a.questions.isEmpty, "the cleared questions came back")
    }

    @Test("what (opt-in): a clear isn't undone by a question asked on another Mac before the clear reached it")
    func questionsClearNotUndone() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.iCloudSync.recentQuestions = true }
        let b = world.mac("B") { $0.iCloudSync.recentQuestions = true }
        a.ask("Q one", at: 1)
        a.ask("Q two", at: 2)
        a.sync(at: 10)
        b.sync(at: 20)
        #expect(Set(b.questions) == ["Q one", "Q two"])
        a.clearQuestions(at: 30)
        b.ask("Q three", at: 40)
        a.sync(at: 50)
        b.sync(at: 60)
        a.sync(at: 70)
        for mac in [a, b] {
            #expect(!mac.questions.contains("Q one") && !mac.questions.contains("Q two"),
                    "Mac \(mac.name): the cleared questions came back: \(mac.questions)")
            #expect(mac.questions.contains("Q three"), "Mac \(mac.name): the question asked after the clear was lost")
        }
    }

    @Test("files (opt-in): recent questions not downloaded yet never empty a Mac's own; merged once they're here")
    func questionsNotHereYet() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.iCloudSync.recentQuestions = true }
        let b = world.mac("B") { $0.iCloudSync.recentQuestions = true }
        a.ask("Q one", at: 1)
        a.sync(at: 10)
        b.sync(at: 20)
        a.ask("Q two", at: 30)
        a.sync(at: 40)
        let real = world.placeholder("questions.json")
        b.ask("Q three", at: 50)
        let report = b.sync(at: 60)
        #expect(report.outcome == .waiting)
        #expect(Set(b.questions) == ["Q one", "Q three"])
        world.download("questions.json", real)
        b.sync(at: 70)
        a.sync(at: 80)
        #expect(Set(b.questions) == ["Q one", "Q two", "Q three"])
        #expect(Set(a.questions) == ["Q one", "Q two", "Q three"])
    }

    @Test("never (opt-in): recent questions sync only while \"Remember recent questions\" is on")
    func questionsOnlyWhileRemembered() throws {
        // Not remembered: a list left from before doesn't go up.
        let world = ICAWorld()
        let a = world.mac("A") { $0.iCloudSync.recentQuestions = true; $0.rememberQuestions = false }
        a.ask("A leftover question", at: 1)
        a.sync(at: 10)
        #expect(!world.everything.contains("leftover"))
        // Nor do they come down to a Mac that doesn't remember them (its Settings switch off, so that stays so).
        let other = ICAWorld()
        let c = other.mac("C") { $0.iCloudSync.recentQuestions = true }
        c.ask("C's question", at: 1)
        c.sync(at: 10)
        let b = other.mac("B") { $0.iCloudSync.recentQuestions = true; $0.iCloudSync.settings = false; $0.rememberQuestions = false }
        b.sync(at: 20)
        #expect(b.questions.isEmpty)
    }

    // MARK: Merging

    @Test("merge: different keys edited on two Macs both survive; each entry keeps the Mac that set it")
    func differentKeysBothSurvive() throws {
        let (world, a, b) = ICA.pair()
        a.edit(at: 100) { $0.maxTokens = 1500 }
        b.edit(at: 110) { $0.typeOut = true }
        a.sync(at: 200)
        b.sync(at: 210)
        a.sync(at: 220)
        for mac in [a, b] {
            #expect(mac.config.maxTokens == 1500, "Mac \(mac.name)")
            #expect(mac.config.typeOut == true, "Mac \(mac.name)")
        }
        let by = (world.entry("maxTokens")?["by"] as? String, world.entry("typeOut")?["by"] as? String)
        #expect(by.0 != nil && by.1 != nil && by.0 != by.1, "one Mac's write took over the other's entry")
    }

    @Test("merge: the same key edited on both Macs: the newer edit wins, whichever Mac syncs first", arguments: [true, false])
    func sameKeyNewerWins(newerSyncsFirst: Bool) throws {
        let (world, a, b) = ICA.pair()
        a.edit(at: 100) { $0.maxTokens = 1500 }
        b.edit(at: 150) { $0.maxTokens = 2500 }
        if newerSyncsFirst {
            b.sync(at: 200)
            a.sync(at: 210)
            b.sync(at: 220)
        } else {
            a.sync(at: 200)
            b.sync(at: 210)
            a.sync(at: 220)
        }
        #expect(a.config.maxTokens == 2500)
        #expect(b.config.maxTokens == 2500)
        #expect(ICA.canon(world.value("maxTokens")) == "2500")
    }

    @Test("merge: the same key changed at the same moment on two Macs: both end with the same value")
    func sameMomentConverges() throws {
        let (world, a, b) = ICA.pair()
        a.edit(at: 100) { $0.maxTokens = 1500 }
        b.edit(at: 100) { $0.maxTokens = 2500 }
        a.sync(at: 200)
        b.sync(at: 210)
        a.sync(at: 220)
        b.sync(at: 230)
        #expect(a.config.maxTokens == b.config.maxTokens)
        #expect(ICA.canon(world.value("maxTokens")) == String(a.config.maxTokens))
    }

    @Test("merge: two changes a fraction of a second apart: the later wins")
    func subSecondChanges() throws {
        let (_, a, b) = ICA.pair()
        a.edit(at: 100.2) { $0.maxTokens = 1500 }
        b.edit(at: 100.7) { $0.maxTokens = 2500 }
        b.sync(at: 200)
        a.sync(at: 210)
        b.sync(at: 220)
        #expect(a.config.maxTokens == 2500)
        #expect(b.config.maxTokens == 2500)
    }

    @Test("merge: a change is as new as the config file's change, not the sync that sends it")
    func stampedWhenTheFileChanged() throws {
        let (world, a, b) = ICA.pair()
        a.edit(at: 100) { $0.timeoutSeconds = 20 }
        b.edit(at: 500) { $0.timeoutSeconds = 45 }
        b.sync(at: 600)
        a.sync(at: 3600)  // A syncs an hour later: its change is still the older one
        b.sync(at: 3700)
        #expect(a.config.timeoutSeconds == 45)
        #expect(b.config.timeoutSeconds == 45)
        b.edit(at: 4000) { $0.typeOut = true }
        b.sync(at: 4100)
        let stamp = ICA.date(world.entry("typeOut")?["modified"])
        #expect(stamp.map { abs($0.timeIntervalSince(ICA.t(4000))) < 1 } == true, "stamped \(String(describing: stamp)), changed at \(ICA.t(4000))")
    }

    @Test("merge: a change is never stamped later than now, even when the file's time is ahead")
    func stampNeverInTheFuture() throws {
        let (world, a, b) = ICA.pair()
        a.edit(at: 100) { $0.maxTokens = 1500 }
        ICA.touch(a.configURL, ICA.t(100 + 86_400))  // written by a clock a day ahead
        a.sync(at: 200)
        let stamp = ICA.date(world.entry("maxTokens")?["modified"])
        #expect(stamp != nil)
        #expect(stamp.map { $0 <= ICA.t(200) } == true, "stamped \(String(describing: stamp)), now is \(ICA.t(200))")
        // So a later change on another Mac still wins.
        b.edit(at: 300) { $0.maxTokens = 2500 }
        b.sync(at: 400)
        a.sync(at: 500)
        #expect(a.config.maxTokens == 2500)
        #expect(b.config.maxTokens == 2500)
    }

    @Test("merge: a stamp from the future is accepted; a later change here is stamped just after it, and wins")
    func futureStampAccepted() throws {
        let (world, a, b) = ICA.pair()
        let future = ICA.t(10 * 365 * 86_400)
        world.put(["maxTokens": 1800], at: future, by: "MacWithAClockAhead")
        a.sync(at: 100)
        b.sync(at: 110)
        #expect(a.config.maxTokens == 1800)
        #expect(b.config.maxTokens == 1800)
        a.edit(at: 200) { $0.maxTokens = 2500 }
        a.sync(at: 210)
        let stamp = ICA.date(world.entry("maxTokens")?["modified"])
        #expect(stamp.map { $0 > future && $0 <= future.addingTimeInterval(1) } == true,
                "stamped \(String(describing: stamp)); the value it replaced was stamped \(future)")
        b.sync(at: 220)
        #expect(b.config.maxTokens == 2500)
        // And a change after that, on the other Mac, wins in turn.
        b.edit(at: 300) { $0.maxTokens = 3000 }
        b.sync(at: 310)
        a.sync(at: 320)
        #expect(a.config.maxTokens == 3000)
        #expect(b.config.maxTokens == 3000)
    }

    @Test("merge: settings.json holds each key with its value, an ISO 8601 time and the Mac that set it")
    func entryFormat() throws {
        let (world, a, b) = ICA.pair()
        a.edit(at: 100) { $0.maxTokens = 1500 }
        a.sync(at: 200)
        b.edit(at: 300) { $0.typeOut = true }
        b.sync(at: 400)
        let maxTokens = try #require(world.entry("maxTokens"))
        let typeOut = try #require(world.entry("typeOut"))
        #expect(ICA.canon(maxTokens["value"]) == "1500")
        #expect(ICA.canon(typeOut["value"]) == "true")
        #expect(ICA.date(maxTokens["modified"]).map { abs($0.timeIntervalSince(ICA.t(100))) < 1 } == true)
        #expect(ICA.date(typeOut["modified"]).map { abs($0.timeIntervalSince(ICA.t(300))) < 1 } == true)
        #expect((maxTokens["by"] as? String)?.isEmpty == false)
        #expect((typeOut["by"] as? String)?.isEmpty == false)
        #expect(maxTokens["by"] as? String != typeOut["by"] as? String)
    }

    @Test("merge: app settings merge per app; the same app edited on both, the newer wins")
    func appProfilesMergePerApp() throws {
        let (_, a, b) = ICA.pair()
        a.edit(at: 100) { $0.appProfiles["com.apple.mail"] = AppProfile(inputLanguage: .chinese) }
        b.edit(at: 110) { $0.appProfiles["com.tinyspeck.slackmacgap"] = AppProfile(typeOut: true) }
        a.sync(at: 200)
        b.sync(at: 210)
        a.sync(at: 220)
        for mac in [a, b] {
            #expect(mac.config.appProfiles["com.apple.mail"]?.inputLanguage == .chinese, "Mac \(mac.name)")
            #expect(mac.config.appProfiles["com.tinyspeck.slackmacgap"]?.typeOut == true, "Mac \(mac.name)")
        }
        a.edit(at: 300) { $0.appProfiles["com.apple.mail"]?.rewriteStyles = ["正式"] }
        b.edit(at: 310) { $0.appProfiles["com.apple.mail"]?.noAI = true }
        b.sync(at: 400)
        a.sync(at: 410)
        b.sync(at: 420)
        for mac in [a, b] {
            let mail = mac.config.appProfiles["com.apple.mail"]
            #expect(mail?.noAI == true, "Mac \(mac.name)")
            #expect(mail?.rewriteStyles == nil, "Mac \(mac.name): the older edit of the app survived")
            #expect(mac.config.appProfiles["com.tinyspeck.slackmacgap"]?.typeOut == true, "Mac \(mac.name)")
        }
    }

    @Test("merge: a key both Macs set for the first time since they synced: the newer wins",
          arguments: ["questionRounds", "appProfile", "jargon"])
    func newKeyOnBothNewerWins(what: String) throws {
        let (_, a, b) = ICA.pair()
        func set(_ mac: ICAMac, _ n: Int, at seconds: TimeInterval) {
            switch what {
            case "questionRounds": mac.edit(at: seconds) { $0.questionRounds = n }
            case "appProfile": mac.edit(at: seconds) { $0.appProfiles["com.apple.mail"] = AppProfile(rewriteStyles: n == 3 ? ["简洁"] : ["正式"]) }
            default: mac.writeJargon("list \(n)\n", at: seconds)
            }
        }
        func value(_ mac: ICAMac) -> String {
            switch what {
            case "questionRounds": return "\(mac.config.questionRounds)"
            case "appProfile": return mac.config.appProfiles["com.apple.mail"]?.rewriteStyles == ["简洁"] ? "3" : "8"
            default: return mac.jargon == "list 3\n" ? "3" : mac.jargon == "list 8\n" ? "8" : "\(mac.jargon ?? "none")"
            }
        }
        set(a, 3, at: 100)
        set(b, 8, at: 150)  // newer
        a.sync(at: 200)
        b.sync(at: 210)
        a.sync(at: 220)
        #expect(value(a) == "8", "A")
        #expect(value(b) == "8", "B: its newer change was lost")
    }

    @Test("merge: one app is one app whatever the case of its bundle id: both Macs end with one, the same")
    func appBundleIDCase() throws {
        let (_, a, b) = ICA.pair()
        a.edit(at: 100) { $0.appProfiles["com.apple.Notes"] = AppProfile(typeOut: true) }
        b.edit(at: 110) { $0.appProfiles["com.apple.notes"] = AppProfile(noAI: true) }
        a.sync(at: 200)
        b.sync(at: 210)
        a.sync(at: 220)
        b.sync(at: 230)
        let notes = [a, b].map { mac in mac.config.appProfiles.filter { $0.key.lowercased() == "com.apple.notes" } }
        #expect(notes[0].count == 1, "A: \(notes[0].keys.sorted())")
        #expect(notes[1].count == 1, "B: \(notes[1].keys.sorted())")
        #expect(notes[0].first?.value == notes[1].first?.value)
    }

    @Test("merge: lists are whole values (custom commands, styles): the newer list wins as it is")
    func listsAreWholeValues() throws {
        let (_, a, b) = ICA.pair { c in
            c.customCommands = [ICA.command("alpha"), ICA.command("beta")]
            c.rewriteStyles = ["润色", "简洁", "正式"]
        }
        #expect(b.config.customCommands.map(\.name) == ["alpha", "beta"])
        a.edit(at: 100) { c in
            c.customCommands.append(ICA.command("gamma"))
            c.rewriteStyles.append("口语")
        }
        b.edit(at: 110) { c in
            c.customCommands.removeFirst()
            c.rewriteStyles = ["正式"]
        }
        a.sync(at: 200)
        b.sync(at: 210)
        a.sync(at: 220)
        for mac in [a, b] {
            #expect(mac.config.customCommands.map(\.name) == ["beta"], "Mac \(mac.name)")
            #expect(mac.config.rewriteStyles == ["正式"], "Mac \(mac.name)")
        }
    }

    @Test("merge: an app's settings deleted against an edit: whichever is newer wins", arguments: [true, false])
    func deletionAgainstEdit(deletionIsNewer: Bool) throws {
        let (world, a, b) = ICA.pair { $0.appProfiles["com.apple.mail"] = AppProfile(inputLanguage: .chinese) }
        #expect(b.config.appProfiles["com.apple.mail"] != nil)
        let (deleteAt, editAt): (TimeInterval, TimeInterval) = deletionIsNewer ? (150, 100) : (100, 150)
        a.edit(at: deleteAt) { $0.appProfiles["com.apple.mail"] = nil }
        b.edit(at: editAt) { $0.appProfiles["com.apple.mail"] = AppProfile(inputLanguage: .chinese, noAI: true) }
        a.sync(at: 200)
        b.sync(at: 210)
        a.sync(at: 220)
        for mac in [a, b] {
            if deletionIsNewer {
                #expect(mac.config.appProfiles["com.apple.mail"] == nil, "Mac \(mac.name): the deleted app came back")
            } else {
                #expect(mac.config.appProfiles["com.apple.mail"]?.noAI == true, "Mac \(mac.name): the later edit was lost")
            }
        }
        if deletionIsNewer {
            // The deletion is a stamped entry, not a gap (another Mac's old copy can't bring it back).
            let tombstone = try #require(world.settings.first { $0.key.lowercased() == "appprofiles.com.apple.mail" }?.value as? [String: Any])
            #expect(tombstone["modified"] != nil)
            #expect(tombstone["by"] != nil)
            #expect(tombstone["value"] == nil || tombstone["value"] is NSNull)
            let c = world.mac("C", at: 300) { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: true) }
            c.sync(at: 310)
            a.sync(at: 320)
            #expect(a.config.appProfiles["com.apple.mail"] == nil, "a joining Mac's copy brought the deleted app back")
        }
    }

    @Test("merge: a setting put back to its default (left out of the file) is put back on the other Mac too")
    func backToDefaultSyncs() throws {
        let (_, a, b) = ICA.pair { $0.questionRounds = 8; $0.questionContinueIn = [.chatgpt] }
        #expect(b.config.questionRounds == 8)
        #expect(b.config.questionContinueIn == [.chatgpt])
        a.edit(at: 100) { $0.questionRounds = QuestionChat.defaultRounds; $0.questionContinueIn = nil }
        #expect(a.file["questionRounds"] == nil)
        a.sync(at: 200)
        b.sync(at: 210)
        #expect(b.config.questionRounds == QuestionChat.defaultRounds)
        #expect(b.config.questionContinueIn == nil)
    }

    // MARK: Joining

    @Test("join: a fresh Mac turning sync on takes iCloud's settings; its defaults never overwrite them")
    func freshMacTakesICloud() throws {
        let world = ICAWorld()
        let a = world.mac("A") { c in
            c.maxTokens = 2000
            c.typeOut = true
            c.setOrder([OutputLanguage("ja")])
            c.rewriteStyles = ["口语"]
            c.appProfiles["com.apple.mail"] = AppProfile(inputLanguage: .chinese)
            c.customCommands = [ICA.command("alpha")]
            c.redaction.enabled = true
        }
        a.writeJargon("A's jargon\n", at: 1)
        a.sync(at: 10)
        let mine = a.config
        // B's settings file is newer than anything A wrote, and all defaults.
        let b = world.mac("B", at: 3000)
        let report = b.sync(at: 3600)
        #expect(report.outcome == .synced)
        a.sync(at: 3700)
        #expect(a.config == mine, "a fresh Mac's defaults overwrote A's settings")
        #expect(a.jargon == "A's jargon\n")
        let bc = b.config
        #expect(bc.maxTokens == 2000)
        #expect(bc.typeOut == true)
        #expect(bc.outputLanguage == OutputLanguage("ja"))
        #expect(bc.rewriteStyles == ["口语"])
        #expect(bc.appProfiles["com.apple.mail"]?.inputLanguage == .chinese)
        #expect(bc.customCommands.map(\.name) == ["alpha"])
        #expect(bc.redaction.enabled == true)
        #expect(b.jargon == "A's jargon\n")
        #expect(ICA.canon(world.value("maxTokens")) == "2000")
    }

    @Test("join: a Mac turning sync on fills only what iCloud lacks")
    func joiningFillsWhatICloudLacks() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.maxTokens = 2000; $0.appProfiles["com.apple.mail"] = AppProfile(inputLanguage: .chinese) }
        a.sync(at: 10)
        let b = world.mac("B", at: 3000) { c in
            c.maxTokens = 3000
            c.questionRounds = 8
            c.appProfiles["com.apple.Notes"] = AppProfile(typeOut: true)
        }
        b.writeJargon("B's jargon\n", at: 3000)
        b.sync(at: 3600)
        a.sync(at: 3700)
        #expect(b.config.maxTokens == 2000, "iCloud had it")
        #expect(a.config.maxTokens == 2000)
        #expect(a.config.questionRounds == 8, "iCloud lacked it")
        #expect(a.config.appProfiles["com.apple.Notes"]?.typeOut == true, "iCloud lacked it")
        #expect(b.config.appProfiles["com.apple.mail"]?.inputLanguage == .chinese)
        #expect(b.config.appProfiles["com.apple.Notes"]?.typeOut == true)
        #expect(a.jargon == "B's jargon\n", "iCloud lacked a jargon list")
    }

    @Test("join: a category turned on for the first time: custom commands and the jargon list merge with iCloud's")
    func categoryTurnedOnLater() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha")] }
        a.writeJargon("A list\n", at: 1)
        a.sync(at: 10)
        let b = world.mac("B") { $0.iCloudSync.jargon = false; $0.customCommands = [ICA.command("bravo")] }
        b.writeJargon("B list\n", at: 2)
        b.sync(at: 20)
        a.sync(at: 30)
        #expect(b.config.customCommands.map(\.name) == ["bravo"], "B's switch is off")
        #expect(b.jargon == "B list\n")
        #expect(a.config.customCommands.map(\.name) == ["alpha"])
        #expect(a.jargon == "A list\n")
        b.edit(at: 100) { $0.iCloudSync.jargon = true }
        b.sync(at: 110)
        a.sync(at: 120)
        #expect(Set(b.config.customCommands.map(\.name)) == ["alpha", "bravo"])
        #expect(Set(ICA.lines(b.jargon)) == ["A list", "B list"])
        #expect(Set(a.config.customCommands.map(\.name)) == ["alpha", "bravo"], "the merge didn't reach A")
        #expect(Set(ICA.lines(a.jargon)) == ["A list", "B list"], "the merge didn't reach A")
    }

    @Test("join: recent questions merge on a first join: both lists, newest first, a question once", arguments: [true, false])
    func questionsMergeOnJoin(firstSync: Bool) throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.iCloudSync.recentQuestions = true }
        a.ask("What is X?", at: 1)
        a.ask("A only", at: 3)
        a.sync(at: 10)
        let b = ICA.join(world, firstSync: firstSync, \.recentQuestions, { _ in }) { b in
            b.ask("what  is   X?", at: 2)
            b.ask("B only", at: 4)
        }
        a.sync(at: 50)
        for mac in [a, b] {
            #expect(mac.questions.map(ICA.normalized) == ["b only", "a only", "what is x?"], "Mac \(mac.name): \(mac.questions)")
        }
    }

    @Test("join: hidden words merge on a first join: a Mac never stops hiding a word it hid", arguments: [true, false])
    func hiddenWordsMergeOnJoin(firstSync: Bool) throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.iCloudSync.hiddenWords = true; $0.redaction.customWords = ["Falcon", "Shared"] }
        a.sync(at: 10)
        let b = ICA.join(world, firstSync: firstSync, \.hiddenWords) { $0.redaction.customWords = ["Nightjar", "Shared"] }
        a.sync(at: 50)
        for mac in [a, b] {
            let words = mac.config.redaction.customWords
            #expect(Set(words) == ["Falcon", "Shared", "Nightjar"], "Mac \(mac.name): \(words)")
            #expect(words.count == 3, "Mac \(mac.name): \(words)")
        }
    }

    @Test("join: custom commands merge by name on a first join; on a clash iCloud's wins", arguments: [true, false])
    func commandsMergeOnJoin(firstSync: Bool) throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha"), ICA.command("beta")] }
        a.sync(at: 10)
        let b = ICA.join(world, firstSync: firstSync, \.jargon) { c in
            c.customCommands = [CustomCommand(name: "alpha", type: .prompt, prompt: "B's own alpha"), ICA.command("gamma")]
        }
        a.sync(at: 50)
        for mac in [a, b] {
            let commands = mac.config.customCommands
            #expect(commands.map(\.name).sorted() == ["alpha", "beta", "gamma"], "Mac \(mac.name): \(commands.map(\.name))")
            #expect(commands.first { $0.name == "alpha" }?.prompt == ICA.command("alpha").prompt, "Mac \(mac.name): iCloud's alpha lost")
        }
    }

    @Test("join: the jargon list merges on a first join: the lines of both, each once", arguments: [true, false])
    func jargonMergesOnJoin(firstSync: Bool) throws {
        let world = ICAWorld()
        let a = world.mac("A")
        a.writeJargon("赋能 = enable\n抓手 = lever\n", at: 1)
        a.sync(at: 10)
        let b = ICA.join(world, firstSync: firstSync, \.jargon, { _ in }) { b in
            b.writeJargon("抓手 = lever\n闭环 = close the loop\n", at: 2)
        }
        a.sync(at: 50)
        for mac in [a, b] {
            let lines = ICA.lines(mac.jargon)
            #expect(Set(lines) == ["赋能 = enable", "抓手 = lever", "闭环 = close the loop"], "Mac \(mac.name): \(lines)")
            #expect(lines.count == 3, "Mac \(mac.name): \(lines)")
        }
    }

    // MARK: Versions

    @Test("versions: a key this version doesn't know is kept in settings.json byte for byte, and ignored here")
    func unknownKeyKeptByteForByte() throws {
        let world = ICAWorld()
        let futureValue = #"{"by":"MacZ-0.9","modified":"2026-10-16T09:00:00Z","value":{"levels":[1,2.50,3e2],"mode":"turbo"}}"#
        let text = "{\n  \"futureSetting\" :   " + futureValue + ",\n"
            + "  \"maxTokens\": {\"value\": 1800, \"modified\": \"2026-10-16T09:00:00Z\", \"by\": \"MacZ-0.9\"}\n}\n"
        world.write("settings.json", Data(text.utf8))
        let b = world.mac("B")
        let first = b.sync(at: 10)
        #expect(b.config.maxTokens == 1800)
        b.edit(at: 100) { $0.typeOut = true; $0.maxTokens = 1900 }
        let second = b.sync(at: 200)
        #expect(world.settingsText.contains(futureValue), "the newer version's entry was rewritten:\n\(world.settingsText)")
        #expect(ICA.canon(world.value("maxTokens")) == "1900")
        #expect(ICA.canon(world.value("typeOut")) == "true")
        #expect(b.file["futureSetting"] == nil)
        #expect(!b.configText.contains("turbo"))
        #expect(!first.applied.contains("futureSetting") && !second.applied.contains("futureSetting"))
    }

    @Test("versions: config.json keeps its own keys this version doesn't know when values from iCloud are written")
    func localUnknownKeysKept() throws {
        let (_, a, b) = ICA.pair()
        b.editFile(at: 50) { file in
            file["futureLocal"] = ["kept": [1, 2, 3], "note": "from 0.9"]
            var openai = file["openai"] as? [String: Any] ?? [:]
            openai["futureField"] = "x"
            file["openai"] = openai
        }
        a.edit(at: 100) { $0.maxTokens = 1700; $0.openai.baseURL = "https://openrouter.ai/api/v1" }
        a.sync(at: 200)
        b.sync(at: 210)
        #expect(b.config.maxTokens == 1700)
        #expect(b.config.openai.baseURL == "https://openrouter.ai/api/v1")
        #expect(ICA.canon(b.file["futureLocal"]) == ICA.canon(["kept": [1, 2, 3], "note": "from 0.9"]))
        #expect((b.file["openai"] as? [String: Any])?["futureField"] as? String == "x")
    }

    @Test("versions: config.json isn't written when nothing from iCloud changes it")
    func configUntouchedWhenNothingChanges() throws {
        let (_, a, b) = ICA.pair()
        a.edit(at: 100) { $0.typeOut = true }
        a.sync(at: 110)
        b.sync(at: 120)
        #expect(b.config.typeOut == true)
        let data = b.configData, mtime = ICA.mtime(b.configURL)
        b.sync(at: 200)
        a.sync(at: 210)
        b.sync(at: 220)
        #expect(b.configData == data)
        #expect(ICA.mtime(b.configURL) == mtime)
    }

    @Test("versions: names from a newer version are left out of lists and refused as single values")
    func newerNames() throws {
        let world = ICAWorld()
        let b = world.mac("B")
        world.put([
            "inputLanguages": ["zh", "tlh", "en"],
            "fuzzyPinyin": ["z-zh", "zh-z-future"],
            "questionContinueIn": ["chatgpt", "futureChat"],
            "candidateLayout": "spiral",
            "provider": "futureai",
            "uiLanguage": "tlh",
            "actionKey": "hyperKey",
            "appProfiles.com.apple.mail": ["inputLanguage": "tlh", "typeOut": true],
        ], at: ICA.t(5))
        let report = b.sync(at: 10)
        let bc = b.config
        #expect(bc.inputLanguages == [.chinese, .english])
        #expect(bc.fuzzyPinyin == ["z-zh"])
        #expect(bc.questionContinueIn == [.chatgpt])
        #expect(bc.candidateLayout == Config.default.candidateLayout)
        #expect(bc.provider == Config.default.provider)
        #expect(bc.uiLanguage == nil)
        #expect(bc.actionKey == Config.default.actionKey)
        #expect(bc.appProfiles["com.apple.mail"] == nil)
        for key in ["candidateLayout", "provider", "uiLanguage", "actionKey", "appProfiles.com.apple.mail"] {
            #expect(report.refused[key] != nil, "\(key) wasn't refused")
        }
        for name in ["tlh", "zh-z-future", "futureChat", "spiral", "futureai", "hyperKey"] {
            #expect(!b.configText.contains(name), "\(name) reached config.json")
        }
    }

    @Test("versions: a rewrite style from a newer version is left out of the list")
    func newerStyleLeftOut() throws {
        let world = ICAWorld()
        let b = world.mac("B")
        world.put(["rewriteStyles": ["正式", "FutureStyle"]], at: ICA.t(5))
        b.sync(at: 10)
        #expect(b.config.rewriteStyles == ["正式"])
        #expect(!b.configText.contains("FutureStyle"))
    }

    // MARK: Files: placeholders, missing, corrupt

    @Test("files: a settings.json not downloaded yet is never empty settings for a Mac turning sync on")
    func placeholderForAJoiningMac() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.maxTokens = 2000; $0.typeOut = true }
        a.sync(at: 10)
        let real = world.placeholder("settings.json")
        let b = world.mac("B", at: 1000)
        let before = b.configData
        let report = b.sync(at: 1100)
        #expect(report.outcome == .waiting)
        #expect(report.applied.isEmpty)
        #expect(!ICA.exists(world.settingsURL), "settings.json was written over a file not downloaded yet")
        #expect(ICA.exists(world.url(".settings.json.icloud")))
        #expect(b.configData == before)
        world.download("settings.json", real)
        #expect(b.sync(at: 1200).outcome == .synced)
        a.sync(at: 1300)
        #expect(b.config.maxTokens == 2000)
        #expect(b.config.typeOut == true)
        #expect(a.config.maxTokens == 2000, "B's defaults went over A's settings")
        #expect(a.config.typeOut == true)
    }

    @Test("files: while settings.json is a placeholder, a synced Mac changes nothing; its own change goes out later")
    func placeholderForASyncedMac() throws {
        let (world, a, b) = ICA.pair()
        b.edit(at: 100) { $0.typeOut = true }
        b.sync(at: 110)
        let real = world.placeholder("settings.json")
        a.edit(at: 200) { $0.maxTokens = 1600 }
        let report = a.sync(at: 210)
        #expect(report.outcome == .waiting)
        #expect(!ICA.exists(world.settingsURL))
        #expect(a.config.maxTokens == 1600)
        #expect(a.config.typeOut == false)
        world.download("settings.json", real)
        a.sync(at: 300)
        b.sync(at: 310)
        #expect(a.config.typeOut == true)
        #expect(b.config.maxTokens == 1600)
    }

    @Test("files: a missing settings.json never resets a Mac's settings")
    func missingSettingsNeverResets() throws {
        let (world, a, b) = ICA.pair { c in
            c.maxTokens = 2000
            c.appProfiles["com.apple.mail"] = AppProfile(inputLanguage: .chinese)
            c.customCommands = [ICA.command("alpha")]
            c.questionRounds = 8
        }
        let aBefore = a.config, bBefore = b.config
        try FileManager.default.removeItem(at: world.settingsURL)
        let ra = a.sync(at: 100)
        let rb = b.sync(at: 110)
        a.sync(at: 120)
        #expect(a.config == aBefore)
        #expect(b.config == bBefore)
        #expect(ra.applied.isEmpty)
        #expect(rb.applied.isEmpty)
    }

    @Test("files: after settings.json is lost (unreadable, or gone), a fresh Mac turning sync on still never overwrites the others' settings with its defaults",
          arguments: [true, false])
    func lostSettingsThenFreshMac(corrupt: Bool) throws {
        let (world, a, b) = ICA.pair { c in
            c.maxTokens = 2000
            c.typeOut = true
            c.appProfiles["com.apple.mail"] = AppProfile(inputLanguage: .chinese)
        }
        let aBefore = a.config, bBefore = b.config
        if corrupt {
            world.write("settings.json", Data("{ truncated".utf8))
        } else {
            try FileManager.default.removeItem(at: world.settingsURL)
        }
        let c = world.mac("C", at: 1000)
        c.sync(at: 1100)
        a.sync(at: 1200)
        b.sync(at: 1300)
        c.sync(at: 1400)
        #expect(a.config == aBefore, "a fresh Mac's defaults overwrote A's settings")
        #expect(b.config == bBefore, "a fresh Mac's defaults overwrote B's settings")
        #expect(c.config.maxTokens == 2000)
        #expect(c.config.typeOut == true)
    }

    @Test("files: a jargon list not downloaded yet (or missing) never empties the Mac's own", arguments: [true, false])
    func jargonNotHereYet(placeholder: Bool) throws {
        let (world, a, b) = ICA.pair()
        a.writeJargon("v1\n", at: 50)
        a.sync(at: 60)
        b.sync(at: 70)
        #expect(b.jargon == "v1\n")
        a.writeJargon("v2, newer\n", at: 100)
        a.sync(at: 110)
        let real: Data
        if placeholder {
            real = world.placeholder("jargon.txt")
        } else {
            real = try #require(world.snapshot["jargon.txt"])
            try FileManager.default.removeItem(at: world.url("jargon.txt"))
        }
        a.edit(at: 115) { $0.typeOut = true }
        a.sync(at: 116)
        let report = b.sync(at: 120)
        #expect(b.jargon == "v1\n")
        #expect(b.config.typeOut == true, "the settings waited for the jargon list")
        if placeholder { #expect(report.outcome == .waiting) }
        world.download("jargon.txt", real)
        b.sync(at: 130)
        #expect(b.jargon == "v2, newer\n")
    }

    @Test("files: a Mac turning sync on while iCloud's jargon list is still downloading never puts its own over it")
    func joiningWhileJargonDownloads() throws {
        let world = ICAWorld()
        let a = world.mac("A")
        a.writeJargon("A's list\n", at: 1)
        a.sync(at: 10)
        let real = world.placeholder("jargon.txt")
        let b = world.mac("B", at: 1000)
        b.writeJargon("B's own list\n", at: 1000)
        b.sync(at: 1100)
        #expect(b.jargon == "B's own list\n")
        #expect(!ICA.exists(world.url("jargon.txt")), "B's list went up over iCloud's")
        world.download("jargon.txt", real)
        b.sync(at: 1200)
        a.sync(at: 1300)
        #expect(Set(ICA.lines(b.jargon)) == ["A's list", "B's own list"])
        #expect(Set(ICA.lines(a.jargon)) == ["A's list", "B's own list"])
    }

    @Test("files: an unreadable settings.json is set aside, never overwritten",
          arguments: ["{\"maxTokens\": {\"value\": 2000, \"modi", "[1, 2, 3]", "\u{0}\u{1}binary\u{2}", "", "\"just a string\""])
    func corruptSetAside(text: String) throws {
        let (world, a, b) = ICA.pair { $0.maxTokens = 2000 }
        let corrupt = Data(text.utf8)
        world.write("settings.json", corrupt)
        let aBefore = a.config
        let report = a.sync(at: 100)
        #expect(report.setAside != nil)
        #expect(a.config == aBefore)
        let kept = world.snapshot.filter { $0.key != "settings.json" && $0.value == corrupt }
        #expect(kept.count == 1, "the unreadable file wasn't kept as it was: \(world.files.sorted())")
        // A new settings.json works for both Macs afterwards; the copy set aside stays.
        a.edit(at: 200) { $0.typeOut = true }
        a.sync(at: 210)
        b.sync(at: 220)
        #expect(b.config.typeOut == true)
        #expect(b.config.maxTokens == 2000)
        #expect(world.snapshot.filter { $0.key != "settings.json" && $0.value == corrupt }.count == 1)
    }

    @Test("files: two unreadable files in a row are both kept")
    func twoCorruptFilesBothKept() throws {
        let (world, a, _) = ICA.pair()
        let first = Data("{ broken one".utf8), second = Data("{ broken two".utf8)
        world.write("settings.json", first)
        a.sync(at: 100)
        world.write("settings.json", second)
        a.sync(at: 100)  // the same second
        let values = Set(world.snapshot.values)
        #expect(values.contains(first))
        #expect(values.contains(second))
    }

    // MARK: Checking incoming values

    @Test("valid: a provider without a key on this Mac is refused for that key, logged, and taken once a key is there")
    func providerWithoutKey() throws {
        let (world, a, b) = ICA.pair()
        b.keys = []
        a.edit(at: 100) { $0.provider = .anthropic; $0.maxTokens = 1500 }
        a.sync(at: 110)
        let first = b.sync(at: 120)
        #expect(b.config.provider == .bedrock)
        #expect(b.config.maxTokens == 1500, "a refused key stopped the others")
        #expect(first.rejected["provider"] == .noKey)
        #expect(b.file["provider"] as? String == "bedrock")
        let second = b.sync(at: 130)
        #expect(second.refused["provider"] != nil)
        #expect(b.config.provider == .bedrock)
        // iCloud's value stays for the other Macs.
        #expect(world.value("provider") as? String == "anthropic")
        b.edit(at: 140) { $0.typeOut = true }
        b.sync(at: 150)
        a.sync(at: 160)
        #expect(a.config.provider == .anthropic, "a Mac that refused the value put its own over it")
        // The key saved in Settings: the next sync takes it.
        b.keys = [.anthropic]
        let third = b.sync(at: 200)
        #expect(b.config.provider == .anthropic)
        #expect(third.refused["provider"] == nil)
    }

    @Test("valid: a provider Settings doesn't offer on this Mac (Apple's model without Apple Intelligence) is refused")
    func providerNotOffered() throws {
        let (_, a, b) = ICA.pair()
        b.offered = Provider.allCases.filter { $0 != .apple }
        a.edit(at: 100) { $0.provider = .apple }
        a.sync(at: 110)
        let report = b.sync(at: 120)
        #expect(b.config.provider == .bedrock)
        #expect(report.refused["provider"] != nil)
    }

    @Test("valid: an AWS profile this Mac doesn't have is refused, and taken once it is there")
    func awsProfileMissing() throws {
        let (_, a, b) = ICA.pair()
        b.awsProfiles = ["default"]
        a.edit(at: 100) { $0.awsProfile = "work" }
        a.sync(at: 110)
        let report = b.sync(at: 120)
        #expect(b.config.awsProfile == "default")
        #expect(report.rejected["awsProfile"] == .noProfile)
        b.awsProfiles = ["default", "work"]
        b.sync(at: 200)
        #expect(b.config.awsProfile == "work")
    }

    @Test("valid: a value Settings wouldn't save never reaches config.json; the other keys still come in", arguments: ICA.badValues)
    func badValuesRefused(bad: ICABadValue) throws {
        let world = ICAWorld()
        let b = world.mac("B")
        b.sync(at: 1)
        let before = b.config
        world.put([bad.key: ICA.json(bad.json), "typeOut": true], at: ICA.t(100))
        let report = b.sync(at: 200)
        var expected = before
        expected.typeOut = true
        #expect(b.config == expected, "\(bad.key) = \(bad.json) reached config.json")
        #expect(report.refused[bad.key] != nil)
    }

    // MARK: Off, and Remove from iCloud

    @Test("off: turning sync off stops it and leaves the local data and the iCloud folder as they are")
    func turningOffLeavesData() throws {
        let (world, a, b) = ICA.pair { $0.maxTokens = 2000 }
        a.writeJargon("A list\n", at: 5)
        a.sync(at: 6)
        b.sync(at: 7)
        a.edit(at: 100) { $0.iCloudSync.enabled = false }
        let aData = a.configData
        #expect(a.sync(at: 110).outcome == .off)
        b.edit(at: 200) { $0.maxTokens = 3000 }
        b.writeJargon("B list\n", at: 200)
        b.sync(at: 210)
        let iCloud = world.snapshot
        #expect(a.sync(at: 300).outcome == .off)
        #expect(a.configData == aData)
        #expect(a.jargon == "A list\n")
        #expect(world.snapshot == iCloud)
        #expect(ICA.exists(world.settingsURL))
        // A change on A while it's off doesn't go out.
        a.edit(at: 400) { $0.typeOut = true }
        a.sync(at: 410)
        b.sync(at: 420)
        #expect(b.config.typeOut == false)
        // On again: B's changes come in, and A's change made while off goes out.
        a.edit(at: 500) { $0.iCloudSync.enabled = true }
        a.sync(at: 510)
        b.sync(at: 520)
        #expect(a.config.maxTokens == 3000)
        #expect(a.jargon == "B list\n")
        #expect(b.config.typeOut == true)
    }

    @Test("off: turned back on, a key changed both here (while off) and in iCloud takes iCloud's value, whichever change is newer",
          arguments: [false, true])
    func rejoinBothChangedICloudWins(offEditIsNewer: Bool) throws {
        let (world, a, b) = ICA.pair()
        a.edit(at: 100) { $0.iCloudSync.enabled = false }
        a.sync(at: 110)
        let (aAt, bAt): (TimeInterval, TimeInterval) = offEditIsNewer ? (300, 200) : (200, 300)
        a.edit(at: aAt) { $0.maxTokens = 1500 }
        b.edit(at: bAt) { $0.maxTokens = 2500 }
        b.sync(at: 310)
        a.edit(at: 400) { $0.iCloudSync.enabled = true }
        a.sync(at: 410)
        b.sync(at: 420)
        #expect(a.config.maxTokens == 2500)
        #expect(b.config.maxTokens == 2500, "the change A made while off went over iCloud's")
        #expect(ICA.canon(world.value("maxTokens")) == "2500")
    }

    @Test("off: turned back on, a key only this Mac changed while off goes up, stamped when sync was turned back on")
    func rejoinOnlyHereGoesUp() throws {
        let (world, a, b) = ICA.pair()
        a.edit(at: 100) { $0.iCloudSync.enabled = false }
        a.sync(at: 110)
        a.edit(at: 200) { $0.typeOut = true }
        b.edit(at: 300) { $0.maxTokens = 2500 }
        b.sync(at: 310)
        a.edit(at: 400) { $0.iCloudSync.enabled = true }
        a.sync(at: 410)
        b.sync(at: 420)
        #expect(a.config.typeOut == true)
        #expect(b.config.typeOut == true)
        #expect(a.config.maxTokens == 2500, "what iCloud changed meanwhile didn't come in")
        let stamp = ICA.date(world.entry("typeOut")?["modified"])
        #expect(stamp.map { $0 >= ICA.t(399) && $0 <= ICA.t(410) } == true,
                "stamped \(String(describing: stamp)): changed at \(ICA.t(200)), sync back on at \(ICA.t(400))")
    }

    @Test("off: Remove from iCloud moves the folder to the Trash, and this Mac joins again as one that never synced")
    func removeFromICloud() throws {
        let name = "AllInOneIME-ica-\(UUID().uuidString)"
        let world = ICAWorld(folderName: name)
        let a = world.mac("A")
        let b = world.mac("B")
        a.sync(at: 1)
        b.sync(at: 2)
        a.edit(at: 100) { $0.maxTokens = 1500 }
        a.sync(at: 110)
        #expect(world.folder.exists)
        // Remove from iCloud… (Settings turns sync off on this Mac first).
        a.edit(at: 200) { $0.iCloudSync.enabled = false }
        let trash = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: world.folder.url, create: false)
        let trashed = trash.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: trashed) }
        try world.folder.remove()
        a.engine.forget()
        #expect(!ICA.exists(world.folder.url))
        #expect(ICA.exists(trashed), "the folder isn't in the Trash")
        #expect(ICA.exists(trashed.appendingPathComponent("settings.json")))
        #expect(a.config.maxTokens == 1500, "local data went with it")
        // B, still on, puts its settings up again (it never got A's 1500).
        b.sync(at: 300)
        #expect(ICA.canon(world.value("maxTokens")) == "1000")
        // A turned on again joins as a Mac that never synced: what iCloud has wins.
        a.edit(at: 400) { $0.iCloudSync.enabled = true }
        a.sync(at: 410)
        #expect(a.config.maxTokens == 1000)
    }

    // MARK: @config

    @Test("@config: turns sync through iCloud on and off, into config.json")
    func configTurnsSyncOnAndOff() throws {
        let world = ICAWorld()
        let mac = world.mac("A") { $0.iCloudSync.enabled = false }
        let env = AIConfig.Environment(iCloudDriveAvailable: { true })
        for on in [true, false] {
            let proposal = try AIConfig.parse(#"{"changes":[{"key":"iCloudSync.enabled","value":\#(on)}]}"#)
            guard case let .success(preview) = AIConfig.preview(proposal, config: mac.config, environment: env) else {
                Issue.record("@config couldn't turn sync \(on ? "on" : "off")")
                return
            }
            _ = try AIConfig.applying(preview.edits, at: mac.configURL)
            #expect(mac.config.iCloudSync.enabled == on)
            #expect(mac.config.iCloudSync.hiddenWords == false)
            #expect(mac.config.iCloudSync.recentQuestions == false)
        }
    }

    @Test("@config: can't turn sync on without iCloud Drive, and says how to turn it on")
    func configNeedsICloudDrive() throws {
        let config = Config.default
        let env = AIConfig.Environment(iCloudDriveAvailable: { false })
        let proposal = try AIConfig.parse(#"{"changes":[{"key":"iCloudSync.enabled","value":true}]}"#)
        let rows = AIConfig.check(proposal, config: config, environment: env).rows
        var applied = config
        _ = AIConfig.apply(rows.compactMap(\.edit), to: &applied)
        #expect(applied.iCloudSync.enabled == false)
        let text = rows.map { $0.text(chinese: false) }.joined(separator: "\n")
            + AIConfig.failureLine(.notAllowed, proposal: proposal, config: config, environment: env)
        #expect(text.contains("Turn on iCloud Drive in System Settings → Apple Account → iCloud"), "\(text)")
    }

    @Test("@config: can't turn on the hidden words or recent questions",
          arguments: [
              #"{"changes":[{"key":"iCloudSync.hiddenWords","value":true}]}"#,
              #"{"changes":[{"key":"iCloudSync.recentQuestions","value":true}]}"#,
              #"{"changes":[{"key":"iCloudSync","value":{"enabled":true,"hiddenWords":true,"recentQuestions":true}}]}"#,
              #"{"changes":[{"key":"iCloudSync.enabled","value":true},{"key":"iCloudSync.hiddenWords","value":true},{"key":"iCloudSync.recentQuestions","value":true}]}"#,
          ])
    func configCantChooseOptIns(answer: String) throws {
        let world = ICAWorld()
        let mac = world.mac("A") { $0.iCloudSync.enabled = false }
        let env = AIConfig.Environment(iCloudDriveAvailable: { true })
        guard let proposal = try? AIConfig.parse(answer) else { return }  // not even understood: nothing changes
        if case let .success(preview) = AIConfig.preview(proposal, config: mac.config, environment: env) {
            _ = try AIConfig.applying(preview.edits, at: mac.configURL)
        }
        #expect(mac.config.iCloudSync.hiddenWords == false)
        #expect(mac.config.iCloudSync.recentQuestions == false)
    }

    // MARK: Rime's sync_dir

    static let installation = """
        distribution_code_name: AllInOneIME
        distribution_name: AllInOneIME
        distribution_version: 0.6.4
        install_time: "Thu Oct 16 10:00:00 2026"
        installation_id: "mac-a-6f1c"
        rime_version: 1.13.1

        """

    @Test("rime: sync_dir points at iCloud's rime/ folder; installation_id and every other line stay as they were")
    func rimeSyncDir() throws {
        let folder = "/Users/someone/Library/Mobile Documents/com~apple~CloudDocs/AllInOneIME/rime"
        let lines = Self.installation.split(separator: "\n").map(String.init)
        let set = RimeSync.installation(Self.installation, syncDir: folder)
        #expect(RimeSync.syncDir(in: set) == folder)
        let setLines = set.split(separator: "\n").map(String.init)
        #expect(setLines.filter { $0.hasPrefix("sync_dir") }.count == 1)
        #expect(setLines.filter { !$0.hasPrefix("sync_dir") } == lines)
        // Again: still one.
        #expect(RimeSync.installation(set, syncDir: folder) == set)
        // Another folder named before (Dropbox …): replaced.
        let moved = RimeSync.installation(Self.installation + "sync_dir: /Users/someone/Dropbox/Rime\n", syncDir: folder)
        #expect(RimeSync.syncDir(in: moved) == folder)
        #expect(!moved.contains("Dropbox"))
        // Taken out: the file as it was.
        let removed = RimeSync.installation(set, syncDir: nil)
        #expect(RimeSync.syncDir(in: removed) == nil)
        #expect(removed.split(separator: "\n").map(String.init) == lines)
    }

    @Test("rime: two Macs point at the same sync folder, each keeping its own installation_id; the file is written only when it changes")
    func rimeTwoMacs() throws {
        let world = ICAWorld()
        let shared = world.folder.url.appendingPathComponent("rime", isDirectory: true)
        var ids: [String] = []
        for (n, id) in ["mac-a-6f1c", "mac-b-91d0"].enumerated() {
            let user = world.root.appendingPathComponent("Rime-\(n)", isDirectory: true)
            try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
            let file = user.appendingPathComponent("installation.yaml")
            try Data(Self.installation.replacingOccurrences(of: "mac-a-6f1c", with: id).utf8).write(to: file)
            #expect(try RimeSync.setSyncDir(shared, userDataDir: user) == true)
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(RimeSync.syncDir(in: text) == shared.path)
            #expect(text.contains("installation_id: \"\(id)\""))
            ids.append(id)
            // The same folder again: not written.
            ICA.touch(file, ICA.t(0))
            #expect(try RimeSync.setSyncDir(shared, userDataDir: user) == false)
            #expect(ICA.mtime(file) == ICA.t(0))
            // Off: taken out, the id kept.
            #expect(try RimeSync.setSyncDir(nil, userDataDir: user) == true)
            let off = try String(contentsOf: file, encoding: .utf8)
            #expect(RimeSync.syncDir(in: off) == nil)
            #expect(off.contains("installation_id: \"\(id)\""))
        }
        #expect(Set(ids).count == 2)
    }

    // MARK: iCloud Drive unavailable

    @Test("unavailable: without iCloud Drive a run says so and writes nothing; the switch is left as it is")
    func unavailableDrive() throws {
        let world = ICAWorld()
        let a = world.mac("A")
        a.folder = ICloudSyncFolder(url: world.root.appendingPathComponent("No iCloud Drive/AllInOneIME", isDirectory: true))
        #expect(a.folder.isAvailable == false)
        let before = a.configData
        let report = a.sync(at: 10)
        #expect(report.outcome == .unavailable)
        #expect(!ICA.exists(world.root.appendingPathComponent("No iCloud Drive")))
        #expect(a.configData == before)
    }

    @Test("unavailable: an iCloud Drive that can't be written is not available")
    func readOnlyDrive() throws {
        let world = ICAWorld()
        let a = world.mac("A")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: world.drive.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: world.drive.path) }
        #expect(world.folder.isAvailable == false)
        #expect(a.sync(at: 10).outcome == .unavailable)
        #expect(!ICA.exists(world.folder.url))
    }

    @Test("unavailable: @doctor says when sync is on, off, failed, and when iCloud Drive isn't available")
    func doctorCheck() throws {
        func findings(_ change: (inout Doctor.Facts.ICloudSyncFacts) -> Void) -> [Doctor.Finding] {
            var facts = Doctor.Facts()
            change(&facts.iCloudSync)
            return Doctor.findings(facts, chinese: false).filter { $0.area == .iCloudSync }
        }
        func text(_ list: [Doctor.Finding]) -> String { list.map { $0.title + " " + ($0.detail ?? "") }.joined(separator: "\n") }
        let off = findings { $0.enabled = false }
        #expect(text(off).lowercased().contains("off"))
        let unavailable = findings { $0.enabled = true; $0.available = false }
        #expect(unavailable.contains { $0.status == .problem })
        #expect(text(unavailable).contains("iCloud Drive"))
        #expect(text(unavailable).contains("System Settings"))
        let failed = findings { $0.enabled = true; $0.lastSync = ICA.t(0); $0.checked = ICA.t(120); $0.lastError = "The disk is full" }
        #expect(text(failed).contains("The disk is full"))
        let synced = findings { $0.enabled = true; $0.lastSync = ICA.t(0); $0.checked = ICA.t(120) }
        #expect(synced.allSatisfy { $0.status == .ok })
        #expect(text(synced).contains("2 min ago"))
    }
}

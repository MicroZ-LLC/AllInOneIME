import Crypto
import Foundation

/// Sync through iCloud (「通过 iCloud 同步」, Settings → General): the settings, the jargon list and custom commands, the
/// words pinyin learned, and on request the hidden words and recent questions, on every Mac of the user, through their own
/// iCloud Drive (`ICloudSyncFolder`: `~/Library/Mobile Documents/com~apple~CloudDocs/AllInOneIME/`). Nothing goes to any
/// server of ours, and no sign-in or iCloud entitlement is needed.
///
/// `settings.json` there holds each synced key with its own stamp, `{ "key": { "value": …, "modified": ISO 8601,
/// "by": "<Mac id>" } }`; a key deleted (an app's settings removed) is a stamped tombstone, `{ "deleted": true, … }`
/// (`Entry`). Each Mac keeps, on its own (`State`), the value every key had when it last synced and that value's stamp: a
/// key whose value changed since is a local change, stamped when its file changed; a key in iCloud with a newer stamp
/// than this Mac's comes in, if it passes the checks Settings makes (`problem`). Key by key, the newest wins (`plan`);
/// lists (`customCommands`, the styles) are whole values, and `appProfiles` is a key per app. A Mac's first sync of a
/// category joins (`Mode.joining`: iCloud's values win, collections merge); one turned back on rejoins
/// (`Mode.rejoining`). Only the keys that changed are written into `settings.json`, the
/// others' text and keys this version doesn't know left as they are, and into `config.json` the same way
/// (`AIConfig.writing`). The whole run is `ICloudSyncEngine`; this is its model.
public enum ICloudSync {
    /// What syncs, each on a switch of its own (`ICloudSyncSettings`).
    public enum Category: String, CaseIterable, Codable, Sendable {
        /// The config keys in `settingsKeys` and every app's settings.
        case settings
        /// The jargon list and `customCommands`.
        case jargon
        /// Rime's user dictionary: what pinyin learned from the user's choices (librime's own sync, `RimeSync`); and the
        /// English words pinyin offers (`englishWordsKey`), learned or added (`addedEnglishWordsKey`).
        case learnedWords
        /// `redaction.customWords`: off by default (iCloud Drive is end-to-end encrypted only with Advanced Data Protection).
        case hiddenWords
        /// The recent `@question`s (`QuestionHistory`): off by default.
        case recentQuestions
    }

    // MARK: - The keys

    /// The config keys "Settings" syncs (each as the config file writes it), besides the apps' (`appPrefix`). The output
    /// and input languages carry the one in use and the default input (the first of each list); `redaction` is its
    /// switches, the words being `hiddenWordsKey`.
    public static let settingsKeys: [String] = [
        "provider", "awsProfile", "region", "modelId", "anthropic", "gemini", "openai",
        "maxTokens", "temperature", "timeoutSeconds",
        "outputLanguages", "inputLanguages", "rewriteStyles", "improveTranslates", "voiceInput", "actionKey", "uiLanguage",
        "claudeInBackground", "rememberQuestions", "questionRounds", "questionContinueIn", "menuBarIcon",
        "typeOut", "typeOutRate", "typeOutVaries", "typeOutMistakes", "fuzzyPinyin", "keyboardLayouts", "candidateLayout",
        "checkForUpdates", "useSelection", "redaction", "learnsEnglishWords",
    ]
    /// One app's settings: "appProfiles.<bundle id>".
    public static let appPrefix = "appProfiles."
    public static let commandsKey = "customCommands"
    public static let hiddenWordsKey = "redaction.customWords"
    /// The English words pinyin offers (`Config.englishWords`) and those of them the user added
    /// (`Config.addedEnglishWords`): with the words it learned.
    public static let englishWordsKey = "englishWords"
    public static let addedEnglishWordsKey = "addedEnglishWords"
    /// The jargon list and the recent questions: entries of `settings.json` that stamp a file next to it (`jargonFile`,
    /// `questionsFile`), their value its SHA-256 (`fileValue`).
    public static let jargonKey = "file:jargon"
    public static let questionsKey = "file:questions"

    /// Never synced, whatever the switches: each Mac decides for itself. The keys and tokens aren't in the config at all
    /// (they're in the keychain); extension sources and their clones run code; extension folders and plugins are paths on
    /// this Mac, and so is where `@note` saves (`notes`: a folder's path); the sync setting itself is per Mac; `typeOutSpeed` is only read (from older files); `outputLanguage` and
    /// `defaultInput` come with their lists. Apps without typos and the recent apps aren't config keys either: named so
    /// that no later version adds them.
    public static let neverSynced: Set<String> = [
        "extensionSources", "extensionFolders", "hiddenExtensionFolders", "findRaycastScripts", "disabledExtensions",
        "extensionPreferences", "jargonFile", "iCloudSync", "typeOutSpeed", "outputLanguage", "defaultInput",
        "typeOutNoTyposApps", "recentApps", "notes",
    ]

    /// The category `key` (a key of `settings.json`) is synced under; nil for a key this version doesn't sync (one a newer
    /// version added: kept in `settings.json` as it is, and ignored here).
    public static func category(of key: String) -> Category? {
        if neverSynced.contains(key) { return nil }
        if settingsKeys.contains(key) { return .settings }
        if key.hasPrefix(appPrefix), AppProfile.isBundleID(String(key.dropFirst(appPrefix.count))) { return .settings }
        switch key {
        case commandsKey, jargonKey: return .jargon
        case hiddenWordsKey: return .hiddenWords
        case englishWordsKey, addedEnglishWordsKey: return .learnedWords
        case questionsKey: return .recentQuestions
        default: return nil
        }
    }

    // MARK: - Folder names

    /// In iCloud Drive.
    public static let folderName = "AllInOneIME"
    public static let settingsFile = "settings.json"
    /// The jargon list as text, whatever its name on each Mac (`Config.jargonURL`).
    public static let jargonFile = "jargon.txt"
    public static let questionsFile = "questions.json"
    /// Rime's sync folder (`sync_dir`): a folder per Mac's Rime installation, each with its user dictionaries' snapshots.
    public static let rimeFolder = "rime"

    // MARK: - Stamps

    /// When a value was set, and on which Mac (`State.macID`): the newer wins; at the same time, the larger Mac id. A stamp
    /// from a Mac whose clock is ahead (even years) is accepted as it is; a later change on this Mac is then stamped 1 ms
    /// after it (`plan`), so it still wins, and so on.
    public struct Stamp: Equatable, Comparable, Sendable {
        public var modified: Date
        public var by: String

        public init(modified: Date, by: String) {
            self.modified = modified
            self.by = by
        }

        public static func < (a: Stamp, b: Stamp) -> Bool {
            a.modified != b.modified ? a.modified < b.modified : a.by < b.by
        }

        /// What a joining Mac's values carry when they go up because iCloud has none (`Mode.joining`): older than any
        /// change, so that they never beat a real stamp (a fresh Mac's defaults over another Mac's settings). Only in the
        /// joining sync itself; a Mac that has synced restamps its own with now when it puts them up again.
        public static func joining(_ mac: String) -> Stamp { Stamp(modified: Date(timeIntervalSince1970: 0), by: mac) }

        public var isJoining: Bool { modified.timeIntervalSince1970 == 0 }
    }

    /// One key: its value as the config file writes it, or nil when it was deleted (a tombstone), and its stamp.
    ///
    /// In `settings.json`: `{ "value": <the value>, "modified": "2026-10-16T18:00:00.000Z", "by": "<Mac id>" }`; a
    /// tombstone (an app's settings removed, `questionRounds` back to its default, which the config leaves out) is
    /// `{ "deleted": true, "modified": …, "by": … }`, with no value. An entry with both, or neither, isn't read.
    ///
    /// A collection (`mergedOnJoin`) changed on a Mac also carries `base`, `"base": { "modified": …, "by": … }`: which
    /// merge its value derives from, the stamp that merge went up with (or a first join's, for a list put up as it was
    /// because iCloud had none), carried along every change made on top of it, on any Mac (`changeBase`). A Mac whose
    /// join merge is still provisional takes an entry of that base as made after seeing its merge: newer, it wins as any
    /// change does, rather than being merged again (which would bring back what was deleted on top of it). In this
    /// Mac's own record, a provisional merge's (or a first join's) `base` is that stamp, and a value received keeps the
    /// base it came with. A merge's result has none: each merge starts anew. A version that doesn't know `base` (0.6.4)
    /// ignores it, and drops it when it writes the entry: the Mac then merges again, as it did before (a delete made on
    /// top of a provisional merge comes back once; made again, it sticks). Two entries are the same whatever their `base`.
    public struct Entry: Equatable, Sendable {
        public var value: AIConfig.JSONValue?
        public var stamp: Stamp
        public var base: Stamp?

        public init(value: AIConfig.JSONValue?, stamp: Stamp, base: Stamp? = nil) {
            self.value = value
            self.stamp = stamp
            self.base = base
        }

        public var isTombstone: Bool { value == nil }

        public static func == (a: Entry, b: Entry) -> Bool { a.value == b.value && a.stamp == b.stamp }

        /// As `settings.json` holds it.
        public var json: AIConfig.JSONValue {
            var fields: [String: AIConfig.JSONValue] = ["modified": .string(ICloudSync.dateText(stamp.modified)), "by": .string(stamp.by)]
            if let value { fields["value"] = value } else { fields["deleted"] = .bool(true) }
            if let base { fields["base"] = .object(["modified": .string(ICloudSync.dateText(base.modified)), "by": .string(base.by)]) }
            return .object(fields)
        }

        /// An entry of `settings.json`; nil when it isn't one (no stamp, a value and a tombstone at once …). A `base`
        /// that isn't a stamp is left out.
        public init?(json: AIConfig.JSONValue) {
            guard case let .object(fields) = json, let stamp = Self.stamp(fields) else { return nil }
            var base: Stamp?
            if case let .object(b)? = fields["base"] { base = Self.stamp(b) }
            let deleted = fields["deleted"] == .bool(true)
            switch (fields["value"], deleted) {
            case (let value?, false): self.init(value: value, stamp: stamp, base: base)
            case (nil, true): self.init(value: nil, stamp: stamp, base: base)
            default: return nil
            }
        }

        private static func stamp(_ fields: [String: AIConfig.JSONValue]) -> Stamp? {
            guard case let .string(modified)? = fields["modified"], let date = ICloudSync.date(modified),
                  case let .string(by)? = fields["by"], !by.isEmpty else { return nil }
            return Stamp(modified: date, by: by)
        }
    }

    /// ISO 8601 with milliseconds (two changes in one second are told apart), in UTC.
    public static func dateText(_ date: Date) -> String {
        dateFormatters.withLock { $0.milliseconds.string(from: date) }
    }

    /// An ISO 8601 date, with or without the fraction of a second.
    public static func date(_ text: String) -> Date? {
        dateFormatters.withLock { $0.milliseconds.date(from: text) ?? $0.seconds.date(from: text) }
    }

    /// The two formats, made once: a sync reads and writes a date for every entry, and making a formatter (ICU's,
    /// behind a lock of its own) costs far more than using one. Behind a lock: one is used by one thread at a time.
    private static let dateFormatters = Locked(initialState: (
        milliseconds: isoFormatter([.withInternetDateTime, .withFractionalSeconds]),
        seconds: isoFormatter([.withInternetDateTime])))

    private static func isoFormatter(_ options: ISO8601DateFormatter.Options) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        return formatter
    }

    // MARK: - settings.json

    /// What `settings.json` holds: the entries this version can read, and the file's text, so that writing it changes only
    /// the entries this Mac writes (`patched`): another Mac's entries, malformed ones and keys of newer versions keep their
    /// text.
    public struct RemoteSettings: Equatable, Sendable {
        public var entries: [String: Entry]
        var text: String?

        public init(entries: [String: Entry] = [:]) {
            self.entries = entries
            text = nil
        }

        public enum ReadError: Error, Equatable { case notAnObject }

        /// The file's entries. Throws when it isn't a JSON object at all (a corrupt file: set aside, never overwritten).
        public static func parse(_ data: Data) throws -> RemoteSettings {
            guard case let .object(fields)? = (try? JSONSerialization.jsonObject(with: data)).flatMap(AIConfig.JSONValue.init) else {
                throw ReadError.notAnObject
            }
            var settings = RemoteSettings(entries: fields.compactMapValues(Entry.init(json:)))
            settings.text = String(decoding: data, as: UTF8.self)
            return settings
        }

        /// The file without `keys`: only their text goes.
        public func removing(_ keys: Set<String>) -> Data {
            if let text, let out = JSONFileText.patched(text, setting: [:], keys: keys) { return Data(out.utf8) }
            var all = entries.mapValues(\.json)
            for key in keys { all[key] = nil }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return (try? encoder.encode(AIConfig.JSONValue.object(all))) ?? Data("{}".utf8)
        }

        /// The file with `changes` written in: only those keys' text changes.
        public func patched(with changes: [String: Entry]) -> Data {
            let values = changes.mapValues(\.json)
            if let text, let out = JSONFileText.patched(text, setting: values, keys: Set(values.keys)) { return Data(out.utf8) }
            // No file yet (or text it can't patch in place): the entries it could read, and the changes.
            var all = entries.mapValues(\.json)
            for (key, value) in values { all[key] = value }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return (try? encoder.encode(AIConfig.JSONValue.object(all))) ?? Data("{}".utf8)
        }
    }

    // MARK: - This Mac's own record

    /// What this Mac knows of the sync, kept on this Mac only (`~/Library/Application Support/AllInOneIME/iCloudSync/
    /// state.json`; the tests and the self-test use their own): its id, each key's value when it last synced (as this
    /// version writes it) with that value's stamp, and how the last run went.
    public struct State: Equatable, Sendable {
        /// A random id for this Mac (`Stamp.by`): nothing about the Mac or the user.
        public var macID: String
        /// The Mac the record was made on (`ICloudSync.machineID(platformUUID:)`: a hash, never the hardware id itself).
        public var machine: String?
        public var entries: [String: Entry] = [:]
        public var lastSync: Date?
        public var lastError: String?
        /// The values from iCloud that didn't pass the checks, by key: the entry's stamp and why. Logged once each.
        public var rejected: [String: Rejection] = [:]
        /// The unreadable `settings.json` last set aside, by its new name.
        public var setAside: String?
        /// The categories this Mac has synced (its first sync of each done: it joined); the others join on their next sync.
        public var joined: Set<Category> = []
        /// The categories it had synced and stopped syncing (sync turned off, or the category's switch): turned on
        /// again, they rejoin (`Mode.rejoining`).
        public var paused: Set<Category> = []
        /// The config file's modification date right after this Mac's sync wrote it: a change can't be dated by a write
        /// that was sync's own.
        public var ownConfigWrite: Date?
        /// The recent questions as they were when this Mac last synced them (a hash of each question's key, never the
        /// text, and when it was asked), to tell a Clear here; and the newest Clear known (`questionsFile`).
        public var questionsSeen: [String: Date] = [:]
        public var questionsCleared: Date?
        /// "Remove from iCloud…" asked while `settings.json` wasn't downloaded: done by the next run that can read it.
        public var pendingRemovals: Set<Category> = []

        public init(macID: String = UUID().uuidString) { self.macID = macID }

        /// Whether this Mac has finished a sync of anything since it started syncing (or since Remove from iCloud).
        public var hasSynced: Bool { !joined.isEmpty }

        public struct Rejection: Equatable, Sendable {
            public var stamp: Stamp
            public var problem: Problem
        }

        /// The record at `url`: a new one (a new Mac id: this Mac joins again) when there is none or it can't be read.
        public static func load(from url: URL) -> State {
            guard let data = try? Data(contentsOf: url),
                  case let .object(fields)? = (try? JSONSerialization.jsonObject(with: data)).flatMap(AIConfig.JSONValue.init),
                  case let .string(mac)? = fields["macID"], !mac.isEmpty else { return State() }
            var state = State(macID: mac)
            if case let .object(entries)? = fields["entries"] { state.entries = entries.compactMapValues(Entry.init(json:)) }
            if case let .string(text)? = fields["lastSync"] { state.lastSync = ICloudSync.date(text) }
            if case let .string(text)? = fields["lastError"] { state.lastError = text }
            if case let .string(text)? = fields["setAside"] { state.setAside = text }
            if case let .string(text)? = fields["machine"] { state.machine = text }
            if let names = fields["joined"]?.strings { state.joined = Set(names.compactMap(Category.init(rawValue:))) }
            if let names = fields["paused"]?.strings { state.paused = Set(names.compactMap(Category.init(rawValue:))) }
            if case let .string(text)? = fields["ownConfigWrite"] { state.ownConfigWrite = ICloudSync.date(text) }
            if case let .object(seen)? = fields["questionsSeen"] {
                state.questionsSeen = seen.compactMapValues { if case let .string(text) = $0 { return ICloudSync.date(text) } else { return nil } }
            }
            if case let .string(text)? = fields["questionsCleared"] { state.questionsCleared = ICloudSync.date(text) }
            if let names = fields["pendingRemovals"]?.strings { state.pendingRemovals = Set(names.compactMap(Category.init(rawValue:))) }
            if case let .object(rejected)? = fields["rejected"] {
                for (key, value) in rejected {
                    guard case let .object(f) = value, case let .string(modified)? = f["modified"], let date = ICloudSync.date(modified),
                          case let .string(by)? = f["by"], case let .string(raw)? = f["problem"], let problem = Problem(rawValue: raw)
                    else { continue }
                    state.rejected[key] = Rejection(stamp: Stamp(modified: date, by: by), problem: problem)
                }
            }
            return state
        }

        public func write(to url: URL) throws {
            var fields: [String: AIConfig.JSONValue] = ["macID": .string(macID), "entries": .object(entries.mapValues(\.json))]
            if let lastSync { fields["lastSync"] = .string(ICloudSync.dateText(lastSync)) }
            if let lastError { fields["lastError"] = .string(lastError) }
            if let setAside { fields["setAside"] = .string(setAside) }
            if let machine { fields["machine"] = .string(machine) }
            if !joined.isEmpty { fields["joined"] = .array(joined.map(\.rawValue).sorted().map { .string($0) }) }
            if !paused.isEmpty { fields["paused"] = .array(paused.map(\.rawValue).sorted().map { .string($0) }) }
            if let ownConfigWrite { fields["ownConfigWrite"] = .string(ICloudSync.dateText(ownConfigWrite)) }
            if !questionsSeen.isEmpty { fields["questionsSeen"] = .object(questionsSeen.mapValues { .string(ICloudSync.dateText($0)) }) }
            if let questionsCleared { fields["questionsCleared"] = .string(ICloudSync.dateText(questionsCleared)) }
            if !pendingRemovals.isEmpty { fields["pendingRemovals"] = .array(pendingRemovals.map(\.rawValue).sorted().map { .string($0) }) }
            if !rejected.isEmpty {
                fields["rejected"] = .object(rejected.mapValues { rejection in
                    .object(["modified": .string(ICloudSync.dateText(rejection.stamp.modified)), "by": .string(rejection.stamp.by),
                             "problem": .string(rejection.problem.rawValue)])
                })
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(AIConfig.JSONValue.object(fields)).write(to: url, options: .atomic)
        }

        /// iCloudSync/state.json in the app's data folder (`CorePaths.dataDir`: ~/Library/Application Support/AllInOneIME
        /// on a Mac).
        public static var defaultURL: URL {
            CorePaths.dataDir.appendingPathComponent("iCloudSync/state.json")
        }
    }

    // MARK: - This Mac's values

    /// The synced keys of `config` in `categories`, each as the config file writes it: a key the config leaves out (an
    /// app without settings, `questionRounds` at its default) isn't there (deleted, if it was synced).
    public static func values(of config: Config, in categories: Set<Category>) -> [String: AIConfig.JSONValue] {
        let encoded = AIConfig.encoded(config)
        var out: [String: AIConfig.JSONValue] = [:]
        if categories.contains(.settings) {
            for key in settingsKeys { out[key] = encoded[key] }
            // Written into the file only when off; synced either way.
            out["learnsEnglishWords"] = .bool(config.learnsEnglishWords)
            if case var .object(redaction)? = encoded["redaction"] {
                redaction["customWords"] = nil
                out["redaction"] = .object(redaction)
            }
            if case let .object(apps)? = encoded["appProfiles"] {
                for (app, profile) in apps { out[appPrefix + app] = profile }
            }
        }
        if categories.contains(.jargon) { out[commandsKey] = encoded[commandsKey] }
        if categories.contains(.hiddenWords), case let .object(redaction)? = encoded["redaction"] {
            out[hiddenWordsKey] = redaction["customWords"] ?? .array([])
        }
        if categories.contains(.learnedWords) {
            for key in [englishWordsKey, addedEnglishWordsKey] { out[key] = encoded[key] ?? .array([]) }
        }
        return out
    }

    /// A file's value in `settings.json`: its SHA-256.
    public static func fileValue(_ data: Data) -> AIConfig.JSONValue {
        .object(["sha256": .string(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())])
    }

    // MARK: - The merge

    /// How a category syncs in a run.
    public enum Mode: Equatable, Sendable {
        /// Its first sync on this Mac (sync turned on, or the category's switch, for the first time): what iCloud has
        /// wins, and this Mac's values go up only where iCloud has none, with a joining stamp (`Stamp.joining`), so that
        /// they never beat a real change. Collections (`mergedOnJoin`) are merged with iCloud's instead.
        case joining
        /// Synced before, then turned off, now on again: a key iCloud changed meanwhile takes iCloud's value (also when
        /// this Mac changed it too); a key only this Mac changed goes up, stamped now; a collection this Mac changed
        /// meanwhile is merged with iCloud's, so that it never drops what it added.
        case rejoining
        /// Each key's newest change wins.
        case normal
    }

    /// The collections a joining (or rejoining) Mac merges with iCloud's rather than taking iCloud's: its custom
    /// commands (by name, iCloud's on a clash), hidden words, English words (those added too) and jargon lines (each
    /// once). Recent questions are always merged (`ICloudSyncEngine`).
    public static let mergedOnJoin: Set<String> = [commandsKey, hiddenWordsKey, englishWordsKey, addedEnglishWordsKey, jargonKey]

    /// What one run does with the keys: what comes into this Mac's config, what goes into `settings.json`, and this Mac's
    /// record afterwards.
    public struct Plan: Equatable, Sendable {
        /// The keys whose value in iCloud is newer and differs from this Mac's (nil: deleted): to check and put in.
        public var incoming: [String: Entry] = [:]
        /// The entries to write into `settings.json`.
        public var outgoing: [String: Entry] = [:]
        /// This Mac's record of each key afterwards: its value and that value's stamp. For an incoming key, iCloud's
        /// entry; `kept` is what to record instead when it isn't put in (refused, or a file not downloaded yet).
        public var entries: [String: Entry] = [:]
        public var kept: [String: Entry] = [:]
        /// Collections to merge with iCloud's (`mergedOnJoin`), with iCloud's entry: joining, or changed here while off.
        public var merges: [String: Entry] = [:]
        /// Of `merges`, those of a join: their result stays provisional (recorded with this Mac's joining stamp, so that
        /// it is merged again rather than replaced) until iCloud carries a list that holds all of this Mac's.
        public var provisional: Set<String> = []
    }

    /// The merge, key by key, of this Mac's values `local`, its record `known` (the keys' values and stamps when it last
    /// synced) and `remote` (`settings.json`'s entries; nil when it can't be read now: nothing comes in or goes out),
    /// for the keys of `categories`, each category in its mode (`modes`; normal when not given). The records of the
    /// categories not synced now are kept.
    ///
    /// Normal: a value that differs from the record is a local change, stamped by `mac` when its file changed
    /// (`changedAt`, at most `now`; `now` when not known), and always after the value it replaces (a stamp from a Mac
    /// whose clock is ahead is accepted, and a change here is stamped 1 ms after it); a key gone is a tombstone, except
    /// for keys in `ignoringLocalAbsence` (a file never created, or deleted, on this Mac); a key new since the last sync
    /// is stamped the same way. Then the newer stamp wins. A key every Mac of this version has that the record lacks (an
    /// older version's) joins instead while it is at its default, or is a collection iCloud has. A Mac that has synced before never lets joining stamps (a
    /// fresh Mac's values, put up while iCloud had lost its settings) over a value it synced: it puts its own back up,
    /// with a real stamp; so it does for any value iCloud no longer has. A value of iCloud's refused here (`refused`, by its
    /// stamp) is checked again each run, and this Mac's never goes over it unless changed here.
    public static func plan(local: [String: AIConfig.JSONValue], known: [String: Entry], remote: [String: Entry]?,
                            categories: Set<Category>, modes: [Category: Mode] = [:], mac: String, now: Date,
                            changedAt: (String) -> Date? = { _ in nil }, ignoringLocalAbsence: Set<String> = [],
                            refused: [String: Stamp] = [:]) -> Plan {
        var plan = Plan()
        var all = Set(local.keys).union(known.keys)
        if let remote { all.formUnion(remote.keys) }
        // What this version's values are on a Mac that never set them: the keys every Mac of it has.
        let defaults = values(of: .default, in: categories)
        func real(_ entry: Entry) -> Entry {
            entry.stamp.isJoining ? Entry(value: entry.value, stamp: Stamp(modified: now, by: mac)) : entry
        }
        for key in all.sorted() {
            guard let category = category(of: key), categories.contains(category) else {
                // Not synced now: the record stays as it was.
                if let record = known[key] { plan.entries[key] = record }
                continue
            }
            let value = local[key]
            let record = known[key]
            let theirs = remote?[key]
            let absent = value == nil && ignoringLocalAbsence.contains(key)
            // A key every Mac of this version has (`defaults`) that this Mac has no record of, in a category it synced:
            // the record was made by an older version, which didn't sync it (0.6.5: the English words, the switch that
            // learns them). Its value here at the default (never set here), or a collection iCloud has, joins as a
            // joining Mac's values do: never over a change made elsewhere (this version's defaults over the words another
            // Mac added, or its learning turned off), the collection merged. Any other value set here since is a change,
            // and the newer wins, as for a key both Macs set for the first time (an app's settings, the jargon list).
            var mode = modes[category] ?? .normal
            if mode != .joining, record == nil, let value, let unset = defaults[key],
               value == unset || mergedOnJoin.contains(key) && theirs != nil {
                mode = .joining
            }
            switch mode {
            case .joining:
                // Nothing recorded until iCloud can be read: the category stays joining.
                guard remote != nil else { continue }
                if let theirs {
                    if let value, theirs.value != nil, value != theirs.value, mergedOnJoin.contains(key) {
                        plan.merges[key] = theirs
                        plan.provisional.insert(key)
                        plan.kept[key] = Entry(value: value, stamp: .joining(mac))
                        continue
                    }
                    plan.entries[key] = theirs
                    if theirs.value != value, !(theirs.value == nil && absent) {
                        plan.incoming[key] = theirs
                        // Refused, this Mac's stays, as joining: it never goes over iCloud's (`refused`).
                        if let value { plan.kept[key] = Entry(value: value, stamp: .joining(mac)) }
                    }
                } else if let value {
                    let entry = Entry(value: value, stamp: .joining(mac))
                    plan.outgoing[key] = entry
                    // A collection put up as it is: a change another Mac makes on top of it is based on it (`base`),
                    // and wins here rather than being merged again (which would bring back what that Mac deleted).
                    plan.entries[key] = mergedOnJoin.contains(key) ? Entry(value: value, stamp: entry.stamp, base: entry.stamp) : entry
                }
            case .rejoining:
                guard remote != nil else {
                    if let record { plan.entries[key] = record }
                    continue
                }
                let changedHere = absent ? false : record.map { $0.value != value } ?? (value != nil)
                // Another Mac's joining stamp (a fresh Mac's value, put up while iCloud had lost what this Mac synced) is
                // no change there: this Mac's goes back up.
                let filler = theirs.map { $0.stamp.isJoining && $0.stamp.by != mac && record != nil && $0.stamp != record?.stamp } ?? false
                let changedThere = (theirs.map { $0.stamp != record?.stamp } ?? false) && !filler
                // Refused, this Mac's value stays, under the record's stamp: never put over iCloud's.
                let held = value.map { Entry(value: $0, stamp: record?.stamp ?? .joining(mac)) }
                if changedHere, let value, let theirs, theirs.value != nil, value != theirs.value, mergedOnJoin.contains(key) {
                    plan.merges[key] = theirs
                    plan.kept[key] = held
                } else if let theirs, changedThere {
                    plan.entries[key] = theirs
                    if theirs.value != value, !(theirs.value == nil && absent) {
                        plan.incoming[key] = theirs
                        plan.kept[key] = held ?? record
                    }
                } else if changedHere {
                    let entry = Entry(value: value, stamp: Stamp(modified: now, by: mac), base: changeBase(key, record))
                    plan.outgoing[key] = entry
                    plan.entries[key] = entry
                } else if let record {
                    let entry = theirs == nil || filler ? real(record) : record
                    if entry != theirs, theirs == nil || filler { plan.outgoing[key] = entry }
                    plan.entries[key] = entry
                }
            case .normal:
                var mine: Entry?
                if let record {
                    // Stamped when the file changed if that is known, never later than now nor before the value it
                    // replaces.
                    let at = max(min(changedAt(key) ?? now, now), record.stamp.modified.addingTimeInterval(0.001))
                    mine = record.value == value || absent ? record
                        : Entry(value: value, stamp: Stamp(modified: at, by: mac), base: changeBase(key, record))
                } else if let value {
                    mine = Entry(value: value, stamp: Stamp(modified: min(changedAt(key) ?? now, now), by: mac))
                }
                guard remote != nil else {
                    plan.entries[key] = mine
                    continue
                }
                guard let theirs else {
                    // iCloud doesn't have it (lost, or never sent): this Mac's goes up, with a real stamp.
                    if let mine {
                        plan.outgoing[key] = real(mine)
                        plan.entries[key] = real(mine)
                    }
                    continue
                }
                if let mine, mine == record, refused[key] == theirs.stamp {
                    // Refused here before and not changed here since: checked again, never put over it.
                    plan.entries[key] = mine
                    plan.incoming[key] = theirs
                    plan.kept[key] = mine
                    continue
                }
                if mergedOnJoin.contains(key), let record, record.stamp.isJoining, record.stamp.by == mac, theirs.stamp.by != mac,
                   theirs.stamp != record.stamp, let value, theirs.value != nil, value != theirs.value,
                   theirs.base == nil || theirs.base != record.base {
                    // Still as this Mac joined (or provisional, from a join's merge), and another Mac's in iCloud: Macs
                    // joined at once, or this one joined offline. The collections merge, as on a join. Not when iCloud's
                    // was changed from this Mac's merge as it went up (`Entry.base`): that Mac saw it, and its change
                    // stands as any newer change does.
                    // Known limits: the merge is of this Mac's whole list, merge included, so a command another Mac
                    // deleted from a list this one hasn't seen (two Macs joined at once, a third deleted one it had)
                    // comes back once; an item from the first Mac to sync that another Mac deleted comes back once too
                    // when the first Mac slept through a merge made on another Mac (that merge starts a `base` of its
                    // own, which this Mac's join record doesn't know), and deleted again it stays deleted; and a join
                    // made offline settles on that Mac's own copy of settings.json, so when the two files meet, iCloud
                    // keeps one and the other Mac's command added meanwhile can be lost.
                    plan.merges[key] = theirs
                    plan.provisional.insert(key)
                    plan.kept[key] = mine
                    continue
                }
                if let mine, let record, theirs.stamp.isJoining, theirs.stamp != record.stamp {
                    // A fresh Mac's value over one this Mac synced (iCloud had lost it): this Mac's goes back up.
                    let entry = real(mine)
                    if entry != theirs { plan.outgoing[key] = entry }
                    plan.entries[key] = entry
                    continue
                }
                if let mine, mine.stamp >= theirs.stamp {
                    // The same stamp is the same change (as this version wrote it: a name it doesn't know left out).
                    if mine.stamp > theirs.stamp { plan.outgoing[key] = mine }
                    plan.entries[key] = mine
                    continue
                }
                plan.entries[key] = theirs
                if theirs.value != value, !(theirs.value == nil && absent) {
                    plan.incoming[key] = theirs
                    if let mine { plan.kept[key] = mine }
                }
            }
        }
        // Fields of an object a newer version added (in iCloud's entry, unknown here) go back up with this Mac's edit.
        for (key, entry) in plan.outgoing {
            if let carried = carryingUnknownFields(of: remote?[key]?.value, into: entry.value, key: key) {
                plan.outgoing[key] = Entry(value: carried, stamp: entry.stamp, base: entry.base)
            }
        }
        return plan
    }

    /// What a change of `key` made here on top of `record` is based on (`Entry.base`), for a collection: the merge (or
    /// the first join) the record's value derives from, its `base`, carried along every change made on top of it, on any
    /// Mac; the record's own stamp when it has none (a merge's result, a value from a version that doesn't know `base`).
    static func changeBase(_ key: String, _ record: Entry?) -> Stamp? {
        guard mergedOnJoin.contains(key), let record else { return nil }
        return record.base ?? record.stamp
    }

    /// The fields this version knows of an object-valued key (`redaction`, a provider's settings, an app's settings); nil
    /// for any other key.
    public static func knownFields(of key: String) -> Set<String>? {
        if key.hasPrefix(appPrefix) { return ["inputLanguage", "rewriteStyles", "typeOut", "noAI", "translateAlways"] }
        switch key {
        case "redaction": return ["enabled", "emails", "phones", "cards", "keys", "ips", "customWords"]
        case "anthropic", "gemini", "openai": return ["model", "baseURL", "effort", "temperature"]
        default: return nil
        }
    }

    /// `mine` with the fields of `theirs` this version doesn't know (`knownFields`) carried over, as `AIConfig.merged`
    /// keeps them in config.json; nil when there are none to carry.
    public static func carryingUnknownFields(of theirs: AIConfig.JSONValue?, into mine: AIConfig.JSONValue?, key: String) -> AIConfig.JSONValue? {
        guard let known = knownFields(of: key), case let .object(icloud)? = theirs, case var .object(fields)? = mine else { return nil }
        let unknown = icloud.filter { !known.contains($0.key) && fields[$0.key] == nil }
        guard !unknown.isEmpty else { return nil }
        for (name, value) in unknown { fields[name] = value }
        return .object(fields)
    }

    // MARK: - Writing the config

    /// Writes `keys` of `config` into the config file at `url` (`AIConfig.writing`), leaving what changed in the file
    /// since the run read it as `old` (Settings saved meanwhile): that change stays, and goes up as a local change next
    /// run. Field by field, at every depth: inside an object-valued key (`appProfiles` per app and per field, `redaction`
    /// per switch and its words, a provider's settings) only the fields Settings changed are left, and the run's other
    /// fields are written, so a save of one app's settings (or one switch) never keeps the run from writing another's.
    /// A list or a plain value Settings changed is left whole (the languages with their companion). Which of the run's
    /// sync keys the file holds as written is for the run to read back (`ICloudSyncEngine`). The top-level keys written,
    /// some maybe only in part.
    @discardableResult
    public static func writeConfig(_ config: Config, readAs old: Config, keys: Set<String>, at url: URL) throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            try config.write(to: url)
            return keys
        }
        let current = (try? Config.load(from: url)) ?? old
        let now = AIConfig.encoded(current), then = AIConfig.encoded(old)
        var values = AIConfig.encoded(config)
        var write = Set<String>()
        for key in keys {
            let companions = AIConfig.companions[key] ?? []
            if ([key] + companions).allSatisfy({ now[$0] == then[$0] }) {
                write.insert(key)
                continue
            }
            // Written with its companion, which Settings changed: both stay as Settings saved them.
            guard companions.isEmpty else { continue }
            let value = keepingChanges(new: values[key], old: then[key], file: now[key])
            values[key] = value
            if value != then[key] { write.insert(key) }
        }
        guard !write.isEmpty else { return [] }
        try AIConfig.writing(values, from: then, keys: write, at: url)
        return write
    }

    /// `new` (a run's value of a key, read as `old`) with `old`'s value wherever `file` (the key in the file now) changed
    /// it since: fields of objects one by one, at every depth; anything else whole. Written from `old`, it leaves exactly
    /// the file's changes.
    static func keepingChanges(new: AIConfig.JSONValue?, old: AIConfig.JSONValue?, file: AIConfig.JSONValue?) -> AIConfig.JSONValue? {
        if new == old || file == old { return new }
        guard case let .object(newFields)? = new, case let .object(oldFields)? = old, case let .object(fileFields)? = file else {
            return old
        }
        var out: [String: AIConfig.JSONValue] = [:]
        for name in Set(newFields.keys).union(oldFields.keys) {
            out[name] = keepingChanges(new: newFields[name], old: oldFields[name], file: fileFields[name])
        }
        return .object(out)
    }

    // MARK: - Merging collections

    /// Custom commands merged: iCloud's (`theirs`), then this Mac's whose name iCloud's lack; on a name in both, iCloud's.
    /// The names of this Mac's commands that iCloud's replaced (they differed).
    public static func mergedCommands(_ theirs: AIConfig.JSONValue, _ mine: AIConfig.JSONValue) -> (value: AIConfig.JSONValue, replaced: [String]) {
        guard case let .array(icloud) = theirs, case let .array(local) = mine else { return (theirs, []) }
        func name(_ command: AIConfig.JSONValue) -> String? {
            if case let .object(fields) = command, case let .string(name)? = fields["name"] { return name.lowercased() }
            return nil
        }
        var out = icloud
        var names = Set(icloud.compactMap(name))
        var replaced: [String] = []
        for command in local {
            guard let key = name(command) else { continue }
            if names.insert(key).inserted {
                out.append(command)
            } else if !icloud.contains(command) {
                replaced.append(key)
            }
        }
        return (.array(out), replaced)
    }

    /// Hidden words merged: iCloud's, then this Mac's that iCloud's lack, as they are matched (`key`: ignoring case; the
    /// English words added by their letters, `EnglishWords.key`).
    public static func mergedWords(_ theirs: AIConfig.JSONValue, _ mine: AIConfig.JSONValue,
                                   key: (String) -> String = { $0.lowercased() }) -> AIConfig.JSONValue {
        let icloud = theirs.strings ?? [], local = mine.strings ?? []
        var seen = Set(icloud.map(key))
        return .array((icloud + local.filter { seen.insert(key($0)).inserted }).map { .string($0) })
    }

    /// English words merged: iCloud's, then this Mac's that iCloud's lack, by their letters (`EnglishWords.key`: "Hugging
    /// Face" is "HuggingFace"), within `EnglishWords.maxWords`. Over it, words learned give way before those added
    /// (`added`, both Macs'), this Mac's before iCloud's, the oldest first: the other Macs' next merge then finds all of
    /// theirs in iCloud's, and settles.
    public static func mergedEnglishWords(_ theirs: AIConfig.JSONValue, _ mine: AIConfig.JSONValue, added: [String]) -> AIConfig.JSONValue {
        let icloud = theirs.strings ?? []
        var seen = Set(icloud.map(EnglishWords.key))
        let lacking = (mine.strings ?? []).filter { seen.insert(EnglishWords.key($0)).inserted }
        let user = Set(added.map(EnglishWords.key))
        var excess = icloud.count + lacking.count - EnglishWords.maxWords
        // Which of each part go: this Mac's first, then iCloud's.
        var gone: [Set<Int>] = [[], []]
        for addedOnes in [false, true] {
            for (part, words) in [lacking, icloud].enumerated() {
                for (i, word) in words.enumerated() where excess > 0 && user.contains(EnglishWords.key(word)) == addedOnes {
                    gone[part].insert(i)
                    excess -= 1
                }
            }
        }
        let kept = icloud.indices.filter { !gone[1].contains($0) }.map { icloud[$0] }
            + lacking.indices.filter { !gone[0].contains($0) }.map { lacking[$0] }
        return .array(kept.map { .string($0) })
    }

    /// Whether the English words `after` hold a word (by its letters) that `before` lacks.
    static func addsWords(_ after: AIConfig.JSONValue?, to before: AIConfig.JSONValue?) -> Bool {
        let had = Set((before?.strings ?? []).map(EnglishWords.key))
        return (after?.strings ?? []).contains { !had.contains(EnglishWords.key($0)) }
    }

    /// A jargon list merged: iCloud's text, then this Mac's lines that iCloud's lacks (each once, spaces at the ends aside).
    public static func mergedJargon(_ theirs: String, _ mine: String) -> String {
        var seen = Set(theirs.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) })
        let added = mine.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && seen.insert(trimmed).inserted
        }
        guard !added.isEmpty else { return theirs }
        let base = theirs.isEmpty || theirs.hasSuffix("\n") ? theirs : theirs + "\n"
        return base + added.joined(separator: "\n") + "\n"
    }

    /// `remote` with one entry per app where several spell its bundle id differently (two Macs added it at once): the
    /// newest. The others stay in the file as they are and are ignored.
    public static func collapsingAppKeys(_ remote: [String: Entry]) -> [String: Entry] {
        var newest: [String: String] = [:]
        for key in remote.keys.sorted() where key.hasPrefix(appPrefix) {
            let id = key.lowercased()
            if let other = newest[id], let a = remote[other], let b = remote[key], a.stamp >= b.stamp { continue }
            newest[id] = key
        }
        return remote.filter { !$0.key.hasPrefix(appPrefix) || newest[$0.key.lowercased()] == $0.key }
    }

    /// `local`'s app keys spelled as `known` spells them where they differ only in case (bundle ids are matched ignoring
    /// case, as the config does): "appProfiles.com.apple.Mail" here is iCloud's "appProfiles.com.apple.mail".
    public static func matchingAppKeys(_ local: [String: AIConfig.JSONValue], to known: some Sequence<String>) -> [String: AIConfig.JSONValue] {
        var spelled: [String: String] = [:]
        for key in known.sorted() where key.hasPrefix(appPrefix) { spelled[key.lowercased()] = spelled[key.lowercased()] ?? key }
        var out: [String: AIConfig.JSONValue] = [:]
        for (key, value) in local {
            guard key.hasPrefix(appPrefix), let other = spelled[key.lowercased()], other != key, local[other] == nil else {
                out[key] = value
                continue
            }
            out[other] = value
        }
        return out
    }

    // MARK: - Checks

    /// Why a value from iCloud isn't applied on this Mac (logged, and shown by Settings → Assistant's checks).
    public enum Problem: String, Codable, Sendable {
        /// Not the kind of value the key holds.
        case wrongType
        /// Out of the range Settings allows (an empty list, more than five languages, a timeout of 0 …).
        case outOfRange
        /// A name this version doesn't know where it can't be left out (a provider, a region, a layout).
        case unknownValue
        /// A custom command Settings wouldn't save (no name of letters, nothing to run, two of one name).
        case invalidCommand
        /// A provider that needs a key this Mac hasn't got: nothing would work here (as Settings → Assistant says).
        case noKey
        /// An AWS profile this Mac doesn't have.
        case noProfile
        /// A key the config always has can't be deleted.
        case cannotDelete

        public func text(language: String) -> String {
            let t = InterfaceWords(language: language)
            switch self {
            case .wrongType: return t.tr("值的类型不对", "not the right kind of value")
            case .outOfRange: return t.tr("超出设置允许的范围", "out of the range Settings allows")
            case .unknownValue: return t.tr("这个版本不认识这个值", "a value this version doesn't know")
            case .invalidCommand: return t.tr("有设置里存不了的命令", "a command Settings couldn't save")
            case .noKey: return t.tr("这台 Mac 上没有它的密钥", "no key for it on this Mac")
            case .noProfile: return t.tr("这台 Mac 上没有这个 AWS profile", "no such AWS profile on this Mac")
            case .cannotDelete: return t.tr("这一项不能删除", "this setting can't be removed")
            }
        }

        /// `text` in Simplified Chinese or English.
        public func text(chinese: Bool) -> String { text(language: InterfaceLanguage.code(chinese: chinese)) }
    }

    /// What the checks need of this Mac: which providers have a key (asked without reading it), the AWS profiles, the
    /// providers offered. The tests give their own.
    public struct Environment: Sendable {
        public var hasKey: @Sendable (Provider) -> Bool
        /// The AWS profiles in ~/.aws (nil: not checked).
        public var awsProfiles: (@Sendable () -> [String])?
        public var offeredProviders: [Provider]
        /// The interface languages this Mac's app ships (`InterfaceLanguage.shipped`): a `uiLanguage` naming another is
        /// refused.
        public var interfaceLanguages: [String]

        public init(hasKey: @escaping @Sendable (Provider) -> Bool = { _ in true }, awsProfiles: (@Sendable () -> [String])? = nil,
                    offeredProviders: [Provider] = Provider.allCases, interfaceLanguages: [String] = InterfaceLanguage.builtIn) {
            self.hasKey = hasKey
            self.awsProfiles = awsProfiles
            self.offeredProviders = offeredProviders
            self.interfaceLanguages = interfaceLanguages
        }
    }

    /// Why `value` (nil: deleted) can't be `key`'s on this Mac, by the rules Settings keeps to; nil when it can. Names a
    /// newer version added where a list can do without them (a language, a fuzzy pair, a place to continue in) are left
    /// out when the config reads it, as for a file written by a newer version; one a single value needs is refused.
    public static func problem(_ key: String, _ value: AIConfig.JSONValue?, environment env: Environment) -> Problem? {
        guard let value else {
            // Only what the config may leave out can be deleted.
            return key.hasPrefix(appPrefix) || ["questionRounds", "questionContinueIn"].contains(key) ? nil : .cannotDelete
        }
        func number(_ range: ClosedRange<Double>) -> Problem? {
            guard case let .number(n) = value else { return .wrongType }
            return range.contains(n) ? nil : .outOfRange
        }
        func strings() -> [String]? { value.strings }
        if key.hasPrefix(appPrefix) {
            guard AppProfile.isBundleID(String(key.dropFirst(appPrefix.count))), case let .object(fields) = value,
                  decodes(AppProfile.self, value) != nil else { return .wrongType }
            if let language = fields["inputLanguage"], language != .null {
                guard case let .string(code) = language else { return .wrongType }
                if Language(rawValue: code) == nil { return .unknownValue }
            }
            if let styles = fields["rewriteStyles"], styles != .null, styles.strings == nil { return .wrongType }
            for flag in ["typeOut", "noAI", "translateAlways"] {
                guard let field = fields[flag], field != .null else { continue }
                guard case .bool = field else { return .wrongType }
            }
            return nil
        }
        switch key {
        case "improveTranslates", "voiceInput", "claudeInBackground", "rememberQuestions", "menuBarIcon", "typeOut",
             "typeOutVaries", "typeOutMistakes", "checkForUpdates", "useSelection", "learnsEnglishWords":
            if case .bool = value { return nil }
            return .wrongType
        case "provider":
            guard case let .string(name) = value else { return .wrongType }
            guard let provider = Provider(rawValue: name), env.offeredProviders.contains(provider) else { return .unknownValue }
            return [.anthropic, .gemini, .openai, .hosted].contains(provider) && !env.hasKey(provider) ? .noKey : nil
        case "awsProfile":
            guard case let .string(name) = value else { return .wrongType }
            if name.trimmingCharacters(in: .whitespaces).isEmpty { return .outOfRange }
            return env.awsProfiles.map { $0().contains(name) } == false ? .noProfile : nil
        case "region":
            if value == .null { return nil }
            guard case let .string(region) = value else { return .wrongType }
            return AIConfig.regions.contains(region) ? nil : .unknownValue
        case "modelId":
            guard case let .string(model) = value else { return .wrongType }
            return model.trimmingCharacters(in: .whitespaces).isEmpty ? .outOfRange : nil
        case "anthropic", "gemini", "openai":
            guard case let .object(fields) = value, decodes(ProviderSettings.self, value) != nil else { return .wrongType }
            if case let .string(url)? = fields["baseURL"] {
                guard let parsed = URL(string: url), ["https", "http"].contains(parsed.scheme?.lowercased() ?? ""), parsed.host != nil
                else { return .outOfRange }
            }
            if case let .string(effort)? = fields["effort"], !["", "low", "medium", "high"].contains(effort) { return .unknownValue }
            if case let .number(t)? = fields["temperature"], !(0...2).contains(t) { return .outOfRange }
            return nil
        case "maxTokens": return number(200...4000)
        case "temperature": return value == .null ? nil : number(0...1)
        case "timeoutSeconds": return number(5...60)
        case "typeOutRate": return number(TypeOut.slowestRate...TypeOut.fastestRate)
        case "questionRounds":
            guard case let .number(n) = value, n == n.rounded() else { return .wrongType }
            return QuestionChat.rounds(Int(n)) == Int(n) ? nil : .outOfRange
        case "outputLanguages":
            guard let codes = strings() else { return .wrongType }
            let pattern = #"^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$"#
            guard codes.allSatisfy({ $0.range(of: pattern, options: .regularExpression) != nil }) else { return .unknownValue }
            return (1...AIConfig.maxOutputLanguages).contains(Set(codes).count) ? nil : .outOfRange
        case "inputLanguages":
            guard let codes = strings() else { return .wrongType }
            let known = codes.compactMap(Language.init(rawValue:))
            return known.isEmpty || Set(codes).count > Config.maxInputLanguages ? .outOfRange : nil
        case "rewriteStyles", "fuzzyPinyin":
            return strings() == nil ? .wrongType : nil
        case "questionContinueIn":
            guard let names = strings() else { return .wrongType }
            return names.contains(where: { ChatHandoff.Destination(rawValue: $0) != nil }) || names.isEmpty ? nil : .unknownValue
        case "keyboardLayouts":
            guard case let .object(fields) = value else { return .wrongType }
            return fields.values.allSatisfy { if case .string = $0 { return true } else { return false } } ? nil : .wrongType
        case "actionKey":
            return decodes(ActionKey.self, value) == nil ? .wrongType : nil
        case "uiLanguage":
            if value == .null { return nil }
            guard case let .string(code) = value else { return .wrongType }
            return InterfaceLanguage.code(forSetting: code, shipped: env.interfaceLanguages) == nil ? .unknownValue : nil
        case "candidateLayout":
            guard case let .string(name) = value else { return .wrongType }
            return CandidateArrangement(rawValue: name) == nil ? .unknownValue : nil
        case "redaction":
            guard case let .object(fields) = value else { return .wrongType }
            for (name, field) in fields where name != "customWords" {
                if case .bool = field { continue }
                return .wrongType
            }
            return nil
        case hiddenWordsKey, englishWordsKey, addedEnglishWordsKey:
            return strings() == nil ? .wrongType : nil
        case commandsKey:
            // An entry of a type this version doesn't know (a later one's) is kept as the config file keeps it; its name
            // is taken all the same.
            guard case .array = value, let entries = decodes([CustomCommand.Entry].self, value) else { return .wrongType }
            var names = Set<String>()
            for entry in entries {
                if let command = entry.command {
                    guard command.isValid, names.insert(command.name.lowercased()).inserted else { return .invalidCommand }
                } else {
                    guard let name = entry.unread.flatMap(CustomCommand.Entry.name) else { return .wrongType }
                    guard names.insert(name.lowercased()).inserted else { return .invalidCommand }
                }
            }
            return nil
        case jargonKey, questionsKey:
            guard case let .object(fields) = value, case let .string(hash)? = fields["sha256"], hash.count == 64 else { return .wrongType }
            return nil
        default:
            return .unknownValue
        }
    }

    /// `value` read as `T` the way the config file is read, or nil.
    static func decodes<T: Decodable>(_ type: T.Type, _ value: AIConfig.JSONValue) -> T? {
        guard let data = try? JSONEncoder().encode([value]) else { return nil }
        return try? JSONDecoder().decode([T].self, from: data).first
    }

    // MARK: - Applying

    /// `config` with `incoming` values (nil: deleted) put in, each checked first (`problem`): those that pass, and the
    /// others with why. Each goes in as the config file holds it and is read back as the config reads a file, so the
    /// result is a config this version would read (its own normalizing included: the language in use leads its list).
    public static func applying(_ incoming: [String: AIConfig.JSONValue?], to config: Config, environment env: Environment)
        -> (config: Config, applied: [String], rejected: [String: Problem]) {
        var current = config
        var applied: [String] = []
        var rejected: [String: Problem] = [:]
        for key in incoming.keys.sorted() {
            let value = incoming[key] ?? nil
            if let problem = problem(key, value, environment: env) {
                rejected[key] = problem
                continue
            }
            var file = AIConfig.encoded(current)
            switch key {
            case "redaction":
                guard case var .object(fields)? = value else { continue }
                if case let .object(old)? = file["redaction"] { fields["customWords"] = old["customWords"] }
                file["redaction"] = .object(fields)
            case hiddenWordsKey:
                guard case var .object(fields)? = file["redaction"] else { continue }
                fields["customWords"] = value
                file["redaction"] = .object(fields)
            case "outputLanguages":
                // The first of the list is the one in use.
                file[key] = value
                if case let .array(codes)? = value, let first = codes.first { file["outputLanguage"] = first }
            case "inputLanguages":
                // The first known one is the default input.
                file[key] = value
                if let first = value?.strings?.first(where: { Language(rawValue: $0) != nil }) { file["defaultInput"] = .string(first) }
            default:
                if key.hasPrefix(appPrefix) {
                    let app = String(key.dropFirst(appPrefix.count))
                    var apps: [String: AIConfig.JSONValue] = [:]
                    if case let .object(existing)? = file["appProfiles"] { apps = existing }
                    // The app as this Mac spells it, if it has settings (bundle ids are matched ignoring case).
                    for other in apps.keys where other.caseInsensitiveCompare(app) == .orderedSame { apps[other] = nil }
                    let spelled = current.profileKey(for: app) ?? app
                    apps[spelled] = value
                    file["appProfiles"] = .object(apps)
                } else {
                    file[key] = value
                }
            }
            guard let data = try? JSONEncoder().encode(AIConfig.JSONValue.object(file)),
                  var next = try? JSONDecoder().decode(Config.self, from: data) else {
                rejected[key] = .wrongType
                continue
            }
            // Style names a newer version added are left out here (iCloud keeps them for the Macs that know them), as
            // the config leaves out a language it doesn't know.
            if key == "rewriteStyles" { next.rewriteStyles = next.rewriteStyles.filter { RewriteStyle.named($0) != nil } }
            if key.hasPrefix(appPrefix), let app = next.profileKey(for: String(key.dropFirst(appPrefix.count))),
               let styles = next.appProfiles[app]?.rewriteStyles {
                next.appProfiles[app]?.rewriteStyles = styles.filter { RewriteStyle.named($0) != nil }
            }
            current = next
            applied.append(key)
        }
        // The English words with every word added in them (one Mac's list may meet the words another added: the newer
        // list won while the other Mac added one), within their limit, the oldest learned going first (a list from iCloud
        // may hold more). Words given back count as the list applied.
        if applied.contains(englishWordsKey) || applied.contains(addedEnglishWordsKey) {
            let words = EnglishWords.withAdded(current.englishWords, added: current.addedEnglishWords)
            if words != current.englishWords, !applied.contains(englishWordsKey) { applied.append(englishWordsKey) }
            current.englishWords = words
        }
        return (current, applied, rejected)
    }
}

/// Which parts sync through iCloud on this Mac (`Config.iCloudSync`): off by default; each switch is this Mac's own,
/// never synced. Hidden words and recent questions are off until turned on in Settings → General (the Assistant can't).
public struct ICloudSyncSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var settings: Bool
    /// The jargon list and the custom commands.
    public var jargon: Bool
    public var learnedWords: Bool
    public var hiddenWords: Bool
    public var recentQuestions: Bool
    /// API keys and passwords, through iCloud Keychain rather than iCloud Drive (`KeySync`): off by default (keys move
    /// into iCloud Keychain only once the user turns this on, never because sync itself was turned on), written in the
    /// config only when on.
    public var keys: Bool

    public init(enabled: Bool = false, settings: Bool = true, jargon: Bool = true, learnedWords: Bool = true,
                hiddenWords: Bool = false, recentQuestions: Bool = false, keys: Bool = false) {
        self.enabled = enabled
        self.settings = settings
        self.jargon = jargon
        self.learnedWords = learnedWords
        self.hiddenWords = hiddenWords
        self.recentQuestions = recentQuestions
        self.keys = keys
    }

    /// The categories turned on (none while sync is off).
    public var categories: Set<ICloudSync.Category> {
        guard enabled else { return [] }
        var out = Set<ICloudSync.Category>()
        if settings { out.insert(.settings) }
        if jargon { out.insert(.jargon) }
        if learnedWords { out.insert(.learnedWords) }
        if hiddenWords { out.insert(.hiddenWords) }
        if recentQuestions { out.insert(.recentQuestions) }
        return out
    }

    /// Keys go through iCloud Keychain: sync on, and its "API keys and passwords" row on.
    public var syncsKeys: Bool { enabled && keys }

    private enum CodingKeys: String, CodingKey { case enabled, settings, jargon, learnedWords, hiddenWords, recentQuestions, keys }

    /// Each switch on its own: a missing one, or one of the wrong type, keeps its default (never an error).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ICloudSyncSettings()
        func flag(_ key: CodingKeys, _ fallback: Bool) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: key)).flatMap { $0 } ?? fallback }
        enabled = flag(.enabled, d.enabled)
        settings = flag(.settings, d.settings)
        jargon = flag(.jargon, d.jargon)
        learnedWords = flag(.learnedWords, d.learnedWords)
        hiddenWords = flag(.hiddenWords, d.hiddenWords)
        recentQuestions = flag(.recentQuestions, d.recentQuestions)
        keys = flag(.keys, d.keys)
    }

    /// As before `keys` came, and `keys` only when it's on (the default needs no line).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(settings, forKey: .settings)
        try c.encode(jargon, forKey: .jargon)
        try c.encode(learnedWords, forKey: .learnedWords)
        try c.encode(hiddenWords, forKey: .hiddenWords)
        try c.encode(recentQuestions, forKey: .recentQuestions)
        if keys != ICloudSyncSettings().keys { try c.encode(keys, forKey: .keys) }
    }
}

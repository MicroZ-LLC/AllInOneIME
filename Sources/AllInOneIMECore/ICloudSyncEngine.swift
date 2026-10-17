import Foundation

/// One sync through iCloud on this Mac (`ICloudSync`): the config's synced keys, the jargon list and the recent questions
/// merged with `settings.json` and the files beside it in `folder`, both ways. Everything it touches is given (`folder`,
/// `configURL`, `stateURL`, `questionsURL`): the app passes iCloud Drive and the user's files; the tests, two "Macs" in
/// temporary folders sharing one. The learned words are Rime's own sync (`RimeSync`), run by the app.
///
/// A run reads nothing but the config while sync is off, and nothing of iCloud while iCloud Drive isn't there. A
/// `settings.json` not downloaded yet stops what comes in and goes out (local changes are stamped meanwhile); one that
/// isn't JSON is set aside under a new name, never overwritten, and a new one written. The config file is written only
/// when a value from iCloud changes it, key by key (`AIConfig.writing`: its other keys, those this version doesn't know
/// too, keep their text), so the input method and Settings read it again as after any change.
public struct ICloudSyncEngine {
    public var folder: ICloudSyncFolder
    public var configURL: URL
    public var stateURL: URL
    public var questionsURL: URL
    public var environment: ICloudSync.Environment
    public var now: () -> Date

    public init(folder: ICloudSyncFolder, configURL: URL = Config.defaultURL, stateURL: URL = ICloudSync.State.defaultURL,
                questionsURL: URL = QuestionHistory.defaultURL, environment: ICloudSync.Environment = .init(),
                now: @escaping () -> Date = Date.init) {
        self.folder = folder
        self.configURL = configURL
        self.stateURL = stateURL
        self.questionsURL = questionsURL
        self.environment = environment
        self.now = now
    }

    /// What a run did.
    public struct Report: Equatable, Sendable {
        public enum Outcome: Equatable, Sendable {
            /// Sync is off on this Mac: nothing was read or written but the config.
            case off
            /// iCloud Drive isn't there (or can't be written): turned off in System Settings, or signed out.
            case unavailable
            case synced
            /// Something another Mac wrote isn't downloaded yet (iCloud was asked to): what could be done was.
            case waiting
            case failed(String)
        }

        public var outcome: Outcome
        /// The keys whose value from iCloud went into the config.
        public var applied: [String] = []
        /// The entries written into `settings.json`.
        public var uploaded: [String] = []
        /// Values from iCloud refused this run for the first time (each logged once), and why.
        public var rejected: [String: ICloudSync.Problem] = [:]
        /// All the values from iCloud refused now (`@doctor` lists them).
        public var refused: [String: ICloudSync.Problem] = [:]
        /// An unreadable `settings.json` set aside this run, by its new name.
        public var setAside: String?
        /// The config's top-level keys written (what to apply at once: the menu bar icon, fuzzy pinyin …).
        public var configKeys: Set<String> = []
        public var jargonChanged = false
        public var questionsChanged = false

        public init(outcome: Outcome) { self.outcome = outcome }
    }

    /// One run, now.
    public func run() -> Report {
        let now = self.now()
        let config: Config
        do {
            config = try Config.load(from: configURL)
        } catch {
            return Report(outcome: .failed(Self.describe(error)))
        }
        let settings = config.iCloudSync
        guard settings.enabled else { return Report(outcome: .off) }
        guard folder.isAvailable else { return Report(outcome: .unavailable) }
        var state = ICloudSync.State.load(from: stateURL)
        var report = Report(outcome: .synced)
        var waiting = false
        func fail(_ error: Error) -> Report {
            state.lastError = Self.describe(error)
            try? state.write(to: stateURL)
            return Report(outcome: .failed(state.lastError ?? ""))
        }

        // settings.json: here, coming down, or not there yet.
        var remote: ICloudSync.RemoteSettings?
        do {
            switch try folder.read(ICloudSync.settingsFile) {
            case .missing: remote = ICloudSync.RemoteSettings()
            case .placeholder: waiting = true
            case let .data(data):
                do {
                    remote = try ICloudSync.RemoteSettings.parse(data)
                } catch {
                    let aside = try folder.setAside(ICloudSync.settingsFile, now: now)
                    report.setAside = aside
                    state.setAside = aside
                    remote = ICloudSync.RemoteSettings()
                }
            }
        } catch {
            return fail(error)
        }

        // This Mac's values: the config's synced keys, and the two files as their hashes.
        var categories = settings.categories
        // Questions only where they are remembered at all.
        if !config.rememberQuestions { categories.remove(.recentQuestions) }
        var local = ICloudSync.values(of: config, in: categories)
        let jargonURL = config.jargonURL
        let jargon = categories.contains(.jargon) ? try? Data(contentsOf: jargonURL) : nil
        if let jargon { local[ICloudSync.jargonKey] = ICloudSync.fileValue(jargon) }
        let history = QuestionHistory.load(from: questionsURL)
        if categories.contains(.recentQuestions) { local[ICloudSync.questionsKey] = ICloudSync.fileValue(Self.encoded(history)) }
        let theirs = remote.map { ICloudSync.collapsingAppKeys($0.entries) }
        local = ICloudSync.matchingAppKeys(local, to: Array(state.entries.keys) + (theirs.map { Array($0.keys) } ?? []))
        // A change is stamped when its file changed (it may have been made while sync was off), at most now.
        let dates = (config: Self.modificationDate(configURL), jargon: Self.modificationDate(jargonURL),
                     questions: Self.modificationDate(questionsURL))
        var plan = ICloudSync.plan(local: local, known: state.entries, remote: theirs, categories: categories, mac: state.macID, now: now,
                                   changedAt: { key in
                                       key == ICloudSync.jargonKey ? dates.jargon : key == ICloudSync.questionsKey ? dates.questions : dates.config
                                   },
                                   ignoringLocalAbsence: [ICloudSync.jargonKey])

        // Values from iCloud into the config, each checked as Settings checks it.
        let incoming = plan.incoming.filter { ![ICloudSync.jargonKey, ICloudSync.questionsKey].contains($0.key) }
        var refused: [String: ICloudSync.State.Rejection] = [:]
        if !incoming.isEmpty {
            let result = ICloudSync.applying(incoming.mapValues(\.value), to: config, environment: environment)
            for (key, problem) in result.rejected {
                plan.entries[key] = plan.kept[key]
                guard let stamp = incoming[key]?.stamp else { continue }
                refused[key] = .init(stamp: stamp, problem: problem)
                if state.rejected[key]?.stamp != stamp { report.rejected[key] = problem }
            }
            // Recorded as this Mac writes them (a name this version doesn't know left out), with iCloud's stamps.
            let after = ICloudSync.matchingAppKeys(ICloudSync.values(of: result.config, in: categories), to: Array(incoming.keys))
            for key in result.applied {
                guard let stamp = incoming[key]?.stamp else { continue }
                plan.entries[key] = after[key].map { ICloudSync.Entry(value: $0, stamp: stamp) } ?? ICloudSync.Entry(value: nil, stamp: stamp)
            }
            let keys = AIConfig.changedKeys(config, result.config)
            if !keys.isEmpty {
                do {
                    try AIConfig.writing(result.config, from: config, keys: keys, at: configURL)
                } catch {
                    return fail(error)
                }
            }
            report.applied = result.applied
            report.configKeys = keys
        }

        // The jargon list: a newer one comes down once its file is here (and is the one stamped).
        if let entry = plan.incoming[ICloudSync.jargonKey] {
            if case let .data(data)? = try? folder.read(ICloudSync.jargonFile), ICloudSync.fileValue(data) == entry.value,
               ICloudSync.problem(ICloudSync.jargonKey, entry.value, environment: environment) == nil {
                do {
                    try FileManager.default.createDirectory(at: jargonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: jargonURL, options: .atomic)
                    report.jargonChanged = true
                } catch {
                    return fail(error)
                }
            } else {
                waiting = true
                plan.entries[ICloudSync.jargonKey] = plan.kept[ICloudSync.jargonKey]
            }
        }

        // Recent questions: a newer list comes down; changed on both Macs since they last synced, the two are merged
        // (newest first, whichever is newer). Until the file is here, nothing goes out over it.
        var questions: Data?
        let q = ICloudSync.questionsKey
        if plan.incoming[q] != nil || plan.bothChanged.contains(q), let entry = theirs?[q] {
            if case let .data(data)? = try? folder.read(ICloudSync.questionsFile), ICloudSync.fileValue(data) == entry.value,
               let other = Self.decodedHistory(data) {
                var merged = other
                if plan.bothChanged.contains(q) {
                    merged = QuestionHistory(entries: (history.entries + other.entries).sorted { $0.date > $1.date })
                    let mine = ICloudSync.Entry(value: ICloudSync.fileValue(Self.encoded(merged)), stamp: .init(modified: now, by: state.macID))
                    plan.entries[q] = mine
                    plan.outgoing[q] = mine
                    questions = Self.encoded(merged)
                }
                if merged != history {
                    do {
                        try merged.write(to: questionsURL)
                        report.questionsChanged = true
                    } catch {
                        return fail(error)
                    }
                }
            } else {
                // The record stays as it was: next time it is still a change on both sides.
                waiting = true
                plan.entries[q] = state.entries[q]
                plan.outgoing[q] = nil
            }
        } else if plan.outgoing[q] != nil {
            questions = Self.encoded(history)
        }

        // Out: the files first, then the entries that stamp them, then only the entries this Mac writes.
        if let remote, !plan.outgoing.isEmpty {
            do {
                if let entry = plan.outgoing[ICloudSync.jargonKey] {
                    if let jargon, ICloudSync.fileValue(jargon) == entry.value {
                        try folder.write(ICloudSync.jargonFile, jargon)
                    } else {
                        plan.outgoing[ICloudSync.jargonKey] = nil  // no list here to send (deleted on this Mac only)
                    }
                }
                if plan.outgoing[ICloudSync.questionsKey] != nil, let questions {
                    try folder.write(ICloudSync.questionsFile, questions)
                }
                if !plan.outgoing.isEmpty {
                    try folder.write(ICloudSync.settingsFile, remote.patched(with: plan.outgoing))
                    report.uploaded = plan.outgoing.keys.sorted()
                }
            } catch {
                return fail(error)
            }
        }

        state.entries = plan.entries
        // Refused values are checked again each run (a key saved since lets one in); while iCloud can't be read, the last
        // ones stand.
        state.rejected = remote == nil ? state.rejected : refused
        refused = state.rejected
        report.refused = refused.mapValues(\.problem)
        if waiting || remote == nil {
            report.outcome = .waiting
        } else {
            state.lastSync = now
            state.lastError = nil
        }
        do {
            try state.write(to: stateURL)
        } catch {
            return Report(outcome: .failed(Self.describe(error)))
        }
        return report
    }

    /// Forgets what this Mac synced (after "Remove from iCloud…"): turned on again, it joins as a Mac that never synced.
    public func forget() {
        let state = ICloudSync.State.load(from: stateURL)
        var fresh = ICloudSync.State(macID: state.macID)
        fresh.lastSync = nil
        try? fresh.write(to: stateURL)
    }

    /// The questions as `questions.json` holds them (the same on every Mac for the same questions).
    static func encoded(_ history: QuestionHistory) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(history)) ?? Data()
    }

    static func decodedHistory(_ data: Data) -> QuestionHistory? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(QuestionHistory.self, from: data)).map { QuestionHistory(entries: $0.entries) }
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

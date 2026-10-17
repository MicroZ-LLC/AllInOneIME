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
            /// Sync is off on this Mac: nothing of iCloud was read or written (this Mac's record notes it, so that turning
            /// it on again rejoins).
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
        /// This Mac's custom commands that iCloud's of the same name replaced when they were merged (logged).
        public var replacedCommands: [String] = []

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
        guard settings.enabled else {
            // Off: what it had synced rejoins when it is turned on again.
            var state = ICloudSync.State.load(from: stateURL)
            if state.hasSynced, state.paused != state.joined {
                state.paused = state.joined
                try? state.write(to: stateURL)
            }
            return Report(outcome: .off)
        }
        guard folder.isAvailable else { return Report(outcome: .unavailable) }
        var state = ICloudSync.State.load(from: stateURL)
        var report = Report(outcome: .synced)
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
            case .placeholder: break
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
        // The categories that are waiting for a file from iCloud (they don't count as synced yet).
        var waiting = Set<ICloudSync.Category>()

        // The categories synced now, each in its mode; those turned off since they synced rejoin later.
        var categories = settings.categories
        // Questions only where they are remembered at all.
        if !config.rememberQuestions { categories.remove(.recentQuestions) }
        state.paused.formUnion(state.joined.subtracting(categories))
        var modes: [ICloudSync.Category: ICloudSync.Mode] = [:]
        for category in categories {
            modes[category] = !state.joined.contains(category) ? .joining : state.paused.contains(category) ? .rejoining : .normal
        }

        // This Mac's values: the config's synced keys, and the jargon list as its hash. The recent questions are merged
        // on their own (below).
        var local = ICloudSync.values(of: config, in: categories)
        let jargonURL = config.jargonURL
        let jargon = categories.contains(.jargon) ? try? Data(contentsOf: jargonURL) : nil
        if let jargon { local[ICloudSync.jargonKey] = ICloudSync.fileValue(jargon) }
        let q = ICloudSync.questionsKey
        var theirs = remote.map { ICloudSync.collapsingAppKeys($0.entries) }
        let questionsEntry = theirs?[q]
        theirs?[q] = nil
        var known = state.entries
        known[q] = nil
        local = ICloudSync.matchingAppKeys(local, to: Array(known.keys) + (theirs.map { Array($0.keys) } ?? []))
        // A change is stamped when its file changed, at most now; not by the config file's time when that was sync's own
        // write.
        let configDate = Self.modificationDate(configURL)
        var own = false
        if let configDate, let written = state.ownConfigWrite { own = abs(configDate.timeIntervalSince(written)) < 0.002 }
        let dates = (config: own ? nil : configDate, jargon: Self.modificationDate(jargonURL))
        var plan = ICloudSync.plan(local: local, known: known, remote: theirs, categories: categories, modes: modes, mac: state.macID,
                                   now: now, changedAt: { $0 == ICloudSync.jargonKey ? dates.jargon : dates.config },
                                   ignoringLocalAbsence: [ICloudSync.jargonKey], refused: state.rejected.mapValues(\.stamp))

        // Collections to merge with iCloud's (joining, or changed here while off).
        var merged: [String: AIConfig.JSONValue] = [:]
        for (key, entry) in plan.merges where key != ICloudSync.jargonKey {
            guard let mine = local[key], let icloud = entry.value else { continue }
            if key == ICloudSync.commandsKey {
                let result = ICloudSync.mergedCommands(icloud, mine)
                merged[key] = result.value
                report.replacedCommands = result.replaced
            } else {
                merged[key] = ICloudSync.mergedWords(icloud, mine)
            }
        }

        // Values from iCloud (and merged ones) into the config, each checked as Settings checks it.
        let incoming = plan.incoming.filter { $0.key != ICloudSync.jargonKey }
        var refused: [String: ICloudSync.State.Rejection] = [:]
        if !incoming.isEmpty || !merged.isEmpty {
            var values = incoming.mapValues(\.value)
            for (key, value) in merged { values[key] = value }
            let result = ICloudSync.applying(values, to: config, environment: environment)
            for (key, problem) in result.rejected {
                plan.entries[key] = plan.kept[key] ?? state.entries[key]
                guard let stamp = (incoming[key] ?? plan.merges[key])?.stamp else { continue }
                refused[key] = .init(stamp: stamp, problem: problem)
                if state.rejected[key]?.stamp != stamp { report.rejected[key] = problem }
            }
            // Recorded as this Mac writes them (a name this version doesn't know left out), with iCloud's stamps; a merge
            // is a change of this Mac's, stamped now, and goes up.
            let after = ICloudSync.matchingAppKeys(ICloudSync.values(of: result.config, in: categories), to: Array(values.keys))
            for key in result.applied {
                if let entry = plan.merges[key] {
                    let mine = ICloudSync.Entry(value: after[key], stamp: .init(modified: now, by: state.macID))
                    plan.entries[key] = mine == entry ? entry : mine
                    if after[key] != entry.value { plan.outgoing[key] = mine } else { plan.entries[key] = entry }
                } else if let stamp = incoming[key]?.stamp {
                    plan.entries[key] = ICloudSync.Entry(value: after[key], stamp: stamp)
                }
            }
            let keys = AIConfig.changedKeys(config, result.config)
            if !keys.isEmpty {
                do {
                    try AIConfig.writing(result.config, from: config, keys: keys, at: configURL)
                } catch {
                    return fail(error)
                }
                state.ownConfigWrite = Self.modificationDate(configURL)
            }
            report.applied = result.applied.filter { incoming[$0] != nil }
            report.configKeys = keys
        }

        // The jargon list: a newer one (or a merge) once its file is here and is the one stamped.
        var jargonOut: Data?
        if let entry = plan.incoming[ICloudSync.jargonKey] ?? plan.merges[ICloudSync.jargonKey] {
            if case let .data(data)? = try? folder.read(ICloudSync.jargonFile), ICloudSync.fileValue(data) == entry.value,
               ICloudSync.problem(ICloudSync.jargonKey, entry.value, environment: environment) == nil {
                var list = data
                if plan.merges[ICloudSync.jargonKey] != nil, let jargon {
                    list = Data(ICloudSync.mergedJargon(String(decoding: data, as: UTF8.self), String(decoding: jargon, as: UTF8.self)).utf8)
                    let mine = ICloudSync.Entry(value: ICloudSync.fileValue(list), stamp: .init(modified: now, by: state.macID))
                    plan.entries[ICloudSync.jargonKey] = list == data ? entry : mine
                    if list != data {
                        plan.outgoing[ICloudSync.jargonKey] = mine
                        jargonOut = list
                    }
                }
                if list != jargon {
                    do {
                        try FileManager.default.createDirectory(at: jargonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try list.write(to: jargonURL, options: .atomic)
                        report.jargonChanged = true
                    } catch {
                        return fail(error)
                    }
                }
            } else {
                // Not here yet: this Mac's own list stays, and nothing goes over iCloud's.
                waiting.insert(.jargon)
                plan.entries[ICloudSync.jargonKey] = plan.kept[ICloudSync.jargonKey] ?? state.entries[ICloudSync.jargonKey]
                plan.outgoing[ICloudSync.jargonKey] = nil
            }
        } else if let entry = plan.outgoing[ICloudSync.jargonKey] {
            if let jargon, ICloudSync.fileValue(jargon) == entry.value {
                jargonOut = jargon
            } else {
                plan.outgoing[ICloudSync.jargonKey] = nil  // no list here to send (deleted on this Mac only)
            }
        }

        // Recent questions: always merged, both lists, newest first, a question once; a Clear anywhere drops every
        // question asked before it.
        var questionsOut: Data?
        if categories.contains(.recentQuestions) {
            switch syncQuestions(remote: remote != nil, entry: questionsEntry, state: &state, now: now) {
            case let .done(changed, upload):
                report.questionsChanged = changed
                if let upload {
                    questionsOut = upload
                    plan.outgoing[q] = ICloudSync.Entry(value: ICloudSync.fileValue(upload), stamp: .init(modified: now, by: state.macID))
                }
            case .waiting: waiting.insert(.recentQuestions)
            case let .failed(error): return fail(error)
            }
        }

        // Out: the files first, then the entries that stamp them, then only the entries this Mac writes.
        if let remote, !plan.outgoing.isEmpty {
            do {
                if let jargonOut, plan.outgoing[ICloudSync.jargonKey] != nil { try folder.write(ICloudSync.jargonFile, jargonOut) }
                if let questionsOut { try folder.write(ICloudSync.questionsFile, questionsOut) }
                try folder.write(ICloudSync.settingsFile, remote.patched(with: plan.outgoing))
                report.uploaded = plan.outgoing.keys.sorted()
            } catch {
                return fail(error)
            }
        }

        state.entries = plan.entries
        if let entry = plan.outgoing[q] ?? questionsEntry { state.entries[q] = entry }
        // Refused values are checked again each run (a key saved since lets one in); while iCloud can't be read, the last
        // ones stand.
        state.rejected = remote == nil ? state.rejected : refused
        report.refused = state.rejected.mapValues(\.problem)
        if remote == nil || !waiting.isEmpty {
            report.outcome = .waiting
        }
        if remote != nil {
            // Each category synced (none of its files still coming down) has joined, or rejoined.
            let done = categories.subtracting(waiting)
            state.joined.formUnion(done)
            state.paused.subtract(done)
            if waiting.isEmpty {
                state.lastSync = now
                state.lastError = nil
            }
        }
        do {
            try state.write(to: stateURL)
        } catch {
            return Report(outcome: .failed(Self.describe(error)))
        }
        return report
    }

    /// How the recent questions went.
    enum QuestionsResult {
        /// Merged: whether this Mac's list changed, and `questions.json` to put up (nil: iCloud's is the same).
        case done(changed: Bool, upload: Data?)
        case waiting
        case failed(Error)
    }

    /// The recent questions merged with iCloud's `questions.json` (`{ "entries": […], "cleared": ISO 8601 }`): the
    /// questions of both, newest first, a question once (its newest wording), at most `QuestionHistory.limit`, less every
    /// one asked before the newest Clear. A Clear here is told from this Mac's record (`State.questionsSeen`): questions it
    /// had when it last synced that are gone now, not pushed out by newer ones; it is dated by the newest of them, so a
    /// question asked anywhere after those survives it. Until iCloud's file is here, nothing is merged nor put up.
    func syncQuestions(remote: Bool, entry: ICloudSync.Entry?, state: inout ICloudSync.State, now: Date) -> QuestionsResult {
        let history = QuestionHistory.load(from: questionsURL)
        let mine = Dictionary(history.entries.map { (Self.questionHash($0.question), $0.date) }, uniquingKeysWith: max)
        var cleared = state.questionsCleared
        let gone = state.questionsSeen.filter { mine[$0.key] == nil }
        let pushedOut = history.entries.count >= QuestionHistory.limit
            && gone.values.allSatisfy { date in history.entries.allSatisfy { $0.date > date } }
        if let newest = gone.values.max(), !pushedOut { cleared = max(cleared ?? newest, newest) }
        state.questionsCleared = cleared
        guard remote else { return .waiting }
        var icloud: (history: QuestionHistory, cleared: Date?, data: Data)?
        switch try? folder.read(ICloudSync.questionsFile) {
        case let .data(data)?:
            guard entry == nil || ICloudSync.fileValue(data) == entry?.value, let read = Self.decodedQuestions(data) else { return .waiting }
            icloud = (read.history, read.cleared, data)
        case .placeholder?: return .waiting
        case .missing?, nil:
            if entry != nil { return .waiting }  // stamped, not here yet
        }
        let allCleared = [cleared, icloud?.cleared].compactMap { $0 }.max()
        let entries = (history.entries + (icloud?.history.entries ?? [])).filter { entry in allCleared.map { entry.date > $0 } ?? true }
        let merged = QuestionHistory(entries: entries.sorted { $0.date > $1.date })
        var changed = false
        if merged != history {
            do {
                try merged.write(to: questionsURL)
                changed = true
            } catch {
                return .failed(error)
            }
        }
        state.questionsSeen = Dictionary(merged.entries.map { (Self.questionHash($0.question), $0.date) }, uniquingKeysWith: max)
        state.questionsCleared = allCleared
        let data = Self.encodedQuestions(merged, cleared: allCleared)
        let unchanged = icloud.map { $0.data == data } ?? (merged.entries.isEmpty && allCleared == nil)
        return .done(changed: changed, upload: unchanged ? nil : data)
    }

    /// A question's key (`QuestionHistory.key`) as this Mac's record keeps it: hashed, never the text.
    static func questionHash(_ question: String) -> String {
        if case let .object(fields) = ICloudSync.fileValue(Data(QuestionHistory.key(question).utf8)), case let .string(hash)? = fields["sha256"] {
            return hash
        }
        return ""
    }

    /// Forgets what this Mac synced (after "Remove from iCloud…"): turned on again, it joins as a Mac that never synced.
    public func forget() {
        let state = ICloudSync.State.load(from: stateURL)
        var fresh = ICloudSync.State(macID: state.macID)
        fresh.lastSync = nil
        try? fresh.write(to: stateURL)
    }

    /// The questions as `questions.json` holds them (the same on every Mac for the same questions), with the newest Clear.
    static func encodedQuestions(_ history: QuestionHistory, cleared: Date?) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(history),
              case var .object(fields)? = (try? JSONSerialization.jsonObject(with: data)).flatMap(AIConfig.JSONValue.init) else { return Data() }
        if let cleared { fields["cleared"] = .string(ICloudSync.dateText(cleared)) }
        let out = JSONEncoder()
        out.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? out.encode(AIConfig.JSONValue.object(fields))) ?? Data()
    }

    static func decodedQuestions(_ data: Data) -> (history: QuestionHistory, cleared: Date?)? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let history = try? decoder.decode(QuestionHistory.self, from: data) else { return nil }
        var cleared: Date?
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let text = object["cleared"] as? String {
            cleared = ICloudSync.date(text)
        }
        return (QuestionHistory(entries: history.entries), cleared)
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

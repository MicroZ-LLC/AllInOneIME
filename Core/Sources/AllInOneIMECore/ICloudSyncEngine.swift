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
public struct ICloudSyncEngine: @unchecked Sendable {  // used from one queue at a time (the app's sync queue)
    public var folder: ICloudSyncFolder
    public var configURL: URL
    public var stateURL: URL
    public var questionsURL: URL
    public var environment: ICloudSync.Environment
    public var now: () -> Date
    /// This Mac's hardware (a hash of its platform UUID, `ICloudSync.machineID(platformUUID:)`): a record made on another
    /// Mac (copied by Migration Assistant) gets a Mac id of its own. The app gives it (the core can't read the hardware);
    /// the tests give their own. Nil: not known, and the record is taken as this Mac's.
    public var machineID: () -> String?
    /// How the config file is written (`ICloudSync.writeConfig`: a key changed in the file since the run read it is
    /// skipped); the keys written. The app writes it on the main thread, as Settings does, and tells Settings at once.
    public var writeConfig: (_ config: Config, _ old: Config, _ keys: Set<String>, _ url: URL) throws -> Set<String> = { config, old, keys, url in
        try ICloudSync.writeConfig(config, readAs: old, keys: keys, at: url)
    }

    public init(folder: ICloudSyncFolder, configURL: URL = Config.defaultURL, stateURL: URL = ICloudSync.State.defaultURL,
                questionsURL: URL = QuestionHistory.defaultURL, environment: ICloudSync.Environment = .init(),
                now: @escaping () -> Date = Date.init, machineID: @escaping () -> String? = { nil }) {
        self.folder = folder
        self.machineID = machineID
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
        /// All the values from iCloud refused now (Settings → Assistant's checks list them).
        public var refused: [String: ICloudSync.Problem] = [:]
        /// An unreadable `settings.json` set aside this run, by its new name.
        public var setAside: String?
        /// The config's top-level keys written (what to apply at once: the menu bar icon, fuzzy pinyin …).
        public var configKeys: Set<String> = []
        public var jargonChanged = false
        public var questionsChanged = false
        /// The categories that joined (their first sync here) this run.
        public var joining: Set<ICloudSync.Category> = []
        /// The categories still waiting for a file from iCloud (the others synced).
        public var waitingFor: Set<ICloudSync.Category> = []
        /// This Mac's record was made on another Mac (Migration Assistant): it got a Mac id of its own, and Rime's
        /// installation id should be made anew too.
        public var newMachine = false
        /// The recent-questions file on this Mac couldn't be read: set aside under this name, the questions not merged.
        public var questionsSetAside: String?
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
        // A record copied from another Mac (Migration Assistant): this Mac gets an id of its own.
        if let machine = machineID() {
            if let made = state.machine, made != machine {
                state.macID = UUID().uuidString
                report.newMachine = true
            }
            state.machine = machine
        }
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
        // A "Remove from iCloud…" that waited for settings.json: done now that it is here (unless turned on again).
        if remote != nil, !state.pendingRemovals.isEmpty {
            for category in state.pendingRemovals.sorted(by: { $0.rawValue < $1.rawValue }) {
                if settings.categories.contains(category) {
                    state.pendingRemovals.remove(category)
                } else if (try? removing(category, state: &state)) == true {
                    state.pendingRemovals.remove(category)
                    if case let .data(data)? = try? folder.read(ICloudSync.settingsFile) { remote = try? ICloudSync.RemoteSettings.parse(data) }
                }
            }
        }
        // The categories that are waiting for a file from iCloud (they don't count as synced yet).
        var waiting = Set<ICloudSync.Category>()

        // The categories synced now, each in its mode; those turned off since they synced rejoin later.
        var categories = settings.categories
        // Questions only where they are remembered at all.
        if !config.rememberQuestions { categories.remove(.recentQuestions) }
        state.paused.formUnion(state.joined.subtracting(categories))
        // Recent questions not synced now (not remembered, or the switch off): what went from here meanwhile is no Clear.
        if !categories.contains(.recentQuestions) { state.questionsSeen = [:] }
        var modes: [ICloudSync.Category: ICloudSync.Mode] = [:]
        for category in categories {
            modes[category] = !state.joined.contains(category) ? .joining : state.paused.contains(category) ? .rejoining : .normal
        }
        report.joining = Set(modes.filter { $0.value == .joining }.keys)

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
                    if after[key] == entry.value {
                        // iCloud's already holds all of this Mac's: taken as it is (a join's merge is settled).
                        plan.entries[key] = entry
                    } else {
                        let mine = ICloudSync.Entry(value: after[key], stamp: .init(modified: now, by: state.macID))
                        plan.outgoing[key] = mine
                        // A join's merge stays provisional (merged again, not replaced) until iCloud carries it; its
                        // `base` is the stamp it goes up with (a change made on top of it isn't merged again).
                        plan.entries[key] = plan.provisional.contains(key)
                            ? ICloudSync.Entry(value: after[key], stamp: .joining(state.macID), base: mine.stamp) : mine
                    }
                } else if let entry = incoming[key] {
                    // With the merge it derives from (`Entry.base`), for a change made here on top of it.
                    plan.entries[key] = ICloudSync.Entry(value: after[key], stamp: entry.stamp, base: entry.base)
                }
            }
            let keys = AIConfig.changedKeys(config, result.config)
            var written = Set<String>()
            // The sync keys Settings changed in the file meanwhile: not written, Settings' save kept.
            var skipped = Set<String>()
            if !keys.isEmpty {
                do {
                    written = try writeConfig(result.config, config, keys, configURL)
                } catch {
                    return fail(error)
                }
                if !written.isEmpty { state.ownConfigWrite = Self.modificationDate(configURL) }
                // Read back, sync key by sync key: `writeConfig` writes every item Settings didn't change (another app's
                // settings, a redaction switch, the hidden words are each their own), so a key the file doesn't hold as
                // the run wrote it is one Settings changed itself. That save stays, and goes up as this Mac's change next
                // run, recorded as the run found it: in a join, as the join keeps this Mac's value (`Plan.kept`: a
                // joining stamp, never over iCloud's real ones); a collection, joining or rejoining, as this Mac's list
                // with its joining stamp, so that the next run merges it with iCloud's again (never replaces it whole);
                // anything else as it was recorded before.
                let current = (try? Config.load(from: configURL)).map {
                    ICloudSync.matchingAppKeys(ICloudSync.values(of: $0, in: categories), to: Array(after.keys))
                }
                for key in result.applied where keys.contains(Self.topKey(key)) {
                    if let current {
                        if current[key] == after[key] { continue }
                    } else if written.contains(Self.topKey(key)) {
                        continue  // unreadable now: taken as written
                    }
                    skipped.insert(key)
                    plan.outgoing[key] = nil
                    let mode = ICloudSync.category(of: key).flatMap { modes[$0] } ?? .normal
                    if mode != .normal, ICloudSync.mergedOnJoin.contains(key), let value = local[key] {
                        plan.entries[key] = ICloudSync.Entry(value: value, stamp: .joining(state.macID))
                    } else if mode == .joining {
                        plan.entries[key] = plan.kept[key]
                    } else {
                        plan.entries[key] = state.entries[key]
                    }
                }
            }
            report.applied = result.applied.filter { incoming[$0] != nil && written.contains(Self.topKey($0)) && !skipped.contains($0) }
            report.configKeys = written
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
                    let provisional = ICloudSync.Entry(value: mine.value, stamp: .joining(state.macID), base: mine.stamp)
                    plan.entries[ICloudSync.jargonKey] = list == data ? entry
                        : plan.provisional.contains(ICloudSync.jargonKey) ? provisional : mine
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
        } else if let entry = theirs?[ICloudSync.jargonKey], let jargon, ICloudSync.fileValue(jargon) == entry.value {
            // iCloud's jargon.txt isn't the list its entry stamps (two Macs' files met), and this Mac has that one: it
            // goes up again, so that no Mac waits for it forever.
            // (A missing one may just not be listed here yet: waited for.)
            var again = false
            if case let .data(data)? = try? folder.read(ICloudSync.jargonFile) { again = ICloudSync.fileValue(data) != entry.value }
            if again {
                do { try folder.write(ICloudSync.jargonFile, jargon) } catch { return fail(error) }
            }
        }

        // Recent questions: always merged, both lists, newest first, a question once; a Clear anywhere drops every
        // question asked before it.
        var questionsOut: Data?
        if categories.contains(.recentQuestions) {
            switch syncQuestions(remote: remote != nil, entry: questionsEntry, state: &state, now: now, report: &report) {
            case .skipped: break
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
                if let questionsOut { try folder.write(ICloudSync.questionsFile, questionsOut, private: true) }
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
        report.waitingFor = waiting
        if remote == nil || !waiting.isEmpty {
            report.outcome = .waiting
        }
        if remote != nil {
            // Each category synced (none of its files still coming down) has joined, or rejoined; one waiting doesn't keep
            // the others from counting as synced.
            let done = categories.subtracting(waiting)
            state.joined.formUnion(done)
            state.paused.subtract(done)
            state.lastSync = now
            state.lastError = nil
        }
        // Known limit: a crash before this (config.json and settings.json written, the record not) leaves no record:
        // the next run joins again under a new Mac id, and what another Mac deleted meanwhile is merged back once.
        do {
            try state.write(to: stateURL)
        } catch {
            return Report(outcome: .failed(Self.describe(error)))
        }
        return report
    }

    /// The config file's top-level key a sync key is in ("appProfiles" for "appProfiles.<id>", "redaction" for the hidden
    /// words).
    static func topKey(_ key: String) -> String {
        if key.hasPrefix(ICloudSync.appPrefix) { return "appProfiles" }
        if key == ICloudSync.hiddenWordsKey { return "redaction" }
        if key == "inputLanguages" || key == "outputLanguages" { return key }
        return key
    }

    /// How the recent questions went.
    enum QuestionsResult {
        /// Merged: whether this Mac's list changed, and `questions.json` to put up (nil: iCloud's is the same).
        case done(changed: Bool, upload: Data?)
        case waiting
        /// This Mac's file couldn't be read: set aside, nothing merged this time.
        case skipped
        case failed(Error)
    }

    /// The recent questions merged with iCloud's `questions.json` (`{ "entries": […], "cleared": ISO 8601 }`): the
    /// questions of both, newest first, a question once (its newest wording), at most `QuestionHistory.limit`, less every
    /// one asked before the newest Clear.
    ///
    /// A Clear is recorded when the user clears them (`recordQuestionsClear`); one made while the input method wasn't
    /// running is told from this Mac's record (`State.questionsSeen`): questions it had when it last synced that are gone
    /// now, not pushed out by newer ones, dated by the newest of them. Questions deleted because "Remember recent
    /// questions" was turned off are no Clear (`forgetQuestionsSeen`). A file here that can't be read is set aside and
    /// nothing is merged this time (it is never taken as no questions); one in iCloud that can't be read is set aside as
    /// `settings.json` is. iCloud's file, readable, is merged whatever its entry says (two Macs' files may have met), and
    /// the merge goes up; one stamped but not here is waited for.
    func syncQuestions(remote: Bool, entry: ICloudSync.Entry?, state: inout ICloudSync.State, now: Date,
                       report: inout Report) -> QuestionsResult {
        var history = QuestionHistory()
        if FileManager.default.fileExists(atPath: questionsURL.path) {
            guard let data = try? Data(contentsOf: questionsURL), let read = Self.decodedQuestions(data) else {
                let folder = ICloudSyncFolder(url: questionsURL.deletingLastPathComponent())
                report.questionsSetAside = try? folder.setAside(questionsURL.lastPathComponent, now: now)
                state.questionsSeen = [:]
                return .skipped
            }
            history = read.history
        }
        // Deleted without a Clear (the mark is read after the file, so a deletion this run saw is always marked).
        if let mark = try? Data(contentsOf: forgottenURL) {
            state.questionsSeen = [:]
            if (try? Data(contentsOf: forgottenURL)) == mark { try? FileManager.default.removeItem(at: forgottenURL) }
        }
        let mine = Dictionary(history.entries.map { (Self.questionHash($0.question), $0.date) }, uniquingKeysWith: max)
        var cleared = state.questionsCleared
        let gone = state.questionsSeen.filter { mine[$0.key] == nil }
        let pushedOut = history.entries.count >= QuestionHistory.limit
            && gone.values.allSatisfy { date in history.entries.allSatisfy { $0.date > date } }
        if let newest = gone.values.max(), !pushedOut { cleared = max(cleared ?? newest, newest) }
        state.questionsCleared = cleared
        guard remote else { return .waiting }
        var icloud: (history: QuestionHistory, cleared: Date?, data: Data)?
        do {
            switch try folder.read(ICloudSync.questionsFile) {
            case let .data(data):
                if let read = Self.decodedQuestions(data) {
                    icloud = (read.history, read.cleared, data)
                } else {
                    report.setAside = try folder.setAside(ICloudSync.questionsFile, now: now)
                }
            case .placeholder: return .waiting
            case .missing:
                // Stamped, not here (maybe not listed here yet): waited for.
                if entry != nil { return .waiting }
            }
        } catch {
            return .failed(error)
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
        let unchanged = icloud.map { $0.data == data } ?? (merged.entries.isEmpty && allCleared == nil && entry == nil)
        return .done(changed: changed, upload: unchanged ? nil : data)
    }

    /// The user cleared the recent questions at `date` ("Clear" in Settings, not turning "Remember recent questions"
    /// off): every Mac drops the questions asked before it. Noted in this Mac's record, if it has one, and only while
    /// this Mac syncs the recent questions: a Clear made while it doesn't is this Mac's alone (turned on later, the other
    /// Macs' questions come back here).
    public func recordQuestionsClear(at date: Date) {
        guard FileManager.default.fileExists(atPath: stateURL.path), let config = try? Config.load(from: configURL),
              config.iCloudSync.categories.contains(.recentQuestions), config.rememberQuestions else { return }
        var state = ICloudSync.State.load(from: stateURL)
        state.questionsCleared = max(state.questionsCleared ?? date, date)
        try? state.write(to: stateURL)
    }

    /// The recent questions are about to be deleted here without a Clear ("Remember recent questions" turned off): what
    /// goes isn't cleared elsewhere. Called before the file is deleted, from any thread: it leaves a mark next to the
    /// record (`forgottenURL`) that a run reads after it reads the questions file, so even a run going on meanwhile never
    /// takes the deletion for a Clear.
    public func forgetQuestionsSeen() {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return }
        try? Data(ICloudSync.dateText(Date()).utf8).write(to: forgottenURL, options: .atomic)
    }

    /// The mark `forgetQuestionsSeen` leaves.
    var forgottenURL: URL { stateURL.deletingLastPathComponent().appendingPathComponent("questions-forgotten") }

    /// How "Remove from iCloud…" for the hidden words or the recent questions went.
    public enum Removal: Equatable, Sendable {
        case removed
        /// `settings.json` isn't downloaded yet: noted, and done by the next run that can read it.
        case waiting
    }

    /// "Remove from iCloud…" for the hidden words or the recent questions: their entry (and `questions.json`) taken out of
    /// iCloud, with the set-aside copies that hold them, every other entry as it is. Other Macs keep theirs; one still
    /// syncing them puts its own back. While `settings.json` isn't downloaded yet it waits (`State.pendingRemovals`).
    @discardableResult
    public func removeFromICloud(_ category: ICloudSync.Category) throws -> Removal {
        guard category == .hiddenWords || category == .recentQuestions else { return .removed }
        var state = ICloudSync.State.load(from: stateURL)
        let done = try removing(category, state: &state)
        if done { state.pendingRemovals.remove(category) } else { state.pendingRemovals.insert(category) }
        try? state.write(to: stateURL)
        return done ? .removed : .waiting
    }

    /// Takes `category` out of iCloud; false while `settings.json` isn't downloaded yet.
    func removing(_ category: ICloudSync.Category, state: inout ICloudSync.State) throws -> Bool {
        let key = category == .hiddenWords ? ICloudSync.hiddenWordsKey : ICloudSync.questionsKey
        let fm = FileManager.default
        if category == .recentQuestions, folder.exists {
            for name in [ICloudSync.questionsFile, ICloudSyncFolder.placeholderName(of: ICloudSync.questionsFile)] {
                let file = folder.url.appendingPathComponent(name)
                if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
            }
        }
        // The copies set aside when they couldn't be read may hold them too.
        for name in (try? fm.contentsOfDirectory(atPath: folder.url.path)) ?? [] {
            let file = folder.url.appendingPathComponent(name)
            if category == .recentQuestions, name.hasPrefix("questions (unreadable ") {
                try fm.removeItem(at: file)
            } else if category == .hiddenWords, name.hasPrefix("settings (unreadable "),
                      let data = try? Data(contentsOf: file), String(decoding: data, as: UTF8.self).contains(ICloudSync.hiddenWordsKey) {
                try fm.removeItem(at: file)
            }
        }
        switch try folder.read(ICloudSync.settingsFile) {
        case .placeholder: return false
        case .missing: break
        case let .data(data):
            if let remote = try? ICloudSync.RemoteSettings.parse(data), remote.entries[key] != nil || data.range(of: Data(key.utf8)) != nil {
                try folder.write(ICloudSync.settingsFile, remote.removing([key]))
            }
        }
        state.entries[key] = nil
        if category == .recentQuestions { state.questionsSeen = [:] }
        return true
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

import Foundation

/// What is learned on this device (Settings v2 §3.2), in one local store: the starting input each app learned and the
/// streaks toward one, the apps where typos couldn't be fixed and the suggestion rows picked (both kept here now), and
/// what `AutocompleteStore` and `TemperatureSupport` learned, reached through it. App identifiers, inputs, counts and
/// times only, never text; never in the config file, never synced. Safe from any thread.
///
/// Privacy → Learned… lists it (`items`), each row forgotten on its own (`forget`) or all at once (`forgetAll`). What is
/// changed is written to its file a moment later, off the caller's thread (`flush` writes it at once).
public final class LearnedStore: @unchecked Sendable {
    /// Where a shell keeps it: a file in the app's data folder (`CorePaths.dataDir`, Application Support).
    public static var defaultURL: URL { CorePaths.dataDir.appendingPathComponent("learned.json") }

    /// How many suggestion rows picked are kept: the latest.
    public static let picksKept = 500

    /// Where it is kept (nil: in memory only).
    public let file: URL?
    /// What autocomplete learned per app (the apps where it stopped), and the models that refuse a temperature: kept
    /// where they always were, reached through this store.
    public let autocomplete: AutocompleteStore
    public let temperature: TemperatureSupport

    private let contents: Locked<Contents>
    private let learns = Locked(initialState: true)
    /// What was changed waits to be written (`keepSoon`).
    private let writeWaiting = Locked(initialState: false)
    /// Where it is written: in order, off the caller's thread (a key's handling never waits for the disk).
    private static let writes = DispatchQueue(label: "com.aipinyin.learned.store", qos: .utility)

    /// The store kept in `file` (nil: in memory only), reaching what `autocomplete` and `temperature` learned.
    public init(file: URL?, autocomplete: AutocompleteStore, temperature: TemperatureSupport) {
        self.file = file
        self.autocomplete = autocomplete
        self.temperature = temperature
        contents = Locked(initialState: file.flatMap(Self.read) ?? Contents())
    }

    // MARK: The starting input (§3.1)

    /// Whether fields' switches teach it starting inputs (`corrected`); on. A shell's self-test turns it off where its
    /// checks switch inputs in field after field, each expecting the input its field starts in.
    public var learnsStartingInputs: Bool {
        get { learns.withLock { $0 } }
        set { learns.withLock { $0 = newValue } }
    }

    /// The starting input `app` learned (its id in any case), if it learned one.
    public func startingInput(in app: String?) -> Input? {
        guard let app, !app.isEmpty else { return nil }
        return contents.withLock { $0.startingInputs[app.lowercased()]?.input }
    }

    /// A field of `app` corrected with Shift before anything was typed in it, to `input` (§3.1): the app's streak goes on
    /// with it, or starts again with it; the second in a row, the app learns it. True when it learns it now (what is said
    /// once); false too when the app had learned it already.
    @discardableResult
    public func corrected(_ app: String, to input: Input, at date: Date = Date()) -> Bool {
        guard !app.isEmpty, learnsStartingInputs else { return false }
        let key = app.lowercased()
        let learned = contents.withLock { contents -> Bool in
            var streak = contents.streaks[key].flatMap { $0.input == input ? $0 : nil } ?? Streak(input: input, count: 0, last: date)
            streak.count = min(streak.count + 1, Self.inARow)
            streak.last = date
            contents.streaks[key] = streak
            guard streak.count >= Self.inARow, contents.startingInputs[key]?.input != input else { return false }
            contents.startingInputs[key] = StartingInput(app: app, input: input, learned: date)
            return true
        }
        keepSoon()
        return learned
    }

    /// How many fields in a row an app's fields are corrected to the same input before it learns it.
    static let inARow = 2

    // MARK: Typos and picked rows

    /// Remembers `app` as one where typos couldn't be fixed (the Mac's `TypoMemory` until now): true if it wasn't yet.
    /// Never an app without an id.
    @discardableResult
    public func turnTyposOff(in app: String, at date: Date = Date()) -> Bool {
        guard !app.isEmpty else { return false }
        let added = contents.withLock { contents -> Bool in
            guard contents.typosOff[app.lowercased()] == nil else { return false }
            contents.typosOff[app.lowercased()] = TyposOff(app: app, since: date)
            return true
        }
        if added { keepSoon() }
        return added
    }

    /// Whether `app` is one where typos couldn't be fixed (it gets none).
    public func typosOff(in app: String) -> Bool {
        contents.withLock { $0.typosOff[app.lowercased()] != nil }
    }

    /// The apps where typos couldn't be fixed, as they were told, in the order they were (those of one time by id).
    public var typosOffApps: [String] {
        contents.withLock { $0.typosOff.values.sorted { ($0.since, $0.app.lowercased()) < ($1.since, $1.app.lowercased()) }.map(\.app) }
    }

    /// The suggestion rows picked, oldest first (what `SuggestionsServices.loadPicks` gives), and keeping one: the
    /// latest `picksKept`.
    public var picks: [SuggestionPick] { contents.withLock { $0.picks } }

    public func recordPick(_ pick: SuggestionPick) {
        contents.withLock { $0.picks = Array(($0.picks + [pick]).suffix(Self.picksKept)) }
        keepSoon()
    }

    // MARK: What was learned before

    /// What this device learned before this store kept it (0.6.6 and earlier: the Mac's apps where typos couldn't be
    /// fixed and its suggestion-picks.json), moved in: added to what is here (the picks before it first), written at once.
    /// True when it is in the file now (or the store keeps no file): the shell may remove where it was.
    @discardableResult
    public func moveIn(typosOff apps: [String], picks: [SuggestionPick], at date: Date = Date()) -> Bool {
        guard !apps.isEmpty || !picks.isEmpty else { return true }
        contents.withLock { contents in
            for app in apps where !app.isEmpty && contents.typosOff[app.lowercased()] == nil {
                contents.typosOff[app.lowercased()] = TyposOff(app: app, since: date)
            }
            contents.picks = Array((picks + contents.picks).suffix(Self.picksKept))
        }
        guard let file else { return true }
        flush()
        return Self.read(file).map { kept in
            apps.allSatisfy { $0.isEmpty || kept.typosOff[$0.lowercased()] != nil } && kept.picks.count >= min(picks.count, Self.picksKept)
        } ?? false
    }

    // MARK: Privacy → Learned…

    /// Privacy → Learned…: a row for each thing learned, its text in the interface language, apps named by `appName`
    /// (else by their id): the starting inputs learned, the apps where autocomplete stopped, those with typos off, the
    /// suggestion rows picked (one row, how many), the models that don't take a temperature.
    public func items(appName: (String) -> String?) -> [LearnedItem] {
        let (inputs, typos, picked) = contents.withLock { ($0.startingInputs.values, $0.typosOff.values, $0.picks.count) }
        func name(_ app: String) -> String { appName(app) ?? app }
        func byName(_ a: String, _ b: String) -> Bool { name(a).localizedCaseInsensitiveCompare(name(b)) == .orderedAscending }
        var items: [LearnedItem] = []
        for learned in inputs.sorted(by: { byName($0.app, $1.app) }) {
            items.append(LearnedItem(kind: .startingInput(app: learned.app, input: learned.input)))
        }
        let stopped = autocomplete.learning.apps.filter(\.value.stopped).keys
        for app in stopped.sorted(by: byName) { items.append(LearnedItem(kind: .autocompleteStopped(app: app))) }
        for app in typos.map(\.app).sorted(by: byName) { items.append(LearnedItem(kind: .typosOff(app: app))) }
        if picked > 0 { items.append(LearnedItem(kind: .pickedRows(count: picked))) }
        for model in temperature.models {
            guard let colon = model.firstIndex(of: ":"), let provider = Provider(rawValue: String(model[..<colon])) else { continue }
            items.append(LearnedItem(kind: .noTemperature(provider: provider, model: String(model[model.index(after: colon)...]))))
        }
        return items.map { item in
            var item = item
            item.text = item.kind.text(name)
            return item
        }
    }

    /// Forget: `item` forgotten where it is kept (a learned starting input with its app's streak).
    public func forget(_ item: LearnedItem) {
        switch item.kind {
        case let .startingInput(app, _):
            contents.withLock { contents in
                contents.startingInputs[app.lowercased()] = nil
                contents.streaks[app.lowercased()] = nil
            }
        case let .autocompleteStopped(app):
            autocomplete.learn { $0.forget(app) }
        case let .typosOff(app):
            contents.withLock { _ = $0.typosOff.removeValue(forKey: app.lowercased()) }
        case .pickedRows:
            contents.withLock { $0.picks = [] }
        case let .noTemperature(provider, model):
            temperature.forget(provider, model: model)
        }
        keepSoon()
    }

    /// Forget All: every item, and every streak (autocomplete's learning in every app too).
    public func forgetAll() {
        contents.withLock { $0 = Contents() }
        autocomplete.learn { $0.restart() }
        temperature.forget()
        keepSoon()
    }

    // MARK: The file

    /// Writes to its file now what waits to be written. True when the file has it (or there is none).
    @discardableResult
    public func flush() -> Bool {
        guard file != nil else { return true }
        return Self.writes.sync { write() }
    }

    /// What was changed, written `writes`' next turn: one write for all that changes meanwhile.
    private func keepSoon() {
        guard file != nil else { return }
        let first = writeWaiting.withLock { waiting -> Bool in
            defer { waiting = true }
            return !waiting
        }
        guard first else { return }
        Self.writes.async { self.write() }
    }

    /// Writes what is kept now, on `writes`: each write the latest, in order.
    @discardableResult
    private func write() -> Bool {
        writeWaiting.withLock { $0 = false }
        let kept = contents.withLock { $0 }
        guard let file else { return true }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Platform.current.files.writePrivate(try encoder.encode(kept), to: file)
            return true
        } catch {
            Self.log.error("learned: not written (\(String(describing: type(of: error))))")
            return false
        }
    }

    private static func read(_ file: URL) -> Contents? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Contents.self, from: data)
    }

    static let log = CoreLog(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "ime")

    // MARK: What the file holds

    /// What this store keeps itself, as its file has it; apps by their id in lower case.
    struct Contents: Codable, Equatable {
        var startingInputs: [String: StartingInput] = [:]
        var streaks: [String: Streak] = [:]
        var typosOff: [String: TyposOff] = [:]
        var picks: [SuggestionPick] = []

        init() {}

        private enum CodingKeys: String, CodingKey {
            case startingInputs, streaks, typosOff, picks
        }

        /// Each part on its own, each entry on its own: one this version can't read (an input it doesn't know) is left
        /// out, the rest kept.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func entries<T: Decodable>(_ key: CodingKeys) -> [String: T] {
                let all = (try? c.decodeIfPresent([String: Lenient<T>].self, forKey: key)).flatMap { $0 } ?? [:]
                return all.compactMapValues(\.value)
            }
            startingInputs = entries(.startingInputs)
            streaks = entries(.streaks)
            typosOff = entries(.typosOff)
            picks = ((try? c.decodeIfPresent([Lenient<SuggestionPick>].self, forKey: .picks)).flatMap { $0 } ?? []).compactMap(\.value)
        }
    }

    /// A learned starting input: the app as the field told it, and when.
    struct StartingInput: Codable, Equatable {
        var app: String
        var input: Input
        var learned: Date

        private enum CodingKeys: String, CodingKey { case app, input, learned }

        init(app: String, input: Input, learned: Date) {
            (self.app, self.input, self.learned) = (app, input, learned)
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            app = try c.decode(String.self, forKey: .app)
            guard let input = Input(rawValue: try c.decode(String.self, forKey: .input)) else {
                throw DecodingError.dataCorruptedError(forKey: .input, in: c, debugDescription: "an input this version doesn't know")
            }
            self.input = input
            learned = try c.decode(Date.self, forKey: .learned)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(app, forKey: .app)
            try c.encode(input.rawValue, forKey: .input)
            try c.encode(learned, forKey: .learned)
        }
    }

    /// An app's fields corrected to `input` in a row: how many, the last when.
    struct Streak: Codable, Equatable {
        var input: Input
        var count: Int
        var last: Date

        private enum CodingKeys: String, CodingKey { case input, count, last }

        init(input: Input, count: Int, last: Date) {
            (self.input, self.count, self.last) = (input, count, last)
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let input = Input(rawValue: try c.decode(String.self, forKey: .input)) else {
                throw DecodingError.dataCorruptedError(forKey: .input, in: c, debugDescription: "an input this version doesn't know")
            }
            self.input = input
            count = try c.decode(Int.self, forKey: .count)
            last = try c.decode(Date.self, forKey: .last)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(input.rawValue, forKey: .input)
            try c.encode(count, forKey: .count)
            try c.encode(last, forKey: .last)
        }
    }

    /// An app where typos couldn't be fixed, as it was told, since when.
    struct TyposOff: Codable, Equatable {
        var app: String
        var since: Date
    }

    /// A value, or nil for one that can't be read (never an error).
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
}

/// One row of Privacy → Learned….
public struct LearnedItem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// "Slack: starts in English": `app` as the field told it.
        case startingInput(app: String, input: Input)
        /// "Autocomplete stopped in Mail" (`Autocomplete.Learning`): `app` as it keeps it.
        case autocompleteStopped(app: String)
        /// "Typos off in Terminal".
        case typosOff(app: String)
        /// "Suggestion rows you picked: 42".
        case pickedRows(count: Int)
        /// "Model x doesn't take temperature" (`TemperatureSupport.models`).
        case noTemperature(provider: Provider, model: String)
    }

    public var kind: Kind
    /// The row as the list shows it, in the interface language.
    public var text: String

    public init(kind: Kind, text: String = "") {
        self.kind = kind
        self.text = text
    }
}

extension LearnedItem.Kind {
    /// The row's text in the interface language, apps named by `name`.
    func text(_ name: (String) -> String) -> String {
        switch self {
        case let .startingInput(app, input):
            let input = SessionText.inputName(input, language: UIText.language, coding: nil)
            return tr("\(name(app))：用\(input)开始", "\(name(app)): starts in \(input)")
        case let .autocompleteStopped(app):
            return tr("续写在「\(name(app))」里停下了", "Autocomplete stopped in \(name(app))")
        case let .typosOff(app):
            return tr("「\(name(app))」里不打错字", "Typos off in \(name(app))")
        case let .pickedRows(count):
            return tr("选过的建议行：\(count)", "Suggestion rows you picked: \(count)")
        case let .noTemperature(_, model):
            return tr("模型 \(model) 不接受 temperature", "Model \(model) doesn't take temperature")
        }
    }
}

extension Config {
    /// The input a new text field of `app` starts in (Settings v2 §3.1): what the app learned (`LearnedStore`) where it
    /// can be typed now, else the app's own, else the default (`startingInput(in:among:code:)`).
    public func startingInput(in app: String?, among usable: [Language], code: Bool, learned: Input?) -> Input {
        if let learned, learned == .code ? code : learned.language.map(usable.contains) == true { return learned }
        return startingInput(in: app, among: usable, code: code)
    }
}

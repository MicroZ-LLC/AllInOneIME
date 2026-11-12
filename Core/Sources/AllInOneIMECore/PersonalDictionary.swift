import Foundation

/// A vocabulary file imported in Settings → Input → Chinese. Its Rime `name` is its identity:
/// importing that name again replaces the saved copy, even when the source file has another name.
public struct PersonalDictionary: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let fileName: String
    public let entryCount: Int
}

public enum PersonalDictionaryError: Error, LocalizedError {
    case invalid(String)
    case unsupported(String)
    case userFile
    case managedFile(String)

    public var errorDescription: String? {
        switch self {
        case let .invalid(reason):
            return tr("词库无效：", "Invalid dictionary: ") + reason
        case let .unsupported(reason):
            return tr("暂不支持这个词库：", "This dictionary isn't supported: ") + reason
        case .userFile:
            return tr("Rime 用户目录里有你自己的 rime_ice.custom.yaml，未改动任何文件。请先备份并移开它，再导入；需要保留其中的设置时，请在 Rime 中手动挂载词库。",
                      "The Rime user folder has your own rime_ice.custom.yaml; no files were changed. Back it up and move it aside before importing, or attach your dictionary in Rime manually to keep those settings.")
        case let .managedFile(path):
            return tr("无法安全更新个人词库文件：", "Couldn't safely update the personal dictionary files: ") + path
                + tr("。请先备份并检查 Rime 用户目录中的这个文件。", ". Back up and check this file in the Rime user folder first.")
        }
    }
}

/// Local, app-owned copies of leaf Rime vocabulary dictionaries. The generated dictionary imports
/// rime-ice as well as these tables; its translator keeps `rime_ice` as the learned-word database.
/// No user dictionary database, source file, or user-written customization is edited here.
///
/// Parsing is synchronous and can read up to 32 MiB: a UI caller should import on a worker queue.
/// All writes are serialized with fuzzy-pinyin changes, validated before mutation, and rolled back
/// if a write fails. One the app never finished (it quit or crashed partway: the manifest is written
/// last) is recovered from when the files are next read (`readState`). The caller redeploys Rime after
/// a successful import or removal.
public struct PersonalDictionaryStore: Sendable {
    public let userDirectory: URL
    public let schema: URL
    /// Called before each file is written or removed, with its URL: the tests', a write that fails (or the app that
    /// stops) partway. Nil: none.
    var beforeWrite: (@Sendable (URL) throws -> Void)?

    public init(userDirectory: URL, schema: URL) {
        self.userDirectory = userDirectory
        self.schema = schema
    }

    public func list() throws -> [PersonalDictionary] {
        try Self.locked { try readState().state.dictionaries.map(\.dictionary) }
    }

    /// The copies in the folder kept though they aren't listed: their list (the manifest) was lost, and they can't say what
    /// they are (`readState`). Never deleted, never used; Settings says so, by their file names.
    public func keptCopies() throws -> [String] {
        try Self.locked { try readState().state.kept.map { $0 + ".dict.yaml" } }
    }

    @discardableResult
    public func importDictionary(from source: URL, fuzzyPinyin: [String], characters: ChineseCharacters = .simplified,
                                 scheme: PinyinScheme = .full) throws -> PersonalDictionary {
        // Read and validate the entire source before touching the installed setup, outside the write lock.
        let parsed = try Parsed.read(source)
        return try Self.locked {
            let before = try readState().state
            try checkPatch(requireOwnership: true)
            try checkWrapper()
            let record = Stored(name: parsed.name, fileName: source.lastPathComponent, entryCount: parsed.entries.count,
                                token: "dict_" + UUID().uuidString.replacingOccurrences(of: "-", with: "_"))
            var after = before
            if let index = after.dictionaries.firstIndex(where: { $0.name == record.name }) {
                after.dictionaries[index] = record
            } else {
                after.dictionaries.append(record)
            }
            let table = tableURL(record)
            guard !FileManager.default.fileExists(atPath: table.path) else {
                throw PersonalDictionaryError.managedFile(table.lastPathComponent)
            }
            let says = Self.tableSays + String(decoding: try encodeLine(Said(name: record.name, fileName: record.fileName,
                                                                              entryCount: record.entryCount)), as: UTF8.self)
            var changes: [Change] = [Change(url: table, data: Data(parsed.table(named: reference(record), says: says).utf8))]
            changes += try configurationChanges(for: after, fuzzyPinyin: fuzzyPinyin, characters: characters, scheme: scheme,
                                                checkAlgebra: true)
            changes.append(Change(url: manifest, data: try encode(after)))
            try write(changes)
            removeUnlistedTables(after)
            return record.dictionary
        }
    }

    public func removeDictionary(named name: String, fuzzyPinyin: [String], characters: ChineseCharacters = .simplified,
                                 scheme: PinyinScheme = .full) throws {
        try Self.locked {
            let before = try readState().state
            guard before.dictionaries.contains(where: { $0.name == name }) else { return }
            try checkPatch(requireOwnership: true)
            try checkWrapper()
            var after = before
            after.dictionaries.removeAll { $0.name == name }
            var changes = try configurationChanges(for: after, fuzzyPinyin: fuzzyPinyin, characters: characters, scheme: scheme,
                                                   checkAlgebra: true)
            changes.append(Change(url: manifest, data: try encode(after)))
            try write(changes)
            removeUnlistedTables(after)
            if after.dictionaries.isEmpty { removeBuiltDictionary() }
        }
    }

    /// The shared writer used by FuzzyPinyin.apply too: a fuzzy toggle must keep every dictionary, and the characters
    /// (`characters`, `ChineseCharacters.patch`) go in the same file. With a Shuangpin scheme (`scheme`), the same patch
    /// for its schema too (`schemePatch`); with Zhuyin, its own (`zhuyinPatchText`).
    @discardableResult
    public func applyFuzzyPinyin(_ ids: [String], characters: ChineseCharacters = .simplified,
                                 scheme: PinyinScheme = .full) throws -> FuzzyPinyin.Outcome {
        try Self.locked {
            // The user's own file (or a link): left alone before anything else is read, as fuzzy pinyin always did,
            // whatever the dictionaries' files are like.
            guard try checkPatch(requireOwnership: false) else {
                let listed = (try? readState().state.dictionaries.isEmpty) == false
                return !listed && FuzzyPinyin.known(ids).isEmpty && !characters.isTraditional ? .unchanged : .userFile
            }
            let (state, recovered) = try readState()
            if !state.dictionaries.isEmpty { try checkWrapper() }
            // After a first import that never finished, its wrapper goes too (if it is this app's).
            let leftWrapper = recovered && state.dictionaries.isEmpty && (try? checkWrapper()) != nil
            var changes = try configurationChanges(for: state, fuzzyPinyin: ids, characters: characters, scheme: scheme,
                                                   checkAlgebra: false, includeWrapper: !state.dictionaries.isEmpty || leftWrapper)
            // Recovered: the manifest as it is now (the tables it lists all there).
            if recovered { changes.append(Change(url: manifest, data: try encode(state))) }
            let patchChange = changes.first { $0.url == patch }
            let previous = try contentsIfPresent(patch)
            let wanted = patchChange?.data
            // The wrapper repaired, or a Shuangpin scheme's or Zhuyin's patch written or removed: deployed again too.
            let schemePatches = Set(PinyinScheme.others.map(schemePatch))
            let otherChange = try changes.contains { change in
                guard change.url == wrapper || schemePatches.contains(change.url) else { return false }
                return try contentsIfPresent(change.url) != change.data
            }
            try write(changes)
            removeUnlistedTables(state)
            if state.dictionaries.isEmpty { removeBuiltDictionary() }
            if previous == wanted, !otherChange { return .unchanged }
            return wanted == nil ? .removed : .written
        }
    }

    // MARK: Owned files and the common Rime customization

    private static let lock = NSLock()
    private static func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    private static let folderName = "allinoneime_personal"
    private static let dictionaryName = "allinoneime_personal"
    private static let tableMarker = "# Written by AllInOneIME: personal dictionary. Edits here are replaced."
    /// A table's second line: what it is (`Stored` without its token, which is its file's name), so that the list can be
    /// made again from the tables when the manifest is lost (`readState`).
    private static let tableSays = "# AllInOneIME personal dictionary: "
    private static let wrapperMarker = "# Written by AllInOneIME: personal dictionaries. Edits here are replaced."
    /// The patch's first line is fuzzy pinyin's (`FuzzyPinyin.marker`) with the dictionaries too, so that an earlier
    /// version (0.6.6) still takes the file as its own, and its fuzzy pinyin switch works (it writes the file without
    /// them, and this version adds them again); the second says what else it holds.
    private static let patchDictionaries = "# And the personal dictionaries (Settings → Input → Chinese)."
    /// The line that says the patch has the filter of the candidates removed too (`withRemovedFilter`), and the filter,
    /// appended to the schema's own (librime's "/+"), so it comes after rime-ice's: it sees the text as shown.
    private static let patchRemoved = "# And the filter of the candidates removed (a right-click on one: Settings → Input → Chinese)."
    private static let removedFilter = "  engine/filters/+:\n    - lua_filter@*\(RemovedCandidates.luaFilter)\n"
    /// The first line 0.6.7's first builds wrote instead, which 0.6.6 took for the user's: still this app's.
    private static let earlyPatchMarker = "# Written by AllInOneIME: personal dictionaries and fuzzy pinyin (Settings → Input). Edits here are replaced."
    private var folder: URL { userDirectory.appendingPathComponent(Self.folderName, isDirectory: true) }
    private var manifest: URL { folder.appendingPathComponent("manifest.json") }
    private var wrapper: URL { userDirectory.appendingPathComponent(Self.dictionaryName + ".dict.yaml") }
    private var patch: URL { userDirectory.appendingPathComponent(FuzzyPinyin.fileName) }
    /// A Shuangpin scheme's patch (`PinyinScheme`): rime-ice's (`patch`), made for its schema; Zhuyin's, its own.
    private func schemePatch(_ scheme: PinyinScheme) -> URL { userDirectory.appendingPathComponent("\(scheme.schema).custom.yaml") }
    private func tableURL(_ item: Stored) -> URL { tableURL(token: item.token) }
    private func tableURL(token: String) -> URL { folder.appendingPathComponent(token + ".dict.yaml") }
    private func reference(_ item: Stored) -> String { Self.folderName + "/" + item.token }

    private struct State: Codable {
        var format = "AllInOneIME personal dictionaries v1"
        var dictionaries: [Stored] = []
        /// The tokens of tables kept unlisted (`keptCopies`): never removed by a change. Nil in a manifest without any.
        var keptTokens: [String]?

        var kept: [String] { keptTokens ?? [] }
    }

    private struct Stored: Codable {
        let name: String
        let fileName: String
        let entryCount: Int
        let token: String
        var dictionary: PersonalDictionary { PersonalDictionary(name: name, fileName: fileName, entryCount: entryCount) }
    }

    /// What a table says it is, on its second line (`tableSays`).
    private struct Said: Codable {
        let name: String
        let fileName: String
        let entryCount: Int
    }

    /// The dictionaries the manifest lists, each table checked as this app's. What a write the app never finished
    /// leaves is recovered from (`write` writes the tables first and the manifest last): a table the manifest lists that
    /// isn't there can't be loaded, and is left out. The folder without a manifest (a first import stopped after its
    /// table, a manifest lost: a backup restored without it) is listed again from its tables, each saying what it is on
    /// its second line (`tableSays`; of one name, the newest), in the order they were written; one of this app's that
    /// can't say (an early 0.6.7 build's) is kept as it is (`State.kept`): never listed, never removed. `recovered` says
    /// so: the next change writes the manifest again (`applyFuzzyPinyin` too, which Rime's start makes); each change
    /// removes the tables it neither lists nor keeps (`removeUnlistedTables`). A manifest that isn't this app's, or a
    /// table edited by hand, throws: those files are left for the user to look at.
    private func readState() throws -> (state: State, recovered: Bool) {
        do { try checkRegular(folder, directory: true) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return (State(), false) }
        guard let bytes = try contentsIfPresent(manifest) else { return (tablesSay(), true) }
        guard let state = try? JSONDecoder().decode(State.self, from: bytes),
              state.format == State().format,
              Set(state.dictionaries.map(\.name)).count == state.dictionaries.count,
              Set(state.dictionaries.map(\.token) + state.kept).count == state.dictionaries.count + state.kept.count,
              state.dictionaries.allSatisfy({ !$0.name.isEmpty && $0.entryCount > 0 && Self.isToken($0.token) }),
              state.kept.allSatisfy(Self.isToken) else {
            throw PersonalDictionaryError.managedFile(Self.folderName + "/manifest.json")
        }
        var found = state
        found.dictionaries = []
        // A copy kept that the user has since removed: no longer kept.
        let kept = state.kept.filter { (try? FileManager.default.attributesOfItem(atPath: tableURL(token: $0).path)) != nil }
        found.keptTokens = kept.isEmpty ? nil : kept
        for item in state.dictionaries {
            let table = tableURL(item)
            // Not there at all (not even a dangling link): left out.
            guard (try? FileManager.default.attributesOfItem(atPath: table.path)) != nil else { continue }
            try checkRegular(table)
            let handle = try FileHandle(forReadingFrom: table)
            defer { try? handle.close() }
            let marker = Data((Self.tableMarker + "\n").utf8)
            guard try handle.read(upToCount: marker.count) == marker else {
                throw PersonalDictionaryError.managedFile(reference(item) + ".dict.yaml")
            }
            found.dictionaries.append(item)
        }
        return (found, found.dictionaries.count != state.dictionaries.count || kept != state.kept)
    }

    /// The list as the folder's tables say it, for a folder without a manifest (`readState`): this app's tables (a token's
    /// name, the marker first), each by what its second line says, of one name the newest, oldest first; this app's that
    /// say nothing readable, kept.
    private func tablesSay() -> State {
        var found: [(stored: Stored, written: Date)] = [], kept: [String] = []
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names.sorted() where name.hasSuffix(".dict.yaml") {
            let token = String(name.dropLast(".dict.yaml".count))
            let table = folder.appendingPathComponent(name)
            guard Self.isToken(token), (try? checkRegular(table)) != nil, let handle = try? FileHandle(forReadingFrom: table) else { continue }
            let head = (try? handle.read(upToCount: 4096)) ?? Data()
            try? handle.close()
            let lines = String(decoding: head, as: UTF8.self).split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
            guard lines.first.map(String.init) == Self.tableMarker else { continue }  // not this app's: left alone
            guard lines.count > 2, lines[1].hasPrefix(Self.tableSays),
                  let said = try? JSONDecoder().decode(Said.self, from: Data(lines[1].dropFirst(Self.tableSays.count).utf8)),
                  Self.isName(said.name), !said.fileName.isEmpty, said.entryCount > 0 else {
                kept.append(token)
                continue
            }
            let written = (try? FileManager.default.attributesOfItem(atPath: table.path)[.modificationDate] as? Date) ?? .distantPast
            found.append((Stored(name: said.name, fileName: said.fileName, entryCount: said.entryCount, token: token), written))
        }
        var newest: [String: (stored: Stored, written: Date)] = [:]
        for item in found where newest[item.stored.name].map({ $0.written < item.written }) ?? true { newest[item.stored.name] = item }
        var state = State()
        state.dictionaries = newest.values.sorted { ($0.written, $0.stored.token) < ($1.written, $1.stored.token) }.map(\.stored)
        state.keptTokens = kept.isEmpty ? nil : kept
        return state
    }

    /// A dictionary's name as an import takes it: Latin letters, digits, "-", "_" and ".", at most 128 bytes, not "." or "..".
    private static func isName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 128 && name != "." && name != ".."
            && name.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0) }
    }

    private static func isToken(_ value: String) -> Bool {
        value.hasPrefix("dict_") && value.utf8.count == 41
            && value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
    }

    /// `said` as one line of JSON (a file's name with a line break in it too).
    private func encodeLine(_ said: Said) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(said)
    }

    private func encode(_ state: State) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(state)
    }

    /// False means the user's own file is there, left as is (fuzzy pinyin's existing behavior): one without this
    /// app's first line, or not a file (a link, even to nothing). `requireOwnership`: throws `userFile` then.
    @discardableResult
    private func checkPatch(requireOwnership: Bool) throws -> Bool {
        let owned: Bool
        if let attributes = try? FileManager.default.attributesOfItem(atPath: patch.path) {
            let bytes = attributes[.type] as? FileAttributeType == .typeRegular ? try Data(contentsOf: patch) : nil
            owned = bytes.map { bytes in [FuzzyPinyin.marker, Self.earlyPatchMarker].contains { bytes.starts(with: Data(($0 + "\n").utf8)) } }
                ?? false
        } else {
            owned = true  // none
        }
        if !owned, requireOwnership { throw PersonalDictionaryError.userFile }
        return owned
    }

    /// Whether `url`, a Shuangpin scheme's or Zhuyin's patch, is this app's to write or remove: none there, or one with its first line
    /// (`FuzzyPinyin.marker`). One without it (or a link) is the user's, left as it is.
    private func ownsSchemePatch(_ url: URL) throws -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return true }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { return false }
        return try Data(contentsOf: url).starts(with: Data((FuzzyPinyin.marker + "\n").utf8))
    }

    private func checkWrapper() throws {
        guard let data = try contentsIfPresent(wrapper) else { return }
        guard data.starts(with: Data((Self.wrapperMarker + "\n").utf8)) else {
            throw PersonalDictionaryError.managedFile(wrapper.lastPathComponent)
        }
    }

    private func configurationChanges(for state: State, fuzzyPinyin: [String], characters: ChineseCharacters,
                                      scheme: PinyinScheme = .full, checkAlgebra: Bool, includeWrapper: Bool = true) throws -> [Change] {
        let schemaText = (try? String(contentsOf: schema, encoding: .utf8)) ?? ""
        if checkAlgebra, !FuzzyPinyin.known(fuzzyPinyin).isEmpty, FuzzyPinyin.patch(fuzzyPinyin, schema: schemaText) == nil {
            throw PersonalDictionaryError.unsupported(tr("无法读取当前拼音方案的模糊音规则。", "The current pinyin schema's spelling rules couldn't be read."))
        }
        var changes: [Change] = []
        changes.append(Change(url: patch, data: patchText(for: state, fuzzyPinyin: fuzzyPinyin, characters: characters,
                                                          schemaText: schemaText).map { Data($0.utf8) }))
        // The Shuangpin scheme typed with: the same patch, made for its schema (its own spelling rules after fuzzy
        // pinyin's, its own place of the Traditional switch); Zhuyin, its own. The others' of this app's removed: only
        // what is used is deployed. The user's own left as they are.
        for other in PinyinScheme.others {
            let url = schemePatch(other)
            guard try ownsSchemePatch(url) else { continue }
            guard other == scheme else {
                changes.append(Change(url: url, data: nil))
                continue
            }
            let file = schema.deletingLastPathComponent().appendingPathComponent("\(other.schema).schema.yaml")
            let schemaText = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let text = other == .zhuyin ? zhuyinPatchText(characters: characters, schemaText: schemaText)
                : patchText(for: state, fuzzyPinyin: fuzzyPinyin, characters: characters, schemaText: schemaText)
            changes.append(Change(url: url, data: text.map { Data($0.utf8) }))
        }
        if state.dictionaries.isEmpty {
            if includeWrapper { changes.append(Change(url: wrapper, data: nil)) }
        } else {
            if includeWrapper {
                let base = try baseDictionary()
                let tables = state.dictionaries.map { reference($0) } + base.tables
                let revision = state.dictionaries.map(\.token).joined(separator: "_")
                let dictionary = Self.wrapperMarker + "\n---\nname: \(Self.dictionaryName)\nversion: \"\(revision)\"\n" + base.settings + "import_tables:\n"
                    + tables.map { "  - " + $0 + "\n" }.joined() + "...\n"
                changes.insert(Change(url: wrapper, data: Data(dictionary.utf8)), at: 0)
            }
        }
        // What librime compiled of a patch is left alone here: a deployment may be under way (`datePatches` makes the next
        // one compile what changed).
        return changes
    }

    // MARK: Deploying what was written

    /// The Rime sources this app writes in the user folder, each with what librime compiles of it into `build/` and the
    /// first line it has when it is this app's: the schema list (`PinyinScheme.applySchemaList`), rime-ice's patch and
    /// each other way of typing's (`PinyinScheme.others`).
    static func compiledSources(_ userDirectory: URL) -> [(source: URL, compiled: URL, marker: String)] {
        let build = userDirectory.appendingPathComponent("build", isDirectory: true)
        let schemas = [PinyinScheme.fullSchema] + PinyinScheme.others.map(\.schema)
        return [(userDirectory.appendingPathComponent("default.custom.yaml"), build.appendingPathComponent("default.yaml"),
                 PinyinScheme.schemaListMarker)]
            + schemas.map { (userDirectory.appendingPathComponent("\($0).custom.yaml"), build.appendingPathComponent("\($0).schema.yaml"),
                             FuzzyPinyin.marker) }
    }

    /// Readies this app's Rime sources for a deployment about to start, while librime isn't deploying (`RimeService`
    /// calls it right before): librime compiles a source again when its time differs from the one it recorded in what it
    /// compiled (`__build_info`), in whole seconds, so a source this app wrote in the second librime recorded for it (a
    /// quick import or fuzzy pinyin toggle, or one written while that deployment ran) would be taken for unchanged. Each
    /// written since `since` (the last deployment's start; nil: since what was compiled of it) and in that second is dated
    /// the next one; with `all`, each in that second, written since or not (a redeploy asked to compile them all again).
    /// What librime compiled stays: a source not compiled yet, or the user's own (without this app's first line), is left
    /// as it is. Removing the compiled schema instead, when the patch was written, raced with a deployment under way: its
    /// dictionary found no schema to read the spellings from ("error loading prism definition", "failed to compile").
    /// Throws when a source's time can't be set.
    public static func datePatches(userDirectory: URL, since: Date?, all: Bool = false) throws {
        let fm = FileManager.default
        for (source, compiled, marker) in compiledSources(userDirectory) {
            guard let attributes = try? fm.attributesOfItem(atPath: source.path),
                  attributes[.type] as? FileAttributeType == .typeRegular, let written = attributes[.modificationDate] as? Date,
                  let built = try? fm.attributesOfItem(atPath: compiled.path),
                  built[.type] as? FileAttributeType == .typeRegular, let builtAt = built[.modificationDate] as? Date,
                  let recorded = recordedTime(of: source.deletingPathExtension().lastPathComponent, in: compiled),
                  let handle = try? FileHandle(forReadingFrom: source) else { continue }
            let head = (try? handle.read(upToCount: marker.utf8.count + 1)) ?? Data()
            try? handle.close()
            guard head == Data((marker + "\n").utf8) else { continue }
            let second = written.timeIntervalSince1970.rounded(.down)
            guard second == Double(recorded), all || written > min(builtAt, since ?? builtAt) else { continue }
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: second + 1)], ofItemAtPath: source.path)
        }
    }

    /// The time librime recorded for the source `id` ("rime_ice.custom") in what it compiled (`compiled`'s
    /// `__build_info/timestamps`, at its top); nil when it records none.
    static func recordedTime(of id: String, in compiled: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: compiled) else { return nil }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 16 * 1024)) ?? Data(), as: UTF8.self)
        var section = ""
        for line in head.split(separator: "\n") {
            let indent = line.prefix(while: { $0 == " " }).count
            let content = line.trimmingCharacters(in: .whitespaces)
            switch indent {
            case 0: guard content == "__build_info:" else { return nil }
            case 2: section = content
            default:
                guard section == "timestamps:", let colon = content.lastIndex(of: ":") else { continue }
                let key = content[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                if key == id { return Int(content[content.index(after: colon)...].trimmingCharacters(in: .whitespaces)) }
            }
        }
        return nil
    }

    /// The patch of a schema (`schemaText`, rime-ice's or a Shuangpin scheme's) for these settings: fuzzy pinyin's rules
    /// before the schema's own, the personal dictionaries, the characters, the filter of the candidates removed; nil when
    /// it has none of them.
    private func patchText(for state: State, fuzzyPinyin: [String], characters: ChineseCharacters, schemaText: String) -> String? {
        let fuzzy = FuzzyPinyin.patch(fuzzyPinyin, schema: schemaText)
        // Traditional characters: lines of their own at the end of the patch, whatever else it holds.
        let traditional = characters.patch(schema: schemaText)
        if state.dictionaries.isEmpty {
            let text = fuzzy == nil && traditional == nil ? nil
                : (fuzzy ?? FuzzyPinyin.marker + "\npatch:\n") + (traditional ?? "")
            return withRemovedFilter(text)
        }
        let header = FuzzyPinyin.marker + "\n" + Self.patchDictionaries + "\n"
        var text = fuzzy.map { header + $0.dropFirst(FuzzyPinyin.marker.count + 1) } ?? header + "patch:\n"
        // The dictionary changes; the database of learned words deliberately keeps its old identity.
        text += "  translator/dictionary: \(Self.dictionaryName)\n  translator/user_dict: rime_ice\n"
        text += traditional ?? ""
        return withRemovedFilter(text)
    }

    /// Zhuyin's patch (`PinyinScheme.zhuyin`, rime-bopomofo's schema: `schemaText`): its characters (its own switch,
    /// `ChineseCharacters.patch`), the filter of the candidates removed, and its translators without rime-ice's custom
    /// phrases (custom_phrase.txt beside them, in pinyin letters and Simplified characters, which its schema would find
    /// by Zhuyin's keys: "u", ㄧ, would offer 有). Not fuzzy pinyin, nor the personal dictionaries: those are pinyin
    /// spellings of rime-ice's dictionary, which Zhuyin's (terra_pinyin, in Traditional characters, with tones) isn't.
    /// The translators are the schema's own but that one (rime-bopomofo's at the commit the Makefile pins). Nil without
    /// the schema (nothing to patch).
    private func zhuyinPatchText(characters: ChineseCharacters, schemaText: String) -> String? {
        guard !schemaText.isEmpty else { return nil }
        let translators = "  # Without rime-ice's custom phrases (custom_phrase.txt: pinyin letters, which would be Zhuyin keys here).\n"
            + "  engine/translators: [ punct_translator, reverse_lookup_translator, script_translator ]\n"
        // A tap of Shift: what is composed goes in converted, as macOS's own Zhuyin has it, not the keys typed (rime-ice's
        // default.yaml: `Shift_L: commit_code`). The schema's map replaces default.yaml's whole: its other keys as rime-ice's.
        let shift = "  # A tap of Shift commits what is composed, converted (rime-ice's: the keys typed).\n"
            + "  ascii_composer/switch_key: { Caps_Lock: clear, Shift_L: commit_text, Shift_R: commit_text, Control_L: noop, Control_R: noop }\n"
        return withRemovedFilter(FuzzyPinyin.marker + "\npatch:\n" + translators + shift + (characters.patch(schema: schemaText) ?? ""))
    }

    /// `text`, the patch (nil: none), with AllInOneIME's filter of the candidates removed (`RemovedCandidates.luaFilter`)
    /// last, when the shared data's Lua has it (`lua/` beside the schema: on the Mac the app's scripts, linked into the
    /// pack); without a patch, one of the filter alone. Where it hasn't (Windows ships rime-ice's alone), the patch is as
    /// it was, and `EnglishWordsEngine` leaves them out of what librime shows: a Lua filter librime can't load leaves no
    /// candidate at all.
    private func withRemovedFilter(_ text: String?) -> String? {
        let script = schema.deletingLastPathComponent().appendingPathComponent("lua/\(RemovedCandidates.luaFilter).lua")
        guard FileManager.default.fileExists(atPath: script.path) else { return text }
        let text = text ?? FuzzyPinyin.marker + "\npatch:\n"
        guard let start = text.range(of: "\npatch:\n") else { return text }
        return String(text[..<start.lowerBound]) + "\n" + Self.patchRemoved + String(text[start.lowerBound...]) + Self.removedFilter
    }

    /// `import_tables` imports direct rows, not another dictionary's imports. Flatten the current
    /// rime-ice table graph, retaining each dictionary's own rows as well. Header reads stop before
    /// vocabulary data, so even the large supplied tables need only a small read.
    private func baseDictionary() throws -> (tables: [String], settings: String) {
        var tables: [String] = [], visited = Set<String>(), active = Set<String>()
        var rootHeader = ""
        func visit(_ name: String) throws {
            guard CorePaths.isPlainRelative(name), !name.contains(".."), name != Self.dictionaryName,
                  name.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 47, 95].contains($0) }),
                  !active.contains(name) else { throw PersonalDictionaryError.managedFile(name + ".dict.yaml") }
            guard !visited.contains(name) else { return }
            active.insert(name)
            let relative = name + ".dict.yaml"
            let own = userDirectory.appendingPathComponent(relative)
            let shared = schema.deletingLastPathComponent().appendingPathComponent(relative)
            let file = FileManager.default.fileExists(atPath: own.path) ? own : shared
            let header = try dictionaryHeader(file)
            if name == "rime_ice" { rootHeader = header }
            var imports = EnglishDictionary.importedTables(header)
            if let line = header.components(separatedBy: "\n").first(where: { $0.hasPrefix("import_tables:") }) {
                let inline = try Parsed.uncomment(String(line.dropFirst("import_tables:".count)).trimmingCharacters(in: .whitespaces), line: 1)
                if !inline.isEmpty { imports = try Parsed.flowList(inline, line: 1) }
            }
            for imported in imports { try visit(imported) }
            active.remove(name)
            visited.insert(name)
            tables.append(name)
        }
        try visit("rime_ice")

        // Preserve the base dictionary's preset-vocabulary/encoder settings and other header
        // properties. Only its identity, version and import list belong to the generated wrapper.
        var settings: [String] = [], inHeader = false, skip = false
        for line in rootHeader.components(separatedBy: "\n") {
            let content = line.trimmingCharacters(in: .whitespaces)
            if content == "---" { inHeader = true; continue }
            if content == "..." { break }
            guard inHeader else { continue }
            if !line.hasPrefix(" "), !content.isEmpty, !content.hasPrefix("#"), let colon = content.firstIndex(of: ":") {
                skip = ["name", "version", "import_tables"].contains(String(content[..<colon]))
            }
            if !skip { settings.append(line) }
        }
        return (tables, settings.isEmpty ? "" : settings.joined(separator: "\n") + "\n")
    }

    private func dictionaryHeader(_ file: URL) throws -> String {
        try checkRegular(file)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var bytes = Data()
        while bytes.count < 1024 * 1024 {
            guard let chunk = try handle.read(upToCount: 16 * 1024), !chunk.isEmpty else { break }
            bytes.append(chunk)
            let text = String(decoding: bytes, as: UTF8.self)
            if let end = text.range(of: #"(?m)^\.\.\.[ \t]*\r?$"#, options: .regularExpression) {
                return String(text[..<end.upperBound])
            }
        }
        throw PersonalDictionaryError.managedFile(file.lastPathComponent)
    }

    private func checkRegular(_ url: URL, directory: Bool = false) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == (directory ? .typeDirectory : .typeRegular) else {
            throw PersonalDictionaryError.managedFile(url.lastPathComponent)
        }
    }

    private func contentsIfPresent(_ url: URL) throws -> Data? {
        // attributesOfItem sees a dangling link too; fileExists alone would mistake it for a new path.
        do {
            try checkRegular(url)
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    private struct Change { let url: URL; let data: Data? }

    private func write(_ changes: [Change]) throws {
        let fm = FileManager.default
        // Snapshot and validate every target before creating or changing anything.
        let originals = try changes.map { try contentsIfPresent($0.url) }
        let needsFolder = changes.contains { $0.url.deletingLastPathComponent() == folder }
        let hadUserDirectory = fm.fileExists(atPath: userDirectory.path)
        let hadFolder = fm.fileExists(atPath: folder.path)
        if hadFolder { try checkRegular(folder, directory: true) }
        var attempted = 0
        do {
            try fm.createDirectory(at: userDirectory, withIntermediateDirectories: true)
            if needsFolder { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
            for (index, change) in changes.enumerated() {
                attempted = index + 1
                guard originals[index] != change.data else { continue }
                try beforeWrite?(change.url)
                if let data = change.data { try data.write(to: change.url, options: .atomic) }
                else if originals[index] != nil { try fm.removeItem(at: change.url) }
            }
        } catch {
            for index in (0..<attempted).reversed() {
                if let data = originals[index] { try? data.write(to: changes[index].url, options: .atomic) }
                else { try? fm.removeItem(at: changes[index].url) }
            }
            if !hadFolder, needsFolder { try? fm.removeItem(at: folder) }
            if !hadUserDirectory, (try? fm.contentsOfDirectory(atPath: userDirectory.path).isEmpty) == true {
                try? fm.removeItem(at: userDirectory)
            }
            throw error
        }
    }

    /// The tables in the folder `state` doesn't list: one replaced or removed, and a new one whose import never
    /// finished. Only this app's (a token's name, the marker first), and never one kept (`State.kept`); a failed cleanup
    /// only leaves an unreferenced table, which can't change the active vocabulary or erase user data.
    private func removeUnlistedTables(_ state: State) {
        let fm = FileManager.default
        let listed = Set((state.dictionaries.map(\.token) + state.kept).map { $0 + ".dict.yaml" })
        let marker = Data((Self.tableMarker + "\n").utf8)
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where !listed.contains(name) {
            guard name.hasSuffix(".dict.yaml"), Self.isToken(String(name.dropLast(".dict.yaml".count))) else { continue }
            let table = folder.appendingPathComponent(name)
            guard (try? checkRegular(table)) != nil, let handle = try? FileHandle(forReadingFrom: table) else { continue }
            let owned = (try? handle.read(upToCount: marker.count)) == marker
            try? handle.close()
            if owned { try? fm.removeItem(at: table) }
        }
    }

    /// What Rime built of the wrapper (its words and rime-ice's, as large as rime-ice's own), once no dictionary is left:
    /// nothing uses it any more, and Rime never removes it. Only the wrapper's files; a failure (one in use on Windows)
    /// leaves them for the next time.
    private func removeBuiltDictionary() {
        let build = userDirectory.appendingPathComponent("build", isDirectory: true)
        for kind in ["table", "prism", "reverse"] {
            let built = build.appendingPathComponent("\(Self.dictionaryName).\(kind).bin")
            guard (try? checkRegular(built)) != nil else { continue }
            try? FileManager.default.removeItem(at: built)
        }
    }

    // MARK: Deliberately limited dictionary format

    private struct Entry {
        let text: String
        let code: String
        let weight: String
    }

    private struct Parsed {
        let name: String
        let sort: String
        let entries: [Entry]

        static func read(_ source: URL) throws -> Parsed {
            guard source.lastPathComponent.lowercased().hasSuffix(".dict.yaml") else {
                throw PersonalDictionaryError.unsupported(tr("请选择 .dict.yaml 文件。", "Choose a .dict.yaml file."))
            }
            let size = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard size.isRegularFile == true else {
                throw PersonalDictionaryError.invalid(tr("请选择一个词库文件。", "Choose a dictionary file."))
            }
            guard (size.fileSize ?? 0) <= 32 * 1024 * 1024 else {
                throw PersonalDictionaryError.unsupported(tr("文件不能超过 32 MiB。", "The file must be at most 32 MiB."))
            }
            let bytes = try Data(contentsOf: source)
            guard bytes.count <= 32 * 1024 * 1024, var text = String(data: bytes, encoding: .utf8), !text.contains("\0") else {
                throw PersonalDictionaryError.invalid(tr("文件必须是 UTF-8 文本，且不能含有 NUL 字符。", "The file must be UTF-8 text without NUL characters."))
            }
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n")
            var started = false, ended = false, name: String?, sort = "by_weight"
            var columns: [String]?, listKey: String?, keys = Set<String>(), rows: [(Int, String)] = []
            for (offset, line) in lines.enumerated() {
                let number = offset + 1
                let content = line.trimmingCharacters(in: .whitespaces)
                if content.isEmpty || content.hasPrefix("#") { continue }
                if ended { rows.append((number, line)); continue }
                if !started {
                    guard content == "---" else { throw invalidLine(number, tr("缺少 --- 词库头。", "Missing the --- dictionary header.")) }
                    started = true; continue
                }
                if content == "..." { ended = true; continue }
                let header = try uncomment(content, line: number)
                if line.first?.isWhitespace == true {
                    guard let listKey, header.hasPrefix("- ") else {
                        throw unsupportedLine(number, tr("只支持简单的词库头和 columns 列表。", "Only a simple dictionary header and columns list are supported."))
                    }
                    if listKey == "import_tables" {
                        throw unsupportedLine(number, tr("请导入直接包含词条的词库，不能依赖 import_tables 中的其他文件。", "Import a file containing its own entries, without dependencies in import_tables."))
                    }
                    columns!.append(try scalar(String(header.dropFirst(2)), line: number))
                    continue
                }
                listKey = nil
                guard let colon = header.firstIndex(of: ":") else { throw invalidLine(number, tr("词库头需要 key: value。", "The dictionary header needs key: value.")) }
                let key = String(header[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(header[header.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                guard keys.insert(key).inserted else { throw invalidLine(number, tr("词库头包含重复字段。", "The dictionary header has a duplicate field.")) }
                switch key {
                case "name": name = try scalar(value, line: number)
                case "version": _ = try scalar(value, line: number)
                case "sort":
                    sort = try scalar(value, line: number)
                    guard ["original", "by_weight"].contains(sort) else { throw unsupportedLine(number, "sort: " + sort) }
                case "columns":
                    if value.isEmpty { columns = []; listKey = key }
                    else { columns = try flowList(value, line: number) }
                case "import_tables":
                    if value.isEmpty { listKey = key }
                    else if try !flowList(value, line: number).isEmpty {
                        throw unsupportedLine(number, tr("请导入直接包含词条的词库，不能依赖 import_tables 中的其他文件。", "Import a file containing its own entries, without dependencies in import_tables."))
                    }
                case "use_preset_vocabulary":
                    guard value == "false" else { throw unsupportedLine(number, tr("每条词条都必须带明确的拼音编码。", "Every entry must have an explicit pinyin code.")) }
                default:
                    throw unsupportedLine(number, tr("不支持词库头字段：", "Unsupported dictionary header field: ") + key)
                }
            }
            guard started, ended, let name, !name.isEmpty else {
                throw PersonalDictionaryError.invalid(tr("词库头必须包含 name，并以 --- 和 ... 分隔。", "The dictionary header must contain name and be delimited by --- and ... ."))
            }
            guard PersonalDictionaryStore.isName(name) else {
                throw PersonalDictionaryError.unsupported(tr("name 只能包含英文字母、数字、-、_ 和 .，最多 128 字节。", "name may contain Latin letters, digits, -, _ and ., up to 128 bytes."))
            }
            let layout = columns ?? ["text", "code", "weight"]
            guard Set(layout) == Set(["text", "code"]) || Set(layout) == Set(["text", "code", "weight"]), Set(layout).count == layout.count else {
                throw PersonalDictionaryError.unsupported(tr("columns 必须是 text、code，以及可选的 weight，每种只出现一次。", "columns must contain text, code and optionally weight, each exactly once."))
            }
            let textIndex = layout.firstIndex(of: "text")!, codeIndex = layout.firstIndex(of: "code")!
            let weightIndex = layout.firstIndex(of: "weight")
            var entries: [Entry] = [], seen = Set<String>()
            for (number, line) in rows {
                let fields = line.components(separatedBy: "\t")
                let missingLastWeight = weightIndex == layout.count - 1 && fields.count == layout.count - 1
                guard fields.count == layout.count || missingLastWeight,
                      fields.indices.contains(textIndex), fields.indices.contains(codeIndex) else {
                    throw invalidLine(number, tr("词条需要按 columns 顺序用 Tab 分隔。", "Separate the entry's fields with tabs, in columns order."))
                }
                let phrase = fields[textIndex]
                let code = fields[codeIndex].split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
                guard !phrase.trimmingCharacters(in: .whitespaces).isEmpty,
                      phrase.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }), !code.isEmpty,
                      code.utf8.allSatisfy({ (97...122).contains($0) || $0 == 32 }) else {
                    throw invalidLine(number, tr("词条必须有文字和小写拼音编码，音节用空格分开（ü 写作 v）。", "Every entry needs text and a lowercase pinyin code, with spaces between syllables (v for ü)."))
                }
                let rawWeight = weightIndex.flatMap { fields.indices.contains($0) ? fields[$0] : nil }?.trimmingCharacters(in: .whitespaces) ?? ""
                let weight = rawWeight.isEmpty ? "100" : rawWeight
                guard let numeric = Double(weight), numeric.isFinite, numeric >= 0,
                      weightPattern.firstMatch(in: weight, range: NSRange(weight.startIndex..., in: weight)) != nil else {
                    throw invalidLine(number, tr("weight 必须是有限的非负数。", "weight must be a finite, nonnegative number."))
                }
                if seen.insert(phrase + "\t" + code).inserted { entries.append(Entry(text: phrase, code: code, weight: weight)) }
            }
            guard !entries.isEmpty else { throw PersonalDictionaryError.invalid(tr("词库中没有带拼音编码的词条。", "The dictionary has no entries with pinyin codes.")) }
            return Parsed(name: name, sort: sort, entries: entries)
        }

        /// What an entry's weight is written as: a plain decimal number, with an exponent or not. Made once: it is matched
        /// against every entry of a file (up to 32 MiB of them).
        private static let weightPattern = try! NSRegularExpression(pattern: #"^[+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#)

        /// The table as it is written, `says` its second line (`tableSays`).
        func table(named name: String, says: String) -> String {
            PersonalDictionaryStore.tableMarker + "\n" + says + "\n---\nname: \(name)\nversion: \"\(UUID().uuidString)\"\nsort: \(sort)\n...\n"
                + entries.map { $0.text + "\t" + $0.code + "\t" + $0.weight + "\n" }.joined()
        }

        private static func invalidLine(_ line: Int, _ reason: String) -> PersonalDictionaryError {
            .invalid(tr("第 \(line) 行：", "Line \(line): ") + reason)
        }
        private static func unsupportedLine(_ line: Int, _ reason: String) -> PersonalDictionaryError {
            .unsupported(tr("第 \(line) 行：", "Line \(line): ") + reason)
        }

        /// A small header reader, never a YAML evaluator. Quoted scalars, comments and both usual
        /// columns layouts work; aliases, includes, tags and multiline values are rejected.
        fileprivate static func uncomment(_ text: String, line: Int) throws -> String {
            var quote: Character?, escaped = false
            var previous: Character?
            for index in text.indices {
                let character = text[index]
                if escaped { escaped = false; previous = character; continue }
                if quote == "\"", character == "\\" { escaped = true; previous = character; continue }
                if let active = quote { if character == active { quote = nil } }
                else if character == "\"" || character == "'" { quote = character }
                else if character == "#", previous == nil || previous?.isWhitespace == true {
                    return String(text[..<index]).trimmingCharacters(in: .whitespaces)
                }
                previous = character
            }
            guard quote == nil else { throw invalidLine(line, tr("引号没有闭合。", "Unclosed quotation mark.")) }
            return text
        }

        private static func scalar(_ value: String, line: Int) throws -> String {
            let value = value.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") {
                guard let data = value.data(using: .utf8), let result = try? JSONDecoder().decode(String.self, from: data) else {
                    throw unsupportedLine(line, tr("不支持这个带引号的字段。", "This quoted field isn't supported."))
                }
                return result
            }
            if value.hasPrefix("'") {
                guard value.count >= 2, value.hasSuffix("'") else { throw invalidLine(line, tr("引号没有闭合。", "Unclosed quotation mark.")) }
                return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
            guard !value.isEmpty, !value.contains(where: { "[]{}&*!|>\"'".contains($0) }) else {
                throw unsupportedLine(line, tr("不支持 YAML 引用、标签或复杂字段。", "YAML references, tags and complex fields aren't supported."))
            }
            return value
        }

        fileprivate static func flowList(_ value: String, line: Int) throws -> [String] {
            guard value.hasPrefix("["), value.hasSuffix("]") else {
                throw unsupportedLine(line, tr("列表需要用 [text, code, weight] 或缩进的 - 列表。", "Use a list such as [text, code, weight], or indented - items."))
            }
            let middle = value.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            return middle.isEmpty ? [] : try middle.components(separatedBy: ",").map { try scalar($0, line: line) }
        }
    }
}

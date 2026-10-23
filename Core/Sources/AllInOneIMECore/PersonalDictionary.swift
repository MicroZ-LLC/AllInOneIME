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

    @discardableResult
    public func importDictionary(from source: URL, fuzzyPinyin: [String]) throws -> PersonalDictionary {
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
            var changes: [Change] = [Change(url: table, data: Data(parsed.table(named: reference(record)).utf8))]
            changes += try configurationChanges(for: after, fuzzyPinyin: fuzzyPinyin, checkAlgebra: true)
            changes.append(Change(url: manifest, data: try encode(after)))
            try write(changes)
            removeUnlistedTables(after)
            return record.dictionary
        }
    }

    public func removeDictionary(named name: String, fuzzyPinyin: [String]) throws {
        try Self.locked {
            let before = try readState().state
            guard before.dictionaries.contains(where: { $0.name == name }) else { return }
            try checkPatch(requireOwnership: true)
            try checkWrapper()
            var after = before
            after.dictionaries.removeAll { $0.name == name }
            var changes = try configurationChanges(for: after, fuzzyPinyin: fuzzyPinyin, checkAlgebra: true)
            changes.append(Change(url: manifest, data: try encode(after)))
            try write(changes)
            removeUnlistedTables(after)
        }
    }

    /// The shared writer used by FuzzyPinyin.apply too: a fuzzy toggle must keep every dictionary.
    @discardableResult
    public func applyFuzzyPinyin(_ ids: [String]) throws -> FuzzyPinyin.Outcome {
        try Self.locked {
            let (state, recovered) = try readState()
            if try !checkPatch(requireOwnership: false) {
                return state.dictionaries.isEmpty && FuzzyPinyin.known(ids).isEmpty ? .unchanged : .userFile
            }
            if !state.dictionaries.isEmpty { try checkWrapper() }
            // After a first import that never finished, its wrapper goes too (if it is this app's).
            let leftWrapper = recovered && state.dictionaries.isEmpty && (try? checkWrapper()) != nil
            var changes = try configurationChanges(for: state, fuzzyPinyin: ids, checkAlgebra: false,
                                                   includeWrapper: !state.dictionaries.isEmpty || leftWrapper)
            // Recovered: the manifest as it is now (the tables it lists all there).
            if recovered { changes.append(Change(url: manifest, data: try encode(state))) }
            let patchChange = changes.first { $0.url == patch }
            let previous = try contentsIfPresent(patch)
            let wanted = patchChange?.data
            let repairedWrapper = try changes.contains { change in
                guard change.url == wrapper else { return false }
                return try contentsIfPresent(change.url) != change.data
            }
            try write(changes)
            removeUnlistedTables(state)
            if previous == wanted, !repairedWrapper { return .unchanged }
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
    private static let wrapperMarker = "# Written by AllInOneIME: personal dictionaries. Edits here are replaced."
    private static let patchMarker = "# Written by AllInOneIME: personal dictionaries and fuzzy pinyin (Settings → Input). Edits here are replaced."
    private var folder: URL { userDirectory.appendingPathComponent(Self.folderName, isDirectory: true) }
    private var manifest: URL { folder.appendingPathComponent("manifest.json") }
    private var wrapper: URL { userDirectory.appendingPathComponent(Self.dictionaryName + ".dict.yaml") }
    private var patch: URL { userDirectory.appendingPathComponent(FuzzyPinyin.fileName) }
    private func tableURL(_ item: Stored) -> URL { folder.appendingPathComponent(item.token + ".dict.yaml") }
    private func reference(_ item: Stored) -> String { Self.folderName + "/" + item.token }

    private struct State: Codable {
        var format = "AllInOneIME personal dictionaries v1"
        var dictionaries: [Stored] = []
    }

    private struct Stored: Codable {
        let name: String
        let fileName: String
        let entryCount: Int
        let token: String
        var dictionary: PersonalDictionary { PersonalDictionary(name: name, fileName: fileName, entryCount: entryCount) }
    }

    /// The dictionaries the manifest lists, each table checked as this app's. What a write the app never finished
    /// leaves is recovered from (`write` writes the tables first and the manifest last): the folder without a manifest
    /// is a first import's, nothing listed yet; a table the manifest lists that isn't there can't be loaded, and is left
    /// out. `recovered` says so: the next change writes the manifest again (`applyFuzzyPinyin` too, which Rime's start
    /// makes); each change removes the tables it doesn't list (`removeUnlistedTables`). A manifest that isn't this app's, or a table
    /// edited by hand, throws: those files are left for the user to look at.
    private func readState() throws -> (state: State, recovered: Bool) {
        do { try checkRegular(folder, directory: true) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return (State(), false) }
        guard let bytes = try contentsIfPresent(manifest) else { return (State(), true) }
        guard let state = try? JSONDecoder().decode(State.self, from: bytes),
              state.format == State().format,
              Set(state.dictionaries.map(\.name)).count == state.dictionaries.count,
              Set(state.dictionaries.map(\.token)).count == state.dictionaries.count,
              state.dictionaries.allSatisfy({ !$0.name.isEmpty && $0.entryCount > 0 && Self.isToken($0.token) }) else {
            throw PersonalDictionaryError.managedFile(Self.folderName + "/manifest.json")
        }
        var found = state
        found.dictionaries = []
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
        return (found, found.dictionaries.count != state.dictionaries.count)
    }

    private static func isToken(_ value: String) -> Bool {
        value.hasPrefix("dict_") && value.utf8.count == 41
            && value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
    }

    private func encode(_ state: State) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(state)
    }

    /// False means a user-written file was left as is (fuzzy pinyin's existing behavior).
    @discardableResult
    private func checkPatch(requireOwnership: Bool) throws -> Bool {
        guard let bytes = try contentsIfPresent(patch) else { return true }
        let owned = [FuzzyPinyin.marker, Self.patchMarker].contains { bytes.starts(with: Data(($0 + "\n").utf8)) }
        if !owned, requireOwnership { throw PersonalDictionaryError.userFile }
        return owned
    }

    private func checkWrapper() throws {
        guard let data = try contentsIfPresent(wrapper) else { return }
        guard data.starts(with: Data((Self.wrapperMarker + "\n").utf8)) else {
            throw PersonalDictionaryError.managedFile(wrapper.lastPathComponent)
        }
    }

    private func configurationChanges(for state: State, fuzzyPinyin: [String], checkAlgebra: Bool,
                                      includeWrapper: Bool = true) throws -> [Change] {
        let schemaText = (try? String(contentsOf: schema, encoding: .utf8)) ?? ""
        let fuzzy = FuzzyPinyin.patch(fuzzyPinyin, schema: schemaText)
        if checkAlgebra, !FuzzyPinyin.known(fuzzyPinyin).isEmpty, fuzzy == nil {
            throw PersonalDictionaryError.unsupported(tr("无法读取当前拼音方案的模糊音规则。", "The current pinyin schema's spelling rules couldn't be read."))
        }
        var changes: [Change] = []
        if state.dictionaries.isEmpty {
            changes.append(Change(url: patch, data: fuzzy.map { Data($0.utf8) }))
            if includeWrapper { changes.append(Change(url: wrapper, data: nil)) }
        } else {
            var text = fuzzy?.replacingOccurrences(of: FuzzyPinyin.marker, with: Self.patchMarker)
                ?? Self.patchMarker + "\npatch:\n"
            // The dictionary changes; the database of learned words deliberately keeps its old identity.
            text += "  translator/dictionary: \(Self.dictionaryName)\n  translator/user_dict: rime_ice\n"
            changes.append(Change(url: patch, data: Data(text.utf8)))
            if includeWrapper {
                let base = try baseDictionary()
                let tables = state.dictionaries.map { reference($0) } + base.tables
                let revision = state.dictionaries.map(\.token).joined(separator: "_")
                let dictionary = Self.wrapperMarker + "\n---\nname: \(Self.dictionaryName)\nversion: \"\(revision)\"\n" + base.settings + "import_tables:\n"
                    + tables.map { "  - " + $0 + "\n" }.joined() + "...\n"
                changes.insert(Change(url: wrapper, data: Data(dictionary.utf8)), at: 0)
            }
        }
        if let customization = changes.first(where: { $0.url == patch }), try contentsIfPresent(patch) != customization.data {
            // Rime's config freshness uses second-resolution file times. A quick import or fuzzy
            // toggle can otherwise reuse the preceding schema despite full maintenance. This is a
            // generated deployment output, never a source/customization file; force it to rebuild.
            let build = userDirectory.appendingPathComponent("build", isDirectory: true)
            do {
                try checkRegular(build, directory: true)
                changes.append(Change(url: build.appendingPathComponent("rime_ice.schema.yaml"), data: nil))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {}
        }
        return changes
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
    /// finished. Only this app's (a token's name, the marker first); a failed cleanup only leaves an unreferenced
    /// table, which can't change the active vocabulary or erase user data.
    private func removeUnlistedTables(_ state: State) {
        let fm = FileManager.default
        let listed = Set(state.dictionaries.map { $0.token + ".dict.yaml" })
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
            guard name.utf8.count <= 128, name.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0) }), name != ".", name != ".." else {
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
                      weight.range(of: #"^[+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else {
                    throw invalidLine(number, tr("weight 必须是有限的非负数。", "weight must be a finite, nonnegative number."))
                }
                if seen.insert(phrase + "\t" + code).inserted { entries.append(Entry(text: phrase, code: code, weight: weight)) }
            }
            guard !entries.isEmpty else { throw PersonalDictionaryError.invalid(tr("词库中没有带拼音编码的词条。", "The dictionary has no entries with pinyin codes.")) }
            return Parsed(name: name, sort: sort, entries: entries)
        }

        func table(named name: String) -> String {
            PersonalDictionaryStore.tableMarker + "\n---\nname: \(name)\nversion: \"\(UUID().uuidString)\"\nsort: \(sort)\n...\n"
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

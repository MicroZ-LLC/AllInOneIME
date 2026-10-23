import Foundation
import Testing
@testable import AllInOneIMECore

/// Personal dictionaries when a write fails partway, or the app stops partway (it quits or crashes between the table,
/// the wrapper, the patch and the manifest): a failure puts every file back; what a stop leaves never keeps importing,
/// removing or fuzzy pinyin from working, and its leftovers go. Every path is the test's own.
struct PersonalDictionaryRecoveryTests {
    struct Stop: Error {}

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("personal-dictionary-recovery-\(UUID().uuidString)")
    var user: URL { root.appendingPathComponent("Rime") }
    var schema: URL { root.appendingPathComponent("rime_ice.schema.yaml") }
    var folder: URL { user.appendingPathComponent("allinoneime_personal") }
    var wrapper: URL { user.appendingPathComponent("allinoneime_personal.dict.yaml") }

    init() throws {
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try "schema:\n  schema_id: rime_ice\nspeller:\n  algebra:\n    - derive/^([nl])ue$/$1ve/\ntranslator:\n  dictionary: rime_ice\n"
            .write(to: schema, atomically: true, encoding: .utf8)
        try "---\nname: rime_ice\nversion: \"1\"\nsort: by_weight\n...\n你好\tni hao\t1000\n"
            .write(to: root.appendingPathComponent("rime_ice.dict.yaml"), atomically: true, encoding: .utf8)
    }

    func store(in directory: URL? = nil, failing: (@Sendable (URL) throws -> Void)? = nil) -> PersonalDictionaryStore {
        var store = PersonalDictionaryStore(userDirectory: directory ?? user, schema: schema)
        store.beforeWrite = failing
        return store
    }

    func source(_ name: String, _ row: String) throws -> URL {
        let file = root.appendingPathComponent(name + ".dict.yaml")
        try "---\nname: \(name)\nversion: \"1\"\n...\n\(row)\n".write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Every file under `directory`, by relative path.
    func files(_ directory: URL? = nil) throws -> [String: Data] {
        let directory = directory ?? user
        var result: [String: Data] = [:]
        let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        while let file = entries?.nextObject() as? URL {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(file.resolvingSymlinksInPath().path.dropFirst(directory.resolvingSymlinksInPath().path.count + 1))]
                    = try Data(contentsOf: file)
            }
        }
        return result
    }

    /// The tables in the folder, and those the wrapper imports: the same, so Rime can build it.
    func expectConsistent(_ directory: URL, listed: Int, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let folder = directory.appendingPathComponent("allinoneime_personal")
        let tables = Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".dict.yaml") }.map { "allinoneime_personal/" + $0.dropLast(".dict.yaml".count) })
        #expect(tables.count == listed, "tables: \(tables)", sourceLocation: sourceLocation)
        let wrapper = (try? String(contentsOf: directory.appendingPathComponent("allinoneime_personal.dict.yaml"), encoding: .utf8)) ?? ""
        let imported = Set(wrapper.split(separator: "\n").compactMap { line -> String? in
            line.hasPrefix("  - allinoneime_personal/") ? String(line.dropFirst(4)) : nil
        })
        #expect(imported == tables, "the wrapper imports \(imported), the folder has \(tables)", sourceLocation: sourceLocation)
    }

    static let points = ["table", "wrapper", "patch", "manifest"]
    static func point(_ url: URL) -> String {
        if url.lastPathComponent == "manifest.json" { return "manifest" }
        if url.lastPathComponent == FuzzyPinyin.fileName { return "patch" }
        if url.lastPathComponent == "allinoneime_personal.dict.yaml" { return "wrapper" }
        return url.deletingLastPathComponent().lastPathComponent == "allinoneime_personal" ? "table" : "other"
    }

    // MARK: A write that fails

    /// An import or a removal whose write fails at any of its files: every file as it was, the dictionaries as listed,
    /// and the next change works.
    @Test(arguments: points)
    func aFailedWritePutsEveryFileBack(_ at: String) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try store().importDictionary(from: try source("team_alpha", "霁鸢星槎\tji yuan xing cha"), fuzzyPinyin: ["n-l"])
        let before = try files()
        let failing = store { url in if Self.point(url) == at { throw Stop() } }
        // Another fuzzy pair with it, so that the patch changes too.
        #expect(throws: Stop.self) {
            try failing.importDictionary(from: try source("team_beta", "鹭汀云笺\tlu ting yun jian"), fuzzyPinyin: ["n-l", "z-zh"])
        }
        #expect(try files() == before)
        #expect(try store().list() == [first])
        // Removing the last one writes no table: from the wrapper on.
        if at != "table" {
            #expect(throws: Stop.self) { try failing.removeDictionary(named: first.name, fuzzyPinyin: ["n-l"]) }
            #expect(try files() == before)
            #expect(try store().list() == [first])
        }
        let second = try store().importDictionary(from: try source("team_beta", "鹭汀云笺\tlu ting yun jian"), fuzzyPinyin: ["n-l"])
        #expect(try store().list() == [first, second])
        try expectConsistent(user, listed: 2)
    }

    // MARK: The app stopping partway

    /// The user folder as the app leaves it when it stops right before writing `at`, during `change`: a copy of it then,
    /// in a folder of its own (the store then fails, which puts the original back).
    func stopped(at: String, during change: (PersonalDictionaryStore) throws -> Void) throws -> URL {
        let left = root.appendingPathComponent("left-at-\(at)-\(UUID().uuidString)")
        let user = self.user
        let stopping = store { url in
            guard Self.point(url) == at else { return }
            try FileManager.default.copyItem(at: user, to: left)
            throw Stop()
        }
        #expect(throws: Stop.self) { try change(stopping) }
        try #require(FileManager.default.fileExists(atPath: left.path), "no write of the \(at)")
        return left
    }

    /// The first import stopped anywhere: nothing is listed, and importing, fuzzy pinyin and removing all work; what it
    /// left goes.
    @Test(arguments: points)
    func aFirstImportThatStoppedIsUndone(_ at: String) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let alpha = try source("team_alpha", "霁鸢星槎\tji yuan xing cha")
        let left = try stopped(at: at) { try $0.importDictionary(from: alpha, fuzzyPinyin: []) }
        let store = store(in: left)
        #expect(try store.list().isEmpty)
        // Rime's start applies fuzzy pinyin: the leftovers go, and nothing refers to them.
        _ = try store.applyFuzzyPinyin(["n-l"])
        try expectConsistent(left, listed: 0)
        #expect(!FileManager.default.fileExists(atPath: left.appendingPathComponent("allinoneime_personal.dict.yaml").path))
        let patch = try String(contentsOf: left.appendingPathComponent(FuzzyPinyin.fileName), encoding: .utf8)
        #expect(!patch.contains("allinoneime_personal") && patch.contains("derive/^n/l/"))
        let imported = try store.importDictionary(from: alpha, fuzzyPinyin: ["n-l"])
        #expect(try store.list() == [imported])
        try expectConsistent(left, listed: 1)
        try store.removeDictionary(named: imported.name, fuzzyPinyin: ["n-l"])
        #expect(try store.list().isEmpty)
        try expectConsistent(left, listed: 0)
    }

    /// An import beside another, stopped anywhere: the other is still listed and used, the new one's table goes.
    @Test(arguments: points)
    func anotherImportThatStoppedKeepsWhatWasThere(_ at: String) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try store().importDictionary(from: try source("team_alpha", "霁鸢星槎\tji yuan xing cha"), fuzzyPinyin: [])
        let beta = try source("team_beta", "鹭汀云笺\tlu ting yun jian")
        let left = try stopped(at: at) { try $0.importDictionary(from: beta, fuzzyPinyin: ["n-l"]) }
        let store = store(in: left)
        #expect(try store.list() == [first])
        _ = try store.applyFuzzyPinyin([])
        try expectConsistent(left, listed: 1)
        let second = try store.importDictionary(from: beta, fuzzyPinyin: [])
        #expect(try store.list() == [first, second])
        try expectConsistent(left, listed: 2)
    }

    /// A removal stopped before its manifest: still listed, and removed the next time; stopped after it, before its table
    /// went: the table goes with the next change.
    @Test func aRemovalThatStoppedIsDoneNextTime() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try store().importDictionary(from: try source("team_alpha", "霁鸢星槎\tji yuan xing cha"), fuzzyPinyin: [])
        let second = try store().importDictionary(from: try source("team_beta", "鹭汀云笺\tlu ting yun jian"), fuzzyPinyin: [])
        let left = try stopped(at: "manifest") { try $0.removeDictionary(named: first.name, fuzzyPinyin: []) }
        #expect(try store(in: left).list() == [first, second])
        try store(in: left).removeDictionary(named: first.name, fuzzyPinyin: [])
        #expect(try store(in: left).list() == [second])
        try expectConsistent(left, listed: 1)
        // Its table still there after the manifest was written.
        let table = try #require(try files(folder).keys.first { try files(left.appendingPathComponent("allinoneime_personal"))[$0] == nil })
        try FileManager.default.copyItem(at: folder.appendingPathComponent(table), to: left.appendingPathComponent("allinoneime_personal/" + table))
        _ = try store(in: left).applyFuzzyPinyin(["n-l"])
        #expect(try store(in: left).list() == [second])
        try expectConsistent(left, listed: 1)
        _ = try store(in: left).importDictionary(from: try source("team_gamma", "霁鸢雾港\tji yuan wu gang"), fuzzyPinyin: [])
        try expectConsistent(left, listed: 2)
    }

    // MARK: What Rime built

    /// The last dictionary removed: what Rime built of the wrapper goes, nothing else it built; while one is left, it
    /// stays (Rime builds it again).
    @Test func removingTheLastDictionaryRemovesWhatRimeBuiltOfIt() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try store().importDictionary(from: try source("team_alpha", "霁鸢星槎\tji yuan xing cha"), fuzzyPinyin: [])
        let second = try store().importDictionary(from: try source("team_beta", "鹭汀云笺\tlu ting yun jian"), fuzzyPinyin: [])
        let build = user.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        let personal = ["table", "prism", "reverse"].map { "allinoneime_personal.\($0).bin" }
        let others = ["rime_ice.table.bin", "rime_ice.prism.bin", "rime_ice.reverse.bin", "melt_eng.table.bin"]
        for name in personal + others { try Data(name.utf8).write(to: build.appendingPathComponent(name)) }
        func built() -> Set<String> { Set((try? FileManager.default.contentsOfDirectory(atPath: build.path)) ?? []) }
        try store().removeDictionary(named: first.name, fuzzyPinyin: [])
        #expect(built().isSuperset(of: personal + others))
        try store().removeDictionary(named: second.name, fuzzyPinyin: [])
        #expect(built().isDisjoint(with: personal))
        #expect(built().isSuperset(of: others))
        for name in others { #expect(try Data(contentsOf: build.appendingPathComponent(name)) == Data(name.utf8)) }
    }

    /// A table the manifest lists, gone (deleted by hand): left out, and the wrapper no longer imports it.
    @Test func aListedTableThatIsGoneIsLeftOut() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try store().importDictionary(from: try source("team_alpha", "霁鸢星槎\tji yuan xing cha"), fuzzyPinyin: [])
        let second = try store().importDictionary(from: try source("team_beta", "鹭汀云笺\tlu ting yun jian"), fuzzyPinyin: [])
        let wrapper = try String(contentsOf: self.wrapper, encoding: .utf8)
        let token = try #require(wrapper.split(separator: "\n").first { $0.hasPrefix("  - allinoneime_personal/") })
            .dropFirst("  - allinoneime_personal/".count)
        try FileManager.default.removeItem(at: folder.appendingPathComponent(token + ".dict.yaml"))
        #expect(try store().list() == [second])
        #expect(try store().applyFuzzyPinyin([]) == .written)
        #expect(try store().list() == [second])
        try expectConsistent(user, listed: 1)
        _ = first
    }
}

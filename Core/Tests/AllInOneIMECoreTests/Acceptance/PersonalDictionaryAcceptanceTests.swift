import Foundation
import Testing
@testable import AllInOneIMECore

// Independent acceptance tests, derived from the agreed personal-dictionary contract. The implementation author
// owns production code only. These tests exercise the public store API without reading its generated integration
// files; real candidate, commit, fuzzy-pinyin and process-persistence assertions live in the Rime acceptance suite.
// Every path here is temporary. Neither the installed input method nor the user's configuration is used.

private final class PersonalDictionaryAcceptanceWorld {
    let root: URL
    let user: URL
    let sources: URL
    let schema: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("personal-dictionary-acceptance-\(UUID().uuidString)", isDirectory: true)
        user = root.appendingPathComponent("Rime", isDirectory: true)
        sources = root.appendingPathComponent("Original dictionaries", isDirectory: true)
        schema = root.appendingPathComponent("rime_ice.schema.yaml")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        // A public Rime schema fixture, including ordinary algebra for the existing fuzzy-pinyin API.
        try """
        schema:
          schema_id: rime_ice
          name: Acceptance schema
        speller:
          alphabet: abcdefghijklmnopqrstuvwxyz
          algebra:
            - derive/^([nl])ue$/$1ve/
            - derive/([aeiou])ng$/$1gn/
        translator:
          dictionary: rime_ice
          user_dict: rime_ice
        """.write(to: schema, atomically: true, encoding: .utf8)
        // Importing supplements an installed Chinese pack. Its base vocabulary is present beside the schema,
        // just as in a real pack; a one-row dictionary is sufficient for these store-only cases.
        try Self.dictionary("rime_ice", rows: ["你好\tni hao\t1000"])
            .write(to: root.appendingPathComponent("rime_ice.dict.yaml"), atomically: true, encoding: .utf8)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var store: PersonalDictionaryStore { PersonalDictionaryStore(userDirectory: user, schema: schema) }

    func source(_ body: String, fileName: String = "Team vocabulary.dict.yaml") throws -> URL {
        let file = sources.appendingPathComponent(fileName)
        try body.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    static func dictionary(_ name: String = "acceptance_team", rows: [String],
                           columns: String? = nil, extraHeader: String = "") -> String {
        let columnLine = columns.map { "columns: \($0)\n" } ?? ""
        return "---\nname: \(name)\nversion: \"acceptance-1\"\nsort: by_weight\n"
            + columnLine + extraHeader + "...\n" + rows.joined(separator: "\n") + "\n"
    }

    /// Files, by relative path and bytes. A failed operation must not partially replace a working setup.
    func files(under directory: URL? = nil) throws -> [String: Data] {
        let directory = directory ?? user
        let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        var result: [String: Data] = [:]
        while let file = entries?.nextObject() as? URL {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(file.path.dropFirst(directory.path.count + 1))] = try Data(contentsOf: file)
            }
        }
        return result
    }

    func protect(_ relativePath: String, contents: String) throws -> URL {
        let file = user.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}

private func personalDictionaryRejection(_ operation: () throws -> Void) -> Error? {
    do {
        try operation()
        Issue.record("The unsupported or unsafe dictionary operation succeeded")
        return nil
    } catch {
        #expect(!error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "A rejected import must explain how the user can correct it")
        return error
    }
}

@Suite("Personal dictionaries: independent acceptance")
struct PersonalDictionaryAcceptanceTests {
    @Test("An import lists its dictionary name and entry count and leaves the original untouched")
    func importsAndListsVocabulary() throws {
        let world = try PersonalDictionaryAcceptanceWorld()
        #expect(try world.store.list().isEmpty)
        let source = try world.source(PersonalDictionaryAcceptanceWorld.dictionary(rows: [
            "霁鸢星槎\tce shi ci ku\t900000", "鹭汀云笺\tyan shou ci biao\t800000"
        ]))
        let original = try Data(contentsOf: source)
        let imported = try world.store.importDictionary(from: source, fuzzyPinyin: [])
        #expect(imported.name == "acceptance_team")
        #expect(imported.entryCount == 2)
        #expect(!imported.fileName.isEmpty)
        #expect(try world.store.list() == [imported])
        #expect(try Data(contentsOf: source) == original)
    }

    @Test("Two-column UTF-8 vocabulary works without weights; comments and blank lines are not entries")
    func optionalWeightsAndComments() throws {
        let world = try PersonalDictionaryAcceptanceWorld()
        let source = try world.source(PersonalDictionaryAcceptanceWorld.dictionary(rows: [
            "# A private team vocabulary", "", "霁鸢星槎\tce shi ci ku", "鹭汀云笺\tyan shou ci biao", ""
        ], columns: "[text, code]"))
        let imported = try world.store.importDictionary(from: source, fuzzyPinyin: [])
        #expect(imported.entryCount == 2)
        #expect(try world.store.list().map(\.name) == ["acceptance_team"])
    }

    @Test("Standard explicit text/code/weight columns are accepted")
    func standardColumns() throws {
        let world = try PersonalDictionaryAcceptanceWorld()
        let source = try world.source(PersonalDictionaryAcceptanceWorld.dictionary(rows: [
            "霁鸢星槎\tce shi ci ku\t900000"
        ], columns: "[text, code, weight]"))
        #expect(try world.store.importDictionary(from: source, fuzzyPinyin: []).entryCount == 1)
    }

    @Test("Reordered columns are honored or explicitly rejected without changing the working dictionaries")
    func reorderedColumns() throws {
        let world = try PersonalDictionaryAcceptanceWorld()
        let first = try world.source(PersonalDictionaryAcceptanceWorld.dictionary(rows: ["霁鸢星槎\tce shi ci ku"]))
        let imported = try world.store.importDictionary(from: first, fuzzyPinyin: [])
        let reordered = try world.source(PersonalDictionaryAcceptanceWorld.dictionary("acceptance_reordered", rows: [
            "yan shou ci biao\t800000\t鹭汀云笺"
        ], columns: "[code, weight, text]"), fileName: "Reordered columns.dict.yaml")
        let before = try world.files()
        do {
            let second = try world.store.importDictionary(from: reordered, fuzzyPinyin: [])
            #expect(second.name == "acceptance_reordered" && second.entryCount == 1)
            #expect(Set(try world.store.list().map(\.name)) == [imported.name, second.name])
        } catch {
            let explanation = error.localizedDescription.lowercased()
            #expect(explanation.contains("column") || explanation.contains("layout") || explanation.contains("列"),
                    "An unsupported column order must be explained: \(error)")
            #expect(try world.files() == before)
            #expect(try world.store.list() == [imported])
        }
    }

    @Test("Dictionary identity comes from its name; separate imports coexist even with the same source basename")
    func multipleDictionaries() throws {
        let world = try PersonalDictionaryAcceptanceWorld()
        let first = try world.source(PersonalDictionaryAcceptanceWorld.dictionary("acceptance_first", rows: [
            "霁鸢星槎\tce shi ci ku"
        ]))
        _ = try world.store.importDictionary(from: first, fuzzyPinyin: [])
        // The picker can select another file with the same basename from another folder.
        let secondDirectory = world.sources.appendingPathComponent("Second source", isDirectory: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let second = secondDirectory.appendingPathComponent(first.lastPathComponent)
        try PersonalDictionaryAcceptanceWorld.dictionary("acceptance_second", rows: [
            "鹭汀云笺\tyan shou ci biao", "霁鸢雾港\tce shi geng xin"
        ]).write(to: second, atomically: true, encoding: .utf8)
        _ = try world.store.importDictionary(from: second, fuzzyPinyin: [])
        let listed = try world.store.list()
        #expect(Set(listed.map(\.name)) == ["acceptance_first", "acceptance_second"])
        #expect(listed.first { $0.name == "acceptance_first" }?.entryCount == 1)
        #expect(listed.first { $0.name == "acceptance_second" }?.entryCount == 2)
    }

    @Test("Reimport updates one managed dictionary; editing or deleting the original does not update it")
    func reimportUpdatesByIdentity() throws {
        let world = try PersonalDictionaryAcceptanceWorld()
        let source = try world.source(PersonalDictionaryAcceptanceWorld.dictionary(rows: ["霁鸢星槎\tce shi ci ku"]))
        let first = try world.store.importDictionary(from: source, fuzzyPinyin: [])
        try PersonalDictionaryAcceptanceWorld.dictionary(rows: [
            "鹭汀云笺\tyan shou ci biao", "霁鸢雾港\tce shi geng xin"
        ]).write(to: source, atomically: true, encoding: .utf8)
        #expect(try world.store.list() == [first], "The source is not a watched configuration file")
        let changedSource = try Data(contentsOf: source)
        let second = try world.store.importDictionary(from: source, fuzzyPinyin: [])
        #expect(second.id == first.id && second.entryCount == 2)
        #expect(try world.store.list() == [second])
        #expect(try Data(contentsOf: source) == changedSource)
        let repeated = try world.store.importDictionary(from: source, fuzzyPinyin: [])
        #expect(repeated == second)
        #expect(try world.store.list() == [second])
        try FileManager.default.removeItem(at: source)
        #expect(try world.store.list() == [second])
        // A newly constructed store must obtain state from disk.
        #expect(try PersonalDictionaryStore(userDirectory: world.user, schema: world.schema).list() == [second])
    }

    @Test("Removing an import preserves its source and every other imported dictionary")
    func removeOneDictionary() throws {
        let world = try PersonalDictionaryAcceptanceWorld()
        let firstSource = try world.source(PersonalDictionaryAcceptanceWorld.dictionary("acceptance_first", rows: [
            "霁鸢星槎\tce shi ci ku"
        ]))
        let secondSource = try world.source(PersonalDictionaryAcceptanceWorld.dictionary("acceptance_second", rows: [
            "鹭汀云笺\tyan shou ci biao"
        ]), fileName: "Other.dict.yaml")
        let first = try world.store.importDictionary(from: firstSource, fuzzyPinyin: [])
        let second = try world.store.importDictionary(from: secondSource, fuzzyPinyin: [])
        let originals = try world.files(under: world.sources)
        try world.store.removeDictionary(named: first.name, fuzzyPinyin: [])
        #expect(try world.store.list() == [second])
        #expect(try world.files(under: world.sources) == originals)
        try world.store.removeDictionary(named: second.name, fuzzyPinyin: [])
        #expect(try world.store.list().isEmpty)
        #expect(try world.files(under: world.sources) == originals)
    }

    @Test("Dictionary and fuzzy-pinyin operations preserve user files and the existing learned-database identity")
    func preservesUnrelatedUserData() throws {
        let world = try PersonalDictionaryAcceptanceWorld()
        let protected = try [
            world.protect("default.custom.yaml", contents: "# Mine\npatch:\n  menu/page_size: 7\n"),
            world.protect("custom_phrase.txt", contents: "私有短语\tprivate\t1\n"),
            world.protect("installation.yaml", contents: "installation_id: acceptance-device\nsync_dir: /private/never-write-here\n"),
            world.protect("rime_ice.userdb/KEEP", contents: "existing learned dictionary identity"),
            world.protect("my-own.dict.yaml", contents: "# unrelated user-owned dictionary\n")
        ]
        let bytes = try protected.map { try Data(contentsOf: $0) }
        let source = try world.source(PersonalDictionaryAcceptanceWorld.dictionary(rows: ["霁鸢星槎\tce shi ci ku"]))
        let imported = try world.store.importDictionary(from: source, fuzzyPinyin: [])
        _ = try FuzzyPinyin.apply(["n-l"], schema: world.schema, userDir: world.user)
        #expect(try world.store.list() == [imported])
        _ = try world.store.applyFuzzyPinyin([])
        try world.store.removeDictionary(named: imported.name, fuzzyPinyin: [])
        for (file, original) in zip(protected, bytes) {
            #expect(try Data(contentsOf: file) == original, "Preserve \(file.lastPathComponent)")
        }
    }

    @Test("A user-owned Rime customization blocks import before any managed state is changed")
    func refusesUserCustomizationOnImport() throws {
        let world = try PersonalDictionaryAcceptanceWorld()
        let own = "# My Rime configuration\npatch:\n  menu/page_size: 7\n  translator/enable_sentence: false\n"
        _ = try world.protect("rime_ice.custom.yaml", contents: own)
        let source = try world.source(PersonalDictionaryAcceptanceWorld.dictionary(rows: ["霁鸢星槎\tce shi ci ku"]))
        let before = try world.files()
        let error = personalDictionaryRejection { _ = try world.store.importDictionary(from: source, fuzzyPinyin: []) }
        #expect(error?.localizedDescription.contains("rime_ice.custom.yaml") == true,
                "Explain which user-owned file prevents automatic integration")
        #expect(try world.files() == before)
        #expect(try world.store.list().isEmpty)
    }

    @Test("If the user takes ownership of customization, updates and removals refuse without partial mutation")
    func refusesUserCustomizationOnUpdateAndRemove() throws {
        let world = try PersonalDictionaryAcceptanceWorld()
        let source = try world.source(PersonalDictionaryAcceptanceWorld.dictionary(rows: ["霁鸢星槎\tce shi ci ku"]))
        let imported = try world.store.importDictionary(from: source, fuzzyPinyin: [])
        _ = try world.protect("rime_ice.custom.yaml", contents: "# User took ownership\npatch:\n  menu/page_size: 8\n")
        try PersonalDictionaryAcceptanceWorld.dictionary(rows: ["鹭汀云笺\tyan shou ci biao"])
            .write(to: source, atomically: true, encoding: .utf8)
        let before = try world.files()
        _ = personalDictionaryRejection { _ = try world.store.importDictionary(from: source, fuzzyPinyin: ["n-l"]) }
        #expect(try world.files() == before)
        #expect(try world.store.list() == [imported])
        _ = personalDictionaryRejection { try world.store.removeDictionary(named: imported.name, fuzzyPinyin: []) }
        #expect(try world.files() == before)
        #expect(try world.store.list() == [imported])
    }

    private struct InvalidDictionary: Sendable {
        let label: String
        let body: Data
    }

    private static let invalidDictionaries: [InvalidDictionary] = {
        let dict = PersonalDictionaryAcceptanceWorld.dictionary
        return [
            InvalidDictionary(label: "empty", body: Data()),
            InvalidDictionary(label: "invalid UTF-8", body: Data([0xff, 0xfe, 0xff])),
            InvalidDictionary(label: "missing Rime header", body: Data("霁鸢星槎\tce shi ci ku\n".utf8)),
            InvalidDictionary(label: "missing name", body: Data("---\nversion: \"1\"\n...\n霁鸢星槎\tce shi ci ku\n".utf8)),
            InvalidDictionary(label: "missing code", body: Data(dict("acceptance_invalid", ["霁鸢星槎"], nil, "").utf8)),
            InvalidDictionary(label: "empty text", body: Data(dict("acceptance_invalid", ["\tce shi ci ku"], nil, "").utf8)),
            InvalidDictionary(label: "nonnumeric weight", body: Data(dict("acceptance_invalid", ["霁鸢星槎\tce shi ci ku\theavy"], nil, "").utf8)),
            InvalidDictionary(label: "unknown column layout", body: Data(dict("acceptance_invalid", ["霁鸢星槎\tce shi ci ku"], "[text, meaning]", "").utf8)),
            InvalidDictionary(label: "external table block", body: Data(dict("acceptance_invalid", ["霁鸢星槎\tce shi ci ku"], nil,
                "import_tables:\n  - external_team_dictionary\n").utf8)),
            InvalidDictionary(label: "external table inline", body: Data(dict("acceptance_invalid", ["霁鸢星槎\tce shi ci ku"], nil,
                "import_tables: [external_team_dictionary]\n").utf8))
        ]
    }()

    @Test("Invalid or dependent input cannot partially replace a working dictionary", arguments: invalidDictionaries)
    private func rejectsInvalidInput(_ bad: InvalidDictionary) throws {
        let world = try PersonalDictionaryAcceptanceWorld()
        let source = try world.source(PersonalDictionaryAcceptanceWorld.dictionary(rows: ["霁鸢星槎\tce shi ci ku"]))
        let imported = try world.store.importDictionary(from: source, fuzzyPinyin: ["n-l"])
        let invalid = world.sources.appendingPathComponent("Invalid.dict.yaml")
        try bad.body.write(to: invalid)
        let before = try world.files()
        _ = personalDictionaryRejection { _ = try world.store.importDictionary(from: invalid, fuzzyPinyin: ["n-l"]) }
        #expect(try world.files() == before, "Rejected \(bad.label) must not change persisted state")
        #expect(try world.store.list() == [imported])
    }

    @Test("A malformed reimport preserves the previously loaded copy")
    func rejectsInvalidUpdate() throws {
        let world = try PersonalDictionaryAcceptanceWorld()
        let source = try world.source(PersonalDictionaryAcceptanceWorld.dictionary(rows: ["霁鸢星槎\tce shi ci ku"]))
        let imported = try world.store.importDictionary(from: source, fuzzyPinyin: [])
        try PersonalDictionaryAcceptanceWorld.dictionary(rows: ["replacement without an explicit code"])
            .write(to: source, atomically: true, encoding: .utf8)
        let before = try world.files()
        _ = personalDictionaryRejection { _ = try world.store.importDictionary(from: source, fuzzyPinyin: []) }
        #expect(try world.files() == before)
        #expect(try world.store.list() == [imported])
    }

    @Test("An unreadable selection fails without changing the working setup")
    func unreadableSource() throws {
        let world = try PersonalDictionaryAcceptanceWorld()
        let source = try world.source(PersonalDictionaryAcceptanceWorld.dictionary(rows: ["霁鸢星槎\tce shi ci ku"]))
        let imported = try world.store.importDictionary(from: source, fuzzyPinyin: [])
        let before = try world.files()
        _ = personalDictionaryRejection {
            _ = try world.store.importDictionary(from: world.sources.appendingPathComponent("Missing.dict.yaml"), fuzzyPinyin: [])
        }
        _ = personalDictionaryRejection { _ = try world.store.importDictionary(from: world.sources, fuzzyPinyin: []) }
        #expect(try world.files() == before)
        #expect(try world.store.list() == [imported])
    }
}

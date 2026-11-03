import Foundation
import Testing
@testable import AllInOneIMECore

/// Fuzzy pinyin beside the personal dictionaries, as it was before them: the user's own `rime_ice.custom.yaml` (a link
/// to one too) is `.userFile`, whatever the dictionaries' files are like; and the file written with dictionaries is still
/// 0.6.6's own, so that its fuzzy pinyin switch works after a downgrade.
struct FuzzyPinyinCompatibilityTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("fuzzy-compatibility-\(UUID().uuidString)")
    var user: URL { root.appendingPathComponent("Rime") }
    var schema: URL { root.appendingPathComponent("rime_ice.schema.yaml") }
    var patch: URL { user.appendingPathComponent(FuzzyPinyin.fileName) }
    var store: PersonalDictionaryStore { PersonalDictionaryStore(userDirectory: user, schema: schema) }

    init() throws {
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try "schema:\n  schema_id: rime_ice\nspeller:\n  algebra:\n    - derive/^([nl])ue$/$1ve/\ntranslator:\n  dictionary: rime_ice\n"
            .write(to: schema, atomically: true, encoding: .utf8)
        try "---\nname: rime_ice\nversion: \"1\"\nsort: by_weight\n...\n你好\tni hao\t1000\n"
            .write(to: root.appendingPathComponent("rime_ice.dict.yaml"), atomically: true, encoding: .utf8)
    }

    func importOne(fuzzy: [String] = []) throws -> PersonalDictionary {
        let file = root.appendingPathComponent("team.dict.yaml")
        try "---\nname: team\nversion: \"1\"\n...\n霁鸢星槎\tji yuan xing cha\n".write(to: file, atomically: true, encoding: .utf8)
        return try store.importDictionary(from: file, fuzzyPinyin: fuzzy)
    }

    /// 0.6.6's `FuzzyPinyin.apply`, as it shipped (its marker, its rules: `FuzzyPinyin.patch` is unchanged since).
    static func apply066(_ ids: [String], schema schemaURL: URL, userDir: URL) throws -> FuzzyPinyin.Outcome {
        let marker = "# Written by AllInOneIME: fuzzy pinyin (Settings → Input). Edits here are replaced."
        let file = userDir.appendingPathComponent(FuzzyPinyin.fileName)
        let existing = try? String(contentsOf: file, encoding: .utf8)
        if let existing, !existing.hasPrefix(marker) { return ids.isEmpty ? .unchanged : .userFile }
        let schema = (try? String(contentsOf: schemaURL, encoding: .utf8)) ?? ""
        guard let wanted = FuzzyPinyin.patch(ids, schema: schema) else {
            guard existing != nil else { return .unchanged }
            try FileManager.default.removeItem(at: file)
            return .removed
        }
        guard wanted != existing else { return .unchanged }
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try wanted.write(to: file, atomically: true, encoding: .utf8)
        return .written
    }

    // MARK: The user's own file

    /// A link where the patch goes (to the user's file, or to nothing): theirs, never followed, replaced or a reason to
    /// throw; an import says so.
    @Test(arguments: [true, false])
    func aLinkIsTheUsersOwn(_ dangling: Bool) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let mine = root.appendingPathComponent("my-rime_ice.custom.yaml")
        if !dangling { try "patch:\n  menu/page_size: 9\n".write(to: mine, atomically: true, encoding: .utf8) }
        try FileManager.default.createSymbolicLink(at: patch, withDestinationURL: mine)
        #expect(try FuzzyPinyin.apply(["n-l"], schema: schema, userDir: user) == .userFile)
        #expect(try FuzzyPinyin.apply([], schema: schema, userDir: user) == .unchanged)
        do {
            _ = try importOne()
            Issue.record("an import over a link was taken")
        } catch PersonalDictionaryError.userFile {
        } catch {
            Issue.record("refused with \(error), not as the user's own file")
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: patch.path) == mine.path)
        #expect(try store.list().isEmpty)
    }

    /// The user's own file, beside a manifest that can't be read: `.userFile` as before, not an error about the manifest.
    @Test func theUsersOwnFileComesBeforeTheManifest() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try importOne()
        try "not a manifest".write(to: user.appendingPathComponent("allinoneime_personal/manifest.json"), atomically: true, encoding: .utf8)
        try "patch:\n  menu/page_size: 9\n".write(to: patch, atomically: true, encoding: .utf8)
        #expect(try FuzzyPinyin.apply(["n-l"], schema: schema, userDir: user) == .userFile)
        #expect(try FuzzyPinyin.apply([], schema: schema, userDir: user) == .unchanged)
        #expect(try String(contentsOf: patch, encoding: .utf8) == "patch:\n  menu/page_size: 9\n")
        // With a manifest that reads, the dictionaries can't be attached either: said too.
        try FileManager.default.removeItem(at: user.appendingPathComponent("allinoneime_personal"))
        _ = try FileManager.default.removeItem(at: patch)
        _ = try importOne()
        try "patch:\n  menu/page_size: 9\n".write(to: patch, atomically: true, encoding: .utf8)
        #expect(try FuzzyPinyin.apply([], schema: schema, userDir: user) == .userFile)
    }

    // MARK: Back to 0.6.6

    /// The patch written with a dictionary (fuzzy pinyin on or off) is 0.6.6's to rewrite: its switch turns fuzzy pinyin
    /// on and off (without the dictionaries, which it doesn't have). Back on this version, they are in it again.
    @Test(arguments: [[], ["n-l"]])
    func zeroSixSixTakesThePatchAsItsOwn(_ fuzzy: [String]) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let team = try importOne(fuzzy: fuzzy)
        #expect(try String(contentsOf: patch, encoding: .utf8).contains("translator/dictionary: allinoneime_personal"))
        // 0.6.6 starts (with the pairs the config has), then the switch is changed there.
        let started = try Self.apply066(fuzzy, schema: schema, userDir: user)
        #expect(started != .userFile && started != .unchanged)
        #expect(try Self.apply066(["n-l", "z-zh"], schema: schema, userDir: user) == .written)
        #expect(try String(contentsOf: patch, encoding: .utf8) == FuzzyPinyin.patch(["n-l", "z-zh"], schema: String(contentsOf: schema, encoding: .utf8)))
        #expect(try Self.apply066([], schema: schema, userDir: user) == .removed)
        #expect(try Self.apply066(["z-zh"], schema: schema, userDir: user) == .written)
        // This version again: the dictionary is attached as it starts, the pairs kept.
        #expect(try store.applyFuzzyPinyin(["z-zh"]) == .written)
        let text = try String(contentsOf: patch, encoding: .utf8)
        #expect(text.contains("translator/dictionary: allinoneime_personal") && text.contains("derive/^zh/z/"))
        #expect(try store.list() == [team])
        #expect(try store.applyFuzzyPinyin(["z-zh"]) == .unchanged)
    }

    /// 0.6.7's first builds wrote another first line: still this app's, and rewritten with 0.6.6's.
    @Test func theFirstBuildsPatchIsStillThisAppsOwn() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try importOne()
        let early = "# Written by AllInOneIME: personal dictionaries and fuzzy pinyin (Settings → Input). Edits here are replaced.\n"
            + "patch:\n  translator/dictionary: allinoneime_personal\n  translator/user_dict: rime_ice\n"
        try early.write(to: patch, atomically: true, encoding: .utf8)
        #expect(try store.applyFuzzyPinyin([]) == .written)
        #expect(try String(contentsOf: patch, encoding: .utf8).hasPrefix(FuzzyPinyin.marker + "\n"))
    }
}

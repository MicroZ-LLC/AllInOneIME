import Foundation
import Testing
@testable import AllInOneIMECore

/// Fuzzy pinyin: the rules written into the Rime user folder, and never over the user's own file.
struct FuzzyPinyinTests {
    let schema = """
    schema:
      schema_id: rime_ice
    speller:
      alphabet: abc
      algebra:
        ### 模糊音
        # - derive/^([zcs])h/$1/
        - erase/^hm$/ # 响应超级简拼
        - abbrev/^([a-z]).+$/$1/   # 超级简拼
        - derive/^([nl])ve$/$1ue/
    translator:
      dictionary: rime_ice
      algebra:
        - xform/x/y/
    """

    @Test func theSchemaRulesFollowTheFuzzyOnes() throws {
        #expect(FuzzyPinyin.algebra(ofSchema: schema) == ["erase/^hm$/", "abbrev/^([a-z]).+$/$1/", "derive/^([nl])ve$/$1ue/"])
        let patch = try #require(FuzzyPinyin.patch(["n-l", "z-zh"], schema: schema))
        #expect(patch.hasPrefix(FuzzyPinyin.marker) && patch.contains("patch:\n  speller/algebra:\n"))
        // In the catalog's order (z-zh before n-l), then the schema's own.
        let rules = patch.split(separator: "\n").filter { $0.hasPrefix("    - ") }.map { String($0.dropFirst(6)) }
        #expect(rules == ["\"derive/^zh/z/\"", "\"derive/^z([^h])/zh$1/\"", "\"derive/^n/l/\"", "\"derive/^l/n/\"",
                          "\"erase/^hm$/\"", "\"abbrev/^([a-z]).+$/$1/\"", "\"derive/^([nl])ve$/$1ue/\""])
        #expect(FuzzyPinyin.patch([], schema: schema) == nil && FuzzyPinyin.patch(["n-l"], schema: "speller:\n") == nil)
        #expect(FuzzyPinyin.known(["n-l", "bogus", "z-zh", "n-l"]) == ["z-zh", "n-l"])
        #expect(FuzzyPinyin.pairs.first?.label == "z ↔ zh")
    }

    @Test func writtenChangedRemovedAndTheUsersOwnLeftAlone() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fuzzy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let schemaURL = dir.appendingPathComponent("rime_ice.schema.yaml")
        try schema.write(to: schemaURL, atomically: true, encoding: .utf8)
        let user = dir.appendingPathComponent("user")
        let file = user.appendingPathComponent(FuzzyPinyin.fileName)
        #expect(try FuzzyPinyin.apply([], schema: schemaURL, userDir: user) == .unchanged)
        #expect(try FuzzyPinyin.apply(["n-l"], schema: schemaURL, userDir: user) == .written)
        #expect(try FuzzyPinyin.apply(["n-l"], schema: schemaURL, userDir: user) == .unchanged)
        #expect(try FuzzyPinyin.apply(["n-l", "in-ing"], schema: schemaURL, userDir: user) == .written)
        #expect(try String(contentsOf: file, encoding: .utf8).contains("derive/ing$/in/"))
        #expect(try FuzzyPinyin.apply([], schema: schemaURL, userDir: user) == .removed && !FileManager.default.fileExists(atPath: file.path))
        // The user's own file: never written over, nor removed.
        try "patch:\n  menu/page_size: 9\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(try FuzzyPinyin.apply(["n-l"], schema: schemaURL, userDir: user) == .userFile)
        #expect(try FuzzyPinyin.apply([], schema: schemaURL, userDir: user) == .unchanged)
        #expect(try String(contentsOf: file, encoding: .utf8) == "patch:\n  menu/page_size: 9\n")
    }

    @Test func keptInTheConfig() throws {
        var config = Config.default
        #expect(config.fuzzyPinyin.isEmpty)
        config.fuzzyPinyin = ["z-zh", "n-l"]
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(decoded.fuzzyPinyin == ["z-zh", "n-l"])
        let written = try JSONDecoder().decode(Config.self, from: Data(#"{"fuzzyPinyin": ["n-l", "nope", "z-zh"]}"#.utf8))
        #expect(written.fuzzyPinyin == ["z-zh", "n-l"])
    }
}

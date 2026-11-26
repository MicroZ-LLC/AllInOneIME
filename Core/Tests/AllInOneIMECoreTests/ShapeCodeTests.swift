import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Shape codes (`ShapeCode`): the setting read, a schema's filters, the patch's lines, and the patch writer putting them in
/// each pinyin schema's patch, never Zhuyin's. librime on rime-ice's schemas and the real tables: `ShapeCodeRimeTests` in
/// the shell's Rime tests.
struct ShapeCodeTests {
    @Test func theSettingNamesATableTheAppCarriesOrIsOff() {
        #expect(ShapeCode.allCases.map(\.rawValue) == ["moqi", "flypy", "wubi86", "cangjie"])
        #expect(ShapeCode.allCases.map(\.table) == ["moqi_aux_code", "flypy_full", "wubi86-code", "cangjie5_quick_code"])
        // 自然码's table isn't carried (its license), and a later version's table is off here too.
        for off in [nil, "", "off", "ziranma", "zhengma"] { #expect(ShapeCode(setting: off) == nil, "\(off ?? "nil")") }
        #expect(ShapeCode(setting: "wubi86") == .wubi86)
    }

    /// As much of rime-ice's schema as the patch reads: its filters, rime-ice's own on "`" among them.
    static let schema = """
        schema:
          schema_id: rime_ice
        engine:
          filters:
            - lua_filter@*corrector  # a comment
            # - lua_filter@*commented_out
            - simplifier@traditionalize
            - lua_filter@*search@radical_pinyin
            - uniquifier
        key_binder:
          search: "`"
        """

    @Test func theSchemasFiltersInOrder() {
        #expect(ShapeCode.filters(ofSchema: Self.schema)
            == ["lua_filter@*corrector", "simplifier@traditionalize", "lua_filter@*search@radical_pinyin", "uniquifier"])
        #expect(ShapeCode.filters(ofSchema: "schema:\n  schema_id: bopomofo\n").isEmpty)
    }

    /// A shared data folder with the filter's script (unless `script` is false), the `tables` in `aux_code/`, and the
    /// schemas: rime-ice's, Microsoft Shuangpin's (the same filters) and Zhuyin's (none of them).
    private func shared(tables: [ShapeCode], script: Bool = true) throws -> URL {
        let shared = TestScratch.temporary("shape-code-\(UUID().uuidString)").appendingPathComponent("shared")
        let fm = FileManager.default
        try fm.createDirectory(at: shared.appendingPathComponent("lua"), withIntermediateDirectories: true)
        try fm.createDirectory(at: shared.appendingPathComponent(ShapeCode.folder), withIntermediateDirectories: true)
        if script { try Data("-- filter".utf8).write(to: shared.appendingPathComponent("lua/\(ShapeCode.luaFilter).lua")) }
        for table in tables {
            try Data("鱼=da\n".utf8).write(to: shared.appendingPathComponent("\(ShapeCode.folder)/\(table.table).txt"))
        }
        try Data(Self.schema.utf8).write(to: shared.appendingPathComponent("rime_ice.schema.yaml"))
        let mspy = Self.schema.replacingOccurrences(of: "schema_id: rime_ice", with: "schema_id: double_pinyin_mspy")
        try Data(mspy.utf8).write(to: shared.appendingPathComponent("double_pinyin_mspy.schema.yaml"))
        try Data("schema:\n  schema_id: bopomofo\n".utf8).write(to: shared.appendingPathComponent("bopomofo.schema.yaml"))
        return shared
    }

    @Test func thePatchTakesRimeIcesPlaceWithTheScriptAndTheTable() throws {
        let shared = try shared(tables: [.moqi])
        defer { try? FileManager.default.removeItem(at: shared.deletingLastPathComponent()) }
        let patch = try #require(ShapeCode.moqi.patch(schema: Self.schema, sharedData: shared))
        #expect(patch.contains("  engine/filters/@2: lua_filter@*aux_code\n"), "\(patch)")
        #expect(patch.contains("  aux_code/dictionary: moqi_aux_code\n  aux_code/learn_trigger: \"`\"\n"), "\(patch)")
        #expect(!patch.contains("no_learn_trigger") && !patch.contains("update"), "\(patch)")
        // A schema without rime-ice's filter on "`": after the others.
        let other = Self.schema.replacingOccurrences(of: "    - lua_filter@*search@radical_pinyin\n", with: "")
        #expect(ShapeCode.moqi.patch(schema: other, sharedData: shared)?.contains("  engine/filters/@next: lua_filter@*aux_code\n") == true)
        // Without its table, or without the script: nothing (typing stays as it was).
        #expect(ShapeCode.cangjie.patch(schema: Self.schema, sharedData: shared) == nil)
        let noScript = try self.shared(tables: [.moqi], script: false)
        defer { try? FileManager.default.removeItem(at: noScript.deletingLastPathComponent()) }
        #expect(ShapeCode.moqi.patch(schema: Self.schema, sharedData: noScript) == nil)
    }

    @Test func simplifiedTableKeepsOtherFiltersInOrderForTraditionalOutput() throws {
        let shared = try shared(tables: [.wubi86])
        defer { try? FileManager.default.removeItem(at: shared.deletingLastPathComponent()) }
        let withExtraFilter = Self.schema.replacingOccurrences(of: "    - \(ShapeCode.radicalFilter)",
                                                                with: "    - lua_filter@*custom\n    - \(ShapeCode.radicalFilter)")
        let patch = try #require(ShapeCode.wubi86.patch(schema: withExtraFilter, sharedData: shared, characters: .taiwan))
        #expect(patch.contains("""
            engine/filters/@1: lua_filter@*aux_code
              engine/filters/@2: simplifier@traditionalize
              engine/filters/@3: lua_filter@*custom
            """))
        let withoutRadical = Self.schema.replacingOccurrences(of: "    - \(ShapeCode.radicalFilter)\n", with: "")
        let inserted = try #require(ShapeCode.wubi86.patch(schema: withoutRadical, sharedData: shared, characters: .hongkong))
        #expect(inserted.contains(#""engine/filters/@before 1": lua_filter@*aux_code"#))
    }

    @Test func eachPinyinSchemasPatchHasThemAndZhuyinsNever() throws {
        let shared = try shared(tables: ShapeCode.allCases)
        defer { try? FileManager.default.removeItem(at: shared.deletingLastPathComponent()) }
        let user = shared.deletingLastPathComponent().appendingPathComponent("user")
        let schema = shared.appendingPathComponent("rime_ice.schema.yaml")
        func patch(_ id: String) -> String? { try? String(contentsOf: user.appendingPathComponent("\(id).custom.yaml"), encoding: .utf8) }
        func apply(_ code: ShapeCode?, _ scheme: PinyinScheme) throws -> FuzzyPinyin.Outcome {
            try FuzzyPinyin.apply([], characters: .simplified, scheme: scheme, shapeCode: code, schema: schema, userDir: user)
        }
        #expect(try apply(.wubi86, .microsoft) == .written)
        for id in ["rime_ice", "double_pinyin_mspy"] {
            let text = try #require(patch(id), "\(id)")
            #expect(text.hasPrefix(FuzzyPinyin.marker + "\n"))
            #expect(text.contains("  engine/filters/@2: lua_filter@*aux_code\n  aux_code/dictionary: wubi86-code\n"), "\(id): \(text)")
        }
        // The same again: nothing to deploy; another table: written.
        #expect(try apply(.wubi86, .microsoft) == .unchanged)
        #expect(try apply(.cangjie, .microsoft) == .written)
        #expect(patch("double_pinyin_mspy")?.contains("aux_code/dictionary: cangjie5_quick_code") == true)
        // Zhuyin: its patch has none of it, full pinyin's still has.
        #expect(try apply(.cangjie, .zhuyin) == .written)
        #expect(patch("bopomofo").map { !$0.contains("aux_code") } ?? true, "\(patch("bopomofo") ?? "")")
        #expect(patch("rime_ice")?.contains("lua_filter@*aux_code") == true)
        // Off: gone.
        #expect(try apply(nil, .full) != .unchanged)
        #expect(patch("rime_ice").map { !$0.contains("aux_code") } ?? true)
        #expect(try apply(nil, .full) == .unchanged)
    }
}

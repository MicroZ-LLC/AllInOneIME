import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Independent acceptance contract for shape-code filtering (辅助码 / 形码筛选), spec of 2026-11-23: after the pinyin (full
// pinyin or any Shuangpin scheme), "`" and a table's shape letters narrow the candidates. Written from the spec alone; the
// implementer doesn't edit it (AGENTS.md rule 11). This file covers the setting (the config file, Settings → Input →
// Chinese, iCloud sync) and the session's keys on a stand-in engine; the Rime acceptance file of the same name
// (Tests/AllInOneIMERimeTests/Acceptance) types on the real rime-ice data and librime, each table's real codes.

// MARK: - Adapter: the implementation's names this file assumes (retarget here only)

private enum ShapeCodeNames {
    /// The config file's key, the Settings field's id, the synced setting's name.
    static let key = "shapeCode"
    /// The tables offered, by the config's value, in the picker's order. A table left out of the app (its licence)
    /// comes out of this list.
    static let tables = ["moqi", "flypy", "wubi86", "cangjie"]  // ziranma: not shipped (no licence, "禁止商用")
    static func get(_ config: Config) -> String? { config.shapeCode }
    static func set(_ table: String?, in config: inout Config) { config.shapeCode = table }
    /// The core's enum of the tables, by raw value; off is nil, not a case.
    static var enumValues: [String] { ShapeCode.allCases.map(\.rawValue) }
    /// The picker's value for Off (the config keeps nil).
    static let offValue = AIConfig.JSONValue.string("off")
}

// MARK: - The spec's words

/// Every table the spec names, as Settings names it (Chinese, English).
private let tableNames: [String: (zh: String, en: String)] = [
    "moqi": ("墨奇码", "Moqi"), "flypy": ("鹤形", "Xiaohe shape"), "ziranma": ("自然码", "Ziranma"),
    "wubi86": ("五笔 86", "Wubi 86"), "cangjie": ("仓颉", "Cangjie"),
]
private let fieldWords = (zh: (label: "辅助码", help: "拼音后按 ` 或单击右 ⌥，再打形码，筛出想要的字", off: "关闭"),
                          en: (label: "Shape codes", help: "After the pinyin, press ` or tap right ⌥, then type the shape code to narrow the candidates",
                               off: "Off"))

/// rime-ice's way with "`", played by a stand-in engine: in its spelling's alphabet but starting nothing
/// (`speller/initials`), so typed into the input while something is composed, and with nothing composed its punctuation
/// ('`' : '·'). Its candidates for a few inputs play the filter's part (the Rime acceptance file has the real one).
private final class ShapeCodeEngine: PinyinEngine {
    let base = FakeEngine()
    private(set) var selected: [String] = []
    private var punctuation: String?

    init() {
        base.dictionary = [
            "yu": ["与", "于", "鱼"], "yu`": ["与", "于", "鱼"], "yu`d": ["鱼", "浴"], "yu`da": ["鱼"],
            "jiyu": ["给予", "鲫鱼", "激欲"], "jiyu`": ["给予", "鲫鱼", "激欲"], "jiyu`d": ["激欲", "鲫鱼"],
        ]
    }

    func selectSchema(_ id: String) -> Bool {
        selected.append(id)
        return true
    }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        guard keycode == 0x60, mask == 0 else { return base.processKey(keycode, mask: mask) }
        base.keys.append((keycode, mask))
        if base.input.isEmpty {
            punctuation = "·"
        } else {
            base.input.append("`")
            base.highlighted = 0
        }
        return true
    }

    func takeCommit() -> String? {
        if let punctuation {
            self.punctuation = nil
            return punctuation
        }
        return base.takeCommit()
    }

    func snapshot() -> EngineSnapshot { base.snapshot() }
    func selectCandidate(onPage index: Int) -> Bool { base.selectCandidate(onPage: index) }
    func deleteCandidate(onPage index: Int) -> Bool { base.deleteCandidate(onPage: index) }
    func setRemovedCandidates(_ texts: [String]) { base.setRemovedCandidates(texts) }
    func commitComposition() -> String? { base.commitComposition() }
    var rawInput: String { base.rawInput }
    func clearComposition() { base.clearComposition() }
    func setAsciiMode(_ on: Bool) { base.setAsciiMode(on) }
}

@Suite("Shape codes", .serialized)
struct ShapeCodeAcceptanceTests {
    private typealias Names = ShapeCodeNames

    // MARK: The config file

    @Test func offByDefaultAndInAFileFromBefore() throws {
        #expect(Names.get(.default) == nil)
        let old = try JSONDecoder().decode(Config.self, from: Data(#"{"inputLanguages":["zh","en"],"pinyinScheme":"double_pinyin_mspy"}"#.utf8))
        #expect(Names.get(old) == nil)
        #expect(old.pinyinScheme == "double_pinyin_mspy")
        let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        #expect(saved[Names.key] == nil || saved[Names.key] is NSNull, "off: a file from before stays without the key")
        #expect(Config.allKeys.contains(Names.key), "a key of the config file")
    }

    @Test func everyTableRoundTripsAsItsName() throws {
        #expect(!Names.tables.isEmpty && Set(Names.tables).isSubset(of: Set(tableNames.keys)), "the spec's tables only")
        #expect(Set(Names.tables).isSubset(of: Set(Names.enumValues)), "\(Names.enumValues)")
        #expect(Set(Names.enumValues).isSubset(of: Set(tableNames.keys)), "off is nil, no case: \(Names.enumValues)")
        for table in Names.tables {
            var config = Config.default
            Names.set(table, in: &config)
            let data = try JSONEncoder().encode(config)
            let saved = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(saved[Names.key] as? String == table)
            #expect(Names.get(try JSONDecoder().decode(Config.self, from: data)) == table)
        }
        var off = Config.default
        Names.set(Names.tables[0], in: &off)
        Names.set(nil, in: &off)
        #expect(Names.get(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(off))) == nil)
    }

    /// A table a later version adds (synced from it, say) leaves the file readable, the other settings as they were.
    @Test func aTableThisVersionDoesntKnowLeavesTheRestRead() throws {
        let file = #"{"inputLanguages":["zh","en"],"pinyinScheme":"double_pinyin_mspy","\#(Names.key)":"zhengma","fuzzyPinyin":["z-zh"]}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(file.utf8))
        #expect(config.pinyinScheme == "double_pinyin_mspy" && config.fuzzyPinyin == ["z-zh"])
        #expect(Names.get(config).map { !Names.tables.contains($0) } ?? true)
    }

    /// One setting of its own: the typing scheme changed keeps the table, and the table keeps the other settings.
    @Test func independentOfTheTypingSchemeAndTheOtherSettings() throws {
        var config = Config.default
        config.chineseCharacters = .taiwan
        config.fuzzyPinyin = ["z-zh"]
        config.removedCandidates = ["拟好"]
        config.pinyinScheme = "double_pinyin_mspy"
        Names.set(Names.tables[0], in: &config)
        for scheme in PinyinScheme.allCases {
            config.pinyinScheme = scheme.setting
            let loaded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
            #expect(Names.get(loaded) == Names.tables[0], "\(scheme)")
            #expect(loaded.typedPinyin == scheme && loaded.chineseCharacters == .taiwan)
            #expect(loaded.fuzzyPinyin == ["z-zh"] && loaded.removedCandidates == ["拟好"])
        }
    }

    // MARK: Settings → Input → Chinese

    private func service(language: String, file: String? = nil) throws -> (SettingsService, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shape-code-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data((file ?? #"{"inputLanguages":["zh","en"],"uiLanguage":"\#(language)"}"#).utf8).write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins"))
        return (SettingsService(store: SettingsStore(configURL: url), platform: .mac, library: library), url)
    }

    @Test func onePickerUnderTypingOffAndEveryTable() throws {
        let (service, url) = try service(language: "en")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = service.document()
        let field = try #require(document.field(Names.key))
        #expect(field.label == fieldWords.en.label)
        #expect(field.help == fieldWords.en.help)
        #expect(field.value == Names.offValue, "off by default")
        let choices = try #require(field.choices)
        #expect(choices.map(\.value) == [Names.offValue] + Names.tables.map(AIConfig.JSONValue.string))
        #expect(choices.map(\.label) == [fieldWords.en.off] + Names.tables.compactMap { tableNames[$0]?.en })
        // Under Typing (Input → Chinese), after it.
        let section = try #require(document.sections.first { $0.fields.contains { $0.id == "pinyinScheme" } })
        let ids = section.fields.map(\.id)
        let typing = try #require(ids.firstIndex(of: "pinyinScheme"))
        let picker = try #require(ids.firstIndex(of: Names.key), "in Typing's section: \(ids)")
        #expect(picker > typing, "\(ids)")
    }

    @Test func inChinese() throws {
        let (service, url) = try service(language: "zh")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let field = try #require(service.document().field(Names.key))
        #expect(field.label == fieldWords.zh.label)
        #expect(field.help == fieldWords.zh.help)
        #expect(field.choices?.map(\.label) == [fieldWords.zh.off] + Names.tables.compactMap { tableNames[$0]?.zh })
    }

    /// Shown for full pinyin and every Shuangpin scheme, hidden for the ways that aren't pinyin (Zhuyin; Wubi 86, whose
    /// spec, issue #187, hides them too); and, as Typing, only with Chinese typed.
    @Test func shownForPinyinHiddenForZhuyin() throws {
        let (service, url) = try service(language: "en")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let notPinyin: Set<PinyinScheme> = [.zhuyin, .wubi]
        for scheme in PinyinScheme.allCases {
            _ = try service.set("pinyinScheme", to: .string(scheme.rawValue)).get()
            let field = service.document().field(Names.key)
            #expect((field == nil) == notPinyin.contains(scheme), "\(scheme)")
        }
        let (english, other) = try self.service(language: "en", file: #"{"inputLanguages":["en"],"uiLanguage":"en"}"#)
        defer { try? FileManager.default.removeItem(at: other.deletingLastPathComponent()) }
        #expect(english.document().field(Names.key) == nil, "no Chinese typed: no Typing, no shape codes")
    }

    @Test func pickingATableSavesItAndOffTakesItOut() throws {
        let (service, url) = try service(language: "en")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        for table in Names.tables {
            _ = try service.set(Names.key, to: .string(table)).get()
            #expect(Names.get(try Config.load(from: url)) == table)
            #expect(service.document().field(Names.key)?.value == .string(table))
        }
        // Not a table: refused, the table kept.
        if case .success = service.set(Names.key, to: .string("zhengma")) { Issue.record("a table that isn't one was taken") }
        #expect(Names.get(try Config.load(from: url)) == Names.tables.last)
        _ = try service.set(Names.key, to: Names.offValue).get()
        #expect(Names.get(try Config.load(from: url)) == nil)
        #expect(service.document().field(Names.key)?.value == Names.offValue)
        // Picking a Shuangpin scheme after keeps it.
        _ = try service.set(Names.key, to: .string(Names.tables[0])).get()
        _ = try service.set("pinyinScheme", to: .string(PinyinScheme.microsoft.rawValue)).get()
        let config = try Config.load(from: url)
        #expect(Names.get(config) == Names.tables[0] && config.typedPinyin == .microsoft)
    }

    /// Every interface language the catalog has: the field's words translated (the core's tests read the catalog; the
    /// app compiles it into its bundle).
    @Test func translatedInEveryInterfaceLanguage() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try Data(contentsOf: package.appendingPathComponent("Resources/Localizable.xcstrings"))
        let tables = try StringCatalog.tables(from: catalog)
        let english = [fieldWords.en.label, fieldWords.en.help, fieldWords.en.off] + Names.tables.compactMap { tableNames[$0]?.en }
        for language in StringCatalogCheck.languages {
            let table = try #require(tables[language], "\(language)")
            for words in english {
                #expect(table[words]?.isEmpty == false, "\(language): \(words)")
            }
            let (service, url) = try service(language: language)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let field = try #require(service.document().field(Names.key), "\(language)")
            #expect(!field.label.isEmpty && !(field.help ?? "").isEmpty, "\(language)")
            #expect(field.choices?.allSatisfy { !$0.label.isEmpty } == true, "\(language)")
        }
    }

    // MARK: iCloud sync, as the typing scheme

    @Test func syncCarriesTheTableBothWaysAndOffToo() {
        #expect(ICloudSync.settingsKeys.contains(Names.key))
        let world = ICAWorld()
        let a = world.mac("A") { Names.set(Names.tables[0], in: &$0) }
        let b = world.mac("B")
        a.sync(at: 10)
        let first = b.sync(at: 20)
        #expect(Names.get(b.config) == Names.tables[0])
        #expect(first.configKeys.contains(Names.key))
        let other = Names.tables[Names.tables.count - 1]
        b.edit(at: 30) { Names.set(other, in: &$0) }
        b.sync(at: 40)
        let second = a.sync(at: 50)
        #expect(Names.get(a.config) == other)
        #expect(second.configKeys.contains(Names.key))
        a.edit(at: 60) { Names.set(nil, in: &$0) }
        a.sync(at: 70)
        let third = b.sync(at: 80)
        #expect(Names.get(b.config) == nil, "off syncs too")
        #expect(third.configKeys.contains(Names.key))
    }

    @Test func syncTakesOnlyATableThisVersionHas() {
        let env = ICloudSync.Environment()
        for table in Names.tables {
            #expect(ICloudSync.problem(Names.key, .string(table), environment: env) == nil, "\(table)")
        }
        #expect(ICloudSync.problem(Names.key, .string("zhengma"), environment: env) == .unknownValue)
        #expect(ICloudSync.problem(Names.key, .bool(true), environment: env) == .wrongType)
        #expect(ICloudSync.problem(Names.key, nil, environment: env) == nil, "deleted: off")
    }

    // MARK: The keys, on a stand-in engine

    private func host(_ engine: ShapeCodeEngine, scheme: PinyinScheme, table: String?) -> FakeHost {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.pinyinScheme = scheme.setting
        Names.set(table, in: &config)
        let fixed = config
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.appTypesKeys = true
        host.focus()
        return host
    }

    /// In full pinyin and every Shuangpin scheme "`" and the letters after it go to the engine while something is
    /// composed, nothing reaches the field (nor is marked there) before a pick, and a pick (Space, a digit) puts in the
    /// candidate alone.
    @Test func graveReachesTheEngineInEverySchemeAndOnlyThePickGoesIn() {
        for scheme in [PinyinScheme.full] + PinyinScheme.shuangpin {
            let engine = ShapeCodeEngine()
            let host = host(engine, scheme: scheme, table: Names.tables[0])
            host.type("yu`da")
            #expect(engine.rawInput == "yu`da", "\(scheme): \(engine.rawInput)")
            #expect(host.document.isEmpty && host.marked.isEmpty, "\(scheme): \(host.document)")
            #expect(host.panel?.rows.first?.text == "鱼", "\(scheme)")
            host.press(FakeHost.space)
            #expect(host.document == "鱼" && engine.rawInput.isEmpty, "\(scheme): \(host.document)")
            host.type("jiyu`d")
            #expect(engine.rawInput == "jiyu`d", "\(scheme): \(engine.rawInput)")
            host.type("2")
            #expect(host.document == "鱼鲫鱼" && engine.rawInput.isEmpty, "\(scheme): \(host.document)")
            #expect(!host.document.contains("`"))
        }
    }

    /// Backspace takes the shape letters, then "`", then the pinyin: each the engine's.
    @Test func backspaceTakesTheLettersThenTheGraveThenThePinyin() {
        for scheme in [PinyinScheme.full, .microsoft] {
            let engine = ShapeCodeEngine()
            let host = host(engine, scheme: scheme, table: Names.tables[0])
            host.type("yu`da")
            var inputs: [String] = []
            for _ in 0..<5 {
                host.press(KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}"))
                inputs.append(engine.rawInput)
            }
            #expect(inputs == ["yu`d", "yu`", "yu", "y", ""], "\(scheme)")
            #expect(host.document.isEmpty && host.panel == nil, "\(scheme): \(host.document)")
        }
    }

    /// "`" with nothing composed is what it is with shape codes off (the engine's punctuation): nothing composed after.
    @Test func graveWithNothingComposedIsAsWithShapeCodesOff() {
        func grave(_ table: String?, _ scheme: PinyinScheme) -> (String, Bool) {
            let engine = ShapeCodeEngine()
            let host = host(engine, scheme: scheme, table: table)
            host.type("`")
            return (host.document, engine.rawInput.isEmpty && host.panel == nil)
        }
        for scheme in [PinyinScheme.full, .microsoft, .xiaohe] {
            let off = grave(nil, scheme)
            #expect(off == ("·", true), "\(scheme): \(off)")
            for table in Names.tables {
                #expect(grave(table, scheme) == off, "\(scheme) \(table)")
            }
        }
    }
}

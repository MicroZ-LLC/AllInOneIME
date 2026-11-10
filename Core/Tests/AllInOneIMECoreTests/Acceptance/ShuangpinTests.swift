import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Independent acceptance contract for the 2026-11-09 Shuangpin request. Implementers do not edit Acceptance tests.
// Minimal expected API: Config.pinyinScheme: String? (nil and "full" mean full pinyin), and
// PinyinEngine.selectSchema(_ id: String) -> Bool. InputSession applies the configured schema before the next key.
// The Rime acceptance file exercises the same method on RimeSession with the bundled real schemas.

private final class ShuangpinEngine: PinyinEngine {
    let base = FakeEngine()
    private(set) var selected: [String] = []

    func selectSchema(_ id: String) -> Bool {
        selected.append(id)
        base.dictionary = id == "double_pinyin_flypy"
            ? ["nihc": ["你好"], "nihao": ["nihao"]]
            : ["nihao": ["你好"], "nihc": ["nihc"]]
        return true
    }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool { base.processKey(keycode, mask: mask) }
    func takeCommit() -> String? { base.takeCommit() }
    func snapshot() -> EngineSnapshot { base.snapshot() }
    func selectCandidate(onPage index: Int) -> Bool { base.selectCandidate(onPage: index) }
    func deleteCandidate(onPage index: Int) -> Bool { base.deleteCandidate(onPage: index) }
    func setRemovedCandidates(_ texts: [String]) { base.setRemovedCandidates(texts) }
    func commitComposition() -> String? { base.commitComposition() }
    var rawInput: String { base.rawInput }
    func clearComposition() { base.clearComposition() }
    func setAsciiMode(_ on: Bool) { base.setAsciiMode(on) }
}

@Suite("Shuangpin", .serialized)
struct ShuangpinTests {
    private let schemes = [
        "double_pinyin_flypy", "double_pinyin", "double_pinyin_mspy", "double_pinyin_sogou",
        "double_pinyin_abc", "double_pinyin_jiajia", "double_pinyin_ziguang",
    ]

    @Test func configDefaultsAndOldFilesAreFullPinyin() throws {
        #expect(Config.default.pinyinScheme == nil || Config.default.pinyinScheme == "full")
        let old = try JSONDecoder().decode(Config.self, from: Data(#"{"inputLanguages":["zh","en"],"chineseCharacters":"taiwan"}"#.utf8))
        #expect(old.pinyinScheme == nil || old.pinyinScheme == "full")
        #expect(old.chineseCharacters == .taiwan)
        let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        #expect(saved["pinyinScheme"] == nil || saved["pinyinScheme"] as? String == "full")
    }

    @Test func everyShuangpinChoiceRoundTripsAsItsSchemaID() throws {
        for id in schemes {
            var config = Config.default
            config.pinyinScheme = id
            let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
            #expect(saved["pinyinScheme"] as? String == id)
            #expect(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config)).pinyinScheme == id)
        }
        var full = Config.default
        full.pinyinScheme = "full"
        let reloaded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(full))
        #expect(reloaded.pinyinScheme == nil || reloaded.pinyinScheme == "full")
    }

    private func service(language: String) throws -> (SettingsService, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shuangpin-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(#"{"inputLanguages":["zh","en"],"uiLanguage":"\#(language)"}"#.utf8).write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins"))
        return (SettingsService(store: SettingsStore(configURL: url), platform: .mac, library: library), url)
    }

    @Test func settingsOffersAllSchemesBesideCharactersAndSavesChoice() throws {
        let (service, url) = try service(language: "en")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = service.document()
        let field = try #require(document.field("pinyinScheme"))
        #expect(field.label == "Typing")
        #expect(field.value == .string("full"))
        #expect(field.choices?.map(\.value) == (["full"] + schemes).map(AIConfig.JSONValue.string))
        #expect(field.choices?.map(\.label) == ["Full pinyin", "Shuangpin – Xiaohe", "Shuangpin – Ziranma",
                                                "Shuangpin – Microsoft", "Shuangpin – Sogou", "Shuangpin – Zhineng ABC",
                                                "Shuangpin – Pinyin Jiajia", "Shuangpin – Ziguang"])
        let section = try #require(document.sections.first { $0.fields.contains { $0.id == "chineseCharacters" } })
        let ids = section.fields.map(\.id)
        let typing = try #require(ids.firstIndex(of: "pinyinScheme"))
        let characters = try #require(ids.firstIndex(of: "chineseCharacters"))
        #expect(abs(typing - characters) == 1)
        _ = try service.set("pinyinScheme", to: .string("double_pinyin_flypy")).get()
        #expect(try Config.load(from: url).pinyinScheme == "double_pinyin_flypy")
    }

    @Test func typingChoiceIsLocalizedInSevenInterfaceLanguages() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try Data(contentsOf: package.appendingPathComponent("Resources/Localizable.xcstrings"))
        let tables = try StringCatalog.tables(from: catalog)
        let labels = ["fr": "Saisie", "de": "Eingabeweise", "es": "Escritura", "ja": "入力方式", "ko": "입력 방식"]
        let englishChoices = PinyinScheme.allCases.map { $0.name(in: "en") }
        let englishHelp = UIText.$scopedLanguage.withValue("en") { UIText.pinyinSchemeHelp }
        for language in ["zh", "en", "fr", "de", "es", "ja", "ko"] {
            let (service, url) = try service(language: language)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let field = try #require(service.document().field("pinyinScheme"), "\(language)")
            #expect(!field.label.isEmpty && !(field.help ?? "").isEmpty, "\(language)")
            #expect(field.choices?.count == 8, "\(language)")
            #expect(field.choices?.allSatisfy { !$0.label.isEmpty } == true, "\(language)")
            if language == "zh" {
                #expect(field.label == "输入方式")
                #expect(field.choices?.first?.label == "全拼")
                #expect(field.choices?.contains { $0.label.contains("小鹤") } == true)
            } else if language == "en" {
                #expect(field.label == "Typing")
                #expect(field.choices?.first?.label == "Full pinyin")
            } else {
                // Core tests have no installed translation table. The app compiles this catalog into its bundle.
                let table = try #require(tables[language], "\(language)")
                #expect(table["Typing"] == labels[language], "\(language) field label")
                #expect(table["Full pinyin"]?.isEmpty == false && table["Full pinyin"] != "Full pinyin",
                        "\(language) full-pinyin choice")
                #expect(table[englishHelp]?.isEmpty == false, "\(language) field help")
                #expect(englishChoices.allSatisfy { table[$0]?.isEmpty == false }, "\(language) scheme choices")
            }
        }
    }

    @Test func syncCarriesTheChoiceBothWays() {
        let world = ICAWorld()
        let a = world.mac("A") { $0.pinyinScheme = "double_pinyin_flypy" }
        let b = world.mac("B")
        a.sync(at: 10)
        let first = b.sync(at: 20)
        #expect(b.config.pinyinScheme == "double_pinyin_flypy")
        #expect(first.configKeys.contains("pinyinScheme"))
        b.edit(at: 30) { $0.pinyinScheme = "double_pinyin_mspy" }
        b.sync(at: 40)
        let second = a.sync(at: 50)
        #expect(a.config.pinyinScheme == "double_pinyin_mspy")
        #expect(second.configKeys.contains("pinyinScheme"))
    }

    @Test func choosingShuangpinKeepsOtherInputAndAISettings() throws {
        var config = Config.default
        config.chineseCharacters = .taiwan
        config.fuzzyPinyin = ["z-zh"]
        config.englishWords = ["Bedrock"]
        config.removedCandidates = ["拟好"]
        config.provider = .anthropic
        config.autocomplete = true
        config.pinyinScheme = "double_pinyin_flypy"
        let loaded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(loaded.chineseCharacters == .taiwan)
        #expect(loaded.fuzzyPinyin == ["z-zh"])
        #expect(loaded.englishWords == ["Bedrock"])
        #expect(loaded.removedCandidates == ["拟好"])
        #expect(loaded.provider == .anthropic && loaded.autocomplete)
        #expect(loaded.pinyinScheme == "double_pinyin_flypy")
    }

    @Test func nextKeyUsesNewSchemeWithoutRefocusing() {
        final class Box { var config = Config.default }
        let box = Box()
        box.config.setOrder([Language.chinese, .english])
        let engine = ShuangpinEngine()
        var services = SessionServices(loadSettings: { box.config })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.focus()
        host.type("nihao")
        host.press(FakeHost.space)
        #expect(host.document == "你好")
        box.config.pinyinScheme = "double_pinyin_flypy"
        host.type("nihc")
        #expect(engine.selected.last == "double_pinyin_flypy")
        #expect(host.panel?.rows.contains { $0.text.contains("你好") } == true)
        host.press(FakeHost.space)
        #expect(host.document == "你好你好")
        box.config.pinyinScheme = "full"
        host.type("nihao")
        #expect(engine.selected.last == "rime_ice")
        host.press(FakeHost.space)
        #expect(host.document == "你好你好你好")
    }

    @Test func oneAtMatchesCommandByLettersAndShowsShuangpinCandidates() {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.pinyinScheme = "double_pinyin_flypy"
        let fixed = config
        let engine = ShuangpinEngine()
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.focus()
        host.type("@im")
        #expect(host.composer.paletteMatches.contains { $0.name == "improve" }, "@ command matching still uses letters")
        let nextEngine = ShuangpinEngine()
        services.levelOne = { .engine(nextEngine) }
        let next = FakeHost(services: services)
        next.focus()
        next.type("@nihc")
        #expect(next.panel?.candidates?.contains("你好") == true,
                "the separate pinyin candidate line uses the Shuangpin scheme")
    }
}

import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Independent acceptance contract for Zhuyin (2026-11-10). Implementers do not edit Acceptance tests.
// Assumed API: Config.pinyinScheme stores "bopomofo"; PinyinScheme(setting: "bopomofo") selects that
// Rime schema, PinyinScheme.allCases lists it, and PinyinEngine.selectSchema("bopomofo") is called
// before the next key. SettingsService keeps its existing "pinyinScheme" and "chineseCharacters" fields.

private final class ZhuyinEngine: PinyinEngine {
    private(set) var selected: [String] = []
    private(set) var keys: [Int32] = []
    private var input = ""
    private var commit: String?
    private var ascii = false

    func selectSchema(_ id: String) -> Bool { selected.append(id); return true }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        keys.append(keycode)
        if ascii { return false }
        if (0x61...0x7a).contains(keycode) || (0x30...0x39).contains(keycode) {
            input.append(Character(Unicode.Scalar(UInt8(keycode))))
            return true
        }
        if keycode == RimeKey.returnKey, !input.isEmpty {
            commit = input == "su3cl3" ? "你好" : input
            input = ""
            return true
        }
        if keycode == RimeKey.escape { input = ""; return true }
        return !input.isEmpty
    }

    func takeCommit() -> String? { defer { commit = nil }; return commit }
    func snapshot() -> EngineSnapshot {
        EngineSnapshot(isComposing: !input.isEmpty, preedit: input, cursor: input.count,
                       candidates: input.isEmpty ? [] : [EngineCandidate(label: "1", text: input == "su3cl3" ? "你好" :
                                                                          input == "bedrock" ? "貝德" : input)],
                       isAsciiMode: ascii)
    }
    func selectCandidate(onPage index: Int) -> Bool {
        guard index == 0, !input.isEmpty else { return false }
        commit = input == "su3cl3" ? "你好" : input
        input = ""
        return true
    }
    func commitComposition() -> String? {
        guard !input.isEmpty else { return nil }
        defer { input = "" }
        return input == "su3cl3" ? "你好" : input
    }
    var rawInput: String { input }
    func clearComposition() { input = "" }
    func setAsciiMode(_ on: Bool) { ascii = on }
}

@Suite("Zhuyin", .serialized)
struct ZhuyinTests {
    private func service(language: String = "en", characters: String? = nil) throws -> (SettingsService, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zhuyin-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        var json: [String: Any] = ["inputLanguages": ["zh", "en"], "uiLanguage": language]
        if let characters { json["chineseCharacters"] = characters }
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins"))
        return (SettingsService(store: SettingsStore(configURL: url), platform: .mac, library: library), url)
    }

    @Test func schemaIDRoundTripsAndIsNotShuangpin() throws {
        let scheme = PinyinScheme(setting: "bopomofo")
        #expect(scheme.rawValue == "bopomofo")
        #expect(scheme.schema == "bopomofo")
        #expect(scheme.setting == "bopomofo")
        #expect(PinyinScheme.allCases.contains(scheme))
        #expect(!PinyinScheme.shuangpin.contains(scheme))
        #expect(scheme.schemaList.contains("bopomofo"))
        var config = Config.default
        config.pinyinScheme = "bopomofo"
        let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        #expect(saved["pinyinScheme"] as? String == "bopomofo")
        #expect(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config)).typedPinyin.schema == "bopomofo")
    }

    @Test func settingsOffersZhuyinBesideCharactersInSevenLanguages() throws {
        let english = "Zhuyin (Bopomofo) – Standard"
        let chinese = "注音 – 標準/大千"
        let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Localizable.xcstrings")
        let tables = try StringCatalog.tables(from: Data(contentsOf: catalog))
        for language in ["zh", "en", "fr", "de", "es", "ja", "ko"] {
            let (service, url) = try service(language: language)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let document = service.document()
            let field = try #require(document.field("pinyinScheme"), "\(language)")
            let choice = try #require(field.choices?.first { $0.value == .string("bopomofo") }, "\(language)")
            #expect(!choice.label.isEmpty, "\(language)")
            if language == "zh" { #expect(choice.label == chinese) }
            if language == "en" { #expect(choice.label == english) }
            if !["zh", "en"].contains(language) {
                #expect(tables[language]?[english]?.isEmpty == false, "\(language) Zhuyin translation")
                #expect(tables[language]?[english] != english, "\(language) Zhuyin translation")
            }
            let section = try #require(document.sections.first { $0.fields.contains { $0.id == "chineseCharacters" } })
            let ids = section.fields.map(\.id)
            let typing = try #require(ids.firstIndex(of: "pinyinScheme"))
            let characters = try #require(ids.firstIndex(of: "chineseCharacters"))
            #expect(abs(typing - characters) == 1)
        }
    }

    @Test func settingsSearchFindsAllFourNames() throws {
        // SettingsSpot is in the macOS executable, outside this Core test target. Check its search-row
        // keywords, which are exactly the words the window's SettingsSpot.search() queries.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/AllInOneIME/SettingsSearch.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "case .pinyinScheme:\n"))
        let end = try #require(source.range(of: "case .chineseCharacters:", range: start.upperBound..<source.endIndex))
        let keywords = source[start.upperBound..<end.lowerBound].lowercased()
        for word in ["zhuyin", "注音", "bopomofo", "大千"] {
            #expect(keywords.contains(word), "Settings search must find \(word)")
        }
    }

    @Test func firstZhuyinChoiceDefaultsCharactersToTaiwanButKeepsAnExplicitChoice() throws {
        let (service, url) = try service()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try Config.load(from: url).chineseCharacters == nil)
        _ = try service.set("pinyinScheme", to: .string("bopomofo")).get()
        let chosen = try Config.load(from: url)
        #expect(chosen.pinyinScheme == "bopomofo")
        #expect(chosen.chineseCharacters == .taiwan)
        #expect(chosen.typedChinese == .taiwan)
        _ = try service.set("chineseCharacters", to: .string("simplified")).get()
        _ = try service.set("pinyinScheme", to: .string("full")).get()
        _ = try service.set("pinyinScheme", to: .string("bopomofo")).get()
        #expect(try Config.load(from: url).chineseCharacters == .simplified)

        let (prior, priorURL) = try self.service(characters: "hongkong")
        defer { try? FileManager.default.removeItem(at: priorURL.deletingLastPathComponent()) }
        _ = try prior.set("pinyinScheme", to: .string("bopomofo")).get()
        #expect(try Config.load(from: priorURL).chineseCharacters == .hongkong)
    }

    @Test func digitsAreZhuyinInputWhileComposing() {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.pinyinScheme = "bopomofo"
        let fixed = config
        let engine = ZhuyinEngine()
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.focus()
        host.type("su")
        host.type("3") // ㄋㄧˇ: a tone, not candidate 3
        #expect(engine.selected.last == "bopomofo")
        #expect(engine.rawInput == "su3")
        #expect(engine.keys.contains(0x33))
        #expect(host.document.isEmpty)
        host.type("cl3")
        #expect(engine.rawInput == "su3cl3")
        host.press(FakeHost.enter)
        #expect(host.document == "你好")
    }

    @Test func magicKeyStillMatchesLatinCommandNamesWithoutZhuyinCandidateLine() {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.pinyinScheme = "bopomofo"
        let fixed = config
        let engine = ZhuyinEngine()
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.focus()
        host.type("@im")
        #expect(host.composer.paletteMatches.contains { $0.name == "improve" })
        #expect(host.composer.oneAt?.letters == "im")
        #expect(engine.rawInput.isEmpty, "letters after @ are command names, not Zhuyin keys")
        #expect(host.panel?.candidates?.isEmpty != false, "one @ has no Zhuyin candidate line")
    }

    @Test func englishWordsDoNotJoinZhuyinCandidates() {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.pinyinScheme = "bopomofo"
        config.englishWords = ["Bedrock"]
        let fixed = config
        let engine = ZhuyinEngine()
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        services.englishDictionary = { EnglishDictionary([]) }
        let host = FakeHost(services: services)
        host.focus()
        host.type("bedrock")
        #expect(engine.selected.last == "bopomofo")
        #expect(host.composer.engine?.snapshot().candidates.contains { $0.text == "Bedrock" } != true)
    }

    @Test func userDocumentationAndBundledDataNoticesNameZhuyin() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func read(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let guideHasZhuyin = try read("Resources/user-guide.md").localizedCaseInsensitiveContains("zhuyin")
        let englishReadmeHasZhuyin = try read("README.md").localizedCaseInsensitiveContains("zhuyin")
        let chineseReadmeHasZhuyin = try read("README.zh-CN.md").contains("注音")
        #expect(guideHasZhuyin)
        #expect(englishReadmeHasZhuyin)
        #expect(chineseReadmeHasZhuyin)
        let changelog = try read("CHANGELOG.md")
        let release = try #require(changelog.range(of: "## 0.7.3"))
        let next = changelog.range(of: "\n## ", range: release.upperBound..<changelog.endIndex)?.lowerBound
            ?? changelog.endIndex
        let releaseHasZhuyin = changelog[release.upperBound..<next].localizedCaseInsensitiveContains("zhuyin")
        #expect(releaseHasZhuyin)
        let notices = try read("THIRD_PARTY_NOTICES.md")
        let noticesNameBopomofo = notices.contains("rime-bopomofo")
        let noticesNameTerraPinyin = notices.contains("rime-terra-pinyin")
        #expect(noticesNameBopomofo)
        #expect(noticesNameTerraPinyin)
    }
}

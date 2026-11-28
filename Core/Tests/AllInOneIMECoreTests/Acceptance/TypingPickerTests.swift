import Foundation
import Testing
@testable import AllInOneIMECore

// Independent acceptance contract for the Typing picker split (Settings → Typing, 0.7.6, spec of 2026-11-27), written
// from the spec's text only. Implementers do not edit Acceptance tests (AGENTS.md rule 11).
//
// "Row 1 打字方式 / Typing: four choices: 全拼 / 双拼 / 注音 / 五笔 86. It shows Shuangpin whenever the saved scheme is any
// Shuangpin scheme. Row 2 双拼方案 / Shuangpin scheme … shown only while Shuangpin is chosen … Picking one saves that
// scheme in `Config.pinyinScheme`. Choosing Shuangpin in row 1 selects the scheme used last, remembered in the settings
// model (in memory is enough, and survives switching away to full pinyin / Zhuyin / Wubi and back within a session); if
// none was used, 小鹤 (Xiaohe). If the saved scheme is already a Shuangpin one when Settings opens, that is the
// remembered one." UI only: the same `Config.pinyinScheme` values, no new config key, no migration.
//
// The spec's fixed interface (Core, public):
// - `enum TypingWay: String, CaseIterable, Sendable { case fullPinyin, shuangpin, zhuyin, wubi }`, in that order, with
//   `init(_ scheme: PinyinScheme)` (every Shuangpin scheme → .shuangpin) and `name(in:)` (zh-Hans: 全拼/双拼/注音/五笔 86;
//   en: Full pinyin/Shuangpin/Zhuyin/Wubi 86).
// - `SettingsStore.typingWay` (from the config), `SettingsStore.shuangpinScheme` (the Shuangpin scheme used last,
//   `.xiaohe` when none was), `SettingsStore.setTypingWay(_:)` (.shuangpin → `setPinyinScheme(shuangpinScheme)`, the
//   others their scheme, .fullPinyin → `.full`), and `setPinyinScheme` remembering the Shuangpin schemes it sets.
// - `setPinyinScheme` and `Config.pinyinScheme`'s values (nil, "double_pinyin_flypy" … "bopomofo", "wubi86") unchanged;
//   the settings document's `pinyinScheme` field (SettingsSchema, and its fixture) stays consistent with them.
// Not seen here: the Mac's two rows as drawn, and the settings search (TypingPickerSearchTests, in the Mac tests).

@Suite("Typing picker split", .serialized)
struct TypingPickerTests {
    /// Row 2's schemes, in the spec's order: 小鹤 / 自然码 / 微软 / 搜狗 / 智能ABC / 拼音加加 / 紫光.
    static let shuangpinSchemes: [PinyinScheme] = [.xiaohe, .ziranma, .microsoft, .sogou, .zhinengABC, .pinyinJiajia, .ziguang]

    /// What `Config.pinyinScheme` keeps for each scheme, as it did before the change (nil for full pinyin).
    static let savedValues: [(scheme: PinyinScheme, value: String?)] = [
        (.full, nil), (.xiaohe, "double_pinyin_flypy"), (.ziranma, "double_pinyin"), (.microsoft, "double_pinyin_mspy"),
        (.sogou, "double_pinyin_sogou"), (.zhinengABC, "double_pinyin_abc"), (.pinyinJiajia, "double_pinyin_jiajia"),
        (.ziguang, "double_pinyin_ziguang"), (.zhuyin, "bopomofo"), (.wubi, "wubi86"),
    ]

    /// A config file of the test's own (Chinese and English typed, an English interface), with `scheme` saved as
    /// `Config.pinyinScheme` and `characters` as `Config.chineseCharacters` when given. `remove` deletes its folder.
    private func configFile(scheme: String? = nil, characters: String? = nil) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("typing-picker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        var json: [String: Any] = ["inputLanguages": ["zh", "en"], "uiLanguage": "en"]
        if let scheme { json["pinyinScheme"] = scheme }
        if let characters { json["chineseCharacters"] = characters }
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        return url
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// The top-level keys of the config file at `url`.
    private func fileKeys(_ url: URL) throws -> Set<String> {
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return Set(object.keys)
    }

    private func isSendable<T: Sendable>(_: T.Type) -> Bool { true }

    // MARK: TypingWay

    @Test func theFourWaysInTheSpecsOrder() {
        #expect(TypingWay.allCases == [.fullPinyin, .shuangpin, .zhuyin, .wubi])
        #expect(TypingWay.allCases.map(\.rawValue) == ["fullPinyin", "shuangpin", "zhuyin", "wubi"])
        #expect(TypingWay(rawValue: "shuangpin") == .shuangpin)
        // A way is not a scheme: no scheme's saved value names one.
        for (_, value) in Self.savedValues {
            if let value { #expect(TypingWay(rawValue: value) == nil, "\(value)") }
        }
        #expect(isSendable(TypingWay.self))
    }

    @Test func eachWayIsNamedInChineseAndEnglish() throws {
        let names: [TypingWay: (zh: String, en: String)] = [
            .fullPinyin: ("全拼", "Full pinyin"), .shuangpin: ("双拼", "Shuangpin"), .zhuyin: ("注音", "Zhuyin"),
            .wubi: ("五笔 86", "Wubi 86"),
        ]
        for way in TypingWay.allCases {
            let name = try #require(names[way], "\(way)")
            #expect(way.name(in: "zh-Hans") == name.zh, "\(way) in Chinese: \(way.name(in: "zh-Hans"))")
            #expect(way.name(in: "en") == name.en, "\(way) in English: \(way.name(in: "en"))")
        }
    }

    /// Interface text in every language (rule 14): each way's English name is in the core's catalog for every language
    /// that has full pinyin's (`make strings`).
    @Test func eachWaysNameIsInEveryLanguageOfTheCatalog() throws {
        let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Localizable.xcstrings")
        let tables = try StringCatalog.tables(from: Data(contentsOf: catalog))
        let languages = tables.filter { $0.value["Full pinyin"]?.isEmpty == false }.map(\.key).sorted()
        #expect(!languages.isEmpty)
        for language in languages {
            for way in TypingWay.allCases {
                let english = way.name(in: "en")
                #expect(tables[language]?[english]?.isEmpty == false, "\(language): \(english)")
            }
        }
    }

    @Test func everySchemeBelongsToItsWay() {
        #expect(TypingWay(PinyinScheme.full) == .fullPinyin)
        for scheme in Self.shuangpinSchemes {
            #expect(TypingWay(scheme) == .shuangpin, "\(scheme)")
        }
        #expect(TypingWay(PinyinScheme.zhuyin) == .zhuyin)
        #expect(TypingWay(PinyinScheme.wubi) == .wubi)
        // Every scheme there is: Shuangpin exactly when it is a Shuangpin scheme, and each way has one.
        for scheme in PinyinScheme.allCases {
            #expect((TypingWay(scheme) == .shuangpin) == scheme.isShuangpin, "\(scheme)")
        }
        #expect(Set(PinyinScheme.allCases.map { TypingWay($0) }) == Set(TypingWay.allCases))
        // Row 2 lists the Shuangpin schemes in the spec's order.
        #expect(PinyinScheme.shuangpin == Self.shuangpinSchemes)
    }

    // MARK: The config

    /// "UI only; same `Config.pinyinScheme` values, no new config key, no migration".
    @Test func theSavedValuesAreThoseOfBefore() throws {
        #expect(PinyinScheme.allCases.count == Self.savedValues.count)
        for (scheme, value) in Self.savedValues {
            #expect(scheme.setting == value, "\(scheme)")
            #expect(PinyinScheme(setting: value) == scheme, "\(value ?? "nil")")
            var config = Config.default
            config.pinyinScheme = value
            let loaded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
            #expect(loaded.pinyinScheme == value, "\(scheme)")
            #expect(loaded.typedPinyin == scheme, "\(scheme)")
        }
        #expect(PinyinScheme(setting: "full") == .full)
    }

    // MARK: SettingsStore

    @Test func shuangpinChosenFirstIsXiaohe() throws {
        let url = try configFile()
        defer { remove(url) }
        let store = SettingsStore(configURL: url)
        #expect(store.typingWay == .fullPinyin)
        #expect(store.shuangpinScheme == .xiaohe)
        store.setTypingWay(.shuangpin)
        #expect(store.typingWay == .shuangpin)
        #expect(store.config.pinyinScheme == "double_pinyin_flypy")
        #expect(try Config.load(from: url).pinyinScheme == "double_pinyin_flypy")
        #expect(store.shuangpinScheme == .xiaohe)
    }

    @Test func eachWayChosenSavesItsSchemesValue() throws {
        let url = try configFile()
        defer { remove(url) }
        let store = SettingsStore(configURL: url)
        let steps: [(way: TypingWay, value: String?)] = [
            (.wubi, "wubi86"), (.zhuyin, "bopomofo"), (.shuangpin, "double_pinyin_flypy"), (.fullPinyin, nil),
            (.zhuyin, "bopomofo"), (.fullPinyin, nil), (.wubi, "wubi86"), (.shuangpin, "double_pinyin_flypy"),
        ]
        for (way, value) in steps {
            store.setTypingWay(way)
            #expect(store.typingWay == way)
            #expect(store.config.pinyinScheme == value, "\(way): \(store.config.pinyinScheme ?? "nil")")
            #expect(store.config.typedPinyin == PinyinScheme(setting: value), "\(way)")
            // Saved, as a choice in Settings is.
            #expect(try Config.load(from: url).pinyinScheme == value, "\(way) saved")
        }
    }

    @Test func theShuangpinSchemeUsedLastComesBackAfterTheOtherWays() throws {
        let url = try configFile()
        defer { remove(url) }
        let store = SettingsStore(configURL: url)
        store.setTypingWay(.shuangpin)
        // Row 2: Ziranma picked.
        store.setPinyinScheme(.ziranma)
        #expect(store.shuangpinScheme == .ziranma)
        #expect(try Config.load(from: url).pinyinScheme == "double_pinyin")
        for way in [TypingWay.fullPinyin, .zhuyin, .wubi] {
            store.setTypingWay(way)
            #expect(store.typingWay == way)
            #expect(store.shuangpinScheme == .ziranma, "after \(way)")
            store.setTypingWay(.shuangpin)
            #expect(store.config.typedPinyin == .ziranma, "back from \(way)")
            #expect(try Config.load(from: url).pinyinScheme == "double_pinyin", "back from \(way)")
        }
        // Away through all three in a row, and back.
        store.setPinyinScheme(.ziguang)
        store.setTypingWay(.wubi)
        store.setTypingWay(.zhuyin)
        store.setTypingWay(.fullPinyin)
        #expect(store.shuangpinScheme == .ziguang)
        store.setTypingWay(.shuangpin)
        #expect(store.config.pinyinScheme == "double_pinyin_ziguang")
        // Setting a way that isn't Shuangpin by its scheme doesn't change the one remembered.
        store.setPinyinScheme(.wubi)
        store.setPinyinScheme(.zhuyin)
        store.setPinyinScheme(.full)
        #expect(store.shuangpinScheme == .ziguang)
        #expect(store.typingWay == .fullPinyin)
    }

    @Test func everyShuangpinSchemePickedIsTheOneRemembered() throws {
        let url = try configFile()
        defer { remove(url) }
        let store = SettingsStore(configURL: url)
        for scheme in Self.shuangpinSchemes.reversed() {
            store.setPinyinScheme(scheme)
            #expect(store.typingWay == .shuangpin, "\(scheme)")
            #expect(store.shuangpinScheme == scheme)
            store.setTypingWay(.fullPinyin)
            #expect(store.shuangpinScheme == scheme, "\(scheme) after full pinyin")
            store.setTypingWay(.shuangpin)
            #expect(store.config.typedPinyin == scheme)
            #expect(try Config.load(from: url).pinyinScheme == scheme.rawValue, "\(scheme)")
        }
    }

    /// "If the saved scheme is already a Shuangpin one when Settings opens, that is the remembered one."
    @Test(arguments: [PinyinScheme.xiaohe, .ziranma, .microsoft, .sogou, .zhinengABC, .pinyinJiajia, .ziguang])
    func aShuangpinSchemeSavedBeforeIsTheOneRemembered(_ scheme: PinyinScheme) throws {
        let url = try configFile(scheme: scheme.rawValue)
        defer { remove(url) }
        let store = SettingsStore(configURL: url)
        #expect(store.typingWay == .shuangpin)
        #expect(store.shuangpinScheme == scheme)
        for way in [TypingWay.zhuyin, .wubi, .fullPinyin] {
            store.setTypingWay(way)
            store.setTypingWay(.shuangpin)
            #expect(store.config.typedPinyin == scheme, "back from \(way)")
            #expect(try Config.load(from: url).pinyinScheme == scheme.rawValue, "back from \(way)")
        }
    }

    /// Full pinyin, Zhuyin and Wubi saved show as themselves (a value this version doesn't know is full pinyin, as
    /// before), and Shuangpin chosen then starts at Xiaohe: none was used.
    @Test func theOtherWaysSavedShowAsThemselvesAndShuangpinStartsAtXiaohe() throws {
        let saved: [(value: String?, way: TypingWay)] = [
            (nil, .fullPinyin), ("full", .fullPinyin), ("bopomofo", .zhuyin), ("wubi86", .wubi), ("wubi98", .fullPinyin),
        ]
        for (value, way) in saved {
            let url = try configFile(scheme: value)
            defer { remove(url) }
            let store = SettingsStore(configURL: url)
            #expect(store.typingWay == way, "\(value ?? "none") saved")
            #expect(store.shuangpinScheme == .xiaohe, "\(value ?? "none") saved")
            store.setTypingWay(.shuangpin)
            #expect(store.config.typedPinyin == .xiaohe, "\(value ?? "none") saved")
            #expect(try Config.load(from: url).pinyinScheme == "double_pinyin_flypy", "\(value ?? "none") saved")
        }
    }

    /// `typingWay` is the config's: whatever set `Config.pinyinScheme`.
    @Test func theWayShownFollowsTheConfig() throws {
        let url = try configFile()
        defer { remove(url) }
        let store = SettingsStore(configURL: url)
        for (scheme, value) in Self.savedValues {
            store.config.pinyinScheme = value
            #expect(store.typingWay == TypingWay(scheme), "\(scheme)")
        }
    }

    /// Zhuyin chosen in row 1 does what choosing it in the one menu did (`setPinyinScheme`): Taiwan's characters for one
    /// who never picked any, the characters picked kept; Shuangpin and Wubi leave them as they are.
    @Test func zhuyinChosenAsAWayPicksTaiwansCharactersAsBefore() throws {
        let url = try configFile()
        defer { remove(url) }
        SettingsStore(configURL: url).setTypingWay(.zhuyin)
        #expect(try Config.load(from: url).chineseCharacters == .taiwan)

        let picked = try configFile(characters: "hongkong")
        defer { remove(picked) }
        SettingsStore(configURL: picked).setTypingWay(.zhuyin)
        #expect(try Config.load(from: picked).chineseCharacters == .hongkong)

        let others = try configFile()
        defer { remove(others) }
        let store = SettingsStore(configURL: others)
        store.setTypingWay(.shuangpin)
        store.setTypingWay(.wubi)
        store.setTypingWay(.fullPinyin)
        #expect(try Config.load(from: others).chineseCharacters == nil)
    }

    /// No new config key: a way chosen writes the file exactly as choosing its scheme did, and the remembered Shuangpin
    /// scheme is written nowhere in it.
    @Test func aWayChosenWritesTheFileAsItsSchemeChosenDid() throws {
        let byWay = try configFile()
        let byScheme = try configFile()
        defer {
            remove(byWay)
            remove(byScheme)
        }
        let ways = SettingsStore(configURL: byWay)
        let schemes = SettingsStore(configURL: byScheme)
        let before = try fileKeys(byWay)
        ways.setPinyinScheme(.sogou)
        schemes.setPinyinScheme(.sogou)
        let steps: [(way: TypingWay, scheme: PinyinScheme)] = [
            (.fullPinyin, .full), (.wubi, .wubi), (.shuangpin, .sogou), (.zhuyin, .zhuyin), (.shuangpin, .sogou), (.fullPinyin, .full),
        ]
        for (way, scheme) in steps {
            ways.setTypingWay(way)
            schemes.setPinyinScheme(scheme)
            #expect(ways.config == schemes.config, "\(way)")
            #expect(try fileKeys(byWay) == fileKeys(byScheme), "\(way)")
            #expect(try Config.load(from: byWay) == Config.load(from: byScheme), "\(way)")
        }
        // Only the keys a scheme choice has always written (the scheme, and Zhuyin's characters).
        let after = try fileKeys(byWay)
        #expect(after.subtracting(before).isSubset(of: ["pinyinScheme", "chineseCharacters"]), "\(after.subtracting(before))")
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ways.config)) as? [String: Any])
        let named = encoded.keys.filter { $0.lowercased().contains("shuangpin") || $0.lowercased().contains("typingway") }
        #expect(named.isEmpty, "\(named)")
    }

    // MARK: The settings document

    /// The settings document's `pinyinScheme` field (SettingsSchema; Windows' Settings and its fixture) stays as it was:
    /// its value for each of the four ways is the scheme's saved value, it still offers every scheme, and a Shuangpin
    /// scheme picked through it is remembered too (it sets it with `setPinyinScheme`).
    @Test func theDocumentsSchemeFieldKeepsItsValuesForTheFourWays() throws {
        let saved: [(value: String?, shown: String, way: TypingWay)] = [
            (nil, "full", .fullPinyin), ("double_pinyin_flypy", "double_pinyin_flypy", .shuangpin),
            ("double_pinyin", "double_pinyin", .shuangpin), ("double_pinyin_ziguang", "double_pinyin_ziguang", .shuangpin),
            ("bopomofo", "bopomofo", .zhuyin), ("wubi86", "wubi86", .wubi),
        ]
        let everyScheme = Set(PinyinScheme.allCases.map { AIConfig.JSONValue.string($0.rawValue) })
        for (value, shown, way) in saved {
            let url = try configFile(scheme: value)
            defer { remove(url) }
            let store = SettingsStore(configURL: url)
            let library = PluginLibrary(directory: url.deletingLastPathComponent().appendingPathComponent("plugins"))
            let service = SettingsService(store: store, platform: .mac, library: library)
            let field = try #require(service.document().field("pinyinScheme"), "\(shown)")
            #expect(field.value == .string(shown), "\(shown): \(String(describing: field.value))")
            #expect(Set(field.choices?.map(\.value) ?? []) == everyScheme, "\(shown)")
            #expect(store.typingWay == way, "\(shown)")
        }

        let url = try configFile()
        defer { remove(url) }
        let store = SettingsStore(configURL: url)
        let library = PluginLibrary(directory: url.deletingLastPathComponent().appendingPathComponent("plugins"))
        let service = SettingsService(store: store, platform: .mac, library: library)
        _ = try service.set("pinyinScheme", to: .string("double_pinyin_sogou")).get()
        #expect(store.typingWay == .shuangpin)
        #expect(store.shuangpinScheme == .sogou)
        _ = try service.set("pinyinScheme", to: .string("wubi86")).get()
        #expect(store.typingWay == .wubi)
        #expect(service.document().field("pinyinScheme")?.value == .string("wubi86"))
        store.setTypingWay(.shuangpin)
        #expect(try Config.load(from: url).pinyinScheme == "double_pinyin_sogou")
        #expect(service.document().field("pinyinScheme")?.value == .string("double_pinyin_sogou"))
    }
}

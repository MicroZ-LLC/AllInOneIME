import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// Settings' Chinese typing as two menus (`TypingWay`, and the Shuangpin scheme below it): the way each scheme types, the
/// ways' names, and the Shuangpin scheme the store picks for Shuangpin (`SettingsStore.shuangpinScheme`), all kept in the
/// one `Config.pinyinScheme`.
struct TypingWayTests {
    /// A config file of its own in a temporary folder, with `scheme` saved (none: full pinyin).
    func file(_ scheme: PinyinScheme? = nil) throws -> URL {
        let folder = TestScratch.temporary("typing-way-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        let setting = scheme?.setting.map { "\"pinyinScheme\": \"\($0)\", " } ?? ""
        try Data("{\(setting)\"inputLanguages\": [\"zh\", \"en\"]}".utf8).write(to: url)
        return url
    }

    func saved(_ url: URL) throws -> String? { try Config.load(from: url).pinyinScheme }

    @Test func eachSchemeTypesOneWay() {
        #expect(TypingWay.allCases == [.fullPinyin, .shuangpin, .zhuyin, .wubi])
        #expect(TypingWay(.full) == .fullPinyin && TypingWay(.zhuyin) == .zhuyin && TypingWay(.wubi) == .wubi)
        #expect(PinyinScheme.shuangpin.allSatisfy { TypingWay($0) == .shuangpin })
        #expect(PinyinScheme.shuangpin.count == 7)
        // Back to a scheme: Shuangpin's is the one given; each other way has its own.
        for scheme in PinyinScheme.allCases {
            #expect(TypingWay(scheme).scheme(shuangpin: scheme.isShuangpin ? scheme : .xiaohe) == scheme)
        }
        #expect(TypingWay.shuangpin.scheme(shuangpin: .ziguang) == .ziguang)
    }

    @Test func theWaysNames() {
        #expect(TypingWay.allCases.map { $0.name(in: "zh-Hans") } == ["全拼", "双拼", "注音", "五笔 86"])
        #expect(TypingWay.allCases.map { $0.name(in: "zh") } == ["全拼", "双拼", "注音", "五笔 86"])
        #expect(TypingWay.allCases.map { $0.name(in: "en") } == ["Full pinyin", "Shuangpin", "Zhuyin", "Wubi 86"])
        // The schemes' own names stay what the flat list (the settings document, the search) has.
        #expect(PinyinScheme.xiaohe.name(in: "zh-Hans") == "双拼 – 小鹤")
    }

    @Test func translatedInEveryLanguage() throws {
        let data = try Data(contentsOf: PinyinSchemeTests.package.appendingPathComponent("Resources/Localizable.xcstrings"))
        let lookup = InterfaceText.tableLookup(try StringCatalog.tables(from: data))
        for language in StringCatalogCheck.languages {
            for way in TypingWay.allCases {
                #expect(lookup(way.name(in: "en"), language)?.isEmpty == false, "\(language): \(way)")
            }
        }
    }

    /// Shuangpin picks Xiaohe until a scheme is used; after one, that one, also after full pinyin, Zhuyin or Wubi in
    /// between. Each pick is saved as the scheme, nothing else.
    @Test func shuangpinPicksTheSchemeUsedLast() throws {
        let url = try file()
        let store = SettingsStore(configURL: url)
        #expect(store.typingWay == .fullPinyin && store.shuangpinScheme == .xiaohe)
        store.setTypingWay(.shuangpin)
        #expect(store.typingWay == .shuangpin)
        #expect(try saved(url) == "double_pinyin_flypy")
        store.setPinyinScheme(.sogou)
        #expect(store.shuangpinScheme == .sogou)
        #expect(try saved(url) == "double_pinyin_sogou")
        for way in [TypingWay.fullPinyin, .zhuyin, .wubi] {
            store.setTypingWay(way)
            #expect(store.typingWay == way && store.shuangpinScheme == .sogou)
            store.setTypingWay(.shuangpin)
            #expect(store.config.typedPinyin == .sogou)
            #expect(try saved(url) == "double_pinyin_sogou")
        }
        store.setTypingWay(.fullPinyin)
        #expect(try saved(url) == nil)
        store.setTypingWay(.wubi)
        #expect(try saved(url) == "wubi86")
        // In memory only: Settings opened again on full pinyin starts at Xiaohe.
        store.setTypingWay(.fullPinyin)
        #expect(SettingsStore(configURL: url).shuangpinScheme == .xiaohe)
    }

    /// The scheme saved when Settings opens is the one remembered; Shuangpin picked again while it is typed keeps it.
    @Test func theSchemeSavedIsRemembered() throws {
        let url = try file(.microsoft)
        let store = SettingsStore(configURL: url)
        #expect(store.typingWay == .shuangpin && store.shuangpinScheme == .microsoft)
        store.setTypingWay(.shuangpin)
        #expect(try saved(url) == "double_pinyin_mspy")
        store.setTypingWay(.zhuyin)
        #expect(try saved(url) == "bopomofo")
        #expect(store.shuangpinScheme == .microsoft)
        store.setTypingWay(.shuangpin)
        #expect(try saved(url) == "double_pinyin_mspy")
    }

    /// A scheme the config leaves by another way (the file changed by the input menu's Settings, sync or by hand, read
    /// again) is remembered as one picked here is.
    @Test func aSchemeLeftInTheFileIsRemembered() throws {
        let url = try file(.ziguang)
        let store = SettingsStore(configURL: url)
        try Data("{\"inputLanguages\": [\"zh\", \"en\"]}".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        store.reloadIfChanged()
        #expect(store.typingWay == .fullPinyin && store.shuangpinScheme == .ziguang)
        store.setTypingWay(.shuangpin)
        #expect(try saved(url) == "double_pinyin_ziguang")
    }

    /// Zhuyin picked as a way still picks Taiwan's characters for one who never picked any (`setPinyinScheme`'s rule).
    @Test func zhuyinAsAWayFollowsTheSchemesRules() throws {
        let url = try file()
        let store = SettingsStore(configURL: url)
        store.setTypingWay(.zhuyin)
        #expect(store.config.chineseCharacters == .taiwan)
        #expect(try saved(url) == "bopomofo")
    }
}

@Suite("Shuangpin scheme names")
struct ShuangpinNameTests {
    @Test("the second menu names the scheme alone")
    func shortNames() {
        #expect(PinyinScheme.shuangpin.map { $0.shuangpinName(in: "zh-Hans") }
            == ["小鹤", "自然码", "微软", "搜狗", "智能ABC", "拼音加加", "紫光"])
        #expect(PinyinScheme.xiaohe.shuangpinName(in: "en") == "Xiaohe")
        #expect(PinyinScheme.full.shuangpinName(in: "en") == "Full pinyin")
    }
}

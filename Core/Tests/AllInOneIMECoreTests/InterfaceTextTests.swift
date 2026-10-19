import Foundation
import Testing
@testable import AllInOneIMECore

/// Interface text and its language: `UIString`, the catalog lookup (`InterfaceText`), picking the language
/// (`InterfaceLanguage`), and the config value.
struct InterfaceTextTests {
    /// A folder standing in for an app: `<code>.lproj/Localizable.strings` with `tables[code]`, as the Makefile
    /// compiles the catalog (an XML property list). A new folder each time: Bundle keeps what it has read.
    static func app(_ tables: [String: [String: String]]) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("interface-text-\(UUID().uuidString)")
        for (code, table) in tables {
            let folder = root.appendingPathComponent("\(code).lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: table, format: .xml, options: 0)
            try data.write(to: folder.appendingPathComponent("Localizable.strings"))
        }
        return try #require(Bundle(path: root.path))
    }

    static func lproj(_ app: Bundle, _ code: String) throws -> Bundle { try #require(InterfaceText.bundle(code, app: app)) }

    // MARK: UIString

    @Test func literalsBecomeFormats() {
        let n = 3, name = "Ada"
        let text: UIString = "\(n) items for \(name), 100% done"
        #expect(text.format == "%@ items for %@, 100%% done")
        #expect(text.arguments == ["3", "Ada"])
        #expect(text.text == "3 items for Ada, 100% done")
        let plain: UIString = "50% off"
        #expect(plain.format == "50%% off" && plain.arguments.isEmpty && plain.text == "50% off")
        // An argument is never read as a format.
        let odd = "%@ %d %%"
        let quoted: UIString = "“\(odd)”"
        #expect(quoted.format == "“%@”" && quoted.text == "“%@ %d %%”")
    }

    @Test func runtimeStringsAndJoinedLiterals() {
        #expect(UIString("100% sure") == UIString(stringLiteral: "100% sure"))
        #expect(UIString("100% sure").format == "100%% sure")
        let count = 2
        let joined: UIString = "\(count) of " + "\(count + 1), " + "50%"
        #expect(joined.format == "%@ of %@, 50%%" && joined.arguments == ["2", "3"] && joined.text == "2 of 3, 50%")
    }

    // MARK: Translations

    @Test func translateFillsTheArgumentsIn() throws {
        let app = try Self.app(["fr": ["%@ items": "%@ éléments", "%@ of %@": "%2$@ sur %1$@", "100%% done": "fini à 100 %%",
                                       "Open": "Ouvrir"]])
        let fr = try Self.lproj(app, "fr")
        let n = 4, total = 9
        #expect(InterfaceText.translate("\(n) items", in: fr) == "4 éléments")
        #expect(InterfaceText.translate("\(n) of \(total)", in: fr) == "9 sur 4")
        #expect(InterfaceText.translate("100% done", in: fr) == "fini à 100 %")
        #expect(InterfaceText.translate("Open", in: fr) == "Ouvrir")
        #expect(InterfaceText.translate("Close", in: fr) == nil)
    }

    /// A translation that doesn't fit its arguments is no translation: never a crash, nor garbage.
    @Test func badTranslationsGiveNil() throws {
        let app = try Self.app(["fr": ["%@ items": "%@ %@ éléments", "Saved": "%d enregistrés", "%@ left": "il reste %3$@",
                                       "Done": "Fini %", "%@ new": "%1$@ nouveaux, %@", "Zero %@": "%0$@"]])
        let fr = try Self.lproj(app, "fr")
        let n = 2
        #expect(InterfaceText.translate("\(n) items", in: fr) == nil)  // two arguments for one
        #expect(InterfaceText.translate("Saved", in: fr) == nil)  // %d
        #expect(InterfaceText.translate("\(n) left", in: fr) == nil)  // the third of one
        #expect(InterfaceText.translate("Done", in: fr) == nil)  // a lone %
        #expect(InterfaceText.translate("\(n) new", in: fr) == "2 nouveaux, 2")  // positional and in order
        #expect(InterfaceText.translate("Zero \(n)", in: fr) == nil)
    }

    @Test func textPicksByLanguage() throws {
        let app = try Self.app(["fr": ["%@ items": "%@ éléments", "remove.delete": "Supprimer"]])
        let n = 5
        #expect(InterfaceText.text("共 \(n) 个", "\(n) items", language: "zh-Hans", app: app) == "共 5 个")
        #expect(InterfaceText.text("共 \(n) 个", "\(n) items", language: "en", app: app) == "5 items")
        #expect(InterfaceText.text("共 \(n) 个", "\(n) items", language: "fr", app: app) == "5 éléments")
        #expect(InterfaceText.text("关闭", "Close", language: "fr", app: app) == "Close")  // not translated yet
        #expect(InterfaceText.text("共 \(n) 个", "\(n) items", language: "de", app: app) == "5 items")  // no de.lproj
        // A key of its own, where the English text has another meaning elsewhere.
        #expect(InterfaceText.text("删除", "Remove", key: "remove.delete", language: "fr", app: app) == "Supprimer")
        #expect(InterfaceText.text("删除", "Remove", key: "remove.delete", language: "en", app: app) == "Remove")
        #expect(InterfaceText.text("移除", "Remove", language: "fr", app: app) == "Remove")
    }

    @Test func configTextUsesTheLanguage() {
        #expect(AIConfig.Text(chinese: true).language == "zh-Hans" && AIConfig.Text(chinese: false).language == "en")
        var text = AIConfig.Text(language: "fr")
        #expect(!text.chinese && text.layout(.vertical) == "Vertical")  // no fr.lproj in the test bundle: English
        text.chinese = true
        #expect(text.language == "zh-Hans" && text.layout(.vertical) == "竖排")
        #expect(AIConfig.Text(language: "zh-Hant").chinese)
        #expect(AIConfig.Environment(chinese: true).language == "zh-Hans" && AIConfig.Environment(language: "fr").language == "fr")
    }

    // MARK: The language

    static let shipped = ["en", "zh-Hans"]

    @Test(arguments: [
        (["ja", "en"], "en"), (["ja", "zh-Hans"], "zh-Hans"), (["ja-JP"], "en"), ([], "en"), (["fr", "de"], "en"),
        (["en-GB", "zh-Hans"], "en"), (["zh-Hans-CN", "en"], "zh-Hans"), (["zh-CN"], "zh-Hans"), (["zh-SG"], "zh-Hans"),
        (["zh"], "zh-Hans"), (["zh-Hant-TW"], "zh-Hans"), (["zh-TW"], "zh-Hans"), (["zh-HK"], "zh-Hans"),
        (["zh-MO"], "zh-Hans"), (["zh_Hans_CN"], "zh-Hans"), (["ZH-hant"], "zh-Hans"), (["en_US"], "en"),
    ])
    func pickAmongTheBuiltInOnes(_ preferred: [String], _ expected: String) {
        #expect(InterfaceLanguage.pick(preferred: preferred, shipped: Self.shipped) == expected, "\(preferred)")
    }

    @Test(arguments: [
        (["zh-Hant-TW"], "zh-Hant"), (["zh-HK"], "zh-Hant"), (["zh-MO"], "zh-Hant"), (["zh-TW", "en"], "zh-Hant"),
        (["zh-Hans-HK"], "zh-Hans"), (["pt-BR"], "pt-BR"), (["pt-PT"], "pt"), (["pt_br"], "pt-BR"), (["ja-JP"], "ja"),
        (["fr-CA", "en"], "fr"), (["de", "ja"], "ja"), (["ko", "fr"], "fr"), (["ja-Jpan-JP"], "ja"),
    ])
    func pickAmongMore(_ preferred: [String], _ expected: String) {
        let shipped = ["en", "zh-Hans", "zh-Hant", "pt", "pt-BR", "ja", "fr"]
        #expect(InterfaceLanguage.pick(preferred: preferred, shipped: shipped) == expected, "\(preferred)")
    }

    /// The language with a region, else the language alone, else another variant of it in the same script.
    @Test func pickPrefersTheRegion() {
        #expect(InterfaceLanguage.pick(preferred: ["pt-BR"], shipped: ["en", "zh-Hans", "pt"]) == "pt")
        #expect(InterfaceLanguage.pick(preferred: ["pt-BR"], shipped: ["en", "zh-Hans", "pt", "pt-PT"]) == "pt")
        #expect(InterfaceLanguage.pick(preferred: ["pt-BR", "zh-Hans"], shipped: ["en", "zh-Hans", "pt-PT"]) == "pt-PT")
        #expect(InterfaceLanguage.pick(preferred: ["es-419"], shipped: ["en", "zh-Hans", "es-MX"]) == "es-MX")
        #expect(InterfaceLanguage.pick(preferred: ["sr-Latn-RS"], shipped: ["en", "zh-Hans", "sr-Latn"]) == "sr-Latn")
        #expect(InterfaceLanguage.pick(preferred: ["sr-Cyrl-RS", "en"], shipped: ["en", "zh-Hans", "sr-Latn"]) == "en")
        // Spelled as shipped.
        #expect(InterfaceLanguage.pick(preferred: ["PT_BR"], shipped: ["en", "zh-Hans", "pt-br"]) == "pt-br")
        #expect(InterfaceLanguage.pick(preferred: ["zh-TW"], shipped: ["en", "zh-Hans", "zh_Hant"]) == "zh_Hant")
    }

    /// The languages the apps ship (`StringCatalogCheck.languages`, compiled into `<code>.lproj`), from the system's
    /// preferred languages: a region is its language, Traditional Chinese never Simplified, Portugal's Portuguese
    /// Brazil's rather than English.
    static let everyLanguage = InterfaceLanguage.builtIn + StringCatalogCheck.languages

    @Test(arguments: [
        (["zh-Hant-TW"], "zh-Hant"), (["zh-Hant"], "zh-Hant"), (["zh-TW"], "zh-Hant"), (["zh-HK"], "zh-Hant"),
        (["zh-Hant-HK", "en"], "zh-Hant"), (["zh-MO"], "zh-Hant"), (["zh_Hant_TW"], "zh-Hant"),
        (["zh-Hans-CN"], "zh-Hans"), (["zh-CN"], "zh-Hans"), (["zh-SG"], "zh-Hans"), (["zh-Hans-HK"], "zh-Hans"),
        (["pt-BR"], "pt-BR"), (["pt-PT"], "pt-BR"), (["pt-PT", "en"], "pt-BR"), (["pt"], "pt-BR"), (["pt-AO"], "pt-BR"),
        (["de-AT"], "de"), (["de-CH"], "de"), (["de-DE"], "de"), (["es-MX"], "es"), (["es-419"], "es"), (["es-ES"], "es"),
        (["fr-CA"], "fr"), (["fr-FR"], "fr"), (["ja-JP"], "ja"), (["ja"], "ja"), (["ko-KR"], "ko"), (["ko"], "ko"),
        (["en-GB", "ja"], "en"), (["ru-RU", "de-AT"], "de"), (["ru-RU", "it"], "en"), (["ja-JP", "zh-Hant-TW"], "ja"),
    ])
    func pickEachLanguage(_ preferred: [String], _ expected: String) {
        #expect(InterfaceLanguage.pick(preferred: preferred, shipped: Self.everyLanguage) == expected, "\(preferred)")
    }

    /// Only Simplified Chinese takes `tr`'s first argument; Traditional Chinese is a catalog language like the others.
    @Test func simplifiedOrTraditional() {
        for code in ["zh-Hans", "zh-CN", "zh", "zh_Hans_SG"] { #expect(InterfaceLanguage.isSimplifiedChinese(code), "\(code)") }
        for code in ["zh-Hant", "zh-TW", "zh-HK", "en", "ja"] { #expect(!InterfaceLanguage.isSimplifiedChinese(code), "\(code)") }
        #expect(InterfaceLanguage.isChinese("zh-Hant"))
        let lookup: InterfaceText.Lookup = { key, language in language == "zh-Hant" && key == "Open" ? "打開" : nil }
        #expect(InterfaceText.text("打开", "Open", language: "zh-Hant", lookup: lookup) == "打開")
        #expect(InterfaceText.text("打开", "Open", language: "zh-Hans", lookup: lookup) == "打开")
        // Names written in Chinese in the code are Simplified Chinese's; Traditional Chinese has the system's.
        #expect(Language.french.name(in: "zh-Hans") == "法语" && Language.french.name(in: "zh-Hant") == "法文")
        #expect(OutputLanguage("ja").name(in: "zh-Hans") == "日语" && OutputLanguage("ja").name(in: "zh-Hant") == "日文")
        #expect(OutputLanguage("zh-Hant").name(in: "zh-Hant") == "繁體中文")
    }

    @Test func codeForTheSetting() {
        let shipped = ["en", "zh-Hans", "fr"]
        #expect(InterfaceLanguage.code(forSetting: "zh", shipped: shipped) == "zh-Hans")
        #expect(InterfaceLanguage.code(forSetting: "en", shipped: shipped) == "en")
        #expect(InterfaceLanguage.code(forSetting: "fr", shipped: shipped) == "fr")
        #expect(InterfaceLanguage.code(forSetting: "FR", shipped: shipped) == "fr")
        #expect(InterfaceLanguage.code(forSetting: "zh-Hans", shipped: shipped) == "zh-Hans")
        for value in [nil, "", "de", "zh-Hant", "Base"] {
            #expect(InterfaceLanguage.code(forSetting: value, shipped: shipped + ["Base"]) == nil, "\(value ?? "nil")")
        }
        // Saved as older versions read it.
        #expect(InterfaceLanguage.setting(for: "zh-Hans") == "zh" && InterfaceLanguage.setting(for: "en") == "en")
        #expect(InterfaceLanguage.setting(for: "fr") == "fr" && InterfaceLanguage.setting(for: "pt-BR") == "pt-BR")
        for code in shipped { #expect(InterfaceLanguage.code(forSetting: InterfaceLanguage.setting(for: code), shipped: shipped) == code) }
    }

    @Test func shippedAndNamed() throws {
        let app = try Self.app(["fr": [:], "en": [:], "pt-BR": [:]])
        #expect(InterfaceLanguage.shipped(in: app) == ["en", "zh-Hans", "fr", "pt-BR"])
        #expect(InterfaceLanguage.current(setting: "fr", preferred: ["en"], app: app) == "fr")
        #expect(InterfaceLanguage.current(setting: "de", preferred: ["pt-BR", "en"], app: app) == "pt-BR")
        #expect(InterfaceLanguage.current(setting: "zh", preferred: ["fr"], app: app) == "zh-Hans")
        #expect(InterfaceLanguage.current(setting: nil, preferred: ["ja", "zh-Hant-TW"], app: app) == "zh-Hans")
        #expect(InterfaceLanguage.name("en") == "English" && InterfaceLanguage.name("zh-Hans") == "简体中文")
        #expect(InterfaceLanguage.name("fr") == "Français")
        #expect(InterfaceLanguage.isChinese("zh-Hans") && InterfaceLanguage.isChinese("zh-Hant") && !InterfaceLanguage.isChinese("en"))
    }

    /// Language names follow the interface language; Chinese and English as before.
    @Test func languageNamesInTheInterfaceLanguage() {
        #expect(Language.french.name(in: "zh-Hans") == "法语" && Language.french.name(in: "en") == "French")
        #expect(Language.french.name(in: "fr").lowercased() == "français")
        let japanese = OutputLanguage("ja")
        #expect(japanese.name(in: "zh-Hans") == japanese.name(chinese: true) && japanese.name(in: "en") == "Japanese")
        #expect(OutputLanguage.chinese.name(in: "en") == "Chinese" && OutputLanguage.english.name(in: "zh-Hans") == "英文")
        #expect(OutputLanguage("ja").name(in: "fr").lowercased() == "japonais")
        #expect(OutputLanguage("hi").name(in: "en") == "Hindi" && OutputLanguage("hi").name(in: "zh-Hans") == "印地语")
    }

    // MARK: The config

    @Test func configKeepsTheCode() throws {
        func decode(_ json: String) throws -> Config { try JSONDecoder().decode(Config.self, from: Data(json.utf8)) }
        #expect(try decode(#"{"uiLanguage": "zh"}"#).uiLanguage == "zh")
        #expect(try decode(#"{"uiLanguage": "en"}"#).uiLanguage == "en")
        #expect(try decode(#"{"uiLanguage": "pt-BR"}"#).uiLanguage == "pt-BR")
        #expect(try decode(#"{"uiLanguage": ""}"#).uiLanguage == nil)
        #expect(try decode(#"{"uiLanguage": 3}"#).uiLanguage == nil)
        var config = Config.default
        config.uiLanguage = "zh"
        let text = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        #expect(text.contains(#""uiLanguage":"zh""#))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ui-language-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ConfigFile.uiLanguage(from: url) == nil)
        try Data(#"{"uiLanguage": "fr", "maxTokens": "not a number"}"#.utf8).write(to: url)
        #expect(ConfigFile.uiLanguage(from: url) == "fr")  // read even where the whole config can't be
        try Data(#"{"uiLanguage": null}"#.utf8).write(to: url)
        #expect(ConfigFile.uiLanguage(from: url) == nil)
    }

    // MARK: Without .lproj bundles (Windows, Android, Linux)

    /// Fixtures/interface-text.xcstrings: French and German entries, a key of its own, an entry not translated, an empty
    /// one, one with only plural variations and a stale one.
    static func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "interface-text", withExtension: "xcstrings", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func catalogTablesWithoutBundles() throws {
        let data = try Self.fixture()
        let fr = try StringCatalog.table("fr", from: data)
        #expect(fr["%@ items"] == "%@ éléments" && fr["Move %@ to %@"] == "Déplacer %1$@ vers %2$@" && fr["100%% done"] == "fini à 100 %%")
        #expect(fr["remove.delete"] == "Supprimer")  // a key of its own
        #expect(fr["Close"] == nil && fr["Open"] == nil)  // not translated; translated as nothing
        #expect(fr["%@ files"] == nil)  // only plural variations, which tr doesn't use: English
        #expect(fr.count == 5)
        #expect(try StringCatalog.table("en", from: data) == ["remove.delete": "Remove"])
        #expect(try StringCatalog.table("ja", from: data).isEmpty)  // a language the catalog doesn't have
        #expect(try StringCatalog.languages(in: data) == ["de", "en", "fr"])
        #expect(throws: (any Error).self) { try StringCatalog.table("fr", from: Data("not a catalog".utf8)) }
    }

    @Test func translateFromATable() throws {
        let fr = try StringCatalog.table("fr", from: Self.fixture())
        let n = 4, file = "a.txt", folder = "Docs"
        #expect(InterfaceText.translate("\(n) items", in: fr) == "4 éléments")
        #expect(InterfaceText.translate("Move \(file) to \(folder)", in: fr) == "Déplacer a.txt vers Docs")
        #expect(InterfaceText.translate("100% done", in: fr) == "fini à 100 %")
        #expect(InterfaceText.translate("Remove", key: "remove.delete", in: fr) == "Supprimer")
        #expect(InterfaceText.translate("Close", in: fr) == nil)
        // The bundle path's placeholder checks: never a crash, nor garbage.
        #expect(InterfaceText.translate("\(n) left", in: ["%@ left": "il reste %3$@"]) == nil)
        #expect(InterfaceText.translate("Saved", in: ["Saved": "%d enregistrés"]) == nil)
        #expect(InterfaceText.translate("\(n) new", in: ["%@ new": "%1$@ nouveaux, %@"]) == "4 nouveaux, 4")

        // Every language through one lookup, as a shell without bundles sets `InterfaceText.lookup`.
        let lookup = InterfaceText.tableLookup(try StringCatalog.tables(from: Self.fixture()))
        #expect(InterfaceText.text("共 \(n) 个", "\(n) items", language: "fr", lookup: lookup) == "4 éléments")
        #expect(InterfaceText.text("共 \(n) 个", "\(n) items", language: "de", lookup: lookup) == "4 Einträge")
        #expect(InterfaceText.text("共 \(n) 个", "\(n) items", language: "ja", lookup: lookup) == "4 items")  // no such language
        #expect(InterfaceText.text("关闭", "Close", language: "fr", lookup: lookup) == "Close")  // not translated yet
        #expect(InterfaceText.text("删除", "Remove", key: "remove.delete", language: "fr", lookup: lookup) == "Supprimer")
        #expect(InterfaceText.text("共 \(n) 个", "\(n) items", language: "zh-Hans", lookup: lookup) == "共 4 个")
        #expect(InterfaceText.text("共 \(n) 个", "\(n) items", language: "en", lookup: lookup) == "4 items")
    }

    /// %@, %n$@ and %% filled in by hand, the same on every Foundation.
    @Test func fillByHand() {
        #expect(InterfaceText.fill("%2$@ sur %1$@, %%, %@", ["a", "b"]) == "b sur a, %, a")
        #expect(InterfaceText.fill("plain", []) == "plain" && InterfaceText.fill("%%", []) == "%")
        #expect(InterfaceText.fill("%@ and %@", ["only"]) == nil)
        #expect(InterfaceText.fill("%0$@", ["x"]) == nil && InterfaceText.fill("%1$", ["x"]) == nil)
        #expect(InterfaceText.fill("100 %", []) == nil && InterfaceText.fill("% f", []) == nil)
        #expect(InterfaceText.fill("%1$d", ["1"]) == nil && InterfaceText.fill("%s", ["1"]) == nil)
        #expect(InterfaceText.fill("“%@”", ["%@ %d %%"]) == "“%@ %d %%”")  // an argument is never read as a format
        #expect(InterfaceText.fill("%@ – %@", ["é🙂", "中文"]) == "é🙂 – 中文")
        #expect(InterfaceText.fill("%99999999999999999999$@", ["x"]) == nil)
    }

    // MARK: The catalog

    /// The core's package root (this file is Tests/AllInOneIMECoreTests/InterfaceTextTests.swift).
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Resources/Localizable.xcstrings, the core's text: a String Catalog in English, whose translations fit their keys'
    /// arguments (else the app shows English for them).
    @Test func catalogTranslationsFit() throws {
        try StringCatalogCheck.translationsFit(Self.root.appendingPathComponent("Resources/Localizable.xcstrings"))
    }

    /// Every interface language has every key in use, and its placeholders are the English's.
    @Test func everyLanguageHasEveryKey() throws {
        let catalog = Self.root.appendingPathComponent("Resources/Localizable.xcstrings")
        try StringCatalogCheck.everyKeyTranslated(catalog)
        try StringCatalogCheck.placeholdersMatch(catalog)
    }

    @Test func placeholdersReadAsArguments() {
        #expect(StringCatalogCheck.arguments("%@ of %@, 100%%") == [0: 1, 1: 1])
        #expect(StringCatalogCheck.arguments("%2$@ sur %1$@") == [0: 1, 1: 1])
        #expect(StringCatalogCheck.arguments("plain") == [:])
        #expect(StringCatalogCheck.arguments("%@ %@") != StringCatalogCheck.arguments("%@"))
        #expect(StringCatalogCheck.arguments("50% off") == nil && StringCatalogCheck.arguments("%d") == nil)
    }

    /// The core's catalog read without Apple's tools, as the Windows shell reads it (`StringCatalog`): every language
    /// has a table with every key in use, Traditional Chinese's filled in and looked up as the shell's `tr` does.
    @Test func everyLanguageLoadsFromTheCatalog() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("Resources/Localizable.xcstrings"))
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(catalog["strings"] as? [String: [String: Any]])
        let inUse = Set(entries.filter { $0.value["extractionState"] as? String != "stale" }.keys)
        let tables = try StringCatalog.tables(from: data)
        #expect(Set(try StringCatalog.languages(in: data)).isSuperset(of: StringCatalogCheck.languages))
        for language in StringCatalogCheck.languages {
            let table = try StringCatalog.table(language, from: data)
            #expect(inUse.isSubset(of: Set(table.keys)), "\(language): \(inUse.subtracting(table.keys).sorted().prefix(5))")
            #expect(tables[language] == table)
        }
        let hant = try StringCatalog.table("zh-Hant", from: data)
        let lookup = InterfaceText.tableLookup(tables)
        let n = 12
        let vertical = InterfaceText.text("竖排", "Vertical", language: "zh-Hant", lookup: lookup)
        #expect(vertical == hant["Vertical"] && vertical != "竖排" && vertical != "Vertical")
        let english: UIString = " (\(n))"
        #expect(InterfaceText.translate(english, in: hant) == hant[" (%@)"].flatMap { InterfaceText.fill($0, ["12"]) })
    }
}

/// The interface language as the process keeps it (`UIText`): a change is told on the main thread, whatever thread made
/// it, so a panel on screen all along redraws where it draws.
struct InterfaceLanguageStateTests {
    @Test func aChangeMadeOffTheMainThreadIsToldOnIt() throws {
        // This test waits for the main thread: it can't be on it.
        guard !Thread.isMainThread else { return }
        try withInterfaceLanguage("en") {
            // Each notice: on the main thread or not, and the language then.
            let notices = Locked(initialState: [(main: Bool, language: String)]())
            let told = DispatchSemaphore(value: 0)
            let observer = NotificationCenter.default.addObserver(forName: .allInOneIMEInterfaceLanguageChanged, object: nil,
                                                                  queue: nil) { _ in
                notices.withLock { $0.append((Thread.isMainThread, UIText.language)) }
                told.signal()
            }
            defer { NotificationCenter.default.removeObserver(observer) }
            // A session on a thread of its own (a queue) picks another language.
            DispatchQueue.global().async { UIText.choice = "zh" }
            while !notices.withLock({ $0.contains { $0.language == "zh-Hans" } }) {
                try #require(told.wait(timeout: .now() + 10) == .success, "no notice in Chinese")
            }
            #expect(notices.withLock { $0.allSatisfy(\.main) })
        }
    }
}

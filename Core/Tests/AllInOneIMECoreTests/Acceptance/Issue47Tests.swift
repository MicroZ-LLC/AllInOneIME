import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// #47: a user typing Traditional Chinese (`chineseCharacters` "taiwan" or "hongkong", or unset on a Traditional-Chinese
/// Mac) sees Chinese named with its characters where the input is named: the menu's "Chinese (pinyin, Traditional)",
/// 「中文（拼音·繁體）」. What an app learned and its own settings named it plain "Chinese (pinyin)": the notice "Slack
/// starts in Chinese (pinyin) from now on" after two fields in a row switched to Chinese with Shift before typing, the
/// Apps settings' summary and "Starts in" choices, and "Previous per-app settings". Through fields' sessions as the
/// Settings v2 learning tests drive them (`SettingsV2World`), the settings document (`SettingsService`) and `Config`.
@Suite(.serialized, MemorySecrets(), SuggestionsOneAtATime())
struct Issue47Tests {
    typealias Apps = SettingsV2Apps

    /// Chinese's name with Traditional characters in the interface language `language`, the part of it the tests look for.
    static func traditional(_ language: String) -> String { language == "zh" ? "繁體" : "Traditional" }

    /// Two fields of Slack in a row switched from English to Chinese with Shift before typing, then the next one taking
    /// the focus: what the fields said of Slack by then.
    func learnChinese(_ world: SettingsV2World) -> [String] {
        world.corrected(Apps.slack)
        world.corrected(Apps.slack)
        world.field(Apps.slack)
        return world.said.filter { $0.contains("Slack") }
    }

    // MARK: - The notice

    /// The issue's: Characters set to Traditional (Taiwan), an app that starts in English learns to start in Chinese, and
    /// the notice names the Chinese the user types: "Slack starts in Chinese (pinyin, Traditional) from now on".
    @Test(arguments: ["en", "zh"])
    func theNoticeOfALearnedChineseSaysTraditional(_ language: String) async throws {
        await withInterfaceLanguage(language) {
            let world = SettingsV2World([.english, .chinese])
            world.config.uiLanguage = language
            world.config.chineseCharacters = .taiwan
            let said = learnChinese(world)
            #expect(world.learnedInput(Apps.slack) == .language(.chinese), "\(world.items())")
            #expect(said.count == 1, "\(world.said)")
            #expect(said.first?.contains(Self.traditional(language)) == true, "\(said)")
            if language == "en" {
                #expect(said.first == "Slack starts in Chinese (pinyin, Traditional) from now on", "\(said)")
            } else {
                #expect(said.first?.contains("中文（拼音·繁體）") == true, "\(said)")
            }
        }
    }

    /// Hong Kong's characters are Traditional too.
    @Test func hongKongsNoticeSaysTraditional() async throws {
        await withInterfaceLanguage("en") {
            let world = SettingsV2World([.english, .chinese])
            world.config.chineseCharacters = .hongkong
            let said = learnChinese(world)
            #expect(said.count == 1 && said.first?.contains("Traditional") == true, "\(world.said)")
        }
    }

    /// Characters left unset on a Mac whose first language is Traditional Chinese: Chinese is typed in Traditional
    /// characters (`Config.typedChinese`), and the notice says so.
    @Test func unsetOnATraditionalChineseMacTheNoticeSaysTraditional() async throws {
        await withInterfaceLanguage("en") {
            TCA.onMac(preferring: ["zh-Hant-TW", "en-US"]) {
                let world = SettingsV2World([.english, .chinese])
                world.config.chineseCharacters = nil
                #expect(world.config.typedChinese.isTraditional)
                let said = learnChinese(world)
                #expect(said.count == 1 && said.first?.contains("Traditional") == true, "\(world.said)")
            }
        }
    }

    /// Simplified as before: "Chinese (pinyin)", no "Traditional".
    @Test func simplifiedsNoticeIsAsBefore() async throws {
        await withInterfaceLanguage("en") {
            let world = SettingsV2World([.english, .chinese])
            world.config.chineseCharacters = .simplified
            let said = learnChinese(world)
            #expect(said == ["Slack starts in Chinese (pinyin) from now on"], "\(world.said)")
        }
    }

    // MARK: - The Apps settings

    /// A config file of its own with `text`, and a settings service on it (its plugins in the test's own folder).
    func service(_ text: String) throws -> (service: SettingsService, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("issue47-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(text.utf8).write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
        return (SettingsService(store: SettingsStore(configURL: url), platform: .mac, library: library), folder)
    }

    /// Per-App Settings: Slack's row, set to start in Chinese, says "Starts in Chinese (pinyin, Traditional)", and its
    /// "Starts in" names Chinese so among its choices.
    @Test(arguments: ["en", "zh"])
    func theAppsSettingsNameChineseTraditional(_ language: String) throws {
        let (service, folder) = try service("""
            {"provider": "anthropic", "uiLanguage": "\(language)", "inputLanguages": ["en", "zh"], "chineseCharacters": "taiwan",
             "appProfiles": {"\(Apps.slack)": {"inputLanguage": "zh"}}}
            """)
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = service.document()
        let slack = try #require(document.field("apps.profiles")?.items?.first { $0.id == Apps.slack })
        let detail = slack.detail ?? ""
        #expect(detail.contains(Self.traditional(language)), "the summary: \(detail)")
        if language == "en" { #expect(detail.contains("Starts in Chinese (pinyin, Traditional)"), "\(detail)") }
        let starts = try #require(document.field("apps.\(Apps.slack).inputLanguage"))
        let zh = starts.choices?.first { $0.value == .string("zh") }
        #expect(zh?.label.contains(Self.traditional(language)) == true, "Starts in: \(starts.choices ?? [])")
    }

    /// "Same as everywhere (…)" names the default input, Chinese, with its characters too.
    @Test func sameAsEverywhereNamesChineseTraditional() throws {
        let (service, folder) = try service("""
            {"provider": "anthropic", "uiLanguage": "en", "inputLanguages": ["zh", "en"], "chineseCharacters": "taiwan",
             "appProfiles": {"\(Apps.slack)": {"noAI": true}}}
            """)
        defer { try? FileManager.default.removeItem(at: folder) }
        let starts = try #require(service.document().field("apps.\(Apps.slack).inputLanguage"))
        let same = starts.choices?.first { $0.value == .null }
        #expect(same?.label == "Same as everywhere (Chinese (pinyin, Traditional))", "\(starts.choices ?? [])")
    }

    /// Simplified as before: "Starts in Chinese (pinyin)".
    @Test func simplifiedsAppsSettingsAreAsBefore() throws {
        let (service, folder) = try service("""
            {"provider": "anthropic", "uiLanguage": "en", "inputLanguages": ["en", "zh"], "chineseCharacters": "simplified",
             "appProfiles": {"\(Apps.slack)": {"inputLanguage": "zh"}}}
            """)
        defer { try? FileManager.default.removeItem(at: folder) }
        let slack = service.document().field("apps.profiles")?.items?.first { $0.id == Apps.slack }
        #expect(slack?.detail?.contains("Starts in Chinese (pinyin)") == true, "\(slack?.detail ?? "-")")
        #expect(slack?.detail?.contains("Traditional") == false, "\(slack?.detail ?? "-")")
    }

    // MARK: - Previous per-app settings

    /// "Previous per-app settings": an app's own starting input in Chinese reads "Slack: starts in Chinese (pinyin,
    /// Traditional)".
    @Test func previousPerAppSettingsNameChineseTraditional() async throws {
        await withInterfaceLanguage("en") {
            var config = Config.default
            config.uiLanguage = "en"
            config.chineseCharacters = .taiwan
            config.changeProfile(for: Apps.slack) { $0.inputLanguage = .chinese }
            let rows = config.previousAppSettings(appName: Apps.name)
            let slack = rows.first { $0.app == Apps.slack }
            #expect(slack?.text == "Slack: starts in Chinese (pinyin, Traditional)", "\(rows)")
        }
    }
}

import Foundation
import Testing

@Suite("Zhuyin repository coverage")
struct ZhuyinRepositoryTests {
    @Test func settingsSearchFindsAllFourNames() throws {
        // SettingsSpot is in the macOS executable. Check its search-row
        // keywords, which are exactly the words the window's SettingsSpot.search() queries.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/AllInOneIME/SettingsSearch.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "case .pinyinScheme:\n"))
        let end = try #require(source.range(of: "case .chineseCharacters:", range: start.upperBound..<source.endIndex))
        let keywords = source[start.upperBound..<end.lowerBound].lowercased()
        for word in ["zhuyin", "注音", "bopomofo", "大千"] {
            #expect(keywords.contains(word), "Settings search must find \(word)")
        }
    }

    @Test func userDocumentationAndBundledDataNoticesNameZhuyin() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
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

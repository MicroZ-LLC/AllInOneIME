import Foundation
import Testing
@testable import AllInOneIMECore

/// The small stand-ins for Apple-only API that keep the core portable.
struct PortableTests {
    @Test func lockedSharesItsValueAcrossTasks() async {
        let counter = Locked(initialState: 0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 { group.addTask { counter.withLock { $0 += 1 } } }
        }
        #expect(counter.withLock { $0 } == 100)
    }

    @Test func jsonBooleansAreNotNumbers() throws {
        let values = try #require(try JSONSerialization.jsonObject(with: Data("[true, false, 1, 0, 1.0]".utf8)) as? [NSNumber])
        #expect(values.map(\.isBoolean) == [true, true, false, false, false])
    }

    @Test func chineseEncodingsAreFoundations() {
        let hello = "你好"
        #expect(String(data: Data([0xC4, 0xE3, 0xBA, 0xC3]), encoding: WebReader.gb18030) == hello)
        #expect(String(data: Data([0xA7, 0x41, 0xA6, 0x6E]), encoding: WebReader.big5) == hello)
        #if canImport(Darwin)
        #expect(WebReader.gb18030.rawValue
            == CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        #expect(WebReader.big5.rawValue == CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        #endif
    }

    #if os(macOS)
    @Test func theMacsFoldersAreTheSameAsEver() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(CorePaths.home.path == home)
        #expect(Config.userURL.path == home + "/.config/allinoneime/config.json")
        #expect(JargonLibrary.defaultURL.path == home + "/.config/allinoneime/jargon.txt")
        #expect(PluginStore.directory.path == home + "/.config/allinoneime/plugins")
        #expect(LanguagePackStore.defaultDirectory.path == home + "/Library/Application Support/AllInOneIME/LanguagePacks")
        #expect(ExtensionSources.directory.path == home + "/Library/Application Support/AllInOneIME/Sources")
        #expect(QuestionHistory.defaultURL.path == home + "/Library/Application Support/AllInOneIME/recent-questions.json")
        #expect(ClaudeAgents.projectsRoot.path == home + "/.claude/projects")
        #expect(CorePaths.logsDir.path == home + "/Library/Logs/AllInOneIME")
        #expect(CorePaths.cacheDir.path == home + "/Library/Caches/AllInOneIME")
    }
    #endif
}

import Foundation
import Testing
@testable import AllInOneIMECore

/// Windows' settings document says what Windows has (Enter, a terminal window, this PC, cmd, the Credential Manager,
/// `%USERPROFILE%`), in every language; the Mac's says what it said. In `SettingsServiceTests`: one at a time, keys in
/// memory only.
extension SettingsServiceTests {
    /// A config with the fields these texts are in: Chinese (the English words), the action key, a custom command (the
    /// editor's schema), the agent, the extension folders.
    static func wordingConfig(_ language: String, actionKey: String = "enter") -> String {
        #"{"uiLanguage": "\#(language)", "inputLanguages": ["en", "zh"], "actionKey": "\#(actionKey)", "#
            + #""customCommands": [{"name": "py", "type": "run", "argv": ["python3", "-c", "{input}"]}]}"#
    }

    /// The document `platform`'s settings window gets, as JSON.
    func wordingDocument(_ platform: SettingsPlatform, _ text: String) throws -> String {
        let (service, url) = try service(text, platform: platform)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(service.document()), as: UTF8.self)
    }

    /// What only the Mac has, in a document's text.
    static let macOnlyWords = ["⏎", "⌥", "⌘", "⌃", "your Mac", "this Mac", "zsh", "~/", "keychain", "in Terminal", "Return",
                          "Mac 上", "钥匙串", "⏎ 回车"]

    @Test func windowsDocumentNamesWindowsKeysAndPlaces() throws {
        for language in ["en", "zh-Hans", "fr", "ja", "de", "es", "ko", "pt-BR", "zh-Hant"] {
            for key in ["enter", "space", "optionTap"] {
                // What the window shows: not the ids (an extension folder's is its path as the config keeps it).
                let windows = try withInterfaceLanguage(language) { try wordingDocument(.windows, Self.wordingConfig(language, actionKey: key)) }
                    .replacingOccurrences(of: #""id":"[^"]*""#, with: "", options: .regularExpression)
                for mac in Self.macOnlyWords where language == "en" || mac.unicodeScalars.contains(where: { !$0.isASCII }) || mac == "zsh"
                    || mac == "~/" {
                    #expect(!windows.contains(mac), "\(language), \(key): \(Self.found(mac, in: windows))")
                }
                #expect(windows.contains("cmd /c {input}") && windows.contains(#"%USERPROFILE%\\.config\\allinoneime\\extensions"#),
                        "\(language), \(key)")
                #expect(windows.contains("Enter"), "\(language), \(key)")
            }
        }
        let english = try withInterfaceLanguage("en") { try wordingDocument(.windows, Self.wordingConfig("en")) }
        for text in ["\"Enter\"", "Enter runs an @ command", "this PC", "Run in a terminal", "in a terminal window",
                     "write cmd /c {input}", "and Enter, then again", "Enter inserts it"] {
            #expect(english.contains(text), "\(text)")
        }
    }

    /// `text` where `found` first is in it, with what is around it.
    static func found(_ found: String, in text: String) -> String {
        guard let range = text.range(of: found) else { return found }
        let start = text.index(range.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 40, limitedBy: text.endIndex) ?? text.endIndex
        return "…" + text[start..<end] + "…"
    }

    @Test func theMacsDocumentIsAsItWas() throws {
        let mac = try withInterfaceLanguage("en") { try wordingDocument(.mac, Self.wordingConfig("en")) }
        for text in ["⏎ Return", "Return runs an @ command", "Programs run on your Mac", "Run in Terminal", "It opens in Terminal",
                     "write zsh -c {input}", "(bedrock and ⏎, then again)", "⏎ inserts it", "~/.config/allinoneime/extensions",
                     "@improve, @translate, @question … and ⏎"] {
            #expect(mac.contains(text), "\(text)")
        }
        #expect(!mac.contains("%USERPROFILE%") && !mac.contains("cmd /c"))
    }

    @Test func aFolderAsWindowsWritesIt() {
        #expect(ExtensionStore.windowsShown("~/.config/allinoneime/extensions") == #"%USERPROFILE%\.config\allinoneime\extensions"#)
        #expect(ExtensionStore.windowsShown("~") == "%USERPROFILE%")
        #expect(ExtensionStore.windowsShown(#"D:\Scripts"#) == #"D:\Scripts"#)
        let home = #"C:\Users\Li Ming"#
        let environment = ["USERPROFILE": home, "AppData": #"C:\Users\Li Ming\AppData\Roaming"#]
        func typed(_ path: String) -> String { ExtensionStore.typedOnWindows(path, home: home, environment: environment) }
        // The placeholder typed as it is: the default folder, as the config keeps it (no second one).
        #expect(typed(#"%USERPROFILE%\.config\allinoneime\extensions"#) == ExtensionStore.defaultFolder)
        #expect(typed(#"%appdata%\AllInOneIME\scripts"#) == "~/AppData/Roaming/AllInOneIME/scripts", "a name in any case")
        #expect(typed(#"c:\users\li ming\Scripts"#) == "~/Scripts", "the home in any case")
        #expect(typed("C:/Users/Li Ming") == "~")
        #expect(typed(#"D:\Scripts"#) == #"D:\Scripts"#)
        #expect(typed(#"%NOSUCH%\x"#) == #"%NOSUCH%\x"#, "a name it lacks stays")
        #expect(typed(#"C:\Users\Li Mingo\x"#) == #"C:\Users\Li Mingo\x"#, "another folder that begins the same")
    }

    @Test func aFolderInTheHomeFolderIsKeptFromItAndRemovedHoweverItIsWritten() throws {
        let (service, url) = try service(#"{"extensionFolders": []}"#, platform: .windows)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let name = "aio-wording-\(UUID().uuidString)"
        let folder = (NSHomeDirectory() as NSString).appendingPathComponent(name)
        guard case .success = service.performNow(SettingsAction(field: "extensions.folders", name: "add", value: .string(folder))) else {
            Issue.record("not added")
            return
        }
        #expect(try Config.load(from: url).extensionFolders == ["~/" + name])
        let item = try #require(service.document().field("extensions.folders")?.items?.first)
        #expect(item.id == "~/" + name && item.title == #"%USERPROFILE%\"# + name)
        // Removed by the path it was added with, as by its id.
        guard case .success = service.performNow(SettingsAction(field: "extensions.folders", name: "remove", item: folder)) else {
            Issue.record("not removed")
            return
        }
        #expect(try Config.load(from: url).extensionFolders.isEmpty)
    }

    @Test func theKeyStoreIsNamedForThePlatform() {
        let windows = Platform(terms: .windows)
        let saved = withInterfaceLanguage("en") { Platform.$override.withValue(windows) { SettingsStore.couldntSaveKey } }
        #expect(saved == "Couldn't save to the Credential Manager: ")
        let mac = withInterfaceLanguage("en") { Platform.$override.withValue(Platform(terms: .mac)) { SettingsStore.couldntSaveKey } }
        #expect(mac == "Couldn't save to the keychain: ")
    }
}

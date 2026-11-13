import Foundation
import Testing

/// Acceptance (0.7.4, written from the spec): AllInOneIME registers as a Chinese, Simplified input source again so that
/// macOS's "Use the Caps Lock key to switch to and from ABC" switches to it. Resources/Info.plist says so
/// (`TISIntendedLanguage` zh-Hans, the script repertoire Hans only, `TICapsLockLanguageSwitchCapable`), while the input
/// source ID and the bundle ID stay 0.7.3's (an update keeps it in the user's input sources); every text that tells the
/// user where to add it says "Chinese, Simplified", not "English".
struct CapsLockInputSourceAcceptanceTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// 0.7.3's (origin/release-0.7.3, Resources/Info.plist).
    static let sourceID073 = "com.allinoneime.inputmethod.AllInOneIME"
    static let bundleID073 = "com.allinoneime.inputmethod.AllInOneIME"
    static let connection073 = "com.allinoneime.inputmethod.AllInOneIME_Connection"

    func plist() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("Resources/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func theInfoPlistRegistersAChineseSimplifiedSourceThatCapsLockSwitchesTo() throws {
        let info = try plist()
        #expect(info["TISIntendedLanguage"] as? String == "zh-Hans")
        #expect(info["tsInputMethodCharacterRepertoireKey"] as? [String] == ["Hans"])
        #expect(info["TICapsLockLanguageSwitchCapable"] as? Bool == true)
    }

    @Test func theInputSourceAndBundleIDsAre073s() throws {
        let info = try plist()
        #expect(info["TISInputSourceID"] as? String == Self.sourceID073)
        #expect(info["CFBundleIdentifier"] as? String == Self.bundleID073)
        #expect(info["InputMethodConnectionName"] as? String == Self.connection073)
        // No input modes: the one source keeps its one ID.
        #expect(info["ComponentInputModeDict"] == nil && info["tsInputModeListKey"] == nil)
    }

    /// When the repository has 0.7.3's release branch, the IDs are compared with its Info.plist itself.
    @Test func theIDsMatchTheReleaseBranchWhenItIsThere() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", Self.root.path, "show", "origin/release-0.7.3:Resources/Info.plist"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let old = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        let info = try plist()
        for key in ["TISInputSourceID", "CFBundleIdentifier", "InputMethodConnectionName"] {
            #expect(info[key] as? String == old[key] as? String, "\(key)")
        }
    }

    // MARK: - The texts

    /// The language names "English" in the languages the docs and the strings are in, as the step before "→ AllInOneIME".
    static let englishStep = try! NSRegularExpression(pattern:
        #"(English|英语|英語|Englisch|Inglés|Ingles|Anglais|영어|Inglês|Inglese|İngilizce|Английский|الإنجليزية|अंग्रेज़ी|Tiếng Anh|ภาษาอังกฤษ|Bahasa Inggris)[」”"）)]*\s*→\s*AllInOneIME"#)

    static func englishSteps(_ text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return englishStep.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    static func files(under folder: String, extensions: Set<String>) -> [URL] {
        let base = root.appendingPathComponent(folder)
        guard let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        return walk.compactMap { $0 as? URL }.filter { extensions.contains($0.pathExtension) }
    }

    @Test func theSourcesSayChineseSimplifiedNotEnglish() throws {
        let sources = Self.files(under: "Sources", extensions: ["swift"]) + Self.files(under: "Core/Sources", extensions: ["swift"])
        #expect(!sources.isEmpty)
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(Self.englishSteps(text).isEmpty, "\(file.lastPathComponent): \(Self.englishSteps(text))")
            #expect(!text.contains("listed under English") && !text.contains("「英语」下") && !text.contains("英语下面"),
                    "\(file.lastPathComponent)")
        }
        // The install and register texts: `--register`, the installer, the input source step, the identity hand-over.
        for path in ["Sources/AllInOneIME/main.swift", "Sources/AllInOneIMEInstaller/main.swift",
                     "Sources/AllInOneIME/InputSourceStep.swift"] {
            let text = try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
            #expect(text.contains("Chinese, Simplified → AllInOneIME") && text.contains("简体中文 → AllInOneIME"), "\(path)")
        }
    }

    @Test func theDocsSayChineseSimplifiedNotEnglish() throws {
        let docs = ["README.md", "README.zh-CN.md", "Resources/user-guide.md"].map { Self.root.appendingPathComponent($0) }
            + Self.files(under: "docs/readme", extensions: ["md"])
        for file in docs {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(Self.englishSteps(text).isEmpty, "\(file.lastPathComponent): \(Self.englishSteps(text))")
        }
        let readme = try String(contentsOf: Self.root.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(readme.contains("Chinese, Simplified → AllInOneIME") && readme.contains("Caps Lock"))
        let chinese = try String(contentsOf: Self.root.appendingPathComponent("README.zh-CN.md"), encoding: .utf8)
        #expect(chinese.contains("简体中文 → AllInOneIME") && chinese.contains("大写锁定"))
    }

    /// The translations of the texts that name the step say the Chinese one too, in every language.
    @Test func theTranslationsSayChineseSimplifiedNotEnglish() throws {
        let catalog = Self.root.appendingPathComponent("Resources/Localizable.xcstrings")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: Any])
        // The English texts the sources use now.
        let sources = Self.files(under: "Sources", extensions: ["swift"]).compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        var checked = 0
        for (key, value) in strings where key.contains("Chinese, Simplified") && key.contains("AllInOneIME") {
            let localizations = (value as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for (language, entry) in localizations {
                let text = ((entry as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                #expect(Self.englishSteps(text).isEmpty, "\(language): \(text.prefix(120))")
                checked += 1
            }
        }
        #expect(checked > 0)
        // A key that still says English isn't one the sources use.
        for key in strings.keys where !Self.englishSteps(key).isEmpty {
            let firstLine = key.split(separator: "\n").first { $0.contains("AllInOneIME") }.map(String.init) ?? key
            #expect(!sources.contains(firstLine.trimmingCharacters(in: .whitespaces)), "in use: \(key.prefix(120))")
        }
    }
}

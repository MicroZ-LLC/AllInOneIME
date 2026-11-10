import Foundation
import Testing
@testable import AllInOneIMECore

// Assumed minimal Core API for this acceptance contract:
//   UserGuide(text: String) has `sections` and `excerpts(for question: String) -> String?`.
//   Converter.init(..., loadUserGuide: @escaping @Sendable () -> String?) accepts the text read by
//   the shell from its bundled Resources/user-guide.md. Only @question may use that loader.
//   The selected excerpts are sent under "AllInOneIME user guide, excerpts"; a file-capable agent
//   receives the bundled guide's path instead of the excerpts.
// The fixture below isolates selection and request composition from the shipped guide's wording.

@Suite("User guide for @question", .serialized, MemorySecrets())
struct UserGuideTests {
    private let fixture = """
    ## Setup / 安装
    Add AllInOneIME in System Settings → Keyboard → Input Sources → English.
    ## Shuangpin / 双拼
    Open Settings → Input → Chinese (pinyin) → Typing and choose a Shuangpin scheme.
    ## Magic key / 魔法键
    Open Settings → General → Magic key to change the command prefix.
    ## Autocomplete / 自动补全
    Open Settings → General → Autocomplete to choose when suggestions appear.
    ## Clipboard history / 剪贴板历史
    Press ⌃V to show recent copies. Change it in Settings → General → Clipboard history.
    ## Commands and keys / 命令和按键
    Type @translate and press Return to translate using the languages in Settings → General.
    ## Privacy / 隐私
    Guide excerpts are app documentation, never the current configuration or API keys.
    """

    private func sent(_ question: String, guideText: String?) async throws -> QCSent {
        let endpoint = "user-guide-\(UUID().uuidString.lowercased()).test"
        var config = Config.default
        config.provider = .anthropic
        config.anthropic = ProviderSettings(baseURL: "https://\(endpoint)")
        config.rememberQuestions = false
        config.englishWords = ["private-config-word-78542"]
        let fixed = config
        let converter = Converter(client: BedrockClient(session: QCStubProtocol.session()),
                                  loadConfig: { fixed }, loadKey: { _, _ in "private-api-key-78542" },
                                  loadJargon: { _ in [] }, loadUserGuide: { guideText })
        for try await _ in converter.generate(.question, input: question) {}
        let body = try #require(QCStubProtocol.bodies(endpoint).first)
        return try QCSent(body)
    }

    private func requestText(_ sent: QCSent) -> String {
        ([sent.system] + sent.messages.map(\.text)).joined(separator: "\n")
    }

    @Test(arguments: [
        ("怎么打开双拼", "## Shuangpin / 双拼"),
        ("how do I change the magic key", "## Magic key / 魔法键"),
        ("AllInOneIME 怎么设置自动补全", "## Autocomplete / 自动补全"),
        ("⌃V 怎么用", "## Clipboard history / 剪贴板历史"),
        ("how do I use @translate", "## Commands and keys / 命令和按键"),
    ])
    func relevantQuestionsSelectTheRightSections(question: String, heading: String) throws {
        let guide = UserGuide(text: fixture)
        #expect(guide.sections.count == 7)
        let excerpts = try #require(guide.excerpts(for: question))
        let headings = excerpts.split(separator: "\n").filter { $0.hasPrefix("## ") }
        #expect((2...3).contains(headings.count), "selected headings: \(headings)")
        #expect(excerpts.contains(heading), "\(question): \(headings)")
        #expect(excerpts.count <= 3_100, "the excerpt budget is about 3,000 characters")
    }

    @Test(arguments: ["what is the capital of France", "帮我解释这句话"])
    func ordinaryQuestionsHaveNoExcerptsOrRequestChange(question: String) async throws {
        #expect(UserGuide(text: fixture).excerpts(for: question) == nil)
        let withoutGuide = try await sent(question, guideText: nil)
        let withGuide = try await sent(question, guideText: fixture)
        #expect(withGuide.raw == withoutGuide.raw, "an ordinary @question request changed")
    }

    @Test(arguments: [
        ("怎么打开双拼", "## Shuangpin / 双拼"),
        ("how do I change the magic key", "## Magic key / 魔法键"),
        ("AllInOneIME 怎么设置自动补全", "## Autocomplete / 自动补全"),
        ("⌃V 怎么用", "## Clipboard history / 剪贴板历史"),
        ("how do I use @translate", "## Commands and keys / 命令和按键"),
    ])
    func imeQuestionsSendOnlyRelevantGuideText(question: String, heading: String) async throws {
        let excerpts = try #require(UserGuide(text: fixture).excerpts(for: question))
        let request = try await sent(question, guideText: fixture)
        let text = requestText(request)
        #expect(text.contains("AllInOneIME user guide, excerpts"))
        #expect(text.contains(excerpts))
        #expect(text.contains(heading))
        #expect(text.split(separator: "\n").filter { $0.hasPrefix("## ") }.count <= 3,
                "the request includes more than three guide sections")
        #expect(!excerpts.contains("private-config-word-78542"))
        #expect(!excerpts.contains("private-api-key-78542"))
        #expect(!text.contains("private-config-word-78542"))
        #expect(!text.contains("private-api-key-78542"))
    }

    @Test func selectionNeverExceedsTheExcerptBudget() throws {
        let longGuide = """
        ## Shuangpin / 双拼
        \(String(repeating: "双拼 setup and scheme. ", count: 100))
        ## Chinese typing / 中文输入
        \(String(repeating: "双拼 typing and keys. ", count: 100))
        ## Input settings / 输入设置
        \(String(repeating: "双拼 input settings. ", count: 100))
        ## Unrelated
        \(String(repeating: "unrelated material. ", count: 100))
        """
        let excerpts = try #require(UserGuide(text: longGuide).excerpts(for: "怎么打开双拼"))
        #expect(excerpts.contains("## Shuangpin / 双拼"))
        #expect(excerpts.count <= 3_100, "the selected text exceeds about 3,000 characters")
        #expect(excerpts.split(separator: "\n").filter { $0.hasPrefix("## ") }.count <= 3)
        #expect(!excerpts.contains("## Unrelated"))
    }

    private var guideURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../Resources/user-guide.md").standardizedFileURL
    }

    @Test func shippedGuideCoversSettingsFieldsAndBuiltInCommands() throws {
        let url = guideURL
        #expect(FileManager.default.fileExists(atPath: url.path), "the app must ship Resources/user-guide.md")
        let guide = try String(contentsOf: url, encoding: .utf8)
        #expect(guide.contains("## ") && guide.contains("设置"), "the guide needs short English and Chinese sections")
        let searchable = guide.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        for topic in ["Input Sources", "English", "Accessibility", "Shuangpin", "magic key", "English words",
                      "clipboard history", "autocomplete", "Translate as You Type", "privacy", "updates"] {
            #expect(searchable.contains(topic.lowercased()), "guide omits \(topic)")
        }
        #expect(guide.contains("Settings → Input → Chinese (pinyin) → Typing"))

        // Read the same SettingsDocument fields the SettingsService tests do, from isolated config files.
        // Different providers and input modes expose conditional fields that the default document misses.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("guide-fields-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var fields: [String: SettingsDocument.Field] = [:]
        let samples = Provider.allCases.map { provider in
            "{\"provider\":\"\(provider.rawValue)\",\"inputLanguages\":[\"en\",\"zh\"]}"
        } + ["{\"inputLanguages\":[\"en\"]}", "{\"inputLanguages\":[\"zh\"]}"]
        for (index, json) in samples.enumerated() {
            let folder = directory.appendingPathComponent(String(index), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let configURL = folder.appendingPathComponent("config.json")
            try Data(json.utf8).write(to: configURL)
            let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
            let document = SettingsService(store: SettingsStore(configURL: configURL), platform: .mac, library: library).document()
            func collect(_ field: SettingsDocument.Field) {
                fields[field.id] = field
                for child in field.schema ?? [] { collect(child) }
                for item in field.items ?? [] {
                    for child in item.fields ?? [] { collect(child) }
                }
            }
            for section in document.sections {
                for field in section.fields { collect(field) }
            }
        }
        #expect(!fields.isEmpty, "the test must see the Settings document")
        for field in fields.values.sorted(by: { $0.id < $1.id }) {
            let label = field.label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            #expect(searchable.contains(label) || searchable.contains("`\(field.id)`"),
                    "guide omits Settings field \(field.id) (\(field.label))")
        }
        for command in Command.builtins {
            #expect(searchable.contains("@\(command.name)"), "guide omits built-in @\(command.name)")
        }
    }
}

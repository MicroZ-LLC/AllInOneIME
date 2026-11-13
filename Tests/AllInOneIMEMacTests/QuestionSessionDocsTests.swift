import Foundation
import Testing

/// What the READMEs and the user guide (which `@question` reads from) say of the question sessions: each conversation a
/// new one, nothing remembered across them; ⌘⏎ opens the CLI as the user set it up, a normal interactive session with
/// their own rules, tools and MCP servers, unlike the web-only session; text not typed keeps the web to the addresses
/// typed.
struct QuestionSessionDocsTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func read(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The text of `document` from `heading` to the next heading of its level or above (one line, its wrapping undone).
    func section(_ document: String, _ heading: String) throws -> String {
        let start = try #require(document.range(of: heading))
        let rest = document[start.upperBound...]
        let end = rest.range(of: "\n## ")?.lowerBound ?? rest.range(of: "\n### ")?.lowerBound ?? rest.endIndex
        return rest[..<end].replacingOccurrences(of: "\n", with: " ")
    }

    @Test func nothingSaysTheSessionRemembersEarlierQuestions() throws {
        for path in ["README.md", "README.zh-CN.md", "Resources/user-guide.md", "CHANGELOG.md", "CHANGELOG.zh-CN.md"] {
            let text = try read(path)
            #expect(!text.contains("remembers earlier questions") && !text.contains("记得以前问过的问题"), "\(path)")
        }
        let readme = try section(try read("README.md"), "### @question in a session of its own")
        #expect(readme.contains("is a new conversation in the session") && readme.contains("not earlier conversations"))
    }

    @Test func theHandOffIsTheCLIAsTheUserSetItUp() throws {
        let readme = try section(try read("README.md"), "### @question in a session of its own")
        #expect(readme.contains("normal interactive session") && readme.contains("your own rules")
                && readme.contains("MCP servers"), "README")
        let chinese = try section(try read("README.zh-CN.md"), "### @question 用输入法自己的会话")
        #expect(chinese.contains("普通的交互式会话") && chinese.contains("你自己的规则") && chinese.contains("MCP 服务器"), "README.zh-CN")
        let guide = try section(try read("Resources/user-guide.md"), "## Question sessions read the web, not your files")
        #expect(guide.contains("normal interactive session") && guide.contains("MCP servers") && guide.contains("普通的交互式会话"))
    }

    @Test func thePrivacyTextSaysTheWebIsKeptToTheAddressesTyped() throws {
        let privacy = try section(try read("README.md"), "## Privacy")
        #expect(privacy.contains("only the addresses you typed yourself") && privacy.contains("web tools are off"))
        let chinese = try read("README.zh-CN.md")
        #expect(chinese.contains("只能打开你自己打的网址"))
    }
}

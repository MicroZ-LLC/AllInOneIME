import Foundation
import Testing

/// Acceptance (0.7.4, written from the spec): the Mac's side of `@question`'s own session, read from the input method's
/// sources and the README (the executable target can't be linked into a test). The core's behavior is checked with fake
/// CLIs in the core's QuestionSessionAcceptanceTests.
struct QuestionSessionMacAcceptanceTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func read(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The Swift sources of the input method, without comments.
    func code(_ path: String) throws -> String {
        try read(path).split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let comment = line.range(of: "//") else { return line }
                return line[..<comment.lowerBound]
            }
            .joined(separator: "\n")
    }

    func inputMethodSources() throws -> [(name: String, code: String)] {
        let folder = Self.root.appendingPathComponent("Sources/AllInOneIME")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".swift") }.sorted()
        return try files.map { ($0, try code("Sources/AllInOneIME/" + $0)) }
    }

    // MARK: - 4. The README tells how to open each session

    @Test func theReadmeTellsHowToOpenEachSession() throws {
        let readme = try read("README.md")
        let section = try #require(readme.range(of: "To open the session yourself").map { String(readme[$0.lowerBound...].prefix(1500)) })
        #expect(section.contains("claude-session") && section.contains("claude --resume AllInOneIME"), "Claude Code")
        #expect(section.contains("codex resume AllInOneIME"), "Codex")
        #expect(section.contains("gemini-session") && section.contains("gemini --resume"), "Gemini CLI")
        #expect(section.contains("kiro-session") && section.contains("kiro-cli chat --resume"), "Kiro CLI")
        let chinese = try read("README.zh-CN.md")
        for needle in ["claude --resume AllInOneIME", "codex resume AllInOneIME", "gemini-session", "kiro-session", "kiro-cli chat --resume"] {
            #expect(chinese.contains(needle), "README.zh-CN.md: \(needle)")
        }
    }

    // MARK: - 2. When the sign-in is looked at

    /// Never at launch: nothing in the input method looks at the sign-in or starts a session except Settings' pane and
    /// the sessions' own file (the core's converter does it for a question about to be asked).
    @Test func nothingLooksAtTheSignInAtLaunch() throws {
        for (name, code) in try inputMethodSources() {
            if code.contains("checkAvailability(") {
                #expect(["ClaudeSessionMac.swift", "ClaudeSessionSettings.swift"].contains(name), "\(name) looks at the sign-in")
            }
            // The question sessions' prewarm (`ClaudeSessionManager.prewarm`), not the panel's or another service's.
            for line in code.split(separator: "\n") where line.contains(".prewarm(") {
                #expect(!line.contains("ClaudeSessionMac") && !line.contains("session.prewarm") && !line.contains("manager"),
                        "\(name) starts a session: \(line)")
            }
            #expect(!code.contains("questionSessionChecked("), "\(name) looks at the sign-in")
        }
        let main = try code("Sources/AllInOneIME/main.swift")
        #expect(!main.contains("ClaudeSessionMac"), "launch touches the sessions")
    }

    /// Opening Settings (its @question pane appearing) looks again, forced, at every agent.
    @Test func openingSettingsForcesALook() throws {
        let settings = try code("Sources/AllInOneIME/ClaudeSessionSettings.swift")
        let appear = try #require(settings.range(of: ".onAppear").map { String(settings[$0.lowerBound...].prefix(300)) })
        #expect(appear.contains("ClaudeSessionMac.checkAvailability"))
        let mac = try code("Sources/AllInOneIME/ClaudeSessionMac.swift")
        let check = try #require(mac.range(of: "static func checkAvailability").map { String(mac[$0.lowerBound...].prefix(700)) })
        #expect(check.contains("checkAvailability(force: true)") && check.contains("managers"))
    }

    // MARK: - 5. What each session's process gets

    /// Every session's process is started with what its agent needs in its environment (Codex's
    /// CODEX_EXEC_SERVER_URL=none, Gemini CLI's GEMINI_CLI_NO_RELAUNCH).
    @Test func everySessionGetsItsAgentsEnvironment() throws {
        let mac = try code("Sources/AllInOneIME/ClaudeSessionMac.swift")
        let launcher = try #require(mac.range(of: "private static func launcher").map { String(mac[$0.lowerBound...].prefix(500)) })
        #expect(launcher.contains("backend.environment") && launcher.contains("merging"))
        #expect(mac.contains("launcher: launcher(ClaudeCodeBackend()"))
        let session = try #require(mac.range(of: "private static func session").map { String(mac[$0.lowerBound...].prefix(400)) })
        #expect(session.contains("launcher(backend"))
        for backend in ["CodexBackend()", "ACPBackend.gemini", "ACPBackend.kiro"] {
            #expect(mac.contains("session(\(backend))"), "\(backend)")
        }
    }

    /// The user's own Gemini CLI and Codex settings are never written: nothing in the sources names them as a file to write.
    @Test func theUsersGeminiAndCodexSettingsAreNeverWritten() throws {
        var sources = try inputMethodSources().map(\.code)
        let core = Self.root.appendingPathComponent("Core/Sources/AllInOneIMECore")
        for name in try FileManager.default.contentsOfDirectory(atPath: core.path) where name.hasSuffix(".swift") {
            sources.append(try code("Core/Sources/AllInOneIMECore/" + name))
        }
        for code in sources {
            #expect(!code.contains("config.toml"))
            #expect(!code.contains(#"".codex""#))
            // Gemini CLI's settings are read (the sign-in), never written.
            for line in code.split(separator: "\n") where line.contains(".gemini") || line.contains("GeminiCli") {
                #expect(!line.contains(".write(") && !line.contains("createFile") && !line.contains("copyItem"), "\(line)")
            }
        }
    }

    // MARK: - Picking another backend

    /// Picking where questions go in Settings ends every session's process (the next question starts the one picked).
    @Test func pickingABackendEndsTheSessions() throws {
        let settings = try code("Sources/AllInOneIME/ClaudeSessionSettings.swift")
        let set = try #require(settings.range(of: "set: { backend in").map { String(settings[$0.lowerBound...].prefix(400)) })
        #expect(set.contains("questionBackend = backend") && set.contains("session.stop()"))
    }
}

import AppKit
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

    // MARK: - Settings → AI: one choice of AI (0.7.4's owner-approved design)

    /// One picker for the AI, built from the core's choices by how they connect (`AIChoice.groups`): no Automatic, and no
    /// separate provider or Questions picker left.
    @Test func theAIPickerIsOneChoiceWithNoAutomatic() throws {
        let picker = try code("Sources/AllInOneIME/AIPicker.swift") + "\n" + (try code("Sources/AllInOneIME/ClaudeSessionSettings.swift"))
        #expect(picker.contains("AIChoice.groups("))
        for word in ["Automatic", "automatic", "自动"] { #expect(!picker.contains(word), "the AI picker says \(word)") }
        for (name, code) in try inputMethodSources() {
            #expect(!code.contains("$model.config.provider") && !code.contains("$model.config.questionBackend")
                    && !code.contains("ForEach(Provider.offered") && !code.contains("QuestionBackend.allCases"),
                    "\(name) has a picker of its own for the provider or the questions")
        }
    }

    /// A CLI's sign-in is looked at only by Settings → AI: as it shows with a CLI chosen, as its cards open, and as a CLI is
    /// picked; never with a provider chosen and the cards closed, never as a provider is picked, never at launch (see
    /// `nothingLooksAtTheSignInAtLaunch`).
    @Test func theSignInIsLookedAtOnlyOnTheAIPageForACLIOrTheCards() throws {
        for (name, code) in try inputMethodSources() where code.contains("refreshSessions(") || code.contains("checkAvailability(") {
            #expect(["ClaudeSessionMac.swift", "ClaudeSessionSettings.swift"].contains(name), "\(name) looks at a sign-in")
        }
        let settings = try code("Sources/AllInOneIME/ClaudeSessionSettings.swift")
        // Shown: only with the cards open or a CLI chosen.
        let appear = try #require(settings.range(of: ".onAppear").map { String(settings[$0.lowerBound...].prefix(400)) })
        let look = try #require(appear.range(of: "ClaudeSessionMac.checkAvailability"))
        let before = appear[..<look.lowerBound]
        #expect(before.contains("guard") && before.contains("choosing") && before.contains(".agent != nil"), "\(before)")
        // The cards opened: looked at; closed: not.
        let change = try #require(settings.range(of: ".onChange(of: choosing)").map { String(settings[$0.lowerBound...].prefix(120)) })
        #expect(change.contains("if choosing") && change.contains("refreshSessions()"), "\(change)")
        // Picking: a provider looks at nothing itself; a CLI (another than before) is looked at.
        let choose = try #require(settings.range(of: "func choose(").map { String(settings[$0.lowerBound...].prefix(300)) })
        let chooseBody = choose[..<(choose.range(of: "\n    }")?.lowerBound ?? choose.endIndex)]
        #expect(!chooseBody.contains("refreshSessions") && !chooseBody.contains("checkAvailability"), "\(chooseBody)")
        let set = try #require(settings.range(of: "set: { backend in").map { String(settings[$0.lowerBound...].prefix(500)) })
        let refresh = try #require(set.range(of: "refreshSessions()"))
        #expect(set[..<refresh.lowerBound].contains("if backend != nil"), "a provider picked looks at the CLIs: \(set)")
    }

    /// A CLI found only inside a desktop app counts as installed: the ChatGPT app's codex (bundle com.openai.codex since the
    /// Codex app merged into it), the Claude app's Claude Code. Where the input method looks for each program (the
    /// sessions' launchers, so their sign-in looks and starts, and the hand-off to Terminal) falls back to the app's copy.
    /// Where this Mac has one of those apps, its copy is where the sources look.
    @Test func aCLIOnlyInADesktopAppCountsAsInstalled() throws {
        let mac = try code("Sources/AllInOneIME/ClaudeSessionMac.swift")
        let claude = try #require(mac.range(of: "static var claudeURL").map { String(mac[$0.lowerBound...].prefix(300)) })
        #expect(claude.contains("desktopBundled(.claude)"), "\(claude)")
        let program = try #require(mac.range(of: "static func program(").map { String(mac[$0.lowerBound...].prefix(300)) })
        #expect(program.contains("desktopBundled(agent)"), "\(program)")
        #expect(mac.contains("executable: { claudeURL }") && mac.contains("executable: { program(backend.agent) }"))
        let handOff = try #require(mac.range(of: "static func handOff(").map { String(mac[$0.lowerBound...].prefix(400)) })
        #expect(handOff.contains("program(session.backend.agent)"), "\(handOff)")
        let bundled = try #require(mac.range(of: "static func desktopBundled(").map { String(mac[$0.lowerBound...].prefix(1400)) })
        #expect(bundled.contains("com.openai.codex") && bundled.contains("Contents/Resources/codex-cli/bin/codex"))
        #expect(bundled.contains("Library/Application Support/Claude/claude-code") && bundled.contains("claude.app/Contents/MacOS/claude"))

        // This Mac's: the Claude app's Claude Code, where it has it, is an executable at that place.
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude-code")
        if let versions = try? fm.contentsOfDirectory(atPath: root.path), !versions.isEmpty {
            let found = versions.contains { version in
                ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(version).path)) ?? []).contains { hash in
                    fm.isExecutableFile(atPath: root.appendingPathComponent("\(version)/\(hash)/claude.app/Contents/MacOS/claude").path)
                }
            }
            #expect(found, "the Claude app's Claude Code isn't where the input method looks: \(versions)")
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            #expect(fm.isExecutableFile(atPath: app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex").path),
                    "the ChatGPT app's codex isn't where the input method looks: \(app.path)")
        }
    }
}

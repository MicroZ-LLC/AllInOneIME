import Foundation
import Testing

/// `@agent` finds a CLI where the question sessions do (`ClaudeSessionMac.program`, read from the input method's sources:
/// the executable target can't be linked into a test): one lookup, so a CLI that only came with a desktop app (the
/// Claude app's Claude Code, the ChatGPT app's codex) counts as installed for `@agent` too, and runs from there.
struct AgentProgramLookupTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The Swift source at `path` without comments.
    func code(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.range(of: "//").map { line[..<$0.lowerBound] } ?? line }
            .joined(separator: "\n")
    }

    /// `code` from `start` on, `length` characters.
    func part(_ code: String, _ start: String, _ length: Int = 600) throws -> String {
        let begin = try #require(code.range(of: start))
        return String(code[begin.lowerBound...].prefix(length))
    }

    @Test func theLookupIsTheSessionsForEveryAgentsProgram() throws {
        let mac = try code("Sources/AllInOneIME/ClaudeSessionMac.swift")
        let agent = try part(mac, "static func agent(program:", 200)
        #expect(agent.contains("SessionAgent.allCases") && agent.contains(".program == program"), "\(agent)")
        let installed = try part(mac, "static func isInstalled(", 400)
        #expect(installed.contains("agent(program: program)") && installed.contains("self.program(agent) != nil"), "\(installed)")
        #expect(installed.contains("CommandRunner.isInstalled"), "any other program as before: \(installed)")
    }

    @Test func agentLooksWhereTheSessionsLook() throws {
        let settings = try code("Sources/AllInOneIME/AgentSettings.swift")
        let availability = try part(settings, "static func installed(program:", 300)
        #expect(availability.contains("ClaudeSessionMac.isInstalled(program)"), "\(availability)")
        let services = try code("Sources/AllInOneIME/SessionServices+Mac.swift")
        let program = try part(services, "services.programInstalled = {", 400)
        #expect(program.contains("ClaudeSessionMac.isInstalled(program)"), "\(program)")
        let panel = try code("Sources/AllInOneIME/FloatingPanel.swift")
        let tasks = try part(panel, "listAgents: {", 500)
        #expect(tasks.contains("ClaudeSessionMac.claudeURL") && tasks.contains("AgentMonitor.run(claude.path"), "\(tasks)")
        let monitor = try code("Sources/AllInOneIME/AgentMonitor.swift")
        #expect(monitor.contains("var claude: String { ClaudeSessionMac.claudeURL?.path"))
        let terminal = try code("Sources/AllInOneIME/TerminalLauncher.swift")
        let launch = try part(terminal, "static func agent(", 400)
        #expect(launch.contains("ClaudeSessionMac.agent(program: argv[0])") && launch.contains("ClaudeSessionMac.program(agent)"),
                "\(launch)")
    }

    /// No lookup of its own left: `TerminalLauncher.claudePath` only where the sessions' lookup starts.
    @Test func noOtherLookupIsLeft() throws {
        let folder = Self.root.appendingPathComponent("Sources/AllInOneIME")
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.hasSuffix(".swift") {
            let source = try code("Sources/AllInOneIME/" + name)
            guard source.contains("claudePath") else { continue }
            #expect(["TerminalLauncher.swift", "ClaudeSessionMac.swift"].contains(name), "\(name) looks for claude itself")
        }
        let mac = try code("Sources/AllInOneIME/ClaudeSessionMac.swift")
        #expect(try part(mac, "static var claudeURL", 200).contains("TerminalLauncher.claudePath"))
    }
}

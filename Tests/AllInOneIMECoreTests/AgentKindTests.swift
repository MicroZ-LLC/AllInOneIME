import Foundation
import Testing
@testable import AllInOneIMECore

struct AgentKindTests {
    @Test func eachAgentsProgramAndArguments() {
        #expect(AgentKind.claude.terminalArguments() == ["claude", "--"] && AgentKind.claude.program() == "claude")
        #expect(AgentKind.gemini.terminalArguments() == ["gemini", "-i"] && AgentKind.gemini.program() == "gemini")
        #expect(AgentKind.kiro.terminalArguments() == ["kiro-cli", "chat", "--"] && AgentKind.kiro.program() == "kiro-cli")
        #expect(AgentKind.custom.terminalArguments(custom: ["/opt/bin/muse", "--"]) == ["/opt/bin/muse", "--"])
        #expect(AgentKind.custom.displayName(custom: ["/opt/bin/muse", "--"]) == "muse")
        // A custom agent without a command has nothing to run.
        for empty in [[], [""], ["  "]] as [[String]] {
            #expect(AgentKind.custom.program(custom: empty) == nil && AgentKind.custom.terminalArguments(custom: empty) == nil)
        }
        #expect(AgentKind.allCases.filter(\.supportsBackground) == [.claude])
    }

    @Test func atAgentIsTheBuiltInAndNeedsTheAgentsProgram() {
        #expect(Command.builtins.contains(.agent) && !Command.builtins.contains { $0.name == "claude" })
        #expect(Command.parse("@agent 你好")! == (.agent, "你好"))
        #expect(Command.agent.program == "claude")
        #expect(Command.agent.program(agent: .kiro) == "kiro-cli")
        #expect(Command.agent.program(agent: .custom, custom: ["muse"]) == "muse")
        #expect(Command.agent.program(agent: .custom) == nil)
        #expect(Command.py.program(agent: .gemini) == Command.py.program)  // only @agent's depends on it
        #expect(Command.agent.usesAI)
    }

    @Test func theConfigKeepsTheAgent() throws {
        #expect(Config.default.agent == .claude && Config.default.agentCommand.isEmpty)
        var config = Config.default
        config.agent = .custom
        config.agentCommand = ["muse", "--"]
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(decoded.agent == .custom && decoded.agentCommand == ["muse", "--"])
        // A kind a later version added is Claude Code here, and the rest of the file still reads.
        let later = try JSONDecoder().decode(Config.self, from: Data(#"{"agent": "codex", "claudeInBackground": false}"#.utf8))
        #expect(later.agent == .claude && !later.claudeInBackground)
    }

    @Test func claudesUseMovesToAgentOnce() {
        let now = Date()
        var usage = CommandUsage()
        for _ in 0..<3 { usage.record("claude", now: now) }
        let score = usage.score("claude", now: now)
        usage.migrateRenamed(from: "claude", to: "agent")
        #expect(usage.score("agent", now: now) == score && usage.score("claude", now: now) == 0)
        // Already kept under the new name: that one stays.
        usage.record("claude", now: now)
        usage.migrateRenamed(from: "claude", to: "agent")
        #expect(usage.score("agent", now: now) == score)
    }
}

import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// The MCP servers a session gets (`SessionMCP`): what the manager gives a process as it starts, Kiro's mode with them,
/// and the TOML and HTTP forms read.
struct SessionMCPTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("session-mcp-\(UUID().uuidString)")

    static let docs = MCPServer(name: "docs", transport: .stdio(command: "/bin/echo", args: [], env: ["TOKEN": "fake"]))
    static let mcp = SessionMCP([.init(server: docs, tools: ["search"])])

    @Test func aProcessStartedWithTheWebOpenGetsTheServersInItsFolder() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let fake = FakeClaude()
        let session = ClaudeSessionManager(launcher: fake, store: ClaudeSessionStore(directory: folder), userSettings: { nil },
                                           mcp: { Self.mcp })
        session.prewarm()
        #expect(await Timing.eventually { fake.last != nil })
        let arguments = try #require(fake.last?.arguments)
        let file = folder.appendingPathComponent(ClaudeSession.mcpFile)
        #expect(arguments.contains("--mcp-config") && arguments.contains(file.path))
        #expect(arguments.contains { $0.contains("mcp__docs__search") })
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        session.stop()
    }

    @Test func noServersRemovesAnEarlierFile() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ClaudeSessionStore(directory: folder)
        try store.writeMCP(ClaudeCodeBackend().mcpFiles(Self.mcp))
        let file = folder.appendingPathComponent(ClaudeSession.mcpFile)
        #expect(FileManager.default.fileExists(atPath: file.path))
        try store.writeMCP(ClaudeCodeBackend().mcpFiles(.none))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func kiroRunsInItsMCPModeOnlyWithServersAndTheWebOpen() {
        let kiro = ACPBackend.kiro
        let withServers = kiro.driver(sessionID: "s", agentSessionID: nil, resume: false, directory: folder, web: .open, mcp: Self.mcp)
        let without = kiro.driver(sessionID: "s", agentSessionID: nil, resume: false, directory: folder, web: .open, mcp: .none)
        let offline = kiro.driver(sessionID: "s", agentSessionID: nil, resume: false, directory: folder, web: .only([]), mcp: Self.mcp)
        #expect((withServers as? ACPDriver)?.mode == ACPBackend.kiroMCPMode)
        #expect((without as? ACPDriver)?.mode == ACPBackend.kiroMode)
        #expect((offline as? ACPDriver)?.mode == ACPBackend.kiroOfflineMode)
    }

    @Test func codexTomlInlineTablesAndQuotedNames() {
        let servers = MCPServers.fromTOML("""
            model = "x"
            [mcp_servers."my-docs"]
            command = 'npx'   # a comment
            args = ["-y", "docs-server"]
            env = { TOKEN = "fake", MODE = "read" }
            [mcp_servers.remote]
            url = "https://example.com/mcp"
            http_headers = { Authorization = "Bearer fake" }
            [profiles.other]
            command = "not-a-server"
            """)
        #expect(servers.map(\.name) == ["my-docs", "remote"])
        #expect(servers[0].transport == .stdio(command: "npx", args: ["-y", "docs-server"], env: ["TOKEN": "fake", "MODE": "read"]))
        #expect(servers[1].transport == .http(url: "https://example.com/mcp", headers: ["Authorization": "Bearer fake"], sse: false))
    }

    @Test func anHTTPAnswerIsReadFromJSONOrItsLastEvent() {
        #expect(MCPToolList.message(in: Data(#"{"id":1,"result":{}}"#.utf8))?["id"] as? Int == 1)
        let events = Data("event: message\ndata: {\"id\":2,\"result\":{\"tools\":[]}}\n\n".utf8)
        #expect(MCPToolList.message(in: events)?["id"] as? Int == 2)
        #expect(MCPToolList.message(in: Data("nothing".utf8)) == nil)
    }
}

/// What the review of #139 found, kept from coming back.
struct SessionMCPReviewTests {
    @Test func codexArraysOnSeveralLinesAndCommentsAfterAHeader() {
        let servers = MCPServers.fromTOML("""
            [mcp_servers.docs]  # the docs
            command = "npx"
            args = [
              "-y",  # quiet
              "docs-server",
            ]
            """)
        #expect(servers.first?.transport == .stdio(command: "npx", args: ["-y", "docs-server"], env: [:]))
    }

    @Test func aRequestOfTheServersOwnIsNoAnswer() async throws {
        let lines = [#"{"jsonrpc":"2.0","id":7,"method":"ping"}"#, #"{"jsonrpc":"2.0","id":1,"result":{}}"#,
                     #"{"jsonrpc":"2.0","id":8,"method":"roots/list"}"#,
                     #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"look","annotations":{"readOnlyHint":true}}]}}"#]
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        for line in lines { continuation.yield(Data(line.utf8)) }
        continuation.finish()
        let tools = try await MCPToolList.converse(send: { _ in }, answers: stream)
        #expect(tools == [MCPTool(name: "look", readOnly: true)])
    }

    @Test func aToolNameThatCouldAddAnotherIsLeftOut() {
        let server = MCPServer(name: "my docs", transport: .stdio(command: "x", args: [], env: [:]))
        let mcp = SessionMCP([.init(server: server, tools: ["search", "x,mcp__other__write", ""])])
        #expect(mcp.claudeTools == ["mcp__my_docs__search"])
    }
}

struct SessionMCPThirdReviewTests {
    @Test func aMultiLineStringIsSkipped() {
        let servers = MCPServers.fromTOML(#"""
            notes = """
            a [ that never closes
            [mcp_servers.fake]
            """
            [mcp_servers.real]
            command = "npx"
            """#)
        #expect(servers.map(\.name) == ["real"])
    }
}

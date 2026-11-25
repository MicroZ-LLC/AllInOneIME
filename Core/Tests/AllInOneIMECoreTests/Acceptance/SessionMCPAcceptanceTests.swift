import Foundation
import Testing
@testable import AllInOneIMECore

/// 0.7.5: the session's agent gets the MCP servers the user checked in Settings, found in the agent's own config, and of
/// each only its read-only tools (`annotations.readOnlyHint == true`), and only while the conversation's web is open.
///
/// Where the contract gave no signature these tests assume (all in `found`, `tools` and `Fixture` below):
/// `MCPServers.found(_ agent:environment:home:) -> [MCPServer]`; `MCPServer` has `name`, `command`, `args`, `env`, `url`;
/// `MCPToolList.list(_:)` may be async and throwing; `mcpConfig:` is a file `URL`; `ClaudeSession.mcpFile` is the
/// file's path in the session's folder (a `String`).
@Suite struct SessionMCPAcceptanceTests {
    // MARK: Helpers

    /// A temp folder, removed by the caller.
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-accept-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func put(_ text: String, _ path: String, in folder: URL) throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// The servers of `agent`'s own config, with `home` as the home folder (never the real one).
    private func found(_ agent: SessionAgent, _ environment: [String: String] = [:], home: URL) -> [MCPServer] {
        MCPServers.found(agent, environment: environment, home: home)
    }

    private func json(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    /// Three servers in a fake Claude Code config: "docs" and "writer" (stdio), "remote" (http).
    private func claudeServers(home: URL) throws -> [MCPServer] {
        try put("""
            {"numStartups": 3, "mcpServers": {
              "writer": {"command": "/bin/cat", "args": []},
              "docs": {"command": "/bin/echo", "args": ["a", "b"], "env": {"TOKEN": "fake-token"}},
              "remote": {"type": "http", "url": "https://example.com/mcp", "headers": {"X-Fake": "1"}}
            }}
            """, ".claude.json", in: home)
        return found(.claude, home: home)
    }

    /// "docs" and "remote" checked with read-only tools, "writer" checked with none, "gone" no longer in the config.
    private func checkedMCP(_ agent: SessionAgent, _ servers: [MCPServer]) -> SessionMCP {
        SessionMCP.of(agent, checked: ["docs": ["search", "read"], "remote": ["fetch"], "writer": [], "gone": ["x"]], found: servers)
    }

    /// A stdio MCP server as a shell script: answers `initialize`, ignores the notification, and gives its tools in two
    /// pages (`nextCursor` "page2"). Each answer carries the request's id.
    private static let fakeServer = #"""
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -n 's/.*"id"[ ]*:[ ]*\([0-9][0-9]*\).*/\1/p')
          case "$line" in
            *notifications*) ;;
            *tools*list*page2*)
              echo '{"jsonrpc":"2.0","id":'"$id"',"result":{"tools":[{"name":"plain","inputSchema":{"type":"object"}},{"name":"look","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":true}}]}}' ;;
            *tools*list*)
              echo '{"jsonrpc":"2.0","id":'"$id"',"result":{"tools":[{"name":"read","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":true}},{"name":"write","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":false}}],"nextCursor":"page2"}}' ;;
            *initialize*)
              echo '{"jsonrpc":"2.0","id":'"$id"',"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"fake","version":"1"}}}' ;;
          esac
        done

        """#

    // MARK: 1. The agent's own config

    @Test func claudeServersAreReadFromItsConfigSortedByName() throws {
        let home = try folder(); defer { try? FileManager.default.removeItem(at: home) }
        let servers = try claudeServers(home: home)
        #expect(servers.map(\.name) == ["docs", "remote", "writer"])
        let docs = try #require(servers.first)
        #expect(docs.command == "/bin/echo")
        #expect(docs.args == ["a", "b"])
        #expect(docs.env == ["TOKEN": "fake-token"])
        #expect(String(describing: servers[1].url).contains("https://example.com/mcp"))
    }

    @Test func claudeConfigDirWinsOverHomeAndIsNeverWritten() throws {
        let home = try folder(); defer { try? FileManager.default.removeItem(at: home) }
        _ = try claudeServers(home: home)
        let text = #"{"mcpServers": {"other": {"command": "/bin/echo"}}}"#
        try put(text, "config/.claude.json", in: home)
        let config = home.appendingPathComponent("config")
        #expect(found(.claude, ["CLAUDE_CONFIG_DIR": config.path], home: home).map(\.name) == ["other"])
        #expect(try String(contentsOf: config.appendingPathComponent(".claude.json"), encoding: .utf8) == text)
    }

    @Test func kiroServersLeaveOutDisabledOnes() throws {
        let home = try folder(); defer { try? FileManager.default.removeItem(at: home) }
        try put("""
            {"mcpServers": {
              "zeta": {"command": "/bin/echo", "args": ["z"]},
              "off": {"command": "/bin/echo", "disabled": true},
              "alpha": {"url": "https://example.com/mcp", "disabled": false}
            }}
            """, ".kiro/settings/mcp.json", in: home)
        let servers = found(.kiro, home: home)
        #expect(servers.map(\.name) == ["alpha", "zeta"])
        #expect(servers.last?.command == "/bin/echo")
        #expect(servers.last?.args == ["z"])
    }

    @Test func codexServersComeFromItsTomlTables() throws {
        let home = try folder(); defer { try? FileManager.default.removeItem(at: home) }
        let toml = """
            model = "some-model"

            [mcp_servers.remote]
            url = "https://example.com/mcp"

            [mcp_servers.docs]
            command = "/bin/echo"
            args = ["a", "b"]

            [mcp_servers.docs.env]
            TOKEN = "fake-token"

            [mcp_servers.off]
            command = "/bin/cat"
            enabled = false

            [profiles.work]
            model = "other-model"

            """
        try put(toml, ".codex/config.toml", in: home)
        let servers = found(.codex, home: home)
        #expect(servers.map(\.name) == ["docs", "remote"])
        #expect(servers.first?.command == "/bin/echo")
        #expect(servers.first?.args == ["a", "b"])
        #expect(servers.first?.env == ["TOKEN": "fake-token"])
        let lastURL = String(describing: servers.last?.url)
        #expect(lastURL.contains("https://example.com/mcp"))

        try put("[mcp_servers.elsewhere]\ncommand = \"/bin/echo\"\n", "codex-home/config.toml", in: home)
        let codexHome = home.appendingPathComponent("codex-home").path
        #expect(found(.codex, ["CODEX_HOME": codexHome], home: home).map(\.name) == ["elsewhere"])
    }

    @Test func antigravityHasNoneAndAMissingConfigIsNoServers() throws {
        let home = try folder(); defer { try? FileManager.default.removeItem(at: home) }
        #expect(!MCPServers.supports(.antigravity))
        #expect(MCPServers.supports(.claude) && MCPServers.supports(.codex) && MCPServers.supports(.kiro))
        for agent in SessionAgent.allCases { #expect(found(agent, home: home).isEmpty) }
    }

    // MARK: 2. What the user checked

    @Test func checkedServersAreInConfigOnlyWhenThereAreSome() throws {
        var config = Config.fresh
        #expect(config.sessionMCP.isEmpty)
        let empty = try #require(String(data: try JSONEncoder().encode(config), encoding: .utf8))
        #expect(!empty.contains("sessionMCP"))

        let checked = ["claude": ["docs": ["search", "read"]], "kiro": ["alpha": []]]
        config.sessionMCP = checked
        let data = try JSONEncoder().encode(config)
        #expect(String(data: data, encoding: .utf8)?.contains("sessionMCP") == true)
        #expect(try JSONDecoder().decode(Config.self, from: data).sessionMCP == checked)
        #expect(ICloudSync.neverSynced.contains("sessionMCP"))
    }

    // MARK: 3. Read-only tools

    @Test func toolsAreListedAcrossPagesAndOnlyAHintOfTrueIsReadOnly() async throws {
        let home = try folder(); defer { try? FileManager.default.removeItem(at: home) }
        try put(Self.fakeServer, "fake-mcp.sh", in: home)
        let script = home.appendingPathComponent("fake-mcp.sh").path
        try put(#"{"mcpServers": {"fake": {"command": "/bin/sh", "args": ["\#(script)"]}}}"#, ".claude.json", in: home)
        let server = try #require(found(.claude, home: home).first)

        let tools: [MCPTool] = try await MCPToolList.list(server)
        #expect(tools.map(\.name) == ["read", "write", "plain", "look"])
        #expect(tools.filter(\.readOnly).map(\.name) == ["read", "look"])
    }

    @Test func aMissingProgramIsNotFound() async throws {
        let home = try folder(); defer { try? FileManager.default.removeItem(at: home) }
        let command = home.appendingPathComponent("no-such-mcp-server").path
        try put(#"{"mcpServers": {"missing": {"command": "\#(command)"}}}"#, ".claude.json", in: home)
        let server = try #require(found(.claude, home: home).first)
        do {
            _ = try await MCPToolList.list(server)
            Issue.record("a missing program listed tools")
        } catch MCPToolListError.notFound(let missing) {
            #expect(missing == command)
        }
    }

    // MARK: 4. What reaches the session

    @Test func onlyCheckedServersWithReadOnlyToolsAreGiven() throws {
        let home = try folder(); defer { try? FileManager.default.removeItem(at: home) }
        let servers = try claudeServers(home: home)
        let mcp = checkedMCP(.claude, servers)
        #expect(!mcp.isEmpty)
        #expect(mcp.servers.map(\.server.name).sorted() == ["docs", "remote"])
        #expect(mcp.servers.first { $0.server.name == "docs" }?.tools.sorted() == ["read", "search"])
        #expect(mcp.servers.first { $0.server.name == "remote" }?.tools == ["fetch"])

        #expect(SessionMCP.none.isEmpty && SessionMCP.none.servers.isEmpty)
        #expect(SessionMCP.of(.claude, checked: [:], found: servers).isEmpty)
        #expect(SessionMCP.of(.claude, checked: ["writer": []], found: servers).isEmpty)
        #expect(SessionMCP.of(.claude, checked: ["docs": ["search"]], found: []).isEmpty)
    }

    // MARK: 5 and 6. Claude Code

    @Test func claudeArgumentsAllowExactlyTheReadOnlyToolsWhileTheWebIsOpen() throws {
        let home = try folder(); defer { try? FileManager.default.removeItem(at: home) }
        let mcp = checkedMCP(.claude, try claudeServers(home: home))
        let file = home.appendingPathComponent("session-mcp.json")
        func arguments(_ web: SessionWeb, _ mcp: SessionMCP) -> [String] {
            ClaudeSession.arguments(sessionID: "id-1", resume: false, settings: nil, web: web, mcp: mcp, mcpConfig: file)
        }

        let with = arguments(.open, mcp)
        #expect(with.contains("--strict-mcp-config"))
        let flag = try #require(with.firstIndex(of: "--mcp-config"))
        #expect(with[flag + 1] == file.path)
        let allowed = try #require(with.firstIndex(of: "--allowedTools")).advanced(by: 1)
        let tools = with[allowed].components(separatedBy: ",")
        #expect(Array(tools.prefix(2)) == ["WebSearch", "WebFetch"])
        #expect(Set(tools.dropFirst(2)) == ["mcp__docs__search", "mcp__docs__read", "mcp__remote__fetch"])
        #expect(tools.count == 5)

        let address = try #require(URL(string: "https://example.org/page"))
        for other in [arguments(.open, .none), arguments(.only([]), mcp), arguments(.only([address]), mcp)] {
            #expect(other.contains("--strict-mcp-config"))
            #expect(!other.contains("--mcp-config"))
            #expect(!other.contains { $0.contains("mcp__") })
        }
        #expect(arguments(.open, .none) == ClaudeSession.arguments(sessionID: "id-1", resume: false, settings: nil, web: .open))
    }

    @Test func claudeMCPFileHoldsOnlyTheGivenServers() throws {
        let home = try folder(); defer { try? FileManager.default.removeItem(at: home) }
        let files = ClaudeCodeBackend().mcpFiles(checkedMCP(.claude, try claudeServers(home: home)))
        #expect(files.count == 1)
        let file = try #require(files.first)
        #expect(file.path == ClaudeSession.mcpFile)
        let servers = try #require(try json(file.content)["mcpServers"] as? [String: [String: Any]])
        #expect(servers.keys.sorted() == ["docs", "remote"])
        #expect(servers["docs"]?["type"] as? String == "stdio")
        #expect(servers["docs"]?["command"] as? String == "/bin/echo")
        #expect(servers["docs"]?["args"] as? [String] == ["a", "b"])
        #expect(servers["docs"]?["env"] as? [String: String] == ["TOKEN": "fake-token"])
        #expect(servers["remote"]?["type"] as? String == "http")
        #expect(servers["remote"]?["url"] as? String == "https://example.com/mcp")

        let none = ClaudeCodeBackend().mcpFiles(.none)
        #expect(none.map(\.path) == [ClaudeSession.mcpFile])
        #expect(none.first?.content == "")
    }

    // MARK: 7. Kiro and Antigravity

    @Test func kiroAgentFileAllowsOnlyTheReadOnlyToolsAndTheWeb() throws {
        let home = try folder(); defer { try? FileManager.default.removeItem(at: home) }
        try put("""
            {"mcpServers": {"docs": {"command": "/bin/echo", "args": ["a"]}, "remote": {"url": "https://example.com/mcp"},
                            "writer": {"command": "/bin/cat"}}}
            """, ".kiro/settings/mcp.json", in: home)
        let mcp = checkedMCP(.kiro, found(.kiro, home: home))
        #expect(ACPBackend.kiroMCPMode == "allinoneime-mcp")

        let files = ACPBackend.kiro.mcpFiles(mcp)
        #expect(files.map(\.path) == [".kiro/agents/allinoneime-mcp.json"])
        let agent = try json(try #require(files.first).content)
        let servers = try #require(agent["mcpServers"] as? [String: [String: Any]])
        #expect(servers.keys.sorted() == ["docs", "remote"])
        #expect(servers["docs"]?["command"] as? String == "/bin/echo")
        let allowed = try #require(agent["allowedTools"] as? [String])
        #expect(Set(allowed) == ["@docs/search", "@docs/read", "@remote/fetch", "web_search", "web_fetch"])
        #expect(allowed.count == 5)

        let none = ACPBackend.kiro.mcpFiles(.none)
        #expect(none.map(\.path) == [".kiro/agents/allinoneime-mcp.json"])
        #expect(none.first?.content == "")
        #expect(AntigravityBackend(base: home).mcpFiles(mcp).isEmpty)
        #expect(AntigravityBackend(base: home).mcpFiles(.none).isEmpty)
    }

    // MARK: 8. Codex

    @Test func codexKeepsTheCheckedServersToTheirReadOnlyToolsAndTurnsTheRestOff() throws {
        let home = try folder(); defer { try? FileManager.default.removeItem(at: home) }
        try put("""
            [mcp_servers.docs]
            command = "/bin/echo"

            [mcp_servers.remote]
            url = "https://example.com/mcp"

            [mcp_servers.writer]
            command = "/bin/cat"

            """, ".codex/config.toml", in: home)
        let mcp = SessionMCP.of(.codex, checked: ["docs": ["search", "read"], "writer": []], found: found(.codex, home: home))
        let read: [String: Any] = ["model": "some-model", "mcp_servers": [
            "docs": ["command": "/bin/echo"], "remote": ["url": "https://example.com/mcp"], "writer": ["command": "/bin/cat"],
        ]]

        let kept = try #require(CodexDriver.mcpServersOff(read, keeping: mcp)["mcp_servers"] as? [String: [String: Any]])
        #expect(kept.keys.sorted() == ["docs", "remote", "writer"])
        #expect(kept["docs"]?["enabled"] as? Bool == true)
        #expect((kept["docs"]?["enabled_tools"] as? [String])?.sorted() == ["read", "search"])
        #expect(kept["docs"]?["command"] as? String == "/bin/echo")
        #expect(kept["remote"]?["enabled"] as? Bool == false)
        #expect(kept["remote"]?["url"] as? String == "https://example.com/mcp")
        #expect(kept["writer"]?["enabled"] as? Bool == false)
        #expect(kept["writer"]?["command"] as? String == "/bin/cat")

        let off = try #require(CodexDriver.mcpServersOff(read, keeping: .none)["mcp_servers"] as? [String: [String: Any]])
        #expect(off.count == 3)
        #expect(off.values.allSatisfy { $0["enabled"] as? Bool == false })
    }

    // MARK: 9. The files in the session's folder

    @Test func mcpFilesAreWrittenForTheUserOnlyAndRemovedWhenEmpty() throws {
        let home = try folder(); defer { try? FileManager.default.removeItem(at: home) }
        let store = ClaudeSessionStore(directory: home.appendingPathComponent("session"), files: [])
        let paths = [ClaudeSession.mcpFile, ".kiro/agents/allinoneime-mcp.json"]
        let content = #"{"mcpServers": {"docs": {"command": "/bin/echo", "env": {"TOKEN": "fake-token"}, "type": "stdio"}}}"#

        try store.writeMCP(paths.map { SessionFile(path: $0, content: content) })
        for path in paths {
            let url = store.directory.appendingPathComponent(path)
            #expect(try String(contentsOf: url, encoding: .utf8) == content)
            let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            #expect(permissions?.intValue == 0o600)
        }

        try store.writeMCP(paths.map { SessionFile(path: $0, content: "") })
        for path in paths {
            #expect(!FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(path).path))
        }
    }
}

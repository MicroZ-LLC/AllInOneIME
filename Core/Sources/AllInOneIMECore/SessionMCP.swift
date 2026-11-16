import Foundation

/// An MCP server the user set up in an agent's own config (`MCPServers.found`), as that agent would start it.
public struct MCPServer: Equatable, Sendable {
    public enum Transport: Equatable, Sendable {
        /// A program spoken to on its standard input and output.
        case stdio(command: String, args: [String], env: [String: String])
        /// One reached over HTTP (`sse`: the older server-sent events transport).
        case http(url: String, headers: [String: String], sse: Bool)
    }

    public var name: String
    public var transport: Transport

    public init(name: String, transport: Transport) {
        self.name = name
        self.transport = transport
    }

    /// A stdio server's program, arguments and environment; nil, none and none for one over HTTP.
    public var command: String? { if case let .stdio(command, _, _) = transport { command } else { nil } }
    public var args: [String] { if case let .stdio(_, args, _) = transport { args } else { [] } }
    public var env: [String: String] { if case let .stdio(_, _, env) = transport { env } else { [:] } }
    /// An HTTP server's address; nil for a stdio one.
    public var url: String? { if case let .http(url, _, _) = transport { url } else { nil } }

    /// The server as an `mcpServers` entry (Claude Code's `--mcp-config`, Kiro's agent config): `typed` adds Claude
    /// Code's `type`.
    func entry(typed: Bool) -> [String: Any] {
        switch transport {
        case let .stdio(command, args, env):
            var entry: [String: Any] = ["command": command, "args": args]
            if !env.isEmpty { entry["env"] = env }
            if typed { entry["type"] = "stdio" }
            return entry
        case let .http(url, headers, sse):
            var entry: [String: Any] = ["url": url]
            if !headers.isEmpty { entry["headers"] = headers }
            if typed { entry["type"] = sse ? "sse" : "http" }
            return entry
        }
    }
}

/// The MCP servers an agent's session may use (owner, 0.7.5): the ones checked in Settings → AI (`Config.sessionMCP`),
/// each with its read-only tools only (`MCPTool.readOnly`), the only ones allowed. A server with none isn't started.
/// Given only to a conversation whose web tools are open (`SessionWeb.open`): a question with text the user didn't type
/// gets no tools at all.
public struct SessionMCP: Equatable, Sendable {
    public struct Server: Equatable, Sendable {
        public var server: MCPServer
        /// The tools the session may call: the read-only ones, by their MCP names.
        public var tools: [String]

        public init(server: MCPServer, tools: [String]) {
            self.server = server
            self.tools = tools
        }
    }

    public var servers: [Server]

    /// Each server's tools with a name MCP allows (letters, digits, `_`, `-`, `.`) only: one with a comma or a space
    /// could add another tool to an agent's list of those allowed.
    public init(_ servers: [Server] = []) {
        self.servers = servers.map { Server(server: $0.server, tools: $0.tools.filter(Self.isToolName)) }.filter { !$0.tools.isEmpty }
    }

    static func isToolName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || "_-.".unicodeScalars.contains($0) }
    }

    public static let none = SessionMCP()

    public var isEmpty: Bool { servers.isEmpty }

    /// What `agent`'s session gets of `checked` (`Config.sessionMCP[agent]`: a server's name and its read-only tools),
    /// with the servers as found in the agent's config now (`found`): one checked that isn't there any more is left out.
    public static func of(_ agent: SessionAgent, checked: [String: [String]], found: [MCPServer]) -> SessionMCP {
        SessionMCP(found.compactMap { server in checked[server.name].map { Server(server: server, tools: $0) } })
    }

    // MARK: - Each agent's way

    /// Claude Code's `--mcp-config` file: the servers, typed.
    public var claudeConfig: String {
        Self.json(["mcpServers": Dictionary(uniqueKeysWithValues: servers.map { ($0.server.name, $0.server.entry(typed: true)) })])
    }

    /// Claude Code's names of the tools allowed (`mcp__<server>__<tool>`), for `--allowedTools`.
    public var claudeTools: [String] {
        servers.flatMap { server in
            // Claude Code's name of a server: any character but a letter, digit, `_` or `-` as `_`.
            let name = String(server.server.name.unicodeScalars.map { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-") ? Character($0) : "_" })
            return server.tools.map { "mcp__\(name)__\($0)" }
        }
    }

    /// Kiro's names of the tools allowed (`@<server>/<tool>`), for its agent config's `tools` and `allowedTools`.
    public var kiroTools: [String] {
        servers.flatMap { server in server.tools.map { "@\(server.server.name)/\($0)" } }
    }

    /// Kiro's agent config's `mcpServers`.
    var kiroServers: [String: Any] {
        Dictionary(uniqueKeysWithValues: servers.map { ($0.server.name, $0.server.entry(typed: false)) })
    }

    /// The thread config Codex gets for the servers of its own config (`config/read`'s `mcp_servers`): each one checked
    /// on, with only its read-only tools (`enabled_tools`); every other one off.
    func codexServers(_ configured: [String: Any]) -> [String: Any] {
        let kept = Dictionary(uniqueKeysWithValues: servers.map { ($0.server.name, $0.tools) })
        var result: [String: Any] = [:]
        for (name, server) in configured {
            let server = server as? [String: Any] ?? [:]
            var entry: [String: Any] = ["enabled": false]
            if let tools = kept[name] { entry = ["enabled": true, "enabled_tools": tools] }
            for key in ["url", "command"] { if let value = server[key] as? String { entry[key] = value } }
            result[name] = entry
        }
        return result
    }

    static func json(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

/// The MCP servers in each agent's own config, read, never written: Claude Code's `.claude.json` (in CLAUDE_CONFIG_DIR,
/// else the home folder; its user-wide `mcpServers`), Kiro CLI's `~/.kiro/settings/mcp.json`, Codex's `config.toml`
/// (in CODEX_HOME, else `~/.codex`; its `[mcp_servers.*]`). Antigravity's session can't have any (`supports`). One the
/// config turns off (`disabled`, `enabled = false`) isn't listed.
public enum MCPServers {
    /// Whether `agent`'s session can use MCP servers.
    public static func supports(_ agent: SessionAgent) -> Bool { agent != .antigravity }

    public static func found(_ agent: SessionAgent, environment: [String: String] = ProcessInfo.processInfo.environment,
                             home: URL = CorePaths.home) -> [MCPServer] {
        func folder(_ variable: String, _ fallback: String) -> URL {
            let set = environment[variable].map { ($0 as NSString).expandingTildeInPath } ?? ""
            return set.isEmpty ? home.appendingPathComponent(fallback, isDirectory: true) : URL(fileURLWithPath: set, isDirectory: true)
        }
        switch agent {
        case .claude:
            let file = environment["CLAUDE_CONFIG_DIR"].map { _ in folder("CLAUDE_CONFIG_DIR", ".claude") }
                .map { $0.appendingPathComponent(".claude.json") } ?? home.appendingPathComponent(".claude.json")
            return fromJSON(try? Data(contentsOf: file))
        case .kiro:
            return fromJSON(try? Data(contentsOf: home.appendingPathComponent(".kiro/settings/mcp.json")))
        case .codex:
            let file = folder("CODEX_HOME", ".codex").appendingPathComponent("config.toml")
            return fromTOML((try? String(contentsOf: file, encoding: .utf8)) ?? "")
        case .antigravity:
            return []
        }
    }

    /// The servers of a JSON config's `mcpServers` (Claude Code's, Kiro's), by name.
    static func fromJSON(_ data: Data?) -> [MCPServer] {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = object["mcpServers"] as? [String: Any] else { return [] }
        return servers.compactMap { name, value in
            guard let entry = value as? [String: Any], entry["disabled"] as? Bool != true else { return nil }
            return server(name, entry)
        }.sorted { $0.name < $1.name }
    }

    static func server(_ name: String, _ entry: [String: Any]) -> MCPServer? {
        let strings = { (key: String) in (entry[key] as? [String: Any] ?? [:]).compactMapValues { $0 as? String } }
        if let command = entry["command"] as? String, !command.isEmpty {
            return MCPServer(name: name, transport: .stdio(command: command, args: entry["args"] as? [String] ?? [], env: strings("env")))
        }
        if let url = entry["url"] as? String, !url.isEmpty {
            let type = (entry["type"] as? String ?? entry["transport"] as? String ?? "").lowercased()
            return MCPServer(name: name, transport: .http(url: url, headers: strings("headers"), sse: type == "sse"))
        }
        return nil
    }

    /// The servers of Codex's `config.toml`: its `[mcp_servers.<name>]` tables (`command`, `args`, `url`, `enabled`) and
    /// their `env` / `http_headers` tables or inline tables. Only what a server's entry is written with; anything else in
    /// the file is skipped.
    static func fromTOML(_ text: String) -> [MCPServer] {
        var entries: [String: [String: Any]] = [:]
        var order: [String] = []
        var table: (name: String, sub: String?)?
        for line in TOMLLine.logicalLines(text) {
            if line.hasPrefix("[") {
                let header = line.firstIndex(of: "]").map { String(line[..<$0]) } ?? line
                let path = TOMLLine.keyPath(String(header.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))))
                guard path.count >= 2, path[0] == "mcp_servers" else { table = nil; continue }
                table = (path[1], path.count > 2 ? path[2] : nil)
                if entries[path[1]] == nil { entries[path[1]] = [:]; order.append(path[1]) }
                continue
            }
            guard let current = table, let (key, value) = TOMLLine.pair(line) else { continue }
            if let sub = current.sub {
                var map = entries[current.name]?[sub] as? [String: Any] ?? [:]
                map[key] = value
                entries[current.name]?[sub] = map
            } else {
                entries[current.name]?[key] = value
            }
        }
        return order.compactMap { name in
            guard var entry = entries[name], entry["enabled"] as? Bool != false else { return nil }
            if let headers = entry["http_headers"] { entry["headers"] = headers }
            return server(name, entry)
        }.sorted { $0.name < $1.name }
    }
}

/// The few TOML forms an MCP server's entry is written with: `key = "string"`, `key = 'literal'`, `key = true`,
/// `key = ["a", "b"]` and `key = { a = "b" }` on one line.
enum TOMLLine {
    /// The file's lines without blanks and comment lines, a value whose `[` or `{` closes on a later line (an array
    /// written one item a line) joined into one.
    static func logicalLines(_ text: String) -> [String] {
        var lines: [String] = [], pending = "", multiline: String?
        for raw in text.components(separatedBy: .newlines) {
            // A multi-line string (`"""`, `'''`) is skipped, its key with it: no server's entry is written so.
            if let open = multiline { if raw.contains(open) { multiline = nil }; continue }
            if let open = ["\"\"\"", "'''"].first(where: { raw.components(separatedBy: $0).count == 2 }) { multiline = open; continue }
            let line = withoutComment(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            pending += pending.isEmpty ? line : " " + line
            if pending.hasPrefix("[") || depth(pending) <= 0 { lines.append(pending); pending = "" }
        }
        if !pending.isEmpty { lines.append(pending) }
        return lines
    }

    /// How many `[` and `{` outside quotes are still open in `text`.
    static func depth(_ text: String) -> Int {
        var depth = 0, quote: Character?
        for character in text {
            if let open = quote { if character == open { quote = nil }; continue }
            switch character {
            case "\"", "'": quote = character
            case "[", "{": depth += 1
            case "]", "}": depth -= 1
            default: continue
            }
        }
        return depth
    }

    /// `line` up to a `#` outside quotes.
    static func withoutComment(_ line: String) -> String {
        var quote: Character?
        for index in line.indices {
            let character = line[index]
            if let open = quote { if character == open { quote = nil }; continue }
            if character == "\"" || character == "'" { quote = character } else if character == "#" { return String(line[..<index]) }
        }
        return line
    }

    static func keyPath(_ text: String) -> [String] {
        var parts: [String] = []
        var current = "", quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "." {
                parts.append(current.trimmingCharacters(in: .whitespaces)); current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts
    }

    static func pair(_ line: String) -> (String, Any)? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let key = keyPath(String(line[..<equals])).joined(separator: ".")
        var scanner = Substring(line[line.index(after: equals)...])
        guard let value = Self.value(&scanner) else { return nil }
        return (key, value)
    }

    private static func skipSpaces(_ text: inout Substring) {
        while let first = text.first, first == " " || first == "\t" { text.removeFirst() }
    }

    /// A quoted string from `text`, which starts with its `quote`: escapes only in a "basic" one.
    private static func string(_ text: inout Substring, quote first: Character) -> String? {
        text.removeFirst()
        var result = ""
        while let character = text.first {
            text.removeFirst()
            if character == first { return result }
            if character == "\\" && first == "\"", let escaped = text.first {
                text.removeFirst()
                result.append(["n": "\n", "t": "\t"][escaped] ?? escaped)
            } else {
                result.append(character)
            }
        }
        return nil
    }

    static func value(_ text: inout Substring) -> Any? {
        skipSpaces(&text)
        guard let first = text.first else { return nil }
        switch first {
        case "\"", "'":
            return string(&text, quote: first)
        case "[":
            text.removeFirst()
            var items: [Any] = []
            while true {
                skipSpaces(&text)
                if text.first == "]" { text.removeFirst(); return items }
                guard let item = value(&text) else { return nil }
                items.append(item)
                skipSpaces(&text)
                if text.first == "," { text.removeFirst() }
            }
        case "{":
            text.removeFirst()
            var table: [String: Any] = [:]
            while true {
                skipSpaces(&text)
                if text.first == "}" { text.removeFirst(); return table }
                guard let equals = text.firstIndex(of: "=") else { return nil }
                let key = keyPath(String(text[..<equals])).joined(separator: ".")
                text = text[text.index(after: equals)...]
                guard let item = value(&text) else { return nil }
                table[key] = item
                skipSpaces(&text)
                if text.first == "," { text.removeFirst() }
            }
        default:
            let word = text.prefix { !",]} \t#".contains($0) }
            guard !word.isEmpty else { return nil }
            text = text.dropFirst(word.count)
            if word == "true" { return true }
            if word == "false" { return false }
            return Double(word) ?? String(word)
        }
    }
}

extension ClaudeSessionStore {
    /// The MCP servers' files (`SessionBackend.mcpFiles`): each written readable by the user only (a server's `env` may
    /// hold a key), one with no content removed.
    public func writeMCP(_ files: [SessionFile]) throws {
        for file in files {
            let url = directory.appendingPathComponent(file.path)
            guard !file.content.isEmpty else { try? FileManager.default.removeItem(at: url); continue }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? Data(contentsOf: url)) != Data(file.content.utf8) { try Data(file.content.utf8).write(to: url, options: .atomic) }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}

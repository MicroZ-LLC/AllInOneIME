import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A tool an MCP server offers (`tools/list`): read-only only when the server says so (its `annotations.readOnlyHint`
/// is true, MCP 2025-03-26 on); one that doesn't say counts as one that changes things, and the session never gets it.
public struct MCPTool: Equatable, Sendable {
    public var name: String
    public var readOnly: Bool

    public init(name: String, readOnly: Bool) {
        self.name = name
        self.readOnly = readOnly
    }

    init?(_ object: Any) {
        guard let tool = object as? [String: Any], let name = tool["name"] as? String, !name.isEmpty else { return nil }
        let annotations = tool["annotations"] as? [String: Any]
        self.init(name: name, readOnly: annotations?["readOnlyHint"] as? Bool == true)
    }
}

public enum MCPToolListError: Error, Equatable, Sendable {
    /// Its program isn't on the PATH.
    case notFound(String)
    /// It ended, or said nothing usable, before it listed its tools.
    case failed
    /// No list within the time given.
    case timedOut
    /// It wants a sign-in (HTTP 401/403): the agent signs in to it, we don't.
    case signInNeeded
    /// The old HTTP+SSE transport: not listed here.
    case unsupported
}

/// Lists an MCP server's tools as Settings → AI shows them (`SessionMCP`): it is started (stdio, through the core's
/// `ProcessLauncher`, with the login shell's environment and the server's own, as its agent would) or asked (HTTP),
/// `initialize`, then `tools/list` (every page), then stopped. Never while typing; nothing it lists is called.
public enum MCPToolList {
    public static let timeout: Duration = .seconds(20)
    /// No cookies kept, and no redirect to another host: the headers of the agent's config (a token) go to the server's
    /// own address only.
    public static let session = URLSession(configuration: .ephemeral, delegate: SameHostRedirects(), delegateQueue: nil)
    static let protocolVersion = "2025-06-18"

    public static func list(_ server: MCPServer, processes: any ProcessLauncher = Platform.current.processes,
                            session: URLSession = MCPToolList.session, timeout: Duration = MCPToolList.timeout) async throws -> [MCPTool] {
        switch server.transport {
        case let .stdio(command, args, env):
            return try await stdio(command: command, args: args, env: env, processes: processes, timeout: timeout)
        case let .http(url, headers, sse):
            guard !sse, let url = URL(string: url) else { throw MCPToolListError.unsupported }
            return try await http(url: url, headers: headers, session: session, timeout: timeout)
        }
    }

    static func request(_ id: Int, _ method: String, _ params: [String: Any] = [:]) -> Data {
        let object: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        // Its keys in one order every time (`method` before `params`), whatever the dictionary's.
        return (try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys)) ?? Data()
    }

    static let initialized = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)

    static var initializeParams: [String: Any] {
        ["protocolVersion": protocolVersion, "capabilities": [String: Any](),
         "clientInfo": ["name": "allinoneime", "version": "1"]]
    }

    // MARK: - stdio

    private static func stdio(command: String, args: [String], env: [String: String], processes: any ProcessLauncher,
                              timeout: Duration) async throws -> [MCPTool] {
        // As its agent starts it: the input method's environment (HOME, TMPDIR …) with the login shell's PATH and
        // variables, then the server's own.
        let environment = processes.environment.merging(processes.loginEnvironment) { $1 }.merging(env) { $1 }
        let executable = command.contains("/") ? URL(fileURLWithPath: (command as NSString).expandingTildeInPath)
            : CommandRunner.resolve(command, path: environment["PATH"])
        guard let executable, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw MCPToolListError.notFound(command)
        }
        let input = Pipe(), output = Pipe()
        let reader = MCPLineReader()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; reader.finish() } else { reader.add(data) }
        }
        let process: any LaunchedProcess
        do {
            process = try processes.launch(LaunchSpec(executable: executable, arguments: args, environment: environment,
                                                      standardInput: .pipe(input), standardOutput: .pipe(output),
                                                      standardError: .null))
        } catch {
            throw MCPToolListError.failed
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            process.kill()
        }
        let send: @Sendable (Data) -> Void = { line in try? input.fileHandleForWriting.write(contentsOf: line + Data("\n".utf8)) }
        return try await withTimeout(timeout) {
            try await converse(send: send, answers: reader.lines)
        }
    }

    /// The conversation over lines: `initialize`, then `tools/list` until it has no `nextCursor`.
    static func converse(send: @Sendable (Data) -> Void, answers: AsyncStream<Data>) async throws -> [MCPTool] {
        send(request(1, "initialize", initializeParams))
        var tools: [MCPTool] = []
        var next = 2, awaited = 1
        for await line in answers {
            // Only the answer to the request sent last: a notification, or a request of the server's own (`ping`,
            // `roots/list`: a `method`, an id of its own), isn't one.
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], message["method"] == nil,
                  let id = message["id"] as? Int, id == awaited else { continue }
            if message["error"] != nil { throw MCPToolListError.failed }
            let result = message["result"] as? [String: Any] ?? [:]
            if id == 1 {
                send(initialized)
            } else {
                tools += (result["tools"] as? [Any] ?? []).compactMap(MCPTool.init)
                guard let cursor = result["nextCursor"] as? String, !cursor.isEmpty else { return tools }
            }
            let cursor = id == 1 ? nil : result["nextCursor"] as? String
            send(request(next, "tools/list", cursor.map { ["cursor": $0] } ?? [:]))
            (awaited, next) = (next, next + 1)
        }
        throw MCPToolListError.failed
    }

    // MARK: - HTTP (Streamable HTTP)

    private static func http(url: URL, headers: [String: String], session: URLSession, timeout: Duration) async throws -> [MCPTool] {
        try await withTimeout(timeout) {
            var sessionID: String?
            func post(_ body: Data) async throws -> [String: Any]? {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
                for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
                if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401 || status == 403 { throw MCPToolListError.signInNeeded }
                guard (200..<300).contains(status) else { throw MCPToolListError.failed }
                if let id = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = id }
                return message(in: data)
            }
            guard let opened = try await post(request(1, "initialize", initializeParams)), opened["result"] != nil else {
                throw MCPToolListError.failed
            }
            _ = try? await post(initialized)
            var tools: [MCPTool] = [], cursor: String?, id = 2
            repeat {
                guard let answer = try await post(request(id, "tools/list", cursor.map { ["cursor": $0] } ?? [:])),
                      let result = answer["result"] as? [String: Any] else { throw MCPToolListError.failed }
                tools += (result["tools"] as? [Any] ?? []).compactMap(MCPTool.init)
                cursor = (result["nextCursor"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                id += 1
            } while cursor != nil && id < 50
            return tools
        }
    }

    /// The JSON-RPC answer in a response: its body, or the last `data:` event of a server-sent events body.
    static func message(in data: Data) -> [String: Any]? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return object }
        let events = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
            .filter { $0.hasPrefix("data:") }.map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        return events.reversed().lazy.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }.first
    }

    static func withTimeout<T: Sendable>(_ timeout: Duration, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw MCPToolListError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw MCPToolListError.failed }
            return first
        }
    }
}

/// A server's standard output in lines (JSON-RPC messages, one per line).
final class MCPLineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let continuation: AsyncStream<Data>.Continuation
    let lines: AsyncStream<Data>

    init() { (lines, continuation) = AsyncStream<Data>.makeStream() }

    func add(_ data: Data) {
        lock.lock()
        buffer += data
        var found: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            found.append(buffer[buffer.startIndex..<newline])
            buffer = Data(buffer[buffer.index(after: newline)...])
        }
        lock.unlock()
        for line in found { continuation.yield(line) }
    }

    func finish() { continuation.finish() }
}

/// Follows a redirect only to the same host (`MCPToolList.session`).
final class SameHostRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        request.url?.host == task.originalRequest?.url?.host ? request : nil
    }
}

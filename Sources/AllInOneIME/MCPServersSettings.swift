import AllInOneIMECore
import SwiftUI

/// Settings → AI's MCP servers (owner, 0.7.5), under a CLI chosen as the AI: the servers in that agent's own config
/// (`MCPServers.found`), each with a checkbox, none checked at first. A server checked has its tools listed
/// (`MCPToolList`, as it is checked and each time the page shows) and only its read-only ones saved (`Config.sessionMCP`),
/// the only ones its session may call; the session starts again with the next question. Their config is only read.
struct MCPServersSection: View {
    @ObservedObject var model: SettingsModel
    let agent: SessionAgent
    @StateObject private var lister = MCPServerLister.preview ?? MCPServerLister()

    var body: some View {
        Section {
            if !MCPServers.supports(agent) {
                Text(tr("\(agent.displayName) 的会话暂时不能用 MCP 服务器。", "\(agent.displayName)'s session can't use MCP servers yet."))
                    .font(.callout).foregroundStyle(.secondary)
            } else if lister.servers.isEmpty {
                Text(lister.loaded ? tr("\(agent.displayName) 的设置里没有 MCP 服务器。", "No MCP servers in \(agent.displayName)'s settings.") : "…")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(lister.servers, id: \.name) { server in
                    Toggle(isOn: checked(server)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                            Text(lister.note(server.name, checked: checkedTools[server.name] != nil))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            SectionTitle(tr("MCP 服务器", "MCP Servers"), icon: CommandIcons.plugins)
        } footer: {
            Text(tr("勾上的服务器，AI 对话只能用它的只读工具（搜索、读取），发送、修改的工具一律不给。服务器取自 \(agent.displayName) 自己的设置。",
                    "A checked server gives the AI chat its read-only tools only (search, read), never one that sends or changes anything. The servers come from \(agent.displayName)'s own settings."))
                .font(.callout).foregroundStyle(.secondary)
        }
        .disabled(!model.canSave)
        .task(id: agent) {
            guard MCPServerLister.preview == nil else { return }
            await lister.load(agent, refreshing: Array(checkedTools.keys)) { save($0, $1) }
        }
    }

    private var checkedTools: [String: [String]] { model.config.sessionMCP[agent.rawValue] ?? [:] }

    private func checked(_ server: MCPServer) -> Binding<Bool> {
        Binding(get: { checkedTools[server.name] != nil }, set: { on in
            if on {
                save(server.name, [])
                Task { await lister.list(server) { save($0, $1) } }
            } else {
                save(server.name, nil)
            }
        })
    }

    /// `tools` (read-only) saved for `name`, nil: unchecked. The session's process ends: the next question starts it with
    /// the servers as checked now.
    private func save(_ name: String, _ tools: [String]?) {
        var servers = checkedTools
        guard servers[name] != tools else { return }
        servers[name] = tools
        model.config.sessionMCP[agent.rawValue] = servers.isEmpty ? nil : servers
        model.save()
        if model.persists { ClaudeSessionMac.managers[agent]?.stop() }
    }
}

/// The servers found and what listing their tools said, for `MCPServersSection`; the work off the main thread.
@MainActor
final class MCPServerLister: ObservableObject {
    enum Listing: Equatable {
        case listing
        case listed(readOnly: Int, total: Int)
        case failed(MCPToolListError)
    }

    @Published private(set) var servers: [MCPServer] = []
    @Published private(set) var loaded = false
    @Published private(set) var listings: [String: Listing] = [:]

    /// What the page shows instead of this Mac's servers (the README's images, `SettingsPageImages`); nil: this Mac's.
    static var preview: MCPServerLister?

    /// Three servers as an agent's config might have them: one checked with its tools listed, one checked with none
    /// read-only, one not checked.
    static var sample: MCPServerLister {
        let lister = MCPServerLister()
        lister.servers = ["github", "linear", "slack"].map { MCPServer(name: $0, transport: .stdio(command: "npx", args: [], env: [:])) }
        lister.loaded = true
        lister.listings = ["github": .listed(readOnly: 12, total: 26), "linear": .listed(readOnly: 0, total: 4)]
        return lister
    }

    /// The servers in `agent`'s config, then the tools of the ones checked (`refreshing`) listed again.
    func load(_ agent: SessionAgent, refreshing: [String], save: @escaping (String, [String]) -> Void) async {
        guard MCPServers.supports(agent) else { return }
        let environment = ClaudeSessionMac.environment(agent)
        servers = await Task.detached { MCPServers.found(agent, environment: environment) }.value
        loaded = true
        for server in servers where refreshing.contains(server.name) { await list(server, save: save) }
    }

    /// Lists `server`'s tools; its read-only ones go to `save`.
    func list(_ server: MCPServer, save: @escaping (String, [String]) -> Void) async {
        listings[server.name] = .listing
        do {
            let tools = try await Task.detached { try await MCPToolList.list(server) }.value
            let readOnly = tools.filter(\.readOnly).map(\.name)
            listings[server.name] = .listed(readOnly: readOnly.count, total: tools.count)
            save(server.name, readOnly)
        } catch {
            listings[server.name] = .failed(error as? MCPToolListError ?? .failed)
        }
    }

    /// What its row says under its name.
    func note(_ name: String, checked: Bool) -> String {
        switch listings[name] {
        case nil: return checked ? "…" : tr("勾上后列出它的工具", "Check it to list its tools")
        case .listing: return tr("正在列出工具…", "Listing its tools…")
        case let .listed(readOnly, total) where readOnly == 0:
            return tr("\(total) 个工具都不是只读的，不会给 AI 对话", "None of its \(total) tools is read-only: none goes to the AI chat")
        case let .listed(readOnly, total): return tr("\(readOnly) 个只读工具（共 \(total) 个）", "\(readOnly) read-only tools (of \(total))")
        case let .failed(error): return Self.describe(error)
        }
    }

    static func describe(_ error: MCPToolListError) -> String {
        switch error {
        case let .notFound(command): return tr("找不到 \(command)", "\(command) not found")
        case .timedOut: return tr("列出工具超时", "Listing its tools timed out")
        case .signInNeeded: return tr("它要先登录：在 agent 里登录后再试", "It needs a sign-in: sign in from the agent, then try again")
        case .unsupported: return tr("这种连接方式（SSE）暂不支持", "This connection (SSE) isn't supported yet")
        case .failed: return tr("没能列出它的工具", "Couldn't list its tools")
        }
    }
}

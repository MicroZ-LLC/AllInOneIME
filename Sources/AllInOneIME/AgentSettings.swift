import AllInOneIMECore
import AllInOneIMEMac
import SwiftUI

/// Settings → Commands → `@agent`: the coding agent it hands the text to (`Config.agent`, `AgentKind`), whether that one
/// is on this Mac and how it starts in Terminal, and its own settings (Claude Code's background tasks, the custom agent's
/// command). Another agent's own settings show too while one is set otherwise than its default.
struct AgentSettingsPage: View {
    @ObservedObject var model: SettingsModel
    /// The custom agent's command as typed (`Config.agentCommand` follows it, split into words).
    @State private var commandLine = ""

    var body: some View {
        Section {
            // One not on this Mac can still be picked: `@agent` isn't offered until it's installed.
            Picker(selection: $model.config.agent) {
                ForEach(AgentKind.allCases, id: \.self) { kind in
                    Text(title(kind) + (installed(kind) ? "" : tr("（未安装）", " (not installed)"))).tag(kind)
                }
            } label: {
                titled(model.triggered(tr("@agent 交给", "@agent hands it to")),
                       tr("在终端打开它，你打的字是第一句话。", "It opens in Terminal with what you typed as its first message."))
            }
            .settingsRow(.agent, shown: model.spot)
            status(model.config.agent)
            if model.config.agent == .claude || !model.config.claudeInBackground { claudeSettings }
            if model.config.agent == .custom || !model.config.agentCommand.isEmpty { customSettings }
        } header: {
            SectionTitle(model.triggered(tr("Agent（@agent）", "Agent (@agent)")), icon: CommandIcons.agent)
        }
        .disabled(!model.canSave)
    }

    /// Whether the agent is on this Mac, and what runs in Terminal (the text typed is its last argument).
    @ViewBuilder private func status(_ kind: AgentKind) -> some View {
        let arguments = kind.terminalArguments(custom: model.config.agentCommand)
        LabeledContent {
            if arguments == nil {
                Text(tr("还没有命令", "No command yet")).foregroundStyle(.secondary)
            } else if installed(kind) {
                Label(tr("已安装", "Installed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Label(tr("未安装", "Not installed"), systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            }
        } label: {
            titled(tr("在这台 Mac 上", "On this Mac"),
                   arguments.map { tr("在终端里运行：", "Runs in Terminal: ") + CustomCommand.commandLine($0) + tr(" <你打的字>", " <what you typed>") }
                       ?? tr("在下面写上命令。", "Write its command below."))
        }
    }

    /// Claude Code's own: its background tasks (`claude --bg`), which `@tasks` and the menu bar panel list.
    @ViewBuilder private var claudeSettings: some View {
        Toggle(isOn: $model.config.claudeInBackground) {
            titled(tr("Claude Code 在后台运行，做完通知我", "Claude Code runs in the background and notifies me"),
                   model.triggered(tr("做完弹通知，点通知在终端里接着聊；@tasks 和菜单栏面板列出这些任务。",
                      "A notification says when it's done and opens it in Terminal; @tasks and the menu bar panel list these tasks.")))
        }
    }

    /// The custom agent's command: words as a custom terminal command's, the text typed added as the last argument.
    @ViewBuilder private var customSettings: some View {
        TextField(text: $commandLine, prompt: Text(tr("例如 ", "e.g. ") + "muse --")) {
            titled(tr("命令", "Command"), tr("你打的字加在最后，作为最后一个参数。", "What you typed is added as its last argument."))
        }
            .onAppear { commandLine = CustomCommand.commandLine(model.config.agentCommand) }
            .onChange(of: commandLine) {
                // An unclosed quote while typing keeps the last command that reads.
                guard let argv = CustomCommand.arguments(fromCommandLine: commandLine) else { return }
                if argv != model.config.agentCommand { model.config.agentCommand = argv }
            }
            // A command written elsewhere (by hand, read again) is shown; one typed here stays as typed.
            .onChange(of: model.config.agentCommand) {
                if CustomCommand.arguments(fromCommandLine: commandLine) != model.config.agentCommand {
                    commandLine = CustomCommand.commandLine(model.config.agentCommand)
                }
            }
    }

    private func installed(_ kind: AgentKind) -> Bool { AgentAvailability.installed(kind, custom: model.config.agentCommand) }

    /// An agent's name in the picker and its section's title: a custom one without a command is "自定义" / "Custom".
    private func title(_ kind: AgentKind) -> String {
        guard kind == .custom else { return kind.displayName() }
        return kind.program(custom: model.config.agentCommand) == nil
            ? tr("自定义", "Custom") : tr("自定义：", "Custom: ") + kind.displayName(custom: model.config.agentCommand)
    }

    /// A row's title with a short explanation under it, as System Settings shows them.
    private func titled(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

}

/// Whether an agent's program is on this Mac, for `@agent`'s settings and the `@question` hand-off: each program looked up
/// once (the first lookup asks the login shell for its PATH), again once the settings window opens. Main thread only.
enum AgentAvailability {
    private static var found: [String: Bool] = [:]

    /// Looked up again from now on (the Settings window opens).
    static func forget() { found = [:] }

    /// The self-test's: `program` taken as installed or not, until `forget`.
    static func pretend(_ program: String, installed: Bool) { found[program] = installed }

    static func installed(_ kind: AgentKind, custom: [String]) -> Bool {
        kind.program(custom: custom).map(installed(program:)) ?? false
    }

    /// Whether `program` (`AgentKind.program`) is on this Mac: Claude Code also where Terminal finds it.
    static func installed(program: String) -> Bool {
        if let known = found[program] { return known }
        let installed = (program == "claude" && TerminalLauncher.claudePath != nil)
            || CommandRunner.isInstalled(program, path: ShellEnvironment.current["PATH"])
        found[program] = installed
        return installed
    }
}

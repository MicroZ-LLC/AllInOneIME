import AllInOneIMECore
import SwiftUI

// Settings → Custom Commands, the Suggestions type (spec Suggestions v1, decision 24): a custom command that is a
// suggestion source. Its form in the command editor (prefix, program, look up as you type, refresh, what a row inserts),
// how it is doing (as a plugin's completion source says it in Settings → Plugins) and Refresh Now.

extension SettingsModel {
    /// "Refresh Now" for the custom command named `name`'s source: its program run again at once, paused or not.
    func refreshNow(command name: String) {
        guard store.persists else { return }
        SuggestionsShared.refreshNow(plugin: CompletionSourceKey.customCommands, source: name.lowercased())
    }

    /// A custom command saved or deleted that is (or was) a suggestion source: the field being typed in takes it at once
    /// (one saved runs its program again, its edit being new; one deleted or renamed is forgotten, its cached list
    /// deleted).
    func commandSourceChanged(saved: CustomCommand?, was: CustomCommand?) {
        guard store.persists, saved?.type == .suggestions || was?.type == .suggestions else { return }
        if let saved, saved.type == .suggestions {
            refreshNow(command: saved.name)
        } else {
            SuggestionsShared.settingsChanged()
        }
    }
}

/// The editor's Insert: one of the presets, or the templates written under Advanced.
enum InsertChoice: Hashable {
    case preset(CustomCommand.InsertPreset)
    case own
}

/// The Suggestions type's part of the command editor: the prefix, the program (as a command line), Look up as you type
/// (from the Nth character), how often the list is run again, how long it may run, and what a row inserts (a preset, or
/// under Advanced the templates as config.json has them).
struct SuggestionSourceForm: View {
    @Binding var prefix: String
    @Binding var commandLine: String
    @Binding var query: Bool
    @Binding var queryMinChars: Int
    @Binding var refresh: String
    @Binding var timeout: Double
    /// `insert` as JSON text (empty: the default, the match alone).
    @Binding var insert: String
    let missingProgram: String?
    @State private var advanced = false

    /// How often the list may be run again (`refresh`): from 5 minutes to 7 days, and what the command has if it's
    /// another.
    private var refreshChoices: [String] {
        let choices = ["5m", "15m", "30m", "1h", "6h", "12h", "1d", "7d"]
        return choices.contains(refresh) ? choices : choices + [refresh]
    }

    var body: some View {
        TextField(tr("前缀", "Prefix"), text: $prefix, prompt: Text("JIRA-"))
            .font(.body.monospaced())
        TextField(tr("程序", "Program"), text: $commandLine, prompt: Text("~/bin/jira-list"))
            .font(.body.monospaced())
        Text(tr("不带参数运行时打印全部条目：每行「匹配⇥标题⇥网址」（标题、网址可以不写），或者插件那样的 JSON。打了前缀，光标下面就列出对得上的行，Tab 插入。不经过 shell（要 shell 就写 zsh -c …）；参数里有空格时用引号。",
                "Run with no input, it prints every item: a line each, \"match⇥title⇥url\" (title and url optional), or the plugins' JSON. Type the prefix and the rows that match show under the caret; Tab inserts. Never through a shell (for one, write zsh -c …); quote arguments with spaces."))
            .font(.caption).foregroundStyle(.secondary)
        Toggle(tr("边打边查（把前缀后面打的字交给程序）", "Look up as you type (what you type after the prefix goes to the program)"), isOn: $query)
        if query {
            Stepper(value: $queryMinChars, in: 1...32) {
                Text(tr("从第 \(queryMinChars) 个字开始查", "From character \(queryMinChars) on"))
            }
            Text(tr("前缀后面打的字作为一个参数给程序：写在命令里 {input} 的位置，没写就放在最后。",
                    "What you type after the prefix goes to the program as one argument: where {input} is in the command, else last."))
                .font(.caption).foregroundStyle(.secondary)
        }
        Picker(tr("刷新", "Refresh"), selection: $refresh) {
            ForEach(refreshChoices, id: \.self) { choice in
                Text(Self.every(choice)).tag(choice)
            }
        }
        Stepper(value: $timeout, in: 1...PluginManifest.maxTimeout, step: 1) {
            Text(tr("最多运行 \(Int(timeout)) 秒", "Stop after \(Int(timeout)) s"))
        }
        Picker(tr("插入", "Insert"), selection: insertChoice) {
            Text(tr("只插入匹配的部分", "Just the match")).tag(InsertChoice.preset(.match))
            Text(tr("连同标题", "With its title")).tag(InsertChoice.preset(.title))
            Text(tr("连同标题和链接（聊天 App 里）", "With title and link (in chat apps)")).tag(InsertChoice.preset(.titleAndLink))
            if insertChoice.wrappedValue == .own { Text(tr("自己写的模板", "Your own templates")).tag(InsertChoice.own) }
        }
        DisclosureGroup(tr("高级", "Advanced"), isExpanded: $advanced) {
            PlainTextEditor(text: $insert, label: tr("插入模板", "Insert templates"))
                .frame(minHeight: 70)
            Text(tr("和插件的 insert 一样：default（一般 App）、chat（聊天 App 和浏览器）、terminal（终端和代码编辑器，只插入匹配）；每个是一个模板或依次尝试的一组，变量有 {match} {arg} {title} {url}。",
                    "As a plugin's insert: default (ordinary apps), chat (chat apps and browsers), terminal (terminals and code editors: the match only); each a template or a list tried in turn, with {match} {arg} {title} {url}."))
                .font(.caption).foregroundStyle(.secondary)
        }
        if let missingProgram {
            Label(tr("这台 Mac 上找不到 \(missingProgram)：装好之前，这个来源会显示出错。",
                     "\(missingProgram) isn't on this Mac: until it is, this source shows an error."),
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    /// The preset the templates are, or the user's own; a preset picked writes its templates.
    private var insertChoice: Binding<InsertChoice> {
        Binding(get: {
            guard case let .some(parsed) = Self.parse(insert) else { return .own }
            return CustomCommand.InsertPreset(parsed).map(InsertChoice.preset) ?? .own
        }, set: { choice in
            guard case let .preset(preset) = choice else { return }
            insert = Self.text(preset.insert ?? CustomCommand.InsertPreset.defaultInsert)
        })
    }

    /// "Every 15 min", "Every 1 h".
    static func every(_ refresh: String) -> String {
        let seconds = (try? CustomCommand(name: "x", type: .suggestions, prefix: "x", refresh: refresh).suggestionSource?.get())?.refresh
        return seconds.map { tr("每 \(CompletionSource.interval($0))", "Every \(CompletionSource.interval($0))") } ?? refresh
    }

    /// `text` read as `insert`: `.some(nil)` when it is empty (the default's), nil when it isn't JSON.
    static func parse(_ text: String) -> AIConfig.JSONValue?? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .some(nil) }
        guard let value = try? JSONDecoder().decode(AIConfig.JSONValue.self, from: Data(trimmed.utf8)) else { return nil }
        return .some(value)
    }

    /// `insert` as the editor shows it: JSON, its keys sorted, indented.
    static func text(_ insert: AIConfig.JSONValue?) -> String {
        guard let insert, let object = try? JSONSerialization.jsonObject(with: Data(insert.json.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension CustomCommand.InsertPreset {
    /// The default's templates as config.json writes them, for the editor to show (`insert` is nil for it).
    static let defaultInsert: AIConfig.JSONValue = .object(["default": .string("{arg}")])
}

/// How a custom suggestion source is doing, under it in the command editor and the command list: that it came from
/// another Mac and runs nothing until allowed, why it isn't used, that Suggestions are off, or its items, when it last
/// updated and its last error; read again whenever suggestions report a change. With `refresh`, Refresh Now beside it
/// (not for one awaiting confirmation: nothing of it runs).
struct CommandSourceStatus: View {
    let command: CustomCommand
    let config: Config
    var refresh: (() -> Void)?
    @State private var status: CompletionSourceStatus?

    var body: some View {
        if let state = command.suggestionsState(config, status: status) {
            HStack(alignment: .firstTextBaseline) {
                if state.problem {
                    Label(state.text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    Text(state.text).foregroundStyle(.secondary)
                }
                Spacer()
                if let refresh, command.isValid, !config.awaitsConfirmation(command) { Button(tr("立即刷新", "Refresh Now"), action: refresh) }
            }
            .font(.caption).fixedSize(horizontal: false, vertical: true)
            .onAppear(perform: read)
            .onReceive(NotificationCenter.default.publisher(for: .allInOneIMESuggestionsChanged)) { _ in read() }
        }
    }

    private func read() { status = SuggestionsShared.store.status(CompletionSourceKey(command: command.name)) }
}

import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import SwiftUI

/// A custom @ command being added (`index` nil) or edited in the settings: the place the list showed it at, and the
/// command as it was then.
struct CommandEdit: Identifiable {
    let id = UUID()
    var index: Int?
    var command: CustomCommand

    /// The name of the command being edited (nil: one being added). The edit is saved by it, never by `index`: sync
    /// through iCloud may change the list while the editor is open (`SettingsModel.saveCommand`).
    var original: String? { index == nil ? nil : command.name }
}

/// The form for one custom @ command: its name, what it does (an instruction for the AI, a program
/// to run, a program in Terminal, a web page to open, a text to insert, or suggestions from a program as a prefix is
/// typed) and how, its icon and color in the command list, and a Test run on a sample (`CommandTrial`). Saving hands
/// the finished definition back.
struct CommandEditor: View {
    let original: CommandEdit
    /// The other custom commands, the installed plugins and the custom commands a later version wrote
    /// (`Config.unreadCustomCommandNames`): their names are taken.
    let others: [CustomCommand]
    let plugins: [String]
    let unread: [String]
    /// The settings as they are (the magic key, Suggestions' switch): what a suggestion source says of itself.
    let config: Config
    /// A suggestion source's Refresh Now, by its name.
    let refreshNow: (String) -> Void
    /// Saves the definition; false when it wasn't (another command has its name by now): the editor stays open.
    let onSave: (CustomCommand) -> Bool
    @Environment(\.dismiss) private var dismiss
    /// A name the save found taken (a command of that name came in from another Mac while the editor was open).
    @State private var takenOnSave: String?

    @State private var name: String
    @State private var type: CustomCommand.CommandType
    @State private var summary: String
    @State private var prompt: String
    /// `argv` as one line: `python3 -c {input}`.
    @State private var commandLine: String
    /// `run`: the text goes to standard input instead of `{input}`.
    @State private var useStdin: Bool
    @State private var latin: Bool
    @State private var timeout: Double
    /// `link`: the web address, with `{input}`.
    @State private var url: String
    /// `snippet`: the text to insert, with its placeholders.
    @State private var text: String
    /// The "Insert Placeholder" menu puts its placeholder in at the text's caret.
    @State private var placeholderTarget = PlainTextEditor.Inserter()
    /// `suggestions`: its keys as the form has them (`SuggestionSourceForm`); `insert` as JSON text (empty: the default).
    @State private var prefix: String
    @State private var query: Bool
    @State private var queryMinChars: Int
    @State private var refresh: String
    @State private var insert: String
    /// The program of the command line isn't on this Mac (looked up in the background).
    @State private var missingProgram: String?
    /// Its icon in the command list: an SF Symbol's name or one emoji; nil, Default (its kind's: `IconToken.custom`).
    @State private var icon: String?
    /// Its icon's color: a named one (`IconToken.Color.names`, or one config.json has otherwise, kept); nil, Default.
    @State private var color: String?
    @State private var pickingIcon = false
    /// The Test run's sample (the text after the command, or the selection), and what the run gave.
    @State private var sample: String
    @State private var trial: Trial?
    @State private var trialTask: Task<Void, Never>?
    /// An AI instruction's Test run, asked before the sample is sent.
    @State private var confirmingAI = false

    /// A Test run under way, or what it gave: what it would put in, or why it gave nothing.
    enum Trial: Equatable {
        case running
        case passed(String)
        case failed(String)
    }

    /// `sample` and `trial`: a Test run shown as done (the settings' images).
    init(edit: CommandEdit, others: [CustomCommand], plugins: [String] = [], unread: [String] = [], config: Config = .default,
         sample: String = "", trial: Trial? = nil,
         refreshNow: @escaping (String) -> Void = { _ in }, onSave: @escaping (CustomCommand) -> Bool) {
        original = edit
        self.others = others
        self.plugins = plugins
        self.unread = unread
        self.config = config
        self.refreshNow = refreshNow
        self.onSave = onSave
        let c = edit.command
        _name = State(initialValue: c.name)
        _type = State(initialValue: c.type)
        _summary = State(initialValue: c.summary ?? "")
        _prompt = State(initialValue: c.prompt ?? "")
        _commandLine = State(initialValue: CustomCommand.commandLine(c.argv ?? []))
        _useStdin = State(initialValue: c.stdin != nil)
        _latin = State(initialValue: c.typesLatin)
        _timeout = State(initialValue: c.timeout)
        _url = State(initialValue: c.url ?? "")
        _text = State(initialValue: c.text ?? "")
        _prefix = State(initialValue: c.prefix ?? "")
        _query = State(initialValue: c.query ?? false)
        _queryMinChars = State(initialValue: c.queryMinChars ?? 3)
        _refresh = State(initialValue: c.refresh ?? "1h")
        _insert = State(initialValue: SuggestionSourceForm.text(c.insert))
        _icon = State(initialValue: c.icon)
        _color = State(initialValue: c.color)
        _sample = State(initialValue: sample)
        _trial = State(initialValue: trial)
    }

    /// The definition as the form has it now (nil: the command line has an open quote), over what the form doesn't show
    /// (config.json's own: a stdin of its own, a source's `minChars` and `compare`) as it was.
    private var draft: CustomCommand? {
        var c = original.command.kept(as: type)
        c.name = name.trimmingCharacters(in: .whitespaces).lowercased()
        let description = summary.trimmingCharacters(in: .whitespaces)
        c.summary = description.isEmpty ? nil : description
        // As config.json spells them; Default leaves the key out.
        c.icon = icon.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        c.color = color
        switch type {
        case .prompt:
            c.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        case .run, .terminal:
            guard let argv = CustomCommand.arguments(fromCommandLine: commandLine) else { return nil }
            c.argv = argv
            if type == .run {
                // A stdin the switch can't show ("{input}\nquit\n") stays while the switch is on.
                c.stdin = useStdin ? c.stdin ?? CustomCommand.placeholder + "\n" : nil
                c.timeoutSeconds = timeout != CustomCommand.defaultTimeout ? timeout : nil
            }
        case .link:
            c.url = url.trimmingCharacters(in: .whitespaces)
        case .snippet:
            c.text = text
        case .suggestions:
            guard let argv = CustomCommand.arguments(fromCommandLine: commandLine),
                  case let .some(parsed) = SuggestionSourceForm.parse(insert) else { return nil }
            c.argv = argv
            c.prefix = prefix.trimmingCharacters(in: .whitespaces)
            (c.query, c.queryMinChars) = query ? (true, queryMinChars) : (nil, nil)
            c.refresh = refresh != "1h" ? refresh : nil
            c.timeoutSeconds = timeout != CustomCommand.defaultTimeout ? timeout : nil
            // A preset as config.json writes it (the default: none); else the templates as written.
            c.insert = CustomCommand.InsertPreset(parsed).map(\.insert) ?? parsed
        }
        // Stored only when it differs from the type's default (Latin for programs, as typed for the AI and pages).
        if type != .snippet, type != .suggestions {
            c.ascii = latin != CustomCommand.typesLatinByDefault(type) ? latin : nil
        }
        return c
    }

    private var problem: String? {
        if type == .suggestions, SuggestionSourceForm.parse(insert) == nil {
            return tr("插入模板要写成 JSON，比如 {\"default\": \"{arg}\"}", "Write the insert templates as JSON, like {\"default\": \"{arg}\"}")
        }
        guard let draft else { return Self.describe(.unbalancedQuote) }
        if let takenOnSave, draft.name == takenOnSave { return Self.describe(.nameTaken) }
        return draft.problem(among: others, plugins: plugins, unread: unread, trigger: config.commandTrigger).map(Self.describe)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    HStack {
                        TextField(tr("名字", "Name"), text: $name, prompt: Text(tr("只用英文字母，比如 py", "Letters only, e.g. py")))
                        Menu(tr("从例子开始", "Start from an Example")) {
                            ForEach(Self.examples, id: \.name) { example in
                                // With the trigger the Settings window set (`UIText.commandTrigger`).
                                Button(UIText.commandTrigger + example.name + "  " + (example.summary ?? "")) { load(example) }
                            }
                        }
                        .fixedSize()
                    }
                    // Segmented where the six fit (Chinese, in the editor's 560 points), else a menu (English and the
                    // longer languages): never cut off.
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(tr("做什么", "What it does"))
                            Spacer()
                            typePicker.pickerStyle(.segmented).fixedSize()
                        }
                        LabeledContent(tr("做什么", "What it does")) { typePicker.pickerStyle(.menu).fixedSize() }
                    }
                    .onChange(of: type) { latin = CustomCommand.typesLatinByDefault(type) }
                    TextField(tr("说明", "Description"), text: $summary,
                              prompt: Text(tr("命令列表里显示，可以不填", "Shown in the command list (optional)")))
                    // Its icon in the command list, as it will show there.
                    LabeledContent(tr("图标", "Icon")) {
                        Button { pickingIcon = true } label: {
                            HStack(spacing: 6) {
                                IconTile(icon: CandidateView.Icon(IconToken.custom(appearance)))
                                // A symbol by its name (an emoji shows as itself).
                                if icon.map(IconToken.isEmoji) != true {
                                    Text(icon ?? tr("默认", "Default")).foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.borderless)
                        .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
                            CommandIconPicker(icon: $icon, type: type, color: color) { pickingIcon = false }
                        }
                    }
                    LabeledContent(tr("颜色", "Color")) { CommandColorPicker(color: $color, type: type) }
                }

                Section {
                    switch type {
                    case .prompt:
                        TextEditor(text: $prompt)
                            .font(.body)
                            .frame(minHeight: 90)
                        Text(tr("告诉 AI 怎么处理命令后面写的内容，比如「把用户的话写成一条礼貌简短的回复」。回答出现在候选里，⏎ 上屏。",
                                "Tell the AI what to do with the text after the command, e.g. \"Write a short, polite reply to the user's message.\" The answer appears in the candidates; ⏎ inserts it."))
                            .font(.caption).foregroundStyle(.secondary)
                    case .snippet:
                        // Not a TextEditor: macOS's smart quotes and dashes would turn " into “” and -- into — in it.
                        PlainTextEditor(text: $text, inserter: placeholderTarget, label: tr("插入文字", "Insert text"))
                            .frame(minHeight: 90)
                        HStack(alignment: .firstTextBaseline) {
                            Text(tr("命令后面写的内容换掉 {input}；{名字?} 是要填的空，用逗号分开依次填；{{ 写出 {",
                                    "The text after the command replaces {input}; {label?} is a blank, filled in order, separated by commas; write {{ for {"))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Menu(tr("插入占位符", "Insert Placeholder")) {
                                ForEach(Self.placeholders, id: \.self) { placeholder in
                                    Button(placeholder) { placeholderTarget.insert(placeholder, into: $text) }
                                }
                            }
                            .fixedSize()
                        }
                        LabeledContent(tr("预览", "Preview")) {
                            Text(Self.preview(text))
                                .font(.callout)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    case .link:
                        TextField(tr("网址", "Address"), text: $url, prompt: Text("https://www.google.com/search?q={input}"))
                            .font(.body.monospaced())
                        Text(tr("{input} 换成命令后面写的内容（自动编码），放在 ? 后面。按执行键在浏览器打开，不上屏。只能用 https://。",
                                "{input} becomes the text after the command (encoded), after the ?. The action key opens it in the browser; nothing is inserted. https:// only."))
                            .font(.caption).foregroundStyle(.secondary)
                    case .suggestions:
                        SuggestionSourceForm(prefix: $prefix, commandLine: $commandLine, query: $query, queryMinChars: $queryMinChars,
                                             refresh: $refresh, timeout: $timeout, insert: $insert, missingProgram: missingProgram)
                    case .run, .terminal:
                        TextField(tr("命令", "Command"), text: $commandLine, prompt: Text("python3 -c {input}"))
                            .font(.body.monospaced())
                        Text(tr("{input} 换成命令后面写的内容，始终是一个参数，不经过 shell（要 shell 就写 zsh -c {input}）。参数里有空格时用引号。",
                                "{input} becomes the text after the command, always as one argument, never through a shell (for one, write zsh -c {input}). Quote arguments with spaces."))
                            .font(.caption).foregroundStyle(.secondary)
                        if type == .run {
                            Toggle(tr("把内容作为标准输入（命令里不用写 {input}）", "Send the text to standard input (no {input} needed)"),
                                   isOn: $useStdin)
                            Stepper(value: $timeout, in: 1...120, step: 1) {
                                Text(tr("最多运行 \(Int(timeout)) 秒", "Stop after \(Int(timeout)) s"))
                            }
                        }
                        if let missingProgram {
                            Label(tr("这台 Mac 上找不到 \(missingProgram)：装好之前，这个命令不会出现在列表里。",
                                     "\(missingProgram) isn't on this Mac: until it is, the command won't show up in the list."),
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    if type != .snippet, type != .suggestions {
                        Toggle(tr("用英文字母输入（写代码、路径时）", "Type English letters (for code and paths)"), isOn: $latin)
                    }
                }
                if CommandTrial.offered(type) { testRunSection }
                // How the source saved is doing (not a new one's, nor one being turned into another type).
                if original.original != nil, original.command.type == .suggestions, type == .suggestions {
                    Section(tr("状态", "Status")) {
                        CommandSourceStatus(command: original.command, config: config) { refreshNow(original.command.name) }
                    }
                }
                if type == .run || type == .terminal {
                    Text(tr("「运行程序」和「在终端运行」会在你的 Mac 上执行命令：只加你自己写的、信得过的。它们只在你按执行键时运行，密码框里不运行。",
                            "Programs run on your Mac: add only commands you wrote and trust. They run only when you press the action key, never in password fields."))
                        .font(.caption).foregroundStyle(.secondary)
                } else if type == .suggestions {
                    // When it runs, as the settings document says it (Windows' window too).
                    Text(UIText.suggestionsProgramRuns(on: .mac)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                if let problem { Text(problem).foregroundStyle(.red).font(.callout) }
                Spacer()
                Button(tr("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(tr("保存", "Save")) {
                    guard let draft else { return }
                    if onSave(draft) { dismiss() } else { takenOnSave = draft.name }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
            .padding()
        }
        .frame(width: 560, height: 600)
        .task(id: commandLine) { await checkProgram() }
        .task(id: type) { await checkProgram() }
        // What a Test run showed is the command's as it was, on the sample as it was: stopped and gone once what it
        // runs, or the sample, changes (what it gives later isn't shown: `testRun`).
        .onChange(of: runnable) { stopTrial() }
        .onChange(of: sample) { stopTrial() }
        .onDisappear { trialTask?.cancel() }
        .confirmationDialog(CommandTrial.confirmation(config), isPresented: $confirmingAI, titleVisibility: .visible) {
            Button(tr("运行", "Run")) { testRun(confirmed: true) }
            Button(tr("取消", "Cancel"), role: .cancel) {}
        }
    }

    /// What a Test run runs: the command as the form has it, but for what doesn't change a run (its name, description,
    /// icon and color).
    private var runnable: CustomCommand? {
        draft.map { draft in
            var c = draft
            (c.name, c.summary, c.icon, c.color) = ("", nil, nil, nil)
            return c
        }
    }

    /// The icon as the command list will show it: its own, else its kind's.
    private var appearance: CustomCommand { CustomCommand(name: name, type: type, icon: icon, color: color) }

    /// Test run: the sample typed beside it, the command run once on it as the action key would run it, and what it
    /// gives shown here (`CommandTrial`): nothing is inserted, opened or typed in an app. An AI instruction asks first.
    private var testRunSection: some View {
        Section {
            HStack {
                TextField(tr("样例输入", "Sample input"), text: $sample,
                          prompt: Text(tr("命令后面写的内容，或者选中的文字", "The text after the command, or the selection")))
                if trial == .running {
                    ProgressView().controlSize(.small)
                    Button(tr("取消", "Cancel")) { stopTrial() }
                } else {
                    Button(tr("试运行", "Test run")) { testRun() }.disabled(draft == nil)
                }
            }
            switch trial {
            case let .passed(output)?:
                Text(output)
                    .font(.callout.monospaced())
                    .lineLimit(10)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case let .failed(reason)?:
                Label(reason, systemImage: "xmark.octagon.fill")
                    .font(.callout).foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            case .running?, nil:
                EmptyView()
            }
        } footer: {
            Text(tr("用样例运行一次，和按执行键一样（同样的时限；terminal 命令在后台运行，10 秒后停下），结果只显示在这里：不上屏，也不打开。",
                    "Runs it once on the sample, as the action key would (with the same time limit; a terminal command runs in the background and stops after 10 seconds), and shows what it gives here: nothing is inserted or opened."))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Runs the command as the form has it on the sample; an AI instruction only once the user agreed to send it.
    private func testRun(confirmed: Bool = false) {
        guard let command = draft else { return }
        if CommandTrial.asks(command.type), !confirmed {
            confirmingAI = true
            return
        }
        trialTask?.cancel()
        trial = .running
        let (sample, config) = (sample, config)
        trialTask = Task {
            let outcome: Trial
            do {
                outcome = .passed(try await CommandTrial.run(command, sample: sample) { command, sample in
                    try await CommandTrial.ask(command, sample: sample, config: config)
                })
            } catch {
                outcome = .failed(UIText.describe(error))
            }
            // Stopped (what it runs or the sample changed, another run, the editor closed): not the form's now.
            guard !Task.isCancelled else { return }
            trial = outcome
        }
    }

    /// The Test run stopped (a program as Esc stops it), what it showed gone.
    private func stopTrial() {
        trialTask?.cancel()
        trialTask = nil
        trial = nil
    }

    /// "What it does": the six kinds of command (its label for accessibility; the row shows it).
    private var typePicker: some View {
        Picker(tr("做什么", "What it does"), selection: $type) {
            Text(tr("AI 指令", "AI instruction")).tag(CustomCommand.CommandType.prompt)
            Text(tr("运行程序", "Run a program")).tag(CustomCommand.CommandType.run)
            Text(tr("在终端运行", "Run in Terminal")).tag(CustomCommand.CommandType.terminal)
            Text(tr("打开网页", "Open a web page")).tag(CustomCommand.CommandType.link)
            Text(tr("插入文字", "Insert text")).tag(CustomCommand.CommandType.snippet)
            Text(tr("建议", "Suggestions")).tag(CustomCommand.CommandType.suggestions)
        }
        .labelsHidden()
    }

    private func load(_ example: CustomCommand) {
        var taken = Set(others.map { $0.name.lowercased() })
        taken.formUnion(Command.builtins.map(\.name))
        taken.formUnion(plugins)
        taken.formUnion(unread.map { $0.lowercased() })
        name = taken.contains(example.name) ? "" : example.name
        type = example.type
        summary = example.summary ?? ""
        prompt = example.prompt ?? ""
        commandLine = CustomCommand.commandLine(example.argv ?? [])
        useStdin = example.stdin != nil
        latin = example.typesLatin
        timeout = example.timeout
        url = example.url ?? ""
        text = example.text ?? ""
        prefix = example.prefix ?? ""
        query = example.query ?? false
        queryMinChars = example.queryMinChars ?? 3
        refresh = example.refresh ?? "1h"
        insert = SuggestionSourceForm.text(example.insert)
        (icon, color) = (example.icon, example.color)
    }

    /// What the "Insert Placeholder" menu adds (at the text's caret).
    static let placeholders = ["{input}", "{name?}", "{clipboard}", "{selection}", "{date}", "{time}", "{date:EEEE}", "{cursor}"]

    /// The text as it will go in (the core's renderer): the date and time now, the rest as sample values (‹input›,
    /// ‹name›), the caret where `{cursor}` puts it (▏).
    static func preview(_ text: String, now: Date = Date()) -> String {
        let template = SnippetTemplate.parse(text)
        let values = SnippetValues(input: "‹input›", fields: template.fieldLabels.map { "‹\($0)›" }, clipboard: "‹clipboard›",
                                   selection: "‹selection›", now: now, timeZone: .current, locale: Locale(identifier: UIText.language))
        let rendered = template.render(values)
        guard let back = rendered.caretBack else { return rendered.text }
        let units = Array(rendered.text.utf16)
        let at = max(units.count - back, 0)
        return String(decoding: units[..<at], as: UTF16.self) + "▏" + String(decoding: units[at...], as: UTF16.self)
    }

    /// Looks the command line's program up in the user's shell PATH (the first time, the shell is asked).
    private func checkProgram() async {
        guard type == .run || type == .terminal || type == .suggestions, let program = CustomCommand.arguments(fromCommandLine: commandLine)?.first, !program.isEmpty else {
            missingProgram = nil
            return
        }
        let found = await Task.detached { CommandRunner.isInstalled(program, path: ShellEnvironment.current["PATH"]) }.value
        missingProgram = found ? nil : program
    }

    static func describe(_ problem: CustomCommand.Problem) -> String { UIText.describe(problem) }

    /// The menu's starting points.
    static var examples: [CustomCommand] {
        [
            CustomCommand(name: "sig", type: .snippet, summary: tr("邮件签名", "Email signature"),
                          text: "Best,\n" + NSFullUserName() + "\n{cursor}"),
            CustomCommand(name: "meet", type: .snippet, summary: tr("会议链接", "Meeting link"), text: "https://zoom.us/j/1234567890"),
            CustomCommand(name: "today", type: .snippet, summary: tr("今天的日期", "Today's date"), text: "{date}"),
            CustomCommand(name: "ja", type: .prompt, summary: tr("翻译成日语", "Translate to Japanese"),
                          prompt: "Translate the user's text into natural Japanese. Reply with the translation only."),
            // Python and sandboxed JavaScript are built in (@py, @js); Node.js with its files and modules isn't.
            CustomCommand(name: "node", type: .run, summary: tr("运行 Node.js", "Run Node.js"), argv: ["node", "-p", CustomCommand.placeholder]),
            CustomCommand(name: "bc", type: .run, summary: tr("用 bc 计算", "Calculate with bc"), argv: ["bc", "-l"],
                          stdin: CustomCommand.placeholder + "\n"),
            CustomCommand(name: "google", type: .link, summary: tr("用 Google 搜索", "Search with Google"),
                          url: "https://www.google.com/search?q=" + CustomCommand.placeholder),
            CustomCommand(name: "sh", type: .terminal, summary: tr("在终端运行", "Run in Terminal"),
                          argv: ["zsh", "-c", CustomCommand.placeholder + "; exec zsh"]),
            // A program of your own that prints "match⇥title⇥url" lines (docs: custom commands).
            CustomCommand(name: "jira", type: .suggestions, summary: tr("Jira 问题", "Jira issues"), argv: ["~/bin/jira-list"],
                          prefix: "JIRA-", insert: CustomCommand.InsertPreset.title.insert),
        ]
    }
}

/// A text typed exactly as it is: an NSTextView with smart quotes, smart dashes, text replacement and spelling
/// correction off (SwiftUI's TextEditor follows the system's "Use smart quotes and dashes"), so a snippet's JSON or code
/// keeps its `"` and `--`. Plain text, in a monospaced font.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Puts text in at the caret (`Inserter.insert`).
    var inserter: Inserter?
    var label: String?

    /// Puts text in at the caret of the editor it's given to, as typed there (Undo takes it out); at the end of the text
    /// while there's no editor on screen.
    @MainActor final class Inserter {
        weak var textView: NSTextView?

        func insert(_ piece: String, into text: Binding<String>) {
            guard let textView, textView.window != nil else {
                text.wrappedValue += piece
                return
            }
            let range = textView.selectedRange()
            guard textView.shouldChangeText(in: range, replacementString: piece) else { return }
            textView.replaceCharacters(in: range, with: piece)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location + (piece as NSString).length, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        Self.plain(view)
        view.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        view.textContainerInset = NSSize(width: 2, height: 4)
        view.string = text
        view.delegate = context.coordinator
        view.setAccessibilityLabel(label)
        inserter?.textView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let view = scroll.documentView as? NSTextView else { return }
        // Text set from outside (an example loaded); never while something is being typed into it (marked text).
        if view.string != text, !view.hasMarkedText() { view.string = text }
        inserter?.textView = view
    }

    /// Typed as it is: nothing replaced while typing.
    static func plain(_ view: NSTextView) {
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.smartInsertDeleteEnabled = false
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}

/// The Icon field's picker: the common SF Symbols (`IconToken.commandSymbols`), searched by name (any other symbol by its
/// whole name), one emoji typed (Emoji…), or Default, the icon of the command's kind.
struct CommandIconPicker: View {
    @Binding var icon: String?
    let type: CustomCommand.CommandType
    let color: String?
    /// Closes the popover.
    var done: () -> Void = {}
    @State private var searchText = ""
    @State private var typingEmoji = false
    @State private var emoji = ""
    @FocusState private var emojiFocused: Bool

    /// The symbols shown for `query`: the offered ones whose name has it, after the one it names whole (any symbol of
    /// SF Symbols'), those this Mac has.
    static func symbols(matching query: String) -> [String] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        var shown = IconToken.commandSymbols.filter { query.isEmpty || $0.contains(query) }
        if !query.isEmpty, !shown.contains(query) { shown.insert(query, at: 0) }
        return shown.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
    }

    var body: some View {
        let shown = Self.symbols(matching: searchText)
        VStack(alignment: .leading, spacing: 10) {
            TextField(tr("搜索符号", "Search Symbols"), text: $searchText, prompt: Text(tr("搜索 SF Symbols 名字", "Search SF Symbols names")))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 9), spacing: 4) {
                    ForEach(shown, id: \.self) { name in
                        Button {
                            icon = name
                            done()
                        } label: {
                            IconTile(icon: tile(.symbol(name, fallback: IconToken.custom(CustomCommand(name: "", type: type)).fallback)), size: 22)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 6).fill(icon == name ? Color.accentColor.opacity(0.25) : .clear))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                        .accessibilityLabel(name)
                    }
                }
            }
            .frame(height: 200)
            .overlay {
                if shown.isEmpty { Text(tr("没有这个名字的符号", "No symbol by that name")).foregroundStyle(.secondary) }
            }
            Divider()
            HStack {
                Button(tr("默认", "Default")) {
                    icon = nil
                    done()
                }
                Button(tr("表情符号…", "Emoji…")) {
                    typingEmoji = true
                    emojiFocused = true
                    // The system's emoji picker types into the field.
                    NSApp.orderFrontCharacterPalette(nil)
                }
                if typingEmoji {
                    TextField(tr("一个表情符号", "One emoji"), text: $emoji)
                        .frame(width: 70)
                        .focused($emojiFocused)
                        .onChange(of: emoji) { take(emoji) }
                }
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 330)
    }

    /// `glyph` on the command's color, as the list draws it.
    private func tile(_ glyph: IconToken.Glyph) -> CandidateView.Icon {
        CandidateView.Icon(IconToken(glyph, color: IconToken.custom(CustomCommand(name: "", type: type, color: color)).color))
    }

    /// The last emoji typed into the field, as the icon (anything else typed is left out).
    private func take(_ typed: String) {
        guard let last = typed.last.map(String.init), IconToken.isEmoji(last) else { return }
        if emoji != last { emoji = last }
        icon = last
    }
}

/// The Color field: Default (the color of the command's kind), then the named colors as swatches (`IconToken.Color
/// .names`), and a color config.json names otherwise ("#34C759"), kept while it is the one chosen.
struct CommandColorPicker: View {
    @Binding var color: String?
    let type: CustomCommand.CommandType

    var body: some View {
        HStack(spacing: 4) {
            Button { color = nil } label: {
                Text(tr("默认", "Default"))
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(color == nil ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: color == nil ? 2 : 1))
            }
            .buttonStyle(.plain)
            .help(tr("默认", "Default"))
            ForEach(names, id: \.self) { name in
                Button { color = name } label: { swatch(name) }
                    .buttonStyle(.plain)
                    .help(IconToken.Color.named(name).map(UIText.name) ?? name)
                    .accessibilityLabel(IconToken.Color.named(name).map(UIText.name) ?? name)
            }
        }
    }

    /// The named colors, and the one chosen if it is another.
    private var names: [String] {
        guard let color, !IconToken.Color.names.contains(color.lowercased()), IconToken.Color.named(color) != nil else {
            return IconToken.Color.names
        }
        return IconToken.Color.names + [color]
    }

    private func swatch(_ name: String) -> some View {
        let chosen = color?.lowercased() == name.lowercased()
        return Circle()
            .fill(Color(nsColor: IconToken.Color.named(name).map(NSColor.icon) ?? .clear))
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
            .padding(2)
            .overlay(Circle().strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 2))
    }
}

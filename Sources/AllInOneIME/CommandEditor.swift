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
/// to run, a program in Terminal, a web page to open, or a text to insert) and how. Saving hands the finished
/// definition back.
struct CommandEditor: View {
    let original: CommandEdit
    /// The other custom commands, the installed plugins and the custom commands a later version wrote
    /// (`Config.unreadCustomCommandNames`): their names are taken.
    let others: [CustomCommand]
    let plugins: [String]
    let unread: [String]
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
    /// The program of the command line isn't on this Mac (looked up in the background).
    @State private var missingProgram: String?

    init(edit: CommandEdit, others: [CustomCommand], plugins: [String] = [], unread: [String] = [],
         onSave: @escaping (CustomCommand) -> Bool) {
        original = edit
        self.others = others
        self.plugins = plugins
        self.unread = unread
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
    }

    /// The definition as the form has it now (nil: the command line has an open quote).
    private var draft: CustomCommand? {
        var c = CustomCommand(name: name.trimmingCharacters(in: .whitespaces).lowercased(), type: type)
        let description = summary.trimmingCharacters(in: .whitespaces)
        c.summary = description.isEmpty ? nil : description
        switch type {
        case .prompt:
            c.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        case .run, .terminal:
            guard let argv = CustomCommand.arguments(fromCommandLine: commandLine) else { return nil }
            c.argv = argv
            if type == .run {
                if useStdin { c.stdin = CustomCommand.placeholder + "\n" }
                if timeout != CustomCommand.defaultTimeout { c.timeoutSeconds = timeout }
            }
        case .link:
            c.url = url.trimmingCharacters(in: .whitespaces)
        case .snippet:
            c.text = text
        }
        // Stored only when it differs from the type's default (Latin for programs, as typed for the AI and pages).
        if latin != CustomCommand.typesLatinByDefault(type), type != .snippet { c.ascii = latin }
        return c
    }

    private var problem: String? {
        guard let draft else { return Self.describe(.unbalancedQuote) }
        if let takenOnSave, draft.name == takenOnSave { return Self.describe(.nameTaken) }
        return draft.problem(among: others, plugins: plugins, unread: unread).map(Self.describe)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    HStack {
                        TextField(tr("名字", "Name"), text: $name, prompt: Text(tr("只用英文字母，比如 py", "Letters only, e.g. py")))
                        Menu(tr("从例子开始", "Start from an Example")) {
                            ForEach(Self.examples, id: \.name) { example in
                                Button("@\(example.name)  " + (example.summary ?? "")) { load(example) }
                            }
                        }
                        .fixedSize()
                    }
                    Picker(tr("做什么", "What it does"), selection: $type) {
                        Text(tr("AI 指令", "AI instruction")).tag(CustomCommand.CommandType.prompt)
                        Text(tr("运行程序", "Run a program")).tag(CustomCommand.CommandType.run)
                        Text(tr("在终端运行", "Run in Terminal")).tag(CustomCommand.CommandType.terminal)
                        Text(tr("打开网页", "Open a web page")).tag(CustomCommand.CommandType.link)
                        Text(tr("插入文字", "Insert text")).tag(CustomCommand.CommandType.snippet)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { latin = CustomCommand.typesLatinByDefault(type) }
                    TextField(tr("说明", "Description"), text: $summary,
                              prompt: Text(tr("命令列表里显示，可以不填", "Shown in the command list (optional)")))
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
                    if type != .snippet {
                        Toggle(tr("用英文字母输入（写代码、路径时）", "Type English letters (for code and paths)"), isOn: $latin)
                    }
                }
                if type == .run || type == .terminal {
                    Text(tr("「运行程序」和「在终端运行」会在你的 Mac 上执行命令：只加你自己写的、信得过的。它们只在你按执行键时运行，密码框里不运行。",
                            "Programs run on your Mac: add only commands you wrote and trust. They run only when you press the action key, never in password fields."))
                        .font(.caption).foregroundStyle(.secondary)
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
        .frame(width: 520, height: 520)
        .task(id: commandLine) { await checkProgram() }
        .task(id: type) { await checkProgram() }
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
        guard type == .run || type == .terminal, let program = CustomCommand.arguments(fromCommandLine: commandLine)?.first, !program.isEmpty else {
            missingProgram = nil
            return
        }
        let found = await Task.detached { CommandRunner.isInstalled(program, path: ShellEnvironment.current["PATH"]) }.value
        missingProgram = found ? nil : program
    }

    static func describe(_ problem: CustomCommand.Problem) -> String {
        switch problem {
        case .emptyName: return tr("给命令起个名字", "Give the command a name")
        case .nameNotLetters: return tr("名字只能用英文字母（最多 24 个）", "Names are letters only (24 at most)")
        case .nameTaken: return tr("这个名字已经有命令在用了", "Another command has this name")
        case .emptyPrompt: return tr("写上给 AI 的指令", "Write the instruction for the AI")
        case .emptyCommand: return tr("写上要运行的命令", "Write the command to run")
        case .unbalancedQuote: return tr("命令里有引号没有配对", "A quote in the command isn't closed")
        case .link(.empty): return tr("写上要打开的网址", "Write the address to open")
        case .link(.notHTTPS): return tr("网址要以 https:// 开头", "The address must start with https://")
        case .link(.placeholderCount): return tr("网址里要有一个 {input}", "Put {input} in the address once")
        case .link(.placeholderNotInQuery): return tr("{input} 要放在 ? 后面", "Put {input} after the ? in the address")
        case .link(.invalid): return tr("网址格式不对", "The address isn't valid")
        case .emptyText: return tr("写上要插入的文字", "Write the text to insert")
        case .twoCursors: return tr("{cursor} 只能有一个", "{cursor} can appear only once")
        }
    }

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

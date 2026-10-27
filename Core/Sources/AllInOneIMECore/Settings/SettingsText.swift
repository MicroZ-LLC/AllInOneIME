import Foundation

// What the settings say about a value, the same in every settings window: the Mac's and Windows' (the settings
// document, `SettingsDocument`).

extension UIText {
    /// How the chosen action key works, and what Space does with it; the keys as `terms` names them (on Windows Enter,
    /// a tap of Ctrl, Ctrl+Space, a recorded shortcut as it is pressed there), the commands with the trigger (`triggered`).
    public static func actionKeyNote(_ key: ActionKey, terms: PlatformTerms = Platform.current.terms) -> String {
        triggered(terms.keyStyle == .names ? windowsActionKeyNote(key, terms: terms) : macActionKeyNote(key))
    }

    private static func macActionKeyNote(_ key: ActionKey) -> String {
        switch key {
        case .enter:
            return tr("@ 命令写完按 ⏎ 执行，拼音没选完也能直接按。没有 @ 时 ⏎ 就是普通回车。",
                      "Return runs a command typed with @, also on pinyin not yet picked. Without @, Return is a normal Return.")
        case .optionTap:
            // Holding the right ⌥ dictates only while voice input is on (`Features.voiceInput`).
            return Features.voiceInput
                ? tr("按一下 ⌥ 马上松开，左右都行；按住右 ⌥ 仍然是说话。@ 命令按 ⏎ 也执行。",
                     "Press either ⌥ and let go right away; holding right ⌥ still dictates. @ commands also run on Return.")
                : tr("按一下 ⌥ 马上松开，左右都行。@ 命令按 ⏎ 也执行。",
                     "Press either ⌥ and let go right away. @ commands also run on Return.")
        case .optionSpace:
            return tr("拼音没选完也可以直接按 ⌥空格。⌥空格被 Alfred、Raycast 等占用时，改用「单按 ⌥」。@ 命令按 ⏎ 也执行。",
                      "⌥Space also works before the pinyin is picked. If Alfred, Raycast or another app uses ⌥Space, "
                          + "choose Tap ⌥. @ commands also run on Return.")
        case .space:
            return tr("空格先选词，没有要选的了再按一次空格执行；英文模式下连按两次空格。@ 命令按 ⏎ 也执行。",
                      "Space picks words; once nothing is left to pick, Space again runs it. In English mode, press Space twice. "
                          + "@ commands also run on Return.")
        case let .shortcut(key):
            return tr("@ 命令写完按 \(key.name) 执行；⏎ 也执行，没有 @ 时 ⏎ 是普通回车。",
                      "\(key.name) runs a command typed with @; Return does too, and without @ Return is a normal Return.")
        }
    }

    /// `actionKeyNote` with the keys' names (Windows'): no dictation there, so a tap of Ctrl does nothing else.
    private static func windowsActionKeyNote(_ key: ActionKey, terms: PlatformTerms) -> String {
        switch key {
        case .enter:
            return tr("@ 命令写完按 Enter 执行，拼音没选完也能直接按。没有 @ 时 Enter 就是普通的换行。",
                      "Enter runs a command typed with @, also on pinyin not yet picked. Without @, Enter is a normal Enter.")
        case .optionTap:
            return tr("按一下 Ctrl 马上松开，左右都行。@ 命令按 Enter 也执行。",
                      "Press either Ctrl and let go right away. @ commands also run on Enter.")
        case .optionSpace:
            return tr("拼音没选完也可以直接按 Ctrl+空格。@ 命令按 Enter 也执行。",
                      "Ctrl+Space also works before the pinyin is picked. @ commands also run on Enter.")
        case .space:
            return tr("空格先选词，没有要选的了再按一次空格执行；英文模式下连按两次空格。@ 命令按 Enter 也执行。",
                      "Space picks words; once nothing is left to pick, Space again runs it. In English mode, press Space twice. "
                          + "@ commands also run on Enter.")
        case let .shortcut(key):
            let name = terms.name(key, space: tr("空格", "Space"))
            return tr("@ 命令写完按 \(name) 执行；Enter 也执行，没有 @ 时 Enter 是普通的换行。",
                      "\(name) runs a command typed with @; Enter does too, and without @ Enter is a normal Enter.")
        }
    }

    /// The words of a settings window's own controls (`SettingsDocument.strings`), in the interface language: its title,
    /// the buttons of the fields' actions ("action.<name>", and "action.<name>.item" where an item's differs), of the
    /// lists and the editors, and the confirmation an action that deletes asks for ("confirm.<name>", "{name}" the thing's).
    public static var settingsWindowStrings: [String: String] {
        [
            "window.title": tr("AllInOneIME 设置", "AllInOneIME Settings"),
            "action.setKey": tr("保存", "Save"),
            "action.removeKey": tr("删除…", "Remove…", key: "action.removeKey"),
            "action.test": tr("测试", "Test"),
            "action.browse": tr("打开插件库", "Open the Library"),
            "action.install": tr("安装", "Install"),
            "action.remove": tr("移除", "Remove"),
            "action.save": tr("新建…", "New…"),
            "action.save.item": tr("编辑…", "Edit…"),
            "action.delete": tr("删除…", "Delete…"),
            "action.add": tr("添加", "Add"),
            "action.hide": tr("隐藏", "Hide"),
            "action.show": tr("显示", "Show"),
            "action.cancel": tr("取消", "Cancel"),
            "confirm.removeKey": tr("删除「{name}」？", "Remove “{name}”?"),
            "confirm.delete": tr("删除「{name}」？", "Delete “{name}”?"),
            "confirm.removeItem": tr("移除「{name}」？", "Remove “{name}”?", key: "confirm.removeItem"),
            "save": tr("保存", "Save"),
            "cancel": tr("取消", "Cancel"),
            "choose": tr("选择…", "Choose…"),
            "moveUp": tr("上移", "Move up"),
            "moveDown": tr("下移", "Move down"),
            "remove": tr("移除", "Remove"),
            "add": tr("添加…", "Add…"),
            "paste": tr("粘贴", "Paste it"),
            "working": tr("正在进行…", "Working…"),
        ]
    }

    /// What keeps a custom command from being saved, as its editor says it.
    public static func describe(_ problem: CustomCommand.Problem) -> String {
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
        case .badPrefix:
            return tr("前缀要写 1 到 16 个英文字母、数字或 . _ - #，不能以 @ 开头，比如 JIRA-",
                      "The prefix must be 1 to 16 letters, digits or . _ - #, not starting with @, like JIRA-")
        case let .prefixIsMagicKey(trigger):
            return tr("前缀不能以魔法键 \(trigger) 开头：打 \(trigger) 会打开命令列表", "The prefix can't start with the magic key \(trigger): typing it opens the command list")
        case .badTemplate: return tr("插入模板写得不对：每个 { 都要有 }，比如 {arg} {title}", "An insert template isn't valid: close each { with }, like {arg} {title}")
        case .timeoutTooLong: return tr("建议来源最多运行 20 秒", "A suggestion source can run 20 seconds at most")
        case let .suggestions(reason): return tr("不能作为建议来源：", "Can't be a suggestion source: ") + reason
        }
    }

    /// When a custom `suggestions` command's program runs on `device`, as its editor says it (the Mac's, the settings
    /// document's): as the session runs it (InputSession+Suggestions), its list as a text field takes the focus (before
    /// anything is typed, so maybe in a password field; given nothing of the field) and at its refresh interval; a query
    /// only with what follows the prefix, where rows may show (never in a password field).
    public static func suggestionsProgramRuns(on device: PlatformTerms.Device) -> String {
        device == .mac
            ? tr("这个程序会在你的 Mac 上运行：有输入框获得焦点时拿列表（可能是密码框，但输入框里的内容一概不给它），之后按刷新间隔再拿；边打边查时把前缀后面打的字作为一个参数给它，密码框里从不查。只加你自己写的、信得过的程序。",
                 "The program runs on your Mac: for its list when a text field gets the focus (it may be a password field: nothing of the field is given to it), then at the refresh interval; with Look up as you type, with what you type after the prefix as one argument, never in a password field. Add only programs you wrote and trust.")
            : tr("这个程序会在这台电脑上运行：有输入框获得焦点时拿列表（可能是密码框，但输入框里的内容一概不给它），之后按刷新间隔再拿；边打边查时把前缀后面打的字作为一个参数给它，密码框里从不查。只加你自己写的、信得过的程序。",
                 "The program runs on this PC: for its list when a text field gets the focus (it may be a password field: nothing of the field is given to it), then at the refresh interval; with Look up as you type, with what you type after the prefix as one argument, never in a password field. Add only programs you wrote and trust.")
    }

    /// "Show in the @ list", the switch under a plugin or script extension command with suggestions, next to their
    /// switch (`Config.hiddenFromCommandList`): the commands named with `trigger` (a window's own settings').
    public static func showInCommandList(trigger: String = UIText.commandTrigger) -> String {
        triggered(tr("在 @ 列表里显示", "Show in the @ list"), trigger: trigger)
    }

    /// What "Show in the @ list" does, under it: off, the command is out of the list and its name after the magic key is
    /// text like any other; its suggestions are as they were.
    public static func showInCommandListHelp(trigger: String = UIText.commandTrigger) -> String {
        triggered(tr("关掉后，它不在 @ 命令列表里，打 @ 加它的名字也只是普通文字；它的建议照常出现。",
                     "Off: it isn't in the @ command list, and @ with its name is just text; its suggestions still show."), trigger: trigger)
    }

    /// Clipboard history's switch (Settings → General, `Config.clipboardHistory`), under its name: what ⌃V does with it,
    /// what is kept and where, and that off, ⌃V is as before.
    public static func clipboardHistoryHelp(terms: PlatformTerms = Platform.current.terms) -> String {
        tr("按 \(terms.paste) 列出最近复制的文字，选一条就放进去；⇧↓ ⇧↑ 多选，\(terms.enter) 一行一条放进去。只记文字，只存在这台 Mac 上，密码管理器标成隐藏的内容不记。关掉后 \(terms.paste) 和以前一样。",
           "\(terms.paste) lists the text you copied lately and puts in the one you choose; ⇧↓ ⇧↑ choose several, and \(terms.enter) puts them in one per line. Text only, kept on this Mac only, never what a password manager marks as concealed. Off, \(terms.paste) works as before.")
    }

    /// How many texts clipboard history keeps (`Config.clipboardHistoryLimit`), the label of its number.
    public static var clipboardHistoryLimitLabel: String { tr("保留最近几条", "Keep the last") }

    /// Why a custom command in config.json isn't used (`CustomCommand.Refused`), as Settings → Custom Commands says it
    /// under its name: "This command isn't used: “minChars” should be a whole number".
    public static func describe(_ refused: CustomCommand.Refused) -> String {
        let reason: String
        switch refused.reason {
        case let .wrongKind(field, kind):
            let kind = switch kind {
            case .text: tr("文字", "text")
            case .number: tr("数字", "a number")
            case .wholeNumber: tr("整数", "a whole number")
            case .trueOrFalse: tr("true 或 false", "true or false")
            case .list: tr("列表 [ … ]", "a list, [ … ]")
            }
            reason = tr("「\(field)」应该是\(kind)", "“\(field)” should be \(kind)")
        case let .missing(field): reason = tr("缺少「\(field)」", "“\(field)” is missing")
        case .unreadable: reason = tr("读不出一个命令", "it can't be read as a command")
        }
        return tr("这个命令没有用上：\(reason)", "This command isn't used: \(reason)")
    }
}

extension TypeOut {
    /// The typing speed as shown: "每秒 16 个字" / "16 a second", or slower than one a second "6 秒一个字" / "6 s each".
    public static func label(rate: Double) -> String {
        if rate >= 1 { return tr("每秒 \(Int(rate.rounded())) 个字", "\(Int(rate.rounded())) a second") }
        let seconds = 1 / rate
        let shown = seconds < 2 ? String(format: "%.1f", seconds) : String(Int(seconds.rounded()))
        return tr("\(shown) 秒一个字", "\(shown) s each")
    }

    /// A speed rounded to what the label shows (whole characters a second, or whole / tenth seconds each).
    public static func rounded(rate: Double) -> Double {
        if rate >= 1 { return rate.rounded() }
        let seconds = 1 / rate
        return 1 / (seconds < 2 ? (seconds * 10).rounded() / 10 : seconds.rounded())
    }
}

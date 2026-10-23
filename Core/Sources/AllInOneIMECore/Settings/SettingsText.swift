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
            return tr("按一下 ⌥ 马上松开，左右都行；按住右 ⌥ 仍然是说话。@ 命令按 ⏎ 也执行。",
                      "Press either ⌥ and let go right away; holding right ⌥ still dictates. @ commands also run on Return.")
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
        }
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

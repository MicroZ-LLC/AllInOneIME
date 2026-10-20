import AllInOneIMECore
import Foundation

/// The candidate window's sample panels: the core's models as the engine's sessions show them, one for each thing the
/// window draws (a row or a column of candidates, the command list with its icons, a draft's input with its caret and
/// header, results coming in, a conversation with where it can go on, a list under a hint, an error, every icon). What
/// `AllInOneIMEEngine --render-panel` draws into PNG files to look at, and what the panel's tests draw.
public enum PanelSamples {
    public struct Sample {
        public var name: String
        public var model: PanelModel
        /// A conversation's height limit at 96 DPI (the window's is half the monitor's), scaled with the DPI.
        public var maxHeight: Int
    }

    /// The samples; `image`: a picture for the icons' image row (drawn as its fallback where it can't be read).
    public static func all(image: String? = nil) -> [Sample] {
        typealias Row = PanelModel.Row
        var samples: [Sample] = []
        func add(_ name: String, _ model: PanelModel, maxHeight: Int = 0) { samples.append(Sample(name: name, model: model, maxHeight: maxHeight)) }

        add("pinyin-row", PanelModel(
            rows: ["你好", "拟好", "你号", "泥好", "妮好", "👋"].enumerated().map { Row(label: "\($0.offset + 1)", text: $0.element, kind: .candidate) },
            highlighted: 0, footer: "空格 选词 · 开头打 @ 用命令", detail: "第 1 页", horizontal: true))
        add("pinyin-column", PanelModel(
            rows: [Row(label: "1", text: "我今天有点不舒服", kind: .candidate), Row(label: "2", text: "我今天", kind: .candidate),
                   Row(label: "3", text: "握紧", comment: "wò jǐn", kind: .candidate), Row(label: "4", text: "我今", kind: .candidate),
                   Row(label: "5", text: "我进", kind: .candidate)],
            highlighted: 0, footer: "空格 选词 · Enter 翻译成英文", detail: "第 1 页"))
        for language in ["zh-Hans", "en"] {
            add("palette-" + language, palette(language: language))
        }
        add("draft", PanelModel(
            status: .hint("写点内容，或按 Ctrl+V 粘贴"), input: PanelModel.Input(prompt: "improve › ", text: "帮我改一下这句话，让它更礼貌", caret: 6),
            header: ["选中的文字：Thanks for the update, I'll take a look tomorrow.", "附件：截图 2 张"],
            footer: "Ctrl+V 粘贴 · Backspace 删字 · Esc 清除"))
        add("results", PanelModel(
            rows: [Row(label: "0", text: "我今天有点不舒服", comment: "原文", kind: .original),
                   Row(label: "1", text: "I'm not feeling well today.", comment: "英文", kind: .translation),
                   Row(label: "2", text: "I've been feeling a bit under the weather today.", comment: "英文", kind: .translation),
                   Row(label: "3", text: "I feel kind of off tod", comment: "英文", kind: .translation, isComplete: false)],
            highlighted: 1, status: .loading("正在生成…"), input: PanelModel.Input(prompt: "translate › ", text: "我今天有点不舒服", caret: nil),
            footer: "输入，Shift+Enter 修改 · 空格 / Enter 上屏 · 数字 选择 · 0 原文 · Ctrl+C 复制 · Esc 返回", detail: "1.1s"))
        add("conversation", conversation(highlighted: nil), maxHeight: 460)
        add("conversation-scrolled-up", conversation(highlighted: 1), maxHeight: 460)
        add("report-issue", PanelModel(
            status: .list("会附上这些信息，发送前可以在浏览器里看到：", items: [
                "AllInOneIME 0.6.6（Windows 11 26200）", "这台电脑的输入语言：中文（简体）、英语（美国）",
                "最近 20 行日志（不含你打的字和密钥）"]),
            input: PanelModel.Input(prompt: "reportissue › ", text: "候选窗在记事本里不出现", caret: 11),
            footer: "Enter 在浏览器里打开 · Esc 返回"))
        add("error", PanelModel(
            status: .error("请求失败：401 Unauthorized\n检查 API key 是否正确，或在设置里换一个服务。"),
            input: PanelModel.Input(prompt: "question › ", text: "什么是量子计算", caret: nil),
            footer: "Enter 再试一次 · Esc 返回"))
        add("icons", icons(image: image))
        add("notice", PanelModel.notice("已复制"))
        return samples
    }

    /// The command list after "@", as the core's presenter makes it on Windows (its icons, its summaries).
    static func palette(language: String) -> PanelModel {
        let composer = Composer(engine: LatinEngine(), voiceEnabled: false, actionKey: .enter)
        composer.commands = Command.builtins
        composer.modifierRoles = .windows
        _ = composer.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        return PanelPresenter(config: .default, language: language, terms: .windows).model(for: composer)
    }

    /// An `@question` conversation of five rounds (an answer long enough to wrap), where it can go on above, the next
    /// question's line with its caret; scrolled to the last row, or to `highlighted` above.
    static func conversation(highlighted: Int?) -> PanelModel {
        typealias Row = PanelModel.Row
        let rounds = [
            ("什么是量子计算", "量子计算是一种利用量子力学原理（如叠加和纠缠）来处理信息的计算方式。与经典计算机用 0 和 1 表示比特不同，量子计算机使用量子比特，可以同时处于多种状态的叠加中。"),
            ("它现在能做什么", "目前的量子计算机仍处于早期阶段，容易受噪声干扰，能可靠完成的任务很少，主要用于研究和演示。"),
            ("哪些公司在做", "IBM、Google、微软、亚马逊，还有 IonQ、Rigetti 等初创公司。"),
            ("会取代普通电脑吗", "不会。它只在少数特定问题上可能更快，日常的工作仍然交给经典计算机。"),
            ("用一句话总结", "量子计算用量子比特的叠加和纠缠，在某些问题上有望远超经典计算机，但还远未成熟。"),
        ]
        var rows: [Row] = []
        for (index, round) in rounds.enumerated() {
            rows.append(Row(label: "", text: round.0, comment: "问", kind: .original, pickable: false))
            rows.append(Row(label: "\(index + 1)", text: round.1, comment: "答", kind: .translation, choice: index))
        }
        return PanelModel(
            rows: rows, highlighted: highlighted ?? rows.count - 1,
            input: PanelModel.Input(prompt: "追问 6/10 › ", text: "", caret: 0),
            handoff: PanelModel.Handoff(title: "在 Claude 或其他 AI 中继续", choices: [
                .init(shortcut: "Ctrl+1", name: "Claude Code"), .init(shortcut: "Ctrl+2", name: "Claude"),
                .init(shortcut: "Ctrl+3", name: "ChatGPT"), .init(shortcut: "Ctrl+4", name: "Gemini"),
                .init(shortcut: "Ctrl+5", name: "Kiro CLI")]),
            footer: "Shift+Enter 追问 · Enter 上屏 · 1–5 选择 · Ctrl+C 复制 · Esc 返回", detail: "2.3s", transcript: true)
    }

    /// Every built-in icon by its name, then a symbol the window knows, one it doesn't (its fallback), an emoji and an
    /// image.
    static func icons(image: String?) -> PanelModel {
        typealias Row = PanelModel.Row
        let colors: [IconToken.Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink, .brown, .gray]
        var rows = IconToken.Builtin.allCases.enumerated().map { index, builtin in
            Row(label: "", text: builtin.rawValue, comment: String(format: "U+%04X", PanelIcons.glyph(builtin).unicodeScalars.first!.value),
                kind: .candidate, icon: IconToken(builtin, color: colors[index % colors.count]))
        }
        rows.append(Row(label: "", text: "symbol heart", kind: .candidate, icon: IconToken(.symbol("heart.fill", fallback: .prompt), color: .pink)))
        rows.append(Row(label: "", text: "symbol unknown → prompt", kind: .candidate,
                        icon: IconToken(.symbol("no.such.symbol", fallback: .prompt), color: .indigo)))
        rows.append(Row(label: "", text: "emoji 🍅", kind: .candidate, icon: IconToken(.emoji("🍅", fallback: .scriptShow), color: .teal)))
        rows.append(Row(label: "", text: "image", comment: image.map { ($0 as NSString).lastPathComponent } ?? "none: fallback", kind: .candidate,
                        icon: IconToken(.image(path: image ?? "C:\\nowhere\\icon.png", fallback: .scriptList), color: .teal)))
        rows.append(Row(label: "", text: "grayscale(0.25) and #34C759", kind: .candidate, icon: IconToken(.terminal, color: .grayscale(0.25))))
        return PanelModel(rows: rows, footer: "\(rows.count) icons")
    }

    /// The checkout's Resources/AppIcon.png, for the samples of a build of this package (`swift build`: Windows/.build/…):
    /// two folders above `.build`. Nil for any other copy, and never a folder further up, which any user of the PC may
    /// make (C:\Resources).
    public static func checkoutIcon(executable: String,
                                    exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        let parts = executable.replacingOccurrences(of: "/", with: "\\").split(separator: "\\", omittingEmptySubsequences: false)
        guard let build = parts.lastIndex(where: { $0.lowercased() == ".build" }), build >= 2 else { return nil }
        let icon = (parts[..<(build - 1)].map(String.init) + ["Resources", "AppIcon.png"]).joined(separator: "\\")
        return exists(icon) ? icon : nil
    }
}

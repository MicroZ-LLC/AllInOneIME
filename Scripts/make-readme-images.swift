// Builds the README images from the panels rendered by `AllInOneIME --selftest`:
//   swift Scripts/make-readme-images.swift /tmp/allinoneime-selftest docs          Chinese interface and captions
//   swift Scripts/make-readme-images.swift /tmp/allinoneime-selftest docs/en en    English: the `en-*` scenes
//                 (English typed, translated into Spanish, French and German) and the `-en` renders
// demo.png      @translate, side by side, each under a text line with the inline (marked) text
// improve.png   @improve: polished, plus rewrites
// english.png   (Chinese only) English typed directly → English polish; Chinese as the output language
// voice.png     dictation (hold right ⌥) after a command
// commands.png  the @ command palette → @question's answer
// open.png      @open: Spotlight as you type, and a path listing a folder (only macOS's own apps)
// candidates-horizontal.png   pinyin candidates side by side (the default layout)
// refine.png    refining the results: an instruction typed under them → the refined results
// recent-questions.png   @question with nothing after it: the recent questions (made-up ones)
// selection.png @improve on the selected text, with an email and a phone number hidden from the AI
// question-chat.png   an @question conversation: two rounds, the next question's line on top (canned answers)
// question-chat-handoff.png   after the last round: where to go on (the agents installed, Claude, ChatGPT, a copy)
// panel-dark.png, settings.png, dashboard.png   copies of the renders (dashboard: the floating panel, sample data)
// settings-assistant.png   Settings → Assistant: a request's preview and the checks (a canned answer, made-up findings)
import AppKit

let args = CommandLine.arguments
let source = URL(fileURLWithPath: args.count > 1 ? args[1] : "/tmp/allinoneime-selftest")
let output = URL(fileURLWithPath: args.count > 2 ? args[2] : "docs")
/// The interface the renders show and the captions' language: zh (the default) or en.
let language = args.count > 3 ? args[3] : "zh"
guard ["zh", "en"].contains(language) else {
    FileHandle.standardError.write(Data("unknown language '\(language)': zh or en\n".utf8))
    exit(2)
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// A caption in the images' language.
func tr(_ chinese: String, _ english: String) -> String { language == "en" ? english : chinese }

/// A render of the self-test; with the English interface it is `<name>-en.png`.
func render(_ name: String) -> URL {
    source.appendingPathComponent(name + (language == "en" ? "-en" : "") + ".png")
}

func load(_ name: String) -> NSBitmapImageRep { load(url: render(name)) }

/// One of the English README's own scenes (`en-*.png`), as it is.
func loadScene(_ name: String) -> NSBitmapImageRep { load(url: source.appendingPathComponent(name + ".png")) }

/// The text line above a panel, as the self-test saved it (`<name>.marked.txt`), else `fallback`.
func marked(_ name: String, _ fallback: String) -> String {
    (try? String(contentsOf: source.appendingPathComponent(name + ".marked.txt"), encoding: .utf8)).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
}

func load(url: URL) -> NSBitmapImageRep {
    guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else {
        fatalError("missing \(url.path); run `make selftest` first")
    }
    return rep
}

func png(_ size: NSSize, scale: CGFloat, _ draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

struct Step {
    let caption: String
    let marked: String
    let panel: NSBitmapImageRep
    /// The text line's text is selected in the field (a command on the selection), not the input method's marked text.
    var selected = false
}

/// A long text line cut to fit above its panel.
func cut(_ line: String, _ length: Int = 60) -> String { line.count > length ? String(line.prefix(length)) + "…" : line }

/// Steps side by side: caption, a text line with the input method's inline (underlined) text, and
/// the candidate panel just below the line, as on screen.
func composite(_ steps: [Step], to name: String) throws {
    // Renders are 2x bitmaps; lay out in points.
    let scale: CGFloat = 2
    let margin: CGFloat = 28, gap: CGFloat = 36, captionHeight: CGFloat = 30, fieldHeight: CGFloat = 40
    let captionFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    let fieldFont = NSFont.systemFont(ofSize: 17)
    let panelSizes = steps.map { NSSize(width: CGFloat($0.panel.pixelsWide) / scale, height: CGFloat($0.panel.pixelsHigh) / scale) }
    // A step is as wide as its panel, or its caption / text line if those are wider.
    let widths = zip(steps, panelSizes).map { step, size in
        max(size.width,
            (step.caption as NSString).size(withAttributes: [.font: captionFont]).width,
            (step.marked as NSString).size(withAttributes: [.font: fieldFont]).width + 30)
    }
    let width = margin * 2 + widths.reduce(0, +) + gap * CGFloat(steps.count - 1)
    let height = margin * 2 + captionHeight + fieldHeight + 6 + (panelSizes.map(\.height).max() ?? 0)

    let image = png(NSSize(width: width, height: height), scale: scale) {
        NSColor(calibratedWhite: 0.955, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        var x = margin
        for (index, step) in steps.enumerated() {
            let size = panelSizes[index]
            let top = height - margin
            NSAttributedString(string: step.caption, attributes: [
                .font: captionFont, .foregroundColor: NSColor(white: 0.15, alpha: 1),
            ]).draw(at: NSPoint(x: x, y: top - 20))
            let field = NSRect(x: x, y: top - captionHeight - fieldHeight, width: widths[index], height: fieldHeight)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: field, xRadius: 8, yRadius: 8).fill()
            NSColor(white: 0.82, alpha: 1).setStroke()
            NSBezierPath(roundedRect: field.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
            let markedWidth = (step.marked as NSString).size(withAttributes: [.font: fieldFont]).width
            if step.selected {
                NSColor(calibratedRed: 0.70, green: 0.84, blue: 1, alpha: 1).setFill()
                NSRect(x: field.minX + 11, y: field.minY + 8, width: markedWidth + 2, height: 23).fill()
            }
            NSAttributedString(string: step.marked, attributes: [
                .font: fieldFont, .foregroundColor: NSColor.black,
                .underlineStyle: step.selected ? 0 : NSUnderlineStyle.single.rawValue,
            ]).draw(at: NSPoint(x: field.minX + 12, y: field.minY + 9))
            if !step.selected {
                NSColor.controlAccentColor.setFill()
                NSRect(x: field.minX + 12 + markedWidth + 2, y: field.minY + 9, width: 2, height: 21).fill()
            }
            // Source-over: drawn as is (copy), the panel's rounded corners would punch holes in the image.
            step.panel.draw(in: NSRect(x: x, y: field.minY - 6 - size.height, width: size.width, height: size.height),
                            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += widths[index] + gap
        }
    }
    try image.write(to: output.appendingPathComponent(name))
}

if language == "en" {
    try composite([
        Step(caption: "① Type @translate and a sentence", marked: "translate › running 10 minutes late, start without me",
             panel: loadScene("en-translate-draft")),
        Step(caption: "② Press ⏎: a line in each language you added", marked: "translate › running 10 minutes late, start without me",
             panel: loadScene("en-translate")),
    ], to: "demo.png")
    try composite([
        Step(caption: "① Type @improve and a rough sentence", marked: "improve › this is a blocker bug your team need fix it asap",
             panel: loadScene("en-improve-draft")),
        Step(caption: "② Press ⏎: polished versions, plus rewrites", marked: "improve › this is a blocker bug your team need fix it asap",
             panel: loadScene("en-improve")),
    ], to: "improve.png")
    try composite([
        Step(caption: "Type @improve, then hold right ⌥ to talk", marked: marked("8-voice-english", "improve › This is a blocker"),
             panel: load("8-voice-english")),
    ], to: "voice.png")
    try composite([
        Step(caption: "① Type @ first: the command list; letters filter it", marked: "@", panel: loadScene("en-palette")),
        Step(caption: "② @question and a question, press ⏎: the answer", marked: "question › what is quantum computing",
             panel: loadScene("en-question")),
    ], to: "commands.png")
} else {
    try composite([
        Step(caption: tr("① 开头打 @translate，再打拼音", "① Type @translate, then pinyin"),
             marked: "translate › wo jin tian you dian bu shu fu", panel: load("2-translate-pinyin")),
        Step(caption: tr("② 按 ⏎：三种地道的英文说法", "② Press ⏎: three idiomatic English versions"),
             marked: "translate › 我今天有点不舒服", panel: load("3-translate")),
    ], to: "demo.png")

    try composite([
        Step(caption: tr("① 开头打 @improve，再打拼音", "① Type @improve, then pinyin"),
             marked: "improve › wo jin tian you dian bu shu fu", panel: load("1b-sentence-pinyin")),
        Step(caption: tr("② 按 ⏎：润色 + 改写，不翻译", "② Press ⏎: polished, plus rewrites (no translation)"),
             marked: "improve › 我今天有点不舒服", panel: load("4-final-light")),
    ], to: "improve.png")

    try composite([
        Step(caption: tr("@improve 加英文：英文润色（含黑话）", "@improve with English: English polish (incl. Jargon)"),
             marked: "improve › this is a blocker bug your team need fix it asap", panel: load("7-english-light")),
        Step(caption: tr("@improve 加中文：中文润色 + 改写", "@improve with Chinese: Chinese polish + rewrites"),
             marked: "improve › 这个项目的进度太慢了", panel: load("7b-chinese-output")),
    ], to: "english.png")

    try composite([
        Step(caption: tr("先打 @improve，再按住右 ⌥ 说话", "Type @improve, then hold right ⌥ to talk"),
             marked: "improve › 我今天有", panel: load("8-voice")),
    ], to: "voice.png")

    try composite([
        Step(caption: tr("① 开头打 @：命令列表，打字母筛选", "① Type @ first: the command list; letters filter it"),
             marked: "@", panel: load("10-palette")),
        Step(caption: tr("② @question 加问题，按 ⏎：回答", "② @question and a question, press ⏎: the answer"),
             marked: "question › 什么是量子计算", panel: load("11-question")),
    ], to: "commands.png")
}

try composite([
    Step(caption: tr("① @open 加名字：边打边找", "① @open and a name: results as you type"),
         marked: "open › calculator", panel: load("12-open")),
    Step(caption: tr("② 以 / 开头是路径：列出文件夹，Tab 补全", "② A path (starts with /): lists the folder, Tab completes"),
         marked: "open › /System/Applications/", panel: load("12b-open-path")),
], to: "open.png")

// 0.6.3's release notes.
try composite([
    Step(caption: tr("打拼音：候选词横排，← → 选，↑↓ 翻页", "Type pinyin: candidates side by side, ← → choose, ↑↓ turn the page"),
         marked: marked("1b-pinyin-horizontal", "ni hao"), panel: load("1b-pinyin-horizontal")),
], to: "candidates-horizontal.png")
try composite([
    Step(caption: tr("① 结果出来后，直接打要怎么改", "① With the results up, type what to change"),
         marked: cut(marked("refine-typing", "improve › i wanted to let you know")), panel: load("refine-typing")),
    Step(caption: tr("② 按 ⏎：同一个面板里换成改过的结果", "② Press ⏎: the refined results, in the same panel"),
         marked: cut(marked("refine", "improve › i wanted to let you know")), panel: load("refine")),
], to: "refine.png")
try composite([
    Step(caption: tr("只打 @question：最近问过的问题，选一个直接看答案", "Type @question alone: your recent questions; pick one to see its answer"),
         marked: "question › ", panel: load("question-recent-list")),
], to: "recent-questions.png")
let selectedText = "pls tell bob.tester@example.com the meeting moved, or call 555-123-4567 tomorow"
try composite([
    Step(caption: tr("选中文字，打 @improve 按 ⏎：改写选中的文字，邮箱和电话不发给 AI",
                     "Select text, type @improve, ⏎: rewrites of the selection; the email and number never reach the AI"),
         marked: cut(selectedText, 90), panel: load("redaction"), selected: true),
], to: "selection.png")

// 0.6.4's release notes.
try composite([
    Step(caption: tr("答案下面接着打下一个问题：⇧⏎ 追问，⏎ 上屏选中的答案",
                     "Type the next question under the answer: ⇧⏎ asks it, ⏎ inserts the answer selected"),
         marked: marked("question-chat", "question › what is rust"), panel: load("question-chat")),
], to: "question-chat.png")
try composite([
    Step(caption: tr("聊满后：⌘1、⌘2… 在装了的 agent、Claude 或 ChatGPT 里接着聊",
                     "After the last round: ⌘1, ⌘2 … go on in the agents installed, Claude or ChatGPT"),
         marked: marked("question-chat-handoff", "question › what is rust"), panel: load("question-chat-handoff")),
], to: "question-chat-handoff.png")

let dark = language == "en" ? source.appendingPathComponent("en-improve-dark.png") : render("4-final-dark")
for (from, to) in [(dark, "panel-dark.png"), (render("6-settings"), "settings.png"), (render("14-dashboard"), "dashboard.png"),
                   (render("assistant"), "settings-assistant.png")] {
    try? FileManager.default.removeItem(at: output.appendingPathComponent(to))
    try FileManager.default.copyItem(at: from, to: output.appendingPathComponent(to))
}
print("wrote \(output.path)/demo.png, improve.png, english.png, voice.png, commands.png, open.png, panel-dark.png, settings.png, dashboard.png, "
      + "candidates-horizontal.png, refine.png, recent-questions.png, selection.png, question-chat.png, question-chat-handoff.png, "
      + "settings-assistant.png")

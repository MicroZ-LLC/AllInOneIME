import AllInOneIMECore
import Foundation

extension CommandEditor {
    /// The menu's starting points.
    static var examples: [CustomCommand] {
        [
            CustomCommand(name: "sig", type: .snippet, summary: tr("邮件签名", "Email signature"),
                          text: "Best,\n" + NSFullUserName() + "\n{cursor}"),
            CustomCommand(name: "meet", type: .snippet, summary: tr("会议链接", "Meeting link"), text: "https://zoom.us/j/1234567890"),
            CustomCommand(name: "today", type: .snippet, summary: tr("今天的日期", "Today's date"), text: "{date}"),
            CustomCommand(name: "ja", type: .prompt, summary: tr("翻译成日语", "Translate to Japanese"),
                          prompt: "Translate the user's text into natural Japanese. Reply with the translation only."),
            // Sandboxed JavaScript is built in (@js); Python, as the built-in @py ran it before 0.7.5, and Node.js with its
            // files and modules aren't.
            CommandExamples.python,
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

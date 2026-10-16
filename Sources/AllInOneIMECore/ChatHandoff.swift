import Foundation

/// Going on with an `@question` conversation elsewhere (`QuestionChat`): after the last round the panel allows
/// (`Config.questionRounds`), or at any round with ⌘⏎, it offers the coding agent `@agent` hands to (Claude Code by
/// default), Claude, ChatGPT or Gemini on the web, or copying the conversation, picked with ⌘1–⌘5
/// (`Config.questionContinueIn` says which, in which order). The text goes to the service the user picks, as it was
/// shown: values hidden from our own requests (`Redaction`) are in it as they are, since the user chooses to send it
/// there.
public enum ChatHandoff {
    public enum Destination: String, Codable, CaseIterable, Equatable, Sendable {
        /// The coding agent `@agent` hands to (`Config.agent`: Claude Code by default, whose name the config's
        /// `claudeCode` keeps), in Terminal, interactive, with the conversation as its first message.
        case claudeCode
        case claudeWeb
        case chatgpt
        case gemini
        /// The conversation on the clipboard, in Markdown.
        case copy
    }

    /// What the choices are when the config doesn't say: the agent `@agent` hands to (when it's installed,
    /// `agentInstalled`), Claude on the web, ChatGPT, then copying. Gemini can be added in the settings.
    public static func defaultChoices(claudeCode installed: Bool) -> [Destination] {
        (installed ? [.claudeCode] : []) + [.claudeWeb, .chatgpt, .copy]
    }

    /// The choices offered: `configured` (`Config.questionContinueIn`; nil: `defaultChoices`) in its order, each once,
    /// without the agent when it isn't installed. Never none: copying is always possible.
    public static func choices(_ configured: [Destination]?, claudeCode installed: Bool) -> [Destination] {
        var seen = Set<Destination>()
        let list = (configured ?? defaultChoices(claudeCode: installed))
            .filter { ($0 != .claudeCode || installed) && seen.insert($0).inserted }
        return list.isEmpty ? [.copy] : list
    }

    /// Whether `.claudeCode`, the agent `@agent` hands to, can be offered: that agent's program (`AgentKind.program`) is
    /// on this Mac, as `installed` finds it. Another agent being installed (Claude Code, say) doesn't stand in for it; a
    /// custom agent without a command never is.
    public static func agentInstalled(_ config: Config, installed: (String) -> Bool) -> Bool {
        config.agent.program(custom: config.agentCommand).map(installed) ?? false
    }

    // MARK: - The text

    /// What ends the conversation handed over, before the follow-up typed (if any).
    public static let continuation = "Let's continue this discussion."

    /// The conversation in Markdown: "**Q:** …" and "**A:** …" paragraphs, oldest first (rounds without an answer
    /// yet have only their question). `selection`: the text selected in the field that the first question was about, as
    /// a quoted block before them ("**Selected text:**", then each of its lines after "> ").
    public static func markdown(_ rounds: [QuestionChat.Round], selection: String? = nil) -> String {
        let quoted = selection.map { $0.trimmingCharacters(in: .newlines) }.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }.map {
            "**Selected text:**\n\n" + $0.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
        }
        return ([quoted].compactMap { $0 } + rounds.flatMap { round -> [String] in
            let answer = round.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            return ["**Q:** " + round.question.trimmingCharacters(in: .whitespacesAndNewlines)] + (answer.isEmpty ? [] : ["**A:** " + answer])
        }).joined(separator: "\n\n")
    }

    /// The first message of the conversation where it goes on: the selected text it was about (if any), the rounds,
    /// "Let's continue this discussion.", and the follow-up typed, if any.
    public static func prompt(_ rounds: [QuestionChat.Round], followUp: String = "", selection: String? = nil) -> String {
        let next = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        return markdown(rounds, selection: selection) + "\n\n" + continuation + (next.isEmpty ? "" : "\n\n" + next)
    }

    /// What "copy" puts on the clipboard: the selected text (if any), the rounds, and the follow-up typed as the next
    /// question.
    public static func copied(_ rounds: [QuestionChat.Round], followUp: String = "", selection: String? = nil) -> String {
        let next = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        return markdown(rounds + (next.isEmpty ? [] : [QuestionChat.Round(question: next, answer: "")]), selection: selection)
    }

    // MARK: - Where it goes

    /// The longest web address that carries the conversation (`?q=`); a longer one goes on the clipboard instead.
    public static let maxURLLength = 6000

    /// What picking `destination` does with `prompt` (`prompt(_:followUp:)`), and `copied` for copying.
    public enum Action: Equatable, Sendable {
        /// Start the agent `@agent` hands to in Terminal with `prompt` as its first message.
        case claudeCode(prompt: String)
        /// Open `url`; with `clipboard`, that text is put on the clipboard first, to paste there.
        case open(URL, clipboard: String?)
        /// Put `text` on the clipboard.
        case copy(String)
    }

    public static func action(_ destination: Destination, prompt: String, copied: String) -> Action {
        switch destination {
        case .claudeCode: return .claudeCode(prompt: prompt)
        case .claudeWeb: return web("https://claude.ai/new", prompt)
        case .chatgpt: return web("https://chatgpt.com/", prompt)
        // No way to fill its message box from the address that works reliably.
        case .gemini: return .open(URL(string: "https://gemini.google.com/app")!, clipboard: prompt)
        case .copy: return .copy(copied)
        }
    }

    /// `base` with `?q=` and the text, when that is no longer than `maxURLLength`; else `base`, the text on the clipboard.
    static func web(_ base: String, _ text: String) -> Action {
        if let encoded = text.addingPercentEncoding(withAllowedCharacters: queryAllowed), base.count + 3 + encoded.count <= maxURLLength,
           let url = URL(string: base + "?q=" + encoded) {
            return .open(url, clipboard: nil)
        }
        return .open(URL(string: base)!, clipboard: text)
    }

    /// The characters left as they are in a query's value: unreserved ones only (`&`, `+`, `=`, `#` … are encoded).
    static let queryAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}

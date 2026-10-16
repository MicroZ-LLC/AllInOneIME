import Foundation

/// Going on with an `@question` conversation elsewhere (`QuestionChat`): after the last round the panel allows
/// (`Config.questionRounds`), or at any round with ⌘⏎, it offers the coding agents installed here (the one `@agent` hands
/// to first, then the others), Claude, ChatGPT or Gemini on the web, or copying the conversation, picked with ⌘1–⌘9
/// (`Config.questionContinueIn` says which, in which order). The text goes to the service the user picks, as it was
/// shown: values hidden from our own requests (`Redaction`) are in it as they are, since the user chooses to send it
/// there.
public enum ChatHandoff {
    public enum Destination: String, Codable, CaseIterable, Equatable, Sendable {
        /// Whatever `@agent` hands to (`Config.agent`), by that agent's name: a list with it follows the agent picked
        /// (the default list starts with it). It stands for that agent's own entry in the same list, which is then left
        /// out. Never a choice itself: `choices` puts the agent's own in its place.
        case atAgent = "agent"
        /// Claude Code in Terminal, interactive, with the conversation as its first message, started as `@agent` starts
        /// it (`AgentKind.terminalArguments`).
        case claudeCode
        /// Gemini CLI, Kiro CLI and the custom agent (`Config.agentCommand`), likewise.
        case geminiCLI, kiroCLI, customAgent
        case claudeWeb
        case chatgpt
        case gemini
        /// The conversation on the clipboard, in Markdown.
        case copy

        /// The one that starts `agent` in Terminal.
        public init(agent: AgentKind) {
            switch agent {
            case .claude: self = .claudeCode
            case .gemini: self = .geminiCLI
            case .kiro: self = .kiroCLI
            case .custom: self = .customAgent
            }
        }

        /// The coding agent it starts in Terminal; nil for the web and copying.
        public var agent: AgentKind? {
            switch self {
            case .claudeCode: return .claude
            case .geminiCLI: return .gemini
            case .kiroCLI: return .kiro
            case .customAgent: return .custom
            case .atAgent, .claudeWeb, .chatgpt, .gemini, .copy: return nil
            }
        }
    }

    /// The list the choices come from when the config doesn't say: `@agent`'s agent, every agent, then Claude on the web,
    /// ChatGPT and copying. Gemini on the web can be added in the settings.
    public static let defaultList: [Destination] = [.atAgent, .claudeCode, .geminiCLI, .kiroCLI, .customAgent, .claudeWeb, .chatgpt, .copy]

    /// What the choices are when the config doesn't say (`defaultList`): the agent `@agent` hands to (`picked`) first, so
    /// ⌘1 is it, then the other agents (Claude Code, Gemini CLI, Kiro CLI, the custom one), each only when `installed`;
    /// then Claude on the web, ChatGPT and copying.
    public static func defaultChoices(picked: AgentKind, installed: (AgentKind) -> Bool) -> [Destination] {
        choices(nil, picked: picked, installed: installed)
    }

    /// The choices offered: `configured` (`Config.questionContinueIn`; nil: `defaultList`) as `shownIndices` has it, in its
    /// order, with `.atAgent` as `picked`'s own entry. Never none: copying is always possible.
    public static func choices(_ configured: [Destination]?, picked: AgentKind, installed: (AgentKind) -> Bool) -> [Destination] {
        let list = configured ?? defaultList
        let offered = shownIndices(list, picked: picked, installed: installed)
            .map { list[$0] == .atAgent ? Destination(agent: picked) : list[$0] }
        return offered.isEmpty ? [.copy] : offered
    }

    /// The entries of `list` offered now, by place: each once; an agent only when `installed`; `.atAgent` when `picked`
    /// is, and with it in the list `picked`'s own entry is left out (`.atAgent` stands for it).
    public static func shownIndices(_ list: [Destination], picked: AgentKind, installed: (AgentKind) -> Bool) -> [Int] {
        let follows = list.contains(.atAgent)
        var seen = Set<Destination>()
        return list.indices.filter { index in
            let entry = list[index]
            if entry == .atAgent {
                return installed(picked) && seen.insert(Destination(agent: picked)).inserted
            }
            if let kind = entry.agent, (follows && kind == picked) || !installed(kind) { return false }
            return seen.insert(entry).inserted
        }
    }

    /// `list` after an edit in Settings of the entries it offers (`shown`, as `shownIndices` found them): `edited` is
    /// what they are now, reordered, one taken out or one added (at the end). The entries not offered (an agent not
    /// installed right now, the agent `.atAgent` stands for) keep their places; only one taken out goes (and any other
    /// copy of it).
    public static func edited(_ list: [Destination], shown: [Int], to edited: [Destination]) -> [Destination] {
        let before = shown.map { list[$0] }
        let removed = Set(before).subtracting(edited)
        var order = edited.filter(before.contains)[...]
        var result: [Destination] = []
        for (index, entry) in list.enumerated() where !removed.contains(entry) {
            result.append(shown.contains(index) ? order.popFirst() ?? entry : entry)
        }
        return result + order + edited.filter { !before.contains($0) }
    }

    /// Whether `kind` can be offered: its program (`AgentKind.program`, a custom one's from `config.agentCommand`) is on
    /// this Mac, as `program` finds it. A custom agent without a command never is.
    public static func installed(_ kind: AgentKind, in config: Config, program: (String) -> Bool) -> Bool {
        kind.program(custom: config.agentCommand).map(program) ?? false
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
        /// Start `agent` in Terminal with `prompt` as its first message, as `@agent` starts it.
        case agent(AgentKind, prompt: String)
        /// Open `url`; with `clipboard`, that text is put on the clipboard first, to paste there.
        case open(URL, clipboard: String?)
        /// Put `text` on the clipboard.
        case copy(String)
    }

    public static func action(_ destination: Destination, prompt: String, copied: String) -> Action {
        switch destination {
        // Never a choice (`choices` puts the agent's own in its place): Claude Code, `@agent`'s default.
        case .atAgent: return .agent(.claude, prompt: prompt)
        case .claudeCode: return .agent(.claude, prompt: prompt)
        case .geminiCLI: return .agent(.gemini, prompt: prompt)
        case .kiroCLI: return .agent(.kiro, prompt: prompt)
        case .customAgent: return .agent(.custom, prompt: prompt)
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

import Foundation

/// A custom command tried once from its editor (Settings → Commands → a command's Test run), on a sample of the text it
/// takes: what is typed after it, or the text selected when nothing is (a snippet's `{selection}`, where it takes no
/// typed text). It runs as a real run does, with the same timeouts and limits, and what it would put in the app is
/// shown instead: never inserted, opened or typed anywhere. What it shows:
///
/// - `run`: what the program printed (`CommandRunner`: its timeout, 64 KB at most);
/// - `terminal`: the same program run in the background instead of a Terminal window, with a `run` command's default
///   timeout, and what it printed;
/// - `link`: the web address it would open (not opened);
/// - `snippet`: the text it would insert, `{clipboard}` (and `{selection}`, when the sample is the typed text) as
///   samples (‹clipboard›), the caret's place as ▏;
/// - `prompt`: the AI's answer, from the provider in use; the sample is sent to it only once the user agreed
///   (`confirmation`, asked first: `asks`).
///
/// A `suggestions` command has no test run: its Status has Refresh Now.
public enum CommandTrial {
    /// Why a test run gave nothing, in the interface language (as a real run says it: "Type something after the
    /// command").
    public struct Refusal: Error, Equatable, InterfaceDescribedError {
        public var message: String
        public var interfaceDescription: String? { message }

        public init(_ message: String) { self.message = message }
    }

    /// An AI instruction's answer to the sample (`ask`, or a test's own).
    public typealias Asker = @Sendable (CustomCommand, String) async throws -> String

    /// Whether a command of `type` has a test run: all but a suggestion source.
    public static func offered(_ type: CustomCommand.CommandType) -> Bool { type != .suggestions }

    /// Whether its test run sends the sample to the AI: the user is asked first (`confirmation`).
    public static func asks(_ type: CustomCommand.CommandType) -> Bool { type == .prompt }

    /// What the user is asked before an AI instruction's test run: "This sends the sample to Claude API".
    public static func confirmation(_ config: Config) -> String {
        let provider = UIText.name(config.provider)
        return tr("这会把样例发给\(provider)", "This sends the sample to \(provider)", key: "commandTrial.sends")
    }

    /// `command` run once on `sample` (`CommandTrial`): what it would put in, or an error that says why it gave
    /// nothing (`UIText.describe`). `ask` answers an AI instruction: call it only once the user agreed (`asks`).
    /// Cancelling the task stops it (a program as Esc stops it).
    public static func run(_ command: CustomCommand, sample: String, ask: Asker) async throws -> String {
        let messages = Composer.Messages.make(language: UIText.language)
        // What the command needs to run (a program, an address …); its name doesn't matter here.
        switch command.problem(among: []) {
        case nil, .emptyName?, .nameNotLetters?, .nameTaken?: break
        case let problem?: throw Refusal(UIText.describe(problem))
        }
        if command.type == .snippet { return try snippet(command, sample: sample, messages: messages) }
        guard !sample.isEmpty else { throw Refusal(messages.typeAfterCommand) }
        let output: String
        switch command.type {
        case .prompt:
            output = try await ask(command, sample)
        case .run:
            output = try await finalOutput(CommandRunner.run(command, input: sample))
        case .terminal:
            output = try await CommandRunner.output(command.arguments(for: sample), stdin: nil, timeout: CustomCommand.defaultTimeout,
                                                    maxOutput: CommandRunner.maxOutputBytes)
        case .link:
            guard sample.count <= LinkTemplate.maxInputLength else { throw Refusal(messages.linkTooLong) }
            guard let url = LinkTemplate.url(command.url ?? "", input: sample) else { throw Refusal(messages.noResult) }
            output = url.absoluteString
        case .snippet, .suggestions:
            throw Refusal(messages.noResult)
        }
        try Task.checkCancellation()
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Refusal(messages.noResult) }
        return output
    }

    /// The AI's answer to `sample`, as `command`'s real run asks the provider `config` sets (its hidden values hidden,
    /// its timeout): never from the answers kept.
    public static func ask(_ command: CustomCommand, sample: String, config: Config) async throws -> String {
        let converter = Converter(loadConfig: { config })
        let name = command.name.isEmpty ? "test" : command.name.lowercased()
        var answer = ""
        for try await update in converter.generate(Command(name: name, kind: .generate, custom: command), input: sample, fresh: true)
        where update.isFinal {
            answer = update.result.versions.map(\.text).joined(separator: "\n")
        }
        return answer
    }

    /// What a program printed, once it exited.
    private static func finalOutput(_ updates: AsyncThrowingStream<ConversionUpdate, Error>) async throws -> String {
        var output = ""
        for try await update in updates where update.isFinal { output = update.rawText }
        return output
    }

    /// The text a snippet would insert, its blanks filled from the sample as a real run fills them from the text after
    /// it (`Composer.insertSnippet`); the sample is the selection instead for one that takes no typed text but the
    /// selection.
    private static func snippet(_ command: CustomCommand, sample: String, messages: Composer.Messages) throws -> String {
        let text = command.text ?? ""
        guard text.count <= Composer.maxNoteLength else { throw Refusal(messages.snippetTooLong) }
        let template = SnippetTemplate.parse(text)
        let selected = !template.needsTyping && template.needs.contains(.selection)
        let typed = selected ? "" : sample
        var fields: [String] = []
        if !template.fieldLabels.isEmpty {
            fields = ScriptCommand.split(typed, into: template.fieldLabels.count)
            let missing = zip(template.fieldLabels, fields).filter { $0.1.isEmpty }.map(\.0)
            guard missing.isEmpty else { throw Refusal(messages.scriptNeeds + missing.joined(separator: ", ")) }
        } else if template.needs.contains(.input), typed.isEmpty {
            throw Refusal(messages.typeAfterCommand)
        }
        let values = SnippetValues(input: typed, fields: fields, clipboard: "‹clipboard›", selection: selected ? sample : "‹selection›",
                                   timeZone: .current, locale: Locale(identifier: UIText.language))
        var rendered = template.render(values)
        if !template.needsTyping, !typed.isEmpty {
            rendered.text += " " + typed
            rendered.caretBack = rendered.caretBack.map { $0 + 1 + typed.utf16.count }
        }
        guard rendered.text.count <= Composer.maxNoteLength else { throw Refusal(messages.snippetTooLong) }
        guard let back = rendered.caretBack else { return rendered.text }
        let units = Array(rendered.text.utf16)
        let at = max(units.count - back, 0)
        return String(decoding: units[..<at], as: UTF16.self) + "▏" + String(decoding: units[at...], as: UTF16.self)
    }
}

import Foundation

/// One @ (0.7.0): the magic key, then whatever the user wants. The list says what can be done with the text, the likeliest
/// first, each row what ⏎ does with it: the commands its letters start (a power user's `@tr`), what is known at once
/// (a sum's value, a web address, an app or folder, a reminder for a time in it), the writing actions (Improve,
/// Translate, the user's own AI instructions once used), and Ask AI last, so that nothing is a dead end. Nothing is sent,
/// run or read before ⏎. The same on every platform: the sources are the session's services (an app index, a reminder's
/// reading of a time); where a platform has none, those rows don't appear.
public enum OneAt {
    /// What a row does with ⏎.
    public enum Action: Equatable, Sendable {
        /// A command found by its name (or its summary, title, keywords): picked as the command list picks it.
        case command(Command)
        /// A sum's value (`Arithmetic`): it goes in place of the text.
        case value(String)
        /// A web address, an app, a folder or a file: opened.
        case open(SearchResult)
        /// A time read from the text: the reminder, added.
        case reminder(ReminderDraft)
        /// A writing action on the text, or on the selection: what `@name text` does (`@improve`, `@translate`,
        /// `@question`, `@reply`, a prompt command, a plugin that takes text).
        case write(Command)
        /// The selection rewritten as the text typed says (`Command.edit`, what `@improve text` does on a selection).
        case edit

        /// What tells two rows apart while the list changes: a highlight stays on its row.
        public var id: String {
            switch self {
            case let .command(command): return "command:" + command.name
            case let .value(value): return "value:" + value
            case let .open(result): return "open:" + result.path
            case let .reminder(reminder): return "reminder:" + reminder.title
            case let .write(command): return "write:" + command.name
            case .edit: return "edit"
            }
        }

        /// The command whose use it counts for (`CommandUsage`), and whose name the row shows, dimmed.
        public var command: Command? {
            switch self {
            case let .command(command), let .write(command): return command
            case .value: return nil
            case .open: return .open
            case .reminder: return .reminder
            case .edit: return .improve
            }
        }
    }

    /// What the rows are worked out from.
    public struct Input {
        /// The text after the magic key, as it would be with the pinyin's first candidate.
        public var text: String
        /// The letters right after the key while they are a name being typed (English) or composed as pinyin: what
        /// command names and an app's pinyin or initials are looked up by. Nil: none.
        public var letters: String?
        /// The text selected in the field when the key was typed (nil: none).
        public var selection: String?
        /// The commands offered, and those whose name the letters start, in the order the command list has them
        /// (`Command.palette`).
        public var commands: [Command]
        public var named: [Command]
        public var usage: CommandUsage
        /// The app typed in (its bundle id), whether it is a chat app, whether it has No AI (`AppProfile.noAI`).
        public var app: String?
        public var chat: Bool
        public var noAI: Bool
        /// The first of the input languages.
        public var mainLanguage: Language
        /// What is known at once for a text (`SessionServices.instantResults`), and the files Spotlight found for this
        /// one so far.
        public var instant: (String) -> [SearchResult]
        public var files: [SearchResult]
        /// The reminder for a time in the text (`SessionServices.parseReminder`); nil: none there.
        public var reminder: (String) -> ReminderDraft?
        /// The words of the user's commands (summary, title, keywords), split and folded as `OneAt.words` does: what a
        /// text finds them by besides their names.
        public var words: (Command) -> [String]

        public init(text: String, letters: String? = nil, selection: String? = nil, commands: [Command], named: [Command] = [],
                    usage: CommandUsage = CommandUsage(), app: String? = nil, chat: Bool = false, noAI: Bool = false,
                    mainLanguage: Language = .chinese, instant: @escaping (String) -> [SearchResult] = { _ in [] },
                    files: [SearchResult] = [], reminder: @escaping (String) -> ReminderDraft? = { _ in nil },
                    words: @escaping (Command) -> [String] = { _ in [] }) {
            self.text = text
            self.letters = letters
            self.selection = selection
            self.commands = commands
            self.named = named
            self.usage = usage
            self.app = app
            self.chat = chat
            self.noAI = noAI
            self.mainLanguage = mainLanguage
            self.instant = instant
            self.files = files
            self.reminder = reminder
            self.words = words
        }
    }

    /// The most apps, folders and files listed for a text: what is known at once, and as many of Spotlight's files.
    public static let openLimit = 3
    /// The most of the user's own writing actions listed for a sentence or a selection.
    public static let ownLimit = 3

    /// The rows for `input`, in order ("The order, exactly"): the first rule that applies decides the first row, the
    /// others that apply follow in the same order, then the writing actions by use in this app (then overall), Ask AI last
    /// unless a question put it first. With a selection and nothing typed: Reply first in a chat app, Translate or Improve
    /// by the selected text, the writing actions, Ask AI about it last; text typed with a selection is an instruction for
    /// it. AI rows aren't offered in an app with No AI, nor Reply outside chat apps, nor a command that is off.
    public static func actions(_ input: Input) -> [Action] {
        let text = input.text.trimmingCharacters(in: .whitespaces)
        let ai = !input.noAI
        // The built-in writing actions, where they are offered (not off): the catalog has them first.
        let builtins = input.commands.prefix { $0.custom == nil && $0.plugin == nil && $0.script == nil }
        func offered(_ command: Command) -> Command? { builtins.first { $0.name == command.name } }
        var rows: [Action] = []
        var listed = Set<String>()
        func add(_ action: Action) { if listed.insert(action.id).inserted { rows.append(action) } }

        if let selection = input.selection {
            // Letters that start a command's name put it first here too.
            input.named.forEach { add(.command($0)) }
            if !text.isEmpty {
                // An instruction for the selection ("改正式一点"), then a reply that says it, then a question about it.
                if ai, offered(.improve) != nil { add(.edit) }
                if ai, input.chat, let reply = offered(.reply) { add(.write(reply)) }
                if ai, let question = offered(.question) { add(.write(question)) }
                return rows
            }
            if ai, input.chat, let reply = offered(.reply) { add(.write(reply)) }
            let other = isOtherLanguage(selection, main: input.mainLanguage)
            if ai, let first = offered(other ? .translate : .improve) { add(.write(first)) }
            writingActions(input, other: other).forEach { add(.write($0)) }
            if ai, let question = offered(.question) { add(.write(question)) }
            return rows
        }

        // Nothing typed: the command list, the most used (here first) on top; without AI here, the commands that don't
        // use it.
        guard !text.isEmpty || input.letters?.isEmpty == false else {
            let all = input.named.isEmpty ? Command.palette("", in: input.commands, usage: input.usage, app: input.app, limit: .max) : input.named
            return all.filter { ai || !$0.usesAI }.map(Action.command)
        }

        // 1. The commands the letters start, then the user's own found by their words.
        input.named.forEach { add(.command($0)) }
        for command in found(byWords: text, input) where ai || !command.usesAI { add(.command(command)) }
        var ruled = false
        // 2. A sum: its value.
        if let value = Arithmetic.value(of: text) {
            add(.value(Arithmetic.format(value)))
            ruled = true
        }
        // 3. A web address: opened in the browser.
        let web = SearchResult.web(text)
        if let web {
            add(.open(web))
            ruled = true
        }
        // 4. An app, a folder, a file opened before (what is known at once): by the letters (an app's pinyin or
        // initials), then by the text. Spotlight's files join below all the rows (`withFiles`).
        var instant: ArraySlice<SearchResult> = []
        if web == nil, Arithmetic.value(of: text) == nil {
            var known: [SearchResult] = []
            for query in [input.letters, text].compactMap({ $0 }) where !query.isEmpty {
                for result in input.instant(query) where !known.contains(where: { $0.path == result.path }) { known.append(result) }
            }
            instant = known.prefix(openLimit)
            instant.forEach { add(.open($0)) }
            if !instant.isEmpty { ruled = true }
        }
        // 5. A time: the reminder, the rest of the text its title.
        if let reminder = input.reminder(text), reminder.due != nil, !reminder.title.isEmpty {
            add(.reminder(reminder))
            ruled = true
        }
        // 6. A question: Ask AI.
        let question = isQuestion(text)
        if question, ai, let ask = offered(.question), !input.named.contains(ask) {
            add(.write(ask))
            ruled = true
        }
        // 7. Mostly another language than the main input language: Translate.
        let other = isOtherLanguage(text, main: input.mainLanguage)
        if other, ai, let translate = offered(.translate), !input.named.contains(translate) {
            add(.write(translate))
            ruled = true
        }
        // 8. Otherwise (no earlier rule applied): Improve.
        if !ruled, input.named.isEmpty, ai, let improve = offered(.improve) { add(.write(improve)) }
        // The writing actions by use, then Ask AI last; not one whose command the letters named (its row is there).
        let named = Set(input.named.map(\.name))
        writingActions(input, other: other).filter { !named.contains($0.name) }.forEach { add(.write($0)) }
        if ai, let ask = offered(.question), !named.contains(ask.name) { add(.write(ask)) }
        let files = input.files.filter { file in !instant.contains { $0.path == file.path } }.prefix(openLimit)
        return withFiles(rows, files.map(Action.open))
    }

    /// `rows` with Spotlight's files: they come after the rows are shown, so they never take the first row nor move the
    /// highlight (⏎ does the same whether Spotlight answered yet or not): below the rows, above Ask AI when it is the
    /// last; none where there is no row of the rules (nothing to keep first).
    static func withFiles(_ rows: [Action], _ files: [Action]) -> [Action] {
        let files = files.filter { !rows.contains($0) }
        guard !rows.isEmpty, !files.isEmpty else { return rows }
        let ask = rows.count > 1 && rows.last == .write(.question) ? 1 : 0
        return Array(rows.dropLast(ask)) + files + rows.suffix(ask)
    }

    /// Improve and Translate, and the user's own writing actions once used (at most `ownLimit`: the most used in this app,
    /// then overall), by use in this app, then overall; ties in the order the text gives (Translate first for another
    /// language, else Improve), the user's after them in the catalog's. Without AI here, none (each is the AI's).
    static func writingActions(_ input: Input, other: Bool) -> [Command] {
        let builtins = Set(input.commands.prefix { $0.custom == nil && $0.plugin == nil && $0.script == nil }.map(\.name))
        var actions: [Command] = []
        if !input.noAI {
            actions += (other ? [Command.translate, .improve] : [.improve, .translate]).filter { builtins.contains($0.name) }
        }
        // The user's own used anywhere, the most used in this app first, then overall, then in the catalog's order.
        let own = input.commands.enumerated().filter { _, command in
            takesText(command) && (!input.noAI || !command.usesAI) && input.usage.score(command.name) > 0
        }.map { offset, command in
            (command, here: input.usage.score(command.name, in: input.app), all: input.usage.score(command.name), offset)
        }.sorted { a, b in
            if a.here != b.here { return a.here > b.here }
            if a.all != b.all { return a.all > b.all }
            return a.3 < b.3
        }.prefix(ownLimit).map(\.0)
        actions += own
        let order = Dictionary(actions.enumerated().map { ($0.element.name, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return actions.sorted { a, b in
            let (inA, inB) = (input.usage.score(a.name, in: input.app), input.usage.score(b.name, in: input.app))
            if inA != inB { return inA > inB }
            let (allA, allB) = (input.usage.score(a.name), input.usage.score(b.name))
            if allA != allB { return allA > allB }
            return order[a.name]! < order[b.name]!
        }
    }

    /// Whether `command` is one of the user's own writing actions: a prompt command (an AI instruction), a prompt plugin
    /// (one that sends the text to the AI with its instruction). Never a `run`, `terminal` or `link` command, a script or
    /// link plugin, a snippet or a script extension: those are offered only by what the text says of them
    /// (`found(byWords:)`).
    static func takesText(_ command: Command) -> Bool {
        if let plugin = command.plugin { return plugin.manifest.type == .prompt }
        return command.custom?.type == .prompt && command.script == nil
    }

    /// The user's own commands (custom ones, plugins, script extensions, snippets) whose words (`Input.words`: summary,
    /// title, keywords) each word of `text` starts, in any language (Chinese anywhere in them: "签名" in "邮件签名"), in the
    /// catalog's order. Not the built-in ones: those are found by name.
    static func found(byWords text: String, _ input: Input) -> [Command] {
        let keywords = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !keywords.isEmpty, text.count <= 60 else { return [] }
        let named = Set(input.named.map(\.name))
        return input.commands.filter { command in
            guard command.custom != nil || command.plugin != nil || command.script != nil, !named.contains(command.name) else { return false }
            let words = input.words(command)
            return !words.isEmpty && keywords.allSatisfy { keyword in
                keyword.containsHan ? words.contains { $0.contains(keyword) } : words.contains { $0.hasPrefix(keyword) }
            }
        }
    }

    /// `text`'s words, lowercased and without accents: split where there is neither a letter nor a digit.
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    // MARK: - What the text is

    /// The Chinese that makes a sentence a question.
    static let chineseQuestionWords = ["吗", "呢", "什么", "怎么", "为什么", "哪", "几", "多少"]
    /// The English words a question starts with.
    static let englishQuestionWords: Set<String> = ["how", "what", "why", "when", "where", "who", "which", "can", "could",
                                                     "should", "is", "are", "do", "does"]

    /// Whether `text` is a question: it ends with "?" or "？", has 吗 呢 什么 怎么 为什么 哪 几 多少 in it, or starts with
    /// how, what, why, when, where, who, which, can, could, should, is, are, do or does.
    public static func isQuestion(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("?") || text.hasSuffix("？") { return true }
        if chineseQuestionWords.contains(where: { text.contains($0) }) { return true }
        let first = text.prefix { $0.isLetter || $0 == "'" }.lowercased()
        return englishQuestionWords.contains(first)
    }

    /// The language most of `text` is in: Chinese by its Han characters, else by `Language.of`, a Latin word counting as
    /// two characters (a Chinese sentence with an English name in it is Chinese).
    public static func mostly(_ text: String) -> Language {
        var han = 0, latinWords = 0, inWord = false
        for character in text {
            if String(character).containsHan {
                han += 1
                inWord = false
            } else if character.isLetter {
                if !inWord { latinWords += 1 }
                inWord = true
            } else {
                inWord = false
            }
        }
        if han > 0, han >= 2 * latinWords { return .chinese }
        let rest = String(String.UnicodeScalarView(text.unicodeScalars.filter { !String($0).containsHan }))
        return Language.of(rest)
    }

    /// Whether `text` is mostly in another language than `main` (letters only: a sum or an address has none).
    static func isOtherLanguage(_ text: String, main: Language) -> Bool {
        guard text.contains(where: \.isLetter) else { return false }
        return mostly(text) != main
    }
}

/// Arithmetic for one @: a small evaluator of numbers and `+ - * / × ÷ ( ) % ^ .` only (their full-width forms too, as
/// pinyin types them), never a script engine on the text. `%` after a number is percent ("200*15%" is 30), `^` a power,
/// right to left. All of the text must be a sum with at least one operator ("3" alone is no sum).
public enum Arithmetic {
    /// The value of `text`, or nil when it isn't all a sum (a letter, an unknown sign, unbalanced brackets, a division by
    /// zero, a value too large).
    public static func value(of text: String) -> Double? {
        let normalized = text.unicodeScalars.map { scalar -> Character in
            // Full-width ASCII (＋－＊／（）％＾．０–９), as pinyin may type them.
            if (0xFF01...0xFF5E).contains(scalar.value), let ascii = Unicode.Scalar(scalar.value - 0xFEE0) { return Character(ascii) }
            switch scalar {
            case "×": return "*"
            case "÷": return "/"
            case "−": return "-"
            case "。": return "."
            default: return Character(scalar)
            }
        }
        guard normalized.count <= 200, normalized.contains(where: \.isNumber) else { return nil }
        var parser = Parser(characters: normalized.filter { !$0.isWhitespace })
        guard let value = parser.sum(), parser.atEnd, parser.operators > 0, value.isFinite else { return nil }
        return value
    }

    /// `value` as it goes in: an integer without a point ("23"), else up to 12 significant digits, no trailing zeros
    /// ("3.5", "0.3").
    public static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.12g", value)
        if text.contains("."), !text.contains("e") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// A recursive-descent parser: sum = product (("+" | "-") product)*; product = power (("*" | "/") power)*;
    /// power = unary ("^" power)?; unary = "-" unary | "+" unary | postfix; postfix = atom "%"*; atom = number | "(" sum ")".
    private struct Parser {
        let characters: [Character]
        var at = 0
        /// How many operators were read: a sum has one at least.
        var operators = 0

        init(characters: [Character]) { self.characters = characters }

        var atEnd: Bool { at == characters.count }
        private var next: Character? { at < characters.count ? characters[at] : nil }

        mutating func sum() -> Double? {
            guard var value = product() else { return nil }
            while let sign = next, sign == "+" || sign == "-" {
                at += 1
                operators += 1
                guard let right = product() else { return nil }
                value = sign == "+" ? value + right : value - right
            }
            return value
        }

        mutating func product() -> Double? {
            guard var value = power() else { return nil }
            while let sign = next, sign == "*" || sign == "/" {
                at += 1
                operators += 1
                guard let right = power() else { return nil }
                if sign == "/" {
                    guard right != 0 else { return nil }
                    value /= right
                } else {
                    value *= right
                }
            }
            return value
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            guard next == "^" else { return base }
            at += 1
            operators += 1
            guard let exponent = power(), abs(exponent) <= 1000 else { return nil }
            return pow(base, exponent)
        }

        mutating func unary() -> Double? {
            if next == "-" || next == "+" {
                let negative = next == "-"
                at += 1
                return unary().map { negative ? -$0 : $0 }
            }
            guard var value = atom() else { return nil }
            while next == "%" {
                at += 1
                operators += 1
                value /= 100
            }
            return value
        }

        mutating func atom() -> Double? {
            if next == "(" {
                at += 1
                guard let value = sum(), next == ")" else { return nil }
                at += 1
                return value
            }
            var digits = ""
            while let c = next, c.isASCII, c.isNumber || c == "." {
                digits.append(c)
                at += 1
            }
            // "1.2.3", "." alone: no number.
            guard !digits.isEmpty, digits.filter({ $0 == "." }).count <= 1, digits != "." else { return nil }
            return Double(digits)
        }
    }
}

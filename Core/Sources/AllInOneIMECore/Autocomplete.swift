import Foundation

// MARK: - Autocomplete

/// Autocomplete (「续写」): after a pause in typing, the rest of the sentence in gray after the caret, from a model; Tab
/// puts it in. One switch (`Config.autocomplete`, the input menu and the menu bar panel); an app's own choice
/// (`AppProfile.autocomplete`; code editors are off until set so, `isCodeEditor`); in an app where none of the last 30
/// suggestions was taken it stops by itself (`Learning`).
///
/// The core has the logic: when it may run at all (`blocker`, `isOn`), how long the pause is (`Route.pause`), what is
/// sent (`context`, `Prompt.autocompleteRequest`, hidden values as usual), what of the answer is shown (`trimmed`), what
/// Tab does (`tab`), the suggestions kept for the text they continue (`Cache`), what is learned per app (`Learning`) and
/// counted (`Metrics`). The session runs it (InputSession+Autocomplete.swift): the pause is a timer, the field's text is
/// read once it's over (`SessionOutput.readField`), the request runs in a slot of its own that every key stops, and the
/// suggestion is an output (`SessionOutput.ghost`) the shell draws after the caret.
public enum Autocomplete {
    /// What goes with a request: the text before the caret (its last characters) and after it (`following`).
    public static let beforeLimit = 1500
    public static let afterLimit = 200
    /// The most a suggestion is: about a dozen words, or 25 characters of Chinese or Japanese, to the end of a sentence.
    public static let maxWords = 12
    public static let maxWideCharacters = 25
    /// A Tab this soon after the suggestion came up is the user's own (pressed before they could see it): it goes to the
    /// app, and the suggestion goes.
    public static let tabGrace: TimeInterval = 0.12
    /// ⌘Z as the next key this soon after Tab put a suggestion in takes it back: a Tab pressed out of habit (to indent, to
    /// take an editor's own completion), so the suggestion counts as not taken (`Metrics.undone`, `Learning.takenBack`).
    public static let undoWindow: TimeInterval = 5
    /// How long the model may say nothing before the request is given up.
    public static let timeout: TimeInterval = 4
    /// The answer's limit in tokens: a dozen words, with room to spare.
    public static let maxTokens = 48

    // MARK: The model

    /// The model a pause asks: Apple's on-device model, unless the user picked a cloud provider of their own
    /// (`offersCloud`) and agreed, once, to send it what is before the caret: there, as it is set now
    /// (`Config.autocompleteCloud`, `destination`). Where the on-device model can't run nothing is shown: it never turns
    /// to a cloud provider by itself.
    public enum Route: Equatable, Sendable {
        case onDevice
        case cloud(Provider)

        /// The shortest pause before asking (longer for one who types slowly, `Rhythm`): longer than the time between
        /// keys of most typing, so that a request goes when the user stops, not between two keys; a cloud model is
        /// asked less often.
        public var pause: TimeInterval { self == .onDevice ? 0.35 : 0.5 }
        /// A suggestion that comes later than this after it was asked for (the pause over) is dropped: late is worse
        /// than none.
        public var late: TimeInterval { self == .onDevice ? 2 : 3 }
    }

    public static func route(_ config: Config) -> Route {
        cloudAnswer(config) == true ? .cloud(config.provider) : .onDevice
    }

    /// Whether turning it on asks first: a cloud provider picked, and the user hasn't said yet whether it may go there,
    /// where its requests go now (`destination`): never asked, or asked about another provider, host, AWS profile or
    /// region.
    public static func asksForCloud(_ config: Config) -> Bool {
        destination(config) != nil && cloudAnswer(config) == nil
    }

    /// The user's answer about sending text where `config`'s requests go now (`destination`): true yes, false the
    /// on-device model only; nil not asked about it (an answer about another destination is none).
    public static func cloudAnswer(_ config: Config) -> Bool? {
        guard let destination = destination(config), let consent = config.autocompleteCloud, consent.destination == destination else {
            return nil
        }
        return consent.allowed
    }

    /// `yes` (or no) as the answer about where `config`'s requests go now; nothing for a provider it never asks.
    public static func answer(_ yes: Bool, in config: inout Config) {
        guard let destination = destination(config) else { return }
        config.autocompleteCloud = Consent(allowed: yes, destination: destination)
    }

    /// Where a request of autocomplete's would go with `config`'s cloud provider: the provider and the host its requests go
    /// to ("anthropic api.anthropic.com", "openai api.deepseek.com"); for Bedrock, the AWS profile and the region set
    /// (none: the profile's own), whose account and place they are ("bedrock default us-west-2"). Nil for one it never
    /// asks (`offersCloud`).
    public static func destination(_ config: Config) -> String? {
        guard offersCloud(config.provider) else { return nil }
        if config.provider == .bedrock {
            return ["bedrock", config.awsProfile, config.region ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
        return config.provider.rawValue + " " + (HTTPProviders.host(of: config.settings(for: config.provider)) ?? "")
    }

    /// The user's answer about sending the text before the caret to a cloud provider (`Config.autocompleteCloud`), and
    /// where it was about (`destination`).
    public struct Consent: Codable, Equatable, Sendable {
        /// Yes, it may send there; no, the on-device model only.
        public var allowed: Bool
        public var destination: String

        public init(allowed: Bool, destination: String) {
            self.allowed = allowed
            self.destination = destination
        }
    }

    /// Whether autocomplete may ask `provider`, once the user agreed: a cloud provider of the user's own (an API key, an
    /// AWS profile). Never AllInOneIME Cloud: its free requests a day are for the @ commands, and a few minutes of pauses
    /// would use them up (the day's commands would then all fail); with it picked, autocomplete uses the on-device model,
    /// and says why (`AIConfig.Text.autocompleteHostedOnDevice`, the Mac's input menu).
    public static func offersCloud(_ provider: Provider) -> Bool {
        provider != .apple && provider != .hosted
    }

    // MARK: Where it runs

    /// Whether it runs in `app` by the settings: the app's own choice (Settings → Apps), else the switch, unless it has
    /// stopped there for want of use (`stopped`, `Learning`) or the app is a code editor (`isCodeEditor`).
    public static func isOn(in app: String?, config: Config, stopped: Bool) -> Bool {
        if let own = config.profile(for: app)?.autocomplete { return own }
        return config.autocomplete && !stopped && !isCodeEditor(app)
    }

    /// Whether `app` (a bundle id, or a Windows app id; in any case) is a code editor (`CodeEditors`, which suggestions go
    /// by too): Tab indents there and takes the editor's own completion, which a gray suggestion would take instead, and
    /// what is written there is code. Off there unless the app is set to autocomplete always (`AppProfile.autocomplete`).
    public static func isCodeEditor(_ app: String?) -> Bool { CodeEditors.contains(app) }

    /// Why it never runs in a field, whatever the settings.
    public enum Blocker: Equatable, Sendable {
        /// Secure input is on (a password field, the lock screen), or the field is a password field.
        case secureInput
        /// A terminal: it runs what it's given, and tells nothing of its text.
        case terminal
        /// A remote desktop, a virtual machine or an SSH client (`EnglishWords.isRemote`): its password fields can't be told.
        case remote
        /// A password manager (`PasswordManagers`).
        case passwordManager
        /// The app has no AI (`AppProfile.noAI`).
        case noAI
        /// Translate as You Type is on.
        case translating
        /// Something is being written: pinyin, a command, a draft.
        case composing
    }

    /// Why it can't run in `field` now, if it can't.
    public static func blocker(in field: FieldInfo, secureInput: Bool, config: Config, composing: Bool, translating: Bool) -> Blocker? {
        if secureInput || field.secure { return .secureInput }
        if field.terminal { return .terminal }
        if EnglishWords.isRemote(field.app) { return .remote }
        if PasswordManagers.contains(field.app) { return .passwordManager }
        if !config.allowsAI(in: field.app) { return .noAI }
        if translating { return .translating }
        if composing { return .composing }
        return nil
    }

    // MARK: What is sent

    /// What a request continues: the text before the caret, the last `beforeLimit` characters of it, and what of the text
    /// after it a model needs so as not to write it again (`following`).
    public struct Context: Equatable, Sendable {
        public var before: String
        public var after: String

        public init(before: String, after: String = "") {
            self.before = before
            self.after = after
        }
    }

    /// What a request is made of, from what the field says (`text`; nil: it tells nothing, so what was typed into it since
    /// it took the focus, `typed`, stands in) and its selection (`selection`, UTF-16). Nil, and nothing asked: text
    /// selected, the caret not at the end of a line, no word on the line yet to go on from (`hasWord`), or a line that
    /// looks like a code or a card's number (digits and no letters).
    public static func context(_ text: FieldText?, selection: Range<Int>? = nil, typed: String = "") -> Context? {
        if let selection, !selection.isEmpty { return nil }
        let before = text?.before ?? typed
        let after = text?.after ?? ""
        // Only at the end of a line: nothing but spaces between the caret and the line's end.
        let rest = after.prefix { !$0.isNewline }
        guard rest.allSatisfy(\.isWhitespace) else { return nil }
        let line = before.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last.map(String.init) ?? ""
        guard line.filter({ !$0.isWhitespace }).count >= 2, hasWord(line) else { return nil }
        if looksLikeNumbers(line) { return nil }
        return Context(before: String(before.suffix(beforeLimit)), after: following(after))
    }

    /// What of the text after the caret goes with a request: up to the end of its first line with something on it (what a
    /// small model says again in place of a suggestion, and what the answer is checked against: `copiesWhatFollows`),
    /// `afterLimit` characters at most. Nothing past it, nor only spaces: the field's later lines aren't for the model to
    /// go on with.
    static func following(_ after: String) -> String {
        guard let start = after.firstIndex(where: { !$0.isWhitespace }) else { return "" }
        let end = after[start...].firstIndex(where: \.isNewline) ?? after.endIndex
        return String(after[..<end].prefix(afterLimit))
    }

    /// Whether `line` has a word to go on from: a whole one (a space or a mark after it: "Hi "), one of three letters
    /// or more ("iss"), or two Chinese or Japanese characters. One or two letters alone ("is") aren't: the model can
    /// only guess at what follows them.
    static func hasWord(_ line: String) -> Bool {
        if line.filter(\.isWide).count >= 2 { return true }
        var run = 0
        for character in line {
            if (character.isLetter || character.isNumber) && !character.isWide {
                run += 1
                if run >= 3 { return true }
            } else if run > 0 {
                return true
            }
        }
        return false
    }

    /// A line of digits with no letters (four or more digits): a one-time code, a card's number, a phone number.
    static func looksLikeNumbers(_ line: String) -> Bool {
        line.filter(\.isNumber).count >= 4 && !line.contains(where: \.isLetter)
    }

    // MARK: What is shown

    /// What of the model's answer `raw` is shown after `before`: its first line, without quotes around it or the end of
    /// `before` said again, up to the end of the first sentence, a dozen words or 25 Chinese characters at most (cut
    /// between words), spaces where they belong. Nil: nothing worth showing, as when it says what is already there, the
    /// text after the caret (`after`).
    public static func trimmed(_ raw: String, before: String, after: String = "") -> String? {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        // What the model put around it: tags, quotes, a code fence; a tag cut short at the end, where the answer was
        // read only that far or the model left it so ("…提升</", "</after").
        for tag in tags { text = text.replacingOccurrences(of: tag, with: "") }
        if let cut = tags.flatMap({ tag in (2..<tag.count).map { tag.prefix($0) } }).filter({ text.hasSuffix($0) && $0.first == "<" })
            .map(\.count).max() {
            text.removeLast(cut)
        }
        // The first line with something on it: the continuation starts on the caret's line.
        guard let first = text.split(separator: "\n", omittingEmptySubsequences: false).first(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else { return nil }
        var line = String(first).replacingOccurrences(of: "\t", with: " ")
        line = line.filter { !$0.isNewline && $0.unicodeScalars.allSatisfy(KeyEvent.isPrintable) }
        line = stripQuotes(line)
        // Chinese, Japanese or Korean after text with none of it ("Hi" + "你好。"): not the user's language.
        if line.contains(where: { $0.isWide && $0.isLetter }), !before.suffix(200).contains(where: \.isWide) { return nil }
        // Only the end of what was typed said again ("iss" after "iss"): nothing to add.
        if saysTheEndAgain(line, before: before) { return nil }
        // The end of what was typed said again ("…see you" → "see you tomorrow"), the unfinished word written whole
        // ("iss" → "issue"): only the rest.
        line = droppingEcho(line, before: before)
        line = droppingUnfinishedWord(line, before: before)
        // The text after the caret said again ("Frobnicate" with "\nFrobnicate" after it): it's there already.
        if copiesWhatFollows(line, after: after) { return nil }
        // An unfinished word gets its rest, never a word of its own glued on ("tomo" + "later").
        if gluesAWordOn(line, before: before, after: after) { return nil }
        // A space between words where the model left it out, none where it's wrong (after a space, a line's start, CJK).
        let last = before.last
        if last == nil || last!.isWhitespace || last!.isWide {
            line = String(line.drop { $0 == " " })
        } else if needsSpace(line, before: before) {
            line = " " + line
        }
        line = cut(line)
        while line.last == " " { line.removeLast() }
        guard line.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return line
    }

    /// What a model puts around an answer.
    static let tags = ["<continuation>", "</continuation>", "<after>", "</after>", "<before>", "</before>", "<caret>", "```"]

    /// Whether `raw` already holds all that would be shown (`trimmed`): a line's end, a sentence's end, or more words or
    /// Chinese characters than a suggestion has. The request stops reading there.
    public static func isEnough(_ raw: String) -> Bool {
        let body = raw.drop { $0.isWhitespace || $0.isNewline }
        if body.contains(where: \.isNewline) { return true }
        let text = String(body)
        if sentenceEnd(in: text) != nil { return true }
        return words(in: text) > maxWords || text.filter(\.isWide).count > maxWideCharacters
    }

    /// Whether `line` starts a new word after `before` though the model wrote no space (a small model often doesn't), when
    /// it starts with a Latin letter or a digit:
    /// - after a word on its own ("the" + "file", "to" + "another", "yesterday's" + "meeting") that isn't the start of
    ///   one `line` finishes ("wor" + "ld"), by the English words the core has (`isWord`);
    /// - after , ; : ! ? …, and a full stop before a capital or a digit ("update." + "I will") or after an abbreviation
    ///   ("e.g." + "grep"), not a number's ("3." + "5", "1," + "000", "10:" + "30");
    /// - after a digit, before a word ("room 4" + "on the second floor"), not "4" + "th" nor "3" + "pm".
    static func needsSpace(_ line: String, before: String) -> Bool {
        guard let last = before.last, let next = line.first, next.isASCII, next.isLetter || next.isNumber else { return false }
        let start = String(line.prefix { $0.isASCII && $0.isLetter }).lowercased()
        if last.isASCII, last.isLetter {
            let end = lastWord(before).lowercased()
            guard !start.isEmpty else { return false }
            return !isWord(end + start) && (isWord(end) || endsWithContraction(before))
        }
        let afterDigit = before.dropLast().last?.isNumber == true
        switch last {
        case ",", ";", ":": return !(afterDigit && next.isNumber)
        case "!", "?", "…": return true
        case ".":
            if afterDigit && next.isNumber { return false }
            return next.isUppercase || next.isNumber || endsWithAbbreviation(before.dropLast()) || before.hasSuffix("...")
        default:
            return last.isNumber && isWord(start) && !unitsAfterNumbers.contains(start)
        }
    }

    /// Words of one or two letters (the English word list has none): "to" + "another", "Hi" + "there".
    static let shortWords: Set<String> = [
        "a", "i", "am", "an", "as", "at", "be", "by", "do", "go", "he", "hi", "if", "in", "is", "it", "me", "my", "no", "of",
        "oh", "ok", "on", "or", "so", "to", "up", "us", "we",
    ]

    /// Words that go right after a number: "3am", "4a".
    static let unitsAfterNumbers: Set<String> = ["a", "am"]

    /// Whether `text` ends with an English contraction's ending, a word's end: "yesterday's", "don't", "we're", "I'll".
    static func endsWithContraction(_ text: String) -> Bool {
        let end = lastWord(text)
        let rest = text.dropLast(end.count)
        guard ["s", "t", "d", "m", "ll", "re", "ve"].contains(end.lowercased()), let mark = rest.last, mark == "'" || mark == "’"
        else { return false }
        return rest.dropLast().last?.isLetter == true
    }

    /// `text` up to the end of its first sentence, `maxWords` words and `maxWideCharacters` wide characters.
    static func cut(_ text: String) -> String {
        var out = text
        if let end = sentenceEnd(in: out) { out = String(out[..<end]) }
        var result = ""
        var words = 0, wide = 0
        var inWord = false
        for character in out {
            if character.isWide {
                wide += 1
                if wide > maxWideCharacters { break }
                inWord = false
            } else if character == " " {
                inWord = false
            } else if !inWord {
                inWord = true
                words += 1
                if words > maxWords { break }
            }
            result.append(character)
        }
        if result.count < out.count, !(result.last?.isWide ?? false) {
            // Cut between words: what was left of a word at the cut goes.
            if let space = result.lastIndex(of: " ") { result = String(result[..<space]) }
        }
        return result
    }

    /// Where the first sentence of `text` ends (after its mark, and a closing quote or bracket after it): 。！？ anywhere,
    /// . ! ? … followed by a space or the end of the text (not "3.5" nor "e.g.x", nor the full stop of "Mr." or "e.g.").
    static func sentenceEnd(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if "。！？.!?…".contains(character) {
                // The mark, and a closing quote or bracket after it.
                var end = text.index(after: index)
                while end < text.endIndex, "\"'”’」』）)]".contains(text[end]) { end = text.index(after: end) }
                // A Western mark ends a sentence before a space or the end only; not a full stop with nothing before it
                // ("..." starting the answer), nor an abbreviation's.
                let ends = "。！？".contains(character) || end == text.endIndex || text[end] == " "
                if ends, text[..<index].contains(where: { $0.isLetter || $0.isNumber }),
                   !(character == "." && endsWithAbbreviation(text[..<index])) { return end }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Abbreviations whose full stop doesn't end a sentence (in small letters, without their last full stop).
    static let abbreviations: Set<String> = ["mr", "mrs", "ms", "dr", "prof", "jr", "sr", "e.g", "i.e", "etc", "vs", "cf"]

    /// Whether `text` ends with one of `abbreviations`, a word of its own ("Mr" in "Please tell Mr", not "summer").
    static func endsWithAbbreviation(_ text: Substring) -> Bool {
        let word = text.reversed().prefix { $0.isLetter || $0 == "." }
        return abbreviations.contains(String(word.reversed()).lowercased())
    }

    /// Words (runs of anything but spaces and wide characters) in `text`, as `cut` counts them: the wide characters are
    /// counted apart (`maxWideCharacters`), so a Chinese answer isn't read only to its 12th character.
    static func words(in text: String) -> Int {
        var count = 0, inWord = false
        for character in text {
            if character.isWide {
                inWord = false
            } else if character == " " {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }

    /// `line` without quotes around all of it.
    static func stripQuotes(_ line: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'"), ("「", "」"), ("`", "`")]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for (open, close) in pairs where trimmed.count >= 2 && trimmed.first == open && trimmed.last == close {
            let inner = String(trimmed.dropFirst().dropLast())
            // A leading space the model meant stays (the line had one before the quote).
            return (line.first == " " ? " " : "") + inner
        }
        return line
    }

    /// `line` without what `before` ends with, when the model said that again: eight characters at least (three of them
    /// Chinese or Japanese), so that a continuation that only starts like the end of the text isn't cut.
    static func droppingEcho(_ line: String, before: String) -> String {
        let candidate = line.drop { $0 == " " }
        let tail = before.suffix(200)
        var length = min(candidate.count, tail.count)
        while length > 0 {
            let prefix = candidate.prefix(length)
            let enough = prefix.count >= 8 || prefix.filter(\.isWide).count >= 3
            if enough, tail.hasSuffix(prefix) {
                return String(candidate.dropFirst(length))
            }
            length -= 1
        }
        return line
    }

    /// Whether `line` says the text after the caret (`after`, its first line with something on it) again: its start, all
    /// of that line and more, or two words or more of it ("Frobnicate" with "\nFrobnicate" after the caret, "带伞" with
    /// "\n记得带伞"). By words (`tokens`), in any case, whatever the marks between them.
    static func copiesWhatFollows(_ line: String, after: String) -> Bool {
        guard let next = after.split(whereSeparator: \.isNewline).first(where: { !$0.allSatisfy(\.isWhitespace) }) else { return false }
        let said = tokens(line), there = tokens(String(next))
        guard !said.isEmpty, !there.isEmpty else { return false }
        if there.starts(with: said) || said.starts(with: there) { return true }
        return said.count >= 2 && there.count > said.count
            && (1...(there.count - said.count)).contains { there[$0..<($0 + said.count)].elementsEqual(said) }
    }

    /// The words of `text` in small letters, each Chinese, Japanese or Korean character one, without spaces and marks.
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = [], word = ""
        for character in text.lowercased() {
            if character.isWide || !(character.isLetter || character.isNumber) {
                if !word.isEmpty { tokens.append(word) }
                word = ""
                if character.isWide, character.isLetter || character.isNumber { tokens.append(String(character)) }
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty { tokens.append(word) }
        return tokens
    }

    /// Whether all of `line` is the end of `before` again, from the start of a word there ("iss" after "iss", "the rep"
    /// after "…send you the rep"; in any case, give or take the spaces and marks around it).
    static func saysTheEndAgain(_ line: String, before: String) -> Bool {
        let said = line.lowercased().drop { !($0.isLetter || $0.isNumber) }
        let core = String(said.reversed().drop { !($0.isLetter || $0.isNumber) }.reversed())
        let text = before.lowercased()
        guard let first = core.first, text.hasSuffix(core) else { return false }
        guard let previous = text.dropLast(core.count).last else { return true }
        return first.isWide || !(previous.isLetter || previous.isNumber)
    }

    /// `line` without what it says again of the unfinished word `before` ends with: all of it, where the model wrote the
    /// word whole ("iss" + "issue" → "ue"), or its last letters, where the rest finishes the word from before them
    /// ("tomo" + "morrow" → "rrow", "comm" + "mand" → "and"). Only an unfinished word ("that" + "that's right" stays).
    static func droppingUnfinishedWord(_ line: String, before: String) -> String {
        let typed = lastWord(before).lowercased(), said = line.lowercased()
        guard !typed.isEmpty, !isWord(typed) else { return line }
        if said.hasPrefix(typed) { return String(line.dropFirst(typed.count)) }
        let next = String(said.prefix { $0.isASCII && $0.isLetter })
        guard !next.isEmpty, !isWord(typed + next) else { return line }
        let overlap = (1..<typed.count).reversed().first { count in
            next.count > count && next.hasPrefix(typed.suffix(count)) && isWord(String(typed.dropLast(count)) + next)
        }
        return overlap.map { String(line.dropFirst($0)) } ?? line
    }

    /// Whether `line` would glue a word of its own onto the unfinished word `before` ends with instead of finishing it:
    /// "tomo" + "later", "iss" + "it means", a capital right after a small letter ("iss" + "Frobnicate"), a word of the
    /// field before or after the caret copied ("iss" + "frobnicate"). Not where the two make one word, nor after a word
    /// on its own (a new word, `needsSpace`); a piece that is no word at all ("Bonjo" + "ur") may finish one the word list
    /// doesn't have.
    static func gluesAWordOn(_ line: String, before: String, after: String = "") -> Bool {
        let typed = lastWord(before), next = String(line.prefix { $0.isASCII && $0.isLetter })
        guard let last = typed.last, let first = next.first else { return false }
        let (end, start) = (typed.lowercased(), next.lowercased())
        if isWord(end + start) || isWord(end) || endsWithContraction(before) { return false }
        if last.isLowercase && first.isUppercase { return true }
        if isWord(start) { return true }
        let field = before.dropLast(typed.count) + " " + after
        return field.split { !($0.isASCII && $0.isLetter) }.contains { $0.lowercased() == start }
    }

    /// The Latin letters `text` ends with: the word being typed ("iss" in "Frobnicate. iss"), none after a space or a mark.
    static func lastWord(_ text: String) -> String {
        String(text.reversed().prefix { $0.isASCII && $0.isLetter }.reversed())
    }

    /// Whether `text` reads as English: half its Latin words at least, but the one being typed, are English words
    /// (`isWord`), or it has none yet ("iss"). What the spaces of an answer are put in by are English words
    /// (`needsSpace`, `gluesAWordOn`): "Wir sehen uns" isn't.
    static func looksEnglish(_ text: String) -> Bool {
        var words = text.split { !($0.isASCII && $0.isLetter) }.map { $0.lowercased() }
        if let last = text.last, last.isASCII, last.isLetter { words.removeLast() }
        return words.isEmpty || words.filter(isWord).count * 2 >= words.count
    }

    /// Whether `word` (in small letters) is a word on its own, by the English word list the core has (`RedactionWords`)
    /// and the short words it leaves out (`shortWords`).
    static func isWord(_ word: String) -> Bool {
        shortWords.contains(word) || RedactionWords.isEnglish(word)
    }

    // MARK: Keys

    /// What Tab does while a suggestion is up.
    public enum TabUse: Equatable, Sendable {
        /// It goes in.
        case accept
        /// The app gets the Tab (⇧Tab, ⌥Tab, a Tab right as the suggestion came up), and the suggestion goes.
        case passOn
    }

    /// What `event` does to a suggestion up `shownFor` seconds; nil: it isn't a Tab.
    public static func tab(_ event: KeyEvent, shownFor: TimeInterval) -> TabUse? {
        guard event.key == .tab else { return nil }
        guard event.modifiers.subtracting(.capsLock).subtracting(.sides).isEmpty else { return .passOn }
        return shownFor < tabGrace ? .passOn : .accept
    }

    // MARK: Text typed into a field

    /// What was put into the field since it took the focus, as far as the input method knows it (the keys it let through
    /// that type, what it put in): what a request continues where the field tells nothing of its text (WeChat). Forgotten
    /// when the caret may have moved (an arrow, ⏎, a click, a shortcut), a character taken back for ⌫.
    public struct Typed: Equatable, Sendable {
        public private(set) var text = ""

        public init() {}

        public mutating func add(_ typed: String) {
            text = String((text + typed).suffix(Autocomplete.beforeLimit))
        }

        public mutating func backspace() {
            if !text.isEmpty { text.removeLast() }
        }

        public mutating func forget() { text = "" }
    }

    // MARK: The user's rhythm

    /// How fast the user types: the time between their last keys, and the pause that tells they stopped (`pause`), half
    /// as long again as the usual time between their keys (the median), never shorter than the model's (`Route.pause`)
    /// nor longer than `longest`. A pause shorter than the time between keys asks between two keys, for nothing.
    public struct Rhythm: Equatable, Sendable {
        /// The last keys' times between them kept, and how many it takes to go by them.
        static let kept = 40
        static let enough = 5
        /// A gap between two keys this long is a stop, not the rhythm.
        static let stop: TimeInterval = 1.5
        public static let longest: TimeInterval = 1.2

        public private(set) var intervals: [TimeInterval] = []
        private var last: TimeInterval?

        public init() {}

        /// A key that typed, at `time` (seconds of uptime).
        public mutating func key(at time: TimeInterval) {
            if let last, time >= last, time - last < Self.stop {
                intervals = Array((intervals + [time - last]).suffix(Self.kept))
            }
            last = time
        }

        /// The usual time between keys; nil before there are `enough`.
        public var median: TimeInterval? {
            guard intervals.count >= Self.enough else { return nil }
            let sorted = intervals.sorted()
            let middle = sorted.count / 2
            return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
        }

        /// The pause before asking, at least `base`.
        public func pause(_ base: TimeInterval) -> TimeInterval {
            guard let median else { return base }
            return max(base, min(median * 1.5, Self.longest))
        }
    }

    // MARK: Suggestions kept

    /// The last suggestions and the text they continue, in the app they were made in: the same text again (before the
    /// caret and after it, in the same app) shows its suggestion at once, and so does text typed since that runs into
    /// one (its rest is shown). No request for either. One waved away with Esc goes, and is remembered as not wanted
    /// (`rejected`): neither it nor an answer that says it again is shown for that text.
    public struct Cache: Equatable, Sendable {
        public struct Entry: Equatable, Sendable {
            /// The text before the caret it was made for, and after it.
            public var before: String
            public var after: String
            /// The app it was made in, its bundle id in small letters (nil: none told).
            public var app: String?
            public var text: String

            public init(_ text: String, for context: Context, in app: String?) {
                (before, after, self.app, self.text) = (context.before, context.after, app?.lowercased(), text)
            }

            /// Whether it was made for the same text after the caret, in the same app, as `context` in `app`.
            func isFor(_ context: Context, in app: String?) -> Bool {
                after == context.after && self.app == app?.lowercased()
            }
        }

        public static let capacity = 20
        /// How much of the text before the caret has to be the same: its last characters (the rest of the field may have
        /// scrolled out of what was read).
        static let matched = 200

        public private(set) var entries: [Entry] = []
        /// The suggestions waved away (Esc), the last `capacity`.
        public private(set) var rejected: [Entry] = []

        public init() {}

        public mutating func add(_ entry: Entry) {
            entries.removeAll { $0.before == entry.before && $0.after == entry.after && $0.app == entry.app }
            entries.append(entry)
            if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        }

        /// `text` for `before` alone: no text after the caret, no app.
        public mutating func add(_ text: String, after before: String) {
            add(Entry(text, for: Context(before: before), in: nil))
        }

        /// What is left of a suggestion for `context` in `app`, and the one it is: one made for it, or for text before
        /// it that `context.before` goes on with as the suggestion did (typed along), with the same text after the
        /// caret, in the same app; never one waved away there (`isRejected`). Nil: none, or one typed to its end.
        public func kept(for context: Context, in app: String?) -> (rest: String, entry: Entry)? {
            for entry in entries.reversed() where entry.isFor(context, in: app) {
                for typed in 0..<entry.text.count where matches(entry, typed: typed, before: context.before) {
                    let rest = String(entry.text.dropFirst(typed))
                    if !isRejected(rest, for: context, in: app) { return (rest, entry) }
                    break
                }
            }
            return nil
        }

        /// What is left of a suggestion for `before` alone (`kept`).
        public func rest(after before: String) -> String? {
            kept(for: Context(before: before), in: nil)?.rest
        }

        /// `entry` waved away (Esc): it goes, and isn't shown again for its text (`isRejected`).
        public mutating func reject(_ entry: Entry) {
            entries.removeAll { $0.before == entry.before && $0.after == entry.after && $0.app == entry.app }
            rejected.removeAll { $0 == entry }
            rejected.append(entry)
            if rejected.count > Self.capacity { rejected.removeFirst(rejected.count - Self.capacity) }
        }

        /// Whether `text`, a suggestion for `context` in `app`, is one waved away there: what was left of it at that
        /// text (typed along or not), in the same words but for spaces at its ends and its closing mark.
        public func isRejected(_ text: String, for context: Context, in app: String?) -> Bool {
            let words = Self.words(text)
            return rejected.contains { entry in
                entry.isFor(context, in: app) && (0..<entry.text.count).contains { typed in
                    matches(entry, typed: typed, before: context.before) && Self.words(entry.text.dropFirst(typed)) == words
                }
            }
        }

        static func words<S: StringProtocol>(_ text: S) -> String {
            var words = text.trimmingCharacters(in: .whitespaces)
            while let last = words.last, ".!?…。！？".contains(last) { words.removeLast() }
            return words
        }

        /// Whether `before` is `entry.before` followed by the suggestion's first `typed` characters.
        private func matches(_ entry: Entry, typed: Int, before: String) -> Bool {
            let along = entry.text.prefix(typed)
            guard before.hasSuffix(along) else { return false }
            let earlier = before.dropLast(along.count)
            let length = min(Self.matched, entry.before.count, earlier.count)
            // The same end, and as long as it is: one read shorter (the field's start) is the same text only if both are.
            return earlier.suffix(length) == entry.before.suffix(length)
                && (length == Self.matched || earlier.count == entry.before.count)
        }
    }

    // MARK: Learning per app

    /// What happened to the suggestions in each app: in one where none of the last `window` was taken, it stops (said
    /// once), until the app is set to autocomplete always or the switch is turned on again; never in an app set to
    /// always or never (it goes by that). Where they are often waved away it waits longer before asking (`pause`). Kept
    /// on this device.
    public struct Learning: Codable, Equatable, Sendable {
        public static let window = 30

        public struct App: Codable, Equatable, Sendable {
            /// The last `window` suggestions, true for one taken (Tab, or typed to its end).
            public var outcomes: [Bool] = []
            public var stopped = false
            /// Waved away in a row (Esc, or typed past).
            public var dismissedInARow = 0

            public init() {}
        }

        public var apps: [String: App] = [:]

        public init() {}

        /// One suggestion's end in `app`: taken or not. True when it stops there now; never where it `mayStop` not (the
        /// app's own choice decides there).
        public mutating func record(_ taken: Bool, in app: String, mayStop: Bool = true) -> Bool {
            let key = app.lowercased()
            var entry = apps[key] ?? App()
            entry.outcomes = Array((entry.outcomes + [taken]).suffix(Self.window))
            entry.dismissedInARow = taken ? 0 : entry.dismissedInARow + 1
            return settle(entry, key, mayStop: mayStop)
        }

        /// The suggestion just taken in `app` taken back at once (⌘Z right after Tab, `undoWindow`): not taken after all.
        /// True when it stops there now; never where it `mayStop` not (`record`).
        public mutating func takenBack(in app: String, mayStop: Bool = true) -> Bool {
            let key = app.lowercased()
            guard var entry = apps[key], entry.outcomes.last == true else { return false }
            entry.outcomes[entry.outcomes.count - 1] = false
            entry.dismissedInARow += 1
            return settle(entry, key, mayStop: mayStop)
        }

        /// `entry` kept for `key`, stopped when none of the last `window` was taken and it `mayStop`: true when it stops
        /// now.
        private mutating func settle(_ entry: App, _ key: String, mayStop: Bool) -> Bool {
            var entry = entry
            let stops = mayStop && !entry.stopped && entry.outcomes.count >= Self.window && !entry.outcomes.contains(true)
            if stops { entry.stopped = true }
            apps[key] = entry
            return stops
        }

        public func stopped(_ app: String?) -> Bool {
            guard let app else { return false }
            return apps[app.lowercased()]?.stopped == true
        }

        /// The switch turned on again: every app starts over.
        public mutating func restart() { apps = [:] }

        /// The pause before asking in `app`: `base`, longer where suggestions are waved away one after the other, up
        /// to twice as long after ten.
        public func pause(_ base: TimeInterval, in app: String?) -> TimeInterval {
            let streak = app.flatMap { apps[$0.lowercased()]?.dismissedInARow } ?? 0
            return base * (1 + Double(min(streak, 10)) / 10)
        }
    }

    // MARK: Metrics

    /// What is counted on this device (never sent anywhere): how many suggestions were asked for, shown and taken, how
    /// much of them went in, how long they took to come up, Tabs taken back at once, the apps where it stopped, the
    /// times it was turned off within a day, the tokens cloud providers read and wrote for it.
    public struct Metrics: Codable, Equatable, Sendable {
        public var asked = 0
        public var shown = 0
        /// Shown from what was kept (`Cache`), with no request.
        public var fromCache = 0
        /// Taken with Tab (and not taken back at once: `undone`).
        public var accepted = 0
        /// Typed to their end.
        public var typedThrough = 0
        public var dismissed = 0
        public var shownCharacters = 0
        /// Of what was shown, what went in: by Tab, and typed along.
        public var acceptedCharacters = 0
        /// Taken with Tab, then back with ⌘Z right after it (`undoWindow`): counted as waved away (`dismissed`), not taken.
        public var undone = 0
        /// Answers that came too late to show (`Route.late`), and requests that failed.
        public var late = 0
        public var failed = 0
        /// Milliseconds from the start of the pause to the suggestion shown, the last 200.
        public var latencies: [Int] = []
        public var stoppedApps = 0
        public var turnedOn = 0
        public var turnedOffWithinADay = 0
        public var lastTurnedOn: Date?
        public var cloudInputTokens = 0
        public var cloudOutputTokens = 0

        public init() {}

        static let latenciesKept = 200

        public mutating func shown(_ text: String, after seconds: TimeInterval, fromCache cached: Bool) {
            shown += 1
            shownCharacters += text.count
            if cached { fromCache += 1 }
            latencies = Array((latencies + [Int((seconds * 1000).rounded())]).suffix(Self.latenciesKept))
        }

        /// The switch turned on or off at `date`.
        public mutating func switched(on: Bool, at date: Date) {
            if on {
                turnedOn += 1
                lastTurnedOn = date
            } else if let since = lastTurnedOn {
                if date.timeIntervalSince(since) < 24 * 3600 { turnedOffWithinADay += 1 }
                lastTurnedOn = nil
            }
        }

        /// Taken (Tab) of those shown.
        public var acceptance: Double? { shown == 0 ? nil : Double(accepted) / Double(shown) }
        /// Of the characters shown, those that went in.
        public var acceptedShare: Double? { shownCharacters == 0 ? nil : Double(acceptedCharacters) / Double(shownCharacters) }
        /// The 90th percentile of `latencies`.
        public var p90: Int? {
            guard !latencies.isEmpty else { return nil }
            let sorted = latencies.sorted()
            return sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.9).rounded(.up)) - 1)]
        }
        /// Tabs taken back at once, of every Tab.
        public var undoneShare: Double? { accepted + undone == 0 ? nil : Double(undone) / Double(accepted + undone) }
        /// Turned off within a day of being turned on, of the times it was turned on.
        public var offWithinADayShare: Double? { turnedOn == 0 ? nil : Double(turnedOffWithinADay) / Double(turnedOn) }

        /// One line for the menus: "Shown 340 · taken 12% · 90% within 210 ms"; nil before anything was shown.
        public func summary(language: String) -> String? {
            guard let acceptance else { return nil }
            let t = InterfaceWords(language: language)
            let percent = Int((acceptance * 100).rounded())
            var line = t.tr("已显示 \(shown) 次 · 接受 \(percent)%", "Shown \(shown) times · \(percent)% taken")
            if let p90 { line += t.tr(" · 九成在 \(p90) ms 内", " · 90% within \(p90) ms") }
            return line
        }
    }
}

extension Character {
    /// A character of Chinese, Japanese or Korean: a word on its own, with no spaces between them.
    var isWide: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xAC00...0xD7AF, 0x20000...0x2FA1F,
             0x3000...0x303F, 0xFF01...0xFF60:
            return true
        default:
            return false
        }
    }
}

// MARK: - What is kept between fields

/// Autocomplete's state across a shell's text fields and launches: the suggestions kept (`Autocomplete.Cache`, in
/// memory), what is learned per app and what is counted (in `defaults`, written a moment after it changes, off the
/// session's thread), what was said once. The shell gives one to every session (`SessionServices.autocomplete`); the
/// default keeps it all in memory. Safe from any thread.
public final class AutocompleteStore: @unchecked Sendable {
    private struct State {
        var cache = Autocomplete.Cache()
        var learning = Autocomplete.Learning()
        var metrics = Autocomplete.Metrics()
        var said: Set<String> = []
        var prewarmed: TimeInterval?
        /// The switch as last seen (`saw`), nil before.
        var switchSeen: Bool?
        /// What was counted and learned waits to be written (`keepSoon`).
        var writeWaiting = false
        var rhythm = Autocomplete.Rhythm()
    }

    static let learningKey = "autocompleteLearning"
    static let metricsKey = "autocompleteMetrics"
    static let switchKey = "autocompleteSwitch"
    /// The on-device model is loaded ahead of the first pause when a field takes the focus, at most once in this long.
    static let prewarmEvery: TimeInterval = 60
    /// How long what was counted and learned waits before it's written (`keepSoon`): what changes meanwhile goes with it.
    public static let writeDelay: TimeInterval = 2
    /// Where it's written: off the session's thread (a key's end of a suggestion never waits for the defaults).
    private static let writes = DispatchQueue(label: "com.aipinyin.autocomplete.store", qos: .utility)

    private let state: Locked<State>
    private let defaults: any KeyValueStore
    /// `writeDelay`, but the tests'.
    private let delay: TimeInterval

    public init(defaults: any KeyValueStore = MemoryKeyValueStore(), writeDelay: TimeInterval = AutocompleteStore.writeDelay) {
        self.defaults = defaults
        delay = writeDelay
        var initial = State()
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: Self.learningKey), let learning = try? decoder.decode(Autocomplete.Learning.self, from: data) {
            initial.learning = learning
        }
        if let data = defaults.data(forKey: Self.metricsKey), let metrics = try? decoder.decode(Autocomplete.Metrics.self, from: data) {
            initial.metrics = metrics
        }
        initial.switchSeen = defaults.string(forKey: Self.switchKey).flatMap { ["on": true, "off": false][$0] }
        state = Locked(initialState: initial)
    }

    public var learning: Autocomplete.Learning { state.withLock { $0.learning } }
    public var metrics: Autocomplete.Metrics { state.withLock { $0.metrics } }

    /// Counts something (`Autocomplete.Metrics`), and keeps it (written a moment later: `keepSoon`).
    public func count(_ change: (inout Autocomplete.Metrics) -> Void) {
        state.withLock { change(&$0.metrics) }
        keepSoon()
    }

    /// Changes what is learned per app, and keeps it (written a moment later: `keepSoon`); what `change` returns.
    @discardableResult
    public func learn<T>(_ change: (inout Autocomplete.Learning) -> T) -> T {
        let result = state.withLock { change(&$0.learning) }
        keepSoon()
        return result
    }

    /// What was counted and learned, written to the defaults `writeDelay` from now, off the caller's thread: one write
    /// for all that changes meanwhile (`flush`).
    private func keepSoon() {
        let first = state.withLock { state -> Bool in
            defer { state.writeWaiting = true }
            return !state.writeWaiting
        }
        guard first else { return }
        Self.writes.asyncAfter(deadline: .now() + delay) { self.flush() }
    }

    /// What was counted and learned, written to the defaults now (what was waiting to be: `keepSoon`).
    public func flush() {
        let (metrics, learning) = state.withLock { state in
            state.writeWaiting = false
            return (state.metrics, state.learning)
        }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(metrics) { defaults.set(data, forKey: Self.metricsKey) }
        if let data = try? encoder.encode(learning) { defaults.set(data, forKey: Self.learningKey) }
    }

    /// The switch turned on or off (counted; on, every app starts over).
    public func switched(on: Bool, at date: Date = Date()) {
        keepSeen(on)
        count { $0.switched(on: on, at: date) }
        if on { learn { $0.restart() } }
    }

    /// The switch as the settings have it, seen by a session as it takes them (a field takes the focus, the settings
    /// change): turned on or off since it was last seen, elsewhere than the input method's own switch (Settings →
    /// Assistant, a hand edit of the config file), it is counted and every app starts over, as with the switch
    /// (`switched`, which counts its own). Seen the first time: only kept.
    public func saw(switch on: Bool, at date: Date = Date()) {
        let before = state.withLock { $0.switchSeen }
        guard before != on else { return }
        if before == nil { keepSeen(on) } else { switched(on: on, at: date) }
    }

    private func keepSeen(_ on: Bool) {
        let changed = state.withLock { state -> Bool in
            defer { state.switchSeen = on }
            return state.switchSeen != on
        }
        if changed { defaults.set(on ? "on" : "off", forKey: Self.switchKey) }
    }

    /// `entry` kept (`Autocomplete.Cache`), unless it is one waved away for its text: false then.
    @discardableResult
    public func keep(_ entry: Autocomplete.Cache.Entry) -> Bool {
        state.withLock { state in
            guard !state.cache.isRejected(entry.text, for: Autocomplete.Context(before: entry.before, after: entry.after),
                                          in: entry.app) else { return false }
            state.cache.add(entry)
            return true
        }
    }

    /// What is left of a suggestion kept for `context` in `app`, and the one it is (`Autocomplete.Cache.kept`).
    public func kept(for context: Autocomplete.Context, in app: String?) -> (rest: String, entry: Autocomplete.Cache.Entry)? {
        state.withLock { $0.cache.kept(for: context, in: app) }
    }

    /// A suggestion waved away with Esc: not this one (`Autocomplete.Cache.reject`).
    public func reject(_ entry: Autocomplete.Cache.Entry) {
        state.withLock { $0.cache.reject(entry) }
    }

    /// Whether it stopped in `app` for want of use (`Autocomplete.Learning`).
    public func stopped(in app: String?) -> Bool {
        state.withLock { $0.learning.stopped(app) }
    }

    /// The pause before asking in `app`: at least `base`, as the user types (`Autocomplete.Rhythm`), longer where
    /// suggestions are waved away (`Autocomplete.Learning.pause`).
    public func pause(_ base: TimeInterval, in app: String?) -> TimeInterval {
        state.withLock { $0.learning.pause($0.rhythm.pause(base), in: app) }
    }

    /// A key that typed at `time` (seconds of uptime), in any field: the user's rhythm (`Autocomplete.Rhythm`).
    public func keyTyped(at time: TimeInterval) {
        state.withLock { $0.rhythm.key(at: time) }
    }

    /// True the first time it's asked with `key` in this process: something said once.
    public func once(_ key: String) -> Bool {
        state.withLock { $0.said.insert(key).inserted }
    }

    /// Whether the on-device model is to be loaded now (`now`: seconds of uptime): not in the last `prewarmEvery`.
    func prewarmDue(at now: TimeInterval) -> Bool {
        state.withLock { state in
            if let last = state.prewarmed, now - last < Self.prewarmEvery { return false }
            state.prewarmed = now
            return true
        }
    }
}

// MARK: - The request

extension Prompt {
    /// Bump when the wording of autocomplete's request changes.
    public static let autocompleteVersion = 2

    /// Autocomplete's instructions, for where it is typed (`AppClass`). Unspaced (`spaced` false), the answer is asked
    /// to start with no space (`autocompleteRequest`).
    static func autocompleteSystem(app: String?, spaced: Bool = true) -> String {
        let place: String
        switch AppClass(app: app) {
        case .chat: place = "a chat message"
        case .mail: place = "an email"
        case .other: place = "a document or a text field"
        }
        let start = spaced
            ? "If the text stops inside a word, first finish that word, with no space before it; otherwise start with a "
                + "space before the next word (none in Chinese or Japanese)."
            : "If the text stops inside a word, first finish that word. Never start with a space: one is put in where a "
                + "new word starts."
        return """
            You are the autocomplete of a text field: you suggest the next words the user is about to type, shown in gray \
            after the caret. The text is \(place). The text before the caret is between <before> and </before>. The text \
            between <after> and </after>, if any, is already in the field after the caret: never write it.

            Rules:
            - Answer with only the words that come right after the caret, as plain text: no tags, no quotes, no \
            explanations.
            - Write as the user, going on with their own text: never reply to it, answer it or greet them.
            - \(start)
            - Never repeat the text before the caret.
            - Use the same language, tone and style as the text.
            - At most one sentence, ending where that sentence ends; at most \(Autocomplete.maxWords) words (\
            \(Autocomplete.maxWideCharacters) characters in Chinese or Japanese).
            - If you can't tell how it goes on, answer with nothing at all.
            """
    }

    typealias AutocompleteExample = (context: Autocomplete.Context, answer: String)

    /// Autocomplete's few-shot examples, for Apple's on-device model (a small one, which without them answers in the
    /// request's tags, replies to the text, says it again and glues words on): a new word, the text after the caret not
    /// written, the writer's own text going on (not a reply), a word finished.
    static let autocompleteEnglishExamples: [AutocompleteExample] = [
        (.init(before: "Can we push the deadline to"), " next Wednesday?"),
        (.init(before: "Hi Mark,\nJust a quick reminder about", after: "\nCheers,"), " the budget review on Friday."),
        (.init(before: "Thank you for the invitation."), " I would be happy to join."),
        (.init(before: "Please review the attached docu"), "ment before our call."),
    ]
    static let autocompleteChineseExamples: [AutocompleteExample] = [
        (.init(before: "这周五晚上我们"), "一起去吃火锅吧？"),
        (.init(before: "下班后我打算", after: "\n别忘了带钥匙"), "去超市买点水果。"),
        (.init(before: "感谢大家的支持，"), "我们下周会公布最终结果。"),
    ]

    /// The examples for text that ends with `before`, in its script (the model answers in the examples' language): the
    /// English ones after Latin letters (without the space at the start, `spaced` false), the Chinese ones after
    /// Chinese, none after Japanese, Korean or another script.
    static func autocompleteExamples(for before: String, spaced: Bool = true) -> [AutocompleteExample] {
        let end = String(before.suffix(200))
        if end.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }) {
            return []
        }
        if end.contains(where: \.isWide) { return autocompleteChineseExamples }
        guard AppleModel.mostlyLatin(end) else { return [] }
        return spaced ? autocompleteEnglishExamples : autocompleteEnglishExamples.map { ($0.context, String($0.answer.drop { $0 == " " })) }
    }

    /// Autocomplete's request: the instructions, then the text before the caret (and after it) as the message; for the
    /// on-device model (`onDevice`), few-shot examples before it (`autocompleteExamples`). On English (`Autocomplete
    /// .looksEnglish`) the on-device model is asked for no space at the start: it can't tell a word being finished from
    /// a new one ("rep" + " report", "comm" + " mand"), and a space is put in by the English words where a new one starts
    /// (`Autocomplete.needsSpace`). Other languages keep the model's own spaces.
    public static func autocompleteRequest(_ context: Autocomplete.Context, app: String?, onDevice: Bool = false) -> ConverseRequest {
        let end = String(context.before.suffix(200))
        let spaced = !onDevice || !(AppleModel.mostlyLatin(end) && Autocomplete.looksEnglish(end))
        let examples = onDevice ? autocompleteExamples(for: context.before, spaced: spaced).flatMap { example in
            [ConverseRequest.Message(role: "user", text: autocompleteMessage(example.context)),
             ConverseRequest.Message(role: "assistant", text: example.answer)]
        } : []
        return ConverseRequest(system: [.init(autocompleteSystem(app: app, spaced: spaced))],
                               messages: examples + [.init(role: "user", text: autocompleteMessage(context))],
                               inferenceConfig: .init(maxTokens: Autocomplete.maxTokens, temperature: 0.2))
    }

    static func autocompleteMessage(_ context: Autocomplete.Context) -> String {
        "<before>\(context.before)</before>" + (context.after.isEmpty ? "" : "\n<after>\(context.after)</after>")
    }
}

extension Autocomplete {
    /// What a request answered: the suggestion (nil: none worth showing), the text it continues, where it went, and the
    /// tokens a cloud provider said it read and wrote.
    public struct Answer: Equatable, Sendable {
        public var text: String?
        public var before: String
        public var route: Route
        public var inputTokens: Int?
        public var outputTokens: Int?

        public init(text: String?, before: String, route: Route, inputTokens: Int? = nil, outputTokens: Int? = nil) {
            self.text = text
            self.before = before
            self.route = route
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
        }
    }
}

extension Converter {
    /// Autocomplete's suggestion for `context` in `app` (`Prompt.autocompleteRequest`), from the model the settings
    /// give it (`Autocomplete.route`): the on-device one unless the user agreed to a cloud provider. Throws
    /// `AppleModelError.unavailable` where the on-device model can't run (never another model in its place), and
    /// `AppProfile.Refusal.noAI` in an app with no AI. Hidden values as for any request (`Redaction`); the answer is read
    /// only as far as a suggestion goes (`Autocomplete.isEnough`).
    public func autocomplete(_ context: Autocomplete.Context, app: String?) async throws -> Autocomplete.Answer {
        var config = try Self.settings(try loadConfig(), app: app)
        let route = Autocomplete.route(config)
        if route == .onDevice {
            let availability = client.apple.availability
            guard availability == .available else { throw AppleModelError.unavailable(availability) }
            config.provider = .apple
        }
        config.timeoutSeconds = Autocomplete.timeout
        var redaction = Redaction(config.redaction)
        let hidden = redaction?.hide([context.before, context.after]) ?? [context.before, context.after]
        let sent = Autocomplete.Context(before: hidden[0], after: hidden[1])
        let request = Prompt.autocompleteRequest(sent, app: app, onDevice: route == .onDevice)
        let body = redaction?.protect(request, sent: Prompt.autocompleteMessage(sent)) ?? request
        var text = ""
        var inputTokens: Int?, outputTokens: Int?
        for try await event in client.stream(body, config: config, loadCredentials: loadCredentials, loadKey: loadKey) {
            switch event {
            case let .textDelta(delta): text += delta
            case let .textReplaced(whole): text = whole
            case let .metadata(_, input, output): (inputTokens, outputTokens) = (input ?? inputTokens, output ?? outputTokens)
            case .messageStop: break
            }
            if Autocomplete.isEnough(text) { break }
        }
        try Task.checkCancellation()
        let restored = Autocomplete.trimmed(text, before: sent.before, after: sent.after).map { redaction?.restore($0) ?? $0 }
        // A placeholder the model made up, or one that didn't come back whole: nothing rather than a placeholder.
        let shown = restored.flatMap { AppleModel.placeholder.firstMatch(in: $0, range: NSRange(location: 0, length: ($0 as NSString).length)) == nil ? $0 : nil }
        return Autocomplete.Answer(text: shown, before: context.before, route: route,
                                   inputTokens: route == .onDevice ? nil : inputTokens, outputTokens: route == .onDevice ? nil : outputTokens)
    }

    /// Whether the on-device model can run now (what a pause asks before it reads the field).
    public var onDeviceAvailability: AppleModelAvailability { client.apple.availability }

    /// Loads the on-device model ahead of a request (nothing is sent), where it can run.
    public func prewarmOnDevice() {
        guard client.apple.availability == .available, let backend = client.apple as? any AppleGuidedBackend else { return }
        Task.detached(priority: .utility) { backend.prewarm() }
    }
}

// MARK: - Settings → Assistant

extension AIConfig {
    /// Autocomplete turned on or off in a sentence (`Key.autocomplete`). On with a cloud provider picked, the row says
    /// that it uses the model on this Mac until the user allows the provider, in the input menu; with AllInOneIME Cloud
    /// picked, that it only ever uses that model, and why (`Autocomplete.offersCloud`).
    static func checkAutocomplete(_ value: JSONValue, in config: Config, text: Text) -> Row? {
        let (label, path) = (text.autocompleteLabel, Key.autocomplete.path)
        guard case let .bool(on) = value else { return Row(key: path, label: label, status: .refused(text.notValid)) }
        guard on != config.autocomplete else { return nil }
        let onDevice = !on ? "" : Autocomplete.asksForCloud(config) ? text.autocompleteOnDevice(config.provider)
            : config.provider == .hosted ? text.autocompleteHostedOnDevice : ""
        return Row(key: path, label: label, old: text.onOff(config.autocomplete), new: text.onOff(on) + onDevice, status: .change,
                   edit: .autocomplete(on))
    }

    /// Autocomplete's names, lowercased, as `AIConfigFit.relevance` reads words: the interface's own in its languages (续写,
    /// 續寫, Autovervollständigen, Complétion automatique, オートコンプリート, 자동 완성, Autocompletar) and the usual others
    /// ("auto complete", "autocompletion", 自动补全, 自动完成, 自动联想, 補完, Vervollständigung, autocompletado).
    static let autocompleteNames = [
        "autocompl", "auto compl", "续写", "續寫", "补全", "補全", "自动完成", "自動完成", "自动联想", "自動聯想", "オートコンプリート", "補完",
        "자동 완성", "자동완성", "이어 쓰기", "autovervollständig", "vervollständig", "complétion", "saisie semi",
    ]

    /// Words that may mean Autocomplete ("suggestions", 灰字), lowercased: its setting goes into the on-device model's
    /// context with them, but a sentence with them is never read as turning it.
    static let autocompleteHints = ["suggestion", "灰字", "sugerencia", "sugestão"]

    /// Whether `text` (what the user typed) turns Autocomplete on (true) or off (false): it names it and says which
    /// (`switchAsked`: neither, both or a negation say nothing). Nil too when it names an app, or apps: Autocomplete for
    /// one app is set in Settings → Apps, not here.
    static func autocompleteAsked(_ text: String, context: AIConfigPrompt.Context) -> Bool? {
        guard autocompleteNames.contains(where: AIConfigFit.Words(text).contains), let on = switchAsked(text) else { return nil }
        let relevant = AIConfigFit.relevance([text], context: context)
        return relevant.parts.contains(.apps) || !relevant.apps.isEmpty ? nil : on
    }

    /// `autocompleteAsked`, when that is all `sentence` asks: it names no other setting, language or style
    /// (`AIConfigFit.relevance` without Autocomplete's names). Such a sentence is answered from that alone, without a
    /// request (`AIConfigService.ask`): the on-device model has answered "我要把 auto complete 打开" with it off as it was,
    /// with nothing, and with another app's settings.
    static func onlyAutocomplete(_ sentence: String, context: AIConfigPrompt.Context) -> Bool? {
        guard let on = autocompleteAsked(sentence, context: context) else { return nil }
        return AIConfigFit.relevance([sentence], context: context, ignoring: Set(autocompleteNames)).parts.isEmpty ? on : nil
    }

    /// The answer to a sentence `onlyAutocomplete` reads, as a model writes it.
    static func autocompleteAnswer(_ on: Bool) -> String { #"{"changes": [{"key": "autocomplete", "value": \#(on)}]}"# }

    /// `proposal` with Autocomplete as what the user typed turns it (`autocompleteAsked`), whatever the model answered: its
    /// value the other way is the sentence's, and an answer without it gets it; the model's note, about what it answered,
    /// goes then. As it is when the sentence doesn't turn Autocomplete, or the answer already has it so.
    static func followingSentence(_ proposal: Proposal, config: Config, env: Environment) -> Proposal {
        guard let on = autocompleteAsked(env.typedText, context: AIConfigPrompt.Context(config: config, apps: env.apps)) else {
            return proposal
        }
        let asked = Change(key: .autocomplete, value: .bool(on))
        guard !proposal.changes.contains(asked) else { return proposal }
        return Proposal(changes: proposal.changes.filter { $0.key != .autocomplete } + [asked])
    }
}

extension AIConfig.Text {
    public var autocompleteLabel: String { tr("续写", "Autocomplete") }
    /// After "Autocomplete: off → on" with a cloud provider picked (`provider`): where to allow it, the input menu's
    /// item for it (`AutocompleteSwitch`, the Mac's).
    func autocompleteOnDevice(_ provider: Provider) -> String {
        let name = provider.displayName
        return tr("（先用本机模型；要用 \(name)，在输入法菜单里选「续写用 \(name)」）",
                  " (it uses the model on this Mac; to use \(name), choose “Autocomplete with \(name)” in the input menu)")
    }
    /// After "Autocomplete: off → on" with AllInOneIME Cloud picked (`Autocomplete.offersCloud`).
    var autocompleteHostedOnDevice: String {
        UIText.triggered(tr("（只用本机模型：AllInOneIME 云每天的免费次数留给 @ 命令）",
                            " (it uses only the model on this Mac: AllInOneIME Cloud's free requests a day are kept for @ commands)"))
    }
}

// MARK: - The candidate panel's line

extension PanelModel {
    /// Autocomplete's suggestion as a line of the candidate panel, where a shell can't draw it after the caret (it can't
    /// tell where the caret is): the suggestion dimmed, after "Tab", and what the keys do, in the interface language
    /// `language`.
    public static func autocomplete(_ text: String, language: String) -> PanelModel {
        let t = InterfaceWords(language: language)
        return PanelModel(rows: [Row(label: "Tab", text: text, kind: .original, pickable: false)],
                          footer: t.tr("Tab 接受 · Esc 不要", "Tab accept · Esc dismiss"))
    }
}

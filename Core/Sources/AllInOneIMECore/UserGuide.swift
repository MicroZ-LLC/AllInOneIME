import Foundation

/// AllInOneIME's own user guide (Resources/user-guide.md, shipped in the app; the shell hands its text to the
/// `Converter`): short sections under "## " headings, one topic each, in English and Chinese. `@question` reads it only
/// when the question is about AllInOneIME (`isAbout`, a small local check): the few sections that match it best
/// (`excerpts`, by their headings and words, no AI involved) go with the request as reference. Nothing of the user's is in
/// it: it is the app's own documentation. A coding agent the conversation goes on in reads the file itself (`path`).
public struct UserGuide: Sendable {
    /// One topic: its heading (without "## ") and what follows it, up to the next heading.
    public struct Section: Equatable, Sendable {
        public var heading: String
        public var body: String

        /// The section as it is in the guide, and as it goes with a request.
        public var text: String { "## \(heading)\n\(body)" }
    }

    public let sections: [Section]
    /// Each section's words (`terms`): its heading's and its body's.
    private let indexed: [(heading: Set<String>, body: Set<String>)]

    /// Sections sent with a question, at most; at least this many when the guide has them.
    static let maxSections = 3
    static let minSections = 2
    /// The longest excerpt sent, in Characters.
    static let budget = 3_000
    /// What a heading's word counts for against a body's.
    static let headingWeight = 3.0

    /// The guide in `text`: what is before the first "## " heading (a title) is no section.
    public init(text: String) {
        var sections: [Section] = []
        var heading: String?
        var lines: [Substring] = []
        func close() {
            if let heading {
                sections.append(Section(heading: heading, body: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                close()
                heading = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                lines = []
            } else {
                lines.append(line)
            }
        }
        close()
        self.sections = sections
        indexed = sections.map { (Self.terms($0.heading), Self.terms($0.body)) }
    }

    // MARK: - Choosing what goes with a question

    /// The sections that answer `question` best, as they are in the guide ("## " headings and all, best first), at most
    /// `maxSections` and `budget` Characters; nil when the question isn't about AllInOneIME (`isAbout`), and @question's
    /// request is then as it always was.
    public func excerpts(for question: String) -> String? {
        let asked = Self.question(in: question)
        guard Self.isAbout(asked), !sections.isEmpty else { return nil }
        let words = Self.terms(asked)
        let scores = indexed.map { score(words, $0) }
        let ranked = sections.indices.sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
        // Those it matches; when fewer than two do, the next ones in the guide's order (its first sections are the
        // general ones).
        let matched = ranked.filter { scores[$0] > 0 }
        let candidates = matched.count >= Self.minSections ? matched : matched + ranked.filter { scores[$0] <= 0 }
        let count = matched.count >= Self.minSections ? Self.maxSections : Self.minSections
        var chosen: [String] = []
        var used = 0
        for index in candidates where chosen.count < count {
            let text = sections[index].text
            let separator = chosen.isEmpty ? 0 : 2
            if used + separator + text.count <= Self.budget {
                chosen.append(text)
                used += separator + text.count
            } else if chosen.isEmpty {
                // The best one alone is too long: its start, cut at a line.
                let cut = Self.cut(text, to: Self.budget)
                chosen.append(cut)
                used = cut.count
            }
        }
        return chosen.isEmpty ? nil : chosen.joined(separator: "\n\n")
    }

    /// How well a section's words match the question's: each word of the question in the heading or the body, the fewer
    /// sections have it the more it counts.
    private func score(_ words: Set<String>, _ section: (heading: Set<String>, body: Set<String>)) -> Double {
        words.reduce(0) { total, word in
            let inHeading = section.heading.contains(word), inBody = section.body.contains(word)
            guard inHeading || inBody else { return total }
            let sections = indexed.filter { $0.heading.contains(word) || $0.body.contains(word) }.count
            let weight = log(1 + Double(indexed.count) / Double(sections))
            return total + weight * ((inHeading ? Self.headingWeight : 0) + (inBody ? 1 : 0))
        }
    }

    /// `text` up to `limit` Characters, ended at the last line break before it (or the limit) with "…".
    static func cut(_ text: String, to limit: Int) -> String {
        let room = String(text.prefix(limit - 1))
        let end = room.lastIndex(of: "\n").map { String(room[..<$0]) } ?? room
        return end + "…"
    }

    // MARK: - Whether a question is about AllInOneIME

    /// Whether `question` is about AllInOneIME: it names the app, an input method with a setting or a "how", one of its
    /// settings or features by a name nothing else uses, one of its @ commands, or a key by its symbol. Local and small:
    /// anything else is an ordinary question.
    public static func isAbout(_ question: String) -> Bool {
        let text = normalized(Self.question(in: question))
        // English by whole words ("how", not "show"); Chinese, which has no spaces, anywhere.
        let spaced = " " + words(text).joined(separator: " ") + " "
        func says(_ phrase: String) -> Bool { phrase.first?.isASCII == true ? spaced.contains(" \(phrase) ") : text.contains(phrase) }
        if names.contains(where: says) { return true }
        if inputMethod.contains(where: says), asking.contains(where: says) { return true }
        if features.contains(where: says) { return true }
        if text.unicodeScalars.contains(where: keySymbols.contains) { return true }
        return mentionsCommand(text)
    }

    /// The question typed, without what @question adds to it: the selected text it's about (`Prompt.question`), a
    /// screenshot's text (`Prompt.withScreenshot`).
    static func question(in input: String) -> String {
        let markers = ["\n\n<selected_text>\n", Prompt.screenshotRule]
        let end = markers.compactMap { input.range(of: $0)?.lowerBound }.min() ?? input.endIndex
        return String(input[..<end])
    }

    /// The app's names (as `words` splits them: "all-in-one" is three words).
    static let names = ["allinoneime", "all in one ime", "allinone ime"]
    /// An input method, said generally …
    static let inputMethod = ["输入法", "input method", "input methods", "ime", "input source", "input sources", "输入源"]
    /// … and asked about.
    static let asking = ["设置", "设定", "怎么", "如何", "怎样", "how", "setting", "settings", "configure", "set up", "turn on",
                         "turn off"]
    /// Its settings and features by the names only it gives them (as the Settings window and the guide say them).
    static let features = [
        "shuangpin", "双拼", "magic key", "魔法键", "action key", "执行键", "fuzzy pinyin", "模糊音",
        "translate as you type", "边打边译", "clipboard history", "剪贴板历史", "autocomplete",
        "english words", "你的英文词", "rewrite styles", "rewrite style", "改写风格", "jargon list", "黑话库",
        "personal dictionaries", "personal dictionary", "个人词库", "removed candidates", "删掉的候选词",
        "type results out", "逐字上屏", "candidate panel", "候选面板",
    ]
    /// Modifier and key symbols: ⌃ ⌥ ⇧ ⌘ ⏎ ⇥ ⎋.
    static let keySymbols = Set("⌃⌥⇧⌘⏎⇥⎋".unicodeScalars)

    /// Whether `text` (normalized) names a built-in command: "@" and its name, not inside a word or an address.
    static func mentionsCommand(_ text: String) -> Bool {
        let names = Set(Command.builtins.map(\.name))
        var rest = text[...]
        while let at = rest.firstIndex(of: "@") {
            let before = at == text.startIndex ? nil : text[text.index(before: at)]
            let name = text[text.index(after: at)...].prefix { $0.isASCII && $0.isLetter }
            if before.map({ !($0.isLetter || $0.isNumber) }) ?? true, names.contains(String(name)) { return true }
            rest = text[text.index(after: at)...]
        }
        return false
    }

    // MARK: - Words

    /// `text` lowercased, full-width letters and "＠" as ASCII, accents dropped.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The words matched (`terms`): runs of letters and digits, an "@" or key symbols before them kept (`@translate`,
    /// `⌃v`). Chinese, Japanese and Korean have no spaces: each run of them as its pairs of characters (one alone as
    /// it is).
    static func words(_ text: String) -> [String] {
        var out: [String] = []
        var latin = "", cjk: [Character] = []
        func flush() {
            if latin.contains(where: { $0.isLetter || $0.isNumber || keySymbols.contains($0.unicodeScalars.first!) }) { out.append(latin) }
            latin = ""
            if cjk.count == 1 { out.append(String(cjk)) }
            if cjk.count > 1 { out += zip(cjk, cjk.dropFirst()).map { String([$0, $1]) } }
            cjk = []
        }
        for character in text {
            if isCJK(character) {
                if !latin.isEmpty { flush() }
                cjk.append(character)
            } else if character.isLetter || character.isNumber || character == "@" || keySymbols.contains(character.unicodeScalars.first!) {
                if !cjk.isEmpty { flush() }
                // A symbol after letters starts a word of its own ("⌘c⌘v"); letters after a symbol go on with it.
                if !latin.isEmpty, !(character.isLetter || character.isNumber), latin.last?.isLetter == true || latin.last?.isNumber == true {
                    flush()
                }
                latin.append(character)
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    /// The words a text is matched by: `words` of it normalized, without the common ones, plurals as their singular;
    /// and each two English words in a row ("magic key", "api key"), which say more than either alone.
    static func terms(_ text: String) -> Set<String> {
        let all = words(normalized(text)).map { stopWords.contains($0) ? nil : singular($0) }
        let pairs = zip(all, all.dropFirst()).compactMap { pair -> String? in
            guard let a = pair.0, let b = pair.1, a.first?.isASCII == true, b.first?.isASCII == true else { return nil }
            return a + " " + b
        }
        return Set(all.compactMap { $0 } + pairs)
    }

    /// "keys" as "key", "settings" as "setting" (not "process", "this").
    static func singular(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss"), word.first?.isASCII == true else { return word }
        return String(word.dropLast())
    }

    static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return true
        default: return false
        }
    }

    /// Words that say nothing about which section: question words, articles, pronouns; in Chinese, the pairs that only
    /// ask ("怎么", "如何").
    static let stopWords: Set<String> = [
        "a", "an", "the", "how", "do", "does", "did", "i", "me", "my", "you", "your", "it", "its", "is", "are", "was", "be",
        "to", "in", "on", "of", "for", "with", "and", "or", "what", "where", "why", "when", "which", "who", "can", "could",
        "should", "would", "will", "this", "that", "these", "those", "there", "here", "use", "using", "want", "need", "get",
        "please", "about", "from", "by", "at", "as", "if", "not", "no", "so", "up", "any", "some", "one", "into", "make",
        "怎么", "如何", "怎样", "什么", "为什", "么样", "可以", "一下", "这个", "那个", "我的", "我想", "是否", "请问", "么用",
    ]
}

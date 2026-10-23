import Foundation

/// A row of suggestions as a session shows it and puts it in (spec 1.4, 2).
struct SuggestionRow: Equatable {
    var text: String
    var comment: String
    /// What it puts in, whole: what was typed (`typed`) is its start, in any case; only the rest goes in.
    var insertion: String
    /// The caret this many UTF-16 units back from the end of what went in (a snippet's `$0`).
    var caretBack = 0
    /// What the terminal and code editor class completes: the item's `match`, a keyword, a snippet's trigger, a word.
    var completion: String
    /// The part of the token it answers: the whole token for a plugin's row, the identifier for coding's.
    var typed: String
    /// Kept as picked (rows picked before come first); nil: not kept (the field's own words).
    var pick: SuggestionPick?
    /// The source's title, for the footer, and when its list was made.
    var source: String
    var madeAt: Date?

    /// What goes in for it: what wasn't typed yet (the typed part, its case, stays).
    var rest: String { String(insertion.dropFirst(typed.count)) }
}

/// The rows a plugin's completion source has for a token (spec 1.3, 1.4, 6.7, 6.8, 6.13).
enum PluginRows {
    /// The part of `token` after `source`'s prefix, when the source applies to it: it starts with the prefix (in any
    /// case, full-width forms as ASCII) and has `minChars` characters after it; without a prefix, it is all digits and
    /// that long. Nil: it doesn't apply.
    static func afterPrefix(_ token: String, _ source: CompletionSource) -> String? {
        let normalized = SuggestionsToken.normalized(token)
        guard let prefix = source.prefix else {
            guard normalized.allSatisfy({ $0.isASCII && $0.isNumber }), normalized.count >= max(source.minChars, 1) else { return nil }
            return normalized
        }
        guard normalized.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        let after = String(normalized.dropFirst(prefix.count))
        return after.count >= source.minChars ? after : nil
    }

    /// Whether `item` answers `token` (normalized, in small letters) as `source` compares.
    static func matches(_ item: CompletionItem, _ lowered: String, _ source: CompletionSource) -> Bool {
        let match = item.match.lowercased()
        return source.compare == .exact ? match == lowered : match.hasPrefix(lowered)
    }

    /// The templates of `source` for an app of `appClass`: nil, none there (`null`); the terminal and code editor
    /// class's are `{match}` (spec 6.10).
    static func templates(_ source: CompletionSource, _ appClass: SuggestionsAppClass) -> [String]? {
        let chosen: CompletionInsert.Templates
        switch appClass {
        case .ordinary, .none: chosen = source.insert.default
        case .chat: chosen = source.insert.chat ?? source.insert.default
        case .codeEditor:
            if (source.insert.terminal ?? source.insert.default) == .off { return nil }
            return ["{match}"]
        }
        if case let .templates(list) = chosen { return list }
        return nil
    }

    /// The rows of `items` (the list's, then the queries' answers, each match once) for `token` in an app of
    /// `appClass`: those whose insertion starts with what was typed.
    static func rows(_ token: String, plugin: InstalledPlugin, source: CompletionSource, lists: [[CompletionItem]],
                     madeAt: Date?, appClass: SuggestionsAppClass, in t: InterfaceWords) -> [SuggestionRow] {
        guard let templates = templates(source, appClass) else { return [] }
        let typed = SuggestionsToken.normalized(token)
        let lowered = typed.lowercased()
        let title = source.title.text(chinese: t.chinese)
        var seen = Set<String>()
        var rows: [SuggestionRow] = []
        for list in lists {
            for item in list where matches(item, lowered, source) {
                guard seen.insert(item.match.lowercased()).inserted,
                      let insertion = CompletionTemplate.fill(templates, with: item),
                      SuggestionsToken.normalized(insertion).lowercased().hasPrefix(lowered) else { continue }
                let (text, comment) = shown(item)
                rows.append(SuggestionRow(text: text, comment: comment, insertion: insertion, completion: item.match, typed: token,
                                          pick: SuggestionPick(plugin: plugin.name, source: source.name, match: item.match),
                                          source: title, madeAt: madeAt))
            }
        }
        return rows
    }

    /// An item's row: its match, then its title and subtitle; its title alone when it starts with its match ("#12 Fix
    /// login").
    static func shown(_ item: CompletionItem) -> (text: String, comment: String) {
        let title = item.title ?? ""
        if !title.isEmpty, title.lowercased().hasPrefix(item.match.lowercased()) {
            return (title, item.subtitle ?? "")
        }
        let comment = [title, item.subtitle ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        return (item.match, comment)
    }
}

/// Rows picked before first (spec 6.18): by frecency, how often and how recently each was picked (each pick counts
/// less the more picks came after it), then in the order they came.
enum Frecency {
    /// How much a pick counts for each pick after it.
    static let decay = 0.9
    /// The picks looked at: the latest.
    static let window = 500

    static func scores(_ picks: [SuggestionPick]) -> [SuggestionPick: Double] {
        var scores: [SuggestionPick: Double] = [:]
        var weight = 1.0
        for pick in picks.suffix(window).reversed() {
            scores[pick, default: 0] += weight
            weight *= decay
        }
        return scores
    }

    static func ordered(_ rows: [SuggestionRow], picks: [SuggestionPick]) -> [SuggestionRow] {
        guard !picks.isEmpty else { return rows }
        let scores = scores(picks)
        let picked = rows.enumerated().compactMap { index, row -> (Int, Double)? in
            row.pick.flatMap { scores[$0] }.map { (index, $0) }
        }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.map(\.0)
        let first = Set(picked)
        return picked.map { rows[$0] } + rows.indices.filter { !first.contains($0) }.map { rows[$0] }
    }
}

/// Coding mode's rows (spec 2): the installed packs' snippets and keywords, and the field's own words.
enum CodingRows {
    /// Rows from this many characters of an identifier on.
    static let minChars = 2
    /// The field's words: identifiers this long at least.
    static let minWordLength = 4
    /// How much of the field's text is looked through, each side of the caret.
    static let scanned = 20_000

    /// A snippet's body as it goes in: `${n:text}` as its text, `${n}` and `$n` as nothing, the caret at `$0` (its
    /// UTF-16 units from the end; at the end without one).
    static func expand(_ body: String) -> (text: String, caretBack: Int) {
        var out = ""
        var caret: Int?
        let characters = Array(body)
        var index = 0
        func digits(from start: Int) -> (String, Int) {
            var end = start
            while end < characters.count, characters[end].isASCII, characters[end].isNumber { end += 1 }
            return (String(characters[start..<end]), end)
        }
        while index < characters.count {
            let character = characters[index]
            guard character == "$", index + 1 < characters.count else {
                out.append(character)
                index += 1
                continue
            }
            let next = characters[index + 1]
            if next.isASCII, next.isNumber {
                let (number, end) = digits(from: index + 1)
                if number == "0" { caret = out.utf16.count }
                index = end
            } else if next == "{" {
                let (number, end) = digits(from: index + 2)
                guard !number.isEmpty, end < characters.count, characters[end] == "}" || characters[end] == ":" else {
                    out.append(character)
                    index += 1
                    continue
                }
                var close = end
                if characters[end] == ":" {
                    close = characters[end...].firstIndex(of: "}") ?? characters.count
                }
                if number == "0" { caret = out.utf16.count }
                if characters[end] == ":" { out += String(characters[(end + 1)..<min(close, characters.count)]) }
                index = min(close + 1, characters.count)
            } else {
                out.append(character)
                index += 1
            }
        }
        return (out, caret.map { out.utf16.count - $0 } ?? 0)
    }

    /// The identifiers of `text` (`minWordLength` characters or more, not starting with a digit), the one the caret is
    /// in left out, most frequent first, then the nearest to the caret.
    static func words(_ text: FieldText) -> [String] {
        let before = Array(text.before.suffix(scanned)), after = Array(text.after.prefix(scanned))
        var counts: [String: (count: Int, distance: Int)] = [:]
        func note(_ word: [Character], distance: Int) {
            guard word.count >= minWordLength, let first = word.first, !first.isNumber else { return }
            let key = String(word)
            let old = counts[key] ?? (0, Int.max)
            counts[key] = (old.count + 1, min(old.distance, distance))
        }
        // Before the caret, from the caret back; the word the caret is at the end of is the one being typed.
        var word: [Character] = []
        var index = before.count - 1
        while index >= 0, SuggestionsToken.isIdentifierCharacter(before[index]) { index -= 1 }
        let typedStart = index + 1
        let typedEnd = after.firstIndex { !SuggestionsToken.isIdentifierCharacter($0) } ?? after.count
        for position in stride(from: typedStart - 1, through: 0, by: -1) {
            if SuggestionsToken.isIdentifierCharacter(before[position]) {
                word.insert(before[position], at: 0)
            } else {
                note(word, distance: before.count - position - 1)
                word = []
            }
        }
        note(word, distance: before.count)
        word = []
        for position in typedEnd..<after.count {
            if SuggestionsToken.isIdentifierCharacter(after[position]) {
                word.append(after[position])
            } else {
                note(word, distance: position - word.count)
                word = []
            }
        }
        note(word, distance: after.count - word.count)
        return counts.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.value.distance < $1.value.distance }
            .map(\.key)
    }

    /// The leading whitespace (spaces and tabs) of the line `before` ends in: the caret's line's, which a snippet's second
    /// and later lines get (spec 6.19).
    static func indent(_ before: String) -> String {
        let line = before.lastIndex(where: \.isNewline).map { before[before.index(after: $0)...] } ?? before[...]
        return String(line.prefix { $0 == " " || $0 == "\t" })
    }

    /// `body` with `indent` after each of its line breaks.
    static func indented(_ body: String, by indent: String) -> String {
        guard !indent.isEmpty else { return body }
        var out = ""
        for character in body {
            out.append(character)
            if character.isNewline { out += indent }
        }
        return out
    }

    /// The rows for `identifier` (what is typed of it): the packs' snippets whose trigger it starts (the whole trigger
    /// too) and whose body starts with it, their keywords it starts (not one typed in full), and `words`; in an app of
    /// `appClass` (terminals and code editors: a snippet completes as its trigger). A snippet's later lines get `indent`
    /// (the caret's line's); one that puts in what another pack's does is one row, naming both languages (spec 6.19).
    static func rows(_ identifier: String, packs: [CodingLanguagePack], words: [String], indent: String = "",
                     appClass: SuggestionsAppClass, in t: InterfaceWords) -> [SuggestionRow] {
        guard identifier.count >= minChars else { return [] }
        let code = appClass == .codeEditor
        var snippets: [(row: SuggestionRow, languages: [String], title: String?)] = []
        var byInsertion: [String: Int] = [:]
        for pack in packs {
            for snippet in pack.snippets where snippet.trigger.hasPrefix(identifier) {
                let (text, caretBack) = expand(indented(snippet.body, by: indent))
                guard text.hasPrefix(identifier) else { continue }
                let (insertion, back) = code ? (snippet.trigger, 0) : (text, caretBack)
                let key = insertion + "\u{0}\(back)"
                if let index = byInsertion[key] {
                    if !snippets[index].languages.contains(pack.title) { snippets[index].languages.append(pack.title) }
                    continue
                }
                byInsertion[key] = snippets.count
                // Its title where it says more than its trigger.
                let title = snippet.title.flatMap { $0 == snippet.trigger ? nil : $0 }
                // Picked as itself, not as every snippet of its trigger ("if", "if/else", "main guard").
                let pick = SuggestionPick(plugin: "", source: pack.language, match: "snippet:\(snippet.trigger):\(snippet.title ?? snippet.body)")
                snippets.append((SuggestionRow(text: snippet.trigger, comment: "", insertion: insertion, caretBack: back,
                                               completion: snippet.trigger, typed: identifier, pick: pick, source: pack.title),
                                 [pack.title], title))
            }
        }
        // Its languages, then its title, or that it's a snippet ("Python · function", "C/C++ · snippet").
        let snippetWord = t.tr("代码片段", "snippet")
        var rows = snippets.map { snippet in
            var row = snippet.row
            row.comment = snippet.languages.joined(separator: "/") + " · " + (snippet.title ?? snippetWord)
            return row
        }
        var keywords = Set<String>()
        for pack in packs {
            for keyword in pack.keywords where keyword.hasPrefix(identifier) && keyword != identifier {
                guard keywords.insert(keyword).inserted else { continue }
                rows.append(SuggestionRow(text: keyword, comment: pack.title, insertion: keyword, completion: keyword, typed: identifier,
                                          pick: SuggestionPick(plugin: "", source: pack.language, match: keyword), source: pack.title))
            }
        }
        let fieldWords = t.tr("这个字段里的词", "Words in this field")
        for word in words where word.hasPrefix(identifier) && word != identifier && !keywords.contains(word) {
            rows.append(SuggestionRow(text: word, comment: "", insertion: word, completion: word, typed: identifier, pick: nil,
                                      source: fieldWords))
        }
        return rows
    }
}

/// The longest start `texts` share, in any case (the first's case kept).
func commonPrefix(_ texts: [String]) -> String {
    guard var common = texts.first.map(Array.init) else { return "" }
    for text in texts.dropFirst() {
        let other = Array(text)
        var length = 0
        while length < min(common.count, other.count), String(common[length]).lowercased() == String(other[length]).lowercased() {
            length += 1
        }
        common = Array(common.prefix(length))
    }
    return String(common)
}

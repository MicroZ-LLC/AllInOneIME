import Foundation

/// A row of suggestions as a session shows it and puts it in (spec 1.4, 2).
struct SuggestionRow: Equatable {
    var text: String
    var comment: String
    /// What it puts in, whole: what was typed (`typed`) is its start, in any case; only the rest goes in.
    var insertion: String
    /// The caret this many UTF-16 units back from the end of what went in, where the field reports ranges (a snippet's
    /// first tab stop, or its `$0`).
    var caretBack = 0
    /// What it puts in instead where the field reports no ranges (the caret stays at the end there), when that differs:
    /// a snippet's first tab stop with its text too.
    var plainInsertion: String?
    /// What the terminal and code editor class completes: the item's `match`, a keyword, a snippet's trigger, a word.
    var completion: String
    /// The part of the token it answers: the whole token for a plugin's row, the identifier for coding's.
    var typed: String
    /// Kept as picked (rows picked before come first); nil: not kept (the field's own words).
    var pick: SuggestionPick?
    /// The source's title, for the footer, and when its list was made.
    var source: String
    var madeAt: Date?
    /// Code's (a pack's keyword or snippet, a word of the field), not a plugin's: Return picks it at once, as an
    /// IDE does (`InputSession.suggestionsReturnRow`).
    var coding = false

    /// What goes in for it where the field reports ranges (`ranges`), or not: what wasn't typed yet (the typed part, its
    /// case, stays).
    func rest(ranges: Bool) -> String { String((ranges ? insertion : plainInsertion ?? insertion).dropFirst(typed.count)) }
}

/// A list's or a query's items with what finding a token's among them needs, made once (off the session's thread, as
/// they come): each `match` in small letters, and where each is.
struct CompletionItems: Sendable {
    let items: [CompletionItem]
    /// Each item's `match` in small letters, in the items' order.
    let lowered: [String]
    /// The first item of each match in small letters.
    let positions: [String: Int]
    /// Whether each item is the first of its match in small letters.
    let firsts: [Bool]

    /// Their UTF-8, one after another, and where each starts (and, last, where the last ends): what a token's start is
    /// looked for in, a few bytes compared for most items.
    private let bytes: [UInt8]
    private let starts: [Int]

    init(_ items: [CompletionItem]) {
        self.items = items
        lowered = items.map { $0.match.lowercased() }
        var positions: [String: Int] = [:]
        positions.reserveCapacity(items.count)
        var firsts: [Bool] = []
        firsts.reserveCapacity(items.count)
        var bytes: [UInt8] = []
        var starts: [Int] = []
        starts.reserveCapacity(items.count + 1)
        for (index, match) in lowered.enumerated() {
            let first = positions[match] == nil
            if first { positions[match] = index }
            firsts.append(first)
            starts.append(bytes.count)
            bytes += match.utf8
        }
        starts.append(bytes.count)
        (self.positions, self.firsts, self.bytes, self.starts) = (positions, firsts, bytes, starts)
    }

    var count: Int { items.count }

    /// The first item from `start` on that answers `token` (normalized, in small letters) as `source` compares
    /// (`PluginRows.matches`); nil: none.
    func next(answering token: String, _ source: CompletionSource, from start: Int) -> Int? {
        guard start < items.count else { return nil }
        // A token not in ASCII, or compared whole: as `matches` compares, item by item.
        let wanted = Array(token.utf8)
        guard source.compare == .prefix, wanted.allSatisfy({ $0 < 0x80 }) else {
            return (start..<items.count).first { PluginRows.matches(lowered[$0], token, source) }
        }
        return bytes.withUnsafeBufferPointer { bytes in
            starts.withUnsafeBufferPointer { starts in
                wanted.withUnsafeBufferPointer { wanted in
                    var index = start
                    while index < items.count {
                        let from = starts[index], length = starts[index + 1] - from
                        var same = length >= wanted.count
                        var offset = 0
                        while same, offset < wanted.count {
                            same = bytes[from + offset] == wanted[offset]
                            offset += 1
                        }
                        // What follows isn't ASCII: a mark could join the token's last character (`hasPrefix` says).
                        if same, length == wanted.count || bytes[from + wanted.count] < 0x80 || lowered[index].hasPrefix(token) {
                            return index
                        }
                        index += 1
                    }
                    return nil
                }
            }
        }
    }
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

    /// Whether an item whose `match` in small letters is `match` answers `token` (normalized, in small letters) as
    /// `source` compares.
    static func matches(_ match: String, _ lowered: String, _ source: CompletionSource) -> Bool {
        source.compare == .exact ? match == lowered : match.hasPrefix(lowered)
    }

    /// How many of `items` answer `token` (normalized, in small letters), counted up to `limit`.
    static func count(_ items: CompletionItems, answering lowered: String, _ source: CompletionSource, upTo limit: Int) -> Int {
        var (count, start) = (0, 0)
        while count < limit, let found = items.next(answering: lowered, source, from: start) {
            count += 1
            start = found + 1
        }
        return count
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

    /// The most matching items a key fills the templates of for a source's rows (with a `limit`; those picked before
    /// aside): a template whose insertion never starts with what was typed (`"{url}"`, a plugin's mistake) costs a key no
    /// more than that over a list of 20,000, and shows no rows.
    static let maxTried = 100

    /// The rows of `lists` (the list's items, then the queries' answers, each match once: its first) for `token` in an
    /// app of `appClass`, in their order: those whose insertion starts with what was typed. Only what matches is looked
    /// at, and only until `limit` rows are found (nil: all of them), `maxTried` items tried at most then; the items
    /// picked before (`picked`, their `match`) are rows wherever they are, looked up on their own.
    static func rows(_ token: String, plugin: InstalledPlugin, source: CompletionSource, lists: [CompletionItems],
                     madeAt: Date?, appClass: SuggestionsAppClass, picked: Set<String> = [], limit: Int? = nil,
                     in t: InterfaceWords) -> [SuggestionRow] {
        guard let maker = RowMaker(token, plugin: plugin, source: source, madeAt: madeAt, appClass: appClass, in: t) else { return [] }
        // Where each row is: its list, then its place there.
        var found: [(list: Int, index: Int, row: SuggestionRow)] = []
        var (others, tried) = (0, 0)
        maker.each(in: lists) { number, index, item in
            // Picked before: looked up below, wherever it is.
            if picked.contains(item.match) { return true }
            tried += 1
            if let row = maker.row(item) {
                found.append((number, index, row))
                others += 1
            }
            guard let limit else { return true }
            return others < limit && tried < maxTried
        }
        for match in picked {
            let key = match.lowercased()
            guard matches(key, maker.lowered, source),
                  let (number, index) = lists.enumerated().lazy.compactMap({ number, list in list.positions[key].map { (number, $0) } }).first,
                  lists[number].items[index].match == match, let row = maker.row(lists[number].items[index]) else { continue }
            found.append((number, index, row))
        }
        return found.sorted { ($0.list, $0.index) < ($1.list, $1.index) }.map(\.row)
    }

    /// What each row of `lists` for `token` completes (as `rows` has them, every one: its `completion`), in their order,
    /// until `visit` says to stop (false): what Tab in a terminal or code editor completes is what all of them share.
    /// Only the insertion is made, no row.
    static func eachCompletion(_ token: String, plugin: InstalledPlugin, source: CompletionSource, lists: [CompletionItems],
                               appClass: SuggestionsAppClass, in t: InterfaceWords, _ visit: (String) -> Bool) {
        guard let maker = RowMaker(token, plugin: plugin, source: source, madeAt: nil, appClass: appClass, in: t) else { return }
        maker.each(in: lists) { _, _, item in maker.insertion(item) == nil || visit(item.match) }
    }

    /// What makes a source's rows for a token: its templates for the app's class, read once.
    struct RowMaker {
        let token: String
        let lowered: String
        let plugin: InstalledPlugin
        let source: CompletionSource
        let templates: [[CompletionTemplate.Part]]
        /// The template is `{match}` (the terminal and code editor class's): an item that answers the token puts in its
        /// match, which starts with what was typed.
        let matchOnly: Bool
        let title: String
        let madeAt: Date?

        /// Nil: the source has no rows in an app of `appClass` (`templates`).
        init?(_ token: String, plugin: InstalledPlugin, source: CompletionSource, madeAt: Date?, appClass: SuggestionsAppClass,
              in t: InterfaceWords) {
            guard let templates = PluginRows.templates(source, appClass) else { return nil }
            (self.token, self.plugin, self.source, self.madeAt) = (token, plugin, source, madeAt)
            lowered = SuggestionsToken.normalized(token).lowercased()
            self.templates = templates.compactMap(CompletionTemplate.parts)
            matchOnly = self.templates == [[.variable("match")]]
            title = source.title.text(chinese: t.chinese)
        }

        /// What `item` (one that answers the token: `each`) puts in, if it starts with what was typed.
        func insertion(_ item: CompletionItem) -> String? {
            if matchOnly { return item.match }
            guard let insertion = CompletionTemplate.fill(templates, with: item),
                  SuggestionsToken.normalized(insertion).lowercased().hasPrefix(lowered) else { return nil }
            return insertion
        }

        /// `item`'s row, if its insertion starts with what was typed.
        func row(_ item: CompletionItem) -> SuggestionRow? {
            guard let insertion = insertion(item) else { return nil }
            let (text, comment) = shown(item)
            return SuggestionRow(text: text, comment: comment, insertion: insertion, completion: item.match, typed: token,
                                 pick: SuggestionPick(plugin: plugin.name, source: source.name, match: item.match),
                                 source: title, madeAt: madeAt)
        }

        /// Each item of `lists` that answers the token, a match once (its first), in order, with its list and place,
        /// until `visit` says to stop (false).
        func each(in lists: [CompletionItems], _ visit: (Int, Int, CompletionItem) -> Bool) {
            for (number, list) in lists.enumerated() {
                var start = 0
                while let index = list.next(answering: lowered, source, from: start) {
                    start = index + 1
                    // A match once: its first (which answers the token too) visited already.
                    guard list.firsts[index],
                          number == 0 || !lists[..<number].contains(where: { $0.positions[list.lowered[index]] != nil }) else { continue }
                    guard visit(number, index, list.items[index]) else { return }
                }
            }
        }
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
        ordered(rows, scores: scores(picks))
    }

    /// `ordered` with the picks' scores (`scores`), worked out once for several sources' rows.
    static func ordered(_ rows: [SuggestionRow], scores: [SuggestionPick: Double]) -> [SuggestionRow] {
        guard !scores.isEmpty else { return rows }
        let picked = rows.enumerated().compactMap { index, row -> (Int, Double)? in
            row.pick.flatMap { scores[$0] }.map { (index, $0) }
        }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.map(\.0)
        let first = Set(picked)
        return picked.map { rows[$0] } + rows.indices.filter { !first.contains($0) }.map { rows[$0] }
    }
}

/// Code's rows (spec 2, decision 22): its coding language's pack's snippets and keywords, and the field's own words.
enum CodingRows {
    /// Rows from this many characters of an identifier on.
    static let minChars = 2
    /// The field's words: identifiers this long at least.
    static let minWordLength = 4
    /// How much of the field's text is looked through, each side of the caret.
    static let scanned = 20_000

    /// A snippet's body as it goes in (its caret as UTF-16 units from the end): `${n:text}` as its text, `${n}` and `$n`
    /// as nothing, the caret at its first tab stop in reading order, whichever comes first of `$0` and the numbered ones;
    /// a numbered stop chosen so goes in without its text, wherever it is (its mirrors too), the others keep theirs; at
    /// the end without a stop (spec 2, decisions 21 and 23). `toFirstStop` false, for a field the caret can't be put back
    /// into: every stop with its text, the caret at `$0`.
    static func expand(_ body: String, toFirstStop: Bool = true) -> (text: String, caretBack: Int) {
        let parts = snippetParts(body)
        let first = toFirstStop ? parts.lazy.compactMap { part -> Int? in
            if case let .stop(number, _) = part { return number } else { return nil }
        }.first.flatMap { $0 > 0 ? $0 : nil } : nil
        var out = ""
        var (atFirst, atZero): (Int?, Int?) = (nil, nil)
        for part in parts {
            switch part {
            case let .text(text):
                out += text
            case let .stop(number, _) where number == first:
                if atFirst == nil { atFirst = out.utf16.count }
            case let .stop(number, text):
                if number == 0 { atZero = out.utf16.count }
                out += text
            }
        }
        return (out, (atFirst ?? atZero).map { out.utf16.count - $0 } ?? 0)
    }

    /// A piece of a snippet's body: text as it goes in, or a tab stop (`$n`, `${n}`, `${n:text}`), its number and text.
    enum SnippetPart: Equatable {
        case text(String)
        case stop(Int, String)
    }

    /// `body` as its text and its tab stops, in order; a `$` that starts none is text.
    static func snippetParts(_ body: String) -> [SnippetPart] {
        var parts: [SnippetPart] = []
        var out = ""
        func stop(_ number: String, _ text: String) {
            if !out.isEmpty { parts.append(.text(out)) }
            out = ""
            parts.append(.stop(Int(number) ?? .max, text))
        }
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
                stop(number, "")
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
                stop(number, characters[end] == ":" ? String(characters[(end + 1)..<min(close, characters.count)]) : "")
                index = min(close + 1, characters.count)
            } else {
                out.append(character)
                index += 1
            }
        }
        if !out.isEmpty { parts.append(.text(out)) }
        return parts
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

    /// The rows for `identifier` (what is typed of it): `pack`'s snippets whose trigger it starts (the whole trigger too)
    /// and whose body starts with it, its keywords it starts (not one typed in full), and `words`; in an app of
    /// `appClass` (terminals and code editors: a snippet completes as its trigger). A snippet's later lines get `indent`
    /// (the caret's line's); two that put in the same are one row (spec 6.19). The comment says what a row is, not its
    /// language: Code has one (decision 22).
    static func rows(_ identifier: String, pack: CodingLanguagePack?, words: [String], indent: String = "",
                     appClass: SuggestionsAppClass, in t: InterfaceWords) -> [SuggestionRow] {
        guard identifier.count >= minChars else { return [] }
        let code = appClass == .codeEditor
        var snippets: [(row: SuggestionRow, title: String?)] = []
        var byInsertion = Set<String>()
        if let pack {
            for snippet in pack.snippets where snippet.trigger.hasPrefix(identifier) {
                let body = indented(snippet.body, by: indent)
                // Where the caret can't go back into it, every stop's text; else the first stop's left out, the caret
                // there, unless that stop is within what was typed (a body that starts with it): `$0`'s then.
                let plain = expand(body, toFirstStop: false)
                guard plain.text.hasPrefix(identifier) else { continue }
                var (text, caretBack) = expand(body)
                if !text.hasPrefix(identifier) { (text, caretBack) = plain }
                let (insertion, back, other) = code ? (snippet.trigger, 0, nil) : (text, caretBack, plain.text == text ? nil : plain.text)
                guard byInsertion.insert(insertion + "\u{0}\(back)\u{0}" + (other ?? "")).inserted else { continue }
                // Its title where it says more than its trigger.
                let title = snippet.title.flatMap { $0 == snippet.trigger ? nil : $0 }
                // Picked as itself, not as every snippet of its trigger ("if", "if/else", "main guard").
                let pick = SuggestionPick(plugin: "", source: pack.language, match: "snippet:\(snippet.trigger):\(snippet.title ?? snippet.body)")
                snippets.append((SuggestionRow(text: snippet.trigger, comment: "", insertion: insertion, caretBack: back,
                                               plainInsertion: other, completion: snippet.trigger, typed: identifier, pick: pick,
                                               source: pack.title, coding: true), title))
            }
        }
        // Its title, or that it's a snippet ("function", "snippet").
        let snippetWord = t.tr("代码片段", "snippet")
        var rows = snippets.map { snippet in
            var row = snippet.row
            row.comment = snippet.title ?? snippetWord
            return row
        }
        var keywords = Set<String>()
        if let pack {
            let keywordWord = t.tr("关键字", "keyword")
            for keyword in pack.keywords where keyword.hasPrefix(identifier) && keyword != identifier {
                guard keywords.insert(keyword).inserted else { continue }
                rows.append(SuggestionRow(text: keyword, comment: keywordWord, insertion: keyword, completion: keyword, typed: identifier,
                                          pick: SuggestionPick(plugin: "", source: pack.language, match: keyword), source: pack.title,
                                          coding: true))
            }
        }
        let fieldWords = t.tr("这个字段里的词", "Words in this field")
        for word in words where word.hasPrefix(identifier) && word != identifier && !keywords.contains(word) {
            rows.append(SuggestionRow(text: word, comment: "", insertion: word, completion: word, typed: identifier, pick: nil,
                                      source: fieldWords, coding: true))
        }
        return rows
    }
}

/// The longest start `texts` share, in any case (the first's case kept).
func commonPrefix(_ texts: [String]) -> String {
    guard var common = texts.first else { return "" }
    for text in texts.dropFirst() where !common.isEmpty {
        common = commonPrefix(common, text)
    }
    return common
}

/// The longest start `a` and `b` share, in any case (`a`'s case kept; `a` itself when it is all shared). Byte by byte
/// while both are ASCII (an item's match, a keyword: most often all of it), character by character where either isn't
/// (or a mark could join the last character compared): no string made per character.
func commonPrefix(_ a: String, _ b: String) -> String {
    var (a, b) = (a, b)
    // The bytes both share, where they stop at a character's start in both; nil: not so.
    let shared: Int? = a.withUTF8 { x in
        b.withUTF8 { y in
            let end = min(x.count, y.count)
            var n = 0
            while n < end {
                var (c, d) = (x[n], y[n])
                guard c < 0x80, d < 0x80 else { break }
                if c != d {
                    if (0x41...0x5A).contains(c) { c |= 0x20 }
                    if (0x41...0x5A).contains(d) { d |= 0x20 }
                    guard c == d else { break }
                }
                n += 1
            }
            return (n == x.count || x[n] < 0x80) && (n == y.count || y[n] < 0x80) ? n : nil
        }
    }
    if let shared {
        return shared == a.utf8.count ? a : String(a[..<a.utf8.index(a.utf8.startIndex, offsetBy: shared)])
    }
    var (k, l) = (a.startIndex, b.startIndex)
    while k < a.endIndex, l < b.endIndex {
        let (c, d) = (a[k], b[l])
        guard c == d || c.lowercased() == d.lowercased() else { break }
        (k, l) = (a.index(after: k), b.index(after: l))
    }
    return k == a.endIndex ? a : String(a[..<k])
}

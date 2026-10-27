import Foundation

/// A row of suggestions as a session shows it and puts it in (spec 1.4, 2).
struct SuggestionRow: Equatable {
    var text: String
    var comment: String
    /// What it puts in, whole: what was typed (`typed`) is its start, in any case, and only the rest goes in; unless it
    /// `replaces` the token.
    var insertion: String
    /// `insertion` doesn't start with what was typed (a template like `[{title}]({url})`, 0.6.7.1 §1): where the field
    /// reports ranges, it takes the token's place, the token taken out and all of it put in.
    var replaces = false
    /// The caret this many UTF-16 units back from the end of what went in, where the field reports ranges (a snippet's
    /// first tab stop, or its `$0`).
    var caretBack = 0
    /// What it puts in instead where the field reports no ranges (the caret stays at the end there, and no token can be
    /// taken out), when that differs: a snippet's first tab stop with its text too; for a row that `replaces`, the next
    /// of its templates that starts with what was typed (what was typed itself where none does: nothing more goes in).
    var plainInsertion: String?
    /// What the row is of: the item's `match`, a keyword, a snippet's trigger, a word (`isSame`).
    var completion: String
    /// The part of the token it answers: the whole token for a plugin's row, the identifier for coding's.
    var typed: String
    /// Kept as picked (rows picked before come first); nil: not kept (the field's own words).
    var pick: SuggestionPick?
    /// The source's title, for the footer, and when its list was made.
    var source: String
    var madeAt: Date?

    /// What goes in for it where the field reports ranges (`ranges`), or not: what wasn't typed yet (the typed part, its
    /// case, stays), or (`replacing`) the whole of it in the token's place.
    func put(ranges: Bool) -> (text: String, replacing: Bool) {
        if replaces, ranges { return (insertion, true) }
        return (String((ranges ? insertion : plainInsertion ?? insertion).dropFirst(typed.count)), false)
    }

    /// What wasn't typed yet of what goes in for it (`put`); for a row that takes the token's place there, all of it.
    func rest(ranges: Bool) -> String { put(ranges: ranges).text }

    /// Whether `other` is this row made again for the same token: the same item, keyword or snippet (its pick), else the
    /// same word from the same source. What it puts in, and what its comment says, may differ (the caret's line's
    /// indentation read since, an item's title as a query tells it).
    func isSame(as other: SuggestionRow) -> Bool {
        pick == other.pick && source == other.source && text == other.text && completion == other.completion
    }
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
        var found: Int?
        each(answering: token, source, from: start) { index in
            found = index
            return false
        }
        return found
    }

    /// Each item from `start` on that answers `token` (normalized, in small letters) as `source` compares
    /// (`PluginRows.matches`), in order, until `visit` says to stop (false): what `next` finds, the token's bytes read
    /// once for all of them (a key may look for 100).
    func each(answering token: String, _ source: CompletionSource, from start: Int = 0, _ visit: (Int) -> Bool) {
        guard start < items.count else { return }
        // A token not in ASCII, or compared whole: as `matches` compares, item by item.
        let wanted = Array(token.utf8)
        guard source.compare == .prefix, wanted.allSatisfy({ $0 < 0x80 }) else {
            for index in start..<items.count where PluginRows.matches(lowered[index], token, source) {
                guard visit(index) else { return }
            }
            return
        }
        bytes.withUnsafeBufferPointer { bytes in
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
                            guard visit(index) else { return }
                        }
                        index += 1
                    }
                }
            }
        }
    }
}

/// The rows a completion source has for a token (spec 1.3, 1.4, 6.7, 6.8, 6.13; 0.6.7.1 §1): a plugin's, a script
/// extension's, a custom command's.
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
        var count = 0
        guard limit > 0 else { return 0 }
        items.each(answering: lowered, source) { _ in
            count += 1
            return count < limit
        }
        return count
    }

    /// The templates of `source` for an app of `appClass` where the user chose `insert` (decision 28: the app's own, else
    /// the one everywhere): the source's own for the class, the terminal and code editor class's `{match}` (spec 6.10),
    /// or the choice's in every class. Nil: none there (`null`), whatever is chosen. The one place a row's templates are
    /// decided.
    static func templates(_ source: CompletionSource, _ appClass: SuggestionsAppClass, insert: SuggestionsInsert = .source) -> [String]? {
        let chosen: CompletionInsert.Templates
        switch appClass {
        case .ordinary, .none: chosen = source.insert.default
        case .chat: chosen = source.insert.chat ?? source.insert.default
        case .codeEditor:
            if (source.insert.terminal ?? source.insert.default) == .off { return nil }
            return insert.templates ?? ["{match}"]
        }
        if case let .templates(list) = chosen { return insert.templates ?? list }
        return nil
    }

    /// The most matching items a key fills the templates of for a source's rows (with a `limit`; those picked before
    /// aside): templates none of which can go in here (`"{url}"` where the field reports no ranges) cost a key no more
    /// than that over a list of 20,000, and show no rows.
    static let maxTried = 100

    /// The rows of `lists` (the list's items, then the queries' answers, each match once: its first) for `token` in an
    /// app of `appClass` where `insert` is chosen, in their order: those whose `match` answers the token and that have a
    /// template that can go in here (`RowMaker.insertion`; `replacing`: the field reports ranges, and one that doesn't
    /// start with what was typed can take its place). Only what matches is looked at, and only until `limit` rows are
    /// found (nil: all of them), `maxTried` items tried at most then; the items picked before (`picked`, their `match`)
    /// are rows wherever they are, looked up on their own.
    static func rows(_ token: String, key: CompletionSourceKey, source: CompletionSource, lists: [CompletionItems],
                     madeAt: Date?, appClass: SuggestionsAppClass, insert: SuggestionsInsert = .source, replacing: Bool = false,
                     picked: Set<String> = [], limit: Int? = nil, in t: InterfaceWords) -> [SuggestionRow] {
        guard let maker = RowMaker(token, key: key, source: source, madeAt: madeAt, appClass: appClass, insert: insert,
                                   replacing: replacing, in: t)
        else { return [] }
        // The rows in the order their items were visited, and where each is: its list, then its place there.
        var rows: [SuggestionRow] = []
        var places: [(list: Int, index: Int)] = []
        rows.reserveCapacity(min(limit ?? 16, 16))
        var tried = 0
        maker.each(in: lists) { number, index, item in
            // Picked before: looked up below, wherever it is.
            if picked.contains(item.match) { return true }
            tried += 1
            if let row = maker.row(item) {
                rows.append(row)
                places.append((number, index))
            }
            guard let limit else { return true }
            return rows.count < limit && tried < maxTried
        }
        let others = rows.count
        for match in picked {
            let key = match.lowercased()
            guard matches(key, maker.lowered, source),
                  let (number, index) = lists.enumerated().lazy.compactMap({ number, list in list.positions[key].map { (number, $0) } }).first,
                  lists[number].items[index].match == match, let row = maker.row(lists[number].items[index]) else { continue }
            rows.append(row)
            places.append((number, index))
        }
        // Visited in order: only the rows picked before, added last, need their places.
        guard rows.count > others else { return rows }
        return places.indices.sorted { (places[$0].list, places[$0].index) < (places[$1].list, places[$1].index) }.map { rows[$0] }
    }

    /// What makes a source's rows for a token: its templates for the app's class and the choice made there, read once.
    struct RowMaker {
        let token: String
        let lowered: String
        /// The source's (a plugin's, a custom command's): what a row picked is kept by.
        let key: CompletionSourceKey
        let source: CompletionSource
        let templates: [[CompletionTemplate.Part]]
        /// The template is `{match}` (the terminal and code editor class's): an item that answers the token puts in its
        /// match, which starts with what was typed.
        let matchOnly: Bool
        /// The field reports where its text is (`InputSession.suggestionsReplace`): a template that doesn't start with
        /// what was typed can take the token's place.
        let replacing: Bool
        let title: String
        let madeAt: Date?

        /// Nil: the source has no rows in an app of `appClass` (`templates`).
        init?(_ token: String, key: CompletionSourceKey, source: CompletionSource, madeAt: Date?, appClass: SuggestionsAppClass,
              insert: SuggestionsInsert = .source, replacing: Bool = false, in t: InterfaceWords) {
            guard let templates = PluginRows.templates(source, appClass, insert: insert) else { return nil }
            (self.token, self.key, self.source, self.madeAt, self.replacing) = (token, key, source, madeAt, replacing)
            lowered = SuggestionsToken.normalized(token).lowercased()
            self.templates = templates.compactMap(CompletionTemplate.parts)
            matchOnly = self.templates == [[.variable("match")]]
            title = source.title.text(chinese: t.chinese)
        }

        /// What `item` (one that answers the token: `each`) puts in (0.6.7.1 §1): the first of its templates whose
        /// variables it all has and that can go in here. One that starts with what was typed (normalized, in any case)
        /// follows it; one that doesn't takes the token's place where the field reports ranges (`replacing`: then also
        /// `plain`, the next that starts with what was typed, for a key that finds the field reports none after all), and
        /// is skipped for the next elsewhere. Nil: none can.
        func insertion(_ item: CompletionItem) -> (text: String, replaces: Bool, plain: String?)? {
            if matchOnly { return (item.match, false, nil) }
            var replacement: String?
            for parts in templates {
                guard let filled = CompletionTemplate.fill([parts], with: item) else { continue }
                if SuggestionsToken.normalized(filled).lowercased().hasPrefix(lowered) {
                    return replacement.map { ($0, true, filled) } ?? (filled, false, nil)
                }
                // Nothing in the token's place would only take it out.
                if replacing, replacement == nil, !filled.trimmingCharacters(in: .whitespaces).isEmpty { replacement = filled }
            }
            return replacement.map { ($0, true, nil) }
        }

        /// `item`'s row, if one of its templates can go in here (`insertion`).
        func row(_ item: CompletionItem) -> SuggestionRow? {
            guard let put = insertion(item) else { return nil }
            let (text, comment) = shown(item)
            return SuggestionRow(text: text, comment: comment, insertion: put.text, replaces: put.replaces,
                                 plainInsertion: put.replaces ? put.plain ?? token : nil, completion: item.match, typed: token,
                                 pick: SuggestionPick(plugin: key.plugin, source: key.source, match: item.match),
                                 source: title, madeAt: madeAt)
        }

        /// Each item of `lists` that answers the token, a match once (its first), in order, with its list and place,
        /// until `visit` says to stop (false).
        func each(in lists: [CompletionItems], _ visit: (Int, Int, CompletionItem) -> Bool) {
            var going = true
            for (number, list) in lists.enumerated() where going {
                list.each(answering: lowered, source) { index in
                    // A match once: its first (which answers the token too) visited already.
                    guard list.firsts[index],
                          number == 0 || !lists[..<number].contains(where: { $0.positions[list.lowered[index]] != nil }) else { return true }
                    going = visit(number, index, list.items[index])
                    return going
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
    /// and whose body starts with it, its keywords and built-ins it starts (not one typed in full), and `words`; in an
    /// app of `appClass` (terminals and code editors: a snippet goes in as its trigger). A snippet's later lines get
    /// `indent` (the caret's line's); two that put in the same are one row (spec 6.19). The comment says what a row is,
    /// not its language: Code has one (decision 22).
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
                                               source: pack.title), title))
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
            // Its keywords, then its built-ins (functions, types, library names), each saying which it is.
            let lists = [(pack.keywords, t.tr("关键字", "keyword")), (pack.builtins ?? [], t.tr("内置", "built-in"))]
            for (list, comment) in lists {
                for keyword in list where keyword.hasPrefix(identifier) && keyword != identifier {
                    guard keywords.insert(keyword).inserted else { continue }
                    rows.append(SuggestionRow(text: keyword, comment: comment, insertion: keyword, completion: keyword, typed: identifier,
                                              pick: SuggestionPick(plugin: "", source: pack.language, match: keyword), source: pack.title))
                }
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

import Foundation

/// A completion source's template (`insert`): text with an item's variables in braces, `{match}`, `{arg}` and the
/// item's own (`{url}`).
enum CompletionTemplate {
    enum Part: Equatable {
        case text(String)
        case variable(String)
    }

    /// `template` in its parts; nil when it isn't one (a `{` not closing a name of letters, digits and `_`, a `}` alone).
    static func parts(_ template: String) -> [Part]? {
        var parts: [Part] = []
        var text = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            if character == "}" { return nil }
            guard character == "{" else {
                text.append(character)
                index = template.index(after: index)
                continue
            }
            guard let close = template[index...].firstIndex(of: "}") else { return nil }
            let name = String(template[template.index(after: index)..<close])
            guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
            if !text.isEmpty { parts.append(.text(text)) }
            text = ""
            parts.append(.variable(name))
            index = template.index(after: close)
        }
        if !text.isEmpty { parts.append(.text(text)) }
        return parts
    }

    /// `templates` filled with `item`'s variables: the first whose variables the item all has (nil: none).
    static func fill(_ templates: [String], with item: CompletionItem) -> String? {
        fill(templates.compactMap(parts), with: item)
    }

    /// `fill` with the templates in their parts (`parts`), read once for many items.
    static func fill(_ templates: [[Part]], with item: CompletionItem) -> String? {
        for parts in templates {
            var out = ""
            var complete = true
            for part in parts {
                switch part {
                case let .text(text): out += text
                case let .variable(name):
                    guard let value = value(of: name, in: item) else {
                        complete = false
                        break
                    }
                    out += value
                }
                if !complete { break }
            }
            if complete { return CompletionOutput.clean(out) }
        }
        return nil
    }

    /// The variable `name` of `item`: its `match`, its `arg` (else its match), or one of its own.
    static func value(of name: String, in item: CompletionItem) -> String? {
        switch name {
        case "match": return item.match
        case "arg": return item.arg ?? item.match
        default: return item.variables?[name]
        }
    }
}

/// The characters a token is made of, and what is typed in another form of them (spec 1.3).
enum SuggestionsToken {
    /// Full-width ASCII forms as ASCII ("＃" "#", "１" "1"); the rest as it is.
    static func normalized(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if (0xFF01...0xFF5E).contains(scalar.value), let ascii = Unicode.Scalar(scalar.value - 0xFEE0) {
                scalars.append(ascii)
            } else if scalar.value == 0x3000 {
                scalars.append(" ")
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// `character` (normalized) can be in a token: Latin letters, digits, `. _ - @ #`.
    static func isTokenCharacter(_ character: Character) -> Bool {
        if "._-@#".contains(character) { return true }
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return false }
        if scalar.isASCII { return character.isLetter || character.isNumber }
        // Latin letters with their marks (Latin-1 Supplement, Extended-A and -B): not Chinese, Japanese, Korean or
        // other scripts, which the input method's own composition puts in.
        return (0xC0...0x24F).contains(scalar.value) && character.isLetter
    }

    /// `character` (normalized) can be in an identifier: Latin letters, digits, `_`.
    static func isIdentifierCharacter(_ character: Character) -> Bool {
        character == "_" || isTokenCharacter(character) && !"._-@#".contains(character)
    }

    /// The identifier `text` ends with (`self.co` → `co`).
    static func identifier(endingAt text: String) -> String {
        String(text.reversed().prefix { isIdentifierCharacter($0) }.reversed())
    }
}

/// What a script returns (`load`, `query`), checked and cleaned (spec 1.2, 6.5, 6.6).
public enum CompletionOutput {
    /// Why an output is refused (the old list is kept), as Settings says it.
    public enum Failure: Error, Equatable {
        case tooLarge(bytes: Int)
        case tooManyItems(Int)
        case notAList

        public var message: String {
            switch self {
            case .tooLarge:
                return tr("插件返回的列表超过 4 MB，没有用", "The plugin's list is larger than 4 MB: not used")
            case .tooManyItems:
                return tr("插件返回的列表超过 20,000 项，没有用", "The plugin's list has more than 20,000 items: not used")
            case .notAList:
                return tr("插件返回的不是带 items 列表的 JSON 对象", "The plugin didn't return a JSON object with an items list")
            }
        }
    }

    /// `data` read: a JSON object with an `items` array, at most `CompletionList.maxBytes` and `maxItems`; each item an
    /// object with a good `match` once control, bidi and zero-width characters are taken out of everything (bad ones
    /// dropped one by one), the same `match` (in any case) kept once, the first. `digitsOnly`: a source without prefix,
    /// whose matches are digits.
    public static func read(_ data: Data, digitsOnly: Bool = false) -> Result<CompletionList, Failure> {
        guard data.count <= CompletionList.maxBytes else { return .failure(.tooLarge(bytes: data.count)) }
        guard let object = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any],
              let entries = object["items"] as? [Any] else { return .failure(.notAList) }
        guard entries.count <= CompletionList.maxItems else { return .failure(.tooManyItems(entries.count)) }
        var items: [CompletionItem] = []
        var seen = Set<String>()
        items.reserveCapacity(entries.count)
        for entry in entries {
            guard let item = item(entry), !digitsOnly || item.match.allSatisfy({ $0.isASCII && $0.isNumber }),
                  seen.insert(item.match.lowercased()).inserted else { continue }
            items.append(item)
        }
        let fetchedAt = (object["fetchedAt"] as? NSNumber).flatMap { number -> Double? in
            number.isBoolean ? nil : number.doubleValue
        }
        return .success(CompletionList(items: items, fetchedAt: fetchedAt))
    }

    /// One item, cleaned; nil when it isn't one.
    static func item(_ entry: Any) -> CompletionItem? {
        guard let fields = entry as? [String: Any], let raw = fields["match"] as? String else { return nil }
        let match = clean(raw)
        guard isMatch(match) else { return nil }
        func text(_ key: String, limit: Int = 300) -> String? {
            guard let value = fields[key] as? String else { return nil }
            let cleaned = String(clean(value).prefix(limit))
            return cleaned.isEmpty ? nil : cleaned
        }
        var variables: [String: String]?
        if let raw = fields["variables"] as? [String: Any] {
            var kept: [String: String] = [:]
            for (name, value) in raw.prefix(32) {
                guard let value = value as? String else { continue }
                kept[name] = String(clean(value).prefix(2000))
            }
            variables = kept.isEmpty ? nil : kept
        }
        return CompletionItem(match: match, title: text("title"), subtitle: text("subtitle"), arg: text("arg", limit: 2000),
                              variables: variables)
    }

    /// 1–64 letters, digits and `. _ - @ #`.
    static func isMatch(_ text: String) -> Bool {
        (1...64).contains(text.count) && text.allSatisfy { character in
            "._-@#".contains(character) || character.unicodeScalars.count == 1 && (character.isLetter || character.isNumber)
                && !(character.unicodeScalars.first?.properties.isEmojiPresentation ?? false)
        }
    }

    /// `text` without what would change what the user sees or a terminal does: control characters (Cc), format ones
    /// (Cf: bidi controls, zero-width characters, the BOM), line and paragraph separators.
    static func clean(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isHidden) else { return text }
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !isHidden(scalar) { scalars.append(scalar) }
        return String(scalars)
    }

    static func isHidden(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }
}

import Foundation

/// What is hidden from the AI before a request is sent (`Redaction`): `Config.redaction`. Off by default; on, each
/// detector is on unless turned off, and the user's own words are hidden too.
public struct RedactionSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var emails: Bool
    public var phones: Bool
    /// Payment card numbers (Luhn-checked, a known issuer's prefix).
    public var cards: Bool
    /// API keys and tokens: known prefixes (sk-, AKIA, ghp_ …) and long random-looking strings.
    public var keys: Bool
    public var ips: Bool
    /// The user's own words and phrases (a project's codename, a name), matched in any case.
    public var customWords: [String]

    public init(enabled: Bool = false, emails: Bool = true, phones: Bool = true, cards: Bool = true, keys: Bool = true,
                ips: Bool = true, customWords: [String] = []) {
        self.enabled = enabled
        self.emails = emails
        self.phones = phones
        self.cards = cards
        self.keys = keys
        self.ips = ips
        self.customWords = customWords
    }

    private enum CodingKeys: String, CodingKey { case enabled, emails, phones, cards, keys, ips, customWords }

    /// Every key is optional: missing ones keep the defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RedactionSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        emails = try c.decodeIfPresent(Bool.self, forKey: .emails) ?? d.emails
        phones = try c.decodeIfPresent(Bool.self, forKey: .phones) ?? d.phones
        cards = try c.decodeIfPresent(Bool.self, forKey: .cards) ?? d.cards
        keys = try c.decodeIfPresent(Bool.self, forKey: .keys) ?? d.keys
        ips = try c.decodeIfPresent(Bool.self, forKey: .ips) ?? d.ips
        customWords = try c.decodeIfPresent([String].self, forKey: .customWords) ?? d.customWords
    }

    /// The words of a settings field: separated by commas (，、 too), semicolons or lines, trimmed, each once.
    public static func words(from text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: { ",，、;；\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// One request's hidden values. Before a request is sent, the values the detectors find in the user's texts (emails,
/// phone and card numbers, keys, IP addresses, the user's own words) are replaced with placeholders such as
/// `[EMAIL_1]` (`hide`), and nothing else of the request may hold them (`protect`); the model's lines get the real
/// values back (`restore`), whatever it did to a placeholder's spacing, case or language. A value keeps its
/// placeholder for the whole request, numbered in the order the values appear. Detection runs on the text with
/// full-width and other compatibility forms folded (NFKC), so "zhang＠example.com" is found too; what is hidden and
/// put back is always the text as typed. A placeholder that can't be told any more stays as written (`isAltered`).
public struct Redaction: Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case email = "EMAIL", phone = "PHONE", card = "CARD", key = "KEY", ip = "IP", item = "ITEM"
    }

    public struct Hidden: Equatable, Sendable {
        public let kind: Kind
        public let number: Int
        /// As typed (not folded).
        public let value: String
        public var placeholder: String { "[\(kind.rawValue)_\(number)]" }
    }

    /// A value found in a text: its kind and where it is in the text as given (UTF-16).
    public struct Found: Equatable, Sendable {
        public let kind: Kind
        public let range: NSRange
    }

    public let settings: RedactionSettings
    /// The values hidden so far, in the order they appear.
    public private(set) var hidden: [Hidden] = []
    public var count: Int { hidden.count }
    /// Every text hidden (the user's text, a custom command's prompt) with what was sent instead.
    public private(set) var texts: [(original: String, sent: String)] = []
    /// Kinds and numbers the user's own texts already hold in a placeholder's shape ("ip_1", "[Item 1]"): never
    /// issued, so what the model writes back can't be mistaken for one of ours.
    private var reserved = Set<String>()

    /// Nil when hiding is off.
    public init?(_ settings: RedactionSettings) {
        guard settings.enabled else { return nil }
        self.settings = settings
    }

    /// The system prompt's last lines when something was hidden (and only then: other requests stay as they were).
    public static let note = "Some values in the text were replaced with placeholders in square brackets, such as "
        + "[EMAIL_1]. Keep every placeholder exactly as it is wherever the value belongs: the same brackets, letters and "
        + "number, never translated, changed or explained."

    // MARK: Hiding

    /// `text` with every value found replaced by its placeholder; a value seen before keeps its placeholder.
    public mutating func hide(_ text: String) -> String { hide([text])[0] }

    /// `texts` (the user's text, then a command's own prompt) hidden in order, numbered across them. Placeholder-
    /// shaped words in any of them are reserved first.
    public mutating func hide(_ texts: [String]) -> [String] {
        for text in texts { reserve(text) }
        return texts.map { text in
            let found = Self.find(text, settings: settings)
            let ns = text as NSString
            // Numbered as they appear, then replaced from the end (the ranges stay valid).
            let placeholders = found.map { placeholder(for: ns.substring(with: $0.range), kind: $0.kind) }
            let out = NSMutableString(string: text)
            for (item, placeholder) in zip(found, placeholders).reversed() { out.replaceCharacters(in: item.range, with: placeholder) }
            self.texts.append((text, out as String))
            return out as String
        }
    }

    private mutating func reserve(_ text: String) {
        let ns = text as NSString
        for match in Self.placeholderShaped.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if let kind = Self.kind(named: ns.substring(with: match.range(at: 1))), let n = Int(ns.substring(with: match.range(at: 2))) {
                reserved.insert("\(kind.rawValue)_\(n)")
            }
        }
    }

    private mutating func placeholder(for value: String, kind: Kind) -> String {
        if let known = hidden.first(where: { $0.value == value }) { return known.placeholder }
        var number = (hidden.filter { $0.kind == kind }.map(\.number).max() ?? 0) + 1
        while reserved.contains("\(kind.rawValue)_\(number)") { number += 1 }
        let entry = Hidden(kind: kind, number: number, value: value)
        hidden.append(entry)
        return entry.placeholder
    }

    /// `request` as it may be sent: its last message (the user's text) is `sent` (`hide`), the texts hidden appear
    /// hidden wherever they are (a custom command's prompt in the instructions), and no other part of it holds a
    /// hidden value. With anything hidden, the system prompt ends with `note`; with nothing, the request is the same.
    public func protect(_ request: ConverseRequest, sent: String) -> ConverseRequest {
        guard !hidden.isEmpty else { return request }
        var out = request
        for i in out.system.indices { out.system[i].text = scrub(out.system[i].text) }
        for i in out.messages.indices {
            for j in out.messages[i].content.indices { out.messages[i].content[j].text = scrub(out.messages[i].content[j].text) }
        }
        if let last = out.messages.indices.last { out.messages[last].content = [.init(sent)] }
        if let last = out.system.indices.last { out.system[last].text += "\n\n" + Self.note }
        return out
    }

    /// `text` with the values hidden so far replaced by their placeholders wherever they are: each text hidden as
    /// it was sent, then what the detectors find in it (the same matching as `hide`, so whatever was found there is
    /// found here), then any value left as typed (all but the user's words, which may be part of a longer word).
    public func scrub(_ text: String) -> String {
        var out = text
        for (original, sent) in texts.sorted(by: { $0.original.count > $1.original.count }) where original != sent && !original.isEmpty {
            out = out.replacingOccurrences(of: original, with: sent)
        }
        let ns = out as NSString
        let replaced = NSMutableString(string: out)
        for item in Self.find(out, settings: settings).reversed() {
            let value = ns.substring(with: item.range)
            if let entry = hidden.first(where: { $0.value == value }) { replaced.replaceCharacters(in: item.range, with: entry.placeholder) }
        }
        out = replaced as String
        for entry in hidden.sorted(by: { $0.value.count > $1.value.count }) where entry.kind != .item {
            out = out.replacingOccurrences(of: entry.value, with: entry.placeholder)
        }
        return out
    }

    /// Whether a jargon list's entry may be sent: nothing in it is a value to hide.
    public func allows(_ entry: JargonEntry) -> Bool {
        let text = entry.term + "\n" + entry.meaning
        return Self.find(text, settings: settings).isEmpty && scrub(text) == text
    }

    // MARK: Restoring

    /// `text` from the model with the real values back. A placeholder may come back with other spacing, case or
    /// brackets, or its kind translated ("[电子邮件_1]"); it is put back only when its kind is one of ours and its
    /// number was issued in this request, and never when the user's own text holds it as written ("ip_1"). Others
    /// stay as written. While a line streams in (`complete` false), what may be the start of a placeholder at its
    /// end isn't shown yet: it is held back before anything is put back.
    public func restore(_ text: String, complete: Bool = true) -> String {
        guard !hidden.isEmpty else { return text }
        var out = complete ? text : Self.holdingBack(text)
        for regex in [Self.bracketed, Self.unclosed, Self.bare] {
            let ns = out as NSString
            let replaced = NSMutableString(string: out)
            for match in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed() {
                if regex == Self.unclosed, !unambiguous(match, in: ns) { continue }
                if let value = resolve(match, in: ns) { replaced.replaceCharacters(in: match.range, with: value) }
            }
            out = replaced as String
        }
        return out
    }

    /// Whether a placeholder whose closing bracket is missing ("[EMAIL_1 today") can only be the one its number
    /// says: no other number issued for its kind starts with its digits ("[EMAIL_1" with EMAIL_10 issued can't tell).
    private func unambiguous(_ match: NSTextCheckingResult, in text: NSString) -> Bool {
        guard let kind = Self.kind(named: text.substring(with: match.range(at: 1))) else { return false }
        let digits = text.substring(with: match.range(at: 3))
        return !hidden.contains { $0.kind == kind && String($0.number) != digits && String($0.number).hasPrefix(digits) }
    }

    /// Every line of `result` restored (`restore`).
    public func restore(_ result: ConversionResult) -> ConversionResult {
        guard !hidden.isEmpty else { return result }
        func line(_ line: CandidateLine) -> CandidateLine {
            CandidateLine(restore(line.text, complete: line.isComplete), isComplete: line.isComplete)
        }
        var out = result
        out.versions = out.versions.map(line)
        out.translations = out.translations.map { Translation(language: $0.language, line: line($0.line)) }
        out.rewrites = out.rewrites.map { Rewrite(style: $0.style, line: line($0.line)) }
        return out
    }

    /// The real value a placeholder written as `match` stands for, or nil.
    private func resolve(_ match: NSTextCheckingResult, in text: NSString) -> String? {
        let token = text.substring(with: match.range)
        guard let number = Int(text.substring(with: match.range(at: match.numberOfRanges - 1))),
              let kind = Self.kind(named: text.substring(with: match.range(at: 1))),
              match.numberOfRanges == 3 || Self.looksPlaceholder(match, in: text),
              !texts.contains(where: { $0.original.contains(token) }) else { return nil }
        return hidden.first { $0.kind == kind && $0.number == number }?.value
    }

    /// Whether a bracketed match is a placeholder rather than words in brackets ("(item 1)"): in square brackets,
    /// or with "_".
    private static func looksPlaceholder(_ match: NSTextCheckingResult, in text: NSString) -> Bool {
        "[【［".contains(text.substring(with: NSRange(location: match.range.location, length: 1)))
            || text.substring(with: match.range(at: 2)) == "_"
    }

    /// Whether `text` (restored) still holds what looks like a placeholder: the model changed one past telling. What
    /// `original` (the user's text) holds as written doesn't count.
    public static func isAltered(_ text: String, original: String = "") -> Bool {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        func own(_ match: NSTextCheckingResult) -> Bool { !original.isEmpty && original.contains(ns.substring(with: match.range)) }
        if bare.matches(in: text, range: all).contains(where: { !own($0) }) { return true }
        // Closed or with its closing bracket missing ("[EMAIL_1 today"), left as it is.
        return (bracketed.matches(in: text, range: all) + unclosed.matches(in: text, range: all)).contains { match in
            guard !own(match) else { return false }
            let square = "[【［".contains(ns.substring(with: NSRange(location: match.range.location, length: 1)))
            let underscore = ns.substring(with: match.range(at: 2)) == "_"
            // Ours in any brackets with "_" or in square ones; another word only in square brackets with "_".
            return kind(named: ns.substring(with: match.range(at: 1))) != nil ? square || underscore : square && underscore
        }
    }

    /// `text` (a line still streaming in) without what may be the start of a placeholder at its end: an open
    /// bracket and what follows it ("[EMAIL_1", "(EMAIL_", "[" alone), or a kind's first letters ("EMAI", "EMAIL_1"
    /// with "EMAIL_10" maybe to come).
    static func holdingBack(_ text: String) -> String {
        var out = text
        for regex in [partialBracket, partialBare] {
            if let tail = regex.firstMatch(in: out, range: NSRange(location: 0, length: (out as NSString).length)) {
                out = (out as NSString).substring(to: tail.range.location)
            }
        }
        return out
    }

    /// A placeholder in brackets, with any spacing and case, its kind maybe translated: "[EMAIL_1]", "[ email 1 ]",
    /// "【邮箱_1】", "(PHONE_2)". Groups: the kind's word, the separator, the number.
    static let bracketed = try! NSRegularExpression(
        pattern: #"[\[【［(（]\s*(\p{L}[\p{L}\p{M}\-]{0,23}?)\s*([_\-\s]?)\s*(\d{1,3})\s*[\]】］)）]"#)
    /// A placeholder whose closing bracket the model left out, before the end, a space or punctuation ("[EMAIL_1",
    /// "(EMAIL_1 today"). Groups as `bracketed`.
    static let unclosed = try! NSRegularExpression(
        pattern: #"[\[【［(（]\s*(\p{L}[\p{L}\p{M}\-]{0,23}?)\s*([_\-\s]?)\s*(\d{1,3})(?=$|\s|[.,;:!?。，；：！？、"'”’…])"#)
    /// Without brackets, the kind as sent and "_": "EMAIL_1", "phone_2". Groups: the kind, the number.
    static let bare = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_\[【［(（])(EMAIL|PHONE|CARD|KEY|IP|ITEM|WORD)_(\d{1,3})(?![\p{N}_])"#, options: .caseInsensitive)
    /// A word and a number in the user's own text that a placeholder could be taken for ("ip_1", "Item 1", "email2").
    static let placeholderShaped = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])(\p{L}[\p{L}\p{M}\-]{0,23}?)\s*[_\-\s]?\s*(\d{1,3})(?!\p{N})"#)
    /// The start of a placeholder in brackets at the end of a line still streaming in.
    static let partialBracket = try! NSRegularExpression(
        pattern: #"[\[【［(（]\s*(?:\p{L}[\p{L}\p{M}\-]{0,23})?\s*[_\-\s]?\s*\d{0,3}\s*$"#)
    /// The start of a placeholder without brackets at the end: a kind's first letters, maybe "_" and digits.
    static let partialBare = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_])(?:E(?:M(?:A(?:I(?:L)?)?)?)?|P(?:H(?:O(?:N(?:E)?)?)?)?|C(?:A(?:R(?:D)?)?)?|K(?:E(?:Y)?)?"#
            + #"|I(?:P|T(?:E(?:M)?)?)?|W(?:O(?:R(?:D)?)?)?)(?:_\d{0,3})?$"#, options: .caseInsensitive)

    /// The kind a placeholder's word names, in English as sent or as a model may translate it.
    static func kind(named word: String) -> Kind? {
        let key = word.lowercased().replacingOccurrences(of: " ", with: "")
        if let kind = Kind(rawValue: key.uppercased()) { return kind }
        return synonyms.first { $0.value.contains(key) }?.key
    }

    private static let synonyms: [Kind: Set<String>] = [
        .email: ["e-mail", "mail", "邮箱", "邮件", "电子邮件", "电邮", "邮箱地址", "メール", "이메일", "correo", "courriel"],
        .phone: ["tel", "telephone", "电话", "手机", "号码", "电话号码", "手机号", "電話", "전화", "teléfono", "téléphone", "telefon", "telefono"],
        .card: ["卡", "卡号", "银行卡", "カード", "카드", "tarjeta", "carte", "karte"],
        .key: ["token", "密钥", "秘钥", "令牌", "キー", "키", "clave", "clé", "schlüssel"],
        .ip: ["ip地址", "ipaddress"],
        .item: ["word", "项", "项目", "条目", "內容", "内容", "項目", "词", "항목", "elemento", "élément", "element"],
    ]

    // MARK: Detectors

    /// `text` with compatibility forms folded (NFKC: full-width letters and digits, "＠", composed accents), and for
    /// each of its UTF-16 units the range of `text` it came from.
    struct Folded {
        let text: String
        private let starts: [Int], ends: [Int]

        init(_ original: String) {
            var text = "", starts: [Int] = [], ends: [Int] = [], at = 0
            for character in original {
                let length = String(character).utf16.count
                let folded = String(character).precomposedStringWithCompatibilityMapping
                for _ in folded.utf16 {
                    starts.append(at)
                    ends.append(at + length)
                }
                text += folded
                at += length
            }
            (self.text, self.starts, self.ends) = (text, starts, ends)
        }

        /// The range of the original text that `range` of the folded one came from.
        func original(_ range: NSRange) -> NSRange {
            guard range.length > 0, NSMaxRange(range) <= starts.count else { return range }
            let start = starts[range.location]
            return NSRange(location: start, length: ends[NSMaxRange(range) - 1] - start)
        }
    }

    /// The values `settings` hides in `text`, in order, none overlapping: of two that overlap, the longer (an email
    /// over the user's word inside it). Found in the folded text (`Folded`); the ranges are the original's.
    public static func find(_ text: String, settings: RedactionSettings) -> [Found] {
        let folded = Folded(text)
        let ns = folded.text as NSString
        let all = NSRange(location: 0, length: ns.length)
        var found: [Found] = []
        func add(_ kind: Kind, _ regex: NSRegularExpression?, _ valid: (String) -> Bool = { _ in true }) {
            guard let regex else { return }
            for match in regex.matches(in: folded.text, range: all) where match.range.length > 0 && valid(ns.substring(with: match.range)) {
                found.append(Found(kind: kind, range: match.range))
            }
        }
        for word in settings.customWords { add(.item, wordRegex(word)) }
        if settings.keys {
            add(.key, keyPrefixes) { $0.contains(where: \.isNumber) }
            add(.key, token, looksRandom)
        }
        if settings.emails { add(.email, email) }
        if settings.cards { add(.card, card) { isCardNumber($0) && oneBreak($0) } }
        if settings.ips {
            add(.ip, ipv4)
            add(.ip, ipv6, isIPv6)
        }
        if settings.phones {
            add(.phone, internationalPhone) { (8...15).contains(digits($0)) && oneBreak($0) }
            for regex in phones { add(.phone, regex) { (9...15).contains(digits($0)) && oneBreak($0) } }
        }
        var kept: [Found] = []
        let ordered = found.enumerated().sorted {
            $0.element.range.length != $1.element.range.length ? $0.element.range.length > $1.element.range.length : $0.offset < $1.offset
        }
        for (_, item) in ordered where !kept.contains(where: { NSIntersectionRange($0.range, item.range).length > 0 }) {
            kept.append(item)
        }
        return kept.sorted { $0.range.location < $1.range.location }.map { Found(kind: $0.kind, range: folded.original($0.range)) }
    }

    /// The user's word or phrase (folded like the text), in any case, any run of spaces or a line break between its
    /// words, as a whole word where it starts or ends with a Latin letter or digit ("Phoenix" not in "Phoenixes");
    /// Chinese and other text has no spaces to tell words by.
    static func wordRegex(_ word: String) -> NSRegularExpression? {
        let folded = word.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folded.isEmpty else { return nil }
        func latin(_ c: Character?) -> Bool { c.map { $0.isASCII && ($0.isLetter || $0.isNumber) } ?? false }
        let body = folded.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: #"\s+"#)
        let pattern = (latin(folded.first) ? "(?<![A-Za-z0-9_])" : "") + body + (latin(folded.last) ? "(?![A-Za-z0-9_])" : "")
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Not an address in a git remote ("git@github.com:org/repo") or a URL's user right after its scheme
    /// ("https://user@host"); after any other "/" it is one ("support@corp.com/sales@corp.com").
    static let email = try! NSRegularExpression(pattern:
        #"(?<![A-Za-z0-9._%+\-])(?<!://)[A-Za-z0-9](?:[A-Za-z0-9._%+\-]*[A-Za-z0-9_%+\-])?@[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?"#
        + #"(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,24}(?![A-Za-z0-9\-]|\.[A-Za-z0-9]|:[A-Za-z0-9~/])"#)

    /// Keys with a known prefix: Claude, OpenAI (DeepSeek …), Stripe, AWS access keys, GitHub, Slack, Google,
    /// GitLab, Hugging Face, and JSON web tokens.
    static let keyPrefixes = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_\-])(?:"#
        + #"sk-ant-[A-Za-z0-9_\-]{16,}|sk-(?:proj-|svcacct-|admin-)?[A-Za-z0-9_\-]{16,}|(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}"#
        + #"|(?:AKIA|ASIA|AGPA|AIDA|AROA|ANPA|ANVA|AIPA)[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}"#
        + #"|xox[abposr]-[A-Za-z0-9\-]{10,}|AIza[0-9A-Za-z_\-]{35}|glpat-[A-Za-z0-9_\-]{20,}|hf_[A-Za-z0-9]{30,}"#
        + #"|eyJ[A-Za-z0-9_\-]{8,}\.eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,})(?![A-Za-z0-9_\-])"#)

    /// A long run of key characters, base64's "/", "+" and "=" padding too (`looksRandom` tells a key from a word or
    /// a path).
    static let token = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_\-+/=])[A-Za-z0-9_\-+/]{24,}={0,2}(?![A-Za-z0-9_\-+/=])"#)

    /// A long string that looks random: the kind of character (a digit, a capital, a small letter) often changes
    /// through it, not words joined ("my-feature-branch-2024", "QuarterlyReview2024Q3", "/Users/me/workspace").
    /// An AWS secret key ("wJalrXUtnFEMI/K7MDENG/bPxRfiCYzEXAMPLEKEY") is, with few digits.
    static func looksRandom(_ token: String) -> Bool {
        let s = token.trimmingCharacters(in: CharacterSet(charactersIn: "="))
        guard s.count >= 24 else { return false }
        let parts = s.split(whereSeparator: { "-_/+".contains($0) })
        if parts.count >= 2, parts.allSatisfy({ $0.allSatisfy(\.isLetter) || $0.allSatisfy(\.isNumber) }) { return false }
        // Short pieces joined by "/" are a path ("C++/CLI/WinRT/Win32/x64/Release"); a base64 key's "/" leaves long ones.
        if s.contains("/"), (s.split(separator: "/").map(\.count).max() ?? 0) < 12 { return false }
        // Pinyin with tone numbers ("wo3xiang3ming2tian1"), and words joined with digits ("convertUTF8ToUTF16AndBack42"):
        // most of the letters are in word-like runs.
        if s.wholeMatch(of: Self.tonedPinyin) != nil || wordShare(s) >= 0.5 { return false }
        let digits = s.filter(\.isNumber).count, upper = s.filter(\.isUppercase).count, lower = s.filter(\.isLowercase).count
        guard entropy(s) >= 3.3 else { return false }
        func kind(_ c: Character) -> Int { c.isNumber ? 0 : c.isUppercase ? 1 : c.isLowercase ? 2 : 3 }
        let kinds = s.map(kind).filter { $0 != 3 }
        let switches = zip(kinds, kinds.dropFirst()).filter { $0 != $1 }.count
        guard Double(switches) / Double(max(kinds.count - 1, 1)) >= 0.3 else { return false }
        if upper > 0, lower > 0 {
            // Both cases: small letters come in short runs (words joined have long ones), and a digit or the
            // length of a key.
            let runs = s.split(whereSeparator: { !$0.isLowercase })
            let average = Double(runs.map(\.count).reduce(0, +)) / Double(max(runs.count, 1))
            return average <= 3.5 && (digits >= 1 || s.count >= 30)
        }
        return digits >= 3 && upper + lower >= 4
    }

    nonisolated(unsafe) static let tonedPinyin = /(?:[a-zü]{0,3}[aeiouü][a-zü]{0,3}[1-5])+[a-zü]*/

    /// The share of `s`'s letters in word-like runs: a small letter run of two or more with a vowel, maybe after a
    /// capital, three letters at least ("convert", "And", "Response"). Random strings have few.
    static func wordShare(_ s: String) -> Double {
        let letters = s.filter(\.isLetter).count
        guard letters > 0 else { return 0 }
        let words = s.matches(of: /[A-Z]?[a-z]{2,}/).map { String(s[$0.range]) }
            .filter { $0.count >= 3 && $0.lowercased().contains(where: { "aeiou".contains($0) }) }
        return Double(words.map(\.count).reduce(0, +)) / Double(letters)
    }

    /// Shannon entropy in bits per character.
    static func entropy(_ s: String) -> Double {
        var counts: [Character: Int] = [:]
        for c in s { counts[c, default: 0] += 1 }
        let n = Double(s.count)
        return counts.values.reduce(0) { $0 - Double($1) / n * log2(Double($1) / n) }
    }

    /// Between the groups of a card or phone number: a space or dash, or a line break with spaces around it (at most
    /// one in a number: `oneBreak`).
    private static let gap = #"(?:[ \-]|[ \t]*\r?\n[ \t]*)"#
    private static func oneBreak(_ text: String) -> Bool { text.filter(\.isNewline).count <= 1 }

    /// 13 to 19 digits, maybe in groups split by spaces, dashes or a line break.
    static let card = try! NSRegularExpression(pattern: #"(?<![0-9\-.])[0-9](?:"# + gap + #"?[0-9]){12,18}(?![0-9\-]|\.[0-9])"#)

    /// A card number: a known issuer's prefix and length (Visa, Mastercard, Amex, Diners, JCB, Discover,
    /// UnionPay), and the Luhn check.
    static func isCardNumber(_ text: String) -> Bool {
        let d = text.filter(\.isNumber).compactMap(\.wholeNumberValue)
        guard (13...19).contains(d.count) else { return false }
        let prefix = d.prefix(4).reduce(0) { $0 * 10 + $1 }
        let two = prefix / 100
        let issuer = d[0] == 4 || (51...55).contains(two) || (2221...2720).contains(prefix) || two == 34 || two == 37
            || two == 36 || two == 38 || two == 30 || two == 35 || prefix == 6011 || (644...649).contains(prefix / 10)
            || two == 65 || two == 62
        guard issuer else { return false }
        let sum = d.reversed().enumerated().reduce(0) { total, item in
            let doubled = item.offset % 2 == 1 ? item.element * 2 : item.element
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum % 10 == 0
    }

    static let ipv4 = try! NSRegularExpression(pattern:
        #"(?<![A-Za-z0-9_.])(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"#
        + #"(?![A-Za-z0-9_]|\.[0-9])"#)
    static let ipv6 = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_:.])(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?![A-Za-z0-9_:])"#)

    /// An IPv6 address with at least two groups written ("fe80::1", not "::1" or a time "12:30:45").
    static func isIPv6(_ text: String) -> Bool {
        var address = in6_addr()
        guard inet_pton(AF_INET6, text, &address) == 1 else { return false }
        return text.split(separator: ":").count >= 2
    }

    /// After "+" and a country code, groups of one to four digits: "+1 (555) 123-4567", "+44 20 7946 0958",
    /// "+81 3-1234-5678", "+33 1 23 45 67 89", "+8613800138000".
    static let internationalPhone = try! NSRegularExpression(pattern:
        #"(?<![A-Za-z0-9_+])\+[0-9]{1,3}(?:"# + gap + #"?\(?[0-9]{1,4}\)?){2,7}(?![0-9])"#)
    /// Numbers without a country code, in the shapes phone numbers are written in (not dates, versions or a
    /// number alone): "(555) 123-4567", "555-123-4567", "138 0013 8000", "13800138000", "010-12345678", "020 7946 0958".
    static let phones: [NSRegularExpression] = [
        #"(?:\([0-9]{3}\) ?|[0-9]{3}(?:[.]|"# + gap + #"))[0-9]{3}(?:[.]|"# + gap + #")[0-9]{4}"#,
        #"1[3-9][0-9](?:"# + gap + #"?[0-9]{4}){2}"#,
        #"0[0-9]{1,4}"# + gap + #"[0-9]{3,4}"# + gap + #"?[0-9]{3,4}"#,
    ].map { try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.#/+\-])"# + $0 + #"(?![0-9]|[.\-][0-9])"#) }

    private static func digits(_ text: String) -> Int { text.filter(\.isNumber).count }
}

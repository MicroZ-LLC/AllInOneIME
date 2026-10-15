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

/// One request's hidden values. Before a request is sent, the values the detectors find in the user's text (emails,
/// phone and card numbers, keys, IP addresses, the user's own words) are replaced with placeholders such as
/// `[EMAIL_1]` (`hide`), and nothing else of the request may hold them (`protect`); the model's lines get the real
/// values back (`restore`), whatever it did to a placeholder's spacing, case or language. A value keeps its
/// placeholder for the whole request. A placeholder that can't be told any more stays as written (`isAltered`).
public struct Redaction: Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case email = "EMAIL", phone = "PHONE", card = "CARD", key = "KEY", ip = "IP", item = "ITEM"
    }

    public struct Hidden: Equatable, Sendable {
        public let kind: Kind
        public let number: Int
        public let value: String
        public var placeholder: String { "[\(kind.rawValue)_\(number)]" }
    }

    /// A value found in a text: its kind and where it is (UTF-16).
    public struct Found: Equatable, Sendable {
        public let kind: Kind
        public let range: NSRange
    }

    public let settings: RedactionSettings
    /// The values hidden so far, in the order found.
    public private(set) var hidden: [Hidden] = []
    public var count: Int { hidden.count }

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
    public mutating func hide(_ text: String) -> String {
        let found = Self.find(text, settings: settings)
        guard !found.isEmpty else { return text }
        let out = NSMutableString(string: text)
        let ns = text as NSString
        for item in found.reversed() {
            out.replaceCharacters(in: item.range, with: placeholder(for: ns.substring(with: item.range), kind: item.kind))
        }
        return out as String
    }

    private mutating func placeholder(for value: String, kind: Kind) -> String {
        if let known = hidden.first(where: { $0.value == value }) { return known.placeholder }
        let entry = Hidden(kind: kind, number: hidden.filter { $0.kind == kind }.count + 1, value: value)
        hidden.append(entry)
        return entry.placeholder
    }

    /// `request` as it may be sent: its last message (the user's text) is `sent` (`hide`), and no other part of it
    /// (the instructions, a custom command's prompt, the examples) holds a hidden value. With anything hidden, the
    /// system prompt ends with `note`; with nothing, the request is the same.
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

    /// `text` with the values hidden so far replaced by their placeholders wherever they are (longest first, the
    /// user's words in any case).
    public func scrub(_ text: String) -> String {
        var out = text
        for entry in hidden.sorted(by: { ($0.value as NSString).length > ($1.value as NSString).length }) {
            let regex = Self.wordRegex(entry.value, caseInsensitive: entry.kind == .item)
            out = regex?.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length),
                                                  withTemplate: NSRegularExpression.escapedTemplate(for: entry.placeholder)) ?? out
        }
        return out
    }

    /// Whether a jargon list's entry may be sent: nothing in it is a value to hide.
    public func allows(_ entry: JargonEntry) -> Bool {
        let text = entry.term + "\n" + entry.meaning
        return Self.find(text, settings: settings).isEmpty && scrub(text) == text
    }

    // MARK: Restoring

    /// `text` from the model with the real values back. A placeholder may come back with other spacing, case,
    /// brackets or its kind translated ("[电子邮件_1]"); one no longer told (another number, a kind and a number
    /// that match nothing) stays as written. While a line streams in (`complete` false), a placeholder only partly
    /// arrived at its end isn't shown yet.
    public func restore(_ text: String, complete: Bool = true) -> String {
        guard !hidden.isEmpty else { return text }
        var out = text
        for regex in [Self.bracketed, Self.bare] {
            let ns = out as NSString
            let replaced = NSMutableString(string: out)
            for match in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed() {
                if let value = resolve(match, in: ns) { replaced.replaceCharacters(in: match.range, with: value) }
            }
            out = replaced as String
        }
        if !complete, let tail = Self.partial.firstMatch(in: out, range: NSRange(location: 0, length: (out as NSString).length)) {
            out = (out as NSString).substring(to: tail.range.location)
        }
        return out
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
        guard let number = Int(text.substring(with: match.range(at: match.numberOfRanges - 1))) else { return nil }
        let bracketed = match.numberOfRanges == 4
        if let kind = Self.kind(named: text.substring(with: match.range(at: 1))) {
            guard !bracketed || Self.looksPlaceholder(match, in: text, knownKind: true) else { return nil }
            return hidden.first { $0.kind == kind && $0.number == number }?.value
        }
        // A kind in a language not known here: told by its number when only one placeholder has it.
        guard bracketed, Self.looksPlaceholder(match, in: text, knownKind: false) else { return nil }
        let candidates = hidden.filter { $0.number == number }
        return candidates.count == 1 ? candidates[0].value : nil
    }

    /// Whether a bracketed match is a placeholder rather than words in brackets ("(item 1)", "[Note 1]"): a known
    /// kind in square brackets or with "_"; another word only in square brackets and with "_".
    private static func looksPlaceholder(_ match: NSTextCheckingResult, in text: NSString, knownKind: Bool) -> Bool {
        let square = "[【［".contains(text.substring(with: NSRange(location: match.range.location, length: 1)))
        let underscore = text.substring(with: match.range(at: 2)) == "_"
        return knownKind ? square || underscore : square && underscore
    }

    /// Whether `text` (restored) still holds what looks like a placeholder: the model changed one past telling.
    public static func isAltered(_ text: String) -> Bool {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        if bare.firstMatch(in: text, range: all) != nil { return true }
        return bracketed.matches(in: text, range: all).contains { match in
            looksPlaceholder(match, in: ns, knownKind: kind(named: ns.substring(with: match.range(at: 1))) != nil)
        }
    }

    /// A placeholder in brackets, with any spacing and case, its kind maybe translated: "[EMAIL_1]", "[ email 1 ]",
    /// "【邮箱_1】", "(PHONE_2)". Groups: the kind's word, the separator, the number.
    static let bracketed = try! NSRegularExpression(
        pattern: #"[\[【［(（]\s*(\p{L}[\p{L}\p{M}\-]{0,23}?)\s*([_\-\s]?)\s*(\d{1,3})\s*[\]】］)）]"#)
    /// Without brackets, the kind as sent and "_": "EMAIL_1", "phone_2". Groups: the kind, the number.
    static let bare = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_])(EMAIL|PHONE|CARD|KEY|IP|ITEM)_(\d{1,3})(?!\p{N})"#, options: .caseInsensitive)
    /// The start of a placeholder at the end of a line still streaming in.
    static let partial = try! NSRegularExpression(pattern: #"[\[【［][\p{L}\p{M}\p{N}_\- ]{0,28}$"#)

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
        .item: ["项", "项目", "条目", "內容", "内容", "項目", "항목", "elemento", "élément", "element"],
    ]

    // MARK: Detectors

    /// The values `settings` hides in `text`, in order, none overlapping: of two that overlap, the longer (an email
    /// over the user's word inside it).
    public static func find(_ text: String, settings: RedactionSettings) -> [Found] {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        var found: [Found] = []
        func add(_ kind: Kind, _ regex: NSRegularExpression?, _ valid: (String) -> Bool = { _ in true }) {
            guard let regex else { return }
            for match in regex.matches(in: text, range: all) where valid(ns.substring(with: match.range)) {
                found.append(Found(kind: kind, range: match.range))
            }
        }
        for word in settings.customWords {
            let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty { add(.item, wordRegex(word, caseInsensitive: true)) }
        }
        if settings.keys {
            add(.key, keyPrefixes) { $0.contains(where: \.isNumber) }
            add(.key, token, looksRandom)
        }
        if settings.emails { add(.email, email) }
        if settings.cards { add(.card, card, isCardNumber) }
        if settings.ips {
            add(.ip, ipv4)
            add(.ip, ipv6, isIPv6)
        }
        if settings.phones {
            add(.phone, internationalPhone) { (8...15).contains(digits($0)) }
            for regex in phones { add(.phone, regex) { (9...15).contains(digits($0)) } }
        }
        var kept: [Found] = []
        let ordered = found.enumerated().sorted {
            $0.element.range.length != $1.element.range.length ? $0.element.range.length > $1.element.range.length : $0.offset < $1.offset
        }
        for (_, item) in ordered where !kept.contains(where: { NSIntersectionRange($0.range, item.range).length > 0 }) {
            kept.append(item)
        }
        return kept.sorted { $0.range.location < $1.range.location }
    }

    /// `word` as a whole word where it starts or ends with a Latin letter or digit ("Phoenix" not in "Phoenixes");
    /// Chinese and other text has no spaces to tell words by.
    static func wordRegex(_ word: String, caseInsensitive: Bool) -> NSRegularExpression? {
        func latin(_ c: Character?) -> Bool { c.map { $0.isASCII && ($0.isLetter || $0.isNumber) } ?? false }
        let pattern = (latin(word.first) ? "(?<![A-Za-z0-9_])" : "") + NSRegularExpression.escapedPattern(for: word)
            + (latin(word.last) ? "(?![A-Za-z0-9_])" : "")
        return try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    static let email = try! NSRegularExpression(pattern:
        #"(?<![A-Za-z0-9._%+\-])[A-Za-z0-9](?:[A-Za-z0-9._%+\-]*[A-Za-z0-9_%+\-])?@[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?"#
        + #"(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,24}(?![A-Za-z0-9\-]|\.[A-Za-z0-9])"#)

    /// Keys with a known prefix: Claude, OpenAI (DeepSeek …), Stripe, AWS access keys, GitHub, Slack, Google,
    /// GitLab, Hugging Face, and JSON web tokens.
    static let keyPrefixes = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_\-])(?:"#
        + #"sk-ant-[A-Za-z0-9_\-]{16,}|sk-(?:proj-|svcacct-|admin-)?[A-Za-z0-9_\-]{16,}|(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}"#
        + #"|(?:AKIA|ASIA|AGPA|AIDA|AROA|ANPA|ANVA|AIPA)[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}"#
        + #"|xox[abposr]-[A-Za-z0-9\-]{10,}|AIza[0-9A-Za-z_\-]{35}|glpat-[A-Za-z0-9_\-]{20,}|hf_[A-Za-z0-9]{30,}"#
        + #"|eyJ[A-Za-z0-9_\-]{8,}\.eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,})(?![A-Za-z0-9_\-])"#)

    /// A long run of key characters (`looksRandom` tells a key from a word).
    static let token = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_\-+])[A-Za-z0-9_\-+]{24,}={0,2}(?![A-Za-z0-9_\-+=])"#)

    /// A long string that looks random: digits and letters mixed through it (often switching between digits,
    /// capitals and small letters), not words joined ("my-feature-branch-2024", "QuarterlyReview2024Q3").
    static func looksRandom(_ token: String) -> Bool {
        let s = token.trimmingCharacters(in: CharacterSet(charactersIn: "="))
        guard s.count >= 24 else { return false }
        let parts = s.split(whereSeparator: { $0 == "-" || $0 == "_" })
        if parts.count >= 2, parts.allSatisfy({ $0.allSatisfy(\.isLetter) || $0.allSatisfy(\.isNumber) }) { return false }
        let digits = s.filter(\.isNumber).count, letters = s.filter(\.isLetter).count
        guard digits >= 3, letters >= 4, entropy(s) >= 3.3 else { return false }
        // How often the kind of character changes (a digit, a capital, a small letter): about every other one
        // in a random string, rarely in words.
        func kind(_ c: Character) -> Int { c.isNumber ? 0 : c.isUppercase ? 1 : c.isLowercase ? 2 : 3 }
        let kinds = s.map(kind).filter { $0 != 3 }
        let switches = zip(kinds, kinds.dropFirst()).filter { $0 != $1 }.count
        return Double(switches) / Double(max(kinds.count - 1, 1)) >= 0.3
    }

    /// Shannon entropy in bits per character.
    static func entropy(_ s: String) -> Double {
        var counts: [Character: Int] = [:]
        for c in s { counts[c, default: 0] += 1 }
        let n = Double(s.count)
        return counts.values.reduce(0) { $0 - Double($1) / n * log2(Double($1) / n) }
    }

    /// 13 to 19 digits, maybe in groups split by spaces or dashes.
    static let card = try! NSRegularExpression(pattern: #"(?<![0-9\-.])[0-9](?:[ \-]?[0-9]){12,18}(?![0-9\-]|\.[0-9])"#)

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

    /// "+1 (555) 123-4567", "+44 20 7946 0958", "+8613800138000".
    static let internationalPhone = try! NSRegularExpression(pattern:
        #"(?<![A-Za-z0-9_+])\+[0-9]{1,3}(?:[ .\-]?\(?[0-9]{2,4}\)?){2,5}(?![0-9])"#)
    /// Numbers without a country code, in the shapes phone numbers are written in (not dates, versions or a
    /// number alone): "(555) 123-4567", "555-123-4567", "138 0013 8000", "13800138000", "010-12345678", "020 7946 0958".
    static let phones: [NSRegularExpression] = [
        #"(?:\([0-9]{3}\) ?|[0-9]{3}[\-. ])[0-9]{3}[\-. ][0-9]{4}"#,
        #"1[3-9][0-9](?:[ \-]?[0-9]{4}){2}"#,
        #"0[0-9]{1,4}[ \-][0-9]{3,4}[ \-]?[0-9]{3,4}"#,
    ].map { try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.#/+\-])"# + $0 + #"(?![0-9]|[.\-][0-9])"#) }

    private static func digits(_ text: String) -> Int { text.filter(\.isNumber).count }
}

#!/usr/bin/env swift
// Keeps Resources/Localizable.xcstrings, the String Catalog of the interface text, in step with the code.
//
//   swift Scripts/strings.swift            (make strings) updates the catalog
//   swift Scripts/strings.swift --check    (make strings-check) changes nothing; fails when the catalog is behind
//
// The interface text is written in the code as `tr("中文", "English")`. The English text, as a printf format ("%@" for
// each interpolation, "%%" for "%": `UIString.format`), is the catalog's key; Simplified Chinese and English come from
// the code, other languages from the catalog (`InterfaceText`). This scans Sources for `tr` calls with two string
// literals (not the self-tests, *SelfTest.swift: their text never reaches translators, and shows in English in the other
// languages) and:
//   - adds the English formats not in the catalog yet, with the Chinese text and the file it is first used in as the
//     comment (what translators see; refreshed for every key in use);
//   - marks the keys no longer used as stale (`extractionState: stale`), and unmarks those used again;
//   - keeps every translation.
// It reports English formats with more than one Chinese text: one key can't hold two meanings, so all but one of them
// get a key of their own, a short dotted name for where or how it is used, `tr("删除", "Remove", key: "remove.delete")`,
// with the English as that key's English value (catalog key ≠ source text). And the calls it can't read: anything but
// two string literals (each may be literals joined with "+"), and a literal key.
//
// --check fails when an English text has more than one Chinese text without keys of their own (a later change can't
// merge two meanings into one key unnoticed), a key in use is missing from the catalog (or stale there, or a key of its
// own has another English there), or a shipped language (any in the catalog but English) has no translation for one;
// it lists them.

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalogURL = root.appendingPathComponent("Resources/Localizable.xcstrings")
let check = CommandLine.arguments.dropFirst().contains("--check")

// MARK: Reading Swift

/// A string literal: its text, with the interpolations as "%@" and "%" as "%%" (as `UIString` makes its format).
struct Literal {
    var format = ""
    var interpolations: [[Token]] = []
}

enum Token {
    case identifier(String)
    case punctuation(UInt8)
    case string(Literal)
}

struct Located {
    var token: Token
    var line: Int
}

/// Reads Swift source into tokens: identifiers, punctuation and string literals (whose interpolations are read too);
/// skips comments, numbers, whitespace. Enough to find `tr(…)` calls, not a Swift parser.
struct Lexer {
    let bytes: [UInt8]
    var index = 0
    var line: Int

    init(_ bytes: [UInt8], line: Int = 1) {
        self.bytes = bytes
        self.line = line
    }

    func peek(_ offset: Int = 0) -> UInt8? { index + offset < bytes.count ? bytes[index + offset] : nil }

    func isIdentifier(_ byte: UInt8) -> Bool {
        (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x30 && byte <= 0x39) || byte == 0x5F || byte >= 0x80
    }

    /// Tokens up to the end, or (`closing`) up to the ")" that closes an interpolation, after it.
    mutating func tokens(closing: Bool = false) throws -> [Located] {
        var out: [Located] = []
        var depth = 0
        while let byte = peek() {
            switch byte {
            case 0x0A: line += 1; index += 1
            case 0x20, 0x09, 0x0D: index += 1
            case 0x2F where peek(1) == 0x2F:  // "//"
                while let b = peek(), b != 0x0A { index += 1 }
            case 0x2F where peek(1) == 0x2A:  // "/*", nested
                index += 2
                var nesting = 1
                while nesting > 0, let b = peek() {
                    if b == 0x2F, peek(1) == 0x2A { nesting += 1; index += 2 } else if b == 0x2A, peek(1) == 0x2F { nesting -= 1; index += 2 } else {
                        if b == 0x0A { line += 1 }
                        index += 1
                    }
                }
            case 0x22,  // '"', or '#' starting a raw string ('#"')
                 0x23 where isStringStart():
                let start = line
                out.append(Located(token: .string(try string()), line: start))
            case _ where isIdentifier(byte):
                var name: [UInt8] = []
                while let b = peek(), isIdentifier(b) { name.append(b); index += 1 }
                out.append(Located(token: .identifier(String(decoding: name, as: UTF8.self)), line: line))
            default:
                index += 1
                if byte == 0x28 { depth += 1 }
                if byte == 0x29 {
                    if closing && depth == 0 { return out }
                    depth -= 1
                }
                out.append(Located(token: .punctuation(byte), line: line))
            }
        }
        if closing { throw LexError.unterminated(line) }
        return out
    }

    func isStringStart() -> Bool {
        var offset = 0
        while peek(offset) == 0x23 { offset += 1 }
        return peek(offset) == 0x22
    }

    /// A string literal from its opening delimiter: "…", """…""", #"…"#.
    mutating func string() throws -> Literal {
        var hashes = 0
        while peek() == 0x23 { hashes += 1; index += 1 }
        if peek() == 0x22, peek(1) == 0x22, peek(2) == 0x22 {
            index += 3
            return try multiline(hashes: hashes)
        }
        index += 1
        var body: [UInt8] = []
        while true {
            guard let b = peek(), b != 0x0A else { throw LexError.unterminated(line) }
            if b == 0x5C, closesEscape(hashes) {  // "\" (with the hashes)
                body.append(contentsOf: bytes[index..<(index + 1 + hashes)])
                index += 1 + hashes
                if let next = peek() { body.append(next); index += 1 }
                if body.last == 0x28 { try skipInterpolation(into: &body) }
                continue
            }
            if b == 0x22, closes(hashes, from: index + 1) {
                index += 1 + hashes
                break
            }
            body.append(b)
            index += 1
        }
        return try Lexer.literal(body, hashes: hashes, line: line)
    }

    /// A multi-line literal after its opening """: the lines between the delimiters, less the closing one's indentation.
    mutating func multiline(hashes: Int) throws -> Literal {
        while let b = peek(), b != 0x0A { index += 1 }
        index += 1
        line += 1
        let first = line
        var raw: [UInt8] = []
        while true {
            guard let b = peek() else { throw LexError.unterminated(line) }
            if b == 0x5C, closesEscape(hashes) {
                raw.append(contentsOf: bytes[index..<(index + 1 + hashes)])
                index += 1 + hashes
                if let next = peek() { raw.append(next); index += 1; if next == 0x0A { line += 1 } }
                if raw.last == 0x28 { try skipInterpolation(into: &raw) }
                continue
            }
            if b == 0x22, peek(1) == 0x22, peek(2) == 0x22, closes(hashes, from: index + 3) {
                index += 3 + hashes
                break
            }
            if b == 0x0A { line += 1 }
            raw.append(b)
            index += 1
        }
        // The last line holds only the closing delimiter's indentation.
        var lines = raw.split(separator: 0x0A, omittingEmptySubsequences: false).map(Array.init)
        let indentation = lines.removeLast()
        let body = lines.map { $0.starts(with: indentation) ? Array($0.dropFirst(indentation.count)) : $0 }
        return try Lexer.literal(Array(body.joined(separator: [0x0A])), hashes: hashes, line: first)
    }

    func closesEscape(_ hashes: Int) -> Bool { (0..<hashes).allSatisfy { peek(1 + $0) == 0x23 } }

    func closes(_ hashes: Int, from start: Int) -> Bool {
        (0..<hashes).allSatisfy { start + $0 < bytes.count && bytes[start + $0] == 0x23 }
    }

    /// Copies an interpolation's code, up to and with its ")", so the literal can be read afterwards.
    mutating func skipInterpolation(into body: inout [UInt8]) throws {
        var inner = Lexer(Array(bytes[index...]), line: line)
        _ = try inner.tokens(closing: true)
        body.append(contentsOf: bytes[index..<(index + inner.index)])
        index += inner.index
        line = inner.line
    }

    /// A literal's text from the bytes between its delimiters: escapes resolved, interpolations read.
    static func literal(_ body: [UInt8], hashes: Int, line: Int) throws -> Literal {
        var literal = Literal()
        var text: [UInt8] = []
        func flush() {
            literal.format += String(decoding: text, as: UTF8.self).replacingOccurrences(of: "%", with: "%%")
            text = []
        }
        var i = 0
        while i < body.count {
            let b = body[i]
            guard b == 0x5C, (0..<hashes).allSatisfy({ i + 1 + $0 < body.count && body[i + 1 + $0] == 0x23 }) else {
                text.append(b)
                i += 1
                continue
            }
            i += 1 + hashes
            guard i < body.count else { break }
            let escaped = body[i]
            i += 1
            switch escaped {
            case 0x6E: text.append(0x0A)  // \n
            case 0x74: text.append(0x09)  // \t
            case 0x72: text.append(0x0D)  // \r
            case 0x30: text.append(0x00)  // \0
            case 0x22, 0x27, 0x5C: text.append(escaped)
            case 0x75:  // \u{…}
                guard let close = body[i...].firstIndex(of: 0x7D),
                      let value = UInt32(String(decoding: body[(i + 1)..<close], as: UTF8.self), radix: 16),
                      let scalar = Unicode.Scalar(value) else { throw LexError.badEscape(line) }
                text.append(contentsOf: Array(String(Character(scalar)).utf8))
                i = close + 1
            case 0x28:  // \( … )
                flush()
                var inner = Lexer(Array(body[i...]), line: line)
                literal.interpolations.append(try inner.tokens(closing: true).map(\.token))
                literal.format += "%@"
                i += inner.index
            case 0x0A: break  // a line continued (multi-line literals)
            case 0x20, 0x09:  // spaces before a continued line
                while i < body.count, body[i] == 0x20 || body[i] == 0x09 { i += 1 }
                if i < body.count, body[i] == 0x0A { i += 1 } else { throw LexError.badEscape(line) }
            default: throw LexError.badEscape(line)
            }
        }
        flush()
        return literal
    }
}

enum LexError: Error {
    case unterminated(Int)
    case badEscape(Int)
}

// MARK: Finding the calls

struct Use {
    var chinese: String
    var english: String
    var key: String?
    var file: String
    var line: Int
    var location: String { "\(file):\(line)" }
}

struct Unreadable {
    var location: String
    var reason: String
}

var uses: [Use] = []
var unreadable: [Unreadable] = []

/// The `tr` calls in `tokens`, and in the interpolations of their literals.
func scan(_ tokens: [Located], file: String) {
    for (i, located) in tokens.enumerated() {
        if case let .string(literal) = located.token {
            for code in literal.interpolations { scan(code.map { Located(token: $0, line: located.line) }, file: file) }
        }
        guard case .identifier("tr") = located.token, i + 1 < tokens.count, case .punctuation(0x28) = tokens[i + 1].token else { continue }
        if i > 0, case .identifier("func") = tokens[i - 1].token { continue }
        let location = "\(file):\(located.line)"
        func punctuation(at j: Int, _ byte: UInt8) -> Bool {
            guard j < tokens.count, case let .punctuation(found) = tokens[j].token else { return false }
            return found == byte
        }
        /// A string literal at `j`, or several joined with "+"; and the index after it.
        func argument(at j: Int) -> (Literal, Int)? {
            guard j < tokens.count, case var .string(literal) = tokens[j].token else { return nil }
            var next = j + 1
            while punctuation(at: next, 0x2B), next + 1 < tokens.count, case let .string(more) = tokens[next + 1].token {
                literal.format += more.format
                literal.interpolations += more.interpolations
                next += 2
            }
            return (literal, next)
        }
        guard let (chinese, comma) = argument(at: i + 2), punctuation(at: comma, 0x2C),
              let (english, end) = argument(at: comma + 1) else {
            unreadable.append(Unreadable(location: location, reason: "not two string literals"))
            continue
        }
        var key: String?
        if punctuation(at: end, 0x29) {
        } else if punctuation(at: end, 0x2C), end + 1 < tokens.count, case .identifier("key") = tokens[end + 1].token,
                  punctuation(at: end + 2, 0x3A), let (keyLiteral, close) = argument(at: end + 3), keyLiteral.interpolations.isEmpty,
                  punctuation(at: close, 0x29) {
            key = keyLiteral.format.replacingOccurrences(of: "%%", with: "%")
        } else {
            unreadable.append(Unreadable(location: location, reason: "not two string literals"))
            continue
        }
        uses.append(Use(chinese: chinese.format, english: english.format, key: key, file: file, line: located.line))
    }
}

let sources = root.appendingPathComponent("Sources")
let files = (FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
    .filter { $0.pathExtension == "swift" && !$0.lastPathComponent.hasSuffix("SelfTest.swift") }
    .map { String($0.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1)) }
    .sorted()
for file in files {
    let data = FileManager.default.contents(atPath: root.appendingPathComponent(file).path) ?? Data()
    var lexer = Lexer(Array(data))
    do {
        scan(try lexer.tokens(), file: file)
    } catch LexError.unterminated(let line), LexError.badEscape(let line) {
        unreadable.append(Unreadable(location: "\(file):\(line)", reason: "can't read this file from here on"))
    } catch {}
}

// MARK: The catalog

/// The key each use looks up: its own key, else its English format.
func key(_ use: Use) -> String { use.key ?? use.english }

var firstUse: [String: Use] = [:]
var order: [String] = []
var meanings: [String: [String: Use]] = [:]  // key → Chinese text → first use
for use in uses {
    let key = key(use)
    if firstUse[key] == nil { firstUse[key] = use; order.append(key) }
    if meanings[key, default: [:]][use.chinese] == nil { meanings[key, default: [:]][use.chinese] = use }
    // A key of its own with two English texts is as wrong as one English text with two meanings.
    if use.key != nil, let first = firstUse[key], first.english != use.english {
        meanings[key, default: [:]]["(English: \(use.english))"] = use
    }
}
let conflicts = order.filter { (meanings[$0]?.count ?? 0) > 1 }

var catalog: [String: Any] = ["sourceLanguage": "en", "version": "1.0", "strings": [String: Any]()]
if let data = FileManager.default.contents(atPath: catalogURL.path) {
    guard let read = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("error: \(catalogURL.path) isn't a String Catalog (JSON)")
        exit(1)
    }
    catalog = read
}
var strings = catalog["strings"] as? [String: Any] ?? [:]

/// The languages the catalog ships besides English.
let shipped = Set(strings.values.flatMap { (($0 as? [String: Any])?["localizations"] as? [String: Any])?.keys ?? [String: Any]().keys })
    .subtracting(["en"]).sorted()

/// What translators see: the Chinese text and the file it is first used in; no line number, which would change the
/// catalog with every edit above it.
func comment(_ use: Use) -> String { "\(use.chinese) — \(use.file)" }

func isStale(_ entry: [String: Any]) -> Bool { entry["extractionState"] as? String == "stale" }

/// A key of its own's English value in the catalog.
func englishValue(_ entry: [String: Any]) -> String? {
    (((entry["localizations"] as? [String: Any])?["en"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
}

func hasTranslation(_ entry: [String: Any], _ language: String) -> Bool {
    guard let localization = (entry["localizations"] as? [String: Any])?[language] as? [String: Any] else { return false }
    if let unit = localization["stringUnit"] as? [String: Any] { return !((unit["value"] as? String) ?? "").isEmpty }
    return localization["variations"] != nil
}

let inUse = Set(order)
var missing: [String] = []
var untranslated: [String: [String]] = [:]
for key in order {
    // Missing, stale, or (a key of its own) with another English than the code's.
    guard let entry = strings[key] as? [String: Any], !isStale(entry),
          firstUse[key]!.key == nil || englishValue(entry) == firstUse[key]!.english else { missing.append(key); continue }
    for language in shipped where !hasTranslation(entry, language) { untranslated[language, default: []].append(key) }
}
let unused = strings.keys.filter { !inUse.contains($0) && !isStale(strings[$0] as? [String: Any] ?? [:]) }.sorted()

func report() {
    print("\(order.count) keys in use (\(uses.count) calls), \(strings.count) in the catalog; shipped languages: \(["en"] + shipped)")
    if !conflicts.isEmpty {
        print("\n\(conflicts.count) English texts with more than one Chinese text (give all but one a key of their own: tr(_:_:key:)):")
        for key in conflicts {
            print("  \"\(key)\"")
            for (chinese, use) in meanings[key]!.sorted(by: { $0.value.location < $1.value.location }) {
                print("      \"\(chinese)\"  \(use.location)")
            }
        }
    }
    if !unreadable.isEmpty {
        print("\n\(unreadable.count) tr calls not read (\(Set(unreadable.map(\.reason)).sorted().joined(separator: ", "))):")
        for call in unreadable { print("  \(call.location): \(call.reason)") }
    }
}

if check {
    report()
    var failed = !conflicts.isEmpty
    if !missing.isEmpty {
        failed = true
        print("\n\(missing.count) keys missing from the catalog, or out of date there (run make strings):")
        for key in missing { print("  \"\(key)\"  \(firstUse[key]!.location)") }
    }
    for language in shipped where !(untranslated[language] ?? []).isEmpty {
        failed = true
        print("\n\(untranslated[language]!.count) keys without a \(language) translation:")
        for key in untranslated[language]! { print("  \"\(key)\"  \(firstUse[key]!.location)") }
    }
    if !unused.isEmpty { print("\n\(unused.count) keys no longer used (make strings marks them stale)") }
    print(failed ? "\nstrings-check: FAILED" : "\nstrings-check: OK")
    exit(failed ? 1 : 0)
}

var added = 0, staled = 0, revived = 0
for key in order {
    let use = firstUse[key]!
    var entry = strings[key] as? [String: Any] ?? [:]
    if strings[key] == nil { added += 1 }
    if isStale(entry) { entry["extractionState"] = nil; revived += 1 }
    entry["comment"] = comment(use)
    if use.key != nil {
        // A key of its own: its English is the code's English format.
        var localizations = entry["localizations"] as? [String: Any] ?? [:]
        localizations["en"] = ["stringUnit": ["state": "translated", "value": use.english]]
        entry["localizations"] = localizations
    }
    strings[key] = entry
}
for key in unused {
    var entry = strings[key] as? [String: Any] ?? [:]
    entry["extractionState"] = "stale"
    strings[key] = entry
    staled += 1
}
catalog["strings"] = strings
var json = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
json.append(0x0A)
if json != FileManager.default.contents(atPath: catalogURL.path) { try json.write(to: catalogURL) }
report()
print("\nmake strings: \(added) added, \(staled) marked stale, \(revived) used again; \(catalogURL.path.dropFirst(root.path.count + 1))")

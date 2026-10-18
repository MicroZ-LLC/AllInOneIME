import Foundation

/// A config file's text with some of its top-level keys rewritten in place (`AIConfig.patchingFile`): the others keep
/// their text byte for byte, formatting and numbers included (a large integer a later version wrote isn't read and
/// written back as a float).
enum JSONFileText {
    /// One `"key" : value` of the top-level object, as byte offsets into the text.
    struct Member {
        var key: String
        var keyStart: Int
        var valueStart: Int
        var valueEnd: Int
    }

    /// `text` with each of `keys` set to its value in `object` (removed where it has none), or nil when the text isn't a
    /// JSON object this can read member by member.
    static func patched(_ text: String, setting object: [String: AIConfig.JSONValue], keys: Set<String>) -> String? {
        var bytes = Array(text.utf8)
        guard let (open, close, members) = scan(bytes) else { return nil }
        // The members' positions shift as they're edited: from the last one back. A key written twice: its last.
        var last: [String: Int] = [:]
        for (index, member) in members.enumerated() { last[member.key] = index }
        var inserts: [(String, AIConfig.JSONValue)] = []
        var edits: [(range: Range<Int>, text: [UInt8])] = []
        for key in keys.sorted() {
            guard let index = last[key] else {
                if let value = object[key] { inserts.append((key, value)) }
                continue
            }
            let member = members[index]
            if let value = object[key] {
                edits.append((member.valueStart..<member.valueEnd, Array(encode(value, indent: indentation(of: member, in: bytes)).utf8)))
            } else if members.count == 1 {
                edits.append((open + 1..<close, []))
            } else if index + 1 < members.count {
                // Up to the next member: its comma and the line break before it go with it.
                edits.append((member.keyStart..<members[index + 1].keyStart, []))
            } else {
                // The last: from the end of the one before it (its comma goes).
                edits.append((members[index - 1].valueEnd..<member.valueEnd, []))
            }
        }
        if !inserts.isEmpty {
            let indent = members.last.map { indentation(of: $0, in: bytes) } ?? "  "
            let at = members.last?.valueEnd ?? open + 1
            let added = inserts.map { "\n" + indent + quoted($0.0) + " : " + encode($0.1, indent: indent) }.joined(separator: ",")
            edits.append((at..<at, Array(((members.isEmpty ? "" : ",") + added + (members.isEmpty ? "\n" : "")).utf8)))
        }
        // Edits that would overlap (two members removed at the end): not in place.
        let ordered = edits.sorted { ($0.range.lowerBound, $0.range.upperBound) < ($1.range.lowerBound, $1.range.upperBound) }
        for (a, b) in zip(ordered, ordered.dropFirst()) where a.range.upperBound > b.range.lowerBound { return nil }
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            bytes.replaceSubrange(edit.range, with: edit.text)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The top-level object's braces and members, or nil when the text isn't one.
    static func scan(_ bytes: [UInt8]) -> (open: Int, close: Int, members: [Member])? {
        var i = 0
        func skipSpace() { while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 } }
        skipSpace()
        guard i < bytes.count, bytes[i] == UInt8(ascii: "{") else { return nil }
        let open = i
        i += 1
        var members: [Member] = []
        skipSpace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "}") { return (open, i, []) }
        while i < bytes.count {
            skipSpace()
            let keyStart = i
            guard let keyEnd = skipValue(bytes, from: i), bytes[keyStart] == UInt8(ascii: "\""),
                  let key = (try? JSONSerialization.jsonObject(with: Data(bytes[keyStart..<keyEnd]), options: .fragmentsAllowed)) as? String
            else { return nil }
            i = keyEnd
            skipSpace()
            guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { return nil }
            i += 1
            skipSpace()
            let valueStart = i
            guard let valueEnd = skipValue(bytes, from: i) else { return nil }
            members.append(Member(key: key, keyStart: keyStart, valueStart: valueStart, valueEnd: valueEnd))
            i = valueEnd
            skipSpace()
            guard i < bytes.count else { return nil }
            if bytes[i] == UInt8(ascii: ",") {
                i += 1
                continue
            }
            guard bytes[i] == UInt8(ascii: "}") else { return nil }
            return (open, i, members)
        }
        return nil
    }

    /// The end of the JSON value starting at `start` (a string, an object or array, a number or a literal), or nil.
    static func skipValue(_ bytes: [UInt8], from start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        var i = start
        switch bytes[i] {
        case UInt8(ascii: "\""):
            i += 1
            while i < bytes.count {
                if bytes[i] == UInt8(ascii: "\\") { i += 2; continue }
                if bytes[i] == UInt8(ascii: "\"") { return i + 1 }
                i += 1
            }
            return nil
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            while i < bytes.count {
                switch bytes[i] {
                case UInt8(ascii: "\""):
                    guard let end = skipValue(bytes, from: i) else { return nil }
                    i = end
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 { return i + 1 }
                default: break
                }
                i += 1
            }
            return nil
        default:
            // A number or true / false / null: up to a separator.
            while i < bytes.count, ![UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), 0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) {
                i += 1
            }
            return i > start ? i : nil
        }
    }

    /// The spaces before a member's key on its line.
    static func indentation(of member: Member, in bytes: [UInt8]) -> String {
        var start = member.keyStart
        while start > 0, bytes[start - 1] == 0x20 || bytes[start - 1] == 0x09 { start -= 1 }
        return String(decoding: bytes[start..<member.keyStart], as: UTF8.self)
    }

    /// `value` as `Config.write` formats it (pretty, sorted keys), its lines after the first indented by `indent`.
    static func encode(_ value: AIConfig.JSONValue, indent: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let text = (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .map { $0.offset == 0 || $0.element.isEmpty ? String($0.element) : indent + $0.element }.joined(separator: "\n")
    }

    static func quoted(_ key: String) -> String {
        (try? JSONEncoder().encode(key)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\(key)\""
    }
}

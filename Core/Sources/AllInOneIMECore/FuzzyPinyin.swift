import Foundation

/// Fuzzy pinyin (模糊音): sounds that can be typed either way, for those who don't tell them apart
/// (zh and z, n and l…). Rime does it with spelling rules (`speller/algebra`): each pair derives the
/// spellings of one from the other, both ways. They go into `rime_ice.custom.yaml` in the Rime user
/// folder, before rime-ice's own rules (as its schema suggests), and Rime is deployed again.
public enum FuzzyPinyin {
    public struct Pair: Identifiable, Equatable, Sendable {
        /// What `Config.fuzzyPinyin` keeps: "z-zh".
        public let id: String
        /// "z ↔ zh".
        public var label: String { id.replacingOccurrences(of: "-", with: " ↔ ") }
        let rules: [String]
    }

    /// Initials first, then finals: the common pairs, in the order rime-ice's schema lists them.
    public static let pairs: [Pair] = [
        Pair(id: "z-zh", rules: ["derive/^zh/z/", "derive/^z([^h])/zh$1/"]),
        Pair(id: "c-ch", rules: ["derive/^ch/c/", "derive/^c([^h])/ch$1/"]),
        Pair(id: "s-sh", rules: ["derive/^sh/s/", "derive/^s([^h])/sh$1/"]),
        Pair(id: "n-l", rules: ["derive/^n/l/", "derive/^l/n/"]),
        Pair(id: "f-h", rules: ["derive/^f/h/", "derive/^h/f/"]),
        Pair(id: "r-l", rules: ["derive/^r/l/", "derive/^l/r/"]),
        Pair(id: "an-ang", rules: ["derive/ang$/an/", "derive/an$/ang/"]),
        Pair(id: "en-eng", rules: ["derive/eng$/en/", "derive/en$/eng/"]),
        Pair(id: "in-ing", rules: ["derive/ing$/in/", "derive/in$/ing/"]),
        Pair(id: "ian-iang", rules: ["derive/iang$/ian/", "derive/ian$/iang/"]),
        Pair(id: "uan-uang", rules: ["derive/uang$/uan/", "derive/uan$/uang/"]),
    ]

    /// The ids of known pairs among `ids`, in the catalog's order, once each (unknown ones dropped).
    public static func known(_ ids: [String]) -> [String] {
        pairs.map(\.id).filter(ids.contains)
    }

    public static let fileName = "rime_ice.custom.yaml"
    /// The first line of the file when AllInOneIME wrote it: one without it is the user's, never touched.
    static let marker = "# Written by AllInOneIME: fuzzy pinyin (Settings → Input). Edits here are replaced."

    /// The schema's own spelling rules, as written in `rime_ice.schema.yaml` (comments dropped).
    static func algebra(ofSchema text: String) -> [String] {
        var rules: [String] = [], inSpeller = false, inAlgebra = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let indent = line.prefix(while: { $0 == " " }).count
            let content = line.trimmingCharacters(in: .whitespaces)
            if content.isEmpty || content.hasPrefix("#") { continue }
            if indent == 0 { inSpeller = content.hasPrefix("speller:"); inAlgebra = false; continue }
            guard inSpeller else { continue }
            if indent == 2 { inAlgebra = content.hasPrefix("algebra:"); continue }
            guard inAlgebra, content.hasPrefix("- ") else { continue }
            var rule = String(content.dropFirst(2))
            if let comment = rule.range(of: " #") { rule = String(rule[..<comment.lowerBound]) }
            rules.append(rule.trimmingCharacters(in: .whitespaces))
        }
        return rules
    }

    /// The patch for `ids` on top of the schema's rules; nil with none (or no rules found in the schema).
    public static func patch(_ ids: [String], schema: String) -> String? {
        let fuzzy = pairs.filter { ids.contains($0.id) }.flatMap(\.rules)
        let own = algebra(ofSchema: schema)
        guard !fuzzy.isEmpty, !own.isEmpty else { return nil }
        let quote = { (rule: String) in "\"" + rule.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return ([marker, "patch:", "  speller/algebra:"] + (fuzzy + own).map { "    - " + quote($0) }).joined(separator: "\n") + "\n"
    }

    public enum Outcome: Equatable, Sendable {
        /// The file already said this (nothing to deploy).
        case unchanged
        case written
        case removed
        /// The folder has the user's own `rime_ice.custom.yaml`: left alone, fuzzy pinyin not applied.
        case userFile
    }

    /// Writes (or removes) the patch in `userDir` for `ids`; the caller deploys Rime again unless `.unchanged`.
    public static func apply(_ ids: [String], schema schemaURL: URL, userDir: URL) throws -> Outcome {
        let file = userDir.appendingPathComponent(fileName)
        let existing = try? String(contentsOf: file, encoding: .utf8)
        if let existing, !existing.hasPrefix(marker) { return ids.isEmpty ? .unchanged : .userFile }
        let schema = (try? String(contentsOf: schemaURL, encoding: .utf8)) ?? ""
        guard let wanted = patch(ids, schema: schema) else {
            guard existing != nil else { return .unchanged }
            try FileManager.default.removeItem(at: file)
            return .removed
        }
        guard wanted != existing else { return .unchanged }
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try wanted.write(to: file, atomically: true, encoding: .utf8)
        return .written
    }
}

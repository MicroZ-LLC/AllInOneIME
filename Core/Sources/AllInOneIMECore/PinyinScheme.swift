import Foundation

/// How Chinese is typed in pinyin (`Config.pinyinScheme`, Settings → Input → Chinese → Typing): full pinyin, each
/// syllable spelled whole (nihao), or Shuangpin (双拼), each syllable two keys, its initial's and its final's (Xiaohe:
/// nihc), in one of the schemes rime-ice ships (its double_pinyin*.schema.yaml, in the Chinese pack: nothing to download).
/// Each is a librime schema of its own on rime-ice's dictionary (full pinyin's is rime-ice's own, `rime_ice`), so what
/// goes with pinyin goes with all of them: the words learned (rime_ice's user dictionary, which they share), the
/// personal dictionaries, the candidates removed, Traditional characters and fuzzy pinyin (the same patch, made for each
/// schema: `PersonalDictionaryStore`), the English words among the candidates (`EnglishWordsEngine`, which reads the
/// letters as the scheme does: `Pinyin.Reading`). The shell deploys the scheme picked beside full pinyin's
/// (`schemaListPatch`), and the session gives level one its schema before the next key (`PinyinEngine.selectSchema`).
///
/// Or Zhuyin (注音, Bopomofo: `zhuyin`), Taiwan's way, on the keys of the Standard (Daqian) layout macOS's own Zhuyin has
/// (1 ㄅ, q ㄆ, a ㄇ…; Space the first tone, 6 ˊ, 3 ˇ, 4 ˋ, 7 ˙): rime-bopomofo's schema, on rime-terra-pinyin's dictionary
/// (in Traditional characters), which the app carries (`zhuyinData`). Its keys are digits and punctuation too, so while a
/// syllable is composed those are librime's (Zhuyin keys, or its picks where its schema has them), and Latin letters are
/// never English words (`EnglishWordsEngine`). Of what goes with pinyin, the characters (its own switch,
/// `ChineseCharacters.patch`) and the candidates removed go with it; fuzzy pinyin and the personal dictionaries (pinyin
/// spellings of rime-ice's dictionary) don't, nor does its own dictionary learn into rime_ice's.
public enum PinyinScheme: String, CaseIterable, Sendable {
    case full
    /// 小鹤双拼.
    case xiaohe = "double_pinyin_flypy"
    /// 自然码双拼.
    case ziranma = "double_pinyin"
    /// 微软双拼.
    case microsoft = "double_pinyin_mspy"
    /// 搜狗双拼.
    case sogou = "double_pinyin_sogou"
    /// 智能 ABC 双拼.
    case zhinengABC = "double_pinyin_abc"
    /// 拼音加加双拼.
    case pinyinJiajia = "double_pinyin_jiajia"
    /// 紫光双拼.
    case ziguang = "double_pinyin_ziguang"
    /// 注音（標準/大千）: rime-bopomofo's schema.
    case zhuyin = "bopomofo"

    /// The scheme `Config.pinyinScheme` names: full pinyin for none, "full", and one this version doesn't know (a later
    /// one's).
    public init(setting: String?) {
        self = setting.flatMap(PinyinScheme.init(rawValue:)) ?? .full
    }

    /// What `Config.pinyinScheme` keeps for it: nil for full pinyin (a file from before the setting doesn't gain the key).
    public var setting: String? { self == .full ? nil : rawValue }

    /// The Shuangpin schemes, in the order Settings lists them.
    public static var shuangpin: [PinyinScheme] { allCases.filter(\.isShuangpin) }

    public var isShuangpin: Bool { self != .full && self != .zhuyin }

    /// Every way of typing but full pinyin: a schema deployed beside rime-ice's when picked, with a patch of its own.
    public static var others: [PinyinScheme] { allCases.filter { $0 != .full } }

    /// The files of Zhuyin's schema and what it needs, which the app carries (`Contents/SharedSupport/rime-zhuyin`, the
    /// Makefile's ZHUYIN_FILES) and links into the Chinese pack (`LanguagePackStore.linkData`): rime-bopomofo's schema
    /// and spelling rules, rime-terra-pinyin's dictionary, rime-stroke's (its reverse lookup by strokes) and the word list
    /// that weighs their words (rime-essay's).
    public static let zhuyinData = ["bopomofo.schema.yaml", "zhuyin.yaml", "terra_pinyin.dict.yaml", "stroke.schema.yaml",
                                    "stroke.dict.yaml", "essay.txt"]

    /// The keys a Zhuyin syllable starts with (rime-bopomofo's `speller/initials`): ㄅ to ㄦ, the digits and
    /// punctuation among them too; not a tone's (Space, 6, 3, 4, 7).
    static let zhuyinInitials = Set("1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/-")

    /// The librime schema it types with: rime-ice's own (`fullSchema`) for full pinyin, else the scheme's.
    public var schema: String { self == .full ? Self.fullSchema : rawValue }

    /// rime-ice's full-pinyin schema, deployed always.
    public static let fullSchema = "rime_ice"

    /// Its name as Settings lists it (Settings → Input → Chinese → Typing): 全拼, 双拼 – 小鹤, Shuangpin – Xiaohe. Zhuyin's
    /// Chinese is in Traditional characters, as Taiwan names it.
    public func name(in language: String) -> String {
        let t = InterfaceWords(language: language)
        switch self {
        case .full: return t.tr("全拼", "Full pinyin")
        case .xiaohe: return t.tr("双拼 – 小鹤", "Shuangpin – Xiaohe")
        case .ziranma: return t.tr("双拼 – 自然码", "Shuangpin – Ziranma")
        case .microsoft: return t.tr("双拼 – 微软", "Shuangpin – Microsoft")
        case .sogou: return t.tr("双拼 – 搜狗", "Shuangpin – Sogou")
        case .zhinengABC: return t.tr("双拼 – 智能ABC", "Shuangpin – Zhineng ABC")
        case .pinyinJiajia: return t.tr("双拼 – 拼音加加", "Shuangpin – Pinyin Jiajia")
        case .ziguang: return t.tr("双拼 – 紫光", "Shuangpin – Ziguang")
        case .zhuyin: return t.tr("注音 – 標準/大千", "Zhuyin (Bopomofo) – Standard")
        }
    }

    // MARK: The schemas deployed

    /// The schemas librime deploys for it, full pinyin's first (a new session starts in it): with Shuangpin or Zhuyin, the
    /// scheme's too; only those, so that only what is used is compiled.
    public var schemaList: [String] { self == .full ? [Self.fullSchema] : [Self.fullSchema, rawValue] }

    /// The first line of `default.custom.yaml` (the schema list, in the Rime user folder) when this app wrote it: one
    /// without it is the user's (`ownsSchemaList`). Its words are those of the first version that wrote it, which said
    /// Shuangpin's only (Zhuyin's list has it too).
    static let schemaListMarker = "# Written by AllInOneIME: the schemas used, full pinyin's and the Shuangpin scheme picked (Settings → Input → Chinese → Typing). Edits here are replaced."

    /// `default.custom.yaml` for `schemas`.
    static func schemaListPatch(_ schemas: [String]) -> String {
        ([schemaListMarker, "patch:", "  schema_list:"] + schemas.map { "    - schema: \($0)" }).joined(separator: "\n") + "\n"
    }

    /// The schemas a `default.custom.yaml` lists ("    - schema: rime_ice"), in order; nil when it has anything else
    /// (another key, a comment at the end of a line): not one this app could have written.
    static func listedSchemas(_ text: String) -> [String]? {
        var schemas: [String] = [], expected = ["patch:", "schema_list:"]
        for line in text.split(whereSeparator: \.isNewline) {
            let content = line.trimmingCharacters(in: .whitespaces)
            if content.isEmpty || content.hasPrefix("#") { continue }
            if !expected.isEmpty {
                guard content == expected.removeFirst() else { return nil }
                continue
            }
            guard content.hasPrefix("- schema:"), !content.contains("#") else { return nil }
            schemas.append(content.dropFirst("- schema:".count).trimmingCharacters(in: .whitespaces))
        }
        return expected.isEmpty ? schemas : nil
    }

    /// Whether `text`, the user folder's `default.custom.yaml`, is this app's to replace: written by it (`schemaListMarker`),
    /// or the full-pinyin list alone, as the Chinese pack's copy and every earlier version had it (whatever its comments
    /// say). Any other is the user's, left as it is.
    static func ownsSchemaList(_ text: String) -> Bool {
        text.hasPrefix(schemaListMarker + "\n") || listedSchemas(text) == [fullSchema]
    }

    public enum ListOutcome: Equatable, Sendable {
        /// It already listed them (nothing to deploy).
        case unchanged
        case written
        /// The folder has the user's own `default.custom.yaml`: left alone. The scheme types only where it lists it.
        case userFile
    }

    /// The user folder's `default.custom.yaml` (`userDir`) listing the schemas `scheme` needs (`schemaList`), unless the
    /// user's own is there (`ownsSchemaList`). Full pinyin's list is left as it is where it has no other schema (the
    /// Chinese pack's copy, which librime's start copies there when it is missing). The caller deploys librime again on
    /// `.written`.
    public static func applySchemaList(_ scheme: PinyinScheme, userDir: URL) throws -> ListOutcome {
        let url = userDir.appendingPathComponent("default.custom.yaml")
        let wanted = scheme.schemaList
        var current: String?
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            // A link, or anything but a file, is the user's.
            guard attributes[.type] as? FileAttributeType == .typeRegular else { return .userFile }
            current = try String(contentsOf: url, encoding: .utf8)
        }
        if let current {
            guard ownsSchemaList(current) else { return .userFile }
            if listedSchemas(current) == wanted { return .unchanged }
        } else if scheme == .full {
            return .unchanged
        }
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try Data(schemaListPatch(wanted).utf8).write(to: url, options: .atomic)
        return .written
    }

    // MARK: Spelling

    /// rime-ice's spelling rules for the scheme (`speller/algebra` in its schema, in order; `ShuangpinSchemaTests` checks
    /// them against the schemas): full pinyin's syllables made into the scheme's two keys. None for full pinyin
    /// (`Pinyin.algebra` is rime-ice's), nor for Zhuyin, whose keys are never read as letters.
    var algebra: [String] {
        switch self {
        case .full, .zhuyin: return []
        case .xiaohe: return Self.erase + Self.vowelsDoubled + [
            "xform/iu$/Ⓠ/", "xform/(.)ei$/$1Ⓦ/", "xform/uan$/Ⓡ/", "xform/[uv]e$/Ⓣ/", "xform/un$/Ⓨ/", "xform/^sh/Ⓤ/",
            "xform/^ch/Ⓘ/", "xform/^zh/Ⓥ/", "xform/uo$/Ⓞ/", "xform/ie$/Ⓟ/", "xform/(.)i?ong$/$1Ⓢ/", "xform/ing$|uai$/Ⓚ/",
            "xform/(.)ai$/$1Ⓓ/", "xform/(.)en$/$1Ⓕ/", "xform/(.)eng$/$1Ⓖ/", "xform/[iu]ang$/Ⓛ/", "xform/(.)ang$/$1Ⓗ/",
            "xform/ian$/Ⓜ/", "xform/(.)an$/$1Ⓙ/", "xform/(.)ou$/$1Ⓩ/", "xform/[iu]a$/Ⓧ/", "xform/iao$/Ⓝ/",
            "xform/(.)ao$/$1Ⓒ/", "xform/ui$/Ⓥ/", "xform/in$/Ⓑ/",
            "xlit/ⓆⓌⓇⓉⓎⓊⒾⓄⓅⓈⒹⒻⒼⒽⒿⓀⓁⓏⓍⒸⓋⒷⓃⓂ/qwrtyuiopsdfghjklzxcvbnm/",
        ]
        case .ziranma: return Self.erase + Self.vowelsDoubled + [
            "xform/iu$/Ⓠ/", "xform/[iu]a$/Ⓦ/", "xform/[uv]an$/Ⓡ/", "xform/[uv]e$/Ⓣ/", "xform/ing$|uai$/Ⓨ/", "xform/^sh/Ⓤ/",
            "xform/^ch/Ⓘ/", "xform/^zh/Ⓥ/", "xform/uo$/Ⓞ/", "xform/[uv]n$/Ⓟ/", "xform/(.)i?ong$/$1Ⓢ/",
            "xform/[iu]ang$/Ⓓ/", "xform/(.)en$/$1Ⓕ/", "xform/(.)eng$/$1Ⓖ/", "xform/(.)ang$/$1Ⓗ/", "xform/ian$/Ⓜ/",
            "xform/(.)an$/$1Ⓙ/", "xform/iao$/Ⓒ/", "xform/(.)ao$/$1Ⓚ/", "xform/(.)ai$/$1Ⓛ/", "xform/(.)ei$/$1Ⓩ/",
            "xform/ie$/Ⓧ/", "xform/ui$/Ⓥ/", "xform/(.)ou$/$1Ⓑ/", "xform/in$/Ⓝ/",
            "xlit/ⓆⓌⓇⓉⓎⓊⒾⓄⓅⓈⒹⒻⒼⒽⓂⒿⒸⓀⓁⓏⓍⓋⒷⓃ/qwrtyuiopsdfghmjcklzxvbn/",
        ]
        case .microsoft, .sogou:
            // The same keys, but for Microsoft's second key for ü's ue (ve: v as well as t).
            let middle = ["xform/ie$/Ⓧ/", "xform/ui$/Ⓥ/"] + (self == .microsoft ? ["derive/Ⓣ$/Ⓥ/"] : [])
            return Self.erase + Self.zeroInitialO + [
                "xform/iu$/Ⓠ/", "xform/[iu]a$/Ⓦ/", "xform/er$|[uv]an$/Ⓡ/", "xform/[uv]e$/Ⓣ/", "xform/v$|uai$/Ⓨ/",
                "xform/^sh/Ⓤ/", "xform/^ch/Ⓘ/", "xform/^zh/Ⓥ/", "xform/uo$/Ⓞ/", "xform/[uv]n$/Ⓟ/",
                "xform/(.)i?ong$/$1Ⓢ/", "xform/[iu]ang$/Ⓓ/", "xform/(.)en$/$1Ⓕ/", "xform/(.)eng$/$1Ⓖ/",
                "xform/(.)ang$/$1Ⓗ/", "xform/ian$/Ⓜ/", "xform/(.)an$/$1Ⓙ/", "xform/iao$/Ⓒ/", "xform/(.)ao$/$1Ⓚ/",
                "xform/(.)ai$/$1Ⓛ/", "xform/(.)ei$/$1Ⓩ/",
            ] + middle + [
                "xform/(.)ou$/$1Ⓑ/", "xform/in$/Ⓝ/", "xform/ing$/;/",
                "xlit/ⓆⓌⓇⓉⓎⓊⒾⓄⓅⓈⒹⒻⒼⒽⓂⒿⒸⓀⓁⓏⓍⓋⒷⓃ/qwrtyuiopsdfghmjcklzxvbn/",
            ]
        case .zhinengABC: return Self.erase + [
            "xform/^zh/Ⓐ/", "xform/^ch/Ⓔ/", "xform/^sh/Ⓥ/", "xform/^([aoe].*)$/Ⓞ$1/", "xform/ei$/Ⓠ/", "xform/ian$/Ⓦ/",
            "xform/er$|iu$/Ⓡ/", "xform/[iu]ang$/Ⓣ/", "xform/ing$/Ⓨ/", "xform/uo$/Ⓞ/", "xform/uan$/Ⓟ/",
            "xform/(.)i?ong$/$1Ⓢ/", "xform/[iu]a$/Ⓓ/", "xform/en$/Ⓕ/", "xform/eng$/Ⓖ/", "xform/ang$/Ⓗ/", "xform/an$/Ⓙ/",
            "xform/iao$/Ⓩ/", "xform/ao$/Ⓚ/", "xform/in$|uai$/Ⓒ/", "xform/ai$/Ⓛ/", "xform/ie$/Ⓧ/", "xform/ou$/Ⓑ/",
            "xform/un$/Ⓝ/", "xform/[uv]e$|ui$/Ⓜ/",
            "xlit/ⓆⓌⒺⓇⓉⓎⓄⓅⒶⓈⒹⒻⒼⒽⒿⓀⓁⓏⓍⒸⓋⒷⓃⓂ/qwertyopasdfghjklzxcvbnm/",
        ]
        case .pinyinJiajia: return Self.erase + Self.zeroInitialO + [
            "xform/iu$/Ⓝ/", "xform/[iu]a$/Ⓑ/", "xform/er$|ing$/Ⓠ/", "xform/[uv]an$/Ⓒ/", "xform/[uv]e$|uai$/Ⓧ/",
            "xform/^sh/Ⓘ/", "xform/^ch/Ⓤ/", "xform/^zh/Ⓥ/", "xform/uo$/Ⓞ/", "xform/[uv]n$/Ⓩ/", "xform/i?ong$/Ⓨ/",
            "xform/[iu]ang$/Ⓗ/", "xform/(.)en$/$1Ⓡ/", "xform/(.)eng$/$1Ⓣ/", "xform/(.)ang$/$1Ⓖ/", "xform/ian$/Ⓙ/",
            "xform/(.)an$/$1Ⓕ/", "xform/iao$/Ⓚ/", "xform/(.)ao$/$1Ⓓ/", "xform/(.)ai$/$1Ⓢ/", "xform/(.)ei$/$1Ⓦ/",
            "xform/ie$/Ⓜ/", "xform/ui$/Ⓥ/", "xform/(.)ou$/$1Ⓟ/", "xform/in$/Ⓛ/",
            "xlit/ⓆⓌⓇⓉⓎⓊⒾⓄⓅⓈⒹⒻⒼⒽⓂⒿⒸⓀⓁⓏⓍⓋⒷⓃ/qwrtyuiopsdfghmjcklzxvbn/",
        ]
        case .ziguang: return Self.erase + [
            "derive/^([jqxy])u$/$1v/", "xform/^([aoe].*)$/Ⓞ$1/", "xform/en$/Ⓦ/", "xform/eng$/Ⓣ/", "xform/in$|uai$/Ⓨ/",
            "xform/^zh/Ⓤ/", "xform/^sh/Ⓘ/", "xform/uo$/Ⓞ/", "xform/ai$/Ⓟ/", "xform/^ch/Ⓐ/", "xform/[iu]ang$/Ⓖ/",
            "xform/ang$/Ⓢ/", "xform/ie$/Ⓓ/", "xform/ian$/Ⓕ/", "xform/(.)i?ong$/$1Ⓗ/", "xform/er$|iu$/Ⓙ/", "xform/ei$/Ⓚ/",
            "xform/uan$/Ⓛ/", "xform/ing$/;/", "xform/ou$/Ⓩ/", "xform/[iu]a$/Ⓧ/", "xform/iao$/Ⓑ/",
            "xform/ue$|ui$|ve$/Ⓝ/", "xform/un$/Ⓜ/", "xform/ao$/Ⓠ/", "xform/an$/Ⓡ/",
            "xlit/ⓌⓉⓎⓊⒾⓄⓅⒶⒼⓈⒹⒻⒽⒿⓀⓁⓏⓍⒷⓃⓂⓆⓇ/wtyuiopagsdfhjklzxbnmqr/",
        ]
        }
    }

    /// The rule every scheme starts with: "xx" (an interjection) is no syllable.
    private static let erase = ["erase/^xx$/"]
    /// Xiaohe's and Ziranma's: ü typed v after j q x y as well, and a syllable without an initial typed with its first
    /// vowel twice (an → aan, ang → aang → ah).
    private static let vowelsDoubled = ["derive/^([jqxy])u$/$1v/", "derive/^([aoe])([ioun])$/$1$1$2/", "xform/^([aoe])(ng)?$/$1$1$2/"]
    /// Microsoft's, Sogou's and Pinyin Jiajia's: ü typed v as well, and a syllable without an initial typed with o first
    /// as well (oai), or a and e twice.
    private static let zeroInitialO = ["derive/^([jqxy])u$/$1v/", "derive/^([aoe].*)$/o$1/", "xform/^([ae])(.*)$/$1$1$2/"]
}

/// librime's spelling algebra (`speller/algebra`), as far as rime-ice's schemas use it: `xform` (a spelling replaced by
/// what the pattern makes of it), `derive` (one made of it added), `erase` (a spelling the pattern matches whole dropped)
/// and `xlit` (letters for letters). What `Pinyin.Reading` reads a scheme's letters by.
enum SpellingAlgebra {
    /// `spellings` with `rules` applied, each to what the ones before it gave. A rule not of those kinds changes nothing.
    static func apply(_ rules: [String], to spellings: Set<String>) -> Set<String> {
        var out = spellings
        for rule in rules {
            let parts = rule.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3, let kind = parts.first else { continue }
            switch kind {
            case "xlit":
                let (from, to) = (Array(parts[1]), Array(parts[2]))
                guard from.count == to.count else { continue }
                let map = Dictionary(zip(from, to), uniquingKeysWith: { first, _ in first })
                out = Set(out.map { String($0.map { map[$0] ?? $0 }) })
            case "xform", "derive", "erase":
                guard let regex = try? NSRegularExpression(pattern: parts[1]) else { continue }
                var next = kind == "derive" ? out : []
                for spelling in out {
                    let range = NSRange(spelling.startIndex..., in: spelling)
                    if kind == "erase" {
                        // librime erases a spelling the pattern matches whole.
                        if let match = regex.firstMatch(in: spelling, range: range), match.range == range { continue }
                        next.insert(spelling)
                        continue
                    }
                    guard parts.count >= 4, regex.firstMatch(in: spelling, range: range) != nil else {
                        if kind == "xform" { next.insert(spelling) }
                        continue
                    }
                    let made = regex.stringByReplacingMatches(in: spelling, range: range, withTemplate: parts[2])
                    if !made.isEmpty { next.insert(made) }
                }
                out = next
            default:
                continue
            }
        }
        return out
    }
}

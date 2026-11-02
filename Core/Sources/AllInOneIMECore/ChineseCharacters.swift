import Foundation

/// The characters Chinese typed in pinyin comes out in (`Config.chineseCharacters`, Settings → Input → Chinese →
/// Characters): Simplified, or Traditional as Taiwan or Hong Kong write it. Rime converts its candidates (rime-ice's
/// `traditionalization` switch, with OpenCC's data: `patch`), and whatever reasons about the language typed takes Chinese
/// for this one (`language`): the AI's prompts, Translate as You Type, `@reply`, screen text, web search, dictation.
public enum ChineseCharacters: String, Codable, CaseIterable, Sendable {
    case simplified
    /// Taiwan's characters and words (软件 → 軟體, 网络 → 網路).
    case taiwan
    /// Hong Kong's characters (软件 → 軟件, 网络 → 網絡).
    case hongkong

    /// Traditional characters (Taiwan's or Hong Kong's).
    public var isTraditional: Bool { self != .simplified }

    /// The variant for the system's preferred languages (`Platform.userLanguages`), read as the interface language reads
    /// them (`InterfaceLanguage.pick`): the first Chinese one decides. Hong Kong's ("zh-HK", "zh-Hant-HK") is Hong Kong's,
    /// another Traditional one ("zh-Hant", "zh-TW", "zh-MO") Taiwan's, any other Simplified; with none, Simplified.
    public static func preferred(from identifiers: [String]) -> ChineseCharacters {
        for identifier in identifiers {
            let parts = identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-").map { $0.lowercased() }
            guard parts.first == "zh" else { continue }
            // A script says it; without one, the region does.
            let script = parts.dropFirst().first { $0.count == 4 }
            let region = parts.dropFirst().first { $0.count == 2 }
            guard script.map({ $0 == "hant" }) ?? ["tw", "hk", "mo"].contains(region ?? "") else { return .simplified }
            return region == "hk" ? .hongkong : .taiwan
        }
        return .simplified
    }

    /// The language Chinese typed in these characters is: "zh" (Simplified, as before), "zh-Hant-TW", "zh-Hant-HK".
    public var language: OutputLanguage {
        switch self {
        case .simplified: return .chinese
        case .taiwan: return .traditionalTaiwan
        case .hongkong: return .traditionalHongKong
        }
    }

    /// Its name as Settings lists it, in its own characters as the system names languages: 简体, 繁體（台灣）, 繁體（香港）.
    public func name(in language: String) -> String {
        let t = InterfaceWords(language: language)
        switch self {
        case .simplified: return t.tr("简体", "Simplified")
        case .taiwan: return t.tr("繁體（台灣）", "Traditional (Taiwan)")
        case .hongkong: return t.tr("繁體（香港）", "Traditional (Hong Kong)")
        }
    }

    // MARK: Rime

    /// The OpenCC config Rime converts with (`opencc/` in the Rime user folder, copied there from the app's): Taiwan's
    /// characters and words, Hong Kong's characters; nil for Simplified, which isn't converted.
    public var openCCConfig: String? {
        switch self {
        case .simplified: return nil
        case .taiwan: return "s2twp.json"
        case .hongkong: return "s2hk.json"
        }
    }

    /// The OpenCC files the configs need, each config with its dictionaries: what the app carries
    /// (Contents/SharedSupport/opencc) and copies into the Rime user folder. s2tw.json (Taiwan's characters without its
    /// words) comes along for whoever sets it in their own patch.
    public static let openCCFiles = [
        "s2twp.json", "s2hk.json", "s2tw.json",
        "STPhrases.ocd2", "STCharacters.ocd2", "TWPhrases.ocd2", "TWVariants.ocd2", "HKVariants.ocd2",
    ]

    /// rime-ice's switch for its Traditional output (`switches` in its schema, and `traditionalize/option_name`).
    static let switchName = "traditionalization"

    /// The lines of the `patch:` of rime-ice's schema (`rime_ice.custom.yaml`, written with fuzzy pinyin's:
    /// `PersonalDictionaryStore.applyFuzzyPinyin`) for these characters: the switch on at the start of every session, found
    /// in the schema by its name (`switchIndex`), its OpenCC config, and the quotation marks Taiwan and Hong Kong write
    /// (" 「」, ' 『』) in both widths. Nil for Simplified, and for a schema without the switch.
    public func patch(schema: String) -> String? {
        guard let config = openCCConfig, let index = Self.switchIndex(Self.switchName, inSchema: schema) else { return nil }
        var lines = [
            "  # \(name(in: "en")) characters: Settings → Input → Chinese → Characters.",
            "  switches/@\(index)/reset: 1",
            "  traditionalize/opencc_config: \(config)",
        ]
        for shape in ["half_shape", "full_shape"] {
            lines.append("  \"punctuator/\(shape)/\\\"\": { pair: [ \"「\", \"」\" ] }")
            lines.append("  \"punctuator/\(shape)/'\": { pair: [ \"『\", \"』\" ] }")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The place of the switch `name` in the schema's `switches` list (from 0), as a patch names it (`switches/@2`);
    /// nil when it has none. Items are written `- name: …` (with more on the lines after) or `- { name: …, … }`.
    static func switchIndex(_ name: String, inSchema text: String) -> Int? {
        var inSwitches = false, index = -1
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let indent = line.prefix(while: { $0 == " " }).count
            var content = line.trimmingCharacters(in: .whitespaces)
            if content.isEmpty || content.hasPrefix("#") { continue }
            // A key at the top starts or ends the list (whose items may start there too: `- name: …` not indented).
            if indent == 0, !(inSwitches && content.hasPrefix("- ")) {
                inSwitches = content.hasPrefix("switches:")
                continue
            }
            guard inSwitches else { continue }
            if content.hasPrefix("- ") {
                index += 1
                content = String(content.dropFirst(2))
            }
            if let comment = content.range(of: " #") { content = String(content[..<comment.lowerBound]) }
            guard index >= 0, let found = content.range(of: #"(?:^|[{,]\s*)name:\s*([A-Za-z0-9_]+)"#, options: .regularExpression)
            else { continue }
            let value = content[found].split(separator: ":").last?.trimmingCharacters(in: .whitespaces)
            if value == name { return index }
        }
        return nil
    }
}

extension OutputLanguage {
    /// Chinese in Traditional characters as Taiwan or Hong Kong write it: what Chinese is typed in when the characters
    /// say so (`ChineseCharacters.language`).
    public static let traditionalTaiwan = OutputLanguage("zh-Hant-TW")
    public static let traditionalHongKong = OutputLanguage("zh-Hant-HK")

    /// The output language `language` is when typed, Chinese in `chinese`'s characters: "zh-Hant-TW" for Chinese typed in
    /// Taiwan's.
    public init(_ language: Language, chinese: ChineseCharacters) {
        self = language == .chinese ? chinese.language : OutputLanguage(language)
    }

    /// Chinese, in either script: "zh", "zh-Hant", "zh-Hant-TW".
    public var isChinese: Bool { InterfaceLanguage.isChinese(code) }

    /// Chinese in Traditional characters: "zh-Hant", "zh-Hant-TW", "zh-TW".
    public var isTraditionalChinese: Bool { isChinese && !InterfaceLanguage.isSimplifiedChinese(code) }

    /// Whether a sentence in it is one in `other`: the same code, or Chinese in the same script (what is typed in Taiwan's
    /// characters is in "zh-Hant", what is typed in Simplified ones in "zh"). Never translated from one into the other.
    public func isSame(as other: OutputLanguage) -> Bool {
        if self == other { return true }
        return isChinese && other.isChinese && isTraditionalChinese == other.isTraditionalChinese
    }

    /// `text`, written in Simplified Chinese (or in no Chinese at all), as this language writes it: in Traditional
    /// characters for Traditional Chinese (ICU's Hans-Hant transform, the same for Taiwan and Hong Kong), as it is for the
    /// others. The prompts' examples, written once, in Simplified Chinese and English.
    func written(_ text: String) -> String {
        guard isTraditionalChinese, text.containsHan else { return text }
        return text.applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false) ?? text
    }
}

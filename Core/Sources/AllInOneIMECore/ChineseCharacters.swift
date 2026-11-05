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
    /// them (`InterfaceLanguage.Tag`): the first Chinese one decides. Hong Kong's ("zh-HK", "zh-Hant-HK") is Hong Kong's,
    /// another Traditional one ("zh-Hant", "zh-TW", "zh-MO") Taiwan's, any other Simplified; with none, Simplified.
    public static func preferred(from identifiers: [String]) -> ChineseCharacters {
        guard let tag = identifiers.lazy.map(InterfaceLanguage.Tag.init).first(where: { $0.language == "zh" }), tag.traditional
        else { return .simplified }
        return tag.region == "HK" ? .hongkong : .taiwan
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

    // MARK: Text

    /// Whether Chinese `text` is written in Traditional characters (true) or Simplified ones (false); nil when it can't
    /// be told: none of its characters differs between the two (香港很美), or it has no Chinese. Text in Simplified
    /// characters changes when made Traditional, text in Traditional ones when made Simplified (ICU's transforms, which
    /// read words: 皇后 and 公里 stay as they are, 后来 becomes 後來); with some of each (a quote in the other), the
    /// side more of them are on. Its first `limit` characters say, so a long selection costs no more than a sentence, and
    /// the same text asked again (the hint under a draft on a selection, at every key) is answered from the last time.
    /// Japanese (any kana) is nil too: its kanji are neither (日本の学校 reads Simplified, 日本語の勉強 Traditional).
    ///
    /// It reads characters, not the writer: Simplified text that keeps a Traditional form by right (乾 in 乾隆) leans
    /// Traditional, and text with no telling characters goes by the setting (`OutputLanguage.of`).
    public static func writtenTraditional(_ text: String, limit: Int = 400) -> Bool? {
        let text = String(text.prefix(limit))
        guard text.containsHan, !text.unicodeScalars.contains(where: isKana) else { return nil }
        if let told = lastTold.withLock({ $0 }), told.text == text { return told.traditional }
        let simplified = changed(text, by: "Hans-Hant"), traditional = changed(text, by: "Hant-Hans")
        let answer = simplified == traditional ? nil : traditional > simplified
        lastTold.withLock { $0 = (text, answer) }
        return answer
    }

    /// The text `writtenTraditional` told last, and what it said.
    private static let lastTold = Locked<(text: String, traditional: Bool?)?>(initialState: nil)

    /// Hiragana or katakana, the halfwidth ones too.
    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3040...0x30FF).contains(scalar.value) || (0xFF66...0xFF9F).contains(scalar.value)
    }

    /// How many characters of `text` ICU's transform `id` changes (as many as it has when their number changes).
    private static func changed(_ text: String, by id: String) -> Int {
        guard let other = text.applyingTransform(StringTransform(rawValue: id), reverse: false) else { return 0 }
        let (before, after) = (Array(text.unicodeScalars), Array(other.unicodeScalars))
        guard before.count == after.count else { return other == text ? 0 : before.count }
        return zip(before, after).filter { $0 != $1 }.count
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

    /// The OpenCC files these characters convert with: their config and the dictionaries it names (of `openCCFiles`);
    /// none for Simplified. What the Doctor checks for them (`RimeService.providedOpenCC`), not the others'.
    public var openCCData: [String] {
        guard let config = openCCConfig else { return [] }
        let variants = self == .hongkong ? ["HKVariants.ocd2"] : ["TWPhrases.ocd2", "TWVariants.ocd2"]
        return [config, "STPhrases.ocd2", "STCharacters.ocd2"] + variants
    }

    /// The characters Rime's patch was last written for, kept by whatever writes it (the Mac's `RimeFuzzy`): with the
    /// setting absent they follow the system's languages (`Config.typedChinese`), which can change while the input method
    /// runs. The prompts, the chip and Settings read them each time and follow at once; the candidates follow once the
    /// patch is written again and Rime deployed again, which `changed` says when to do.
    public final class Written: Sendable {
        private let characters = Locked<ChineseCharacters?>(initialState: nil)

        public init() {}

        /// The patch was just written for `characters`.
        public func wrote(_ characters: ChineseCharacters) {
            self.characters.withLock { $0 = characters }
        }

        /// The characters `config` types in now, when the patch was last written for others: to write it for them (and
        /// deploy again). They count as written from then on, so a change asks once. Nil when they are the same, and
        /// before the patch is first written (Rime's start writes it).
        public func changed(_ config: Config) -> ChineseCharacters? {
            let now = config.typedChinese
            return characters.withLock { written in
                guard let before = written, before != now else { return nil }
                written = now
                return now
            }
        }
    }

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

    /// Chinese in Traditional characters: "zh-Hant", "zh-Hant-TW", "zh-TW". Chinese and not Simplified, as
    /// `InterfaceLanguage` tells them, from one reading of its code.
    public var isTraditionalChinese: Bool {
        let tag = InterfaceLanguage.Tag(code)
        return tag.language == "zh" && tag.traditional
    }

    /// Whether a sentence in it is one in `other`: the same code, or Chinese in the same script (what is typed in Taiwan's
    /// characters is in "zh-Hant", what is typed in Simplified ones in "zh"). Never translated from one into the other.
    /// Each code is read once (`InterfaceLanguage.Tag`), as `isChinese` and `isTraditionalChinese` tell them.
    public func isSame(as other: OutputLanguage) -> Bool {
        if self == other { return true }
        let tag = InterfaceLanguage.Tag(code)
        guard tag.language == "zh" else { return false }
        let otherTag = InterfaceLanguage.Tag(other.code)
        return otherTag.language == "zh" && tag.traditional == otherTag.traditional
    }

    /// The language `text` is written in (`language`, as `Language.of` tells it), Chinese by its own characters when they
    /// tell (`ChineseCharacters.writtenTraditional`): in Simplified ones "zh", in Traditional ones the characters typed
    /// (`chinese`) when those are Traditional too ("zh-Hant-TW"), else "zh-Hant"; when they don't (香港很美), in the
    /// characters typed. For text the user didn't just type, which may be in either (a selection, the clipboard, a page
    /// from the mainland): a Taiwan user's Simplified text is translated into Traditional Chinese, a Simplified user's
    /// Traditional text into Simplified Chinese.
    public static func of(_ text: String, language: Language, chinese: ChineseCharacters) -> OutputLanguage {
        guard language == .chinese, let traditional = ChineseCharacters.writtenTraditional(text) else {
            return OutputLanguage(language, chinese: chinese)
        }
        if !traditional { return .chinese }
        return chinese.isTraditional ? chinese.language : OutputLanguage("zh-Hant")
    }

    /// `text`, written in Simplified Chinese (or in no Chinese at all), as this language writes it: in Traditional
    /// characters for Traditional Chinese (ICU's Hans-Hant transform, the same for Taiwan and Hong Kong, but for the
    /// examples Taiwan words otherwise, written by hand: `Prompt.taiwan`), as it is for the others. The prompts'
    /// examples, written once, in Simplified Chinese and English.
    func written(_ text: String) -> String {
        guard isTraditionalChinese, text.containsHan else { return text }
        if self == .traditionalTaiwan, let taiwan = Prompt.taiwan[text] { return taiwan }
        return text.applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false) ?? text
    }
}

import Foundation

/// How Chinese is typed, as the settings say: the characters, the way of typing pinyin, the shape codes.
public extension Config {
    /// The characters Chinese is typed in: the ones picked (`chineseCharacters`), else those of the system's preferred
    /// languages (`Platform.userLanguages`, `ChineseCharacters.preferred`), read each time: a Mac whose language changes
    /// follows it.
    var typedChinese: ChineseCharacters {
        chineseCharacters ?? .preferred(from: Platform.current.userLanguages.preferred)
    }

    /// How Chinese is typed in pinyin (`pinyinScheme`): full pinyin, a Shuangpin scheme, Zhuyin or Wubi.
    var typedPinyin: PinyinScheme { PinyinScheme(setting: pinyinScheme) }

    /// The output language a sentence typed in `language` is in: Chinese in the characters typed ("zh", "zh-Hant-TW").
    func typedLanguage(_ language: Language) -> OutputLanguage { OutputLanguage(language, chinese: typedChinese) }

    /// The output language `text` is written in: Chinese by its own characters when they tell, else in the characters
    /// typed (`OutputLanguage.of`). What decides whether it is translated into an output language or is in it already.
    func writtenLanguage(of text: String) -> OutputLanguage {
        OutputLanguage.of(text, language: language(of: text), chinese: typedChinese)
    }

    /// The shape codes typed after "`" (`shapeCode`, `ShapeCode`); nil: off. Zhuyin's and Wubi's patches never have them.
    var typedShapeCode: ShapeCode? { ShapeCode(setting: shapeCode) }
}

// How the way of typing pinyin and its shape codes are read from a config file and written to it: out of `init(from:)`
// and `encode(to:)`, already long (as `decodePanel`).
extension Config {
    /// `pinyinScheme` and `shapeCode` in `c`: full pinyin for "full", and for a scheme this version doesn't know (a later
    /// one's); shape codes off for "off" and for a table the app doesn't carry (a later version's). Not errors.
    static func decodeTyping(_ c: KeyedDecodingContainer<CodingKeys>) -> (String?, String?) {
        func string(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)).flatMap { $0 } }
        return (PinyinScheme(setting: string(.pinyinScheme)).setting, ShapeCode(setting: string(.shapeCode))?.rawValue)
    }

    /// Only Shuangpin, Zhuyin or Wubi, and shape codes only once picked: a file from before the settings doesn't gain the keys,
    /// nor one back on full pinyin or with shape codes off.
    func encodeTyping(into c: inout KeyedEncodingContainer<CodingKeys>) throws {
        try c.encodeIfPresent(typedPinyin.setting, forKey: .pinyinScheme)
        try c.encodeIfPresent(typedShapeCode?.rawValue, forKey: .shapeCode)
    }
}

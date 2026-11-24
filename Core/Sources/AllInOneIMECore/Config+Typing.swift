import Foundation

/// How Chinese is typed, as the settings say: the characters, the way of typing pinyin.
public extension Config {
    /// The characters Chinese is typed in: the ones picked (`chineseCharacters`), else those of the system's preferred
    /// languages (`Platform.userLanguages`, `ChineseCharacters.preferred`), read each time: a Mac whose language changes
    /// follows it.
    var typedChinese: ChineseCharacters {
        chineseCharacters ?? .preferred(from: Platform.current.userLanguages.preferred)
    }

    /// How Chinese is typed in pinyin (`pinyinScheme`): full pinyin, a Shuangpin scheme, or Zhuyin.
    var typedPinyin: PinyinScheme { PinyinScheme(setting: pinyinScheme) }

    /// The output language a sentence typed in `language` is in: Chinese in the characters typed ("zh", "zh-Hant-TW").
    func typedLanguage(_ language: Language) -> OutputLanguage { OutputLanguage(language, chinese: typedChinese) }

    /// The output language `text` is written in: Chinese by its own characters when they tell, else in the characters
    /// typed (`OutputLanguage.of`). What decides whether it is translated into an output language or is in it already.
    func writtenLanguage(of text: String) -> OutputLanguage {
        OutputLanguage.of(text, language: language(of: text), chinese: typedChinese)
    }
}

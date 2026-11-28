import Foundation

/// Chinese's settings: fuzzy pinyin, the characters, and how it is typed (Settings → Common → Chinese typing, and the
/// Shuangpin scheme below it).
extension SettingsStore {
    /// Fuzzy pinyin's pairs (`FuzzyPinyin.pairs` ids; the ones this version doesn't know are left out), saved. The shell
    /// applies them to its Rime.
    public func setFuzzyPinyin(_ ids: [String]) {
        config.fuzzyPinyin = FuzzyPinyin.known(ids)
        save()
    }

    /// What turning fuzzy pinyin on picks: the pairs most often mixed up.
    public static let fuzzyDefaults = ["z-zh", "c-ch", "s-sh", "en-eng", "in-ing"]

    /// The characters Chinese is typed in (`Config.chineseCharacters`), saved: picked, they no longer follow the system's
    /// languages. The shell applies them to its Rime, as it does fuzzy pinyin.
    public func setChineseCharacters(_ characters: ChineseCharacters) {
        config.chineseCharacters = characters
        save()
    }

    /// How Chinese is typed in pinyin (`Config.pinyinScheme`: full pinyin, a Shuangpin scheme, Zhuyin or Wubi), saved. The shell
    /// deploys its schema, as it applies fuzzy pinyin; the next key types with it. Zhuyin picked by one who never picked
    /// the characters (`Config.chineseCharacters` absent: the system's languages') picks Taiwan's with it, as Taiwan types
    /// Zhuyin; the user can change them after. Characters picked before stay. A Shuangpin scheme set is the one
    /// Shuangpin picks again after another way (`shuangpinScheme`).
    public func setPinyinScheme(_ scheme: PinyinScheme) {
        config.pinyinScheme = scheme.setting
        if scheme == .zhuyin, config.chineseCharacters == nil { config.chineseCharacters = .taiwan }
        save()
    }

    /// The way Chinese is typed (`TypingWay`): Settings' Chinese typing.
    public var typingWay: TypingWay { TypingWay(config.typedPinyin) }

    /// The Shuangpin scheme Shuangpin types with: the one typed now, else the one typed last (in memory: `lastShuangpin`,
    /// kept as the config leaves it, whether picked here or read from the file), else Xiaohe's.
    public var shuangpinScheme: PinyinScheme {
        let typed = config.typedPinyin
        return typed.isShuangpin ? typed : lastShuangpin ?? .xiaohe
    }

    /// The way Chinese is typed, picked (`setPinyinScheme`): Shuangpin with its scheme used last (`shuangpinScheme`).
    public func setTypingWay(_ way: TypingWay) {
        setPinyinScheme(way.scheme(shuangpin: shuangpinScheme))
    }
}

import Foundation

/// How Chinese is typed, as Settings' first Typing menu offers it (Settings → Common → Chinese typing): full pinyin,
/// Shuangpin, Zhuyin or Wubi 86. Shuangpin stands for all its schemes, picked in the row under it (`PinyinScheme.shuangpin`,
/// `SettingsStore.shuangpinScheme`); what is saved stays the scheme (`Config.pinyinScheme`), so this is never a setting of
/// its own.
public enum TypingWay: String, CaseIterable, Sendable {
    case fullPinyin, shuangpin, zhuyin, wubi

    /// The way `scheme` types: every Shuangpin scheme's is Shuangpin.
    public init(_ scheme: PinyinScheme) {
        switch scheme {
        case .full: self = .fullPinyin
        case .zhuyin: self = .zhuyin
        case .wubi: self = .wubi
        case .xiaohe, .ziranma, .microsoft, .sogou, .zhinengABC, .pinyinJiajia, .ziguang: self = .shuangpin
        }
    }

    /// The scheme it types with: Shuangpin's is `shuangpin`, the one used last (`SettingsStore.shuangpinScheme`).
    public func scheme(shuangpin: PinyinScheme) -> PinyinScheme {
        switch self {
        case .fullPinyin: return .full
        case .shuangpin: return shuangpin
        case .zhuyin: return .zhuyin
        case .wubi: return .wubi
        }
    }

    /// Its name as the menu lists it: 全拼, 双拼, 注音, 五笔 86 (Full pinyin, Shuangpin, Zhuyin, Wubi 86). `language` is an
    /// interface language's code, or "zh", the settings' name of Simplified Chinese (`InterfaceLanguage.setting`).
    public func name(in language: String) -> String {
        let t = InterfaceWords(language: language == "zh" ? "zh-Hans" : language)
        switch self {
        case .fullPinyin: return t.tr("全拼", "Full pinyin")
        case .shuangpin: return t.tr("双拼", "Shuangpin")
        case .zhuyin: return t.tr("注音", "Zhuyin")
        case .wubi: return t.tr("五笔 86", "Wubi 86")
        }
    }
}

import Foundation

/// Chinese's settings in Input, while Chinese is typed: how it is typed (`PinyinScheme`), the characters
/// (`ChineseCharacters`: `characters`, as `Config.typedChinese` read them once), for pinyin its shape codes (`ShapeCode`),
/// fuzzy pinyin.
extension SettingsSchema {
    mutating func chineseTyping(_ fields: inout [Field], characters chinese: ChineseCharacters) {
        let store = store
        // Full pinyin, a Shuangpin scheme, Zhuyin or Wubi, beside the characters (`PinyinScheme`): the Mac deploys it
        // (Windows not yet). Zhuyin picked first picks Taiwan's characters (`SettingsStore.setPinyinScheme`); Wubi leaves
        // them as they are. One field with every scheme, the one key it saves: the Mac's window draws it as two menus, the
        // way (`TypingWay`) and, with Shuangpin, the scheme below it, which pick the same values.
        add(choice("pinyinScheme", UIText.pinyinSchemeLabel, UIText.pinyinSchemeHelp, value: .string(config.typedPinyin.rawValue),
                   choices: PinyinScheme.allCases.map { (Choice($0.rawValue, $0.name(in: UIText.language)), nil) }, platforms: [.mac]),
            to: &fields) { value in
            store.setPinyinScheme(PinyinScheme(setting: value.string))
        }
        // As the system's languages say until one is picked (`Config.typedChinese`).
        add(choice("chineseCharacters", UIText.chineseCharactersLabel, UIText.chineseCharactersHelp,
                   value: .string(chinese.rawValue),
                   choices: ChineseCharacters.allCases.map { (Choice($0.rawValue, $0.name(in: UIText.language)), nil) }),
            to: &fields) { value in
            store.setChineseCharacters(value.string.flatMap(ChineseCharacters.init(rawValue:)) ?? store.config.typedChinese)
        }
        // Shape codes after "`" (`ShapeCode`), the tables the app carries, Off ("off": `Config.shapeCode` nil) first: for
        // pinyin, so not shown with Zhuyin or Wubi (kept, and unused: their patches have none). Deployed by the Mac, as the
        // scheme is. After the characters: the scheme stays beside them.
        if config.typedPinyin.isPinyin {
            add(choice("shapeCode", UIText.shapeCodeLabel, UIText.shapeCodeHelp, value: .string(config.typedShapeCode?.rawValue ?? "off"),
                       choices: [(Choice("off", UIText.shapeCodeOff), nil)]
                           + ShapeCode.allCases.map { (Choice($0.rawValue, $0.name(in: UIText.language)), nil) }, platforms: [.mac]),
                to: &fields) { value in
                store.config.shapeCode = ShapeCode(setting: value.string)?.rawValue
            }
        }
        var fuzzy = Field(id: "fuzzyPinyin", kind: .choices, label: tr("模糊音", "Fuzzy pinyin"),
                          help: tr("分不清的音两种拼法都能打出来，比如 zh 和 z：打 zi 也有「之」", "Sounds you don't tell apart typed either way, e.g. zh and z: zi also offers 之"),
                          value: .array(config.fuzzyPinyin.map(JSON.string)))
        fuzzy.choices = FuzzyPinyin.pairs.map { Choice($0.id, $0.label) }
        add(fuzzy, to: &fields) { store.setFuzzyPinyin(Self.strings($0)) }
    }
}

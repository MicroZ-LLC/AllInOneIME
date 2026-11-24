import AllInOneIMECore
import SwiftUI

/// Common → Typing, while Chinese is typed: how it is typed (`PinyinScheme`) and the characters.
struct ChineseTypingRows: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        pinyinSchemeRow
        chineseCharactersRow
    }

    /// Common → how Chinese is typed: full pinyin, a Shuangpin scheme or Zhuyin (`PinyinScheme`).
    private var pinyinSchemeRow: some View {
        Picker(selection: Binding(get: { model.config.typedPinyin }, set: { model.setPinyinScheme($0) })) {
            ForEach(PinyinScheme.allCases, id: \.self) { scheme in
                Text(scheme.name(in: UIText.language)).tag(scheme)
            }
        } label: {
            titled(.pinyinScheme)
        }
        .pickerStyle(.menu)
        .settingsRow(.pinyinScheme, shown: model.spot)
    }

    /// Common → the Chinese characters typed, as the system's languages say until one is picked (`Config.typedChinese`).
    private var chineseCharactersRow: some View {
        Picker(selection: Binding(get: { model.config.typedChinese }, set: { model.setChineseCharacters($0) })) {
            ForEach(ChineseCharacters.allCases, id: \.self) { characters in
                Text(characters.name(in: UIText.language)).tag(characters)
            }
        } label: {
            titled(.chineseCharacters)
        }
        .pickerStyle(.menu)
        .settingsRow(.chineseCharacters, shown: model.spot)
    }
}

import AllInOneIMECore
import SwiftUI

/// Common → Typing, while Chinese is typed: how it is typed (`PinyinScheme`), the characters, and for pinyin the shape
/// codes (`ShapeCode`; not with Zhuyin or Wubi), as Settings' document has them. The shape codes have no row of the search's own:
/// the search finds them by the scheme's (`SettingsSpot.pinyinScheme`), two rows above them.
struct ChineseTypingRows: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        pinyinSchemeRow
        chineseCharactersRow
        if model.config.typedPinyin.isPinyin { shapeCodeRow }
    }

    /// Common → how Chinese is typed: full pinyin, a Shuangpin scheme, Zhuyin or Wubi (`PinyinScheme`).
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

    /// Common → the shape codes after "`" (`ShapeCode`): Off, or one of the tables the app carries.
    private var shapeCodeRow: some View {
        Picker(selection: Binding(get: { model.config.typedShapeCode }, set: { model.setShapeCode($0) })) {
            Text(UIText.shapeCodeOff).tag(ShapeCode?.none)
            ForEach(ShapeCode.allCases, id: \.self) { code in
                Text(code.name(in: UIText.language)).tag(ShapeCode?.some(code))
            }
        } label: {
            titled(UIText.shapeCodeLabel, UIText.shapeCodeHelp)
        }
        .pickerStyle(.menu)
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

extension SettingsModel {
    /// The shape codes picked (nil: off): saved, and Rime deployed again with the patch for them (a moment, as for fuzzy
    /// pinyin); the next "`" filters with them.
    func setShapeCode(_ code: ShapeCode?) {
        guard code != config.typedShapeCode else { return }
        config.shapeCode = code?.rawValue
        store.save()
        guard persists else { return }
        applyRime()
    }
}

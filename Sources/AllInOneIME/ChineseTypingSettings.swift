import AllInOneIMECore
import SwiftUI

/// Common → Typing, while Chinese is typed: how it is typed (`TypingWay`), with Shuangpin the scheme below it
/// (`PinyinScheme.shuangpin`), the characters, and for pinyin the shape codes (`ShapeCode`; not with Zhuyin or Wubi), as
/// Settings' document has them (one `pinyinScheme` there, both rows here). The Shuangpin scheme and the shape codes have
/// no row of the search's own: the search finds them by Chinese typing's (`SettingsSpot.pinyinScheme`), the first row,
/// shown whatever is typed (a scheme's name lands there even while the scheme's row is hidden).
struct ChineseTypingRows: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        typingWayRow
        if model.config.typedPinyin.isShuangpin { shuangpinSchemeRow }
        chineseCharactersRow
        if model.config.typedPinyin.isPinyin { shapeCodeRow }
    }

    /// Common → how Chinese is typed: full pinyin, Shuangpin, Zhuyin or Wubi (`TypingWay`).
    private var typingWayRow: some View {
        Picker(selection: Binding(get: { TypingWay(model.config.typedPinyin) }, set: { model.setTypingWay($0) })) {
            ForEach(TypingWay.allCases, id: \.self) { way in
                Text(way.name(in: UIText.language)).tag(way)
            }
        } label: {
            titled(.pinyinScheme)
        }
        .pickerStyle(.menu)
        .settingsRow(.pinyinScheme, shown: model.spot)
    }

    /// Common → the Shuangpin scheme, right below how Chinese is typed, only while that is Shuangpin.
    private var shuangpinSchemeRow: some View {
        Picker(selection: Binding(get: { model.config.typedPinyin }, set: { model.setPinyinScheme($0) })) {
            ForEach(PinyinScheme.shuangpin, id: \.self) { scheme in
                Text(scheme.shuangpinName(in: UIText.language)).tag(scheme)
            }
        } label: {
            Text(tr("双拼方案", "Shuangpin scheme"))
        }
        .pickerStyle(.menu)
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
    /// The way Chinese is typed, picked: Shuangpin with the scheme used last (`SettingsStore.setTypingWay`), saved and
    /// deployed as a scheme picked is (`setPinyinScheme`).
    func setTypingWay(_ way: TypingWay) {
        guard way != store.typingWay else { return }
        store.setTypingWay(way)
        guard persists else { return }
        applyRime()
    }

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

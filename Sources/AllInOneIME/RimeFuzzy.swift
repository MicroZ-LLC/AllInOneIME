import AllInOneIMECore
import AllInOneIMERime
import Foundation
import os

/// Fuzzy pinyin (`FuzzyPinyin`) in the Rime user folder: the patch for the pairs the config turns on, for the
/// characters Chinese is typed in (`ChineseCharacters`, Traditional ones through OpenCC), and for the filter of the
/// candidates removed that the app's Lua has (`RemovedCandidates.luaFilter`), so written with no pairs too; for full
/// pinyin's schema and the Shuangpin scheme, Zhuyin or Wubi typed with (`PinyinScheme`), whose schema is deployed beside it
/// (the schema list, `default.custom.yaml`); with the shape codes picked (`ShapeCode`) for pinyin's.
enum RimeFuzzy {
    /// The characters the patch was last written for (`follow`).
    static let written = ChineseCharacters.Written()
    /// The way of typing pinyin the patch and the schema list were last written for (`follow`); nil: not written yet.
    static var writtenScheme: PinyinScheme?
    /// The shape codes the patch was last written for (`follow`); nil: off, or not written yet (`writtenScheme` nil).
    static var writtenShapeCode: ShapeCode?

    /// Writes (or removes) the patch, and the schema list; nil when it couldn't. `.written` and `.removed` need a
    /// deployment, and so does a schema list written (`schemaListWritten`).
    @discardableResult
    static func write(_ ids: [String], characters: ChineseCharacters, scheme: PinyinScheme,
                      shapeCode: ShapeCode?) -> FuzzyPinyin.Outcome? {
        schemaListWritten = false
        guard let shared = RimeDirectories.shared else { return nil }
        // Whatever came of it: tried once for these characters, not again at every check (`follow`).
        defer {
            written.wrote(characters)
            writtenScheme = scheme
            writtenShapeCode = shapeCode
        }
        schemaListWritten = writeSchemaList(scheme)
        do {
            let outcome = try FuzzyPinyin.apply(ids, characters: characters, scheme: scheme, shapeCode: shapeCode,
                                                schema: shared.appendingPathComponent("rime_ice.schema.yaml"), userDir: RimeDirectories.user)
            if outcome == .userFile { log.notice("fuzzy pinyin not applied: the Rime folder has the user's own \(FuzzyPinyin.fileName, privacy: .public)") }
            return outcome
        } catch {
            log.error("could not write the fuzzy pinyin patch: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The last `write` wrote the schema list anew (another scheme picked): librime deploys it.
    private(set) static var schemaListWritten = false

    /// The schemas deployed (`PinyinScheme.applySchemaList`): full pinyin's, and the Shuangpin scheme's, Zhuyin's or Wubi's.
    /// Whether it was written anew.
    private static func writeSchemaList(_ scheme: PinyinScheme) -> Bool {
        do {
            switch try PinyinScheme.applySchemaList(scheme, userDir: RimeDirectories.user) {
            case .written: return true
            case .unchanged: return false
            case .userFile:
                log.notice("the schemas deployed are the user's own default.custom.yaml's: \(scheme.rawValue, privacy: .public) types only if it lists it")
                return false
            }
        } catch {
            log.error("could not write the schema list: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Changed in the settings: written, and Rime deployed again when it changed (about a second; a Shuangpin scheme
    /// deployed for the first time, its spellings too, a moment more; Zhuyin or Wubi, its dictionaries, a couple of seconds).
    @discardableResult
    static func apply(_ ids: [String], characters: ChineseCharacters, scheme: PinyinScheme,
                      shapeCode: ShapeCode?) -> FuzzyPinyin.Outcome? {
        let outcome = write(ids, characters: characters, scheme: scheme, shapeCode: shapeCode)
        if outcome == .written || outcome == .removed || schemaListWritten { RimeService.shared.redeploy() }
        return outcome
    }

    /// The settings read again (a text field focused) or the system's languages changed: with no characters picked they
    /// follow the system's (`Config.typedChinese`), so the candidates do too once they differ from the patch's
    /// (`ChineseCharacters.Written`): written again and deployed again, as a change in the settings is. So is another way
    /// of typing pinyin than the one written (`Config.pinyinScheme` changed in the file, or by the settings of another
    /// shell), which the next key types with once it is deployed; and so are other shape codes (`Config.shapeCode`).
    /// Nothing while the config file doesn't parse (nil): its defaults aren't the user's fuzzy pinyin. Nothing in the
    /// self-test either (`Config.selfTestURL`): its Rime has a user folder of its own, and the patch is the user's.
    @MainActor
    static func follow(_ config: Config?) {
        guard let config, Config.selfTestURL == nil, RimeService.shared.isStarted else { return }
        let characters = written.changed(config)
        let scheme = config.typedPinyin, shapeCode = config.typedShapeCode
        guard characters != nil || scheme != writtenScheme || shapeCode != writtenShapeCode else { return }
        if let characters {
            log.notice("the system's languages changed the characters Chinese is typed in: \(characters.rawValue, privacy: .public)")
        }
        if scheme != writtenScheme { log.notice("pinyin is typed another way: \(scheme.rawValue, privacy: .public)") }
        if shapeCode != writtenShapeCode { log.notice("shape codes: \(shapeCode?.rawValue ?? "off", privacy: .public)") }
        apply(config.fuzzyPinyin, characters: characters ?? config.typedChinese, scheme: scheme, shapeCode: shapeCode)
    }
}

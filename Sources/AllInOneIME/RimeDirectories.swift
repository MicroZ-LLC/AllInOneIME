import AllInOneIMECore
import Foundation

/// Where level one keeps its data: the Chinese language pack's dictionaries, learned words per user,
/// and the Lua scripts the pack's schemas use (in the bundle: packs are data only).
enum RimeDirectories {
    /// The self-test's data folder instead of the pack (`--rime-data`).
    static var override: URL?

    /// The installed Chinese pack's folder; nil until it is downloaded.
    static var shared: URL? {
        if let override { return override }
        let store = LanguagePackStore()
        return store.installed(.chinesePinyin) == nil ? nil : store.folder(.chinesePinyin)
    }
    /// The app's copy of rime-ice's Lua scripts, linked into the pack (`LanguagePackStore.linkCode`).
    static var code: URL? {
        Bundle.main.sharedSupportURL?.appendingPathComponent("rime-lua")
    }
    /// The app's Zhuyin data (rime-bopomofo's schema and what it needs: `PinyinScheme.zhuyinData`), linked into the pack
    /// (`LanguagePackStore.linkData`); compiled only where Zhuyin is picked (the schema list).
    static var zhuyin: URL? {
        Bundle.main.sharedSupportURL?.appendingPathComponent("rime-zhuyin")
    }
    /// The app's Wubi data (rime-wubi's schema and dictionary: `PinyinScheme.wubiData`), linked into the pack
    /// (`LanguagePackStore.linkData`); compiled only where Wubi is picked (the schema list).
    static var wubi: URL? {
        Bundle.main.sharedSupportURL?.appendingPathComponent("rime-wubi")
    }
    /// The app's tables of shape codes (`ShapeCode`, the folder `aux_code` in it), linked into the pack
    /// (`LanguagePackStore.linkData`); their filter is with the scripts (`code`).
    static var auxCode: URL? {
        Bundle.main.sharedSupportURL?.appendingPathComponent("rime-aux-code")
    }
    /// The app's OpenCC data for Traditional characters, copied into the user folder (`RimeService.prepareOpenCC`).
    static var openCC: URL? {
        Bundle.main.sharedSupportURL?.appendingPathComponent("opencc")
    }
    static var user: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AllInOneIME/Rime")
    }
    static var logs: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AllInOneIME")
    }
}

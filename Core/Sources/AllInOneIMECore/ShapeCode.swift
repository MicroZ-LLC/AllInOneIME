import Foundation

/// Shape codes (辅助码, 形码筛选) for pinyin (`Config.shapeCode`, Settings → Input → Chinese → Typing): after the pinyin,
/// "`" and the first letters of a character's shape code in one of these tables leave only the candidates with it: a
/// character whose code starts with them, a word with such a character (those whose first character it is first). The
/// filter is HowcanoeWang/rime-lua-aux-code's `aux_code.lua` (MIT, unmodified, the app's other Lua beside it), its
/// tables the app carries (`Contents/SharedSupport/rime-aux-code/aux_code`, linked into the Chinese pack as `aux_code`:
/// `LanguagePackStore.linkData`); nothing is downloaded. On, it takes the place of rime-ice's own filter on "`" (search.lua's
/// radical pinyin) in the patch of each pinyin schema (`patch`): one meaning per key. Full pinyin and every Shuangpin
/// scheme; never Zhuyin or Wubi (their keys aren't pinyin, and their patches have none of this).
public enum ShapeCode: String, CaseIterable, Sendable {
    /// 墨奇码 (gaboolic/moqima-tables, MIT).
    case moqi
    /// 鹤形, 小鹤音形's shape codes (rime-lua-aux-code's own table, MIT).
    case flypy
    /// 五笔 86 (rime/rime-wubi's table, LGPL-3.0).
    case wubi86
    /// 仓颉五代's first and last codes (rime/rime-cangjie's table, LGPL-3.0).
    case cangjie
    // Not 自然码's: its only table (copperay/ZRM_Aux-code) has no license and says "禁止商用" (no commercial use), so the
    // app doesn't carry it; a config naming it ("ziranma") is off, as one a later version adds.

    /// The table's name in the `aux_code` folder, without ".txt" (`aux_code/dictionary`).
    public var table: String {
        switch self {
        case .moqi: "moqi_aux_code"
        case .flypy: "flypy_full"
        case .wubi86: "wubi86-code"
        case .cangjie: "cangjie5_quick_code"
        }
    }

    /// The one `Config.shapeCode` names; nil (off) for none, "off", and one this version doesn't carry.
    public init?(setting: String?) {
        guard let code = setting.flatMap(ShapeCode.init(rawValue:)) else { return nil }
        self = code
    }

    /// Its name as Settings lists it: 墨奇码, Moqi.
    public func name(in language: String) -> String {
        let t = InterfaceWords(language: language)
        switch self {
        case .moqi: return t.tr("墨奇码", "Moqi")
        case .flypy: return t.tr("鹤形", "Xiaohe shape")
        case .wubi86: return t.tr("五笔 86", "Wubi 86")
        case .cangjie: return t.tr("仓颉", "Cangjie")
        }
    }

    // MARK: Where the filter comes from

    /// The key between the pinyin and the shape code: rime-ice's own for its filter (`key_binder/search`), in its schemas'
    /// alphabet. Not the plugin's ";", a final of Microsoft's and Sogou's Shuangpin.
    public static let trigger = "`"
    /// The filter's script (`lua/aux_code.lua` in the shared data, the app's Lua).
    public static let luaFilter = "aux_code"
    /// The folder of tables beside the pack's data, where the filter reads them (`aux_code/<table>.txt`).
    public static let folder = "aux_code"
    /// rime-ice's filter on "`" (search.lua, by the radicals' pinyin), which this one replaces.
    static let radicalFilter = "lua_filter@*search@radical_pinyin"

    /// The lines of a pinyin schema's patch (`schema`: the schema's text) for this table: the filter in the place of
    /// rime-ice's on "`" (after the others when the schema hasn't that one), and its settings. Nil when the shared data
    /// (`sharedData`, the schema's folder) lacks the script or the table: a Lua filter librime can't load leaves no
    /// candidate at all, and one without its table only a warning in Chinese; typing stays as it was.
    public func patch(schema: String, sharedData: URL) -> String? {
        guard ["lua/\(Self.luaFilter).lua", "\(Self.folder)/\(table).txt"].allSatisfy({
            FileManager.default.fileExists(atPath: sharedData.appendingPathComponent($0).path)
        }) else { return nil }
        let place = Self.filters(ofSchema: schema).firstIndex(of: Self.radicalFilter).map(String.init) ?? "next"
        return ["  # Shape codes (\(name(in: "en"))): Settings → Input → Chinese → Typing. In the place of rime-ice's filter on \"`\".",
                "  engine/filters/@\(place): lua_filter@*\(Self.luaFilter)",
                "  \(Self.folder)/dictionary: \(table)",
                "  \(Self.folder)/learn_trigger: \"\(Self.trigger)\""].joined(separator: "\n") + "\n"
    }

    /// The schema's filters (`engine/filters`), in order, as written in its text (comments dropped).
    static func filters(ofSchema text: String) -> [String] {
        var filters: [String] = [], inEngine = false, inFilters = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let indent = line.prefix(while: { $0 == " " }).count
            var content = line.trimmingCharacters(in: .whitespaces)
            if content.isEmpty || content.hasPrefix("#") { continue }
            if let comment = content.range(of: " #") { content = content[..<comment.lowerBound].trimmingCharacters(in: .whitespaces) }
            if indent == 0 { inEngine = content == "engine:"; inFilters = false; continue }
            guard inEngine else { continue }
            if indent == 2 { inFilters = content == "filters:"; continue }
            if inFilters, content.hasPrefix("- ") { filters.append(content.dropFirst(2).trimmingCharacters(in: .whitespaces)) }
        }
        return filters
    }
}

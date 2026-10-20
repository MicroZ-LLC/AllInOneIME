import Foundation

/// English words among pinyin's candidates (「英文词」), besides those of rime-ice's own English dictionary
/// (`EnglishDictionary`, its `melt_eng`, which librime offers itself): the user's (`Config.englishWords`, added in Settings
/// or learned from letters they put in as typed), the Latin terms of their jargon list, and product and technical words
/// rime-ice lacks (`curated`). `EnglishWordsEngine` puts those whose letters start with what is typed among librime's
/// candidates: nothing is deployed again for a word added, and every shell on the core has them.
public enum EnglishWords {
    /// What a word is typed as and matched by: its Latin letters and digits, lowercased ("Next.js" → "nextjs",
    /// "Hugging Face" → "huggingface").
    public static func key(_ word: String) -> String {
        String(word.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    /// The most words `Config.englishWords` keeps: beyond it, the oldest learned go first, then the oldest added
    /// (`capped`).
    public static let maxWords = 2000
    /// The longest word, in characters.
    public static let maxLength = 40
    /// The fewest letters typed before the longer words that start with them are offered: with fewer, too many do.
    public static let minPrefix = 3
    /// The longest letters typed as they are that are learned: anything longer is more likely a password or a key.
    public static let maxLearned = 24

    /// `text` as a word to offer, its spaces trimmed (one between two parts), or nil: Latin letters, digits and a few
    /// joiners (- . + & ' _ /), a letter first, two letters at least, at most `maxLength` characters.
    public static func word(_ text: String) -> String? {
        let trimmed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard (2...maxLength).contains(trimmed.count), let first = trimmed.first, first.isASCII, first.isLetter,
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || " -.+&'_/".contains($0)) }),
              key(trimmed).filter(\.isLetter).count >= 2 else { return nil }
        return trimmed
    }

    /// The words offered with these settings: the user's (`Config.englishWords`), their jargon list's Latin terms (those
    /// that don't look like a secret: `looksSecret`), then `curated`; each once (by `key`), as it is first spelled.
    public static func offered(_ config: Config, jargon: [JargonEntry]) -> [String] {
        let terms = jargon.map(\.term).filter { word($0) != nil && !looksSecret($0, hidden: []) }
        var seen = Set<String>()
        return (config.englishWords + terms + curated).compactMap(word).filter { seen.insert(key($0)).inserted }
    }

    // MARK: Learning

    /// Whether `typed`, letters the user put in as they are (`EnglishWordsEngine.rawCommitted`), is learned: Latin letters
    /// only, 3 to `maxLearned` of them, a word not offered already (`known`, by key) nor in rime-ice's dictionary, not
    /// pinyin (`Pinyin.isPinyin`: "nihao", "yyds"), with a vowel, and nothing like a secret (`looksSecret`, the user's
    /// hidden words included, anywhere in it).
    public static func learnable(_ typed: String, known: Set<String>, dictionary: EnglishDictionary, hidden: [String]) -> Bool {
        guard (3...maxLearned).contains(typed.count), typed.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        let k = key(typed)
        return !known.contains(k) && !dictionary.contains(k) && !Pinyin.isPinyin(k)
            && k.contains(where: { "aeiouy".contains($0) }) && !looksSecret(typed, hidden: hidden)
    }

    /// Remote desktops and virtual machines, by the beginning of their bundle ids (the Mac's): what is typed there goes to
    /// another computer, whose password fields this one can't tell (secure input stays off), so nothing is learned there.
    /// Microsoft's Remote Desktop (Windows App), Apple's Screen Sharing, Screens, Jump Desktop, Parallels Desktop (and the
    /// Windows apps it shows), VMware Fusion, UTM, VirtualBox, Citrix Workspace, AnyDesk, TeamViewer, RealVNC's viewer,
    /// Chrome Remote Desktop's app (in a browser's tab it goes by the browser's id, and can't be told).
    static let remoteApps = [
        "com.microsoft.rdc", "com.apple.screensharing", "com.edovia.screens", "com.p5sys.jump", "com.parallels.",
        "com.vmware.fusion", "com.utmapp.", "org.virtualbox.app.", "com.citrix.", "com.philandro.anydesk", "com.teamviewer.",
        "com.realvnc.", "com.google.chromeremotedesktop",
    ]

    /// Whether `app` (a bundle id, in any case) is a remote desktop or a virtual machine (`remoteApps`).
    public static func isRemote(_ app: String?) -> Bool {
        guard let app = app?.lowercased() else { return false }
        return remoteApps.contains { app.hasPrefix($0) }
    }

    /// What is never learned or taken from the jargon list: what hiding sensitive information would hide from the AI
    /// (`Redaction`, every detector on: a key or token, a card or phone number, an address; the user's hidden words too,
    /// anywhere in it, in any case, by their letters: "phoenixapi" for "Phoenix"), or what looks random (`looksRandom`).
    static func looksSecret(_ text: String, hidden: [String]) -> Bool {
        let letters = key(text)
        if hidden.contains(where: { let word = key($0); return !word.isEmpty && letters.contains(word) }) { return true }
        if !Redaction.find(text, settings: RedactionSettings(enabled: true, customWords: hidden)).isEmpty { return true }
        return Redaction.isKey(text) || looksRandom(text)
    }

    /// Whether `text` looks random: as many digits as letters (three or more), six consonants in a row, a letter three
    /// times in a row.
    static func looksRandom(_ text: String) -> Bool {
        let k = key(text)
        let digits = k.filter(\.isNumber).count
        if digits >= 3, digits * 2 >= k.count { return true }
        var consonants = 0, repeated = 1
        var previous: Character?
        for c in k {
            consonants = c.isLetter && !"aeiouy".contains(c) ? consonants + 1 : 0
            repeated = c == previous ? repeated + 1 : 1
            previous = c
            if consonants >= 6 || repeated >= 3 { return true }
        }
        return false
    }

    /// Letters put in as typed once, by their letters (`key`), the latest `limit`: the session learns a word the second
    /// time (`InputSession`), so a password typed once is never kept. In memory only, never written or synced: shared by
    /// the fields of one launch (`SessionServices.englishTypedOnce`), forgotten when the app quits. Main thread only, as
    /// the session.
    public final class TypedOnce: @unchecked Sendable {
        public static let limit = 200
        private var keys: [String] = []

        public init() {}

        /// Whether the letters of `typed` were put in before (forgotten then, as they are learned); else they are
        /// remembered.
        public func again(_ typed: String) -> Bool {
            let k = EnglishWords.key(typed)
            if let i = keys.firstIndex(of: k) {
                keys.remove(at: i)
                return true
            }
            keys.append(k)
            if keys.count > Self.limit { keys.removeFirst(keys.count - Self.limit) }
            return false
        }
    }

    /// `typed` learned into the config file at `url` (`Config.englishWords`): added at the end unless a word with its
    /// letters is there, within `maxWords` (`capped`, by the file's `addedEnglishWords`). Only that key of the file changes;
    /// a missing file is written with this Mac's new user's settings. Whether it was added.
    @discardableResult
    public static func learn(_ typed: String, at url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            var config = try Config.load(from: url)
            let list = learning(typed, into: config.englishWords, added: config.addedEnglishWords)
            guard list != config.englishWords else { return false }
            config.englishWords = list
            try config.write(to: url)
            return true
        }
        var added = false
        try AIConfig.patchingFile(at: url) { file in
            let list = file[Config.englishWordsKey]?.strings ?? []
            let new = learning(typed, into: list, added: file[Config.addedEnglishWordsKey]?.strings ?? [])
            guard new != list else { return }
            file[Config.englishWordsKey] = .array(new.map { .string($0) })
            added = true
        }
        return added
    }

    /// `list` with `typed` learned: at the end unless a word with its letters is there, within `maxWords`.
    static func learning(_ typed: String, into list: [String], added: [String]) -> [String] {
        let new = newWords(typed, besides: list)
        return new.isEmpty ? list : capped(list + new, added: added)
    }

    /// `list` within `maxWords`: beyond it the oldest learned words go first (those whose letters `added`, the words the
    /// user added, lacks), then the oldest added.
    public static func capped(_ list: [String], added: [String]) -> [String] {
        var excess = list.count - maxWords
        guard excess > 0 else { return list }
        let kept = Set(added.map(key))
        let out = list.filter { word in
            guard excess > 0, !kept.contains(key(word)) else { return true }
            excess -= 1
            return false
        }
        return Array(out.suffix(maxWords))
    }

    // MARK: The list in Settings

    /// The words of `text` (separated by commas, semicolons or lines: `RedactionSettings.words`) that are words (`word`)
    /// and whose letters neither `list` nor one before them has.
    static func newWords(_ text: String, besides list: [String]) -> [String] {
        var keys = Set(list.map(key))
        return RedactionSettings.words(from: text).compactMap(word).filter { keys.insert(key($0)).inserted }
    }

    /// What Settings' Add did.
    public struct Added: Equatable, Sendable {
        /// The words added.
        public var words: [String] = []
        /// Those refused: what hiding sensitive information hides (`isSensitive`).
        public var refused: [String] = []

        public init(words: [String] = [], refused: [String] = []) {
            self.words = words
            self.refused = refused
        }
    }

    /// Whether a word the user adds is refused: what hiding sensitive information hides from the AI (`Redaction`'s
    /// detectors: a key or token, a card or phone number, an IP or email address), as the list syncs through iCloud and
    /// shows on screen. Not the user's hidden words, nor what only looks random (`looksSecret`, for what is learned): the
    /// user added it.
    public static func isSensitive(_ word: String) -> Bool {
        !Redaction.find(word, settings: RedactionSettings(enabled: true)).isEmpty
    }

    /// Settings' Add: the words of `text` (`newWords`) added at the end of `config`'s English words and marked as the
    /// user's (`Config.addedEnglishWords`), within `maxWords` (`capped`: the oldest learned go first); those
    /// `isSensitive` refused.
    @discardableResult
    public static func add(_ text: String, to config: inout Config) -> Added {
        let found = newWords(text, besides: config.englishWords)
        let refused = found.filter(isSensitive)
        let new = found.filter { !isSensitive($0) }
        guard !new.isEmpty else { return Added(refused: refused) }
        let added = config.addedEnglishWords + new
        config.englishWords = capped(config.englishWords + new, added: added)
        // Each once, and only those the list still has.
        var keys = Set(config.englishWords.map(key))
        config.addedEnglishWords = added.filter { keys.remove(key($0)) != nil }
        return Added(words: new, refused: refused)
    }

    /// A word's ✕ in Settings: `word` gone from `config`'s English words (by its letters, as it is matched), added or
    /// learned.
    public static func remove(_ word: String, from config: inout Config) {
        config.englishWords = removing(word, from: config.englishWords)
        config.addedEnglishWords = removing(word, from: config.addedEnglishWords)
    }

    /// `list` without `word` (by its letters, as it is matched).
    public static func removing(_ word: String, from list: [String]) -> [String] {
        let k = key(word)
        return list.filter { key($0) != k }
    }
}

/// rime-ice's English dictionary (its `melt_eng`), the words its pinyin offers already, by their letters
/// (`EnglishWords.key`): an English word of the user's is offered only when it isn't one of them, and only one that isn't
/// is learned.
public struct EnglishDictionary: Sendable {
    private let keys: Set<String>

    public init(_ words: some Sequence<String>) {
        keys = Set(words.map(EnglishWords.key).filter { !$0.isEmpty })
    }

    public func contains(_ word: String) -> Bool { keys.contains(EnglishWords.key(word)) }
    public var count: Int { keys.count }

    /// The dictionary that imports the others, in a Rime data folder (the Chinese pack's).
    static let file = "melt_eng.dict.yaml"

    /// From a Rime data folder: the tables `melt_eng.dict.yaml` imports (`import_tables`), each entry's word and its code.
    /// Nil without them (no rime-ice there).
    public static func load(rimeData: URL) -> EnglishDictionary? {
        guard let data = try? Data(contentsOf: rimeData.appendingPathComponent(file)) else { return nil }
        var words: [String] = []
        for table in importedTables(String(decoding: data, as: UTF8.self)) {
            guard let table = try? Data(contentsOf: rimeData.appendingPathComponent(table + ".dict.yaml")) else { continue }
            words += entries(String(decoding: table, as: UTF8.self))
        }
        return words.isEmpty ? nil : EnglishDictionary(words)
    }

    /// The tables a dictionary's header imports: "  - en_dicts/en  # comment" under `import_tables:`.
    static func importedTables(_ text: String) -> [String] {
        var tables: [String] = [], inList = false
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "..." { break }
            if trimmed.hasPrefix("import_tables:") {
                inList = true
            } else if inList, trimmed.hasPrefix("- ") {
                let name = trimmed.dropFirst(2).split(separator: "#", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) ?? ""
                if !name.isEmpty, !name.contains("..") { tables.append(name) }
            } else if inList, !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                inList = false
            }
        }
        return tables
    }

    /// A Rime dictionary's entries (after its header, which ends at "..."): each one's word, and its code when it has one
    /// ("iPhone 17\tiPhone17"). Comments are left out.
    static func entries(_ text: String) -> [String] {
        var out: [String] = [], body = false
        for line in text.split(whereSeparator: \.isNewline) {
            if !body {
                body = line.trimmingCharacters(in: .whitespaces) == "..."
                continue
            }
            guard !line.hasPrefix("#") else { continue }
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            out.append(String(columns[0]))
            if columns.count > 1 { out.append(String(columns[1])) }
        }
        return out
    }
}

/// Mandarin pinyin as rime-ice reads it, for where an English word goes among its candidates (`EnglishWordsEngine`) and
/// what isn't learned as one.
enum Pinyin {
    /// The syllables: the system's list with those rime-ice spells and it lacks (这个 zhei, 得 dei, 忒 tei, 𰻞 biang; its
    /// character table's, which `EnglishWordsRimeTests` checks), without the interjections that are consonants alone (m,
    /// ng, hm; rime-ice's speller erases them): "mm" isn't two syllables.
    static let syllables = RedactionWords.pinyin.union(["biang", "cei", "dei", "nia", "tei", "zhei"]).subtracting(["m", "ng", "hm"])
    /// The spellings rime-ice's speller derives from a syllable (its `speller/algebra` in rime_ice.schema.yaml, in order;
    /// `EnglishWordsRimeTests` checks them): ü typed as u or v, and its corrections of letters typed in the wrong order
    /// ("hzi" and "zih" for zhi, "wie" for wei, "zhogn" for zhong) or left out ("do" for dou).
    static let algebra: [(pattern: String, template: String)] = [
        ("^([nl])ve$", "$1ue"), ("^([jqxy])u", "$1v"), ("^([nl])ue$", "$1ve"), ("^([jqxy])v", "$1u"),
        ("([zcs])h(a|e|i|u|ai|ei|an|en|ou|uo|ua|un|ui|uan|uai|uang|ang|eng|ong)$", "h$1$2"), ("([zcs])h([aeiu])$", "$1$2h"),
        ("^([wghk])ai$", "$1ia"), ("([wfghkz])ei$", "$1ie"), ("([jqx])ie$", "$1ei"), ("([rtypsdghklzcbnm])ao$", "$1oa"),
        ("([ypfm])ou$", "$1uo"), ("([wrtypsdfghklzcbnm])ang$", "$1nag"), ("([wrtypsdfghklzcbnm])ang$", "$1agn"),
        ("([wrtpsdfghklzcbnm])eng$", "$1neg"), ("([wrtpsdfghklzcbnm])eng$", "$1egn"), ("([qtypdjlxbnm])ing$", "$1nig"),
        ("([qtypdjlxbnm])ing$", "$1ign"), ("([rtysdghklzcn])ong$", "$1nog"), ("([rtysdghklzcn])ong$", "$1ogn"),
        ("([qtpdjlxbnm])iao$", "$1ioa"), ("([qtpdjlxbnm])iao$", "$1oia"), ("([rtsghkzc])ui$", "$1iu"), ("([qjlxnm])iu$", "$1ui"),
        ("([qjlxn])iang$", "$1aing"), ("([qjlxn])iang$", "$1inag"), ("([g|k|h|zh|sh])ua$", "$1au"), ("([g|h|k|zh|ch|sh])uai$", "$1aui"),
        ("([qrtysdghjklzxcn])uan$", "$1aun"), ("([nlyjqx])ue$", "$1eu"), ("([g|h|k|zh|ch|sh])uang$", "$1aung"),
        ("([g|h|k|zh|ch|sh])uang$", "$1uagn"), ("([g|h|k|zh|ch|sh])uang$", "$1unag"), ("([g|h|k|zh|ch|sh])uang$", "$1augn"),
        ("([jqx])iong$", "$1inog"), ("([jqx])iong$", "$1oing"), ("([jqx])iong$", "$1iogn"), ("([jqx])iong$", "$1oign"),
        // Letters left out: "do" for dou and dong, "lon" for long, "ten" for teng, "lng" for lang, leng, ling and long.
        ("([rtsdghkzc])o(u|ng)$", "$1o"), ("(.+)ong$", "$1on"), ("([tl])eng$", "$1en"), ("([qwrtypsdfghjklzxcbnm])([aeio])ng$", "$1ng"),
    ]
    /// The syllables as rime-ice's speller reads them: as spelled, and as its `algebra` derives them, each rule applied to
    /// what the ones before it gave.
    static let spellings: Set<String> = {
        var out = syllables
        for (pattern, template) in algebra {
            let regex = try! NSRegularExpression(pattern: pattern)
            for spelling in out {
                let range = NSRange(location: 0, length: (spelling as NSString).length)
                guard regex.firstMatch(in: spelling, range: range) != nil else { continue }
                out.insert(regex.stringByReplacingMatches(in: spelling, range: range, withTemplate: template))
            }
        }
        return out
    }()
    /// The longest spelling, in letters.
    private static let longest = spellings.map(\.count).max() ?? 6
    /// The initials a syllable can be typed as on its own (rime-ice's abbreviations: "llm" for 来了吗).
    static let initials: Set<String> = Set("b p m f d t n l g k h j q x zh ch sh r z c s y w".split(separator: " ").map(String.init))
    /// The beginnings of the spellings: what may end pinyin still being typed ("zhon").
    static let syllablePrefixes: Set<String> = Set(spellings.flatMap { spelling in
        (1...spelling.count).map { String(spelling.prefix($0)) }
    })

    /// Whether `letters` (lowercased) is pinyin: spellings only ("nihao", "xiaomi", "zheige", "zhogn"), or, up to four
    /// letters, spellings and initials ("rug" ru-g, "mac" ma-c, "llm"), which rime-ice takes for pinyin before an English
    /// word (its `reduce_english_filter`).
    static func isPinyin(_ letters: String) -> Bool {
        let s = Array(letters)
        return splits(s, allowing: { spellings.contains($0) })
            || s.count <= 4 && splits(s, allowing: { spellings.contains($0) || initials.contains($0) })
    }

    /// Whether `letters` is pinyin still being typed: pinyin (`isPinyin`), or spellings then the beginning of one
    /// ("zhongg", "openr" o-pen-r).
    static func isPinyinBeingTyped(_ letters: String) -> Bool {
        if isPinyin(letters) { return true }
        let s = Array(letters)
        return (0..<s.count).contains { cut in
            (cut == 0 || splits(Array(s[..<cut]), allowing: { spellings.contains($0) }))
                && syllablePrefixes.contains(String(s[cut...]))
        }
    }

    /// Whether `s` is a run of units `allowing` takes (each `longest` letters at most), with nothing left.
    private static func splits(_ s: [Character], allowing: (String) -> Bool) -> Bool {
        guard !s.isEmpty else { return false }
        var reachable = [Bool](repeating: false, count: s.count + 1)
        reachable[0] = true
        for start in 0..<s.count where reachable[start] {
            for length in 1...min(longest, s.count - start) where allowing(String(s[start..<(start + length)])) {
                reachable[start + length] = true
            }
        }
        return reachable[s.count]
    }
}

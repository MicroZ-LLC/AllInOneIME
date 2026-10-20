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

    /// The most words `Config.englishWords` keeps: beyond it, the oldest go first.
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
    /// hidden words included).
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
    /// (`Redaction`, every detector on: a key or token, a card or phone number, an address; the user's hidden words too),
    /// or what looks random: as many digits as letters (three or more), six consonants in a row, a letter three times in a
    /// row.
    static func looksSecret(_ text: String, hidden: [String]) -> Bool {
        if !Redaction.find(text, settings: RedactionSettings(enabled: true, customWords: hidden)).isEmpty { return true }
        if Redaction.isKey(text) { return true }
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

    /// `typed` learned into the config file at `url` (`Config.englishWords`): added at the end unless a word with its
    /// letters is there, the oldest going beyond `maxWords`. Only that key of the file changes; a missing file is
    /// written with this Mac's new user's settings. Whether it was added.
    @discardableResult
    public static func learn(_ typed: String, at url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            var config = try Config.load(from: url)
            let list = adding(typed, to: config.englishWords)
            guard list != config.englishWords else { return false }
            config.englishWords = list
            try config.write(to: url)
            return true
        }
        var added = false
        try AIConfig.patchingFile(at: url) { file in
            let list = file[Config.englishWordsKey]?.strings ?? []
            let new = adding(typed, to: list)
            guard new != list else { return }
            file[Config.englishWordsKey] = .array(new.map { .string($0) })
            added = true
        }
        return added
    }

    // MARK: The list in Settings

    /// `list` with the words of `text` (separated by commas, semicolons or lines: `RedactionSettings.words`) added at the
    /// end, each that is a word (`word`) and whose letters no word of the list has; the oldest go beyond `maxWords`.
    public static func adding(_ text: String, to list: [String]) -> [String] {
        var keys = Set(list.map(key))
        var out = list
        for part in RedactionSettings.words(from: text) {
            guard let word = word(part), keys.insert(key(word)).inserted else { continue }
            out.append(word)
        }
        return Array(out.suffix(maxWords))
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
    /// The syllables, without the interjections that are consonants alone (m, ng, hm): "mm" isn't two syllables.
    static let syllables = RedactionWords.pinyin.subtracting(["m", "ng", "hm"])
    /// The initials a syllable can be typed as on its own (rime-ice's abbreviations: "llm" for 来了吗).
    static let initials: Set<String> = Set("b p m f d t n l g k h j q x zh ch sh r z c s y w".split(separator: " ").map(String.init))
    /// The beginnings of the syllables: what may end pinyin still being typed ("zhon").
    static let syllablePrefixes: Set<String> = Set(syllables.flatMap { syllable in
        (1...syllable.count).map { String(syllable.prefix($0)) }
    })

    /// Whether `letters` (lowercased) is pinyin: syllables only ("nihao", "xiaomi"), or, up to four letters, syllables
    /// and initials ("rug" ru-g, "mac" ma-c, "llm"), which rime-ice takes for pinyin before an English word (its
    /// `reduce_english_filter`).
    static func isPinyin(_ letters: String) -> Bool {
        let s = Array(letters)
        return splits(s, allowing: { syllables.contains($0) })
            || s.count <= 4 && splits(s, allowing: { syllables.contains($0) || initials.contains($0) })
    }

    /// Whether `letters` is pinyin still being typed: pinyin (`isPinyin`), or syllables then the beginning of one
    /// ("zhongg", "openr" o-pen-r).
    static func isPinyinBeingTyped(_ letters: String) -> Bool {
        if isPinyin(letters) { return true }
        let s = Array(letters)
        return (0..<s.count).contains { cut in
            (cut == 0 || splits(Array(s[..<cut]), allowing: { syllables.contains($0) }))
                && syllablePrefixes.contains(String(s[cut...]))
        }
    }

    /// Whether `s` is a run of units `allowing` takes (each six letters at most), with nothing left.
    private static func splits(_ s: [Character], allowing: (String) -> Bool) -> Bool {
        guard !s.isEmpty else { return false }
        var reachable = [Bool](repeating: false, count: s.count + 1)
        reachable[0] = true
        for start in 0..<s.count where reachable[start] {
            for length in 1...min(6, s.count - start) where allowing(String(s[start..<(start + length)])) {
                reachable[start + length] = true
            }
        }
        return reachable[s.count]
    }
}

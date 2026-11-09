import Foundation

/// English words among pinyin's candidates (「英文词」), besides those of rime-ice's own English dictionary
/// (`EnglishDictionary`, its `melt_eng`, which librime offers itself): the user's (`Config.englishWords`, added in Settings
/// or learned from letters they put in as typed, or typed in English mode), the Latin terms of their jargon list, and product and technical words
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
    /// only, 3 to `maxLearned` of them, a word not offered already (`known`, by key) nor in rime-ice's dictionary, not one
    /// the user removed (`removed`, by key: `RemovedCandidates.keys`), not pinyin (`Pinyin.isPinyin`: "nihao", "yyds";
    /// with the user's fuzzy pinyin, `fuzzy`: "fongxian" with f ↔ h), with a vowel, and nothing like a secret
    /// (`looksSecret`, the user's hidden words included, anywhere in it).
    public static func learnable(_ typed: String, known: Set<String>, dictionary: EnglishDictionary, hidden: [String],
                                 fuzzy: [String] = [], removed: Set<String> = []) -> Bool {
        guard (3...maxLearned).contains(typed.count), typed.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        let k = key(typed)
        return !known.contains(k) && !dictionary.contains(k) && !removed.contains(k) && !Pinyin.isPinyin(k, fuzzy: fuzzy)
            && k.contains(where: { "aeiouy".contains($0) }) && !looksSecret(typed, hidden: hidden)
    }

    /// Remote desktops, virtual machines and SSH clients, by the beginning of their bundle ids (the Mac's, in small
    /// letters): what is typed there goes to another computer, whose password fields (and password prompts) this one can't
    /// tell (secure input stays off), so nothing is learned there. Microsoft's Remote Desktop (Windows App), Apple's Screen
    /// Sharing, Screens, Jump Desktop, Parallels Desktop (and the Windows apps it shows), VMware's (Fusion, Horizon) and
    /// Omnissa's Horizon, UTM, VirtualBox, Citrix Workspace, AnyDesk, TeamViewer, RealVNC's viewer, Chrome Remote Desktop's
    /// app (in a browser's tab it goes by the browser's id, and can't be told), Parsec, RustDesk, Splashtop, NoMachine,
    /// Amazon WorkSpaces; Termius, Royal TSX, Core Shell, SecureCRT, Prompt, Secure ShellFish (the terminals the shell knows
    /// are its own, `FieldInfo.terminal`). Their ids as Homebrew's casks, Apple's App Store lookup or the apps' own
    /// Info.plist give them (Prompt's as its iOS app's, which the Mac's shares). A terminal inside an editor (VS Code's,
    /// Cursor's, JetBrains') has the editor's id, and can't be told.
    static let remoteApps = [
        "com.microsoft.rdc", "com.apple.screensharing", "com.edovia.screens", "com.p5sys.jump", "com.parallels.",
        "com.vmware.", "com.omnissa.horizon", "com.utmapp.", "org.virtualbox.app.", "com.citrix.", "com.philandro.anydesk",
        "com.teamviewer.", "com.realvnc.", "com.google.chromeremotedesktop", "tv.parsec.", "com.carriez.rustdesk",
        "com.splashtop.", "com.nomachine.", "com.amazon.workspaces",
        "com.termius", "com.lemonmojo.royaltsx", "io.coressh.", "com.vandyke.securecrt", "com.panic.prompt",
        "com.appliedphasor.secure-shellfish",
    ]

    /// The same on Windows, by their program's file name (an app id "win:mstsc.exe", wire protocol §4): Remote Desktop
    /// Connection (mstsc), the Remote Desktop client and the session window of Azure Virtual Desktop and Windows App
    /// (msrdcw, msrdc), Hyper-V's VM window (vmconnect), VMware Workstation and Player, VirtualBox's VM window, Horizon's
    /// client (vmware-view; horizon-client since Omnissa's 8.14) and its session window (vmware-remotemks), Citrix's
    /// session window and Desktop Viewer (wfica32, cdviewer), AnyDesk, TeamViewer, RustDesk, Parsec (parsecd), Splashtop
    /// Business (strwinclt), NoMachine's player (nxplayer.exe, and the nxplayer.bin it ships beside it, its name on the
    /// Mac and Linux too), Amazon WorkSpaces, VNC viewers (RealVNC's, TigerVNC's, UltraVNC's vncviewer, TightVNC's
    /// tvnviewer), the remote desktop managers (Remote Desktop Connection Manager, Royal TS, mRemoteNG, Devolutions' Remote
    /// Desktop Manager, RemoteDesktopManager64 in its older versions); SSH clients the engine doesn't know as terminals
    /// (Termius, SecureCRT, Xshell, Bitvise's terminal, FinalShell, electerm).
    static let remotePrograms: Set<String> = [
        "mstsc.exe", "msrdc.exe", "msrdcw.exe", "vmconnect.exe", "vmware.exe", "vmplayer.exe", "virtualboxvm.exe",
        "vmware-view.exe", "horizon-client.exe", "vmware-remotemks.exe", "wfica32.exe", "cdviewer.exe", "anydesk.exe",
        "teamviewer.exe", "rustdesk.exe", "parsecd.exe", "strwinclt.exe", "nxplayer.exe", "nxplayer.bin", "workspaces.exe",
        "vncviewer.exe", "tvnviewer.exe", "rdcman.exe", "royalts.exe", "mremoteng.exe", "remotedesktopmanager.exe",
        "remotedesktopmanager64.exe",
        "termius.exe", "securecrt.exe", "xshell.exe", "bvterm.exe", "finalshell.exe", "electerm.exe",
    ]
    /// And packaged apps, by their package's name (an app id "win:<package>_<publisher>!<app>"): Microsoft's Remote
    /// Desktop app and Windows App.
    static let remotePackages = ["microsoft.remotedesktop_", "microsoftcorporationii.windows365_"]

    /// Whether `app` (a bundle id, or a Windows app id; in any case) is a remote desktop, a virtual machine or an SSH
    /// client (`remoteApps`, `remotePrograms`, `remotePackages`).
    public static func isRemote(_ app: String?) -> Bool {
        guard let app = app?.lowercased() else { return false }
        if app.hasPrefix("win:") {
            let id = String(app.dropFirst(4))
            return remotePrograms.contains(id) || remotePackages.contains { id.hasPrefix($0) }
        }
        return remoteApps.contains { app.hasPrefix($0) }
    }

    /// Whether letters put in as typed in `field` (`EnglishWordsEngine.rawCommitted`) are learned, as every shell learns
    /// them (`InputSession`, the Windows engine; words typed in English mode too, `learnsTypedInEnglish`): the second time (`typedOnce`; the first time they are only remembered,
    /// in memory) when they may be a word (`learnable`, not one of `offered` already). Never during secure input
    /// (`secureInput`; the session's is true also in a field not known to be no password field: the Mac without
    /// Accessibility learns nothing where secure input is off, `InputSession.fieldIsPrivate`) or in a password field
    /// (`FieldInfo.secure`), in a terminal (a password prompt of sudo's or ssh's
    /// doesn't turn secure input on in every one), in a remote desktop, a virtual machine or an SSH client (`isRemote`),
    /// in a password manager (`PasswordManagers`: a password shown in a plain field there), in an app with no AI, or with
    /// learning off (`Config.learnsEnglishWords`). Never one the user removed (`removed`, by key: the engine's
    /// `EnglishWordsEngine.removedKeys`). `config` is read only past those.
    public static func learns(_ typed: String, in field: FieldInfo, secureInput: Bool, config: () -> Config, offered: [String],
                              dictionary: EnglishDictionary, removed: @autoclosure () -> Set<String> = [],
                              typedOnce: TypedOnce) -> Bool {
        learns(typed, in: field, secureInput: secureInput, config: config, known: Set(offered.map(key)),
               dictionary: dictionary, removed: removed(), typedOnce: typedOnce)
    }

    /// `learns` with the words offered by their letters (`known`, made only past the field's checks: the session's are
    /// kept, `EnglishWordsEngine.keys`, not made again for each word).
    public static func learns(_ typed: String, in field: FieldInfo, secureInput: Bool, config: () -> Config,
                              known: @autoclosure () -> Set<String>, dictionary: EnglishDictionary,
                              removed: @autoclosure () -> Set<String> = [], typedOnce: TypedOnce) -> Bool {
        guard let config = learningConfig(in: field, secureInput: secureInput, config: config) else { return false }
        return !dictionary.contains(typed)  // most words typed in English mode: told before the words offered are gone through
            && learnable(typed, known: known(), dictionary: dictionary, hidden: config.redaction.customWords,
                         fuzzy: config.fuzzyPinyin, removed: removed())
            && typedOnce.again(typed)
    }

    /// Whether anything typed in `field` may be learned (`learns`, before what was typed is looked at): not during
    /// secure input or in a password field, a terminal, a remote desktop, a virtual machine, an SSH client or a
    /// password manager, in an app with AI, with learning on. What a session asks before it learns anything in a field.
    static func mayLearn(in field: FieldInfo, secureInput: Bool, config: () -> Config) -> Bool {
        learningConfig(in: field, secureInput: secureInput, config: config) != nil
    }

    /// The settings, where what is typed in `field` may be learned (`mayLearn`); `config` read only past what the field
    /// tells.
    private static func learningConfig(in field: FieldInfo, secureInput: Bool, config: () -> Config) -> Config? {
        guard !secureInput, !field.secure, !field.terminal, !isRemote(field.app), !PasswordManagers.contains(field.app) else {
            return nil
        }
        let config = config()
        return config.learnsEnglishWords && config.allowsAI(in: field.app) ? config : nil
    }

    /// Whether `typed`, learned in `app` while the settings were only the defaults (`Held`: their file didn't parse), is
    /// learned by the user's settings, `config`, read again: as `learns` has them, with learning on, in an app with AI,
    /// and still learnable with their words (`known`), hidden words, fuzzy pinyin and the candidates removed.
    static func allows(_ typed: String, in app: String?, config: Config, known: Set<String>, dictionary: EnglishDictionary,
                       removed: Set<String>) -> Bool {
        config.learnsEnglishWords && config.allowsAI(in: app)
            && learnable(typed, known: known, dictionary: dictionary, hidden: config.redaction.customWords,
                         fuzzy: config.fuzzyPinyin, removed: removed)
    }

    /// Whether a word typed in English mode (`EnglishModeWords`: letters that went straight to the app, between a space or
    /// a mark and a space, a mark or ⏎) is learned: by the rule letters put in as typed while typing pinyin are (`learns`:
    /// the second time, the first only remembered; never during secure input, in a password field, a terminal, a remote
    /// desktop, a virtual machine or an SSH client, a password manager, an app with no AI, with learning off; never
    /// pinyin, a word rime-ice or the user has, what looks like a secret or holds a hidden word), and never one with a
    /// capital first, which in prose is a name (a person's, a place's) or a sentence's first word: not even remembered.
    public static func learnsTypedInEnglish(_ typed: String, in field: FieldInfo, secureInput: Bool, config: () -> Config,
                                            offered: [String], dictionary: EnglishDictionary,
                                            removed: @autoclosure () -> Set<String> = [], typedOnce: TypedOnce) -> Bool {
        learnsTypedInEnglish(typed, in: field, secureInput: secureInput, config: config, known: Set(offered.map(key)),
                             dictionary: dictionary, removed: removed(), typedOnce: typedOnce)
    }

    /// `learnsTypedInEnglish` with the words offered by their letters (`learns(_:in:secureInput:config:known:…)`).
    public static func learnsTypedInEnglish(_ typed: String, in field: FieldInfo, secureInput: Bool, config: () -> Config,
                                            known: @autoclosure () -> Set<String>, dictionary: EnglishDictionary,
                                            removed: @autoclosure () -> Set<String> = [], typedOnce: TypedOnce) -> Bool {
        guard let first = typed.first, !first.isUppercase else { return false }
        return learns(typed, in: field, secureInput: secureInput, config: config, known: known(), dictionary: dictionary,
                      removed: removed(), typedOnce: typedOnce)
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
            keys.append(k, keepingLast: Self.limit)
            return false
        }
    }

    /// Words learned (`learns`) while the settings were only the defaults (their file doesn't parse: a comma left in an
    /// editor), each with the app it was typed in: neither offered nor written then, as the defaults aren't the user's
    /// settings (learning may be off there, the app one with no AI, the word one of their hidden words). Held until a
    /// session reads the user's settings again, which learns those they allow (`allows`) and forgets the rest; the latest
    /// `TypedOnce.limit`. In memory only, shared by the fields of one launch (`SessionServices.englishWordsHeld`),
    /// forgotten when the app quits. Main thread only, as the session.
    public final class Held: @unchecked Sendable {
        private var words: [(typed: String, app: String?)] = []

        public init() {}

        var isEmpty: Bool { words.isEmpty }

        func hold(_ typed: String, in app: String?) {
            words.append((typed, app), keepingLast: TypedOnce.limit)
        }

        /// Those held, oldest first, no longer held.
        func take() -> [(typed: String, app: String?)] {
            defer { words = [] }
            return words
        }
    }

    /// `typed` learned into the config file at `url` (`Config.englishWords`): added at the end unless a word with its
    /// letters is there or the user removed it (`Config.removedCandidates`, by its letters), within `maxWords` (`capped`,
    /// by the file's `addedEnglishWords`). Only that key of the file changes; a missing file is written with this Mac's
    /// new user's settings. Whether it was added.
    @discardableResult
    public static func learn(_ typed: String, at url: URL) throws -> Bool {
        try learn([typed], at: url)
    }

    /// `words` learned into the config file at `url` as `learn(_:at:)` learns one, each in turn, in one write of the file
    /// as it is now (under `AIConfig.fileLock`). Whether any was added.
    @discardableResult
    public static func learn(_ words: [String], at url: URL) throws -> Bool {
        try write(words.map(Change.learn), at: url)
    }

    /// What `Writer` writes into the config file.
    public enum Change: Equatable, Sendable {
        /// An English word learned (`learn(_:at:)`).
        case learn(String)
        /// A candidate the user removed (`RemovedCandidates.remove(_:at:)`): on the list of those removed, the English
        /// words as they are.
        case remove(String)
    }

    /// `changes` made to the config file at `url`, each in turn, in one write of the file as it is now (under
    /// `AIConfig.fileLock`): only the keys they change (`englishWords` for a word learned, `removedCandidates` for a
    /// candidate removed); a missing file is written with this Mac's new user's settings. Whether anything changed.
    @discardableResult
    public static func write(_ changes: [Change], at url: URL) throws -> Bool {
        AIConfig.fileLock.lock(); defer { AIConfig.fileLock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else {
            var config = try Config.load(from: url)
            let lists = Lists(words: config.englishWords, added: config.addedEnglishWords, removed: config.removedCandidates)
            let new = lists.with(changes)
            guard new != lists else { return false }
            (config.englishWords, config.removedCandidates) = (new.words, new.removed)
            try config.write(to: url)
            return true
        }
        var changed = false
        try AIConfig.patchingFile(at: url) { file in
            let lists = Lists(words: file[Config.englishWordsKey]?.strings ?? [],
                              added: file[Config.addedEnglishWordsKey]?.strings ?? [],
                              removed: file[Config.removedCandidatesKey]?.strings ?? [])
            let new = lists.with(changes)
            for (key, old, list) in [(Config.englishWordsKey, lists.words, new.words),
                                     (Config.removedCandidatesKey, lists.removed, new.removed)] where list != old {
                // An emptied list goes, as the config writes none.
                file[key] = list.isEmpty ? nil : .array(list.map { .string($0) })
                changed = true
            }
        }
        return changed
    }

    /// The lists of the config file `write` changes, and the words the user added (`added`: what a word learned is
    /// capped by).
    private struct Lists: Equatable {
        var words: [String]
        let added: [String]
        var removed: [String]

        /// With `changes` made, in turn.
        func with(_ changes: [Change]) -> Lists {
            var out = self
            for change in changes {
                switch change {
                case let .learn(typed):
                    // Never one removed meanwhile (in another field, on another Mac).
                    if RemovedCandidates.keys(out.removed).contains(key(typed)) { continue }
                    out.words = learning(typed, into: out.words, added: out.added)
                case let .remove(text):
                    out.removed = RemovedCandidates.adding(text, to: out.removed)
                }
            }
            return out
        }
    }

    /// English words learned and candidates removed written into the config file (`write`) off the caller's thread, so
    /// that a key's handling never waits for the file to be read, parsed and written: in order, on a queue of their own,
    /// those told meanwhile in one write, each into the file as it is then (what another writer changed stays, keys this
    /// version doesn't know too; under `AIConfig.fileLock`, so that no writer of this process writes between its read and
    /// its write). The session offers a word, and leaves out a candidate removed, at once (`EnglishWordsEngine.words`,
    /// `EnglishWordsEngine.removedCandidates`), and every field until it is written (`unwrittenRemovals`). A change whose
    /// write fails (a file that doesn't parse, one that can't be written) is kept and written with the next one, or once
    /// the shell says the file may take it again (`retry`), never tried again on its own; the process drains them before
    /// it ends (`drain`). Safe from any thread.
    public final class Writer: @unchecked Sendable {
        /// Told on the writer's queue once changes are in the file at a URL: what the shell may read there, off its thread.
        private let written: @Sendable (URL) -> Void
        /// The changes waiting to be written, and where.
        private let waiting = Locked<[(change: Change, url: URL)]>(initialState: [])
        /// The candidates removed not in their file yet (`unwrittenRemovals`), in order: waiting, being written, or kept.
        private let unwritten = Locked<[(candidate: String, url: URL)]>(initialState: [])
        /// Those whose write failed, in order, the latest `maxWords` and `RemovedCandidates.maxCount` at most: written
        /// before the next ones. On the queue only.
        private var kept: [(change: Change, url: URL)] = []
        private let queue = DispatchQueue(label: "com.allinoneime.english-words", qos: .utility)

        public init(written: @escaping @Sendable (URL) -> Void = { _ in }) {
            self.written = written
        }

        /// `typed` learned into the config file at `url` a moment later, with the changes told meanwhile (and those
        /// kept since their write failed).
        public func learn(_ typed: String, at url: URL) {
            add(.learn(typed), at: url)
        }

        /// `candidate` removed in the config file at `url` (`RemovedCandidates.remove(_:at:)`) a moment later, in order
        /// with the words learned.
        public func remove(_ candidate: String, at url: URL) {
            add(.remove(candidate), at: url)
        }

        /// The candidates removed (`remove`) not in the config file at `url` yet, oldest first: told and not written yet,
        /// or kept since their write failed. What every field's session leaves out besides the file's list, until it is
        /// written: the list's from then on (`RemovedCandidates.Given`). Asked just before the file is read, so that one
        /// written in between is in what is read; never waits for a write.
        public func unwrittenRemovals(at url: URL) -> [String] {
            unwritten.withLock { $0.filter { $0.url == url }.map(\.candidate) }
        }

        private func add(_ change: Change, at url: URL) {
            // Unwritten before it can be written.
            if case let .remove(candidate) = change { unwritten.withLock { $0.append((candidate, url)) } }
            let first = waiting.withLock { waiting -> Bool in
                defer { waiting.append((change, url)) }
                return waiting.isEmpty
            }
            if first { queue.async { self.write() } }
        }

        /// The changes kept since their write failed written again, a moment later: what the shell calls once it reads the
        /// file anew and it parses (fixed in an editor, say). Nothing when none is kept.
        public func retry() {
            queue.async { if !self.kept.isEmpty { self.write() } }
        }

        /// Waits until the changes told so far are in the file (a self-test reads it then). Never under
        /// `AIConfig.fileLock`.
        public func flush() {
            queue.sync { write() }
        }

        /// Waits `seconds` at most for the changes told so far to be in the file, those kept since their write failed
        /// tried once more: what the process does before it ends. Whether they all went in. Never under
        /// `AIConfig.fileLock`.
        @discardableResult
        public func drain(within seconds: TimeInterval) -> Bool {
            let done = Locked(initialState: false), finished = DispatchSemaphore(value: 0)
            queue.async {
                self.write()
                done.withLock { $0 = self.kept.isEmpty }
                finished.signal()
            }
            return finished.wait(timeout: .now() + seconds) == .success && done.withLock { $0 }
        }

        /// The changes kept, then those waiting, written on the queue: one write for each file, in turn; those of a write
        /// that fails kept for the next.
        private func write() {
            let changes = kept + waiting.withLock { waiting -> [(change: Change, url: URL)] in
                defer { waiting = [] }
                return waiting
            }
            kept = []
            var start = changes.startIndex
            while start < changes.endIndex {
                let url = changes[start].url
                let end = changes[start...].firstIndex { $0.url != url } ?? changes.endIndex
                do {
                    if try EnglishWords.write(changes[start..<end].map(\.change), at: url) { written(url) }
                    settled(changes[start..<end])
                } catch {
                    kept += changes[start..<end]
                    EnglishWords.log.error("could not keep an English word or a removed candidate yet, kept to try again (\(String(describing: type(of: error))))")
                }
                start = end
            }
            let most = EnglishWords.maxWords + RemovedCandidates.maxCount
            if kept.count > most {
                settled(kept.prefix(kept.count - most))  // lost: never written
                kept.removeFirst(kept.count - most)
            }
        }

        /// The candidates removed among `changes` no longer unwritten: in their file now, or given up.
        private func settled(_ changes: ArraySlice<(change: Change, url: URL)>) {
            unwritten.withLock { unwritten in
                for (change, url) in changes {
                    guard case let .remove(candidate) = change,
                          let at = unwritten.firstIndex(where: { $0.candidate == candidate && $0.url == url })
                    else { continue }
                    unwritten.remove(at: at)
                }
            }
        }
    }

    static let log = CoreLog(subsystem: "com.allinoneime.inputmethod.AllInOneIME", category: "ime")

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

    /// `list` with the words of `added` it lacks (by their letters) at the end, within `maxWords` (`capped`): every word
    /// the user added is offered, also when the list came from a Mac that hadn't seen it added (iCloud sync).
    public static func withAdded(_ list: [String], added: [String]) -> [String] {
        var keys = Set(list.map(key))
        return capped(list + added.filter { keys.insert(key($0)).inserted }, added: added)
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

    /// Settings' Add: the words of `text` the user hasn't added yet (`newWords`) added at the end of `config`'s English
    /// words and marked as the user's (`Config.addedEnglishWords`), within `maxWords` (`capped`: the oldest learned go
    /// first); those `isSensitive` refused. One learned already becomes the user's, as written now: as if removed and
    /// added again; one of theirs removed among the candidates is added again the same way. Each added comes off the
    /// list of those removed (`Config.removedCandidates`, by its letters: `RemovedCandidates.restoring(words:from:)`), so
    /// that it comes up as the user asked.
    @discardableResult
    public static func add(_ text: String, to config: inout Config) -> Added {
        let removed = RemovedCandidates.keys(config.removedCandidates)
        let found = newWords(text, besides: config.addedEnglishWords.filter { !removed.contains(key($0)) })
        let refused = found.filter(isSensitive)
        let new = found.filter { !isSensitive($0) }
        guard !new.isEmpty else { return Added(refused: refused) }
        let marked = Set(new.map(key))
        let added = config.addedEnglishWords.filter { !marked.contains(key($0)) } + new
        config.englishWords = capped(config.englishWords.filter { !marked.contains(key($0)) } + new, added: added)
        // Each once, and only those the list still has.
        var keys = Set(config.englishWords.map(key))
        config.addedEnglishWords = added.filter { keys.remove(key($0)) != nil }
        config.removedCandidates = RemovedCandidates.restoring(words: new, from: config.removedCandidates)
        return Added(words: new, refused: refused)
    }

    /// Why a settings window's list wasn't taken (`edit`).
    public enum Refusal: Equatable, Sendable {
        /// A word typed in isn't one (`word`).
        case notAWord
        /// A word typed in is what hiding sensitive information hides (`isSensitive`).
        case sensitive
    }

    /// A settings window's list of the user's English words, in any order (Windows' Settings app: the words as one line):
    /// those of `config`'s English words whose letters it lacks removed, added or learned (`remove`), and its words whose
    /// letters `config`'s lack added as Settings' Add adds them (`add`: the user's). Nothing changes when a word added
    /// isn't one or is refused (`isSensitive`): why. A word only spelled another way stays as it was.
    public static func edit(_ config: inout Config, to list: [String]) -> Refusal? {
        let had = Set(config.englishWords.map(key))
        let typed = list.filter { !had.contains(key($0)) }
        let words = typed.compactMap(word)
        if words.contains(where: isSensitive) { return .sensitive }
        if words.count < typed.count { return .notAWord }
        let kept = Set(list.map(key))
        for word in config.englishWords where !kept.contains(key(word)) { remove(word, from: &config) }
        if !words.isEmpty { add(words.joined(separator: ", "), to: &config) }
        return nil
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
    /// character table's, which `EnglishWordsRimeTests` checks), without those its speller erases (`erased`): "mm" isn't
    /// two syllables.
    static let syllables = RedactionWords.pinyin.union(["biang", "cei", "dei", "nia", "tei", "zhei"]).subtracting(erased)
    /// The interjections that are consonants alone, which rime-ice's speller erases (`erase/^hm$/` …).
    static let erased: Set<String> = ["hm", "m", "n", "ng"]
    /// rime-ice's abbreviations (`abbrev/^([a-z]).+$/$1/`: a syllable typed as its first letter, zh ch sh whole), which
    /// `initials` reads. Its speller has no rules but these, `erased` and `algebra` (`EnglishWordsRimeTests` checks).
    static let abbreviations: [(pattern: String, template: String)] = [("^([a-z]).+$", "$1"), ("^([zcs]h).+$", "$1")]
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
    /// The initials a syllable can be typed as on its own (rime-ice's abbreviations: "llm" for 来了吗).
    static let initials: Set<String> = Set("b p m f d t n l g k h j q x zh ch sh r z c s y w".split(separator: " ").map(String.init))

    /// How rime-ice's speller reads pinyin with the user's fuzzy pinyin (`Config.fuzzyPinyin`, `FuzzyPinyin`): the
    /// syllables as spelled, and as its rules derive them, each rule applied to what the ones before it gave: the fuzzy
    /// pairs' first, then rime-ice's own (`algebra`), as `FuzzyPinyin.patch` puts them.
    struct Reading: Sendable {
        let spellings: Set<String>
        /// The beginnings of the spellings: what may end pinyin still being typed ("zhon").
        let prefixes: Set<String>
        /// The longest spelling, in letters.
        let longest: Int

        init(fuzzy: [String]) {
            var out = Pinyin.syllables
            for (pattern, template) in FuzzyPinyin.derivations(fuzzy) + Pinyin.algebra {
                let regex = try! NSRegularExpression(pattern: pattern)
                for spelling in out {
                    let range = NSRange(location: 0, length: (spelling as NSString).length)
                    guard regex.firstMatch(in: spelling, range: range) != nil else { continue }
                    out.insert(regex.stringByReplacingMatches(in: spelling, range: range, withTemplate: template))
                }
            }
            spellings = out
            prefixes = Set(out.flatMap { spelling in (1...spelling.count).map { String(spelling.prefix($0)) } })
            longest = out.map(\.count).max() ?? 6
        }
    }

    /// The reading for the fuzzy pairs `fuzzy` (ids; those not known left out), made once for each set of them.
    static func reading(fuzzy: [String]) -> Reading {
        let pairs = FuzzyPinyin.known(fuzzy)
        if let made = readings.withLock({ $0[pairs] }) { return made }
        let made = Reading(fuzzy: pairs)
        readings.withLock { $0[pairs] = made }
        return made
    }
    private static let readings = Locked<[[String]: Reading]>(initialState: [:])

    /// The syllables as rime-ice's speller reads them, without fuzzy pinyin.
    static var spellings: Set<String> { reading(fuzzy: []).spellings }

    /// Whether `letters` (lowercased) is pinyin, with the fuzzy pairs `fuzzy`: spellings only ("nihao", "xiaomi",
    /// "zheige", "zhogn"), or, up to four letters, spellings and initials ("rug" ru-g, "mac" ma-c, "llm"), which rime-ice
    /// takes for pinyin before an English word (its `reduce_english_filter`).
    static func isPinyin(_ letters: String, fuzzy: [String] = []) -> Bool {
        let reading = reading(fuzzy: fuzzy)
        let s = Array(letters)
        return splits(s, reading, allowing: { reading.spellings.contains($0) })
            || s.count <= 4 && splits(s, reading, allowing: { reading.spellings.contains($0) || initials.contains($0) })
    }

    /// Whether `letters` is pinyin still being typed: pinyin (`isPinyin`), or spellings then the beginning of one
    /// (`endsInASpellingBegun`).
    static func isPinyinBeingTyped(_ letters: String, fuzzy: [String] = []) -> Bool {
        isPinyin(letters, fuzzy: fuzzy) || endsInASpellingBegun(letters, fuzzy: fuzzy)
    }

    /// Whether `letters` is spellings, or none, then the beginning of one ("zhongg", "openr" o-pen-r, "zhon"): what
    /// `isPinyinBeingTyped` adds to `isPinyin`, for a caller that has asked that already.
    static func endsInASpellingBegun(_ letters: String, fuzzy: [String] = []) -> Bool {
        let reading = reading(fuzzy: fuzzy)
        let s = Array(letters)
        return (0..<s.count).contains { cut in
            (cut == 0 || splits(Array(s[..<cut]), reading, allowing: { reading.spellings.contains($0) }))
                && reading.prefixes.contains(String(s[cut...]))
        }
    }

    /// Whether `s` is a run of units `allowing` takes (each the reading's longest spelling at most), with nothing left.
    private static func splits(_ s: [Character], _ reading: Reading, allowing: (String) -> Bool) -> Bool {
        guard !s.isEmpty else { return false }
        var reachable = [Bool](repeating: false, count: s.count + 1)
        reachable[0] = true
        for start in 0..<s.count where reachable[start] {
            for length in 1...min(reading.longest, s.count - start) where allowing(String(s[start..<(start + length)])) {
                reachable[start + length] = true
            }
        }
        return reachable[s.count]
    }
}

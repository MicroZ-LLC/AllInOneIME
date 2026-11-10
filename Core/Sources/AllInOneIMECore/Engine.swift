import Foundation

/// One entry of the pinyin engine's candidate menu.
public struct EngineCandidate: Equatable, Sendable {
    public var label: String
    public var text: String
    public var comment: String

    public init(label: String, text: String, comment: String = "") {
        self.label = label
        self.text = text
        self.comment = comment
    }
}

/// What the level-one engine currently shows.
public struct EngineSnapshot: Equatable, Sendable {
    /// True while the engine holds input that has not been committed.
    public var isComposing: Bool
    /// Inline composition text, e.g. "我今天 you dian".
    public var preedit: String
    /// Caret position in `preedit`, in Characters.
    public var cursor: Int
    /// Candidates on the current page.
    public var candidates: [EngineCandidate]
    public var highlighted: Int
    public var pageNumber: Int
    public var isLastPage: Bool
    /// Latin mode: the engine lets letters through to the application.
    public var isAsciiMode: Bool

    public init(
        isComposing: Bool = false, preedit: String = "", cursor: Int = 0,
        candidates: [EngineCandidate] = [], highlighted: Int = 0,
        pageNumber: Int = 0, isLastPage: Bool = true, isAsciiMode: Bool = false
    ) {
        self.isComposing = isComposing
        self.preedit = preedit
        self.cursor = cursor
        self.candidates = candidates
        self.highlighted = highlighted
        self.pageNumber = pageNumber
        self.isLastPage = isLastPage
        self.isAsciiMode = isAsciiMode
    }

    public static let empty = EngineSnapshot()
}

/// Level one: a local pinyin engine (librime in the app, a fake in tests). Main thread only.
public protocol PinyinEngine: AnyObject {
    /// Feeds one key as an X11 keysym plus modifier mask (see `RimeKey`). Returns true if consumed.
    func processKey(_ keycode: Int32, mask: Int32) -> Bool
    /// Text the engine committed since the last call, if any.
    func takeCommit() -> String?
    func snapshot() -> EngineSnapshot
    /// Selects a candidate on the current page (mouse click). Returns true if it was selected.
    func selectCandidate(onPage index: Int) -> Bool
    /// Deletes a candidate on the current page (a right-click, ⌃⌦): what the engine learned of it is forgotten. One made
    /// from a word and put beside it (an emoji: 👏 after 鼓掌) isn't deleted, the word stays as it was. Returns true if it
    /// was one the engine could delete.
    func deleteCandidate(onPage index: Int) -> Bool
    /// The candidates the user removed (`EnglishWordsEngine.removedCandidates`), by their text as shown: an engine that
    /// can leave them out itself does (librime, with AllInOneIME's filter: `RemovedCandidates.property`), its pages laid
    /// out from what is left, each full.
    func setRemovedCandidates(_ texts: [String])
    /// Commits the current composition as converted text and returns it.
    func commitComposition() -> String?
    /// The typed letters of the current composition.
    var rawInput: String { get }
    func clearComposition()
    func setAsciiMode(_ on: Bool)
    /// The language it types when not in its ASCII mode: Chinese (librime), Hindi (`HindiEngine`).
    var language: Language { get }
    /// Types with the schema `id` from the next key on (librime's: "rime_ice" for full pinyin, "double_pinyin_flypy"
    /// for Xiaohe's Shuangpin: `PinyinScheme.schema`), what is composed dropped. False when it can't (the schema isn't
    /// deployed): it types as before.
    func selectSchema(_ id: String) -> Bool
}

extension PinyinEngine {
    public var language: Language { .chinese }
    /// An engine that learns nothing has nothing to forget.
    public func deleteCandidate(onPage index: Int) -> Bool { false }
    /// One that can't leaves it to `EnglishWordsEngine`, which leaves them out of what it shows.
    public func setRemovedCandidates(_ texts: [String]) {}
    /// An engine with one way of typing has no schema to change to.
    public func selectSchema(_ id: String) -> Bool { false }
}

extension String {
    /// True if the text contains CJK ideographs (i.e. it is Chinese text, not just symbols).
    public var containsHan: Bool {
        unicodeScalars.contains { $0.properties.isIdeographic }
    }

    /// The text without punctuation, whitespace and case: two strings with the same key say the
    /// same thing in the same words (e.g. "我今天有点不舒服" and "我今天有点不舒服。").
    public var wordingKey: String {
        var scalars = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            switch scalar.properties.generalCategory {
            case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                 .initialPunctuation, .finalPunctuation, .otherPunctuation,
                 .spaceSeparator, .lineSeparator, .paragraphSeparator, .control, .format:
                continue
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars).lowercased()
    }
}

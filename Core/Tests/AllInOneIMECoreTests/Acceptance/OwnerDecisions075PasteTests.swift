import CoreGraphics
import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Owner decisions 2026-11-14 (0.7.5), part 3: a multi-line paste into a command's draft (⌘V/⌃V, clipboard history) is
/// joined into one line (`Composer.oneLine`); Korean (Hangul syllables and jamo) gets one space between two lines, as
/// English does; Chinese and Japanese (kanji, kana, full-width punctuation) stay joined without one. The same rule for the
/// lines of one message read from a screenshot (`ScreenText`). Written from the spec by a separate agent; the implementer
/// doesn't edit it (AGENTS.md rule 11).
@Suite(.serialized)
struct OwnerDecisions075PasteTests {
    /// (the lines, the one line they make).
    static let korean: [(String, String)] = [
        ("한국어\n문장", "한국어 문장"),
        ("안녕하세요.\n반갑습니다", "안녕하세요. 반갑습니다"),
        ("오늘은\n날씨가 좋네요", "오늘은 날씨가 좋네요"),
        ("ㅋㅋ\nㅎㅎ", "ㅋㅋ ㅎㅎ"),
    ]
    static let mixed: [(String, String)] = [
        ("日本語の文\n한국어", "日本語の文 한국어"),
        ("한국어\n中文", "한국어 中文"),
        ("中文\n한국어", "中文 한국어"),
    ]
    /// Unchanged: Chinese and Japanese lines without a space, English with one.
    static let unchanged: [(String, String)] = [
        ("第一行\n第二行", "第一行第二行"),
        ("日本語\nの文", "日本語の文"),
        ("你好，\n世界", "你好，世界"),
        ("カタカナ\nひらがな", "カタカナひらがな"),
        ("first line\nsecond", "first line second"),
        ("第一行\nhello", "第一行 hello"),
    ]

    // MARK: - Composer.oneLine

    @Test func koreanLinesAreJoinedWithASpace() {
        for (lines, joined) in Self.korean {
            #expect(Composer.oneLine(lines) == joined, "\(lines.debugDescription) → \(Composer.oneLine(lines).debugDescription)")
        }
    }

    @Test func koreanNextToChineseOrJapaneseGetsASpace() {
        for (lines, joined) in Self.mixed {
            #expect(Composer.oneLine(lines) == joined, "\(lines.debugDescription) → \(Composer.oneLine(lines).debugDescription)")
        }
    }

    @Test func chineseAndJapaneseLinesStayJoinedWithoutASpace() {
        for (lines, joined) in Self.unchanged {
            #expect(Composer.oneLine(lines) == joined, "\(lines.debugDescription) → \(Composer.oneLine(lines).debugDescription)")
        }
    }

    // MARK: - A screenshot's message lines

    /// Two lines of one message (`ChatTranscript.join`, in ScreenText.swift) follow the same rule.
    @Test func aMessagesLinesFollowTheSameRule() {
        let pairs: [(String, String, String)] = [
            ("한국어", "문장", "한국어 문장"), ("안녕하세요.", "반갑습니다", "안녕하세요. 반갑습니다"),
            ("日本語の文", "한국어", "日本語の文 한국어"), ("한국어", "中文", "한국어 中文"),
            ("第一行", "第二行", "第一行第二行"), ("日本語", "の文", "日本語の文"), ("first", "second", "first second"),
        ]
        for (first, second, joined) in pairs {
            #expect(ChatTranscript.join(first, second) == joined, "\(first) + \(second) → \(ChatTranscript.join(first, second))")
        }
    }

    /// Read from a screenshot: two lines of the other party's bubble, close together on the left, are one message.
    @Test func aScreenshotsKoreanMessageReadsWithASpace() {
        func message(_ first: String, _ second: String) -> String {
            let lines = [
                RecognizedLine(text: first, box: CGRect(x: 0.05, y: 0.10, width: 0.4, height: 0.03), confidence: 0.9),
                RecognizedLine(text: second, box: CGRect(x: 0.05, y: 0.135, width: 0.4, height: 0.03), confidence: 0.9),
            ]
            return ScreenText(lines: lines).text
        }
        #expect(message("한국어", "문장") == "한국어 문장", "\(message("한국어", "문장"))")
        #expect(message("第一行", "第二行") == "第一行第二行", "\(message("第一行", "第二行"))")
        #expect(message("日本語", "の文") == "日本語の文", "\(message("日本語", "の文"))")
    }

    // MARK: - Pasted into a command's draft

    /// A field whose clipboard holds `clipboard` (clipboard history kept with `items`, or not kept: ⌃V as before it),
    /// letters typed as they are, "@improve " written.
    func improveDraft(clipboard: String, history items: [String]? = nil) -> FakeHost {
        let composer = Composer()
        composer.setInputMode(.english)
        let host = FakeHost(services: SessionServices(loadSettings: { .default }), composer: composer)
        host.clipboard = .text(clipboard)
        host.clipboardNow = Date(timeIntervalSince1970: 1_000_000)
        if let items {
            host.clipboardHistory = items.enumerated().map { index, text in
                ClipboardHistoryItem(text: text, copiedAt: host.clipboardNow.addingTimeInterval(-Double(index + 1) * 60))
            }
            host.keepClipboardHistory()
        }
        host.focus()
        host.type("@improve ")
        #expect(host.composer.draft == "@improve ", "\(host.composer.draft)")
        return host
    }

    /// ⌃V without clipboard history: the clipboard's lines in the draft as one line.
    @Test func controlVPastesKoreanLinesWithASpace() async {
        await withInterfaceLanguage("en") {
            for (lines, joined) in Self.korean + Self.mixed + Self.unchanged {
                let host = improveDraft(clipboard: lines)
                host.press(FakeHost.controlV)
                #expect(host.composer.draft == "@improve " + joined, "\(lines.debugDescription) → \(host.composer.draft)")
            }
        }
    }

    /// Clipboard history's row picked in a command: pasted as ⌃V pastes.
    @Test func clipboardHistoryPastesKoreanLinesWithASpace() async {
        await withInterfaceLanguage("en") {
            for (lines, joined) in [("한국어\n문장", "한국어 문장"), ("第一行\n第二行", "第一行第二行")] {
                let host = improveDraft(clipboard: lines, history: [lines])
                host.press(FakeHost.controlV)
                #expect(host.panel?.highlighted == 0, "\(String(describing: host.panel?.rows.map(\.text)))")
                host.press(FakeHost.enter)
                #expect(host.composer.draft == "@improve " + joined, "\(lines.debugDescription) → \(host.composer.draft)")
            }
        }
    }
}

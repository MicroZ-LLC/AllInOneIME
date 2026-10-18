import Foundation

/// The text of a screenshot pasted into a draft (⌃V with an image on the clipboard), read on the device
/// (`Platform.current.text`): the image never leaves it, and isn't kept once read. `@reply` takes it as the conversation
/// it answers (`transcript`: who said what); every other command takes its text (`text`): the AI's as context or as the
/// text to work on, the others pasted, as clipboard text would be.
public struct ScreenText: Equatable, Sendable {
    /// What was read, as a conversation: the lines top to bottom, a message's lines joined, times dropped.
    public var transcript: ChatTranscript

    public init(transcript: ChatTranscript) {
        self.transcript = transcript
    }

    public init(lines: [RecognizedLine]) {
        transcript = ChatTranscript.make(lines: lines)
    }

    /// Its text, a message a line, without speakers.
    public var text: String { transcript.plainText }

    /// How many lines it has (`text`'s).
    public var lineCount: Int { transcript.messages.count }

    /// Why nothing was read.
    public enum Problem: Error, Equatable, Sendable {
        /// This device can't read text in images (`UnsupportedTextRecognizer`).
        case unsupported
        /// None was found in it.
        case noText
        /// The recognizer took longer than `ScreenText.timeout`.
        case timedOut
    }

    /// The longest a screenshot is read for (Vision's first load takes ~17 s).
    public static let timeout: TimeInterval = 20

    /// The lines read with too little confidence to be text (an icon, a photo's texture).
    static let minimumConfidence = 0.2

    /// The text of `image` (PNG or TIFF data), read by `recognizer` in `languages` (`languages(_:)`), for at most
    /// `timeout` seconds. Throws `Problem` (or the recognizer's own error).
    public static func recognize(_ image: Data, with recognizer: any TextRecognizer, languages: [String],
                                 timeout: TimeInterval = ScreenText.timeout) async throws -> ScreenText {
        let lines = try await firstOf(seconds: timeout) { try await recognizer.recognize(image: image, languages: languages) }
        let kept = lines.filter { $0.confidence >= minimumConfidence && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !kept.isEmpty else { throw Problem.noText }
        let text = ScreenText(lines: kept)
        guard !text.transcript.messages.isEmpty else { throw Problem.noText }
        return text
    }

    /// `work`'s result, or `Problem.timedOut` once `seconds` have gone by first (the work, which may not stop when
    /// cancelled, is then left to end on its own).
    static func firstOf<T: Sendable>(seconds: TimeInterval, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let resumed = Locked(initialState: false)
        let timer = Locked<Task<Void, Never>?>(initialState: nil)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            @Sendable func finish(_ result: Result<T, Error>) {
                guard resumed.withLock({ done in
                    if done { return false }
                    done = true
                    return true
                }) else { return }
                timer.withLock { $0?.cancel() }
                continuation.resume(with: result)
            }
            let task = Task {
                do { finish(.success(try await work())) } catch { finish(.failure(error)) }
            }
            let clock = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                task.cancel()
                finish(.failure(Problem.timedOut))
            }
            timer.withLock { $0 = clock }
            if resumed.withLock({ $0 }) { clock.cancel() }
        }
    }

    /// The recognizer's languages for `config`, the likeliest first: Simplified Chinese first when Chinese is typed or
    /// written into, then the input and output languages, and English always.
    public static func languages(_ config: Config) -> [String] {
        let chinese = config.inputLanguages.contains(.chinese) || config.outputLanguages.contains { $0.code.hasPrefix("zh") }
        var codes: [String] = chinese ? ["zh-Hans"] : []
        codes += config.inputLanguages.map { recognizerCode(OutputLanguage($0)) }
        codes += config.outputLanguages.map(recognizerCode)
        codes.append("en-US")
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }

    /// An output language's code as recognizers name it ("en" → "en-US", "ja" → "ja-JP").
    static func recognizerCode(_ language: OutputLanguage) -> String {
        let table = ["en": "en-US", "zh": "zh-Hans", "zh-Hant": "zh-Hant", "ja": "ja-JP", "ko": "ko-KR", "fr": "fr-FR",
                     "de": "de-DE", "es": "es-ES", "pt": "pt-BR", "it": "it-IT", "ru": "ru-RU", "vi": "vi-VT", "th": "th-TH",
                     "id": "id-ID", "ar": "ar-SA", "hi": "hi-IN"]
        return table[language.code] ?? language.code
    }
}

/// A screenshot's lines as a conversation (`make`): top to bottom, a message's lines joined, the times between messages
/// dropped, and the speakers told apart by side where both are there: the other party's bubbles on the left (`them`),
/// the user's own on the right (`me`), as chat apps lay them out.
public struct ChatTranscript: Equatable, Sendable {
    public enum Speaker: String, Equatable, Sendable {
        case them, me, unknown
    }

    public struct Message: Equatable, Sendable {
        public var speaker: Speaker
        public var text: String

        public init(speaker: Speaker, text: String) {
            self.speaker = speaker
            self.text = text
        }
    }

    public var messages: [Message]
    /// Both sides have a message: the speakers are named (`text`). Otherwise all is one side, which can't be told from
    /// the other (a document, Slack's layout), and nothing is labelled.
    public var labelled: Bool

    public init(messages: [Message], labelled: Bool) {
        self.messages = messages
        self.labelled = labelled
    }

    /// Each message on a line, "them: …" or "me: …" when `labelled`.
    public var text: String { render(messages) }

    /// Each message on a line, without speakers.
    public var plainText: String { messages.map(\.text).joined(separator: "\n") }

    /// The last messages of the other party, oldest first (all of them when the transcript isn't labelled).
    public func last(_ count: Int, of speaker: Speaker = .them) -> [String] {
        Array(messages.filter { !labelled || $0.speaker == speaker }.suffix(count).map(\.text))
    }

    /// `text`, keeping the last messages that fit in `limit` characters (a single message too long for it: its end).
    public func text(limit: Int) -> String {
        var kept: [Message] = []
        var total = 0
        for message in messages.reversed() {
            let line = render([message])
            let added = line.count + (kept.isEmpty ? 0 : 1)
            if total + added > limit {
                if kept.isEmpty { return String(line.suffix(limit)) }
                break
            }
            kept.insert(message, at: 0)
            total += added
        }
        return render(kept)
    }

    private func render(_ messages: [Message]) -> String {
        messages.map { message in
            labelled && message.speaker != .unknown ? message.speaker.rawValue + ": " + message.text : message.text
        }.joined(separator: "\n")
    }

    /// The conversation in `lines` (boxes 0…1, top-left origin): sorted top to bottom; a line on the left (`minX` < 0.30,
    /// `midX` < 0.5) is the other party's, one on the right (`maxX` > 0.70, `midX` > 0.5) the user's; lines of a side
    /// less than 1.2 line heights apart are one message; short centred lines that are times ("14:32", "昨天 09:10",
    /// "Yesterday") are dropped. Speakers are named only when both sides have a message.
    public static func make(lines: [RecognizedLine]) -> ChatTranscript {
        let sorted = lines.sorted { $0.box.minY != $1.box.minY ? $0.box.minY < $1.box.minY : $0.box.minX < $1.box.minX }
        var messages: [(speaker: Speaker, text: String, bottom: CGFloat, height: CGFloat)] = []
        for line in sorted {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let speaker = side(of: line.box)
            if speaker == .unknown, isTime(text) { continue }
            if let last = messages.last, last.speaker == speaker, speaker != .unknown,
               line.box.minY - last.bottom < 1.2 * (last.height + line.box.height) / 2 {
                messages[messages.count - 1].text = join(last.text, text)
                messages[messages.count - 1].bottom = max(last.bottom, line.box.maxY)
                continue
            }
            messages.append((speaker, text, line.box.maxY, line.box.height))
        }
        let them = messages.contains { $0.speaker == .them }, me = messages.contains { $0.speaker == .me }
        return ChatTranscript(messages: messages.map { Message(speaker: $0.speaker, text: $0.text) }, labelled: them && me)
    }

    static func side(of box: CGRect) -> Speaker {
        if box.minX < 0.30, box.midX < 0.5 { return .them }
        if box.maxX > 0.70, box.midX > 0.5 { return .me }
        return .unknown
    }

    /// Two lines of a message: no space between Chinese, Japanese or Korean.
    static func join(_ first: String, _ second: String) -> String {
        guard let last = first.last, let next = second.first else { return first + second }
        return Composer.isCJK(last) && Composer.isCJK(next) ? first + second : first + " " + second
    }

    /// A time or day between messages: "14:32", "下午 3:20", "昨天 09:10", "Yesterday 9:10 PM", "星期一", "10月17日 14:32",
    /// "2026/10/17". Short: a message that mentions a time is longer.
    static func isTime(_ text: String) -> Bool {
        guard text.count <= 24 else { return false }
        var rest = text.lowercased()
        let hasClock = rest.range(of: #"\d{1,2}[:：]\d{2}"#, options: .regularExpression) != nil
        let hasDate = rest.range(of: #"\d{1,4}[/.\-年月]\d{1,2}"#, options: .regularExpression) != nil
        for word in dayWords.sorted(by: { $0.count > $1.count }) { rest = rest.replacingOccurrences(of: word, with: " ") }
        let wordOnly = rest.trimmingCharacters(in: .whitespaces).isEmpty
        rest = rest.replacingOccurrences(of: #"[\d:：/.\-,年月日号\s]"#, with: "", options: .regularExpression)
        return rest.isEmpty && (hasClock || hasDate || wordOnly && text.count >= 2)
    }

    static let dayWords: [String] = [
        "今天", "昨天", "前天", "上午", "下午", "中午", "晚上", "凌晨", "早上", "傍晚", "星期一", "星期二", "星期三", "星期四",
        "星期五", "星期六", "星期日", "星期天", "周一", "周二", "周三", "周四", "周五", "周六", "周日", "周天",
        "today", "yesterday", "am", "pm", "a.m.", "p.m.", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
        "sunday", "mon", "tue", "wed", "thu", "fri", "sat", "sun", "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug",
        "sep", "oct", "nov", "dec",
    ]
}

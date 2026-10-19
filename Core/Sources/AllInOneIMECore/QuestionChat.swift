import Foundation

/// An `@question` conversation in the panel: once an answer is in, what is typed is the next question (not a refine),
/// up to `Config.questionRounds` rounds (5 by default), after which the panel offers to go on in Claude or another AI
/// (`ChatHandoff`). Each follow-up is an ordinary multi-turn request: @question's system prompt, the questions and
/// answers so far as user and assistant turns, then the new question (`request`). The composer keeps the rounds in the
/// refine plumbing (`Refinement`): its request is the first question, each turn an answer and the question after it.
public enum QuestionChat {
    /// One round: a question and the answer to it.
    public struct Round: Codable, Equatable, Sendable {
        public var question: String
        public var answer: String

        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }

    /// Rounds in the panel before it suggests going on elsewhere (`Config.questionRounds`), and what that may be set to.
    public static let defaultRounds = 5
    public static let roundRange = 2...10

    /// `configured` kept within `roundRange`.
    public static func rounds(_ configured: Int) -> Int { min(max(configured, roundRange.lowerBound), roundRange.upperBound) }

    /// The longest follow-up question kept, in Characters (a refine instruction has `Refinement.maxInstructionLength`).
    public static let maxFollowUpLength = 2000

    /// The rounds of a conversation kept as a refinement: `first` the first question (as sent), each turn the answer
    /// shown and the question typed after it, `latest` the answer to the last question (nil: not in yet).
    public static func rounds(first: String, turns: [Refinement.Turn], latest: String?) -> [Round] {
        var questions = [first] + turns.map(\.instruction)
        let answers = turns.map { $0.answer.versions.first?.text ?? "" } + [latest ?? ""]
        if questions.isEmpty { questions = [""] }
        return zip(questions, answers).map { Round(question: $0, answer: $1) }
    }

    /// `rounds` as the refine plumbing keeps them (`rounds(first:turns:latest:)` the other way round): the first
    /// question, the turns, and the last answer.
    public static func turns(_ rounds: [Round]) -> (first: String, turns: [Refinement.Turn], latest: String) {
        guard let first = rounds.first else { return ("", [], "") }
        let turns = zip(rounds, rounds.dropFirst()).map {
            Refinement.Turn(answer: ConversionResult(versions: [CandidateLine($0.answer)]), instruction: $1.question)
        }
        return (first.question, turns, rounds.last?.answer ?? "")
    }

    // MARK: - The request

    /// The request for the next answer: @question's own (`Prompt.commandRequest`), with the rounds so far as user and
    /// assistant turns before `question`. With no rounds it is exactly the normal @question request.
    public static func request(_ rounds: [Round], question: String, config: Config) -> ConverseRequest {
        var request = Prompt.commandRequest(.question, input: question, config: config)
        let earlier = rounds.flatMap {
            [ConverseRequest.Message(role: "user", text: $0.question), ConverseRequest.Message(role: "assistant", text: $0.answer)]
        }
        request.messages.insert(contentsOf: earlier, at: 0)
        return request
    }

    /// `turns` (a refinement of `.command(.question, first)`) as the request for the answer to the last turn's question.
    public static func request(first: String, turns: [Refinement.Turn], config: Config) -> ConverseRequest {
        let all = rounds(first: first, turns: turns, latest: nil)
        return request(Array(all.dropLast()), question: all.last?.question ?? first, config: config)
    }

    /// Bump when the request's shape changes (part of the cache key).
    public static let version = 1

    /// The part of a follow-up's cache key that is the conversation after the first question.
    static func turnsKey(_ turns: [Refinement.Turn]) -> String {
        "chat\(version)|" + turns.map { ($0.answer.versions.first?.text ?? "") + "\u{1F}" + $0.instruction }.joined(separator: "\u{1E}")
    }

    // MARK: - Fitting the on-device model's context

    /// How much of an older answer is kept when it is shortened (`fit`): its start and its end, in Characters.
    static let keptHead = 120
    static let keptTail = 60
    /// What stands for the part of an answer left out.
    static let cut = " … "

    /// `request` made to fit a small context (Apple's on-device model: 4K tokens, 8K on macOS 27) by the same estimate
    /// and with the same room for the answer as `AppleModel.request`: the oldest answers lose their middles first, then
    /// the oldest rounds go, until it fits. The last question is always sent, whole. `shortened`: something was left out.
    public static func fit(_ request: ConverseRequest, contextSize: Int, maxTokens: Int) -> (request: ConverseRequest, shortened: Bool) {
        var out = request
        let room = min(maxTokens, AppleModel.answerRoom, contextSize / 3)
        func size() -> Int {
            AppleModel.estimatedTokens(out.system.map(\.text).joined(separator: "\n\n"))
                + out.messages.reduce(0) { $0 + AppleModel.estimatedTokens($1.content.map(\.text).joined()) }
        }
        func fits() -> Bool { size() + room <= contextSize }
        var shortened = false
        // The answers before the last question, oldest first.
        for index in out.messages.indices.dropLast() where !fits() && out.messages[index].role == "assistant" {
            let text = out.messages[index].content.map(\.text).joined()
            guard text.count > keptHead + keptTail + cut.count else { continue }
            out.messages[index].content = [.init(String(text.prefix(keptHead)) + cut + String(text.suffix(keptTail)))]
            shortened = true
        }
        // Then whole rounds, oldest first (a question and its answer).
        while !fits(), out.messages.count >= 3 {
            out.messages.removeFirst(2)
            shortened = true
        }
        return (out, shortened)
    }
}

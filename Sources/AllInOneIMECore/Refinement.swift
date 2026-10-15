import Foundation

/// A follow-up on AI results already shown ("shorter", "more formal", "用更口语的说法"): the request that gave them,
/// and each answer with the instruction the user typed after it. The model gets the same request again, then the
/// conversation so far, and answers in the same line format (`Prompt.refineRequest`, `Prompt.commandRefineRequest`).
public struct Refinement: Equatable, Sendable {
    /// What the results came from.
    public enum Request: Equatable, Sendable {
        /// `@improve`, `@translate` (or both written together): the command and the text the conversion was given.
        case writing(Command?, input: String)
        /// A `.generate` command (`@question`, a prompt command, `Command.edit` on a selection) and its input.
        case command(Command, input: String)
    }

    /// One step: the results shown, and the instruction typed for them.
    public struct Turn: Equatable, Sendable {
        public var answer: ConversionResult
        public var instruction: String

        public init(answer: ConversionResult, instruction: String) {
            self.answer = answer
            self.instruction = instruction
        }
    }

    public var request: Request
    /// Oldest first; the last instruction is the one to run now.
    public var turns: [Turn]

    public init(request: Request, turns: [Turn]) {
        self.request = request
        self.turns = turns
    }

    /// The longest refine instruction kept, in Characters (a sentence or two).
    public static let maxInstructionLength = 200
}

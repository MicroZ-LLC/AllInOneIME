import Foundation
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Owner decision 2026-11-15 (no inline preedit): in every app what is being typed (pinyin, a command draft, a word
/// Code holds) shows only in the candidate panel's input line, never as marked text in the field; the field gets text
/// only on commit. What these tests read in place of the field's marked text.
extension FakeHost {
    /// The candidate panel's input line as shown: its prompt and text, a syllable split (a space between two Latin
    /// letters: librime's "ni hao") left out. Nil: no panel, no input line, or an empty one.
    var inputLine: String? {
        guard let input = panel?.input, !input.text.isEmpty else { return nil }
        let characters = Array(input.prompt + input.text)
        var line = ""
        for (index, character) in characters.enumerated() {
            if character == " ", index > 0, index + 1 < characters.count,
               characters[index - 1].isASCII && characters[index - 1].isLetter,
               characters[index + 1].isASCII && characters[index + 1].isLetter { continue }
            line.append(character)
        }
        return line
    }

    /// Composed as the decision has it: nothing marked in the field, and `text` (syllable splits left out) in the panel's
    /// input line.
    func composes(_ text: String) -> Bool { marked.isEmpty && inputLine == text }

    /// What a failed `composes` says.
    var composing: String { "marked \(marked.debugDescription), input line \(inputLine.debugDescription)" }
}

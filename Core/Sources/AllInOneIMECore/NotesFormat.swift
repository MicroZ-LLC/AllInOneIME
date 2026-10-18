import Foundation

/// How a note goes to Apple Notes and how the folder's notes come back, without Notes itself (the app's
/// NotesBridge runs the AppleScript, and the macOS shell reads its reply: `entries(from:limit:)`): pure, so it can be
/// tested.
public enum NotesFormat {
    /// A note's body is HTML: a <div> per line (\r\n is one break; an empty line keeps its height), the text
    /// escaped, and spaces that HTML would collapse (several in a row, or at either end of a line) kept as
    /// no-break spaces.
    public static func html(_ text: String) -> String {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { line in
            let chars = Array(line)
            var out = ""
            for (i, c) in chars.enumerated() {
                switch c {
                case "&": out += "&amp;"
                case "<": out += "&lt;"
                case ">": out += "&gt;"
                case "\"": out += "&quot;"
                case " ":
                    let alone = i > 0 && i < chars.count - 1 && chars[i - 1] != " " && chars[i + 1] != " "
                    out += alone ? " " : "&nbsp;"
                default: out.append(c)
                }
            }
            return "<div>" + (out.isEmpty ? "<br>" : out) + "</div>"
        }.joined()
    }

    /// A note's title as Notes shows it: its first line with text, at most `limit` characters.
    public static func title(of text: String, limit: Int = 80) -> String {
        let line = text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return String(line.prefix(limit))
    }

    /// A note listed from the folder.
    public struct Entry: Equatable, Sendable {
        public let id: String
        public let title: String
        public let modified: Date

        public init(id: String, title: String, modified: Date) {
            self.id = id
            self.title = title
            self.modified = modified
        }
    }
}

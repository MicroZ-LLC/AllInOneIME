import AllInOneIMECore
import AllInOneIMEMac
import Foundation
import Testing

/// The text around the caret as read from what a field tells (`FieldTextReading`), over the signals recorded on a real
/// Mac (2026-11-14, a logging build of the input method typing into fields of its own harness and into a local page in
/// Brave): an empty field reads as empty, never as "nothing told", so that the text typed before it was cleared (a chat
/// app's field after its message is sent) never stands in for it; a field that tells no length (Chromium, Qt) is read
/// up to its caret.
struct FieldTextReadingTests {
    /// A field as it answered IMK: what it told (`length`, the selection, the marked text) and what reading a range of
    /// its text gave (`reads`: its text, nil past its end, as an NSTextView and Chromium answer; false: nil always).
    struct Field: Sendable {
        let name: String
        var text = ""
        var length: Int
        var selected: NSRange
        var marked = NSRange(location: NSNotFound, length: 0)
        var reads = true

        func read(before: Int = 300, after: Int = 300) -> FieldText? {
            FieldTextReading.read(.init(length: length, selected: selected, marked: marked), before: before, after: after) {
                guard reads, $0.location != NSNotFound, NSMaxRange($0) <= (text as NSString).length else { return nil }
                return (text as NSString).substring(with: $0)
            }
        }
    }

    static let earlier = "earlier text in the field"
    static let notFound = NSRange(location: NSNotFound, length: 0)
    static func caret(_ at: Int) -> NSRange { NSRange(location: at, length: 0) }

    /// Empty fields: read, with nothing in them (not nil: nil would let what was typed earlier stand in).
    @Test(arguments: [
        Field(name: "an empty NSTextView", length: 0, selected: caret(0)),
        Field(name: "an NSTextView cleared by its app after 9 characters were typed", length: 0, selected: caret(0)),
        Field(name: "an empty <input> in Brave", length: 0, selected: caret(0)),
        Field(name: "a <textarea> in Brave cleared by its page", length: 0, selected: caret(0)),
        Field(name: "an empty NSTextView with marked text only", text: "nihao", length: 5, selected: caret(5),
              marked: NSRange(location: 0, length: 5)),
    ])
    func emptyFieldsReadAsEmpty(_ field: Field) {
        #expect(field.read() == FieldText(before: "", after: ""), "\(field.name)")
    }

    /// Fields whose text can be read: what is before the caret (and after it, where the length is told).
    @Test(arguments: [
        Field(name: "an NSTextView, the caret at the end", text: earlier + " hello w", length: 33, selected: caret(33)),
        Field(name: "an NSTextView whose attributedSubstring(forProposedRange:) says nil (IMK reads attributedString())",
              text: earlier + " hello w", length: 33, selected: caret(33)),
        Field(name: "a <textarea> in Brave (no length told)", text: earlier + " hello w", length: 0, selected: caret(32)),
        Field(name: "a contenteditable in Brave (no length told)", text: earlier + " hello w", length: 0, selected: caret(32)),
        Field(name: "a Qt-like field (no attributedString(): no length told)", text: earlier + " hello w", length: 0,
              selected: caret(33)),
    ])
    func readableFieldsReadToTheCaret(_ field: Field) {
        let caret = field.selected.location
        let before = (field.text as NSString).substring(to: min(caret, (field.text as NSString).length))
        #expect(field.read()?.before == before, "\(field.name)")
    }

    /// A field cleared by its page, then typed into again (Brave): only what is in it now, not what was typed before.
    @Test func aFieldClearedThenTypedIntoReadsWhatIsInItNow() {
        let field = Field(name: "an <input> in Brave cleared after \"hel\", then \"l\"", text: "l", length: 0, selected: Self.caret(1))
        #expect(field.read() == FieldText(before: "l", after: ""))
    }

    /// Fields that can't be read: nil (what was typed into them stands in).
    @Test(arguments: [
        Field(name: "a WeChat-like field (attributedString() empty, the caret told)", text: earlier + " hello w", length: 0,
              selected: caret(33), reads: false),
        Field(name: "a field of its own drawing that tells no caret (a game)", text: "hello w", length: 0, selected: notFound,
              reads: false),
        Field(name: "a field of its own drawing that tells a caret and no text", text: "hello w", length: 0, selected: caret(7),
              reads: false),
        Field(name: "a field that tells its length and reads nothing back", text: "hello w", length: 7, selected: caret(7),
              reads: false),
        Field(name: "an app with no text field focused", length: 2_147_483_647,
              selected: NSRange(location: NSNotFound, length: NSNotFound), reads: false),
    ])
    func unreadableFieldsReadAsNothing(_ field: Field) {
        #expect(field.read() == nil, "\(field.name)")
    }

    /// Notes tells marked text of no length where there is none: the caret goes by the selection.
    @Test func markedTextOfNoLengthIsNone() {
        let text = String(repeating: "a", count: 40)
        let field = Field(name: "Notes", text: text, length: 40, selected: Self.caret(20), marked: Self.caret(20))
        #expect(field.read(before: 5, after: 5) == FieldText(before: String(repeating: "a", count: 10),
                                                              after: String(repeating: "a", count: 10)))
    }

    /// The limits hold where no length is told too: up to `before` characters (twice as many UTF-16 units) before it.
    @Test func noLengthToldKeepsTheLimit() {
        let text = String(repeating: "b", count: 100)
        let field = Field(name: "Brave", text: text, length: 0, selected: Self.caret(100))
        #expect(field.read(before: 10, after: 10) == FieldText(before: String(repeating: "b", count: 20), after: ""))
    }

    /// Editing inside a field that tells no length (Brave): the text after the caret is read too, so the caret isn't taken
    /// for the end of the line (autocomplete asks only there).
    @Test(arguments: [
        Field(name: "\"hellox world\" in Brave, the caret after the x", text: "hellox world", length: 0, selected: caret(6)),
        Field(name: "\"hello\" in Brave, the caret at the start", text: "hello", length: 0, selected: caret(0)),
    ])
    func noLengthToldReadsTheTextAfterTheCaret(_ field: Field) {
        let after = (field.text as NSString).substring(from: field.selected.location)
        let read = field.read()
        #expect(read?.before == (field.text as NSString).substring(to: field.selected.location), "\(field.name)")
        #expect(read?.after.isEmpty == false && after.hasPrefix(read?.after ?? "\u{0}"), "\(field.name)")
    }

    /// Marked text or a selection in a field that tells no length: what is after it is read from its end, never the
    /// marked text or the selection itself (an `@reply` draft is not the field's text).
    @Test func noLengthToldReadsAfterTheMarkedTextOrTheSelection() {
        let draft = Field(name: "only a marked @reply draft in Brave", text: "@reply", length: 0, selected: Self.caret(6),
                          marked: NSRange(location: 0, length: 6))
        #expect(draft.read() == FieldText(before: "", after: ""))
        let selection = Field(name: "a selection inside \"hello world\" in Brave", text: "hello world", length: 0,
                              selected: NSRange(location: 6, length: 5))
        #expect(selection.read() == FieldText(before: "hello ", after: ""))
        let middle = Field(name: "\"wor\" selected in \"hello world\" in Brave", text: "hello world", length: 0,
                           selected: NSRange(location: 6, length: 3))
        #expect(middle.read()?.before == "hello " && middle.read()?.after.hasPrefix("l") == true)
    }

    /// The whole rest of the line is read, not just what a shorter probe happened to reach: a space then a word after the
    /// caret is text after it, not the end of the line.
    @Test(arguments: [1, 2, 3, 7, 50, 399, 400])
    func noLengthToldReadsTheWholeSuffix(_ restLength: Int) {
        let rest = " " + String(repeating: "x", count: restLength)
        let field = Field(name: "Brave", text: "hello" + rest, length: 0, selected: Self.caret(5))
        #expect(field.read(before: 300, after: 300)?.after == String(rest.prefix(600)))
    }
}

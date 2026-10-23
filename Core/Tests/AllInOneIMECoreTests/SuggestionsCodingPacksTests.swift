import Foundation
import Testing
@testable import AllInOneIMECore

/// The coding language packs this repository ships (Core/CodingPacks/), read as the app reads a downloaded one, and what
/// their snippets put in through a session (spec 6.19): a snippet's second and later lines get the caret's line's
/// indentation, what several installed packs' snippets put in alike is one row, a pack's row names its language, and a
/// snippet picked comes first among its trigger's. The rig: Acceptance/SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsCodingPacksTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("CodingPacks", isDirectory: true)

    static func shipped(_ language: String) throws -> CodingLanguagePack {
        try JSONDecoder().decode(CodingLanguagePack.self, from: Data(contentsOf: folder.appendingPathComponent(language + ".json")))
    }

    /// A world in coding mode with `packs` installed.
    static func coding(_ packs: [CodingLanguagePack]) -> SuggestionsWorld {
        let world = SuggestionsWorld()
        world.packs = packs
        world.codingMode = true
        return world
    }

    /// The texts of the rows, each with its comment.
    static func texts(_ field: SuggestionsField) -> [String] { field.rows.map { $0.text + " " + $0.comment } }

    // MARK: - The packs

    /// Every pack in Core/CodingPacks is kept as a downloaded one is (`CodingPackStore.keep`: a pack, of the language its
    /// file is named for, within the limits), names no keyword twice, and offers each of its snippets for its trigger
    /// (spec 6.13: the body starts with it), with its caret at its first tab stop (none is in the trigger), every stop's
    /// text where the field reports no ranges.
    @Test func theShippedPacksAreGood() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let languages = files.map { $0.deletingPathExtension().lastPathComponent }
        #expect(Set(languages) == ["c", "cpp", "go", "java", "javascript", "python", "typescript"], "\(languages)")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coding-packs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodingPackStore(directory: directory)
        let t = InterfaceWords(language: "en")
        for (file, language) in zip(files, languages) {
            let pack = try store.keep(Data(contentsOf: file), language: language)
            #expect(Set(pack.keywords).count == pack.keywords.count, "\(language): a keyword twice")
            for snippet in pack.snippets {
                let rows = CodingRows.rows(snippet.trigger, packs: [pack], words: [], appClass: .ordinary, in: t)
                let (text, back) = CodingRows.expand(snippet.body)
                let plain = CodingRows.expand(snippet.body, toFirstStop: false).text
                #expect(rows.contains { $0.insertion == text && $0.caretBack == back && ($0.plainInsertion ?? $0.insertion) == plain },
                        "\(language): \(snippet.trigger) (\(snippet.title ?? "")) is never offered, or not with its caret at its first stop")
            }
        }
        #expect(store.installed().map(\.title) == ["C", "C++", "Go", "Java", "JavaScript", "Python", "TypeScript"])
    }

    @Test func theCaretsLineGivesTheIndentation() {
        #expect(CodingRows.indent("def main():\n    x = ") == "    ")
        #expect(CodingRows.indent("func main() {\r\n\t\t") == "\t\t")
        #expect(CodingRows.indent("  top") == "  " && CodingRows.indent("x\n") == "" && CodingRows.indent("") == "")
        #expect(CodingRows.indented("a\nb\n", by: "  ") == "a\n  b\n  " && CodingRows.indented("a\nb", by: "") == "a\nb")
    }

    // MARK: - Through a session

    /// A snippet's second and later lines get the leading whitespace of the line the caret is on; the caret still goes to
    /// its first tab stop (try/except's exception, its text left out).
    @Test func aSnippetsLaterLinesGetTheCaretLinesIndentation() async throws {
        try await inEnglish {
            let world = Self.coding([try Self.shipped("python")])
            let field = world.field()
            field.host.document = "def main():\n    "
            field.type("tr")
            #expect(field.settle { field.rows.first?.comment.contains("try/except") == true }, "\(Self.texts(field))")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.tab))
            let rest = " as e:\n        print(e)"
            #expect(field.document == "def main():\n    try:\n        \n    except " + rest, "\(field.document.debugDescription)")
            let moves = field.host.outputs.dropFirst(before).compactMap { output -> Int? in
                if case let .moveCaret(back, _) = output { return back } else { return nil }
            }
            #expect(moves == [rest.utf16.count], "the caret at ${1:Exception}, after its line's indentation: \(moves)")

            // Tabs as the line has them, after code on it too.
            let go = Self.coding([try Self.shipped("go")])
            let tabs = go.field()
            tabs.host.document = "func main() {\n\tx := 1; "
            tabs.type("if")
            #expect(tabs.settle { tabs.rows.contains { $0.comment.contains("if err != nil") } }, "\(Self.texts(tabs))")
            let index = try #require(tabs.rows.firstIndex { $0.comment.contains("if err != nil") })
            #expect(tabs.pick(at: index))
            #expect(tabs.document == "func main() {\n\tx := 1; if err != nil {\n\t\treturn \n\t}", "\(tabs.document.debugDescription)")
        }
    }

    /// A snippet's caret goes to its first tab stop, `${1:name}`, with that stop's text left out (the others keep theirs),
    /// with Return as with Tab; its later lines still get the caret's line's indentation. Where the field reports no
    /// ranges the caret can't go back into it: every stop's text goes in, the caret at the end, as before.
    @Test func theCaretGoesToTheFirstTabStopWithoutItsText() async throws {
        try await inEnglish {
            let world = Self.coding([try Self.shipped("python")])
            let field = world.field(app: "com.apple.Notes")
            field.type("def")
            #expect(field.settle { field.rows.first?.comment.contains("function") == true }, "\(Self.texts(field))")
            var before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.enter))
            #expect(field.document == "def ():\n    ", "\(field.document.debugDescription)")
            #expect(Self.moves(field, since: before) == ["():\n    ".utf16.count], "right after \"def \": \(Self.moves(field, since: before))")

            let indented = world.field()
            indented.host.document = "class A:\n    "
            indented.type("def")
            #expect(indented.settle { indented.rows.contains { $0.comment.contains("method") } }, "\(Self.texts(indented))")
            let index = try #require(indented.rows.firstIndex { $0.comment.contains("method") })
            before = indented.host.outputs.count
            #expect(indented.pick(at: index))
            #expect(indented.document == "class A:\n    def (self):\n        ", "\(indented.document.debugDescription)")
            #expect(Self.moves(indented, since: before) == ["(self):\n        ".utf16.count], "\(Self.moves(indented, since: before))")

            // Another world: the method picked above comes first in this one.
            let plain = Self.coding([try Self.shipped("python")]).field()
            plain.type("def")
            #expect(plain.settle { plain.rows.first?.comment.contains("function") == true }, "\(Self.texts(plain))")
            var context = plain.host.context
            context.read.subtract([.selectedRange, .selection])
            context.selectedRange = nil
            context.selection = nil
            before = plain.host.outputs.count
            plain.host.send(.key(SuggestionKeys.tab, context))
            let outputs = Array(plain.host.outputs.dropFirst(before))
            #expect(outputs.contains { if case .commit(" name():\n    ") = $0 { true } else if case .commitAfterKey(" name():\n    ") = $0 { true } else { false } },
                    "no ranges: its text, the caret at the end (\(outputs))")
            #expect(Self.moves(plain, since: before).allSatisfy { $0 == 0 }, "\(outputs)")
        }
    }

    /// The caret moves back the session asked for since output `start`.
    static func moves(_ field: SuggestionsField, since start: Int) -> [Int] {
        field.host.outputs.dropFirst(start).compactMap { output -> Int? in
            if case let .moveCaret(back, _) = output { return back } else { return nil }
        }
    }

    /// A line without indentation adds none: the body goes in as it is.
    @Test func noIndentationAddsNone() async throws {
        try await inEnglish {
            let world = Self.coding([try Self.shipped("python")])
            let field = world.field()
            field.host.document = "import os\n"
            field.type("tr")
            #expect(field.settle { field.rows.first?.comment.contains("try/except") == true }, "\(Self.texts(field))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "import os\ntry:\n    \nexcept  as e:\n    print(e)", "\(field.document.debugDescription)")
        }
    }

    /// A pack's snippet row says its language, then its title ("Python · function"), or that it's a snippet where the
    /// title is only its trigger; a keyword's, its language.
    @Test func aPacksRowNamesItsLanguage() async throws {
        try await inEnglish {
            let world = Self.coding([try Self.shipped("python")])
            let field = world.field()
            field.type("de")
            #expect(field.settle { !field.rows.isEmpty }, "\(Self.texts(field))")
            #expect(Self.texts(field) == ["def Python · function", "def Python · method", "def Python", "del Python"], "\(Self.texts(field))")
            let printing = world.field()
            printing.type("pr")
            #expect(printing.settle { Self.texts(printing).first == "print Python · snippet" }, "\(Self.texts(printing))")
        }
    }

    /// What several installed packs' snippets put in alike is one row, its comment naming each pack's language: C's, C++'s
    /// and Java's `if`; two bodies written differently that come out the same (their first stops, `${1:…}` and `${2:…}`,
    /// empty, the caret there).
    @Test func identicalExpansionsFromSeveralPacksShowOnce() async throws {
        try await inEnglish {
            let world = Self.coding([try Self.shipped("c"), try Self.shipped("cpp"), try Self.shipped("java")])
            let field = world.field()
            field.type("if")
            #expect(field.settle { !field.rows.isEmpty }, "\(Self.texts(field))")
            #expect(field.rows.filter { $0.text == "if" }.map(\.comment) == ["C/C++/Java · snippet", "C/C++/Java · if/else"],
                    "\(Self.texts(field))")

            let written = Self.coding([
                CodingLanguagePack(language: "example", title: "Example", version: "1.0.0", keywords: [],
                                   snippets: [.init(trigger: "show", body: "show(${1:value})$0", title: "show")]),
                CodingLanguagePack(language: "other", title: "Other", version: "1.0.0", keywords: [],
                                   snippets: [.init(trigger: "show", body: "show(${2:value})${0}", title: "show")]),
            ])
            let both = written.field()
            both.type("sh")
            #expect(both.settle { !both.rows.isEmpty }, "\(Self.texts(both))")
            #expect(Self.texts(both) == ["show Example/Other · snippet"], "\(Self.texts(both))")
            #expect(both.press(SuggestionKeys.tab))
            #expect(both.document == "show()", "\(both.document)")
        }
    }

    /// In a code editor a snippet completes as its trigger: a trigger's several snippets there are one row.
    @Test func inACodeEditorATriggersSnippetsAreOneRow() async throws {
        try await inEnglish {
            let world = Self.coding([try Self.shipped("python")])
            let field = world.field(app: SuggestionsApps.vsCode)
            field.type("fo")
            #expect(field.settle { !field.rows.isEmpty }, "\(Self.texts(field))")
            #expect(field.rows.filter { $0.text == "for" && $0.comment.contains(" · ") }.count == 1, "\(Self.texts(field))")
        }
    }

    /// A snippet picked comes first next time, before the others of its trigger (each is picked as itself).
    @Test func aSnippetPickedComesFirstAmongItsTriggers() async throws {
        try await inEnglish {
            let world = Self.coding([try Self.shipped("python")])
            let field = world.field()
            field.type("if")
            #expect(field.settle { field.rows.count == 3 }, "\(Self.texts(field))")
            let index = try #require(field.rows.firstIndex { $0.comment.contains("main guard") }, "\(Self.texts(field))")
            #expect(index > 0)
            #expect(field.pick(at: index))
            #expect(field.document == "if __name__ == \"__main__\":\n    ", "its first stop, main(), left out: \(field.document.debugDescription)")
            let again = world.field()
            again.type("if")
            #expect(again.settle { again.rows.count == 3 }, "\(Self.texts(again))")
            #expect(again.rows.first?.comment.contains("main guard") == true, "\(Self.texts(again))")
        }
    }
}

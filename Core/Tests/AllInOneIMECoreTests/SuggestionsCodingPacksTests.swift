import Foundation
import Testing
@testable import AllInOneIMECore

/// The coding language packs this repository ships (Core/CodingPacks/), read as the app reads a downloaded one, and what
/// their snippets put in through a session in Code (spec 6.19, decision 22): a snippet's second and later lines get the
/// caret's line's indentation, only Code's language's pack gives rows (the others installed don't), what two snippets put
/// in alike is one row, a row says what it is (not its language), and a snippet picked comes first among its trigger's.
/// The rig: Acceptance/SuggestionsAcceptanceTests.swift (Code's world and fields: `addCode`, `codeField`).
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsCodingPacksTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("CodingPacks", isDirectory: true)

    static func shipped(_ language: String) throws -> CodingLanguagePack {
        try JSONDecoder().decode(CodingLanguagePack.self, from: Data(contentsOf: folder.appendingPathComponent(language + ".json")))
    }

    /// A world with `packs` installed and the Code input in `language` (else the first pack's).
    static func coding(_ packs: [CodingLanguagePack], language: String? = nil) -> SuggestionsWorld {
        let world = SuggestionsWorld()
        world.addCode(language ?? packs.first?.language ?? "python", packs: packs)
        return world
    }

    /// The texts of the rows, each with its comment.
    static func texts(_ field: SuggestionsField) -> [String] { field.rows.map { $0.text + " " + $0.comment } }

    /// Picks Code's row at `index` in an ordinary app: Tab the first, else ↓ `index` times and Return. The first row is
    /// chosen from the start, so ↓ moves at once (decision 31), as `SuggestionsField.pick(at:)` has it for every row.
    static func pick(_ field: SuggestionsField, at index: Int) -> Bool {
        if index == 0 { return field.press(SuggestionKeys.tab) }
        var handled = true
        for _ in 0..<index { handled = field.press(SuggestionKeys.down) && handled }
        return field.press(SuggestionKeys.enter) && handled
    }

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
            let builtins = pack.builtins ?? []
            #expect(Set(builtins).count == builtins.count, "\(language): a built-in twice")
            #expect(Set(pack.keywords).isDisjoint(with: builtins), "\(language): a word both a keyword and a built-in")
            // Every word offered from its first characters, saying which it is.
            for (word, kind) in pack.keywords.map({ ($0, "keyword") }) + builtins.map({ ($0, "built-in") })
            where word.count > CodingRows.minChars {
                let rows = CodingRows.rows(String(word.prefix(CodingRows.minChars)), pack: pack, words: [], appClass: .ordinary, in: t)
                #expect(rows.contains { $0.text == word && $0.comment == kind }, "\(language): \(word) isn't offered as a \(kind)")
            }
            // A language's built-in functions, types and library names aren't its keywords.
            let someBuiltins = Self.someBuiltins[language] ?? []
            #expect(!someBuiltins.isEmpty && Set(someBuiltins).isSubset(of: builtins), "\(language): \(someBuiltins) among \(builtins)")
            for snippet in pack.snippets {
                let rows = CodingRows.rows(snippet.trigger, pack: pack, words: [], appClass: .ordinary, in: t)
                let (text, back) = CodingRows.expand(snippet.body)
                let plain = CodingRows.expand(snippet.body, toFirstStop: false).text
                #expect(rows.contains { $0.insertion == text && $0.caretBack == back && ($0.plainInsertion ?? $0.insertion) == plain },
                        "\(language): \(snippet.trigger) (\(snippet.title ?? "")) is never offered, or not with its caret at its first stop")
            }
        }
        #expect(store.installed().map(\.title) == ["C", "C++", "Go", "Java", "JavaScript", "Python", "TypeScript"])
    }

    /// Words of each shipped pack that are built-ins (functions, types, library names), not keywords.
    static let someBuiltins: [String: [String]] = [
        "python": ["format", "len", "range", "enumerate", "isinstance", "ValueError"],
        "go": ["len", "make", "append", "string", "nil", "Println"],
        "java": ["String", "System", "ArrayList", "println", "Override"],
        "javascript": ["console", "Promise", "setTimeout", "undefined", "forEach"],
        "typescript": ["Promise", "Partial", "setTimeout", "parseInt", "forEach"],
        "c": ["strlen", "memcpy", "NULL", "size_t", "stdio"],
        "cpp": ["vector", "string", "push_back", "make_unique", "std"],
    ]

    /// A pack's `builtins` (optional): their rows say "built-in" (in the interface's language), as a keyword's say
    /// "keyword"; a pack without them is read as before, and one listing too many isn't kept.
    @Test func aBuiltInsRowSaysBuiltIn() async throws {
        let json = #"""
            { "language": "example", "title": "Example", "version": "1.0.0", "keywords": ["for"],
              "builtins": ["format", "forward"], "snippets": [] }
            """#
        let pack = try JSONDecoder().decode(CodingLanguagePack.self, from: Data(json.utf8))
        #expect(pack.builtins == ["format", "forward"] && pack.problem == nil)
        #expect(try JSONDecoder().decode(CodingLanguagePack.self, from: JSONEncoder().encode(pack)) == pack)
        let without = try JSONDecoder().decode(CodingLanguagePack.self, from: Data(#"{ "language": "example", "title": "Example", "version": "1.0.0", "keywords": ["for"], "snippets": [] }"#.utf8))
        #expect(without.builtins == nil && without.problem == nil)
        var tooMany = pack
        tooMany.builtins = Array(repeating: "x", count: CodingLanguagePack.maxKeywords + 1)
        #expect(tooMany.problem != nil)
        tooMany.builtins = ["two words"]
        #expect(tooMany.problem != nil)

        let rows = { (language: String) in
            CodingRows.rows("fo", pack: pack, words: ["format", "fortune"], appClass: .ordinary, in: InterfaceWords(language: language))
                .map { $0.text + " " + $0.comment }
        }
        #expect(rows("en") == ["for keyword", "format built-in", "forward built-in", "fortune "], "\(rows("en"))")
        #expect(rows("zh-Hans") == ["for 关键字", "format 内置", "forward 内置", "fortune "], "\(rows("zh-Hans"))")

        // Python's: "for" offers its snippets and the built-in format, said so.
        try await inEnglish {
            let world = Self.coding([try Self.shipped("python")])
            let field = world.codeField()
            field.type("for")
            #expect(field.settle { !field.rows.isEmpty }, "\(Self.texts(field))")
            #expect(Self.texts(field) == ["for for … in", "for for … in range", "for for … in enumerate", "format built-in"],
                    "\(Self.texts(field))")
        }
    }

    @Test func theCaretsLineGivesTheIndentation() {
        #expect(CodingRows.indent("def main():\n    x = ") == "    ")
        #expect(CodingRows.indent("func main() {\r\n\t\t") == "\t\t")
        #expect(CodingRows.indent("  top") == "  " && CodingRows.indent("x\n") == "" && CodingRows.indent("") == "")
        #expect(CodingRows.indented("a\nb\n", by: "  ") == "a\n  b\n  " && CodingRows.indented("a\nb", by: "") == "a\nb")
    }

    // MARK: - Through a session

    /// A snippet's second and later lines get the leading whitespace of the line the caret is on; the caret still goes to
    /// its first tab stop in reading order (try/except's `$0`, in its body, the exception's text kept).
    @Test func aSnippetsLaterLinesGetTheCaretLinesIndentation() async throws {
        try await inEnglish {
            let world = Self.coding([try Self.shipped("python")])
            let field = world.codeField()
            field.host.document = "def main():\n    "
            field.type("tr")
            #expect(field.settle { field.rows.first?.comment.contains("try/except") == true }, "\(Self.texts(field))")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.tab))
            let rest = "\n    except Exception as e:\n        print(e)"
            #expect(field.document == "def main():\n    try:\n        " + rest, "\(field.document.debugDescription)")
            let moves = field.host.outputs.dropFirst(before).compactMap { output -> Int? in
                if case let .moveCaret(back, _) = output { return back } else { return nil }
            }
            #expect(moves == [rest.utf16.count], "the caret at $0, after its line's indentation: \(moves)")

            // Tabs as the line has them, after code on it too.
            let go = Self.coding([try Self.shipped("go")])
            let tabs = go.codeField()
            tabs.host.document = "func main() {\n\tx := 1; "
            tabs.type("if")
            #expect(tabs.settle { tabs.rows.contains { $0.comment.contains("if err != nil") } }, "\(Self.texts(tabs))")
            let index = try #require(tabs.rows.firstIndex { $0.comment.contains("if err != nil") })
            #expect(Self.pick(tabs, at: index))
            #expect(tabs.document == "func main() {\n\tx := 1; if err != nil {\n\t\treturn \n\t}", "\(tabs.document.debugDescription)")
        }
    }

    /// A snippet's caret goes to its first tab stop, `${1:name}`, with that stop's text left out (the others keep theirs),
    /// with Return as with Tab; its later lines still get the caret's line's indentation. Where the field reports no
    /// ranges the caret can't go back into it: every stop's text goes in, the caret at the end, as before.
    @Test func theCaretGoesToTheFirstTabStopWithoutItsText() async throws {
        try await inEnglish {
            let world = Self.coding([try Self.shipped("python")])
            let field = world.codeField(app: "com.apple.Notes")
            field.type("def")
            #expect(field.settle { field.rows.first?.comment.contains("function") == true }, "\(Self.texts(field))")
            var before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.enter))
            #expect(field.document == "def ():\n    ", "\(field.document.debugDescription)")
            #expect(Self.moves(field, since: before) == ["():\n    ".utf16.count], "right after \"def \": \(Self.moves(field, since: before))")

            let indented = world.codeField()
            indented.host.document = "class A:\n    "
            indented.type("def")
            #expect(indented.settle { indented.rows.contains { $0.comment.contains("method") } }, "\(Self.texts(indented))")
            let index = try #require(indented.rows.firstIndex { $0.comment.contains("method") })
            before = indented.host.outputs.count
            #expect(Self.pick(indented, at: index))
            #expect(indented.document == "class A:\n    def (self):\n        ", "\(indented.document.debugDescription)")
            #expect(Self.moves(indented, since: before) == ["(self):\n        ".utf16.count], "\(Self.moves(indented, since: before))")

            // Another world: the method picked above comes first in this one.
            let plain = Self.coding([try Self.shipped("python")]).codeField()
            plain.type("def")
            #expect(plain.settle { plain.rows.first?.comment.contains("function") == true }, "\(Self.texts(plain))")
            var context = plain.host.context
            context.read.subtract([.selectedRange, .selection])
            context.selectedRange = nil
            context.selection = nil
            before = plain.host.outputs.count
            plain.host.send(.key(SuggestionKeys.tab, context))
            let outputs = Array(plain.host.outputs.dropFirst(before))
            #expect(outputs.contains { if case .commit("def name():\n    ") = $0 { true } else { false } },
                    "no ranges: its text in place of the word held, the caret at the end (\(outputs))")
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
            let field = world.codeField()
            field.host.document = "import os\n"
            field.type("tr")
            #expect(field.settle { field.rows.first?.comment.contains("try/except") == true }, "\(Self.texts(field))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "import os\ntry:\n    \nexcept Exception as e:\n    print(e)", "\(field.document.debugDescription)")
        }
    }

    /// A snippet's row says its title ("function"), or that it's a snippet where the title is only its trigger; a
    /// keyword's that it's a keyword. Never the language: Code has one (decision 22).
    @Test func aCodeRowSaysWhatItIs() async throws {
        try await inEnglish {
            let world = Self.coding([try Self.shipped("python")])
            let field = world.codeField()
            field.type("de")
            #expect(field.settle { !field.rows.isEmpty }, "\(Self.texts(field))")
            #expect(Self.texts(field) == ["def function", "def method", "def keyword", "del keyword"], "\(Self.texts(field))")
            let printing = world.codeField()
            printing.type("pr")
            #expect(printing.settle { Self.texts(printing).first == "print snippet" }, "\(Self.texts(printing))")
        }
    }

    /// Only Code's language's pack gives rows, whatever else is installed: C's `if` in C (C++'s and Java's, which put in
    /// the same, aren't there to name), Java's in Java; two snippets of one pack written differently that come out the
    /// same are one row (their first stops, `${1:…}` and `${2:…}`, empty, the caret there).
    @Test func onlyCodesLanguageGivesRows() async throws {
        try await inEnglish {
            let packs = [try Self.shipped("c"), try Self.shipped("cpp"), try Self.shipped("java")]
            let c = Self.coding(packs, language: "c").codeField()
            c.type("if")
            #expect(c.settle { !c.rows.isEmpty }, "\(Self.texts(c))")
            #expect(c.rows.filter { $0.text == "if" }.map(\.comment) == ["snippet", "if/else"], "\(Self.texts(c))")
            #expect(c.host.panel?.detail == "C", "the source, C's pack: \(c.footer)")
            let java = Self.coding(packs, language: "java").codeField()
            java.type("sw")
            #expect(java.settle { !java.rows.isEmpty }, "\(Self.texts(java))")
            #expect(java.host.panel?.detail == "Java" && java.rows.first?.text == "switch", "\(Self.texts(java))")

            let written = Self.coding([
                CodingLanguagePack(language: "example", title: "Example", version: "1.0.0", keywords: [],
                                   snippets: [.init(trigger: "show", body: "show(${1:value})$0", title: "show"),
                                              .init(trigger: "show", body: "show(${2:value})${0}", title: "show")]),
            ])
            let both = written.codeField()
            both.type("sh")
            #expect(both.settle { !both.rows.isEmpty }, "\(Self.texts(both))")
            #expect(Self.texts(both) == ["show snippet"], "\(Self.texts(both))")
            #expect(both.press(SuggestionKeys.tab))
            #expect(both.document == "show()", "\(both.document)")
        }
    }

    /// In a code editor a snippet completes as its trigger: a trigger's several snippets there are one row.
    @Test func inACodeEditorATriggersSnippetsAreOneRow() async throws {
        try await inEnglish {
            let world = Self.coding([try Self.shipped("python")])
            let field = world.codeField(app: SuggestionsApps.vsCode)
            field.type("fo")
            #expect(field.settle { !field.rows.isEmpty }, "\(Self.texts(field))")
            #expect(field.rows.filter { $0.text == "for" && $0.comment != "keyword" }.count == 1, "\(Self.texts(field))")
        }
    }

    /// A snippet picked comes first next time, before the others of its trigger (each is picked as itself).
    @Test func aSnippetPickedComesFirstAmongItsTriggers() async throws {
        try await inEnglish {
            let world = Self.coding([try Self.shipped("python")])
            let field = world.codeField()
            field.type("if")
            #expect(field.settle { field.rows.count == 3 }, "\(Self.texts(field))")
            let index = try #require(field.rows.firstIndex { $0.comment.contains("main guard") }, "\(Self.texts(field))")
            #expect(index > 0)
            #expect(Self.pick(field, at: index))
            #expect(field.document == "if __name__ == \"__main__\":\n    ", "its first stop, main(), left out: \(field.document.debugDescription)")
            let again = world.codeField()
            again.type("if")
            #expect(again.settle { again.rows.count == 3 }, "\(Self.texts(again))")
            #expect(again.rows.first?.comment.contains("main guard") == true, "\(Self.texts(again))")
        }
    }
}

import Foundation
import Testing
@testable import AllInOneIMECore

/// What the acceptance tests leave to the implementation: iCloud placeholders and case when a name is taken, long
/// emoji titles, a paragraph past Notion's pieces per block, the other 4xx answers, the settings' coding.
struct NoteDestinationsTests {
    private func draft(_ text: String) -> NoteDraft {
        NoteDraft(text: text, created: Date(timeIntervalSince1970: 1_792_000_000), timeZone: TimeZone(identifier: "UTC")!)
    }

    @Test func aNameIsTakenInAnyCaseAndByAnICloudPlaceholder() {
        typealias M = MarkdownFolderDestination
        #expect(M.fileName(for: draft("Hello"), existing: ["hello.md"]) == "Hello 2.md")
        #expect(M.fileName(for: draft("Hello"), existing: [".Hello.md.icloud"]) == "Hello 2.md")
        #expect(M.fileName(for: draft("con.notes"), existing: []) == "con_.notes.md")
        #expect(M.fileName(for: draft("  \n  "), existing: []) == "Note 2026-10-14 1746.md")
        // 80 emoji of 4 bytes each: cut by whole characters to fit 255 bytes.
        let emoji = M.fileName(for: draft(String(repeating: "😀", count: 80)), existing: [])
        #expect(emoji.utf8.count <= 255 && emoji.hasSuffix(".md") && emoji.dropLast(3).allSatisfy { $0 == "😀" })
    }

    @Test func aVaultIsFoundUpTheTreeAndTheOpenURLEscapesThePath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("note-dest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let deep = root.appendingPathComponent("a/b c/d", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        #expect(MarkdownFolderDestination.vaultRoot(of: deep) == nil)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/.obsidian"), withIntermediateDirectories: true)
        #expect(MarkdownFolderDestination.vaultRoot(of: deep)?.lastPathComponent == "a")
        let file = deep.appendingPathComponent("Plan & ideas #1.md")
        let open = MarkdownFolderDestination.openURL(for: file).absoluteString
        #expect(open.hasPrefix("obsidian://open?path=%2F") && open.contains("%26") && open.contains("%20") && open.contains("%23"))
    }

    @Test func aHugeParagraphSpreadsOverBlocksWithinNotionsLimits() {
        let paragraph = String(repeating: "x", count: 250_000)  // 125 pieces: more than one block holds
        let blocks = NotionFormat.blocks(paragraph)
        #expect(blocks.count == 2 && blocks.allSatisfy { $0.count <= NotionFormat.maxPieces })
        #expect(blocks.flatMap { $0 }.joined() == paragraph)
        // A character is never cut in two (UTF-16 counted as Notion counts it).
        let pieces = NotionFormat.pieces(String(repeating: "😀", count: 1500))
        #expect(pieces.allSatisfy { $0.utf16.count <= NotionFormat.maxText } && pieces.joined() == String(repeating: "😀", count: 1500))
    }

    @Test func otherAnswersMapToWhatTheyMean() {
        #expect(NotionAPI.error(status: 409, body: Data(#"{"code":"conflict_error"}"#.utf8)) == .notionRefused(code: "conflict_error"))
        #expect(NotionAPI.error(status: 400, body: Data("not json".utf8)) == .notionRefused(code: "HTTP 400"))
        #expect(NotionAPI.error(status: 502, body: Data()) == .notionTrouble(status: 502))
        #expect(NoteError.notionNotSetUp.needsTheUser && !NoteError.offline.needsTheUser)
        #expect(NoteError.notionTimedOut(seconds: 10).message(language: "en") == "Notion didn't answer within 10 s")
    }

    @Test func theSettingsCodeAsTheSpecSays() throws {
        let target = NotionTarget(id: "a", kind: .page, title: "Journal")
        let settings = NoteSettings(destination: .notion, notion: target)
        let json = try #require(String(data: JSONEncoder().encode(settings), encoding: .utf8))
        #expect(json.contains(#""destination":"notion""#) && !json.contains("folder"))
        #expect(try JSONDecoder().decode(NoteSettings.self, from: Data(json.utf8)) == settings)
        // A broken target is no target; the rest still reads.
        let odd = try JSONDecoder().decode(NoteSettings.self, from: Data(#"{"destination":"folder","folder":"~/x","notion":{"kind":"wiki"}}"#.utf8))
        #expect(odd.destination == .folder && odd.notion == nil && odd.folderURL?.path.hasSuffix("/x") == true)
        // Without a folder, a folder destination saves to Notes.
        struct System: NoteDestination {
            var name: String { "Notes" }
            var leavesDevice: Bool { false }
            func save(_ draft: NoteDraft) async throws -> SavedNoteRef { SavedNoteRef(id: nil, title: "") }
            func check() async throws -> String { "" }
        }
        #expect(NoteDestinations.make(NoteSettings(destination: .folder), system: System()).name == "Notes")
        #expect(NoteDestinations.openURL(forSaved: "x-coredata://A/ICNote/p1") == nil)
        #expect(NoteDestinations.openURL(forSaved: "https://www.notion.so/x")?.absoluteString == "https://www.notion.so/x")
    }
}

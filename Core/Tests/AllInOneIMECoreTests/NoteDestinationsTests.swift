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

    // MARK: - Writing a file: never half of one, nothing left behind

    private func tempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("note-dest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func names(_ folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    @Test func aWriteThatFailsHalfWayLeavesNoFileBehind() async throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("old".utf8).write(to: folder.appendingPathComponent("Big note.md"))
        // The disk fills up half way: some of it written, then an error (not "the name is taken").
        let destination = MarkdownFolderDestination(folder: folder) { data, file in
            try data.prefix(10).write(to: file, options: .withoutOverwriting)
            throw CocoaError(.fileWriteOutOfSpace)
        }
        await #expect(throws: CocoaError.self) { _ = try await destination.save(draft("Big note\n" + String(repeating: "x", count: 5000))) }
        #expect(names(folder) == ["Big note.md"], "\(names(folder))")
        #expect(try String(contentsOf: folder.appendingPathComponent("Big note.md"), encoding: .utf8) == "old")
    }

    @Test func aFolderThatGoesAwayDuringTheWriteIsMissingAndNothingIsLeft() async throws {
        let parent = try tempFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = parent.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = MarkdownFolderDestination(folder: folder) { _, _ in
            try FileManager.default.removeItem(at: folder)
            throw CocoaError(.fileNoSuchFile)
        }
        do {
            _ = try await destination.save(draft("Hello"))
            Issue.record("saved into a folder that went away")
        } catch {
            #expect(error as? NoteError == .folderMissing(path: folder.path), "\(error)")
        }
        #expect(names(parent).isEmpty)
    }

    @Test func aNameTakenWhileWritingGetsTheNextAndNothingIsOverwritten() async throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Another app makes "Hello.md" between the listing and the rename.
        let destination = MarkdownFolderDestination(folder: folder) { data, file in
            try data.write(to: file, options: .withoutOverwriting)
            try Data("theirs".utf8).write(to: folder.appendingPathComponent("Hello.md"), options: .withoutOverwriting)
        }
        let ref = try await destination.save(draft("Hello\nworld"))
        #expect(names(folder) == ["Hello.md", "Hello 2.md"], "\(names(folder))")
        #expect(try String(contentsOf: folder.appendingPathComponent("Hello.md"), encoding: .utf8) == "theirs")
        #expect(ref.id.flatMap(URL.init(string:))?.lastPathComponent == "Hello 2.md")
        #expect(try String(contentsOf: folder.appendingPathComponent("Hello 2.md"), encoding: .utf8)
                == MarkdownFolderDestination.document(for: draft("Hello\nworld")))
        #expect(ref.destinationName == "“\(folder.lastPathComponent)”")
    }

    @Test func onlyTheNameTakenCountsAsTaken() {
        #expect(MarkdownFolderDestination.isTaken(POSIXError(.EEXIST)))
        #expect(MarkdownFolderDestination.isTaken(CocoaError(.fileWriteFileExists)))
        #expect(!MarkdownFolderDestination.isTaken(CocoaError(.fileWriteOutOfSpace)))
        #expect(!MarkdownFolderDestination.isTaken(POSIXError(.EIO)))
    }

    // MARK: - Vaults, looked up off the main thread

    @Test func aSlowLookupIsUnknownAndNotTriedAgainForAMinute() async throws {
        let calls = Locked(initialState: 0)
        let clock = Locked(initialState: Date(timeIntervalSince1970: 1_792_000_000))
        let release = DispatchSemaphore(value: 0)
        let roots = VaultRoots(timeout: 0.5, retryAfter: 60, now: { clock.withLock { $0 } }) { _ in
            calls.withLock { $0 += 1 }
            release.wait()
            return nil
        }
        let folder = URL(fileURLWithPath: "/Volumes/Gone NAS/Vault/Inbox", isDirectory: true)
        #expect(roots.lookUp(folder) == .unknown)  // waited half a second at most
        #expect(roots.lookUp(folder, fresh: true) == .unknown)  // at once: not tried again
        #expect(roots.cached(folder) == .unknown)
        #expect(calls.withLock { $0 } == 1, "one lookup at a time")
        release.signal()
        for _ in 0..<200 where roots.cached(folder) == .unknown { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(roots.cached(folder) == VaultRoots.Answer.noVault, "what the slow lookup found is kept")
        // A minute later it may be asked again.
        clock.withLock { $0 += 61 }
        release.signal()
        #expect(roots.lookUp(folder, fresh: true) == VaultRoots.Answer.noVault)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func theCacheIsOnlyReadAndALookupStartsInTheBackground() async throws {
        let root = try tempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let roots = VaultRoots()
        #expect(roots.cached(inbox) == .unknown)  // nothing yet: a lookup started
        for _ in 0..<200 where roots.cached(inbox) == .unknown { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(roots.cached(inbox).isVault)
        #expect(MarkdownFolderDestination(folder: inbox, roots: roots).name == "Obsidian")
        let saved = try await MarkdownFolderDestination(folder: inbox, roots: roots).save(draft("Hi"))
        #expect(saved.destinationName == "Obsidian")
    }

}

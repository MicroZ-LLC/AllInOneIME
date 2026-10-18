import Foundation

/// `@note` into a folder of Markdown files (an Obsidian vault, or any folder): a new file per note, named after its first
/// line (`fileName(for:existing:)`), holding front matter and then the whole text as typed (`document(for:)`). A file
/// is only ever created, never written over: a name that's taken gets " 2", " 3" … The folder is never made: one that
/// isn't there (an unmounted volume, a moved vault) is an error.
///
/// The note is written to a hidden file of its own in the folder first, then given its name in one step that fails when
/// the name is taken (`FileOps.swap` without `exists`: `renamex_np(RENAME_EXCL)`, Linux's `renameat2(RENAME_NOREPLACE)`;
/// where the volume can't, a hard link): there is never half a note under its name, and never one over another. A write
/// that fails removes the hidden file: nothing is left behind.
public struct MarkdownFolderDestination: NoteDestination {
    public let folder: URL
    /// Writes a new file (the hidden one), never over one: injectable, for the tests to fail it.
    public typealias Write = @Sendable (_ data: Data, _ file: URL) throws -> Void
    private let write: Write
    private let roots: VaultRoots

    public init(folder: URL, roots: VaultRoots = .shared, write: @escaping Write = MarkdownFolderDestination.writeNew) {
        self.folder = folder
        self.roots = roots
        self.write = write
    }

    /// `data` in a new file at `file`; an error when something is there already.
    public static let writeNew: Write = { data, file in try data.write(to: file, options: .withoutOverwriting) }

    /// "Obsidian" in a vault, else the folder's name in quotes, as the notice shows it: “Inbox”. On the main thread only
    /// what is remembered (`VaultRoots.cached`: the folder's name until a lookup in the background has answered);
    /// elsewhere looked up, a second at most.
    public var name: String {
        Self.name(of: folder, Thread.isMainThread ? roots.cached(folder) : roots.lookUp(folder))
    }

    static func name(of folder: URL, _ answer: VaultRoots.Answer) -> String {
        answer.isVault ? "Obsidian" : "“" + folder.lastPathComponent + "”"
    }

    public var leavesDevice: Bool { false }

    public func save(_ draft: NoteDraft) async throws -> SavedNoteRef {
        guard Self.isFolder(folder) else { throw NoteError.folderMissing(path: folder.path) }
        let data = Data(Self.document(for: draft).utf8)
        var existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let hidden = folder.appendingPathComponent(".\(UUID().uuidString).allinoneime-note.tmp", isDirectory: false)
        do {
            try write(data, hidden)
        } catch {
            throw failed(error, leaving: hidden)
        }
        // A name taken meanwhile (another app writing there): the next one.
        for _ in 0..<1000 {
            let name = Self.fileName(for: draft, existing: existing)
            let file = folder.appendingPathComponent(name, isDirectory: false)
            do {
                try Self.place(hidden, at: file)
            } catch where Self.isTaken(error) {
                existing.insert(name)
                continue
            } catch {
                throw failed(error, leaving: hidden)
            }
            // Looked up again here, off the main thread: the notice says where it went ("Saved to Obsidian").
            let answer = roots.lookUp(folder, fresh: true)
            return SavedNoteRef(id: file.absoluteString, title: NotesFormat.title(of: draft.text),
                                destinationName: Self.name(of: folder, answer))
        }
        try? FileManager.default.removeItem(at: hidden)
        throw CocoaError(.fileWriteFileExists)
    }

    /// A write or a rename that failed: the hidden file removed (whatever of it was written), and the folder gone
    /// meanwhile said as such.
    private func failed(_ error: Error, leaving hidden: URL) -> Error {
        try? FileManager.default.removeItem(at: hidden)
        return Self.isFolder(folder) ? error : NoteError.folderMissing(path: folder.path)
    }

    /// `hidden` given the name `file`, never over another file: in one step, else (a volume that can't) as a second name
    /// (a hard link), the hidden one then removed. Throws `isTaken` when the name is.
    static func place(_ hidden: URL, at file: URL) throws {
        do {
            try Platform.current.files.swap(hidden, into: file, exists: false)
            return
        } catch where isTaken(error) {
            throw error
        } catch {
            // No exclusive rename here (some network and FAT volumes): a link fails just the same when the name is taken.
        }
        try FileManager.default.linkItem(at: hidden, to: file)
        try? FileManager.default.removeItem(at: hidden)
    }

    /// Whether `error` is the name being taken (EEXIST), and nothing else.
    static func isTaken(_ error: Error) -> Bool {
        if let error = error as? POSIXError { return error.code == .EEXIST }
        if let error = error as? CocoaError {
            if error.code == .fileWriteFileExists { return true }
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                return underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(POSIXErrorCode.EEXIST.rawValue)
            }
        }
        return false
    }

    public func check() async throws -> String {
        guard Self.isFolder(folder) else { throw NoteError.folderMissing(path: folder.path) }
        return name
    }

    static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: - The file

    /// The longest a file name may be, in UTF-8 bytes (macOS, Windows and Linux all take 255).
    static let maxNameBytes = 255

    /// The new file's name, ".md" included: the note's title (`NotesFormat.title`, at most 80 characters) with each of
    /// `/\:*?"<>|#^[]` and control characters as "-", dots and spaces trimmed at either end, a Windows device name
    /// ("CON") with "_" after it; nothing left, the time it was written ("Note 2026-10-17 1403"). Taken in `existing`
    /// (the folder's names; any case, and an iCloud placeholder `.name.icloud` too): " 2", " 3" … before ".md".
    public static func fileName(for draft: NoteDraft, existing: Set<String>) -> String {
        var base = sanitized(NotesFormat.title(of: draft.text))
        if base.isEmpty { base = timeName(draft) }
        let taken = Set(existing.flatMap { name -> [String] in
            var names = [folded(name)]
            // iCloud Drive keeps a file not downloaded yet as ".<name>.icloud".
            if name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > ".icloud".count + 1 {
                names.append(folded(String(name.dropFirst().dropLast(".icloud".count))))
            }
            return names
        })
        var number = 1
        while true {
            let suffix = (number == 1 ? "" : " \(number)") + ".md"
            let name = fitted(base, bytes: maxNameBytes - suffix.utf8.count) + suffix
            if !taken.contains(folded(name)) { return name }
            number += 1
        }
    }

    /// The front matter (when it was written, ISO 8601 with its offset), then the text as typed: UTF-8, line endings LF.
    public static func document(for draft: NoteDraft) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = draft.timeZone
        let text = draft.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return "---\ncreated: \(formatter.string(from: draft.created))\n---\n" + text
    }

    /// The folder holding `.obsidian` (an Obsidian vault): `folder` itself or one it is in, on the same volume (the walk
    /// stops where the volume does, its device number changing: never up through `/Volumes` or `/`); nil when there is
    /// none, or `folder` isn't there. It looks at the disk, so not on the main thread (`VaultRoots`).
    public static func vaultRoot(of folder: URL) -> URL? {
        // Links followed first: a vault reached through one (~/Vault → /Volumes/Disk/Vault) is on the volume it leads to.
        var current = folder.resolvingSymlinksInPath().standardizedFileURL
        guard let volume = device(of: current) else { return nil }
        while true {
            if isFolder(current.appendingPathComponent(".obsidian", isDirectory: true)) { return current }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path || current.path == "/" || current.path.isEmpty { return nil }
            guard device(of: parent) == volume else { return nil }
            current = parent
        }
    }

    /// The volume `url` is on (`stat`'s `st_dev`); nil when it isn't there.
    private static func device(of url: URL) -> UInt64? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemNumber] as? NSNumber)?.uint64Value
    }

    /// What opens a saved file: Obsidian (`obsidian://open?path=`, the file's absolute path) when it is in a vault, else
    /// the file itself (in its default app). On the main thread, only what `VaultRoots` remembers of its folder;
    /// elsewhere looked up again, a second at most.
    public static func openURL(for file: URL) -> URL {
        let folder = file.deletingLastPathComponent()
        let answer = Thread.isMainThread ? VaultRoots.shared.cached(folder) : VaultRoots.shared.lookUp(folder, fresh: true)
        guard answer.isVault else { return file }
        let path = file.standardizedFileURL.path.addingPercentEncoding(withAllowedCharacters: unreserved) ?? file.path
        return URL(string: "obsidian://open?path=" + path) ?? file
    }

    /// What a URL's query value keeps as it is (RFC 3986's unreserved characters): everything else is escaped, "/" "&"
    /// and spaces too.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    // MARK: - Names

    /// What Windows, macOS and Obsidian's links can't have in a name.
    private static let forbidden = Set("/\\:*?\"<>|#^[]".unicodeScalars)

    /// Windows' device names, which no file may be called (whatever its extension).
    private static let reserved: Set<String> = Set(["CON", "PRN", "AUX", "NUL"]
        + (1...9).map { "COM\($0)" } + (1...9).map { "LPT\($0)" })

    static func sanitized(_ title: String) -> String {
        var out = ""
        for scalar in title.unicodeScalars {
            let control = scalar.properties.generalCategory == .control
            out.unicodeScalars.append(forbidden.contains(scalar) || control ? "-" : scalar)
        }
        return deviceNameAvoided(trimmed(out))
    }

    /// Dots and spaces trimmed at either end (Windows drops them; a leading dot hides the file).
    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
    }

    /// "CON" → "CON_", "con.notes" → "con_.notes".
    private static func deviceNameAvoided(_ name: String) -> String {
        let stem = name.prefix { $0 != "." }
        guard reserved.contains(stem.uppercased()) else { return name }
        return stem + "_" + name.dropFirst(stem.count)
    }

    /// `base` cut, by whole characters, to at most `bytes` UTF-8 bytes (trimmed again at the end it was cut at).
    private static func fitted(_ base: String, bytes: Int) -> String {
        guard base.utf8.count > bytes else { return base }
        var cut = ""
        for character in base {
            if cut.utf8.count + String(character).utf8.count > bytes { break }
            cut.append(character)
        }
        let fitted = trimmed(cut)
        return fitted.isEmpty ? "Note" : fitted
    }

    /// A name compared as macOS and Windows compare them: any case, either Unicode form.
    private static func folded(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// "Note 2026-10-17 1403": when it was written, in its time zone.
    private static func timeName(_ draft: NoteDraft) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = draft.timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.created)
        func two(_ n: Int?) -> String { n.map { $0 < 10 ? "0\($0)" : "\($0)" } ?? "00" }
        return "Note \(c.year ?? 0)-\(two(c.month))-\(two(c.day)) \(two(c.hour))\(two(c.minute))"
    }
}

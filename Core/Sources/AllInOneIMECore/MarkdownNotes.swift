import Foundation

/// `@note` into a folder of Markdown files (an Obsidian vault, or any folder): a new file per note, named after its first
/// line (`fileName(for:existing:)`), holding front matter and then the whole text as typed (`document(for:)`). A file
/// is only ever created, never written over: a name that's taken gets " 2", " 3" … The folder is never made: one that
/// isn't there (an unmounted volume, a moved vault) is an error.
public struct MarkdownFolderDestination: NoteDestination {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// "Obsidian" in a vault, else the folder's name in quotes, as the notice shows it: “Inbox”.
    public var name: String {
        Self.vaultRoot(of: folder) != nil ? "Obsidian" : "“" + folder.lastPathComponent + "”"
    }

    public var leavesDevice: Bool { false }

    public func save(_ draft: NoteDraft) async throws -> SavedNoteRef {
        let fm = FileManager.default
        guard Self.isFolder(folder) else { throw NoteError.folderMissing(path: folder.path) }
        let data = Data(Self.document(for: draft).utf8)
        var existing = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        // A name taken meanwhile (another app writing there): the next one.
        for _ in 0..<1000 {
            let name = Self.fileName(for: draft, existing: existing)
            let file = folder.appendingPathComponent(name, isDirectory: false)
            do {
                try data.write(to: file, options: .withoutOverwriting)
                return SavedNoteRef(id: file.absoluteString, title: NotesFormat.title(of: draft.text))
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                existing.insert(name)
            } catch where fm.fileExists(atPath: file.path) && !existing.contains(name) {
                // Made by another app between the listing and the write (an exclusive create fails before writing).
                existing.insert(name)
            } catch {
                // The folder went away meanwhile.
                if !Self.isFolder(folder) { throw NoteError.folderMissing(path: folder.path) }
                throw error
            }
        }
        throw CocoaError(.fileWriteFileExists)
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

    /// The folder holding `.obsidian` (an Obsidian vault): `folder` itself or one it is in; nil when there is none.
    public static func vaultRoot(of folder: URL) -> URL? {
        var current = folder.standardizedFileURL
        while true {
            if isFolder(current.appendingPathComponent(".obsidian", isDirectory: true)) { return current }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path || current.path == "/" || current.path.isEmpty { return nil }
            current = parent
        }
    }

    /// What opens a saved file: Obsidian (`obsidian://open?path=`, the file's absolute path) when it is in a vault, else
    /// the file itself (in its default app).
    public static func openURL(for file: URL) -> URL {
        guard vaultRoot(of: file.deletingLastPathComponent()) != nil else { return file }
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

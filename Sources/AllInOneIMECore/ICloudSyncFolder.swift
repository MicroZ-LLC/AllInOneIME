import Crypto
import Foundation

/// The folder the Macs share (`ICloudSync`): `AllInOneIME` in iCloud Drive (`iCloudDrive`), or any folder (the tests and
/// the self-test use a temporary one, two "Macs" at once). iCloud Drive is plain files in the user's Library, so the
/// Developer ID build needs no iCloud entitlement; the system syncs the files.
///
/// A file another Mac wrote may not be downloaded yet: a placeholder (`.settings.json.icloud`, as iCloud Drive left them
/// before macOS 14), or a dataless file that iCloud says isn't current. `read` never reads one (that could wait on the
/// network): it asks iCloud to download it and says so, and the caller waits for it. A placeholder is never "no file", nor
/// an empty one.
public struct ICloudSyncFolder: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// ~/Library/Mobile Documents/com~apple~CloudDocs: iCloud Drive itself.
    public static func iCloudDriveRoot(home: URL = CorePaths.home) -> URL {
        home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    /// iCloud Drive's AllInOneIME folder.
    public static func iCloudDrive(home: URL = CorePaths.home) -> ICloudSyncFolder {
        ICloudSyncFolder(url: iCloudDriveRoot(home: home).appendingPathComponent(ICloudSync.folderName, isDirectory: true))
    }

    /// Whether the drive it is in (the folder above it) is there and can be written: iCloud Drive turned on for this
    /// Mac's Apple Account. The folder itself is made on the first sync.
    public var isAvailable: Bool {
        let drive = url.deletingLastPathComponent().path
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: drive, isDirectory: &isFolder) && isFolder.boolValue
            && FileManager.default.isWritableFile(atPath: drive)
    }

    /// Whether the folder exists (something was synced, or is coming down from iCloud).
    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// What `read` found.
    public enum Contents: Equatable, Sendable {
        /// No such file (nor a placeholder of one).
        case missing
        /// It isn't downloaded yet: iCloud was asked to download it.
        case placeholder
        case data(Data)
    }

    /// The placeholder iCloud Drive leaves for a file not downloaded: ".<name>.icloud" beside it.
    public static func placeholderName(of name: String) -> String { "." + name + ".icloud" }

    /// The name a placeholder stands for ("settings.json" for ".settings.json.icloud"), or nil for another file.
    public static func name(ofPlaceholder file: String) -> String? {
        guard file.hasPrefix("."), file.hasSuffix(".icloud"), file.count > ".icloud".count + 1 else { return nil }
        return String(file.dropFirst().dropLast(".icloud".count))
    }

    /// The file `name` (a path in the folder: "settings.json", "rime/…"), if it is here and downloaded.
    public func read(_ name: String) throws -> Contents {
        let file = url.appendingPathComponent(name)
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else {
            let placeholder = file.deletingLastPathComponent().appendingPathComponent(Self.placeholderName(of: file.lastPathComponent))
            guard fm.fileExists(atPath: placeholder.path) else { return .missing }
            Self.startDownloading(file)
            return .placeholder
        }
        guard Self.isDownloaded(file) else {
            Self.startDownloading(file)
            return .placeholder
        }
        return .data(try Data(contentsOf: file))
    }

    /// Writes `data` as `name` in one step (another reader sees the old file or the new one), making the folder first;
    /// `private`: readable by the user only from the start (0600), as the recent questions are on the Mac.
    public func write(_ name: String, _ data: Data, private: Bool = false) throws {
        let file = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if `private` {
            try QuestionHistory.replace(file, with: data)
        } else {
            try data.write(to: file, options: .atomic)
        }
    }

    /// Moves `name` aside, never overwriting it or anything: "settings.json" → "settings (unreadable 2026-10-16 180501).json".
    /// The new name.
    public func setAside(_ name: String, now: Date = Date()) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var aside = ""
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : " \(attempt + 1)"
            aside = "\(stem) (unreadable \(formatter.string(from: now))\(suffix))" + (ext.isEmpty ? "" : "." + ext)
            if !FileManager.default.fileExists(atPath: url.appendingPathComponent(aside).path) { break }
        }
        // `moveItem` never replaces a file that is there.
        try FileManager.default.moveItem(at: url.appendingPathComponent(name), to: url.appendingPathComponent(aside))
        return aside
    }

    /// Asks iCloud to download every placeholder and not-downloaded file under `subfolder` (the other Macs' Rime
    /// snapshots before Rime merges them). How many were asked for.
    @discardableResult
    public func downloadAll(in subfolder: String) -> Int {
        let base = url.appendingPathComponent(subfolder)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return 0 }
        var asked = 0
        for case let file as URL in walker {
            if let real = Self.name(ofPlaceholder: file.lastPathComponent) {
                Self.startDownloading(file.deletingLastPathComponent().appendingPathComponent(real))
                asked += 1
            } else if !Self.isDownloaded(file) {
                Self.startDownloading(file)
                asked += 1
            }
        }
        return asked
    }

    /// Placeholders anywhere under `subfolder`: files still coming down.
    public func placeholders(in subfolder: String) -> [String] {
        let base = url.appendingPathComponent(subfolder)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { ($0 as? URL).flatMap { Self.name(ofPlaceholder: $0.lastPathComponent) } }
    }

    /// "Remove from iCloud…": the folder goes to the Trash (iCloud Drive's own, where it can be put back for a while).
    public func remove() throws {
        guard exists else { return }
        try Platform.current.files.trash(url)
    }

    /// Whether iCloud has `file` downloaded: true for a file that isn't in iCloud at all (a temporary folder).
    static func isDownloaded(_ file: URL) -> Bool {
        guard let values = try? file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true, let status = values.ubiquitousItemDownloadingStatus else { return true }
        return status == .current
    }

    static func startDownloading(_ file: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: file)
    }
}

extension ICloudSync {
    /// This Mac's hardware as the sync record keeps it: a hash of its platform UUID (never the UUID itself), so that a
    /// record copied from another Mac by Migration Assistant is told by it. The app reads the UUID (IOKit on a Mac:
    /// `MachineIdentity` in the input method) and gives it to the engine (`ICloudSyncEngine.machineID`).
    public static func machineID(platformUUID uuid: String) -> String {
        SHA256.hash(data: Data(("AllInOneIME sync machine " + uuid).utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// Rime's own user-data sync for the learned words: `sync_dir` in Rime's `installation.yaml` (in the Rime user folder)
/// names the shared folder; each Mac's Rime installation (`installation_id`, its own) writes a snapshot of its user
/// dictionaries in a folder of its own there and merges the others' into its own (`RimeService.syncUserData`).
public enum RimeSync {
    /// `installation.yaml`'s text with `sync_dir` set to `folder` (nil: removed), every other line as it was
    /// (`installation_id` is never touched: it is this Mac's).
    public static func installation(_ text: String, syncDir folder: String?) -> String {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        lines.removeAll { $0.hasPrefix("sync_dir:") }
        if let folder {
            let quoted = "\"" + folder.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
            lines.append("sync_dir: " + quoted)
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    /// The `sync_dir` `installation.yaml` names, if any.
    public static func syncDir(in text: String) -> String? {
        guard let line = text.components(separatedBy: "\n").first(where: { $0.hasPrefix("sync_dir:") }) else { return nil }
        var value = line.dropFirst("sync_dir:".count).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
        }
        return value
    }

    /// Takes `sync_dir` out of `installation.yaml`, only when it is `ours` (a folder the user set there stays). Whether it did.
    @discardableResult
    public static func removeSyncDir(ifItIs ours: URL, userDataDir: URL) throws -> Bool {
        let file = userDataDir.appendingPathComponent("installation.yaml")
        guard let text = try? String(contentsOf: file, encoding: .utf8), let current = syncDir(in: text),
              URL(fileURLWithPath: current).standardizedFileURL.path == ours.standardizedFileURL.path else { return false }
        try Data(installation(text, syncDir: nil).utf8).write(to: file, options: .atomic)
        return true
    }

    /// `installation.yaml` without its `installation_id`, so that librime makes a new one (this Rime folder was copied
    /// from another Mac, whose installation it would otherwise pass for). Whether there was one.
    @discardableResult
    public static func resetInstallationID(userDataDir: URL) throws -> Bool {
        let file = userDataDir.appendingPathComponent("installation.yaml")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
        let lines = text.components(separatedBy: "\n")
        let kept = lines.filter { !$0.hasPrefix("installation_id:") }
        guard kept.count != lines.count else { return false }
        try Data(kept.joined(separator: "\n").utf8).write(to: file, options: .atomic)
        return true
    }

    /// Sets (or removes) `sync_dir` in `userDataDir/installation.yaml`, writing it only when it changes. Whether it did.
    @discardableResult
    public static func setSyncDir(_ folder: URL?, userDataDir: URL) throws -> Bool {
        let file = userDataDir.appendingPathComponent("installation.yaml")
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        guard syncDir(in: text) != folder?.path else { return false }
        if folder == nil, text.isEmpty { return false }
        try FileManager.default.createDirectory(at: userDataDir, withIntermediateDirectories: true)
        try Data(installation(text, syncDir: folder?.path).utf8).write(to: file, options: .atomic)
        return true
    }
}

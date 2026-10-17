import Foundation

/// An input language's data beyond English, which needs none: dictionaries and schemas for an engine the
/// app carries (librime for pinyin). The app ships English only; the user downloads a pack in Settings →
/// Input (`LanguagePackLibrary`). Data only: a pack never carries code (no Lua, no libraries), and the Lua
/// scripts its schemas use come from the app bundle (`LanguagePackStore.linkCode`).
public struct LanguagePack: Sendable, Equatable, Hashable, Identifiable {
    /// Folder and index name: "zh-pinyin".
    public let id: String
    /// The input language it makes available.
    public let language: Language
    /// Files that must be there for the engine to start: a pack without them isn't installed.
    public let requiredFiles: [String]
    public let name: LocalizedText

    public static let chinesePinyin = LanguagePack(
        id: "zh-pinyin", language: .chinese,
        requiredFiles: ["pack.json", "default.yaml", "rime_ice.schema.yaml", "build/rime_ice.table.bin"],
        name: LocalizedText(en: "Chinese (pinyin)", zh: "中文（拼音）"))

    /// Korean: the 2-set layout's keys and how jamo make syllables (`HangulTables`).
    public static let koreanHangul = LanguagePack(
        id: "ko-hangul", language: .korean, requiredFiles: ["pack.json", HangulTables.fileName],
        name: LocalizedText(en: "Korean", zh: "韩语"))

    /// Hindi: Latin letters as they sound in Devanagari, and common words (`HindiTables`).
    public static let hindiPhonetic = LanguagePack(
        id: "hi-phonetic", language: .hindi, requiredFiles: ["pack.json", HindiTables.fileName],
        name: LocalizedText(en: "Hindi", zh: "印地语"))

    /// Every pack this app knows how to use. Japanese, … come here as new engines are added.
    public static let catalog = [chinesePinyin, koreanHangul, hindiPhonetic]

    /// The pack `language` needs; nil when it needs none (English).
    public static func `for`(_ language: Language) -> LanguagePack? {
        catalog.first { $0.language == language }
    }
}

/// A pack's `pack.json`, at the top of its archive: which pack and version the data is.
public struct LanguagePackManifest: Codable, Equatable, Sendable {
    public var id: String
    public var version: String
    /// What the data was built from, for the settings and bug reports: "rime-ice 2026.06.30".
    public var upstream: String?

    public init(id: String, version: String, upstream: String? = nil) {
        self.id = id
        self.version = version
        self.upstream = upstream
    }
}

/// `install.json` in an installed pack's folder.
public struct LanguagePackRecord: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Downloaded from the pack library (checked against the signed index).
        case library
        /// Taken over from an earlier app version that bundled the data (`LanguagePackStore.adopt`).
        case app
    }

    public var id: String
    public var version: String
    public var source: Source
    /// The archive's sha256, for a library install.
    public var sha256: String?

    public init(id: String, version: String, source: Source, sha256: String? = nil) {
        self.id = id
        self.version = version
        self.source = source
        self.sha256 = sha256
    }
}

public enum LanguagePackError: Error, LocalizedError, Equatable {
    case unreachable(String)
    case http(status: Int, file: String)
    case tooLarge(String)
    case missingSignature
    case badSignature
    case unsupportedSchema(Int)
    case malformedIndex
    /// The library has no version of the pack this app can use.
    case notOffered(String)
    case invalidEntry(String)
    case hashMismatch
    case unpack(String)
    /// The archive holds something a pack may not: code, links, a file outside it, or misses a required file.
    case invalidContent(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .unreachable(host): return "Can't reach \(host)"
        case let .http(status, file): return "The download server answered HTTP \(status) for \(file)"
        case let .tooLarge(file): return "\(file) is larger than the index says"
        case .missingSignature: return "The language pack index isn't signed"
        case .badSignature:
            return "The language pack index failed its signature check (it may be mid-update: try again in a few minutes)"
        case let .unsupportedSchema(schema): return "The language packs need a newer AllInOneIME (index schema \(schema))"
        case .malformedIndex: return "The language pack index can't be read"
        case let .notOffered(id): return "No version of \(id) for this AllInOneIME is available yet"
        case let .invalidEntry(detail): return "The language pack index has a bad entry: \(detail)"
        case .hashMismatch: return "The download doesn't match the signed index; nothing was changed"
        case let .unpack(detail): return "Couldn't unpack the language pack: \(detail)"
        case let .invalidContent(detail): return "The language pack isn't valid: \(detail)"
        case .cancelled: return "Cancelled"
        }
    }

    init(_ error: PluginLibraryError) {
        switch error {
        case .missingSignature: self = .missingSignature
        default: self = .badSignature
        }
    }
}

/// Where packs are installed: one folder per pack (`<id>/`), which is the engine's data folder as it is
/// (librime's shared data directory), with `install.json` saying where it came from.
public struct LanguagePackStore: Sendable {
    public static var defaultDirectory: URL {
        CorePaths.dataDir.appendingPathComponent("LanguagePacks", isDirectory: true)
    }

    public var directory: URL

    public init(directory: URL = LanguagePackStore.defaultDirectory) {
        self.directory = directory
    }

    public func folder(_ pack: LanguagePack) -> URL {
        directory.appendingPathComponent(pack.id, isDirectory: true)
    }

    /// The install record of `pack`, if it is installed and complete (its required files are there).
    public func installed(_ pack: LanguagePack) -> LanguagePackRecord? {
        let folder = folder(pack)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("install.json")),
              let record = try? JSONDecoder().decode(LanguagePackRecord.self, from: data), record.id == pack.id,
              pack.requiredFiles.allSatisfy({ FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) })
        else { return nil }
        return record
    }

    /// Bytes on disk of an installed pack (shown before removing it).
    public func size(_ pack: LanguagePack) -> Int64 {
        let folder = folder(pack)
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { walker.skipDescendants(); continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Deletes an installed pack. The engine may still have it open: it keeps working until it's started anew.
    public func remove(_ pack: LanguagePack) throws {
        let folder = folder(pack)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        // Renamed away first, so the folder is gone in one step even if deleting the files takes a moment.
        let trash = directory.appendingPathComponent(".\(pack.id).removing-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: folder, to: trash)
        try? FileManager.default.removeItem(at: trash)
    }

    /// Installs `pack` from a data folder an earlier app bundled (`Contents/SharedSupport/rime`): copied
    /// without its code (Lua) and checked like a download, then put in place in one step. An existing
    /// install is left alone. For upgrades: a user who typed pinyin keeps it without a download.
    @discardableResult
    public func adopt(_ pack: LanguagePack, from source: URL, version: String) throws -> LanguagePackRecord {
        if let record = installed(pack) { return record }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(pack.id).tmp-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: temporary) }
        try fm.copyItem(at: source, to: temporary)
        for item in Self.codeFolders { try? fm.removeItem(at: temporary.appendingPathComponent(item)) }
        // What the app bundled had no pack.json: written for it, like a download's.
        let manifest = LanguagePackManifest(id: pack.id, version: version, upstream: nil)
        try JSONEncoder().encode(manifest).write(to: temporary.appendingPathComponent("pack.json"))
        let record = LanguagePackRecord(id: pack.id, version: version, source: .app)
        try finish(pack, temporary: temporary, record: record)
        return record
    }

    /// Checks an unpacked pack in `temporary`, writes its record and swaps it into place.
    func finish(_ pack: LanguagePack, temporary: URL, record: LanguagePackRecord) throws {
        try Self.validate(temporary, pack: pack)
        try JSONEncoder().encode(record).write(to: temporary.appendingPathComponent("install.json"))
        let destination = folder(pack)
        try PluginLibrary.moveIntoPlace(temporary, destination)
    }

    /// Folders of code an engine's data may come with (rime-ice's Lua): never taken from a pack.
    static let codeFolders = ["lua"]
    /// Extensions of files that are code (scripts, libraries, executables; Windows' too, as a pack is the same everywhere):
    /// a pack with one is refused.
    static let codeExtensions: Set<String> = ["lua", "dylib", "so", "bundle", "app", "framework", "sh", "py", "js", "rb", "pl", "command", "plugin",
                                              "exe", "dll", "com", "bat", "cmd", "ps1", "psm1", "vbs", "wsf", "hta", "msi", "scr", "lnk"]

    /// A pack folder that is data only: plain files and folders (no links, no special files), nothing
    /// with code's extension, no code folder, every required file present, and a pack.json naming this pack.
    static func validate(_ folder: URL, pack: LanguagePack) throws {
        let fm = FileManager.default
        for item in codeFolders where fm.fileExists(atPath: folder.appendingPathComponent(item).path) {
            throw LanguagePackError.invalidContent("it has code (\(item)/)")
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isExecutableKey]
        guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: keys) else {
            throw LanguagePackError.invalidContent("unreadable")
        }
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: Set(keys))
            let name = url.lastPathComponent
            if values.isSymbolicLink == true { throw LanguagePackError.invalidContent("it has a link (\(name))") }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw LanguagePackError.invalidContent("it has a special file (\(name))") }
            if codeExtensions.contains(url.pathExtension.lowercased()) {
                throw LanguagePackError.invalidContent("it has code (\(name))")
            }
            // Data never needs to run: whatever the archive said, nothing in it is executable.
            if values.isExecutable == true { try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        }
        for file in pack.requiredFiles where !fm.fileExists(atPath: folder.appendingPathComponent(file).path) {
            throw LanguagePackError.invalidContent("\(file) is missing")
        }
        guard let manifest = try? JSONDecoder().decode(LanguagePackManifest.self, from: Data(contentsOf: folder.appendingPathComponent("pack.json"))),
              manifest.id == pack.id else {
            throw LanguagePackError.invalidContent("pack.json doesn't name \(pack.id)")
        }
    }

    /// Points the pack's `lua/` at the app's own copy of the scripts its schemas use (`code`), replacing
    /// whatever link was there; removes it when the app has none. Called before every engine start, so a
    /// moved or updated app is followed. The pack itself never holds code (`validate`).
    public func linkCode(_ pack: LanguagePack, from code: URL?) throws {
        let link = folder(pack).appendingPathComponent("lua")
        let fm = FileManager.default
        // On Windows a link's target reads back with "\" ("C:\…\rime-lua"), a URL's path with "/": spelled alike first.
        if let current = try? fm.destinationOfSymbolicLink(atPath: link.path),
           (CorePaths.isSeparator("\\") ? current.replacingOccurrences(of: "\\", with: "/") : current) == code?.path { return }
        if (try? fm.attributesOfItem(atPath: link.path)) != nil {
            // Only ever our link: a real folder here would be code that didn't come from the app.
            try fm.removeItem(at: link)
        }
        if let code { try fm.createSymbolicLink(at: link, withDestinationURL: code) }
    }
}

/// Upgrades from versions that bundled the Chinese data: who keeps pinyin.
public enum LanguagePackMigration {
    /// Whether this user typed Chinese before packs existed: their settings have Chinese among the input
    /// languages (a file from before input languages counts: it decodes with Chinese), or, with no
    /// settings file at all, librime has deployed for them (the default had Chinese then).
    public static func wantsChinese(configFile: URL = Config.defaultURL, rimeUserFolder: URL) -> Bool {
        if FileManager.default.fileExists(atPath: configFile.path) {
            guard let data = try? Data(contentsOf: configFile), let config = try? JSONDecoder().decode(Config.self, from: data) else {
                return true  // unreadable: keep what they may have had rather than take pinyin away
            }
            return config.inputLanguages.contains(.chinese)
        }
        return hasDeployed(rimeUserFolder)
    }

    /// librime has deployed in this user folder (it writes `installation.yaml` and `build/` then).
    public static func hasDeployed(_ rimeUserFolder: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: rimeUserFolder.appendingPathComponent("installation.yaml").path)
            || fm.fileExists(atPath: rimeUserFolder.appendingPathComponent("build").path)
    }
}

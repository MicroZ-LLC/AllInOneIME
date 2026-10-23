import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Coding languages (spec 2, decision 22): packages of their own kind, the Code input's (Settings → Input, under Code:
// never among the input languages' packs). Each pack is one JSON file (`CodingLanguagePack`) from the language library
// (the same as language packs': https://languages.allinoneime.com/), listed in its signed `coding-packs.json` (the
// language packs' key), checked against its sha256 and size there and for what it holds before it is kept.

/// The language library's `coding-packs.json`: every coding pack version on offer.
public struct CodingPackIndex: Decodable, Equatable, Sendable {
    public var schema: Int
    public var generated: String?
    public var packs: [Entry]

    public struct Entry: Codable, Equatable, Sendable {
        /// The pack's language ("python").
        public var language: String
        public var title: String
        public var version: String
        public var minAppVersion: String?
        /// The pack's file: an https address (a release asset of the library), or a path relative to the library.
        public var url: String
        public var sha256: String
        public var size: Int64

        public init(language: String, title: String, version: String, minAppVersion: String? = nil, url: String, sha256: String,
                    size: Int64) {
            self.language = language
            self.title = title
            self.version = version
            self.minAppVersion = minAppVersion
            self.url = url
            self.sha256 = sha256
            self.size = size
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        generated = try c.decodeIfPresent(String.self, forKey: .generated)
        // An entry this app can't read (a field a later schema changed) is left out, not the whole index.
        packs = try c.decode([Lenient].self, forKey: .packs).compactMap(\.entry)
    }

    private enum CodingKeys: String, CodingKey { case schema, generated, packs }

    private struct Lenient: Decodable {
        var entry: Entry?
        init(from decoder: Decoder) throws { entry = try? Entry(from: decoder) }
    }
}

extension CodingLanguagePack {
    /// The most a pack may be, and hold.
    public static let maxBytes = 1 << 20
    static let maxKeywords = 2000
    static let maxSnippets = 500

    /// Why `self` isn't a pack to keep (nil: it is): its language ([a-z0-9+#-], 1–32), a title and a version, at most
    /// `maxKeywords` keywords of 1–64 characters and `maxSnippets` snippets each with a trigger of identifier characters
    /// and a body of 4,000 characters at most.
    public var problem: String? {
        guard Self.isLanguage(language) else { return "the language must be 1–32 small letters, digits, +, # or -" }
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty, !version.isEmpty else { return "no title or version" }
        guard keywords.count <= Self.maxKeywords, keywords.allSatisfy({ (1...64).contains($0.count) && !$0.contains(where: \.isWhitespace) })
        else { return "keywords must be words of 1–64 characters (\(Self.maxKeywords) at most)" }
        guard snippets.count <= Self.maxSnippets,
              snippets.allSatisfy({ (1...64).contains($0.trigger.count) && $0.trigger.allSatisfy(SuggestionsToken.isIdentifierCharacter)
                                      && !$0.body.isEmpty && $0.body.count <= 4000 }) else {
            return "snippets need a trigger of letters, digits or _ and a body of 4,000 characters at most"
        }
        return nil
    }

    /// Whether `id` can be a pack's language (`Config.codingLanguage`): 1–32 small letters, digits, +, # or -.
    public static func isLanguage(_ id: String) -> Bool {
        (1...32).contains(id.count) && id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || "+#-".contains($0)) }
    }

    /// The coding languages the Code input offers, in the order its menu lists them: the language library's packs.
    public static let offered: [(language: String, title: String)] = [
        ("python", "Python"), ("java", "Java"), ("go", "Go"), ("typescript", "TypeScript"), ("javascript", "JavaScript"),
        ("c", "C"), ("cpp", "C++"),
    ]

    /// The name of the coding language `language` ("Python"): as offered, else an installed pack's own title (a language
    /// a later library added), else the id.
    public static func title(of language: String, installed: [CodingLanguagePack] = []) -> String {
        offered.first { $0.language == language }?.title ?? installed.first { $0.language == language }?.title ?? language
    }
}

/// Where coding packs are kept: `<language>.json` each, in the app's data folder (`CodingPacks/`), read once a change
/// shows (the folder's date and the files').
public final class CodingPackStore: @unchecked Sendable {
    public static var defaultDirectory: URL { CorePaths.dataDir.appendingPathComponent("CodingPacks", isDirectory: true) }

    public let directory: URL
    private let cache = Locked<(stamp: [String: Date], packs: [CodingLanguagePack])?>(initialState: nil)

    public init(directory: URL = CodingPackStore.defaultDirectory) {
        self.directory = directory
    }

    /// The packs installed, by language; one that can't be read (or isn't a pack) is left out.
    public func installed() -> [CodingLanguagePack] {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
        var stamp: [String: Date] = [:]
        for file in files {
            stamp[file.lastPathComponent] = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        if let kept = cache.withLock({ $0 }), kept.stamp == stamp { return kept.packs }
        let packs = files.compactMap { file -> CodingLanguagePack? in
            guard let data = try? Data(contentsOf: file), data.count <= CodingLanguagePack.maxBytes,
                  let pack = try? JSONDecoder().decode(CodingLanguagePack.self, from: data), pack.problem == nil,
                  file.deletingPathExtension().lastPathComponent == pack.language else { return nil }
            return pack
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        cache.withLock { $0 = (stamp, packs) }
        return packs
    }

    /// `data` kept as the pack of `language` (it must be one, of that language), in place of the one before, in one step.
    @discardableResult
    public func keep(_ data: Data, language: String, version: String? = nil) throws -> CodingLanguagePack {
        guard data.count <= CodingLanguagePack.maxBytes, let pack = try? JSONDecoder().decode(CodingLanguagePack.self, from: data)
        else { throw LanguagePackError.invalidContent("not a coding pack") }
        if let problem = pack.problem { throw LanguagePackError.invalidContent(problem) }
        guard pack.language == language, version.map({ $0 == pack.version }) ?? true else {
            throw LanguagePackError.invalidContent("the pack doesn't match the index")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Platform.current.files.writePrivate(data, to: directory.appendingPathComponent(language + ".json"))
        cache.withLock { $0 = nil }
        return pack
    }

    /// The pack of `language` removed.
    public func remove(_ language: String) throws {
        guard CodingLanguagePack.isLanguage(language) else { return }
        let file = directory.appendingPathComponent(language + ".json")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        cache.withLock { $0 = nil }
    }
}

/// Downloads and installs coding packs from the language library, as language packs are (`LanguagePackLibrary`: the
/// index's signature checked with the key built into the app before it is read, a pack kept only once its sha256 and
/// size match the index and it reads as a pack of its language). Network only when the user asks.
public struct CodingPackLibrary: Sendable {
    public static let indexName = "coding-packs.json"
    public static let schema = 1

    public var baseURL: URL
    public var publicKey: Data
    public var configuration: URLSessionConfiguration
    public var appVersion: String
    public var store: CodingPackStore
    /// Plain http to this computer (a test server): only for tests.
    public var allowsLocalHTTP: Bool

    public init(baseURL: URL = LanguagePackLibrary.defaultBaseURL, publicKey: Data = LanguagePackLibrary.publicKey,
                configuration: URLSessionConfiguration? = nil, appVersion: String = AppVersion.string,
                store: CodingPackStore = CodingPackStore(), allowsLocalHTTP: Bool = false) {
        self.baseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL : URL(string: baseURL.absoluteString + "/")!
        self.publicKey = publicKey
        self.configuration = configuration ?? LanguagePackLibrary.makeConfiguration()
        self.appVersion = appVersion
        self.store = store
        self.allowsLocalHTTP = allowsLocalHTTP
    }

    public func fetchIndex() async throws -> CodingPackIndex {
        let index = try await fetch(Self.indexName, limit: LanguagePackLibrary.maxIndexBytes)
        let signature: Data
        do {
            signature = try await fetch(Self.indexName + ".sig", limit: 4096)
        } catch LanguagePackError.http(status: 404, _) {
            throw LanguagePackError.missingSignature
        }
        return try Self.verify(index: index, signature: signature, publicKey: publicKey)
    }

    /// The index in `data`, if `signature` is the key's signature of exactly these bytes (checked first).
    public static func verify(index data: Data, signature: Data, publicKey: Data) throws -> CodingPackIndex {
        do {
            try PluginLibrary.checkSignature(data, signature: signature, publicKey: publicKey)
        } catch let error as PluginLibraryError {
            throw LanguagePackError(error)
        }
        struct Schema: Decodable { var schema: Int }
        guard let schema = try? JSONDecoder().decode(Schema.self, from: data).schema else { throw LanguagePackError.malformedIndex }
        guard schema == Self.schema else { throw LanguagePackError.unsupportedSchema(schema) }
        guard let index = try? JSONDecoder().decode(CodingPackIndex.self, from: data) else { throw LanguagePackError.malformedIndex }
        return index
    }

    /// The newest version of each language this app can use, by title.
    public func offered(in index: CodingPackIndex) -> [CodingPackIndex.Entry] {
        let usable = index.packs.filter { entry in
            CodingLanguagePack.isLanguage(entry.language) && (entry.minAppVersion.map { SemVer.compare(appVersion, $0) >= 0 } ?? true)
        }
        return Dictionary(grouping: usable, by: \.language).values
            .compactMap { $0.max { SemVer.compare($0.version, $1.version) < 0 } }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Downloads `entry`'s pack (its size and sha256 checked as it comes) and keeps it in place of the one before.
    @discardableResult
    public func install(_ entry: CodingPackIndex.Entry, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws
        -> CodingLanguagePack {
        guard CodingLanguagePack.isLanguage(entry.language) else { throw LanguagePackError.invalidEntry(entry.language) }
        guard entry.sha256.count == 64, entry.sha256.allSatisfy(\.isHexDigit) else { throw LanguagePackError.invalidEntry("sha256") }
        guard entry.size > 0, entry.size <= CodingLanguagePack.maxBytes else { throw LanguagePackError.invalidEntry("size") }
        guard let url = URL(string: entry.url, relativeTo: baseURL)?.absoluteURL, isAllowed(url) else {
            throw LanguagePackError.invalidEntry(entry.url)
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("coding-pack-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let hash = try await Download.run(url, to: work, expectedSize: entry.size, configuration: configuration,
                                          allowsLocalHTTP: allowsLocalHTTP, progress: progress)
        guard hash == entry.sha256.lowercased() else { throw LanguagePackError.hashMismatch }
        return try store.keep(Data(contentsOf: work), language: entry.language, version: entry.version)
    }

    /// `language`'s pack, the newest version the library offers this app (`offered`), downloaded and kept in place of the
    /// one before: what picking a coding language whose pack isn't installed does (the Code input's menu, decision 22),
    /// as adding an input language downloads its pack. The library has none for it: `notOffered`.
    @discardableResult
    public func install(language: String, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> CodingLanguagePack {
        guard let entry = offered(in: try await fetchIndex()).first(where: { $0.language == language }) else {
            throw LanguagePackError.notOffered(CodingLanguagePack.title(of: language))
        }
        return try await install(entry, progress: progress)
    }

    func isAllowed(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return allowsLocalHTTP && LanguagePackLibrary.isLocal(url)
        default: return false
        }
    }

    private func fetch(_ path: String, limit: Int) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        guard isAllowed(url) else { throw LanguagePackError.unreachable(url.absoluteString) }
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw LanguagePackError.unreachable(url.host ?? url.absoluteString)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw LanguagePackError.http(status: status, file: path) }
        guard data.count <= limit else { throw LanguagePackError.tooLarge(path) }
        return data
    }
}

import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The language pack library's `packs.json`: every pack version on offer, each an archive (.tar.xz) with
/// its sha256. Signed with the plugin library's key and served next to its index; only ever built from
/// bytes whose signature was verified.
public struct LanguagePackIndex: Decodable, Equatable, Sendable {
    public var schema: Int
    public var generated: String?
    public var packs: [Entry]

    public struct Entry: Decodable, Equatable, Sendable {
        public var id: String
        public var version: String
        public var minAppVersion: String?
        /// The archive: an https address (a GitHub release asset: too large for the library's git
        /// repository), or a path relative to the library.
        public var url: String
        public var sha256: String
        /// The archive's exact size in bytes (the download stops beyond it, and the progress goes by it).
        public var size: Int64
        /// Bytes once unpacked, shown before downloading.
        public var installedSize: Int64?
        public var upstream: String?
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

/// Downloads and installs language packs, from their own library (https://languages.allinoneime.com/: the
/// MicroZ-LLC/AllInOneIME-languages repository, its archives release assets there), signed with their own
/// key (`publicKey`; the private half is in the maintainer's login keychain, service
/// `allinoneime-languages-signing`), apart from the plugins'. Same trust as the plugin library: the index's
/// signature is checked with the key built into the app before it is read, and an archive is unpacked only once its
/// sha256 matches the index. Unpacked with the system's tar (which refuses ".." and absolute paths),
/// then checked to be data only (`LanguagePackStore.validate`) and swapped into place in one step.
/// Network only when the user asks (or once, on upgrade, for a user who had Chinese).
public struct LanguagePackLibrary: Sendable {
    public static let indexName = "packs.json"
    public static let defaultBaseURL = URL(string: "https://languages.allinoneime.com/")!
    /// The public half of the language packs' Ed25519 signing key.
    public static let publicKey = Data(base64Encoded: "MYnQfpeOxhKUAowyQUmJU0RgCZe5/tA8oFc2YszlGQ8=")!
    public static let schema = 1
    public static let maxIndexBytes = 1 << 20
    /// Unpacked size cap, whatever the index says: a pack is dictionaries, not a disk filler.
    public static let maxInstalledBytes: Int64 = 2 << 30

    public var baseURL: URL
    public var publicKey: Data
    public var configuration: URLSessionConfiguration
    public var appVersion: String
    public var store: LanguagePackStore
    /// Plain http to this Mac (a test server): only for the developer commands and tests.
    public var allowsLocalHTTP: Bool

    public init(baseURL: URL = LanguagePackLibrary.defaultBaseURL, publicKey: Data = LanguagePackLibrary.publicKey,
                configuration: URLSessionConfiguration? = nil, appVersion: String = AppVersion.string,
                store: LanguagePackStore = LanguagePackStore(), allowsLocalHTTP: Bool = false) {
        self.baseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL : URL(string: baseURL.absoluteString + "/")!
        self.publicKey = publicKey
        self.configuration = configuration ?? Self.makeConfiguration()
        self.appVersion = appVersion
        self.store = store
        self.allowsLocalHTTP = allowsLocalHTTP
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        // Tens of megabytes on a slow line: the resource timeout is generous, a stall still ends it.
        configuration.timeoutIntervalForResource = 3600
        return configuration
    }

    // MARK: Index

    public func fetchIndex() async throws -> LanguagePackIndex {
        let index = try await fetch(Self.indexName, limit: Self.maxIndexBytes)
        let signature: Data
        do {
            signature = try await fetch(Self.indexName + ".sig", limit: 4096)
        } catch LanguagePackError.http(status: 404, _) {
            throw LanguagePackError.missingSignature
        }
        return try Self.verify(index: index, signature: signature, publicKey: publicKey)
    }

    /// The index in `data`, if `signature` is the key's signature of exactly these bytes (checked first).
    public static func verify(index data: Data, signature: Data, publicKey: Data) throws -> LanguagePackIndex {
        do {
            try PluginLibrary.checkSignature(data, signature: signature, publicKey: publicKey)
        } catch let error as PluginLibraryError {
            throw LanguagePackError(error)
        }
        struct Schema: Decodable { var schema: Int }
        guard let schema = try? JSONDecoder().decode(Schema.self, from: data).schema else { throw LanguagePackError.malformedIndex }
        guard schema == Self.schema else { throw LanguagePackError.unsupportedSchema(schema) }
        guard let index = try? JSONDecoder().decode(LanguagePackIndex.self, from: data) else { throw LanguagePackError.malformedIndex }
        return index
    }

    /// The newest version of `pack` this app can use.
    public func newest(_ pack: LanguagePack, in index: LanguagePackIndex) -> LanguagePackIndex.Entry? {
        index.packs
            .filter { $0.id == pack.id && ($0.minAppVersion.map { SemVer.compare(appVersion, $0) >= 0 } ?? true) }
            .max { SemVer.compare($0.version, $1.version) < 0 }
    }

    // MARK: Installing

    /// Fetches the index and installs the newest usable version of `pack`. `progress` gets the share
    /// downloaded (0…1), from any thread.
    @discardableResult
    public func install(_ pack: LanguagePack, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> LanguagePackRecord {
        let index = try await fetchIndex()
        guard let entry = newest(pack, in: index) else { throw LanguagePackError.notOffered(pack.id) }
        return try await install(entry, pack: pack, progress: progress)
    }

    /// Downloads `entry`'s archive (checking its size and sha256 as it comes), unpacks it into a
    /// temporary folder, checks it is `pack`'s data and nothing else, then swaps it into place. Any
    /// failure leaves the installed pack as it was.
    @discardableResult
    public func install(_ entry: LanguagePackIndex.Entry, pack: LanguagePack,
                        progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> LanguagePackRecord {
        guard entry.id == pack.id else { throw LanguagePackError.invalidEntry(entry.id) }
        guard entry.sha256.count == 64, entry.sha256.allSatisfy(\.isHexDigit) else { throw LanguagePackError.invalidEntry("sha256") }
        guard entry.size > 0 else { throw LanguagePackError.invalidEntry("size") }
        guard let url = URL(string: entry.url, relativeTo: baseURL)?.absoluteURL, isAllowed(url) else {
            throw LanguagePackError.invalidEntry(entry.url)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let work = store.directory.appendingPathComponent(".\(pack.id).tmp-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        try fm.createDirectory(at: work, withIntermediateDirectories: false)
        let archive = work.appendingPathComponent("pack.tar.xz")
        let hash = try await Download.run(url, to: archive, expectedSize: entry.size, configuration: configuration,
                                          allowsLocalHTTP: allowsLocalHTTP, progress: progress)
        guard hash == entry.sha256.lowercased() else { throw LanguagePackError.hashMismatch }

        let unpacked = work.appendingPathComponent("data", isDirectory: true)
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: false)
        try Self.unpack(archive, into: unpacked)
        try? fm.removeItem(at: archive)
        let size = LanguagePackStore.sizeOfFolder(unpacked)
        guard size <= Self.maxInstalledBytes else { throw LanguagePackError.invalidContent("too large unpacked") }
        let manifest = try? JSONDecoder().decode(LanguagePackManifest.self, from: Data(contentsOf: unpacked.appendingPathComponent("pack.json")))
        guard manifest?.version == entry.version else { throw LanguagePackError.invalidContent("pack.json doesn't match the index") }
        let record = LanguagePackRecord(id: pack.id, version: entry.version, source: .library, sha256: entry.sha256.lowercased())
        try store.finish(pack, temporary: unpacked, record: record)
        return record
    }

    /// https anywhere (the signed hash, not the host, vouches for the bytes); http only to this Mac, when allowed.
    func isAllowed(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return allowsLocalHTTP && Self.isLocal(url)
        default: return false
        }
    }

    static func isLocal(_ url: URL) -> Bool { ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "") }

    /// The system's tar (bsdtar): refuses entries with ".." or an absolute path and doesn't extract
    /// through links; no owners, extended attributes or Mac metadata.
    static func unpack(_ archive: URL, into folder: URL) throws {
        let errors = Pipe()
        let tar = try Platform.current.processes.launch(LaunchSpec(
            executable: systemTar,
            arguments: ["-x", "-J", "-f", archive.path, "-C", folder.path, "--no-same-owner", "--no-xattrs", "--no-mac-metadata", "--no-acls", "--no-fflags"],
            standardOutput: .null, standardError: .pipe(errors)))
        let message = errors.fileHandleForReading.readDataToEndOfFile()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            throw LanguagePackError.unpack(String(decoding: message, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// /usr/bin/tar; on Windows (10 and later) its own bsdtar, in System32 (the variable's name in any case).
    static var systemTar: URL {
        #if os(Windows)
        let root = ProcessInfo.processInfo.environment.first { $0.key.uppercased() == "SYSTEMROOT" }?.value ?? #"C:\Windows"#
        return URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("System32/tar.exe")
        #else
        return URL(fileURLWithPath: "/usr/bin/tar")
        #endif
    }

    // MARK: Network

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

extension LanguagePackStore {
    static func sizeOfFolder(_ folder: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker { total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        return total
    }
}

/// One archive download into a file: hashed and counted as it arrives (never more than the index's
/// size), with progress; follows redirects only to https (GitHub sends release assets elsewhere), or only
/// where `allowsRedirect` says (the app's own updates: GitHub's release servers).
final class Download: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let file: FileHandle
    private let expectedSize: Int64
    private let allowsLocalHTTP: Bool
    private let allowsRedirect: (@Sendable (URL) -> Bool)?
    private let progress: @Sendable (Double) -> Void
    private var hasher = SHA256()
    private var received: Int64 = 0
    private var failure: LanguagePackError?
    private var continuation: CheckedContinuation<String, Error>?
    private var lastReported = -1.0

    private init(file: FileHandle, expectedSize: Int64, allowsLocalHTTP: Bool, allowsRedirect: (@Sendable (URL) -> Bool)?,
                 progress: @escaping @Sendable (Double) -> Void) {
        self.file = file
        self.expectedSize = expectedSize
        self.allowsLocalHTTP = allowsLocalHTTP
        self.allowsRedirect = allowsRedirect
        self.progress = progress
    }

    /// Downloads `url` into `destination` and returns its sha256 (hex).
    static func run(_ url: URL, to destination: URL, expectedSize: Int64, configuration: URLSessionConfiguration,
                    allowsLocalHTTP: Bool, allowsRedirect: (@Sendable (URL) -> Bool)? = nil,
                    progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil),
              let file = try? FileHandle(forWritingTo: destination) else { throw LanguagePackError.unpack("can't write the download") }
        defer { try? file.close() }
        let download = Download(file: file, expectedSize: expectedSize, allowsLocalHTTP: allowsLocalHTTP,
                                allowsRedirect: allowsRedirect, progress: progress)
        let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                download.lock.withLock { download.continuation = continuation }
                if Task.isCancelled { download.fail(.cancelled, task) } else { task.resume() }
            }
        } onCancel: {
            download.fail(.cancelled, task)
        }
    }

    private func fail(_ error: LanguagePackError, _ task: URLSessionTask) {
        lock.withLock { if failure == nil { failure = error } }
        task.cancel()
        finish(nil)
    }

    private func finish(_ error: Error?) {
        let (continuation, result): (CheckedContinuation<String, Error>?, Result<String, Error>) = lock.withLock {
            let pending = self.continuation
            self.continuation = nil
            if let failure { return (pending, .failure(failure)) }
            if let error { return (pending, .failure(error)) }
            if received != expectedSize { return (pending, .failure(LanguagePackError.hashMismatch)) }
            return (pending, .success(hasher.finalize().map { String(format: "%02x", $0) }.joined()))
        }
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            lock.withLock { if failure == nil { failure = .http(status: status, file: dataTask.originalRequest?.url?.lastPathComponent ?? "") } }
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let share: Double? = lock.withLock {
            guard failure == nil else { return nil }
            received += Int64(data.count)
            guard received <= expectedSize else {
                failure = .tooLarge(dataTask.originalRequest?.url?.lastPathComponent ?? "the download")
                return nil
            }
            hasher.update(data: data)
            do { try file.write(contentsOf: data) } catch { failure = .unpack("can't write the download") }
            let share = Double(received) / Double(expectedSize)
            // About every percent: the settings redraw on each report.
            guard share - lastReported >= 0.01 || share >= 1 else { return nil }
            lastReported = share
            return share
        }
        if let share { progress(share) } else if lock.withLock({ failure != nil }) { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let url = request.url
        let ok = allowsRedirect.map { allows in url.map(allows) ?? false }
            ?? (url?.scheme?.lowercased() == "https" || (allowsLocalHTTP && url.map(LanguagePackLibrary.isLocal) == true))
        if !ok { lock.withLock { failure = .unreachable(url?.absoluteString ?? "") } }
        completionHandler(ok ? request : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error.map { _ in LanguagePackError.unreachable(task.originalRequest?.url?.host ?? "the download server") })
    }
}

import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `update.json` (https://allinoneime.com/update.json, from the site's public/ folder): the newest release, written
/// and signed by `Scripts/build-update-manifest.swift` (`make update-manifest`) with the releases' own Ed25519
/// key, apart from the plugins' and the language packs'. Only ever built from bytes whose signature was verified.
public struct UpdateManifest: Decodable, Equatable, Sendable {
    public var schema: Int
    public var generated: String?
    /// CFBundleShortVersionString and CFBundleVersion of the apps in the download.
    public var version: String
    public var build: String
    /// LSMinimumSystemVersion: an older macOS is told so instead of offered the update.
    public var minimumSystemVersion: String
    /// The update archive (`AllInOneIME-<version>-update.zip`: both apps, as the installer's Payload.zip has
    /// them): a release asset on GitHub, or a file on allinoneime.com (`UpdateURLPolicy`).
    public var url: String
    public var sha256: String
    /// The archive's exact size in bytes (the download stops beyond it, and the progress goes by it).
    public var size: Int64
    /// The release's page, and what's new in a sentence or two, by language ("en", "zh").
    public var notesURL: String?
    public var summary: [String: String]?

    public func summary(chinese: Bool) -> String? {
        let text = summary?[chinese ? "zh" : "en"] ?? summary?["en"]
        return text?.isEmpty == false ? text : nil
    }
}

public enum UpdateError: Error, LocalizedError, Equatable {
    case unreachable(String)
    case http(status: Int, file: String)
    case tooLarge(String)
    case missingSignature
    /// Not signed by the releases' key: tampered with, or caught mid-update.
    case badSignature
    case unsupportedSchema(Int)
    case malformedManifest
    /// The manifest's version isn't newer than the one installed: never installed (no downgrades).
    case notNewer(String)
    case needsNewerSystem(String)
    /// An address the updater doesn't download from (`UpdateURLPolicy`), or a bad hash or size.
    case invalidManifest(String)
    case sizeMismatch
    case hashMismatch
    case unpack(String)
    /// The archive's apps aren't the ones the manifest names (bundle ID, version, signature, or they don't start).
    case invalidApp(String)
    /// This copy isn't the installed one (~/Library/Input Methods/AllInOneIME.app): nothing to update in place.
    case notInstalled
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .unreachable(host): return "Can't reach \(host)"
        case let .http(status, file): return "The update server answered HTTP \(status) for \(file)"
        case let .tooLarge(file): return "\(file) is larger than the update manifest says"
        case .missingSignature: return "The update manifest isn't signed"
        case .badSignature: return "The update manifest failed its signature check (it may be mid-update: try again in a few minutes)"
        case let .unsupportedSchema(schema): return "The update manifest needs a newer AllInOneIME (schema \(schema))"
        case .malformedManifest: return "The update manifest can't be read"
        case let .notNewer(version): return "Version \(version) isn't newer than this one; nothing was changed"
        case let .needsNewerSystem(version): return "This update needs macOS \(version) or later"
        case let .invalidManifest(detail): return "The update manifest has a bad entry: \(detail)"
        case .sizeMismatch: return "The download's size doesn't match the signed manifest; nothing was changed"
        case .hashMismatch: return "The download doesn't match the signed manifest; nothing was changed"
        case let .unpack(detail): return "Couldn't unpack the update: \(detail)"
        case let .invalidApp(detail): return "The update isn't a valid AllInOneIME: \(detail); nothing was changed"
        case .notInstalled: return "This copy of AllInOneIME isn't the installed one; download the installer instead"
        case .cancelled: return "Cancelled"
        }
    }
}

/// Where updates may come from. The manifest's signature and the archive's sha256 vouch for the bytes; this
/// keeps the download itself to the places releases are published: https only, allinoneime.com or a release
/// asset of MicroZ-LLC/AllInOneIME on GitHub, and redirects only within GitHub's release servers. Plain http
/// to this Mac only for a test server, when allowed.
public enum UpdateURLPolicy {
    public static let site = "allinoneime.com"
    public static let releasesPath = "/MicroZ-LLC/AllInOneIME/releases/download/"
    /// Where github.com sends a release asset's download.
    public static let releaseAssetHosts: Set<String> = ["objects.githubusercontent.com", "release-assets.githubusercontent.com"]

    /// The manifest: https on allinoneime.com.
    public static func allowsManifest(_ url: URL, allowsLocalHTTP: Bool) -> Bool {
        if allowsLocalHTTP, isLocal(url) { return true }
        return isPlainHTTPS(url) && host(url) == site
    }

    /// The archive the manifest names.
    public static func allowsDownload(_ url: URL, allowsLocalHTTP: Bool) -> Bool {
        if allowsLocalHTTP, isLocal(url) { return true }
        guard isPlainHTTPS(url) else { return false }
        switch host(url) {
        case site: return true
        case "github.com": return url.path.hasPrefix(releasesPath) && !url.path.contains("/../")
        default: return false
        }
    }

    /// A redirect on the way to the manifest or its signature: only to the same host, or to allinoneime.com.
    public static func allowsManifestRedirect(to url: URL, from origin: URL, allowsLocalHTTP: Bool) -> Bool {
        if allowsLocalHTTP, isLocal(url), isLocal(origin) { return true }
        return isPlainHTTPS(url) && (host(url) == host(origin) || host(url) == site)
    }

    /// A redirect on the way to the archive: only to where a release download is, or GitHub's release servers.
    public static func allowsRedirect(to url: URL, allowsLocalHTTP: Bool) -> Bool {
        if allowsDownload(url, allowsLocalHTTP: allowsLocalHTTP) { return true }
        return isPlainHTTPS(url) && releaseAssetHosts.contains(host(url))
    }

    static func host(_ url: URL) -> String { url.host?.lowercased() ?? "" }

    /// https, the default port, no user name or password in it.
    static func isPlainHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }

    static func isLocal(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && LanguagePackLibrary.isLocal(url)
    }
}

/// When the input method looks for an update by itself: once a day at most (at launch, or when a text field is
/// activated: never on a keystroke), an hour after a check that failed (offline), and never when turned off.
public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 3600
    public static let retryInterval: TimeInterval = 3600

    /// `lastSuccess`: the last check that got an answer; `lastAttempt`: the last one started. A date in the
    /// future (the clock was set back) counts as long ago.
    public static func isDue(now: Date, lastSuccess: Date?, lastAttempt: Date?, enabled: Bool) -> Bool {
        guard enabled else { return false }
        func elapsed(_ date: Date?, _ interval: TimeInterval) -> Bool {
            guard let date else { return true }
            let since = now.timeIntervalSince(date)
            return since < 0 || since >= interval
        }
        return elapsed(lastSuccess, interval) && elapsed(lastAttempt, retryInterval)
    }
}

/// What a check found.
public enum UpdateAvailability: Equatable, Sendable {
    case upToDate
    case available
    /// Newer, but for a newer macOS than this one.
    case needsNewerSystem
}

/// The apps of an update, unpacked and checked, ready to be swapped in.
public struct UpdatePayload: Equatable, Sendable {
    public var inputMethod: URL
    public var settingsApp: URL

    public init(inputMethod: URL, settingsApp: URL) {
        self.inputMethod = inputMethod
        self.settingsApp = settingsApp
    }
}

/// AllInOneIME's own updates: the signed manifest, and its archive, downloaded and checked. The manifest's
/// signature is checked with the key built into the app before it is read; the archive is unpacked only once
/// its size and sha256 match the manifest, and its apps are used only when their bundle IDs, versions and code
/// signatures check out. A version that isn't newer than this one is never installed. Swapping the apps in
/// is the input method's (`--apply-update`, with `BundleSwap`).
public struct Updater: Sendable {
    public static let defaultManifestURL = URL(string: "https://allinoneime.com/update.json")!
    /// The public half of the releases' Ed25519 signing key; the private half is only in the maintainer's
    /// login keychain (service `allinoneime-releases-signing`).
    public static let publicKey = Data(base64Encoded: "+zppTAxWuTfrxrrxaK1aSQUv9fGX/A2gSeIImImme14=")!
    public static let schema = 1
    public static let maxManifestBytes = 64 << 10
    /// No release is anywhere near this: a disk filler is refused before it's downloaded.
    public static let maxArchiveBytes: Int64 = 1 << 30
    public static let inputMethodName = "AllInOneIME.app"
    public static let settingsAppName = "AllInOneIME Settings.app"
    public static let bundleID = "com.aipinyin.inputmethod.AIPinyin"
    public static let settingsBundleID = "com.aipinyin.settings"

    public var manifestURL: URL
    public var publicKey: Data
    public var configuration: URLSessionConfiguration
    public var currentVersion: String
    /// This Mac's macOS ("15.1.0").
    public var systemVersion: String
    /// Plain http to this Mac (a test server): only for the developer commands and tests.
    public var allowsLocalHTTP: Bool

    public init(manifestURL: URL = Updater.defaultManifestURL, publicKey: Data = Updater.publicKey,
                configuration: URLSessionConfiguration? = nil, currentVersion: String = AppVersion.string,
                systemVersion: String = Updater.thisSystem, allowsLocalHTTP: Bool = false) {
        self.manifestURL = manifestURL
        self.publicKey = publicKey
        self.configuration = configuration ?? Self.makeConfiguration()
        self.currentVersion = currentVersion
        self.systemVersion = systemVersion
        self.allowsLocalHTTP = allowsLocalHTTP
    }

    public static var thisSystem: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = LanguagePackLibrary.makeConfiguration()
        configuration.timeoutIntervalForRequest = 30
        return configuration
    }

    // MARK: Manifest

    /// Downloads update.json and its signature and returns the manifest, once the signature checks out.
    /// The bytes come back too: the input method keeps them to show the notice after a restart.
    public func fetchManifest() async throws -> (manifest: UpdateManifest, data: Data, signature: Data) {
        guard UpdateURLPolicy.allowsManifest(manifestURL, allowsLocalHTTP: allowsLocalHTTP) else {
            throw UpdateError.invalidManifest(manifestURL.absoluteString)
        }
        let signatureURL = URL(string: manifestURL.absoluteString + ".sig")!
        let data = try await fetch(manifestURL, limit: Self.maxManifestBytes)
        let signature: Data
        do {
            signature = try await fetch(signatureURL, limit: 4096)
        } catch UpdateError.http(status: 404, _) {
            throw UpdateError.missingSignature
        }
        return (try Self.verify(manifest: data, signature: signature, publicKey: publicKey), data, signature)
    }

    /// The manifest in `data`, if `signature` (base64) is the key's signature of exactly these bytes (checked
    /// before anything is parsed).
    public static func verify(manifest data: Data, signature: Data, publicKey: Data) throws -> UpdateManifest {
        do {
            try PluginLibrary.checkSignature(data, signature: signature, publicKey: publicKey)
        } catch PluginLibraryError.missingSignature {
            throw UpdateError.missingSignature
        } catch {
            throw UpdateError.badSignature
        }
        struct Schema: Decodable { var schema: Int }
        guard let schema = try? JSONDecoder().decode(Schema.self, from: data).schema else { throw UpdateError.malformedManifest }
        guard schema == Self.schema else { throw UpdateError.unsupportedSchema(schema) }
        guard let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: data) else { throw UpdateError.malformedManifest }
        return manifest
    }

    /// The manifest against this app and this Mac.
    public func availability(of manifest: UpdateManifest) -> UpdateAvailability {
        guard SemVer.compare(manifest.version, currentVersion) > 0 else { return .upToDate }
        return SemVer.compare(systemVersion, manifest.minimumSystemVersion) >= 0 ? .available : .needsNewerSystem
    }

    /// Fetches the manifest and says whether it's an update for this app.
    public func check() async throws -> (manifest: UpdateManifest, availability: UpdateAvailability, data: Data, signature: Data) {
        let fetched = try await fetchManifest()
        return (fetched.manifest, availability(of: fetched.manifest), fetched.data, fetched.signature)
    }

    // MARK: Download

    /// The manifest's archive, validated before any network: newer than this app (never a downgrade), for this
    /// macOS, a sha256 and a size, from an address `UpdateURLPolicy` allows.
    public func archiveURL(_ manifest: UpdateManifest) throws -> URL {
        switch availability(of: manifest) {
        case .upToDate: throw UpdateError.notNewer(manifest.version)
        case .needsNewerSystem: throw UpdateError.needsNewerSystem(manifest.minimumSystemVersion)
        case .available: break
        }
        guard manifest.sha256.count == 64, manifest.sha256.allSatisfy(\.isHexDigit) else { throw UpdateError.invalidManifest("sha256") }
        guard manifest.size > 0, manifest.size <= Self.maxArchiveBytes else { throw UpdateError.invalidManifest("size") }
        guard let url = URL(string: manifest.url), UpdateURLPolicy.allowsDownload(url, allowsLocalHTTP: allowsLocalHTTP) else {
            throw UpdateError.invalidManifest(manifest.url)
        }
        return url
    }

    /// Downloads the manifest's archive into `file`, checking its size as it comes and its sha256 at the end
    /// (a file that doesn't match is deleted). `progress` gets the share downloaded (0…1), from any thread.
    public func download(_ manifest: UpdateManifest, to file: URL,
                         progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let url = try archiveURL(manifest)
        let local = allowsLocalHTTP
        let hash: String
        do {
            hash = try await Download.run(url, to: file, expectedSize: manifest.size, configuration: configuration,
                                          allowsLocalHTTP: local,
                                          allowsRedirect: { UpdateURLPolicy.allowsRedirect(to: $0, allowsLocalHTTP: local) },
                                          progress: progress)
        } catch let error as LanguagePackError {
            try? FileManager.default.removeItem(at: file)
            switch error {
            // Short of the size (`Download` reports it as a mismatch), or beyond it.
            case .hashMismatch, .tooLarge: throw UpdateError.sizeMismatch
            case let .http(status, name): throw UpdateError.http(status: status, file: name)
            case let .unreachable(host): throw UpdateError.unreachable(host)
            case .cancelled: throw UpdateError.cancelled
            default: throw UpdateError.unpack(error.localizedDescription)
            }
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        guard hash == manifest.sha256.lowercased() else {
            try? FileManager.default.removeItem(at: file)
            throw UpdateError.hashMismatch
        }
    }

    // MARK: Network

    /// A small file (the manifest, its signature) of at most `limit` bytes: refused as soon as it's longer, as it
    /// comes, never read whole first. Redirects only to the same host or allinoneime.com (`ManifestRedirects`).
    private func fetch(_ url: URL, limit: Int) async throws -> Data {
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var data = Data()
        do {
            let redirects = ManifestRedirects(from: url, allowsLocalHTTP: allowsLocalHTTP)
            let (bytes, response) = try await HTTPStream.bytes(for: URLRequest(url: url), session: session, redirect: { redirects.request($0) })
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw UpdateError.http(status: status, file: url.lastPathComponent) }
            guard response.expectedContentLength <= Int64(limit) else { throw UpdateError.tooLarge(url.lastPathComponent) }
            for try await byte in bytes {
                guard data.count < limit else { throw UpdateError.tooLarge(url.lastPathComponent) }
                data.append(byte)
            }
        } catch let error as UpdateError {
            throw error
        } catch is CancellationError {
            throw UpdateError.cancelled
        } catch {
            throw UpdateError.unreachable(url.host ?? url.absoluteString)
        }
        return data
    }
}

/// The redirects the manifest and its signature may take (`UpdateURLPolicy.allowsManifestRedirect`); any other is
/// refused, and the redirect's own answer is then what comes back (not 200: refused too).
struct ManifestRedirects: Sendable {
    let origin: URL
    let allowsLocalHTTP: Bool

    init(from origin: URL, allowsLocalHTTP: Bool) {
        self.origin = origin
        self.allowsLocalHTTP = allowsLocalHTTP
    }

    func request(_ request: URLRequest) -> URLRequest? {
        guard let url = request.url, UpdateURLPolicy.allowsManifestRedirect(to: url, from: origin, allowsLocalHTTP: allowsLocalHTTP)
        else { return nil }
        return request
    }
}

/// What `--apply-update` left behind for the input method that starts next: whether the update went in, and
/// if not, why (the previous version is back). JSON in `UpdateResult.url`.
public struct UpdateResult: Codable, Equatable, Sendable {
    public var from: String
    public var to: String
    public var ok: Bool
    public var error: String?
    public var date: Date

    public init(from: String, to: String, ok: Bool, error: String? = nil, date: Date = Date()) {
        self.from = from
        self.to = to
        self.ok = ok
        self.error = error
        self.date = date
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func read(_ url: URL) -> UpdateResult? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: url)).flatMap { try? decoder.decode(UpdateResult.self, from: $0) }
    }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A cloud provider's connection opened ahead of a request (`Converter.warmConnection`). The shared session's connection
/// to a service closes after two or three minutes idle, and the request after the pause would wait for a new one: DNS,
/// TCP and TLS, 50 to 300 ms. Where nothing went to the service in the last `idle`, a HEAD goes to its origin
/// ("https://host:port/": no user or password, path or query of the base URL) on the same session, with no key, no
/// credentials and no body, any authentication asked of it refused, never redirected, so that the connection is open when
/// the request goes. One an idle period: a HEAD, or a request, counts as something sent there. Only for a provider at its
/// own default base URL (`isDefault`), to its host (`isBuiltIn`: the Claude API's, the Gemini API's, OpenAI's,
/// `bedrock-runtime.<region>.amazonaws.com`): never for a base URL of the user's, even one on another built-in provider's
/// host, never the hosted service; and only to one a real request has succeeded at before (`WarmOrigins`). Nothing of a key, the keychain, the environment or the AWS files
/// is read for it. One for each session (`BedrockClient`).
public final class ConnectionWarmth: Sendable {
    /// A service nothing went to for this long is idle: its connection may be gone by the time the request goes.
    public static let idle: TimeInterval = 90
    /// How long a HEAD may take before it's given up (it is only ever waited for by itself).
    static let timeout: TimeInterval = 10

    /// The origin ("https://host:port") → when something last went there (`now`).
    private let sent = Locked<[String: TimeInterval]>(initialState: [:])
    private let now: @Sendable () -> TimeInterval
    /// The origins a request succeeded at.
    let succeeded: WarmOrigins

    public init(succeeded: WarmOrigins = WarmOrigins(file: nil),
                now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.succeeded = succeeded
        self.now = now
    }

    /// A request goes to `url` now.
    func sending(to url: URL?) {
        guard let origin = url.flatMap(Self.origin) else { return }
        let time = now()
        sent.withLock { $0[origin] = time }
    }

    /// A request to `url` was answered (HTTP 200): its origin is remembered, where it is one a HEAD may go to
    /// (`isBuiltIn`).
    func answered(_ url: URL?) {
        guard let url, let head = Self.headURL(url), let origin = Self.origin(head) else { return }
        succeeded.remember(origin)
    }

    /// Whether a HEAD goes to `url` now: a built-in provider's host at its default address (`headURL`) that a request
    /// succeeded at before and nothing went to in the last `idle`. True marks it sent.
    func due(_ url: URL) -> Bool {
        guard let origin = Self.headURL(url).flatMap(Self.origin), succeeded.knows(origin) else { return false }
        let time = now()
        return sent.withLock { sent in
            if let last = sent[origin], time - last < Self.idle { return false }
            sent[origin] = time
            return true
        }
    }

    /// The HEAD to `url`'s origin on `session`, where it is due (`due`), off the caller's thread: never redirected (as no
    /// request to a provider is), any authentication challenge refused, its answer taken to its end, so that the
    /// connection stays open, and not looked at. True if it went.
    @discardableResult
    func warm(_ url: URL, session: URLSession) -> Bool {
        guard due(url), let head = Self.headURL(url) else { return false }
        var request = URLRequest(url: head, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = "HEAD"
        request.httpShouldHandleCookies = false
        Task.detached(priority: .utility) {
            guard let (body, _) = try? await HTTPStream.bytes(for: request, session: session, redirect: { _ in nil },
                                                              refusesAuthentication: true) else { return }
            do { for try await _ in body {} } catch {}
        }
        return true
    }

    /// Where the HEAD for a base URL goes: "https://host:port/", lowercased, nothing else of it (no user or password, no
    /// path, no query). Nil where none goes: not a built-in provider's host at its default address (`isBuiltIn`).
    static func headURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), isBuiltIn(host, port: url.port) else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = "/"
        return parts.url
    }

    /// The hosts of the built-in providers' default base URLs (`ProviderSettings.defaults`): the Claude API's, the Gemini
    /// API's, OpenAI's. Never the hosted service's.
    static let builtInHosts: Set<String> = Set([Provider.anthropic, .gemini, .openai].compactMap { provider in
        ProviderSettings.defaults(for: provider).baseURL.flatMap { URL(string: $0)?.host?.lowercased() }
    })

    /// Whether `host` (lowercased) on `port` (nil: https's own) is a built-in provider's at its default address: one of
    /// `builtInHosts`, or Bedrock's in a region ("bedrock-runtime.us-east-1.amazonaws.com", `BedrockClient.origin`), on
    /// port 443. A base URL of the user's (another host, another port, a relay, a model on this Mac) is never one.
    static func isBuiltIn(_ host: String, port: Int?) -> Bool {
        guard port == nil || port == 443, host != HostedService.host else { return false }
        if builtInHosts.contains(host) { return true }
        let prefix = "bedrock-runtime.", suffix = ".amazonaws.com"
        guard host.hasPrefix(prefix), host.hasSuffix(suffix), host.count > prefix.count + suffix.count else { return false }
        let region = host.dropFirst(prefix.count).dropLast(suffix.count)
        return (try? BedrockClient.origin(region: String(region)))?.host == host
    }

    /// Whether `base`, `provider`'s base URL in the settings, is the provider's own default one
    /// (`ProviderSettings.defaults`), with or without a "/" after it, its scheme and host in any case: a base URL of the
    /// user's is never warmed, not even one on another built-in provider's host (Anthropic's set to OpenAI's address).
    static func isDefault(_ base: String, for provider: Provider) -> Bool {
        func address(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(),
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.port == nil || url.port == 443
            else { return nil }
            return "\(scheme)://\(host)\(url.path)"
        }
        guard let own = ProviderSettings.defaults(for: provider).baseURL.flatMap(address) else { return false }
        return address(base) == own
    }

    /// "scheme://host:port" of `url`, lowercased: what a connection is kept for.
    static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }
}

/// The origins ("https://host:443") a real AI request succeeded at, and when it last did: where a connection may be
/// opened ahead of a request (`ConnectionWarmth`). One not succeeded at for `kept` is forgotten. Kept for the app in
/// `warm-origins.json` among the caches (`CorePaths.cacheDir`, this computer's, never synced, never in config.json): the
/// origins and the times only, never a key, a request or an answer. Safe from any thread; read and written off the key's
/// (by the requests and the HEADs).
public final class WarmOrigins: Sendable {
    /// The app's own (`BedrockClient()`'s): in the caches.
    public static let shared = WarmOrigins(file: CorePaths.cacheDir.appendingPathComponent("warm-origins.json"))

    /// How long an origin is remembered after the last request that succeeded there.
    public static let kept: TimeInterval = 30 * 24 * 3600
    /// A success at an origin remembered less than this ago isn't written again.
    static let rewrite: TimeInterval = 24 * 3600

    /// Where they are kept (nil: for the process only: a test's, a self-test's).
    let file: URL?
    private let today: @Sendable () -> Date
    /// The origin → when a request last succeeded there, read from `file` on first use.
    private let origins = Locked<[String: Date]?>(initialState: nil)

    public init(file: URL?, today: @escaping @Sendable () -> Date = { Date() }) {
        self.file = file
        self.today = today
    }

    /// Whether a request succeeded at `origin` in the last `kept`.
    func knows(_ origin: String) -> Bool {
        let now = today()
        return origins.withLock { origins in
            let known = origins ?? Self.read(file)
            origins = known
            return known[origin].map { now.timeIntervalSince($0) < Self.kept } ?? false
        }
    }

    /// The origin of these, `matching`, a request succeeded at last in the last `kept`.
    func latest(where matching: (String) -> Bool) -> String? {
        let now = today()
        return origins.withLock { origins in
            let known = origins ?? Self.read(file)
            origins = known
            return known.filter { matching($0.key) && now.timeIntervalSince($0.value) < Self.kept }.max { $0.value < $1.value }?.key
        }
    }

    /// A request succeeded at `origin` now: remembered, written where it is new or its last success was a day ago or more
    /// (those not succeeded at for `kept` left out).
    func remember(_ origin: String) {
        let now = today()
        origins.withLock { origins in
            var known = origins ?? Self.read(file)
            let last = known[origin]
            known[origin] = now
            known = known.filter { now.timeIntervalSince($0.value) < Self.kept }
            origins = known
            guard let file, last.map({ now.timeIntervalSince($0) >= Self.rewrite }) ?? true else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(known) else { return }
            // A cache: kept in memory when it can't be written.
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Platform.current.files.writePrivate(data, to: file)
        }
    }

    private static func read(_ file: URL?) -> [String: Date] {
        guard let file, let data = try? Data(contentsOf: file) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Date].self, from: data)) ?? [:]
    }
}

extension Converter {
    /// `provider`'s connection opened ahead of a request (`ConnectionWarmth`): to its base URL where that is the
    /// provider's own default one (`ConnectionWarmth.isDefault`; Bedrock: its region's endpoint, the region the settings
    /// name, else the one a request succeeded at last), and a request succeeded there before. Nothing for a base URL of
    /// the user's (also on another built-in provider's host), the hosted service or the on-device model. Off the caller's thread; nothing is waited for, and nothing read but what
    /// the warm-up remembers (`WarmOrigins`).
    public func warmConnection(to provider: Provider, config: Config) {
        let (warmth, session) = (client.bedrock.warmth, client.session)
        switch provider {
        case .anthropic, .gemini, .openai:
            let base = (config.settings(for: provider).baseURL ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            guard ConnectionWarmth.isDefault(base, for: provider), let url = URL(string: base), ConnectionWarmth.headURL(url) != nil
            else { return }
            Task.detached(priority: .utility) { warmth.warm(url, session: session) }
        case .bedrock:
            let region = config.region?.trimmingCharacters(in: .whitespaces)
            Task.detached(priority: .utility) {
                let named = region.flatMap { $0.isEmpty ? nil : try? BedrockClient.origin(region: $0) }
                let last = warmth.succeeded.latest { origin in
                    URL(string: origin).flatMap { $0.host }.map { $0.hasPrefix("bedrock-runtime.") } ?? false
                }
                guard let url = named ?? last.flatMap(URL.init(string:)) else { return }
                warmth.warm(url, session: session)
            }
        case .hosted, .apple:
            return
        }
    }
}

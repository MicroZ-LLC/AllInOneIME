import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A cloud provider's connection opened ahead of a request (`Converter.warmConnection`). The shared session's connection
/// to a service closes after two or three minutes idle, and the request after the pause would wait for a new one: DNS,
/// TCP and TLS, 50 to 300 ms. Where nothing went to the service in the last `idle`, a HEAD goes to its base URL on the
/// same session, with no key, no credentials and no body, so that the connection is open when the request goes. One an
/// idle period: a HEAD, or a request, counts as something sent there. Only to a host on the internet (`isPublic`): never
/// to the hosted service (a HEAD there would run it), by provider or by its host, nor to this Mac or the local network.
/// One for each session (`BedrockClient`).
public final class ConnectionWarmth: Sendable {
    /// A service nothing went to for this long is idle: its connection may be gone by the time the request goes.
    public static let idle: TimeInterval = 90
    /// How long a HEAD may take before it's given up (it is only ever waited for by itself).
    static let timeout: TimeInterval = 10

    /// The origin ("https://host:port") → when something last went there (`now`).
    private let sent = Locked<[String: TimeInterval]>(initialState: [:])
    private let now: @Sendable () -> TimeInterval

    public init(now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    /// A request goes to `url` now.
    func sending(to url: URL?) {
        guard let origin = url.flatMap(Self.origin) else { return }
        let time = now()
        sent.withLock { $0[origin] = time }
    }

    /// Whether a HEAD goes to `url` now: an https address on the internet (`isPublic`) nothing went to in the last
    /// `idle`, not the hosted service's. True marks it sent.
    func due(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), Self.isPublic(host),
              host != HostedService.host, let origin = Self.origin(url) else { return false }
        let time = now()
        return sent.withLock { sent in
            if let last = sent[origin], time - last < Self.idle { return false }
            sent[origin] = time
            return true
        }
    }

    /// The HEAD to `url` on `session`, where it is due (`due`), off the caller's thread: never redirected (as no request
    /// to a provider is), its answer taken to its end, so that the connection stays open, and not looked at. True if it
    /// went.
    @discardableResult
    func warm(_ url: URL, session: URLSession) -> Bool {
        guard due(url) else { return false }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = "HEAD"
        request.httpShouldHandleCookies = false
        Task.detached(priority: .utility) {
            guard let (body, _) = try? await HTTPStream.bytes(for: request, session: session, redirect: { _ in nil }) else { return }
            do { for try await _ in body {} } catch {}
        }
        return true
    }

    /// The names no host on the internet ends with: this computer, the local network, a VPN's own names (Tailscale's),
    /// and those set aside for tests and examples.
    static let privateSuffixes = ["local", "lan", "home", "home.arpa", "internal", "intranet", "corp", "private", "localhost",
                                  "localdomain", "test", "example", "invalid", "onion", "arpa", "ts.net", "alt"]

    /// Whether `host` (lowercased) is a name on the internet, the only place a HEAD goes: never an IP address in any of
    /// its spellings ("192.168.1.2", "127.1", "0x7f000001", "[::ffff:127.0.0.1]", "100.64.0.1"), a name of one label
    /// ("myserver", "localhost"), or one under a private-use name (`privateSuffixes`: "nas.lan", "box.home.arpa",
    /// "mac.tail1234.ts.net", "localhost." with its dot).
    static func isPublic(_ host: String) -> Bool {
        var host = host.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, !host.contains(":"), !host.contains("["), !host.contains("%") else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }), let last = labels.last else { return false }
        // A last label of digits (or "0x…") is an address: no top-level name is one.
        if last.allSatisfy(\.isNumber) || last.hasPrefix("0x") { return false }
        return !privateSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// "scheme://host:port" of `url`, lowercased: what a connection is kept for.
    static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }
}

extension Converter {
    /// `provider`'s connection opened ahead of a request (`ConnectionWarmth`), with `config`'s base URL (Bedrock: its
    /// region's endpoint, the region read from the settings or the AWS files, nothing run). Nothing for the hosted
    /// service or the on-device model. Off the caller's thread; nothing is waited for.
    public func warmConnection(to provider: Provider, config: Config) {
        let (warmth, session) = (client.bedrock.warmth, client.session)
        switch provider {
        case .anthropic, .gemini, .openai:
            let base = (config.settings(for: provider).baseURL ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            guard let url = URL(string: base) else { return }
            warmth.warm(url, session: session)
        case .bedrock:
            let (region, profile) = (config.region, config.awsProfile)
            Task.detached(priority: .utility) {
                let region = region ?? AWSSharedConfig.region(profile: profile) ?? "us-east-1"
                guard let url = try? BedrockClient.origin(region: region) else { return }
                warmth.warm(url, session: session)
            }
        case .hosted, .apple:
            return
        }
    }
}

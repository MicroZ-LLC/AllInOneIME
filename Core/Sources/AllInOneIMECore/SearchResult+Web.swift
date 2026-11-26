import Foundation

/// A web address typed after `@open`, as a result to open in the default browser.
extension SearchResult {
    /// The query as a web address to open, or nil: "https://…" and "www.…" always; a bare
    /// "name.tld/…" only for common top-level domains, so "report.pdf" or "Safari.app" stay file names;
    /// localhost and IP addresses, with a port or not ("localhost:3000", "192.168.1.1"), over http: a server
    /// on this Mac or the network, which mostly has no certificate.
    public static func web(_ query: String) -> SearchResult? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace), !text.hasPrefix("/"), !text.hasPrefix("~") else { return nil }
        let lower = text.lowercased()
        let explicit = lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.")
        if !explicit, let url = URL(string: "http://" + text), url.user == nil,
           let host = url.host?.lowercased(), host == "localhost" || isIPv4(host) {
            return SearchResult(name: name(of: url, host: host), path: url.absoluteString)
        }
        guard let url = webAddress(text), let host = url.host?.lowercased() else { return nil }
        if !explicit {
            guard let tld = host.split(separator: ".").last, commonDomains.contains(String(tld)) else { return nil }
        }
        return SearchResult(name: name(of: url, host: host), path: url.absoluteString)
    }

    /// The address as typed, made a URL: `example.com/a` → `https://example.com/a`. Nil unless http(s) with a host that
    /// has a dot in it (or localhost).
    static func webAddress(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), host.contains(".") || host == "localhost" else { return nil }
        return url
    }

    /// How a web address is listed: its host, port and path ("github.com/…", "localhost:3000").
    private static func name(of url: URL, host: String) -> String {
        host + (url.port.map { ":\($0)" } ?? "") + (url.path.count > 1 ? url.path : "")
    }

    /// Four numbers from 0 to 255 with dots between: 127.0.0.1, 192.168.1.1 (not 1.2.3, 999.1.1.1).
    static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            (1...3).contains(part.count) && part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber) && Int(part).map { $0 <= 255 } == true
        }
    }

    static let commonDomains: Set<String> = [
        "com", "org", "net", "io", "ai", "dev", "co", "me", "gov", "edu", "info", "xyz", "tech", "site", "so", "gg", "tv",
        "cn", "hk", "tw", "jp", "kr", "sg", "uk", "us", "ca", "au", "de", "fr", "eu", "in", "ru", "br",
    ]
}

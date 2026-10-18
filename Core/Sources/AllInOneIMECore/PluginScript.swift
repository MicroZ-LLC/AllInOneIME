import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One request a plugin script makes with `fetch`, and its answer.
public struct PluginRequest: Equatable, Sendable {
    public var url: String
    public var headers: [String: String]
}

public struct PluginResponse: Equatable, Sendable {
    public var status: Int
    public var text: String
    /// Set when there is no response (host not allowed, network error, too large, …).
    public var error: String?

    public init(status: Int = 0, text: String = "", error: String? = nil) {
        self.status = status
        self.text = text
        self.error = error
    }
}

/// What carries out a script's requests: `URLSessionFetcher`, or a stub in the tests. Blocking (the
/// script runs in its own process).
public protocol PluginFetcher: Sendable {
    func fetch(_ requests: [PluginRequest]) -> [PluginResponse]
}

public enum PluginScriptError: Error, LocalizedError, Equatable {
    /// The script threw, or `run` didn't return text: the message is shown.
    case failed(String)
    case noRunFunction

    public var errorDescription: String? {
        switch self {
        case let .failed(message): return message
        case .noRunFunction: return "The plugin has no run(input) function"
        }
    }
}

/// Runs a plugin's JavaScript: `run(input, context)` with nothing but `fetch` (see docs/plugins.md).
public enum PluginScript {
    /// The `fetch` scripts call, over the native one (`__fetch(urls, headers)` → [{status, text, error}]).
    static let prelude = """
        "use strict";
        const fetch = (function (native) {
          function response(r) {
            return { status: r.status, ok: r.status >= 200 && r.status < 300, text: r.text,
                     json() { return JSON.parse(r.text); } };
          }
          return function fetch(url, options) {
            const many = Array.isArray(url);
            const urls = (many ? url : [url]).map(String);
            const results = native(urls, (options && options.headers) || {});
            if (!many) {
              if (results[0].error) throw new Error(results[0].error);
              return response(results[0]);
            }
            return results.map(r => r.error ? { ok: false, status: 0, error: r.error, text: "",
                                                json() { throw new Error(r.error); } } : response(r));
          };
        })(__fetch);
        """

    /// What `run` gets after the text: `{language: "zh"}` or `{language: "en"}`, the input method's interface
    /// language, else `{}` (an older app, or a language the interface can't be in). Nothing else.
    static func context(language: Language?) -> [String: String] {
        guard let language, language == .chinese || language == .english else { return [:] }
        return ["language": language.rawValue]
    }

    public static func evaluate(source: String, input: String, language: Language? = nil, fetcher: PluginFetcher,
                                engine: any ScriptEngine = Platform.current.scripts) throws -> String {
        guard let context = engine.makeContext() else { throw PluginScriptError.failed("JavaScript is not available") }
        var thrown: String? { context.exception.map { $0.toString() ?? "error" } }
        let native = context.function { arguments in
            let list = (arguments.first?.toArray() ?? []).map { "\($0)" }
            let fields = ((arguments.count > 1 ? arguments[1].toDictionary() : nil) ?? [:]).mapValues { "\($0)" }
            return fetcher.fetch(list.map { PluginRequest(url: $0, headers: fields) }).map { r -> [String: Any] in
                var out: [String: Any] = ["status": r.status, "text": r.text]
                if let error = r.error { out["error"] = error }
                return out
            }
        }
        context.setGlobal("__fetch", native)
        context.evaluate(prelude)
        context.evaluate(source)
        if let thrown { throw PluginScriptError.failed(thrown) }
        guard let run = context.global("run"), run.isObject, !run.isUndefined else {
            throw PluginScriptError.noRunFunction
        }
        // `run(input)` plugins work as before: JavaScript ignores the extra argument.
        let value = run.call([input, Self.context(language: language)])
        if let thrown { throw PluginScriptError.failed(Self.clean(thrown)) }
        guard let value, value.isString, let text = value.toString() else {
            throw PluginScriptError.failed("run(input) must return text")
        }
        return text
    }

    /// "Error: XYZ: not found" → "XYZ: not found".
    static func clean(_ message: String) -> String {
        message.hasPrefix("Error: ") ? String(message.dropFirst(7)) : message
    }
}

/// `fetch` for real: HTTPS to the plugin's hosts only (redirects too), no cookies or cache, at most
/// `maxRequests` a run, `maxBytes` a response, `timeout` a request; several URLs run in parallel.
public final class URLSessionFetcher: NSObject, PluginFetcher, URLSessionTaskDelegate, @unchecked Sendable {
    public let hosts: Set<String>
    public static let maxRequests = 8
    public static let maxBytes = 1 << 20
    public static let timeout: TimeInterval = 5

    private let lock = NSLock()
    private var used = 0
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    public init(hosts: [String]) {
        self.hosts = Set(hosts.map { $0.lowercased() })
    }

    /// Whether a script may request `url`.
    public func allows(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return hosts.contains(host)
    }

    public func fetch(_ requests: [PluginRequest]) -> [PluginResponse] {
        // Filled in by the requests' completion handlers, which may run at once on other threads.
        let results = Locked(initialState: [PluginResponse](repeating: PluginResponse(error: "not sent"), count: requests.count))
        let group = DispatchGroup()
        for (index, request) in requests.enumerated() {
            let url = URL(string: request.url)
            guard allows(url), let url else {
                let error = "not allowed: \(url?.host ?? request.url) (the plugin lists \(hosts.sorted().joined(separator: ", ")))"
                results.withLock { $0[index] = PluginResponse(error: error) }
                continue
            }
            lock.lock()
            used += 1
            let over = used > Self.maxRequests
            lock.unlock()
            if over {
                results.withLock { $0[index] = PluginResponse(error: "too many requests (at most \(Self.maxRequests))") }
                continue
            }
            var urlRequest = URLRequest(url: url)
            for (name, value) in request.headers where name.lowercased() != "cookie" {
                urlRequest.setValue(value, forHTTPHeaderField: name)
            }
            group.enter()
            session.dataTask(with: urlRequest) { data, response, error in
                let result: PluginResponse
                if let error {
                    result = PluginResponse(error: (error as? URLError)?.code == .timedOut ? "\(url.host ?? "") timed out" : "can't reach \(url.host ?? "")")
                } else if (data?.count ?? 0) > Self.maxBytes {
                    result = PluginResponse(error: "response too large")
                } else {
                    result = PluginResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                            text: String(decoding: data ?? Data(), as: UTF8.self))
                }
                results.withLock { $0[index] = result }
                group.leave()
            }.resume()
        }
        group.wait()
        return results.withLock { $0 }
    }

    /// Redirects stay within the plugin's hosts.
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(allows(request.url) ? request : nil)
    }
}

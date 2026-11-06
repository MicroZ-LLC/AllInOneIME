import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import AllInOneIMECore

// Issue #33: an API key follows an HTTP redirect to a host it isn't bound to. A base URL (a relay, a gateway, a local
// proxy) that answers 3xx to another host gets the request sent there again, with the key's header (x-api-key,
// x-goog-api-key, Authorization: Bearer) and, on a 307 or 308, the user's text. Expected: the redirect is refused and
// shown as an HTTP error, and the other host receives nothing. Requests go through the real `Converter` (`@improve`'s
// and `@translate`'s path) and `HostedAccount.signIn` to a stub URL protocol, so what reached each host is read back.

/// Answers each host as the test says: a redirect elsewhere (as a relay can), or a reply (as the API would). Keeps every
/// request it gets, by host. A redirect is sent as URLSession's own HTTP loader sends it: on a 307 or 308, the same
/// request (method, headers, body) to the new address; followed, this request is stopped, and refused, the redirect
/// itself is the response (as `SearchStub` does).
private final class Issue33Stub: URLProtocol, @unchecked Sendable {
    enum Answer: Sendable {
        case redirect(status: Int, to: String)
        case reply(status: Int, body: String)
    }

    private struct State {
        var answers: [String: Answer] = [:]
        var requests: [String: [URLRequest]] = [:]
    }

    private static let state = Locked(initialState: State())

    static func serve(_ host: String, _ answer: Answer) {
        state.withLock {
            $0.answers[host] = answer
            $0.requests[host] = []
        }
    }

    static func requests(_ host: String) -> [URLRequest] {
        state.withLock { $0.requests[host] ?? [] }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Issue33Stub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = self.request
        // URLSession hands the body over as a stream, which reads once: kept as data.
        if request.httpBody == nil, let stream = request.httpBodyStream {
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            stream.open()
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            request.httpBody = data
        }
        let host = request.url?.host ?? ""
        let asked = request
        let answer = Self.state.withLock { state -> Answer? in
            state.requests[host, default: []].append(asked)
            return state.answers[host]
        }
        guard let answer, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        switch answer {
        case let .redirect(status, location):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": location, "Content-Type": "application/json"])!
            #if canImport(Darwin)
            var next = request
            next.url = URL(string: location)
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            #endif
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"error":{"type":"moved","message":"Moved elsewhere"}}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case let .reply(status, body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

// Apple's URLSession only: corelibs' stops the process at a stub's redirect (`HTTPStreamTests.stubsCanRedirect`).
@Suite(.enabled(if: HTTPStreamTests.stubsCanRedirect))
struct Issue33Tests {
    let key = "sk-issue33-secret"

    /// What the other host would answer, in the provider's own stream: a whole answer, so that a followed redirect
    /// ends as a conversion from there.
    func answer(_ provider: Provider) -> String {
        let text = #"EN: Hello from the other host\n"#
        switch provider {
        case .anthropic:
            return #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\#(text)"}}"# + "\n\n"
                + #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"# + "\n\n"
        case .gemini:
            return #"data: {"candidates":[{"content":{"parts":[{"text":"\#(text)"}]},"finishReason":"STOP"}]}"# + "\n\n"
        case .openai:
            return #"data: {"choices":[{"delta":{"content":"\#(text)"},"finish_reason":"stop"}]}"# + "\n\n" + "data: [DONE]\n\n"
        default:
            return #"data: {"text":"\#(text)"}"# + "\n\n" + #"data: {"stop":"end_turn"}"# + "\n\n"
        }
    }

    /// A converter for `provider` whose base URL is `base`; the key is bound to `base`'s host and to no other.
    func converter(_ provider: Provider, base: String?) -> Converter {
        var config = Config.default
        config.provider = provider
        switch provider {
        case .anthropic: config.anthropic.baseURL = base
        case .gemini: config.gemini.baseURL = base
        case .openai:
            config.openai.baseURL = base
            config.openai.model = "relay-model"  // an OpenAI-compatible service has no default model
        default: break
        }
        config.rewriteStyles = []
        let fixed = config
        let bound = HTTPProviders.host(of: config.settings(for: provider)) ?? ""
        let key = key
        return Converter(client: BedrockClient(session: Issue33Stub.session()), loadConfig: { fixed },
                         loadKey: { asked, host in asked == provider && host == bound ? key : nil })
    }

    /// Converts "你好" and returns the error it ends with (nil: none).
    func failure(of converter: Converter) async -> Error? {
        do {
            for try await _ in converter.convert("你好") {}
            return nil
        } catch {
            return error
        }
    }

    /// What reached `host`: each request's address and whether it carried the key.
    func reached(_ host: String) -> [String] {
        Issue33Stub.requests(host).map { request in
            let headers = request.allHTTPHeaderFields ?? [:]
            let carried = headers.values.contains { $0.contains(key) } ? "with the key" : "without the key"
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            return "\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?") \(carried)"
                + (body.contains("你好") ? ", with the text" : "")
        }
    }

    func expectHTTP(_ error: Error?, provider: Provider, status: Int, _ comment: Comment,
                    sourceLocation: SourceLocation = #_sourceLocation) {
        guard case let .http(failed, code, _, _)? = error as? ProviderError else {
            Issue.record("\(comment): expected ProviderError.http(status: \(status)), got \(error.map { "\($0)" } ?? "no error")",
                         sourceLocation: sourceLocation)
            return
        }
        #expect(failed == provider && code == status, comment, sourceLocation: sourceLocation)
    }

    /// The configured host answers 307 to another host: refused, shown as the 307, and the other host gets nothing (not
    /// the key in its header, not the text).
    @Test(arguments: [Provider.openai, .anthropic, .gemini])
    func aRedirectToAnotherHostIsRefused(_ provider: Provider) async {
        let from = "relay.issue33-\(provider.rawValue).test", to = "elsewhere.issue33-\(provider.rawValue).test"
        Issue33Stub.serve(from, .redirect(status: 307, to: "https://\(to)/v1/steal"))
        Issue33Stub.serve(to, .reply(status: 200, body: answer(provider)))

        let error = await failure(of: converter(provider, base: "https://\(from)/v1"))

        expectHTTP(error, provider: provider, status: 307, "\(provider)")
        #expect(Issue33Stub.requests(from).count == 1, "\(provider): the configured host is asked once")
        #expect(reached(to).isEmpty, "\(provider): the other host was sent \(reached(to))")
    }

    /// A 308 from https to plain http elsewhere: the key never goes over http to the internet (which `insecureBaseURL`
    /// refuses for a base URL itself).
    @Test func aRedirectToPlainHTTPIsRefused() async {
        let from = "gateway.issue33-http.test", to = "plain.issue33-http.test"
        Issue33Stub.serve(from, .redirect(status: 308, to: "http://\(to)/v1/chat/completions"))
        Issue33Stub.serve(to, .reply(status: 200, body: answer(.openai)))

        let error = await failure(of: converter(.openai, base: "https://\(from)/v1"))

        expectHTTP(error, provider: .openai, status: 308, "https → http")
        #expect(reached(to).isEmpty, "the http host was sent \(reached(to))")
    }

    /// AllInOneIME Cloud's chat: its session token doesn't follow a redirect either.
    @Test func theHostedServiceRefusesARedirect() async throws {
        let from = try #require(HTTPProviders.host(of: Config.default.settings(for: .hosted)))
        let to = "elsewhere.issue33-hosted.test"
        Issue33Stub.serve(from, .redirect(status: 307, to: "https://\(to)/chat"))
        Issue33Stub.serve(to, .reply(status: 200, body: answer(.hosted)))

        let error = await failure(of: converter(.hosted, base: nil))

        expectHTTP(error, provider: .hosted, status: 307, "hosted")
        #expect(Issue33Stub.requests(from).count == 1, "the service is asked once")
        #expect(reached(to).isEmpty, "the other host was sent \(reached(to))")
    }

    /// Signing in to AllInOneIME Cloud: the ID token in the body doesn't follow a 307 elsewhere. (The other host's
    /// answer has no token, so a followed redirect stores nothing in the keychain.)
    @Test func signingInRefusesARedirect() async {
        let from = "login.issue33-signin.test", to = "elsewhere.issue33-signin.test"
        Issue33Stub.serve(from, .redirect(status: 307, to: "https://\(to)/login"))
        Issue33Stub.serve(to, .reply(status: 200, body: "{}"))

        var failed: Error?
        do {
            _ = try await HostedAccount.signIn(idToken: "id-token-\(key)", baseURL: "https://\(from)", session: Issue33Stub.session())
        } catch {
            failed = error
        }

        expectHTTP(failed, provider: .hosted, status: 307, "sign-in")
        #expect(reached(to).isEmpty, "the other host was sent \(reached(to))")
    }
}

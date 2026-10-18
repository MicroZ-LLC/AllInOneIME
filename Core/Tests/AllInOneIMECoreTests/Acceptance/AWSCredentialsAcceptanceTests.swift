import CryptoKit
import Foundation
import os
import Testing
@testable import AllInOneIMECore

// Acceptance tests for 0.6.4's AWS credentials for Bedrock, written from the spec (every common profile type, cached
// and refreshed automatically) and the coordinator's decisions, not from the implementation:
//
// - Within a named profile, as the AWS CLI does it: role_arn (a source_profile naming the profile itself takes its own
//   static keys), then SSO, then the credentials file's keys, then credential_process, then the config file's keys.
// - The environment's keys come first only for the profile setting "" or "default"; never for a named profile.
//   AWS_PROFILE is ignored (Settings picks the profile). mfa_serial is refused before anything runs.
// - STS ExpiredToken during AssumeRole fetches the source again, once. Bedrock refusing expired credentials: refreshed
//   and sent again exactly once, only when no text has arrived yet.
// - Error messages name the program, never its arguments. A refresh that fails in the last 5 minutes fails the request.
//
// Nothing here reads the user's ~/.aws, runs their credential_process or goes online: every test has its own temporary
// HOME, and STS, the SSO portal, the program and the clock are the injected ones. The keys are AWS's documented
// examples, put together at run time.

// MARK: - Example keys

enum AWSAccKeys {
    /// The SigV4 test suite's key ID.
    static let id = "AKID" + "EXAMPLE"
    /// The IAM documentation's example secret.
    static let secret = "wJalrXUtnFEMI/K7MDENG/" + "bPxRfiCYEXAMPLEKEY"
    /// The SigV4 test suite's secret.
    static let vectorSecret = "wJalrXUtnFEMI/K7MDENG+" + "bPxRfiCYEXAMPLEKEY"
    /// An SSO access token as `aws sso login` caches it.
    static let ssoToken = "aoaEXAMPLE" + "SSOTOKEN" + "Zm9vYmFyYmF6"

    /// Keys told apart by `tag`: "AKIDEXAMPLE<tag>", the example secret and a session token with the tag.
    static func credentials(_ tag: String, token: Bool = true) -> AWSCredentials {
        AWSCredentials(accessKeyId: id + tag, secretAccessKey: secret + tag,
                       sessionToken: token ? "FwoGZXIvYXdzEXAMPLE" + "TOKEN" + tag : nil)
    }

    /// None of the secrets used here (secret keys, session tokens, the SSO token) is in `text`.
    static func hidesSecrets(_ text: String) -> Bool {
        !text.contains("EXAMPLEKEY") && !text.contains("EXAMPLETOKEN") && !text.contains("EXAMPLESSOTOKEN")
            && !text.contains("bPxRfiCY") && !text.contains("Zm9vYmFyYmF6")
    }
}

// MARK: - A temporary HOME

/// A temporary HOME with `.aws/config`, `.aws/credentials` and `.aws/sso/cache`, never the user's.
struct AWSAccHome: Sendable {
    let root: URL

    init(config: String = "", credentials: String = "") throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aws-acceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".aws/sso/cache"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try write(config: config, credentials: credentials)
    }

    var path: String { root.path }
    var bin: URL { root.appendingPathComponent("bin") }

    func write(config: String, credentials: String) throws {
        try Data(config.utf8).write(to: root.appendingPathComponent(".aws/config"))
        try Data(credentials.utf8).write(to: root.appendingPathComponent(".aws/credentials"))
    }

    @discardableResult
    func file(_ relative: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    /// An SSO sign-in as `aws sso login` caches it: `~/.aws/sso/cache/<SHA-1 of the session name or start URL>.json`.
    func signIn(_ key: String, expiresAt: Date, token: String = AWSAccKeys.ssoToken) throws {
        let name = Insecure.SHA1.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let json = """
            {"startUrl": "https://my-sso-portal.awsapps.com/start", "region": "us-east-1", "accessToken": "\(token)",
             "expiresAt": "\(AWSAcc.iso(expiresAt))", "clientId": "EXAMPLECLIENTID", "clientSecret": "EXAMPLECLIENTSECRET",
             "registrationExpiresAt": "2027-01-01T00:00:00Z", "refreshToken": "EXAMPLEREFRESHTOKEN"}
            """
        try file(".aws/sso/cache/\(name).json", json)
    }

    /// An executable shell script in `bin`.
    func script(_ name: String, _ body: String) throws -> URL {
        let url = try file("bin/\(name)", "#!/bin/sh\n" + body + "\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    /// Every file and folder under HOME, with a hash of each file's contents.
    func snapshot() -> [String: String] {
        let base = root.resolvingSymlinksInPath().path
        var out: [String: String] = [:]
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return out }
        for case let url as URL in walk {
            let full = url.resolvingSymlinksInPath().path
            let relative = full.hasPrefix(base) ? String(full.dropFirst(base.count)) : full
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                out[relative] = "folder"
            } else {
                out[relative] = (try? Data(contentsOf: url)).map { AWSAccSigV4.hash($0) } ?? "unreadable"
            }
        }
        return out
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

// MARK: - The clock, the program, STS and the SSO portal

final class AWSAccClock: Sendable {
    /// 2026-10-16 19:00 UTC, 12:00 in Los Angeles.
    static let start = Date(timeIntervalSince1970: 1_792_177_200)
    private let time = OSAllocatedUnfairLock(initialState: AWSAccClock.start)
    var now: Date { time.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { time.withLock { $0 = $0.addingTimeInterval(seconds) } }
    var read: @Sendable () -> Date { { [self] in now } }
}

/// Holds a stub's answer until opened (at most `limit` seconds, so a test that waits on it can't hang).
final class AWSAccGate: Sendable {
    private let opened = OSAllocatedUnfairLock(initialState: false)
    func open() { opened.withLock { $0 = true } }
    func wait(limit: TimeInterval = 5) async {
        let end = Date().addingTimeInterval(limit)
        while Date() < end, !opened.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(10)) }
    }
}

/// `credential_process` as a stub: every request recorded, each answered by `handler` (its index counts from 0). The
/// default answers exit status 1: nothing real ever runs unless a test asks for the real runner.
final class AWSAccRunner: Sendable {
    typealias Handler = @Sendable (_ request: AWSProcessRequest, _ index: Int) async throws -> AWSProcessResult
    private let state = OSAllocatedUnfairLock(initialState: [AWSProcessRequest]())
    private let handler: Handler

    init(_ handler: @escaping Handler = { _, _ in AWSProcessResult(status: 1, standardOutput: Data(), standardError: Data("stub".utf8)) }) {
        self.handler = handler
    }

    var requests: [AWSProcessRequest] { state.withLock { $0 } }
    var count: Int { requests.count }

    var run: AWSCredentialContext.RunProcess {
        { [self] request in
            let index = state.withLock { $0.append(request); return $0.count - 1 }
            return try await handler(request, index)
        }
    }

    /// Each run prints `<prefix><n>` credentials (n from 1) as the AWS CLI expects them, expiring `lifetime` after the
    /// clock's time (no Expiration when nil), after `delay`.
    static func issuing(_ prefix: String, clock: AWSAccClock? = nil, lifetime: TimeInterval? = nil,
                        delay: Duration = .zero) -> AWSAccRunner {
        AWSAccRunner { _, index in
            if delay != .zero { try? await Task.sleep(for: delay) }
            let expiration = lifetime.flatMap { lifetime in clock.map { $0.now.addingTimeInterval(lifetime) } }
            return AWSProcessResult(status: 0, standardOutput: AWSAcc.processJSON(AWSAccKeys.credentials("\(prefix)\(index + 1)"),
                                                                                  expiration: expiration))
        }
    }
}

/// STS and the SSO portal as a stub: every request recorded, each host answered by its handler (index: the request's
/// number to that host, from 0); an unknown host can't be reached.
final class AWSAccHTTP: Sendable {
    struct Reply: Sendable {
        var status: Int
        var body: String
        var headers: [String: String] = [:]
    }

    typealias Handler = @Sendable (_ request: URLRequest, _ index: Int) async -> Reply
    private let state = OSAllocatedUnfairLock(initialState: (requests: [URLRequest](), handlers: [String: Handler]()))

    func on(_ host: String, _ handler: @escaping Handler) { state.withLock { $0.handlers[host] = handler } }

    func requests(_ host: String? = nil) -> [URLRequest] {
        state.withLock { state in state.requests.filter { host == nil || $0.url?.host == host } }
    }

    var send: AWSCredentialContext.Send {
        { [self] request in
            let host = request.url?.host ?? ""
            let (index, handler) = state.withLock { state -> (Int, Handler?) in
                let index = state.requests.filter { $0.url?.host == host }.count
                state.requests.append(request)
                return (index, state.handlers[host])
            }
            guard let handler, let url = request.url else { throw URLError(.cannotFindHost) }
            let reply = await handler(request, index)
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            return (Data(reply.body.utf8), response)
        }
    }
}

enum AWSAccSTS {
    static func host(_ region: String) -> String { "sts.\(region).amazonaws.com" }

    /// An `AssumeRoleResponse` as the STS API reference shows it.
    static func response(_ credentials: AWSCredentials, expiration: Date) -> String {
        """
        <AssumeRoleResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
          <AssumeRoleResult>
            <SourceIdentity>Alice</SourceIdentity>
            <AssumedRoleUser>
              <Arn>arn:aws:sts::123456789012:assumed-role/demo/TestAR</Arn>
              <AssumedRoleId>ARO123EXAMPLE123:TestAR</AssumedRoleId>
            </AssumedRoleUser>
            <Credentials>
              <AccessKeyId>\(credentials.accessKeyId)</AccessKeyId>
              <SecretAccessKey>\(credentials.secretAccessKey)</SecretAccessKey>
              <SessionToken>\(credentials.sessionToken ?? "")</SessionToken>
              <Expiration>\(AWSAcc.iso(expiration))</Expiration>
            </Credentials>
            <PackedPolicySize>6</PackedPolicySize>
          </AssumeRoleResult>
          <ResponseMetadata>
            <RequestId>c6104cbe-af31-11e0-8154-cbc7ccf896c7</RequestId>
          </ResponseMetadata>
        </AssumeRoleResponse>
        """
    }

    /// An STS `ErrorResponse` as the API reference shows it.
    static func error(_ code: String, _ message: String) -> String {
        """
        <ErrorResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
          <Error>
            <Type>Sender</Type>
            <Code>\(code)</Code>
            <Message>\(message)</Message>
          </Error>
          <RequestId>4ee6d7b1-8e4b-11e0-a0b3-c3d8EXAMPLE</RequestId>
        </ErrorResponse>
        """
    }

    static let denied = "User: arn:aws:iam::123456789012:user/dev is not authorized to perform: sts:AssumeRole on resource: arn:aws:iam::123456789012:role/demo"
    static let expired = "The security token included in the request is expired"

    /// Every AssumeRole answered with `<prefix><n>` credentials, expiring `lifetime` after the clock's time.
    static func issuing(_ prefix: String, clock: AWSAccClock, lifetime: TimeInterval = 3600, delay: Duration = .zero) -> AWSAccHTTP.Handler {
        { _, index in
            if delay != .zero { try? await Task.sleep(for: delay) }
            return .init(status: 200, body: response(AWSAccKeys.credentials("\(prefix)\(index + 1)"),
                                                     expiration: clock.now.addingTimeInterval(lifetime)))
        }
    }
}

enum AWSAccSSO {
    static func host(_ region: String) -> String { "portal.sso.\(region).amazonaws.com" }

    /// `GetRoleCredentials`' answer (expiration in milliseconds since 1970).
    static func response(_ credentials: AWSCredentials, expiration: Date) -> String {
        #"{"roleCredentials":{"accessKeyId":"\#(credentials.accessKeyId)","secretAccessKey":"\#(credentials.secretAccessKey)","sessionToken":"\#(credentials.sessionToken ?? "")","expiration":\#(Int64(expiration.timeIntervalSince1970 * 1000))}}"#
    }

    static func issuing(_ prefix: String, clock: AWSAccClock, lifetime: TimeInterval = 3600) -> AWSAccHTTP.Handler {
        { _, index in
            .init(status: 200, body: response(AWSAccKeys.credentials("\(prefix)\(index + 1)"), expiration: clock.now.addingTimeInterval(lifetime)),
                  headers: ["Content-Type": "application/json"])
        }
    }

    static let config = """
        [profile sso]
        sso_session = my-sso
        sso_account_id = 111122223333
        sso_role_name = ReadOnly
        region = us-west-2
        [sso-session my-sso]
        sso_start_url = https://my-sso-portal.awsapps.com/start
        sso_region = us-east-1
        sso_registration_scopes = sso:account:access

        """
}

// MARK: - Shared helpers

enum AWSAcc {
    static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    static let roleArn = "arn:aws:iam::123456789012:role/demo"

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func processJSON(_ credentials: AWSCredentials, expiration: Date?) -> Data {
        var object: [String: Any] = ["Version": 1, "AccessKeyId": credentials.accessKeyId, "SecretAccessKey": credentials.secretAccessKey]
        if let token = credentials.sessionToken { object["SessionToken"] = token }
        if let expiration { object["Expiration"] = iso(expiration) }
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// A section of keys, for either file (`section`: "dev", "default", "profile dev" …).
    static func keys(_ section: String, _ credentials: AWSCredentials) -> String {
        var text = "[\(section)]\naws_access_key_id = \(credentials.accessKeyId)\naws_secret_access_key = \(credentials.secretAccessKey)\n"
        if let token = credentials.sessionToken { text += "aws_session_token = \(token)\n" }
        return text
    }

    static func environment(_ credentials: AWSCredentials) -> [String: String] {
        var out = ["AWS_ACCESS_KEY_ID": credentials.accessKeyId, "AWS_SECRET_ACCESS_KEY": credentials.secretAccessKey]
        if let token = credentials.sessionToken { out["AWS_SESSION_TOKEN"] = token }
        return out
    }

    /// A resolver on `home` (HOME set to it, the files found from it), with the stub program (or the real runner),
    /// the stub STS/SSO and the clock.
    static func resolver(_ home: AWSAccHome, environment: [String: String] = [:], runner: AWSAccRunner? = AWSAccRunner(),
                         http: AWSAccHTTP = AWSAccHTTP(), clock: AWSAccClock = AWSAccClock(),
                         processTimeout: TimeInterval = 60) -> AWSCredentialResolver {
        var variables = environment
        variables["HOME"] = home.path
        let context = AWSCredentialContext(
            environment: variables, files: nil,
            processEnvironment: ["PATH": home.bin.path + ":/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home.path],
            runProcess: runner?.run ?? AWSProcessRunner.run, send: http.send, now: clock.read, processTimeout: processTimeout)
        return AWSCredentialResolver(context: context)
    }

    /// The error `body` throws (nil: none).
    static func failure<T>(_ body: () async throws -> T) async -> Error? {
        do {
            _ = try await body()
            return nil
        } catch {
            return error
        }
    }

    /// What the user is shown for `error`.
    static func message(_ error: Error?, chinese: Bool = false) -> String {
        guard let error else { return "" }
        if let error = error as? AWSCredentialError { return error.message(chinese: chinese) }
        return error.localizedDescription
    }

    /// The access key ID a request was signed with.
    static func signedKey(_ request: URLRequest) -> String? {
        authorization(request)?.keyId
    }

    struct Authorization {
        var keyId: String
        var scope: String
        var signedHeaders: [String]
        var signature: String
    }

    static func authorization(_ request: URLRequest) -> Authorization? {
        guard let header = request.value(forHTTPHeaderField: "Authorization"), header.hasPrefix("AWS4-HMAC-SHA256 ") else { return nil }
        var fields: [String: String] = [:]
        for part in header.dropFirst("AWS4-HMAC-SHA256 ".count).components(separatedBy: ",") {
            let pair = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { fields[pair[0]] = pair[1] }
        }
        guard let credential = fields["Credential"], let slash = credential.firstIndex(of: "/"),
              let signed = fields["SignedHeaders"], let signature = fields["Signature"] else { return nil }
        return Authorization(keyId: String(credential[..<slash]), scope: String(credential[credential.index(after: slash)...]),
                             signedHeaders: signed.components(separatedBy: ";"), signature: signature)
    }

    /// The form fields of an STS request's body.
    static func form(_ request: URLRequest) -> [String: String] {
        guard let body = request.httpBody else { return [:] }
        var out: [String: String] = [:]
        for pair in String(decoding: body, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map {
                String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
            }
            out[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return out
    }

    static func hasCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }
}

// MARK: - SigV4, computed here independently

enum AWSAccSigV4 {
    static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ data: Data) -> String { hex(SHA256.hash(data: data)) }

    static func signingKey(secret: String, date: String, region: String, service: String) -> Data {
        var key = Data("AWS4\(secret)".utf8)
        for part in [date, region, service, "aws4_request"] {
            key = Data(HMAC<SHA256>.authenticationCode(for: Data(part.utf8), using: SymmetricKey(data: key)))
        }
        return key
    }

    static func canonicalRequest(method: String, path: String, query: String, headers: [String: String], signed: [String],
                                 body: Data) -> String {
        var lower: [String: String] = [:]
        for (name, value) in headers {
            lower[name.lowercased()] = value.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
                .joined(separator: " ")
        }
        let canonicalHeaders = signed.map { "\($0):\(lower[$0] ?? "")\n" }.joined()
        return [method, path, query, canonicalHeaders, signed.joined(separator: ";"), hash(body)].joined(separator: "\n")
    }

    static func signature(secret: String, amzDate: String, region: String, service: String, canonicalRequest: String) -> String {
        let scope = "\(amzDate.prefix(8))/\(region)/\(service)/aws4_request"
        let toSign = ["AWS4-HMAC-SHA256", amzDate, scope, hash(Data(canonicalRequest.utf8))].joined(separator: "\n")
        let key = signingKey(secret: secret, date: String(amzDate.prefix(8)), region: region, service: service)
        return hex(HMAC<SHA256>.authenticationCode(for: Data(toSign.utf8), using: SymmetricKey(data: key)))
    }

    /// The signature AWS would expect for `request` as sent: the headers it names in SignedHeaders, its body.
    static func expectedSignature(_ request: URLRequest, secret: String, region: String, service: String) -> String? {
        guard let auth = AWSAcc.authorization(request), let url = request.url, let amzDate = request.value(forHTTPHeaderField: "X-Amz-Date")
        else { return nil }
        var headers = request.allHTTPHeaderFields ?? [:]
        headers["host"] = url.host
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.percentEncodedPath.isEmpty == false ? components!.percentEncodedPath : "/"
        let canonical = canonicalRequest(method: request.httpMethod ?? "GET", path: path, query: components?.percentEncodedQuery ?? "",
                                         headers: headers, signed: auth.signedHeaders, body: request.httpBody ?? Data())
        return signature(secret: secret, amzDate: amzDate, region: region, service: service, canonicalRequest: canonical)
    }
}

// MARK: - Bedrock as a stub transport

final class AWSAccBedrockStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var headers: [String: String]
        var body: Data
    }

    private static let state = OSAllocatedUnfairLock(initialState: (replies: [String: [Reply]](), keys: [String: [String]]()))

    /// The answers for `host`, in order; once they run out, a 500.
    static func on(_ host: String, _ replies: [Reply]) { state.withLock { $0.replies[host] = replies } }
    /// The access key ID of each request sent to `host`.
    static func keys(_ host: String) -> [String] { state.withLock { $0.keys[host] ?? [] } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AWSAccBedrockStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let key = AWSAcc.signedKey(request) ?? ""
        let reply = Self.state.withLock { state -> Reply in
            state.keys[host, default: []].append(key)
            guard var queue = state.replies[host], !queue.isEmpty else {
                return Reply(status: 500, headers: [:], body: Data(#"{"message":"no more stub replies"}"#.utf8))
            }
            let first = queue.removeFirst()
            state.replies[host] = queue
            return first
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    // The replies.

    static func refused(_ type: String?, status: Int = 403, message: String = AWSAccSTS.expired) -> Reply {
        var headers = ["Content-Type": "application/json"]
        if let type { headers["x-amzn-ErrorType"] = "\(type):http://internal.amazon.com/coral/com.amazon.coral.service/" }
        return Reply(status: status, headers: headers, body: Data(#"{"message":"\#(message)"}"#.utf8))
    }

    static func answer(_ text: String) -> Reply {
        stream(AWSAccEventStream.text(text) + AWSAccEventStream.stop() + AWSAccEventStream.metadata())
    }

    static func stream(_ bytes: [UInt8]) -> Reply {
        Reply(status: 200, headers: ["Content-Type": "application/vnd.amazon.eventstream"], body: Data(bytes))
    }
}

/// `application/vnd.amazon.eventstream` frames, written here (string headers only).
enum AWSAccEventStream {
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    static func frame(_ headers: [(String, String)], _ payload: String) -> [UInt8] {
        var encoded: [UInt8] = []
        for (name, value) in headers {
            let n = Array(name.utf8), v = Array(value.utf8)
            encoded.append(UInt8(n.count))
            encoded += n
            encoded.append(7)
            encoded += [UInt8(v.count >> 8), UInt8(v.count & 0xFF)]
            encoded += v
        }
        let body = Array(payload.utf8)
        var out = bigEndian(UInt32(12 + encoded.count + body.count + 4)) + bigEndian(UInt32(encoded.count))
        out += bigEndian(crc32(out))
        out += encoded + body
        out += bigEndian(crc32(out))
        return out
    }

    static func event(_ type: String, _ payload: String) -> [UInt8] {
        frame([(":event-type", type), (":content-type", "application/json"), (":message-type", "event")], payload)
    }

    static func text(_ text: String) -> [UInt8] {
        event("contentBlockDelta", #"{"contentBlockIndex":0,"delta":{"text":"\#(text)"}}"#)
    }

    static func stop() -> [UInt8] { event("messageStop", #"{"stopReason":"end_turn"}"#) }

    static func metadata() -> [UInt8] {
        event("metadata", #"{"usage":{"inputTokens":5,"outputTokens":2},"metrics":{"latencyMs":120}}"#)
    }

    static func exception(_ type: String, _ message: String) -> [UInt8] {
        frame([(":exception-type", type), (":content-type", "application/json"), (":message-type", "exception")],
              #"{"message":"\#(message)"}"#)
    }
}

enum AWSAccBedrock {
    /// One Bedrock request through the provider (`ChatClient.stream`) with the resolver's credentials for `profile`:
    /// the text that came, and the error it ended with.
    static func ask(_ resolver: AWSCredentialResolver, region: String, profile: String = "dev") async -> (text: String, error: Error?) {
        var config = Config.default
        config.provider = .bedrock
        config.region = region
        config.awsProfile = profile
        let client = ChatClient(bedrock: BedrockClient(session: AWSAccBedrockStub.session()))
        let body = ConverseRequest(system: [.init("Reply briefly.")], messages: [.init(role: "user", text: "hello")],
                                   inferenceConfig: .init(maxTokens: 50, temperature: nil))
        var text = ""
        do {
            let stream = client.stream(body, config: config, loadCredentials: { try await resolver.resolve(profile: $0) },
                                       loadKey: { _, _ in nil })
            for try await event in stream {
                if case let .textDelta(delta) = event { text += delta }
            }
            return (text, nil)
        } catch {
            return (text, error)
        }
    }

    static func host(_ region: String) -> String { "bedrock-runtime.\(region).amazonaws.com" }
}

// MARK: - Each source

@Suite(.timeLimit(.minutes(1)))
struct AWSCredentialsAcceptanceSourceTests {
    @Test func staticKeysFromTheCredentialsFileWithASessionToken() async throws {
        let keys = AWSAccKeys.credentials("STATIC")
        let home = try AWSAccHome(config: "[profile dev]\nregion = eu-central-1\n", credentials: AWSAcc.keys("dev", keys))
        defer { home.remove() }
        let runner = AWSAccRunner(), http = AWSAccHTTP()
        let resolved = try await AWSAcc.resolver(home, runner: runner, http: http).resolve(profile: "dev")
        #expect(resolved.credentials == keys)
        #expect(resolved.credentials.sessionToken == keys.sessionToken, "aws_session_token is kept")
        #expect(resolved.region == "eu-central-1")
        #expect(resolved.expiration == nil, "static keys don't expire")
        #expect(runner.count == 0 && http.requests().isEmpty)
    }

    @Test func staticKeysFromTheConfigFile() async throws {
        let keys = AWSAccKeys.credentials("CONFIG", token: false)
        let home = try AWSAccHome(config: AWSAcc.keys("profile dev", keys) + "region = us-west-2\n")
        defer { home.remove() }
        let resolved = try await AWSAcc.resolver(home).resolve(profile: "dev")
        #expect(resolved.credentials == keys)
        #expect(resolved.credentials.sessionToken == nil)
    }

    @Test func credentialProcessIsSplitLikeTheCLIAndRunWithoutAShell() async throws {
        let home = try AWSAccHome(config: """
            [profile dev]
            credential_process = /usr/local/bin/my-creds --profile dev
            [profile quoted]
            credential_process = "/opt/my tools/my-creds" --name 'a b' c\\ d --flag="x y"
            [profile shelly]
            credential_process = my-creds $HOME ~/x a|b c&&d >out
            """)
        defer { home.remove() }
        let clock = AWSAccClock()
        let runner = AWSAccRunner.issuing("PROC", clock: clock, lifetime: 3600)
        let resolver = AWSAcc.resolver(home, runner: runner, clock: clock)
        let resolved = try await resolver.resolve(profile: "dev")
        #expect(resolved.credentials == AWSAccKeys.credentials("PROC1"))
        #expect(resolved.expiration == clock.now.addingTimeInterval(3600))
        _ = try await resolver.resolve(profile: "quoted")
        _ = try await resolver.resolve(profile: "shelly")
        let requests = runner.requests
        try #require(requests.count == 3)
        #expect(requests[0].arguments == ["/usr/local/bin/my-creds", "--profile", "dev"])
        #expect(requests[1].arguments == ["/opt/my tools/my-creds", "--name", "a b", "c d", "--flag=x y"])
        #expect(requests[2].arguments == ["my-creds", "$HOME", "~/x", "a|b", "c&&d", ">out"], "no expansion, no shell operators")
        // The login shell's PATH and the home folder; 60 s unless the context says otherwise.
        #expect(requests[0].environment["PATH"] == home.bin.path + ":/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(requests[0].environment["HOME"] == home.path)
        #expect(requests[0].timeout == 60)
        #expect(try AWSCredentialProcess.arguments("/usr/local/bin/my-creds --profile dev") == ["/usr/local/bin/my-creds", "--profile", "dev"])
    }

    @Test func credentialProcessQuotingAsPythonsShlex() throws {
        #expect(try AWSCredentialProcess.arguments(#"my-creds 'single \ kept' "dq \"inner\"" a\ b x"y z"w"#)
            == ["my-creds", #"single \ kept"#, #"dq "inner""#, "a b", "xy zw"])
        #expect(try AWSCredentialProcess.arguments("my-creds\t--profile   dev") == ["my-creds", "--profile", "dev"])
        #expect(throws: (any Error).self) { try AWSCredentialProcess.arguments(#"my-creds "unclosed"#) }
        #expect(throws: (any Error).self) { try AWSCredentialProcess.arguments("   ") }
    }

    @Test func theDefaultTimeoutIsSixtySeconds() async throws {
        let home = try AWSAccHome(config: "[profile dev]\ncredential_process = /usr/local/bin/my-creds --profile dev\n")
        defer { home.remove() }
        let runner = AWSAccRunner.issuing("PROC")
        let context = AWSCredentialContext(environment: ["HOME": home.path], runProcess: runner.run, send: AWSAccHTTP().send)
        #expect(context.processTimeout == 60)
        _ = try await AWSCredentialResolver(context: context).resolve(profile: "dev")
        #expect(runner.requests.first?.timeout == 60)
    }

    @Test func theRealRunnerUsesThePathHomeAndArgumentsWithStdinClosedAndStderrApart() async throws {
        let home = try AWSAccHome()
        defer { home.remove() }
        let keys = AWSAccKeys.credentials("REAL")
        // Found on the PATH by name; reports what it got in the session token; writes noise to stderr.
        _ = try home.script("acc-creds", """
            input=$(cat)
            echo "progress: fetching credentials" >&2
            printf '{"Version": 1, "AccessKeyId": "%s", "SecretAccessKey": "%s", "SessionToken": "%s|%s|%s|%s|%s"}' \
              "\(keys.accessKeyId)" "\(keys.secretAccessKey)" "$1" "$2" "$3" "$HOME" "${#input}"
            """)
        try home.write(config: "[profile dev]\ncredential_process = acc-creds --profile \"my dev\" '$HOME'\n", credentials: "")
        let resolver = AWSAcc.resolver(home, runner: nil)
        let resolved = try await resolver.resolve(profile: "dev")
        #expect(resolved.credentials.accessKeyId == keys.accessKeyId)
        #expect(resolved.credentials.sessionToken == "--profile|my dev|$HOME|\(home.path)|0",
                "arguments split without a shell, HOME is the home folder, stdin empty, stderr not mixed into the JSON")
    }

    @Test func roleWithAStaticSourceProfile() async throws {
        let base = AWSAccKeys.credentials("BASE")
        let home = try AWSAccHome(config: """
            [profile role]
            role_arn = \(AWSAcc.roleArn)
            source_profile = base
            region = eu-west-1
            role_session_name = typing-session
            external_id = ext-1234
            duration_seconds = 1800
            """, credentials: AWSAcc.keys("base", base))
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        http.on(AWSAccSTS.host("eu-west-1"), AWSAccSTS.issuing("ROLE", clock: clock, lifetime: 1800))
        let resolved = try await AWSAcc.resolver(home, http: http, clock: clock).resolve(profile: "role")
        #expect(resolved.credentials == AWSAccKeys.credentials("ROLE1"))
        #expect(resolved.expiration == clock.now.addingTimeInterval(1800))
        let requests = http.requests()
        try #require(requests.count == 1)
        let request = requests[0]
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://sts.eu-west-1.amazonaws.com/")
        let form = AWSAcc.form(request)
        #expect(form["Action"] == "AssumeRole" && form["Version"] == "2011-06-15")
        #expect(form["RoleArn"] == AWSAcc.roleArn)
        #expect(form["RoleSessionName"] == "typing-session")
        #expect(form["ExternalId"] == "ext-1234")
        #expect(form["DurationSeconds"] == "1800")
        #expect(AWSAcc.signedKey(request) == base.accessKeyId, "signed with the source profile's keys")
        #expect(request.value(forHTTPHeaderField: "X-Amz-Security-Token") == base.sessionToken)
    }

    @Test func theDefaultSessionNameIsAllinoneimeAndATimestamp() async throws {
        let home = try AWSAccHome(config: "[profile role]\nrole_arn = \(AWSAcc.roleArn)\nsource_profile = base\n",
                                  credentials: AWSAcc.keys("base", AWSAccKeys.credentials("BASE")))
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        http.on(AWSAccSTS.host("us-east-1"), AWSAccSTS.issuing("ROLE", clock: clock))
        _ = try await AWSAcc.resolver(home, http: http, clock: clock).resolve(profile: "role")
        let form = AWSAcc.form(try #require(http.requests().first))
        let name = try #require(form["RoleSessionName"])
        #expect(name.hasPrefix("allinoneime-") && name.count > "allinoneime-".count, "\(name)")
        // What STS accepts: 2 to 64 of [\w+=,.@-].
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_+=,.@-"))
        #expect((2...64).contains(name.count) && name.unicodeScalars.allSatisfy { $0.isASCII && allowed.contains($0) }, "\(name)")
        #expect(form["ExternalId"] == nil && form["DurationSeconds"] == nil, "only sent when set")
    }

    @Test func roleThenRoleThenCredentialProcess() async throws {
        let home = try AWSAccHome(config: """
            [profile top]
            role_arn = arn:aws:iam::123456789012:role/top
            source_profile = middle
            region = us-west-2
            [profile middle]
            role_arn = arn:aws:iam::123456789012:role/middle
            source_profile = proc
            [profile proc]
            credential_process = /usr/local/bin/my-creds --profile dev
            region = ap-southeast-2
            """)
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        let runner = AWSAccRunner.issuing("PROC", clock: clock, lifetime: 3600)
        http.on(AWSAccSTS.host("us-east-1"), AWSAccSTS.issuing("MID", clock: clock))
        http.on(AWSAccSTS.host("us-west-2"), AWSAccSTS.issuing("TOP", clock: clock))
        let resolved = try await AWSAcc.resolver(home, runner: runner, http: http, clock: clock).resolve(profile: "top")
        #expect(resolved.credentials == AWSAccKeys.credentials("TOP1"))
        #expect(runner.count == 1 && runner.requests.first?.arguments == ["/usr/local/bin/my-creds", "--profile", "dev"])
        let requests = http.requests()
        try #require(requests.count == 2)
        #expect(requests[0].url?.host == AWSAccSTS.host("us-east-1"), "middle has no region: us-east-1")
        #expect(AWSAcc.form(requests[0])["RoleArn"] == "arn:aws:iam::123456789012:role/middle")
        #expect(AWSAcc.signedKey(requests[0]) == AWSAccKeys.credentials("PROC1").accessKeyId)
        #expect(requests[0].value(forHTTPHeaderField: "X-Amz-Security-Token") == AWSAccKeys.credentials("PROC1").sessionToken)
        #expect(requests[1].url?.host == AWSAccSTS.host("us-west-2"))
        #expect(AWSAcc.form(requests[1])["RoleArn"] == "arn:aws:iam::123456789012:role/top")
        #expect(AWSAcc.signedKey(requests[1]) == AWSAccKeys.credentials("MID1").accessKeyId)
    }

    @Test func roleWithCredentialSourceEnvironment() async throws {
        let env = AWSAccKeys.credentials("ENV")
        let home = try AWSAccHome(config: "[profile envrole]\nrole_arn = \(AWSAcc.roleArn)\ncredential_source = Environment\nregion = us-west-2\n")
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        http.on(AWSAccSTS.host("us-west-2"), AWSAccSTS.issuing("ROLE", clock: clock))
        let resolved = try await AWSAcc.resolver(home, environment: AWSAcc.environment(env), http: http, clock: clock).resolve(profile: "envrole")
        #expect(resolved.credentials == AWSAccKeys.credentials("ROLE1"))
        let request = try #require(http.requests().first)
        #expect(AWSAcc.signedKey(request) == env.accessKeyId)
        #expect(request.value(forHTTPHeaderField: "X-Amz-Security-Token") == env.sessionToken)
    }

    @Test(arguments: [("Ec2InstanceMetadata", "EC2"), ("EcsContainer", "ECS")])
    func credentialSourcesForEC2AndECSAreUnsupportedWithTheReason(source: String, reason: String) async throws {
        let home = try AWSAccHome(config: "[profile cloud]\nrole_arn = \(AWSAcc.roleArn)\ncredential_source = \(source)\n")
        defer { home.remove() }
        let http = AWSAccHTTP()
        let resolver = AWSAcc.resolver(home, environment: AWSAcc.environment(AWSAccKeys.credentials("ENV")), http: http)
        let error = await AWSAcc.failure { try await resolver.resolve(profile: "cloud") }
        let message = AWSAcc.message(error)
        #expect(error is AWSCredentialError)
        #expect(message.lowercased().contains("unsupported") && message.contains(reason), "\(message)")
        #expect(http.requests().isEmpty)
    }

    @Test func ssoWithAnSSOSession() async throws {
        let home = try AWSAccHome(config: AWSAccSSO.config)
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(8 * 3600))
        http.on(AWSAccSSO.host("us-east-1"), AWSAccSSO.issuing("SSO", clock: clock))
        let resolved = try await AWSAcc.resolver(home, http: http, clock: clock).resolve(profile: "sso")
        #expect(resolved.credentials == AWSAccKeys.credentials("SSO1"))
        #expect(resolved.expiration == clock.now.addingTimeInterval(3600))
        #expect(resolved.region == "us-west-2")
        let request = try #require(http.requests().first)
        #expect(request.httpMethod ?? "GET" == "GET")
        let url = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(url.scheme == "https" && url.host == "portal.sso.us-east-1.amazonaws.com" && url.path == "/federation/credentials")
        let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query == ["role_name": "ReadOnly", "account_id": "111122223333"])
        #expect(request.value(forHTTPHeaderField: "x-amz-sso_bearer_token") == AWSAccKeys.ssoToken)
    }

    @Test func ssoWithALegacyStartURL() async throws {
        let start = "https://legacy-portal.awsapps.com/start"
        let home = try AWSAccHome(config: """
            [profile legacy]
            sso_start_url = \(start)
            sso_region = eu-west-1
            sso_account_id = 444455556666
            sso_role_name = Developer
            """)
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        try home.signIn(start, expiresAt: clock.now.addingTimeInterval(3600))
        http.on(AWSAccSSO.host("eu-west-1"), AWSAccSSO.issuing("LEGACY", clock: clock))
        let resolved = try await AWSAcc.resolver(home, http: http, clock: clock).resolve(profile: "legacy")
        #expect(resolved.credentials == AWSAccKeys.credentials("LEGACY1"))
        let query = (http.requests().first?.url).flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        #expect(Set(query.map { "\($0.name)=\($0.value ?? "")" }) == ["role_name=Developer", "account_id=444455556666"])
    }

    @Test func theSSOCacheFileIsNamedByTheSHA1OfTheSessionName() {
        let folder = URL(fileURLWithPath: "/tmp/sso-cache")
        #expect(AWSSSO.cacheFile(key: "my-sso", in: folder).lastPathComponent == "0ad374308c5a4e22f723adf10145eafad7c4031c.json")
    }

    @Test func environmentKeysForAnEmptyOrDefaultProfileSetting() async throws {
        let env = AWSAccKeys.credentials("ENV")
        let home = try AWSAccHome()
        defer { home.remove() }
        let resolver = AWSAcc.resolver(home, environment: AWSAcc.environment(env))
        #expect(try await resolver.resolve(profile: "").credentials == env)
        #expect(try await resolver.resolve(profile: "default").credentials == env)
        #expect(try await resolver.resolve(profile: "default").credentials.sessionToken == env.sessionToken, "AWS_SESSION_TOKEN too")
    }

    @Test func environmentKeysComeFirstEvenWhenDefaultHasKeys() async throws {
        let env = AWSAccKeys.credentials("ENV"), file = AWSAccKeys.credentials("FILE")
        let home = try AWSAccHome(config: "[default]\nregion = us-west-2\n", credentials: AWSAcc.keys("default", file))
        defer { home.remove() }
        let resolver = AWSAcc.resolver(home, environment: AWSAcc.environment(env))
        #expect(try await resolver.resolve(profile: "default").credentials == env)
        #expect(try await resolver.resolve(profile: "").credentials == env)
    }

    @Test func environmentKeysWhenDefaultHasOnlyARegion() async throws {
        let env = AWSAccKeys.credentials("ENV")
        let home = try AWSAccHome(config: "[default]\nregion = us-west-2\n")
        defer { home.remove() }
        let resolver = AWSAcc.resolver(home, environment: AWSAcc.environment(env))
        #expect(try await resolver.resolve(profile: "default").credentials == env)
        #expect(try await resolver.resolve(profile: "").credentials == env)
    }

    @Test func environmentKeysAreNeverUsedForANamedProfile() async throws {
        let env = AWSAccKeys.credentials("ENV"), dev = AWSAccKeys.credentials("DEV")
        let home = try AWSAccHome(config: "[profile regiononly]\nregion = us-west-2\n", credentials: AWSAcc.keys("dev", dev))
        defer { home.remove() }
        let resolver = AWSAcc.resolver(home, environment: AWSAcc.environment(env))
        #expect(try await resolver.resolve(profile: "dev").credentials == dev)
        let regionOnly = await AWSAcc.failure { try await resolver.resolve(profile: "regiononly") }
        #expect(regionOnly is AWSCredentialError, "a named profile without credentials fails rather than taking the environment's")
        let missing = await AWSAcc.failure { try await resolver.resolve(profile: "nosuchprofile") }
        #expect(missing is AWSCredentialError)
    }

    @Test func awsProfileInTheEnvironmentIsIgnored() async throws {
        let def = AWSAccKeys.credentials("DEFAULT"), other = AWSAccKeys.credentials("OTHER")
        let home = try AWSAccHome(credentials: AWSAcc.keys("default", def) + AWSAcc.keys("other", other))
        defer { home.remove() }
        let resolver = AWSAcc.resolver(home, environment: ["AWS_PROFILE": "other", "AWS_DEFAULT_PROFILE": "other"])
        #expect(try await resolver.resolve(profile: "").credentials == def)
        #expect(try await resolver.resolve(profile: "default").credentials == def)
        // Nor does it stand in for a profile that isn't there.
        let empty = try AWSAccHome(credentials: AWSAcc.keys("other", other))
        defer { empty.remove() }
        let error = await AWSAcc.failure { try await AWSAcc.resolver(empty, environment: ["AWS_PROFILE": "other"]).resolve(profile: "") }
        #expect(error != nil)
    }

    @Test func awsConfigFileAndSharedCredentialsFileAreRespected() async throws {
        let decoy = AWSAccKeys.credentials("DECOY"), real = AWSAccKeys.credentials("ELSEWHERE")
        let home = try AWSAccHome(config: "[profile dev]\nregion = us-east-1\n[profile decoyonly]\nregion = us-east-1\n",
                                  credentials: AWSAcc.keys("dev", decoy))
        defer { home.remove() }
        let config = try home.file("elsewhere/my-config", "[profile dev]\nregion = ca-central-1\n[profile proc]\ncredential_process = /usr/local/bin/my-creds\n")
        let credentials = try home.file("elsewhere/my-credentials", AWSAcc.keys("dev", real))
        let environment = ["AWS_CONFIG_FILE": config.path, "AWS_SHARED_CREDENTIALS_FILE": credentials.path]
        let runner = AWSAccRunner()
        let resolver = AWSAcc.resolver(home, environment: environment, runner: runner)
        let resolved = try await resolver.resolve(profile: "dev")
        #expect(resolved.credentials == real)
        #expect(resolved.region == "ca-central-1")
        #expect(Set(resolver.profiles().map(\.name)) == ["dev", "proc"])
        // @config's listing reads the same files.
        let listed = AIConfig.awsProfiles(environment: environment)
        #expect(listed.map(\.name).sorted() == ["dev", "proc"])
        #expect(listed.first { $0.name == "dev" }?.region == "ca-central-1")
        #expect(runner.count == 0)
    }

    @Test func credentialsNeverShowTheSecretOrToken() {
        let keys = AWSAccKeys.credentials("SHOWN")
        for text in [String(describing: keys), "\(keys)", String(reflecting: keys)] {
            #expect(AWSAccKeys.hidesSecrets(text), "\(text.count) characters")
            #expect(!text.contains(keys.accessKeyId), "at most the key ID's last 4 characters")
        }
    }
}

// MARK: - The order within a profile

@Suite(.timeLimit(.minutes(1)))
struct AWSCredentialsAcceptanceOrderTests {
    @Test func roleArnBeatsTheProfilesOwnKeys() async throws {
        let own = AWSAccKeys.credentials("OWN"), base = AWSAccKeys.credentials("BASE")
        let home = try AWSAccHome(config: "[profile both]\nrole_arn = \(AWSAcc.roleArn)\nsource_profile = base\n",
                                  credentials: AWSAcc.keys("both", own) + AWSAcc.keys("base", base))
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        http.on(AWSAccSTS.host("us-east-1"), AWSAccSTS.issuing("ROLE", clock: clock))
        let resolver = AWSAcc.resolver(home, http: http, clock: clock)
        #expect(try await resolver.resolve(profile: "both").credentials == AWSAccKeys.credentials("ROLE1"))
        #expect(http.requests().map(AWSAcc.signedKey) == [base.accessKeyId])
        #expect(resolver.status(profile: "both").kind == .role(source: "base"))
    }

    @Test func aSourceProfileNamingItselfUsesItsOwnStaticKeys() async throws {
        let own = AWSAccKeys.credentials("SELF")
        let home = try AWSAccHome(config: "[profile selfish]\nrole_arn = \(AWSAcc.roleArn)\nsource_profile = selfish\n",
                                  credentials: AWSAcc.keys("selfish", own))
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        http.on(AWSAccSTS.host("us-east-1"), AWSAccSTS.issuing("ROLE", clock: clock))
        let resolved = try await AWSAcc.resolver(home, http: http, clock: clock).resolve(profile: "selfish")
        #expect(resolved.credentials == AWSAccKeys.credentials("ROLE1"))
        #expect(http.requests().map(AWSAcc.signedKey) == [own.accessKeyId])
    }

    // botocore resolves a source profile that has keys of its own with those keys, not by assuming its role (a profile
    // naming itself only works at the top): only the outer role is assumed.
    @Test func aSourceProfileWithKeysOfItsOwnIsUsedWithThem() async throws {
        let own = AWSAccKeys.credentials("SELF"), base = AWSAccKeys.credentials("BASE")
        let home = try AWSAccHome(config: """
            [profile outer]
            role_arn = arn:aws:iam::123456789012:role/outer
            source_profile = inner
            [profile inner]
            role_arn = arn:aws:iam::123456789012:role/inner
            source_profile = inner
            [profile outer2]
            role_arn = arn:aws:iam::123456789012:role/outer2
            source_profile = inner2
            [profile inner2]
            role_arn = arn:aws:iam::123456789012:role/inner2
            source_profile = base
            """, credentials: AWSAcc.keys("inner", own) + AWSAcc.keys("inner2", own) + AWSAcc.keys("base", base))
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        http.on(AWSAccSTS.host("us-east-1"), AWSAccSTS.issuing("ROLE", clock: clock))
        let resolver = AWSAcc.resolver(home, http: http, clock: clock)
        #expect(try await resolver.resolve(profile: "outer").credentials == AWSAccKeys.credentials("ROLE1"))
        #expect(try await resolver.resolve(profile: "outer2").credentials == AWSAccKeys.credentials("ROLE2"))
        let requests = http.requests()
        #expect(requests.map { AWSAcc.form($0)["RoleArn"] ?? "" } == ["arn:aws:iam::123456789012:role/outer", "arn:aws:iam::123456789012:role/outer2"])
        #expect(requests.map(AWSAcc.signedKey) == [own.accessKeyId, own.accessKeyId])
        // Resolved on its own, inner is still a role (a profile naming itself takes its own keys as the source).
        #expect(try await resolver.resolve(profile: "inner").credentials == AWSAccKeys.credentials("ROLE3"))
        #expect(http.requests().last.flatMap(AWSAcc.signedKey) == own.accessKeyId)
    }

    @Test func roleArnBeatsSSO() async throws {
        let base = AWSAccKeys.credentials("BASE")
        let home = try AWSAccHome(config: AWSAccSSO.config + """
            [profile rolesso]
            role_arn = \(AWSAcc.roleArn)
            source_profile = base
            sso_session = my-sso
            sso_account_id = 111122223333
            sso_role_name = ReadOnly
            """, credentials: AWSAcc.keys("base", base))
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(3600))
        http.on(AWSAccSTS.host("us-east-1"), AWSAccSTS.issuing("ROLE", clock: clock))
        http.on(AWSAccSSO.host("us-east-1"), AWSAccSSO.issuing("SSO", clock: clock))
        #expect(try await AWSAcc.resolver(home, http: http, clock: clock).resolve(profile: "rolesso").credentials == AWSAccKeys.credentials("ROLE1"))
        #expect(http.requests(AWSAccSSO.host("us-east-1")).isEmpty)
    }

    @Test func ssoBeatsKeysInTheCredentialsFile() async throws {
        let home = try AWSAccHome(config: AWSAccSSO.config, credentials: AWSAcc.keys("sso", AWSAccKeys.credentials("FILE")))
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(3600))
        http.on(AWSAccSSO.host("us-east-1"), AWSAccSSO.issuing("SSO", clock: clock))
        #expect(try await AWSAcc.resolver(home, http: http, clock: clock).resolve(profile: "sso").credentials == AWSAccKeys.credentials("SSO1"))
    }

    @Test func keysInTheCredentialsFileBeatCredentialProcess() async throws {
        let file = AWSAccKeys.credentials("FILE")
        let home = try AWSAccHome(config: "[profile both]\ncredential_process = /usr/local/bin/my-creds --profile dev\n",
                                  credentials: AWSAcc.keys("both", file))
        defer { home.remove() }
        let runner = AWSAccRunner.issuing("PROC")
        #expect(try await AWSAcc.resolver(home, runner: runner).resolve(profile: "both").credentials == file)
        #expect(runner.count == 0)
    }

    @Test func credentialProcessBeatsKeysInTheConfigFile() async throws {
        let home = try AWSAccHome(config: AWSAcc.keys("profile both", AWSAccKeys.credentials("CONFIG"))
            + "credential_process = /usr/local/bin/my-creds --profile dev\n")
        defer { home.remove() }
        let runner = AWSAccRunner.issuing("PROC")
        #expect(try await AWSAcc.resolver(home, runner: runner).resolve(profile: "both").credentials == AWSAccKeys.credentials("PROC1"))
        #expect(runner.count == 1)
    }

    @Test func credentialProcessInTheCredentialsFileBeatsKeysInTheConfigFile() async throws {
        let home = try AWSAccHome(config: AWSAcc.keys("profile both", AWSAccKeys.credentials("CONFIG")),
                                  credentials: "[both]\ncredential_process = /usr/local/bin/my-creds --profile dev\n")
        defer { home.remove() }
        let runner = AWSAccRunner.issuing("PROC")
        #expect(try await AWSAcc.resolver(home, runner: runner).resolve(profile: "both").credentials == AWSAccKeys.credentials("PROC1"))
    }

    @Test func keysInTheCredentialsFileBeatKeysInTheConfigFile() async throws {
        let file = AWSAccKeys.credentials("FILE")
        let home = try AWSAccHome(config: AWSAcc.keys("profile both", AWSAccKeys.credentials("CONFIG")), credentials: AWSAcc.keys("both", file))
        defer { home.remove() }
        #expect(try await AWSAcc.resolver(home).resolve(profile: "both").credentials == file)
    }
}

// MARK: - Expiry and refresh

@Suite(.timeLimit(.minutes(1)))
struct AWSCredentialsAcceptanceRefreshTests {
    func processHome() throws -> AWSAccHome {
        try AWSAccHome(config: "[profile dev]\ncredential_process = /usr/local/bin/my-creds --profile dev\n")
    }

    func roleHome() throws -> AWSAccHome {
        try AWSAccHome(config: "[profile role]\nrole_arn = \(AWSAcc.roleArn)\nsource_profile = base\n",
                       credentials: AWSAcc.keys("base", AWSAccKeys.credentials("BASE")))
    }

    @Test func theMarginsAreFiveAndTenMinutes() {
        #expect(AWSCredentialResolver.refreshMargin == 5 * 60)
        #expect(AWSCredentialResolver.backgroundWindow == 10 * 60)
    }

    @Test func cachedWhileMoreThanTenMinutesAreLeft() async throws {
        let home = try processHome()
        defer { home.remove() }
        let clock = AWSAccClock(), runner = AWSAccRunner.issuing("P", clock: clock, lifetime: 3600)
        let resolver = AWSAcc.resolver(home, runner: runner, clock: clock)
        #expect(try await resolver.resolve(profile: "dev").credentials == AWSAccKeys.credentials("P1"))
        clock.advance(49 * 60)  // 11 minutes left
        #expect(try await resolver.resolve(profile: "dev").credentials == AWSAccKeys.credentials("P1"))
        await resolver.waitForRefreshes()
        #expect(runner.count == 1)
    }

    @Test func underTenMinutesTheCachedOnesAreUsedAndRefreshedInTheBackground() async throws {
        let home = try processHome()
        defer { home.remove() }
        let clock = AWSAccClock(), runner = AWSAccRunner.issuing("P", clock: clock, lifetime: 3600)
        let resolver = AWSAcc.resolver(home, runner: runner, clock: clock)
        _ = try await resolver.resolve(profile: "dev")
        clock.advance(51 * 60)  // 9 minutes left
        #expect(try await resolver.resolve(profile: "dev").credentials == AWSAccKeys.credentials("P1"))
        await resolver.waitForRefreshes()
        #expect(runner.count == 2, "refreshed in the background")
        #expect(try await resolver.resolve(profile: "dev").credentials == AWSAccKeys.credentials("P2"))
        #expect(runner.count == 2)
    }

    @Test func typingNeverWaitsOnSTSInTheBackgroundWindow() async throws {
        let home = try roleHome()
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP(), gate = AWSAccGate()
        http.on(AWSAccSTS.host("us-east-1")) { _, index in
            if index > 0 { await gate.wait() }
            return .init(status: 200, body: AWSAccSTS.response(AWSAccKeys.credentials("ROLE\(index + 1)"), expiration: clock.now.addingTimeInterval(3600)))
        }
        let resolver = AWSAcc.resolver(home, http: http, clock: clock)
        _ = try await resolver.resolve(profile: "role")
        clock.advance(51 * 60)
        let started = Date()
        let resolved = try await resolver.resolve(profile: "role")
        let waited = Date().timeIntervalSince(started)
        #expect(resolved.credentials == AWSAccKeys.credentials("ROLE1"), "the cached ones, without waiting for STS")
        #expect(waited < 2, "waited \(waited) s for STS")
        gate.open()
        await resolver.waitForRefreshes()
        #expect(try await resolver.resolve(profile: "role").credentials == AWSAccKeys.credentials("ROLE2"))
        #expect(http.requests().count == 2)
    }

    @Test func underFiveMinutesTheyAreFetchedBeforeTheRequest() async throws {
        let home = try processHome()
        defer { home.remove() }
        let clock = AWSAccClock(), runner = AWSAccRunner.issuing("P", clock: clock, lifetime: 3600)
        let resolver = AWSAcc.resolver(home, runner: runner, clock: clock)
        _ = try await resolver.resolve(profile: "dev")
        clock.advance(56 * 60)  // 4 minutes left
        #expect(try await resolver.resolve(profile: "dev").credentials == AWSAccKeys.credentials("P2"))
        #expect(runner.count == 2)
    }

    @Test func theFiveMinuteBoundary() async throws {
        let home = try processHome()
        defer { home.remove() }
        // 5 min 10 s left: still good (a background refresh may start).
        let clock = AWSAccClock(), runner = AWSAccRunner.issuing("P", clock: clock, lifetime: 3600)
        let resolver = AWSAcc.resolver(home, runner: runner, clock: clock)
        _ = try await resolver.resolve(profile: "dev")
        clock.advance(3600 - 310)
        #expect(try await resolver.resolve(profile: "dev").credentials == AWSAccKeys.credentials("P1"))
        await resolver.waitForRefreshes()
        // 4 min 50 s left: fetched again first.
        let clock2 = AWSAccClock(), runner2 = AWSAccRunner.issuing("P", clock: clock2, lifetime: 3600)
        let resolver2 = AWSAcc.resolver(home, runner: runner2, clock: clock2)
        _ = try await resolver2.resolve(profile: "dev")
        clock2.advance(3600 - 290)
        #expect(try await resolver2.resolve(profile: "dev").credentials == AWSAccKeys.credentials("P2"))
    }

    @Test func aRoleIsAssumedAgainFiveMinutesBeforeItExpires() async throws {
        let home = try roleHome()
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        http.on(AWSAccSTS.host("us-east-1"), AWSAccSTS.issuing("ROLE", clock: clock, lifetime: 3600))
        let resolver = AWSAcc.resolver(home, http: http, clock: clock)
        _ = try await resolver.resolve(profile: "role")
        clock.advance(30 * 60)
        #expect(try await resolver.resolve(profile: "role").credentials == AWSAccKeys.credentials("ROLE1"))
        #expect(http.requests().count == 1)
        clock.advance(26 * 60)
        #expect(try await resolver.resolve(profile: "role").credentials == AWSAccKeys.credentials("ROLE2"))
        #expect(http.requests().count == 2)
    }

    @Test func ssoCredentialsAreFetchedAgainFiveMinutesBeforeTheyExpire() async throws {
        let home = try AWSAccHome(config: AWSAccSSO.config)
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(8 * 3600))
        http.on(AWSAccSSO.host("us-east-1"), AWSAccSSO.issuing("SSO", clock: clock))
        let resolver = AWSAcc.resolver(home, http: http, clock: clock)
        _ = try await resolver.resolve(profile: "sso")
        clock.advance(45 * 60)
        #expect(try await resolver.resolve(profile: "sso").credentials == AWSAccKeys.credentials("SSO1"))
        clock.advance(11 * 60)
        #expect(try await resolver.resolve(profile: "sso").credentials == AWSAccKeys.credentials("SSO2"))
        #expect(http.requests().count == 2)
    }

    @Test func withoutAnExpirationTheProgramRunsOnceUntilAnAuthError() async throws {
        let home = try processHome()
        defer { home.remove() }
        let clock = AWSAccClock(), runner = AWSAccRunner.issuing("P")
        let resolver = AWSAcc.resolver(home, runner: runner, clock: clock)
        let first = try await resolver.resolve(profile: "dev")
        #expect(first.expiration == nil)
        clock.advance(30 * 86400)
        #expect(try await resolver.resolve(profile: "dev").credentials == first.credentials)
        #expect(runner.count == 1)
        // AWS said they expired: run again.
        #expect(try await resolver.refresh(profile: "dev", replacing: first.credentials).credentials == AWSAccKeys.credentials("P2"))
        #expect(try await resolver.resolve(profile: "dev").credentials == AWSAccKeys.credentials("P2"))
        #expect(runner.count == 2)
    }

    @Test func aFailedBackgroundRefreshKeepsTheCachedOnesButOneInTheLastFiveMinutesFailsTheRequest() async throws {
        let home = try roleHome()
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        http.on(AWSAccSTS.host("us-east-1")) { _, index in
            index == 0
                ? .init(status: 200, body: AWSAccSTS.response(AWSAccKeys.credentials("ROLE1"), expiration: clock.now.addingTimeInterval(3600)))
                : .init(status: 403, body: AWSAccSTS.error("AccessDenied", AWSAccSTS.denied))
        }
        let resolver = AWSAcc.resolver(home, http: http, clock: clock)
        _ = try await resolver.resolve(profile: "role")
        clock.advance(51 * 60)
        #expect(try await resolver.resolve(profile: "role").credentials == AWSAccKeys.credentials("ROLE1"))
        await resolver.waitForRefreshes()
        #expect(http.requests().count >= 2, "a background refresh was tried")
        clock.advance(60)
        #expect(try await resolver.resolve(profile: "role").credentials == AWSAccKeys.credentials("ROLE1"),
                "still more than 5 minutes left: the cached ones")
        await resolver.waitForRefreshes()
        clock.advance(4 * 60)  // 4 minutes left
        let error = await AWSAcc.failure { try await resolver.resolve(profile: "role") }
        #expect(error is AWSCredentialError)
        #expect(AWSAcc.message(error).contains("AccessDenied"), "\(AWSAcc.message(error))")
    }

    @Test func forceRefreshGoesThroughTheWholeChain() async throws {
        let home = try AWSAccHome(config: """
            [profile role]
            role_arn = \(AWSAcc.roleArn)
            source_profile = proc
            [profile proc]
            credential_process = /usr/local/bin/my-creds --profile dev
            """)
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        let runner = AWSAccRunner.issuing("PROC", clock: clock, lifetime: 3600)
        http.on(AWSAccSTS.host("us-east-1"), AWSAccSTS.issuing("ROLE", clock: clock))
        let resolver = AWSAcc.resolver(home, runner: runner, http: http, clock: clock)
        _ = try await resolver.resolve(profile: "role")
        #expect(try await resolver.resolve(profile: "role", forceRefresh: true).credentials == AWSAccKeys.credentials("ROLE2"))
        #expect(runner.count == 2 && http.requests().count == 2, "Test Connection exercises the full chain")
    }

    @Test func invalidateForgetsTheCachedOnes() async throws {
        let home = try processHome()
        defer { home.remove() }
        let runner = AWSAccRunner.issuing("P")
        let resolver = AWSAcc.resolver(home, runner: runner)
        _ = try await resolver.resolve(profile: "dev")
        resolver.invalidate(profile: "dev")
        #expect(try await resolver.resolve(profile: "dev").credentials == AWSAccKeys.credentials("P2"))
        #expect(runner.count == 2)
    }
}

// MARK: - Single flight

@Suite(.timeLimit(.minutes(1)))
struct AWSCredentialsAcceptanceSingleFlightTests {
    static func concurrently(_ count: Int, _ body: @escaping @Sendable () async throws -> AWSCredentials) async throws -> Set<String> {
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<count { group.addTask { try await body().accessKeyId } }
            var out = Set<String>()
            for try await id in group { out.insert(id) }
            return out
        }
    }

    @Test func concurrentRequestsRunTheProgramOnce() async throws {
        let home = try AWSAccHome(config: "[profile dev]\ncredential_process = /usr/local/bin/my-creds --profile dev\n")
        defer { home.remove() }
        let clock = AWSAccClock()
        let runner = AWSAccRunner.issuing("P", clock: clock, lifetime: 3600, delay: .milliseconds(300))
        let resolver = AWSAcc.resolver(home, runner: runner, clock: clock)
        let ids = try await Self.concurrently(25) { try await resolver.resolve(profile: "dev").credentials }
        #expect(ids == [AWSAccKeys.credentials("P1").accessKeyId])
        #expect(runner.count == 1)
        #expect(resolver.fetchCount(profile: "dev") == 1)
    }

    @Test func concurrentRequestsAssumeTheRoleOnce() async throws {
        let home = try AWSAccHome(config: """
            [profile role]
            role_arn = \(AWSAcc.roleArn)
            source_profile = proc
            [profile proc]
            credential_process = /usr/local/bin/my-creds --profile dev
            """)
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        let runner = AWSAccRunner.issuing("PROC", clock: clock, lifetime: 3600, delay: .milliseconds(100))
        http.on(AWSAccSTS.host("us-east-1"), AWSAccSTS.issuing("ROLE", clock: clock, delay: .milliseconds(300)))
        let resolver = AWSAcc.resolver(home, runner: runner, http: http, clock: clock)
        let ids = try await Self.concurrently(25) { try await resolver.resolve(profile: "role").credentials }
        #expect(ids == [AWSAccKeys.credentials("ROLE1").accessKeyId])
        #expect(http.requests().count == 1 && runner.count == 1)
    }

    @Test func concurrentRequestsInTheBackgroundWindowStartOneRefresh() async throws {
        let home = try AWSAccHome(config: "[profile dev]\ncredential_process = /usr/local/bin/my-creds --profile dev\n")
        defer { home.remove() }
        let clock = AWSAccClock()
        let runner = AWSAccRunner.issuing("P", clock: clock, lifetime: 3600, delay: .milliseconds(300))
        let resolver = AWSAcc.resolver(home, runner: runner, clock: clock)
        _ = try await resolver.resolve(profile: "dev")
        clock.advance(51 * 60)
        let ids = try await Self.concurrently(25) { try await resolver.resolve(profile: "dev").credentials }
        #expect(ids == [AWSAccKeys.credentials("P1").accessKeyId])
        await resolver.waitForRefreshes()
        #expect(runner.count == 2)
    }

    @Test func concurrentRefreshesAfterTheSameRefusalRunTheProgramOnce() async throws {
        let home = try AWSAccHome(config: "[profile dev]\ncredential_process = /usr/local/bin/my-creds --profile dev\n")
        defer { home.remove() }
        let runner = AWSAccRunner.issuing("P", delay: .milliseconds(200))
        let resolver = AWSAcc.resolver(home, runner: runner)
        let failed = try await resolver.resolve(profile: "dev").credentials
        let ids = try await Self.concurrently(10) { try await resolver.refresh(profile: "dev", replacing: failed).credentials }
        #expect(ids == [AWSAccKeys.credentials("P2").accessKeyId])
        #expect(runner.count == 2)
    }
}

// MARK: - STS ExpiredToken: the source fetched again, once

@Suite(.timeLimit(.minutes(1)))
struct AWSCredentialsAcceptanceSTSRetryTests {
    func home() throws -> AWSAccHome {
        try AWSAccHome(config: """
            [profile role]
            role_arn = \(AWSAcc.roleArn)
            source_profile = proc
            [profile proc]
            credential_process = /usr/local/bin/my-creds --profile dev
            """)
    }

    @Test func anExpiredSourceIsFetchedAgainOnce() async throws {
        let home = try home()
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP(), runner = AWSAccRunner.issuing("PROC")
        http.on(AWSAccSTS.host("us-east-1")) { _, index in
            index == 0
                ? .init(status: 400, body: AWSAccSTS.error("ExpiredToken", AWSAccSTS.expired))
                : .init(status: 200, body: AWSAccSTS.response(AWSAccKeys.credentials("ROLE"), expiration: clock.now.addingTimeInterval(3600)))
        }
        let resolved = try await AWSAcc.resolver(home, runner: runner, http: http, clock: clock).resolve(profile: "role")
        #expect(resolved.credentials == AWSAccKeys.credentials("ROLE"))
        #expect(runner.count == 2)
        #expect(http.requests().map(AWSAcc.signedKey) == [AWSAccKeys.credentials("PROC1").accessKeyId, AWSAccKeys.credentials("PROC2").accessKeyId])
    }

    @Test func onlyOnce() async throws {
        let home = try home()
        defer { home.remove() }
        let http = AWSAccHTTP(), runner = AWSAccRunner.issuing("PROC")
        http.on(AWSAccSTS.host("us-east-1")) { _, _ in .init(status: 400, body: AWSAccSTS.error("ExpiredToken", AWSAccSTS.expired)) }
        let error = await AWSAcc.failure { try await AWSAcc.resolver(home, runner: runner, http: http).resolve(profile: "role") }
        #expect(error is AWSCredentialError)
        #expect(runner.count == 2 && http.requests().count == 2)
    }

    @Test func otherSTSErrorsDontFetchTheSourceAgain() async throws {
        let home = try home()
        defer { home.remove() }
        let http = AWSAccHTTP(), runner = AWSAccRunner.issuing("PROC")
        http.on(AWSAccSTS.host("us-east-1")) { _, _ in .init(status: 403, body: AWSAccSTS.error("AccessDenied", AWSAccSTS.denied)) }
        let error = await AWSAcc.failure { try await AWSAcc.resolver(home, runner: runner, http: http).resolve(profile: "role") }
        #expect(error is AWSCredentialError)
        #expect(runner.count == 1 && http.requests().count == 1)
    }
}

// MARK: - Bedrock: refreshed and sent again once

@Suite(.timeLimit(.minutes(1)))
struct AWSCredentialsAcceptanceBedrockRetryTests {
    func processResolver(clock: AWSAccClock = AWSAccClock(), lifetime: TimeInterval? = nil) throws -> (AWSCredentialResolver, AWSAccRunner, AWSAccHome) {
        let home = try AWSAccHome(config: "[profile dev]\ncredential_process = /usr/local/bin/my-creds --profile dev\n")
        let runner = AWSAccRunner.issuing("B", clock: clock, lifetime: lifetime)
        return (AWSAcc.resolver(home, runner: runner, clock: clock), runner, home)
    }

    @Test func anExpiredTokenIsRefreshedAndSentAgainOnce() async throws {
        let region = "us-accept-1", host = AWSAccBedrock.host(region)
        AWSAccBedrockStub.on(host, [AWSAccBedrockStub.refused("ExpiredTokenException"), AWSAccBedrockStub.answer("OK")])
        let (resolver, runner, home) = try processResolver()
        defer { home.remove() }
        let (text, error) = await AWSAccBedrock.ask(resolver, region: region)
        #expect(error == nil, "\(String(describing: error))")
        #expect(text == "OK")
        #expect(AWSAccBedrockStub.keys(host) == [AWSAccKeys.credentials("B1").accessKeyId, AWSAccKeys.credentials("B2").accessKeyId])
        #expect(runner.count == 2)
    }

    @Test func credentialsThatHadNotExpiredYetAreStillDroppedAndFetchedAgain() async throws {
        let region = "us-accept-2", host = AWSAccBedrock.host(region)
        AWSAccBedrockStub.on(host, [AWSAccBedrockStub.refused("ExpiredTokenException"), AWSAccBedrockStub.answer("OK")])
        let (resolver, runner, home) = try processResolver(lifetime: 3600)
        defer { home.remove() }
        let (text, error) = await AWSAccBedrock.ask(resolver, region: region)
        #expect(error == nil && text == "OK")
        #expect(runner.count == 2)
        #expect(AWSAccBedrockStub.keys(host).count == 2)
    }

    @Test func refusedTwiceFailsAfterExactlyTwoRequests() async throws {
        let region = "us-accept-3", host = AWSAccBedrock.host(region)
        AWSAccBedrockStub.on(host, [AWSAccBedrockStub.refused("ExpiredTokenException"), AWSAccBedrockStub.refused("ExpiredTokenException"),
                                    AWSAccBedrockStub.answer("OK")])
        let (resolver, runner, home) = try processResolver()
        defer { home.remove() }
        let (text, error) = await AWSAccBedrock.ask(resolver, region: region)
        #expect(error != nil && text.isEmpty)
        #expect((error as? BedrockError)?.isExpiredCredentials == true, "the refusal is what's reported")
        #expect(AWSAccBedrockStub.keys(host).count == 2)
        #expect(runner.count == 2)
    }

    @Test func noRetryOnceTextHasArrived() async throws {
        let region = "us-accept-4", host = AWSAccBedrock.host(region)
        AWSAccBedrockStub.on(host, [AWSAccBedrockStub.stream(AWSAccEventStream.text("Hel")
                                        + AWSAccEventStream.exception("ExpiredTokenException", AWSAccSTS.expired)),
                                    AWSAccBedrockStub.answer("Hello")])
        let (resolver, runner, home) = try processResolver()
        defer { home.remove() }
        let (text, error) = await AWSAccBedrock.ask(resolver, region: region)
        #expect(text == "Hel")
        #expect(error != nil)
        #expect(AWSAccBedrockStub.keys(host).count == 1, "not sent again after text came")
        #expect(runner.count == 1)
    }

    @Test func anExpiredTokenExceptionBeforeAnyTextIsRetried() async throws {
        let region = "us-accept-5", host = AWSAccBedrock.host(region)
        AWSAccBedrockStub.on(host, [AWSAccBedrockStub.stream(AWSAccEventStream.exception("ExpiredTokenException", AWSAccSTS.expired)),
                                    AWSAccBedrockStub.answer("OK")])
        let (resolver, runner, home) = try processResolver()
        defer { home.remove() }
        let (text, error) = await AWSAccBedrock.ask(resolver, region: region)
        #expect(error == nil && text == "OK")
        #expect(AWSAccBedrockStub.keys(host).count == 2 && runner.count == 2)
    }

    @Test(arguments: [
        ("us-accept-6", "UnrecognizedClientException", 403, "The security token included in the request is invalid."),
        ("us-accept-7", "InvalidSignatureException", 403, "The security token included in the request is expired"),
        ("us-accept-8", nil, 403, "The security token included in the request is expired"),
    ] as [(String, String?, Int, String)])
    func otherAuthErrorsAreRetried(region: String, type: String?, status: Int, message: String) async throws {
        let host = AWSAccBedrock.host(region)
        AWSAccBedrockStub.on(host, [AWSAccBedrockStub.refused(type, status: status, message: message), AWSAccBedrockStub.answer("OK")])
        let (resolver, runner, home) = try processResolver()
        defer { home.remove() }
        let (text, error) = await AWSAccBedrock.ask(resolver, region: region)
        #expect(error == nil && text == "OK", "\(String(describing: error))")
        #expect(AWSAccBedrockStub.keys(host).count == 2 && runner.count == 2)
    }

    @Test(arguments: [
        ("us-accept-9", "AccessDeniedException", 403, "You don't have access to the model with the specified model ID."),
        ("us-accept-10", "InvalidSignatureException", 403,
         "The request signature we calculated does not match the signature you provided."),
        ("us-accept-11", "ValidationException", 400, "The provided model identifier is invalid."),
        ("us-accept-12", "ThrottlingException", 429, "Too many requests, please wait before trying again."),
    ] as [(String, String, Int, String)])
    func otherErrorsAreNotRetried(region: String, type: String, status: Int, message: String) async throws {
        let host = AWSAccBedrock.host(region)
        AWSAccBedrockStub.on(host, [AWSAccBedrockStub.refused(type, status: status, message: message), AWSAccBedrockStub.answer("OK")])
        let (resolver, runner, home) = try processResolver()
        defer { home.remove() }
        let (_, error) = await AWSAccBedrock.ask(resolver, region: region)
        #expect(error != nil)
        #expect(AWSAccBedrockStub.keys(host).count == 1 && runner.count == 1)
    }

    @Test func aRoleProfileIsAssumedAgainForTheRetry() async throws {
        let region = "us-accept-13", host = AWSAccBedrock.host(region)
        AWSAccBedrockStub.on(host, [AWSAccBedrockStub.refused("ExpiredTokenException"), AWSAccBedrockStub.answer("OK")])
        let home = try AWSAccHome(config: "[profile dev]\nrole_arn = \(AWSAcc.roleArn)\nsource_profile = base\n",
                                  credentials: AWSAcc.keys("base", AWSAccKeys.credentials("BASE")))
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        http.on(AWSAccSTS.host("us-east-1"), AWSAccSTS.issuing("ROLE", clock: clock))
        let resolver = AWSAcc.resolver(home, http: http, clock: clock)
        let (text, error) = await AWSAccBedrock.ask(resolver, region: region)
        #expect(error == nil && text == "OK")
        #expect(AWSAccBedrockStub.keys(host) == [AWSAccKeys.credentials("ROLE1").accessKeyId, AWSAccKeys.credentials("ROLE2").accessKeyId])
        #expect(http.requests().count == 2)
    }

    @Test func throughTheConverter() async throws {
        let region = "us-accept-14", host = AWSAccBedrock.host(region)
        let url = try #require(Bundle.module.url(forResource: "bedrock-converse-stream", withExtension: "bin", subdirectory: "Fixtures"))
        AWSAccBedrockStub.on(host, [AWSAccBedrockStub.refused("ExpiredTokenException"), AWSAccBedrockStub.stream(Array(try Data(contentsOf: url)))])
        let (resolver, runner, home) = try processResolver()
        defer { home.remove() }
        var config = Config.default
        config.provider = .bedrock
        config.region = region
        config.awsProfile = "dev"
        let fixed = config
        let converter = Converter(client: BedrockClient(session: AWSAccBedrockStub.session()), loadConfig: { fixed },
                                  loadCredentials: { try await resolver.resolve(profile: $0) })
        var last: ConversionUpdate?
        for try await update in converter.convert("我今天有点不舒服") { last = update }
        #expect(last?.isFinal == true)
        #expect(AWSAccBedrockStub.keys(host).count == 2 && runner.count == 2)
    }

    @Test(arguments: [
        (BedrockError.http(status: 403, type: "ExpiredTokenException", message: "The security token included in the request is expired"), true),
        (.http(status: 403, type: "UnrecognizedClientException", message: "The security token included in the request is invalid."), true),
        (.http(status: 403, type: "InvalidSignatureException", message: "The security token included in the request is expired"), true),
        (.http(status: 403, type: nil, message: "The security token included in the request is expired"), true),
        (.stream(type: "ExpiredTokenException", message: "The security token included in the request is expired"), true),
        (.http(status: 403, type: "InvalidSignatureException", message: "The request signature we calculated does not match the signature you provided."), false),
        (.http(status: 403, type: "AccessDeniedException", message: "You don't have access to the model with the specified model ID."), false),
        (.http(status: 400, type: "ValidationException", message: "The provided model identifier is invalid."), false),
        (.http(status: 500, type: "InternalServerException", message: "The security token included in the request is expired"), false),
        (.invalidResponse("stream ended mid-message"), false),
    ] as [(BedrockError, Bool)])
    func whichBedrockErrorsMeanExpiredCredentials(error: BedrockError, expired: Bool) {
        #expect(error.isExpiredCredentials == expired)
    }
}

// MARK: - Cycles and MFA

@Suite(.timeLimit(.minutes(1)))
struct AWSCredentialsAcceptanceCycleAndMFATests {
    @Test func twoProfilesNamingEachOther() async throws {
        let home = try AWSAccHome(config: """
            [profile a]
            role_arn = arn:aws:iam::123456789012:role/a
            source_profile = b
            [profile b]
            role_arn = arn:aws:iam::123456789012:role/b
            source_profile = a
            """)
        defer { home.remove() }
        let runner = AWSAccRunner(), http = AWSAccHTTP()
        let resolver = AWSAcc.resolver(home, runner: runner, http: http)
        let error = await AWSAcc.failure { try await resolver.resolve(profile: "a") }
        guard case .sourceProfileLoop? = error as? AWSCredentialError else {
            Issue.record("expected a source_profile loop, got \(String(describing: error))")
            return
        }
        let message = AWSAcc.message(error)
        #expect(message.contains("a") && message.contains("b"))
        #expect(runner.count == 0 && http.requests().isEmpty)
        #expect(!resolver.status(profile: "a").isReady)
    }

    @Test func aLoopFurtherDownTheChain() async throws {
        let home = try AWSAccHome(config: """
            [profile a]
            role_arn = arn:aws:iam::123456789012:role/a
            source_profile = b
            [profile b]
            role_arn = arn:aws:iam::123456789012:role/b
            source_profile = c
            [profile c]
            role_arn = arn:aws:iam::123456789012:role/c
            source_profile = b
            """)
        defer { home.remove() }
        let http = AWSAccHTTP()
        let error = await AWSAcc.failure { try await AWSAcc.resolver(home, http: http).resolve(profile: "a") }
        guard case .sourceProfileLoop? = error as? AWSCredentialError else {
            Issue.record("expected a source_profile loop, got \(String(describing: error))")
            return
        }
        #expect(http.requests().isEmpty)
    }

    @Test func aProfileNamingItselfWithoutKeysFails() async throws {
        let home = try AWSAccHome(config: "[profile selfish]\nrole_arn = \(AWSAcc.roleArn)\nsource_profile = selfish\n")
        defer { home.remove() }
        let http = AWSAccHTTP(), runner = AWSAccRunner()
        let error = await AWSAcc.failure { try await AWSAcc.resolver(home, runner: runner, http: http).resolve(profile: "selfish") }
        #expect(error is AWSCredentialError)
        #expect(http.requests().isEmpty && runner.count == 0)
    }

    static let mfaMessage = "this profile needs an MFA code; use credential_process or SSO, or run your CLI to cache credentials"

    @Test func mfaIsRefusedBeforeAnythingRuns() async throws {
        let home = try AWSAccHome(config: """
            [profile mfa]
            role_arn = \(AWSAcc.roleArn)
            source_profile = proc
            mfa_serial = arn:aws:iam::123456789012:mfa/user
            [profile mfakeys]
            role_arn = \(AWSAcc.roleArn)
            source_profile = base
            mfa_serial = arn:aws:iam::123456789012:mfa/user
            [profile proc]
            credential_process = /usr/local/bin/my-creds --profile dev
            """, credentials: AWSAcc.keys("base", AWSAccKeys.credentials("BASE")))
        defer { home.remove() }
        let clock = AWSAccClock(), runner = AWSAccRunner.issuing("PROC"), http = AWSAccHTTP()
        http.on(AWSAccSTS.host("us-east-1"), AWSAccSTS.issuing("ROLE", clock: clock))
        let resolver = AWSAcc.resolver(home, runner: runner, http: http, clock: clock)
        for profile in ["mfa", "mfakeys"] {
            let error = await AWSAcc.failure { try await resolver.resolve(profile: profile) }
            #expect(error is AWSCredentialError)
            #expect(AWSAcc.message(error).contains(Self.mfaMessage), "\(AWSAcc.message(error))")
            #expect(!AWSAcc.message(error, chinese: true).isEmpty)
            let status = resolver.status(profile: profile)
            #expect(!status.isReady)
            #expect(status.line(chinese: false, now: clock.now, timeZone: AWSAcc.losAngeles).contains(Self.mfaMessage))
        }
        #expect(runner.count == 0 && http.requests().isEmpty, "refused before the program or STS")
    }
}

// MARK: - SSO

@Suite(.timeLimit(.minutes(1)))
struct AWSCredentialsAcceptanceSSOTests {
    static let expiredMessage = "Your SSO sign-in for profile sso has expired. Run `aws sso login --profile sso` in Terminal"

    @Test func anExpiredSignInSaysWhatToRun() async throws {
        let home = try AWSAccHome(config: AWSAccSSO.config)
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(-60))
        http.on(AWSAccSSO.host("us-east-1"), AWSAccSSO.issuing("SSO", clock: clock))
        let resolver = AWSAcc.resolver(home, http: http, clock: clock)
        let error = try #require(await AWSAcc.failure { try await resolver.resolve(profile: "sso") } as? AWSCredentialError)
        #expect(error.message(chinese: false) == Self.expiredMessage)
        #expect(error.fixCommand == "aws sso login --profile sso")
        #expect(error.shortMessage(chinese: false).contains("aws sso login --profile sso"))
        #expect(error.message(chinese: true).contains("aws sso login --profile sso"))
        #expect(http.requests().isEmpty, "no sign-in to try with")
        let status = resolver.status(profile: "sso")
        #expect(!status.isReady)
        #expect(status.fixCommand == "aws sso login --profile sso")
        #expect(status.line(chinese: false, now: clock.now, timeZone: AWSAcc.losAngeles).contains("aws sso login --profile sso"))
    }

    @Test func noSignInCachedSaysWhatToRun() async throws {
        let home = try AWSAccHome(config: AWSAccSSO.config)
        defer { home.remove() }
        let http = AWSAccHTTP()
        let resolver = AWSAcc.resolver(home, http: http)
        let error = try #require(await AWSAcc.failure { try await resolver.resolve(profile: "sso") } as? AWSCredentialError)
        #expect(error.fixCommand == "aws sso login --profile sso")
        #expect(error.message(chinese: false).contains("aws sso login --profile sso"))
        #expect(http.requests().isEmpty)
        #expect(resolver.status(profile: "sso").fixCommand == "aws sso login --profile sso")
    }

    @Test func aPortal401MeansTheSignInExpired() async throws {
        let home = try AWSAccHome(config: AWSAccSSO.config)
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(3600))
        http.on(AWSAccSSO.host("us-east-1")) { _, _ in
            .init(status: 401, body: #"{"message":"Session token not found or invalid"}"#,
                  headers: ["x-amzn-ErrorType": "UnauthorizedException:http://internal.amazon.com/coral/com.amazonaws.switchboard.portal/"])
        }
        let error = try #require(await AWSAcc.failure { try await AWSAcc.resolver(home, http: http, clock: clock).resolve(profile: "sso") }
            as? AWSCredentialError)
        #expect(error.message(chinese: false) == Self.expiredMessage)
        #expect(error.fixCommand == "aws sso login --profile sso")
    }

    @Test func otherPortalErrorsNeverShowTheToken() async throws {
        let home = try AWSAccHome(config: AWSAccSSO.config)
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(3600))
        http.on(AWSAccSSO.host("us-east-1")) { _, _ in
            .init(status: 403, body: #"{"message":"No access"}"#,
                  headers: ["x-amzn-ErrorType": "ForbiddenException:http://internal.amazon.com/coral/com.amazonaws.switchboard.portal/"])
        }
        let error = await AWSAcc.failure { try await AWSAcc.resolver(home, http: http, clock: clock).resolve(profile: "sso") }
        #expect(error is AWSCredentialError)
        #expect(AWSAccKeys.hidesSecrets(AWSAcc.message(error)) && AWSAccKeys.hidesSecrets(AWSAcc.message(error, chinese: true)))
    }

    @Test func aRoleWhoseSourceSignInExpiredNamesTheSSOProfile() async throws {
        let home = try AWSAccHome(config: AWSAccSSO.config + "[profile role]\nrole_arn = \(AWSAcc.roleArn)\nsource_profile = sso\n")
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(-60))
        let resolver = AWSAcc.resolver(home, http: http, clock: clock)
        let error = try #require(await AWSAcc.failure { try await resolver.resolve(profile: "role") } as? AWSCredentialError)
        #expect(error.fixCommand == "aws sso login --profile sso")
        #expect(error.message(chinese: false) == Self.expiredMessage)
        #expect(resolver.status(profile: "role").fixCommand == "aws sso login --profile sso")
        #expect(http.requests().isEmpty)
    }

    @Test func theSSOCacheIsOnlyRead() async throws {
        let home = try AWSAccHome(config: AWSAccSSO.config)
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(3600))
        http.on(AWSAccSSO.host("us-east-1"), AWSAccSSO.issuing("SSO", clock: clock))
        let before = home.snapshot()
        let resolver = AWSAcc.resolver(home, http: http, clock: clock)
        _ = try await resolver.resolve(profile: "sso")
        clock.advance(56 * 60)
        _ = try await resolver.resolve(profile: "sso")
        clock.advance(4 * 3600)  // the sign-in expired
        _ = await AWSAcc.failure { try await resolver.resolve(profile: "sso") }
        _ = resolver.status(profile: "sso")
        #expect(home.snapshot() == before)
    }
}

// MARK: - credential_process failures

@Suite(.timeLimit(.minutes(1)))
struct AWSCredentialsAcceptanceProcessErrorTests {
    static let command = "/usr/local/bin/my-creds --profile dev --token-file hunter2-ARG"

    func resolve(stdout: String, stderr: String = "", status: Int32 = 0) async throws -> Error? {
        let home = try AWSAccHome(config: "[profile dev]\ncredential_process = \(Self.command)\n")
        defer { home.remove() }
        let runner = AWSAccRunner { _, _ in AWSProcessResult(status: status, standardOutput: Data(stdout.utf8), standardError: Data(stderr.utf8)) }
        return await AWSAcc.failure { try await AWSAcc.resolver(home, runner: runner).resolve(profile: "dev") }
    }

    func expectShown(_ error: Error?, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(error is AWSCredentialError, sourceLocation: sourceLocation)
        for chinese in [false, true] {
            let message = AWSAcc.message(error, chinese: chinese)
            #expect(message.contains("my-creds"), "names the program: \(message)", sourceLocation: sourceLocation)
            #expect(!message.contains("hunter2-ARG") && !message.contains("--token-file"), "never its arguments: \(message)",
                    sourceLocation: sourceLocation)
            #expect(AWSAccKeys.hidesSecrets(message), "never a secret", sourceLocation: sourceLocation)
            if let error = error as? AWSCredentialError {
                #expect(AWSAccKeys.hidesSecrets(error.shortMessage(chinese: chinese)), sourceLocation: sourceLocation)
            }
        }
    }

    @Test func aNonZeroExitShowsTheLastLinesOfStderr() async throws {
        let lines = ["first-line-marker"] + (1...10).map { "working on step \($0)" } + ["final-line-marker: session expired, sign in again"]
        let error = try await resolve(stdout: "", stderr: lines.joined(separator: "\n") + "\n", status: 3)
        expectShown(error)
        let message = AWSAcc.message(error)
        #expect(message.contains("final-line-marker: session expired, sign in again"), "\(message)")
        #expect(!message.contains("first-line-marker"), "the last lines only: \(message)")
    }

    @Test func aNonZeroExitNeverShowsWhatWasPrintedOnStdout() async throws {
        let keys = AWSAccKeys.credentials("LEAK")
        let error = try await resolve(stdout: String(decoding: AWSAcc.processJSON(keys, expiration: nil), as: UTF8.self), stderr: "failed", status: 1)
        expectShown(error)
    }

    @Test func secretsInStderrAreNotShown() async throws {
        let keys = AWSAccKeys.credentials("STDERR")
        let error = try await resolve(stdout: "", stderr: "bad key \(keys.secretAccessKey)\ntoken \(keys.sessionToken!)\n", status: 2)
        expectShown(error)
    }

    // {ID} and {SECRET} are filled in at run time (the arguments are printed with the results).
    @Test(arguments: [
        "this is not JSON",
        "",
        "[]",
        #"{"Version": 1, "AccessKeyId": "{ID}", "SecretAccessKey": "{SECRET}""#,
        #"{"Version": 2, "AccessKeyId": "{ID}", "SecretAccessKey": "{SECRET}"}"#,
        #"{"Version": "1", "AccessKeyId": "{ID}", "SecretAccessKey": "{SECRET}"}"#,
        #"{"AccessKeyId": "{ID}", "SecretAccessKey": "{SECRET}"}"#,
        #"{"Version": 1, "SecretAccessKey": "{SECRET}"}"#,
        #"{"Version": 1, "AccessKeyId": "{ID}"}"#,
        #"{"Version": 1, "AccessKeyId": "{ID}", "SecretAccessKey": "{SECRET}", "Expiration": "next tuesday"}"#,
    ])
    func malformedOutputIsAnErrorThatNeverQuotesIt(template: String) async throws {
        let id = AWSAccKeys.id + "LEAK"
        let stdout = template.replacingOccurrences(of: "{ID}", with: id).replacingOccurrences(of: "{SECRET}", with: AWSAccKeys.secret + "LEAK")
        let error = try await resolve(stdout: stdout, stderr: "warning: using cached session\n")
        expectShown(error)
        #expect(!AWSAcc.message(error).contains(id))
        #expect(AWSAcc.message(error).contains("warning: using cached session"), "with its stderr: \(AWSAcc.message(error))")
    }

    @Test(arguments: [
        "this is not JSON",
        #"{"Version": 2, "AccessKeyId": "AKID", "SecretAccessKey": "s"}"#,
        #"{"Version": 1, "AccessKeyId": "AKID"}"#,
        #"{"Version": 1, "SecretAccessKey": "s"}"#,
        #"{"AccessKeyId": "AKID", "SecretAccessKey": "s"}"#,
    ])
    func theParserRefusesWhatTheCLIRefuses(stdout: String) {
        #expect(throws: (any Error).self) { try AWSCredentialProcess.parse(Data(stdout.utf8)) }
    }

    @Test func theParserReadsTheCLIFormat() throws {
        let keys = AWSAccKeys.credentials("PARSE")
        let parsed = try AWSCredentialProcess.parse(AWSAcc.processJSON(keys, expiration: Date(timeIntervalSince1970: 1_792_180_800)))
        #expect(parsed.credentials == keys)
        #expect(parsed.expiration == Date(timeIntervalSince1970: 1_792_180_800))
        let noToken = try AWSCredentialProcess.parse(AWSAcc.processJSON(AWSAccKeys.credentials("PARSE", token: false), expiration: nil))
        #expect(noToken.credentials.sessionToken == nil && noToken.expiration == nil)
    }

    @Test func aRealProgramThatFailsShowsItsStderrWithoutItsArguments() async throws {
        let home = try AWSAccHome()
        defer { home.remove() }
        let program = try home.script("my-creds", "echo 'starting' >&2\necho 'denied: your session is over' >&2\nexit 3")
        try home.write(config: "[profile dev]\ncredential_process = \(program.path) --profile dev --token-file hunter2-ARG\n", credentials: "")
        let error = await AWSAcc.failure { try await AWSAcc.resolver(home, runner: nil).resolve(profile: "dev") }
        expectShown(error)
        #expect(AWSAcc.message(error).contains("denied: your session is over"), "\(AWSAcc.message(error))")
    }

    @Test func aRealProgramThatHangsIsStoppedAfterTheTimeout() async throws {
        let home = try AWSAccHome()
        defer { home.remove() }
        let program = try home.script("my-creds", "sleep 30")
        try home.write(config: "[profile dev]\ncredential_process = \(program.path) --profile dev --token-file hunter2-ARG\n", credentials: "")
        let started = Date()
        let error = await AWSAcc.failure { try await AWSAcc.resolver(home, runner: nil, processTimeout: 1).resolve(profile: "dev") }
        #expect(Date().timeIntervalSince(started) < 15, "stopped long before the program's 30 s")
        expectShown(error)
    }

    @Test func aProgramThatIsntThereNamesTheProgram() async throws {
        let home = try AWSAccHome(config: "[profile dev]\ncredential_process = my-creds-not-installed --profile dev --token-file hunter2-ARG\n")
        defer { home.remove() }
        let error = await AWSAcc.failure { try await AWSAcc.resolver(home, runner: nil).resolve(profile: "dev") }
        #expect(error is AWSCredentialError)
        let message = AWSAcc.message(error)
        #expect(message.contains("my-creds-not-installed") && !message.contains("hunter2-ARG"), "\(message)")
    }
}

// MARK: - STS answers, endpoints and the signature

@Suite(.timeLimit(.minutes(1)))
struct AWSCredentialsAcceptanceSTSTests {
    @Test func stsErrorResponsesAreRead() {
        let parsed = AWSSTS.parseError(Data(AWSAccSTS.error("AccessDenied", AWSAccSTS.denied).utf8))
        #expect(parsed.code == "AccessDenied")
        #expect(parsed.message == AWSAccSTS.denied)
        let expired = AWSSTS.parseError(Data(AWSAccSTS.error("ExpiredToken", AWSAccSTS.expired).utf8))
        #expect(expired.code == "ExpiredToken" && expired.message == AWSAccSTS.expired)
    }

    @Test func theAssumeRoleResponseIsRead() throws {
        let keys = AWSAccKeys.credentials("DOC")
        let expiration = Date(timeIntervalSince1970: 1_573_306_481)  // 2019-11-09T13:34:41Z, as in the API reference
        let parsed = try #require(AWSSTS.parseAssumeRole(Data(AWSAccSTS.response(keys, expiration: expiration).utf8)))
        #expect(parsed.credentials == keys)
        #expect(parsed.expiration == expiration)
    }

    @Test func anSTSRefusalShowsTheCodeAndMessage() async throws {
        let home = try AWSAccHome(config: "[profile role]\nrole_arn = \(AWSAcc.roleArn)\nsource_profile = base\n",
                                  credentials: AWSAcc.keys("base", AWSAccKeys.credentials("BASE")))
        defer { home.remove() }
        let http = AWSAccHTTP()
        http.on(AWSAccSTS.host("us-east-1")) { _, _ in .init(status: 403, body: AWSAccSTS.error("AccessDenied", AWSAccSTS.denied)) }
        let error = await AWSAcc.failure { try await AWSAcc.resolver(home, http: http).resolve(profile: "role") }
        #expect(error is AWSCredentialError)
        let message = AWSAcc.message(error)
        #expect(message.contains("AccessDenied") && message.contains("is not authorized to perform: sts:AssumeRole"), "\(message)")
        #expect(AWSAccKeys.hidesSecrets(message))
    }

    @Test func anUnreadableSTSAnswerIsAnError() async throws {
        let home = try AWSAccHome(config: "[profile role]\nrole_arn = \(AWSAcc.roleArn)\nsource_profile = base\n",
                                  credentials: AWSAcc.keys("base", AWSAccKeys.credentials("BASE")))
        defer { home.remove() }
        let http = AWSAccHTTP()
        http.on(AWSAccSTS.host("us-east-1")) { _, index in
            index == 0 ? .init(status: 503, body: "<html><body>Service Unavailable</body></html>") : .init(status: 200, body: "<AssumeRoleResponse/>")
        }
        let resolver = AWSAcc.resolver(home, http: http)
        #expect(await AWSAcc.failure { try await resolver.resolve(profile: "role") } is AWSCredentialError)
        #expect(await AWSAcc.failure { try await resolver.resolve(profile: "role") } is AWSCredentialError)
    }

    @Test func stsIsAskedInTheRoleProfilesRegion() async throws {
        let home = try AWSAccHome(config: """
            [profile role]
            role_arn = \(AWSAcc.roleArn)
            source_profile = base
            region = eu-west-1
            [profile noregion]
            role_arn = \(AWSAcc.roleArn)
            source_profile = base
            [profile base]
            region = ap-southeast-2
            """, credentials: AWSAcc.keys("base", AWSAccKeys.credentials("BASE")))
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        for region in ["eu-west-1", "us-east-1", "ap-southeast-2"] { http.on(AWSAccSTS.host(region), AWSAccSTS.issuing("ROLE", clock: clock)) }
        let resolver = AWSAcc.resolver(home, http: http, clock: clock)
        _ = try await resolver.resolve(profile: "role")
        _ = try await resolver.resolve(profile: "noregion")
        let requests = http.requests()
        try #require(requests.count == 2)
        #expect(requests[0].url?.host == "sts.eu-west-1.amazonaws.com")
        #expect(AWSAcc.authorization(requests[0])?.scope.hasSuffix("/eu-west-1/sts/aws4_request") == true)
        #expect(requests[1].url?.host == "sts.us-east-1.amazonaws.com", "no region of its own: us-east-1, not the source's")
        #expect(AWSAcc.authorization(requests[1])?.scope.hasSuffix("/us-east-1/sts/aws4_request") == true)
        #expect(try AWSSTS.endpoint(region: "eu-west-1") == URL(string: "https://sts.eu-west-1.amazonaws.com/"))
    }

    @Test(arguments: ["x@evil.example#", "us-east-1.evil.example/", "us east 1"])
    func aRegionThatIsntOneNeverSendsTheKeysElsewhere(region: String) async throws {
        let home = try AWSAccHome(config: "[profile role]\nrole_arn = \(AWSAcc.roleArn)\nsource_profile = base\nregion = \(region)\n",
                                  credentials: AWSAcc.keys("base", AWSAccKeys.credentials("BASE")))
        defer { home.remove() }
        let http = AWSAccHTTP()
        let error = await AWSAcc.failure { try await AWSAcc.resolver(home, http: http).resolve(profile: "role") }
        #expect(error != nil)
        for request in http.requests() {
            let host = request.url?.host ?? ""
            #expect(host.hasPrefix("sts.") && host.hasSuffix(".amazonaws.com") && !host.contains("evil"), "sent to \(host)")
        }
    }

    // The signature, checked against AWS's published SigV4 test vectors and computed here from what is sent.

    static let vectorDate = Date(timeIntervalSince1970: 1_440_938_160)  // 20150830T123600Z

    @Test func theIndependentSignerMatchesAWSsPublishedVectors() {
        // aws-sig-v4-test-suite: get-vanilla.
        let vanilla = AWSAccSigV4.canonicalRequest(method: "GET", path: "/", query: "",
                                                   headers: ["Host": "example.amazonaws.com", "X-Amz-Date": "20150830T123600Z"],
                                                   signed: ["host", "x-amz-date"], body: Data())
        #expect(AWSAccSigV4.signature(secret: AWSAccKeys.vectorSecret, amzDate: "20150830T123600Z", region: "us-east-1", service: "service",
                                      canonicalRequest: vanilla) == "5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31")
        // aws-sig-v4-test-suite: post-x-www-form-urlencoded.
        let form = AWSAccSigV4.canonicalRequest(method: "POST", path: "/", query: "",
                                                headers: ["Content-Type": "application/x-www-form-urlencoded", "Host": "example.amazonaws.com",
                                                          "X-Amz-Date": "20150830T123600Z"],
                                                signed: ["content-type", "host", "x-amz-date"], body: Data("Param1=value1".utf8))
        #expect(AWSAccSigV4.signature(secret: AWSAccKeys.vectorSecret, amzDate: "20150830T123600Z", region: "us-east-1", service: "service",
                                      canonicalRequest: form) == "ff11897932ad3f4e8b18135d722051e5ac45fc38421b1da7b9d196a0fe09473a")
        // The SigV4 guide's IAM ListUsers example and its signing key example.
        let listUsers = AWSAccSigV4.canonicalRequest(
            method: "GET", path: "/", query: "Action=ListUsers&Version=2010-05-08",
            headers: ["Content-Type": "application/x-www-form-urlencoded; charset=utf-8", "Host": "iam.amazonaws.com", "X-Amz-Date": "20150830T123600Z"],
            signed: ["content-type", "host", "x-amz-date"], body: Data())
        #expect(AWSAccSigV4.hash(Data(listUsers.utf8)) == "f536975d06c0309214f805bb90ccff089219ecd68b2577efef23edd43b7e1a59")
        #expect(AWSAccSigV4.signature(secret: AWSAccKeys.vectorSecret, amzDate: "20150830T123600Z", region: "us-east-1", service: "iam",
                                      canonicalRequest: listUsers) == "5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7")
        #expect(AWSAccSigV4.hex(AWSAccSigV4.signingKey(secret: AWSAccKeys.vectorSecret, date: "20120215", region: "us-east-1", service: "iam"))
            == "f4780e2d9f65fa895f9c67b32ce1baf0b0d8a43505a000a1a9e090d414db404d")
    }

    @Test func theSignerSTSUsesMatchesAWSsPublishedVectors() {
        let keys = AWSCredentials(accessKeyId: AWSAccKeys.id, secretAccessKey: AWSAccKeys.vectorSecret)
        var vanilla = URLRequest(url: URL(string: "https://example.amazonaws.com/")!)
        vanilla.httpMethod = "GET"
        SigV4Signer(credentials: keys, region: "us-east-1", service: "service").sign(&vanilla, body: Data(), date: Self.vectorDate)
        #expect(vanilla.value(forHTTPHeaderField: "Authorization")
            == "AWS4-HMAC-SHA256 Credential=\(AWSAccKeys.id)/20150830/us-east-1/service/aws4_request, SignedHeaders=host;x-amz-date, Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31")
        var form = URLRequest(url: URL(string: "https://example.amazonaws.com/")!)
        form.httpMethod = "POST"
        form.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        SigV4Signer(credentials: keys, region: "us-east-1", service: "service").sign(&form, body: Data("Param1=value1".utf8), date: Self.vectorDate)
        #expect(form.value(forHTTPHeaderField: "Authorization")
            == "AWS4-HMAC-SHA256 Credential=\(AWSAccKeys.id)/20150830/us-east-1/service/aws4_request, SignedHeaders=content-type;host;x-amz-date, Signature=ff11897932ad3f4e8b18135d722051e5ac45fc38421b1da7b9d196a0fe09473a")
    }

    @Test func theAssumeRoleRequestSentCarriesTheSignatureAWSExpects() async throws {
        let base = AWSCredentials(accessKeyId: AWSAccKeys.id, secretAccessKey: AWSAccKeys.secret, sessionToken: "FwoGZXIvYXdzEXAMPLE" + "TOKENBASE")
        let home = try AWSAccHome(config: """
            [profile role]
            role_arn = \(AWSAcc.roleArn)
            source_profile = base
            region = eu-west-1
            role_session_name = typing-session
            external_id = ext-1234
            """, credentials: AWSAcc.keys("base", base))
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        http.on(AWSAccSTS.host("eu-west-1"), AWSAccSTS.issuing("ROLE", clock: clock))
        _ = try await AWSAcc.resolver(home, http: http, clock: clock).resolve(profile: "role")
        let request = try #require(http.requests().first)
        let auth = try #require(AWSAcc.authorization(request))
        #expect(request.value(forHTTPHeaderField: "X-Amz-Date") == "20261016T190000Z", "the injected clock's time")
        #expect(auth.keyId == AWSAccKeys.id)
        #expect(auth.scope == "20261016/eu-west-1/sts/aws4_request")
        #expect(Set(auth.signedHeaders).isSuperset(of: ["content-type", "host", "x-amz-date", "x-amz-security-token"]), "\(auth.signedHeaders)")
        #expect(auth.signedHeaders == auth.signedHeaders.sorted())
        let expected = AWSAccSigV4.expectedSignature(request, secret: AWSAccKeys.secret, region: "eu-west-1", service: "sts")
        #expect(auth.signature == expected)
    }

    @Test func anAssumeRoleRequestOnAWSsVectorDateAndKeys() throws {
        let keys = AWSCredentials(accessKeyId: AWSAccKeys.id, secretAccessKey: AWSAccKeys.vectorSecret)
        let request = try AWSSTS.assumeRoleRequest(roleArn: "arn:aws:iam::123456789012:role/demo", sessionName: "TestAR", region: "us-east-1",
                                                   credentials: keys, date: Self.vectorDate)
        #expect(request.url?.absoluteString == "https://sts.us-east-1.amazonaws.com/")
        #expect(AWSAcc.form(request) == ["Action": "AssumeRole", "Version": "2011-06-15", "RoleArn": "arn:aws:iam::123456789012:role/demo",
                                         "RoleSessionName": "TestAR"])
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("RoleArn=arn%3Aaws%3Aiam%3A%3A123456789012%3Arole%2Fdemo"),
                "form-encoded")
        let auth = try #require(AWSAcc.authorization(request))
        #expect(auth.scope == "20150830/us-east-1/sts/aws4_request")
        #expect(auth.signature == AWSAccSigV4.expectedSignature(request, secret: AWSAccKeys.vectorSecret, region: "us-east-1", service: "sts"))
        #expect(request.value(forHTTPHeaderField: "X-Amz-Security-Token") == nil)
    }
}

// MARK: - Settings, @doctor and @config: what is shown, and what never runs

@Suite(.timeLimit(.minutes(1)))
struct AWSCredentialsAcceptanceStatusTests {
    func home() throws -> AWSAccHome {
        let home = try AWSAccHome()
        let program = try home.script("acc-creds", "touch \"$HOME/ran-credential-process\"\nexit 1")
        try home.write(config: AWSAccSSO.config + """
            [profile keys]
            region = us-west-2
            [profile proc]
            credential_process = \(program.path) --profile dev
            region = eu-west-1
            [profile base]
            region = us-east-1
            [profile role]
            role_arn = \(AWSAcc.roleArn)
            source_profile = base
            """, credentials: AWSAcc.keys("keys", AWSAccKeys.credentials("KEYS")) + AWSAcc.keys("base", AWSAccKeys.credentials("BASE")))
        return home
    }

    @Test func theStatusLinesInBothLanguages() async throws {
        let home = try home()
        defer { home.remove() }
        let clock = AWSAccClock(), http = AWSAccHTTP()
        let runner = AWSAccRunner.issuing("PROC", clock: clock, lifetime: 3600)                    // 13:00 in Los Angeles
        try home.signIn("my-sso", expiresAt: Date(timeIntervalSince1970: 1_792_189_800))             // 15:30
        http.on(AWSAccSTS.host("us-east-1"), AWSAccSTS.issuing("ROLE", clock: clock, lifetime: 5400))  // 13:30
        http.on(AWSAccSSO.host("us-east-1"), AWSAccSSO.issuing("SSO", clock: clock, lifetime: 7200))   // 14:00
        let resolver = AWSAcc.resolver(home, runner: runner, http: http, clock: clock)
        func line(_ profile: String, chinese: Bool = false) -> String {
            resolver.status(profile: profile).line(chinese: chinese, now: clock.now, timeZone: AWSAcc.losAngeles)
        }
        #expect(line("keys").hasPrefix("Static keys"), "\(line("keys"))")
        #expect(line("proc").hasPrefix("credential_process"), "\(line("proc"))")
        #expect(line("role").hasPrefix("Role via base"), "\(line("role"))")
        #expect(line("sso").hasPrefix("SSO (signed in until 15:30)"), "\(line("sso"))")
        #expect(resolver.status(profile: "keys").isReady && resolver.status(profile: "sso").isReady)
        for profile in ["proc", "role", "sso"] { _ = try await resolver.resolve(profile: profile) }
        #expect(line("proc").hasPrefix("credential_process") && line("proc").contains("13:00"), "\(line("proc"))")
        #expect(line("role").hasPrefix("Role via base") && line("role").contains("13:30"), "\(line("role"))")
        #expect(line("sso").hasPrefix("SSO (signed in until 15:30)") && line("sso").contains("14:00"), "\(line("sso"))")
        for (profile, time) in [("keys", nil), ("proc", "13:00"), ("role", "13:30"), ("sso", "14:00")] as [(String, String?)] {
            let english = line(profile), chinese = line(profile, chinese: true)
            #expect(chinese != english && AWSAcc.hasCJK(chinese), "\(chinese)")
            if let time { #expect(chinese.contains(time), "\(chinese)") }
            #expect(AWSAccKeys.hidesSecrets(english) && AWSAccKeys.hidesSecrets(chinese))
            #expect(!english.contains(AWSAccKeys.id + "KEYS") && !chinese.contains(AWSAccKeys.id + "KEYS"))
        }
        #expect(line("role", chinese: true).contains("base"))
        #expect(line("sso", chinese: true).contains("SSO") && line("sso", chinese: true).contains("15:30"))
    }

    @Test func theProfilePickerListsEveryProfileWithItsTypeAndNothingRuns() async throws {
        let home = try home()
        defer { home.remove() }
        let clock = AWSAccClock()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(3600))
        // The real runner: had anything run the program, it would have left its mark.
        let http = AWSAccHTTP()
        let resolver = AWSAcc.resolver(home, runner: nil, http: http, clock: clock)
        let profiles = Dictionary(uniqueKeysWithValues: resolver.profiles().map { ($0.name, $0) })
        #expect(Set(profiles.keys) == ["keys", "proc", "base", "role", "sso"])
        #expect(profiles["keys"]?.kind == .staticKeys && profiles["keys"]?.region == "us-west-2")
        #expect(profiles["proc"]?.kind == .credentialProcess && profiles["proc"]?.region == "eu-west-1")
        #expect(profiles["role"]?.kind == .role(source: "base"))
        #expect(profiles["sso"]?.kind == .sso && profiles["sso"]?.region == "us-west-2")
        for name in profiles.keys { _ = resolver.status(profile: name) }
        #expect(!FileManager.default.fileExists(atPath: home.root.appendingPathComponent("ran-credential-process").path))
        #expect(http.requests().isEmpty)
        #expect(resolver.fetchCount(profile: "proc") == 0 && resolver.fetchCount(profile: "role") == 0 && resolver.fetchCount(profile: "sso") == 0)
    }

    @Test func configsProfileListingGivesNamesAndRegionsOnlyAndNeverRunsAnything() throws {
        let home = try home()
        defer { home.remove() }
        let environment = ["AWS_CONFIG_FILE": home.root.appendingPathComponent(".aws/config").path,
                           "AWS_SHARED_CREDENTIALS_FILE": home.root.appendingPathComponent(".aws/credentials").path]
        let before = home.snapshot()
        let listed = AIConfig.awsProfiles(environment: environment)
        #expect(listed == [AIConfig.AWSProfile(name: "base", region: "us-east-1"), AIConfig.AWSProfile(name: "keys", region: "us-west-2"),
                           AIConfig.AWSProfile(name: "proc", region: "eu-west-1"), AIConfig.AWSProfile(name: "role", region: nil),
                           AIConfig.AWSProfile(name: "sso", region: "us-west-2")])
        #expect(!FileManager.default.fileExists(atPath: home.root.appendingPathComponent("ran-credential-process").path))
        #expect(home.snapshot() == before)
    }

    @Test func doctorsFixForAnExpiredSignInIsTheCommand() async throws {
        let home = try AWSAccHome(config: AWSAccSSO.config)
        defer { home.remove() }
        let clock = AWSAccClock()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(-60))
        let status = AWSAcc.resolver(home, clock: clock).status(profile: "sso")
        #expect(status.kind == .sso)
        #expect(status.fixCommand == "aws sso login --profile sso")
        #expect(status.problem?.message(chinese: false) == AWSCredentialsAcceptanceSSOTests.expiredMessage)
    }
}

// MARK: - Never on disk

@Suite(.timeLimit(.minutes(1)))
struct AWSCredentialsAcceptanceDiskTests {
    @Test func credentialsAreNeverWrittenToDisk() async throws {
        let home = try AWSAccHome()
        defer { home.remove() }
        let keys = AWSAccKeys.credentials("DISK")
        let program = try home.script("my-creds", """
            printf '{"Version": 1, "AccessKeyId": "%s", "SecretAccessKey": "%s", "SessionToken": "%s", "Expiration": "%s"}' \
              "\(keys.accessKeyId)" "\(keys.secretAccessKey)" "\(keys.sessionToken!)" "\(AWSAcc.iso(AWSAccClock.start.addingTimeInterval(3600)))"
            """)
        try home.write(config: AWSAccSSO.config + """
            [profile proc]
            credential_process = \(program.path) --profile dev
            [profile role]
            role_arn = \(AWSAcc.roleArn)
            source_profile = proc
            [profile chained]
            role_arn = arn:aws:iam::123456789012:role/chained
            source_profile = sso
            """, credentials: AWSAcc.keys("keys", AWSAccKeys.credentials("KEYS")))
        let clock = AWSAccClock(), http = AWSAccHTTP()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(8 * 3600))
        http.on(AWSAccSTS.host("us-east-1"), AWSAccSTS.issuing("ROLE", clock: clock))
        http.on(AWSAccSSO.host("us-east-1"), AWSAccSSO.issuing("SSO", clock: clock))
        let before = home.snapshot()
        let resolver = AWSAcc.resolver(home, runner: nil, http: http, clock: clock)
        for profile in ["keys", "proc", "role", "sso", "chained"] {
            _ = try await resolver.resolve(profile: profile)
            _ = try await resolver.resolve(profile: profile, forceRefresh: true)
        }
        clock.advance(52 * 60)
        for profile in ["proc", "role", "sso", "chained"] { _ = try await resolver.resolve(profile: profile) }
        await resolver.waitForRefreshes()
        _ = try await resolver.refresh(profile: "role", replacing: nil)
        _ = resolver.profiles()
        for profile in ["keys", "proc", "role", "sso", "chained"] { _ = resolver.status(profile: profile).line(chinese: false) }
        #expect(home.snapshot() == before, "HOME is as the test left it")
    }
}

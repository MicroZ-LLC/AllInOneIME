import Foundation
import os
import Testing
@testable import AllInOneIMECore

// MARK: - Helpers (a temp HOME with the AWS files, a clock, canned STS and SSO answers)

/// A temporary HOME with `.aws/config` and `.aws/credentials`, never the user's.
struct AWSCTHome {
    let root: URL

    init(config: String = "", credentials: String = "") throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aws-creds-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".aws/sso/cache"), withIntermediateDirectories: true)
        try write(config: config, credentials: credentials)
    }

    func write(config: String, credentials: String) throws {
        try Data(config.utf8).write(to: root.appendingPathComponent(".aws/config"))
        try Data(credentials.utf8).write(to: root.appendingPathComponent(".aws/credentials"))
    }

    var files: AWSFileLocations { AWSFileLocations(environment: ["HOME": root.path]) }

    /// An SSO sign-in as the AWS CLI caches it.
    func signIn(_ key: String, expiresAt: Date, token: String = "sso-access-token-EXAMPLE") throws {
        let formatter = ISO8601DateFormatter()
        let json = """
            {"startUrl": "https://my-sso-portal.awsapps.com/start", "region": "us-east-1", "accessToken": "\(token)",
             "expiresAt": "\(formatter.string(from: expiresAt))", "clientId": "client-EXAMPLE", "clientSecret": "secret-EXAMPLE",
             "refreshToken": "refresh-EXAMPLE"}
            """
        try Data(json.utf8).write(to: AWSSSO.cacheFile(key: key, in: files.ssoCache))
    }

    /// An executable script in the temp HOME.
    func script(_ name: String, _ body: String) throws -> String {
        let url = root.appendingPathComponent(name)
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

final class AWSCTClock: Sendable {
    private let time: OSAllocatedUnfairLock<Date>
    init(_ start: Date = Date(timeIntervalSince1970: 1_792_173_600)) { time = OSAllocatedUnfairLock(initialState: start) }  // 2026-10-16 18:00 UTC
    var now: Date { time.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { time.withLock { $0 = $0.addingTimeInterval(seconds) } }
    var read: @Sendable () -> Date { { [self] in now } }
}

/// Canned HTTP answers by host, in order (the last one repeats), and every request seen.
final class AWSCTHTTP: Sendable {
    struct Answer: Sendable {
        var status: Int
        var body: String
        var headers: [String: String] = [:]
        var delay: TimeInterval = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: (answers: [String: [Answer]](), requests: [URLRequest]()))

    func on(_ host: String, _ answers: Answer...) { state.withLock { $0.answers[host, default: []] += answers } }

    var requests: [URLRequest] { state.withLock { $0.requests } }
    func requests(_ host: String) -> [URLRequest] { requests.filter { $0.url?.host == host } }

    var send: AWSCredentialContext.Send {
        { [self] request in
            let answer = state.withLock { state -> Answer? in
                state.requests.append(request)
                let host = request.url?.host ?? ""
                guard var queue = state.answers[host], let first = queue.first else { return nil }
                if queue.count > 1 { queue.removeFirst() }
                state.answers[host] = queue
                return first
            }
            guard let answer else { throw URLError(.cannotFindHost) }
            if answer.delay > 0 { try await Task.sleep(nanoseconds: UInt64(answer.delay * 1e9)) }
            let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)!
            return (Data(answer.body.utf8), response)
        }
    }
}

/// A stand-in for `credential_process`: what it was asked to run, and what it answers.
final class AWSCTRunner: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (runs: [AWSProcessRequest](), outputs: [AWSProcessResult](), held: false))
    let delay: TimeInterval

    init(_ outputs: [AWSProcessResult], delay: TimeInterval = 0) {
        self.delay = delay
        state.withLock { $0.outputs = outputs }
    }

    var runs: [AWSProcessRequest] { state.withLock { $0.runs } }

    /// Runs from now on don't answer until `release`.
    func hold() { state.withLock { $0.held = true } }
    func release() { state.withLock { $0.held = false } }

    var run: AWSCredentialContext.RunProcess {
        { [self] request in
            let output = state.withLock { state -> AWSProcessResult in
                state.runs.append(request)
                return state.outputs.count > 1 ? state.outputs.removeFirst() : state.outputs[0]
            }
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
            while state.withLock({ $0.held }) { try await Task.sleep(for: .milliseconds(10)) }
            return output
        }
    }
}

enum AWSCT {
    static var iso: ISO8601DateFormatter { ISO8601DateFormatter() }

    #if os(Windows)
    /// A program every system has, as a credential_process line writes it (its shlex rules keep "/", not "\").
    static let echo = WindowsTestTools.systemProgram("where.exe").replacingOccurrences(of: "\\", with: "/")
    #else
    static let echo = "/bin/echo"
    #endif

    static func processJSON(_ id: String, expiration: Date? = nil, token: String? = "process-token") -> AWSProcessResult {
        var fields = [#""Version": 1"#, #""AccessKeyId": "\#(id)""#, #""SecretAccessKey": "process-secret-\#(id)""#]
        if let token { fields.append(#""SessionToken": "\#(token)""#) }
        if let expiration { fields.append(#""Expiration": "\#(iso.string(from: expiration))""#) }
        return AWSProcessResult(status: 0, standardOutput: Data(("{" + fields.joined(separator: ", ") + "}").utf8))
    }

    /// STS's AssumeRole answer, as in its API reference (the token wrapped over lines).
    static func assumeRoleXML(_ id: String, expiration: Date) -> String {
        """
        <AssumeRoleResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
        <AssumeRoleResult>
        <SourceIdentity>DevUser123</SourceIdentity>
          <AssumedRoleUser>
            <Arn>arn:aws:sts::123456789012:assumed-role/demo/John</Arn>
            <AssumedRoleId>ARO123EXAMPLE123:John</AssumedRoleId>
          </AssumedRoleUser>
          <Credentials>
            <AccessKeyId>\(id)</AccessKeyId>
            <SecretAccessKey>wJalrXUtnFEMI/K7MDENG/bPxRfiCYzEXAMPLEKEY</SecretAccessKey>
            <SessionToken>
             AQoDYXdzEPT//////////wEXAMPLEtc764bNrC9SAPBSM22wDOk4x4HIZ8j4FZTwdQW
             LWsKWHGBuFqwAeMicRXmxfpSPfIeoIYRqTflfKD8YUuwthAx7mSEI/qkPpKPi/kMcGd
             +scqKmlzm8FDrypNC9Yjc8fPOLn9FX9KSYvKTr4rvx3iSIlTJabIQwj2ICCR/oLxBA==
            </SessionToken>
            <Expiration>\(iso.string(from: expiration))</Expiration>
          </Credentials>
        <PackedPolicySize>8</PackedPolicySize>
        </AssumeRoleResult>
        <ResponseMetadata>
        <RequestId>c6104cbe-af31-11e0-8154-cbc7ccf896c7</RequestId>
        </ResponseMetadata>
        </AssumeRoleResponse>
        """
    }

    static func stsError(_ code: String, _ message: String) -> String {
        """
        <ErrorResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
          <Error>
            <Type>Sender</Type>
            <Code>\(code)</Code>
            <Message>\(message)</Message>
          </Error>
          <RequestId>4a5d7d2c-1e7b-4f5d-9b0a-000000000000</RequestId>
        </ErrorResponse>
        """
    }

    /// The SSO portal's GetRoleCredentials answer.
    static func ssoJSON(_ id: String, expiration: Date) -> String {
        #"{"roleCredentials": {"accessKeyId": "\#(id)", "secretAccessKey": "sso-secret", "sessionToken": "sso-session-token", "expiration": \#(Int64(expiration.timeIntervalSince1970 * 1000))}}"#
    }

    static func resolver(_ home: AWSCTHome, clock: AWSCTClock = AWSCTClock(), http: AWSCTHTTP = AWSCTHTTP(),
                         runner: AWSCTRunner? = nil, environment: [String: String] = [:]) -> AWSCredentialResolver {
        var env = environment
        env["HOME"] = home.root.path
        let nothing: AWSCredentialContext.RunProcess = { @Sendable _ in throw AWSProcessError.notFound("nothing should run") }
        return AWSCredentialResolver(context: AWSCredentialContext(environment: env, runProcess: runner?.run ?? nothing,
                                                                   send: http.send, now: clock.read))
    }

    static func header(_ request: URLRequest, _ name: String) -> String? { request.value(forHTTPHeaderField: name) }

    static func body(_ request: URLRequest) -> String { String(decoding: request.httpBody ?? Data(), as: UTF8.self) }
}

// MARK: - credential_process: the command and its output

struct AWSCredentialProcessTests {
    /// Each expectation is Python's `shlex.split` (what the AWS CLI uses) on the same text.
    @Test(arguments: [
        ("/usr/local/bin/my-creds --profile dev", ["/usr/local/bin/my-creds", "--profile", "dev"]),
        (#"a 'b c' "d \" e" f\ g"#, ["a", "b c", #"d " e"#, "f g"]),
        ("x '' y", ["x", "", "y"]),
        (#"p "a\\b\nc""#, ["p", #"a\b\nc"#]),
        ("  lead  trail  ", ["lead", "trail"]),
        (#"a"b"c"#, ["abc"]),
        ("q 'it''s'", ["q", "its"]),
        ("tab\tsep\nline", ["tab", "sep", "line"]),
        (#"keeps $HOME and ~ and *"#, ["keeps", "$HOME", "and", "~", "and", "*"]),
        ("my-creds '\u{301}abc'", ["my-creds", "\u{301}abc"]),
        ("my-creds caf\u{E9} \u{4E2D}\u{6587} \u{1F600}", ["my-creds", "caf\u{E9}", "\u{4E2D}\u{6587}", "\u{1F600}"]),
        ("my-creds \"e\u{301}\"x", ["my-creds", "e\u{301}x"]),
    ] as [(String, [String])])
    func splitsLikeTheAWSCLI(command: String, expected: [String]) throws {
        #expect(try AWSCredentialProcess.arguments(command) == expected)
    }

    @Test func refusesCommandsThatCantBeSplit() {
        #expect(throws: AWSCredentialProcess.SplitError.unclosedQuote) { try AWSCredentialProcess.arguments("my-creds 'oops") }
        #expect(throws: AWSCredentialProcess.SplitError.unclosedQuote) { try AWSCredentialProcess.arguments(#"my-creds "oops"#) }
        #expect(throws: AWSCredentialProcess.SplitError.trailingBackslash) { try AWSCredentialProcess.arguments(#"my-creds \"#) }
        #expect(throws: AWSCredentialProcess.SplitError.empty) { try AWSCredentialProcess.arguments("   ") }
    }

    @Test func parsesTheOutput() throws {
        let full = try AWSCredentialProcess.parse(Data(#"""
            {"Version": 1, "AccessKeyId": "ASIAEXAMPLE", "SecretAccessKey": "s3cr3t", "SessionToken": "tok", "Expiration": "2026-10-16T19:30:00Z"}
            """#.utf8))
        #expect(full.credentials == AWSCredentials(accessKeyId: "ASIAEXAMPLE", secretAccessKey: "s3cr3t", sessionToken: "tok"))
        #expect(full.expiration == AWSCT.iso.date(from: "2026-10-16T19:30:00Z"))
        let fractional = try AWSCredentialProcess.parse(Data(#"{"Version":1,"AccessKeyId":"A","SecretAccessKey":"S","Expiration":"2026-10-16T19:30:00.123+00:00"}"#.utf8))
        #expect(fractional.credentials.sessionToken == nil)
        #expect(abs((fractional.expiration?.timeIntervalSince1970 ?? 0) - 1_792_179_000.123) < 0.01)
        let none = try AWSCredentialProcess.parse(Data(#"{"Version":1,"AccessKeyId":"A","SecretAccessKey":"S"}"#.utf8))
        #expect(none.expiration == nil)
    }

    @Test(arguments: [
        ("", "it printed nothing"),
        ("AccessKeyId=A SecretAccessKey=super-secret-value", "it isn't a JSON object"),
        (#"["Version", 1]"#, "it isn't a JSON object"),
        (#"{"AccessKeyId":"A","SecretAccessKey":"super-secret-value"}"#, "\"Version\": 1 is missing"),
        (#"{"Version":2,"AccessKeyId":"A","SecretAccessKey":"super-secret-value"}"#, "\"Version\" isn't 1"),
        (#"{"Version":"1","AccessKeyId":"A","SecretAccessKey":"super-secret-value"}"#, "\"Version\" isn't 1"),
        (#"{"Version":1,"SecretAccessKey":"super-secret-value"}"#, "\"AccessKeyId\" is missing"),
        (#"{"Version":1,"AccessKeyId":"A"}"#, "\"SecretAccessKey\" is missing"),
        (#"{"Version":1,"AccessKeyId":"A","SecretAccessKey":"super-secret-value","Expiration":"tomorrow"}"#, "\"Expiration\" isn't an ISO 8601 time"),
    ] as [(String, String)])
    func malformedOutputSaysWhyWithoutQuotingIt(output: String, reason: String) {
        #expect(throws: AWSCredentialProcess.OutputError(reason)) { try AWSCredentialProcess.parse(Data(output.utf8)) }
        #expect(!reason.contains("super-secret-value"))
    }

    @Test func standardErrorShowsItsLastLinesWithKeysMasked() {
        let stderr = Data("starting\n\u{1B}[31mloading profile\u{1B}[0m\nwarning: cache miss\nerror: key AKIAIOSFODNN7EXAMPLE was revoked\n".utf8)
        let shown = AWSCredentialProcess.lastLines(stderr)
        #expect(shown == "loading profile / warning: cache miss / error: key [KEY] was revoked")
    }
}

// MARK: - STS and SSO requests and answers

struct AWSSTSAndSSOTests {
    let example = AWSCredentials(accessKeyId: "AKIDEXAMPLE", secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY")
    let at1800 = Date(timeIntervalSince1970: 1_792_173_600)  // 2026-10-16T18:00:00Z

    /// The AWS SigV4 test suite's `post-x-www-form-urlencoded` (the form STS takes), through the same signer.
    @Test func signerMatchesTheAWSTestSuiteFormPost() {
        var request = URLRequest(url: URL(string: "https://example.amazonaws.com/")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = Data("Param1=value1".utf8)
        SigV4Signer(credentials: example, region: "us-east-1", service: "service")
            .sign(&request, body: body, date: ISO8601DateFormatter().date(from: "2015-08-30T12:36:00Z")!)
        #expect(request.value(forHTTPHeaderField: "Authorization") ==
            "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, "
            + "SignedHeaders=content-type;host;x-amz-date, Signature=ff11897932ad3f4e8b18135d722051e5ac45fc38421b1da7b9d196a0fe09473a")
    }

    /// AssumeRole as botocore's SigV4Auth signs the same request (AWS's example credentials, a fixed time).
    @Test func assumeRoleRequestIsSignedAsBotocoreSignsIt() throws {
        let request = try AWSSTS.assumeRoleRequest(roleArn: "arn:aws:iam::123456789012:role/demo", sessionName: "allinoneime-1792188000",
                                                   region: "us-west-2", credentials: example, date: at1800)
        #expect(request.url?.absoluteString == "https://sts.us-west-2.amazonaws.com/")
        #expect(request.httpMethod == "POST")
        #expect(AWSCT.body(request) == "Action=AssumeRole&Version=2011-06-15&RoleArn=arn%3Aaws%3Aiam%3A%3A123456789012%3Arole%2Fdemo"
            + "&RoleSessionName=allinoneime-1792188000")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded; charset=utf-8")
        #expect(request.value(forHTTPHeaderField: "X-Amz-Date") == "20261016T180000Z")
        #expect(request.value(forHTTPHeaderField: "Authorization") ==
            "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20261016/us-west-2/sts/aws4_request, SignedHeaders=content-type;host;x-amz-date, "
            + "Signature=394e5caf8263030324a87bd7210ea50b6cda553e99047fd73f9e265d69cebd4c")
    }

    @Test func assumeRoleWithASessionTokenExternalIdAndDuration() throws {
        let source = AWSCredentials(accessKeyId: "ASIAEXAMPLESOURCE", secretAccessKey: "source/secret+EXAMPLE",
                                    sessionToken: "IQoJb3JpZ2luX2VjEXAMPLE//token+/=")
        let request = try AWSSTS.assumeRoleRequest(roleArn: "arn:aws:iam::123456789012:role/demo", sessionName: "allinoneime-1792188000",
                                                   externalId: "ext id/+=", durationSeconds: 3600, region: "eu-central-1",
                                                   credentials: source, date: at1800)
        #expect(AWSCT.body(request).hasSuffix("&DurationSeconds=3600&ExternalId=ext%20id%2F%2B%3D"))
        #expect(request.value(forHTTPHeaderField: "X-Amz-Security-Token") == "IQoJb3JpZ2luX2VjEXAMPLE//token+/=")
        #expect(request.value(forHTTPHeaderField: "Authorization") ==
            "AWS4-HMAC-SHA256 Credential=ASIAEXAMPLESOURCE/20261016/eu-central-1/sts/aws4_request, "
            + "SignedHeaders=content-type;host;x-amz-date;x-amz-security-token, "
            + "Signature=46fefeaff523cd6d42df59e5b180d42ea54cb995ae7c71304d786b77cf4829a4")
    }

    @Test func stsEndpointIsRegional() throws {
        #expect(try AWSSTS.endpoint(region: "ap-northeast-1").absoluteString == "https://sts.ap-northeast-1.amazonaws.com/")
        #expect(try AWSSTS.endpoint(region: "cn-north-1").absoluteString == "https://sts.cn-north-1.amazonaws.com.cn/")
        #expect(throws: BedrockError.invalidRegion("us-east-1.evil.com/x")) { try AWSSTS.endpoint(region: "us-east-1.evil.com/x") }
    }

    @Test func readsTheAssumeRoleAnswerAndErrors() throws {
        let expiration = AWSCT.iso.date(from: "2019-07-15T23:28:33Z")!
        let parsed = try #require(AWSSTS.parseAssumeRole(Data(AWSCT.assumeRoleXML("ASIAIOSFODNN7EXAMPLE", expiration: expiration).utf8)))
        #expect(parsed.credentials.accessKeyId == "ASIAIOSFODNN7EXAMPLE")
        #expect(parsed.credentials.secretAccessKey == "wJalrXUtnFEMI/K7MDENG/bPxRfiCYzEXAMPLEKEY")
        #expect(parsed.credentials.sessionToken?.hasPrefix("AQoDYXdzEPT//////////wEXAMPLE") == true)
        #expect(parsed.credentials.sessionToken?.contains(where: \.isWhitespace) == false)
        #expect(parsed.expiration == expiration)
        // The documentation's own fractional time.
        let docs = AWSCT.assumeRoleXML("A", expiration: expiration).replacingOccurrences(of: "2019-07-15T23:28:33Z", with: "2019-07-15T23:28:33.359Z")
        #expect(AWSSTS.parseAssumeRole(Data(docs.utf8))?.expiration.timeIntervalSince1970 == expiration.timeIntervalSince1970 + 0.359)
        let error = AWSSTS.parseError(Data(AWSCT.stsError("AccessDenied", "User: x is not authorized to perform: sts:AssumeRole").utf8))
        #expect(error.code == "AccessDenied" && error.message == "User: x is not authorized to perform: sts:AssumeRole")
        #expect(AWSSTS.parseAssumeRole(Data("<html>nope</html>".utf8)) == nil)
    }

    @Test func ssoCacheFileIsTheSHA1OfTheSessionOrStartURL() {
        let folder = URL(fileURLWithPath: "/tmp/cache")
        #expect(AWSSSO.cacheFile(key: "my-sso", in: folder).lastPathComponent == "0ad374308c5a4e22f723adf10145eafad7c4031c.json")
        #expect(AWSSSO.cacheFile(key: "https://my-sso-portal.awsapps.com/start", in: folder).lastPathComponent
            == "c7aaaf71fcc8777ae2475525ed049d39fe16c484.json")
    }

    @Test func ssoRoleCredentialsRequestAndAnswer() throws {
        let request = try AWSSSO.roleCredentialsRequest(region: "eu-west-1", accountId: "123456789012", roleName: "Bedrock User", token: "tok")
        #expect(request.url?.absoluteString
            == "https://portal.sso.eu-west-1.amazonaws.com/federation/credentials?role_name=Bedrock%20User&account_id=123456789012")
        #expect(request.httpMethod == "GET" && request.value(forHTTPHeaderField: "x-amz-sso_bearer_token") == "tok")
        let expiration = Date(timeIntervalSince1970: 1_792_177_200)
        let parsed = try #require(AWSSSO.parseRoleCredentials(Data(AWSCT.ssoJSON("ASIASSO", expiration: expiration).utf8)))
        #expect(parsed.credentials == AWSCredentials(accessKeyId: "ASIASSO", secretAccessKey: "sso-secret", sessionToken: "sso-session-token"))
        #expect(parsed.expiration == expiration)
        #expect(AWSSSO.parseRoleCredentials(Data(#"{"roleCredentials": {}}"#.utf8)) == nil)
        #expect(throws: BedrockError.invalidRegion("x/y")) {
            try AWSSSO.roleCredentialsRequest(region: "x/y", accountId: "1", roleName: "r", token: "t")
        }
    }

    @Test func readsTheCLIsTimesIncludingTheOldUTCSuffix() throws {
        #expect(AWSTime.parse("2026-10-16T18:00:00Z")?.timeIntervalSince1970 == 1_792_173_600)
        #expect(AWSTime.parse("2026-10-16T18:00:00UTC")?.timeIntervalSince1970 == 1_792_173_600)
        #expect(AWSTime.parse("2026-10-16T20:00:00+02:00")?.timeIntervalSince1970 == 1_792_173_600)
        #expect(AWSTime.parse("soon") == nil)
        // No time zone is UTC (as botocore reads it); a space for the "T"; +0000; z; any number of fractional digits.
        for text in ["2026-10-16T18:00:00", "2026-10-16 18:00:00", "2026-10-16 18:00:00Z", "2026-10-16T18:00:00+0000",
                     "2026-10-16T18:00:00z", " 2026-10-16T18:00:00Z\n", "2026-10-16T11:00:00-07:00"] {
            #expect(AWSTime.parse(text)?.timeIntervalSince1970 == 1_792_173_600, "\(text)")
        }
        #expect(abs((AWSTime.parse("2026-10-16T18:00:00.123456789Z")?.timeIntervalSince1970 ?? 0) - 1_792_173_600.123456789) < 1e-5)
        #expect(AWSTime.parse("2026-10-16T18:00:00.5")?.timeIntervalSince1970 == 1_792_173_600.5)
        for bad in ["2026-13-01T00:00:00Z", "2026-02-30T00:00:00Z", "2026-10-16T25:00:00Z", "2026-10-16", "2026-10-16T18:00Z"] {
            #expect(AWSTime.parse(bad) == nil, "\(bad)")
        }
        // A program's Expiration without a zone.
        let parsed = try AWSCredentialProcess.parse(Data(#"{"Version":1,"AccessKeyId":"A","SecretAccessKey":"S","Expiration":"2026-10-16 18:00:00"}"#.utf8))
        #expect(parsed.expiration?.timeIntervalSince1970 == 1_792_173_600)
    }

    @Test func ssoTokensNeverPrintTheirToken() {
        let token = AWSSSO.Token(accessToken: "eyJ-secret-token", expiresAt: Date(timeIntervalSince1970: 1_792_173_600))
        for text in ["\(token)", String(reflecting: token), "\([token])"] {
            #expect(!text.contains("eyJ-secret-token") && text.contains("2026-10-16T18:00:00Z"), "\(text)")
        }
    }

    @Test func credentialsNeverPrintTheirSecrets() {
        let credentials = AWSCredentials(accessKeyId: "ASIAEXAMPLE1234", secretAccessKey: "very-secret", sessionToken: "token-value")
        for text in ["\(credentials)", String(reflecting: credentials), "\([credentials])"] {
            #expect(!text.contains("very-secret") && !text.contains("token-value") && !text.contains("ASIAEXAMPLE"), "\(text)")
            #expect(text.contains("1234"))
        }
    }
}

// MARK: - Resolving each kind of profile

struct AWSCredentialResolverTests {
    @Test func staticKeysAndRegionAsBefore() async throws {
        let home = try AWSCTHome(config: "[profile work]\nregion = eu-west-1\n",
                                 credentials: "[work]\naws_access_key_id = AKIAWORK\naws_secret_access_key = workSecret\naws_session_token = tok\n")
        defer { home.remove() }
        let resolver = AWSCT.resolver(home)
        let resolved = try await resolver.resolve(profile: "work")
        #expect(resolved.credentials == AWSCredentials(accessKeyId: "AKIAWORK", secretAccessKey: "workSecret", sessionToken: "tok"))
        #expect(resolved.region == "eu-west-1" && resolved.kind == .staticKeys && resolved.expiration == nil)
        #expect(resolver.fetchCount(profile: "work") == 0)
    }

    @Test func keysAreNeverMixedAcrossTheTwoFiles() async throws {
        let home = try AWSCTHome(config: "[profile p]\naws_access_key_id = AKIACONFIG\naws_secret_access_key = c\naws_session_token = configToken\n",
                                 credentials: "[p]\naws_access_key_id = AKIACREDS\naws_secret_access_key = k\n")
        defer { home.remove() }
        let resolved = try await AWSCT.resolver(home).resolve(profile: "p")
        #expect(resolved.credentials == AWSCredentials(accessKeyId: "AKIACREDS", secretAccessKey: "k"))
    }

    @Test func environmentFirstForDefaultNeverForANamedProfile() async throws {
        let env = ["AWS_ACCESS_KEY_ID": "AKIAENV", "AWS_SECRET_ACCESS_KEY": "envSecret", "AWS_SESSION_TOKEN": "envToken", "AWS_REGION": "ca-central-1"]
        let none = try AWSCTHome(credentials: "[work]\naws_access_key_id = AKIAWORK\naws_secret_access_key = w\n")
        defer { none.remove() }
        for name in ["", "default", " default "] {
            let resolved = try await AWSCT.resolver(none, environment: env).resolve(profile: name)
            #expect(resolved.credentials == AWSCredentials(accessKeyId: "AKIAENV", secretAccessKey: "envSecret", sessionToken: "envToken"))
            #expect(resolved.kind == .environment && resolved.region == "ca-central-1")
        }
        // A named profile never takes the environment's keys.
        await #expect(throws: AWSCredentialError.profileNotFound("other")) { try await AWSCT.resolver(none, environment: env).resolve(profile: "other") }
        #expect(try await AWSCT.resolver(none, environment: env).resolve(profile: "work").credentials.accessKeyId == "AKIAWORK")
        // "default" takes the environment's keys first, even over a default profile with keys (as the AWS CLI does); without
        // them, the profile's.
        let withDefault = try AWSCTHome(credentials: "[default]\naws_access_key_id = AKIADEFAULT\naws_secret_access_key = d\n")
        defer { withDefault.remove() }
        let first = try await AWSCT.resolver(withDefault, environment: env).resolve(profile: "default")
        #expect(first.credentials.accessKeyId == "AKIAENV" && first.kind == .environment && first.region == "ca-central-1")
        #expect(try await AWSCT.resolver(withDefault).resolve(profile: "default").credentials.accessKeyId == "AKIADEFAULT")
        #expect(try await AWSCT.resolver(withDefault, environment: ["AWS_ACCESS_KEY_ID": "AKIAHALF"]).resolve(profile: "default")
            .credentials.accessKeyId == "AKIADEFAULT", "only both the key ID and the secret count")
        // A named profile without credentials still doesn't take them.
        let named = try AWSCTHome(config: "[profile work]\nregion = eu-west-1\n")
        defer { named.remove() }
        await #expect(throws: AWSCredentialError.noCredentials(profile: "work")) {
            try await AWSCT.resolver(named, environment: env).resolve(profile: "work")
        }
        // One with only a region: the environment's keys, its region.
        let regionOnly = try AWSCTHome(config: "[default]\nregion = sa-east-1\n")
        defer { regionOnly.remove() }
        let fromEnvironment = try await AWSCT.resolver(regionOnly, environment: env).resolve(profile: "default")
        #expect(fromEnvironment.kind == .environment && fromEnvironment.region == "ca-central-1", "AWS_REGION wins, as in the CLI")
        #expect(try await AWSCT.resolver(regionOnly, environment: ["AWS_ACCESS_KEY_ID": "AKIAENV", "AWS_SECRET_ACCESS_KEY": "e"])
            .resolve(profile: "default").region == "sa-east-1")
        await #expect(throws: AWSCredentialError.noCredentials(profile: "default")) { try await AWSCT.resolver(regionOnly).resolve(profile: "default") }
        await #expect(throws: AWSCredentialError.profileNotFound("default")) { try await AWSCT.resolver(none).resolve(profile: "") }
    }

    @Test func filesNamedByTheEnvironment() async throws {
        let home = try AWSCTHome()
        defer { home.remove() }
        let config = home.root.appendingPathComponent("elsewhere-config"), credentials = home.root.appendingPathComponent("elsewhere-credentials")
        try Data("[profile far]\nregion = ap-south-1\n".utf8).write(to: config)
        try Data("[far]\naws_access_key_id = AKIAFAR\naws_secret_access_key = f\n".utf8).write(to: credentials)
        let env = ["AWS_CONFIG_FILE": config.path, "AWS_SHARED_CREDENTIALS_FILE": credentials.path]
        let resolver = AWSCT.resolver(home, environment: env)
        let resolved = try await resolver.resolve(profile: "far")
        #expect(resolved.credentials.accessKeyId == "AKIAFAR" && resolved.region == "ap-south-1")
        #expect(resolver.profiles().map(\.name) == ["far"])
        let tilde = AWSFileLocations(environment: ["HOME": "/Users/someone", "AWS_CONFIG_FILE": "~/cfg/aws", "AWS_SHARED_CREDENTIALS_FILE": "/etc/creds"])
        #expect(tilde.config.path == "/Users/someone/cfg/aws" && tilde.credentials.path == "/etc/creds")
        #expect(tilde.ssoCache.path == "/Users/someone/.aws/sso/cache")
    }

    @Test func credentialProcessRunsWithTheLoginPathInHomeAndIsCachedUntilFiveMinutesBeforeExpiry() async throws {
        let home = try AWSCTHome(config: "[profile dev]\ncredential_process = /usr/local/bin/my-creds --profile dev\nregion = us-west-2\n")
        defer { home.remove() }
        let clock = AWSCTClock()
        let runner = AWSCTRunner([AWSCT.processJSON("ASIAONE", expiration: clock.now.addingTimeInterval(3600)),
                                  AWSCT.processJSON("ASIATWO", expiration: clock.now.addingTimeInterval(7200))])
        let resolver = AWSCT.resolver(home, clock: clock, runner: runner)
        let first = try await resolver.resolve(profile: "dev")
        #expect(first.credentials.accessKeyId == "ASIAONE" && first.kind == .credentialProcess && first.region == "us-west-2")
        #expect(first.expiration == clock.now.addingTimeInterval(3600))
        let run = try #require(runner.runs.first)
        #expect(run.arguments == ["/usr/local/bin/my-creds", "--profile", "dev"])
        #expect(run.directory == home.root && run.timeout == 60 && run.environment["PATH"] != nil)
        clock.advance(3600 - 11 * 60)  // 11 minutes left: cached
        #expect(try await resolver.resolve(profile: "dev").credentials.accessKeyId == "ASIAONE")
        #expect(runner.runs.count == 1)
        clock.advance(7 * 60)  // 4 minutes left: fetched again first
        #expect(try await resolver.resolve(profile: "dev").credentials.accessKeyId == "ASIATWO")
        #expect(runner.runs.count == 2)
    }

    // The limit only catches a request that waits for the refresh, which is held until the test lets it go.
    @Test(.timeLimit(.minutes(1)))
    func underTenMinutesLeftARequestGetsTheCachedOnesAndRefreshesInTheBackground() async throws {
        let home = try AWSCTHome(config: "[profile dev]\ncredential_process = my-creds\n")
        defer { home.remove() }
        let clock = AWSCTClock()
        let runner = AWSCTRunner([AWSCT.processJSON("ASIAONE", expiration: clock.now.addingTimeInterval(3600)),
                                  AWSCT.processJSON("ASIATWO", expiration: clock.now.addingTimeInterval(7200))])
        let resolver = AWSCT.resolver(home, clock: clock, runner: runner)
        _ = try await resolver.resolve(profile: "dev")
        clock.advance(3600 - 8 * 60)  // 8 minutes left
        // Answered while the refresh is held up: it didn't wait for it.
        runner.hold()
        #expect(try await resolver.resolve(profile: "dev").credentials.accessKeyId == "ASIAONE")
        #expect(resolver.fetchCount(profile: "dev") == 2)
        // Another request meanwhile doesn't start a second refresh.
        #expect(try await resolver.resolve(profile: "dev").credentials.accessKeyId == "ASIAONE")
        runner.release()
        await resolver.waitForRefreshes()
        #expect(runner.runs.count == 2)
        #expect(try await resolver.resolve(profile: "dev").credentials.accessKeyId == "ASIATWO")
        #expect(resolver.status(profile: "dev").expiration == clock.now.addingTimeInterval(7200 - 3600 + 8 * 60))
    }

    @Test func concurrentRequestsWaitForOneRefresh() async throws {
        let home = try AWSCTHome(config: "[profile dev]\ncredential_process = my-creds\n")
        defer { home.remove() }
        let clock = AWSCTClock()
        let runner = AWSCTRunner([AWSCT.processJSON("ASIAONE", expiration: clock.now.addingTimeInterval(3600))], delay: 0.3)
        let resolver = AWSCT.resolver(home, clock: clock, runner: runner)
        let ids = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 { group.addTask { try await resolver.resolve(profile: "dev").credentials.accessKeyId } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(ids == Array(repeating: "ASIAONE", count: 8))
        #expect(runner.runs.count == 1 && resolver.fetchCount(profile: "dev") == 1)
    }

    @Test func withoutAnExpirationKeptUntilAWSRefusesThem() async throws {
        let home = try AWSCTHome(config: "[profile dev]\ncredential_process = my-creds\n")
        defer { home.remove() }
        let clock = AWSCTClock()
        let runner = AWSCTRunner([AWSCT.processJSON("ASIAONE"), AWSCT.processJSON("ASIATWO")])
        let resolver = AWSCT.resolver(home, clock: clock, runner: runner)
        let first = try await resolver.resolve(profile: "dev")
        clock.advance(30 * 86400)
        #expect(try await resolver.resolve(profile: "dev").credentials.accessKeyId == "ASIAONE")
        // Refused by AWS: run again.
        let refresh = try #require(first.refresh)
        let fresh = try await refresh()
        #expect(fresh.credentials.accessKeyId == "ASIATWO" && runner.runs.count == 2)
        // A second request that failed with the old ones gets the new ones without another run.
        #expect(try await resolver.refresh(profile: "dev", replacing: first.credentials).credentials.accessKeyId == "ASIATWO")
        #expect(runner.runs.count == 2)
    }

    @Test func aChangedProfileIsFetchedAgain() async throws {
        let home = try AWSCTHome(config: "[profile dev]\ncredential_process = my-creds --one\n")
        defer { home.remove() }
        let runner = AWSCTRunner([AWSCT.processJSON("ASIAONE"), AWSCT.processJSON("ASIATWO")])
        let resolver = AWSCT.resolver(home, runner: runner)
        _ = try await resolver.resolve(profile: "dev")
        try home.write(config: "[profile dev]\ncredential_process = my-creds --two\n", credentials: "")
        #expect(try await resolver.resolve(profile: "dev").credentials.accessKeyId == "ASIATWO")
        #expect(runner.runs.last?.arguments == ["my-creds", "--two"])
    }

    @Test func aFailingProcessShowsItsStandardErrorMaskedNeverItsOutput() async throws {
        let home = try AWSCTHome(config: "[profile dev]\ncredential_process = /opt/tools/my-creds --token hunter2\n")
        defer { home.remove() }
        let failed = AWSProcessResult(status: 3, standardOutput: Data("AccessKeyId=AKIAIOSFODNN7EXAMPLE".utf8),
                                      standardError: Data("refreshing…\nerror: session for AKIAIOSFODNN7EXAMPLE expired\n".utf8))
        await #expect(throws: AWSCredentialError.processFailed(profile: "dev", program: "my-creds", status: 3,
                                                               stderr: "refreshing… / error: session for [KEY] expired")) {
            try await AWSCT.resolver(home, runner: AWSCTRunner([failed])).resolve(profile: "dev")
        }
        let garbage = AWSProcessResult(status: 0, standardOutput: Data("SecretAccessKey: not-json-secret".utf8),
                                       standardError: Data("warning: old output format\n".utf8))
        do {
            _ = try await AWSCT.resolver(home, runner: AWSCTRunner([garbage])).resolve(profile: "dev")
            Issue.record("bad JSON was accepted")
        } catch let error as AWSCredentialError {
            #expect(error == .processOutputInvalid(profile: "dev", program: "my-creds", reason: "it isn't a JSON object",
                                                   stderr: "warning: old output format"))
            #expect(error.message(chinese: false) == "AWS profile 'dev': credential_process (my-creds) didn't print the JSON the AWS CLI "
                + "expects: it isn't a JSON object; it said: warning: old output format")
            #expect(!error.message(chinese: false).contains("not-json-secret") && !error.message(chinese: false).contains("hunter2"))
        }
        let broken = try AWSCTHome(config: "[profile dev]\ncredential_process = my-creds 'unclosed\n")
        defer { broken.remove() }
        await #expect(throws: AWSCredentialError.invalidCommand(profile: "dev", reason: "a quote isn't closed")) {
            try await AWSCT.resolver(broken, runner: AWSCTRunner([garbage])).resolve(profile: "dev")
        }
    }

    @Test func roleWithASourceProfileIsAssumedAtTheRegionalEndpoint() async throws {
        let home = try AWSCTHome(
            config: """
                [profile base]
                region = us-east-2
                [profile dev]
                role_arn = arn:aws:iam::123456789012:role/Bedrock
                source_profile = base
                region = eu-west-1
                external_id = shared-id
                duration_seconds = 1800
                """,
            credentials: "[base]\naws_access_key_id = AKIABASE\naws_secret_access_key = baseSecret\n")
        defer { home.remove() }
        let clock = AWSCTClock(), http = AWSCTHTTP()
        http.on("sts.eu-west-1.amazonaws.com", .init(status: 200, body: AWSCT.assumeRoleXML("ASIAROLE", expiration: clock.now.addingTimeInterval(1800))))
        let resolver = AWSCT.resolver(home, clock: clock, http: http)
        let resolved = try await resolver.resolve(profile: "dev")
        #expect(resolved.credentials.accessKeyId == "ASIAROLE" && resolved.kind == .role(source: "base") && resolved.region == "eu-west-1")
        #expect(resolved.expiration == clock.now.addingTimeInterval(1800))
        let request = try #require(http.requests.first)
        #expect(AWSCT.header(request, "Authorization")?.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIABASE/20261016/eu-west-1/sts/aws4_request") == true)
        #expect(AWSCT.body(request) == "Action=AssumeRole&Version=2011-06-15&RoleArn=arn%3Aaws%3Aiam%3A%3A123456789012%3Arole%2FBedrock"
            + "&RoleSessionName=allinoneime-1792173600&DurationSeconds=1800&ExternalId=shared-id")
        _ = try await resolver.resolve(profile: "dev")
        #expect(http.requests.count == 1, "cached")
    }

    @Test func roleDefaultsToUSEast1AndItsOwnSessionName() async throws {
        let home = try AWSCTHome(config: "[profile dev]\nrole_arn = arn:aws:iam::1:role/r\nsource_profile = base\nrole_session_name = me@example\n",
                                 credentials: "[base]\naws_access_key_id = AKIABASE\naws_secret_access_key = b\n")
        defer { home.remove() }
        let http = AWSCTHTTP()
        http.on("sts.us-east-1.amazonaws.com", .init(status: 200, body: AWSCT.assumeRoleXML("ASIAROLE", expiration: Date().addingTimeInterval(3600))))
        _ = try await AWSCT.resolver(home, http: http).resolve(profile: "dev")
        #expect(AWSCT.body(try #require(http.requests.first)).contains("&RoleSessionName=me%40example"))
    }

    @Test func rolesChainThroughRolesAndProcesses() async throws {
        let home = try AWSCTHome(config: """
            [profile source]
            credential_process = my-creds
            [profile middle]
            role_arn = arn:aws:iam::1:role/middle
            source_profile = source
            [profile top]
            role_arn = arn:aws:iam::2:role/top
            source_profile = middle
            region = us-west-2
            """)
        defer { home.remove() }
        let clock = AWSCTClock(), http = AWSCTHTTP()
        http.on("sts.us-east-1.amazonaws.com", .init(status: 200, body: AWSCT.assumeRoleXML("ASIAMIDDLE", expiration: clock.now.addingTimeInterval(3600))))
        http.on("sts.us-west-2.amazonaws.com", .init(status: 200, body: AWSCT.assumeRoleXML("ASIATOP", expiration: clock.now.addingTimeInterval(3600))))
        let runner = AWSCTRunner([AWSCT.processJSON("ASIASOURCE")])
        let resolved = try await AWSCT.resolver(home, clock: clock, http: http, runner: runner).resolve(profile: "top")
        #expect(resolved.credentials.accessKeyId == "ASIATOP" && runner.runs.count == 1)
        #expect(AWSCT.header(http.requests(("sts.us-east-1.amazonaws.com"))[0], "Authorization")?.contains("Credential=ASIASOURCE/") == true)
        #expect(AWSCT.header(http.requests(("sts.us-west-2.amazonaws.com"))[0], "Authorization")?.contains("Credential=ASIAMIDDLE/") == true)
        #expect(AWSCT.header(http.requests(("sts.us-west-2.amazonaws.com"))[0], "X-Amz-Security-Token")?.hasPrefix("AQoDYXdzEPT") == true)
    }

    @Test func roleFromTheEnvironment() async throws {
        let home = try AWSCTHome(config: "[profile dev]\nrole_arn = arn:aws:iam::1:role/r\ncredential_source = Environment\n")
        defer { home.remove() }
        let http = AWSCTHTTP()
        http.on("sts.us-east-1.amazonaws.com", .init(status: 200, body: AWSCT.assumeRoleXML("ASIAROLE", expiration: Date().addingTimeInterval(3600))))
        let env = ["AWS_ACCESS_KEY_ID": "AKIAENV", "AWS_SECRET_ACCESS_KEY": "e"]
        let resolved = try await AWSCT.resolver(home, http: http, environment: env).resolve(profile: "dev")
        #expect(resolved.kind == .role(source: "Environment") && resolved.credentials.accessKeyId == "ASIAROLE")
        #expect(AWSCT.header(try #require(http.requests.first), "Authorization")?.contains("Credential=AKIAENV/") == true)
        await #expect(throws: AWSCredentialError.environmentMissing(profile: "dev")) { try await AWSCT.resolver(home, http: http).resolve(profile: "dev") }
    }

    @Test(arguments: ["Ec2InstanceMetadata", "EcsContainer"])
    func instanceAndContainerSourcesAreUnsupportedWithTheReason(source: String) async throws {
        let home = try AWSCTHome(config: "[profile dev]\nrole_arn = arn:aws:iam::1:role/r\ncredential_source = \(source)\n")
        defer { home.remove() }
        let http = AWSCTHTTP()
        do {
            _ = try await AWSCT.resolver(home, http: http).resolve(profile: "dev")
            Issue.record("resolved")
        } catch let error as AWSCredentialError {
            #expect(error == .unsupportedCredentialSource(profile: "dev", source: source))
            #expect(error.message(chinese: false).contains("unsupported") && error.message(chinese: false).contains("not on a Mac"))
        }
        #expect(http.requests.isEmpty)
    }

    @Test func mfaIsRefusedBeforeAnythingRuns() async throws {
        let home = try AWSCTHome(config: """
            [profile source]
            credential_process = my-creds
            [profile dev]
            role_arn = arn:aws:iam::1:role/r
            source_profile = source
            mfa_serial = arn:aws:iam::1:mfa/me
            """)
        defer { home.remove() }
        let http = AWSCTHTTP(), runner = AWSCTRunner([AWSCT.processJSON("ASIASOURCE")])
        do {
            _ = try await AWSCT.resolver(home, http: http, runner: runner).resolve(profile: "dev")
            Issue.record("resolved")
        } catch let error as AWSCredentialError {
            #expect(error == .needsMFA(profile: "dev"))
            #expect(error.message(chinese: false).contains(
                "this profile needs an MFA code; use credential_process or SSO, or run your CLI to cache credentials"))
        }
        #expect(http.requests.isEmpty && runner.runs.isEmpty)
        #expect(AWSCT.resolver(home).status(profile: "dev").problem == .needsMFA(profile: "dev"))
    }

    @Test func sourceProfileLoopsAreFound() async throws {
        let home = try AWSCTHome(config: """
            [profile a]
            role_arn = arn:aws:iam::1:role/a
            source_profile = b
            [profile b]
            role_arn = arn:aws:iam::1:role/b
            source_profile = a
            [profile self]
            role_arn = arn:aws:iam::1:role/s
            source_profile = self
            """)
        defer { home.remove() }
        let http = AWSCTHTTP()
        let resolver = AWSCT.resolver(home, http: http)
        await #expect(throws: AWSCredentialError.sourceProfileLoop(["a", "b", "a"])) { try await resolver.resolve(profile: "a") }
        await #expect(throws: AWSCredentialError.sourceProfileLoop(["self", "self"])) { try await resolver.resolve(profile: "self") }
        #expect(http.requests.isEmpty)
        #expect(resolver.status(profile: "b").problem == .sourceProfileLoop(["b", "a", "b"]))
        // A role naming itself with keys of its own: they're its source (botocore), not a loop.
        try home.write(config: "[profile self]\nrole_arn = arn:aws:iam::1:role/s\nsource_profile = self\n",
                       credentials: "[self]\naws_access_key_id = AKIASELF\naws_secret_access_key = s\n")
        http.on("sts.us-east-1.amazonaws.com", .init(status: 200, body: AWSCT.assumeRoleXML("ASIASELFROLE", expiration: Date().addingTimeInterval(3600))))
        let assumed = try await resolver.resolve(profile: "self")
        #expect(assumed.kind == .role(source: "self") && assumed.credentials.accessKeyId == "ASIASELFROLE")
        #expect(AWSCT.header(try #require(http.requests.first), "Authorization")?.contains("Credential=AKIASELF/") == true)
        #expect(resolver.status(profile: "self").problem == nil)
        // Met again further down the chain, a profile is a loop even with keys of its own (only itself may name itself).
        try home.write(config: "[profile c]\nrole_arn = arn:aws:iam::1:role/c\nsource_profile = d\n[profile d]\nrole_arn = arn:aws:iam::1:role/d\nsource_profile = c\n",
                       credentials: "[c]\naws_access_key_id = AKIAC\naws_secret_access_key = c\n")
        await #expect(throws: AWSCredentialError.sourceProfileLoop(["c", "d", "c"])) { try await resolver.resolve(profile: "c") }
        #expect(resolver.status(profile: "c").problem == .sourceProfileLoop(["c", "d", "c"]))
    }

    /// Two roles naming each other, asked for at the same time: both fail at once with the loop (neither waits for the
    /// other's fetch).
    @Test func aMutualLoopRequestedAtOnceFailsInsteadOfHanging() async throws {
        let home = try AWSCTHome(config: """
            [profile a]
            role_arn = arn:aws:iam::1:role/a
            source_profile = b
            [profile b]
            role_arn = arn:aws:iam::1:role/b
            source_profile = a
            [profile top]
            role_arn = arn:aws:iam::1:role/top
            source_profile = a
            """)
        defer { home.remove() }
        let http = AWSCTHTTP()
        // Reading the environment takes a moment, so the requests overlap.
        let resolver = AWSCredentialResolver(context: AWSCredentialContext(
            environment: { Thread.sleep(forTimeInterval: 0.05); return [:] }, files: home.files, processEnvironment: { [:] }, send: http.send))
        let outcomes = OSAllocatedUnfairLock(initialState: [String: String]())
        for profile in ["a", "b", "top", "a", "b"] {
            Task.detached {
                let outcome: String
                do { outcome = try await resolver.resolve(profile: profile).credentials.accessKeyId } catch { outcome = "\(error)" }
                outcomes.withLock { $0[profile, default: ""] += outcome + ";" }
            }
        }
        let deadline = Date().addingTimeInterval(10)
        while outcomes.withLock({ $0.values.reduce(0) { $0 + $1.split(separator: ";").count } }) < 5, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let seen = outcomes.withLock { $0 }
        #expect(seen["a"] == "\(AWSCredentialError.sourceProfileLoop(["a", "b", "a"]));\(AWSCredentialError.sourceProfileLoop(["a", "b", "a"]));",
                "\(seen)")
        #expect(seen["b"] == "\(AWSCredentialError.sourceProfileLoop(["b", "a", "b"]));\(AWSCredentialError.sourceProfileLoop(["b", "a", "b"]));",
                "\(seen)")
        #expect(seen["top"] == "\(AWSCredentialError.sourceProfileLoop(["a", "b", "a"]));", "\(seen)")
        #expect(http.requests.isEmpty && resolver.fetchCount(profile: "a") == 0 && resolver.fetchCount(profile: "b") == 0)
    }

    @Test func awsRegionWinsOverTheProfilesRegionAsInTheCLI() async throws {
        let home = try AWSCTHome(config: """
            [profile keys]
            region = eu-west-1
            [profile dev]
            role_arn = arn:aws:iam::1:role/r
            source_profile = keys
            region = eu-west-1
            """, credentials: "[keys]\naws_access_key_id = AKIAKEYS\naws_secret_access_key = k\n")
        defer { home.remove() }
        let http = AWSCTHTTP()
        http.on("sts.ap-south-1.amazonaws.com", .init(status: 200, body: AWSCT.assumeRoleXML("ASIAROLE", expiration: Date().addingTimeInterval(3600))))
        let resolver = AWSCT.resolver(home, http: http, environment: ["AWS_REGION": "ap-south-1", "AWS_DEFAULT_REGION": "us-east-2"])
        #expect(try await resolver.resolve(profile: "keys").region == "ap-south-1")
        let role = try await resolver.resolve(profile: "dev")
        #expect(role.region == "ap-south-1" && http.requests.first?.url?.host == "sts.ap-south-1.amazonaws.com", "STS there too")
        #expect(resolver.status(profile: "keys").region == "ap-south-1" && resolver.region(profile: "keys") == "ap-south-1")
        #expect(try await AWSCT.resolver(home, environment: ["AWS_DEFAULT_REGION": "us-east-2"]).resolve(profile: "keys").region == "us-east-2")
        #expect(try await AWSCT.resolver(home).resolve(profile: "keys").region == "eu-west-1")
        #expect(AWSSharedConfig.region(profile: "keys", environment: ["HOME": home.root.path, "AWS_CONFIG_FILE": home.files.config.path,
                                                                      "AWS_REGION": "ap-south-1"]) == "ap-south-1")
    }

    @Test func theProgramPathIsntExpandedLikeAShellWould() async throws {
        let home = try AWSCTHome()
        defer { home.remove() }
        let script = try home.script("my-creds", #"printf '{"Version": 1, "AccessKeyId": "ASIATILDE", "SecretAccessKey": "s"}'"#)
        let folder = URL(fileURLWithPath: script).deletingLastPathComponent()
        #expect(AWSProcessRunner.resolve("~/my-creds", path: "/usr/bin:/bin", directory: folder) == nil, "~ is a folder name, as for the CLI")
        #expect(AWSProcessRunner.resolve(script, path: nil, directory: folder)?.path == script)
        #expect(AWSProcessRunner.resolve("./my-creds", path: nil, directory: folder) != nil, "relative to the home folder it runs in")
        #expect(AWSProcessRunner.resolve("my-creds", path: folder.path, directory: URL(fileURLWithPath: "/")) != nil)
        try home.write(config: "[profile dev]\ncredential_process = ~/my-creds\n", credentials: "")
        let resolver = AWSCredentialResolver(context: AWSCredentialContext(environment: ["HOME": home.root.path]))
        await #expect(throws: AWSCredentialError.processNotFound(profile: "dev", program: "my-creds")) { try await resolver.resolve(profile: "dev") }
        #expect(resolver.status(profile: "dev").problem == .processNotFound(profile: "dev", program: "my-creds"))
    }

    @Test func doctorSaysWhenCredentialsWillBeFetchedAndALastRefreshThatFailed() async throws {
        let home = try AWSCTHome(config: "[profile dev]\nrole_arn = arn:aws:iam::1:role/r\nsource_profile = keys\n[profile proc]\ncredential_process = \(AWSCT.echo)\n",
                                 credentials: "[keys]\naws_access_key_id = AKIAKEYS\naws_secret_access_key = k\n")
        defer { home.remove() }
        // The checks tell the time by the real clock.
        let clock = AWSCTClock(Date()), http = AWSCTHTTP()
        http.on("sts.us-east-1.amazonaws.com", .init(status: 200, body: AWSCT.assumeRoleXML("ASIAROLE", expiration: clock.now.addingTimeInterval(3600))),
                .init(status: 403, body: AWSCT.stsError("AccessDenied", "Not allowed any more")))
        let resolver = AWSCT.resolver(home, clock: clock, http: http)
        func rows(_ profile: String) -> [Doctor.Finding] {
            var facts = Doctor.Facts()
            var config = Config.default
            config.provider = .bedrock
            config.awsProfile = profile
            facts.config = config
            facts.awsStatus = resolver.status(profile: profile)
            facts.awsProfile = .success("us-east-1")
            return Doctor.findings(facts, chinese: false).filter { $0.area == .provider }
        }
        #expect(rows("dev").map(\.status) == [.ok] && rows("dev")[0].detail?.hasSuffix("assumed when a request needs it") == true, "\(rows("dev"))")
        #expect(rows("proc")[0].detail?.hasSuffix("runs when a request needs credentials") == true)
        #expect(rows("keys")[0].detail?.hasSuffix("credentials found") == true, "static keys as before")
        _ = try await resolver.resolve(profile: "dev")
        #expect(rows("dev")[0].detail?.contains("credentials expire at") == true)
        // A refresh that failed while the credentials still hold.
        await #expect(throws: AWSCredentialError.self) { try await resolver.resolve(profile: "dev", forceRefresh: true) }
        let after = rows("dev")  // problems and warnings first
        let failed = try #require(after.first { $0.title == "AWS credentials: the last refresh failed" }, "\(after)")
        #expect(failed.status == .warning && failed.detail?.contains("Not allowed any more") == true)
        #expect(after.map(\.status).sorted() == [.warning, .ok] && after.contains { $0.detail?.contains("credentials expire at") == true })
    }

    @Test func theStatusLineIsReadAgainAtTheNextChange() {
        let now = Date(timeIntervalSince1970: 1_792_173_600)
        var status = AWSProfileStatus(profile: "dev")
        #expect(status.secondsUntilChange(now: now) == 60, "at least every minute")
        status.hasCredentials = true
        status.expiration = now.addingTimeInterval(20)
        #expect(status.secondsUntilChange(now: now) == 20.5, "when the credentials expire")
        status.signedInUntil = now.addingTimeInterval(5)
        #expect(status.secondsUntilChange(now: now) == 5.5, "when the sign-in ends")
        status.signedInUntil = now.addingTimeInterval(-5)
        status.expiration = now.addingTimeInterval(0.1)
        #expect(status.secondsUntilChange(now: now) == 1, "never sooner than a second")
    }

    /// botocore's order within a named profile: role_arn, SSO, the credentials file's keys, credential_process, the config
    /// file's keys.
    @Test func withinAProfileTheAWSCLIsOrder() async throws {
        let home = try AWSCTHome(config: """
            [profile base]
            region = us-east-1
            [profile both]
            role_arn = arn:aws:iam::1:role/both
            source_profile = base
            [profile ssoAndKeys]
            sso_session = my-sso
            sso_account_id = 123456789012
            sso_role_name = BedrockUser
            [profile keysAndProcess]
            credential_process = my-creds
            [profile processAndConfigKeys]
            credential_process = my-creds
            aws_access_key_id = AKIACONFIG
            aws_secret_access_key = c
            [profile configKeys]
            aws_access_key_id = AKIACONFIGONLY
            aws_secret_access_key = c
            [profile hybrid]
            role_arn = arn:aws:iam::1:role/never
            source_profile = base
            [profile top]
            role_arn = arn:aws:iam::1:role/top
            source_profile = hybrid
            [profile sessionOnly]
            sso_session = my-sso
            [sso-session my-sso]
            sso_start_url = https://my-sso-portal.awsapps.com/start
            sso_region = us-east-1
            """, credentials: """
            [base]
            aws_access_key_id = AKIABASE
            aws_secret_access_key = b
            [both]
            aws_access_key_id = AKIABOTH
            aws_secret_access_key = b
            [ssoAndKeys]
            aws_access_key_id = AKIASSOKEYS
            aws_secret_access_key = s
            [keysAndProcess]
            aws_access_key_id = AKIACREDSFILE
            aws_secret_access_key = k
            [hybrid]
            aws_access_key_id = AKIAHYBRID
            aws_secret_access_key = h
            """)
        defer { home.remove() }
        let clock = AWSCTClock(), http = AWSCTHTTP()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(3600))
        http.on("sts.us-east-1.amazonaws.com", .init(status: 200, body: AWSCT.assumeRoleXML("ASIAROLE", expiration: clock.now.addingTimeInterval(3600))))
        http.on("portal.sso.us-east-1.amazonaws.com", .init(status: 200, body: AWSCT.ssoJSON("ASIASSO", expiration: clock.now.addingTimeInterval(3600))))
        let runner = AWSCTRunner([AWSCT.processJSON("ASIAPROCESS")])
        let resolver = AWSCT.resolver(home, clock: clock, http: http, runner: runner)
        // 1. A role, though the profile has keys too: assumed with its source's keys.
        let both = try await resolver.resolve(profile: "both")
        #expect(both.kind == .role(source: "base") && both.credentials.accessKeyId == "ASIAROLE")
        #expect(AWSCT.header(try #require(http.requests.last), "Authorization")?.contains("Credential=AKIABASE/") == true)
        // 2. SSO before keys.
        #expect(try await resolver.resolve(profile: "ssoAndKeys").credentials.accessKeyId == "ASIASSO")
        // 3. The credentials file's keys before credential_process, 4. which comes before the config file's keys.
        #expect(try await resolver.resolve(profile: "keysAndProcess").credentials.accessKeyId == "AKIACREDSFILE")
        #expect(runner.runs.isEmpty)
        let process = try await resolver.resolve(profile: "processAndConfigKeys")
        #expect(process.kind == .credentialProcess && process.credentials.accessKeyId == "ASIAPROCESS" && runner.runs.count == 1)
        #expect(try await resolver.resolve(profile: "configKeys").kind == .staticKeys)
        // A source profile with keys of its own is used with them, not assumed as a role itself.
        let stsBefore = http.requests.count
        #expect(try await resolver.resolve(profile: "top").credentials.accessKeyId == "ASIAROLE")
        #expect(http.requests.count == stsBefore + 1)
        #expect(AWSCT.header(try #require(http.requests.last), "Authorization")?.contains("Credential=AKIAHYBRID/") == true)
        // Resolved on its own, it is the role.
        #expect(try await resolver.resolve(profile: "hybrid").kind == .role(source: "base"))
        await #expect(throws: AWSCredentialError.invalidProfile(profile: "sessionOnly", reason: "an SSO profile needs sso_account_id and sso_role_name")) {
            try await resolver.resolve(profile: "sessionOnly")
        }
        // The settings' picker says the same kinds.
        let kinds = Dictionary(uniqueKeysWithValues: resolver.profiles().map { ($0.name, $0.kind) })
        #expect(kinds["both"] == .role(source: "base") && kinds["ssoAndKeys"] == .sso && kinds["keysAndProcess"] == .staticKeys
                && kinds["processAndConfigKeys"] == .credentialProcess && kinds["hybrid"] == .role(source: "base"))
        #expect(AWSProfileKind.role(source: "base").label(chinese: false) == "Role via base")
    }

    @Test func badRoleSettingsSayWhatsWrong() async throws {
        let home = try AWSCTHome(config: """
            [profile neither]
            role_arn = arn:aws:iam::1:role/r
            [profile both]
            role_arn = arn:aws:iam::1:role/r
            source_profile = x
            credential_source = Environment
            [profile duration]
            role_arn = arn:aws:iam::1:role/r
            source_profile = x
            duration_seconds = an hour
            [profile web]
            role_arn = arn:aws:iam::1:role/r
            web_identity_token_file = /tmp/token
            [profile missing]
            role_arn = arn:aws:iam::1:role/r
            source_profile = nowhere
            """)
        defer { home.remove() }
        let resolver = AWSCT.resolver(home)
        await #expect(throws: AWSCredentialError.invalidProfile(profile: "neither", reason: "role_arn needs source_profile or credential_source")) {
            try await resolver.resolve(profile: "neither")
        }
        await #expect(throws: AWSCredentialError.invalidProfile(profile: "both", reason: "role_arn has both source_profile and credential_source; keep one")) {
            try await resolver.resolve(profile: "both")
        }
        await #expect(throws: AWSCredentialError.invalidProfile(profile: "duration", reason: "duration_seconds isn't a number of seconds: an hour")) {
            try await resolver.resolve(profile: "duration")
        }
        await #expect(throws: AWSCredentialError.unsupported(profile: "web", kind: "web_identity_token_file")) { try await resolver.resolve(profile: "web") }
        await #expect(throws: AWSCredentialError.profileNotFound("nowhere")) { try await resolver.resolve(profile: "missing") }
    }

    @Test func stsErrorsAreShownWithTheirCode() async throws {
        let home = try AWSCTHome(config: "[profile dev]\nrole_arn = arn:aws:iam::1:role/r\nsource_profile = base\n",
                                 credentials: "[base]\naws_access_key_id = AKIABASE\naws_secret_access_key = b\n")
        defer { home.remove() }
        let http = AWSCTHTTP()
        http.on("sts.us-east-1.amazonaws.com", .init(status: 403, body: AWSCT.stsError("AccessDenied", "User: base is not authorized to perform: sts:AssumeRole")))
        await #expect(throws: AWSCredentialError.stsFailed(profile: "dev", code: "AccessDenied", message: "User: base is not authorized to perform: sts:AssumeRole")) {
            try await AWSCT.resolver(home, http: http).resolve(profile: "dev")
        }
        let offline = AWSCredentialResolver(context: AWSCredentialContext(environment: ["HOME": home.root.path], send: AWSCredentialContext.offline))
        await #expect(throws: AWSCredentialError.network(profile: "dev", message: "no network connection")) { try await offline.resolve(profile: "dev") }
    }

    @Test func anExpiredSourceIsFetchedAgainOnceWhenSTSSaysSo() async throws {
        let home = try AWSCTHome(config: "[profile source]\ncredential_process = my-creds\n[profile dev]\nrole_arn = arn:aws:iam::1:role/r\nsource_profile = source\n")
        defer { home.remove() }
        let http = AWSCTHTTP()
        http.on("sts.us-east-1.amazonaws.com", .init(status: 403, body: AWSCT.stsError("ExpiredToken", "The security token included in the request is expired")),
                .init(status: 200, body: AWSCT.assumeRoleXML("ASIAROLE", expiration: Date().addingTimeInterval(3600))))
        let runner = AWSCTRunner([AWSCT.processJSON("ASIAOLD"), AWSCT.processJSON("ASIANEW")])
        let resolved = try await AWSCT.resolver(home, http: http, runner: runner).resolve(profile: "dev")
        #expect(resolved.credentials.accessKeyId == "ASIAROLE" && runner.runs.count == 2)
        #expect(AWSCT.header(http.requests[1], "Authorization")?.contains("Credential=ASIANEW/") == true)
    }

    @Test func ssoSessionProfileUsesTheCachedSignIn() async throws {
        let home = try AWSCTHome(config: """
            [profile sso-dev]
            sso_session = my-sso
            sso_account_id = 123456789012
            sso_role_name = BedrockUser
            region = us-west-2
            [sso-session my-sso]
            sso_start_url = https://my-sso-portal.awsapps.com/start
            sso_region = us-east-1
            sso_registration_scopes = sso:account:access
            """)
        defer { home.remove() }
        let clock = AWSCTClock(), http = AWSCTHTTP()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(8 * 3600))
        http.on("portal.sso.us-east-1.amazonaws.com", .init(status: 200, body: AWSCT.ssoJSON("ASIASSO", expiration: clock.now.addingTimeInterval(3600))))
        let resolver = AWSCT.resolver(home, clock: clock, http: http)
        let resolved = try await resolver.resolve(profile: "sso-dev")
        #expect(resolved.credentials == AWSCredentials(accessKeyId: "ASIASSO", secretAccessKey: "sso-secret", sessionToken: "sso-session-token"))
        #expect(resolved.kind == .sso && resolved.region == "us-west-2" && resolved.expiration == clock.now.addingTimeInterval(3600))
        let request = try #require(http.requests.first)
        #expect(request.url?.query == "role_name=BedrockUser&account_id=123456789012")
        #expect(AWSCT.header(request, "x-amz-sso_bearer_token") == "sso-access-token-EXAMPLE")
        #expect(resolver.profiles() == [AWSProfileSummary(name: "sso-dev", region: "us-west-2", kind: .sso)], "the session isn't a profile")
        // The SSO cache is only read.
        let cached = try FileManager.default.contentsOfDirectory(atPath: home.files.ssoCache.path)
        #expect(cached == ["0ad374308c5a4e22f723adf10145eafad7c4031c.json"])
    }

    @Test func legacySSOProfile() async throws {
        let home = try AWSCTHome(config: """
            [profile old]
            sso_start_url = https://my-sso-portal.awsapps.com/start
            sso_region = eu-west-1
            sso_account_id = 123456789012
            sso_role_name = BedrockUser
            """)
        defer { home.remove() }
        let clock = AWSCTClock(), http = AWSCTHTTP()
        try home.signIn("https://my-sso-portal.awsapps.com/start", expiresAt: clock.now.addingTimeInterval(3600))
        http.on("portal.sso.eu-west-1.amazonaws.com", .init(status: 200, body: AWSCT.ssoJSON("ASIAOLD", expiration: clock.now.addingTimeInterval(3600))))
        #expect(try await AWSCT.resolver(home, clock: clock, http: http).resolve(profile: "old").credentials.accessKeyId == "ASIAOLD")
    }

    @Test func expiredOrMissingSSOSignInSaysToSignInAgain() async throws {
        let home = try AWSCTHome(config: """
            [profile sso-dev]
            sso_session = my-sso
            sso_account_id = 123456789012
            sso_role_name = BedrockUser
            [sso-session my-sso]
            sso_start_url = https://my-sso-portal.awsapps.com/start
            sso_region = us-east-1
            """)
        defer { home.remove() }
        let clock = AWSCTClock(), http = AWSCTHTTP()
        let resolver = AWSCT.resolver(home, clock: clock, http: http)
        await #expect(throws: AWSCredentialError.ssoNotSignedIn(profile: "sso-dev")) { try await resolver.resolve(profile: "sso-dev") }
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(-60))
        do {
            _ = try await resolver.resolve(profile: "sso-dev")
            Issue.record("resolved")
        } catch let error as AWSCredentialError {
            #expect(error == .ssoExpired(profile: "sso-dev"))
            #expect(error.message(chinese: false) == "Your SSO sign-in for profile sso-dev has expired. Run `aws sso login --profile sso-dev` in Terminal")
            #expect(error.shortMessage(chinese: false) == "SSO sign-in expired: run aws sso login --profile sso-dev")
            #expect(error.fixCommand == "aws sso login --profile sso-dev")
        }
        #expect(http.requests.isEmpty)
        // The portal no longer taking the sign-in says the same.
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(3600))
        http.on("portal.sso.us-east-1.amazonaws.com", .init(status: 401, body: #"{"message":"Session token not found or invalid"}"#,
                                                            headers: ["x-amzn-ErrorType": "UnauthorizedException"]))
        await #expect(throws: AWSCredentialError.ssoExpired(profile: "sso-dev")) { try await resolver.resolve(profile: "sso-dev") }
        #expect(AWSCredentialError.ssoExpired(profile: "my profile").fixCommand == "aws sso login --profile 'my profile'")
    }

    @Test func ssoForbiddenRoleAndMalformedAnswers() async throws {
        let home = try AWSCTHome(config: """
            [profile sso-dev]
            sso_session = my-sso
            sso_account_id = 123456789012
            sso_role_name = BedrockUser
            [sso-session my-sso]
            sso_start_url = https://my-sso-portal.awsapps.com/start
            sso_region = us-east-1
            """)
        defer { home.remove() }
        let clock = AWSCTClock(), http = AWSCTHTTP()
        try home.signIn("my-sso", expiresAt: clock.now.addingTimeInterval(3600))
        http.on("portal.sso.us-east-1.amazonaws.com", .init(status: 403, body: #"{"message":"No access"}"#, headers: ["x-amzn-ErrorType": "ForbiddenException"]),
                .init(status: 200, body: "<html>maintenance</html>"))
        let resolver = AWSCT.resolver(home, clock: clock, http: http)
        await #expect(throws: AWSCredentialError.ssoFailed(profile: "sso-dev", status: 403, message: "ForbiddenException: No access")) {
            try await resolver.resolve(profile: "sso-dev")
        }
        await #expect(throws: AWSCredentialError.invalidResponse(profile: "sso-dev", detail: "no roleCredentials in the SSO response")) {
            try await resolver.resolve(profile: "sso-dev")
        }
        let incomplete = try AWSCTHome(config: "[profile s]\nsso_session = nope\nsso_account_id = 1\nsso_role_name = r\n")
        defer { incomplete.remove() }
        await #expect(throws: AWSCredentialError.invalidProfile(profile: "s", reason: "sso_session nope has no [sso-session nope] section")) {
            try await AWSCT.resolver(incomplete).resolve(profile: "s")
        }
    }

    @Test func listingProfilesRunsAndFetchesNothing() throws {
        let home = try AWSCTHome(config: """
            [default]
            region = us-west-2
            [profile proc]
            credential_process = /usr/local/bin/my-creds --profile dev
            [profile role]
            role_arn = arn:aws:iam::1:role/r
            source_profile = default
            [profile sso]
            sso_session = s
            sso_account_id = 1
            sso_role_name = r
            [sso-session s]
            sso_start_url = https://my-sso-portal.awsapps.com/start
            sso_region = us-east-1
            [services local]
            bedrock-runtime =
              endpoint_url = http://localhost
            """, credentials: "[default]\naws_access_key_id = AKIADEFAULT\naws_secret_access_key = d\n")
        defer { home.remove() }
        let http = AWSCTHTTP(), runner = AWSCTRunner([AWSCT.processJSON("X")])
        let resolver = AWSCT.resolver(home, http: http, runner: runner)
        #expect(resolver.profiles() == [
            AWSProfileSummary(name: "default", region: "us-west-2", kind: .staticKeys),
            AWSProfileSummary(name: "proc", region: nil, kind: .credentialProcess),
            AWSProfileSummary(name: "role", region: nil, kind: .role(source: "default")),
            AWSProfileSummary(name: "sso", region: nil, kind: .sso),
        ])
        for name in ["default", "proc", "role", "sso"] { _ = resolver.status(profile: name) }
        #expect(runner.runs.isEmpty && http.requests.isEmpty)
        // The Assistant's own listing is unchanged: names and regions.
        #expect(AIConfig.awsProfiles(environment: ["AWS_CONFIG_FILE": home.files.config.path,
                                                   "AWS_SHARED_CREDENTIALS_FILE": home.files.credentials.path]).map(\.name)
            == ["default", "proc", "role", "sso"])
    }

    @Test func statusLinesSayTheKindAndWhenTheCredentialsExpire() async throws {
        let home = try AWSCTHome(config: """
            [profile proc]
            credential_process = \(AWSCT.echo)
            [profile role]
            role_arn = arn:aws:iam::1:role/r
            source_profile = sso
            [profile sso]
            sso_session = s
            sso_account_id = 1
            sso_role_name = r
            [sso-session s]
            sso_start_url = https://my-sso-portal.awsapps.com/start
            sso_region = us-east-1
            [profile mfa]
            role_arn = arn:aws:iam::1:role/r
            source_profile = keys
            mfa_serial = arn:aws:iam::1:mfa/me
            """, credentials: "[keys]\naws_access_key_id = AKIAKEYS\naws_secret_access_key = k\n")
        defer { home.remove() }
        let clock = AWSCTClock(), http = AWSCTHTTP()
        let utc = TimeZone(identifier: "UTC")!
        try home.signIn("s", expiresAt: clock.now.addingTimeInterval(4 * 3600))
        http.on("portal.sso.us-east-1.amazonaws.com", .init(status: 200, body: AWSCT.ssoJSON("ASIASSO", expiration: clock.now.addingTimeInterval(3600))))
        http.on("sts.us-east-1.amazonaws.com", .init(status: 200, body: AWSCT.assumeRoleXML("ASIAROLE", expiration: clock.now.addingTimeInterval(5400))))
        let resolver = AWSCT.resolver(home, clock: clock, http: http)
        func line(_ profile: String, chinese: Bool = false) -> String { resolver.status(profile: profile).line(chinese: chinese, now: clock.now, timeZone: utc) }
        #expect(line("keys") == "Static keys: found the keys for this profile")
        #expect(line("keys", chinese: true) == "静态密钥：已找到这个 profile 的密钥")
        #expect(line("proc") == "credential_process: runs when a request needs credentials")
        #expect(line("role") == "Role via sso (signed in until 22:00): assumed when a request needs it", "the source's sign-in")
        #expect(line("sso") == "SSO (signed in until 22:00): credentials fetched when a request needs them")
        #expect(line("mfa").hasPrefix("Role via keys: AWS profile 'mfa': this profile needs an MFA code"))
        #expect(line("nope") == "AWS profile 'nope' not found (~/.aws/config, ~/.aws/credentials)")
        _ = try await resolver.resolve(profile: "role")
        #expect(line("role") == "Role via sso (signed in until 22:00): credentials expire at 19:30")
        #expect(line("sso") == "SSO (signed in until 22:00): credentials expire at 19:00")
        #expect(line("sso", chinese: true) == "SSO（登录有效至 22:00）：凭证 19:00 到期")
        // Signed out meanwhile: the cached credentials still work; the line says what to run.
        try home.signIn("s", expiresAt: clock.now.addingTimeInterval(-1))
        let status = resolver.status(profile: "role")
        #expect(status.isReady && status.fixCommand == "aws sso login --profile sso")
        #expect(line("role") == "Role via sso: credentials expire at 19:30; Your SSO sign-in for profile sso has expired. Run `aws sso login --profile sso` in Terminal")
        clock.advance(2 * 3600)
        #expect(!resolver.status(profile: "role").isReady)
        #expect(line("sso") == "SSO: Your SSO sign-in for profile sso has expired. Run `aws sso login --profile sso` in Terminal")
        #expect(AWSProfileStatus.time(clock.now.addingTimeInterval(86400), now: clock.now, language: "en", timeZone: utc) == "Oct 17 20:00")
    }
}

// MARK: - Bedrock: refreshed and sent again once when AWS says the credentials expired

final class AWSRetryStub: URLProtocol, @unchecked Sendable {
    struct Answer: Sendable { var status: Int; var headers: [String: String]; var body: Data }
    private static let state = OSAllocatedUnfairLock(initialState: (answers: [String: [Answer]](), keys: [String: [String]]()))

    static func on(_ host: String, _ answers: [Answer]) { state.withLock { $0.answers[host] = answers } }
    /// The access key ID each request to `host` was signed with.
    static func keys(_ host: String) -> [String] { state.withLock { $0.keys[host] ?? [] } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AWSRetryStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let key = request.value(forHTTPHeaderField: "Authorization")?.components(separatedBy: "Credential=").last?
            .split(separator: "/").first.map(String.init) ?? ""
        let answer = Self.state.withLock { state -> Answer? in
            state.keys[host, default: []].append(key)
            guard var queue = state.answers[host], !queue.isEmpty else { return nil }
            let first = queue.removeFirst()
            if !queue.isEmpty { state.answers[host] = queue }
            return first
        }
        guard let answer, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct BedrockCredentialRetryTests {
    static func expired(_ type: String = "ExpiredTokenException", status: Int = 403,
                        message: String = "The security token included in the request is expired") -> AWSRetryStub.Answer {
        .init(status: status, headers: ["x-amzn-ErrorType": type],
              body: Data(#"{"message":"\#(message)"}"#.utf8))
    }

    static func ok() throws -> AWSRetryStub.Answer {
        .init(status: 200, headers: ["Content-Type": "application/vnd.amazon.eventstream"], body: Data(try fixture("bedrock-converse-stream")))
    }

    func converter(region: String, resolver: AWSCredentialResolver) -> Converter {
        var config = Config.default
        config.region = region
        config.awsProfile = "dev"
        let fixed = config
        return Converter(client: BedrockClient(session: AWSRetryStub.session()), loadConfig: { fixed },
                         loadCredentials: { try await resolver.resolve(profile: $0) })
    }

    func processResolver() throws -> (AWSCredentialResolver, AWSCTRunner, AWSCTHome) {
        let home = try AWSCTHome(config: "[profile dev]\ncredential_process = my-creds\n")
        let runner = AWSCTRunner([AWSCT.processJSON("ASIAFIRST"), AWSCT.processJSON("ASIASECOND"), AWSCT.processJSON("ASIATHIRD")])
        return (AWSCT.resolver(home, runner: runner), runner, home)
    }

    @Test func expiredTokenRefreshesAndRetriesOnce() async throws {
        let region = "us-retry-1", host = "bedrock-runtime.us-retry-1.amazonaws.com"
        AWSRetryStub.on(host, [Self.expired(), try Self.ok()])
        let (resolver, runner, home) = try processResolver()
        defer { home.remove() }
        var final: ConversionUpdate?
        for try await update in converter(region: region, resolver: resolver).convert("我今天有点不舒服") { final = update }
        #expect(final?.isFinal == true && final?.result.versions.isEmpty == false)
        #expect(AWSRetryStub.keys(host) == ["ASIAFIRST", "ASIASECOND"])
        #expect(runner.runs.count == 2)
    }

    @Test func onlyOnce() async throws {
        let region = "us-retry-2", host = "bedrock-runtime.us-retry-2.amazonaws.com"
        AWSRetryStub.on(host, [Self.expired("UnrecognizedClientException", message: "The security token included in the request is invalid."),
                               Self.expired(), try Self.ok()])
        let (resolver, runner, home) = try processResolver()
        defer { home.remove() }
        await #expect(throws: BedrockError.http(status: 403, type: "ExpiredTokenException", message: "The security token included in the request is expired")) {
            for try await _ in converter(region: region, resolver: resolver).convert("我今天有点不舒服") {}
        }
        #expect(AWSRetryStub.keys(host) == ["ASIAFIRST", "ASIASECOND"] && runner.runs.count == 2)
    }

    @Test func otherErrorsAreNotRetried() async throws {
        let region = "us-retry-3", host = "bedrock-runtime.us-retry-3.amazonaws.com"
        AWSRetryStub.on(host, [Self.expired("AccessDeniedException", message: "You don't have access to the model"), try Self.ok()])
        let (resolver, runner, home) = try processResolver()
        defer { home.remove() }
        await #expect(throws: BedrockError.self) {
            for try await _ in converter(region: region, resolver: resolver).convert("我今天有点不舒服") {}
        }
        #expect(AWSRetryStub.keys(host) == ["ASIAFIRST"] && runner.runs.count == 1)
    }

    @Test func aLoaderWithoutARefreshIsAskedAgain() async throws {
        let region = "us-retry-4", host = "bedrock-runtime.us-retry-4.amazonaws.com"
        AWSRetryStub.on(host, [Self.expired("InvalidSignatureException", message: "The security token included in the request is expired"),
                               try Self.ok()])
        let calls = OSAllocatedUnfairLock(initialState: 0)
        var config = Config.default
        config.region = region
        let fixed = config
        let converter = Converter(client: BedrockClient(session: AWSRetryStub.session()), loadConfig: { fixed }, loadCredentials: { _ in
            let n = calls.withLock { $0 += 1; return $0 }
            return AWSSharedConfig.Resolved(credentials: AWSCredentials(accessKeyId: "AKIDCALL\(n)", secretAccessKey: "s"), region: nil)
        })
        for try await _ in converter.convert("你好") {}
        #expect(AWSRetryStub.keys(host) == ["AKIDCALL1", "AKIDCALL2"])
    }

    @Test(arguments: [
        (BedrockError.http(status: 403, type: "ExpiredTokenException", message: "x"), true),
        (.http(status: 400, type: "UnrecognizedClientException", message: "The security token included in the request is invalid."), true),
        (.http(status: 403, type: "InvalidSignatureException", message: "Signature expired: 20261016T180000Z is now earlier than 20261016T181000Z"), false),
        (.http(status: 403, type: "InvalidSignatureException", message: "The security token included in the request is expired"), true),
        (.http(status: 403, type: nil, message: "The provided token has expired."), true),
        (.http(status: 403, type: "AccessDeniedException", message: "You don't have access to the model with the specified model ID."), false),
        (.http(status: 400, type: "ValidationException", message: "The provided model identifier is invalid."), false),
        (.stream(type: "ExpiredTokenException", message: "x"), true),
        (.invalidResponse("x"), false),
    ] as [(BedrockError, Bool)])
    func whichErrorsMeanExpiredCredentials(error: BedrockError, expired: Bool) {
        #expect(error.isExpiredCredentials == expired)
    }
}

// MARK: - The real program runner

struct AWSProcessRunnerTests {
    @Test func runsWithoutAShellStdinClosedAndOutputsApart() async throws {
        let home = try AWSCTHome()
        defer { home.remove() }
        let script = try home.script("fake-creds", """
            input=$(cat)
            echo "stdin had ${#input} bytes; args: $1|$2; dir: $(pwd)" >&2
            printf '{"Version": 1, "AccessKeyId": "ASIAFAKE", "SecretAccessKey": "fake-secret", "Expiration": "2099-01-01T00:00:00Z"}'
            """)
        let result = try await AWSProcessRunner.run(AWSProcessRequest(arguments: [script, "a b", "$HOME"], environment: ["PATH": "/usr/bin:/bin"],
                                                                      directory: home.root, timeout: 10))
        #expect(result.status == 0)
        let said = String(decoding: result.standardError, as: UTF8.self).trimmingCharacters(in: .newlines)
        #expect(said.hasPrefix("stdin had 0 bytes; args: a b|$HOME; dir: /") && said.hasSuffix("/" + home.root.lastPathComponent), "\(said)")
        #expect(try AWSCredentialProcess.parse(result.standardOutput).credentials.accessKeyId == "ASIAFAKE")
    }

    @Test func stopsAfterTheTimeoutAndSaysWhenMissing() async throws {
        let home = try AWSCTHome()
        defer { home.remove() }
        let script = try home.script("slow-creds", "sleep \(Timing.longSleep)")
        let started = Date()
        await #expect(throws: AWSProcessError.timedOut(0.5)) {
            try await AWSProcessRunner.run(AWSProcessRequest(arguments: [script], environment: ["PATH": "/usr/bin:/bin"], directory: home.root, timeout: 0.5))
        }
        #expect(Date().timeIntervalSince(started) < Timing.wellBeforeLongSleep, "stopped long before the script's minute")
        await #expect(throws: AWSProcessError.notFound("no-such-creds-program")) {
            try await AWSProcessRunner.run(AWSProcessRequest(arguments: ["no-such-creds-program"], environment: ["PATH": "/usr/bin:/bin"],
                                                             directory: home.root, timeout: 5))
        }
    }

    @Test func aFakeCredentialProcessEndToEnd() async throws {
        let home = try AWSCTHome()
        defer { home.remove() }
        let script = try home.script("my-creds", #"""
            [ "$1" = "--profile" ] && [ "$2" = "dev" ] || { echo "bad args" >&2; exit 2; }
            printf '{"Version": 1, "AccessKeyId": "ASIAFAKE", "SecretAccessKey": "fake-secret", "SessionToken": "fake-token"}'
            """#)
        let failing = try home.script("failing-creds", "echo 'token AKIAIOSFODNN7EXAMPLE rejected' >&2; exit 7")
        try home.write(config: "[profile dev]\ncredential_process = \(script) --profile dev\n[profile bad]\ncredential_process = \(failing)\n", credentials: "")
        let resolver = AWSCredentialResolver(context: AWSCredentialContext(environment: ["HOME": home.root.path]))
        let resolved = try await resolver.resolve(profile: "dev")
        #expect(resolved.credentials == AWSCredentials(accessKeyId: "ASIAFAKE", secretAccessKey: "fake-secret", sessionToken: "fake-token"))
        await #expect(throws: AWSCredentialError.processFailed(profile: "bad", program: "failing-creds", status: 7, stderr: "token [KEY] rejected")) {
            try await resolver.resolve(profile: "bad")
        }
        let slow = try home.script("slow-creds", "sleep 30")
        try home.write(config: "[profile slow]\ncredential_process = \(slow)\n", credentials: "")
        let impatient = AWSCredentialResolver(context: AWSCredentialContext(environment: ["HOME": home.root.path], processTimeout: 0.5))
        await #expect(throws: AWSCredentialError.processTimedOut(profile: "slow", program: "slow-creds", seconds: 1)) {
            try await impatient.resolve(profile: "slow")
        }
    }
}

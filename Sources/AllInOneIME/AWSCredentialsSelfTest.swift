import AllInOneIMECore
import AppKit
import os

/// Answers Bedrock requests in the self-test's AWS section: "expired" first, then a plain refusal; records the access
/// key ID each was signed with.
final class AWSSelfTestBedrockStub: URLProtocol, @unchecked Sendable {
    private static let state = OSAllocatedUnfairLock(initialState: [String]())

    static var keys: [String] { state.withLock { $0 } }
    static func reset() { state.withLock { $0 = [] } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AWSSelfTestBedrockStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.value(forHTTPHeaderField: "Authorization")?.components(separatedBy: "Credential=").last?
            .split(separator: "/").first.map(String.init) ?? ""
        let count = Self.state.withLock { $0.append(key); return $0.count }
        let (type, message) = count == 1 ? ("ExpiredTokenException", "The security token included in the request is expired")
            : ("ValidationException", "The self-test's stand-in answers no further")
        let response = HTTPURLResponse(url: request.url!, statusCode: count == 1 ? 403 : 400, httpVersion: "HTTP/1.1",
                                       headerFields: ["x-amzn-ErrorType": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"message":"\#(message)"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension SelfTest {
    /// Bedrock's AWS credentials with made-up profiles in a temporary HOME (named by AWS_CONFIG_FILE and
    /// AWS_SHARED_CREDENTIALS_FILE), a fake `credential_process` script run for real, STS and the SSO portal answered by a
    /// stand-in: every kind resolves, is cached and refreshed; MFA and an expired SSO sign-in say what to do; Bedrock
    /// refused as expired is retried once with fresh credentials; Settings' status line and its checks say the same. The
    /// user's ~/.aws is never read and their programs never run.
    static func testAWSCredentials(snapshotDirectory: URL) {
        section("AWS credentials: every kind of profile (fake profiles in a temporary HOME)")
        let home = snapshotDirectory.appendingPathComponent("aws-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try? FileManager.default.createDirectory(at: home.appendingPathComponent(".aws/sso/cache"), withIntermediateDirectories: true)
        let config = home.appendingPathComponent("aws-config"), credentials = home.appendingPathComponent("aws-credentials")
        let runs = home.appendingPathComponent("runs.log")
        // The fake credential process: counts its runs, prints credentials good for an hour.
        let script = home.appendingPathComponent("my-creds")
        let expires = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let body = """
            #!/bin/sh
            echo run >> \(AWSCredentialError.shellWord(runs.path))
            [ "$1" = "--profile" ] && [ "$2" = "dev" ] || { echo "unexpected arguments" >&2; exit 2; }
            printf '{"Version": 1, "AccessKeyId": "ASIASELFTESTPROC%s", "SecretAccessKey": "selftest-secret", "SessionToken": "selftest-token", "Expiration": "\(expires)"}' "$(wc -l < \(AWSCredentialError.shellWord(runs.path)) | tr -d ' ')"
            """
        try? Data(body.utf8).write(to: script)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        try? Data("""
            [profile tools]
            credential_process = \(AWSCredentialError.shellWord(script.path)) --profile dev
            region = us-west-2
            [profile dev]
            role_arn = arn:aws:iam::123456789012:role/BedrockUser
            source_profile = tools
            region = eu-west-1
            [profile mfa]
            role_arn = arn:aws:iam::123456789012:role/BedrockUser
            source_profile = tools
            mfa_serial = arn:aws:iam::123456789012:mfa/me
            [profile sso-dev]
            sso_session = my-sso
            sso_account_id = 123456789012
            sso_role_name = BedrockUser
            [profile sso-old]
            sso_session = old-sso
            sso_account_id = 123456789012
            sso_role_name = BedrockUser
            [sso-session my-sso]
            sso_start_url = https://my-sso-portal.awsapps.com/start
            sso_region = us-east-1
            [sso-session old-sso]
            sso_start_url = https://my-old-portal.awsapps.com/start
            sso_region = us-east-1
            """.utf8).write(to: config)
        try? Data("[keys]\naws_access_key_id = AKIASELFTESTKEYS\naws_secret_access_key = selftest-secret\n".utf8).write(to: credentials)
        let iso = ISO8601DateFormatter()
        for (session, until) in [("my-sso", Date().addingTimeInterval(3 * 3600)), ("old-sso", Date().addingTimeInterval(-60))] {
            try? Data(#"{"accessToken": "selftest-sso-token", "expiresAt": "\#(iso.string(from: until))"}"#.utf8)
                .write(to: AWSSSO.cacheFile(key: session, in: home.appendingPathComponent(".aws/sso/cache")))
        }
        // STS and the SSO portal: a stand-in that records what was sent.
        let sent = OSAllocatedUnfairLock(initialState: [URLRequest]())
        let send: AWSCredentialContext.Send = { request in
            sent.withLock { $0.append(request) }
            let host = request.url?.host ?? "", soon = Date().addingTimeInterval(3000)
            let body = host.hasPrefix("sts.")
                ? "<AssumeRoleResponse><AssumeRoleResult><Credentials><AccessKeyId>ASIASELFTESTROLE</AccessKeyId><SecretAccessKey>s</SecretAccessKey>"
                    + "<SessionToken>t</SessionToken><Expiration>\(ISO8601DateFormatter().string(from: soon))</Expiration></Credentials></AssumeRoleResult></AssumeRoleResponse>"
                : #"{"roleCredentials": {"accessKeyId": "ASIASELFTESTSSO", "secretAccessKey": "s", "sessionToken": "t", "expiration": \#(Int64(soon.timeIntervalSince1970 * 1000))}}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!)
        }
        let environment = ["HOME": home.path, "AWS_CONFIG_FILE": config.path, "AWS_SHARED_CREDENTIALS_FILE": credentials.path]
        // The program runs with the login shell's PATH, as in the input method.
        var processEnvironment = ShellEnvironment.current
        processEnvironment["HOME"] = home.path
        let resolver = AWSCredentialResolver(context: AWSCredentialContext(environment: environment, processEnvironment: processEnvironment,
                                                                           send: send))
        func resolve(_ profile: String) -> Result<AWSSharedConfig.Resolved, Error> {
            var result: Result<AWSSharedConfig.Resolved, Error>?
            Task { result = await Result { try await resolver.resolve(profile: profile) } }
            _ = pump(timeout: 15) { result != nil }
            return result ?? .failure(CancellationError())
        }
        func runCount() -> Int { ((try? String(contentsOf: runs, encoding: .utf8)) ?? "").split(separator: "\n").count }

        check(resolver.profiles().map(\.name) == ["dev", "keys", "mfa", "sso-dev", "sso-old", "tools"] && runCount() == 0 && sent.withLock(\.isEmpty),
              "the profiles are listed with their kinds, nothing run or fetched (\(resolver.profiles().map { "\($0.name): \($0.kind.label(chinese: false))" }))")
        let keys = try? resolve("keys").get()
        check(keys?.credentials.accessKeyId == "AKIASELFTESTKEYS" && keys?.kind == .staticKeys, "static keys from AWS_SHARED_CREDENTIALS_FILE")
        let tools = try? resolve("tools").get()
        check(tools?.credentials.accessKeyId == "ASIASELFTESTPROC1" && tools?.kind == .credentialProcess && tools?.expiration != nil,
              "credential_process runs the fake script with the login shell's PATH (\(tools?.credentials.description ?? "failed"))")
        _ = resolve("tools")
        check(runCount() == 1, "credential_process: cached until 5 minutes before it expires (\(runCount()) run)")
        let dev = try? resolve("dev").get()
        let assume = sent.withLock { $0.first { $0.url?.host == "sts.eu-west-1.amazonaws.com" } }
        check(dev?.credentials.accessKeyId == "ASIASELFTESTROLE" && dev?.kind == .role(source: "tools")
              && assume?.value(forHTTPHeaderField: "Authorization")?.contains("Credential=ASIASELFTESTPROC1/") == true && runCount() == 1,
              "role_arn: AssumeRole at the regional endpoint, signed with the source profile's credentials")
        if case let .failure(error) = resolve("mfa") {
            check(error as? AWSCredentialError == .needsMFA(profile: "mfa") && UIText.describe(error).contains("MFA"), "mfa_serial: \(UIText.describe(error))")
        } else {
            check(false, "mfa_serial was resolved")
        }
        let sso = try? resolve("sso-dev").get()
        let portal = sent.withLock { $0.first { $0.url?.host == "portal.sso.us-east-1.amazonaws.com" } }
        check(sso?.credentials.accessKeyId == "ASIASELFTESTSSO" && portal?.value(forHTTPHeaderField: "x-amz-sso_bearer_token") == "selftest-sso-token",
              "SSO: the AWS CLI's cached sign-in, GetRoleCredentials")
        let fetchesBefore = sent.withLock(\.count)
        if case let .failure(error) = resolve("sso-old") {
            check(error as? AWSCredentialError == .ssoExpired(profile: "sso-old") && sent.withLock(\.count) == fetchesBefore,
                  "an expired SSO sign-in says what to run: \(UIText.describe(error))")
        } else {
            check(false, "an expired SSO sign-in was used")
        }

        // Bedrock refused as expired: the credentials fetched again and the request sent again, once.
        AWSSelfTestBedrockStub.reset()
        var bedrock = Config.default
        bedrock.provider = .bedrock
        bedrock.awsProfile = "tools"
        bedrock.region = "us-west-2"
        let fixed = bedrock
        let converter = Converter(client: BedrockClient(session: AWSSelfTestBedrockStub.session()), loadConfig: { fixed },
                                  loadCredentials: { try await resolver.resolve(profile: $0) })
        var outcome: Error??
        Task {
            do {
                for try await _ in converter.convert("selftest") {}
                outcome = .some(nil)
            } catch {
                outcome = .some(error)
            }
        }
        _ = pump(timeout: 15) { outcome != nil }
        check(AWSSelfTestBedrockStub.keys == ["ASIASELFTESTPROC1", "ASIASELFTESTPROC2"] && runCount() == 2
              && (outcome ?? nil).map { UIText.describe($0).contains("ValidationException") } == true,
              "Bedrock's ExpiredTokenException: refreshed and retried once (\(AWSSelfTestBedrockStub.keys))")

        // Settings → AI Provider: the kind next to each profile, the status line, the command for an expired sign-in.
        let model = SettingsModel(configURL: home.appendingPathComponent("config.json"), persists: false)
        model.aws.resolver = resolver
        for profile in ["sso-old", "dev", "tools"] {
            model.config.awsProfile = profile
            model.aws.load(profile: profile)
        }
        let english = UIText.choice
        UIText.choice = .english
        defer { UIText.choice = english }
        check(model.aws.label("dev") == "dev  —  Role via tools" && model.aws.label("sso-dev") == "sso-dev  —  SSO",
              "the profile picker shows each profile's kind (\(model.aws.label("dev")))")
        check(model.credentialStatus.hasPrefix("credential_process: credentials expire at ") && model.credentialsReady,
              "the status line: \(model.credentialStatus)")
        model.config.awsProfile = "sso-old"
        model.aws.load(profile: "sso-old")
        check(model.aws.status?.fixCommand == "aws sso login --profile sso-old" && !model.credentialsReady
              && model.credentialStatus.contains("Run `aws sso login --profile sso-old` in Terminal"),
              "an expired SSO sign-in: \(model.credentialStatus)")

        // Settings → Assistant's checks: the kind and expiry, or the expired sign-in with its command to copy.
        var facts = Doctor.Facts()
        var doctorConfig = bedrock
        doctorConfig.awsProfile = "sso-old"
        facts.config = doctorConfig
        let status = resolver.status(profile: "sso-old")
        facts.awsStatus = status
        facts.awsProfile = .failure(Doctor.ProbeError(status.problem?.message(chinese: false) ?? ""))
        let row = Doctor.findings(facts, chinese: false).first { $0.area == .provider }
        check(row?.status == .problem && row?.fix == .copyCommand("aws sso login --profile sso-old")
              && row?.detail?.contains("Your SSO sign-in for profile sso-old has expired") == true,
              "the checks: \(row?.text(chinese: false) ?? "no row")")
        doctorConfig.awsProfile = "dev"
        facts.config = doctorConfig
        facts.awsStatus = resolver.status(profile: "dev")
        facts.awsProfile = .success("eu-west-1")
        let ok = Doctor.findings(facts, chinese: false).first { $0.area == .provider }
        check(ok?.status == .ok && ok?.detail?.contains("(Role via tools)") == true && ok?.detail?.contains("credentials expire at") == true,
              "the checks: \(ok?.text(chinese: false) ?? "no row")")
        check(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".aws/credentials").path),
              "nothing was written to the AWS folder (credentials stay in memory)")
    }
}

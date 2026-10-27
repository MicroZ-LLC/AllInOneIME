import AllInOneIMECore
import AllInOneIMEMac
import AppKit

extension SelfTest {
    /// Settings with made-up AWS profiles in a temporary HOME (named by AWS_CONFIG_FILE), a fake `credential_process`
    /// script run for real and STS answered by a stand-in: the kind next to each profile, the status line, the command for
    /// an expired SSO sign-in, and Settings → Assistant's checks saying the same. The user's ~/.aws is never read and their
    /// programs never run. (How every kind of profile resolves, is cached and refreshed, and Bedrock's retry with fresh
    /// credentials: AWSCredentialsTests and AWSCredentialsAcceptanceTests.)
    static func testAWSCredentials(snapshotDirectory: URL) {
        section("AWS credentials in Settings (fake profiles in a temporary HOME)")
        let home = snapshotDirectory.appendingPathComponent("aws-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try? FileManager.default.createDirectory(at: home.appendingPathComponent(".aws/sso/cache"), withIntermediateDirectories: true)
        let config = home.appendingPathComponent("aws-config")
        // The fake credential process: prints credentials good for an hour.
        let script = home.appendingPathComponent("my-creds")
        let expires = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let body = """
            #!/bin/sh
            [ "$1" = "--profile" ] && [ "$2" = "dev" ] || { echo "unexpected arguments" >&2; exit 2; }
            printf '{"Version": 1, "AccessKeyId": "ASIASELFTESTPROC", "SecretAccessKey": "selftest-secret", "SessionToken": "selftest-token", "Expiration": "\(expires)"}'
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
        try? Data(#"{"accessToken": "selftest-sso-token", "expiresAt": "\#(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60)))"}"#.utf8)
            .write(to: AWSSSO.cacheFile(key: "old-sso", in: home.appendingPathComponent(".aws/sso/cache")))
        // STS: a stand-in.
        let send: AWSCredentialContext.Send = { request in
            let soon = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3000))
            let body = "<AssumeRoleResponse><AssumeRoleResult><Credentials><AccessKeyId>ASIASELFTESTROLE</AccessKeyId><SecretAccessKey>s</SecretAccessKey>"
                + "<SessionToken>t</SessionToken><Expiration>\(soon)</Expiration></Credentials></AssumeRoleResult></AssumeRoleResponse>"
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!)
        }
        let environment = ["HOME": home.path, "AWS_CONFIG_FILE": config.path]
        // The program runs with the login shell's PATH, as in the input method.
        var processEnvironment = ShellEnvironment.current
        processEnvironment["HOME"] = home.path
        let resolver = AWSCredentialResolver(context: AWSCredentialContext(environment: environment, processEnvironment: processEnvironment,
                                                                           send: send))
        // Fetched first: the status lines say when the credentials expire.
        for profile in ["tools", "dev"] {
            var done = false
            Task {
                _ = try? await resolver.resolve(profile: profile)
                done = true
            }
            _ = pump(timeout: 15) { done }
        }

        // Settings → AI Provider: the kind next to each profile, the status line, the command for an expired sign-in.
        let model = SettingsModel(configURL: home.appendingPathComponent("config.json"), persists: false)
        model.aws.resolver = resolver
        for profile in ["sso-old", "dev", "tools"] {
            model.config.awsProfile = profile
            model.aws.load(profile: profile)
        }
        let english = UIText.choice
        UIText.choice = "en"
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
        var doctorConfig = Config.default
        doctorConfig.provider = .bedrock
        doctorConfig.region = "us-west-2"
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

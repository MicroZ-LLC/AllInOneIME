import Foundation
import Testing
@testable import AllInOneIMECore

/// #64: with `AWS_CONFIG_FILE` or `AWS_SHARED_CREDENTIALS_FILE` exported in the login shell (.zshrc), Settings → AI's
/// AWS Profile picker lists that file's profiles and Bedrock's requests use them, while Settings → Assistant reads
/// `~/.aws` instead: it says no profile is found, or refuses the one asked for ("no such profile in ~/.aws"). Expected:
/// the Assistant lists and accepts the same profiles as the picker, from the files named in the shell (README: "the
/// files … named in your shell"). The login environment is given through `Platform.override`, the files are in a
/// temporary folder; the input method's own environment names no AWS file (as launchd starts it).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AWS_CONFIG_FILE"] == nil
                    && ProcessInfo.processInfo.environment["AWS_SHARED_CREDENTIALS_FILE"] == nil,
                "the input method's own environment names no AWS file"))
struct Issue64Tests {
    /// No programs, and `variables` as the user's login shell's.
    struct LoginShell: ProcessLauncher {
        var variables: [String: String]
        var canLaunch: Bool { false }
        var environment: [String: String] { variables }
        var loginEnvironment: [String: String] { variables }
        func isRunnable(_ program: URL) -> Bool { false }
        func launch(_ spec: LaunchSpec) throws -> any LaunchedProcess { throw ProcessLaunchError.unsupported }
    }

    /// Names no one has in their own ~/.aws, so the files given here are the only place they can come from.
    static let work = "work-issue64", personal = "personal-issue64"

    /// The AWS files in a folder of their own, outside ~/.aws: a config file with `[profile work-issue64]` and a
    /// credentials file with `[personal-issue64]`.
    struct Files {
        let folder: URL
        var config: URL { folder.appendingPathComponent("aws-config") }
        var credentials: URL { folder.appendingPathComponent("aws-credentials") }

        init() throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("issue64-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("[default]\nregion = us-east-1\n\n[profile \(Issue64Tests.work)]\nregion = eu-west-1\n".utf8).write(to: config)
            try Data("[\(Issue64Tests.personal)]\naws_access_key_id = AKIAEXAMPLEISSUE64\naws_secret_access_key = sample-secret\n".utf8)
                .write(to: credentials)
        }

        func remove() { try? FileManager.default.removeItem(at: folder) }
    }

    /// Whether `listed` has the profile `name`. (The listing itself is never printed: today it is this Mac's ~/.aws.)
    static func lists(_ listed: [AIConfig.AWSProfile], _ name: String) -> Bool { listed.contains { $0.name == name } }

    /// `body` run with `login` as the login shell's variables.
    static func inLoginShell<T>(_ login: [String: String], _ body: () throws -> T) rethrows -> T {
        var platform = Platform.current
        platform.processes = LoginShell(variables: login)
        return try Platform.$override.withValue(platform) { try body() }
    }

    /// The issue's own case: `AWS_CONFIG_FILE` in the login shell. The Assistant's listing has its `[profile work]`.
    @Test func profilesOfTheConfigFileNamedInTheShellAreListed() throws {
        let files = try Files()
        defer { files.remove() }
        let listed = Self.inLoginShell(["AWS_CONFIG_FILE": files.config.path]) { AIConfig.awsProfiles() }
        let listsWork = Self.lists(listed, Self.work)
        #expect(listsWork, "the profile in the config file named in the shell isn't listed")
        #expect(listed.first { $0.name == Self.work }?.region == "eu-west-1")
    }

    /// `AWS_SHARED_CREDENTIALS_FILE` in the login shell: the profile in that credentials file is listed.
    @Test func profilesOfTheCredentialsFileNamedInTheShellAreListed() throws {
        let files = try Files()
        defer { files.remove() }
        let listed = Self.inLoginShell(["AWS_SHARED_CREDENTIALS_FILE": files.credentials.path]) { AIConfig.awsProfiles() }
        let listsPersonal = Self.lists(listed, Self.personal)
        #expect(listsPersonal, "the profile in the credentials file named in the shell isn't listed")
    }

    /// Both files named in the shell: the Assistant lists what the AWS Profile picker lists (the live resolver's
    /// profiles, which Bedrock's requests use), no more and no fewer.
    @Test func theAssistantListsWhatThePickerLists() throws {
        let files = try Files()
        defer { files.remove() }
        let login = ["AWS_CONFIG_FILE": files.config.path, "AWS_SHARED_CREDENTIALS_FILE": files.credentials.path]
        let (assistant, picker) = Self.inLoginShell(login) {
            (AIConfig.awsProfiles(), AWSCredentialResolver(context: .live).profiles())
        }
        let expected = [AIConfig.AWSProfile(name: "default", region: "us-east-1"), AIConfig.AWSProfile(name: Self.personal, region: nil),
                        AIConfig.AWSProfile(name: Self.work, region: "eu-west-1")]
        #expect(picker.map { AIConfig.AWSProfile(name: $0.name, region: $0.region) } == expected)
        let sameAsPicker = assistant == expected
        #expect(sameAsPicker, "the Assistant doesn't list the picker's profiles, with their regions")
    }

    /// "Use my work AWS profile" answered with the profile from the file named in the shell: the Assistant's check
    /// (against the profiles it lists, as Settings → Assistant gives them) offers the change, not "no such profile".
    @Test func theProfileFromTheShellsFileIsNotRefused() throws {
        let files = try Files()
        defer { files.remove() }
        var config = Config.default
        config.provider = .bedrock
        config.awsProfile = "default"
        let env = AIConfig.Environment(awsProfiles: { AIConfig.awsProfiles().map(\.name) }, typedText: "use my work AWS profile")
        let answer = #"{"changes":[{"key":"awsProfile","value":"\#(Self.work)"}]}"#
        let preview = try Self.inLoginShell(["AWS_CONFIG_FILE": files.config.path]) {
            AIConfig.preview(try AIConfig.parse(answer), config: config, environment: env)
        }
        #expect(try preview.get().edits == [.awsProfile(Self.work)])
    }
}

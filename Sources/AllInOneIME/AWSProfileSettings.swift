import AllInOneIMECore
import AppKit
import SwiftUI

/// Settings → AI Provider (Bedrock): every AWS profile with its kind, and the chosen one's status line (its kind, when
/// its credentials expire, what's wrong and the command that fixes it). Read off the main thread (the files, the login
/// shell's variables, the SSO sign-in's end); nothing is run or fetched here: Test Connection does that.
@MainActor
final class AWSProfileModel: ObservableObject {
    @Published private(set) var summaries: [AWSProfileSummary] = []
    @Published private(set) var status: AWSProfileStatus?
    /// The input method's; the README images give a sample one.
    var resolver = AWSCredentialResolver.shared
    private var generation = 0

    /// Reads them again in the background (the window opening, another profile picked, Test Connection done).
    func refresh(profile: String) {
        generation += 1
        let resolver = resolver, current = generation
        Task.detached(priority: .userInitiated) {
            let summaries = resolver.profiles(), status = resolver.status(profile: profile)
            await MainActor.run { [weak self] in
                guard let self, self.generation == current else { return }
                self.summaries = summaries
                self.status = status
            }
        }
    }

    /// Reads them again and waits for that (the status row's loop).
    func reread(profile: String) async {
        generation += 1
        let resolver = resolver, current = generation
        let (summaries, status) = await Task.detached(priority: .utility) { (resolver.profiles(), resolver.status(profile: profile)) }.value
        guard generation == current else { return }
        self.summaries = summaries
        self.status = status
    }

    /// Reads them now (the self-test, the README images).
    func load(profile: String) {
        generation += 1
        summaries = resolver.profiles()
        status = resolver.status(profile: profile)
    }

    /// The status read for `profile` (nil: not read yet, or for another).
    func status(for profile: String) -> AWSProfileStatus? {
        let name = profile.trimmingCharacters(in: .whitespaces)
        guard let status, status.profile == (name.isEmpty ? "default" : name) else { return nil }
        return status
    }

    /// "dev — Role via base".
    func label(_ name: String, shownAs: String? = nil) -> String {
        guard let kind = summaries.first(where: { $0.name == name })?.kind else { return shownAs ?? name }
        return (shownAs ?? name) + "  —  " + kind.label(language: UIText.language)
    }

    /// The status line, in the window's language.
    func line(profile: String) -> String {
        guard let status = status(for: profile) else { return tr("正在读取 profile…", "Reading the profile…") }
        return status.line(language: UIText.language)
    }
}

/// The AWS Profile picker: every profile, its kind next to its name.
struct AWSProfilePicker: View {
    @Binding var selection: String
    let names: [String]
    /// Screenshots: the name shown for the selected one.
    let shownAs: String?
    @ObservedObject var aws: AWSProfileModel

    /// The profiles as the resolver lists them once read (the files the environment names), the chosen one always.
    private var shownNames: [String] {
        var list = aws.summaries.isEmpty ? names : aws.summaries.map(\.name)
        if !list.contains(selection) { list.insert(selection, at: 0) }
        return list
    }

    var body: some View {
        Picker("AWS Profile", selection: $selection) {
            ForEach(shownNames, id: \.self) { name in
                Text(aws.label(name, shownAs: name == selection ? shownAs : nil)).tag(name)
            }
        }
    }
}

/// Under the region: the profile's status line, and for an SSO sign-in to renew, its command with Copy Command and Open
/// in Terminal.
struct AWSProfileStatusRow: View {
    let profile: String
    @ObservedObject var aws: AWSProfileModel
    /// Screenshots: the name shown in place of the profile's own.
    var shownAs: String?

    var body: some View {
        let status = aws.status(for: profile)
        VStack(alignment: .leading, spacing: 4) {
            Text(shown(aws.line(profile: profile)))
                .font(.caption)
                .foregroundStyle(status.map { $0.isReady && $0.problem == nil && $0.lastError == nil } ?? true ? Color.secondary : Color.orange)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let command = status?.fixCommand {
                HStack(spacing: 8) {
                    Text(shown(command)).font(.caption.monospaced()).textSelection(.enabled)
                    Button(tr("复制命令", "Copy Command")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                    .controlSize(.small)
                    Button(tr("在终端里打开", "Open in Terminal")) { AWSProfileStatusRow.openInTerminal(command) }
                        .controlSize(.small)
                }
            }
        }
        // Read when shown and again at each boundary (credentials expiring, a sign-in ending, at least every minute), so the
        // line never goes stale while the window stays open; coming back to the window reads it too (`didBecomeKey`).
        .task(id: profile) {
            while !Task.isCancelled {
                await aws.reread(profile: profile)
                let wait = aws.status(for: profile)?.secondsUntilChange() ?? 60
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    private func shown(_ text: String) -> String {
        guard let shownAs, shownAs != profile else { return text }
        return text.replacingOccurrences(of: profile, with: shownAs)
    }

    /// The command in a new Terminal window, as `@agent` opens one (`TerminalLauncher`): its words as they are, never
    /// through a shell.
    static func openInTerminal(_ command: String) {
        guard let arguments = try? AWSCredentialProcess.arguments(command) else { return }
        do {
            try TerminalLauncher.launch(arguments, name: "aws-sso-login")
        } catch {
            log.error("couldn't open Terminal for the SSO sign-in: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Sample AWS profiles for the settings' images (`--settings-image`): made-up names, keys and sign-ins in a folder of
/// their own, never the user's ~/.aws; STS and the SSO portal are answered here (nothing goes online, nothing runs).
@MainActor
enum AWSProfileSamples {
    static let config = """
        [default]
        region = us-west-2

        [profile base]
        region = us-west-2

        [profile dev]
        role_arn = arn:aws:iam::123456789012:role/BedrockUser
        source_profile = base
        region = us-west-2

        [profile sso-dev]
        sso_session = my-sso
        sso_account_id = 123456789012
        sso_role_name = BedrockUser
        region = us-west-2

        [profile sso-old]
        sso_session = old-sso
        sso_account_id = 123456789012
        sso_role_name = BedrockUser
        region = us-west-2

        [profile tools]
        credential_process = /usr/local/bin/my-creds --profile dev
        region = us-west-2

        [sso-session my-sso]
        sso_start_url = https://my-sso-portal.awsapps.com/start
        sso_region = us-east-1

        [sso-session old-sso]
        sso_start_url = https://my-old-portal.awsapps.com/start
        sso_region = us-east-1
        """

    static let credentials = """
        [default]
        aws_access_key_id = AKIAIOSFODNN7EXAMPLE
        aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

        [base]
        aws_access_key_id = AKIAI44QH8DHBEXAMPLE
        aws_secret_access_key = je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY
        """

    /// The samples written into `folder` (its `.aws`, its SSO sign-ins: my-sso for 3 more hours, old-sso expired), and a
    /// resolver over them whose STS and SSO answers are canned.
    static func resolver(in folder: URL, now: Date = Date()) -> AWSCredentialResolver {
        let files = AWSFileLocations(environment: ["HOME": folder.path])
        try? FileManager.default.createDirectory(at: files.ssoCache, withIntermediateDirectories: true)
        try? Data(config.utf8).write(to: files.config)
        try? Data(credentials.utf8).write(to: files.credentials)
        let iso = ISO8601DateFormatter()
        for (session, expires) in [("my-sso", now.addingTimeInterval(3 * 3600)), ("old-sso", now.addingTimeInterval(-3600))] {
            let token = #"{"accessToken": "sample-token", "expiresAt": "\#(iso.string(from: expires))"}"#
            try? Data(token.utf8).write(to: AWSSSO.cacheFile(key: session, in: files.ssoCache))
        }
        let roleExpires = iso.string(from: now.addingTimeInterval(55 * 60)), ssoExpires = Int64(now.addingTimeInterval(50 * 60).timeIntervalSince1970 * 1000)
        let send: AWSCredentialContext.Send = { request in
            let host = request.url?.host ?? ""
            let body = host.hasPrefix("sts.")
                ? "<AssumeRoleResponse><AssumeRoleResult><Credentials><AccessKeyId>ASIAEXAMPLEROLE</AccessKeyId>"
                    + "<SecretAccessKey>sample-secret</SecretAccessKey><SessionToken>sample-token</SessionToken>"
                    + "<Expiration>\(roleExpires)</Expiration></Credentials></AssumeRoleResult></AssumeRoleResponse>"
                : #"{"roleCredentials": {"accessKeyId": "ASIAEXAMPLESSO", "secretAccessKey": "sample-secret", "sessionToken": "sample-token", "expiration": \#(ssoExpires)}}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!)
        }
        return AWSCredentialResolver(context: AWSCredentialContext(
            environment: ["HOME": folder.path], runProcess: { _ in throw AWSProcessError.notFound("my-creds") }, send: send))
    }

    /// Where `use` put them (`render` deletes it).
    private static var folder: URL?

    /// The window's AWS profiles from the samples (in a temporary folder): "default" chosen (static keys), dev and
    /// sso-dev already fetched.
    static func use(in model: SettingsModel) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AllInOneIME-aws-samples-\(UUID().uuidString)")
        Self.folder = folder
        let resolver = resolver(in: folder)
        var done = false
        Task {
            _ = try? await resolver.resolve(profile: "dev")
            _ = try? await resolver.resolve(profile: "sso-dev")
            done = true
        }
        let deadline = Date().addingTimeInterval(5)
        while !done, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        model.aws.resolver = resolver
        model.config.awsProfile = "default"
        model.aws.load(profile: "default")
    }

    /// Settings → AI Provider with a role, an SSO profile and an SSO sign-in that expired (with its command):
    /// `settings-provider-aws-<role|sso|sso-expired>.png`.
    static func render(_ model: SettingsModel, to output: URL, appearance: NSAppearance.Name) {
        let (provider, profile, shownAs) = (model.config.provider, model.config.awsProfile, model.profileShownAs)
        model.config.provider = .bedrock
        model.profileShownAs = nil  // sample names
        for (name, file) in [("dev", "aws-role"), ("sso-dev", "aws-sso"), ("sso-old", "aws-sso-expired")] {
            model.config.awsProfile = name
            model.aws.load(profile: name)
            SettingsImage.render(model, page: .provider, to: output.appendingPathComponent("settings-provider-\(file).png"),
                                 appearance: appearance) { RunLoop.main.run(until: Date().addingTimeInterval($0)) }
        }
        (model.config.provider, model.config.awsProfile, model.profileShownAs) = (provider, profile, shownAs)
        model.aws.load(profile: profile)
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }
}

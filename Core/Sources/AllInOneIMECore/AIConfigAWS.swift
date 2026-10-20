import Foundation

extension AIConfig {
    /// An AWS profile as Settings → Assistant may know it: its name and region, nothing else of it.
    public struct AWSProfile: Equatable, Sendable {
        public var name: String
        public var region: String?

        public init(name: String, region: String? = nil) {
            self.name = name
            self.region = region
        }
    }

    /// The AWS profiles in `~/.aws/config` and `~/.aws/credentials` (or the files the environment names) and their
    /// regions, read line by line: section names and `region` lines only, never a key, a token or any other setting.
    /// SSO, role and `credential_process` profiles are listed with their region like the others.
    public static func awsProfiles(environment: [String: String] = ProcessInfo.processInfo.environment) -> [AWSProfile] {
        let home = CorePaths.home
        let config = environment["AWS_CONFIG_FILE"] ?? home.appendingPathComponent(".aws/config").path
        let credentials = environment["AWS_SHARED_CREDENTIALS_FILE"] ?? home.appendingPathComponent(".aws/credentials").path
        return awsProfiles(config: try? String(contentsOfFile: config, encoding: .utf8),
                           credentials: try? String(contentsOfFile: credentials, encoding: .utf8))
    }

    /// The profiles in these files' texts: the config file's region first (the credentials file's where it has none).
    public static func awsProfiles(config: String?, credentials: String?) -> [AWSProfile] {
        var regions: [String: String?] = [:]
        var order: [String] = []
        func read(_ text: String?, isConfig: Bool) {
            guard let text else { return }
            var section: String?
            for raw in text.split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("[") && line.hasSuffix("]") {
                    var name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                    if isConfig {
                        // "[profile work]"; "[default]"; "[sso-session x]" and "[services x]" aren't profiles.
                        if name.hasPrefix("profile ") {
                            name = String(name.dropFirst("profile ".count)).trimmingCharacters(in: .whitespaces)
                        } else if name != "default" {
                            section = nil
                            continue
                        }
                    }
                    section = name.isEmpty ? nil : name
                    if let section, regions[section] == nil {
                        regions[section] = .some(nil)
                        order.append(section)
                    }
                    continue
                }
                // Only a profile's own `region` line: an indented one belongs to a nested setting (`s3 =` …).
                guard let section, raw.first?.isWhitespace != true, !line.hasPrefix("#"), !line.hasPrefix(";"),
                      let equals = line.firstIndex(of: "=") else { continue }
                guard line[..<equals].trimmingCharacters(in: .whitespaces).lowercased() == "region" else { continue }
                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                // The config file's region wins over one in the credentials file.
                if !value.isEmpty, isConfig || (regions[section] ?? nil) == nil { regions[section] = .some(value) }
            }
        }
        read(credentials, isConfig: false)
        read(config, isConfig: true)
        let names = order.sorted { a, b in a == "default" ? b != "default" : b == "default" ? false : a < b }
        return names.map { AWSProfile(name: $0, region: regions[$0] ?? nil) }
    }

    /// Whether a Bedrock model ID names the AWS account: an ARN (an inference profile's, a custom model's), or an account ID
    /// (twelve digits) in it. It goes to no provider but Amazon Bedrock (`AIConfigPrompt.Context.showsAWSAccount`).
    public static func namesAWSAccount(_ modelId: String) -> Bool {
        modelId.lowercased().hasPrefix("arn:") || modelId.range(of: #"(?<![0-9])[0-9]{12}(?![0-9])"#, options: .regularExpression) != nil
    }

    /// The account IDs in AWS profiles' names (an SSO profile is "AdministratorAccess-123456789012" by default), hidden from
    /// a provider other than Amazon Bedrock as "[account 1]", "[account 2]" (the same account, the same number), the rest
    /// of the name kept (`AIConfigPrompt.Context.showsAWSAccount`); an answer that names a profile so has its IDs put back.
    public struct AWSAccounts: Equatable, Sendable {
        /// The IDs in the names' order: the first is "[account 1]".
        public private(set) var ids: [String] = []

        public init(_ names: [String]) {
            for name in names {
                for id in Self.ids(in: name) where !ids.contains(id) { ids.append(id) }
            }
        }

        /// `name` with each account ID in it as "[account N]".
        public func hiding(_ name: String) -> String {
            var shown = ""
            for (run, isID) in Self.runs(name) {
                shown += isID ? ids.firstIndex(of: run).map { "[account \($0 + 1)]" } ?? run : run
            }
            return shown
        }

        /// `text` (an answer) with each "[account N]" as its ID again.
        public func restoring(_ text: String) -> String {
            ids.enumerated().reduce(text) { $0.replacingOccurrences(of: "[account \($1.offset + 1)]", with: $1.element) }
        }

        /// The account IDs in `name`: twelve digits, no more and no fewer (as `namesAWSAccount` finds them).
        static func ids(in name: String) -> [String] { runs(name).filter(\.isID).map(\.text) }

        /// `name` cut into runs of ASCII digits and the rest, each run with whether it is an account ID.
        private static func runs(_ name: String) -> [(text: String, isID: Bool)] {
            var runs: [(text: String, isID: Bool)] = []
            var current = "", digits = false
            func flush() {
                if !current.isEmpty { runs.append((current, digits && current.count == 12)) }
                current = ""
            }
            for character in name {
                let digit = character.isASCII && character.isNumber
                if digit != digits { flush() }
                digits = digit
                current.append(character)
            }
            flush()
            return runs
        }
    }

    /// Whether `text` is about AWS or Bedrock, by its words (not letters inside others: "draws", "laws"): only then are
    /// the profiles' names sent to a cloud provider.
    public static func mentionsAWS(_ text: String) -> Bool {
        let words = AIConfigFit.Words(text)
        return ["aws", "bedrock", "amazon", "profile", "亚马逊", "亞馬遜", "アマゾン", "아마존"].contains(where: words.contains)
    }
}

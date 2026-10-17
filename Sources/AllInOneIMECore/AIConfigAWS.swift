import Foundation

extension AIConfig {
    /// An AWS profile as `@config` may know it: its name and region, nothing else of it.
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

    /// Whether `text` is about AWS or Bedrock: only then are the profiles' names sent to a cloud provider.
    public static func mentionsAWS(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["aws", "bedrock", "amazon", "profile", "亚马逊"].contains { lower.contains($0) }
    }
}

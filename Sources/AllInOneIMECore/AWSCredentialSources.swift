import CryptoKit
import Foundation

// MARK: - credential_process

/// `credential_process`: the command from the profile, split into arguments as the AWS CLI splits it (POSIX shell words,
/// no shell), and the JSON it prints.
public enum AWSCredentialProcess {
    /// Why a command can't be split.
    public enum SplitError: Error, Equatable, Sendable {
        case unclosedQuote
        case trailingBackslash
        case empty

        public var reason: String {
            switch self {
            case .unclosedQuote: return "a quote isn't closed"
            case .trailingBackslash: return "it ends with a backslash"
            case .empty: return "it's empty"
            }
        }
    }

    /// `command` as arguments, the way Python's `shlex.split` (POSIX) does it for the AWS CLI: spaces, tabs and line breaks
    /// separate words; '…' keeps everything as it is; "…" keeps everything but \" and \\; a backslash outside quotes keeps
    /// the next character. Nothing is expanded (no `~`, `$VAR` or globs) and nothing runs in a shell. Read scalar by
    /// scalar, as Python reads code points: a quote followed by a combining mark is still a quote.
    public static func arguments(_ command: String) throws -> [String] {
        var out: [String] = [], word = String.UnicodeScalarView(), inWord = false
        var quote: Unicode.Scalar?
        let scalars = Array(command.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let c = scalars[index]
            if let open = quote {
                if c == open {
                    quote = nil
                } else if open == "\"", c == "\\", index + 1 < scalars.count, scalars[index + 1] == "\"" || scalars[index + 1] == "\\" {
                    index += 1
                    word.append(scalars[index])
                } else {
                    word.append(c)
                }
            } else if c == "'" || c == "\"" {
                quote = c
                inWord = true
            } else if c == "\\" {
                guard index + 1 < scalars.count else { throw SplitError.trailingBackslash }
                index += 1
                word.append(scalars[index])
                inWord = true
            } else if c == " " || c == "\t" || c == "\n" || c == "\r" {
                if inWord { out.append(String(word)) }
                word = String.UnicodeScalarView()
                inWord = false
            } else {
                word.append(c)
                inWord = true
            }
            index += 1
        }
        if quote != nil { throw SplitError.unclosedQuote }
        if inWord { out.append(String(word)) }
        guard let first = out.first, !first.isEmpty else { throw SplitError.empty }
        return out
    }

    /// Why the output can't be used (never quoting it: it may hold a secret).
    public struct OutputError: Error, Equatable, Sendable {
        public var reason: String
        public init(_ reason: String) { self.reason = reason }
    }

    /// The credentials in what the program printed: `{"Version": 1, "AccessKeyId", "SecretAccessKey", "SessionToken"?,
    /// "Expiration"?}` (an ISO 8601 time).
    public static func parse(_ output: Data) throws -> (credentials: AWSCredentials, expiration: Date?) {
        guard let object = try? JSONSerialization.jsonObject(with: output), let json = object as? [String: Any] else {
            throw OutputError(output.isEmpty ? "it printed nothing" : "it isn't a JSON object")
        }
        guard let version = json["Version"] as? NSNumber, !(version === kCFBooleanTrue || version === kCFBooleanFalse),
              version.doubleValue == 1 else {
            throw OutputError(json["Version"] == nil ? "\"Version\": 1 is missing" : "\"Version\" isn't 1")
        }
        func text(_ key: String) -> String? { (json[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        guard let id = text("AccessKeyId") else { throw OutputError("\"AccessKeyId\" is missing") }
        guard let secret = text("SecretAccessKey") else { throw OutputError("\"SecretAccessKey\" is missing") }
        var expiration: Date?
        if let value = json["Expiration"], !(value is NSNull) {
            guard let string = value as? String, let date = AWSTime.parse(string) else {
                throw OutputError("\"Expiration\" isn't an ISO 8601 time")
            }
            expiration = date
        }
        return (AWSCredentials(accessKeyId: id, secretAccessKey: secret, sessionToken: text("SessionToken")), expiration)
    }

    /// The last lines a failed program wrote to standard error, as shown: control characters out, at most 3 lines and
    /// 300 characters, anything like a key masked.
    public static func lastLines(_ data: Data, lines: Int = 3, limit: Int = 300) -> String {
        let text = CommandRunner.cleanOutput(data)
        let kept = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .suffix(lines).joined(separator: " / ")
        let short = kept.count > limit ? "…" + String(kept.suffix(limit)) : kept
        return AIConfig.maskingKeys(short, with: "[KEY]")
    }
}

/// Times as AWS and credential programs write them: "2026-10-16T22:30:00Z", with fractional seconds (any number of
/// digits), `z`, an offset ("+00:00", "+0000", "-07:00"), the AWS CLI's older "UTC", or none (UTC, as botocore reads
/// it); a space for the "T" too.
enum AWSTime {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2}):(\d{2})(\.\d+)?(Z|z|UTC|[+-]\d{2}:?\d{2})?$"#)

    static func parse(_ text: String) -> Date? {
        let string = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = string as NSString
        guard let match = pattern.firstMatch(in: string, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
        var parts = DateComponents()
        (parts.year, parts.month, parts.day) = (Int(group(1)!), Int(group(2)!), Int(group(3)!))
        (parts.hour, parts.minute, parts.second) = (Int(group(4)!), Int(group(5)!), Int(group(6)!))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let month = parts.month, (1...12).contains(month), let day = parts.day, (1...31).contains(day),
              let hour = parts.hour, hour < 24, let minute = parts.minute, minute < 60, let second = parts.second, second <= 60,
              let base = calendar.date(from: parts), calendar.component(.day, from: base) == day else { return nil }
        let fraction = group(7).flatMap { Double("0" + $0) } ?? 0
        var offset = 0
        if let zone = group(8), zone.hasPrefix("+") || zone.hasPrefix("-") {
            let digits = zone.dropFirst().replacingOccurrences(of: ":", with: "")
            guard let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)), hours < 24, minutes < 60 else { return nil }
            offset = (hours * 3600 + minutes * 60) * (zone.hasPrefix("-") ? -1 : 1)
        }
        return base.addingTimeInterval(fraction - Double(offset))
    }
}

// MARK: - STS AssumeRole

/// STS `AssumeRole` at the regional endpoint, signed with SigV4, and its XML answer.
public enum AWSSTS {
    /// `https://sts.<region>.amazonaws.com/` (`.amazonaws.com.cn` in China); a region with anything but lowercase letters,
    /// digits and dashes is refused.
    public static func endpoint(region: String) throws -> URL {
        guard AWSRegion.isValid(region) else { throw BedrockError.invalidRegion(region) }
        let suffix = region.hasPrefix("cn-") ? "amazonaws.com.cn" : "amazonaws.com"
        return URL(string: "https://sts.\(region).\(suffix)/")!
    }

    /// The signed request: `Action=AssumeRole&Version=2011-06-15&RoleArn=…&RoleSessionName=…` (then `DurationSeconds`,
    /// `ExternalId` when set), form-encoded, the service `sts`.
    public static func assumeRoleRequest(roleArn: String, sessionName: String, externalId: String? = nil, durationSeconds: Int? = nil,
                                         region: String, credentials: AWSCredentials, date: Date, timeout: TimeInterval = 20) throws -> URLRequest {
        var parameters = [("Action", "AssumeRole"), ("Version", "2011-06-15"), ("RoleArn", roleArn), ("RoleSessionName", sessionName)]
        if let durationSeconds { parameters.append(("DurationSeconds", String(durationSeconds))) }
        if let externalId { parameters.append(("ExternalId", externalId)) }
        let body = Data(parameters.map { SigV4Signer.uriEncode($0.0) + "=" + SigV4Signer.uriEncode($0.1) }.joined(separator: "&").utf8)
        var request = URLRequest(url: try endpoint(region: region), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        SigV4Signer(credentials: credentials, region: region, service: "sts").sign(&request, body: body, date: date)
        return request
    }

    /// The credentials and their expiration in an `AssumeRoleResponse`.
    public static func parseAssumeRole(_ data: Data) -> (credentials: AWSCredentials, expiration: Date)? {
        let fields = XMLFields.read(data, ["AccessKeyId", "SecretAccessKey", "SessionToken", "Expiration"])
        func value(_ name: String) -> String? {
            // A token may be shown wrapped over lines (as in the documentation): it never holds whitespace itself.
            fields[name].map { $0.components(separatedBy: .whitespacesAndNewlines).joined() }.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let id = value("AccessKeyId"), let secret = value("SecretAccessKey"), let token = value("SessionToken"),
              let expiration = value("Expiration").flatMap(AWSTime.parse) else { return nil }
        return (AWSCredentials(accessKeyId: id, secretAccessKey: secret, sessionToken: token), expiration)
    }

    /// An `ErrorResponse`'s code and message.
    public static func parseError(_ data: Data) -> (code: String?, message: String?) {
        let fields = XMLFields.read(data, ["Code", "Message"])
        return (fields["Code"]?.trimmingCharacters(in: .whitespacesAndNewlines), fields["Message"]?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// STS codes that say the credentials it was called with have expired or aren't known: the source's are fetched again.
    static let expiredCodes: Set<String> = ["ExpiredToken", "ExpiredTokenException", "InvalidClientTokenId", "RequestExpired"]
}

/// The text of some elements of an XML document (the first of each), namespaces aside.
final class XMLFields: NSObject, XMLParserDelegate {
    private let wanted: Set<String>
    private var values: [String: String] = [:]
    private var current: String?
    private var buffer = ""

    private init(_ wanted: Set<String>) { self.wanted = wanted }

    static func read(_ data: Data, _ names: Set<String>) -> [String: String] {
        let reader = XMLFields(names)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        _ = parser.parse()
        return reader.values
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if wanted.contains(name), values[name] == nil {
            current = name
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if current != nil { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == current {
            values[name] = buffer
            current = nil
        }
    }
}

// MARK: - SSO

/// IAM Identity Center (SSO): the sign-in the AWS CLI cached (`aws sso login`), only read, and the portal's
/// `GetRoleCredentials`.
public enum AWSSSO {
    /// A cached sign-in: its token (never shown) and when it expires.
    public struct Token: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        public var accessToken: String
        public var expiresAt: Date

        /// Printed or logged, only when it expires: never the token.
        public var description: String { "AWSSSO.Token(expires \(ISO8601DateFormatter().string(from: expiresAt)))" }
        public var debugDescription: String { description }
    }

    /// `<folder>/<SHA-1 of the session name or start URL>.json`, as the AWS CLI names it.
    public static func cacheFile(key: String, in folder: URL) -> URL {
        let hash = Insecure.SHA1.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(hash + ".json")
    }

    /// The token cached at `url`; nil when there is none, or it can't be read.
    public static func readToken(at url: URL) -> Token? {
        guard let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let token = json["accessToken"] as? String, !token.isEmpty,
              let expires = (json["expiresAt"] as? String).flatMap(AWSTime.parse) else { return nil }
        return Token(accessToken: token, expiresAt: expires)
    }

    /// `GET https://portal.sso.<region>.amazonaws.com/federation/credentials?role_name=…&account_id=…` with the token in
    /// `x-amz-sso_bearer_token`.
    public static func roleCredentialsRequest(region: String, accountId: String, roleName: String, token: String,
                                              timeout: TimeInterval = 20) throws -> URLRequest {
        guard AWSRegion.isValid(region) else { throw BedrockError.invalidRegion(region) }
        let suffix = region.hasPrefix("cn-") ? "amazonaws.com.cn" : "amazonaws.com"
        let query = "role_name=\(SigV4Signer.uriEncode(roleName))&account_id=\(SigV4Signer.uriEncode(accountId))"
        var request = URLRequest(url: URL(string: "https://portal.sso.\(region).\(suffix)/federation/credentials?\(query)")!,
                                 timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "x-amz-sso_bearer_token")
        return request
    }

    /// `{"roleCredentials": {"accessKeyId", "secretAccessKey", "sessionToken", "expiration"}}` (milliseconds since 1970).
    public static func parseRoleCredentials(_ data: Data) -> (credentials: AWSCredentials, expiration: Date)? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let role = json["roleCredentials"] as? [String: Any],
              let id = role["accessKeyId"] as? String, !id.isEmpty,
              let secret = role["secretAccessKey"] as? String, !secret.isEmpty,
              let milliseconds = (role["expiration"] as? NSNumber)?.doubleValue else { return nil }
        let token = (role["sessionToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return (AWSCredentials(accessKeyId: id, secretAccessKey: secret, sessionToken: token),
                Date(timeIntervalSince1970: milliseconds / 1000))
    }

    /// The portal's error message (`{"message": …}`), if any.
    static func errorMessage(_ data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (json["message"] as? String) ?? (json["Message"] as? String)
    }
}

enum AWSRegion {
    /// Lowercase letters, digits and dashes only: it goes into a host name.
    static func isValid(_ region: String) -> Bool {
        !region.isEmpty && region.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.lowercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "-")
        }
    }
}

// MARK: - Running credential_process

/// What `credential_process` is started with.
public struct AWSProcessRequest: Equatable, Sendable {
    /// The program, then its arguments.
    public var arguments: [String]
    public var environment: [String: String]
    public var directory: URL
    public var timeout: TimeInterval

    public init(arguments: [String], environment: [String: String], directory: URL, timeout: TimeInterval) {
        self.arguments = arguments
        self.environment = environment
        self.directory = directory
        self.timeout = timeout
    }
}

public struct AWSProcessResult: Equatable, Sendable {
    public var status: Int32
    public var standardOutput: Data
    public var standardError: Data

    public init(status: Int32, standardOutput: Data, standardError: Data = Data()) {
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public enum AWSProcessError: Error, Equatable, Sendable {
    case notFound(String)
    case timedOut(TimeInterval)
}

/// Runs a program without a shell: found on the request's PATH, in its folder, standard input closed, standard output and
/// standard error read apart (1 MB each at most), stopped (its process group) after the timeout or when the task is
/// cancelled.
public enum AWSProcessRunner {
    static let maxOutput = 1 << 20

    /// The program as the AWS CLI finds it: a name without "/" on `path`, else the path itself (relative to `directory`),
    /// with nothing expanded (no `~`). Nil when it isn't there or can't be run.
    public static func resolve(_ program: String, path: String?, directory: URL) -> URL? {
        let fm = FileManager.default
        if program.contains("/") {
            let url = program.hasPrefix("/") ? URL(fileURLWithPath: program) : directory.appendingPathComponent(program)
            return fm.isExecutableFile(atPath: url.path) ? url : nil
        }
        for folder in (path ?? "").split(separator: ":") where !folder.isEmpty {
            let candidate = URL(fileURLWithPath: String(folder)).appendingPathComponent(program)
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public static func run(_ request: AWSProcessRequest) async throws -> AWSProcessResult {
        guard let program = request.arguments.first,
              let url = resolve(program, path: request.environment["PATH"], directory: request.directory) else {
            throw AWSProcessError.notFound(request.arguments.first ?? "")
        }
        let run = Run()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                run.start(url, request, continuation)
            }
        } onCancel: {
            run.stop()
        }
    }

    private final class Run: @unchecked Sendable {
        private let lock = NSLock()
        private let process = Process()
        private var output = Data(), errors = Data()
        private var timedOut = false, finished = false, started = false, cancelled = false
        private var continuation: CheckedContinuation<AWSProcessResult, Error>?
        private var timeout: TimeInterval = 60

        func start(_ url: URL, _ request: AWSProcessRequest, _ continuation: CheckedContinuation<AWSProcessResult, Error>) {
            lock.lock()
            self.continuation = continuation
            timeout = request.timeout
            let skip = cancelled
            lock.unlock()
            if skip { return finish(CancellationError()) }
            process.executableURL = url
            process.arguments = Array(request.arguments.dropFirst())
            process.environment = request.environment
            process.currentDirectoryURL = request.directory
            process.standardInput = FileHandle.nullDevice
            let stdout = Pipe(), stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            let pipes = DispatchGroup()
            for (pipe, isOutput) in [(stdout, true), (stderr, false)] {
                pipes.enter()
                pipe.fileHandleForReading.readabilityHandler = { [self] handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        handle.readabilityHandler = nil
                        pipes.leave()
                        return
                    }
                    lock.lock()
                    if isOutput {
                        if output.count < AWSProcessRunner.maxOutput { output.append(chunk.prefix(AWSProcessRunner.maxOutput - output.count)) }
                    } else if errors.count < AWSProcessRunner.maxOutput {
                        errors.append(chunk.prefix(AWSProcessRunner.maxOutput - errors.count))
                    }
                    lock.unlock()
                }
            }
            process.terminationHandler = { [self] _ in
                // Something it started in the background may keep the pipes open: don't wait long for that.
                DispatchQueue.global().async { [self] in
                    _ = pipes.wait(timeout: .now() + 1)
                    finish(nil)
                }
            }
            do {
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                return finish(AWSProcessError.notFound(request.arguments.first ?? ""))
            }
            lock.lock()
            started = true
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + max(request.timeout, 0.1)) { [self] in
                lock.lock()
                let running = !finished
                if running { timedOut = true }
                lock.unlock()
                if running { kill() }
            }
        }

        func stop() {
            lock.lock()
            cancelled = true
            let running = started && !finished
            lock.unlock()
            if running { kill() }
        }

        /// Its process group (what it started too): SIGTERM, then SIGKILL half a second later.
        private func kill() {
            let pid = process.processIdentifier
            guard pid > 0 else { return }
            Darwin.kill(-pid, SIGTERM)
            Darwin.kill(pid, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                Darwin.kill(-pid, SIGKILL)
                Darwin.kill(pid, SIGKILL)
            }
        }

        private func finish(_ error: Error?) {
            lock.lock()
            guard !finished, let continuation else { return lock.unlock() }
            finished = true
            self.continuation = nil
            let (output, errors, timedOut, cancelled, timeout) = (output, errors, timedOut, cancelled, timeout)
            lock.unlock()
            if let error { return continuation.resume(throwing: error) }
            if cancelled { return continuation.resume(throwing: CancellationError()) }
            if timedOut { return continuation.resume(throwing: AWSProcessError.timedOut(timeout)) }
            continuation.resume(returning: AWSProcessResult(status: process.terminationStatus, standardOutput: output, standardError: errors))
        }
    }
}

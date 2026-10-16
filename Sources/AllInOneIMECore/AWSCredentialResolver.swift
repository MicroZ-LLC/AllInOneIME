import Foundation
import os

/// What the resolver reads and calls, so the tests and the self-test can give their own: the AWS variables, the files,
/// how `credential_process` runs, the HTTP client for STS and SSO, and the clock.
public struct AWSCredentialContext: Sendable {
    public typealias RunProcess = @Sendable (AWSProcessRequest) async throws -> AWSProcessResult
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    /// `AWSEnvironment.variables` and `HOME`, asked for each resolution.
    public var environment: @Sendable () -> [String: String]
    /// Where the files are; nil: from `environment` (`AWSFileLocations(environment:)`).
    public var files: AWSFileLocations?
    /// The environment `credential_process` runs with (the login shell's PATH).
    public var processEnvironment: @Sendable () -> [String: String]
    public var runProcess: RunProcess
    public var send: Send
    public var now: @Sendable () -> Date
    public var processTimeout: TimeInterval

    public init(environment: @escaping @Sendable () -> [String: String], files: AWSFileLocations? = nil,
                processEnvironment: @escaping @Sendable () -> [String: String], runProcess: @escaping RunProcess = AWSProcessRunner.run,
                send: @escaping Send = AWSCredentialContext.offline, now: @escaping @Sendable () -> Date = { Date() },
                processTimeout: TimeInterval = 60) {
        self.environment = environment
        self.files = files
        self.processEnvironment = processEnvironment
        self.runProcess = runProcess
        self.send = send
        self.now = now
        self.processTimeout = processTimeout
    }

    /// Fixed variables: what the tests give. `credential_process` gets PATH /usr/bin:/bin:/usr/sbin:/sbin and HOME (the
    /// files' home) unless `processEnvironment` says otherwise.
    public init(environment: [String: String] = [:], files: AWSFileLocations? = nil, processEnvironment: [String: String]? = nil,
                runProcess: @escaping RunProcess = AWSProcessRunner.run, send: @escaping Send = AWSCredentialContext.offline,
                now: @escaping @Sendable () -> Date = { Date() }, processTimeout: TimeInterval = 60) {
        let home = (files ?? AWSFileLocations(environment: environment)).home.path
        let process = processEnvironment ?? ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home]
        self.init(environment: { environment }, files: files, processEnvironment: { process }, runProcess: runProcess, send: send,
                  now: now, processTimeout: processTimeout)
    }

    public var locations: AWSFileLocations { files ?? AWSFileLocations(environment: environment()) }

    /// The input method's: its own environment over the login shell's, the login shell's PATH for `credential_process`
    /// (with the AWS files' variables, so the program reads the same files), HTTP through an ephemeral session.
    public static let live = AWSCredentialContext(
        environment: { AWSEnvironment.merged(own: ProcessInfo.processInfo.environment, login: ShellEnvironment.login) },
        processEnvironment: {
            var environment = ShellEnvironment.current
            let aws = AWSEnvironment.merged(own: ProcessInfo.processInfo.environment, login: ShellEnvironment.login)
            for name in ["AWS_CONFIG_FILE", "AWS_SHARED_CREDENTIALS_FILE"] { environment[name] = aws[name] }
            return environment
        },
        send: { request in
            let (data, response) = try await liveSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, http)
        })

    private static let liveSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    /// No network: what the tests get unless they give a stub.
    public static let offline: Send = { _ in throw URLError(.notConnectedToInternet) }
}

/// What the settings and `@doctor` show of a profile, read without running a program or going online: its kind and
/// region, the credentials held for it (when they expire), the SSO sign-in's end, a problem known in advance (a profile
/// not found, an MFA code needed, an SSO sign-in expired …), and the last refresh's error.
public struct AWSProfileStatus: Equatable, Sendable {
    public var profile: String
    /// Nil: the profile isn't there.
    public var kind: AWSProfileKind?
    public var region: String?
    /// Credentials held now (fetched, or the static keys found).
    public var hasCredentials = false
    /// When the credentials held now expire (nil: none held, or they don't).
    public var expiration: Date?
    /// SSO (also the source of a role): when the cached sign-in ends.
    public var signedInUntil: Date?
    /// What will stop the next refresh, known now.
    public var problem: AWSCredentialError?
    /// Why the last refresh failed (the credentials held, if any, are still used until they expire).
    public var lastError: AWSCredentialError?

    public init(profile: String) { self.profile = profile }

    /// Nothing known stands in the way of a request (it may still fail: a program, STS or the portal decide).
    public var isReady: Bool { problem == nil || hasCredentials }

    /// What fixes the problem in Terminal ("aws sso login --profile X").
    public var fixCommand: String? { problem?.fixCommand ?? lastError?.fixCommand }

    /// "Static keys: found the keys for this profile", "Role via base: credentials expire at 15:30", "SSO (signed in until
    /// 18:00): …", "credential_process: runs when a request needs credentials", or the problem.
    public func line(chinese: Bool, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        func tr(_ zh: String, _ en: String) -> String { chinese ? zh : en }
        let separator = tr("：", ": ")
        guard let kind, kind != .noCredentials else {
            return (problem ?? (kind == nil ? .profileNotFound(profile) : .noCredentials(profile: profile))).message(chinese: chinese)
        }
        var label = kind.label(chinese: chinese)
        if let until = signedInUntil, until > now {
            label += tr("（登录到 \(Self.time(until, now: now, chinese: true, timeZone: timeZone))）",
                        " (signed in until \(Self.time(until, now: now, chinese: false, timeZone: timeZone)))")
        }
        var detail: String
        if let expiration, hasCredentials, expiration > now {
            detail = tr("凭证 \(Self.time(expiration, now: now, chinese: true, timeZone: timeZone)) 到期",
                        "credentials expire at \(Self.time(expiration, now: now, chinese: false, timeZone: timeZone))")
            if let problem { detail += tr("；", "; ") + problem.message(chinese: chinese) }
        } else if let problem {
            detail = problem.message(chinese: chinese)
        } else {
            switch kind {
            case .staticKeys: detail = tr("已找到这个 profile 的密钥", "found the keys for this profile")
            case .environment: detail = tr("已找到 shell 里的 AWS_ACCESS_KEY_ID", "found AWS_ACCESS_KEY_ID in your shell")
            case .credentialProcess:
                detail = hasCredentials ? tr("凭证一直用到 AWS 不再接受", "credentials kept until AWS stops taking them")
                    : tr("需要凭证时才运行", "runs when a request needs credentials")
            case .role: detail = tr("需要时才切换角色", "assumed when a request needs it")
            case .sso: detail = tr("需要时才取凭证", "credentials fetched when a request needs them")
            case .noCredentials: detail = AWSCredentialError.noCredentials(profile: profile).message(chinese: chinese)
            }
        }
        if let lastError, lastError != problem {
            detail += tr("；上次刷新失败：", "; the last refresh failed: ") + lastError.shortMessage(chinese: chinese)
        }
        return label + separator + detail
    }

    /// "15:30" today, else "Oct 17 15:30" ("10月17日 15:30").
    static func time(_ date: Date, now: Date, chinese: Bool, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: chinese ? "zh_Hans" : "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : chinese ? "M月d日 HH:mm" : "MMM d HH:mm"
        return formatter.string(from: date)
    }
}

/// Credentials for an AWS profile, as the AWS CLI resolves them (`AWSProfilePlan.make` has the order): `role_arn`
/// (`source_profile`, or `credential_source = Environment`), SSO, static keys in the credentials file,
/// `credential_process`, static keys in the config file; for "default" (or no name) the environment's keys first. What expires is cached per profile, in memory only, until 5 minutes before it does; a request
/// with under 10 minutes left gets the cached credentials and starts a refresh in the background. Requests that come
/// while one is fetched wait for that one. Programs run and STS or SSO is called only for a request (or Test
/// Connection), never to list profiles.
public final class AWSCredentialResolver: Sendable {
    /// The input method's: one cache for every request.
    public static let shared = AWSCredentialResolver(context: .live)
    /// Credentials are fetched again this long before they expire.
    public static let refreshMargin: TimeInterval = 5 * 60
    /// With less than this left, a request starts a refresh in the background.
    public static let backgroundWindow: TimeInterval = 10 * 60
    /// After a background refresh failed, the next one waits this long.
    static let backgroundRetryDelay: TimeInterval = 30

    public let context: AWSCredentialContext

    struct Fetched: Equatable, Sendable {
        var credentials: AWSCredentials
        var expiration: Date?
    }

    private struct Entry: Sendable {
        var fingerprint: String
        var value: Fetched?
        var task: Task<Fetched, Error>?
        var taskID = 0
        var lastError: AWSCredentialError?
        var lastBackgroundFailure: Date?
    }

    private struct State: Sendable {
        var entries: [String: Entry] = [:]
        var nextID = 0
        /// How many times each profile's credentials were fetched (program run, STS or SSO called).
        var fetches: [String: Int] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(context: AWSCredentialContext) {
        self.context = context
    }

    /// A loader for `Converter` and `ChatClient`.
    public var loader: @Sendable (_ profile: String) async throws -> AWSSharedConfig.Resolved {
        { [self] profile in try await resolve(profile: profile) }
    }

    // MARK: Resolving

    /// The profile's credentials and region: the cached ones while they are good for 5 more minutes, else fetched (once
    /// for every request waiting). `forceRefresh` (Test Connection): fetched again through the whole chain, the cached
    /// ones kept if that fails.
    public func resolve(profile: String, forceRefresh: Bool = false) async throws -> AWSSharedConfig.Resolved {
        let name = Self.name(profile)
        let (fetched, plan, region, _) = try await credentials(name, force: forceRefresh)
        return AWSSharedConfig.Resolved(
            credentials: fetched.credentials, region: region, expiration: fetched.expiration, kind: plan.kind,
            refresh: AWSCredentialRefresh { [self] in try await refresh(profile: name, replacing: fetched.credentials) })
    }

    /// After AWS refused `failed` as expired: the cache dropped (unless it already holds others, fetched by another
    /// request meanwhile) and the profile resolved again.
    public func refresh(profile: String, replacing failed: AWSCredentials?) async throws -> AWSSharedConfig.Resolved {
        let name = Self.name(profile)
        state.withLock { state in
            if let failed, state.entries[name]?.value?.credentials == failed { state.entries[name]?.value = nil }
            if failed == nil { state.entries[name]?.value = nil }
        }
        return try await resolve(profile: name)
    }

    /// Forgets the cached credentials (of one profile, or all).
    public func invalidate(profile: String? = nil) {
        state.withLock { state in
            if let profile { state.entries[Self.name(profile)]?.value = nil } else {
                for name in state.entries.keys { state.entries[name]?.value = nil }
            }
        }
    }

    /// Waits for the refreshes running now (those in the background too).
    public func waitForRefreshes() async {
        while true {
            let tasks = state.withLock { $0.entries.values.compactMap(\.task) }
            if tasks.isEmpty { return }
            for task in tasks { _ = try? await task.value }
            await Task.yield()
        }
    }

    /// How many times the profile's credentials were fetched (a program run, STS or the SSO portal called).
    public func fetchCount(profile: String) -> Int { state.withLock { $0.fetches[Self.name(profile)] ?? 0 } }

    static func name(_ profile: String) -> String {
        let trimmed = profile.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "default" : trimmed
    }

    /// The profile's credentials, plan and region, and the cache entry they're kept in. `chain`: the role profiles being
    /// resolved that lead here (`asSource`: as the last one's `source_profile`).
    private func credentials(_ name: String, chain: [String] = [], force: Bool, asSource: Bool = false)
        async throws -> (fetched: Fetched, plan: AWSProfilePlan, region: String?, key: String) {
        let files = AWSProfileFiles.read(context.locations)
        // A profile met again is a loop, except a role naming itself with keys of its own: those are its source (botocore).
        if let start = chain.firstIndex(of: name), !(asSource && chain.last == name && files.hasStaticKeys(name)) {
            throw AWSCredentialError.sourceProfileLoop(Array(chain[start...]) + [name])
        }
        let environment = context.environment()
        let plan = try AWSProfilePlan.make(name, files: files, environment: environment, asSource: asSource)
        let region = Self.region(name, plan: plan, files: files, environment: environment)
        switch plan {
        case let .staticKeys(keys), let .environment(keys):
            return (Fetched(credentials: keys, expiration: nil), plan, region, name)
        case .process, .role, .sso:
            // A source resolved otherwise than the profile itself (a role's own keys…) is cached apart from it.
            let key = asSource && (try? AWSProfilePlan.make(name, files: files, environment: environment)) != plan ? name + " (source)" : name
            let fingerprint = AWSProfilePlan.fingerprint(name, files: files)
            let fetched = try await cached(key, fingerprint: fingerprint, force: force) { [self] in
                try await fetch(plan, profile: name, chain: chain + [name], force: force)
            }
            return (fetched, plan, region, key)
        }
    }

    /// The profile's own region, else (keys from the environment) `AWS_REGION` or `AWS_DEFAULT_REGION`.
    static func region(_ name: String, plan: AWSProfilePlan?, files: AWSProfileFiles, environment: [String: String]) -> String? {
        if let region = files.region(name) { return region }
        if case .environment? = plan { return AWSEnvironment.region(environment) }
        return files.contains(name) ? nil : AWSEnvironment.region(environment)
    }

    private enum Next: Sendable {
        case use(Fetched)
        case wait(Task<Fetched, Error>)
    }

    /// The cached credentials while fresh (a background refresh started when under 10 minutes are left), else the fetch
    /// running now, else a new one.
    private func cached(_ name: String, fingerprint: String, force: Bool,
                        fetch: @escaping @Sendable () async throws -> Fetched) async throws -> Fetched {
        let now = context.now()
        let next: Next = state.withLock { state in
            var entry = state.entries[name] ?? Entry(fingerprint: fingerprint)
            if entry.fingerprint != fingerprint { entry = Entry(fingerprint: fingerprint) }  // the profile changed: start over
            defer { state.entries[name] = entry }
            if !force, let value = entry.value, Self.isFresh(value, now: now) {
                if let expiration = value.expiration, expiration.timeIntervalSince(now) < Self.backgroundWindow, entry.task == nil,
                   entry.lastBackgroundFailure.map({ now.timeIntervalSince($0) >= Self.backgroundRetryDelay }) ?? true {
                    let task = start(name, &state, &entry, background: true, fetch: fetch)
                    entry.task = task
                }
                return .use(value)
            }
            if let task = entry.task { return .wait(task) }
            let task = start(name, &state, &entry, background: false, fetch: fetch)
            entry.task = task
            return .wait(task)
        }
        switch next {
        case let .use(value): return value
        case let .wait(task): return try await task.value
        }
    }

    private func start(_ name: String, _ state: inout State, _ entry: inout Entry, background: Bool,
                       fetch: @escaping @Sendable () async throws -> Fetched) -> Task<Fetched, Error> {
        state.nextID += 1
        let id = state.nextID
        entry.taskID = id
        state.fetches[name, default: 0] += 1
        return Task.detached { [self] in
            do {
                let fetched = try await fetch()
                finish(name, id: id, background: background, result: .success(fetched))
                return fetched
            } catch {
                let reported = error as? AWSCredentialError ?? .invalidResponse(profile: name, detail: String(describing: error))
                finish(name, id: id, background: background, result: .failure(reported))
                throw reported
            }
        }
    }

    private func finish(_ name: String, id: Int, background: Bool, result: Result<Fetched, AWSCredentialError>) {
        let now = context.now()
        state.withLock { state in
            guard var entry = state.entries[name], entry.taskID == id else { return }
            entry.task = nil
            switch result {
            case let .success(fetched):
                entry.value = fetched
                entry.lastError = nil
                entry.lastBackgroundFailure = nil
            case let .failure(error):
                entry.lastError = error
                if background { entry.lastBackgroundFailure = now }
            }
            state.entries[name] = entry
        }
    }

    static func isFresh(_ fetched: Fetched, now: Date) -> Bool {
        fetched.expiration.map { now < $0.addingTimeInterval(-refreshMargin) } ?? true
    }

    // MARK: Fetching

    private func fetch(_ plan: AWSProfilePlan, profile: String, chain: [String], force: Bool) async throws -> Fetched {
        switch plan {
        case let .staticKeys(keys), let .environment(keys):
            return Fetched(credentials: keys, expiration: nil)
        case let .process(command):
            return try await runProcess(command, profile: profile)
        case let .role(role):
            return try await assumeRole(role, profile: profile, chain: chain, force: force)
        case let .sso(sso):
            return try await ssoCredentials(sso, profile: profile)
        }
    }

    private func runProcess(_ command: String, profile: String) async throws -> Fetched {
        let arguments: [String]
        do {
            arguments = try AWSCredentialProcess.arguments(command)
        } catch let error as AWSCredentialProcess.SplitError {
            throw AWSCredentialError.invalidCommand(profile: profile, reason: error.reason)
        }
        // The program's name only: its arguments may hold something private.
        let program = URL(fileURLWithPath: arguments[0]).lastPathComponent
        let request = AWSProcessRequest(arguments: arguments, environment: context.processEnvironment(), directory: context.locations.home,
                                        timeout: context.processTimeout)
        let result: AWSProcessResult
        do {
            result = try await context.runProcess(request)
        } catch AWSProcessError.notFound {
            throw AWSCredentialError.processNotFound(profile: profile, program: program)
        } catch let AWSProcessError.timedOut(seconds) {
            throw AWSCredentialError.processTimedOut(profile: profile, program: program, seconds: Int(seconds.rounded()))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AWSCredentialError {
            throw error
        } catch {
            throw AWSCredentialError.processFailed(profile: profile, program: program, status: -1,
                                                   stderr: AIConfig.maskingKeys(String(describing: error), with: "[KEY]"))
        }
        guard result.status == 0 else {
            throw AWSCredentialError.processFailed(profile: profile, program: program, status: result.status,
                                                   stderr: AWSCredentialProcess.lastLines(result.standardError))
        }
        do {
            let parsed = try AWSCredentialProcess.parse(result.standardOutput)
            return Fetched(credentials: parsed.credentials, expiration: parsed.expiration)
        } catch let error as AWSCredentialProcess.OutputError {
            throw AWSCredentialError.processOutputInvalid(profile: profile, program: program, reason: error.reason,
                                                          stderr: AWSCredentialProcess.lastLines(result.standardError))
        }
    }

    private func assumeRole(_ role: AWSProfilePlan.Role, profile: String, chain: [String], force: Bool) async throws -> Fetched {
        var source: AWSCredentials
        var sourceKey: String?
        switch role.source {
        case let .profile(name):
            let resolved = try await credentials(name, chain: chain, force: force, asSource: true)
            (source, sourceKey) = (resolved.fetched.credentials, resolved.key)
        case .environment:
            guard let keys = AWSEnvironment.credentials(context.environment()) else {
                throw AWSCredentialError.environmentMissing(profile: profile)
            }
            source = keys
        }
        let now = context.now()
        let sessionName = role.sessionName ?? "allinoneime-\(Int(now.timeIntervalSince1970))"
        let region = role.region ?? "us-east-1"
        func call(_ credentials: AWSCredentials) async throws -> Fetched {
            let request: URLRequest
            do {
                request = try AWSSTS.assumeRoleRequest(roleArn: role.roleArn, sessionName: sessionName, externalId: role.externalId,
                                                       durationSeconds: role.durationSeconds, region: region, credentials: credentials,
                                                       date: context.now())
            } catch {
                throw AWSCredentialError.invalidProfile(profile: profile, reason: "region \(region) isn't a valid region")
            }
            let (data, response) = try await send(request, profile: profile)
            guard response.statusCode == 200 else {
                let error = AWSSTS.parseError(data)
                throw AWSCredentialError.stsFailed(profile: profile, code: error.code,
                                                   message: Self.shown(error.message ?? "HTTP \(response.statusCode)"))
            }
            guard let parsed = AWSSTS.parseAssumeRole(data) else {
                throw AWSCredentialError.invalidResponse(profile: profile, detail: "no credentials in the AssumeRole response")
            }
            return Fetched(credentials: parsed.credentials, expiration: parsed.expiration)
        }
        do {
            return try await call(source)
        } catch let error as AWSCredentialError {
            // The source's own credentials expired (a program's without an expiration, say): fetched again, once.
            guard case let .stsFailed(_, code?, _) = error, AWSSTS.expiredCodes.contains(code), case let .profile(name) = role.source,
                  let key = sourceKey else {
                throw error
            }
            let failed = source
            state.withLock { state in
                if state.entries[key]?.value?.credentials == failed { state.entries[key]?.value = nil }
            }
            source = try await credentials(name, chain: chain, force: false, asSource: true).fetched.credentials
            return try await call(source)
        }
    }

    private func ssoCredentials(_ sso: AWSProfilePlan.SSO, profile: String) async throws -> Fetched {
        let file = AWSSSO.cacheFile(key: sso.cacheKey, in: context.locations.ssoCache)
        guard let token = AWSSSO.readToken(at: file) else { throw AWSCredentialError.ssoNotSignedIn(profile: profile) }
        guard token.expiresAt > context.now() else { throw AWSCredentialError.ssoExpired(profile: profile) }
        let request: URLRequest
        do {
            request = try AWSSSO.roleCredentialsRequest(region: sso.region, accountId: sso.accountId, roleName: sso.roleName,
                                                        token: token.accessToken)
        } catch {
            throw AWSCredentialError.invalidProfile(profile: profile, reason: "sso_region \(sso.region) isn't a valid region")
        }
        let (data, response) = try await send(request, profile: profile)
        switch response.statusCode {
        case 200:
            guard let parsed = AWSSSO.parseRoleCredentials(data) else {
                throw AWSCredentialError.invalidResponse(profile: profile, detail: "no roleCredentials in the SSO response")
            }
            return Fetched(credentials: parsed.credentials, expiration: parsed.expiration)
        case 401:
            // The portal no longer takes the cached sign-in.
            throw AWSCredentialError.ssoExpired(profile: profile)
        default:
            let type = response.value(forHTTPHeaderField: "x-amzn-ErrorType")?.split(separator: ":").first.map(String.init)
            let message = AWSSSO.errorMessage(data) ?? "no message"
            throw AWSCredentialError.ssoFailed(profile: profile, status: response.statusCode,
                                               message: Self.shown((type.map { "\($0): " } ?? "") + message))
        }
    }

    private func send(_ request: URLRequest, profile: String) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await context.send(request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw AWSCredentialError.network(profile: profile, message: Self.describe(error))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AWSCredentialError {
            throw error
        } catch {
            throw AWSCredentialError.network(profile: profile, message: Self.shown(String(describing: error)))
        }
    }

    static func describe(_ error: URLError) -> String {
        switch error.code {
        case .timedOut: return "the request timed out"
        case .notConnectedToInternet, .networkConnectionLost: return "no network connection"
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "can't reach the server"
        default: return "network error \(error.code.rawValue)"
        }
    }

    /// Server text as shown: short, anything like a key masked.
    static func shown(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return AIConfig.maskingKeys(line.count > 300 ? String(line.prefix(300)) + "…" : line, with: "[KEY]")
    }

    // MARK: What the settings show

    /// Every profile in the files with its region and kind, for the AWS Profile picker. Nothing runs.
    public func profiles() -> [AWSProfileSummary] {
        let files = AWSProfileFiles.read(context.locations)
        let environment = context.environment()
        return files.names.map { name in
            AWSProfileSummary(name: name, region: files.region(name), kind: Self.kind(name, files: files, environment: environment) ?? .noCredentials)
        }
    }

    /// The profile's region (its own, else `AWS_REGION` when it comes from the environment).
    public func region(profile: String) -> String? {
        let name = Self.name(profile)
        let files = AWSProfileFiles.read(context.locations), environment = context.environment()
        return Self.region(name, plan: try? AWSProfilePlan.make(name, files: files, environment: environment), files: files, environment: environment)
    }

    /// The profile as the settings show it (`AWSProfileStatus`): files and the SSO cache read, nothing run or fetched.
    public func status(profile: String) -> AWSProfileStatus {
        let name = Self.name(profile)
        let files = AWSProfileFiles.read(context.locations)
        let environment = context.environment()
        var status = AWSProfileStatus(profile: name)
        status.kind = Self.kind(name, files: files, environment: environment)
        status.region = Self.region(name, plan: try? AWSProfilePlan.make(name, files: files, environment: environment), files: files,
                                    environment: environment)
        let now = context.now()
        do {
            let plan = try AWSProfilePlan.make(name, files: files, environment: environment)
            switch plan {
            case .staticKeys, .environment:
                status.hasCredentials = true
            case .process, .role, .sso:
                let fingerprint = AWSProfilePlan.fingerprint(name, files: files)
                if let entry = state.withLock({ $0.entries[name] }), entry.fingerprint == fingerprint {
                    if let value = entry.value, value.expiration.map({ $0 > now }) ?? true {
                        status.hasCredentials = true
                        status.expiration = value.expiration
                    }
                    status.lastError = entry.lastError
                }
            }
            let checked = check(plan, profile: name, chain: [name], files: files, environment: environment, now: now)
            status.problem = checked.problem
            status.signedInUntil = checked.signedInUntil
        } catch let error as AWSCredentialError {
            status.problem = error
        } catch {
            status.problem = .invalidResponse(profile: name, detail: String(describing: error))
        }
        return status
    }

    /// What stops the plan, as far as the files tell (a role's sources followed), and the SSO sign-in's end.
    private func check(_ plan: AWSProfilePlan, profile: String, chain: [String], files: AWSProfileFiles, environment: [String: String],
                       now: Date) -> (problem: AWSCredentialError?, signedInUntil: Date?) {
        switch plan {
        case .staticKeys, .environment:
            return (nil, nil)
        case let .process(command):
            do {
                let arguments = try AWSCredentialProcess.arguments(command)
                if CommandRunner.resolve(arguments[0], path: context.processEnvironment()["PATH"]) == nil {
                    return (.processNotFound(profile: profile, program: URL(fileURLWithPath: arguments[0]).lastPathComponent), nil)
                }
                return (nil, nil)
            } catch let error as AWSCredentialProcess.SplitError {
                return (.invalidCommand(profile: profile, reason: error.reason), nil)
            } catch {
                return (nil, nil)
            }
        case let .role(role):
            switch role.source {
            case .environment:
                return (AWSEnvironment.credentials(environment) == nil ? .environmentMissing(profile: profile) : nil, nil)
            case let .profile(source):
                if let start = chain.firstIndex(of: source), !(source == profile && files.hasStaticKeys(source)) {
                    return (.sourceProfileLoop(Array(chain[start...]) + [source]), nil)
                }
                do {
                    let sourcePlan = try AWSProfilePlan.make(source, files: files, environment: environment, asSource: true)
                    return check(sourcePlan, profile: source, chain: chain + [source], files: files, environment: environment, now: now)
                } catch let error as AWSCredentialError {
                    return (error, nil)
                } catch {
                    return (nil, nil)
                }
            }
        case let .sso(sso):
            guard let token = AWSSSO.readToken(at: AWSSSO.cacheFile(key: sso.cacheKey, in: context.locations.ssoCache)) else {
                return (.ssoNotSignedIn(profile: profile), nil)
            }
            return (token.expiresAt > now ? nil : .ssoExpired(profile: profile), token.expiresAt)
        }
    }

    /// The kind the profile is, even when it can't work as written (a role needing MFA is still a role).
    static func kind(_ name: String, files: AWSProfileFiles, environment: [String: String]) -> AWSProfileKind? {
        if let plan = try? AWSProfilePlan.make(name, files: files, environment: environment) { return plan.kind }
        guard let settings = files.settings(name) else { return nil }
        func has(_ key: String) -> Bool { AWSProfileFiles.value(settings[key]) != nil }
        // In the order `AWSProfilePlan.make` takes them.
        if has("role_arn") {
            return .role(source: AWSProfileFiles.value(settings["source_profile"]) ?? AWSProfileFiles.value(settings["credential_source"]) ?? "?")
        }
        if has("sso_account_id") || has("sso_role_name") || has("sso_session") || has("sso_start_url") { return .sso }
        if has("aws_access_key_id") { return .staticKeys }
        return has("credential_process") ? .credentialProcess : .noCredentials
    }
}

/// Fresh credentials after AWS said these expired (`AWSCredentialResolver.refresh`). Not part of a value's identity:
/// every one equals every other.
public struct AWSCredentialRefresh: Sendable, Equatable {
    let run: @Sendable () async throws -> AWSSharedConfig.Resolved

    public init(_ run: @escaping @Sendable () async throws -> AWSSharedConfig.Resolved) { self.run = run }

    public func callAsFunction() async throws -> AWSSharedConfig.Resolved { try await run() }

    public static func == (lhs: AWSCredentialRefresh, rhs: AWSCredentialRefresh) -> Bool { true }
}

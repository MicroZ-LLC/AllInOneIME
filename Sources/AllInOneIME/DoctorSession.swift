import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMERime
import AppKit
import Carbon
import EventKit

/// What Settings → Assistant's checks run with (`AssistantModel`, `Doctor`): the probes read what the app already knows
/// (`--status`, Settings' Test Connection, the permission checks, the language pack manager, the update checker, the
/// extension loader's skipped list, the app's own logs), never asking for a permission or a key; the findings show a row
/// each, and the config fixes go through the request's preview, apply and undo.
@MainActor
enum DoctorSession {
    /// What the probes found (the self-test gives its own); `told`, while they run: the facts so far, as each part ends
    /// (the areas not checked yet in `Doctor.Facts.unchecked`).
    static var probe: (_ told: @escaping @MainActor (Doctor.Facts) -> Void) async -> Doctor.Facts = { await liveFacts(told: $0) }
    static var service = DoctorService()
    /// The connection test's limit: a check, not a wait.
    static var connectionTimeout: TimeInterval = 12

    /// The parts of the probes read off the main thread, each on its own, told as it ends: the config file with the keys
    /// saved (the keychain items' attributes, the login shell's variables) and Bedrock's AWS profile; the permissions the
    /// system tells about Apple events and Reminders; the plugins that didn't load; the logs' recent errors.
    private enum Part: Sendable {
        case config(data: Data?, config: Result<Config, Error>, keySaved: [Provider: Bool], awsProfile: Result<String, Error>?,
                    awsStatus: AWSProfileStatus?)
        case permissions(automation: [String: Doctor.Facts.Permission], reminders: EKAuthorizationStatus)
        case plugins(errors: [String])
        case logs(errors: [String])
    }

    /// The probes on this Mac, told as each part ends (`told`), what is known here at once first: the input source,
    /// Apple Intelligence, Accessibility and the microphone, secure input, iCloud sync. What reads files, the keychain
    /// items' attributes, the login shell's variables or asks the system about Apple events runs off the main thread, each
    /// part on its own; the packs, the updater and the extensions are read here, where they live, once the config is in.
    static func liveFacts(told: @escaping @MainActor (Doctor.Facts) -> Void = { _ in }) async -> Doctor.Facts {
        var facts = Doctor.Facts()
        facts.unchecked = Set(Doctor.Area.allCases).subtracting([.connection])
        typealias R = InputSourceRegistrar
        if let source = R.source() {
            facts.inputMethod.enabled = R.bool(source, kTISPropertyInputSourceIsEnabled)
            facts.inputMethod.selectable = R.bool(source, kTISPropertyInputSourceIsSelectCapable)
            facts.inputMethod.selected = R.bool(source, kTISPropertyInputSourceIsSelected)
            facts.inputMethod.listed = R.isInUserList
        } else {
            facts.inputMethod.registered = false
        }
        facts.apple = AppleModel.system.availability
        // This process's own: the input method's, which reads the selection (the settings window runs in it), so this
        // build's signature. System Settings may still show the switch on for the build before an update.
        facts.accessibility = AXIsProcessTrusted() ? .granted : .denied
        if Features.voiceInput {  // the microphone is for voice input, off for now: left unknown, no check
            switch VoiceInput.microphoneAccess {
            case .granted: facts.microphone = .granted
            case .denied: facts.microphone = .denied
            case .notDetermined: facts.microphone = .notDetermined
            }
        }
        facts.secureInput = SecureInput.isOn ? SecureInput.ownerDescription() : nil
        facts.iCloudSync = ICloudSyncController.shared.facts
        facts.unchecked.subtract([.inputMethod, .secureInput, .iCloudSync])
        told(facts)
        let url = AIConfigSession.url, logs = RimeDirectories.logs, lookup = AIConfigSession.keySource
        let rimeUser = RimeDirectories.user, lunarDatabase = RimeDirectories.user.appendingPathComponent("lua/lunar.db")
        var pluginsIn = false
        await withTaskGroup(of: Part.self) { group in
            group.addTask(priority: .userInitiated) {
                let data = try? Data(contentsOf: url)
                let config = Result { try Config.load(from: url) }
                // As Settings and the Assistant's requests see them (the item's attributes: no key read, no prompt).
                let keyed = AIConfigSession.providersWithKey(lookup, config: (try? config.get()) ?? .default)
                var keys: [Provider: Bool] = [:]
                for provider in Provider.allCases where provider != .bedrock && provider != .apple {
                    keys[provider] = keyed.contains(provider)
                }
                var profile: Result<String, Error>?
                var awsStatus: AWSProfileStatus?
                if case let .success(loaded) = config, loaded.provider == .bedrock {
                    // The files and the SSO sign-in read, nothing run or fetched: its kind, expiry, a known problem.
                    let status = AWSCredentialResolver.shared.status(profile: loaded.awsProfile)
                    awsStatus = status
                    profile = status.isReady ? .success(status.region ?? "us-east-1")
                        : .failure(status.problem ?? AWSCredentialError.profileNotFound(status.profile))
                }
                return .config(data: data, config: config, keySaved: keys, awsProfile: profile, awsStatus: awsStatus)
            }
            group.addTask(priority: .userInitiated) {
                .permissions(automation: automation(), reminders: EKEventStore.authorizationStatus(for: .reminder))
            }
            group.addTask(priority: .userInitiated) {
                .plugins(errors: PluginStore.load().skipped.prefix(5).map { "\($0.folder): \($0.reason)" })
            }
            group.addTask(priority: .userInitiated) {
                let config = (try? Config.load(from: url)) ?? .default
                return .logs(errors: recentLogErrors(in: logs, lunarDatabase: lunarDatabase, openCC: openCC(config, rimeUser: rimeUser)))
            }
            for await part in group {
                switch part {
                case let .config(data, config, keySaved, awsProfile, awsStatus):
                    facts.configData = data
                    switch config {
                    case let .success(config): facts.config = config
                    case let .failure(error): facts.configError = UIText.describe(error)
                    }
                    facts.keySaved = keySaved
                    facts.awsProfile = awsProfile.map { $0.mapError { Doctor.ProbeError(UIText.describe($0)) } }
                    facts.awsStatus = awsStatus
                    here(&facts, config: facts.config ?? .default)
                    facts.unchecked.subtract([.config, .provider, .appleIntelligence, .languagePacks, .updates])
                    if pluginsIn { facts.unchecked.remove(.extensions) }
                case let .permissions(automation, reminders):
                    facts.automation = automation
                    switch reminders {
                    case .fullAccess, .writeOnly: facts.automation["Reminders"] = .granted
                    case .denied, .restricted: facts.automation["Reminders"] = .denied
                    default: break
                    }
                    facts.unchecked.remove(.permissions)
                case let .plugins(errors):
                    facts.pluginErrors = errors
                    pluginsIn = true
                    // The extensions' own are read with the config (their folders are its).
                    if !facts.unchecked.contains(.config) { facts.unchecked.remove(.extensions) }
                case let .logs(errors):
                    facts.recentErrors = errors
                    facts.unchecked.remove(.recentErrors)
                }
                told(facts)
            }
        }
        return facts
    }

    /// What is read here, where it lives, for `config`: the language packs of its input languages, the extensions left
    /// out, the updater's state.
    private static func here(_ facts: inout Doctor.Facts, config: Config) {
        let packs = LanguagePackManager.shared
        for language in config.inputLanguages {
            guard let pack = LanguagePack.for(language) else { continue }
            switch packs.state(pack) {
            case .installed:
                let folder = packs.store.folder(pack)
                let whole = pack.requiredFiles.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
                facts.packs[language] = packs.isInstalled(pack) && (whole || RimeDirectories.override != nil) ? .installed : .damaged
            case .downloading: facts.packs[language] = .downloading
            case .notInstalled, .failed: facts.packs[language] = packs.isInstalled(pack) ? .installed : .missing
            }
        }
        facts.skippedExtensions = LiveExtensions.current(config).skipped.prefix(10).map {
            $0.file.lastPathComponent + ": " + UIText.describe($0.problem, file: $0.file)
        }
        let updates = UpdateController.shared
        facts.updates.available = updates.available?.version
        facts.updates.checkEnabled = config.checkForUpdates
        if let result = updates.lastResult, !result.ok { facts.updates.lastError = result.error }
        if case let .failed(message, _) = updates.state { facts.updates.lastError = message }
    }

    /// Whether this process may control the apps the commands use (Notes, Terminal, Messages), asked without a prompt:
    /// an app that isn't running can't tell (left out).
    nonisolated static func automation() -> [String: Doctor.Facts.Permission] {
        var out: [String: Doctor.Facts.Permission] = [:]
        for (name, id) in [("Notes", "com.apple.Notes"), ("Terminal", "com.apple.Terminal"), ("Messages", "com.apple.MobileSMS")] {
            let descriptor = NSAppleEventDescriptor(bundleIdentifier: id)
            let status = withExtendedLifetime(descriptor) { () -> OSStatus in
                guard let target = descriptor.aeDesc else { return OSStatus(procNotFound) }
                return AEDeterminePermissionToAutomateTarget(target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
            }
            switch Int(status) {
            case Int(noErr): out[name] = .granted
            case -1743: out[name] = .denied  // errAEEventNotPermitted
            case -1744: out[name] = .notDetermined  // errAEEventWouldRequireUserConsent
            default: break  // not running: not told
            }
        }
        return out
    }

    /// Where OpenCC's data for Traditional characters stands (`Doctor.OpenCCNow`): not used with Simplified ones, provided
    /// since the Rime user folder got the app's files for the characters typed as it copied them.
    nonisolated static func openCC(_ config: Config, rimeUser: URL) -> Doctor.OpenCCNow {
        let characters = config.typedChinese
        guard characters.isTraditional else { return .unused }
        return RimeService.providedOpenCC(userDataDir: rimeUser, for: characters).map { .provided(since: $0) } ?? .unknown
    }

    /// The error lines of the last week in the app's own logs (the updater's, librime's) in `folder`, summarised.
    nonisolated static func recentLogErrors(in folder: URL, lunarDatabase: URL, openCC: Doctor.OpenCCNow = .unknown) -> [String] {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent == "update.log" || $0.lastPathComponent.contains(".ERROR.") }
            .filter { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) > weekAgo }
        var lines: [String] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            lines += text.split(separator: "\n").suffix(200).map(String.init)
        }
        return Doctor.summarizeLogLines(lines, lunarDatabaseAvailable: FileManager.default.fileExists(atPath: lunarDatabase.path),
                                        openCC: openCC)
    }

    /// What a fix does besides the settings (the self-test records them instead).
    static var perform: (AIConfig.Action) -> Void = { performLive($0) }

    static func performLive(_ action: AIConfig.Action) {
        switch action {
        case .resaveConfig:
            // Only the repeated languages go; every other key of the file stays.
            try? Doctor.removeRepeatedLanguages(at: AIConfigSession.url)
        case .enableInputMethod:
            typealias R = InputSourceRegistrar
            _ = R.register()
            if let source = R.waitForSource(timeout: 2), !R.bool(source, kTISPropertyInputSourceIsEnabled) { _ = TISEnableInputSource(source) }
            if R.waitUntilEnabled(timeout: 2) { _ = R.updateUserList { InputSourceList.adding(R.bundleID, to: $0) } }
        case let .openPrivacy(pane):
            NSWorkspace.shared.open(pane.url)
        case let .downloadPack(language):
            if let pack = LanguagePack.for(language) { LanguagePackManager.shared.download(pack) {} }
        case .openAppleIntelligenceSettings:
            NSWorkspace.shared.open(AppleModel.settingsURL)
        case .checkForUpdates:
            UpdateController.shared.check(userInitiated: true)
            SettingsWindow.shared.show(page: .about)
        case let .copyCommand(command):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }
}

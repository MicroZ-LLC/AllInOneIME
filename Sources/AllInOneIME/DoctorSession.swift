import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Carbon
import EventKit

/// What Settings → Assistant's checks run with (`AssistantModel`, `Doctor`): the probes read what the app already knows
/// (`--status`, Settings' Test Connection, the permission checks, the language pack manager, the update checker, the
/// extension loader's skipped list, the app's own logs), never asking for a permission or a key; the findings show a row
/// each, and the config fixes go through the request's preview, apply and undo.
@MainActor
enum DoctorSession {
    /// What the probes found (the self-test gives its own).
    static var probe: () async -> Doctor.Facts = { await liveFacts() }
    static var service = DoctorService()
    /// The connection test's limit: a check, not a wait.
    static var connectionTimeout: TimeInterval = 12

    /// What the probes read from disk, the keychain's attributes and the system, off the main thread.
    private struct Background: Sendable {
        var configData: Data?
        var config: Result<Config, Error>
        var keySaved: [Provider: Bool]
        var awsProfile: Result<String, Error>?
        var awsStatus: AWSProfileStatus?
        var automation: [String: Doctor.Facts.Permission]
        var reminders: EKAuthorizationStatus
        var pluginErrors: [String]
        var recentErrors: [String]
    }

    /// The probes on this Mac. What reads files, the keychain items' attributes, the login shell's variables or asks the
    /// system about Apple events runs off the main thread; the input source, the packs, the updater and the extensions
    /// are read here, where they live.
    static func liveFacts() async -> Doctor.Facts {
        var facts = Doctor.Facts()
        typealias R = InputSourceRegistrar
        if let source = R.source() {
            facts.inputMethod.enabled = R.bool(source, kTISPropertyInputSourceIsEnabled)
            facts.inputMethod.selectable = R.bool(source, kTISPropertyInputSourceIsSelectCapable)
            facts.inputMethod.selected = R.bool(source, kTISPropertyInputSourceIsSelected)
            facts.inputMethod.listed = R.isInUserList
        } else {
            facts.inputMethod.registered = false
        }
        let url = AIConfigSession.url, logs = RimeDirectories.logs, lookup = AIConfigSession.keySource
        let read = await Task.detached(priority: .userInitiated) { () -> Background in
            let data = try? Data(contentsOf: url)
            let config = Result { try Config.load(from: url) }
            // As Settings and the Assistant's requests see them (the item's attributes: no key read, no prompt).
            let keyed = AIConfigSession.providersWithKey(lookup)
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
            return Background(configData: data, config: config, keySaved: keys, awsProfile: profile, awsStatus: awsStatus,
                              automation: automation(),
                              reminders: EKEventStore.authorizationStatus(for: .reminder),
                              pluginErrors: PluginStore.load().skipped.prefix(5).map { "\($0.folder): \($0.reason)" },
                              recentErrors: recentLogErrors(in: logs))
        }.value
        facts.configData = read.configData
        switch read.config {
        case let .success(config): facts.config = config
        case let .failure(error): facts.configError = UIText.describe(error)
        }
        let config = facts.config ?? .default
        facts.keySaved = read.keySaved
        facts.awsProfile = read.awsProfile.map { $0.mapError { Doctor.ProbeError(UIText.describe($0)) } }
        facts.awsStatus = read.awsStatus
        facts.apple = AppleModel.system.availability
        facts.accessibility = AXIsProcessTrusted() ? .granted : .denied
        switch VoiceInput.microphoneAccess {
        case .granted: facts.microphone = .granted
        case .denied: facts.microphone = .denied
        case .notDetermined: facts.microphone = .notDetermined
        }
        facts.automation = read.automation
        switch read.reminders {
        case .fullAccess, .writeOnly: facts.automation["Reminders"] = .granted
        case .denied, .restricted: facts.automation["Reminders"] = .denied
        default: break
        }
        facts.secureInput = SecureInput.isOn ? SecureInput.ownerDescription() : nil
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
        facts.pluginErrors = read.pluginErrors
        let updates = UpdateController.shared
        facts.updates.available = updates.available?.version
        facts.updates.checkEnabled = config.checkForUpdates
        if let result = updates.lastResult, !result.ok { facts.updates.lastError = result.error }
        if case let .failed(message, _) = updates.state { facts.updates.lastError = message }
        facts.recentErrors = read.recentErrors
        facts.iCloudSync = ICloudSyncController.shared.facts
        return facts
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

    /// The error lines of the last week in the app's own logs (the updater's, librime's) in `folder`, summarised.
    nonisolated static func recentLogErrors(in folder: URL) -> [String] {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent == "update.log" || $0.lastPathComponent.contains(".ERROR.") }
            .filter { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) > weekAgo }
        var lines: [String] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            lines += text.split(separator: "\n").suffix(200).map(String.init)
        }
        return Doctor.summarizeLogLines(lines)
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

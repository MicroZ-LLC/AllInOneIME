import AllInOneIMECore
import AppKit
import Carbon
import EventKit

/// `@doctor` in the input controller (`Doctor`): the probes read what the app already knows (`--status`, Settings' Test
/// Connection, the permission checks, the language pack manager, the update checker, the extension loader's skipped
/// list, the app's own logs), never asking for a permission or a key; the findings show a row each, and the fixes go
/// through `@config`'s preview, apply and undo.
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
        let url = AIConfigSession.url, logs = RimeDirectories.logs
        let read = await Task.detached(priority: .userInitiated) { () -> Background in
            let data = try? Data(contentsOf: url)
            let config = Result { try Config.load(from: url) }
            var keys: [Provider: Bool] = [:]
            for provider in Provider.allCases where provider != .bedrock && provider != .apple {
                keys[provider] = APIKeys.source(provider) != .none  // the item's attributes: no key read, no prompt
            }
            var profile: Result<String, Error>?
            if case let .success(loaded) = config, loaded.provider == .bedrock {
                profile = Result { try AWSSharedConfig.load(profile: loaded.awsProfile).region ?? "us-east-1" }
            }
            return Background(configData: data, config: config, keySaved: keys, awsProfile: profile, automation: automation(),
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
        }
    }
}

extension AllInOneIMEInputController {
    /// `@doctor` (`question` empty) or `@doctor <question>`: the checks, a row each as they come (the connection test
    /// shows as running), then all of them; with a question, the model's explanation and the fixes it names.
    @MainActor
    func startDoctor(_ question: String, id: Int) {
        conversionTask?.cancel()
        lastElapsed = nil
        lastFromCache = false
        let chinese = UIText.chinese
        let started = Date()
        log.notice("@doctor \(id) started (\(question.isEmpty ? "checks" : "with a question", privacy: .public))")
        conversionTask = Task { @MainActor [weak self] in
            var facts = await DoctorSession.probe()
            guard let self, !Task.isCancelled else { return }
            // Not without what it needs (a key, the profile's credentials …): the provider's row already says so.
            let tests = Doctor.canTestConnection(facts)
            if tests { facts.connection = .running }
            let first = Self.report(Doctor.findings(facts, chinese: chinese), chinese: chinese, final: !tests && question.isEmpty)
            self.perform(self.composer.receiveDoctor(first, id: id), client: nil)
            if tests {
                let url = AIConfigSession.url
                let outcome = try? await AIConfigService.withTimeout(DoctorSession.connectionTimeout) { @MainActor in
                    await AIConfigSession.testConnection(url)
                }
                guard !Task.isCancelled else { return }
                let seconds = Int(DoctorSession.connectionTimeout)
                facts.connection = outcome.map { $0.ok ? .ok($0.line) : .failed($0.line) }
                    ?? .failed(chinese ? "\(seconds) 秒内没有回应" : "no answer within \(seconds) s")
            }
            let findings = Doctor.findings(facts, chinese: chinese)
            var report = Self.report(findings, chinese: chinese, final: question.isEmpty)
            if !question.isEmpty {
                self.perform(self.composer.receiveDoctor(report, id: id), client: nil)
                do {
                    // The model reads the findings in English, in the same order as the panel's (the fixes' ids match).
                    let english = Doctor.findings(facts, chinese: false)
                    let answer = try await DoctorSession.service.ask(question, findings: english, config: facts.config ?? .default)
                    guard !Task.isCancelled else { return }
                    report.explanation = answer.explanation + (answer.onDevice ? "" : tr("（由你选的 AI 服务回答）", " (answered by your AI provider)"))
                    report.recommended = answer.fixes
                } catch {
                    guard !Task.isCancelled else { return }
                    report.explanation = tr("没能问 AI：", "Couldn't ask the AI: ") + UIText.describe(error)
                }
                report.isFinal = true
            }
            self.lastElapsed = Date().timeIntervalSince(started)
            // What the real-app test reads (`log stream`): the input method's own finding, and how many problems.
            let inputMethod = findings.first { $0.area == .inputMethod }
                .map { $0.status == .ok ? "ok" : $0.status == .warning ? "warning" : "problem" } ?? "-"
            let (problems, warnings) = (findings.filter { $0.status == .problem }.count, findings.filter { $0.status == .warning }.count)
            log.notice("doctor \(id) done: inputMethod=\(inputMethod, privacy: .public) problems=\(problems) warnings=\(warnings)")
            self.perform(self.composer.receiveDoctor(report, id: id), client: nil)
        }
    }

    /// The findings as the panel shows them.
    static func report(_ findings: [Doctor.Finding], chinese: Bool, final: Bool) -> Composer.ConfigState.Report {
        Composer.ConfigState.Report(lines: findings.map { $0.text(chinese: chinese) }, fixes: findings.map(\.fix),
                                    summary: Doctor.summary(findings, chinese: chinese), isFinal: final)
    }

    /// A finding's fix picked (or ⏎: the safe ones): `@config`'s preview of what they do.
    @MainActor
    func previewFixes(_ fixes: [Doctor.Fix]) {
        Task { @MainActor [weak self] in
            let env = await AIConfigSession.environment("")
            guard let self else { return }
            guard let preview = Doctor.fixPreview(fixes, config: self.loadSettings(), environment: env) else {
                self.showNotice(tr("没有要修的", "Nothing to fix"), client: nil)
                return
            }
            self.perform(self.composer.showFixPreview(preview, lines: preview.rows.map { $0.text(chinese: env.chinese) }), client: nil)
        }
    }

    /// `@doctor`'s panel: the model's explanation (or the summary) over the findings, numbered where a fix can be picked.
    @MainActor
    func doctorPanel(_ model: inout CandidateView.Model) {
        let state = composer.configState
        guard state.applied == nil, state.fixPreview == nil, let report = state.report else {
            if case .translating = composer.phase {
                model.status = .loading(tr("正在检查…", "Checking…"))
                model.footer = tr("检查中… · Esc 取消", "Checking… · Esc cancel")
            }
            return
        }
        // The fixes the model suggested are marked; ⏎ still applies only the safe ones (`Report.defaultFixes`).
        model.rows = composer.choices.enumerated().map { index, choice in
            CandidateView.Row(label: choice.label, text: Self.preview(choice.text),
                              comment: report.recommended.contains(index) ? tr("AI 建议", "suggested") : "",
                              style: .candidate, pickable: !choice.label.isEmpty)
        }
        model.highlighted = nil
        if let explanation = report.explanation {
            model.status = .hint(explanation)
        } else if !report.isFinal, report.recommended.isEmpty, composer.phase != .choosing {
            model.status = .loading(tr("正在检查…", "Checking…"))
        } else {
            model.status = .hint(report.summary)
        }
        let fixable = report.fixes.contains { $0 != nil }
        // "⏎ fix the safe ones" only when there are some (⏎ otherwise closes).
        model.footer = !report.isFinal ? tr("检查中… · Esc 取消", "Checking… · Esc cancel")
            : !fixable ? tr("⏎ / Esc 关闭", "⏎ / Esc close")
            : report.defaultFixes.isEmpty ? tr("数字 修这一项 · ⏎ / Esc 关闭", "Digits fix one · ⏎ / Esc close")
            : tr("数字 修这一项 · ⏎ 修安全的几项 · Esc 关闭", "Digits fix one · ⏎ fix the safe ones · Esc close")
        model.detail = lastElapsed.map { String(format: "%.1fs", $0) }
    }
}

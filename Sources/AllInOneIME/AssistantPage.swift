import AllInOneIMECore
import AppKit
import SwiftUI

/// Settings → Assistant, the page Settings opens on: settings changed by describing them (`AIConfig`, through
/// `AIConfigService` and the environment `AIConfigSession` builds) and the setup checked on this Mac (`Doctor`, with
/// `DoctorSession`'s probes and `DoctorService` for a question). One model for the process (`shared`): a preview, the
/// undo of the last changes and the findings stay while other pages are shown, and go when the input method quits.
@MainActor
final class AssistantModel: ObservableObject {
    static let shared = AssistantModel()

    // MARK: Change settings in a sentence

    /// What the user wants changed, as typed.
    @Published var request = ""
    /// The request is on its way to the model.
    @Published private(set) var working = false
    /// The changes to confirm: a typed request's, or a finding's fix (`fix`).
    @Published private(set) var preview: AIConfig.Preview?
    /// Its rows as shown, in the interface language of the moment it was made.
    @Published private(set) var lines: [String] = []
    /// Why there is no preview (no model, not understood, nothing to change), or what applying couldn't do: one line.
    @Published private(set) var message: String?
    /// "Changed 2 settings", while those changes can be undone (`AIConfigSession.lastApplied`) or after an action.
    @Published private(set) var applied: String?
    /// The changes applied wrote settings: Undo is offered.
    @Published private(set) var appliedWritesSettings = false
    /// What Undo did: what it put back, and what it left because it changed since.
    @Published private(set) var undone: String?
    /// Test Connection after the provider changed: running, then its result.
    @Published private(set) var connection: String?

    // MARK: Check for problems

    /// The findings, in `Doctor`'s order (problems first); empty until the first probe is in.
    @Published private(set) var findings: [Doctor.Finding] = []
    /// The probes (and the connection test, from Check) are running.
    @Published private(set) var checking = false
    /// What's wrong, in the user's words: Check asks the model about it (`DoctorService`).
    @Published var question = ""
    /// The model's explanation of the findings for `question`, and the findings whose fixes it named.
    @Published private(set) var explanation: String?
    @Published private(set) var recommended: [Int] = []
    /// The finding whose command was just copied ("Copied" for a moment).
    @Published private(set) var copied: Int?
    /// The ✓ rows shown though everything is fine (the disclosure opened).
    @Published var showsFine = false

    /// How many times the probes ran, and the connection test (the self-test counts them).
    private(set) var probes = 0
    private(set) var connectionTests = 0

    private var requestTask: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var lastProbe: Date?
    /// The last connection test's result, and the config it ran with: shown again with the probes while the config is
    /// as it was.
    private var tested: (config: Config, connection: Doctor.Facts.Connection)?

    init() {}

    var canPreview: Bool { !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !working }

    /// The last changes can still be undone (within ten minutes).
    var canUndo: Bool {
        appliedWritesSettings && AIConfigSession.lastApplied?.canUndo(at: AIConfigSession.now()) == true
    }

    // MARK: Request → preview → apply → undo

    /// The request sent (⌘⏎, Preview): a key typed into it never goes out (the key field opens instead); the answer
    /// becomes the preview, or the one line that says why there is none.
    func sendRequest() {
        let typed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        cancelRequest()
        clearOutcome()
        dismissPreview()
        let chinese = UIText.chinese
        let text = AIConfig.Text(chinese: chinese)
        let keys = AIConfig.droppingKeys(typed)
        if keys.dropped, keys.text.filter(\.isLetter).count < 2 {
            log.notice("assistant: a key typed into the request was dropped; nothing sent")
            message = text.droppedKey
            AIConfigSession.openKeyField(keys.provider ?? config().provider)
            return
        }
        let config = config()
        let models = AIConfigSession.knownModels()
        let service = AIConfigSession.service
        // The AWS profiles' names go to a cloud provider only when the request is about AWS or Bedrock.
        let showsAWS = service.onDevice || AIConfig.mentionsAWS(keys.text)
        log.notice("assistant: request sent (\(keys.text.count) chars, \(service.onDevice ? "on device" : "provider", privacy: .public))")
        working = true
        requestTask = Task { @MainActor [weak self] in
            let env = await AIConfigSession.environment(keys.text)
            let profiles = showsAWS ? await Task.detached { env.awsProfiles() }.value : []
            let context = AIConfigPrompt.Context(
                config: config, knownModels: models, awsProfiles: profiles, offeredProviders: env.offeredProviders,
                installedPacks: Set(Language.allCases.filter(env.packInstalled)), showsAWSProfile: showsAWS)
            let tools = AIConfigSession.tools(env)
            guard !Task.isCancelled else { return }
            do {
                let answer = try await service.ask(keys.text, context: context, tools: tools)
                guard let self, !Task.isCancelled else { return }
                self.working = false
                self.show(answer: answer.text, env: env, droppedKey: (keys.dropped, keys.provider))
            } catch {
                guard let self, !Task.isCancelled else { return }
                log.error("assistant: the request failed: \(AllInOneIMEInputController.errorKind(error), privacy: .public)")
                self.working = false
                self.message = UIText.describe(error)
            }
        }
    }

    /// The answer checked against the settings as they are now: the preview, or the line that says why not.
    private func show(answer: String, env: AIConfig.Environment, droppedKey: (dropped: Bool, provider: Provider?)) {
        let proposal = try? AIConfig.parse(answer)
        let config = config()
        let outcome = proposal.map { AIConfig.preview($0, config: config, environment: env, droppedKey: droppedKey) }
            ?? .failure(.notUnderstood)
        switch outcome {
        case let .success(preview):
            log.notice("assistant: \(preview.rows.count) rows, \(preview.edits.count) to apply")
            show(preview, chinese: env.chinese)
        case let .failure(failure):
            log.notice("assistant: no preview (\(String(describing: failure), privacy: .public))")
            message = AIConfig.failureLine(failure, proposal: proposal, config: config, environment: env)
        }
    }

    private func show(_ preview: AIConfig.Preview, chinese: Bool) {
        self.preview = preview
        lines = preview.rows.map { $0.text(chinese: chinese) }
    }

    /// Esc or Cancel while the request is on its way: nothing more comes of it.
    func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
        working = false
    }

    /// Cancel on the preview: nothing changes.
    func dismissPreview() {
        preview = nil
        lines = []
    }

    /// Apply: the changes written to the config file (the input method and Settings' other pages read it from there),
    /// with Undo for ten minutes; a fix's actions done; the key field opened when a provider needs a key (it is entered
    /// there, never here); Test Connection after the provider changed.
    func apply() {
        guard let preview, preview.canApply else { return }
        self.preview = nil
        lines = []
        clearOutcome()
        if !preview.edits.isEmpty {
            do {
                let applied = try AIConfig.applying(preview.edits, at: AIConfigSession.url, now: AIConfigSession.now())
                AIConfigSession.lastApplied = applied
                log.notice("assistant: \(applied.count) changes applied")
            } catch {
                log.error("assistant: couldn't write the settings: \(String(describing: error), privacy: .public)")
                message = tr("没有保存：", "Not saved: ") + UIText.describe(error)
                return
            }
            NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
        }
        // A fix's actions besides the settings: a file tidied, a pack downloaded, a pane opened.
        for action in preview.actions { DoctorSession.perform(action) }
        // Tidying the file (the repeated languages) writes it too: the other pages read it again.
        if preview.actions.contains(.resaveConfig) { NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil) }
        appliedWritesSettings = !preview.edits.isEmpty
        applied = preview.edits.isEmpty
            ? tr("已完成：", "Done: ") + preview.rows.filter { $0.action != nil }.map(\.label).joined(separator: tr("；", "; "))
            : Self.changed(preview.edits.count)
        if preview.edits.isEmpty, preview.actions.isEmpty { applied = nil }
        if let provider = preview.needsKey { AIConfigSession.openKeyField(provider) }
        if preview.changesProvider { testConnection() }
        reprobe()
    }

    /// "已改 2 项" / "Changed 2 settings".
    static func changed(_ count: Int) -> String {
        tr("已改 \(count) 项", count == 1 ? "Changed 1 setting" : "Changed \(count) settings")
    }

    /// Settings' own Test Connection on the config file as it is now; its line under the confirmation.
    private func testConnection() {
        connection = tr("正在测试连接…", "Testing the connection…")
        connectionTests += 1
        let url = AIConfigSession.url
        connectionTask?.cancel()
        connectionTask = Task { @MainActor [weak self] in
            let (ok, line) = await AIConfigSession.testConnection(url)
            guard let self, !Task.isCancelled else { return }
            self.connection = ok ? tr("✓ 连接正常：", "✓ Connection works: ") + line : tr("✗ 连接失败：", "✗ Connection failed: ") + line
        }
    }

    /// Undo: the values the last changes replaced, back (within ten minutes); a key changed since is left, and named.
    func undo() {
        let text = AIConfig.Text(chinese: UIText.chinese)
        defer {
            applied = nil
            appliedWritesSettings = false
            connection = nil
        }
        guard let last = AIConfigSession.lastApplied else {
            undone = text.nothingToUndo
            return
        }
        do {
            AIConfigSession.lastApplied = nil
            guard let report = try AIConfig.undoing(last, at: AIConfigSession.url, now: AIConfigSession.now()) else {
                undone = text.nothingToUndo
                return
            }
            log.notice("assistant: \(report.undone) changes undone, \(report.skipped.count) changed since and left as they are")
            NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
            undone = text.undone(skipped: report.skipped)
        } catch {
            undone = tr("没能撤销：", "Couldn't undo: ") + UIText.describe(error)
        }
        reprobe()
    }

    /// What a new request or apply replaces: the last outcome's lines.
    private func clearOutcome() {
        message = nil
        undone = nil
        connection = nil
        connectionTask?.cancel()
        if !canUndo {
            applied = nil
            appliedWritesSettings = false
        }
    }

    /// The page shown again: a confirmation whose undo has run out goes.
    func expireUndo() {
        if appliedWritesSettings, !canUndo {
            applied = nil
            appliedWritesSettings = false
            connection = nil
        }
    }

    // MARK: Check for problems

    /// The quick probes, as the page appears or Settings comes to the front: never a permission asked, a key read or the
    /// AI called. Not again while they run, nor within two seconds of the last (the page appearing and the window coming
    /// to the front at once), unless `now`.
    func probe(now: Bool = false) {
        guard !checking, now || lastProbe.map({ Date().timeIntervalSince($0) > 2 }) ?? true else { return }
        run(connection: false)
    }

    /// Check: the probes, then the connection test (it calls the AI provider) where it can tell anything; with a question,
    /// the model's explanation of the findings.
    func check() {
        checkTask?.cancel()
        checking = false
        run(connection: true)
    }

    /// The probes again after a fix (the last connection result kept while the config is as it was).
    private func reprobe() {
        guard !findings.isEmpty, !checking else { return }
        run(connection: false)
    }

    private func run(connection: Bool) {
        checking = true
        lastProbe = Date()
        probes += 1
        let question = connection ? self.question.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if connection {
            explanation = nil
            recommended = []
        }
        checkTask = Task { @MainActor [weak self] in
            var facts = await DoctorSession.probe()
            guard let self, !Task.isCancelled else { return }
            let chinese = UIText.chinese
            if let tested = self.tested, tested.config == facts.config { facts.connection = tested.connection }
            if connection, Doctor.canTestConnection(facts) {
                facts.connection = .running
                self.findings = Doctor.findings(facts, chinese: chinese)
                self.connectionTests += 1
                let url = AIConfigSession.url
                let outcome = try? await AIConfigService.withTimeout(DoctorSession.connectionTimeout) { @MainActor in
                    await AIConfigSession.testConnection(url)
                }
                guard !Task.isCancelled else { return }
                let seconds = Int(DoctorSession.connectionTimeout)
                facts.connection = outcome.map { $0.ok ? .ok($0.line) : .failed($0.line) }
                    ?? .failed(chinese ? "\(seconds) 秒内没有回应" : "no answer within \(seconds) s")
                if let config = facts.config { self.tested = (config, facts.connection) }
            }
            let findings = Doctor.findings(facts, chinese: chinese)
            self.findings = findings
            if !question.isEmpty {
                do {
                    // The model reads the findings in English, in the same order as the page's (the fixes' ids match).
                    let english = Doctor.findings(facts, chinese: false)
                    let answer = try await DoctorSession.service.ask(question, findings: english, config: facts.config ?? .default)
                    guard !Task.isCancelled else { return }
                    self.explanation = answer.explanation + (answer.onDevice ? "" : tr("（由你选的 AI 服务回答）", " (answered by your AI provider)"))
                    self.recommended = answer.fixes
                } catch {
                    guard !Task.isCancelled else { return }
                    self.explanation = tr("没能问 AI：", "Couldn't ask the AI: ") + UIText.describe(error)
                }
            }
            let (problems, warnings) = (findings.filter { $0.status == .problem }.count, findings.filter { $0.status == .warning }.count)
            log.notice("assistant: checks done (\(connection ? "with" : "without", privacy: .public) the connection): problems=\(problems) warnings=\(warnings)")
            self.checking = false
        }
    }

    /// Every finding is fine: they show as one line ("Everything looks good"), opened by a disclosure.
    var allFine: Bool { !findings.isEmpty && findings.allSatisfy { $0.status == .ok } }

    /// Fix on finding `index`: a config fix shows its changes in the preview above (Apply, Undo); the others act at once,
    /// as they did before. The probes run again after.
    func fix(_ index: Int) {
        guard findings.indices.contains(index), let fix = findings[index].fix else { return }
        switch fix {
        case .repairConfig, .resaveConfig:
            cancelRequest()
            clearOutcome()
            dismissPreview()
            Task { @MainActor [weak self] in
                let env = await AIConfigSession.environment("")
                guard let self else { return }
                if let preview = Doctor.fixPreview([fix], config: self.config(), environment: env) {
                    self.show(preview, chinese: env.chinese)
                } else {
                    self.message = tr("没有要修的", "Nothing to fix")
                }
            }
            return
        case let .openKeyField(provider):
            AIConfigSession.openKeyField(provider)
        case .enableInputMethod: DoctorSession.perform(.enableInputMethod)
        case let .openPrivacy(pane): DoctorSession.perform(.openPrivacy(pane))
        case let .downloadPack(language): DoctorSession.perform(.downloadPack(language))
        case .openAppleIntelligenceSettings: DoctorSession.perform(.openAppleIntelligenceSettings)
        case .checkForUpdates: DoctorSession.perform(.checkForUpdates)
        case let .copyCommand(command):
            DoctorSession.perform(.copyCommand(command))
            copied = index
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                if self?.copied == index { self?.copied = nil }
            }
        }
        log.notice("assistant: a fix was done")
        lastProbe = nil
        // A moment for what it started (the input method enabled again, a download) before the probes look again.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            self?.reprobe()
        }
    }

    private func config() -> Config { (try? Config.load(from: AIConfigSession.url)) ?? .default }

    /// Stops what's on its way (the self-test, between its parts).
    func reset() {
        cancelRequest()
        checkTask?.cancel()
        connectionTask?.cancel()
        (request, preview, lines, message, applied, appliedWritesSettings, undone, connection) = ("", nil, [], nil, nil, false, nil, nil)
        (findings, checking, question, explanation, recommended, copied, showsFine) = ([], false, "", nil, [], nil, false)
        (probes, connectionTests, lastProbe, tested) = (0, 0, nil, nil)
    }
}

/// The page: the request and its preview, then the checks.
struct AssistantPage: View {
    @ObservedObject var assistant: AssistantModel
    @FocusState private var requestFocused: Bool

    var body: some View {
        changeSection
        checkSection
    }

    // MARK: Change settings in a sentence

    @ViewBuilder private var changeSection: some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                TextField(text: $assistant.request, prompt: Text(tr("例如：翻译成日语和英语", "e.g. translate into Japanese and English")),
                          axis: .vertical) {
                    Text(tr("想怎么改", "What to change"))
                }
                .labelsHidden()
                .lineLimit(2...5)
                .focused($requestFocused)
                .onSubmit { assistant.sendRequest() }
                if assistant.working {
                    ProgressView().controlSize(.small).padding(.top, 2)
                    Button(tr("取消", "Cancel")) { assistant.cancelRequest() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button(tr("预览", "Preview")) { assistant.sendRequest() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!assistant.canPreview)
                }
            }
            if let preview = assistant.preview {
                ForEach(Array(preview.rows.enumerated()), id: \.offset) { index, row in
                    previewRow(row, line: assistant.lines.indices.contains(index) ? assistant.lines[index] : "")
                }
                if preview.droppedKey {
                    Label(AIConfig.Text(chinese: UIText.chinese).droppedKeyPreview, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                if let note = preview.note {
                    Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button(tr("取消", "Cancel")) { assistant.dismissPreview() }
                        .keyboardShortcut(.cancelAction)
                    Button(tr("应用", "Apply")) { assistant.apply() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!preview.canApply)
                }
            }
            if let message = assistant.message {
                Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
            }
            if let applied = assistant.applied {
                HStack {
                    Label(applied, systemImage: "checkmark.circle.fill").labelStyle(StatusLabelStyle(color: .green))
                    Spacer()
                    if assistant.canUndo {
                        Button(tr("撤销", "Undo")) { assistant.undo() }
                    }
                }
                if let connection = assistant.connection {
                    Text(connection).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            if let undone = assistant.undone {
                Label(undone, systemImage: "arrow.uturn.backward.circle").foregroundStyle(.secondary)
            }
        } header: {
            SectionTitle(tr("用一句话改设置", "Change settings in a sentence"), icon: SettingsPage.assistant.icon)
        }
    }

    /// A change as Settings names it, old → new; a refused part, a key to enter or an action as one line.
    @ViewBuilder private func previewRow(_ row: AIConfig.Row, line: String) -> some View {
        switch row.status {
        case .change:
            LabeledContent(row.label) {
                Text((row.old ?? "") + " → " + (row.new ?? "")).multilineTextAlignment(.trailing)
            }
        case .refused:
            Text(line).foregroundStyle(.secondary)
        case .needsKey:
            Label(line, systemImage: "key.fill").labelStyle(StatusLabelStyle(color: .orange))
        case .action:
            Text(line)
        }
    }

    // MARK: Check for problems

    @ViewBuilder private var checkSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField(text: $assistant.question, prompt: Text(tr("遇到什么问题？（可选）", "What's wrong? (optional)"))) {
                    Text(tr("问题", "Question"))
                }
                .labelsHidden()
                .onSubmit { if !assistant.question.trimmingCharacters(in: .whitespaces).isEmpty { assistant.check() } }
                Button(tr("检查", "Check")) { assistant.check() }
                    .disabled(assistant.checking)
            }
            if let explanation = assistant.explanation {
                Label(explanation, systemImage: "sparkles").labelStyle(StatusLabelStyle(color: .purple))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if assistant.allFine {
                DisclosureGroup(isExpanded: $assistant.showsFine) {
                    findingRows
                } label: {
                    Label(tr("一切正常", "Everything looks good"), systemImage: "checkmark.circle.fill")
                        .labelStyle(StatusLabelStyle(color: .green))
                }
            } else {
                findingRows
            }
        } header: {
            HStack(spacing: 8) {
                SectionTitle(tr("检查问题", "Check for problems"), icon: SettingsPage.assistant.icon)
                if assistant.checking {
                    ProgressView().controlSize(.small).padding(.top, 6)
                }
            }
        }
        .onAppear {
            assistant.expireUndo()
            assistant.probe()
            AIConfigSession.prewarmIfDue()  // the on-device model and the apps, before a request
            // The request field, once the page is up.
            DispatchQueue.main.async { requestFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            assistant.probe()
        }
    }

    @ViewBuilder private var findingRows: some View {
        ForEach(Array(assistant.findings.enumerated()), id: \.offset) { index, finding in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: Self.symbol(finding.status)).foregroundStyle(Self.color(finding.status))
                    .accessibilityLabel(finding.status.mark)
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.title)
                    if let detail = finding.detail {
                        Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if finding.fix != nil {
                    if assistant.copied == index {
                        Text(tr("已复制", "Copied")).foregroundStyle(.secondary)
                    } else if assistant.recommended.contains(index) {
                        Button(tr("修复", "Fix")) { assistant.fix(index) }.buttonStyle(.borderedProminent)
                    } else {
                        Button(tr("修复", "Fix")) { assistant.fix(index) }
                    }
                }
            }
        }
    }

    static func symbol(_ status: Doctor.Status) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.circle.fill"
        }
    }

    static func color(_ status: Doctor.Status) -> Color {
        switch status {
        case .ok: return .green
        case .warning: return .orange
        case .problem: return .red
        }
    }
}

/// A label whose icon has a color of its own and whose title is in the text's.
private struct StatusLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.foregroundStyle(color)
            configuration.title
        }
    }
}

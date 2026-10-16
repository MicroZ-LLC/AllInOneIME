import AllInOneIMECore
import AppKit
import SwiftUI

/// Settings → Custom Commands → Extension Sources: each Git source with its commit, what's new and its buttons, and
/// "Add from Link…", which clones one and shows what it holds before anything of it loads (`ExtensionSourceSheet`).
struct ExtensionSourcesSection: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var sources = ExtensionSourceController.shared
    /// The add sheet (nil: closed), and the source whose sheet reviews it again (one in the config not trusted yet).
    @State private var adding: ExtensionSourceSheet.Start?
    @State private var removing: ExtensionSource?
    @State private var pinning: ExtensionSource?
    @State private var pinText = ""

    var body: some View {
        Section {
            ForEach(model.config.extensionSources, id: \.url) { source in row(source) }
            if model.config.extensionSources.isEmpty {
                Text(tr("还没有来源。来源是一个 Git 仓库里的扩展包：用你自己的 git 和 SSH 设置克隆，检查之后才启用，有新提交时由你点「更新」。",
                        "No sources yet. A source is an extension bundle in a Git repository: cloned with your own git and SSH setup, enabled only after you've reviewed it, and updated when you click Update."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(tr("从链接添加…", "Add from Link…")) { adding = ExtensionSourceSheet.Start(source: ExtensionSource(url: ""), cloneNow: false) }
        } header: {
            SectionTitle(tr("扩展来源", "Extension Sources"), icon: CommandIcons.scripts)
        } footer: {
            Text(tr("支持 ssh://、git@主机:路径、https:// 和 file:// 地址。不会自动更新：每天检查一次，有新提交时在这里提示。更新只做快进，不运行任何钩子；固定（pin）到标签或提交的来源不检查。",
                    "ssh://, git@host:path, https:// and file:// addresses. Nothing updates by itself: sources are checked once a day and new commits are shown here. Update only fast-forwards and runs no hooks; a source pinned to a tag or commit isn't checked."))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(!model.canSave)
        .sheet(item: $adding) { start in
            ExtensionSourceSheet(model: model, start: start)
        }
        .confirmationDialog(tr("移除这个来源？", "Remove this source?"),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(tr("移除", "Remove"), role: .destructive) {
                if let source = removing { remove(source) }
                removing = nil
            }
        } message: {
            Text(tr("克隆的文件夹会移到废纸篓，它的命令不再加载；偏好设置会保留。", "Its clone goes to the Trash and its commands stop loading; its preferences are kept."))
        }
        .alert(tr("固定到标签或提交", "Pin to a Tag or Commit"),
               isPresented: Binding(get: { pinning != nil }, set: { if !$0 { pinning = nil } })) {
            TextField(tr("标签或提交", "Tag or commit"), text: $pinText)
            Button(tr("固定", "Pin")) {
                if let source = pinning { setPin(source, pinText.trimmingCharacters(in: .whitespaces)) }
                pinning = nil
            }
            Button(tr("取消", "Cancel"), role: .cancel) { pinning = nil }
        } message: {
            Text(tr("固定后停在这个版本，不再检查更新。", "It stays at that version and isn't checked for updates."))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in sources.reload() }
        // The command line (or the file) may have changed the load list: the extensions are read again.
        .onChange(of: model.config.extensionFolders) { model.refreshExtensions() }
    }

    // MARK: A source

    @ViewBuilder private func row(_ source: ExtensionSource) -> some View {
        let status = sources.statuses[source.url]
        let trusted = ExtensionSources.isTrusted(source, status)
        let enabled = ExtensionSources.isEnabled(source, in: model.config, root: sources.root)
        let busy = sources.busy.contains(source.url)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                IconTile(icon: CommandIcons.scripts)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(of: source))
                    Text(source.url).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Text(detail(source, status, trusted: trusted, enabled: enabled)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if !trusted {
                    Button(tr("检查并启用…", "Review…")) { adding = ExtensionSourceSheet.Start(source: source, cloneNow: true) }
                        .disabled(busy)
                } else if !enabled {
                    // Taken out of the load list (Script Extensions → Remove): back in, without another review.
                    Button(tr("启用", "Enable")) {
                        ExtensionSources.enable(source, in: &model.config, root: sources.root)
                        model.save()
                        model.refreshExtensions()
                    }
                } else if let status, source.pin == nil, !status.updates.isEmpty {
                    Text(ExtensionSourceText.updates(status.updates.count))
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                    if status.fastForward {
                        Button(tr("更新", "Update")) { Task { await sources.update(source); model.refreshExtensions() } }.disabled(busy)
                    } else {
                        Button(tr("重新克隆", "Re-clone")) { Task { await sources.reclone(source); model.refreshExtensions() } }.disabled(busy)
                    }
                }
                if trusted { menu(source, status) }
            }
            if let status, trusted, source.pin == nil, !status.updates.isEmpty { commitLog(status) }
            if let error = status?.error {
                VStack(alignment: .leading, spacing: 2) {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.caption)
                    Text(ExtensionSourceText.gitHint(source.url)).font(.caption).foregroundStyle(.secondary)
                    if let hint = source.authHint { Text(hint).font(.caption).foregroundStyle(.secondary) }
                }
                .textSelection(.enabled)
            }
        }
    }

    /// The bundle's title when it's loaded, else the repository's name.
    private func title(of source: ExtensionSource) -> String {
        let folder = ExtensionSources.comparable(ExtensionSources.bundleFolder(for: source, root: sources.root).path)
        return model.extensionIndex.bundles.first { ExtensionSources.comparable($0.folder.path) == folder }?.title ?? source.repositoryName
    }

    /// "a1b2c3d · 2 hr ago · main · checked 5 min ago", or why it isn't loaded.
    private func detail(_ source: ExtensionSource, _ status: ExtensionSourceStatus?, trusted: Bool, enabled: Bool) -> String {
        guard trusted, let status else { return tr("还没有检查并启用：它的命令不会加载", "Not reviewed and enabled yet: its commands don't load") }
        var parts = [ExtensionSourceText.commit(status.commit, status.commitDate)]
        if let pin = source.pin {
            parts.append(tr("固定在 \(pin)", "pinned to \(pin)"))
        } else if let branch = source.branch ?? status.branch {
            parts.append(branch)
        }
        if source.pin == nil {
            parts.append(status.checked.map { tr("检查于 ", "checked ") + DashboardText.ago($0, now: Date(), chinese: UIText.chinese) }
                         ?? tr("还没检查过", "not checked yet"))
            if !source.autoCheck { parts.append(tr("不自动检查", "not checked automatically")) }
        }
        if !enabled { parts.append(tr("没有启用", "not enabled")) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// What's new: subject, author, date (the newest few).
    @ViewBuilder private func commitLog(_ status: ExtensionSourceStatus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(status.updates.prefix(5), id: \.sha) { commit in
                HStack(spacing: 6) {
                    Text(commit.shortSHA).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(commit.subject).font(.caption).lineLimit(1)
                    Text("— " + commit.author + (commit.date.map { ", " + DashboardText.ago($0, now: Date(), chinese: UIText.chinese) } ?? ""))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if status.updates.count > 5 {
                Text(tr("还有 \(status.updates.count - 5) 个", "and \(status.updates.count - 5) more")).font(.caption).foregroundStyle(.secondary)
            }
            if !status.fastForward {
                Text(ExtensionSourceText.describe(ExtensionSourceError.notFastForward)).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.leading, 28)
    }

    private func menu(_ source: ExtensionSource, _ status: ExtensionSourceStatus?) -> some View {
        Menu {
            if source.pin == nil {
                Button(tr("立即检查", "Check Now")) { Task { await sources.check(source) } }
            }
            Toggle(tr("自动检查更新", "Check for Updates Automatically"), isOn: Binding(get: { source.autoCheck }, set: { on in
                change(source) { $0.autoCheck = on }
            }))
            Divider()
            if source.pin != nil {
                Button(tr("取消固定", "Unpin")) { setPin(source, nil) }
            } else if let commit = status?.commit {
                Button(tr("固定在当前提交", "Pin to This Commit")) { setPin(source, String(commit.prefix(12))) }
            }
            Button(tr("固定到…", "Pin to…")) {
                pinText = source.pin ?? ""
                pinning = source
            }
            Button(tr("重新克隆", "Re-clone")) { Task { await sources.reclone(source); model.refreshExtensions() } }
            Button(tr("在访达中显示", "Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([ExtensionSources.bundleFolder(for: source, root: sources.root)])
            }
            Divider()
            Button(tr("移除…", "Remove…"), role: .destructive) { removing = source }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(tr("更多", "More"))
    }

    // MARK: Changes

    private func change(_ source: ExtensionSource, _ edit: (inout ExtensionSource) -> Void) {
        guard let index = model.config.extensionSources.firstIndex(where: { $0.url == source.url }) else { return }
        edit(&model.config.extensionSources[index])
        model.save()
    }

    /// A new pin (nil: follow the branch again): saved, then the clone checked out at it (or checked).
    private func setPin(_ source: ExtensionSource, _ pin: String?) {
        let pin = pin.flatMap { $0.isEmpty ? nil : $0 }
        change(source) { $0.pin = pin }
        Task {
            await sources.pin(source, to: pin)
            model.refreshExtensions()
        }
    }

    private func remove(_ source: ExtensionSource) {
        do {
            try sources.remove(source)
        } catch {
            log.error("extension source: couldn't move the clone to the Trash: \(String(describing: error), privacy: .public)")
        }
        ExtensionSources.remove(source, from: &model.config, root: sources.root)
        model.save()
        model.refreshExtensions()
    }
}

/// "Add from Link…": the address (and, if wanted, the branch, the bundle's folder, a pin), the clone, the bundle to use
/// when there are several, then the review: what the bundle is, its commands, the programs they run, its preferences,
/// where it's from and at which commit, under the warning that it isn't signed. Enable is the only way in; Cancel
/// deletes the clone.
struct ExtensionSourceSheet: View {
    struct Start: Identifiable {
        let id = UUID()
        var source: ExtensionSource
        /// A source from the config being reviewed: cloned at once.
        var cloneNow: Bool
    }

    @ObservedObject var model: SettingsModel
    let start: Start
    @ObservedObject private var sources = ExtensionSourceController.shared
    @Environment(\.dismiss) private var dismiss

    enum Step {
        case form
        case cloning
        case pick(ExtensionSourceManager.Clone)
        case review(ExtensionSourceManager.Clone, ExtensionSourceReview)
        case failed(String)
    }

    @State private var url: String
    @State private var branch: String
    @State private var path: String
    @State private var pin: String
    @State private var step: Step = .form

    init(model: SettingsModel, start: Start, step: Step = .form) {
        self.model = model
        self.start = start
        _url = State(initialValue: start.source.url)
        _branch = State(initialValue: start.source.branch ?? "")
        _path = State(initialValue: start.source.path ?? "")
        _pin = State(initialValue: start.source.pin ?? "")
        _step = State(initialValue: step)
    }

    /// The source as the form has it.
    private var source: ExtensionSource {
        func value(_ text: String) -> String? {
            let text = text.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        var source = start.source
        source.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        source.branch = value(branch)
        source.path = value(path)
        source.pin = value(pin)
        return source
    }

    private var problem: String? {
        guard !url.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        do {
            _ = try ExtensionSources.validate(url)
        } catch {
            return ExtensionSourceText.describe(error)
        }
        if !start.cloneNow, model.config.extensionSources.contains(where: { $0.url == source.url }) {
            return ExtensionSourceText.describe(ExtensionSourceError.alreadyAdded)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            HStack {
                if case let .failed(message) = step {
                    Text(message).foregroundStyle(.red).font(.callout).lineLimit(3).textSelection(.enabled)
                } else if let problem {
                    Text(problem).foregroundStyle(.red).font(.callout)
                }
                Spacer()
                Button(tr("取消", "Cancel")) { cancel() }.keyboardShortcut(.cancelAction)
                switch step {
                case .form, .failed:
                    Button(tr("克隆", "Clone")) { Task { await clone() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty || problem != nil)
                case .cloning, .pick:
                    EmptyView()
                case let .review(clone, review):
                    Button(tr("启用", "Enable")) { enable(clone, review) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(review.bundle == nil)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 600)
        .task { if start.cloneNow, case .form = step { await clone() } }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .form, .failed: form
        case .cloning:
            VStack(spacing: 12) {
                ProgressView()
                Text(tr("正在用你的 git 克隆 \(source.url)…", "Cloning \(source.url) with your git…")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .pick(clone): picker(clone)
        case let .review(_, review): ExtensionSourceReviewView(review: review)
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField(tr("Git 地址", "Git address"), text: $url, prompt: Text("git@github.com:you/my-extensions.git"))
                    .font(.body.monospaced())
                TextField(tr("分支", "Branch"), text: $branch, prompt: Text(tr("默认分支", "the default branch")))
                TextField(tr("扩展包所在文件夹", "Bundle folder"), text: $path, prompt: Text(tr("自动查找 extension.json", "found by its extension.json")))
                TextField(tr("固定到标签或提交", "Pin to a tag or commit"), text: $pin, prompt: Text(tr("不固定：跟随分支", "none: follow the branch")))
            } footer: {
                Text(tr("用你自己的 git 和 SSH 设置（密钥、ssh-agent、~/.ssh/config）克隆到 ~/Library/Application Support/AllInOneIME/Sources。克隆之后先给你看里面有什么，点「启用」之前什么都不会加载或运行。",
                        "Cloned with your own git and SSH setup (keys, agent, ~/.ssh/config) into ~/Library/Application Support/AllInOneIME/Sources. You see what it holds first: nothing in it loads or runs before you click Enable."))
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            if case .failed = step {
                Section {
                    Text(ExtensionSourceText.gitHint(source.url)).font(.caption).foregroundStyle(.secondary)
                    if let hint = start.source.authHint { Text(hint).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func picker(_ clone: ExtensionSourceManager.Clone) -> some View {
        Form {
            Section {
                ForEach(clone.bundles, id: \.self) { folder in
                    Button(folder.isEmpty ? tr("（仓库根目录）", "(the repository's root)") : folder) {
                        path = folder
                        review(clone, path: folder)
                    }
                    .buttonStyle(.link)
                }
            } header: {
                Text(tr("这个仓库里有好几个扩展包，用哪一个？", "The repository has several bundles. Which one?"))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Steps

    private func clone() async {
        step = .cloning
        do {
            let clone = try await sources.cloneForReview(source)
            if let path = source.path {
                review(clone, path: try ExtensionSources.resolveBundlePath(path, in: clone.folder))
            } else if clone.bundles.count > 1 {
                step = .pick(clone)
            } else {
                review(clone, path: try ExtensionSources.resolveBundlePath(nil, in: clone.folder))
            }
        } catch {
            // A clone that can't be used (no bundle in it) goes, unless it's a trusted source's.
            if !ExtensionSources.isTrusted(source, sources.statuses[source.url]) { sources.discard(source) }
            step = .failed(ExtensionSourceText.describe(error))
        }
    }

    private func review(_ clone: ExtensionSourceManager.Clone, path: String) {
        var picked = source
        picked.path = path.isEmpty ? nil : path
        let review = ExtensionSourceReview.make(bundleFolder: ExtensionSources.bundleFolder(for: picked, root: sources.root), path: path,
                                                url: clone.status.url, commit: clone.status.commit, commitDate: clone.status.commitDate,
                                                config: model.config, plugins: model.plugins, found: LiveExtensions.found)
        step = .review(clone, review)
    }

    private func enable(_ clone: ExtensionSourceManager.Clone, _ review: ExtensionSourceReview) {
        var enabled = source
        enabled.path = review.path.isEmpty ? nil : review.path
        ExtensionSources.enable(enabled, in: &model.config, root: sources.root)
        model.save()
        sources.trust(clone)
        model.refreshExtensions()
        dismiss()
    }

    private func cancel() {
        switch step {
        case .pick, .review:
            // A source the config already has keeps its clone only once trusted; a new one's clone goes.
            if !ExtensionSources.isTrusted(source, sources.statuses[source.url]) { sources.discard(source) }
        default: break
        }
        dismiss()
    }
}

/// The review itself: the warning, the bundle, its commands and what they run, its preferences, where it's from.
struct ExtensionSourceReviewView: View {
    let review: ExtensionSourceReview

    var body: some View {
        Form {
            Section {
                Label(ExtensionSourceText.unsigned(review.url), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(.orange)
                LabeledContent(tr("来源", "Source")) {
                    Text(review.url + (review.path.isEmpty ? "" : "  (\(review.path))")).font(.caption.monospaced()).textSelection(.enabled)
                }
                LabeledContent(tr("提交", "Commit")) {
                    Text(ExtensionSourceText.commit(review.commit, review.commitDate)
                         + (review.commitDate.map { " (" + $0.formatted(date: .abbreviated, time: .shortened) + ")" } ?? ""))
                        .font(.caption.monospaced())
                }
            }
            Section {
                if let bundle = review.bundle {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bundle.title).font(.headline)
                        Text([bundle.name, bundle.version, bundle.author].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if let description = bundle.description { Text(description).font(.callout) }
                    }
                } else {
                    Label(tr("这个扩展包加载不了：", "This bundle can't be loaded: ") + (review.problem.map { "\($0)" } ?? ""),
                          systemImage: "xmark.octagon").foregroundStyle(.red)
                }
            } header: {
                Text(tr("扩展包", "Bundle"))
            }
            Section {
                ForEach(review.commands, id: \.name) { command in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("@" + command.name).font(.body.monospaced())
                            Text(command.title)
                            Text(Self.output(command.output) + (command.background ? tr("，后台", ", background") : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let description = command.description { Text(description).font(.caption).foregroundStyle(.secondary) }
                        Text(tr("运行：", "Runs: ") + command.program).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        if let hidden = command.hidden {
                            Label(UIText.describe(hidden, file: URL(fileURLWithPath: command.program)), systemImage: "eye.slash")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .opacity(command.hidden == nil ? 1 : 0.6)
                }
                ForEach(review.skipped, id: \.self) { skipped in
                    Label(tr("没有加载 \(skipped.file.lastPathComponent)：", "Not loaded, \(skipped.file.lastPathComponent): ")
                          + UIText.describe(skipped.problem, file: skipped.file), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text(tr("命令和它们运行的程序", "Commands and the programs they run"))
            }
            if !review.preferences.isEmpty {
                Section {
                    ForEach(review.preferences, id: \.name) { preference in
                        LabeledContent(preference.title) {
                            Text(preference.kind.rawValue + (preference.required ? tr("，必填", ", required") : "")).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(tr("偏好设置", "Preferences"))
                }
            }
        }
        .formStyle(.grouped)
    }

    static func output(_ output: ScriptCommand.Output) -> String {
        switch output {
        case .insert: return tr("上屏", "inserts")
        case .show: return tr("显示", "shows")
        case .list: return tr("列表", "lists")
        case .silent: return tr("静默", "silent")
        }
    }
}

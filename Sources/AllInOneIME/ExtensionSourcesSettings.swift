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
    /// What went wrong with the last Remove, Pin or Unpin, said under the sources.
    @State private var actionError: String?

    var body: some View {
        Section {
            ForEach(model.config.extensionSources, id: \.url) { source in row(source) }
            if model.config.extensionSources.isEmpty {
                Text(tr("还没有来源。来源是一个 Git 仓库里的扩展包：用你自己的 git 和 SSH 设置克隆，检查之后才启用，有新提交时由你点「更新」。",
                        "No sources yet. A source is an extension bundle in a Git repository: cloned with your own git and SSH setup, enabled only after you've reviewed it, and updated when you click Update."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let actionError {
                Label(actionError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red).textSelection(.enabled)
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
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            sources.reload()
            quarantine()
        }
        .onAppear { quarantine() }
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
                    Text(loaded(source, trusted: trusted, enabled: enabled)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if !trusted {
                    Button(tr("检查并启用…", "Review…", key: "extensionSource.reviewAndEnable")) { adding = ExtensionSourceSheet.Start(source: source, cloneNow: true) }
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
                        // A force push: the new history is reviewed like a new source before it replaces the clone.
                        Button(tr("重新克隆…", "Re-clone…")) { adding = ExtensionSourceSheet.Start(source: source, cloneNow: true) }.disabled(busy)
                    }
                }
                if trusted { menu(source, status).disabled(busy) }
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

    /// The settings' images: the sample sources' commands, shown as loaded (their clones aren't on this Mac).
    static var shownLoaded: [String: [String]]?

    /// What of the source actually loads now: its commands, or why none do.
    private func loaded(_ source: ExtensionSource, trusted: Bool, enabled: Bool) -> String {
        if let shown = Self.shownLoaded?[source.url] { return tr("已加载：", "Loaded: ") + shown.joined(separator: " ") }
        let folder = ExtensionSources.comparable(ExtensionSources.bundleFolder(for: source, root: sources.root).path)
        let bundle = model.extensionIndex.bundles.first { ExtensionSources.comparable($0.folder.path) == folder }?.name
        // Each as it is offered: under its alias where its name is taken, or said to be off or left out.
        func listed(_ name: String, offeredAs: String?, hidden: Bool, on: Bool) -> String {
            if !on { return "@" + name + tr("（已关闭）", " (off)") }
            if hidden { return "@" + name + tr("（名字被占用，没有加载）", " (name taken, not loaded)") }
            return "@" + (offeredAs ?? name)
        }
        let off = Set(model.config.disabledExtensions)
        let commands: [String] = model.extensionIndex.commands.filter { ExtensionSources.comparable($0.extensionDirectory.path) == folder }
            .map { command in
                listed(command.name, offeredAs: model.extensionNames[command.id], hidden: model.hiddenExtensions[command.id] != nil,
                       on: !off.contains(command.id) && !(command.source.bundleName.map(off.contains) ?? false))
            }
        let snippets: [String] = model.extensionIndex.snippets.filter { $0.bundle == bundle }.map { snippet in
            listed(snippet.name, offeredAs: model.snippetNames[snippet.id], hidden: model.hiddenSnippets[snippet.id] != nil,
                   on: !off.contains(snippet.id) && !off.contains(snippet.bundle))
        }
        let names = commands + snippets
        if !names.isEmpty { return tr("已加载：", "Loaded: ") + names.joined(separator: " ") }
        if !trusted { return tr("没有加载：还没检查过", "Nothing loaded: not reviewed yet") }
        if !enabled { return tr("没有加载：不在加载列表里", "Nothing loaded: not in the load list") }
        if !FileManager.default.fileExists(atPath: folder) { return tr("没有加载：克隆不在了，请重新克隆", "Nothing loaded: the clone is missing; re-clone it") }
        if let problem = model.skippedExtensions.first(where: { ExtensionSources.comparable($0.file.deletingLastPathComponent().path) == folder }) {
            return tr("没有加载：", "Nothing loaded: ") + UIText.describe(problem.problem, file: problem.file)
        }
        return tr("没有加载：扩展包里没有能用的命令", "Nothing loaded: the bundle has no usable commands")
    }

    /// Folders of the sources folder in the load list that aren't a reviewed source's bundle: taken out, and saved.
    private func quarantine() {
        guard model.canSave, !ExtensionSources.quarantine(&model.config, statuses: sources.statuses, root: sources.root).isEmpty else { return }
        model.save()
        model.refreshExtensions()
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
            parts.append(status.checked.map {
                let ago = RelativeTime.ago($0, now: Date(), language: UIText.language, style: .short)
                return tr("检查于 \(ago)", "checked \(ago)")
            }
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
                    let ago = commit.date.map { RelativeTime.ago($0, now: Date(), language: UIText.language, style: .short) }
                    Text("— " + commit.author + (ago.map { ", " + $0 } ?? ""))
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
            Button(tr("重新克隆…", "Re-clone…")) { adding = ExtensionSourceSheet.Start(source: source, cloneNow: true) }
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

    /// A new pin (nil: back to the branch's newest commit): the clone checked out first, and the pin saved only when
    /// that worked.
    private func setPin(_ source: ExtensionSource, _ pin: String?) {
        let pin = pin.flatMap { $0.isEmpty ? nil : $0 }
        actionError = nil
        Task {
            let error = await sources.pin(source, to: pin)
            if pin == nil, case ExtensionSourceError.notFastForward? = error {
                // The pinned commit isn't in the branch's recent history: the branch is cloned anew and reviewed; the pin
                // is cleared in the config only when that's enabled.
                var following = source
                following.pin = nil
                adding = ExtensionSourceSheet.Start(source: following, cloneNow: true)
            } else if let error {
                actionError = tr("没有改固定：", "The pin wasn't changed: ") + ExtensionSourceText.describe(error)
            } else {
                change(source) { $0.pin = pin }
            }
            model.refreshExtensions()
        }
    }

    private func remove(_ source: ExtensionSource) {
        actionError = sources.remove(source).map { error in
            tr("来源已移除，但克隆没能移到废纸篓（\(error.localizedDescription)），它还在 ",
               "The source is removed, but its clone couldn't go to the Trash (\(error.localizedDescription)); it's still at ")
                + ExtensionStore.abbreviated(ExtensionSources.cloneFolder(for: source.url, root: sources.root).path)
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
    @State private var cancelled = CancelFlag()

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
                    Text(message).foregroundStyle(.red).font(.callout).lineLimit(ExtensionSources.maxMessageLines).textSelection(.enabled)
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
        let token = cancelled
        do {
            let staged = try await sources.stageForReview(source)
            // Cancelled while git was at work: the result goes as soon as it's there.
            guard !token.value else {
                sources.discard(staged)
                return
            }
            do {
                if let path = source.path {
                    review(staged, path: try ExtensionSources.resolveBundlePath(path, in: staged.folder))
                } else if staged.bundles.count > 1 {
                    step = .pick(staged)
                } else {
                    review(staged, path: try ExtensionSources.resolveBundlePath(nil, in: staged.folder))
                }
            } catch {
                sources.discard(staged)
                throw error
            }
        } catch {
            guard !token.value else { return }
            step = .failed(ExtensionSourceText.describe(error))
        }
    }

    private func review(_ staged: ExtensionSourceManager.Clone, path: String) {
        let folder = path.isEmpty ? staged.folder : staged.folder.appendingPathComponent(path, isDirectory: true)
        // Next to what loads now, less this source's own folder (a re-clone replaces it).
        var others = model.config
        let own = ExtensionSources.comparable(ExtensionSources.bundleFolder(for: source, root: sources.root).path)
        others.extensionFolders.removeAll { ExtensionSources.comparable($0) == own }
        let review = ExtensionSourceReview.make(bundleFolder: folder, path: path, url: staged.status.url, commit: staged.status.commit,
                                                commitDate: staged.status.commitDate, config: others, plugins: model.plugins,
                                                found: LiveExtensions.found, repository: staged.folder)
        step = .review(staged, review)
    }

    /// Enable: the staged clone takes the source's place, trusted; the bundle's folder in the load list.
    private func enable(_ staged: ExtensionSourceManager.Clone, _ review: ExtensionSourceReview) {
        var enabled = source
        enabled.path = review.path.isEmpty ? nil : review.path
        do {
            try sources.install(staged)
        } catch {
            sources.discard(staged)
            step = .failed(ExtensionSourceText.describe(error))
            return
        }
        ExtensionSources.enable(enabled, in: &model.config, root: sources.root)
        model.save()
        model.refreshExtensions()
        dismiss()
    }

    /// Cancel: a staged clone is deleted (the one in place, if any, is left as it is); a clone still under way is
    /// deleted when it's done.
    private func cancel() {
        cancelled.value = true
        switch step {
        case let .pick(staged), let .review(staged, _): sources.discard(staged)
        default: break
        }
        dismiss()
    }
}

/// Set when the sheet is cancelled; a clone that finishes later reads it.
final class CancelFlag {
    var value = false
}

/// The review itself: the warning, the bundle, its commands and what they run, its snippets (they run nothing), its
/// preferences, where it's from.
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
                    Label(tr("这个扩展包加载不了：", "This bundle can't be loaded: ")
                          + (review.problem.map { UIText.describe($0, file: URL(fileURLWithPath: review.path.isEmpty ? ExtensionBundle.manifestName : review.path + "/" + ExtensionBundle.manifestName)) } ?? ""),
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
                        if let status = command.status {
                            Text(tr("状态行运行：", "Status line runs: ") + status).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let hidden = command.hidden {
                            Label(UIText.describe(hidden, file: URL(fileURLWithPath: command.program)), systemImage: "eye.slash")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let target = command.leavesRepository {
                            Label(tr("它的脚本是指向仓库外面的链接：\(target)", "Its script is a link out of the repository: \(target)"),
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .opacity(command.hidden == nil ? 1 : 0.6)
                }
                ForEach(review.snippets, id: \.name) { snippet in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("@" + snippet.name).font(.body.monospaced())
                            Text(snippet.text).lineLimit(1)
                            Text(tr("插入文字", "Insert text")).font(.caption).foregroundStyle(.secondary)
                        }
                        if let hidden = snippet.hidden {
                            Label(UIText.describe(hidden, file: URL(fileURLWithPath: ExtensionBundle.manifestName)), systemImage: "eye.slash")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .opacity(snippet.hidden == nil ? 1 : 0.6)
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

/// The menu bar panel's quiet line when extension sources have new commits ("Extension sources: 3 updates"), like the
/// app's own update line; a click opens Settings → Custom Commands. Nothing when there are none.
struct ExtensionSourceNotice: View {
    @ObservedObject var sources: ExtensionSourceController
    /// The sources of the config as it is now (the self-test passes its own).
    var configured: () -> [ExtensionSource] = { LiveConfig.current.extensionSources }
    let open: () -> Void

    var body: some View {
        let count = sources.updateCount(for: configured())
        if count > 0 {
            Button(action: open) {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox.circle.fill").foregroundStyle(Color.accentColor)
                    Text(tr("扩展来源：", "Extension sources: ") + ExtensionSourceText.updates(count)).font(.system(size: 12)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(tr("查看…", "Review…")).font(.system(size: 12)).foregroundStyle(Color.accentColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("打开设置里的「自定义命令」", "Opens Settings → Custom Commands"))
        }
    }
}

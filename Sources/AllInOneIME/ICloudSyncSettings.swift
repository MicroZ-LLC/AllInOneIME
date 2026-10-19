import AllInOneIMECore
import AppKit
import SwiftUI

/// Settings → General → Sync through iCloud (「通过 iCloud 同步」, `ICloudSyncController`): off by default; on only with
/// iCloud Drive there (else how to turn it on, and a button to that pane). Under it, what syncs (hidden words and recent
/// questions off until chosen here; API keys and passwords through iCloud Keychain, off until chosen here too, in a
/// build entitled to it: turning sync on never moves a key), the
/// status, Sync Now, and "Remove from iCloud…" (asked first). All of it is this Mac's own: never synced.
struct ICloudSyncSection: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var sync = ICloudSyncController.shared
    /// Turning it on found no iCloud Drive.
    @State private var driveMissing = false
    @State private var confirmingRemove = false
    /// The hidden words or the recent questions about to be taken out of iCloud (asked first).
    @State private var categoryToRemove: ICloudSync.Category?
    @State private var removeError: String?

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { model.config.iCloudSync.enabled }, set: setEnabled)) {
                titled(tr("通过 iCloud 同步", "Sync through iCloud"), syncsKeys
                       ? tr("设置、黑话库和自定义命令、拼音学到的词，在你所有的 Mac 上都一样；在下面打开后，API 密钥和密码也经过 iCloud 钥匙串同步。只经过你自己的 iCloud，不经过我们的服务器，也不用另外登录。",
                            "Your settings, jargon list, custom commands and the words pinyin learned, the same on all your Macs; your API keys and passwords too, through iCloud Keychain, if you turn that on below. Only through your own iCloud: nothing goes to our servers, and there's nothing else to sign in to.")
                       : tr("设置、黑话库和自定义命令、拼音学到的词，在你所有的 Mac 上都一样。只经过你自己的 iCloud 云盘，不经过我们的服务器，也不用另外登录。",
                            "Your settings, jargon list, custom commands and the words pinyin learned, the same on all your Macs. Only through your own iCloud Drive: nothing goes to our servers, and there's nothing else to sign in to."))
            }
            if driveMissing || (model.config.iCloudSync.enabled && !sync.driveAvailable) {
                HStack(alignment: .firstTextBaseline) {
                    Label(ICloudSync.turnOnDrive(language: UIText.language), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(tr("打开 iCloud 设置", "Open iCloud Settings"), action: Self.openICloudSettings)
                }
            }
            if model.config.iCloudSync.enabled {
                Toggle(isOn: binding(\.settings)) {
                    titled(tr("设置", "Settings"), tr("语言、改写风格、执行键、按 App 设置、AI 服务和模型（不含密钥）…",
                                                     "Languages, rewrite styles, the action key, per-app settings, the AI provider and model (never its key)…"))
                }
                Toggle(tr("黑话库和自定义命令", "Jargon and custom commands"), isOn: binding(\.jargon))
                Toggle(isOn: binding(\.learnedWords)) {
                    titled(tr("学到的词", "Learned words"), tr("拼音从你的选择里学到的词（Rime 的用户词典）", "What pinyin learned from your choices (Rime's user dictionary)"))
                }
                Toggle(isOn: binding(\.hiddenWords)) {
                    titled(tr("隐藏的词", "Hidden words"),
                           tr("你在隐私里加的词。只有开了「高级数据保护」，iCloud 云盘才是端到端加密的。关掉后已同步的仍留在 iCloud 里，用「从 iCloud 移除…」删掉。",
                              "The words you hide from the AI. iCloud Drive is end-to-end encrypted only with Advanced Data Protection. Turned off, the ones synced stay in iCloud until you remove them."))
                }
                removeRow(.hiddenWords)
                Toggle(isOn: binding(\.recentQuestions)) {
                    titled(tr("最近的问题", "Recent questions"),
                           tr("@question 的问题和答案；只在开了「记住最近的问题」时同步。关掉后已同步的仍留在 iCloud 里，用「从 iCloud 移除…」删掉。",
                              "@question's questions and answers; only while “Remember recent questions” is on. Turned off, the ones synced stay in iCloud until you remove them."))
                }
                removeRow(.recentQuestions)
                let keysRow = Self.keysRow(entitled: Self.entitled)
                Toggle(isOn: keysRow.enabled ? binding(\.keys) : .constant(false)) {
                    titled(tr("API 密钥和密码", "API keys and passwords"), keysRow.note)
                }
                .disabled(!keysRow.enabled)
                HStack(alignment: .firstTextBaseline) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(statusLine(now: context.date)).font(.callout).foregroundStyle(statusColor)
                    }
                    Spacer()
                    Button(tr("立即同步", "Sync Now")) { sync.syncNow() }
                        .disabled(!sync.driveAvailable)
                }
            }
            if sync.folderExists {
                HStack {
                    if let removeError { Text(removeError).font(.callout).foregroundStyle(.red) }
                    Spacer()
                    Button(tr("从 iCloud 移除…", "Remove from iCloud…")) { confirmingRemove = true }
                }
            }
        } header: {
            SectionTitle("iCloud", icon: CandidateView.Icon(symbol: "icloud.fill", color: .systemBlue))
        } footer: {
            Text(tr("从不同步：AllInOneIME Cloud 的登录、扩展来源、扩展文件夹和插件、不再打错的 App 和最近用过的 App、窗口状态。每台 Mac 自己决定开不开同步、同步哪些。",
                    "Never synced: the AllInOneIME Cloud sign-in, extension sources, extension folders and plugins, the apps without typos and the recent apps, window state. Each Mac decides for itself whether to sync, and what."))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
        }
        .disabled(!model.canSave)
        .confirmationDialog(tr("从 iCloud 移除同步的数据？", "Remove the synced data from iCloud?"), isPresented: $confirmingRemove) {
            Button(tr("移除", "Remove"), role: .destructive, action: remove)
            Button(tr("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(tr("iCloud 云盘里的 AllInOneIME 文件夹会移到废纸篓，这台 Mac 也不再同步；这台 Mac 上的设置保持不变。还在同步的 Mac 会把它们的设置再放回去：先在那些 Mac 上关掉。",
                    "The AllInOneIME folder in iCloud Drive goes to the Trash, and this Mac stops syncing; your settings on this Mac stay as they are. Macs that still sync put theirs back: turn it off there first.")
                 + (syncsKeys ? " " + tr("API 密钥和密码留在 iCloud 钥匙串里，给你别的 Mac 用（也复制到这台 Mac 上）；要从所有 Mac 上删除一个 key，在同步开着时点它的「删除…」。",
                                         "API keys and passwords stay in iCloud Keychain for your other Macs (and are copied to this Mac); to remove a key from all your Macs, use its Remove… while sync is on.") : ""))
        }
        .confirmationDialog(categoryToRemove == .recentQuestions ? tr("从 iCloud 移除最近的问题？", "Remove the recent questions from iCloud?")
                                : tr("从 iCloud 移除隐藏的词？", "Remove the hidden words from iCloud?"),
                            isPresented: Binding(get: { categoryToRemove != nil }, set: { if !$0 { categoryToRemove = nil } })) {
            Button(tr("移除", "Remove"), role: .destructive) {
                if let category = categoryToRemove { remove(category) }
                categoryToRemove = nil
            }
            Button(tr("取消", "Cancel"), role: .cancel) { categoryToRemove = nil }
        } message: {
            Text(categoryToRemove == .recentQuestions
                 ? tr("它们会从 iCloud 云盘删掉，这台 Mac 也不再同步它们；这台 Mac 上的问题保留。同步它们的其他 Mac 不会再从 iCloud 收到；还开着的 Mac 会把自己的再放回去。",
                      "They're deleted from iCloud Drive and this Mac stops syncing them; the questions on this Mac stay. Other Macs syncing them stop getting them from iCloud; one that still has the switch on puts its own back.")
                 : tr("它们会从 iCloud 云盘删掉，这台 Mac 也不再同步它们；这台 Mac 上的词保留。同步它们的其他 Mac 不会再从 iCloud 收到；还开着的 Mac 会把自己的再放回去。",
                      "They're deleted from iCloud Drive and this Mac stops syncing them; the words on this Mac stay. Other Macs syncing them stop getting them from iCloud; one that still has the switch on puts its own back."))
        }
    }

    /// Keys sync through iCloud Keychain while sync is on: the build is entitled to it, and "API keys and passwords" is on.
    private var syncsKeys: Bool { Self.entitled && model.config.iCloudSync.keys }

    /// Whether this build can sync keys as the section shows it: as entitled for the settings' images
    /// (`--settings-image`, a build without a provisioning profile), else as it is.
    static var shownEntitled: Bool?
    static var entitled: Bool { shownEntitled ?? APIKeys.Keychain.processIsEntitled }

    /// The "API keys and passwords" row (off by default): it can be turned on only in a build entitled to the data
    /// protection keychain (signed with the provisioning profile); elsewhere off and greyed, saying why.
    static func keysRow(entitled: Bool) -> (enabled: Bool, note: String) {
        entitled
            ? (true, tr("经过 iCloud 钥匙串，端到端加密。默认关：打开这一项时，这台 Mac 的密钥才移进 iCloud 钥匙串。需要在 系统设置 → Apple 账户 → iCloud 里打开「密码与钥匙串」。AllInOneIME Cloud 的登录每台 Mac 各自登录。",
                        "Through iCloud Keychain, end-to-end encrypted. Off by default: this Mac's keys move into iCloud Keychain only when you turn this on. Needs Passwords & Keychain on in System Settings → Apple Account → iCloud. Each Mac signs in to AllInOneIME Cloud itself."))
            : (false, tr("这个版本不能同步密钥（没有描述文件）", "This build can't sync keys (no provisioning profile)"))
    }

    /// One of the switches under it: saved, and synced at once.
    private func binding(_ path: WritableKeyPath<ICloudSyncSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.config.iCloudSync[keyPath: path] }, set: { on in
            model.config.iCloudSync[keyPath: path] = on
            model.save()
            sync.syncNow()
        })
    }

    private func setEnabled(_ on: Bool) {
        if on, !sync.canTurnOn() {
            driveMissing = true
            return
        }
        driveMissing = false
        removeError = nil
        model.config.iCloudSync.enabled = on
        model.save()
        sync.syncNow()
    }

    private func remove() {
        if model.config.iCloudSync.enabled {
            model.config.iCloudSync.enabled = false
            model.save()
        }
        sync.removeFromICloud { error in removeError = error.map { tr("没能移除：", "Couldn't remove it: ") + $0 } }
    }

    /// The hidden words or the recent questions out of iCloud: the switch off here first, so they don't go back up.
    private func remove(_ category: ICloudSync.Category) {
        if category == .hiddenWords { model.config.iCloudSync.hiddenWords = false } else { model.config.iCloudSync.recentQuestions = false }
        model.save()
        sync.removeFromICloud(category) { result in
            switch result {
            case .success(.removed): removeError = nil
            case .success(.waiting):
                removeError = tr("正在等 iCloud…：settings.json 下载下来后就移除。", "Waiting for iCloud…: removed once settings.json is downloaded.")
            case let .failure(error):
                removeError = tr("没能移除：", "Couldn't remove it: ") + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// "Remove from iCloud…" under an opt-in's switch, while the shared folder is there.
    @ViewBuilder private func removeRow(_ category: ICloudSync.Category) -> some View {
        if sync.folderExists {
            HStack {
                Spacer()
                Button(tr("从 iCloud 移除…", "Remove from iCloud…")) { categoryToRemove = category }
                    .controlSize(.small)
            }
        }
    }

    private func statusLine(now: Date) -> String {
        if !sync.refused.isEmpty {
            let count = sync.refused.count
            return statusText(now: now) + (count == 1
                ? tr("；iCloud 里有 1 项设置没用在这台 Mac 上（设置 → 助手的「检查问题」说明原因）",
                     "; 1 setting from iCloud isn't used here (Settings → Assistant → Check for problems says why)")
                : tr("；iCloud 里有 \(count) 项设置没用在这台 Mac 上（设置 → 助手的「检查问题」说明原因）",
                     "; \(count) settings from iCloud aren't used here (Settings → Assistant → Check for problems says why)"))
        }
        return statusText(now: now)
    }

    private func statusText(now: Date) -> String {
        switch sync.status {
        case .off: return sync.lastSync.map { lastSynced($0, now: now) }
            ?? tr("还没有同步过", "Not synced yet")
        case .unavailable: return tr("iCloud 云盘不可用", "iCloud Drive isn't available")
        case .syncing: return tr("正在同步…", "Syncing…")
        case let .synced(date): return lastSynced(date, now: now)
        case .waiting: return tr("正在等 iCloud…", "Waiting for iCloud…")
            + (sync.lastSync.map {
                let ago = ICloudSync.ago($0, now: now, language: UIText.language)
                return tr("（上次同步：\(ago)）", " (last synced \(ago))")
            } ?? "")
        case let .failed(message): return message
        }
    }

    /// "Last synced 2 min ago".
    private func lastSynced(_ date: Date, now: Date) -> String {
        let ago = ICloudSync.ago(date, now: now, language: UIText.language)
        return tr("上次同步：\(ago)", "Last synced \(ago)")
    }

    private var statusColor: Color {
        switch sync.status {
        case .failed, .unavailable: return .red
        default: return .secondary
        }
    }

    /// System Settings → Apple Account → iCloud (the Apple Account pane where that isn't found).
    static func openICloudSettings() {
        let panes = ["x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings?iCloud",
                     "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane"]
        for pane in panes {
            if let url = URL(string: pane), NSWorkspace.shared.open(url) { return }
        }
    }

    private func titled(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

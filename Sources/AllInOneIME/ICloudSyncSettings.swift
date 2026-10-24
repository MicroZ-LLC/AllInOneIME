import AllInOneIMECore
import AppKit
import SwiftUI

/// Settings → General → Sync through iCloud (「通过 iCloud 同步」, `ICloudSyncController`): off by default; on only with
/// iCloud Drive there (else how to turn it on, and a button to that pane). One status row, its switch with the last sync
/// under it and a ⋯ menu (Sync Now, API keys and passwords through iCloud Keychain, Remove from iCloud…); the learned
/// words' switch; one switch for the hidden words and the recent questions (off until chosen here). What else syncs (the
/// settings, the jargon list and custom commands) is on unless the config says otherwise, then shown with Restore
/// Default. All of it is this Mac's own: never synced.
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
            HStack(alignment: .center) {
                Toggle(isOn: Binding(get: { model.config.iCloudSync.enabled }, set: setEnabled)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SettingsSpot.iCloudSync.title)
                        if model.config.iCloudSync.enabled {
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                Text(statusLine(now: context.date)).font(.callout).foregroundStyle(statusColor)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text(SettingsSpot.iCloudNote).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if model.config.iCloudSync.enabled || sync.folderExists { moreMenu }
            }
            .settingsRow(.iCloudSync, shown: model.spot)
            if driveMissing || (model.config.iCloudSync.enabled && !sync.driveAvailable) {
                HStack(alignment: .firstTextBaseline) {
                    Label(ICloudSync.turnOnDrive(language: UIText.language), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(tr("打开 iCloud 设置", "Open iCloud Settings"), action: Self.openICloudSettings)
                }
            }
            if model.config.iCloudSync.enabled {
                Toggle(isOn: binding(\.learnedWords)) {
                    titled(tr("学到的词", "Learned words"), tr("拼音从你的选择里学到的词（Rime 的用户词典），和你的英文词",
                                                            "What pinyin learned from your choices (Rime's user dictionary), and your English words"))
                }
                Toggle(isOn: Binding(get: { model.config.iCloudSync.hiddenWords || model.config.iCloudSync.recentQuestions },
                                     set: setPrivate)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("隐藏的词和最近的问题", "Hidden words and recent questions"))
                        Text(tr("只有开了「高级数据保护」才端到端加密；关掉后已同步的仍留在 iCloud 里，直到你移除。",
                                "End-to-end encrypted only with Advanced Data Protection; turned off, what was synced stays in iCloud until you remove it."))
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        // One of the two on alone (a config from before they were one switch): which.
                        if model.config.iCloudSync.hiddenWords != model.config.iCloudSync.recentQuestions {
                            Text(model.config.iCloudSync.hiddenWords ? tr("现在只同步隐藏的词。", "Only the hidden words sync now.")
                                 : tr("现在只同步最近的问题。", "Only the recent questions sync now."))
                                .font(.callout).foregroundStyle(.orange)
                        }
                    }
                }
                // What syncs unless the config says otherwise: one set off shows, with Restore Default.
                if !model.config.iCloudSync.settings {
                    RestoreDefaultRow(title: tr("设置：不同步", "Settings: not synced"), note: tr("默认会同步。", "Synced by default.")) {
                        set(\.settings, true)
                    }
                }
                if !model.config.iCloudSync.jargon {
                    RestoreDefaultRow(title: tr("黑话库和自定义命令：不同步", "Jargon and custom commands: not synced"),
                                      note: tr("默认会同步。", "Synced by default.")) { set(\.jargon, true) }
                }
            }
            if let removeError { Text(removeError).font(.callout).foregroundStyle(.red) }
        } header: {
            SectionTitle("iCloud", icon: CandidateView.Icon(symbol: "icloud.fill", color: .systemBlue))
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

    /// The status row's ⋯: Sync Now, API keys and passwords (through iCloud Keychain, off until chosen; a build without
    /// the provisioning profile can't), and taking things out of iCloud (each asked first).
    private var moreMenu: some View {
        Menu {
            if model.config.iCloudSync.enabled {
                Button(tr("立即同步", "Sync Now")) { sync.syncNow() }
                    .disabled(!sync.driveAvailable)
                Divider()
                let keysRow = Self.keysRow(entitled: Self.entitled)
                Toggle(tr("API 密钥和密码（iCloud 钥匙串）", "API Keys and Passwords (iCloud Keychain)"),
                       isOn: keysRow.enabled ? binding(\.keys) : .constant(false))
                    .disabled(!keysRow.enabled)
                    .help(keysRow.note)
            }
            if sync.folderExists {
                Divider()
                Button(tr("从 iCloud 移除隐藏的词…", "Remove Hidden Words from iCloud…")) { categoryToRemove = .hiddenWords }
                Button(tr("从 iCloud 移除最近的问题…", "Remove Recent Questions from iCloud…")) { categoryToRemove = .recentQuestions }
                Button(tr("从 iCloud 移除…", "Remove from iCloud…")) { confirmingRemove = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(tr("更多 iCloud 选项", "More iCloud options"))
    }

    /// The hidden words and the recent questions, one switch: both on, or both off.
    private func setPrivate(_ on: Bool) {
        model.config.iCloudSync.hiddenWords = on
        model.config.iCloudSync.recentQuestions = on
        model.save()
        sync.syncNow()
    }

    private func set(_ path: WritableKeyPath<ICloudSyncSettings, Bool>, _ on: Bool) {
        model.config.iCloudSync[keyPath: path] = on
        model.save()
        sync.syncNow()
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

    private func statusLine(now: Date) -> String {
        var line = statusText(now: now)
        if syncsKeys { line += tr("；API 密钥和密码经过 iCloud 钥匙串", "; API keys and passwords through iCloud Keychain") }
        if !sync.refused.isEmpty {
            let count = sync.refused.count
            line += count == 1 ? tr("；iCloud 里有 1 项设置没用在这台 Mac 上", "; 1 setting from iCloud isn't used here")
                : tr("；iCloud 里有 \(count) 项设置没用在这台 Mac 上", "; \(count) settings from iCloud aren't used here")
        }
        return line
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
                let ago = RelativeTime.ago($0, now: now, language: UIText.language, style: .shortThenDate)
                return tr("（上次同步：\(ago)）", " (last synced \(ago))")
            } ?? "")
        case let .failed(message): return message
        }
    }

    /// "Last synced 2 min ago".
    private func lastSynced(_ date: Date, now: Date) -> String {
        let ago = RelativeTime.ago(date, now: now, language: UIText.language, style: .shortThenDate)
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

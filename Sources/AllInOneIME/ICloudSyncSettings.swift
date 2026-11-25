import AllInOneIMECore
import AppKit
import SwiftUI

/// Settings → General → Sync through iCloud (「通过 iCloud 同步」, `ICloudSyncController`): off by default; on only with
/// iCloud Drive there (else how to turn it on, and a button to that pane). One status row, its switch with the last sync
/// under it and a ⋯ menu (Sync Now, API keys and passwords through iCloud Keychain, and one Remove from iCloud… that
/// takes all of it out of iCloud, owner 0.7.5); one switch for
/// the hidden words and the recent questions (off until chosen here). What else syncs (the settings, the jargon list and
/// custom commands, and the learned words, whose switch went in 0.7.4) is on unless the config says otherwise, then
/// shown with Restore Default. All of it is this Mac's own: never synced.
struct ICloudSyncSection: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var sync = ICloudSyncController.shared
    /// Turning it on found no iCloud Drive.
    @State private var driveMissing = false
    @State private var confirmingRemove = false
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
                if !model.config.iCloudSync.learnedWords {
                    RestoreDefaultRow(title: tr("学到的词：不同步", "Learned words: not synced"),
                                      note: tr("默认会同步。", "Synced by default.")) { set(\.learnedWords, true) }
                }
            }
            if let removeError { Text(removeError).font(.callout).foregroundStyle(.red) }
        } header: {
            SectionTitle("iCloud", icon: CandidateView.Icon(symbol: "icloud.fill", color: .systemBlue))
        }
        .disabled(!model.canSave)
        // Everything synced at once: what it takes out of iCloud said first.
        .confirmationDialog(tr("从 iCloud 移除同步的数据？", "Remove the synced data from iCloud?"), isPresented: $confirmingRemove) {
            Button(tr("移除", "Remove"), role: .destructive, action: remove)
            Button(tr("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(Self.removeMessage(keysStay: syncsKeys))
        }
    }

    /// What Remove from iCloud… takes out of iCloud, as its confirmation says it: everything synced (the AllInOneIME folder
    /// in iCloud Drive, to the Trash), this Mac no longer syncing, what is on this Mac kept; with keys synced, that they
    /// stay in iCloud Keychain (`keysStay`).
    static func removeMessage(keysStay: Bool) -> String {
        tr("这些会从 iCloud 云盘移除：设置、自定义命令和黑话库、学到的词、隐藏的词和最近的问题（AllInOneIME 文件夹移到废纸篓），这台 Mac 也不再同步；这台 Mac 上的都保留。还在同步的 Mac 会把它们的再放回去：先在那些 Mac 上关掉。",
           "Removed from iCloud Drive: your settings, custom commands and jargon, learned words, hidden words and recent questions (the AllInOneIME folder goes to the Trash), and this Mac stops syncing; everything on this Mac stays. Macs that still sync put theirs back: turn it off there first.")
            + (keysStay ? " " + tr("API 密钥和密码留在 iCloud 钥匙串里，给你别的 Mac 用（也复制到这台 Mac 上）；要从所有 Mac 上删除一个 key，在同步开着时点它的「删除…」。",
                                   "API keys and passwords stay in iCloud Keychain for your other Macs (and are copied to this Mac); to remove a key from all your Macs, use its Remove… while sync is on.") : "")
    }

    /// The status row's ⋯: Sync Now, API keys and passwords (through iCloud Keychain, off until chosen; a build without
    /// the provisioning profile can't), and taking all of it out of iCloud (asked first).
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
            ? (true, tr("经过 iCloud 钥匙串，端到端加密；需要在 系统设置 → Apple 账户 → iCloud 里打开「密码与钥匙串」。",
                        "End-to-end encrypted through iCloud Keychain, which needs Passwords & Keychain on in System Settings → Apple Account → iCloud."))
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
}

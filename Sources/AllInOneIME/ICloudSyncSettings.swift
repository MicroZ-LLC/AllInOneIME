import AllInOneIMECore
import AppKit
import SwiftUI

/// Settings → General → Sync through iCloud (「通过 iCloud 同步」, `ICloudSyncController`): off by default; on only with
/// iCloud Drive there (else how to turn it on, and a button to that pane). Under it, what syncs (hidden words and recent
/// questions off until chosen here), the status, Sync Now, and "Remove from iCloud…" (asked first). All of it is this
/// Mac's own: never synced.
struct ICloudSyncSection: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var sync = ICloudSyncController.shared
    /// Turning it on found no iCloud Drive.
    @State private var driveMissing = false
    @State private var confirmingRemove = false
    @State private var removeError: String?

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { model.config.iCloudSync.enabled }, set: setEnabled)) {
                titled(tr("通过 iCloud 同步", "Sync through iCloud"),
                       tr("设置、黑话库和自定义命令、拼音学到的词，在你所有的 Mac 上都一样。只经过你自己的 iCloud 云盘，不经过我们的服务器，也不用另外登录。",
                          "Your settings, jargon list, custom commands and the words pinyin learned, the same on all your Macs. Only through your own iCloud Drive: nothing goes to our servers, and there's nothing else to sign in to."))
            }
            if driveMissing || (model.config.iCloudSync.enabled && !sync.driveAvailable) {
                HStack(alignment: .firstTextBaseline) {
                    Label(ICloudSync.turnOnDrive(chinese: UIText.chinese), systemImage: "exclamationmark.triangle.fill")
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
                           tr("你在隐私里加的词。只有开了「高级数据保护」，iCloud 云盘才是端到端加密的。",
                              "The words you hide from the AI. iCloud Drive is end-to-end encrypted only with Advanced Data Protection."))
                }
                Toggle(isOn: binding(\.recentQuestions)) {
                    titled(tr("最近的问题", "Recent questions"),
                           tr("@question 的问题和答案；只在开了「记住最近的问题」时同步。", "@question's questions and answers; only while “Remember recent questions” is on."))
                }
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
            Text(tr("从不同步：密钥、令牌和密码，扩展来源，扩展文件夹和插件，窗口状态。每台 Mac 自己决定开不开同步、同步哪些。",
                    "Never synced: keys, tokens and passwords, extension sources, extension folders and plugins, window state. Each Mac decides for itself whether to sync, and what."))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
        }
        .disabled(!model.canSave)
        .confirmationDialog(tr("从 iCloud 移除同步的数据？", "Remove the synced data from iCloud?"), isPresented: $confirmingRemove) {
            Button(tr("移除", "Remove"), role: .destructive, action: remove)
            Button(tr("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(tr("iCloud 云盘里的 AllInOneIME 文件夹会移到废纸篓，这台 Mac 也不再同步；这台 Mac 上的设置保持不变。还在同步的 Mac 会把它们的设置再放回去：先在那些 Mac 上关掉。",
                    "The AllInOneIME folder in iCloud Drive goes to the Trash, and this Mac stops syncing; your settings on this Mac stay as they are. Macs that still sync put theirs back: turn it off there first."))
        }
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
        removeError = sync.removeFromICloud().map { tr("没能移除：", "Couldn't remove it: ") + $0 }
    }

    private func statusLine(now: Date) -> String {
        if !sync.refused.isEmpty {
            let count = sync.refused.count
            return statusText(now: now) + tr("；iCloud 里有 \(count) 项设置没用在这台 Mac 上（@doctor 说明原因）",
                                             count == 1 ? "; 1 setting from iCloud isn't used here (@doctor says why)"
                                                 : "; \(count) settings from iCloud aren't used here (@doctor says why)")
        }
        return statusText(now: now)
    }

    private func statusText(now: Date) -> String {
        switch sync.status {
        case .off: return sync.lastSync.map { tr("上次同步：", "Last synced ") + ICloudSync.ago($0, now: now, chinese: UIText.chinese) }
            ?? tr("还没有同步过", "Not synced yet")
        case .unavailable: return tr("iCloud 云盘不可用", "iCloud Drive isn't available")
        case .syncing: return tr("正在同步…", "Syncing…")
        case let .synced(date): return tr("上次同步：", "Last synced ") + ICloudSync.ago(date, now: now, chinese: UIText.chinese)
        case .waiting: return tr("正在等 iCloud…", "Waiting for iCloud…")
        case let .failed(message): return message
        }
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

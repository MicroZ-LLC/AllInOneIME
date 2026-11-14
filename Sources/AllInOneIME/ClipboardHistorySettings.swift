import AllInOneIMECore
import AllInOneIMEMac
import SwiftUI

/// Settings → General → Clipboard history: its switch (no input-menu item: on by default, off here), why it isn't
/// recording when macOS doesn't let it (Privacy & Security → Paste from Other Apps, with a button to that page), and
/// Clear History. How many it keeps has no row of its own (owner, 0.7.4): set otherwise than 20 (by hand, an earlier
/// version), it shows with Restore Default. Both keys are this Mac's own (never synced), as the history is.
struct ClipboardHistorySection: View {
    @ObservedObject var model: SettingsModel
    /// Whether it may read the clipboard without asking, as macOS says now (told again as the window comes back from
    /// System Settings).
    @State private var access = ClipboardHistoryShared.access
    @State private var cleared = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { model.config.clipboardHistoryOn }, set: { model.setClipboardHistory($0) })) {
                titled(.clipboardHistory)
            }
            .settingsRow(.clipboardHistory, shown: model.spot)
            if model.config.clipboardHistoryOn {
                let kept = model.config.clipboardHistoryKept
                if kept != Config.defaultClipboardHistoryLimit {
                    RestoreDefaultRow(title: tr("保留最近 \(kept) 条", "Keep the last \(kept)"),
                                      note: RestoreDefaultRow.defaultIs("\(Config.defaultClipboardHistoryLimit)")) {
                        model.setClipboardHistoryLimit(Config.defaultClipboardHistoryLimit)
                    }
                }
                // Only when something is wrong: recording is what it does.
                if access != .allowed { permission }
                HStack {
                    Text(tr("只存在这台 Mac 上，不同步，也不发给 AI。", "Kept on this Mac only: never synced, never sent to an AI."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if cleared { Text(tr("已清除", "Cleared")).font(.callout).foregroundStyle(.secondary) }
                    Button(tr("清除历史", "Clear History")) {
                        model.clearClipboardHistory()
                        cleared = true
                    }
                }
            }
        } header: {
            SectionTitle(tr("剪贴板历史", "Clipboard History"), icon: SettingsPage.general.icon)
        }
        .disabled(!model.canSave)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            access = ClipboardHistoryShared.access
        }
    }

    /// Why it isn't recording, and how to allow it: Paste from Other Apps set to Allow for AllInOneIME (it is listed once
    /// a read has asked: ⌃V in a text field).
    private var permission: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(tr("没在记录：在「隐私与安全性」→「从其他App粘贴」里把 AllInOneIME 设成「允许」（没列出的话，先在输入框里按一次 \(Platform.current.terms.paste)）。",
                     "Not recording: set AllInOneIME to Allow in Privacy & Security → Paste from Other Apps (not listed yet? press \(Platform.current.terms.paste) in a text field once)."),
                  systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(tr("打开「隐私与安全性」…", "Open Privacy & Security…")) { ClipboardHistoryShared.openPrivacyPage() }
        }
    }
}

extension SettingsModel {
    /// Clipboard history on (nil: the default) or off (the history deleted at once), saved.
    func setClipboardHistory(_ on: Bool) {
        config.clipboardHistory = on ? nil : false
        save()
        if store.persists { ClipboardHistoryShared.apply(config) }
    }

    /// How many it keeps (5…100; 20 unset), saved; a lower one drops the oldest at once.
    func setClipboardHistoryLimit(_ limit: Int) {
        let kept = min(max(limit, Config.clipboardHistoryLimits.lowerBound), Config.clipboardHistoryLimits.upperBound)
        config.clipboardHistoryLimit = kept == Config.defaultClipboardHistoryLimit ? nil : kept
        save()
        if store.persists { ClipboardHistoryShared.apply(config) }
    }

    /// Clear History: the file deleted (not the preview's: the self-test's and the README images' windows keep nothing).
    func clearClipboardHistory() {
        if store.persists { ClipboardHistoryShared.clear() }
    }
}

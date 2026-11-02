import AllInOneIMECore
import AllInOneIMEMac
import AppKit

/// Clipboard history on this Mac (the core's Session/ClipboardHistory.swift is the panel ⌃V shows): a look at the
/// clipboard's change count each second, cheap enough to run all day (its data read only after a change, and only while
/// Paste from Other Apps allows it without asking: `ClipboardRecorder`); the history's file (`ClipboardHistoryStore`),
/// trimmed at once to a lower limit and deleted as the history is turned off or cleared; what each field's session asks
/// of it (`services`). Main thread only.
@MainActor
enum ClipboardHistoryShared {
    /// The recorder, over the general pasteboard and the user's file (the self-test's never touches either: it gives its
    /// sessions a history of its own).
    static let recorder = ClipboardRecorder(source: SystemClipboard(), store: ClipboardHistoryStore(), secureInput: { SecureInput.isOn })
    /// Where the first showing's note is remembered (the input method's defaults).
    static let noteShownKey = "clipboardHistoryNoteShown"
    /// System Settings → Privacy & Security → Paste from Other Apps.
    static let privacyPage = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!
    /// The self-test's: its sessions have no history unless a check gives one (`AllInOneIMEInputController.services`),
    /// and nothing here reads the user's clipboard or file.
    static var isolated = false
    private static var timer: Timer?
    /// The switch and the limit last applied.
    private static var applied: (on: Bool, limit: Int)?

    /// Starts looking, once a second, at launch.
    static func start() {
        guard timer == nil else { return }
        tick()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The settings as they are now (turned off: the history deleted; a lower limit: the oldest dropped), then, while it's
    /// on, a copy since the last look recorded.
    static func tick() {
        let config = LiveConfig.current
        apply(config)
        guard config.clipboardHistoryOn else { return }
        if recorder.poll(limit: config.clipboardHistoryKept) == .recorded {
            log.debug("clipboard history: a copy recorded (\(recorder.store.items.count, privacy: .public) kept)")
        }
    }

    /// `config`'s switch and limit, once each time they change. Turned on again: only a copy made from then on is recorded.
    static func apply(_ config: Config) {
        let now = (on: config.clipboardHistoryOn, limit: config.clipboardHistoryKept)
        guard applied.map({ $0 != now }) ?? true else { return }
        let wasOff = applied?.on == false
        applied = now
        if now.on {
            if wasOff { recorder.forget() }
            recorder.store.trim(to: now.limit)
        } else {
            clear()
            log.notice("clipboard history: off, deleted")
        }
    }

    /// Clear History, or the history turned off: the file deleted; what's on the clipboard now isn't recorded again at the
    /// next look, only a later copy (`ClipboardRecorder.forget`).
    static func clear() {
        recorder.store.clear()
        recorder.forget()
    }

    /// Whether it may read the clipboard without asking now (as Settings says it).
    static var access: ClipboardAccess { SystemClipboard().access }

    /// What a field's session asks: whether it records (Paste from Other Apps' Allow), the history with a copy made since
    /// the last look, Accessibility (the app's paste key posted for an image and ⌃V again, asked without asking), the first
    /// showing's note (once on this Mac), the privacy page, a kept image's data (a command reads it), whether the clipboard
    /// holds the newest copy still.
    static var services: ClipboardHistoryServices {
        guard !isolated else { return ClipboardHistoryServices() }
        return ClipboardHistoryServices(
            state: { MainActor.assumeIsolated { access == .allowed ? .recording : .notAllowed } },
            items: {
                MainActor.assumeIsolated {
                    tick()
                    return recorder.store.items
                }
            },
            canPassPasteKey: { AXIsProcessTrusted() },
            firstShowing: {
                guard !UserDefaults.standard.bool(forKey: noteShownKey) else { return false }
                UserDefaults.standard.set(true, forKey: noteShownKey)
                return true
            },
            openPermission: { MainActor.assumeIsolated { openPrivacyPage() } },
            imageData: { id in MainActor.assumeIsolated { recorder.store.imageData(id) } },
            clipboardIsNewest: { MainActor.assumeIsolated { recorder.clipboardIsNewest } })
    }

    /// Paste from Other Apps, in System Settings.
    static func openPrivacyPage() {
        NSWorkspace.shared.open(privacyPage)
    }
}

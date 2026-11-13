import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import UserNotifications

/// An `@question`'s answer that came after the panel stopped waiting for it (`LateAnswer`, the core's LateAnswer.swift):
/// a notification (the question, the answer's first line) and the whole answer in clipboard history (⌃V), where the
/// history is on (`LateAnswer.actions`); clicking the notification puts it on the clipboard (`AgentMonitor`, every
/// notification's delegate, hands the click here).
enum LateAnswers {
    /// The notification's key for the answer it copies.
    static let userInfoKey = "lateAnswer"

    /// `answer` shown and kept; from any thread.
    static func deliver(_ answer: LateAnswer) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { take(answer) }
        }
    }

    @MainActor
    private static func take(_ answer: LateAnswer) {
        let config = LiveConfig.current
        log.notice("@question: an answer came in the background (\(answer.answer?.count ?? 0, privacy: .public) chars\(answer.answer == nil ? ", failed" : "", privacy: .public))")
        for action in answer.actions(historyOn: config.clipboardHistoryOn && !ClipboardHistoryShared.isolated) {
            switch action {
            case let .notify(title, body, copies):
                notify(title: title, body: body, copies: copies)
            case let .keepInClipboardHistory(text):
                _ = ClipboardHistoryShared.recorder.store.record(text, at: Date(), limit: config.clipboardHistoryKept)
            }
        }
    }

    private static func notify(title: String, body: String, copies: String?) {
        let center = UNUserNotificationCenter.current()
        // Asked the first time (macOS asks the user once); shown once allowed.
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let copies { content.userInfo = [userInfoKey: copies] }
            center.add(UNNotificationRequest(identifier: "late-answer-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
        }
    }

    /// The notification clicked: its answer on the clipboard.
    @MainActor
    static func clicked(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        log.notice("@question: an answer from the background copied (\(text.count, privacy: .public) chars)")
    }
}

import AllInOneIMECore
import AllInOneIMEMac
import UserNotifications

/// macOS's notification center for the updater's notifications (`UpdateNotifier`). A new version's has Update and Don't
/// Show Again, neither of which brings anything to the front (no `.foreground`): the app being typed in keeps its keys.
/// What the user does with them comes back through the input method's one delegate of the notification center
/// (`AgentMonitor`).
@MainActor
final class SystemUpdateNotices: UpdateNoticePoster {
    static let shared = SystemUpdateNotices()
    /// A new version's category (its buttons); a failure's has none: clicking it is all.
    nonisolated static let category = "update-available"
    /// In a notification's userInfo: which of the updater's it is (`UpdateNotice.Kind`).
    nonisolated static let userInfoKey = "update"

    func permission() async -> UpdateNoticePermission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: return .notAsked
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    func askPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func post(_ notice: UpdateNotice) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = String(notice.body.prefix(240))
        content.sound = .default
        content.userInfo = [Self.userInfoKey: notice.kind.rawValue]
        if notice.kind == .available {
            // The buttons in the interface language of now.
            center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [
                UNNotificationAction(identifier: UpdateNoticeAction.update.rawValue, title: tr("更新", "Update"), options: []),
                UNNotificationAction(identifier: UpdateNoticeAction.dontShowAgain.rawValue, title: tr("不再提示", "Don't Show Again"), options: []),
            ], intentIdentifiers: [])])
            content.categoryIdentifier = Self.category
        }
        do {
            try await center.add(UNNotificationRequest(identifier: "update-\(notice.kind.rawValue)-\(notice.version)", content: content, trigger: nil))
            log.notice("update notification: \(notice.kind.rawValue, privacy: .public) \(notice.version, privacy: .public)")
        } catch {
            log.error("could not post the update notification: \(String(describing: error), privacy: .public)")
        }
    }

    /// The action of a response to one of these (nil: dismissed, nothing to do).
    nonisolated static func action(_ identifier: String) -> UpdateNoticeAction? {
        if identifier == UNNotificationDefaultActionIdentifier { return .open }
        return UpdateNoticeAction(rawValue: identifier).flatMap { $0 == .open ? nil : $0 }
    }
}

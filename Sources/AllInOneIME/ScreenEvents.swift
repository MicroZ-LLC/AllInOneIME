import AppKit

/// What can take one of our windows off the screen with AppKit none the wiser (GitHub #61): the displays changed or woke,
/// the Mac woke, another Space, the app hidden (Hide Others hides an agent app too). Each window that shows while typing
/// (the candidate panel, the image preview beside it, autocomplete's suggestion, the menu bar's panel) is put back on each
/// while it shows: `handler`, on the main thread, as long as this is kept.
final class ScreenEvents {
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(_ handler: @escaping @MainActor () -> Void) {
        let app = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        let events: [(NotificationCenter, Notification.Name)] = [
            (app, NSApplication.didChangeScreenParametersNotification), (app, NSApplication.didHideNotification),
            (workspace, NSWorkspace.screensDidWakeNotification), (workspace, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.activeSpaceDidChangeNotification),
        ]
        observers = events.map { center, name in
            (center, center.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { handler() } })
        }
    }

    deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
    }
}

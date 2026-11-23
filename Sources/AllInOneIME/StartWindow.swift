import AllInOneIMECore
import AppKit
import Carbon
import Combine
import SwiftUI

/// The three-step start a fresh install opens (owner, 0.7.5, #122) instead of teaching a command name: switch to
/// AllInOneIME, connect an AI, then try one @ on a sentence of your own. Shown once per Mac: Done, Skip or closing it
/// marks it seen in the input method's own defaults (not the config file: it isn't a setting, and it isn't synced).
@MainActor
final class StartModel: ObservableObject {
    @Published private(set) var step = 1
    /// The selected input source's name, as step 1 shows it.
    @Published private(set) var sourceName = ""

    private let defaults: UserDefaults
    private let ourSourceID: String

    /// Step 3's buttons, in order: a sum, a time, an app every Mac has. Each gives the same first one-@ row as anywhere.
    static let examples = ["200*15%", "明天下午三点开会", "safari"]

    init(defaults: UserDefaults, ourSourceID: String) {
        self.defaults = defaults
        self.ourSourceID = ourSourceID
    }

    /// The window shown: step 1, or 2 when AllInOneIME is the input source already.
    func start(currentSourceID: String?) {
        step = currentSourceID == ourSourceID ? 2 : 1
    }

    /// Another input source selected: step 1 moves on only when it is AllInOneIME's.
    func inputSourceChanged(to id: String?) {
        if step == 1, id == ourSourceID { step = 2 }
    }

    func showSourceName(_ name: String?) { sourceName = name ?? "" }

    /// Signed in on step 2: typing works now; on to trying it.
    func signedIn() { if step == 2 { step = 3 } }

    /// Later on step 2: typing works without signing in.
    func later() { if step == 2 { step = 3 } }

    /// Done, Skip or the window closed: it isn't shown again.
    func close() { StartWindow.markSeen(defaults) }

    /// Step 3's field: the magic key alone (prefilled), or followed by an example.
    static func fieldText(trigger: String, example: String?) -> String { trigger + (example ?? "") }
}

/// The start's window: shown once, by `--start` (the installer's last button on a fresh install, through the
/// AllInOneIME Settings app) or `showNotification` to a running input method; otherwise Settings as before.
@MainActor
enum StartWindow {
    static let seenKey = "startSeen"
    /// What the AllInOneIME Settings app tells an input method that is running already (a reopen carries no arguments).
    static let showNotification = "com.allinoneime.inputmethod.showStart"

    private static var window: NSWindow?
    private static var listening: NSObjectProtocol?
    private static var observers: [NSObjectProtocol] = []
    private static var signIn: AnyCancellable?
    /// When it was shown: the reopen that follows `showNotification` shows no Settings window over it.
    private(set) static var shownAt: Date?

    nonisolated static func shouldShow(_ defaults: UserDefaults) -> Bool { !defaults.bool(forKey: seenKey) }

    nonisolated static func markSeen(_ defaults: UserDefaults) { defaults.set(true, forKey: seenKey) }

    /// The input method started: `showNotification` listened for (its whole life), and the window the AllInOneIME Settings
    /// app asked for shown, `start` the start (once) or `settings` Settings. Settings shows on About instead when the move
    /// to this identity shows the step to add the input source first (decided by `UpdateController.start`, before this
    /// runs).
    static func launched(start: Bool, settings: Bool) {
        listening = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(showNotification),
                                                                        object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { show() }
        }
        guard start || settings else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if start {
                    show()
                } else if UpdateController.shared.firstShown != .inputSourceStep {
                    SettingsWindow.shared.show()
                }
            }
        }
    }

    /// The start, if it hasn't been seen; Settings otherwise.
    static func show() {
        guard shouldShow(.standard) else {
            SettingsWindow.shared.show()
            return
        }
        shownAt = Date()
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let model = StartModel(defaults: .standard, ourSourceID: InputSourceRegistrar.sourceID)
        let settings = SettingsModel()
        model.start(currentSourceID: InputSourceRegistrar.currentSourceID())
        model.showSourceName(currentSourceName())
        let host = NSHostingController(rootView: StartView(model: model, settings: settings))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.title = tr("开始使用 AllInOneIME", "Get started with AllInOneIME")
        window.setContentSize(NSSize(width: 560, height: 440))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        // The input source switched (Control + Space, the Input menu): step 1 follows it.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                model.showSourceName(currentSourceName())
                model.inputSourceChanged(to: InputSourceRegistrar.currentSourceID())
            }
        })
        // Signed in (step 2's buttons, Settings' own calls): on to step 3.
        signIn = settings.$account.receive(on: RunLoop.main).sink { account in
            if account != nil { MainActor.assumeIsolated { model.signedIn() } }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                                queue: .main) { _ in
            MainActor.assumeIsolated { closed(model) }
        })
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Done or Skip.
    static func close() { window?.close() }

    private static func closed(_ model: StartModel) {
        model.close()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers = []
        signIn = nil
        window = nil
    }

    /// The selected input source's name ("ABC", "AllInOneIME").
    private static func currentSourceName() -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return InputSourceRegistrar.string(current, kTISPropertyLocalizedName)
    }
}

import AllInOneIMECore
import AllInOneIMEMac
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
    /// Whether AllInOneIME's input source is added (System Settings → Keyboard → Input Sources): until it is, step 1
    /// says where to add it, with a button to Keyboard settings (a fresh install where macOS left that to the user).
    @Published private(set) var sourceAdded = true

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

    /// Another input source selected: step 1 moves on only when it is AllInOneIME's (added, then).
    func inputSourceChanged(to id: String?) {
        guard id == ourSourceID else { return }
        sourceAdded = true
        if step == 1 { step = 2 }
    }

    /// The enabled input sources looked at (the window shown, one added or taken out in System Settings).
    func inputSourceAdded(_ added: Bool) { sourceAdded = added }

    func showSourceName(_ name: String?) { sourceName = name ?? "" }

    /// Signed in on step 2: typing works now; on to trying it.
    func signedIn() { if step == 2 { step = 3 } }

    /// The AI chosen has what it needs to answer (`AIStatus.isReady`: a CLI signed in, a key added, Apple's model, a
    /// sign-in), set up in Settings → AI or signed in here: on step 2, on to trying it, as after signing in.
    func aiReady(_ ready: Bool) { if ready, step == 2 { step = 3 } }

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
    private static var ready: AnyCancellable?
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
        EditMenu.install()  // ⌘V, ⌘C, ⌘X, ⌘A, ⌘Z in step 3's field
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let model = StartModel(defaults: .standard, ourSourceID: InputSourceRegistrar.sourceID)
        // Settings' own (kept by its window): read once for both, and a CLI's sign-in Settings looks at is seen here.
        let settings = SettingsWindow.shared.settings
        model.start(currentSourceID: InputSourceRegistrar.currentSourceID())
        model.showSourceName(currentSourceName())
        model.inputSourceAdded(sourceAdded())
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
        // Added in System Settings (step 1's button): step 1 says to switch to it now.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { model.inputSourceAdded(sourceAdded()) }
        })
        // Signed in (step 2's buttons, Settings' own calls): on to step 3.
        signIn = settings.$account.receive(on: RunLoop.main).sink { account in
            if account != nil { MainActor.assumeIsolated { model.signedIn() } }
        }
        // The AI chosen ready (a CLI, a key or Apple's model set up in Settings → AI from step 2's "Use My Own AI…"): on to
        // step 3 too. Looked at as these settings change and as step 2 comes up; read again as the window comes back to
        // the front (from Settings, where it was set up).
        let changes = settings.objectWillChange.merge(with: settings.aws.objectWillChange, model.$step.map { _ in })
        ready = changes.receive(on: RunLoop.main).sink { _ in
            MainActor.assumeIsolated {
                model.aiReady(settings.aiFacts.status(settings.config.ai, config: settings.config).isReady)
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                                queue: .main) { _ in
            MainActor.assumeIsolated { refreshAI(settings, step: model.step) }
        })
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
        (signIn, ready) = (nil, nil)
        window = nil
    }

    /// What step 2 goes by read again (as Settings' own page reads it, `SettingsModel.windowShown`): the AI chosen in the
    /// config file, the keys, the sign-in, the AWS profiles, the CLIs' sign-ins as last looked at. Back on step 2 with a
    /// CLI chosen that isn't ready (signed in in Terminal, or chosen in Settings a moment ago), its sign-in looked at now
    /// (forced: what was found stands for a minute), the step going on as it comes back.
    /// The config file is read off the main thread (`SettingsModel.reloadIfChangedOffMain`), the rest once it is.
    private static func refreshAI(_ settings: SettingsModel, step: Int) {
        settings.reloadIfChangedOffMain {
            settings.refreshKeys()
            settings.refreshAccount()
            settings.aws.refresh(profile: settings.config.awsProfile)
            settings.sessionAvailability = ClaudeSessionMac.managers.mapValues(\.availability)
            if step == 2 { settings.pickedCLIShownAgain() }
        }
    }

    /// Whether AllInOneIME's input source is added (enabled): read only, on the main thread (`InputSourceCheck
    /// .isEnabledNow`: nothing registered or waited for; About's step registers a source Text Input Sources lost, at launch
    /// and as the app comes back, `InputSourceStatus`). A copy that isn't the installed one (a build run from elsewhere)
    /// never is the user's input source, and counts as added.
    private static func sourceAdded() -> Bool {
        !InputSourceStatus.shared.isInstalled || InputSourceCheck.isEnabledNow(InputSourceRegistrar.sourceID)
    }

    /// The selected input source's name ("ABC", "AllInOneIME").
    private static func currentSourceName() -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return InputSourceRegistrar.string(current, kTISPropertyLocalizedName)
    }
}

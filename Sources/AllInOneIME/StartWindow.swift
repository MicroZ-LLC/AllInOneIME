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

    /// Step 3's field (#198): `preset` is the text put in it programmatically, always empty (a selected "@" set there
    /// was typed over, and text set there never reaches the input method, so no @ list opened); `typed` is what the
    /// view feeds the input method as real key events through the field's input context: the magic key alone (on
    /// showing the step), or followed by an example (its button).
    struct TryField: Equatable { var preset: String; var typed: String }

    static func tryField(trigger: String, example: String?) -> TryField {
        TryField(preset: "", typed: trigger + (example ?? ""))
    }

    /// What step 3's field shows once `tryField`'s keys are typed.
    static func fieldText(trigger: String, example: String?) -> String { tryField(trigger: trigger, example: example).typed }

    /// Whether the step's button carries Return as its key equivalent: steps 1 and 2; not 3, where Return belongs to the
    /// field (the @ list's), and with no list open it does nothing rather than closing the guide (#198).
    static func hasDefaultAction(step: Int) -> Bool { step != 3 }

    // MARK: Step 3's keys

    /// One key step 3 posts, down and up: its key (US layout) and Shift as that layout types the character, and the
    /// character itself, which the view sets as the event's characters. Another layout puts other characters on those
    /// keys, and the input method reads the text from the characters (it tells keys such as Esc by their code).
    struct Stroke: Equatable {
        var keyCode: UInt16
        var shift: Bool
        var characters: String

        /// No characters of its own: the event keeps the key's, as a real Escape has them.
        static let escape = Stroke(keyCode: VirtualKey.escape, shift: false, characters: "")
    }

    /// The keys that type `typed`, one stroke a character; with `cancelFirst`, Escape twice before them. What the @ list
    /// has open is ended first: one Esc takes a command's result list back to its draft, the next gives the draft up, or
    /// puts its text in as typed (`Composer.handleOneAtKey`), which the view clears before the rest is typed.
    static func strokes(for typed: String, cancelFirst: Bool) -> [Stroke] {
        (cancelFirst ? [Stroke.escape, .escape] : []) + typed.map(stroke)
    }

    /// Whether the keys cancel first: for an example clicked, which may come while a draft is open in the @ list (typed
    /// before, or the one an example before opened); not for the magic key typed as the step shows, into an empty field.
    static func shouldCancelFirst(example: String?) -> Bool { example != nil }

    /// A character's stroke: a character with no key (明) has no key code (`KeyEvent.noKeyCode`) and only its characters.
    private static func stroke(_ character: Character) -> Stroke {
        // (A character's lower case may be more than one: never one of these keys, then.)
        let lower = character.lowercased()
        if lower.count == 1, let key = lower.first, let code = keys[key] {
            return Stroke(keyCode: code, shift: character != key, characters: String(character))
        }
        if let code = shifted[character] { return Stroke(keyCode: code, shift: true, characters: String(character)) }
        return Stroke(keyCode: KeyEvent.noKeyCode, shift: false, characters: String(character))
    }

    private static let keys: [Character: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
        "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
        "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18, "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E,
        "o": 0x1F, "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, " ": 0x31, "`": 0x32,
    ]
    private static let shifted: [Character: UInt16] = [
        "!": 0x12, "@": 0x13, "#": 0x14, "$": 0x15, "^": 0x16, "%": 0x17, "+": 0x18, "(": 0x19, "&": 0x1A, "_": 0x1B,
        "*": 0x1C, ")": 0x1D, "}": 0x1E, "{": 0x21, "\"": 0x27, ":": 0x29, "|": 0x2A, "<": 0x2B, "?": 0x2C, ">": 0x2F,
        "~": 0x32,
    ]
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

    /// Whether the start's window is the key window of the active app: where step 3's keys may be posted (#198), as they
    /// go to whatever has the keyboard focus.
    static var isKey: Bool { NSApp.isActive && window != nil && NSApp.keyWindow === window }

    nonisolated static func shouldShow(_ defaults: UserDefaults) -> Bool { !defaults.bool(forKey: seenKey) }

    nonisolated static func markSeen(_ defaults: UserDefaults) { defaults.set(true, forKey: seenKey) }

    /// The input method started: `showNotification` listened for (its whole life), and the window the AllInOneIME Settings
    /// app asked for shown, `start` the start (once) or `settings` Settings. Settings shows on About instead when the move
    /// to this identity shows the step to add the input source first (`UpdateController.whenFirstShown`: decided at once,
    /// but right after the move once the first look at the input source answers).
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
                } else {
                    UpdateController.shared.whenFirstShown { first in
                        if first != .inputSourceStep { SettingsWindow.shared.show() }
                    }
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
        // A window, not a panel, and no button of the start's on Esc (`.cancelAction`): an Escape no draft takes (an
        // example's click posts two first, `StartModel.strokes`) goes from the field up to the window's
        // `cancelOperation`, which leaves it open (seen on macOS 27: no completion list either). Keep it so.
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

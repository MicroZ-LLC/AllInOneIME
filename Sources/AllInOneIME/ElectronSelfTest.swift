import AllInOneIMECore
import AppKit

/// The long press of Shift as an Electron app gives it to the input method (Slack, VS Code; Chrome too): every modifier
/// change twice. AppKit hands a modifier change to the input method in `-[NSApplication sendEvent:]`
/// (`TSMProcessRawKeyEvent`); Chromium sends a key event the page didn't handle through `-[NSApplication sendEvent:]`
/// again once the page has let it go by (`-[CommandDispatcher redispatchKeyEvent:]`, its window key), and the input
/// method gets the same Shift down (or up) a second time, 5–20 ms later, the same key, flags and time; with the page
/// busy (Slack's often is, for 100 ms and more), after the next change: a tap comes as down, up, down, up. Option too.
///
/// The Electron harness (Scripts/electron-harness/: Slack's composer, a contenteditable, and a textarea in a pinned
/// Electron; its probe drives it with key events posted to its own window and logs what reaches the input method)
/// recorded what follows; the self-test plays it into the fake field, the app being Slack. With the harness installed
/// (`make electron-harness`, which downloads Electron) and `ALLINONEIME_ELECTRON_HARNESS` naming its folder, it runs the
/// harness and plays what it records now, for both fields.
extension SelfTest {
    /// One thing that reached the input method, `at` seconds into the recording.
    struct Reached: Equatable {
        enum Kind: Equatable {
            case flagsChanged, keyDown, activate, deactivate
            case appActivated(String?)
        }

        var at: TimeInterval
        var kind: Kind
        var keyCode: UInt16 = 0
        var flags: UInt = 0
        /// The event's time, seconds into the recording: a modifier change handed over again has the first one's.
        var timestamp: TimeInterval = 0
        var characters = ""
    }

    /// The probe's lines ("REC <at> flagsChanged <keyCode> <flags, hex> <timestamp>", "REC <at> keyDown … <characters,
    /// percent-encoded>", "REC <at> activate", "REC <at> appActivated <bundle id>"); the others ("posted", "script",
    /// "end") say what the probe did, not what the input method got.
    static func reached(in recording: String) -> [Reached] {
        recording.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 3, parts[0] == "REC", let at = TimeInterval(parts[1]) else { return nil }
            func number(_ index: Int) -> UInt? {
                guard parts.indices.contains(index) else { return nil }
                let text = parts[index]
                return text.hasPrefix("0x") ? UInt(text.dropFirst(2), radix: 16) : UInt(text)
            }
            switch parts[2] {
            case "flagsChanged", "keyDown":
                guard let code = number(3), let flags = number(4), parts.count >= 6, let time = TimeInterval(parts[5]) else { return nil }
                return Reached(at: at, kind: parts[2] == "keyDown" ? .keyDown : .flagsChanged, keyCode: UInt16(code), flags: flags,
                               timestamp: time, characters: parts.count > 6 ? parts[6].removingPercentEncoding ?? "" : "")
            case "activate": return Reached(at: at, kind: .activate)
            case "deactivate": return Reached(at: at, kind: .deactivate)
            case "appActivated": return Reached(at: at, kind: .appActivated(parts.count > 3 ? parts[3] : nil))
            default: return nil
            }
        }
    }

    /// Plays `events` into the fake field at their times, as the input method gets them (Shift held, for the timers'
    /// look at it, as the last modifier change left it), then lets `after` seconds go by; `watch` looks on meanwhile.
    static func replay(_ events: [Reached], _ controller: AllInOneIMEInputController, _ client: FakeTextClient,
                       after: TimeInterval, watch: () -> Void = {}) {
        let start = ProcessInfo.processInfo.systemUptime
        for reached in events {
            _ = pump(timeout: start + reached.at - ProcessInfo.processInfo.systemUptime) { watch(); return false }
            switch reached.kind {
            case .flagsChanged, .keyDown:
                let flags = NSEvent.ModifierFlags(rawValue: reached.flags)
                guard let event = NSEvent.keyEvent(
                    with: reached.kind == .keyDown ? .keyDown : .flagsChanged, location: .zero, modifierFlags: flags,
                    timestamp: start + reached.timestamp, windowNumber: 0, context: nil, characters: reached.characters,
                    charactersIgnoringModifiers: reached.characters.lowercased(), isARepeat: false, keyCode: reached.keyCode)
                else { continue }
                _ = controller.handle(event, client: client)
            case .activate: controller.activateServer(client)
            case .deactivate: controller.deactivateServer(client)
            case let .appActivated(app): AllInOneIMEInputController.otherAppActivated(app)
            }
        }
        _ = pump(timeout: after) { watch(); return false }
    }

    /// Recorded by the Electron harness (Electron 44.9.0, Slack's composer): Shift held 1.28 s, tapped, and held with
    /// a capital typed, each change reaching the input method twice.
    static let electronShiftHold = """
        REC 0.0000 script shift-hold com.github.Electron
        REC 0.0001 posted flagsChanged 56 0x20102
        REC 0.0047 flagsChanged 56 0x20102 0.0001
        REC 0.0214 flagsChanged 56 0x20102 0.0001
        REC 1.2800 posted flagsChanged 56 0x100
        REC 1.2819 flagsChanged 56 0x100 1.2800
        REC 1.2856 flagsChanged 56 0x100 1.2800
        REC 1.8010 end
        """
    static let electronShiftTap = """
        REC 0.0000 script shift-tap com.github.Electron
        REC 0.0001 posted flagsChanged 56 0x20102
        REC 0.0045 flagsChanged 56 0x20102 0.0001
        REC 0.0104 flagsChanged 56 0x20102 0.0001
        REC 0.1039 posted flagsChanged 56 0x100
        REC 0.1068 flagsChanged 56 0x100 0.1039
        REC 0.1101 flagsChanged 56 0x100 0.1039
        REC 0.6055 end
        """
    /// The page busy 250 ms with each key down (`HARNESS_BUSY`): the tap's down and up come again after its release.
    static let electronShiftTapBusy = """
        REC 0.0000 script shift-tap com.github.Electron
        REC 0.0003 posted flagsChanged 56 0x20102
        REC 0.0044 flagsChanged 56 0x20102 0.0002
        REC 0.1076 posted flagsChanged 56 0x100
        REC 0.1082 flagsChanged 56 0x100 0.1076
        REC 0.2576 flagsChanged 56 0x20102 0.0002
        REC 0.2580 flagsChanged 56 0x100 0.1076
        REC 0.6318 end
        """
    /// Left Option tapped: each change twice too.
    static let electronOptionTap = """
        REC 0.0001 script option-tap com.github.Electron
        REC 0.0007 posted flagsChanged 58 0x80120
        REC 0.0142 flagsChanged 58 0x80120 0.0002
        REC 0.0185 flagsChanged 58 0x80120 0.0002
        REC 0.1050 posted flagsChanged 58 0x100
        REC 0.1061 flagsChanged 58 0x100 0.1050
        REC 0.1073 flagsChanged 58 0x100 0.1050
        REC 0.6193 end
        """
    static let electronShiftLetter = """
        REC 0.0000 script shift-letter com.github.Electron
        REC 0.0001 posted flagsChanged 56 0x20102
        REC 0.0052 flagsChanged 56 0x20102 0.0001
        REC 0.0199 flagsChanged 56 0x20102 0.0001
        REC 0.2069 posted keyDown 0 0x20102
        REC 0.2125 keyDown 0 0x20102 0.2069 A
        REC 0.2621 posted keyUp 0 0x20102
        REC 1.2844 posted flagsChanged 56 0x100
        REC 1.2876 flagsChanged 56 0x100 1.2844
        REC 1.2911 flagsChanged 56 0x100 1.2844
        REC 1.7928 end
        """
    /// Made by hand from those: a tap with the page busy, then Shift held for the long press, the tap's copies (and the
    /// press's own down again) coming while it is held.
    static let electronTapThenHoldBusy = """
        REC 0.0000 script shift-tap-then-hold (by hand)
        REC 0.0044 flagsChanged 56 0x20102 0.0002
        REC 0.1082 flagsChanged 56 0x100 0.1076
        REC 0.3000 flagsChanged 56 0x20102 0.2996
        REC 0.3576 flagsChanged 56 0x20102 0.0002
        REC 0.3580 flagsChanged 56 0x100 0.1076
        REC 0.5500 flagsChanged 56 0x20102 0.2996
        REC 1.5000 flagsChanged 56 0x100 1.4996
        REC 1.5030 flagsChanged 56 0x100 1.4996
        REC 1.7000 end
        """

    /// The long press of Shift in Slack (an Electron app: every modifier change twice): it opens the chooser, where 1
    /// turns Translate as You Type on and, again, off; a tap switches the input language once and opens nothing, with the
    /// page busy too (the tap's copies after its release); Shift held with a capital, or with the pointer used (a
    /// Shift-click), opens nothing. A tap of ⌥, the action key, acts once. The controller drops a copy before the composer and the long
    /// press see it, in any text field (`checkCopiesDroppedFirst`). Then the live harness, when there is one.
    static func testShiftHoldInElectron(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        section("The long press of Shift in an Electron app (Slack): the chooser", needs: .composing)
        let saved = (settings: settings, pointer: TranslateModeShared.pointer, stickyKeys: TranslateModeShared.stickyKeys,
                     defaults: TranslateModeShared.defaults, pointerUsed: controller.services.pointerUsedWithin,
                     shiftHeld: TranslateModeShared.shiftHeld)
        let suite = "com.aipinyin.selftest.translatemode.electron"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        TranslateModeShared.defaults = UserDefaults(suiteName: suite) ?? .standard
        // The recorded presses' Shift down as the system has it while the timers run.
        (TranslateModeShared.pointer, TranslateModeShared.stickyKeys, TranslateModeShared.shiftHeld) = ({ .zero }, { false }, { true })
        // Everything as it was found: off, no press timed, no notice, the self-test's own app again.
        defer {
            TranslateModeShared.state = TranslateMode.State()
            controller.perform(controller.composer.setTranslateMode(nil), client: client)
            controller.commitComposition(client)
            controller.hideTranslateChip()
            MenuBarIcon.shared.setTranslating(false)
            (settings, TranslateModeShared.pointer, TranslateModeShared.stickyKeys) = (saved.settings, saved.pointer, saved.stickyKeys)
            (TranslateModeShared.defaults, controller.services.pointerUsedWithin) = (saved.defaults, saved.pointerUsed)
            TranslateModeShared.shiftHeld = saved.shiftHeld
            UserDefaults.standard.removePersistentDomain(forName: suite)
            client.bundleIDOverride = nil
            controller.activateServer(client)
            controller.composer.setInputMode(settings.defaultInput)
            if let notice = controller.notice { controller.endNotice(notice) }
        }
        settings.setOrder([OutputLanguage.english, .chinese])
        settings.setOrder([Language.chinese, .english])
        controller.commitComposition(client)
        client.bundleIDOverride = "com.tinyspeck.slackmacgap"
        controller.activateServer(client)
        controller.composer.setInputMode(.chinese)
        client.inserted.removeAll()
        checkElectronRecordings(hold: reached(in: electronShiftHold), tap: reached(in: electronShiftTap),
                                busyTap: reached(in: electronShiftTapBusy), letter: reached(in: electronShiftLetter),
                                optionTap: reached(in: electronOptionTap), from: "recorded", controller, client)
        checkCopiesDroppedFirst(controller, client)
        testElectronHarness(controller, client)
    }

    /// The checks on one set of recordings (`from`: where they come from).
    static func checkElectronRecordings(hold: [Reached], tap: [Reached], busyTap: [Reached], letter: [Reached],
                                        optionTap: [Reached], from: String,
                                        _ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        let shifts = hold.filter { $0.kind == .flagsChanged }
        check(shifts.count == 4 && shifts[0].timestamp == shifts[1].timestamp && shifts[0].flags == shifts[1].flags,
              "\(from): Shift down and up each reach the input method twice, the same event (\(shifts.map { String(format: "%.3f", $0.at) }))")
        // Held: the chooser at 1.0 s; 1 turns Translate as You Type on.
        var opened = false
        replay(hold, controller, client, after: 0.2) { opened = opened || chooserIsOpen(controller) }
        if chooserIsOpen(controller) { press(controller, client, "1", code: 0x12) }
        check(opened && TranslateModeShared.state.isOn && controller.composer.translateMode?.target == .english
              && controller.composer.inputLanguage == .chinese,
              "\(from): a long press of Shift in Slack opens the chooser, 1 turns Translate as You Type on (\(controller.notice ?? "-"))")
        replay(hold, controller, client, after: 0.2)
        if chooserIsOpen(controller) { press(controller, client, "1", code: 0x12) }
        check(!TranslateModeShared.state.isOn && controller.composer.translateMode == nil,
              "\(from): …and a long press again, 1, turns it off (\(controller.notice ?? "-"))")
        if let notice = controller.notice { controller.endNotice(notice) }
        // A tap: the input language switched once, no chooser.
        var tapOpened = false
        replay(tap, controller, client, after: 1.0) { tapOpened = tapOpened || chooserIsOpen(controller) }
        check(controller.composer.inputLanguage == .english && !TranslateModeShared.state.isOn && !tapOpened,
              "\(from): a tap of Shift switches the input language once (\(controller.composer.inputLanguage)) and toggles nothing")
        tapShift(controller, client)
        // The page busy: the tap's down and up come again after its release, and still switch nothing.
        let busy = busyTap.filter { $0.kind == .flagsChanged }
        check(busy.count == 4 && busy[2].timestamp == busy[0].timestamp && busy[2].flags == busy[0].flags
              && busy[3].timestamp == busy[1].timestamp && busy[2].at > busy[1].at,
              "\(from), the page busy: Shift's down and up reach the input method again after the release (\(busy.map { String(format: "%.3f", $0.at) }))")
        var busyOpened = false
        replay(busyTap, controller, client, after: 1.0) { busyOpened = busyOpened || chooserIsOpen(controller) }
        check(controller.composer.inputLanguage == .english && !TranslateModeShared.state.isOn && !busyOpened,
              "\(from), the page busy: a tap of Shift switches the input language once (\(controller.composer.inputLanguage)), not back")
        if controller.composer.inputLanguage == .english { tapShift(controller, client) }
        // Shift held with a capital typed: no chooser.
        var letterOpened = false
        replay(letter, controller, client, after: 0.3) { letterOpened = letterOpened || chooserIsOpen(controller) }
        check(!TranslateModeShared.state.isOn && !letterOpened, "\(from): Shift held with a capital typed opens no chooser")
        controller.commitComposition(client)
        controller.composer.setInputMode(.chinese)
        client.inserted.removeAll()
        // A Shift-click (the pointer used while Shift is held): no chooser.
        controller.services.pointerUsedWithin = { _ in true }
        var clickOpened = false
        replay(hold, controller, client, after: 0.2) { clickOpened = clickOpened || chooserIsOpen(controller) }
        controller.services.pointerUsedWithin = { _ in false }
        check(!TranslateModeShared.state.isOn && !clickOpened, "\(from): a Shift-click held as long opens no chooser")
        if let notice = controller.notice { controller.endNotice(notice) }
        // A tap of ⌥, the action key, with "@i" typed: it takes the command offered ("@improve "), once.
        let options = optionTap.filter { $0.kind == .flagsChanged }
        check(options.count == 4 && options[0].timestamp == options[1].timestamp && options[0].flags == options[1].flags,
              "\(from): ⌥ down and up each reach the input method twice, the same event (\(options.map { String(format: "%.3f", $0.at) }))")
        let actionKey = settings.actionKey
        settings.actionKey = .optionTap
        controller.applySettings()
        press(controller, client, "@", code: 0x13, flags: .shift)  // ⇧2
        type("i", controller, client)
        replay(optionTap, controller, client, after: 0.2)
        check(controller.composer.draft == "@improve " && client.marked == "improve › ",
              "\(from): a tap of ⌥ (the action key) takes the command offered (\(controller.composer.draft))")
        _ = escape(controller, client)
        controller.commitComposition(client)
        settings.actionKey = actionKey
        controller.applySettings()
        client.inserted.removeAll()
    }

    /// The controller drops a copy before anything sees it (`handleFlagsChanged`): before the composer and its long
    /// press, in any text field. A tap with the page busy, then a long press with the tap's copies coming while Shift is
    /// held: one switch, and the chooser (the copy of the tap's release, reaching the long press, would end the press;
    /// reaching the composer, the two copies would switch back). Then Shift+Tab with the page busy:
    /// the focus in the next field before Shift's copies come; there the copy of Shift's down and the release would be a
    /// tap, but the copy is known in every field (the composer of each field its own).
    static func checkCopiesDroppedFirst(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        var opened = false
        replay(reached(in: electronTapThenHoldBusy), controller, client, after: 0.2) {
            opened = opened || chooserIsOpen(controller)
        }
        if chooserIsOpen(controller) { press(controller, client, "1", code: 0x12) }
        check(opened && TranslateModeShared.state.isOn && controller.composer.inputLanguage == .english,
              "a tap with the page busy, then a long press with its copies coming while Shift is held: the input language "
              + "switched once (\(controller.composer.inputLanguage)) and the chooser, Translate as You Type on (\(controller.notice ?? "-"))")
        if TranslateModeShared.state.isOn { controller.toggleTranslateMode() }  // off again
        if let notice = controller.notice { controller.endNotice(notice) }
        if controller.composer.inputLanguage == .english { tapShift(controller, client) }

        guard let other = AllInOneIMEInputController(server: controller.server(), delegate: nil, client: nil) else {
            return check(false, "a second text field's controller")
        }
        let otherClient = FakeTextClient()
        otherClient.bundleIDOverride = client.bundleIDOverride
        other.clientOverride = otherClient
        other.services.loadSettings = { SelfTest.settings }
        (other.services.loadCommandUsage, other.services.saveCommandUsage) = ({ CommandUsage() }, { _ in })
        other.services.loadExtensions = { _, _ in .empty }
        (other.recordApp, other.services.takeRenameNotice) = ({ _ in }, { _ in nil })
        (other.warmsUpVision, other.selectionByAccessibility) = (false, false)
        other.services.pointerUsedWithin = { _ in false }
        /// Shift's change into `field`, at `time`.
        func shift(_ field: AllInOneIMEInputController, _ fieldClient: FakeTextClient, down: Bool, at time: TimeInterval) {
            guard let event = NSEvent.keyEvent(
                with: .flagsChanged, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0x20102 : 0x100),
                timestamp: time, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: VirtualKey.leftShift)
            else { return }
            _ = field.handle(event, client: fieldClient)
        }
        controller.composer.setInputMode(.chinese)
        let pressed = ProcessInfo.processInfo.systemUptime, released = pressed + 0.12
        shift(controller, client, down: true, at: pressed)
        press(controller, client, "\t", code: VirtualKey.tab, flags: .shift)
        controller.deactivateServer(client)
        other.activateServer(otherClient)
        other.composer.setInputMode(.chinese)
        shift(other, otherClient, down: true, at: pressed)  // the page let Shift's down go by: its copy
        _ = pump(timeout: released - ProcessInfo.processInfo.systemUptime + 0.01) { false }
        shift(other, otherClient, down: false, at: released)
        shift(other, otherClient, down: false, at: released)
        check(other.composer.inputLanguage == .chinese && controller.composer.inputLanguage == .chinese,
              "Shift+Tab with the page busy, Shift's copy reaching the next field: no switch there "
              + "(\(other.composer.inputLanguage)) nor in the field it left (\(controller.composer.inputLanguage))")
        other.deactivateServer(otherClient)
        other.inputControllerWillClose()
        controller.activateServer(client)
    }

    /// The Electron harness itself, when `ALLINONEIME_ELECTRON_HARNESS` names its folder (`make electron-harness`: its
    /// Electron, downloaded by npm, and its probe): each script run in its window, Slack's composer then the textarea
    /// (about 2 s each, the window shown without taking the focus; the tap of Shift a second time with the page busy),
    /// and what reached the input method played into the fake field. Skipped, and said so, without it.
    static func testElectronHarness(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        guard let folder = ProcessInfo.processInfo.environment["ALLINONEIME_ELECTRON_HARNESS"], !folder.isEmpty else {
            print("  the Electron harness: not run (make electron-harness, then make selftest ELECTRON_HARNESS=build/electron-harness)")
            return
        }
        let harness = URL(fileURLWithPath: folder)
        guard FileManager.default.isExecutableFile(atPath: electronBinary(in: harness).path),
              FileManager.default.fileExists(atPath: harness.appendingPathComponent("libprobe.dylib").path) else {
            return check(false, "the Electron harness in \(folder) (Electron and libprobe.dylib: make electron-harness)")
        }
        // Electron's data (its caches, the page's storage) in a temporary folder, not under the user's Library; AppKit's
        // defaults of Electron's app (com.github.Electron) still go to ~/Library/Preferences.
        let userData = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-electron-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: userData, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: userData) }
        for field in ["composer", "textarea"] {
            var recordings: [String: [Reached]] = [:]
            func run(_ script: String, busy: Int? = nil) -> [Reached] {
                reached(in: runElectronHarness(harness, script: script, field: field, busy: busy, userData: userData) ?? "")
            }
            for script in ["shift-hold", "shift-tap", "shift-letter", "option-tap"] { recordings[script] = run(script) }
            let busyTap = run("shift-tap", busy: 250)
            checkElectronRecordings(hold: recordings["shift-hold"] ?? [], tap: recordings["shift-tap"] ?? [], busyTap: busyTap,
                                    letter: recordings["shift-letter"] ?? [], optionTap: recordings["option-tap"] ?? [],
                                    from: "Electron harness, \(field)", controller, client)
        }
        let kept = (try? FileManager.default.contentsOfDirectory(atPath: userData.path)) ?? []
        check(!kept.isEmpty, "the Electron harness kept its data in a temporary folder (\(kept.count) items: "
              + "\(kept.sorted().prefix(3).joined(separator: ", "))…), removed after")
    }

    /// The harness's Electron, as npm installs it.
    static func electronBinary(in harness: URL) -> URL {
        harness.appendingPathComponent("node_modules/electron/dist/Electron.app/Contents/MacOS/Electron")
    }

    /// One run of the harness (its folder, `harness`): what its probe printed (nil: it didn't finish in time). Its key
    /// events go to its own window only, in its own process: the window is said to be key (`HARNESS_FAKE_KEY`; as it
    /// is while someone types in it) without taking the focus from the app in front. `busy`: milliseconds its page
    /// takes over each key down (`HARNESS_BUSY`). `userData`: the folder Electron keeps its data in
    /// (`HARNESS_USER_DATA`).
    static func runElectronHarness(_ harness: URL, script: String, field: String, busy: Int? = nil, userData: URL) -> String? {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-electron-\(script)-\(field).txt")
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: output) else { return nil }
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: output)
        }
        let process = Process()
        process.executableURL = electronBinary(in: harness)
        process.arguments = [harness.path]
        // Of the self-test's environment (AWS keys, say), only what Electron needs to start: its home and temporary
        // folders, the user; a plain PATH. Its data in `userData`.
        var environment = ProcessInfo.processInfo.environment.filter { ["HOME", "TMPDIR", "USER", "LOGNAME"].contains($0.key) }
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["DYLD_INSERT_LIBRARIES"] = harness.appendingPathComponent("libprobe.dylib").path
        (environment["HARNESS_SCRIPT"], environment["HARNESS_FIELD"]) = (script, field)
        (environment["HARNESS_FAKE_KEY"], environment["HARNESS_DELAY"]) = ("1", "2")
        environment["HARNESS_BUSY"] = busy.map(String.init)
        environment["HARNESS_USER_DATA"] = userData.path
        process.environment = environment
        (process.standardOutput, process.standardError) = (handle, FileHandle.nullDevice)
        do { try process.run() } catch {
            print("  the Electron harness didn't start: \(error)")
            return nil
        }
        guard pump(timeout: 30, until: { !process.isRunning }) else {
            process.terminate()
            return nil
        }
        return try? String(contentsOf: output, encoding: .utf8)
    }
}

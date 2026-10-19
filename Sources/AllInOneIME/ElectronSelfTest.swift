import AllInOneIMECore
import AppKit

/// The long press of Shift as an Electron app gives it to the input method (Slack, VS Code; Chrome too): every modifier
/// change twice. AppKit hands a modifier change to the input method in `-[NSApplication sendEvent:]`
/// (`TSMProcessRawKeyEvent`); Chromium sends a key event the page didn't handle through `-[NSApplication sendEvent:]`
/// again once the page has let it go by (`-[CommandDispatcher redispatchKeyEvent:]`, its window key), and the input
/// method gets the same Shift down (or up) a second time, 5–20 ms later, the same key, flags and time.
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
        var shiftDown = false
        let saved = (TranslateModeShared.shiftHeld, TranslateModeShared.shiftDown)
        (TranslateModeShared.shiftHeld, TranslateModeShared.shiftDown) = ({ shiftDown }, { shiftDown })
        defer { (TranslateModeShared.shiftHeld, TranslateModeShared.shiftDown) = saved }
        for reached in events {
            _ = pump(timeout: start + reached.at - ProcessInfo.processInfo.systemUptime) { watch(); return false }
            switch reached.kind {
            case .flagsChanged, .keyDown:
                let flags = NSEvent.ModifierFlags(rawValue: reached.flags)
                if reached.kind == .flagsChanged { shiftDown = flags.contains(.shift) }
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

    /// Translate as You Type's long press in Slack (an Electron app: every modifier change twice): a long press turns it
    /// on and, again, off; a tap switches the input language once and toggles nothing; Shift held with a capital, or
    /// with the pointer used (a Shift-click), toggles nothing. Then the live harness, when there is one.
    static func testShiftHoldInElectron(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        section("Translate as You Type's long press of Shift in an Electron app (Slack)", needs: .composing)
        let saved = (settings: settings, pointer: TranslateModeShared.pointer, stickyKeys: TranslateModeShared.stickyKeys,
                     defaults: TranslateModeShared.defaults, pointerUsed: controller.pointerUsedWithin)
        let suite = "com.aipinyin.selftest.translatemode.electron"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        TranslateModeShared.defaults = UserDefaults(suiteName: suite) ?? .standard
        (TranslateModeShared.pointer, TranslateModeShared.stickyKeys) = ({ .zero }, { false })
        // Everything as it was found: off, no press timed, no notice, the self-test's own app again.
        defer {
            TranslateModeShared.state = TranslateMode.State()
            TranslateModeShared.hold.resync(shiftDown: false)
            TranslateModeShared.holdToken += 1
            (TranslateModeShared.hint, TranslateModeShared.hintField) = (nil, nil)
            controller.perform(controller.composer.setTranslateMode(nil), client: client)
            controller.commitComposition(client)
            controller.hideTranslateChip()
            MenuBarIcon.shared.setTranslating(false)
            (settings, TranslateModeShared.pointer, TranslateModeShared.stickyKeys) = (saved.settings, saved.pointer, saved.stickyKeys)
            (TranslateModeShared.defaults, controller.pointerUsedWithin) = (saved.defaults, saved.pointerUsed)
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
                                letter: reached(in: electronShiftLetter), from: "recorded", controller, client)
        testElectronHarness(controller, client)
    }

    /// The checks on one set of recordings (`from`: where they come from).
    static func checkElectronRecordings(hold: [Reached], tap: [Reached], letter: [Reached], from: String,
                                        _ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        let onHint = tr("继续按住 → 边打边译", "Keep holding → Translate as You Type")
        let shifts = hold.filter { $0.kind == .flagsChanged }
        check(shifts.count == 4 && shifts[0].timestamp == shifts[1].timestamp && shifts[0].flags == shifts[1].flags,
              "\(from): Shift down and up each reach the input method twice, the same event (\(shifts.map { String(format: "%.3f", $0.at) }))")
        // Held: the hint at 0.5 s, then on at 1.0 s, the hint seen while it's held.
        var hinted = false
        replay(hold, controller, client, after: 0.2) { hinted = hinted || controller.notice == onHint }
        check(hinted && TranslateModeShared.state.isOn && controller.composer.translateMode?.target == .english
              && controller.composer.inputLanguage == .chinese,
              "\(from): a long press of Shift in Slack shows the hint, then turns Translate as You Type on (\(controller.notice ?? "-"))")
        replay(hold, controller, client, after: 0.2)
        check(!TranslateModeShared.state.isOn && controller.composer.translateMode == nil,
              "\(from): …and a long press again turns it off (\(controller.notice ?? "-"))")
        if let notice = controller.notice { controller.endNotice(notice) }
        // A tap: the input language switched once, nothing toggled.
        replay(tap, controller, client, after: 1.0)
        check(controller.composer.inputLanguage == .english && !TranslateModeShared.state.isOn,
              "\(from): a tap of Shift switches the input language once (\(controller.composer.inputLanguage)) and toggles nothing")
        tapShift(controller, client)
        // Shift held with a capital typed: nothing turns on.
        replay(letter, controller, client, after: 0.3)
        check(!TranslateModeShared.state.isOn, "\(from): Shift held with a capital typed toggles nothing")
        controller.commitComposition(client)
        controller.composer.setInputMode(.chinese)
        client.inserted.removeAll()
        // A Shift-click (the pointer used while Shift is held): nothing turns on.
        controller.pointerUsedWithin = { _ in true }
        replay(hold, controller, client, after: 0.2)
        controller.pointerUsedWithin = { _ in false }
        check(!TranslateModeShared.state.isOn, "\(from): a Shift-click held as long toggles nothing")
        if let notice = controller.notice { controller.endNotice(notice) }
    }

    /// The Electron harness itself, when `ALLINONEIME_ELECTRON_HARNESS` names its folder (`make electron-harness`: its
    /// Electron, downloaded by npm, and its probe): each script run in its window, Slack's composer then the textarea
    /// (about 2 s each, the window shown without taking the focus), and what reached the input method played into the
    /// fake field. Skipped, and said so, without it.
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
        for field in ["composer", "textarea"] {
            var recordings: [String: [Reached]] = [:]
            for script in ["shift-hold", "shift-tap", "shift-letter"] {
                recordings[script] = reached(in: runElectronHarness(harness, script: script, field: field) ?? "")
            }
            checkElectronRecordings(hold: recordings["shift-hold"] ?? [], tap: recordings["shift-tap"] ?? [],
                                    letter: recordings["shift-letter"] ?? [], from: "Electron harness, \(field)", controller, client)
        }
    }

    /// The harness's Electron, as npm installs it.
    static func electronBinary(in harness: URL) -> URL {
        harness.appendingPathComponent("node_modules/electron/dist/Electron.app/Contents/MacOS/Electron")
    }

    /// One run of the harness (its folder, `harness`): what its probe printed (nil: it didn't finish in time). Its key
    /// events go to its own window only, in its own process: the window is said to be key (`HARNESS_FAKE_KEY`; as it
    /// is while someone types in it) without taking the focus from the app in front.
    static func runElectronHarness(_ harness: URL, script: String, field: String) -> String? {
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
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_INSERT_LIBRARIES"] = harness.appendingPathComponent("libprobe.dylib").path
        (environment["HARNESS_SCRIPT"], environment["HARNESS_FIELD"]) = (script, field)
        (environment["HARNESS_FAKE_KEY"], environment["HARNESS_DELAY"]) = ("1", "2")
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

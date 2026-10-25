import AllInOneIMECore
import AppKit
import InputMethodKit

/// A web page's text field as Chromium's view answers the input method (Slack's composer, every Electron app's): its
/// marked text in its text, where a replacement range puts it; inserted text in place of the range given, else of the
/// marked text, else at the caret; the caret after what went in, or where marked text puts it. Each call that puts text in
/// is kept, with whether it came during the key being answered (`duringKey`, which the self-test sets): what the
/// harness's probe plays into its page (`answer`). The keys the input method lets go by, the app types (`typed`). As a
/// field that ignores the replacement range in setMarkedText, it puts marked text elsewhere (`marksAt`).
final class PageFieldClient: FakeTextClient {
    /// Where setMarkedText puts its text: as Chromium's view does, in place of the replacement range given, else of the
    /// marked text, else at the caret (`asked`); or, the range ignored, in place of the marked text, else at the caret
    /// (`caret`) or at the end of the text, the caret left where it is (`end`).
    enum MarksAt { case asked, caret, end }

    struct Call: Equatable {
        var duringKey: Bool
        var marks: Bool
        /// The replacement range (UTF-16); nil: none (NSNotFound).
        var range: Range<Int>?
        /// Marked text's caret, into it.
        var selection = 0
        var text: String
    }

    private(set) var text = ""
    private(set) var calls: [Call] = []
    var duringKey = false
    var marksAt = MarksAt.asked
    private var marking: NSRange?
    private var caretAt = 0

    var hasMarked: Bool { marking != nil }

    private static func plain(_ value: Any?) -> String { (value as? NSAttributedString)?.string ?? value as? String ?? "" }

    /// `text` in the field, the caret at `caret` (UTF-16), before anything is typed.
    func start(_ text: String, caret: Int) { (self.text, caretAt) = (text, caret) }

    /// The app types `characters` at the caret: a key the input method let go by.
    func typed(_ characters: String) {
        text = (text as NSString).replacingCharacters(in: NSRange(location: caretAt, length: 0), with: characters)
        caretAt += (characters as NSString).length
    }

    /// `string` in place of `given`, else of the marked text, else at the caret: where it went.
    private func put(_ string: String, replacing given: NSRange) -> NSRange {
        let range = given.location != NSNotFound ? given : marking ?? NSRange(location: caretAt, length: 0)
        text = (text as NSString).replacingCharacters(in: range, with: string)
        return range
    }

    override func insertText(_ string: Any!, replacementRange: NSRange) {
        let s = Self.plain(string)
        calls.append(Call(duringKey: duringKey, marks: false, range: AllInOneIMEInputController.range(replacementRange), text: s))
        let at = put(s, replacing: replacementRange)
        (marking, caretAt) = (nil, at.location + (s as NSString).length)
    }

    override func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        let s = Self.plain(string)
        calls.append(Call(duringKey: duringKey, marks: true, range: AllInOneIMEInputController.range(replacementRange),
                          selection: selectionRange.location, text: s))
        let given = switch marksAt {
        case .asked: replacementRange
        case .caret: NSRange(location: NSNotFound, length: 0)
        case .end: marking ?? NSRange(location: (text as NSString).length, length: 0)
        }
        let at = put(s, replacing: given)
        let length = (s as NSString).length
        marking = length == 0 ? nil : NSRange(location: at.location, length: length)
        if marksAt != .end { caretAt = at.location + min(selectionRange.location, length) }
    }

    override func selectedRange() -> NSRange { NSRange(location: caretAt, length: 0) }
    override func markedRange() -> NSRange { marking ?? NSRange(location: NSNotFound, length: 0) }
    override func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        let whole = text as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= whole.length else { return nil }
        return NSAttributedString(string: whole.substring(with: range))
    }
    override func length() -> Int { (text as NSString).length }

    /// `calls` as the harness's probe plays them (HARNESS_ANSWER, `standIn` in probe.m).
    static func answer(_ calls: [Call]) -> String {
        calls.map { call in
            let range = call.range.map { "\($0.lowerBound):\($0.count)" } ?? "none:0"
            let text = call.text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            return "\(call.duringKey ? "key" : "after"):\(call.marks ? "mark" : "insert"):\(range):\(call.selection):\(text)"
        }.joined(separator: ",")
    }

    /// `call` as the probe records it played ("answer …" without "REC <at> answer").
    static func recorded(_ call: Call) -> String {
        let range = call.range.map { "\($0.lowerBound) \($0.count)" } ?? "none 0"
        return "\(call.duringKey ? "key" : "after") \(call.marks ? "mark" : "insert") \(range) \(call.selection) \(call.text.utf16.count)"
    }
}

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
            /// `rawKeyDown`: a key down through TSMProcessRawKeyEvent, not the text input context (only recorded).
            case flagsChanged, keyDown, rawKeyDown, activate, deactivate
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
    /// percent-encoded>", "REC <at> rawKeyDown …" the same, "REC <at> activate", "REC <at> appActivated <bundle id>"); the
    /// others ("posted", "script", "end") say what the probe did, not what the input method got.
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
            case "flagsChanged", "keyDown", "rawKeyDown":
                guard let code = number(3), let flags = number(4), parts.count >= 6, let time = TimeInterval(parts[5]) else { return nil }
                let kind: Reached.Kind = parts[2] == "keyDown" ? .keyDown : parts[2] == "rawKeyDown" ? .rawKeyDown : .flagsChanged
                return Reached(at: at, kind: kind, keyCode: UInt16(code), flags: flags,
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
            case .rawKeyDown: break
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

    /// Translate as You Type's long press in Slack (an Electron app: every modifier change twice): a long press turns it
    /// on and, again, off, as in 0.6.6 (no chooser); a tap switches the input language once and toggles nothing, with the
    /// page busy too (the tap's copies after its release); Shift held with a capital, or with the pointer used (a
    /// Shift-click), toggles nothing. A tap of ⌥, the action key, acts once. The controller drops a copy before the
    /// composer and the long press see it, in any text field (`checkCopiesDroppedFirst`). Then the live harness, when there
    /// is one.
    static func testShiftHoldInElectron(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        section("Translate as You Type's long press of Shift in an Electron app (Slack)", needs: .composing)
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
        let onHint = tr("继续按住 → 边打边译", "Keep holding → Translate as You Type")
        // Held: the hint at 0.5 s, then on at 1.0 s, the hint seen while it's held; no chooser, no rows.
        var (hinted, rows) = (false, false)
        replay(hold, controller, client, after: 0.2) {
            hinted = hinted || controller.notice == onHint
            rows = rows || !controller.session.panelModel().rows.isEmpty
        }
        check(hinted && !rows && TranslateModeShared.state.isOn && controller.composer.translateMode?.target == .english
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
        // The page busy: the tap's down and up come again after its release, and still switch nothing.
        let busy = busyTap.filter { $0.kind == .flagsChanged }
        check(busy.count == 4 && busy[2].timestamp == busy[0].timestamp && busy[2].flags == busy[0].flags
              && busy[3].timestamp == busy[1].timestamp && busy[2].at > busy[1].at,
              "\(from), the page busy: Shift's down and up reach the input method again after the release (\(busy.map { String(format: "%.3f", $0.at) }))")
        replay(busyTap, controller, client, after: 1.0)
        check(controller.composer.inputLanguage == .english && !TranslateModeShared.state.isOn,
              "\(from), the page busy: a tap of Shift switches the input language once (\(controller.composer.inputLanguage)), not back")
        if controller.composer.inputLanguage == .english { tapShift(controller, client) }
        // Shift held with a capital typed: nothing turns on.
        replay(letter, controller, client, after: 0.3)
        check(!TranslateModeShared.state.isOn, "\(from): Shift held with a capital typed toggles nothing")
        controller.commitComposition(client)
        controller.composer.setInputMode(.chinese)
        client.inserted.removeAll()
        // A Shift-click (the pointer used while Shift is held): nothing turns on.
        controller.services.pointerUsedWithin = { _ in true }
        replay(hold, controller, client, after: 0.2)
        controller.services.pointerUsedWithin = { _ in false }
        check(!TranslateModeShared.state.isOn, "\(from): a Shift-click held as long toggles nothing")
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
    /// held: one switch, and Translate as You Type on (the copy of the tap's release, reaching the long press, would end
    /// the press; reaching the composer, the two copies would switch back). Then Shift+Tab with the page busy:
    /// the focus in the next field before Shift's copies come; there the copy of Shift's down and the release would be a
    /// tap, but the copy is known in every field (the composer of each field its own). Back in the field it left, Shift's
    /// down the last change seen there: the first long press turns it on all the same (taken for no copy of it).
    static func checkCopiesDroppedFirst(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        replay(reached(in: electronTapThenHoldBusy), controller, client, after: 0.2)
        check(TranslateModeShared.state.isOn && controller.composer.inputLanguage == .english,
              "a tap with the page busy, then a long press with its copies coming while Shift is held: the input language "
              + "switched once (\(controller.composer.inputLanguage)) and Translate as You Type on (\(controller.notice ?? "-"))")
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
        replay(reached(in: electronShiftHold), controller, client, after: 0.2)
        let reopened = TranslateModeShared.state.isOn
        if reopened { controller.toggleTranslateMode() }  // off again
        if let notice = controller.notice { controller.endNotice(notice) }
        check(reopened, "back in the field Shift+Tab left, Shift's release gone to the next one: the first long press turns it on")
    }

    /// The Electron harness itself, when `ALLINONEIME_ELECTRON_HARNESS` names its folder (`make electron-harness`: its
    /// Electron, downloaded by npm, and its probe): each script run in its window, Slack's composer then the textarea
    /// (about 2 s each, the window shown without taking the focus; the tap of Shift a second time with the page busy),
    /// and what reached the input method played into the fake field; "#17" typed, the page idle and busy, for how often
    /// each key down reaches the input method (`checkKeyDowns`, about 4 s each). Skipped, and said so, without it.
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
            checkKeyDowns(run("hash-digits"), from: "Electron harness, \(field)")
            checkKeyDowns(run("hash-digits", busy: 250), from: "Electron harness, \(field), the page busy")
        }
        let kept = (try? FileManager.default.contentsOfDirectory(atPath: userData.path)) ?? []
        check(!kept.isEmpty, "the Electron harness kept its data in a temporary folder (\(kept.count) items: "
              + "\(kept.sorted().prefix(3).joined(separator: ", "))…), removed after")
    }

    /// What the harness's "#17" (its hash-digits script: ⇧3, 1, 7) shows of key downs, `from` where it ran: each of the
    /// three reaching the input method, and how many times (a key down handed over again has the first one's time), and
    /// what the controller's guard (`KeyEchoes`, on the recording's clock) leaves of them: "#17", each key once. Passes
    /// either way; what it says is the finding. Expected, not yet seen busy: each key down once, the page busy or not, in
    /// both fields, none through TSMProcessRawKeyEvent. Chromium sends a key event the page let go by through
    /// -[NSApplication sendEvent:] again, and the input method gets a modifier change twice because sendEvent: itself
    /// hands it over; a key down reaches the input method only from the view (interpretKeyEvents:), which Chromium's
    /// window keeps an event sent again from. The recorded capital, the page idle (`electronShiftLetter`), came once.
    static func checkKeyDowns(_ recording: [Reached], from: String) {
        let downs = recording.filter { $0.kind == .keyDown }
        var times: [String: Int] = [:]
        for down in downs { times["\(down.keyCode) \(down.timestamp)", default: 0] += 1 }
        var echoes = KeyEchoes()
        var taken = ""
        for down in downs {
            // A second on, the recording's times are the clock's (one of 0 would be none).
            let key = KeyEchoes.Key(keyCode: down.keyCode, characters: down.characters, modifiers: down.flags, timestamp: down.timestamp + 1)
            guard echoes.copy(of: key, now: down.at + 1) == nil else { continue }
            echoes.answered(key, now: down.at + 1, handled: false)
            taken += down.characters
        }
        let again = downs.count - times.count, raw = recording.filter { $0.kind == .rawKeyDown }.count
        let each = downs.map { "\($0.characters) \(String(format: "%.3f", $0.at))" }.joined(separator: ", ")
        check(times.count == 3 && taken == "#17",
              "\(from): \"#17\" typed, its key downs reached the input method \(again == 0 ? "once each" : "with \(again) handed over again")"
                  + " (\(each)), \(raw) through TSMProcessRawKeyEvent; the controller takes \"\(taken)\"")
    }

    /// The harness's Electron, as npm installs it.
    static func electronBinary(in harness: URL) -> URL {
        harness.appendingPathComponent("node_modules/electron/dist/Electron.app/Contents/MacOS/Electron")
    }

    /// One run of the harness (its folder, `harness`): what its probe printed (nil: it didn't finish in time). Its key
    /// events go to its own window only, in its own process: the window is said to be key (`HARNESS_FAKE_KEY`; as it
    /// is while someone types in it) without taking the focus from the app in front. `busy`: milliseconds its page
    /// takes over each key down (`HARNESS_BUSY`). `userData`: the folder Electron keeps its data in
    /// (`HARNESS_USER_DATA`). `typed` and `answer`: what the type-enter script types, and the probe's answer to its Return
    /// (`HARNESS_TYPE`, `HARNESS_ANSWER`: the probe stands in for the input method, and the system's gets none of its keys).
    static func runElectronHarness(_ harness: URL, script: String, field: String, busy: Int? = nil, userData: URL,
                                   typed: String? = nil, answer: String? = nil) -> String? {
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
        (environment["HARNESS_TYPE"], environment["HARNESS_ANSWER"]) = (typed, answer)
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

/// Return on a suggestion row in Slack's composer: Chromium's view gives the page a key as the input method's ("Process",
/// 229) only while there is marked text, or when more than one character goes in during the key with no range; a
/// replacement (inserted with its range) or a single character goes in at once, and the page gets the key itself. 0.6.7.1's
/// Markdown link went in AND Slack sent the message. The Electron harness's page sends as Slack's does (a key down of
/// Enter, 13, not composing), and the probe plays the input method's answer to Return.
extension SelfTest {
    /// What the harness's page did with Return (index.html's "PAGE …" lines, the type-enter script) and how the probe
    /// answered it ("REC … answer …", `PageFieldClient.recorded`): Return's key downs as the page got them (the keyCode,
    /// "composing" if so), what it sent, its text in the end, whether marked text was left in the field.
    struct PageOutcome {
        var enters: [String] = []
        var sent: [String] = []
        var text: String?
        var markedLeft: Bool?
        var answered: [String] = []
    }

    static func pageOutcome(in recording: String) -> PageOutcome {
        var outcome = PageOutcome()
        for line in recording.split(whereSeparator: \.isNewline).map(String.init) {
            let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
            if parts.count == 3, parts[0] == "PAGE",
               let value = try? JSONSerialization.jsonObject(with: Data(parts[2].utf8), options: .fragmentsAllowed) {
                switch parts[1] {
                case "keydown":
                    guard let key = value as? [String: Any], key["key"] as? String == "Enter" else { break }
                    outcome.enters.append("\(key["keyCode"] as? Int ?? 0)" + (key["isComposing"] as? Bool == true ? " composing" : ""))
                case "sent": outcome.sent.append(value as? String ?? "")
                case "text": outcome.text = value as? String
                default: break
                }
            } else if parts.first == "REC" {
                let fields = line.split(separator: " ").map(String.init)
                if fields.count > 3, fields[2] == "answer" { outcome.answered.append(fields.dropFirst(3).joined(separator: " ")) }
                if fields.count == 4, fields[2] == "hasMarkedText" { outcome.markedLeft = fields[3] != "0" }
            }
        }
        return outcome
    }

    /// Recorded by the Electron harness (Electron 44.9.0, Slack's composer, the probe standing in for the input method),
    /// "#17" typed, then Return answered 0.6.7.1's way: the Markdown link inserted with the token's range during the key.
    /// The page gets Return itself (13) and sends.
    static let electronLinkInserted = """
        REC 0.0003 script type-enter com.github.Electron
        PAGE text "#17"
        REC 0.7807 keyDown 36 0x100 0.7767 %0D
        REC 0.7809 answer key insert 0 3 0 75
        PAGE text "[Return sends the message](https://github.com/octo-org/octo-repo/issues/17)"
        PAGE keydown {"key":"Enter","keyCode":13,"isComposing":false}
        PAGE sent "[Return sends the message](https://github.com/octo-org/octo-repo/issues/17)"
        REC 1.8759 hasMarkedText 0
        REC 2.3875 end
        """
    /// …0.6.7.2's: the link marked in the token's place during the key, committed on the run loop's next turn. The page
    /// gets Return as the input method's (229) and sends nothing.
    static let electronLinkMarked = """
        REC 0.0003 script type-enter com.github.Electron
        PAGE text "#17"
        REC 0.8042 keyDown 36 0x100 0.8011 %0D
        REC 0.8043 answer key mark 0 3 75 75
        REC 0.8126 answer after insert none 0 0 75
        PAGE keydown {"key":"Enter","keyCode":229,"isComposing":false}
        PAGE text "[Return sends the message](https://github.com/octo-org/octo-repo/issues/17)"
        PAGE text "[Return sends the message](https://github.com/octo-org/octo-repo/issues/17)"
        PAGE text "[Return sends the message](https://github.com/octo-org/octo-repo/issues/17)"
        REC 1.8851 hasMarkedText 0
        REC 2.4020 end
        """
    /// "#123" typed, Insert set to ID only: the "4" of #1234 marked at the caret during the key, committed after.
    static let electronOneMarked = """
        REC 0.0002 script type-enter com.github.Electron
        PAGE text "#123"
        REC 0.9640 keyDown 36 0x100 0.9598 %0D
        REC 0.9641 answer key mark none 0 1 1
        REC 0.9708 answer after insert none 0 0 1
        PAGE keydown {"key":"Enter","keyCode":229,"isComposing":false}
        PAGE text "#1234"
        PAGE text "#1234"
        PAGE text "#1234"
        REC 2.0209 hasMarkedText 0
        REC 2.5325 end
        """
    /// "#17" typed, ID only, ↓ to its own row (it adds nothing): its last character marked again, committed after.
    static let electronNothingMarked = """
        REC 0.0002 script type-enter com.github.Electron
        PAGE text "#17"
        REC 0.7890 keyDown 36 0x100 0.7849 %0D
        REC 0.7892 answer key mark 2 1 1 1
        REC 0.7979 answer after insert none 0 0 1
        PAGE keydown {"key":"Enter","keyCode":229,"isComposing":false}
        PAGE text "#17"
        PAGE text "#17"
        PAGE text "#17"
        REC 1.8565 hasMarkedText 0
        REC 2.3631 end
        """

    /// Return on a suggestion row in Slack's composer, a web page's field in Chromium's view (0.6.7.2; the GitHub plugin's
    /// issues, a stand-in for api.github.com). A row a key puts in where the page would also get the key (a replacement,
    /// one character, nothing) goes in as marked text during the key, committed once it's done (`markRow`): the Markdown
    /// link in place of "#17" by Return and by Tab, one character ("#123" → "#1234", ID only), and a row that adds nothing
    /// (its last character marked again); the next key, the field left or the app wanting everything in before the run
    /// loop turns commit it first. A field that puts marked text elsewhere (one that ignores the replacement range in
    /// setMarkedText) has it taken out again during the key, and gets 0.6.7.1's: the link with its range, the character
    /// at the caret, nothing. As before: a longer insertion, a terminal, a click on a row. In an NSTextView (iMessage's
    /// kind of field) the row is marked during the key, the text ends as 0.6.7.1's did, and one Undo leaves what it left;
    /// a snippet's caret after one character so put in still lands. Then the controller's calls played into the Electron harness's page when it's there
    /// (`ALLINONEIME_ELECTRON_HARNESS`), 0.6.7.1's way too, for what the page does; else what it recorded.
    static func testRowKeysInChromium(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("Suggestions: Return on a row in Slack's composer puts it in and sends nothing (Chromium's keys)", needs: .composing)
        typealias Call = PageFieldClient.Call
        let saved = (services: controller.services.suggestions, plugins: controller.services.plugins, password: controller.passwordField)
        let folder = snapshotDirectory.appendingPathComponent("suggestions-row-keys", isDirectory: true)
        defer {
            (controller.services.suggestions, controller.services.plugins) = (saved.services, saved.plugins)
            controller.passwordField = saved.password
            try? FileManager.default.removeItem(at: folder)
            controller.activateServer(client)
            controller.composer.setInputMode(settings.defaultInput)
            if let notice = controller.notice { controller.endNotice(notice) }
        }
        guard let approval = useGitHubPlugin(controller, in: folder) else { return }
        controller.passwordField = { false }  // these fields are no password fields, whatever has the focus
        func insert(_ choice: SuggestionsInsert) {
            controller.services.suggestions.settings = { SuggestionsSettings(enabled: [approval], insert: choice) }
        }
        let slack = "com.tinyspeck.slackmacgap"
        let link = "[Return sends the message](https://github.com/\(GitHubStandIn.repository)/issues/17)"
        let tab = ("\t", VirtualKey.tab)

        /// Into `field`, focused in English: `typed`, the app typing what the controller lets go by (`appTypes`); then the
        /// rows, the first's text starting with `first`; then ↓ `moves` times. Whether the rows showed.
        func typeInto(_ field: IMKTextInput, _ typed: String, first: String, moves: Int = 0, appTypes: (String) -> Void) -> Bool {
            controller.activateServer(field)
            controller.composer.setInputMode(.english)
            for character in typed {
                let text = String(character)
                let key = character == "#" ? event(text, code: 0x14, flags: .shift) : event(text, code: keyCodes[character] ?? 0)
                if !controller.handle(key, client: field) { appTypes(text) }
            }
            let shown = pump(timeout: 5) { controller.session.panelModel().rows.first?.text.hasPrefix(first) == true }
            for _ in 0..<moves { _ = controller.handle(event("", code: VirtualKey.down), client: field) }
            return shown
        }
        /// A Slack composer (another app's field: `app`) with `typed` in it, ↓ `moves` times, then `key`, and `then` before
        /// the run loop turns: the calls made during the key and after, whether the field had marked text right after the
        /// key, and the field.
        /// `marksAt`: where it puts marked text; `after`: its text after the caret.
        func inPage(_ typed: String, first: String, moves: Int = 0, key: (String, UInt16) = ("\r", VirtualKey.returnKey),
                    app: String? = nil, marksAt: PageFieldClient.MarksAt = .asked, after: String = "",
                    then: (PageFieldClient) -> Void = { _ in }) -> (handled: Bool, calls: [Call], markedDuring: Bool, page: PageFieldClient) {
            let page = PageFieldClient()
            page.bundleIDOverride = app ?? slack
            page.marksAt = marksAt
            page.start(after, caret: 0)
            let shown = typeInto(page, typed, first: first, moves: moves, appTypes: page.typed)
            let count = page.calls.count
            page.duringKey = true
            let handled = shown && controller.handle(event(key.0, code: key.1), client: page)
            page.duringKey = false
            let markedDuring = page.hasMarked
            then(page)
            _ = pump(timeout: 0.2) { false }  // the run loop's next turns: what goes in once the key is done
            controller.deactivateServer(page)
            return (handled, Array(page.calls.dropFirst(count)), markedDuring, page)
        }
        let said = { (calls: [Call]) in calls.map(PageFieldClient.recorded).joined(separator: "; ") }

        // The Markdown link: marked in place of "#17" during Return, committed after; Tab the same.
        insert(.markdownLink)
        let linkCalls = [Call(duringKey: true, marks: true, range: 0..<3, selection: link.utf16.count, text: link),
                         Call(duringKey: false, marks: false, range: nil, text: link)]
        let viaReturn = inPage("#17", first: "#17")
        check(viaReturn.handled && viaReturn.markedDuring && viaReturn.calls == linkCalls && viaReturn.page.text == link
              && !viaReturn.page.hasMarked,
              "Slack, Markdown link: Return marks the link in place of \"#17\" during the key and commits it after "
              + "(\(said(viaReturn.calls))): \(viaReturn.page.text)")
        let viaTab = inPage("#17", first: "#17", key: tab)
        check(viaTab.handled && viaTab.calls == linkCalls && viaTab.page.text == link, "…Tab the same (\(said(viaTab.calls)))")
        // Before the run loop turns, each commits it first: the next key, the field left, the app wanting everything in.
        let next = inPage("#17", first: "#17") { page in
            if !controller.handle(event("a", code: keyCodes["a"] ?? 0), client: page) { page.typed("a") }
        }
        let left = inPage("#17", first: "#17") { controller.deactivateServer($0) }
        let wanted = inPage("#17", first: "#17") { controller.commitComposition($0) }
        check(next.page.text == link + "a" && left.page.text == link && wanted.page.text == link
              && ![next, left, wanted].contains { $0.page.hasMarked || $0.calls.count != 2 },
              "…committed first by the next key (\(next.page.text)), the field left (\(left.page.text)), the app wanting "
              + "everything in (\(wanted.page.text)); nothing left marked")

        // One character (ID only: the "4" of #1234), and a row that adds nothing ("#17" typed in full, ↓ to its row): the
        // character marked at the caret, or the last one marked again in its place, then committed.
        insert(.id)
        let one = inPage("#123", first: "#1234")
        let oneCalls = [Call(duringKey: true, marks: true, range: nil, selection: 1, text: "4"), Call(duringKey: false, marks: false, range: nil, text: "4")]
        check(one.handled && one.markedDuring && one.calls == oneCalls && one.page.text == "#1234",
              "…ID only, one character: marked at the caret during the key, committed after (\(said(one.calls))): \(one.page.text)")
        let nothing = inPage("#17", first: "#17", moves: 1)
        let nothingCalls = [Call(duringKey: true, marks: true, range: 2..<3, selection: 1, text: "7"),
                            Call(duringKey: false, marks: false, range: nil, text: "7")]
        check(nothing.handled && nothing.markedDuring && nothing.calls == nothingCalls && nothing.page.text == "#17",
              "…a row that adds nothing: its last character marked again during the key, committed after (\(said(nothing.calls))): "
              + nothing.page.text)

        // A field that ignores the replacement range in setMarkedText (marked text at the caret, or at the end of its text):
        // what it marked elsewhere taken out again during the key, then 0.6.7.1's way; one character at the caret stays so.
        let unmark = Call(duringKey: true, marks: true, range: nil, selection: 0, text: "")
        insert(.markdownLink)
        let ignored = inPage("#17", first: "#17", marksAt: .caret)
        check(ignored.handled && !ignored.markedDuring && ignored.page.text == link && !ignored.page.hasMarked
              && ignored.calls == [linkCalls[0], unmark, Call(duringKey: true, marks: false, range: 0..<3, text: link)],
              "a field that ignores the range in setMarkedText: the link marked at the caret is taken out again, and goes in "
              + "with its range during the key as 0.6.7.1 did (\(said(ignored.calls))): \(ignored.page.text)")
        insert(.id)
        let atCaret = inPage("#123", first: "#1234", marksAt: .caret)
        check(atCaret.handled && atCaret.markedDuring && atCaret.calls == oneCalls && atCaret.page.text == "#1234",
              "…one character: at the caret where it asked, marked and committed (\(said(atCaret.calls))): \(atCaret.page.text)")
        let atEnd = inPage("#123", first: "#1234", marksAt: .end, after: " ok")
        check(atEnd.handled && !atEnd.markedDuring && atEnd.page.text == "#1234 ok" && !atEnd.page.hasMarked
              && atEnd.calls == [oneCalls[0], unmark, Call(duringKey: true, marks: false, range: nil, text: "4")],
              "…one character marked at the end, not at the caret: taken out again, inserted at the caret as 0.6.7.1 did "
              + "(\(said(atEnd.calls))): \(atEnd.page.text)")
        let nothingIgnored = inPage("#17", first: "#17", moves: 1, marksAt: .caret)
        check(nothingIgnored.handled && !nothingIgnored.markedDuring && nothingIgnored.page.text == "#17"
              && nothingIgnored.calls == [nothingCalls[0], unmark],
              "…a row that adds nothing marked at the caret: taken out again, nothing put in, as 0.6.7.1 did "
              + "(\(said(nothingIgnored.calls))): \(nothingIgnored.page.text)")

        // As before: a longer insertion and a terminal's during the key, a click with its range.
        insert(.titleAndLink)
        let rest = " Return sends the message https://github.com/\(GitHubStandIn.repository)/issues/17"
        let long = inPage("#17", first: "#17")
        check(long.handled && long.calls == [Call(duringKey: true, marks: false, range: nil, text: rest)] && long.page.text == "#17" + rest,
              "…With title and link: a longer insertion goes in during the key, as before (\(said(long.calls)))")
        insert(.id)
        let terminal = inPage("#123", first: "#1234", app: "com.apple.Terminal")
        check(terminal.handled && terminal.calls == [Call(duringKey: true, marks: false, range: nil, text: "4")],
              "…so does one character in a terminal (\(said(terminal.calls)))")
        insert(.markdownLink)
        let clicked = PageFieldClient()
        clicked.bundleIDOverride = slack
        let shown = typeInto(clicked, "#17", first: "#17", appTypes: clicked.typed)
        let count = clicked.calls.count
        let override = controller.clientOverride
        controller.clientOverride = clicked  // the field being typed in, where what a click answers goes
        if shown { controller.received(.pick(0)) }
        _ = pump(timeout: 0.2) { false }
        controller.clientOverride = override
        controller.deactivateServer(clicked)
        check(Array(clicked.calls.dropFirst(count)) == [Call(duringKey: false, marks: false, range: 0..<3, text: link)] && clicked.text == link,
              "…a click on the row puts the link in with its range, as before (\(said(Array(clicked.calls.dropFirst(count)))))")

        // An NSTextView, iMessage's kind of field: the text as 0.6.7.1's way left it, the caret after it, nothing marked,
        // and one Undo leaving what it left (what was typed: the row one change, the typing before it another).
        func inTextView(_ typed: String, first: String, put: (TextViewClient) -> Void) -> (text: String, caret: Int, marked: Bool, undone: String) {
            let view = TextViewClient()
            view.textView.allowsUndo = true
            defer {
                controller.deactivateServer(view)
                view.close()
            }
            let shown = typeInto(view, typed, first: first) { text in
                view.textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
                _ = pump(timeout: 0.02) { false }
            }
            guard shown else { return ("rows didn't show", 0, false, "") }
            view.textView.breakUndoCoalescing()  // a pause in typing, as before a row is picked
            put(view)
            _ = pump(timeout: 0.2) { false }
            let (text, caret, marked) = (view.text, view.caret.location, view.textView.hasMarkedText())
            view.textView.undoManager?.undo()
            return (text, caret, marked, view.text)
        }
        // Marked during the key: the field put it where asked (where it would be taken out again, nothing is marked).
        var markedByKey: String?
        let pressReturn = { (view: TextViewClient) in
            _ = controller.handle(event("\r", code: VirtualKey.returnKey), client: view)
            let marked = view.textView.markedRange()
            markedByKey = marked.location == NSNotFound ? nil : (view.text as NSString).substring(with: marked)
        }
        let linkBefore = inTextView("#17", first: "#17") { $0.insertText(link, replacementRange: NSRange(location: 0, length: 3)) }
        let linkNow = inTextView("#17", first: "#17", put: pressReturn)
        check(linkNow.text == link && linkNow == linkBefore && markedByKey == link,
              "an NSTextView: Return marks the link in place of \"#17\" during the key (\(markedByKey ?? "nothing marked")) and "
              + "it ends as 0.6.7.1's did (\(linkNow.text), caret \(linkNow.caret), "
              + "\(linkNow.marked ? "marked" : "nothing marked")); one Undo leaves \"\(linkNow.undone)\" (0.6.7.1's: \"\(linkBefore.undone)\")")
        insert(.id)
        let oneBefore = inTextView("#123", first: "#1234") { $0.insertText("4", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        markedByKey = nil
        let oneNow = inTextView("#123", first: "#1234", put: pressReturn)
        check(oneNow.text == "#1234" && oneNow == oneBefore && markedByKey == "4",
              "…one character marked at the caret (\(markedByKey ?? "nothing marked")), as before in the end (\(oneNow.text), "
              + "caret \(oneNow.caret)); one Undo leaves \"\(oneNow.undone)\" (0.6.7.1's: \"\(oneBefore.undone)\")")
        // A snippet's caret in one character so put in (")" with the caret before it): moved once it's committed.
        let view = TextViewClient()
        controller.activateServer(view)
        view.textView.insertText("f(", replacementRange: NSRange(location: NSNotFound, length: 0))
        controller.apply([.rowByKey, .commit(")"), .moveCaret(back: 1, after: ")")], client: view)
        let markedThen = view.textView.hasMarkedText()
        _ = pump(timeout: 0.2) { false }
        check(markedThen && view.text == "f()" && view.caret == NSRange(location: 2, length: 0) && !view.textView.hasMarkedText(),
              "…a snippet's caret after one character marked, then committed: \(view.text.debugDescription), the caret at \(view.caret.location)")
        controller.deactivateServer(view)
        view.close()

        // In the Electron harness's page: the controller's calls as the input method's answer to Return, 0.6.7.1's way for
        // contrast; without the harness, what it recorded (the controller's calls the recorded ones).
        var harness: URL?
        if let path = ProcessInfo.processInfo.environment["ALLINONEIME_ELECTRON_HARNESS"], !path.isEmpty {
            harness = URL(fileURLWithPath: path)
            if let folder = harness, !FileManager.default.isExecutableFile(atPath: electronBinary(in: folder).path)
                || !FileManager.default.fileExists(atPath: folder.appendingPathComponent("libprobe.dylib").path) {
                check(false, "the Electron harness in \(path) (Electron and libprobe.dylib: make electron-harness)")
                harness = nil
            }
        } else {
            print("  the Electron harness: not run (make electron-harness, then ELECTRON_HARNESS=build/electron-harness); what it recorded is checked")
        }
        let userData = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-electron-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: userData, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: userData) }
        let ways: [(what: String, typed: String, calls: [Call], text: String, sends: Bool, recorded: String)] = [
            ("0.6.7.1's way, the link inserted with its range during the key", "#17",
             [Call(duringKey: true, marks: false, range: 0..<3, text: link)], link, true, electronLinkInserted),
            ("the link marked during the key, committed after", "#17", viaReturn.calls, link, false, electronLinkMarked),
            ("one character marked during the key, committed after", "#123", one.calls, "#1234", false, electronOneMarked),
            ("a row that adds nothing, its last character marked again", "#17", nothing.calls, "#17", false, electronNothingMarked),
        ]
        for way in ways {
            let recording = harness.map {
                runElectronHarness($0, script: "type-enter", field: "composer", userData: userData, typed: way.typed,
                                   answer: PageFieldClient.answer(way.calls)) ?? ""
            } ?? way.recorded
            let outcome = pageOutcome(in: recording)
            check(outcome.answered == way.calls.map(PageFieldClient.recorded) && outcome.text == way.text && outcome.markedLeft == false
                  && outcome.enters == [way.sends ? "13" : "229"] && outcome.sent == (way.sends ? [way.text] : []),
                  "\(harness == nil ? "recorded" : "Electron harness"), Slack's composer, \(way.what): Return reached the page as "
                  + "\(outcome.enters), it sent \(outcome.sent.isEmpty ? "nothing" : "\(outcome.sent)"), its text \(outcome.text ?? "-") "
                  + "(\(outcome.answered.joined(separator: "; ")))")
        }
    }
}

import AllInOneIMETestSupport
import Foundation
import Testing

// The Mac controller's side of a draft kept on focus loss (#180), as the review of PR #188 found it (each test one
// finding): `deactivateServer` and `activateServer` on the real controller, with what the Mac is asked replaced
// (`DraftKeeper.shared.readers`: the element Accessibility tells has the focus, whether the input source is ours, the
// notification centre that tells of the lock and of another input source). A kept draft comes back only in the field
// it was typed in (the same controller, the same element, the caret where it was), never in a password field or with
// secure input on; it goes when another input source is selected, the screen locks or sleeps, after ten minutes;
// `deactivateServer` told twice changes nothing of what was kept, and a second controller keeping a draft drops the
// first one's.
//
// The ways run in ControllerOffMainTests' child (Sources/AllInOneIME compiled with a harness in main.swift's place):
// its fields are the child's own, nothing is typed into another app, the panel is drawn invisible.

@Suite(.serialized)
struct KeptDraftControllerTests {
    static func run(_ way: String) throws -> [String: String] { try ControllerOffMainChild.run("kept-" + way) }

    /// ⌘-Tab away and back: the same controller, the same element, the caret where it was. Held through the focus,
    /// then the panel and the draft as they were.
    @Test func backInTheSameFieldTheDraftShowsAgain() throws {
        let report = try Self.run("same")
        #expect(report["keptOnLeave"] == "true" && report["panelOnLeave"] == "false", "\(report)")
        #expect(report["shownAtOnce"] == "false", "shown before Accessibility told which field it is: \(report)")
        #expect(report["restored"] == "true" && report["input"] == "q" && report["typed"] == "", "\(report)")
    }

    /// Review #1 (wrong field): another empty field of the same controller's page takes the focus (both carets at
    /// {0, 0}): the draft doesn't show there, nothing of it goes in, and the field types as any.
    @Test func anotherFieldOfTheSameControllerNeverGetsTheDraft() throws {
        let report = try Self.run("other-field")
        #expect(report["keptOnLeave"] == "true", "\(report)")
        #expect(report["composing"] == "false" && report["kept"] == "false" && report["panel"] == "false", "\(report)")
        #expect(report["typed"] == "s" && report["first"] == "", "the other field holds \(report["typed"] ?? "?"): \(report)")
    }

    /// Review #1: where the field can't be told again (Accessibility not allowed, the element no text field), the draft
    /// goes as the field is left, as before #180, rather than risk another field.
    @Test func aFieldThatCantBeToldAgainKeepsNothing() throws {
        let report = try Self.run("unknown")
        #expect(report["keptOnLeave"] == "false" && report["composing"] == "false", "\(report)")
        #expect(report["restored"] == "false" && report["typed"] == "", "\(report)")
    }

    /// Review #1 (password field): secure input on when the focus is back (a password field of the same client), or
    /// Accessibility telling a password field: the draft goes, and the password's first key puts nothing of it in.
    @Test(arguments: ["secure-input", "secure-field"]) func aPasswordFieldNeverGetsTheDraft(_ way: String) throws {
        let report = try Self.run(way)
        #expect(report["keptOnLeave"] == "true", "\(report)")
        #expect(report["composing"] == "false" && report["kept"] == "false" && report["panel"] == "false", "\(report)")
        #expect(report["typed"] == "s", "the password field holds \(report["typed"] ?? "?"): \(report)")
    }

    /// Review #2: another input source selected (any, told by the system's notification, also while the field has no
    /// focus), and found selected as the field is left: nothing is kept.
    @Test func anotherInputSourceDropsTheDraft() throws {
        let report = try Self.run("source")
        #expect(report["keptBefore"] == "true" && report["afterNotification"] == "false", "\(report)")
        #expect(report["keptLeavingForABC"] == "false" && report["restored"] == "false", "\(report)")
    }

    /// Review #2: the session switched away from, the displays or the Mac asleep, the screen locked: the draft goes.
    @Test func lockAndSleepDropTheDraft() throws {
        let report = try Self.run("lock")
        #expect(report["kept"] == "true,true,true,true" && report["dropped"] == "true,true,true,true", "\(report)")
    }

    /// Review #2: a draft kept longer than its life (ten minutes; the child's is 0.2 s) goes, the field not back.
    @Test func aDraftKeptTooLongGoes() throws {
        let report = try Self.run("expiry")
        #expect(report["life"] == "600.0", "\(report)")
        #expect(report["keptOnLeave"] == "true" && report["keptLater"] == "false" && report["composing"] == "false", "\(report)")
    }

    /// Review #3: `deactivateServer` told again with the client gone doesn't forget the caret the field was left with:
    /// a field with the caret elsewhere still drops the draft.
    @Test func aSecondDeactivateKeepsTheCaretItWasLeftWith() throws {
        let report = try Self.run("double")
        #expect(report["keptOnLeave"] == "true" && report["keptAfterSecond"] == "true", "\(report)")
        #expect(report["restored"] == "false" && report["kept"] == "false", "\(report)")
    }

    /// Review #3: a second controller that keeps a draft (keys without an activation, then left) drops the first one's,
    /// which would otherwise come back with its field later; another controller's text field taking the focus does too,
    /// once Accessibility told it after the settle (an app with no text field leaves it kept: #200's acceptance tests).
    @Test func anotherControllerKeepingOrFocusedDropsTheFirstDraft() throws {
        let report = try Self.run("orphan")
        #expect(report["firstKept"] == "true" && report["secondKept"] == "true" && report["firstAfter"] == "false", "\(report)")
        #expect(report["firstRestored"] == "false", "\(report)")
        let other = try Self.run("other-controller")
        #expect(other["firstKept"] == "true" && other["firstAfter"] == "false" && other["firstRestored"] == "false", "\(other)")
    }

    /// #200: another controller activated before the first field's end is told (the app switched to told first) is
    /// asked as when it comes after: no text field told there leaves the draft kept, and it shows back in its field;
    /// another text field told drops it. Nothing of it goes into either field.
    @Test func anotherControllerActivatedFirstIsAskedAsWhenAfter() throws {
        let none = try Self.run("other-first-none")
        #expect(none["keptOnLeave"] == "true" && none["keptAfterSettle"] == "true", "\(none)")
        #expect(none["firstRestored"] == "true" && none["typed"] == "", "\(none)")
        let field = try Self.run("other-first-field")
        #expect(field["keptOnLeave"] == "true" && field["keptAfterSettle"] == "false", "\(field)")
        #expect(field["firstRestored"] == "false" && field["typed"] == "", "\(field)")
    }

    /// A modifier let go before the field is told (⌘ after ⌘-Tab) leaves the draft held, and it shows; a key typed
    /// before it is told drops it and is typed as any.
    @Test func aModifierBeforeTheFieldIsToldKeepsTheDraftAndAKeyDropsIt() throws {
        let modifier = try Self.run("modifier-held")
        #expect(modifier["heldAfterModifier"] == "true" && modifier["restored"] == "true", "\(modifier)")
        let key = try Self.run("key-held")
        #expect(key["kept"] == "false" && key["typed"] == "x" && key["restored"] == "false", "\(key)")
    }

    /// The second review #1: a modifier key that acts, before the field is told (a tap of Shift switches the input
    /// language, and would put what is composed into the field typed in now), drops the held draft first: nothing of it
    /// goes in, and it doesn't show later.
    @Test func aModifierKeyThatActsBeforeTheFieldIsToldDropsTheDraft() throws {
        let report = try Self.run("shift-held")
        #expect(report["keptAfterShiftDown"] == "false" && report["composing"] == "false", "\(report)")
        #expect(report["typed"] == "" && report["restored"] == "false" && report["owned"] == "false", "\(report)")
    }

    /// The Mac shows a kept draft only once Accessibility told the field (`DraftKeeper.verify`): a key with no
    /// activation told first drops it and is typed as any; a modifier key that acts drops it too, and one let go that
    /// does nothing leaves it kept and hidden, for the activation to come.
    @Test func withNoActivationToldAKeptDraftNeverShows() throws {
        let key = try Self.run("key-unfocused")
        #expect(key["keptOnLeave"] == "true" && key["kept"] == "false" && key["typed"] == "x" && key["owned"] == "false", "\(key)")
        let shift = try Self.run("shift-unfocused")
        #expect(shift["keptOnLeave"] == "true" && shift["kept"] == "false" && shift["composing"] == "false", "\(shift)")
        #expect(shift["typed"] == "" && shift["panel"] == "false" && shift["owned"] == "false", "\(shift)")
        let command = try Self.run("command-unfocused")
        #expect(command["keptAfterModifier"] == "true" && command["panelAfterModifier"] == "false", "\(command)")
        #expect(command["restored"] == "true" && command["typed"] == "", "\(command)")
    }

    /// The second review #2: another controller told `deactivateServer` late (a closing popover's) while the field the
    /// draft is kept for is asked of Accessibility doesn't end that wait: the draft shows in its field.
    @Test func anotherControllersLateDeactivateLeavesTheDraftToItsField() throws {
        let report = try Self.run("stray-deactivate")
        #expect(report["firstKept"] == "true" && report["heldMeanwhile"] == "true", "\(report)")
        #expect(report["firstRestored"] == "true", "the draft stayed held: \(report)")
    }

    /// The second review #2: an answer nothing waits for any more never leaves the draft held in the field that has the
    /// focus: it goes, nothing of it in.
    @Test func anAnswerNoLongerWaitedForNeverLeavesTheDraftHeld() throws {
        let report = try Self.run("stale")
        #expect(report["keptOnLeave"] == "true" && report["kept"] == "false" && report["composing"] == "false", "\(report)")
        #expect(report["typed"] == "" && report["owned"] == "false", "\(report)")
    }

    /// The second review #3: a key typed before the field is told drops the held draft and starts another: that one is
    /// told its field as any draft started is, so it is kept when the focus is lost, and comes back.
    @Test func aDraftStartedOverAHeldOneIsKeptForItsField() throws {
        let report = try Self.run("new-draft")
        // "@w" as the panel shows it while typed ("＠w" until its commands are listed, as any draft's first is).
        #expect(report["input"]?.hasSuffix("w") == true && report["input"]?.contains("q") == false, "\(report)")
        #expect(report["keptOnLeave"] == "true", "the new draft went with the focus: \(report)")
        #expect(report["restored"] == "true" && report["inputBack"] == "w" && report["typed"] == "", "\(report)")
    }

    /// The second review #4: which field it is can't be told where its subrole wasn't read (no answer in time, the
    /// element gone): unknown, never "no password field". One that has no subrole is none.
    @Test func aFieldWhoseSubroleWasNotReadIsUnknown() throws {
        let report = try Self.run("subrole")
        #expect(report["cannotComplete"] == "nil" && report["invalid"] == "nil" && report["failure"] == "nil", "\(report)")
        #expect(report["noValue"] == "false" && report["unsupported"] == "false", "\(report)")
        #expect(report["secure"] == "true" && report["plain"] == "false", "\(report)")
        #expect(report["roleNotRead"] == "nil" && report["noTextField"] == "nil", "\(report)")
    }

    /// After `OffMain`'s declarations in the child (ControllerOffMainTests' harness): the ways named "kept-…".
    static let harness = #"""

    /// What the child's Accessibility tells has the focus (any thread).
    final class KeptElement: @unchecked Sendable {
        private let lock = NSLock()
        private var name: String?
        private var secure = false
        func set(_ name: String?, secure: Bool = false) { lock.withLock { (self.name, self.secure) = (name, secure) } }
        var identity: FieldIdentity? {
            lock.withLock { name.map { FieldIdentity(element: $0 as CFString, secure: secure) } }
        }
    }

    @MainActor
    enum KeptDrafts {
        static let element = KeptElement()
        static let center = NotificationCenter()
        static var ours = true
        static var controller: AllInOneIMEInputController { OffMain.controller }

        /// The controller, with the Mac's answers the child's own: the element "A" has the focus, the input source is ours.
        static func make() {
            OffMain.make()
            configure()
        }

        static func configure() {
            let keeper = DraftKeeper.shared
            element.set("A")
            keeper.readers.identity = { element.identity }
            keeper.readers.sourceIsOurs = { ours }
            keeper.readers.distributed = center
            keeper.settle = 0.01
        }

        static func press(_ characters: String, code: UInt16, shift: Bool = false, on controller: AllInOneIMEInputController, into field: OffMainField) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [],
                                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, characters: characters,
                                         charactersIgnoringModifiers: shift ? "2" : characters, isARepeat: false, keyCode: code)!
            if !controller.handle(event, client: field) { field.insertText(characters, replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }

        /// "@q" typed into `field` (the @ list, its text "q"), and the element with the focus told.
        static func draft(in field: OffMainField) {
            controller.activateServer(field)
            typeDraft(on: controller, in: field)
        }

        static func typeDraft(on controller: AllInOneIMEInputController, in field: OffMainField) {
            press("@", code: 19, shift: true, on: controller, into: field)
            press("q", code: 12, on: controller, into: field)
            OffMain.pump(0.1)
        }

        static var panel: Bool { CandidatePanel.shared.isShowing }
        static var restored: Bool { !controller.session.keepsDraft && controller.composer.isComposing && panel }

        static func same() {
            make()
            let field = OffMainField()
            draft(in: field)
            controller.deactivateServer(field)
            OffMain.say("keptOnLeave", controller.session.keepsDraft)
            OffMain.say("panelOnLeave", panel)
            controller.activateServer(field)
            OffMain.say("shownAtOnce", panel)
            OffMain.pump(0.3)
            OffMain.say("restored", restored)
            OffMain.say("input", controller.session.panelModel().input?.text ?? "")
            OffMain.say("typed", field.document)
        }

        static func otherField() {
            make()
            let (first, second) = (OffMainField(), OffMainField())
            draft(in: first)
            controller.deactivateServer(first)
            OffMain.say("keptOnLeave", controller.session.keepsDraft)
            element.set("B")
            controller.activateServer(second)
            OffMain.pump(0.3)
            OffMain.say("composing", controller.composer.isComposing)
            OffMain.say("kept", controller.session.keepsDraft)
            OffMain.say("panel", panel)
            press("s", code: 1, on: controller, into: second)
            OffMain.pump(0.1)
            OffMain.say("typed", second.document)
            OffMain.say("first", first.document)
        }

        static func unknown() {
            make()
            element.set(nil)
            let field = OffMainField()
            draft(in: field)
            controller.deactivateServer(field)
            OffMain.say("keptOnLeave", controller.session.keepsDraft)
            OffMain.say("composing", controller.composer.isComposing)
            controller.activateServer(field)
            OffMain.pump(0.3)
            OffMain.say("restored", restored)
            OffMain.say("typed", field.document)
        }

        static func password(securInput: Bool) {
            make()
            let field = OffMainField()
            draft(in: field)
            controller.deactivateServer(field)
            OffMain.say("keptOnLeave", controller.session.keepsDraft)
            if securInput { controller.services.secureInputActive = { true } } else { element.set("A", secure: true) }
            controller.activateServer(field)
            OffMain.pump(0.3)
            OffMain.say("composing", controller.composer.isComposing)
            OffMain.say("kept", controller.session.keepsDraft)
            OffMain.say("panel", panel)
            controller.services.secureInputActive = { true }  // the password's key, as the Mac tells it
            press("s", code: 1, on: controller, into: field)
            OffMain.pump(0.1)
            OffMain.say("typed", field.document)
        }

        static func source() {
            make()
            let field = OffMainField()
            draft(in: field)
            controller.deactivateServer(field)
            OffMain.say("keptBefore", controller.session.keepsDraft)
            center.post(name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
            OffMain.pump(0.1)
            OffMain.say("afterNotification", controller.session.keepsDraft || controller.composer.isComposing)
            // Found selected as the field is left (the system didn't have the input method commit first).
            draft(in: field)
            ours = false
            controller.deactivateServer(field)
            OffMain.say("keptLeavingForABC", controller.session.keepsDraft || controller.composer.isComposing)
            ours = true
            controller.activateServer(field)
            OffMain.pump(0.3)
            OffMain.say("restored", restored)
        }

        static func lock() {
            make()
            let field = OffMainField()
            let workspace = NSWorkspace.shared.notificationCenter
            let endings: [(NotificationCenter, Notification.Name)] = [
                (workspace, NSWorkspace.sessionDidResignActiveNotification), (workspace, NSWorkspace.screensDidSleepNotification),
                (workspace, NSWorkspace.willSleepNotification), (center, Notification.Name("com.apple.screenIsLocked")),
            ]
            var (kept, dropped): ([Bool], [Bool]) = ([], [])
            for (center, name) in endings {
                draft(in: field)
                controller.deactivateServer(field)
                kept.append(controller.session.keepsDraft)
                center.post(name: name, object: nil)
                OffMain.pump(0.1)
                dropped.append(!controller.session.keepsDraft && !controller.composer.isComposing)
            }
            OffMain.say("kept", kept.map(String.init).joined(separator: ","))
            OffMain.say("dropped", dropped.map(String.init).joined(separator: ","))
        }

        static func expiry() {
            make()
            OffMain.say("life", DraftKeeper.shared.life)
            DraftKeeper.shared.life = 0.2
            let field = OffMainField()
            draft(in: field)
            controller.deactivateServer(field)
            OffMain.say("keptOnLeave", controller.session.keepsDraft)
            OffMain.pump(0.6)
            OffMain.say("keptLater", controller.session.keepsDraft)
            OffMain.say("composing", controller.composer.isComposing)
        }

        static func double() {
            make()
            let (field, elsewhere) = (OffMainField(), OffMainField())
            field.insertText("ab", replacementRange: NSRange(location: NSNotFound, length: 0))
            draft(in: field)
            controller.deactivateServer(field)
            OffMain.say("keptOnLeave", controller.session.keepsDraft)
            controller.deactivateServer(nil)
            OffMain.say("keptAfterSecond", controller.session.keepsDraft)
            // The same element told (a page that tells one for all its fields), the caret elsewhere: not the field left.
            controller.activateServer(elsewhere)
            OffMain.pump(0.3)
            OffMain.say("restored", restored)
            OffMain.say("kept", controller.session.keepsDraft)
        }

        static func second() -> AllInOneIMEInputController {
            let first = controller
            OffMain.make()
            let second = controller
            OffMain.controller = first
            configure()
            return second
        }

        static func orphan(activating: Bool) {
            make()
            let (first, firstField, secondField) = (controller, OffMainField(), OffMainField())
            draft(in: firstField)
            first.deactivateServer(firstField)
            OffMain.say("firstKept", first.session.keepsDraft)
            let second = second()
            element.set("B")
            if activating {
                second.activateServer(secondField)
                OffMain.pump(0.3)  // the element with the focus asked once it settled: another text field, "B"
            } else {
                // Keys with no activation told first, then left.
                typeDraft(on: second, in: secondField)
                second.deactivateServer(secondField)
                OffMain.say("secondKept", second.session.keepsDraft)
            }
            OffMain.say("firstAfter", first.session.keepsDraft || first.composer.isComposing)
            if activating { second.deactivateServer(secondField) }
            element.set("A")
            first.activateServer(firstField)
            OffMain.pump(0.3)
            OffMain.say("firstRestored", restored)
        }

        /// The second controller activated before the first one's field is left, Accessibility telling `told` there.
        static func otherFirst(_ told: String?) {
            make()
            let (first, firstField, secondField) = (controller, OffMainField(), OffMainField())
            draft(in: firstField)
            let second = second()
            element.set(told)
            second.activateServer(secondField)
            first.deactivateServer(firstField)
            OffMain.say("keptOnLeave", first.session.keepsDraft)
            OffMain.pump(0.3)
            OffMain.say("keptAfterSettle", first.session.keepsDraft)
            second.deactivateServer(secondField)
            element.set("A")
            first.activateServer(firstField)
            OffMain.pump(0.3)
            OffMain.say("firstRestored", restored)
            OffMain.say("typed", firstField.document + secondField.document)
        }

        static func held(key: Bool) {
            make()
            DraftKeeper.shared.settle = 0.15
            let field = OffMainField()
            draft(in: field)
            controller.deactivateServer(field)
            controller.activateServer(field)
            if key {
                press("x", code: 7, on: controller, into: field)
                OffMain.say("kept", controller.session.keepsDraft)
            } else {
                let up = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55)
                if let up { _ = controller.handle(up, client: field) }
                OffMain.say("heldAfterModifier", controller.session.keepsDraft && !panel)
            }
            OffMain.pump(0.5)
            OffMain.say("restored", restored)
            OffMain.say("typed", field.document)
        }

        /// A modifier key changed: `code` its key, `flags` those down now (the device's bits with them, as the Mac tells).
        static func flags(_ code: UInt16, _ flags: UInt, on controller: AllInOneIMEInputController, in field: OffMainField) {
            let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
                                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, characters: "",
                                         charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)
            if let event { _ = controller.handle(event, client: field) }
        }

        /// A tap of the left Shift.
        static func tapShift(in field: OffMainField, between: () -> Void = {}) {
            flags(56, 0x20102, on: controller, in: field)
            between()
            flags(56, 0x100, on: controller, in: field)
        }

        static var owned: Bool { DraftKeeper.shared.owner != nil }

        /// A draft typed and left, the field active again and still asked of Accessibility: Shift tapped.
        static func shiftHeld() {
            make()
            DraftKeeper.shared.settle = 0.15
            let field = OffMainField()
            draft(in: field)
            controller.deactivateServer(field)
            controller.activateServer(field)
            tapShift(in: field) { OffMain.say("keptAfterShiftDown", controller.session.keepsDraft) }
            OffMain.say("composing", controller.composer.isComposing)
            OffMain.pump(0.5)
            OffMain.say("restored", restored)
            OffMain.say("owned", owned)
            OffMain.say("typed", field.document)
        }

        /// A key, a tap of Shift or ⌘ let go with no activation told after the field was left.
        static func unfocused(_ way: String) {
            make()
            let field = OffMainField()
            draft(in: field)
            controller.deactivateServer(field)
            OffMain.say("keptOnLeave", controller.session.keepsDraft)
            switch way {
            case "key": press("x", code: 7, on: controller, into: field)
            case "shift": tapShift(in: field)
            default:
                flags(55, 0x100, on: controller, in: field)
                OffMain.say("keptAfterModifier", controller.session.keepsDraft)
                OffMain.pump(0.3)
                OffMain.say("panelAfterModifier", panel)
                controller.activateServer(field)
            }
            OffMain.say("kept", controller.session.keepsDraft)
            OffMain.say("composing", controller.composer.isComposing)
            OffMain.say("panel", panel)
            OffMain.say("owned", owned)
            OffMain.pump(0.3)
            OffMain.say("restored", restored)
            OffMain.say("typed", field.document)
        }

        static func strayDeactivate() {
            make()
            DraftKeeper.shared.settle = 0.15
            let (first, firstField, secondField) = (controller, OffMainField(), OffMainField())
            draft(in: firstField)
            first.deactivateServer(firstField)
            OffMain.say("firstKept", first.session.keepsDraft)
            let second = second()
            DraftKeeper.shared.settle = 0.15
            first.activateServer(firstField)
            second.deactivateServer(secondField)  // late: its field lost the focus before
            OffMain.say("heldMeanwhile", first.session.keepsDraft && !panel)
            OffMain.pump(0.5)
            OffMain.say("firstRestored", restored)
        }

        static func stale() {
            make()
            DraftKeeper.shared.settle = 0.15
            let field = OffMainField()
            draft(in: field)
            controller.deactivateServer(field)
            OffMain.say("keptOnLeave", controller.session.keepsDraft)
            controller.activateServer(field)
            DraftKeeper.shared.verifying += 1  // the wait ended by something that is neither the field left nor the draft gone
            OffMain.pump(0.5)
            OffMain.say("kept", controller.session.keepsDraft)
            OffMain.say("composing", controller.composer.isComposing)
            OffMain.say("owned", owned)
            OffMain.say("typed", field.document)
        }

        static func newDraft() {
            make()
            DraftKeeper.shared.settle = 0.15
            let field = OffMainField()
            draft(in: field)
            controller.deactivateServer(field)
            controller.activateServer(field)
            press("@", code: 19, shift: true, on: controller, into: field)
            press("w", code: 13, on: controller, into: field)
            OffMain.pump(0.5)
            OffMain.say("input", controller.session.panelModel().input?.text ?? "")
            controller.deactivateServer(field)
            OffMain.say("keptOnLeave", controller.session.keepsDraft)
            controller.activateServer(field)
            OffMain.pump(0.5)
            OffMain.say("restored", restored)
            OffMain.say("inputBack", controller.session.panelModel().input?.text ?? "")
            OffMain.say("typed", field.document)
        }

        static func subrole() {
            let (element, field) = ("A" as CFString, kAXTextFieldRole as CFString)
            func told(_ role: (AXError, CFTypeRef?), _ subrole: (AXError, CFTypeRef?)) -> String {
                FocusedField.identity(of: element, role: role, subrole: subrole).map { String($0.secure) } ?? "nil"
            }
            OffMain.say("cannotComplete", told((.success, field), (.cannotComplete, nil)))
            OffMain.say("invalid", told((.success, field), (.invalidUIElement, nil)))
            OffMain.say("failure", told((.success, field), (.failure, nil)))
            OffMain.say("noValue", told((.success, field), (.noValue, nil)))
            OffMain.say("unsupported", told((.success, field), (.attributeUnsupported, nil)))
            OffMain.say("secure", told((.success, field), (.success, kAXSecureTextFieldSubrole as CFString)))
            OffMain.say("plain", told((.success, field), (.success, "AXSearchField" as CFString)))
            OffMain.say("roleNotRead", told((.cannotComplete, nil), (.success, nil)))
            OffMain.say("noTextField", told((.success, "AXWebArea" as CFString), (.noValue, nil)))
        }

        static func run(_ way: String) -> Bool {
            switch way {
            case "kept-shift-held": shiftHeld()
            case "kept-key-unfocused": unfocused("key")
            case "kept-shift-unfocused": unfocused("shift")
            case "kept-command-unfocused": unfocused("command")
            case "kept-stray-deactivate": strayDeactivate()
            case "kept-stale": stale()
            case "kept-new-draft": newDraft()
            case "kept-subrole": subrole()
            case "kept-same": same()
            case "kept-other-field": otherField()
            case "kept-unknown": unknown()
            case "kept-secure-input": password(securInput: true)
            case "kept-secure-field": password(securInput: false)
            case "kept-source": source()
            case "kept-lock": lock()
            case "kept-expiry": expiry()
            case "kept-double": double()
            case "kept-orphan": orphan(activating: false)
            case "kept-other-controller": orphan(activating: true)
            case "kept-other-first-none": otherFirst(nil)
            case "kept-other-first-field": otherFirst("B")
            case "kept-modifier-held": held(key: false)
            case "kept-key-held": held(key: true)
            default: return false
            }
            return true
        }
    }
    """#
}

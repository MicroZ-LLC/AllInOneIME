import AppKit
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMEMac
import AllInOneIMETestSupport

/// The keys the input method posts itself (`PostedKeys`): its ⌃V (a kept image's paste, ⌃V again) reaches the app at the
/// key tap and as the app hands it over, where its mark is gone, and is never answered as the user's; the user's own ⌃V
/// right after still opens clipboard history. The owner's terminal (0.7.0): ⏎ on a kept image opened the history again
/// instead of pasting it, and so did every ⌃V again.
@Suite(.serialized)
struct PostedKeysTests {
    static let control = UInt64(CGEventFlags.maskControl.rawValue)
    static let command = UInt64(CGEventFlags.maskCommand.rawValue)
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let shot = ClipboardHistoryImage(id: "shot", width: 640, height: 480, bytes: 120_107, thumbnail: "/tmp/shot-thumb.png")

    /// V down with `flags` at `time` (seconds of uptime), marked as the input method marks the keys it posts, or not (the
    /// user's).
    static func v(_ flags: CGEventFlags = .maskControl, at time: TimeInterval, marked: Bool) -> CGEvent {
        let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: 0x09, keyDown: true)!
        event.flags = flags
        event.timestamp = UInt64(time * 1_000_000_000)
        if marked { event.setIntegerValueField(.eventSourceUserData, value: PostedKeys.marker) }
        return event
    }

    /// `event` as the app hands it to the input method, in another process: its data sent over, made an event again.
    static func handedOver(_ event: CGEvent) -> NSEvent {
        NSEvent(cgEvent: CGEvent(withDataAllocator: nil, data: event.data!)!)!
    }

    /// A field's session with clipboard history (texts and a kept image) as the input method's shell has it, its keys as
    /// the shell takes them: at the key tap, then handed over by the app, a key posted here never answered (`PostedKeys`),
    /// any other the session's.
    final class Shell {
        let host: FakeHost
        var keys = PostedKeys()

        init(terminal: Bool = true) {
            var config = Config.default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
            var services = SessionServices(loadSettings: { [config] in config })
            let engine = FakeEngine()
            services.levelOne = { .engine(engine) }
            host = FakeHost(services: services)
            host.terminal = terminal
            host.clipboardNow = PostedKeysTests.now
            host.clipboardHistory = [ClipboardHistoryItem(image: PostedKeysTests.shot, copiedAt: PostedKeysTests.now - 60),
                                     ClipboardHistoryItem(text: "gamma", copiedAt: PostedKeysTests.now - 300)]
            host.clipboardImages = [PostedKeysTests.shot.id: Data([0x89, 0x50, 0x4E, 0x47])]
            host.clipboard = .none  // what the paste of ours leaves there: transient, nothing usable
            host.keepClipboardHistory()
            host.focus()
        }

        /// The app's own paste key posted, as `TerminalPaste.postV` posts it: the key is remembered, then posted marked
        /// (`at` the time the system gives it).
        func post(_ flags: CGEventFlags = .maskControl, now: TimeInterval) -> CGEvent {
            keys.posting(keyCode: 0x09, modifiers: UInt64(flags.rawValue), now: now)
            return PostedKeysTests.v(flags, at: now, marked: true)
        }

        /// `event` at the key tap (`KeyGuard`): true, it goes on untouched (ours); else the session answers it
        /// (`keyAtTap`), whether it took it.
        func atTap(_ event: CGEvent, now: TimeInterval) -> (ours: Bool, took: Bool) {
            let key = PostedKeys.Key(NSEvent(cgEvent: event)!)
            if keys.atTap(key, marked: PostedKeys.isMarked(event), now: now) { return (true, false) }
            return (false, host.press(FakeHost.controlV))
        }

        /// `event` handed over by the app (IMK, `handleKeyDown`): true, ours, it goes on to the app; else the session's.
        func handedOver(_ event: CGEvent, now: TimeInterval) -> (ours: Bool, took: Bool) {
            let handed = PostedKeysTests.handedOver(event)
            let marked = handed.cgEvent.map(PostedKeys.isMarked) ?? false
            if keys.handedOver(PostedKeys.Key(handed), marked: marked, now: now) { return (true, false) }
            return (false, host.press(FakeHost.controlV))
        }

        /// The clipboard reads ⌃V asked for (the panel opening).
        var historyReads: Int {
            host.outputs.filter { if case let .readClipboard(id) = $0 { id < 0 } else { false } }.count
        }
    }

    // MARK: - Why

    /// The mark stays with the event in this process (the key tap has it), and is gone once its data is sent to another
    /// (as an app hands a key over to the input method), archived or sent as an event's data: its key, ⌃ and time stay.
    /// So reading the mark alone, as 0.6.8.2 to 0.7.0 did, took every ⌃V of ours the app handed over for the user's.
    @Test func theMarkDoesNotLeaveTheProcess() throws {
        let posted = Self.v(at: 100, marked: true)
        #expect(PostedKeys.isMarked(posted) && PostedKeys.isMarked(NSEvent(cgEvent: posted)!.cgEvent!))
        let sent = try #require(CGEvent(withDataAllocator: nil, data: try #require(posted.data)))
        #expect(!PostedKeys.isMarked(sent), "an event's data sent over keeps no mark")
        let archived = try NSKeyedArchiver.archivedData(withRootObject: NSEvent(cgEvent: posted)!, requiringSecureCoding: false)
        let unarchived = try #require(try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(archived) as? NSEvent)
        #expect(!PostedKeys.isMarked(try #require(unarchived.cgEvent)), "nor an event archived")
        for event in [NSEvent(cgEvent: sent)!, unarchived] {
            #expect(PostedKeys.Key(event) == PostedKeys.Key(keyCode: 0x09, modifiers: Self.control, timestamp: 100))
        }
    }

    // MARK: - Ours passes

    /// The ⌃V posted goes on at the key tap and again as the app hands it over, though its mark is gone there: the session
    /// never has it, so no clipboard history opens on it.
    @Test func ourPostedControlVPasses() {
        let shell = Shell()
        let posted = shell.post(now: 100)
        #expect(shell.atTap(posted, now: 100.001).ours, "at the tap, by its mark")
        #expect(shell.handedOver(posted, now: 100.035).ours, "handed over by the app, its mark gone")
        #expect(shell.historyReads == 0 && shell.host.panel == nil, "\(shell.host.outputs)")
    }

    /// The owner's terminal: ⌃V, ⏎ on the kept image pastes it with ⌃V; that ⌃V reaches the app (Claude Code takes the
    /// image) and the history doesn't open again.
    @Test func aKeptImagePastedReachesTheApp() {
        let shell = Shell()
        #expect(shell.atTap(Self.v(at: 99, marked: false), now: 99).took && shell.host.panel != nil, "the user's ⌃V shows the history")
        #expect(shell.host.press(FakeHost.enter) && shell.host.imagesPasted == [Self.shot.id] && shell.host.panel == nil)
        let posted = shell.post(now: 100)
        #expect(shell.atTap(posted, now: 100.001).ours && shell.handedOver(posted, now: 100.033).ours)
        #expect(shell.historyReads == 1 && shell.host.panel == nil, "opened once, by the user's ⌃V")
    }

    // MARK: - The user's ⌃V

    /// The user's ⌃V right after ours (50 ms) is the user's: at the tap it opens the history; handed over by the app (where
    /// the tap didn't take it: marked text of the session's there) it does too, by its own time, also while ours, past the
    /// tap, isn't handed over yet (an app busy with output) or never is.
    @Test func aRealControlVRightAfterStillOpensHistory() {
        let shell = Shell()
        let posted = shell.post(now: 100)
        #expect(shell.atTap(posted, now: 100.001).ours && shell.handedOver(posted, now: 100.02).ours)
        let real = Self.v(at: 100.05, marked: false)
        let tap = shell.atTap(real, now: 100.05)
        #expect(!tap.ours && tap.took && shell.historyReads == 1, "at the tap: the user's, the history opens")

        let other = Shell()
        let ours = other.post(now: 100)
        #expect(other.atTap(ours, now: 100.001).ours)
        let handed = other.handedOver(Self.v(at: 100.05, marked: false), now: 100.06)
        #expect(!handed.ours && handed.took && other.historyReads == 1, "handed over: the user's, by its own time")
        #expect(other.handedOver(ours, now: 100.07).ours, "ours handed over late is still ours")
    }

    // MARK: - ⌃V again

    /// ⌃V with the history showing: ⌃V again posts the app's own ⌃V, which passes once, a copy of it too (a page hands a
    /// key over twice), without opening the history again; the user's next ⌃V opens it.
    @Test func controlVAgainPassesOnceAndDoesNotReopenHistory() {
        let shell = Shell()
        #expect(shell.atTap(Self.v(at: 99, marked: false), now: 99).took && shell.host.panel != nil)
        #expect(shell.atTap(Self.v(at: 99.5, marked: false), now: 99.5).took, "⌃V again, taken at the tap")
        #expect(shell.host.pasteKeysPassed == 1 && shell.host.panel == nil, "the app's own paste asked for")
        let posted = shell.post(now: 99.7)  // once ⌃ is up
        #expect(shell.atTap(posted, now: 99.701).ours)
        #expect(shell.handedOver(posted, now: 99.72).ours && shell.handedOver(posted, now: 99.75).ours, "it and its copy")
        #expect(shell.historyReads == 1 && shell.host.panel == nil, "the history didn't open again: \(shell.host.outputs)")
        let next = shell.atTap(Self.v(at: 100.4, marked: false), now: 100.4)
        #expect(!next.ours && next.took && shell.historyReads == 2 && shell.host.panel != nil, "the user's next ⌃V shows it")
    }

    // MARK: - Without the tap

    /// Where the tap didn't see it (off, or turned off by macOS a moment): the first ⌃V like it handed over after it was
    /// posted is ours, once; the next is the user's, and so is one from before it was posted.
    @Test func withoutTheTapTheFirstLikeItOnce() {
        let shell = Shell()
        let posted = shell.post(now: 100)
        let early = shell.handedOver(Self.v(at: 99.9, marked: false), now: 100.01)
        #expect(!early.ours && early.took, "pressed before ours was posted: the user's")
        #expect(shell.handedOver(posted, now: 100.02).ours, "ours")
        #expect(shell.handedOver(posted, now: 100.03).ours, "its copy, by its time")
        #expect(!shell.handedOver(Self.v(at: 100.2, marked: false), now: 100.2).ours, "the next: the user's")

        var keys = PostedKeys()
        keys.posting(keyCode: 0x09, modifiers: Self.control, now: 100)
        let untimed = PostedKeys.Key(keyCode: 0x09, modifiers: Self.control)
        let first = keys.handedOver(untimed, marked: false, now: 100.02), second = keys.handedOver(untimed, marked: false, now: 100.03)
        #expect(first, "no time told: the first like it")
        #expect(!second, "once")
    }

    /// A key down ⌃V-like: `code`, `modifiers` (⌃ unless said), at `time`.
    static func key(_ code: UInt16 = 0x09, _ modifiers: UInt64 = control, at time: TimeInterval) -> PostedKeys.Key {
        PostedKeys.Key(keyCode: code, modifiers: modifiers, timestamp: time)
    }

    /// A key like it that comes after `window` is the user's; a key not like it (⌘V for a ⌃V, V alone) never is ours;
    /// Caps Lock or a side's bit don't make it another.
    @Test func onlyTheSameKeyWithinTheWindow() {
        var keys = PostedKeys()
        keys.posting(keyCode: 0x09, modifiers: Self.control, now: 100)
        let others = [Self.key(0x09, Self.command, at: 100.01), Self.key(0x09, 0, at: 100.01), Self.key(0x08, at: 100.01)]
            .map { keys.handedOver($0, marked: false, now: 100.01) }
        #expect(others == [false, false, false], "⌘V, V alone, ⌃C")
        let late = keys.handedOver(Self.key(at: 102.5), marked: false, now: 102.5)
        #expect(!late, "past the window")

        var command = PostedKeys()
        command.posting(keyCode: 0x09, modifiers: Self.command, now: 100)
        let capsLock = UInt64(CGEventFlags.maskAlphaShift.rawValue) | 0x10  // Caps Lock, the left ⌘'s own bit
        let pasted = command.handedOver(Self.key(0x09, Self.command | capsLock, at: 100.01), marked: false, now: 100.01)
        #expect(pasted, "⌘V posted (text pasted, an app's own paste)")
    }

    /// At the tap only the mark tells: a ⌃V not marked is the user's even right after one was posted (and leaves the post
    /// for its own key), and a marked one is ours even with nothing posted (posted longer ago), then known handed over.
    @Test func atTheTapTheMarkTells() {
        var keys = PostedKeys()
        keys.posting(keyCode: 0x09, modifiers: Self.control, now: 100)
        let users = keys.atTap(Self.key(at: 100), marked: false, now: 100)
        let ours = keys.atTap(Self.key(at: 100.001), marked: true, now: 100.001)
        let handed = keys.handedOver(Self.key(at: 100.001), marked: false, now: 100.03)
        #expect(!users && ours && handed)

        var late = PostedKeys()
        let marked = late.atTap(Self.key(at: 50), marked: true, now: 105)
        let itsCopy = late.handedOver(Self.key(at: 50), marked: false, now: 105.02)
        let next = late.handedOver(Self.key(at: 105.1), marked: false, now: 105.1)
        #expect(marked && itsCopy && !next)
    }
}

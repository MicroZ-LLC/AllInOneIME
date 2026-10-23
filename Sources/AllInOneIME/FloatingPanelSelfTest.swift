import AllInOneIMECore
import AppKit

/// Stand-ins for everything the menu bar panel reads and opens: sample data, and a record of what it
/// asked for. Nothing reaches Notes, EventKit or Claude Code; the setting, the frame and the saved
/// notes stay in memory.
@MainActor
final class PanelStandIns {
    var now = Date()
    var notesRunning = false
    /// What Notes would say of the folder.
    var listedNotes = NotesListing.notAllowed
    /// Opening a note, listing the folder: they wait while these are set (the panel is turned off
    /// meanwhile); opening fails with `showError`.
    var holdShow = false, holdList = false
    var showError: Error?
    var access = ReminderAccess.allowed
    /// The user's answer when the panel's button has macOS ask.
    var answer = ReminderAccess.allowed
    var reminders: [RemindersBridge.Reminder] = []
    /// What `claude agents` lists (nil: Claude Code isn't installed).
    var sessions: [AgentSession]? = []
    /// The transcripts' last replies (session id → reply): one changed is a transcript changed.
    var replies: [String: String] = [:]
    var monitorWatching = false
    /// Autocomplete's switch, as the panel turns it (nothing is written).
    var autocomplete = false
    /// The command trigger the settings would have.
    var commandTrigger = "@"
    let defaults = MemoryKeyValueStore()

    /// `transcriptReads`: the transcripts read (not those the panel already read as they are).
    private(set) var noteLists = 0, reminderReads = 0, agentLooks = 0, transcriptReads = 0
    private(set) var shownNotes: [String] = [], completed: [String] = [], openedAgents: [String] = []
    /// The files and Notion pages the panel would have opened (nothing is).
    private(set) var openedURLs: [URL] = []
    /// The folder notes are saved to, as the config would say it: only files in it are opened.
    var notesFolder: URL?
    private(set) var openedReminders = 0, openedSettings = 0

    var sources: DashboardSources {
        var sources = DashboardSources(
            notesRunning: { self.notesRunning },
            listNotes: { _ in
                self.noteLists += 1
                while self.holdList { try await Task.sleep(nanoseconds: 10_000_000) }
                return self.listedNotes
            },
            showNote: { id in
                while self.holdShow { try await Task.sleep(nanoseconds: 10_000_000) }
                if let error = self.showError { throw error }
                self.shownNotes.append(id)
            },
            openURL: { self.openedURLs.append($0) },
            fileIsGone: { FloatingPanel.isGone($0) },
            notesFolder: { self.notesFolder },
            reminderAccess: { self.access },
            reminders: { _ in
                self.reminderReads += 1
                if self.access == .notDetermined { self.access = self.answer }  // macOS asked
                guard self.access == .allowed else { throw RemindersBridge.RemindersError.notPermitted }
                return self.reminders
            },
            completeReminder: { id in
                self.completed.append(id)
                self.reminders.removeAll { $0.id == id }
            },
            openReminders: { self.openedReminders += 1 },
            openReminderSettings: { self.openedSettings += 1 },
            listAgents: {
                self.agentLooks += 1
                return self.sessions
            },
            lastReplies: { sessions, known in
                var read: [String: AgentReplyCache.Read] = [:]
                for session in sessions {
                    let id = session.sessionId
                    guard let reply = self.replies[id], known[id]?.reply != reply else { continue }
                    self.transcriptReads += 1
                    read[id] = AgentReplyCache.Read(file: URL(fileURLWithPath: "/stand-in/\(id).jsonl"),
                                                    size: UInt64(reply.utf8.count), modified: self.now, reply: reply)
                }
                return read
            },
            monitorWatching: { self.monitorWatching },
            prompt: { _ in nil },
            openAgent: { self.openedAgents.append($0) },
            defaults: defaults,
            now: { self.now })
        sources.autocompleteOn = { self.autocomplete }
        sources.setAutocomplete = { on in
            self.autocomplete = on
            return on
        }
        sources.autocompleteSummary = { nil }
        sources.autocompleteModel = { self.autocomplete ? tr("本机 Apple Intelligence", "Apple Intelligence on this Mac") : nil }
        sources.commandTrigger = { self.commandTrigger }
        return sources
    }

    /// Neutral sample data (README images are public), as of a fixed time so the images stay the same:
    /// two notes, a reminder that is overdue and one tomorrow, a task in progress and one done.
    func sample(chinese: Bool) {
        let calendar = ReminderParser.localCalendar
        now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 9, minute: 41))!
        reminders = [
            RemindersBridge.Reminder(id: "rent", title: chinese ? "交房租" : "Pay the rent",
                                     due: DateComponents(year: 2026, month: 10, day: 15), hasTime: false, overdue: true),
            RemindersBridge.Reminder(id: "call", title: chinese ? "给张三打电话" : "Call Alex",
                                     due: DateComponents(year: 2026, month: 10, day: 18, hour: 15, minute: 0), hasTime: true,
                                     overdue: false),
        ]
        let ms = now.timeIntervalSince1970 * 1000
        let language = chinese ? "zh" : "en"  // other sessions for the other language (their replies are read anew)
        sessions = [
            AgentSession(id: "a1b2c3d4", sessionId: "a1b2c3d4-\(language)", name: chinese ? "重构登录模块" : "Refactor the login module",
                         state: "working", startedAt: ms - 25 * 60_000),
            AgentSession(id: "e5f6a7b8", sessionId: "e5f6a7b8-\(language)", name: chinese ? "写单元测试" : "Write unit tests",
                         state: "done", startedAt: ms - 2 * 3_600_000),
        ]
        replies = ["a1b2c3d4-\(language)": chinese ? "正在拆分 LoginService，已改完 3 个文件" : "Splitting LoginService: 3 files done so far",
                   "e5f6a7b8-\(language)": chinese ? "写好了 12 个单元测试，全部通过" : "Added 12 unit tests; all of them pass"]
        var notes = SavedNotes()
        notes.add(id: "x-coredata://sample/p2", title: chinese ? "买牛奶和鸡蛋" : "Buy milk and eggs", at: now - 3 * 3600)
        notes.add(id: "x-coredata://sample/p1", title: chinese ? "周会要点" : "Weekly meeting notes", at: now - 10 * 60)
        SavedNotesStore.save(notes, to: defaults)
    }
}

extension SelfTest {
    /// The menu bar panel with stand-ins for every source: what it lists and does on a click, that it
    /// never takes focus, its timers and notices, permissions, the setting (menu, settings window,
    /// close button), that off means off (but for the record of saved notes); with the README render,
    /// Chinese and English.
    static func testFloatingPanel(_ controller: AllInOneIMEInputController, snapshotDirectory: URL) {
        section("menu bar panel (stand-ins for Notes, Reminders and Claude Code)")
        let realConfig = try? Data(contentsOf: Config.userURL)
        let stand = PanelStandIns()
        stand.sample(chinese: true)
        let panel = FloatingPanel(sources: stand.sources)
        panel.prepareWindow = { window in
            // Invisible and click-through (someone may be using this Mac); renders draw the view directly.
            window.alphaValue = 0
            window.ignoresMouseEvents = true
        }
        panel.checksOcclusion = false  // an invisible window never counts as seen
        let language = UIText.choice
        // Where a menu bar icon would be: the panel drops down under it.
        let screen = NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 875)
        let anchor = CGRect(x: screen.maxX - 200, y: screen.maxY, width: 22, height: 24)
        defer {
            panel.closeDropDown()
            panel.stopRecordingSavedNotes()
            UIText.choice = language
        }
        func loaded() -> Bool {
            guard case let .list(items) = panel.reminders, !items.isEmpty, case let .list(rows) = panel.tasks else { return false }
            return rows.allSatisfy { $0.reply != nil }
        }
        func post(_ name: Notification.Name, _ info: [AnyHashable: Any]? = nil) {
            NotificationCenter.default.post(name: name, object: nil, userInfo: info)
        }
        func reminderIDs() -> [String] {
            if case let .list(items) = panel.reminders { return items.map(\.id) }
            return []
        }
        func taskRows() -> [AgentTaskRow] {
            if case let .list(rows) = panel.tasks { return rows }
            return []
        }

        // Closed: no window, nothing runs (but the record of saved notes, as runServer sets it up).
        panel.recordSavedNotes()
        check(!panel.droppedDown && panel.isIdle && Config.default.menuBarIcon,
              "closed: no window, no timers, no observers but the record of saved notes; the menu bar icon is on by default")

        // The icon's click drops it down.
        let wasActive = NSApp.isActive
        panel.toggleDropDown(below: anchor)
        check(panel.droppedDown && panel.window?.isVisible == true, "the menu bar icon's click drops it down")
        check(pump(timeout: 3) { loaded() }, "it reads the stand-ins")
        if let window = panel.window {
            // Key only to type in the tasks' search field (becomesKeyOnlyIfNeeded); never main, and showing it
            // or clicking it never activates the input method: the app being typed in stays in front.
            check(window.styleMask.contains(.nonactivatingPanel) && window.becomesKeyOnlyIfNeeded
                  && !window.canBecomeMain && !window.isKeyWindow && NSApp.isActive == wasActive,
                  "non-activating: not key until its search field is clicked, never main, the app being typed in keeps the focus")
            check(window.level == .floating && window.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary])
                  && !window.hidesOnDeactivate && !window.isMovableByWindowBackground,
                  "on every Space and over full-screen apps; it hangs from the icon (not moved by dragging)")
            _ = pump(timeout: 0.5) { window.frame.height == panel.height && panel.listHeight > 0 }
            check(abs(window.frame.maxX - anchor.maxX) < 1 && abs(window.frame.maxY - (anchor.minY - 4)) < 1
                  && window.frame.width == 300 && window.frame.height == panel.height && panel.height <= 420,
                  "right under the icon, right edges lined up, \(Int(window.frame.width)) × \(Int(window.frame.height)) pt")
        }
        check(panel.notes.map(\.title) == ["周会要点", "买牛奶和鸡蛋"], "notes from the store, newest first: \(panel.notes.map(\.title))")
        if case let .list(items) = panel.reminders, items.count == 2 {
            let due = items.map { panel.due($0) ?? "" }
            check(items.map(\.title) == ["交房租", "给张三打电话"] && due[0].hasPrefix("10月15日") && due[1].hasPrefix("明天")
                  && items[0].overdue, "reminders, due first, the overdue one red: \(zip(items.map(\.title), due).map { "\($0) · \($1)" })")
        } else {
            check(false, "reminders: \(panel.reminders)")
        }
        let rows = taskRows()
        check(rows.map(\.title) == ["重构登录模块", "写单元测试"] && rows.map(\.progress) == [.working, .done]
              && rows.map { $0.reply ?? "" } == ["正在拆分 LoginService，已改完 3 个文件", "写好了 12 个单元测试，全部通过"],
              "Claude tasks, newest first, with their last replies")
        check(panel.counts == "2 个提醒 · 1 个任务进行中", "header: \(panel.counts)")

        // README: the expanded panel, light, Chinese and English (the same sample in English).
        func render(_ name: String) {
            guard let window = panel.window, let view = window.contentView else { return check(false, "no window to render") }
            window.appearance = NSAppearance(named: .aqua)
            FloatingPanelView.glass = false  // nothing behind an offscreen rendering to blur
            panel.objectWillChange.send()
            defer {
                window.appearance = nil
                FloatingPanelView.glass = true
                panel.objectWillChange.send()
            }
            _ = pump(timeout: 0.5) { false }
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = snapshotDirectory.appendingPathComponent("\(name).png")
            if let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil {
                print("  snapshot \(url.path) (\(Int(view.bounds.width))×\(Int(view.bounds.height)))")
            }
        }
        render("14-dashboard")
        UIText.choice = "en"
        stand.sample(chinese: false)
        panel.refresh()
        check(pump(timeout: 3) { loaded() && taskRows().first?.title == "Refactor the login module" && panel.notes.first?.title == "Weekly meeting notes" }
              && panel.language == "en", "the English interface, at once")
        check(panel.counts == "2 reminders · 1 task running" && FloatingPanel.completeLabel("Pay the rent") == "Complete \u{201C}Pay the rent\u{201D}",
              "English header and VoiceOver labels: \(panel.counts)")
        render("14-dashboard-en")
        UIText.choice = "zh"
        stand.sample(chinese: true)
        panel.refresh()
        _ = pump(timeout: 3) { loaded() && taskRows().first?.title == "重构登录模块" && panel.notes.first?.title == "周会要点" }
        check(panel.language == "zh-Hans" && FloatingPanel.completeLabel("交房租") == "完成「交房租」", "back to Chinese; the checkbox says 「完成「交房租」」")

        // Clicks: a checkbox completes the reminder (the stand-in), a row opens what it shows.
        if case let .list(items) = panel.reminders, let rent = items.first {
            panel.complete(rent)
            check(panel.completing.contains(rent.id), "the box is checked at once")
            check(pump(timeout: 2) { reminderIDs() == ["call"] } && stand.completed == ["rent"] && panel.completing.isEmpty,
                  "the checkbox completes it, then it's gone from the list (\(reminderIDs()))")
        }
        if let note = panel.notes.first { panel.open(note) }
        panel.openReminders()
        if let row = taskRows().first { panel.open(row) }
        check(pump(timeout: 1) { !stand.shownNotes.isEmpty } && stand.shownNotes == ["x-coredata://sample/p1"]
              && stand.openedReminders == 1 && stand.openedAgents == ["a1b2c3d4"],
              "a note opens in Notes, a reminder's title opens Reminders, a task opens in Terminal")

        // What it hears: @note, @reminder, EventKit's changes, AgentMonitor's looks.
        post(.allInOneIMENoteSaved, ["id": "x-coredata://sample/p3", "title": String(repeating: "长", count: 100)])
        _ = pump(timeout: 0.3) { false }
        check(panel.notes.first?.id == "x-coredata://sample/p3" && panel.notes.first?.title.count == 80
              && SavedNotesStore.load(stand.defaults).notes.count == 3, "a note saved with @note goes first, its title cut to 80")
        var reads = stand.reminderReads
        stand.reminders.append(RemindersBridge.Reminder(id: "milk", title: "买牛奶", due: nil, hasTime: false, overdue: false))
        post(.allInOneIMEReminderAdded, ["id": "milk"])
        check(pump(timeout: 2) { reminderIDs() == ["call", "milk"] } && stand.reminderReads == reads + 1,
              "@reminder's notice reads them again")
        reads = stand.reminderReads
        for _ in 0..<3 { post(.EKEventStoreChanged) }
        _ = pump(timeout: 1.2) { false }
        check(stand.reminderReads == reads + 1, "EventKit's changes (a burst of 3) read them once (\(stand.reminderReads - reads))")
        var looks = stand.agentLooks
        var polled = stand.sessions ?? []
        polled[0].state = "done"
        post(.allInOneIMEAgentsPolled, ["sessions": polled])
        check(pump(timeout: 2) { taskRows().allSatisfy { $0.progress == .done } } && stand.agentLooks == looks
              && panel.counts == "2 个提醒", "AgentMonitor's look shows up without asking Claude Code again (\(panel.counts))")

        // Its own looks: every 15 s (0.3 s here) while expanded, a task isn't done and AgentMonitor isn't
        // looking; a transcript is read again only when it changed.
        panel.closeDropDown()
        (panel.agentInterval, panel.reminderInterval) = (0.3, 0.3)
        panel.toggleDropDown(below: anchor)
        check(pump(timeout: 3) { loaded() }, "dropped down again")
        var transcripts = stand.transcriptReads
        looks = stand.agentLooks
        _ = pump(timeout: 1.1) { false }
        check(stand.agentLooks >= looks + 2 && stand.transcriptReads == transcripts,
              "expanded, a task running: it asks Claude Code itself (\(stand.agentLooks - looks) looks in 1.1 s), "
              + "and doesn't read the transcripts again while they don't change")
        transcripts = stand.transcriptReads
        stand.replies["a1b2c3d4-zh"] = "已改完 5 个文件"
        check(pump(timeout: 2) { taskRows().first?.reply == "已改完 5 个文件" } && stand.transcriptReads == transcripts + 1,
              "…the one that changed is read again (\(stand.transcriptReads - transcripts))")
        var sessions = stand.sessions ?? []
        sessions[0].state = "done"
        stand.sessions = sessions
        panel.refresh()
        _ = pump(timeout: 1) { taskRows().allSatisfy { $0.progress == .done } }
        looks = stand.agentLooks
        _ = pump(timeout: 1.1) { false }
        check(taskRows().allSatisfy { $0.progress == .done } && stand.agentLooks == looks,
              "every task done: it doesn't ask Claude Code by itself (\(stand.agentLooks - looks) looks in 1.1 s)")
        sessions[0].state = "working"
        stand.sessions = sessions
        post(.allInOneIMEAgentStarted, ["id": "a1b2c3d4"])
        check(pump(timeout: 1) { stand.agentLooks > looks && taskRows().first?.progress == .working },
              "@agent starts a task: it looks at once")
        looks = stand.agentLooks
        _ = pump(timeout: 1.1) { false }
        check(stand.agentLooks >= looks + 2, "…and by itself again while that runs (\(stand.agentLooks - looks) looks in 1.1 s)")
        stand.monitorWatching = true
        _ = pump(timeout: 0.05) { false }  // a look asked for just before goes through
        looks = stand.agentLooks
        _ = pump(timeout: 1.1) { false }
        check(stand.agentLooks == looks, "…not while AgentMonitor looks anyway")
        stand.monitorWatching = false
        // Waiting for you isn't running: counted apart.
        sessions[0].state = "waiting_for_permission"
        post(.allInOneIMEAgentsPolled, ["sessions": sessions])
        check(pump(timeout: 1) { panel.counts == "2 个提醒 · 1 个等你" }, "a task waiting for you is counted apart: \(panel.counts)")
        sessions[0].state = "working"
        post(.allInOneIMEAgentsPolled, ["sessions": sessions])
        _ = pump(timeout: 0.3) { panel.counts == "2 个提醒 · 1 个任务进行中" }

        // Notes is asked only while it runs, and then updates titles and drops deleted notes.
        var lists = stand.noteLists
        panel.refresh()
        _ = pump(timeout: 0.3) { false }
        check(stand.noteLists == lists, "Notes isn't asked while it isn't running")
        stand.notesRunning = true
        let listed = [NotesBridge.Note(id: "x-coredata://sample/p1", title: "周会要点（改）", modified: stand.now),
                      NotesBridge.Note(id: "x-coredata://sample/p3", title: "长", modified: stand.now)]
        stand.listedNotes = .folder(listed)
        lists = stand.noteLists
        panel.refresh()
        check(pump(timeout: 2) { panel.notes.count == 2 } && stand.noteLists > lists
              && panel.notes.map(\.title) == ["长", "周会要点（改）"], "Notes running: titles follow it, a deleted note goes (\(panel.notes.map(\.title)))")
        // No AllInOneIME folder in Notes' default account (the user switched it): that says nothing of the
        // notes saved.
        stand.listedNotes = NotesListing(recent: nil)
        lists = stand.noteLists
        panel.refresh()
        _ = pump(timeout: 0.3) { false }
        check(stand.listedNotes == .noFolder && stand.noteLists > lists && panel.notes.count == 2
              && SavedNotesStore.load(stand.defaults).notes.count == 2,
              "no AllInOneIME folder in Notes' default account: no note is dropped")
        stand.listedNotes = .notAllowed  // would need asking
        panel.refresh()
        _ = pump(timeout: 0.3) { false }
        check(panel.notes.count == 2, "without Notes' permission given before it changes nothing")
        // Closed while Notes opens a note: what comes back then is dropped (no message, no timer, Notes
        // isn't asked while it's closed); dropped down again, Notes is asked at once and nothing is left waiting.
        stand.listedNotes = .folder(listed)
        stand.showError = NotesBridge.NotesError.failed(number: -1728)
        (stand.holdShow, stand.holdList) = (true, true)
        if let note = panel.notes.first { panel.open(note) }
        _ = pump(timeout: 0.2) { false }
        panel.closeDropDown()
        _ = pump(timeout: 0.05) { false }  // a listing asked for just before goes out (and waits)
        lists = stand.noteLists
        stand.holdShow = false
        _ = pump(timeout: 0.3) { false }
        check(panel.isIdle && panel.message == nil && stand.noteLists == lists,
              "closed while Notes opens a note: no message, no timer, Notes isn't asked (\(stand.noteLists - lists))")
        panel.toggleDropDown(below: anchor)
        check(pump(timeout: 1) { stand.noteLists > lists }, "dropped down again: Notes is asked for the titles at once")
        stand.holdList = false
        _ = pump(timeout: 0.3) { false }
        lists = stand.noteLists
        panel.refresh()
        check(pump(timeout: 1) { stand.noteLists > lists } && panel.notes.count == 2, "…and again at the next refresh")
        stand.showError = nil
        stand.notesRunning = false

        // Permissions: it never asks on its own; a button has macOS ask; denied, a button opens the settings.
        stand.access = .notDetermined
        reads = stand.reminderReads
        panel.refresh()
        check(pump(timeout: 2) { panel.reminders == .notDetermined } && stand.reminderReads == reads,
              "not decided yet: 「允许读取提醒事项」, nothing read")
        render("14d-dashboard-ask")  // not in the README
        panel.requestReminderAccess()
        check(pump(timeout: 2) { !reminderIDs().isEmpty } && stand.access == .allowed, "the button asks, then they are listed")
        // Denied, and no claude command: a line with a button; the tasks' section says Claude Code isn't there.
        stand.access = .denied
        stand.sessions = nil
        panel.refresh()
        check(pump(timeout: 2) { panel.reminders == .denied && panel.tasks == .notInstalled },
              "denied: a line and a button; Claude Code not installed: the section says so")
        render("14e-dashboard-denied")  // not in the README
        panel.openReminderSettings()
        check(stand.openedSettings == 1 && ReminderAccess.settingsURL.absoluteString.hasSuffix("Privacy_Reminders"),
              "the button opens System Settings → Privacy & Security → Reminders")
        stand.access = .allowed

        // The folder there but empty (its notes deleted in Notes): the saved notes it no longer has go.
        stand.notesRunning = true
        stand.listedNotes = NotesListing(recent: [])
        lists = stand.noteLists
        panel.refresh()
        check(pump(timeout: 2) { panel.notes.isEmpty } && stand.listedNotes == .folder([]) && stand.noteLists > lists
              && SavedNotesStore.load(stand.defaults).notes.isEmpty,
              "the folder there but empty: the saved notes it no longer has are dropped")
        stand.notesRunning = false

        // Swiped away (the 「移除」 button): no longer listed, and not again after a refresh; left as it is in
        // Reminders and Claude Code.
        stand.sample(chinese: true)
        panel.refresh()
        post(.allInOneIMENoteSaved, ["id": "x-coredata://sample/p5", "title": "要移除的"])
        _ = pump(timeout: 3) { !reminderIDs().isEmpty && !taskRows().isEmpty }
        let firstReminder = reminderIDs().first
        let firstTask = taskRows().first?.id
        panel.dismiss(.note("x-coredata://sample/p5"))
        if let firstReminder { panel.dismiss(.reminder(firstReminder)) }
        if let firstTask { panel.dismiss(.task(firstTask)) }
        panel.refresh()
        _ = pump(timeout: 1) { false }
        check(firstReminder != nil && firstTask != nil && !panel.notes.contains { $0.id == "x-coredata://sample/p5" }
              && !reminderIDs().contains(firstReminder ?? "") && !taskRows().contains { $0.id == firstTask }
              && stand.reminders.contains { $0.id == firstReminder }
              && panel.swipedRow == nil,
              "a row swiped away stays away after a refresh, and is left as it is in Reminders and Claude Code")
        stand.defaults.removeValue(forKey: FloatingPanel.dismissedRemindersKey)
        stand.defaults.removeValue(forKey: FloatingPanel.dismissedTasksKey)

        // Nothing at all: the empty states, their commands named with the settings' trigger (~ here).
        stand.sessions = []
        stand.reminders = []
        stand.defaults.removeValue(forKey: SavedNotesStore.key)
        stand.commandTrigger = "~"
        panel.refresh()
        check(pump(timeout: 2) { panel.tasks == .list([]) && panel.reminders == .list([]) } && panel.notes.isEmpty
              && panel.counts.isEmpty, "nothing yet: the three empty lines, no counts")
        let empty = [FloatingPanel.EmptyList.notes, .reminders, .tasks].map { FloatingPanel.emptyLine($0, trigger: panel.commandTrigger) }
        check(panel.commandTrigger == "~" && empty == ["用 ~note 存的笔记会显示在这里", "用 ~reminder 加的提醒会显示在这里",
                                                       "用 ~agent 交给 Claude Code 后台的任务会显示在这里"],
              "the empty lines name the commands with the settings' trigger: \(empty)")
        render("14c-dashboard-empty")  // not in the README
        stand.commandTrigger = "@"

        // Displays changed (one unplugged, the resolution): closed, like a menu.
        post(NSApplication.didChangeScreenParametersNotification)
        check(pump(timeout: 1) { !panel.droppedDown && panel.isIdle }, "closed when the displays change")

        // The settings window's switch saves the menu bar icon's setting and applies it at once (a temporary config file).
        let dir = snapshotDirectory.appendingPathComponent("panel-config")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try? settings.write(to: url)
        var applied: [Bool] = []
        let model = SettingsModel(configURL: url)
        model.applyMenuBarIcon = { applied.append($0) }
        model.setMenuBarIcon(false)
        check(applied == [false] && (try? Config.load(from: url))?.menuBarIcon == false, "the settings switch removes the icon and saves it")
        model.setMenuBarIcon(true)
        let preview = SettingsModel(configURL: url, persists: false)
        preview.applyMenuBarIcon = { applied.append($0) }
        preview.setMenuBarIcon(false)
        check(applied == [false, true] && (try? Config.load(from: url))?.menuBarIcon == true, "…and shows it again; a preview does neither")

        // Fuzzy pinyin: saved in the catalog's order and applied (Rime deployed again); the user's own Rime file reported.
        var fuzzyApplied: [[String]] = []
        model.applyFuzzyPinyin = { ids in
            fuzzyApplied.append(ids)
            return ids.contains("n-l") ? .userFile : .written
        }
        model.setFuzzyPinyin(SettingsModel.fuzzyDefaults)
        check(fuzzyApplied == [SettingsModel.fuzzyDefaults] && !model.fuzzyBlocked
              && (try? Config.load(from: url))?.fuzzyPinyin == SettingsModel.fuzzyDefaults, "turning fuzzy pinyin on saves and applies the usual pairs")
        model.setFuzzy("n-l", on: true)
        check(model.config.fuzzyPinyin == ["z-zh", "c-ch", "s-sh", "n-l", "en-eng", "in-ing"] && model.fuzzyBlocked,
              "a pair added in the catalog's order; the user's own rime_ice.custom.yaml is reported")
        model.setFuzzyPinyin([])
        check(fuzzyApplied.last == [] && (try? Config.load(from: url))?.fuzzyPinyin == [], "…and off again")

        // Closed: a note saved with @note is recorded all the same; nothing else runs.
        let (kept, readsBefore) = (SavedNotesStore.load(stand.defaults).notes.count, stand.reminderReads)
        post(.allInOneIMENoteSaved, ["id": "x-coredata://sample/p4", "title": "x"])
        post(.allInOneIMEReminderAdded, ["id": "x"])
        _ = pump(timeout: 0.7) { false }
        let recorded = SavedNotesStore.load(stand.defaults).notes
        check(recorded.count == kept + 1 && recorded.first?.id == "x-coredata://sample/p4" && panel.isIdle
              && panel.notes.isEmpty && stand.reminderReads == readsBefore,
              "closed: a note saved with @note is recorded all the same (nothing else runs); @reminder goes unheard, nothing is read")
        panel.toggleDropDown(below: anchor)
        check(panel.notes.first?.id == "x-coredata://sample/p4", "dropped down, it lists the note saved while it was closed")
        panel.toggleDropDown(below: anchor)
        check(!panel.droppedDown && panel.isIdle, "the icon's second click closes it")
        check((try? Data(contentsOf: Config.userURL)) == realConfig, "the real config file was not touched")
    }
}

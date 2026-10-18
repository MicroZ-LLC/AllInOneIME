import Foundation
import Testing
@testable import AllInOneIMECore

/// The floating panel's logic: the notes @note saved, its wording, where it goes on the screens, and
/// the background tasks it lists.
struct DashboardTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func savedNotesNewestFirstCutAndCapped() throws {
        var saved = SavedNotes()
        saved.add(id: "a", title: "周会要点\n第二行", at: t0)
        saved.add(id: "b", title: "  \n  买牛奶和鸡蛋  ", at: t0 + 60)
        #expect(saved.notes.map(\.id) == ["b", "a"] && saved.notes.map(\.title) == ["买牛奶和鸡蛋", "周会要点"])
        // Saved again (the same id): moves up, with the new title.
        saved.add(id: "a", title: "周会要点（改）", at: t0 + 120)
        #expect(saved.notes.map(\.id) == ["a", "b"] && saved.notes.first?.title == "周会要点（改）")
        // Titles are cut to 80 characters (characters, not UTF-16 units).
        saved.add(id: "long", title: String(repeating: "长", count: 100) + "\nmore", at: t0 + 180)
        #expect(saved.notes.first?.title == String(repeating: "长", count: 80))
        // At most 30, the oldest forgotten; the panel shows the newest 5.
        for i in 0..<40 { saved.add(id: "n\(i)", title: "note \(i)", at: t0 + Double(1000 + i)) }
        #expect(saved.notes.count == SavedNotes.limit && saved.notes.first?.id == "n39" && saved.notes.last?.id == "n10")
        #expect(saved.newest(5).map(\.id) == ["n39", "n38", "n37", "n36", "n35"] && saved.newest(-1).isEmpty)
        // Kept as JSON; a longer list than the limit (written by hand) is cut when read.
        let decoded = try JSONDecoder().decode(SavedNotes.self, from: JSONEncoder().encode(saved))
        #expect(decoded == saved)
        let many = try JSONEncoder().encode(["notes": Array(repeating: SavedNotes.Note(id: "x", title: "x", saved: t0), count: 40)])
        #expect(try JSONDecoder().decode(SavedNotes.self, from: many).notes.count == SavedNotes.limit)
        #expect(SavedNotes(Array(repeating: SavedNotes.Note(id: "x", title: "x", saved: t0), count: 40)).notes.count == 30)
        // The title as Notes names the note (NotesFormat's), nothing for a blank text.
        #expect(SavedNotes.Note(id: "x", title: "\n \n", saved: t0).title == "" && NotesFormat.title(of: "\n \n").isEmpty)
    }

    @Test func rowsSwipedAway() throws {
        var saved = SavedNotes()
        saved.add(id: "a", title: "一", at: t0)
        saved.add(id: "b", title: "二", at: t0 + 60)
        saved.remove(id: "a")
        saved.remove(id: "missing")
        #expect(saved.notes.map(\.id) == ["b"])

        var dismissed = DismissedRows()
        dismissed.dismiss("r1")
        dismissed.dismiss("r2")
        dismissed.dismiss("r1")  // again: once, the newest
        #expect(dismissed.ids == ["r2", "r1"] && dismissed.contains("r1") && !dismissed.contains("r3"))
        for i in 0..<250 { dismissed.dismiss("x\(i)") }
        #expect(dismissed.ids.count == DismissedRows.limit && dismissed.ids.last == "x249" && !dismissed.contains("r1"))
        #expect(try JSONDecoder().decode(DismissedRows.self, from: JSONEncoder().encode(dismissed)) == dismissed)

        // Let go: a short swipe closes, past half the button it stays open, far enough it's removed.
        #expect(RowSwipe.rest(offset: -10) == .closed)
        #expect(RowSwipe.rest(offset: -40) == .open)
        #expect(RowSwipe.rest(offset: -10, velocity: -800) == .open)
        #expect(RowSwipe.rest(offset: -60, velocity: 800) == .closed)
        #expect(RowSwipe.rest(offset: -180, velocity: 800) == .dismissed)
        #expect(RowSwipe.clamp(20) == 0 && RowSwipe.clamp(-50) == -50 && RowSwipe.clamp(-200) == -180)
    }

    @Test func notesListedByNotesUpdateAndDrop() {
        func saved() -> SavedNotes {
            var notes = SavedNotes()
            notes.add(id: "old", title: "旧笔记", at: t0)
            notes.add(id: "mid", title: "中间", at: t0 + 3600)
            notes.add(id: "new", title: "新笔记", at: t0 + 7200)
            return notes
        }
        // The whole folder (fewer than asked for): titles follow edits, a missing note is gone; a note
        // whose first line is a picture (no name) keeps the title it had.
        var notes = saved()
        let changed = notes.reconcile(with: [("new", "新笔记（改过）", t0 + 9000), ("old", "", t0 + 10)], limit: 200)
        #expect(changed && notes.notes.map(\.id) == ["new", "old"] && notes.notes.map(\.title) == ["新笔记（改过）", "旧笔记"])
        let again = notes.reconcile(with: [("new", "新笔记（改过）", t0 + 9000), ("old", "", t0 + 10)], limit: 200)
        #expect(!again)
        // A full list (as many as asked for): only notes saved after the oldest listed change can be
        // told to be gone (a minute's margin); older ones may just be further down the folder.
        notes = saved()
        notes.reconcile(with: [("x", "x", t0 + 5000), ("y", "y", t0 + 1800)], limit: 2)
        #expect(notes.notes.map(\.id) == ["old"])
        notes = saved()
        notes.reconcile(with: [("x", "x", t0 + 3590), ("y", "y", t0 + 3595)], limit: 2)
        #expect(notes.notes.map(\.id) == ["mid", "old"])  // "mid" was saved within the minute: kept
        // No such folder (Notes' default account switched, the folder renamed): that says nothing of
        // the notes saved, and none is dropped.
        notes = saved()
        let unchanged = notes.reconcile(with: nil, limit: 200)
        #expect(!unchanged && notes == saved())
        // The folder there but empty: everything is gone.
        notes = saved()
        let emptied = notes.reconcile(with: [], limit: 200)
        #expect(emptied && notes.notes.isEmpty)
    }

    @Test func droppedDownUnderTheMenuBarIcon() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)  // below a 25 pt menu bar
        let size = CGSize(width: 300, height: 400)
        // Under the icon, right edges lined up.
        let icon = CGRect(x: 1200, y: 875, width: 24, height: 25)
        #expect(PanelPlacement.below(icon, size: size, visible: [screen]) == CGRect(x: 924, y: 471, width: 300, height: 400))
        // An icon near the left edge: moved right to stay on the screen.
        let left = CGRect(x: 100, y: 875, width: 24, height: 25)
        #expect(PanelPlacement.below(left, size: size, visible: [screen]).minX == 0)
    }

    @Test func tasksAreSearched() {
        func row(_ title: String, _ reply: String?) -> AgentTaskRow {
            AgentTaskRow(id: title, title: title, progress: .done, started: nil, reply: reply)
        }
        let rows = [row("重构登录模块", "改完 3 个文件"), row("Write unit tests", "12 tests pass"), row("fix bug", nil)]
        #expect(AgentTaskList.matching(rows, "").count == 3)
        #expect(AgentTaskList.matching(rows, "登录").map(\.title) == ["重构登录模块"])
        #expect(AgentTaskList.matching(rows, "TESTS pass").map(\.title) == ["Write unit tests"])  // any case, every word
        #expect(AgentTaskList.matching(rows, "文件").map(\.title) == ["重构登录模块"])  // the reply counts
        #expect(AgentTaskList.matching(rows, "nothing").isEmpty)
        #expect(AgentTaskList.limit == 30 && AgentTaskList.shown == 5)
    }

    @Test func howLongAgo() {
        let cases: [(TimeInterval, String, String)] = [
            (-30, "刚刚", "just now"), (59, "刚刚", "just now"), (60, "1 分钟前", "1 min ago"),
            (25 * 60, "25 分钟前", "25 min ago"), (3599, "59 分钟前", "59 min ago"), (3600, "1 小时前", "1 hr ago"),
            (2 * 3600 + 59 * 60, "2 小时前", "2 hr ago"), (86_399, "23 小时前", "23 hr ago"),
            (86_400, "1 天前", "1 day ago"), (3 * 86_400 + 5, "3 天前", "3 days ago"),
        ]
        for (seconds, chinese, english) in cases {
            #expect(DashboardText.ago(t0, now: t0 + seconds, chinese: true) == chinese)
            #expect(DashboardText.ago(t0, now: t0 + seconds, chinese: false) == english)
        }
    }

    @Test func headerCounts() {
        #expect(DashboardText.counts(reminders: 3, running: 1, chinese: true) == "3 个提醒 · 1 个任务进行中")
        #expect(DashboardText.counts(reminders: 3, running: 1, chinese: false) == "3 reminders · 1 task running")
        #expect(DashboardText.counts(reminders: 1, running: 2, chinese: false) == "1 reminder · 2 tasks running")
        #expect(DashboardText.counts(reminders: 0, running: 2, chinese: true) == "2 个任务进行中")
        #expect(DashboardText.counts(reminders: 5, running: 0, chinese: true) == "5 个提醒")
        #expect(DashboardText.counts(reminders: 0, running: 0, chinese: true).isEmpty)
        #expect(DashboardText.counts(reminders: 100, moreReminders: true, running: 0, chinese: true) == "100+ 个提醒")
        #expect(DashboardText.counts(reminders: 1, moreReminders: true, running: 0, chinese: false) == "1+ reminders")
        // Tasks waiting for you aren't running: counted apart.
        #expect(DashboardText.counts(reminders: 3, running: 1, waiting: 1, chinese: true) == "3 个提醒 · 1 个任务进行中 · 1 个等你")
        #expect(DashboardText.counts(reminders: 1, running: 2, waiting: 1, chinese: false)
                == "1 reminder · 2 tasks running · 1 waiting for you")
        #expect(DashboardText.counts(reminders: 0, running: 0, waiting: 2, chinese: true) == "2 个等你")
        #expect(DashboardText.counts(reminders: 0, running: 0, waiting: 2, chinese: false) == "2 waiting for you")
    }

    @Test func aReplysFirstLine() {
        #expect(DashboardText.firstLine("## 完成了\n\n细节……") == "完成了")
        #expect(DashboardText.firstLine("\n\n- **Fixed** the `parse()` bug\n- more") == "Fixed the parse() bug")
        #expect(DashboardText.firstLine("> quoted\nnext") == "quoted")
        #expect(DashboardText.firstLine("1. First step\n2. Second") == "First step")
        #expect(DashboardText.firstLine("3.5 hours left") == "3.5 hours left")
        #expect(DashboardText.firstLine("#hashtag stays") == "#hashtag stays")
        #expect(DashboardText.firstLine("  \n ### \n ok") == "ok")
        #expect(DashboardText.firstLine("   ") == nil && DashboardText.firstLine(nil) == nil)
    }

    @Test func placementOnTheScreens() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 875)  // below a 25 pt menu bar
        let size = CGSize(width: 300, height: 420)
        let first = PanelPlacement.topRight(size, in: main)
        #expect(first == CGRect(x: 1128, y: 443, width: 300, height: 420))
        // On a screen: stays.
        #expect(PanelPlacement.onScreen(first, visible: [main]) == first)
        let side = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        let there = CGRect(x: 2000, y: 300, width: 300, height: 420)
        #expect(PanelPlacement.onScreen(there, visible: [main, side]) == there)
        // That screen gone: to the top right of the first one.
        #expect(PanelPlacement.onScreen(there, visible: [main]) == first)
        // Partly off a screen: moved in, onto the screen it overlaps most.
        #expect(PanelPlacement.onScreen(CGRect(x: 1300, y: 700, width: 300, height: 420), visible: [main])
                == CGRect(x: 1140, y: 455, width: 300, height: 420))
        #expect(PanelPlacement.onScreen(CGRect(x: 1400, y: 100, width: 300, height: 420), visible: [main, side])
                == CGRect(x: 1440, y: 100, width: 300, height: 420))
        // Taller than the screen: its top (the header) stays on it.
        let small = CGRect(x: 0, y: 0, width: 800, height: 300)
        #expect(PanelPlacement.onScreen(CGRect(x: 100, y: 50, width: 300, height: 420), visible: [small])
                == CGRect(x: 100, y: -120, width: 300, height: 420))
        #expect(PanelPlacement.onScreen(there, visible: []) == there)
    }

    @Test func theTasksListed() {
        func session(_ id: String, _ state: String?, started: Double?, name: String? = nil) -> AgentSession {
            AgentSession(id: id, sessionId: id + "-session", name: name, state: state, startedAt: started)
        }
        let ms = t0.timeIntervalSince1970 * 1000
        #expect(AgentTaskList.started(session("a", nil, started: ms)) == t0)
        #expect(AgentTaskList.started(session("a", nil, started: t0.timeIntervalSince1970)) == t0)  // seconds
        #expect(AgentTaskList.started(session("a", nil, started: nil)) == nil)
        // Newest first (up to `limit`); the name, else the prompt @agent started it with, else the id.
        var sessions = (0..<8).map { session("t\($0)", "done", started: ms + Double($0) * 1000, name: "task \($0)") }
        sessions.append(session("nameless", "working", started: ms + 60_000))
        sessions.append(session("blank", "waiting_for_input", started: ms + 50_000, name: "  "))
        let rows = AgentTaskList.rows(sessions, replies: ["t7-session": "Done: 3 files"],
                                      prompt: { $0 == "nameless" ? "fix the\nlogin  bug" : nil })
        #expect(rows.count == 10)
        #expect(rows.map(\.id) == ["nameless", "blank", "t7", "t6", "t5", "t4", "t3", "t2", "t1", "t0"])
        #expect(rows.prefix(6).map(\.title) == ["fix the login bug", "blank", "task 7", "task 6", "task 5", "task 4"])
        #expect(rows.prefix(3).map(\.progress) == [.working, .needsYou, .done])
        #expect(AgentTaskList.newest(sessions, limit: 3).count == 3)
        #expect(rows[2].reply == "Done: 3 files" && rows[0].reply == nil && rows[2].started == t0 + 7)
    }

    /// A transcript line with an assistant reply.
    private func replyLine(_ text: String) -> String {
        #"{"type":"assistant","message":{"content":[{"type":"text","text":"\#(text)"}]}}"#
    }

    /// A transcript line with tool output, about `size` bytes long.
    private func toolLine(_ size: Int = 1000) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"\#(String(repeating: "x", count: size))"}]}}"#
    }

    @Test func repliesAreReadAgainOnlyWhenTheTranscriptChanges() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("projects-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("-Users-me")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let (fileA, fileB) = (folder.appendingPathComponent("a-1.jsonl"), folder.appendingPathComponent("b-1.jsonl"))
        let user = #"{"type":"user","message":{"role":"user","content":"Fix the bug"}}"#
        try [user, replyLine("## Looking into it")].joined(separator: "\n").write(to: fileA, atomically: true, encoding: .utf8)
        try [user, replyLine("May I run `make`?")].joined(separator: "\n").write(to: fileB, atomically: true, encoding: .utf8)
        let running = AgentSession(id: "a", sessionId: "a-1", state: "working", cwd: "/Users/me")
        let waiting = AgentSession(id: "b", sessionId: "b-1", state: "waiting_for_permission", cwd: "/Users/me")
        var cache = AgentReplyCache()
        // Not read yet: both are read, the first line of the reply without its Markdown.
        var read = AgentReplyCache.readChanged([running, waiting], known: cache.known, root: root)
        let sizeA = UInt64(try fileA.size())
        #expect(Set(read.keys) == ["a-1", "b-1"] && read["a-1"]?.file == fileA && read["a-1"]?.size == sizeA)
        cache.store(read)
        #expect(cache.replies == ["a-1": "Looking into it", "b-1": "May I run make?"])
        // Unchanged (a task waiting for you writes nothing): neither is read again, running or not.
        #expect(AgentReplyCache.readChanged([running, waiting], known: cache.known, root: root).isEmpty)
        // One grew: only that one is read again.
        try [user, replyLine("Looking into it"), replyLine("Fixed it.")].joined(separator: "\n")
            .write(to: fileA, atomically: true, encoding: .utf8)
        read = AgentReplyCache.readChanged([running, waiting], known: cache.known, root: root)
        #expect(Array(read.keys) == ["a-1"] && read["a-1"]?.reply == "Fixed it.")
        cache.store(read)
        #expect(cache.replies == ["a-1": "Fixed it.", "b-1": "May I run make?"])
        // A session without a transcript yet is left out (looked for again next time).
        let new = AgentSession(id: "c", sessionId: "c-1", state: "working", cwd: "/Users/me")
        #expect(AgentReplyCache.readChanged([new], known: cache.known, root: root).isEmpty)
        // Sessions no longer shown are forgotten.
        cache.keep(only: [waiting])
        #expect(cache.replies == ["b-1": "May I run make?"] && cache.known.keys.sorted() == ["b-1"])
    }

    @Test func onlyTheEndOfALongTranscriptIsRead() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("projects-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("-Users-me")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("a-1.jsonl")
        let session = AgentSession(id: "a", sessionId: "a-1", state: "working", cwd: "/Users/me")
        // Longer than the tail read: the last reply, near the end, is found.
        var lines = [replyLine("An early reply")] + Array(repeating: toolLine(), count: 400) + [replyLine("The last reply"), toolLine()]
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        #expect(try file.size() > AgentReplyCache.tailBytes)
        let read = AgentReplyCache.readChanged([session], known: [:], root: root)
        #expect(read["a-1"]?.reply == "The last reply")
        // Only tool output in the tail now: what's further back isn't read, and the reply read before stays.
        lines += Array(repeating: toolLine(), count: 300)
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        let again = AgentReplyCache.readChanged([session], known: read, root: root)
        let size = UInt64(try file.size())
        #expect(again["a-1"]?.reply == "The last reply" && again["a-1"]?.size == size)
        let fresh = AgentReplyCache.readChanged([session], known: [:], root: root)
        #expect(fresh["a-1"] != nil && fresh["a-1"]?.reply == nil)
        // The line the tail cuts into is left out; one that's whole is read.
        let short = folder.appendingPathComponent("short.jsonl")
        try [replyLine("first"), replyLine("second")].joined(separator: "\n").write(to: short, atomically: true, encoding: .utf8)
        #expect(AgentReplyCache.lastReply(tailOf: short, bytes: replyLine("second").utf8.count + 5) == "second")
        #expect(AgentReplyCache.lastReply(tailOf: short, bytes: replyLine("second").utf8.count - 5) == nil)
        #expect(AgentReplyCache.lastReply(tailOf: short, bytes: 1 << 20) == "second")
        #expect(AgentReplyCache.lastReply(tailOf: folder.appendingPathComponent("none.jsonl"), bytes: 100) == nil)
    }
}

private extension URL {
    func size() throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? 0
    }
}

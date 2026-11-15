import Foundation
import Testing
@testable import AllInOneIMECore

/// The iCloud sync's merge of the recent questions (`ICloudSyncEngine.syncQuestions`, on its own queue) and `@question`
/// recording one (`QuestionHistoryStore.record`, on the main thread) both rewrite the same file: neither may write over
/// what the other wrote, so a question asked while the sync merges is never lost.
@Suite(.serialized)
struct ICloudSyncQuestionsRaceTests {
    final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    /// A question recorded as `@question` records it (the shell's `QuestionHistoryStore.record`): handed to the file's
    /// queue, not waited for.
    static func record(_ entry: QuestionHistory.Entry, at url: URL) {
        QuestionHistory.updateLater(at: url) { $0.record(entry) }
    }

    @Test func aQuestionAskedWhileTheSyncMergesIsKept() throws {
        let rig = try SyncRig()
        let mac = try rig.mac("A") { $0.iCloudSync = ICloudSyncSettings(enabled: true, recentQuestions: true) }
        let url = mac.engine.questionsURL
        let cloud = rig.folder.url.appendingPathComponent(ICloudSync.questionsFile)
        try FileManager.default.createDirectory(at: rig.folder.url, withIntermediateDirectories: true)
        let t0 = SyncRig.t0
        var lost: [String] = []
        for round in 0..<40 {
            try? FileManager.default.removeItem(at: url)
            let engine = Box(mac.engine)
            let stop = Box(false)
            let done = DispatchSemaphore(value: 0)
            // The sync, merging again and again: each time another Mac's older question in iCloud, so it writes.
            DispatchQueue.global().async {
                var state = ICloudSync.State()
                var turn = 0
                while !stop.value {
                    turn += 1
                    let theirs = QuestionHistory(entries: [.init(question: "theirs \(round) \(turn)", answer: "a",
                                                                 date: t0.addingTimeInterval(Double(turn)))])
                    try? ICloudSyncEngine.encodedQuestions(theirs, cleared: nil).write(to: cloud, options: .atomic)
                    var report = ICloudSyncEngine.Report(outcome: .synced)
                    _ = engine.value.syncQuestions(remote: true, entry: nil, state: &state, now: t0.addingTimeInterval(86_400),
                                                   report: &report)
                }
                done.signal()
            }
            // Four questions asked meanwhile, newer than any of iCloud's: all four are among the five kept.
            let asked = (0..<4).map { "asked \(round) \($0)" }
            for (index, question) in asked.enumerated() {
                Self.record(.init(question: question, answer: "an answer", date: t0.addingTimeInterval(3_600 + Double(index))), at: url)
                usleep(300)
            }
            QuestionHistory.fileQueue.sync {}  // every question written
            usleep(2_000)
            stop.value = true
            // swiftlint:disable:next blocking_call
            done.wait()  // the test's thread, not the main one
            let kept = Set(QuestionHistory.load(from: url).entries.map(\.question))
            lost += asked.filter { !kept.contains($0) }
        }
        #expect(lost.isEmpty, "lost: \(lost)")
    }

    /// Recording a question never waits for a merge going on (it holds the file's lock): it returns at once, and the
    /// question is written once the merge is done. The main thread, where `@question` records it, never waits.
    @Test func recordingDoesNotWaitForAMergeInProgress() throws {
        let rig = try SyncRig()
        let url = rig.root.appendingPathComponent("questions.json")
        QuestionHistory.fileLock.lock()  // a merge in progress
        let start = Date()
        Self.record(.init(question: "asked during a merge", answer: "an answer", date: SyncRig.t0), at: url)
        let took = Date().timeIntervalSince(start)
        usleep(200_000)
        #expect(!FileManager.default.fileExists(atPath: url.path), "not written while the merge holds the file")
        QuestionHistory.fileLock.unlock()
        QuestionHistory.fileQueue.sync {}
        #expect(took < 0.05, "returned after \(took) s")
        #expect(QuestionHistory.load(from: url).entries.map(\.question) == ["asked during a merge"])
    }
}

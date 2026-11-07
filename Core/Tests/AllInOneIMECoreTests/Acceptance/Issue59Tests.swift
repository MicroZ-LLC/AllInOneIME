import Foundation
import Testing
@testable import AllInOneIMECore

/// #59: a recent-questions file that can't be read (truncated, or one entry in it bad) is taken for no questions, and the
/// next `@question` answered replaces it with a file of that one question. With the recent questions synced, the next
/// sync sees the questions it had before gone, takes that for a Clear made while the input method wasn't running, and
/// every Mac drops them. Expected: a file that exists but can't be read is set aside, never written over (as the sync
/// already sets aside one it can't read), and no Mac loses a question to it. Through the iCloud sync acceptance rig
/// (`ICAWorld`, `ICAMac`: each Mac's own files and clock, one shared temporary "iCloud Drive"), a question remembered as
/// the app remembers it (`ICAMac.ask`: the file read, the question recorded, the file written).
struct Issue59Tests {
    /// How A's recent-questions file is damaged.
    enum Damage: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// Cut off halfway (a crash or a full disk while it was copied).
        case truncated
        /// Whole, with one entry's date unreadable (a hand edit, or a file from a newer version).
        case oneBadEntry
        var testDescription: String { rawValue }

        func apply(to url: URL, question: String) throws {
            let data = try Data(contentsOf: url)
            switch self {
            case .truncated:
                try data.prefix(data.count / 2).write(to: url)
            case .oneBadEntry:
                var file = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                var entries = try #require(file["entries"] as? [[String: Any]])
                let index = try #require(entries.firstIndex { $0["question"] as? String == question })
                entries[index]["date"] = "last Tuesday"
                file["entries"] = entries
                try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys]).write(to: url)
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            #expect(throws: (any Error).self, "the damaged file still reads as a whole (the test missed its setup)") {
                try decoder.decode(QuestionHistory.self, from: Data(contentsOf: url))
            }
        }
    }

    /// The issue's case: B asks two questions and the Macs sync; A's file is damaged and A asks a third; A and B sync.
    /// B still has the first two, and the third reaches it; A has all three once it has synced.
    @Test(arguments: Damage.allCases)
    func aDamagedFileOnOneMacClearsNoMac(_ damage: Damage) throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.iCloudSync.recentQuestions = true }
        let b = world.mac("B") { $0.iCloudSync.recentQuestions = true }
        b.ask("Q one", at: 1)
        b.ask("Q two", at: 2)
        b.sync(at: 10)
        a.sync(at: 20)
        b.sync(at: 30)
        try #require(Set(a.questions) == ["Q one", "Q two"], "A didn't get B's questions (the test missed its setup): \(a.questions)")

        try damage.apply(to: a.questionsURL, question: "Q one")
        a.ask("Q three", at: 40)
        a.sync(at: 50)
        b.sync(at: 60)
        a.sync(at: 70)

        #expect(b.questions.contains("Q one") && b.questions.contains("Q two"),
                "\(damage): a damaged file on A cleared B's questions: B has \(b.questions)")
        #expect(Set(b.questions) == ["Q one", "Q two", "Q three"], "\(damage): B has \(b.questions)")
        #expect(Set(a.questions) == ["Q one", "Q two", "Q three"], "\(damage): A has \(a.questions)")
    }

    /// No sync: a question asked while the file can't be read is remembered, and what the file held is still on the Mac
    /// (set aside), not written over.
    @Test func askingSetsAnUnreadableFileAsideInsteadOfWritingOverIt() throws {
        let world = ICAWorld()
        let a = world.mac("A")
        a.ask("Q one", at: 1)
        a.ask("Q two", at: 2)
        try Damage.truncated.apply(to: a.questionsURL, question: "Q one")
        let damaged = try Data(contentsOf: a.questionsURL)

        a.ask("Q three", at: 3)

        #expect(a.questions.first == "Q three", "the question just asked isn't remembered: \(a.questions)")
        let kept = Self.files(under: a.home).filter { $0 != a.questionsURL.resolvingSymlinksInPath() && (try? Data(contentsOf: $0)) == damaged }
        #expect(!kept.isEmpty, "the unreadable file was written over, not set aside: \(Self.files(under: a.home).map(\.lastPathComponent))")
    }

    /// Every file under `folder`, at any depth.
    static func files(under folder: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return walker.compactMap { item in
            guard let url = item as? URL, (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
            return url.resolvingSymlinksInPath()
        }
    }
}

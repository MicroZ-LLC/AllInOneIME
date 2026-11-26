import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMETestSupport
import AppKit
import Foundation
import Testing

/// What the review of PR #162 found in `@open`'s safety and the #61 anchors: a link to a script is shown in Finder as the
/// script is; the row's words and `FileOpenPolicy.label` are the same words; a placement says which app anchor it
/// dropped (so the input controller clears only that one, not another controller's newer one).
struct OpenSafetyReviewTests {
    @Test(arguments: ["payload.terminal", "payload.command", "payload.sh", "payload.tool"])
    func aLinkToAScriptIsShownInFinder(_ target: String) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("open-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let payload = folder.appendingPathComponent(target)
        try Data("echo test\n".utf8).write(to: payload)  // 0644: no execute bit
        let link = folder.appendingPathComponent("readme")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: payload)
        #expect(FileOpenPolicy.action(for: link) == .reveal, "a link named readme to \(target) runs it when opened")
    }

    @Test func theRowAndTheLabelSayTheSame() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("open-label-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("run.command")
        try Data("echo test\n".utf8).write(to: script)
        let words = UIText.words
        let row = SearchResult(name: "run.command", path: script.path, reveals: true)
        #expect(FileOpenPolicy.label(for: script) == SessionText.openAction(row, words, terms: .mac))
        #expect(SessionText.openRow(row, language: words.language, terms: .mac).comment.hasSuffix(FileOpenPolicy.label(for: script)))
    }

    @Test @MainActor func aPlacementTellsWhichAppAnchorItDropped() {
        let client = ProfiledTextClient(.electron)
        let app = "com.tinyspeck.slackmacgap"
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 900)]
        func place(_ lastByApp: inout [String: CGRect]) -> FieldAnchor.Placed {
            var memory = PanelAnchor.Memory()
            memory.enter(.init(client: ObjectIdentifier(client), app: app, session: 1))
            memory.learnWindow { (ProfiledTextClient.window, false) }
            client.beginTurn()
            defer { client.endTurn() }
            return FieldAnchor.place(in: client, app: app, selection: nil, memory: &memory, lastByApp: &lastByApp,
                                     screens: screens, pointer: { CGPoint(x: 500, y: 400) }, accessibility: { _ in nil })
        }
        let stale = CGRect(x: 2200, y: 400, width: 1, height: 18)
        var offScreen = [app: stale]
        #expect(place(&offScreen).dropped == stale && offScreen[app] == nil, "the stale one dropped, and said so")
        var none: [String: CGRect] = [:]
        #expect(place(&none).dropped == nil, "nothing there before: nothing dropped")
    }
}

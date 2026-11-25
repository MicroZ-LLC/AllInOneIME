import AllInOneIMECore
import AllInOneIMEMac
import Foundation
import Testing

/// The core's HostDraftTests through the Mac's own reading code, on each of its profiles: a command's draft typed key
/// by key, and 2000 characters pasted into one with ⌘V, never reach the field's client while they are written: it is
/// asked to mark nothing and given nothing (`ProfiledTextClient.marks`, `inserts`), and the draft is in the panel's
/// input line. (No command is run: the replayer's session has the default AI provider. Dictation is the core's alone:
/// the Mac's shell only records it, `PlatformAction.startVoice`.)
@MainActor
struct HostDraftReplayTests {
    @Test(arguments: HostProfile.allCases)
    func aCommandDraftNeverReachesTheClient(_ profile: HostProfile) throws {
        let keys = "@question what is the plan for today".map { "TYPE \"\($0)\"\nEXPECT doc \"Hi \"\nEXPECT marked none" }
        let scenario = try HostCase.parse("""
            LANG english
            TEXT "Hi |"
            \(keys.joined(separator: "\n"))
            EXPECT preedit "question › what is the plan for today"
            EXPECT panel shown
            KEY escape
            EXPECT doc "Hi "
            """, source: "draft")
        let replayer = HostScenarioTests.replay(scenario, on: profile)
        #expect(replayer.client.marks.allSatisfy(\.isEmpty) && replayer.client.inserts.isEmpty,
                "marked \(replayer.client.marks), put in \(replayer.client.inserts)")
    }

    @Test(arguments: HostProfile.allCases)
    func aLongPasteIntoADraftNeverReachesTheClient(_ profile: HostProfile) throws {
        let pasted = String(String(repeating: "第一行 the first line of a long note, 0123456789.\n", count: 60).prefix(2000))
        let scenario = try HostCase.parse("""
            LANG english
            TEXT "Hi |"
            TYPE "@improve "
            KEY cmd+v
            EXPECT doc "Hi "
            EXPECT marked none
            EXPECT panel shown
            """, source: "paste")
        let replayer = HostReplayer(scenario, profile: profile)
        replayer.clipboard = .text(pasted)
        replayer.run()
        #expect(replayer.failures.isEmpty, "\(replayer.failures)")
        let input = replayer.panel?.input.map { $0.prompt + $0.text } ?? ""
        #expect(input.hasPrefix("improve › 第一行") && input.count > 1000, "\(input.prefix(40))")
        #expect(replayer.client.marks.allSatisfy(\.isEmpty) && replayer.client.inserts.isEmpty,
                "marked \(replayer.client.marks.map { $0.prefix(20) }), put in \(replayer.client.inserts.map { $0.prefix(20) })")
    }
}

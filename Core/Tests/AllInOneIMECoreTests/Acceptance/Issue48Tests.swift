import CryptoKit
import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// #48: a local plugin whose script is a link to a file elsewhere (main.js → ~/code/github.js). Its target edited, the
/// completions were refused, and approving the source again didn't help: only a restart of the input method did. The
/// session reads the script's SHA-256 through the hashes kept for the launch (`FileHashes`), whose stamp was the link's
/// own (lstat), which an edit of its target doesn't change, so the hash first read was kept for the life of the process;
/// approving reads the file as it is now (`PluginStore.sha256`), and the two no longer matched. Through a text field's
/// session as the shell drives it (the rig: SuggestionsAcceptanceTests.swift), the source approved as Settings approves
/// it (`CompletionSourceApproval(enabling:of:)`).
@Suite(.serialized, SuggestionsOneAtATime())
struct Issue48Tests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The script as edited: longer than `SuggestionsPlugins.script`, so its size changes too.
    static let edited = SuggestionsPlugins.script + "\nfunction extra() { return 1; }\n"

    /// The spec's GitHub plugin installed in `folder`/plugins/github/, its main.js a link to `target` (outside the plugin's
    /// folder), read back as the app reads it.
    static func installLinked(to target: URL, in folder: URL) throws -> InstalledPlugin {
        let plugins = folder.appendingPathComponent("plugins", isDirectory: true)
        let directory = plugins.appendingPathComponent("github", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(SuggestionsPlugins.githubManifest().utf8).write(to: directory.appendingPathComponent("plugin.json"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("main.js"), withDestinationURL: target)
        return try #require(PluginStore.load(from: plugins).plugins.first { $0.name == "github" })
    }

    /// The issue's test: the hash kept for a link is read again once its target changed, and is the one approving reads.
    @Test func theHashOfALinkFollowsItsTargetsEdits() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("issue48-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appendingPathComponent("github.js")
        let link = folder.appendingPathComponent("main.js")
        try Data(SuggestionsPlugins.script.utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let hashes = FileHashes()
        #expect(hashes.sha256(of: link) == Self.sha256(SuggestionsPlugins.script), "as written")

        Thread.sleep(forTimeInterval: 0.05)
        try Data(Self.edited.utf8).write(to: target)
        #expect(PluginStore.sha256(of: link) == Self.sha256(Self.edited), "approving reads the edited script")
        #expect(hashes.sha256(of: link) == PluginStore.sha256(of: link), "the target edited: read again")
    }

    /// The issue's trigger: the source approved and its rows shown, the link's target edited, then the source approved
    /// again. Edited, the script is one the user didn't approve: the source is off (nothing sent) and marked lapsed, as
    /// for a plugin updated (SuggestionsSessionTests' `anApprovalThatNoLongerHoldsIsKeptMarkedWithItsCache`). Approved
    /// again, it is asked, with the edited script's SHA-256, and that approval isn't marked lapsed.
    @Test func approvedAgainAfterItsTargetIsEditedALinkedScriptIsAsked() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            let elsewhere = world.folder.appendingPathComponent("code", isDirectory: true)
            try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            let target = elsewhere.appendingPathComponent("github.js")
            try Data(SuggestionsPlugins.script.utf8).write(to: target)
            let plugin = try Self.installLinked(to: target, in: world.folder)
            world.plugins = [plugin]
            world.runtime.list("issues", items: SuggestionsItems.issues)
            let issues = try #require(plugin.manifest.completions.first)
            let approval = try #require(CompletionSourceApproval(enabling: issues, of: plugin))
            #expect(approval.scriptSHA256 == Self.sha256(SuggestionsPlugins.script))
            world.switches.enabled = [approval]
            let lapsed = Locked<[CompletionSourceApproval]>(initialState: [])
            func field() -> SuggestionsField {
                world.field(app: "com.apple.TextEdit") { services in
                    services.suggestions.approvalsLapsed = { marked in
                        lapsed.withLock { $0 += marked }
                        var config = Config.default
                        config.completionSources = world.switches.enabled
                        config.markLapsed(marked)
                        world.switches.enabled = config.completionSources
                    }
                }
            }
            let first = field()
            first.type("#7")
            #expect(first.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "approved: its rows (\(first.issuesShown))")
            #expect(lapsed.withLock { $0 }.isEmpty, "it holds")

            // The target edited, where the user keeps it.
            Thread.sleep(forTimeInterval: 0.05)
            try Data(Self.edited.utf8).write(to: target)
            let calls = world.runtime.calls.count
            let changed = field()
            changed.type("#70")
            changed.idle()
            #expect(changed.rows.isEmpty, "edited since approved: off (\(changed.issuesShown))")
            #expect(world.runtime.calls.count == calls,
                    "edited since approved: nothing sent (\(world.runtime.calls.count - calls) calls, \(world.runtime.queryCalls.map(\.scriptSHA256)))")
            #expect(lapsed.withLock { $0 } == [approval], "edited since approved: marked lapsed (\(lapsed.withLock { $0 }))")

            // Approved again in Settings → Plugins.
            let again = try #require(CompletionSourceApproval(enabling: issues, of: plugin))
            #expect(again.scriptSHA256 == Self.sha256(Self.edited), "the edited script approved")
            world.switches.enabled = [again]
            lapsed.withLock { $0 = [] }
            let before = world.runtime.calls.count
            changed.host.send(.configChanged)
            changed.type(" #70")
            func asked() -> [CompletionCall] { Array(world.runtime.calls.dropFirst(before)).map(\.call) }
            #expect(changed.settle { !asked().isEmpty }, "approved again: asked (\(world.runtime.calls.count - before) calls)")
            #expect(asked().allSatisfy { $0.scriptSHA256 == again.scriptSHA256 }, "with the edited script (\(asked().map(\.scriptSHA256)))")
            #expect(lapsed.withLock { $0 }.isEmpty && world.switches.enabled == [again],
                    "approved again: not marked lapsed (\(lapsed.withLock { $0 }), \(world.switches.enabled.map(\.lapsed)))")

            let fresh = field()
            fresh.type("#7")
            #expect(fresh.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "approved again: its rows (\(fresh.issuesShown))")
        }
    }
}

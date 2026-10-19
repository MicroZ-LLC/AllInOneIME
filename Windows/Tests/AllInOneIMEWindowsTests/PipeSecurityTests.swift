#if os(Windows)
import AllInOneIMECore
import AllInOneIMEWindows
import AllInOneIMEWire
import Foundation
import Testing
import WinSDK

/// The engine's pipe as the DLL's server check sees it (§2.1 and its spec note): the server in this session, run by
/// this user at medium integrity or higher, and the pipe owned by this user, with the low label the SDDL gives it.
struct PipeSecurityTests {
    final class NullHost: WireHost, @unchecked Sendable {
        func perform(_ effect: Composer.Effect, in session: ComposerSession) {}
        func panel(shown: Bool, in session: ComposerSession) {}
    }

    @Test func theDescriptorNamesTheUserAsOwner() {
        #expect(PipeNames.sddl(sid: "S-1-5-21-1-2-3-1001").hasPrefix("O:S-1-5-21-1-2-3-1001D:P("))
    }

    @Test func theServerCheckPasses() throws {
        let sid = try Win32.currentUserSID()
        var options = PipeListener.Options()
        // The user's pipe name with a suffix, as the DLL's tests have it: never the real engine's.
        let name = PipeNames.pipe(sid: sid) + "-test-\(GetCurrentProcessId())"
        options.pipeName = name
        let listener = try PipeListener(server: WireServer(environment: WireEnvironment(host: NullHost())), sid: sid,
                                        options: options)
        try listener.start()
        defer { listener.stop() }
        let client = try PipeClient.connect(name: name, timeout: 2)
        defer { client.close() }
        let facts = client.serverFacts()
        #expect(facts.owner?.caseInsensitiveCompare(sid) == .orderedSame)
        #expect(facts.labelRID == 0x1000)  // SECURITY_MANDATORY_LOW_RID
        #expect(facts.pid == GetCurrentProcessId())
        #expect(client.checkServer(sid: sid) == [])
    }
}
#endif

import AllInOneIMECore
import AllInOneIMEMac
import Foundation
import Testing

struct DesktopCLILookupIsolationTests {
    @Test func injectedLookupUsesTestCLIsWithoutDesktopApps() {
        let fake = URL(fileURLWithPath: "/tmp/test-codex")
        let found = DesktopCLILookup.resolve(.codex, shell: { _ in fake }, bundled: { _ in
            Issue.record("Desktop lookup should not run when the shell supplied a CLI")
            return nil
        })
        #expect(found == fake)
        #expect(DesktopCLILookup.resolve(.codex, shell: { _ in nil }, bundled: { _ in nil }) == nil)
    }

    @Test func productionLookupCanUseTheDesktopApp() {
        let bundled = URL(fileURLWithPath: "/tmp/bundled-codex")
        #expect(DesktopCLILookup.resolve(.codex, shell: { _ in nil }, bundled: { _ in bundled }) == bundled)
    }

    @Test func releaseSourceDoesNotReadTheTestVariable() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let mac = try String(contentsOf: root.appendingPathComponent("Sources/AllInOneIME/ClaudeSessionMac.swift"), encoding: .utf8)
        #expect(!mac.contains("ALLINONEIME_NO_DESKTOP_CLIS"))
        let makefile = try String(contentsOf: root.appendingPathComponent("Makefile"), encoding: .utf8)
        #expect(makefile.contains("TEST_ISOLATION := ALLINONEIME_NO_DESKTOP_CLIS=1"))
    }
}

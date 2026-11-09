import Foundation
import Testing

/// The input method started again after an update (`UpdateRelaunch`): a new instance when none runs, then looked for;
/// what is said when it doesn't run. `open` is a fake; the process list is the kernel's (a process of the test's own).
struct UpdateRelaunchTests {
    let app = URL(fileURLWithPath: "/test/Input Methods/AllInOneIME.app")

    @Test func noneRunningStartsANewInstance() {
        #expect(UpdateRelaunch.openArguments(app, newInstance: true, settings: false) == ["-n", app.path])
        #expect(UpdateRelaunch.openArguments(app, newInstance: true, settings: true) == ["-n", app.path, "--args", "--settings"])
        // One running (macOS started it again): brought forward, never a second one.
        #expect(UpdateRelaunch.openArguments(app, newInstance: false, settings: true) == [app.path, "--args", "--settings"])
    }

    @Test func itIsLookedForUntilItRuns() {
        var opened: [[String]] = [], looks = 0
        let failure = UpdateRelaunch.start(app, newInstance: true, settings: false, open: { opened.append($0); return (0, "") },
                                           running: { looks += 1; return looks >= 3 }, pause: {})
        #expect(failure == nil && opened == [["-n", app.path]] && looks == 3)
    }

    /// `open` that launches nothing (the helper taken for the app: -600), or a new instance that never shows up: said.
    @Test func oneThatDoesntRunIsSaid() {
        var clock = Date(timeIntervalSince1970: 0)
        let notOpened = UpdateRelaunch.start(app, newInstance: true, settings: false,
                                             open: { _ in (1, "LSOpenURLsWithRole() failed with error -600 for the file \(app.path).") },
                                             running: { false }, wait: 10, pause: { clock += 1 }, now: { clock })
        #expect(notOpened == "open exited 1: LSOpenURLsWithRole() failed with error -600 for the file \(app.path).")
        clock = Date(timeIntervalSince1970: 0)
        let gone = UpdateRelaunch.start(app, newInstance: true, settings: false, open: { _ in (0, "") }, running: { false },
                                        wait: 10, pause: { clock += 1 }, now: { clock })
        #expect(gone == "it isn't running 10 s after open")
    }

    /// The kernel's process list finds a process by its executable's path, links resolved (not by Launch Services, for
    /// which the helper may be the app at that path), and the path follows the bundle when it is moved.
    @Test func aProcessIsFoundByItsExecutablesPath() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("relaunch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let macOS = folder.appendingPathComponent("Some.app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent("sleep")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: executable)
        // Signed as the test's own (a copy of a system program elsewhere is stopped at once).
        try FakeApp.run("/usr/bin/codesign", ["--force", "--sign", "-", executable.path])
        let process = Process()
        process.executableURL = executable
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        #expect(UpdateRelaunch.processes(running: executable) == [process.processIdentifier])
        #expect(UpdateRelaunch.processes(running: folder.appendingPathComponent("Other.app/Contents/MacOS/sleep")).isEmpty)
        // Moved aside (as the swap moves the previous apps): its path is where it is now.
        let aside = folder.appendingPathComponent("aside-Some.app")
        try FileManager.default.moveItem(at: folder.appendingPathComponent("Some.app"), to: aside)
        let moved = try #require(UpdateRelaunch.executablePath(of: process.processIdentifier))
        #expect(URL(fileURLWithPath: moved).resolvingSymlinksInPath().path
                == aside.appendingPathComponent("Contents/MacOS/sleep").resolvingSymlinksInPath().path)
        #expect(UpdateRelaunch.processes(running: executable).isEmpty)
    }
}

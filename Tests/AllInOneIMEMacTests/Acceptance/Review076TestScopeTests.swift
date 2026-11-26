import Foundation
import Testing

// The 0.7.6 review's item 35: Scripts/test-scope.sh, which tells a pull request's test jobs from the paths it changed,
// leaves the updater's end-to-end test (`make update-test`: `make app settings-app`, then Scripts/test-update.sh) out
// for changes that test runs on. A pull request that only changes one of these merges without it; the next push to a
// release branch is the first to run it.
//
// Scripts/test-scope-test.sh (part of `make lint`) holds the table of today's answers, some of which these contradict
// (Core/Sources/AllInOneIMECore/Resources/RedactionWords.txt, .github/workflows/quality.yml, Resources/user-guide.md
// and Resources/en.lproj/InfoPlist.strings as "no updater's test"): whoever fixes test-scope.sh changes those rows too.

struct Review076TestScopeTests {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    struct Failure: Error, CustomStringConvertible { var description: String }

    /// Scripts/test-scope.sh's answer for a change of `paths`: `core`, `mac` and `update`.
    static func scope(_ paths: [String]) throws -> [String: String] {
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [repository.appendingPathComponent("Scripts/test-scope.sh").path]
        process.currentDirectoryURL = repository
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data((paths.joined(separator: "\n") + "\n").utf8))
        try input.fileHandleForWriting.close()
        let printed = String(decoding: try output.fileHandleForReading.readToEnd() ?? Data(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(description: "test-scope.sh failed (\(process.terminationStatus)): \(printed)") }
        var answer: [String: String] = [:]
        for line in printed.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { answer[String(parts[0])] = String(parts[1]) }
        }
        return answer
    }

    /// The three the review names. ProcessOutput.swift: every tool the updater and the installer run goes through it
    /// (Updates.swift's `ProcessOutput.tool` for the new version's `--version`, `open` and lsregister; Installer.swift;
    /// IdentityFinish.swift), and it isn't one of the `Update*.swift` files the script knows. RedactionWords.txt:
    /// `make app` fails without it in the core's resource bundle (the Makefile's `test -s …/RedactionWords.txt`), and
    /// the updater's test is what runs `make app` on a pull request. quality.yml: the workflow that runs the updater's
    /// test and decides when (its `update` step and the release-branch rule).
    @Test(arguments: [
        "Core/Sources/AllInOneIMECore/Platform/ProcessOutput.swift",
        "Core/Sources/AllInOneIMECore/Resources/RedactionWords.txt",
        ".github/workflows/quality.yml",
    ])
    func aChangeTheUpdatersTestRunsOnAsksForIt(_ path: String) throws {
        let answer = try Self.scope([path])
        #expect(answer["update"] == "true", "a pull request that changes only \(path) skips `make update-test`: \(answer)")
        #expect(answer["mac"] == "true", "the updater's test runs in mac-test: \(answer)")
    }

    /// The resources `make app` and `make settings-app` put in the apps the updater's test installs, updates and
    /// checks, besides the Info.plist files, entitlements and profile the script already knows: the interface text's
    /// catalogs (compiled into every app; a catalog that doesn't compile fails `make app`), the user guide, the AI
    /// logos, the Info.plist's own strings and the Lua filter copied beside rime's. A change that breaks one of them
    /// breaks the build the updater's test starts with.
    @Test(arguments: [
        "Resources/Localizable.xcstrings",
        "Core/Resources/Localizable.xcstrings",
        "Resources/user-guide.md",
        "Resources/AILogos/anthropic.pdf",
        "Resources/en.lproj/InfoPlist.strings",
        "Resources/rime/lua/allinoneime_removed.lua",
    ])
    func aChangeToWhatGoesIntoTheAppsAsksForTheUpdatersTest(_ path: String) throws {
        let answer = try Self.scope([path])
        #expect(answer["update"] == "true", "a pull request that changes only \(path) skips `make update-test`: \(answer)")
        #expect(answer["mac"] == "true", "the updater's test runs in mac-test: \(answer)")
    }

    /// What needs no updater's test still doesn't ask for it (a guard for the fix: not "always").
    @Test(arguments: ["docs/user-guide.md", "Core/Tests/AllInOneIMECoreTests/ComposerTests.swift", "Sources/AllInOneIME/CandidatePanel.swift"])
    func aChangeTheUpdatersTestDoesntRunOnStillSkipsIt(_ path: String) throws {
        #expect(try Self.scope([path])["update"] == "false")
    }
}

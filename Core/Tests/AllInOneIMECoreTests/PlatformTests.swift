import Foundation
import Testing
@testable import AllInOneIMECore

/// The platform seams (`Platform`) as they behave where a system has nothing to offer, and the system file operations.
/// Nothing here changes `Platform.current`: the stand-ins are used directly, or scoped to a task (`Platform.override`).
struct PlatformTests {
    /// A stand-in scoped to a task: what it runs, and the tasks it starts, see it; the installed platform doesn't change.
    @Test func aStandInForOneTask() async {
        var fake = Platform.current
        fake.processes = NoProcessLauncher()
        fake.secrets = .inMemory()
        fake.secrets.message = { _ in "the test's" }
        let installed = Platform.current.processes.canLaunch
        await Platform.$override.withValue(fake) {
            #expect(!Platform.current.processes.canLaunch && !CommandRunner.isInstalled("sh", path: "/bin"))
            // The keys are read through it too (`APIKeys.keychain` keeps no copy).
            #expect(APIKeys.keychain.message(0) == "the test's")
            await Task { #expect(!Platform.current.processes.canLaunch) }.value
        }
        #expect(Platform.current.processes.canLaunch == installed)
    }

    @Test func theHeuristicLanguageGuess() {
        let guess = HeuristicLanguageIdentifier()
        #expect(guess.dominantLanguage(of: "je me sens pas très bien", among: ["en", "fr"])?.code == "fr")
        #expect(guess.dominantLanguage(of: "this bug is blocker, your team need fix it asap", among: ["en", "fr"])?.code == "en")
        #expect(guess.dominantLanguage(of: "check it", among: ["en", "fr"])?.code == "en")  // nothing to go by: English
        #expect(guess.dominantLanguage(of: "Сегодня я плохо себя чувствую", among: [])?.code == "ru")
        #expect(guess.dominantLanguage(of: "我今天有点不舒服", among: [])?.code == "zh")
        #expect(guess.dominantLanguage(of: "今日はちょっと体調が悪いです", among: [])?.code == "ja")
        #expect(guess.dominantLanguage(of: "आज मेरी तबीयत ठीक नहीं है", among: [])?.code == "hi")
        #expect((guess.dominantLanguage(of: "Сегодня я плохо себя чувствую", among: [])?.confidence ?? 0) >= 0.8)
        #expect(guess.dominantLanguage(of: "Сегодня", among: ["en", "fr"]) == nil)  // not one of those
        #expect(guess.dominantLanguage(of: "123 !?", among: []) == nil)
    }

    @Test func withoutTheSystemsHelpers() throws {
        #expect(RulesOnlyDateDetector().dates(in: "明天下午3点开会").isEmpty)
        #expect(UnsupportedPDFTextExtractor().text(ofPDF: Data("%PDF-1.4".utf8)) == nil)
        #expect(throws: InlineCodeError("JavaScript is not available")) {
            try InlineCode.runJavaScript("1 + 1", print: { _ in }, warn: { _ in }, engine: UnsupportedScriptEngine())
        }
        #expect(throws: PluginScriptError.failed("JavaScript is not available")) {
            try PluginScript.evaluate(source: "function run(t) { return t }", input: "x", fetcher: NoFetcher(),
                                      engine: UnsupportedScriptEngine())
        }
        // No secret store: nothing is kept, and a save says why.
        let store = APIKeys.Keychain.unavailable
        #expect(throws: APIKeys.KeychainError.self) { try APIKeys.save("sk-123456789012", account: "test", label: "Test", in: store) }
        #expect(!APIKeys.hasKeychainKey(account: "test", in: store))
        #expect(APIKeys.KeychainError(status: -4, message: store.message(-4)).errorDescription == "No secret store on this platform")
    }

    @Test func withoutChildProcesses() {
        let none = NoProcessLauncher()
        #expect(!none.canLaunch && !none.isRunnable(URL(fileURLWithPath: "/bin/sh")))
        #expect(throws: ProcessLaunchError.unsupported) { try none.launch(LaunchSpec(executable: URL(fileURLWithPath: "/bin/sh"))) }
        // The commands that run a program are the ones left out there (`Command.catalog`).
        let commands = Command.catalog([CustomCommand(name: "upper", type: .run, argv: ["tr", "a-z", "A-Z"]),
                                        CustomCommand(name: "tweet", type: .prompt, prompt: "Rewrite this as a tweet.")])
        let needing = Set(commands.filter(\.needsChildProcess).map(\.name))
        #expect(needing.isSuperset(of: ["py", "js", "upper"]) && !needing.contains("tweet") && !needing.contains("read"))
    }

    @Test func swapsAndPrivateWrites() throws {
        let files = SystemFileOps()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("platform-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func folderHolding(_ name: String, _ text: String) throws -> URL {
            let url = folder.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url.appendingPathComponent("marker"))
            return url
        }
        func marker(_ url: URL) -> String? { try? String(contentsOf: url.appendingPathComponent("marker"), encoding: .utf8) }

        // Renamed into place where nothing is; never over something there.
        let new = try folderHolding("new", "new"), place = folder.appendingPathComponent("place", isDirectory: true)
        try files.swap(new, into: place, exists: false)
        #expect(marker(place) == "new" && !FileManager.default.fileExists(atPath: new.path))
        let other = try folderHolding("other", "other")
        #expect(throws: (any Error).self) { try files.swap(other, into: place, exists: false) }
        #expect(marker(place) == "new")
        // Swapped with what's there: the source then holds the old.
        try files.swap(other, into: place, exists: true)
        #expect(marker(place) == "other" && marker(other) == "new")

        // A private write: the user's alone, replacing the file, its date kept to the nanosecond the system has.
        let file = folder.appendingPathComponent("private.json")
        try Data("old".utf8).write(to: file)
        try files.writePrivate(Data("new".utf8), to: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "new")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        let date = try #require(files.modificationDate(atPath: file.path))
        #expect(abs(date.timeIntervalSinceNow) < 600)
        #expect(files.modificationDate(atPath: folder.appendingPathComponent("missing").path) == nil)
    }

    struct NoFetcher: PluginFetcher {
        func fetch(_ requests: [PluginRequest]) -> [PluginResponse] { requests.map { _ in PluginResponse(error: "offline") } }
    }
}

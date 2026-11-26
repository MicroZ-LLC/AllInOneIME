import AllInOneIMEMac
import Foundation
import Testing

/// Reproduces item 26: `ContactBook.loadNow` waits on an unbounded `DispatchSemaphore` while asking for
/// Contacts authorization (`CNContactStore.requestAccess`), blocking a worker thread forever if the prompt
/// is never answered.
///
/// Seam: `ContactBook` lives in the `AllInOneIME` executable target (`Sources/AllInOneIME/MessageSending.swift`),
/// so this test compiles it into an isolated child via `SourceCompiler` and swizzles `CNContactStore` in the
/// child process so `authorizationStatus(for:)` reports `.notDetermined` and `requestAccess(for:completionHandler:)`
/// never invokes its completion handler (offline, no TCC prompt). Because `ContactBook` currently has no timeout
/// parameter, a production timeout can honor an optional positive `TimeInterval` override in
/// `ALLINONEIME_CONTACTS_AUTH_TIMEOUT` (set to `"0.3"` here) so this test stays fast.
@Suite(.serialized)
struct ContactsAuthorizationTimeoutAcceptanceTests {
    @Test func unansweredPermissionRequestDoesNotHoldAWorkerForever() throws {
        let result = try ContactsAuthChild.run(
            environment: ["ALLINONEIME_CONTACTS_AUTH_TIMEOUT": "0.3"],
            limit: 2.5
        )
        #expect(result.output.contains("ASKED true"), "Contacts authorization was never requested: \(result.output)")
        #expect(!result.timedOut,
                "ContactBook.load() blocked indefinitely waiting on an unanswered Contacts authorization prompt: \(result.output)")
        if !result.timedOut {
            #expect(result.output.contains("RESULT denied"), "Timed-out authorization should resolve to .denied: \(result.output)")
            #expect(result.elapsed < 2, "ContactBook.load() took \(String(format: "%.2f", result.elapsed)) s")
        }
    }
}

private enum ContactsAuthChild {
    struct RunResult {
        var status: Int32
        var output: String
        var elapsed: TimeInterval
        var timedOut: Bool
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("contacts-auth-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let messageFile = repository.appendingPathComponent("Sources/AllInOneIME/MessageSending.swift")
        let harnessFile = scratch.appendingPathComponent("main.swift")
        try harnessSource.write(to: harnessFile, atomically: true, encoding: .utf8)
        let executable = scratch.appendingPathComponent("contacts-auth-harness")
        let swift = try SourceCompiler.compile(
            repository: repository,
            sources: [messageFile.path, harnessFile.path],
            executable: executable,
            timeout: 60
        )
        guard swift.status == 0 else { throw Failure(description: swift.output) }
        return executable
    }

    static func run(environment: [String: String], limit: TimeInterval) throws -> RunResult {
        let executable = try compiled.get()
        let out = Pipe()
        let process = Process()
        process.executableURL = executable
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = out
        let started = Date()
        try process.run()
        let collected = Locked(initialState: Data())
        let readDone = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            collected.withLock { $0 = data }
            readDone.signal()
        }
        let deadline = Date().addingTimeInterval(limit)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        var timedOut = false
        if process.isRunning {
            timedOut = true
            let pid = process.processIdentifier
            _ = kill(-pid, SIGKILL)
            _ = kill(pid, SIGKILL)
            process.waitUntilExit()
        }
        _ = readDone.wait(timeout: .now() + 1)
        let elapsed = Date().timeIntervalSince(started)
        let text = String(decoding: collected.withLock { $0 }, as: UTF8.self)
        return RunResult(status: process.terminationStatus, output: text, elapsed: elapsed, timedOut: timedOut)
    }

    static let harnessSource = #"""
import AllInOneIMECore
import AllInOneIMEMac
import Contacts
import Foundation
import ObjectiveC
import os

let log = Logger(subsystem: "com.allinoneime.inputmethod.AllInOneIME", category: "test")
let askedLock = NSLock()
var askedFlag = false
var retainedHandlers: [Any] = []

extension CNContactStore {
    @objc class func stub_authorizationStatus(for entityType: CNEntityType) -> CNAuthorizationStatus {
        .notDetermined
    }

    @objc func stub_requestAccess(for entityType: CNEntityType, completionHandler: @escaping (Bool, Error?) -> Void) {
        askedLock.lock()
        askedFlag = true
        retainedHandlers.append(completionHandler)
        askedLock.unlock()
        print("ASKED true")
        fflush(stdout)
        // Intentionally never invoke completionHandler: simulates an unanswered permission prompt.
    }
}

guard let origStatus = class_getClassMethod(CNContactStore.self, #selector(CNContactStore.authorizationStatus(for:))),
      let stubStatus = class_getClassMethod(CNContactStore.self, #selector(CNContactStore.stub_authorizationStatus(for:))),
      let origRequest = class_getInstanceMethod(CNContactStore.self, #selector(CNContactStore.requestAccess(for:completionHandler:))),
      let stubRequest = class_getInstanceMethod(CNContactStore.self, #selector(CNContactStore.stub_requestAccess(for:completionHandler:))) else {
    fputs("failed to locate CNContactStore methods\n", stderr)
    exit(2)
}
method_exchangeImplementations(origStatus, stubStatus)
method_exchangeImplementations(origRequest, stubRequest)

let done = DispatchSemaphore(value: 0)
Task {
    let result = await ContactBook.load()
    askedLock.lock()
    let asked = askedFlag
    askedLock.unlock()
    print("ASKED \(asked)")
    switch result {
    case .denied: print("RESULT denied")
    case let .contacts(list): print("RESULT contacts \(list.count)")
    }
    done.signal()
}
done.wait()
"""#
}

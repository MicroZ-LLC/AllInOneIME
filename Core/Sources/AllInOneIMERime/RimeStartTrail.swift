import AllInOneIMECore
import Foundation

/// Where librime's start got to: each step written down before it runs (`RimeService.start`'s calls into librime, its
/// deployments' start and end, the exit's `finalize`), one a line, in `rime-start.txt` in the Rime logs folder (the user
/// folder without one), and logged. A crash in librime there leaves the step it was in as the file's last line, and the
/// next start says so in the log ("the last start of librime ended during …"). The time, the process and the step's
/// name only: no path, nothing typed. Written at once (not buffered), so that a crash right after keeps it.
final class RimeStartTrail: @unchecked Sendable {
    static let fileName = "rime-start.txt"
    /// The steps a trail ends with when what it wrote down got through; any other last step was under way.
    static let finished: Set<String> = ["started", "deploy success", "deploy failure", "ended at exit"]

    private let lock = NSLock()
    private var handle: FileHandle?
    private var log: CoreLog { RimeService.log }

    /// A new trail in `folder` (made already), after saying in the log where the last one stopped, if in a step.
    func begin(in folder: URL) {
        let url = folder.appendingPathComponent(Self.fileName)
        if let last = try? String(contentsOf: url, encoding: .utf8), let step = Self.unfinished(last) {
            log.error("the last start of librime ended during \"\(step)\" (\(Self.fileName)): a crash or a kill there")
        }
        let opened = lock.withLock {
            try? handle?.close()
            handle = FileManager.default.createFile(atPath: url.path, contents: nil) ? FileHandle(forWritingAtPath: url.path) : nil
            return handle != nil
        }
        if !opened { log.error("librime's start trail not written (\(Self.fileName))") }
    }

    /// Writes `step` down, before it runs, and logs it.
    func step(_ step: String) {
        log.notice("librime: \(step)")
        let time = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone(identifier: "UTC") ?? .current,
                                               formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        let line = Data("\(time) pid \(ProcessInfo.processInfo.processIdentifier) \(step)\n".utf8)
        lock.withLock {
            do { try handle?.write(contentsOf: line) } catch { handle = nil }
        }
    }

    /// The step a trail (its text) was in when it ended, unless that was one of `finished`: nil then, and for none.
    static func unfinished(_ text: String) -> String? {
        guard let last = text.split(separator: "\n").last else { return nil }
        // "<time> pid <pid> <step>"
        let parts = last.split(separator: " ", maxSplits: 3)
        guard parts.count == 4, parts[1] == "pid" else { return nil }
        let step = String(parts[3])
        return finished.contains(step) ? nil : step
    }
}

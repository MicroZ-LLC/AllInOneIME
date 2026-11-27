import AllInOneIMECore
import Foundation
#if os(Windows)
import WinSDK
#endif

/// Where librime's start got to: each step written down before it runs (`RimeService.start`'s calls into librime, its
/// deployments' start and end, the exit's `finalize`), one a line, in `rime-start-<pid>.txt` in the Rime logs folder (the
/// user folder without one), and logged. A file for each process: two that start librime at once (the installer's
/// `--register` and the input method macOS starts for it) never write in, or empty, each other's. A crash in librime
/// leaves the step it was in under way in its file; the next start, finding that process gone, says so in the log ("the
/// last start of librime ended during …") and removes the file. A process still running is left alone: its trail is
/// still being written. The time, the process and the step's name only: no path, nothing typed.
///
/// Written by a queue of its own, a line at a time, in the order the steps came, and not buffered: a line written is in
/// the file whatever happens to the process next. From the main thread `step` doesn't wait for it (InputMethodKit calls
/// in there: never a wait for the disk), the queue writes it right after; from any other thread (a start run there,
/// librime's deployment thread) it is written before `step` returns.
final class RimeStartTrail: @unchecked Sendable {
    /// The start's steps (and the exit's) that end it: any other last one of those was under way.
    static let finished: Set<String> = ["started", "ended at exit"]
    /// A deployment's, written on librime's deployment thread meanwhile: under way until one of `deploymentEnds`.
    static let deploymentStart = "deploy start"
    static let deploymentEnds: Set<String> = ["deploy success", "deploy failure"]

    private let queue = DispatchQueue(label: "AllInOneIME.rimeStartTrail")
    /// This process's file, open for appending: used on `queue` only.
    private var handle: FileHandle?
    private let pid: Int32
    private let isRunning: @Sendable (Int32) -> Bool
    private var log: CoreLog { RimeService.log }

    /// `pid` and `isRunning`: this process's and the system's; the tests' play several processes in one.
    init(pid: Int32 = ProcessInfo.processInfo.processIdentifier,
         isRunning: @escaping @Sendable (Int32) -> Bool = RimeStartTrail.isRunning) {
        self.pid = pid
        self.isRunning = isRunning
    }

    static func fileName(pid: Int32) -> String { "rime-start-\(pid).txt" }

    /// The process a trail's file is of, by its name; nil for any other file.
    static func pid(ofFileName name: String) -> Int32? {
        guard name.hasPrefix("rime-start-"), name.hasSuffix(".txt") else { return nil }
        return Int32(name.dropFirst("rime-start-".count).dropLast(".txt".count))
    }

    /// A new trail in `folder` (made already), after saying in the log where the last ones of processes now gone
    /// stopped, if in a step.
    func begin(in folder: URL) {
        perform { [self] in
            endTrails(in: folder)
            try? handle?.close()
            handle = Self.makeAnew(folder.appendingPathComponent(Self.fileName(pid: pid)))
            if handle == nil { log.error("librime's start trail not written (\(Self.fileName(pid: pid)))") }
        }
    }

    /// Writes `step` down, before it runs, and logs it.
    func step(_ step: String) {
        log.notice("librime: \(step)")
        let time = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone(identifier: "UTC") ?? .current,
                                               formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        let line = Data("\(time) pid \(pid) \(step)\n".utf8)
        perform { [self] in
            do { try handle?.write(contentsOf: line) } catch { handle = nil }
        }
    }

    /// Returns once what was written down so far is in the file: as the process ends (`RimeService.endAtExit`).
    func flush() {
        queue.sync {}
    }

    private func perform(_ work: @escaping @Sendable () -> Void) {
        if Thread.isMainThread { queue.async(execute: work) } else { queue.sync(execute: work) }
    }

    /// The trails in `folder` of processes no longer running (and one of this process's number, from before), each
    /// logged if it ended in a step, and removed.
    private func endTrails(in folder: URL) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
            guard let owner = Self.pid(ofFileName: name), owner == pid || !isRunning(owner) else { continue }
            let file = folder.appendingPathComponent(name)
            if let text = try? String(contentsOf: file, encoding: .utf8), let step = Self.unfinished(text) {
                log.error("the last start of librime ended during \"\(step)\" (\(name)): a crash or a kill there")
            }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// `url` made empty, open for appending: each line is one write at the file's end.
    private static func makeAnew(_ url: URL) -> FileHandle? {
        #if os(Windows)
        guard FileManager.default.createFile(atPath: url.path, contents: nil), let handle = FileHandle(forWritingAtPath: url.path)
        else { return nil }
        _ = try? handle.seekToEnd()
        return handle
        #else
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND | O_CLOEXEC, 0o644)
        return descriptor < 0 ? nil : FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        #endif
    }

    /// Whether process `pid` is running (or may be: one the system won't say of): its trail may be written still.
    static func isRunning(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        #if os(Windows)
        guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, DWORD(pid)) else {
            return Int32(bitPattern: GetLastError()) == ERROR_ACCESS_DENIED
        }
        defer { CloseHandle(process) }
        return WaitForSingleObject(process, 0) == DWORD(WAIT_TIMEOUT)
        #else
        return kill(pid, 0) == 0 || errno == EPERM
        #endif
    }

    /// The step a trail (its text) was in when it ended: the start's (or the exit's) last, unless one of `finished`;
    /// else a deployment begun and not ended; nil when neither, and for none. Its lines come from two threads, the
    /// start's and librime's deployment thread, in whatever order they ran ("started" before "deploy start", or after):
    /// each is read on its own.
    static func unfinished(_ text: String) -> String? {
        var step: String?
        var deploying = false
        for line in text.split(separator: "\n") {
            // "<time> pid <pid> <step>"
            let parts = line.split(separator: " ", maxSplits: 3)
            guard parts.count == 4, parts[1] == "pid" else { continue }
            let name = String(parts[3])
            if name == deploymentStart {
                deploying = true
            } else if deploymentEnds.contains(name) {
                deploying = false
            } else {
                step = name
            }
        }
        if let step, !finished.contains(step) { return step }
        return deploying ? deploymentStart : nil
    }
}

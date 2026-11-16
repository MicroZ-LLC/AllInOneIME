import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// A place in the temporary directory for a test's files, removed when the test process exits. Tests made one folder
/// each (`settings-service-<UUID>` and the like) and seldom removed it: 246,000 of them filled the Mac mini's disk
/// (2026-11-16). `TestScratch.temporary("name-\(UUID().uuidString)")` is
/// `FileManager.default.temporaryDirectory.appendingPathComponent(…)`, remembered for the exit.
public enum TestScratch {
    public static func temporary(_ name: String) -> URL {
        remember(FileManager.default.temporaryDirectory.appendingPathComponent(name))
    }

    public static func temporary(_ name: String, isDirectory: Bool) -> URL {
        remember(FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: isDirectory))
    }

    private static func remember(_ url: URL) -> URL {
        Registry.shared.add(url)
        return url
    }

    private final class Registry: @unchecked Sendable {
        static let shared = Registry()
        private let lock = NSLock()
        private var paths: [String] = []
        private var registered = false

        func add(_ url: URL) {
            lock.lock()
            defer { lock.unlock() }
            paths.append(url.path)
            if !registered {
                registered = true
                atexit { Registry.shared.removeAll() }
            }
        }

        private func removeAll() {
            lock.lock()
            let all = paths
            lock.unlock()
            for path in all { try? FileManager.default.removeItem(atPath: path) }
        }
    }
}

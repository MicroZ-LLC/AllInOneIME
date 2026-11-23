import Foundation

/// A folder removed when its owner lets it go: a test's settings folder (`useTestSettings`), each test's, of which 700
/// were left in TMPDIR a run before the server's end removed it too.
final class RemovedWhenReleased: @unchecked Sendable {
    let url: URL
    init(_ url: URL) { self.url = url }
    deinit { try? FileManager.default.removeItem(at: url) }
}

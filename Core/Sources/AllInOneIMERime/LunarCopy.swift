import Foundation

extension RimeService {
    /// What the user folder's `lua/lunar.db` (or an OpenCC file) was copied from, and the copy as it was made: a later
    /// source is copied over it only while it is still that copy.
    struct LunarCopy: Codable, Equatable {
        static let fileName = "lunar.db.allinoneime.json"

        /// A file's size and modification time.
        struct Stamp: Codable, Equatable {
            var size: UInt64
            var modified: Double

            /// Nil when `url` isn't a file of `type` (a link isn't followed).
            init?(_ url: URL, type: FileAttributeType) {
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      attributes[.type] as? FileAttributeType == type,
                      let size = (attributes[.size] as? NSNumber)?.uint64Value,
                      let modified = attributes[.modificationDate] as? Date else { return nil }
                self.size = size
                self.modified = modified.timeIntervalSince1970
            }
        }

        var source: Stamp
        var copy: Stamp
    }
}

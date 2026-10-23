import Foundation
import Testing
@testable import AllInOneIMECore

/// The coding language packs this repository ships (Core/CodingPacks/), read as the app reads a downloaded one.
struct SuggestionsCodingPacksTests {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("CodingPacks", isDirectory: true)

    // MARK: - The packs

    /// Every pack in Core/CodingPacks is kept as a downloaded one is (`CodingPackStore.keep`: a pack, of the language its
    /// file is named for, within the limits), names no keyword twice, and offers each of its snippets for its trigger
    /// (spec 6.13: the body starts with it).
    @Test func theShippedPacksAreGood() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let languages = files.map { $0.deletingPathExtension().lastPathComponent }
        #expect(Set(languages) == ["c", "cpp", "go", "java", "javascript", "python", "typescript"], "\(languages)")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coding-packs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodingPackStore(directory: directory)
        let t = InterfaceWords(language: "en")
        for (file, language) in zip(files, languages) {
            let pack = try store.keep(Data(contentsOf: file), language: language)
            #expect(Set(pack.keywords).count == pack.keywords.count, "\(language): a keyword twice")
            for snippet in pack.snippets {
                let rows = CodingRows.rows(snippet.trigger, packs: [pack], words: [], appClass: .ordinary, in: t)
                #expect(rows.contains { $0.insertion == CodingRows.expand(snippet.body).text },
                        "\(language): \(snippet.trigger) (\(snippet.title ?? "")) is never offered")
            }
        }
        #expect(store.installed().map(\.title) == ["C", "C++", "Go", "Java", "JavaScript", "Python", "TypeScript"])
    }
}

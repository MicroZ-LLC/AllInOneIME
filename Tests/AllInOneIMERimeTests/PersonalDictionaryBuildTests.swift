import AllInOneIMECore
import Foundation
import Testing
@testable import AllInOneIMERime

/// What real librime builds of the personal dictionaries' wrapper, and that it goes with the last of them: the files
/// `PersonalDictionaryStore` removes then are the ones librime made (their names are its own), and pinyin deploys and
/// works without them. In a process of its own (`RimeWorker`).
struct PersonalDictionaryBuildTests {
    @Test(.enabled(if: RimeWorker.scenario == nil && (RimeWorker.dataAvailable || RimeWorker.required)))
    func whatRimeBuiltGoesWithTheLastDictionary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-dictionary-build-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("dictionary-build", root: root)
    }

    static let scenarios: [String: @Sendable (URL) throws -> Void] = [
        "dictionary-build": { root in
            let user = root.appendingPathComponent("Rime"), build = user.appendingPathComponent("build")
            let service = RimeService.shared
            try service.start(sharedDataDir: RimeFixture.sharedData, userDataDir: user, logDir: nil)
            try #require(service.waitUntilReady(timeout: 120))
            let store = PersonalDictionaryStore(userDirectory: user, schema: RimeFixture.sharedData.appendingPathComponent("rime_ice.schema.yaml"))
            let source = root.appendingPathComponent("team.dict.yaml")
            try "---\nname: build_check\nversion: \"1\"\n...\n霁鸢星槎\tce shi ci ku\t900000\n".write(to: source, atomically: true, encoding: .utf8)
            func candidates(_ input: String) throws -> [String] {
                let session = try #require(service.makeSession())
                defer { session.clearComposition() }
                for byte in input.utf8 { _ = session.processKey(Int32(byte), mask: 0) }
                return session.snapshot().candidates.map(\.text)
            }
            func deploy() throws {
                service.redeploy(invalidateGeneratedSchema: true)
                try #require(service.waitUntilReady(timeout: 180))
                #expect(service.deploymentStatus == .succeeded)
            }
            let personal = ["table", "prism", "reverse"].map { "allinoneime_personal.\($0).bin" }
            func built() -> Set<String> { Set((try? FileManager.default.contentsOfDirectory(atPath: build.path)) ?? []) }

            let imported = try store.importDictionary(from: source, fuzzyPinyin: [])
            try deploy()
            #expect(try candidates("ceshiciku").contains("霁鸢星槎"))
            #expect(built().isSuperset(of: personal), "\(built())")
            try store.removeDictionary(named: imported.name, fuzzyPinyin: [])
            #expect(built().isDisjoint(with: personal), "\(built())")
            try deploy()
            #expect(built().isDisjoint(with: personal), "\(built())")
            #expect(try candidates("nihao").contains("你好"))
            #expect(try !candidates("ceshiciku").contains("霁鸢星槎"))
        },
    ]
}

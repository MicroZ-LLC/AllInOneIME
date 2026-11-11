import Foundation
import Testing
@testable import AllInOneIMECore

/// What librime is to compile again of what this app wrote (`PersonalDictionaryStore.datePatches`, before each deployment):
/// a source it wrote in the second librime recorded for it is dated the next, so librime doesn't take it for unchanged;
/// what librime compiled is never removed (a deployment under way may be reading it).
struct PatchDatesTests {
    let user = FileManager.default.temporaryDirectory.appendingPathComponent("patch-dates-\(UUID().uuidString)")
    var build: URL { user.appendingPathComponent("build") }
    /// A whole second, librime's time for a source.
    let recorded = 1_794_379_400

    /// `name` in the user folder, with `text`, dated `at`.
    func source(_ name: String, _ text: String, at: TimeInterval) throws -> URL {
        let url = user.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: at)], ofItemAtPath: url.path)
        return url
    }

    /// What librime compiled into `build/`, as its `__build_info` records `id`'s time, compiled at `at`.
    func compiled(_ name: String, recording id: String, _ time: Int, at: TimeInterval) throws {
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        let text = "__build_info:\n  rime_version: 1.16.1\n  timestamps:\n    default: 1794369321\n    \(id): \(time)\n"
            + "    rime_ice.schema: 1794369320\nschema:\n  schema_id: x\n"
        let url = build.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: at)], ofItemAtPath: url.path)
    }

    func date(_ url: URL) throws -> TimeInterval {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date).timeIntervalSince1970
    }

    @Test func aPatchWrittenInTheSecondLibrimeRecordedIsDatedTheNext() throws {
        defer { try? FileManager.default.removeItem(at: user) }
        let base = TimeInterval(recorded)
        let patch = try source("rime_ice.custom.yaml", FuzzyPinyin.marker + "\npatch:\n", at: base + 0.7)
        try compiled("rime_ice.schema.yaml", recording: "rime_ice.custom", recorded, at: base + 0.4)
        try PersonalDictionaryStore.datePatches(userDirectory: user, since: nil)
        #expect(try date(patch) == base + 1)
        #expect(FileManager.default.fileExists(atPath: build.appendingPathComponent("rime_ice.schema.yaml").path))
        // Dated once: librime records the next second when it compiles it, and until then it differs already.
        try PersonalDictionaryStore.datePatches(userDirectory: user, since: nil)
        #expect(try date(patch) == base + 1)
    }

    @Test func oneLibrimeCompiledOrSeesChangedIsLeftAlone() throws {
        defer { try? FileManager.default.removeItem(at: user) }
        let base = TimeInterval(recorded)
        // Written before it was compiled, and no deployment since: what librime compiled has it.
        let compiledAlready = try source("rime_ice.custom.yaml", FuzzyPinyin.marker + "\npatch:\n", at: base + 0.2)
        try compiled("rime_ice.schema.yaml", recording: "rime_ice.custom", recorded, at: base + 0.4)
        // Written in another second than librime recorded: it sees the change itself.
        let otherSecond = try source("double_pinyin_flypy.custom.yaml", FuzzyPinyin.marker + "\npatch:\n", at: base + 1.5)
        try compiled("double_pinyin_flypy.schema.yaml", recording: "double_pinyin_flypy.custom", recorded, at: base + 0.4)
        // The user's own patch (not this app's first line).
        let users = try source("bopomofo.custom.yaml", "patch:\n  menu/page_size: 9\n", at: base + 0.7)
        try compiled("bopomofo.schema.yaml", recording: "bopomofo.custom", recorded, at: base + 0.4)
        // Not compiled yet: librime compiles it anyway.
        let notCompiled = try source("double_pinyin.custom.yaml", FuzzyPinyin.marker + "\npatch:\n", at: base + 0.7)
        try PersonalDictionaryStore.datePatches(userDirectory: user, since: nil)
        #expect(try date(compiledAlready) == base + 0.2)
        #expect(try date(otherSecond) == base + 1.5)
        #expect(try date(users) == base + 0.7)
        #expect(try date(notCompiled) == base + 0.7)
    }

    /// One written while the last deployment ran (`since`, its start) may have been read before it was written, though
    /// what was compiled is newer: dated the next second too; with `all`, one written before as well.
    @Test func oneWrittenWhileTheLastDeploymentRanOrAllAreDated() throws {
        defer { try? FileManager.default.removeItem(at: user) }
        let base = TimeInterval(recorded)
        let patch = try source("rime_ice.custom.yaml", FuzzyPinyin.marker + "\npatch:\n", at: base + 0.3)
        try compiled("rime_ice.schema.yaml", recording: "rime_ice.custom", recorded, at: base + 0.4)
        try PersonalDictionaryStore.datePatches(userDirectory: user, since: Date(timeIntervalSince1970: base + 0.5))
        #expect(try date(patch) == base + 0.3)
        try PersonalDictionaryStore.datePatches(userDirectory: user, since: Date(timeIntervalSince1970: base + 0.1))
        #expect(try date(patch) == base + 1)

        let list = try source("default.custom.yaml", PinyinScheme.schemaListPatch(["rime_ice", "bopomofo"]), at: base + 0.2)
        try compiled("default.yaml", recording: "default.custom", recorded, at: base + 0.4)
        try PersonalDictionaryStore.datePatches(userDirectory: user, since: nil)
        #expect(try date(list) == base + 0.2)
        try PersonalDictionaryStore.datePatches(userDirectory: user, since: nil, all: true)
        #expect(try date(list) == base + 1)
    }

    /// Writing the patch leaves what librime compiled (a deployment may be reading it right then).
    @Test func writingThePatchLeavesWhatLibrimeCompiled() throws {
        defer { try? FileManager.default.removeItem(at: user) }
        let schema = user.appendingPathComponent("shared/rime_ice.schema.yaml")
        try FileManager.default.createDirectory(at: schema.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("schema:\n  schema_id: rime_ice\nspeller:\n  algebra:\n    - abbrev/^([a-z]).+$/$1/\n".utf8).write(to: schema)
        for name in ["rime_ice.schema.yaml", "double_pinyin_flypy.schema.yaml"] {
            try compiled(name, recording: "rime_ice.custom", recorded, at: TimeInterval(recorded))
        }
        #expect(try FuzzyPinyin.apply(["n-l"], scheme: .xiaohe, schema: schema, userDir: user) == .written)
        #expect(try FuzzyPinyin.apply([], scheme: .full, schema: schema, userDir: user) == .removed)
        for name in ["rime_ice.schema.yaml", "double_pinyin_flypy.schema.yaml"] {
            #expect(FileManager.default.fileExists(atPath: build.appendingPathComponent(name).path), "\(name)")
        }
    }

    @Test func theTimeLibrimeRecordedIsRead() throws {
        defer { try? FileManager.default.removeItem(at: user) }
        try compiled("rime_ice.schema.yaml", recording: "rime_ice.custom", 42, at: 0)
        let url = build.appendingPathComponent("rime_ice.schema.yaml")
        #expect(PersonalDictionaryStore.recordedTime(of: "rime_ice.custom", in: url) == 42)
        #expect(PersonalDictionaryStore.recordedTime(of: "rime_ice.schema", in: url) == 1_794_369_320)
        #expect(PersonalDictionaryStore.recordedTime(of: "bopomofo.custom", in: url) == nil)
        try Data("schema:\n  schema_id: x\n".utf8).write(to: url)
        #expect(PersonalDictionaryStore.recordedTime(of: "rime_ice.custom", in: url) == nil)
    }
}

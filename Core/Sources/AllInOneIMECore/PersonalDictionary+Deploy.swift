import Foundation

extension PersonalDictionaryStore {
    // MARK: Deploying what was written

    /// The Rime sources this app writes in the user folder, each with what librime compiles of it into `build/` and the
    /// first line it has when it is this app's: the schema list (`PinyinScheme.applySchemaList`), rime-ice's patch and
    /// each other way of typing's (`PinyinScheme.others`).
    static func compiledSources(_ userDirectory: URL) -> [(source: URL, compiled: URL, marker: String)] {
        let build = userDirectory.appendingPathComponent("build", isDirectory: true)
        let schemas = [PinyinScheme.fullSchema] + PinyinScheme.others.map(\.schema)
        return [(userDirectory.appendingPathComponent("default.custom.yaml"), build.appendingPathComponent("default.yaml"),
                 PinyinScheme.schemaListMarker)]
            + schemas.map { (userDirectory.appendingPathComponent("\($0).custom.yaml"), build.appendingPathComponent("\($0).schema.yaml"),
                             FuzzyPinyin.marker) }
    }

    /// Readies this app's Rime sources for a deployment about to start, while librime isn't deploying (`RimeService`
    /// calls it right before): librime compiles a source again when its time differs from the one it recorded in what it
    /// compiled (`__build_info`), in whole seconds, so a source this app wrote in the second librime recorded for it (a
    /// quick import or fuzzy pinyin toggle, or one written while that deployment ran) would be taken for unchanged. Each
    /// written since `since` (the last deployment's start; nil: since what was compiled of it) and in that second is dated
    /// the next one; with `all`, each in that second, written since or not (a redeploy asked to compile them all again).
    /// What librime compiled stays: a source not compiled yet, or the user's own (without this app's first line), is left
    /// as it is. Removing the compiled schema instead, when the patch was written, raced with a deployment under way: its
    /// dictionary found no schema to read the spellings from ("error loading prism definition", "failed to compile").
    /// Throws when a source's time can't be set.
    public static func datePatches(userDirectory: URL, since: Date?, all: Bool = false) throws {
        let fm = FileManager.default
        for (source, compiled, marker) in compiledSources(userDirectory) {
            guard let attributes = try? fm.attributesOfItem(atPath: source.path),
                  attributes[.type] as? FileAttributeType == .typeRegular, let written = attributes[.modificationDate] as? Date,
                  let built = try? fm.attributesOfItem(atPath: compiled.path),
                  built[.type] as? FileAttributeType == .typeRegular, let builtAt = built[.modificationDate] as? Date,
                  let recorded = recordedTime(of: source.deletingPathExtension().lastPathComponent, in: compiled),
                  let handle = try? FileHandle(forReadingFrom: source) else { continue }
            let head = (try? handle.read(upToCount: marker.utf8.count + 1)) ?? Data()
            try? handle.close()
            guard head == Data((marker + "\n").utf8) else { continue }
            let second = written.timeIntervalSince1970.rounded(.down)
            guard second == Double(recorded), all || written > min(builtAt, since ?? builtAt) else { continue }
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: second + 1)], ofItemAtPath: source.path)
        }
    }

    /// The time librime recorded for the source `id` ("rime_ice.custom") in what it compiled (`compiled`'s
    /// `__build_info/timestamps`, at its top); nil when it records none.
    static func recordedTime(of id: String, in compiled: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: compiled) else { return nil }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 16 * 1024)) ?? Data(), as: UTF8.self)
        var section = ""
        for line in head.split(separator: "\n") {
            let indent = line.prefix(while: { $0 == " " }).count
            let content = line.trimmingCharacters(in: .whitespaces)
            switch indent {
            case 0: guard content == "__build_info:" else { return nil }
            case 2: section = content
            default:
                guard section == "timestamps:", let colon = content.lastIndex(of: ":") else { continue }
                let key = content[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                if key == id { return Int(content[content.index(after: colon)...].trimmingCharacters(in: .whitespaces)) }
            }
        }
        return nil
    }
}

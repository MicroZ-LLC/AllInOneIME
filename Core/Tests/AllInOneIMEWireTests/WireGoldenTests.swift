import AllInOneIMECore
@testable import AllInOneIMEWire
import Foundation
import Testing

/// The goldens (§10, WireGoldens/*.jsonl) replayed against the server: a scripted provider, a manual clock and a task
/// runner that runs until idle after each `>` line. `WIRE_WRITE_GOLDENS=1` writes them again from `GoldenScenarios`.
struct WireGoldenTests {
    /// The goldens in the test bundle.
    static var goldens: URL {
        Bundle.module.url(forResource: "WireGoldens", withExtension: nil)!
    }

    /// The goldens in the package's sources, where `WIRE_WRITE_GOLDENS=1` writes them.
    static var sourceGoldens: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("WireGoldens")
    }

    static let names = GoldenScenarios.all.map(\.name)

    @Test(arguments: names)
    func replays(_ name: String) throws {
        let url = Self.goldens.appendingPathComponent(name + ".jsonl")
        let transcript = try WireTranscript(contentsOf: url)
        do {
            try GoldenReplayer(transcript: transcript, directory: Self.goldens).run()
        } catch {
            Issue.record("\(name).jsonl \(error)")
        }
    }

    /// Each golden is what its scenario writes: the `>` lines a client with that document would send, too.
    @Test(arguments: names)
    func scenarioWritesTheGolden(_ name: String) throws {
        let write = try #require(GoldenScenarios.all.first { $0.name == name }?.write)
        let written = try write(Self.goldens)
        if ProcessInfo.processInfo.environment["WIRE_WRITE_GOLDENS"] == "1" {
            try Data(written.utf8).write(to: Self.sourceGoldens.appendingPathComponent(name + ".jsonl"))
            return
        }
        let url = Self.goldens.appendingPathComponent(name + ".jsonl")
        let file = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        let (a, b) = (file.split(separator: "\n", omittingEmptySubsequences: false), written.split(separator: "\n", omittingEmptySubsequences: false))
        if let i = zip(a, b).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
            Issue.record("\(name).jsonl line \(i + 1) differs from its scenario's:\n  file:     \(a[i])\n  scenario: \(b[i])")
        } else if a.count != b.count {
            Issue.record("\(name).jsonl has \(a.count) lines, its scenario writes \(b.count)")
        }
    }

    @Test func everyGoldenHasAScenario() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.goldens.path)
            .filter { $0.hasSuffix(".jsonl") }.map { String($0.dropLast(6)) }
        #expect(Set(files) == Set(Self.names))
    }

    /// The spec's own golden (§10), as far as the Composer agrees with it: the handshake, plain typing, the draft's
    /// start, the panel, and the commit of the version picked.
    @Test func notepadImproveFollowsTheSpec() throws {
        let transcript = try WireTranscript(contentsOf: Self.goldens.appendingPathComponent("notepad-improve.jsonl"))
        let expected = transcript.steps.compactMap { if case let .expect(v, _) = $0 { v } else { nil } }
        #expect(expected.first == (try JSONValue(parsing: """
            {"v":1,"id":1,"re":1,"type":"welcome","version":1,"engine":"$any","enginePid":"$any","capabilities":[],"limits":{"contextBefore":32,"selection":10002}}
            """)))
        #expect(expected[1] == (try JSONValue(parsing: #"{"id":2,"re":4,"type":"result"}"#)))
        #expect(expected.contains(try JSONValue(parsing: #"""
            {"id":6,"re":8,"type":"result","handled":true,"outputs":[{"op":"composition","text":"@","caret":1,"segments":[{"from":0,"to":1,"style":"draft"}]},{"op":"panel","shown":true}]}
            """#)))
        let commit = try #require(expected.first { $0.compact.contains(#""op":"commit""#) })
        #expect(commit.compact.contains(#"{"op":"commit","text":"Hello."}"#))
        #expect(commit.compact.contains(#"{"op":"panel","shown":false}"#))
    }
}

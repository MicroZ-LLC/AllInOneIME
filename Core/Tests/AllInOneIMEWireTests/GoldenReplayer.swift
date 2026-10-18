import AllInOneIMECore
@testable import AllInOneIMEWire
import Foundation

/// Replays a golden transcript (§10) against an in-process server: each `>` frame is sent, the engine runs until idle,
/// and what it sent must be the `<` lines that follow, in order, and nothing else.
struct GoldenReplayer {
    var transcript: WireTranscript
    /// Where the transcript's fixtures are (`#! provider fixtures/…`).
    var directory: URL

    struct Failure: Error, CustomStringConvertible {
        var line: Int
        var message: String
        var description: String { "line \(line): \(message)" }
    }

    /// The setup directives: the provider fixture and the input language.
    static func setup(_ transcript: WireTranscript, directory: URL) throws -> (ScriptedProvider.Fixture?, Language) {
        var fixture: ScriptedProvider.Fixture?
        var language = Language.english
        for case let .directive(text, line) in transcript.steps {
            let words = text.split(separator: " ").map(String.init)
            switch words.first {
            case "provider":
                guard words.count == 2 else { throw Failure(line: line, message: "#! provider <file>") }
                let url = directory.appendingPathComponent(words[1])
                fixture = try WireJSON.decode(ScriptedProvider.Fixture.self, from: Data(contentsOf: url))
            case "inputLanguage":
                guard words.count == 2, let named = Language(goldenName: words[1]) else {
                    throw Failure(line: line, message: "#! inputLanguage <language>")
                }
                language = named
            default:
                break
            }
        }
        return (fixture, language)
    }

    /// A `>` line's frame as sent: its `v` added, and fields whose value is "$any" (a client's own: its pid, a window
    /// handle) left out.
    static func outgoing(_ value: JSONValue) -> Data {
        try! WireJSON.encode(withoutWildcards(WireTranscript.outgoing(value)))
    }

    static func withoutWildcards(_ value: JSONValue) -> JSONValue {
        switch value {
        case let .object(fields):
            return .object(fields.filter { $0.value != .any }.mapValues(withoutWildcards))
        case let .array(items):
            return .array(items.map(withoutWildcards))
        default:
            return value
        }
    }

    /// Runs it; throws at the first difference.
    func run() throws {
        let (fixture, language) = try Self.setup(transcript, directory: directory)
        let engine = TestEngine(fixture: fixture, inputLanguage: language)
        var connection = engine.server.connect(WirePeer())
        var pending: [(data: Data, after: Int)] = []
        var lastLine = 0

        func unexpected(_ line: Int) throws {
            guard let first = pending.first else { return }
            throw Failure(line: line, message: "the engine sent a frame no line expects (after line \(first.after)): "
                + String(decoding: first.data, as: UTF8.self))
        }

        for step in transcript.steps {
            lastLine = step.line
            switch step {
            case let .send(value, line):
                try unexpected(line)
                guard let id = connection else { throw Failure(line: line, message: "not connected") }
                pending += engine.send(Self.outgoing(value), on: id).map { ($0, line) }
            case let .expect(expected, line):
                guard !pending.isEmpty else { throw Failure(line: line, message: "the engine sent nothing") }
                let data = pending.removeFirst().data
                let actual = try JSONValue(parsing: String(decoding: data, as: UTF8.self))
                if let mismatch = WireTranscript.mismatch(expected: expected, actual: actual) {
                    throw Failure(line: line, message: "\(mismatch)\n  got: \(actual.compact)")
                }
            case let .directive(text, line):
                let words = text.split(separator: " ").map(String.init)
                switch words.first {
                case "provider", "inputLanguage", "keys":
                    continue
                case "connect":
                    try unexpected(line)
                    connection = engine.server.connect(WirePeer())
                case "disconnect":
                    try unexpected(line)
                    if let id = connection { engine.server.disconnect(id) }
                    engine.runUntilIdle()
                    connection = nil
                case "closed":
                    try unexpected(line)
                    guard let id = connection, !engine.server.isOpen(id) else {
                        throw Failure(line: line, message: "the engine didn't close the connection")
                    }
                    engine.server.disconnect(id)
                    connection = nil
                default:
                    try unexpected(line)
                    guard let id = connection else { throw Failure(line: line, message: "not connected") }
                    guard engine.server.perform(text, on: id) else {
                        throw Failure(line: line, message: "unknown directive \"\(text)\"")
                    }
                    engine.runUntilIdle()
                    pending += engine.takePushes(for: id).map { ($0, line) }
                }
            }
        }
        try unexpected(lastLine + 1)
    }
}

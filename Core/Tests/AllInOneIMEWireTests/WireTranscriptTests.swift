@testable import AllInOneIMEWire
import Foundation
import Testing

/// How a transcript is read, whatever the checkout made of its line ends.
struct WireTranscriptTests {
    /// A golden checked out or exported with CRLF (core.autocrlf on Windows) reads as the same steps as with LF: Swift
    /// takes "\r\n" for one Character, so split on "\n" alone it was one line, a comment, and no steps at all.
    @Test(arguments: WireGoldenTests.names)
    func aGoldenWithCRLFReadsAsWithLF(_ name: String) throws {
        let url = WireGoldenTests.goldens.appendingPathComponent(name + ".jsonl")
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
        let lf = try WireTranscript(text)
        let crlf = try WireTranscript(text.replacingOccurrences(of: "\n", with: "\r\n"))
        #expect(lf.steps.contains { if case .send = $0 { true } else { false } })
        #expect(crlf.steps == lf.steps)
    }

    @Test func linesEndEitherWay() throws {
        let transcript = try WireTranscript("# a comment\r\n#! connect\r\n> {\"type\":\"ping\"}\n< {\"type\":\"pong\"}\r\n\r\n")
        #expect(transcript.steps == [
            .directive("connect", line: 2),
            .send(.object(["type": .string("ping")]), line: 3),
            .expect(.object(["type": .string("pong")]), line: 4),
        ])
    }
}

import Foundation
import Testing

/// Every AppleScript `NotesBridge` sends is wrapped in `with timeout of N seconds … end timeout`, so a Notes that never
/// answers ends the Apple event with an error instead of holding the serial queue (and every note call behind it). Read
/// from the input method's source: the executable target can't be linked into a test.
struct NotesBridgeTimeoutTests {
    static let source: String = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent("Sources/AllInOneIME/NotesBridge.swift"), encoding: .utf8)) ?? ""
    }()

    /// The text of each `"""` script literal in the file.
    static var scripts: [String] {
        source.components(separatedBy: "\"\"\"").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
    }

    @Test func everyScriptWrapsItsNotesCallsInATimeout() throws {
        let scripts = try #require(Self.scripts.isEmpty ? nil : Self.scripts)
        #expect(scripts.count >= 3)
        for script in scripts {
            #expect(script.contains("with timeout of \\(appleEventTimeout) seconds"), "no timeout in: \(script.prefix(60))")
            #expect(script.contains("end timeout"))
            // The Notes call is inside the timeout block, not before it.
            if let tell = script.range(of: "tell application \"Notes\""), let timeout = script.range(of: "with timeout of") {
                #expect(timeout.lowerBound < tell.lowerBound)
            }
        }
    }

    @Test func theTimeoutIsAFewSeconds() throws {
        let match = try #require(Self.source.firstMatch(of: /static let appleEventTimeout = (\d+)/))
        let seconds = try #require(Int(match.output.1))
        #expect((1...120).contains(seconds))
    }
}

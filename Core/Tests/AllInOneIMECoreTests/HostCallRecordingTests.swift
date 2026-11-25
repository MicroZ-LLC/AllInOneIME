import Foundation
import Testing
import AllInOneIMECore

/// The developer's recording of a field's text-input calls (`HostCallRecording`): typed text only as lengths unless it
/// is asked for, everything else as the field told it, and every line read back.
struct HostCallRecordingTests {
    let redacted = HostCallRecording(keepsText: false)
    let kept = HostCallRecording(keepsText: true)

    @Test func theHeaderSaysWhetherTextIsKept() throws {
        let header = try #require(HostCallRecording.parse(redacted.header()))
        #expect(header.kind == .header && header.name == "host-calls")
        #expect(header.fields["text"] == .bool(false) && header.fields["v"] == .number(1))
        #expect(HostCallRecording.parse(kept.header())?.fields["text"] == .bool(true))
    }

    /// What a field holds or is given is its length only, unless the recording keeps text; ranges as told, NSNotFound
    /// as null.
    @Test func textIsALengthUnlessKept() throws {
        let fields: [String: HostCallRecording.Field] = ["range": .range(location: 3, length: 4), "answer": .text("secret 你好")]
        let line = redacted.call("attributedSubstring", at: 1.23456, fields)
        #expect(!line.contains("secret") && !line.contains("你好"), "\(line)")
        let read = try #require(HostCallRecording.parse(line))
        #expect(read.kind == .call && read.name == "attributedSubstring" && read.time == 1.235)
        #expect(read.range("range") == 3..<7 && read.length("answer") == 9 && read.string("answer") == nil)
        let keptLine = try #require(HostCallRecording.parse(kept.call("attributedSubstring", at: 0, fields)))
        #expect(keptLine.string("answer") == "secret 你好" && keptLine.length("answer") == 9)
        let none = try #require(HostCallRecording.parse(redacted.call("markedRange", at: 0, [
            "answer": .range(location: NSNotFound, length: 0), "text": .text(nil),
        ])))
        #expect(none.fields["answer"] == .null && none.range("answer") == nil && none.length("text") == nil)
    }

    /// A key that types a character is "text" and its length, no key code; named keys and shortcuts are kept.
    @Test func aTypedKeyIsOnlyItsLength() throws {
        let letter = KeyEvent(keyCode: 0x00, characters: "a")
        let line = redacted.event("keyDown", at: 0, redacted.key(letter))
        let read = try #require(HostCallRecording.parse(line))
        #expect(read.string("key") == "text" && read.length("chars") == 1 && read.fields["code"] == nil, "\(line)")
        #expect(!line.contains("\"a\""), "\(line)")
        let keptRead = try #require(HostCallRecording.parse(kept.event("keyDown", at: 0, kept.key(letter))))
        #expect(keptRead.string("chars") == "a" && keptRead.number("code") == 0)

        let enter = try #require(HostCallRecording.parse(redacted.event("keyDown", at: 0, redacted.key(FakeKeys.enter))))
        #expect(enter.string("key") == "enter" && enter.number("code") == Double(VirtualKey.returnKey))
        let paste = KeyEvent(keyCode: 0x09, characters: "v", charactersIgnoringModifiers: "v", modifiers: .command)
        let shortcut = try #require(HostCallRecording.parse(redacted.event("keyDown", at: 0, redacted.key(paste))))
        #expect(shortcut.string("key") == "character" && shortcut.string("chars") == "v" && shortcut.string("mods") == "command")
        let capital = KeyEvent(keyCode: 0x00, characters: "A", modifiers: [.shift, .leftShift])
        let shifted = try #require(HostCallRecording.parse(redacted.event("keyDown", at: 0, redacted.key(capital))))
        #expect(shifted.string("key") == "text" && shifted.string("mods") == "shift" && shifted.string("chars") == nil)
    }

    @Test func rectsPointsAndNamesAsTold() throws {
        let line = redacted.call("firstRect", at: 2, [
            "range": .range(location: 0, length: 0), "answer": .rect(x: 10, y: 20.5, width: 1, height: 18),
            "app": .name("com.example.app"), "point": .point(x: 1, y: 2), "count": .int(3), "none": .none,
        ])
        let read = try #require(HostCallRecording.parse(line))
        #expect(read.fields["answer"] == .array([.number(10), .number(20.5), .number(1), .number(18)]))
        #expect(read.string("app") == "com.example.app" && read.number("count") == 3 && read.fields["none"] == .null)
        #expect(HostCallRecording.parse("not json") == nil && HostCallRecording.parse("{\"x\":1}") == nil)
    }
}

/// Keys the tests above name.
private enum FakeKeys {
    static let enter = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r")
}

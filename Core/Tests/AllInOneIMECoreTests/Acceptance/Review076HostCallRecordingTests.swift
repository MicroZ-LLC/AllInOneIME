import Foundation
import Testing
import AllInOneIMECore

// Reproductions for the 0.7.6 review's items on the developer's IMK call recorder (`HostCallRecording`, off unless a
// developer turns it on), written from the review's text by the independent test author (AGENTS.md rule 20):
//  4. A rect or a point with a number that isn't finite (`NSRect.null`'s infinite origin, a NaN an app answers
//     `firstRect` with) takes the process down while it is recorded: `JSONSerialization` raises an Objective-C
//     exception for it, which `try?` doesn't catch (on Linux it throws, and the whole line is lost as "{}").
//  5. A dead key (⌥E, AZERTY's ^: a key down whose `characters` are empty) is recorded with its hardware key code in a
//     recording that keeps no text, though it is typed text (which accent) as much as the letter after it.
//  6. Reading a recording back traps on a malformed range: a location or length no `Int` holds (`1e100`), a negative
//     length, or two whose sum overflows.
//
// Items 4 and 6 end the process where they happen, so each runs in a child process (Swift Testing's exit test): the
// test fails with the child's crash instead of taking the test run down, and passes once the child exits cleanly.

struct Review076HostCallRecordingTests {
    // MARK: 4. Numbers that aren't finite

    /// Item 4. A rect that isn't finite is recorded without ending the process, and the line still reads back as the call
    /// it was, its other fields kept (the rect itself as the implementer sees fit: `null`, as a range NSNotFound tells,
    /// is the format's way of "nothing told"). (Fails today on the Mac: the child process dies of an uncaught
    /// NSInvalidArgumentException, "Invalid number value (infinite) in JSON write"; on Linux the line is "{}".)
    @Test func aRectThatIsNotFiniteIsRecordedWithoutCrashing() async {
        await #expect(processExitsWith: .success, "recording NSRect.null's infinite origin") {
            let recording = HostCallRecording(keepsText: false)
            // NSRect.null as AppKit gives it: an infinite origin, no size.
            let line = recording.call("firstRect", at: 1, [
                "range": .range(location: 3, length: 0),
                "answer": .rect(x: .infinity, y: .infinity, width: 0, height: 0),
            ])
            guard let read = HostCallRecording.parse(line), read.kind == .call, read.name == "firstRect",
                  read.range("range") == 3..<3 else { exit(EXIT_FAILURE) }
        }
    }

    /// Item 4, the other numbers a field answers with: a NaN in a rect, a point that isn't finite. (Fails today as
    /// above.)
    @Test func aNaNOrAnInfinitePointIsRecordedWithoutCrashing() async {
        await #expect(processExitsWith: .success, "recording a NaN rect and an infinite point") {
            let recording = HostCallRecording(keepsText: false)
            let lines = [
                recording.call("firstRect", at: 1, ["answer": .rect(x: 0, y: .nan, width: 10, height: 18), "count": .int(2)]),
                recording.call("characterIndex", at: 1, ["point": .point(x: -.infinity, y: 4), "count": .int(2)]),
            ]
            for line in lines {
                guard let read = HostCallRecording.parse(line), read.number("count") == 2 else { exit(EXIT_FAILURE) }
            }
        }
    }

    // MARK: 5. A dead key

    /// Item 5. A dead key as the Mac's key down tells it (AppKit gives a dead key neither `characters` nor
    /// `charactersIgnoringModifiers`: both are ""; ⌥E on a U.S. keyboard, the ^ key of a French one, ⇧^ for ¨) in a
    /// recording that keeps no text: no key code, as for any key that types (the code tells which accent was typed); the
    /// recording that keeps text has it. (Fails today: with no characters it is taken for a key that types nothing, and
    /// its hardware key code is recorded.)
    @Test(arguments: [
        KeyEvent(keyCode: 0x0E, characters: "", charactersIgnoringModifiers: "", modifiers: [.option, .leftOption]),
        KeyEvent(keyCode: 0x21, characters: "", charactersIgnoringModifiers: ""),
        KeyEvent(keyCode: 0x21, characters: "", charactersIgnoringModifiers: "", modifiers: [.shift, .leftShift]),
    ])
    func aDeadKeyIsRecordedWithoutItsKeyCode(_ deadKey: KeyEvent) throws {
        // The premise: the key down as AppKit tells a dead key, nothing in either text.
        try #require(deadKey.characters.isEmpty && deadKey.charactersIgnoringModifiers.isEmpty)
        let redacted = HostCallRecording(keepsText: false)
        let line = redacted.event("keyDown", at: 0, redacted.key(deadKey))
        let read = try #require(HostCallRecording.parse(line))
        #expect(read.fields["code"] == nil && read.number("code") == nil && !line.contains("\"code\""),
                "a dead key's hardware key code is in a recording that keeps no text: \(line)")
        #expect(read.string("chars") == nil, "its characters are recorded: \(line)")

        // The same key marked as the core marks one (`KeyEvent.isDeadKey`, its accent in `characters`).
        var marked = deadKey
        marked.isDeadKey = true
        marked.characters = "´"
        let markedLine = redacted.event("keyDown", at: 0, redacted.key(marked))
        let markedRead = try #require(HostCallRecording.parse(markedLine))
        #expect(markedRead.fields["code"] == nil && !markedLine.contains("\"code\"") && markedRead.string("chars") == nil
                    && !markedLine.contains("´"),
                "a key marked dead is recorded with its code or accent: \(markedLine)")

        // Asked for in so many words, it is kept.
        let kept = HostCallRecording(keepsText: true)
        let keptRead = try #require(HostCallRecording.parse(kept.event("keyDown", at: 0, kept.key(deadKey))))
        #expect(keptRead.number("code") == Double(deadKey.keyCode), "the recording that keeps text has the key code")
    }

    /// The control (passes today): the keys that type nothing keep their names and codes, and a shortcut its letter.
    @Test func keysThatTypeNothingKeepTheirCodes() throws {
        let redacted = HostCallRecording(keepsText: false)
        let enter = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r")
        let read = try #require(HostCallRecording.parse(redacted.event("keyDown", at: 0, redacted.key(enter))))
        #expect(read.string("key") == "enter" && read.number("code") == Double(VirtualKey.returnKey))
        let paste = KeyEvent(keyCode: 0x09, characters: "v", charactersIgnoringModifiers: "v", modifiers: .command)
        let shortcut = try #require(HostCallRecording.parse(redacted.event("keyDown", at: 0, redacted.key(paste))))
        #expect(shortcut.string("chars") == "v" && shortcut.number("code") == 9)
    }

    // MARK: 6. Malformed ranges read back

    /// Item 6. A recording's line whose range no `Range<Int>` holds reads back as no range (nil), never a trap: a
    /// location or a length past `Int`, a negative length, a negative location, two whose sum overflows, a fraction's
    /// stay the reader's to refuse or round. (Fails today: `Int(1e100)` and a range whose end is before its start trap,
    /// and the child process dies of it.)
    @Test(arguments: ["[1e100,0]", "[0,1e100]", "[5,-9]", "[9.2e18,9.2e18]", "[-1e100,3]"])
    func aMalformedRangeReadsBackAsNone(_ range: String) async {
        await #expect(processExitsWith: .success, "reading back the range \(range)") { [range] in
            guard let line = HostCallRecording.parse("{\"call\":\"selectedRange\",\"t\":0.5,\"answer\":\(range)}") else {
                exit(EXIT_FAILURE)
            }
            // Reaching the end without a trap is the point; none of these is a range.
            exit(line.range("answer") == nil ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    /// Item 6, a text's length (`{"len": n}`) no `Int` holds: no length (nil), never a trap. (Fails today: `Int(1e100)`.)
    @Test func aMalformedLengthReadsBackAsNone() async {
        await #expect(processExitsWith: .success, "reading back the length 1e100") {
            guard let line = HostCallRecording.parse("{\"call\":\"insertText\",\"t\":0.5,\"text\":{\"len\":1e100}}") else {
                exit(EXIT_FAILURE)
            }
            exit(line.length("text") == nil ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    /// The control (passes today): the ranges a recording writes still read back.
    @Test func wellFormedRangesStillReadBack() throws {
        let line = try #require(HostCallRecording.parse("{\"call\":\"selectedRange\",\"t\":0.5,\"answer\":[3,4],\"none\":null}"))
        #expect(line.range("answer") == 3..<7 && line.range("none") == nil && line.range("missing") == nil)
    }
}

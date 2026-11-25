import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Foundation
import Testing

/// The developer's IMK call recorder (`IMKRecorder`): off unless its variable is set, and then every call of the field
/// and its answer in the host-call recording's lines, typed text as lengths unless its own variable says to keep it.
@MainActor
struct IMKRecorderTests {
    final class Lines: @unchecked Sendable {
        var all: [String] = []
        var text: String { all.joined(separator: "\n") }
    }

    func recorder(_ environment: [String: String]) -> (IMKRecorder, Lines) {
        let lines = Lines()
        return (IMKRecorder(environment: environment, sink: { lines.all.append($0) }), lines)
    }

    func field(_ profile: HostProfile, _ markup: String) throws -> ProfiledTextClient {
        let text = try HostText(markup: markup)
        return ProfiledTextClient(profile, text: text.text, selection: text.selection, marked: text.marked)
    }

    /// Off by default: the client is the field's own, and nothing is written.
    @Test func offUnlessItsVariableIsSet() throws {
        let client = try field(.nstextview, "Hi|")
        for environment in [[:], [IMKRecorder.switchVariable: ""], [IMKRecorder.switchVariable: "0"]] {
            let (recorder, lines) = recorder(environment)
            #expect(!recorder.isOn && recorder.recording(client) === client && recorder.file == nil)
            recorder.event("activate", client: client)
            #expect(lines.all.isEmpty)
        }
    }

    /// On: the reads a key makes (`FieldTextReading`), what goes in and what is marked, each a line with its answer;
    /// the field's text and what was put in only as lengths.
    @Test func everyCallWithItsAnswerAndNoTypedText() throws {
        let (recorder, lines) = recorder([IMKRecorder.switchVariable: "1"])
        let client = try field(.chromium, "Hello wor|ld")
        let recording = try #require(recorder.recording(client))
        #expect(recorder.recording(client) === recording, "one proxy per field: the controller tells fields apart by it")
        let read = FieldTextReading.read(from: recording, before: 1500, after: 200, purpose: "test", secureInputActive: { false },
                                         isTerminal: { _ in false })
        #expect(read == FieldText(before: "Hello wor", after: "ld"), "the field read through the proxy as it is")
        recording.setMarkedText(" ", selectionRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        recording.insertText("你好", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(client.doc == "Hello wor你好ld")
        for secret in ["Hello", "wor", "ld\"", "你好"] { #expect(!lines.text.contains(secret), "\(secret) in \(lines.text)") }
        let parsed = lines.all.compactMap(HostCallRecording.parse)
        #expect(parsed.count == lines.all.count && parsed.first?.kind == .header && parsed.first?.fields["text"] == .bool(false))
        let calls = parsed.filter { $0.kind == .call }
        let counted = client.calls.filter { $0.key != "bundleIdentifier" }.values.reduce(0, +)
        #expect(calls.filter { $0.name != "bundleIdentifier" }.count == counted, "every call the field had, recorded: \(client.calls)")
        let substring = try #require(calls.first { $0.name == "attributedSubstring" && $0.length("answer") == 9 })
        #expect(substring.range("range") == 0..<9)
        #expect(calls.first { $0.name == "insertText" }?.length("text") == 2)
        #expect(calls.first { $0.name == "selectedRange" }?.range("answer") == 9..<9)
    }

    /// With the text variable set too, the text is kept: a session to turn into a scenario by hand.
    @Test func textOnlyWhenAskedFor() throws {
        let (recorder, lines) = recorder([IMKRecorder.switchVariable: "/dev/null", IMKRecorder.textVariable: "1"])
        let client = try field(.nstextview, "Hi Bob|")
        let recording = try #require(recorder.recording(client))
        _ = recording.attributedSubstring(from: NSRange(location: 0, length: 2))
        let call = try #require(lines.all.compactMap(HostCallRecording.parse).first { $0.name == "attributedSubstring" })
        #expect(call.string("answer") == "Hi")
    }

    /// A key down is recorded by kind and length, then whether it was taken; a named key by name.
    @Test func keysAndTheirAnswers() throws {
        let (recorder, lines) = recorder([IMKRecorder.switchVariable: "1"])
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
                                                characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 0x0C))
        let enter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
                                                  characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 0x24))
        recorder.event(key)
        recorder.event(key, handled: true)
        recorder.event(enter)
        let parsed = lines.all.compactMap(HostCallRecording.parse)
        #expect(parsed.map(\.name) == ["host-calls", "keyDown", "answered", "keyDown"])
        #expect(parsed[1].string("key") == "text" && parsed[1].length("chars") == 1 && parsed[1].fields["code"] == nil)
        #expect(parsed[2].fields["handled"] == .bool(true) && parsed[3].string("key") == "enter")
        #expect(!lines.text.contains("\"q\""))
    }

    /// A scenario replayed through the recorder's proxy: its calls recorded as a real app's session would be, one line
    /// each, the same as the field counted.
    @Test(arguments: [HostProfile.nstextview, .chromium, .webkit, .qt])
    func aReplayedScenarioIsRecorded(_ profile: HostProfile) throws {
        let (recorder, lines) = recorder([IMKRecorder.switchVariable: "1"])
        let scenario = try HostCase.parse(#"""
            NAME   pinyin typed and picked, recorded
            LANG   chinese
            TEXT   "Hi |"
            TYPE   nihao
            KEY    space
            EXPECT doc "Hi 你好"
            EXPECT nolost
            """#, source: "recorded")
        let replayer = HostReplayer(scenario, profile: profile, recorder: recorder)
        replayer.run()
        #expect(replayer.failures.isEmpty, "\(replayer.failures)")
        let calls = lines.all.compactMap(HostCallRecording.parse).filter { $0.kind == .call }
        #expect(calls.contains { $0.name == "insertText" && $0.length("text") == 2 }, "\(lines.text)")
        #expect(!lines.text.contains("你好") && !lines.text.contains("Hi "))
    }
}

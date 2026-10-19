import Foundation
import Testing
@testable import AllInOneIMECore

/// `MessageScript`, the AppleScript `@imessage` runs (moved with it from MessagingTests).
struct MessageScriptTests {
    /// The handle and the text are the script's arguments: nothing typed becomes AppleScript.
    @Test func theScriptTakesArgumentsNotText() throws {
        let text = "\" & (do shell script \"say hi\") & \"\nline 2"
        let handle = "+1 555 0100\" to buddy \"x"
        #expect(MessageScript.osascriptArguments(handle: handle, text: text) == ["-", handle, text])
        let script = MessageScript.iMessage
        #expect(script.hasPrefix("on run argv") && script.contains("item 1 of argv") && script.contains("item 2 of argv"))
        #expect(script.contains("send theText to participant theHandle of theAccount"))
        // A stand-in with the same start (no Messages): osascript hands the arguments back unchanged.
        let lines = script.components(separatedBy: "\n")
        let standIn = lines.prefix(3).joined(separator: "\n") + "\n\treturn theHandle & \"|\" & theText\nend run\n"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = MessageScript.osascriptArguments(handle: handle, text: text)
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(standIn.utf8))
        try input.fileHandleForWriting.close()
        let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0 && out.trimmingCharacters(in: .newlines) == handle + "|" + text)
    }
}

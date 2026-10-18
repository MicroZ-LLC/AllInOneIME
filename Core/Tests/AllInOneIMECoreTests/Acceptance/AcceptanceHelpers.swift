import Foundation
import Testing
@testable import AllInOneIMECore

// Helpers the acceptance tests share. They live here, with the acceptance tests, so that those don't depend on the
// implementation's own test files.

/// ⇧⏎: sends a follow-up (an @question conversation's next question, or a refine) once one is typed (0.6.4).
let acceptanceShiftReturn = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift)

/// 0.6.4 added a rule about live data (the weather, news, prices …) at the end of @question's system prompt, and only
/// there. The 0.6.3 goldens are what release 0.6.3 sent, without it. For an @question request `strip` takes it out
/// (it must be there exactly once) so that everything else is still compared byte for byte; any other request is left
/// as it is, so the rule leaking into another command's prompt makes it differ from its golden.
enum AcceptanceLiveRule {
    static let added = " " + Prompt.liveDataRule

    static func strip(_ text: String, question: Bool, sourceLocation: SourceLocation = #_sourceLocation) -> String {
        guard question else { return text }
        let found = text.components(separatedBy: added).count - 1
        #expect(found == 1, "an @question request should have the live-data rule once, has it \(found) times",
                sourceLocation: sourceLocation)
        return text.replacingOccurrences(of: added, with: "")
    }

    static func strip(_ data: Data, question: Bool, sourceLocation: SourceLocation = #_sourceLocation) -> Data {
        guard question else { return data }
        return Data(strip(String(decoding: data, as: UTF8.self), question: true, sourceLocation: sourceLocation).utf8)
    }
}
